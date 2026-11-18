package CodeTrack.dto;

import CodeTrack.entity.Platform;

import java.util.List;

public record LeaderboardEntryDto(int rank, Long userId, String name, String college, String branch,
                                  Integer graduationYear, int totalSolved, int hardSolved,
                                  List<Platform> platforms, Integer codeforcesRating, Integer leetcodeRating,
                                  Integer codechefRating, boolean me) {}
