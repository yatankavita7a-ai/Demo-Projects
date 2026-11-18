package CodeTrack.service.platform;

/**
 * Normalized statistics fetched from one platform. Any field may be null when the
 * platform doesn't expose it.
 *
 * @param totalSolved     problems solved (unique accepted problems)
 * @param easySolved      easy (LeetCode Easy; GfG School+Basic+Easy)
 * @param mediumSolved    medium
 * @param hardSolved      hard
 * @param rating          current contest rating
 * @param maxRating       highest contest rating
 * @param rankTitle       textual rank, e.g. "Expert", "3★", "Knight"
 * @param globalRank      global ranking position
 * @param contests        number of rated contests attended
 * @param score           platform score (GfG coding score)
 * @param repos           GitHub public repositories
 * @param followers       GitHub followers
 * @param stars           GitHub stars across owned public repos
 */
public record PlatformStats(
        Integer totalSolved,
        Integer easySolved,
        Integer mediumSolved,
        Integer hardSolved,
        Integer rating,
        Integer maxRating,
        String rankTitle,
        Integer globalRank,
        Integer contests,
        Integer score,
        Integer repos,
        Integer followers,
        Integer stars
) {
    public static Builder builder() { return new Builder(); }

    public static final class Builder {
        private Integer totalSolved, easySolved, mediumSolved, hardSolved, rating, maxRating,
                globalRank, contests, score, repos, followers, stars;
        private String rankTitle;

        public Builder totalSolved(Integer v) { totalSolved = v; return this; }
        public Builder easySolved(Integer v) { easySolved = v; return this; }
        public Builder mediumSolved(Integer v) { mediumSolved = v; return this; }
        public Builder hardSolved(Integer v) { hardSolved = v; return this; }
        public Builder rating(Integer v) { rating = v; return this; }
        public Builder maxRating(Integer v) { maxRating = v; return this; }
        public Builder rankTitle(String v) { rankTitle = v; return this; }
        public Builder globalRank(Integer v) { globalRank = v; return this; }
        public Builder contests(Integer v) { contests = v; return this; }
        public Builder score(Integer v) { score = v; return this; }
        public Builder repos(Integer v) { repos = v; return this; }
        public Builder followers(Integer v) { followers = v; return this; }
        public Builder stars(Integer v) { stars = v; return this; }

        public PlatformStats build() {
            return new PlatformStats(totalSolved, easySolved, mediumSolved, hardSolved, rating, maxRating,
                    rankTitle, globalRank, contests, score, repos, followers, stars);
        }
    }
}
