package CodeTrack.service.platform;

import CodeTrack.entity.Platform;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;

import java.util.HashMap;
import java.util.Map;

/**
 * GitHub via the REST API: /users/{u} (public_repos, followers) plus stars summed over
 * /users/{u}/repos?type=owner (up to 3 pages of 100). Unauthenticated calls are limited to
 * 60/hour per IP; set {@code app.github.token} (or env GITHUB_TOKEN) for 5000/hour.
 */
@Component
public class GitHubFetcher implements PlatformFetcher {

    private static final String API = "https://api.github.com/users/";
    private static final int PER_PAGE = 100;
    private static final int MAX_PAGES = 3;

    private final HttpSupport http;
    private final String token;

    public GitHubFetcher(HttpSupport http, @Value("${app.github.token:${GITHUB_TOKEN:}}") String token) {
        this.http = http;
        this.token = token == null ? "" : token.trim();
    }

    @Override
    public Platform platform() {
        return Platform.GITHUB;
    }

    @Override
    public PlatformStats fetch(String username) throws PlatformFetchException {
        String user = HttpSupport.encode(username);
        JsonNode profile = getJson(API + user, username);
        if (!profile.isObject()) throw http.unreadable(Platform.GITHUB);

        Integer repos = HttpSupport.intOrNull(profile.path("public_repos"));
        Integer followers = HttpSupport.intOrNull(profile.path("followers"));
        if (repos == null && followers == null) throw http.unreadable(Platform.GITHUB);

        Integer stars;
        try {
            int sum = 0;
            for (int page = 1; page <= MAX_PAGES; page++) {
                JsonNode list = getJson(API + user + "/repos?type=owner&per_page=" + PER_PAGE + "&page=" + page, username);
                if (!list.isArray()) break;
                for (JsonNode repo : list.values()) {
                    Integer s = HttpSupport.intOrNull(repo.path("stargazers_count"));
                    if (s != null) sum += s;
                }
                if (list.size() < PER_PAGE) break;
            }
            stars = sum;
        } catch (PlatformFetchException e) {
            stars = null; // keep repos/followers even if the repo listing fails
        }

        return PlatformStats.builder()
                .repos(repos)
                .followers(followers)
                .stars(stars)
                .build();
    }

    private JsonNode getJson(String url, String username) throws PlatformFetchException {
        Map<String, String> headers = new HashMap<>();
        headers.put("Accept", "application/vnd.github+json");
        headers.put("X-GitHub-Api-Version", "2022-11-28");
        if (!token.isEmpty()) headers.put("Authorization", "Bearer " + token);

        HttpSupport.Response r = http.get(url, headers, Platform.GITHUB);
        // GitHub signals exhausted rate limits with 403 (or 429) and x-ratelimit-remaining: 0.
        if ((r.status() == 403 || r.status() == 429)
                && ("0".equals(r.header("x-ratelimit-remaining")) || r.body().contains("rate limit"))) {
            throw http.rateLimited(Platform.GITHUB);
        }
        http.ensureOk(r, Platform.GITHUB, username);
        return http.readTree(r.body(), Platform.GITHUB);
    }
}
