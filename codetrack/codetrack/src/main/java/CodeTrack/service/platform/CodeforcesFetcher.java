package CodeTrack.service.platform;

import CodeTrack.entity.Platform;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;

import java.time.Duration;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

/**
 * Codeforces via the official public API (https://codeforces.com/apiHelp): user.info (rating, max rating, rank),
 * user.rating (rated contests) and user.status (unique accepted problems). The API allows roughly
 * one call per 2 seconds per IP; on "Call limit exceeded" we wait and retry once.
 * Codeforces doesn't expose a global rank or an easy/medium/hard split, so those stay null.
 */
@Component
public class CodeforcesFetcher implements PlatformFetcher {

    private static final String API = "https://codeforces.com/api/";
    private static final long RETRY_DELAY_MS = 2100;
    /** Codeforces enforces ~1 call / 2 s per IP; space consecutive calls out to avoid "Call limit exceeded". */
    private static final long CALL_SPACING_MS = 2000;
    /** Timeout for one page of user.status (pages are large, ~1 MB). */
    private static final Duration SUBMISSIONS_TIMEOUT = Duration.ofSeconds(30);
    private static final int PAGE_SIZE = 2000;
    private static final int MAX_PAGES = 15;
    private static final Duration DEFAULT_TIMEOUT = Duration.ofSeconds(15);

    private final HttpSupport http;

    public CodeforcesFetcher(HttpSupport http) {
        this.http = http;
    }

    @Override
    public Platform platform() {
        return Platform.CODEFORCES;
    }

    @Override
    public PlatformStats fetch(String username) throws PlatformFetchException {
        String handle = HttpSupport.encode(username);

        JsonNode info = call("user.info?handles=" + handle, username, DEFAULT_TIMEOUT).path(0);
        if (!info.isObject()) throw http.unreadable(Platform.CODEFORCES);

        PlatformStats.Builder b = PlatformStats.builder()
                .rating(HttpSupport.intOrNull(info.path("rating")))
                .maxRating(HttpSupport.intOrNull(info.path("maxRating")))
                .rankTitle(HttpSupport.capitalizeWords(HttpSupport.stringOrNull(info.path("rank"))));

        // Secondary calls are best-effort: keep the profile numbers if they fail.
        try {
            pause();
            JsonNode ratings = call("user.rating?handle=" + handle, username, DEFAULT_TIMEOUT);
            if (ratings.isArray()) b.contests(ratings.size());
        } catch (PlatformFetchException ignored) {
            // leave contests null
        }

        try {
            b.totalSolved(countSolved(handle, username));
        } catch (PlatformFetchException ignored) {
            // leave totalSolved null
        }
        return b.build();
    }

    /**
     * Pages through user.status. Requesting all submissions at once can take minutes for very
     * active users, while pages of PAGE_SIZE return in a few seconds.
     */
    private int countSolved(String handle, String username) throws PlatformFetchException {
        Set<String> solved = new HashSet<>();
        for (int page = 0; page < MAX_PAGES; page++) {
            pause();
            JsonNode submissions = call("user.status?handle=" + handle + "&from=" + (page * PAGE_SIZE + 1)
                    + "&count=" + PAGE_SIZE, username, SUBMISSIONS_TIMEOUT);
            if (!submissions.isArray()) break;
            addSolved(submissions, solved);
            if (submissions.size() < PAGE_SIZE) break;
        }
        return solved.size();
    }

    private static void addSolved(JsonNode submissions, Set<String> solved) {
        for (JsonNode s : submissions.values()) {
            if (!"OK".equals(HttpSupport.stringOrNull(s.path("verdict")))) continue;
            JsonNode p = s.path("problem");
            String index = HttpSupport.stringOrNull(p.path("index"));
            if (index == null) continue;
            String group = HttpSupport.stringOrNull(p.path("contestId"));
            if (group == null) group = HttpSupport.stringOrNull(p.path("problemsetName"));
            if (group == null) group = String.valueOf(HttpSupport.stringOrNull(p.path("name")));
            solved.add(group + "/" + index);
        }
    }

    private static void pause() {
        try {
            Thread.sleep(CALL_SPACING_MS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    /** Calls a Codeforces API method and returns its "result" node, retrying once on rate limits or network errors. */
    private JsonNode call(String methodAndQuery, String username, Duration timeout) throws PlatformFetchException {
        PlatformFetchException last = null;
        for (int attempt = 0; attempt < 2; attempt++) {
            if (attempt > 0) {
                try {
                    Thread.sleep(RETRY_DELAY_MS);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw last;
                }
            }
            HttpSupport.Response r;
            try {
                r = http.get(API + methodAndQuery, Map.of("Accept", "application/json"), Platform.CODEFORCES, timeout);
            } catch (PlatformFetchException networkError) {
                last = networkError;
                continue;
            }
            JsonNode root = http.readTreeOrNull(r.body());
            if (root != null && "OK".equals(HttpSupport.stringOrNull(root.path("status")))) {
                return root.path("result");
            }
            String comment = root == null ? null : HttpSupport.stringOrNull(root.path("comment"));
            String lower = comment == null ? "" : comment.toLowerCase();
            if (lower.contains("not found")) throw http.notFound(Platform.CODEFORCES, username);
            if (lower.contains("limit exceeded") || r.status() == 429) {
                last = http.rateLimited(Platform.CODEFORCES);
                continue;
            }
            http.ensureOk(r, Platform.CODEFORCES, username);
            throw http.unreadable(Platform.CODEFORCES);
        }
        throw last;
    }
}
