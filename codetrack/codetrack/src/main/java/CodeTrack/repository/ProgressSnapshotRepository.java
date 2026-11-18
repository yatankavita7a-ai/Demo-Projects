package CodeTrack.repository;

import CodeTrack.entity.ProgressSnapshot;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface ProgressSnapshotRepository extends JpaRepository<ProgressSnapshot, Long> {
    Optional<ProgressSnapshot> findByUserIdAndDate(Long userId, LocalDate date);

    List<ProgressSnapshot> findByUserIdAndDateGreaterThanEqualOrderByDate(Long userId, LocalDate from);

    @Modifying
    @Query("delete from ProgressSnapshot s where s.user.id = :userId")
    void deleteByUserId(Long userId);
}
