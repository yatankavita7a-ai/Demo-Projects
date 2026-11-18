package CodeTrack.service.platform;

import CodeTrack.entity.Platform;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;

import java.util.Map;

/**
 * LeetCode via its public GraphQL endpoint (no auth needed; needs a Referer and a browser-like UA).
 * globalRank is the profile "Rank" (overall problem-solving ranking); rating/maxRating/contests/rankTitle
 * come from contest data and are null for users who never entered a contest.
 */
@Component
public class LeetCodeFetcher implements PlatformFetcher {

    private static final String URL = "https://leetcode.com/graphql";

    private static final String QUERY = """
            query userStats($username: String!) {
              matchedUser(username: $username) {
                username
                profile { ranking }
                submitStatsGlobal { acSubmissionNum { difficulty count } }
              }
              userContestRanking(username: $username) {
                rating
                attendedContestsCount
                globalRanking
                badge { name }
              }
              userContestRankingHistory(username: $username) {
                attended
                rating
              }
            }
            """;

    private final HttpSupport http;

    public LeetCodeFetcher(HttpSupport http) {
        this.http = http;
    }

    @Override
    public Platform platform() {
        return Platform.LEETCODE;
    }

    @Override
    public PlatformStats fetch(String username) throws PlatformFetchException {
        String body = http.toJson(Map.of(
                "operationName", "userStats",
                "query", QUERY,
                "variables", Map.of("username", username)));
        Map<String, String> headers = Map.of(
                "Referer", "https://leetcode.com/u/" + HttpSupport.encode(username) + "/",
                "Origin", "https://leetcode.com",
                "Accept", "application/json");

        HttpSupport.Response response = http.post(URL, body, headers, Platform.LEETCODE);
        JsonNode root = http.readTreeOrNull(response.body());
        // LeetCode answers 200 (sometimes 400) with errors[].message "That user does not exist."
        if (root != null && mentionsMissingUser(root.path("errors"))) {
            throw http.notFound(Platform.LEETCODE, username);
        }
        http.ensureOk(response, Platform.LEETCODE, username);
        if (root == null) throw http.unreadable(Platform.LEETCODE);

        JsonNode data = root.path("data");
        JsonNode user = data.path("matchedUser");
        if (user.isMissingNode() || user.isNull()) {
            if (data.isObject()) throw http.notFound(Platform.LEETCODE, username);
            throw http.unreadable(Platform.LEETCODE);
        }

        PlatformStats.Builder b = PlatformStats.builder();
        for (JsonNode n : user.path("submitStatsGlobal").path("acSubmissionNum").values()) {
            Integer count = HttpSupport.intOrNull(n.path("count"));
            String difficulty = HttpSupport.stringOrNull(n.path("difficulty"));
            if (difficulty == null) continue;
            switch (difficulty) {
                case "All" -> b.totalSolved(count);
                case "Easy" -> b.easySolved(count);
                case "Medium" -> b.mediumSolved(count);
                case "Hard" -> b.hardSolved(count);
                default -> { }
            }
        }
        b.globalRank(HttpSupport.intOrNull(user.path("profile").path("ranking")));

        JsonNode contest = data.path("userContestRanking");
        Integer attended = HttpSupport.intOrNull(contest.path("attendedContestsCount"));
        if (attended != null && attended > 0) {
            Integer rating = HttpSupport.intOrNull(contest.path("rating"));
            b.contests(attended);
            b.rating(rating);
            b.rankTitle(HttpSupport.stringOrNull(contest.path("badge").path("name")));

            Integer max = rating;
            for (JsonNode h : data.path("userContestRankingHistory").values()) {
                if (!h.path("attended").asBoolean(false)) continue;
                Integer r = HttpSupport.intOrNull(h.path("rating"));
                if (r != null && (max == null || r > max)) max = r;
            }
            b.maxRating(max);
        } else {
            b.contests(0);
        }
        return b.build();
    }

    private static boolean mentionsMissingUser(JsonNode errors) {
        for (JsonNode e : errors.values()) {
            String msg = HttpSupport.stringOrNull(e.path("message"));
            if (msg != null && msg.toLowerCase().contains("does not exist")) return true;
        }
        return false;
    }
}
