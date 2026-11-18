package CodeTrack.service;

import CodeTrack.dto.PlatformProfileDto;
import CodeTrack.entity.Platform;
import CodeTrack.entity.PlatformProfile;
import CodeTrack.entity.ProgressSnapshot;
import CodeTrack.entity.User;
import CodeTrack.exception.ApiException;
import CodeTrack.repository.PlatformProfileRepository;
import CodeTrack.repository.ProgressSnapshotRepository;
import CodeTrack.repository.UserRepository;
import CodeTrack.service.platform.PlatformFetchException;
import CodeTrack.service.platform.PlatformFetcher;
import CodeTrack.service.platform.PlatformStats;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/**
 * Links platform accounts to users and refreshes their stats. Network calls happen outside
 * any database transaction; each save is its own short transaction.
 */
@Service
public class PlatformService {

    private static final Logger log = LoggerFactory.getLogger(PlatformService.class);
    private static final Duration RESYNC_COOLDOWN = Duration.ofSeconds(30);

    private final PlatformProfileRepository profileRepository;
    private final ProgressSnapshotRepository snapshotRepository;
    private final UserRepository userRepository;
    private final Map<Platform, PlatformFetcher> fetchers = new EnumMap<>(Platform.class);
    private final boolean syncOnLink;

    public PlatformService(PlatformProfileRepository profileRepository, ProgressSnapshotRepository snapshotRepository,
                           UserRepository userRepository, List<PlatformFetcher> fetcherBeans,
                           @Value("${app.sync.on-link:true}") boolean syncOnLink) {
        this.profileRepository = profileRepository;
        this.snapshotRepository = snapshotRepository;
        this.userRepository = userRepository;
        this.syncOnLink = syncOnLink;
        fetcherBeans.forEach(f -> fetchers.put(f.platform(), f));
    }

    public List<PlatformProfileDto> list(Long userId) {
        return profileRepository.findByUserIdOrderByPlatform(userId).stream().map(PlatformProfileDto::from).toList();
    }

    public PlatformProfileDto link(Long userId, String platformKey, String input) {
        Platform platform = Platform.fromKey(platformKey);
        String username = platform.extractUsername(input);
        PlatformProfile profile = profileRepository.findByUserIdAndPlatform(userId, platform)
                .orElseGet(() -> new PlatformProfile(userRepository.getReferenceById(userId), platform, username));
        if (profile.getId() != null && !profile.getUsername().equalsIgnoreCase(username)) {
            profile.changeUsername(username);
        }
        profile = profileRepository.save(profile);
        if (syncOnLink) profile = syncProfile(profile);
        else recordSnapshot(userId);
        return PlatformProfileDto.from(profile);
    }

    public void unlink(Long userId, String platformKey) {
        Platform platform = Platform.fromKey(platformKey);
        PlatformProfile profile = profileRepository.findByUserIdAndPlatform(userId, platform)
                .orElseThrow(() -> notLinked(platform));
        profileRepository.delete(profile);
        recordSnapshot(userId);
    }

    public PlatformProfileDto sync(Long userId, String platformKey) {
        Platform platform = Platform.fromKey(platformKey);
        PlatformProfile profile = profileRepository.findByUserIdAndPlatform(userId, platform)
                .orElseThrow(() -> notLinked(platform));
        return PlatformProfileDto.from(syncIfStale(profile));
    }

    public List<PlatformProfileDto> syncAll(Long userId) {
        return profileRepository.findByUserIdOrderByPlatform(userId).stream()
                .map(this::syncIfStale)
                .map(PlatformProfileDto::from)
                .toList();
    }

    /** Refreshes every linked profile once a day (cron configurable via app.sync.cron). */
    @Scheduled(cron = "${app.sync.cron:0 0 3 * * *}")
    public void scheduledSync() {
        List<PlatformProfile> all = profileRepository.findAll();
        log.info("Scheduled sync of {} platform profiles", all.size());
        for (PlatformProfile p : all) {
            if (p.isDemo()) continue;
            try {
                syncProfile(p);
                Thread.sleep(1000); // be polite to the platforms
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            } catch (RuntimeException e) {
                log.warn("Scheduled sync failed for profile {}: {}", p.getId(), e.getMessage());
            }
        }
    }

    private PlatformProfile syncIfStale(PlatformProfile profile) {
        if (profile.isDemo()) return profile;
        Instant last = profile.getLastAttemptAt();
        if (last != null && last.isAfter(Instant.now().minus(RESYNC_COOLDOWN))) return profile;
        return syncProfile(profile);
    }

    private PlatformProfile syncProfile(PlatformProfile profile) {
        Platform platform = profile.getPlatform();
        PlatformFetcher fetcher = fetchers.get(platform);
        Instant now = Instant.now();
        if (fetcher == null) {
            profile.markFailed("Syncing " + platform.getDisplayName() + " is not supported yet", now);
        } else {
            try {
                PlatformStats stats = fetcher.fetch(profile.getUsername());
                profile.applyStats(stats);
                profile.markSynced(now);
            } catch (PlatformFetchException e) {
                profile.markFailed(e.getMessage(), now);
            } catch (RuntimeException e) {
                log.warn("Unexpected error syncing {} '{}'", platform, profile.getUsername(), e);
                profile.markFailed("Could not read " + platform.getDisplayName() + " data right now", now);
            }
        }
        PlatformProfile saved = profileRepository.save(profile);
        recordSnapshot(saved.getUser().getId());
        return saved;
    }

    /** Upserts today's progress point with the user's current total solved count. */
    private void recordSnapshot(Long userId) {
        int total = profileRepository.findByUserIdOrderByPlatform(userId).stream()
                .filter(p -> p.getPlatform().countsSolved())
                .map(PlatformProfile::getTotalSolved)
                .filter(Objects::nonNull)
                .mapToInt(Integer::intValue)
                .sum();
        LocalDate today = LocalDate.now();
        ProgressSnapshot snap = snapshotRepository.findByUserIdAndDate(userId, today)
                .orElseGet(() -> {
                    User ref = userRepository.getReferenceById(userId);
                    return new ProgressSnapshot(ref, today, total);
                });
        snap.setTotalSolved(total);
        try {
            snapshotRepository.save(snap);
        } catch (RuntimeException e) {
            log.debug("Snapshot upsert raced for user {}: {}", userId, e.getMessage());
        }
    }

    private static ApiException notLinked(Platform platform) {
        return new ApiException(HttpStatus.NOT_FOUND, platform.getDisplayName() + " is not connected");
    }
}
