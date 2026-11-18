package CodeTrack.service.platform;

import CodeTrack.entity.Platform;
import org.springframework.stereotype.Component;

import java.net.URI;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * CodeChef has no public API, so this scrapes the server-rendered profile page
 * https://www.codechef.com/users/{handle}. Unknown handles redirect (302) to the home page.
 * Renamed handles 301-redirect to the new handle over plain http, which we follow manually.
 * The global rank shows "Inactive" for users who haven't competed recently (-> null).
 */
@Component
public class CodeChefFetcher implements PlatformFetcher {

    private static final String PROFILE = "https://www.codechef.com/users/";

    private static final Pattern RATING = Pattern.compile("class=\"rating-number\"[^>]*>\\s*(\\d+)");
    private static final Pattern MAX_RATING = Pattern.compile("Highest Rating\\s*(\\d+)");
    private static final Pattern STAR_BLOCK = Pattern.compile("class=\"rating-star\"[^>]*>(.*?)</div>", Pattern.DOTALL);
    private static final Pattern STAR = Pattern.compile("&#9733;|★");
    private static final Pattern GLOBAL_RANK =
            Pattern.compile("href=\"/ratings/all\"[^>]*>\\s*<strong>\\s*([\\d,]+)\\s*</strong>");
    private static final Pattern SOLVED = Pattern.compile("Total Problems Solved:\\s*(\\d+)");
    private static final Pattern SOLVED_MARKER = Pattern.compile("Total Problems Solved:");
    private static final Pattern CONTESTS =
            Pattern.compile("Contests Participated:\\s*(?:<[^>]+>\\s*)*(\\d+)");
    private static final Pattern CONTESTS_HEADING = Pattern.compile("<h3>\\s*Contests\\s*\\((\\d+)\\)");
    private static final Pattern USERS_PATH = Pattern.compile("/users/([A-Za-z0-9_.\\-]+)");

    private final HttpSupport http;

    public CodeChefFetcher(HttpSupport http) {
        this.http = http;
    }

    @Override
    public Platform platform() {
        return Platform.CODECHEF;
    }

    @Override
    public PlatformStats fetch(String username) throws PlatformFetchException {
        Map<String, String> headers = Map.of("Accept", "text/html,application/xhtml+xml");
        HttpSupport.Response r = http.get(PROFILE + HttpSupport.encode(username), headers, Platform.CODECHEF);

        // A renamed handle 301s to http://www.codechef.com/users/<new>; HttpClient won't downgrade https->http.
        if (r.status() >= 300 && r.status() < 400) {
            String location = r.header("Location");
            String renamed = HttpSupport.find(USERS_PATH, location);
            if (renamed == null) throw http.notFound(Platform.CODECHEF, username);
            r = http.get(PROFILE + HttpSupport.encode(renamed), headers, Platform.CODECHEF);
        }
        if (!isProfileUri(r.uri())) {
            // Unknown users are redirected to the home page.
            throw http.notFound(Platform.CODECHEF, username);
        }
        http.ensureOk(r, Platform.CODECHEF, username);

        String html = r.body();
        if (html.contains("cf-chl") || html.contains("Just a moment...")) {
            throw new PlatformFetchException("CodeChef blocked the request, try again later");
        }

        Integer rating = HttpSupport.findInt(RATING, html);
        Integer maxRating = HttpSupport.findInt(MAX_RATING, html);
        Integer globalRank = HttpSupport.findInt(GLOBAL_RANK, html);
        Integer solved = HttpSupport.findInt(SOLVED, html);
        Integer contests = HttpSupport.findInt(CONTESTS, html);
        if (contests == null) contests = HttpSupport.findInt(CONTESTS_HEADING, html);
        String stars = stars(html);

        boolean isProfilePage = html.contains("user-details-container") || html.contains("CodeChef User Profile");
        if (rating == null && maxRating == null && solved == null && contests == null && globalRank == null) {
            if (!isProfilePage) throw http.unreadable(Platform.CODECHEF);
        }
        // A real profile with "Total Problems Solved: " and no number means nothing solved yet.
        if (solved == null && isProfilePage && SOLVED_MARKER.matcher(html).find()) solved = 0;
        if (maxRating != null && maxRating == 0) maxRating = null;

        return PlatformStats.builder()
                .rating(rating)
                .maxRating(maxRating)
                .rankTitle(stars)
                .globalRank(globalRank)
                .totalSolved(solved)
                .contests(contests)
                .build();
    }

    private static boolean isProfileUri(URI uri) {
        return uri != null && uri.getPath() != null && uri.getPath().startsWith("/users/");
    }

    private static String stars(String html) {
        String block = HttpSupport.find(STAR_BLOCK, html);
        if (block == null) return null;
        Matcher m = STAR.matcher(block);
        int count = 0;
        while (m.find()) count++;
        return count > 0 ? count + "★" : null;
    }
}
