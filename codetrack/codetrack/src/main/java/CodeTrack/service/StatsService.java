package CodeTrack.service;

import CodeTrack.dto.*;
import CodeTrack.entity.*;
import CodeTrack.exception.ApiException;
import CodeTrack.repository.PlatformProfileRepository;
import CodeTrack.repository.ProgressSnapshotRepository;
import CodeTrack.repository.UserRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDate;
import java.util.*;
import java.util.function.Function;
import java.util.stream.Collectors;

/** Builds dashboards, leaderboards, college overviews and public portfolios from stored stats. */
@Service
@Transactional(readOnly = true)
public class StatsService {

    private static final int PROGRESS_DAYS = 90;

    private final UserRepository userRepository;
    private final PlatformProfileRepository profileRepository;
    private final ProgressSnapshotRepository snapshotRepository;

    public StatsService(UserRepository userRepository, PlatformProfileRepository profileRepository,
                        ProgressSnapshotRepository snapshotRepository) {
        this.userRepository = userRepository;
        this.profileRepository = profileRepository;
        this.snapshotRepository = snapshotRepository;
    }

    public record LeaderboardQuery(String q, String college, String platform, Integer minSolved, String sort, Integer limit) {}

    /** Per-student aggregate used for ranking. */
    private record StudentStats(User user, List<PlatformProfile> profiles, int totalSolved, int hardSolved,
                                Integer cf, Integer lc, Integer cc) {}

    // ---------------------------------------------------------------- dashboard / public profile

    public DashboardDto dashboard(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "Account no longer exists"));
        List<PlatformProfile> profiles = profileRepository.findByUserIdOrderByPlatform(userId);
        return new DashboardDto(UserDto.from(user), summarize(user, profiles),
                profiles.stream().map(PlatformProfileDto::from).toList(), progress(userId));
    }

    public PublicProfileDto publicProfile(Long id) {
        User user = userRepository.findById(id)
                .filter(u -> u.isPublicProfile() && u.getRole() == Role.STUDENT)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "This profile is private or doesn't exist"));
        List<PlatformProfile> profiles = profileRepository.findByUserIdOrderByPlatform(id);
        return new PublicProfileDto(user.getId(), user.getName(), user.getCollege(), user.getCourse(),
                user.getBranch(), user.getGraduationYear(), user.getBio(), user.getLocation(), user.getCreatedAt(),
                summarize(user, profiles), profiles.stream().map(PlatformProfileDto::from).toList(), progress(id));
    }

    private List<ProgressPoint> progress(Long userId) {
        return snapshotRepository.findByUserIdAndDateGreaterThanEqualOrderByDate(userId,
                        LocalDate.now().minusDays(PROGRESS_DAYS)).stream()
                .map(s -> new ProgressPoint(s.getDate(), s.getTotalSolved()))
                .toList();
    }

    private SummaryDto summarize(User user, List<PlatformProfile> profiles) {
        int total = 0, easy = 0, medium = 0, hard = 0, contests = 0, repos = 0, stars = 0;
        Map<Platform, Integer> best = new EnumMap<>(Platform.class);
        Instant lastSynced = null;
        for (PlatformProfile p : profiles) {
            if (p.getPlatform().countsSolved()) {
                total += n(p.getTotalSolved());
                easy += n(p.getEasySolved());
                medium += n(p.getMediumSolved());
                hard += n(p.getHardSolved());
                contests += n(p.getContests());
                Integer r = p.getMaxRating() != null ? p.getMaxRating() : p.getRating();
                if (r != null) best.put(p.getPlatform(), r);
            } else {
                repos += n(p.getRepos());
                stars += n(p.getStars());
            }
            if (p.getLastSyncedAt() != null && (lastSynced == null || p.getLastSyncedAt().isAfter(lastSynced))) {
                lastSynced = p.getLastSyncedAt();
            }
        }
        Integer collegeRank = null, collegeSize = null;
        if (user.getRole() == Role.STUDENT && user.isPublicProfile() && user.getCollege() != null) {
            List<StudentStats> peers = rank(allPublicStudents().stream()
                    .filter(s -> sameCollege(s.user().getCollege(), user.getCollege())).toList(), "solved");
            collegeSize = peers.size();
            for (int i = 0; i < peers.size(); i++) {
                if (peers.get(i).user().getId().equals(user.getId())) { collegeRank = i + 1; break; }
            }
        }
        return new SummaryDto(total, easy, medium, hard, profiles.size(), contests, repos, stars, best,
                lastSynced, collegeRank, collegeSize);
    }

    // ---------------------------------------------------------------- leaderboard

    public List<LeaderboardEntryDto> leaderboard(LeaderboardQuery query, Long meId) {
        String q = lower(query.q());
        String college = query.college() == null || query.college().isBlank() ? null : query.college();
        Platform platform = query.platform() == null || query.platform().isBlank() ? null : Platform.fromKey(query.platform());
        int min = query.minSolved() == null ? 0 : query.minSolved();
        int limit = query.limit() == null ? 50 : Math.max(1, Math.min(query.limit(), 200));

        List<StudentStats> filtered = allPublicStudents().stream()
                .filter(s -> q == null || lower(s.user().getName()).contains(q)
                        || (s.user().getCollege() != null && lower(s.user().getCollege()).contains(q)))
                .filter(s -> college == null || (s.user().getCollege() != null
                        && lower(s.user().getCollege()).contains(lower(college))))
                .filter(s -> platform == null || s.profiles().stream().anyMatch(p -> p.getPlatform() == platform))
                .filter(s -> s.totalSolved() >= min)
                .toList();
        return toEntries(rank(filtered, query.sort()), limit, meId);
    }

    // ---------------------------------------------------------------- college

    public CollegeOverviewDto collegeOverview(Long collegeUserId) {
        User me = userRepository.findById(collegeUserId)
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "Account no longer exists"));
        if (me.getCollege() == null || me.getCollege().isBlank()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Add your college name in Profile to see your students");
        }
        List<StudentStats> students = rank(allPublicStudents().stream()
                .filter(s -> sameCollege(s.user().getCollege(), me.getCollege())).toList(), "solved");

        Map<Platform, Integer> adoption = new EnumMap<>(Platform.class);
        for (Platform p : Platform.values()) adoption.put(p, 0);
        Map<String, Integer> distribution = new LinkedHashMap<>();
        for (String b : List.of("0", "1-50", "51-200", "201-500", "500+")) distribution.put(b, 0);

        int total = 0, active = 0;
        for (StudentStats s : students) {
            total += s.totalSolved();
            if (!s.profiles().isEmpty()) active++;
            s.profiles().forEach(p -> adoption.merge(p.getPlatform(), 1, Integer::sum));
            distribution.merge(bucket(s.totalSolved()), 1, Integer::sum);
        }
        int avg = students.isEmpty() ? 0 : Math.round((float) total / students.size());
        return new CollegeOverviewDto(me.getCollege(), students.size(), active, total, avg, adoption, distribution,
                toEntries(students, 10, collegeUserId));
    }

    // ---------------------------------------------------------------- helpers

    private List<StudentStats> allPublicStudents() {
        List<User> users = userRepository.findPublicByRole(Role.STUDENT);
        if (users.isEmpty()) return List.of();
        Map<Long, List<PlatformProfile>> byUser = profileRepository
                .findByUserIdIn(users.stream().map(User::getId).toList()).stream()
                .collect(Collectors.groupingBy(p -> p.getUser().getId()));
        List<StudentStats> result = new ArrayList<>();
        for (User u : users) {
            List<PlatformProfile> ps = byUser.getOrDefault(u.getId(), List.of());
            int total = 0, hard = 0;
            Integer cf = null, lc = null, cc = null;
            for (PlatformProfile p : ps) {
                if (!p.getPlatform().countsSolved()) continue;
                total += n(p.getTotalSolved());
                hard += n(p.getHardSolved());
                switch (p.getPlatform()) {
                    case CODEFORCES -> cf = p.getRating();
                    case LEETCODE -> lc = p.getRating();
                    case CODECHEF -> cc = p.getRating();
                    default -> { }
                }
            }
            result.add(new StudentStats(u, ps, total, hard, cf, lc, cc));
        }
        return result;
    }

    private static List<StudentStats> rank(List<StudentStats> list, String sort) {
        Function<StudentStats, Integer> key = switch (sort == null ? "solved" : sort.toLowerCase(Locale.ROOT)) {
            case "hard" -> StudentStats::hardSolved;
            case "codeforces" -> s -> n(s.cf());
            case "leetcode" -> s -> n(s.lc());
            case "codechef" -> s -> n(s.cc());
            default -> StudentStats::totalSolved;
        };
        return list.stream()
                .sorted(Comparator.comparing(key).reversed()
                        .thenComparing(StudentStats::totalSolved, Comparator.reverseOrder())
                        .thenComparing(s -> s.user().getId()))
                .toList();
    }

    private static List<LeaderboardEntryDto> toEntries(List<StudentStats> ranked, int limit, Long meId) {
        List<LeaderboardEntryDto> out = new ArrayList<>();
        for (int i = 0; i < ranked.size() && i < limit; i++) {
            StudentStats s = ranked.get(i);
            User u = s.user();
            out.add(new LeaderboardEntryDto(i + 1, u.getId(), u.getName(), u.getCollege(), u.getBranch(),
                    u.getGraduationYear(), s.totalSolved(), s.hardSolved(),
                    s.profiles().stream().map(PlatformProfile::getPlatform).sorted().toList(),
                    s.cf(), s.lc(), s.cc(), u.getId().equals(meId)));
        }
        return out;
    }

    private static String bucket(int solved) {
        if (solved == 0) return "0";
        if (solved <= 50) return "1-50";
        if (solved <= 200) return "51-200";
        if (solved <= 500) return "201-500";
        return "500+";
    }

    private static boolean sameCollege(String a, String b) {
        return a != null && b != null && a.trim().equalsIgnoreCase(b.trim());
    }

    private static String lower(String s) {
        return s == null || s.isBlank() ? null : s.trim().toLowerCase(Locale.ROOT);
    }

    private static int n(Integer v) {
        return v == null ? 0 : v;
    }
}
