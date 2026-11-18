package CodeTrack.dto;

import java.time.Instant;
import java.util.List;

/** What anyone can see about a student who made their profile public (no email). */
public record PublicProfileDto(Long id, String name, String college, String course, String branch,
                               Integer graduationYear, String bio, String location, Instant memberSince,
                               SummaryDto summary, List<PlatformProfileDto> platforms,
                               List<ProgressPoint> progress) {}
