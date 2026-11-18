package CodeTrack.service.platform;

import CodeTrack.entity.Platform;
import org.springframework.stereotype.Component;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpHeaders;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Shared HTTP/JSON plumbing for the platform fetchers. Every failure is turned into a
 * {@link PlatformFetchException} with a short, user-facing message.
 */
@Component
public class HttpSupport {

    public static final String USER_AGENT =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) "
                    + "Chrome/131.0.0.0 Safari/537.36";

    private static final Duration CONNECT_TIMEOUT = Duration.ofSeconds(10);
    private static final Duration REQUEST_TIMEOUT = Duration.ofSeconds(15);

    /** Raw response: status, body, final URI after redirects and headers. */
    public record Response(int status, String body, URI uri, HttpHeaders headers) {
        public boolean ok() { return status >= 200 && status < 300; }
        public String header(String name) { return headers.firstValue(name).orElse(null); }
    }

    private final HttpClient client;
    private final JsonMapper mapper;

    public HttpSupport() {
        this.client = HttpClient.newBuilder()
                .connectTimeout(CONNECT_TIMEOUT)
                .followRedirects(HttpClient.Redirect.NORMAL)
                .build();
        this.mapper = JsonMapper.builder().build();
    }

    // ---------------------------------------------------------------- requests

    /** GET without any status-code interpretation (only network failures throw). */
    public Response get(String url, Map<String, String> headers, Platform platform) throws PlatformFetchException {
        return send(baseRequest(url, headers).GET().build(), platform);
    }

    /** GET with a custom request timeout, for endpoints that return very large payloads. */
    public Response get(String url, Map<String, String> headers, Platform platform, Duration timeout)
            throws PlatformFetchException {
        return send(baseRequest(url, headers).timeout(timeout).GET().build(), platform);
    }

    /** POST a JSON body without any status-code interpretation (only network failures throw). */
    public Response post(String url, String jsonBody, Map<String, String> headers, Platform platform)
            throws PlatformFetchException {
        HttpRequest request = baseRequest(url, headers)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(jsonBody, StandardCharsets.UTF_8))
                .build();
        return send(request, platform);
    }

    /** GET and return the body of a 2xx response; other statuses map to user-facing errors. */
    public String getString(String url, Map<String, String> headers, Platform platform, String username)
            throws PlatformFetchException {
        return ensureOk(get(url, headers, platform), platform, username).body();
    }

    /** POST JSON and return the body of a 2xx response; other statuses map to user-facing errors. */
    public String postJson(String url, String jsonBody, Map<String, String> headers, Platform platform, String username)
            throws PlatformFetchException {
        return ensureOk(post(url, jsonBody, headers, platform), platform, username).body();
    }

    /** Throws the standard user-facing error for a non-2xx response, otherwise returns it unchanged. */
    public Response ensureOk(Response response, Platform platform, String username) throws PlatformFetchException {
        if (response.ok()) return response;
        int s = response.status();
        if (s == 404) throw notFound(platform, username);
        if (s == 429) throw rateLimited(platform);
        if (s == 403) {
            throw new PlatformFetchException(platform.getDisplayName() + " refused the request, try again later");
        }
        if (s >= 500) {
            throw new PlatformFetchException(platform.getDisplayName() + " is unavailable right now, try again later");
        }
        throw new PlatformFetchException(platform.getDisplayName() + " returned an unexpected response (HTTP " + s + ")");
    }

    private HttpRequest.Builder baseRequest(String url, Map<String, String> headers) {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(url))
                .timeout(REQUEST_TIMEOUT)
                .header("User-Agent", USER_AGENT)
                .header("Accept-Language", "en-US,en;q=0.9");
        boolean hasAccept = false;
        if (headers != null) {
            for (Map.Entry<String, String> e : headers.entrySet()) {
                if (e.getValue() == null) continue;
                if (e.getKey().equalsIgnoreCase("Accept")) hasAccept = true;
                b.header(e.getKey(), e.getValue());
            }
        }
        if (!hasAccept) b.header("Accept", "*/*");
        return b;
    }

    private Response send(HttpRequest request, Platform platform) throws PlatformFetchException {
        try {
            HttpResponse<String> r = client.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            return new Response(r.statusCode(), r.body() == null ? "" : r.body(), r.uri(), r.headers());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw unreachable(platform, e);
        } catch (IOException | RuntimeException e) {
            throw unreachable(platform, e);
        }
    }

    // ---------------------------------------------------------------- errors

    public PlatformFetchException notFound(Platform platform, String username) {
        return new PlatformFetchException("User '" + username + "' not found on " + platform.getDisplayName());
    }

    public PlatformFetchException rateLimited(Platform platform) {
        return new PlatformFetchException(platform.getDisplayName() + " is rate-limiting requests, try again later");
    }

    public PlatformFetchException unreadable(Platform platform) {
        return new PlatformFetchException("Could not read " + platform.getDisplayName() + " profile data");
    }

    private PlatformFetchException unreachable(Platform platform, Throwable cause) {
        return new PlatformFetchException("Could not reach " + platform.getDisplayName(), cause);
    }

    // ---------------------------------------------------------------- JSON

    /** Parses JSON; unparseable bodies become "Could not read X profile data". */
    public JsonNode readTree(String body, Platform platform) throws PlatformFetchException {
        try {
            JsonNode node = mapper.readTree(body);
            if (node == null || node.isMissingNode()) throw unreadable(platform);
            return node;
        } catch (JacksonException e) {
            throw new PlatformFetchException("Could not read " + platform.getDisplayName() + " profile data", e);
        }
    }

    /** Parses JSON, returning null instead of throwing. */
    public JsonNode readTreeOrNull(String body) {
        if (body == null || body.isBlank()) return null;
        try {
            return mapper.readTree(body);
        } catch (JacksonException e) {
            return null;
        }
    }

    public String toJson(Object value) {
        return mapper.writeValueAsString(value);
    }

    /** Integer value of a numeric (or numeric-string) node, else null. Decimals are rounded. */
    public static Integer intOrNull(JsonNode node) {
        if (node == null || node.isMissingNode() || node.isNull()) return null;
        if (node.isNumber()) return (int) Math.round(node.asDouble());
        if (node.isString()) return parseIntOrNull(node.asString());
        return null;
    }

    /** Text value of a node, else null (blank strings become null). */
    public static String stringOrNull(JsonNode node) {
        if (node == null || node.isMissingNode() || node.isNull()) return null;
        String s = node.isString() ? node.stringValue() : node.isNumber() ? node.asString() : null;
        return s == null || s.isBlank() ? null : s.trim();
    }

    // ---------------------------------------------------------------- misc helpers

    public static String encode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20");
    }

    /** Parses "1,234" / " 42 " / "12.6" into an Integer, else null. */
    public static Integer parseIntOrNull(String s) {
        if (s == null) return null;
        String cleaned = s.replace(",", "").trim();
        if (cleaned.isEmpty()) return null;
        try {
            return (int) Math.round(Double.parseDouble(cleaned));
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /** First capture group of {@code pattern} in {@code text} parsed as an int, else null. */
    public static Integer findInt(Pattern pattern, String text) {
        if (text == null) return null;
        Matcher m = pattern.matcher(text);
        return m.find() ? parseIntOrNull(m.group(1)) : null;
    }

    /** First capture group of {@code pattern} in {@code text}, else null. */
    public static String find(Pattern pattern, String text) {
        if (text == null) return null;
        Matcher m = pattern.matcher(text);
        return m.find() ? m.group(1) : null;
    }

    /** "legendary grandmaster" -> "Legendary Grandmaster". */
    public static String capitalizeWords(String s) {
        if (s == null || s.isBlank()) return null;
        StringBuilder sb = new StringBuilder();
        for (String w : s.trim().split("\\s+")) {
            if (!sb.isEmpty()) sb.append(' ');
            sb.append(Character.toUpperCase(w.charAt(0))).append(w.substring(1));
        }
        return sb.toString();
    }
}
