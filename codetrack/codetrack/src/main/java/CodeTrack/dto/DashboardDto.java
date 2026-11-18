package CodeTrack.dto;

import java.util.List;

public record DashboardDto(UserDto user, SummaryDto summary, List<PlatformProfileDto> platforms,
                           List<ProgressPoint> progress) {}
