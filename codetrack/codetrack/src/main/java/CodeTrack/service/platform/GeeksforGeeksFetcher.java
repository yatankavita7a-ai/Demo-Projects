package CodeTrack.service.platform;

import CodeTrack.entity.Platform;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * GeeksforGeeks via the JSON endpoints its own profile page calls:
 * <ul>
 *   <li>GET authapi.geeksforgeeks.org/api-get/user-profile-info/?handle= : coding score, total solved
 *       (400 + "User not found!" for unknown handles)</li>
 *   <li>POST practiceapi.geeksforgeeks.org/api/v1/user/problems/submissions/ : solved problems grouped by
 *       difficulty (School/Basic/Easy/Medium/Hard); best-effort, used for the easy/medium/hard split</li>
 * </ul>
 * GfG exposes no contest rating or global rank on these endpoints.
 */
@Component
public class GeeksforGeeksFetcher implements PlatformFetcher {

    private static final String PROFILE_API = "https://authapi.geeksforgeeks.org/api-get/user-profile-info/?handle=";
    private static final String SUBMISSIONS_API = "https://practiceapi.geeksforgeeks.org/api/v1/user/problems/submissions/";

    private final HttpSupport http;

    public GeeksforGeeksFetcher(HttpSupport http) {
        this.http = http;
    }

    @Override
    public Platform platform() {
        return Platform.GEEKSFORGEEKS;
    }

    @Override
    public PlatformStats fetch(String username) throws PlatformFetchException {
        Map<String, String> headers = Map.of(
                "Accept", "application/json",
                "Origin", "https://www.geeksforgeeks.org",
                "Referer", "https://www.geeksforgeeks.org/user/" + HttpSupport.encode(username) + "/");

        HttpSupport.Response r = http.get(PROFILE_API + HttpSupport.encode(username), headers, Platform.GEEKSFORGEEKS);
        JsonNode root = http.readTreeOrNull(r.body());
        String message = root == null ? null : HttpSupport.stringOrNull(root.path("message"));
        if (message != null && message.toLowerCase().contains("not found")) {
            throw http.notFound(Platform.GEEKSFORGEEKS, username);
        }
        http.ensureOk(r, Platform.GEEKSFORGEEKS, username);
        JsonNode data = root == null ? null : root.path("data");
        if (data == null || !data.isObject()) throw http.unreadable(Platform.GEEKSFORGEEKS);

        Integer score = HttpSupport.intOrNull(data.path("score"));
        Integer total = HttpSupport.intOrNull(data.path("total_problems_solved"));
        if (score == null && total == null) throw http.unreadable(Platform.GEEKSFORGEEKS);

        PlatformStats.Builder b = PlatformStats.builder().score(score).totalSolved(total);
        Map<String, Integer> byDifficulty = difficultyBreakdown(username, headers);
        if (byDifficulty != null) {
            b.easySolved(byDifficulty.get("school") + byDifficulty.get("basic") + byDifficulty.get("easy"));
            b.mediumSolved(byDifficulty.get("medium"));
            b.hardSolved(byDifficulty.get("hard"));
            if (total == null) b.totalSolved(byDifficulty.values().stream().mapToInt(Integer::intValue).sum());
        }
        return b.build();
    }

    /** Solved counts keyed by lower-case difficulty, or null if the endpoint fails. Never throws. */
    private Map<String, Integer> difficultyBreakdown(String username, Map<String, String> headers) {
        try {
            String body = http.toJson(Map.of("handle", username, "requestType", "", "year", "", "month", ""));
            HttpSupport.Response r = http.post(SUBMISSIONS_API, body, headers, Platform.GEEKSFORGEEKS);
            if (!r.ok()) return null;
            JsonNode root = http.readTreeOrNull(r.body());
            if (root == null || !"success".equalsIgnoreCase(HttpSupport.stringOrNull(root.path("status")))) return null;
            JsonNode result = root.path("result");
            if (!result.isObject()) return null;

            Map<String, Integer> counts = new LinkedHashMap<>();
            for (String key : new String[]{"school", "basic", "easy", "medium", "hard"}) counts.put(key, 0);
            for (Map.Entry<String, JsonNode> e : result.properties()) {
                String key = e.getKey().toLowerCase();
                if (!counts.containsKey(key)) continue;
                JsonNode v = e.getValue();
                // Each difficulty maps to an object (or array) of solved problems.
                int n = (v.isObject() || v.isArray()) ? v.size() : 0;
                if (n == 0 && v.isNumber()) n = v.asInt();
                counts.put(key, n);
            }
            return counts;
        } catch (PlatformFetchException | RuntimeException e) {
            return null;
        }
    }
}
