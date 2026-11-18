package CodeTrack.dto;

import CodeTrack.entity.Platform;

import java.time.Instant;
import java.util.Map;

public record SummaryDto(int totalSolved, int easySolved, int mediumSolved, int hardSolved,
                         int platformsConnected, int contests, int githubRepos, int githubStars,
                         Map<Platform, Integer> bestRatings, Instant lastSyncedAt,
                         Integer collegeRank, Integer collegeSize) {}
