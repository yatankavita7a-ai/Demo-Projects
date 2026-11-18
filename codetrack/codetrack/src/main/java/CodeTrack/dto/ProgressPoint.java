package CodeTrack.dto;

import java.time.LocalDate;

public record ProgressPoint(LocalDate date, int totalSolved) {}
