package CodeTrack.repository;

import CodeTrack.entity.Platform;
import CodeTrack.entity.PlatformProfile;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

public interface PlatformProfileRepository extends JpaRepository<PlatformProfile, Long> {
    List<PlatformProfile> findByUserIdOrderByPlatform(Long userId);

    Optional<PlatformProfile> findByUserIdAndPlatform(Long userId, Platform platform);

    List<PlatformProfile> findByUserIdIn(Collection<Long> userIds);

    @Modifying
    @Query("delete from PlatformProfile p where p.user.id = :userId")
    void deleteByUserId(Long userId);
}
