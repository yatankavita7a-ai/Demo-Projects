package CodeTrack.entity;

import CodeTrack.service.platform.PlatformStats;
import jakarta.persistence.*;

import java.time.Instant;

/** A user's linked account on one coding platform plus the last fetched stats. */
@Entity
@Table(name = "platform_profiles",
        uniqueConstraints = @UniqueConstraint(columnNames = {"user_id", "platform"}))
public class PlatformProfile {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private Platform platform;

    @Column(nullable = false, length = 64)
    private String username;

    private Integer totalSolved;
    private Integer easySolved;
    private Integer mediumSolved;
    private Integer hardSolved;
    private Integer rating;
    private Integer maxRating;
    private String rankTitle;
    private Integer globalRank;
    private Integer contests;
    private Integer score;
    private Integer repos;
    private Integer followers;
    private Integer stars;

    @Enumerated(EnumType.STRING)
    @Column(length = 10)
    private SyncStatus syncStatus = SyncStatus.PENDING;

    private String syncMessage;
    private Instant lastSyncedAt;
    private Instant lastAttemptAt;

    /** Sample data created by DemoDataSeeder; never synced against the real platform. */
    private Boolean demo;

    protected PlatformProfile() {}

    public PlatformProfile(User user, Platform platform, String username) {
        this.user = user;
        this.platform = platform;
        this.username = username;
    }

    /** Points a profile at a new username and clears stale stats. */
    public void changeUsername(String username) {
        this.username = username;
        this.demo = null;
        applyStats(new PlatformStats(null, null, null, null, null, null, null, null, null, null, null, null, null));
        this.syncStatus = SyncStatus.PENDING;
        this.syncMessage = null;
        this.lastSyncedAt = null;
        this.lastAttemptAt = null;
    }

    public void applyStats(PlatformStats s) {
        totalSolved = s.totalSolved();
        easySolved = s.easySolved();
        mediumSolved = s.mediumSolved();
        hardSolved = s.hardSolved();
        rating = s.rating();
        maxRating = s.maxRating();
        rankTitle = s.rankTitle();
        globalRank = s.globalRank();
        contests = s.contests();
        score = s.score();
        repos = s.repos();
        followers = s.followers();
        stars = s.stars();
    }

    public void markSynced(Instant now) {
        syncStatus = SyncStatus.OK;
        syncMessage = null;
        lastSyncedAt = now;
        lastAttemptAt = now;
    }

    public void markFailed(String message, Instant now) {
        syncStatus = SyncStatus.ERROR;
        syncMessage = message;
        lastAttemptAt = now;
    }

    public boolean isDemo() { return demo != null && demo; }
    public void markDemo() { this.demo = true; }

    public Long getId() { return id; }
    public User getUser() { return user; }
    public Platform getPlatform() { return platform; }
    public String getUsername() { return username; }
    public Integer getTotalSolved() { return totalSolved; }
    public Integer getEasySolved() { return easySolved; }
    public Integer getMediumSolved() { return mediumSolved; }
    public Integer getHardSolved() { return hardSolved; }
    public Integer getRating() { return rating; }
    public Integer getMaxRating() { return maxRating; }
    public String getRankTitle() { return rankTitle; }
    public Integer getGlobalRank() { return globalRank; }
    public Integer getContests() { return contests; }
    public Integer getScore() { return score; }
    public Integer getRepos() { return repos; }
    public Integer getFollowers() { return followers; }
    public Integer getStars() { return stars; }
    public SyncStatus getSyncStatus() { return syncStatus == null ? SyncStatus.PENDING : syncStatus; }
    public String getSyncMessage() { return syncMessage; }
    public Instant getLastSyncedAt() { return lastSyncedAt; }
    public Instant getLastAttemptAt() { return lastAttemptAt; }
}
