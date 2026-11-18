package CodeTrack.entity;

import CodeTrack.exception.ApiException;
import org.springframework.http.HttpStatus;

import java.net.URI;
import java.util.Arrays;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Supported coding platforms. Each knows how to turn a pasted profile URL
 * (or a bare username) into a username and back into a canonical URL.
 */
public enum Platform {
    LEETCODE("LeetCode", "leetcode.com", "https://leetcode.com/u/%s/", List.of("u")),
    GEEKSFORGEEKS("GeeksforGeeks", "geeksforgeeks.org", "https://www.geeksforgeeks.org/user/%s/", List.of("user", "profile")),
    CODECHEF("CodeChef", "codechef.com", "https://www.codechef.com/users/%s", List.of("users")),
    CODEFORCES("Codeforces", "codeforces.com", "https://codeforces.com/profile/%s", List.of("profile")),
    GITHUB("GitHub", "github.com", "https://github.com/%s", List.of());

    private static final Pattern USERNAME = Pattern.compile("^[A-Za-z0-9_.\\-]{1,64}$");

    private final String displayName;
    private final String host;
    private final String urlTemplate;
    private final List<String> pathPrefixes;

    Platform(String displayName, String host, String urlTemplate, List<String> pathPrefixes) {
        this.displayName = displayName;
        this.host = host;
        this.urlTemplate = urlTemplate;
        this.pathPrefixes = pathPrefixes;
    }

    public String getDisplayName() { return displayName; }

    /** True for competitive-programming platforms whose solved counts add up. */
    public boolean countsSolved() { return this != GITHUB; }

    public String profileUrl(String username) { return urlTemplate.formatted(username); }

    /** Accepts "leetcode", "LEETCODE", "gfg", "geeksforgeeks", etc. */
    public static Platform fromKey(String key) {
        if (key != null) {
            String k = key.trim().toUpperCase().replace("-", "").replace("_", "");
            if (k.equals("GFG")) return GEEKSFORGEEKS;
            for (Platform p : values()) {
                if (p.name().equals(k)) return p;
            }
        }
        throw new ApiException(HttpStatus.BAD_REQUEST, "Unknown platform '" + key + "'. Supported: "
                + Arrays.toString(values()));
    }

    /** Extracts a username from a profile URL or returns the bare username after validating it. */
    public String extractUsername(String input) {
        if (input == null || input.isBlank()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Enter your " + displayName + " username or profile URL");
        }
        String value = input.trim();
        String candidate = value;
        if (value.contains("/") || value.contains(host)) {
            String withScheme = value.matches("^[a-zA-Z]+://.*") ? value : "https://" + value;
            URI uri;
            try {
                uri = URI.create(withScheme.replace(" ", ""));
            } catch (IllegalArgumentException e) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "That doesn't look like a valid URL");
            }
            String uriHost = uri.getHost() == null ? "" : uri.getHost().toLowerCase();
            if (!(uriHost.equals(host) || uriHost.endsWith("." + host))) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "That URL is not a " + displayName + " profile link");
            }
            List<String> segments = Arrays.stream(uri.getPath() == null ? new String[0] : uri.getPath().split("/"))
                    .filter(s -> !s.isBlank()).toList();
            candidate = null;
            for (int i = 0; i < segments.size() - 1; i++) {
                if (pathPrefixes.contains(segments.get(i).toLowerCase())) {
                    candidate = segments.get(i + 1);
                    break;
                }
            }
            if (candidate == null && !segments.isEmpty()) candidate = segments.get(0);
        }
        if (candidate == null || !USERNAME.matcher(candidate).matches()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Could not find a valid " + displayName + " username in '" + value + "'");
        }
        return candidate;
    }
}
