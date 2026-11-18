package CodeTrack.dto;

import CodeTrack.entity.Platform;

import java.util.List;
import java.util.Map;

public record CollegeOverviewDto(String college, int studentCount, int activeCount, int totalSolved,
                                 int averageSolved, Map<Platform, Integer> platformAdoption,
                                 Map<String, Integer> distribution, List<LeaderboardEntryDto> topStudents) {}
