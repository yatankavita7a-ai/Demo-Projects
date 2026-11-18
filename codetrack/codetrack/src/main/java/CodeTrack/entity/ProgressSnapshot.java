package CodeTrack.entity;

import jakarta.persistence.*;

import java.time.LocalDate;

/** One point per user per day: total problems solved after that day's latest sync. */
@Entity
@Table(name = "progress_snapshots",
        uniqueConstraints = @UniqueConstraint(columnNames = {"user_id", "snapshot_date"}))
public class ProgressSnapshot {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Column(name = "snapshot_date", nullable = false)
    private LocalDate date;

    private int totalSolved;

    protected ProgressSnapshot() {}

    public ProgressSnapshot(User user, LocalDate date, int totalSolved) {
        this.user = user;
        this.date = date;
        this.totalSolved = totalSolved;
    }

    public LocalDate getDate() { return date; }
    public int getTotalSolved() { return totalSolved; }
    public void setTotalSolved(int totalSolved) { this.totalSolved = totalSolved; }
}
