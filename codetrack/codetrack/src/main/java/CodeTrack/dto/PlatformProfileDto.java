package CodeTrack.dto;

import CodeTrack.entity.Platform;
import CodeTrack.entity.PlatformProfile;
import CodeTrack.entity.SyncStatus;

import java.time.Instant;

public record PlatformProfileDto(Platform platform, String displayName, String username, String profileUrl,
                                 Integer totalSolved, Integer easySolved, Integer mediumSolved, Integer hardSolved,
                                 Integer rating, Integer maxRating, String rankTitle, Integer globalRank,
                                 Integer contests, Integer score, Integer repos, Integer followers, Integer stars,
                                 SyncStatus syncStatus, String syncMessage, Instant lastSyncedAt) {
    public static PlatformProfileDto from(PlatformProfile p) {
        Platform pl = p.getPlatform();
        return new PlatformProfileDto(pl, pl.getDisplayName(), p.getUsername(), pl.profileUrl(p.getUsername()),
                p.getTotalSolved(), p.getEasySolved(), p.getMediumSolved(), p.getHardSolved(),
                p.getRating(), p.getMaxRating(), p.getRankTitle(), p.getGlobalRank(),
                p.getContests(), p.getScore(), p.getRepos(), p.getFollowers(), p.getStars(),
                p.getSyncStatus(), p.getSyncMessage(), p.getLastSyncedAt());
    }
}
