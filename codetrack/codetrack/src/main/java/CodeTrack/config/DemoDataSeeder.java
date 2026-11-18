package CodeTrack.config;

import CodeTrack.entity.*;
import CodeTrack.repository.PlatformProfileRepository;
import CodeTrack.repository.ProgressSnapshotRepository;
import CodeTrack.repository.UserRepository;
import CodeTrack.service.platform.PlatformStats;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Random;

/**
 * Fills an empty development database with sample institutes, students and a recruiter so every
 * dashboard has something to show. Runs only when {@code app.demo-data=true} (on in the dev profile)
 * and only once: it does nothing if the demo recruiter account already exists.
 *
 * <p>All demo accounts use the password {@value #PASSWORD}. Their platform stats are generated
 * (each student solves at most 2,000 problems in total) and marked as demo, so they are never
 * synced against the real platforms.
 */
@Component
@ConditionalOnProperty(name = "app.demo-data", havingValue = "true")
public class DemoDataSeeder implements CommandLineRunner {

    private static final Logger log = LoggerFactory.getLogger(DemoDataSeeder.class);
    static final String PASSWORD = "demo1234";
    private static final String DOMAIN = "@codetrack.demo";
    private static final int MAX_TOTAL_SOLVED = 2000;
    private static final int MIN_TOTAL_SOLVED = 120;

    private record Institute(String name, String slug, String city, String course, List<String> students) {}

    private static final List<Institute> INSTITUTES = List.of(
            new Institute("IIT Delhi", "iitdelhi", "New Delhi", "B.Tech",
                    List.of("Aarav Sharma", "Ananya Iyer", "Rohan Gupta", "Ishita Verma", "Kabir Malhotra", "Meera Nair")),
            new Institute("NIT Trichy", "nittrichy", "Tiruchirappalli", "B.Tech",
                    List.of("Arjun Reddy", "Diya Krishnan", "Vikram Subramanian", "Sneha Pillai", "Karthik Raman", "Pooja Venkatesh")),
            new Institute("BITS Pilani", "bitspilani", "Pilani", "B.E.",
                    List.of("Aditya Joshi", "Riya Agarwal", "Siddharth Mehta", "Tanvi Kulkarni", "Yash Bansal", "Nisha Choudhary")),
            new Institute("Delhi Technological University", "dtu", "New Delhi", "B.Tech",
                    List.of("Harsh Vardhan", "Simran Kaur", "Manav Arora", "Priya Saxena", "Dev Khanna", "Aisha Khan")),
            new Institute("VIT Vellore", "vit", "Vellore", "B.Tech",
                    List.of("Rahul Menon", "Kavya Rao", "Nikhil Jain", "Shreya Das", "Varun Patel", "Lavanya Murthy"))
    );

    private static final List<String> BRANCHES = List.of("Computer Science", "Information Technology",
            "Electronics & Communication", "AI & Data Science");
    private static final List<String> BIOS = List.of(
            "Competitive programmer who loves graph problems.",
            "Backend developer in the making. Java and Spring Boot fan.",
            "Practising DSA daily, one problem at a time.",
            "Open-source contributor and contest regular.",
            "Interested in systems, databases and clean code.",
            "Building side projects and climbing the rating ladder.");

    private final UserRepository userRepository;
    private final PlatformProfileRepository profileRepository;
    private final ProgressSnapshotRepository snapshotRepository;
    private final PasswordEncoder passwordEncoder;

    public DemoDataSeeder(UserRepository userRepository, PlatformProfileRepository profileRepository,
                          ProgressSnapshotRepository snapshotRepository, PasswordEncoder passwordEncoder) {
        this.userRepository = userRepository;
        this.profileRepository = profileRepository;
        this.snapshotRepository = snapshotRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @Override
    public void run(String... args) {
        if (userRepository.existsByEmail("recruiter" + DOMAIN)) return;

        String hash = passwordEncoder.encode(PASSWORD);
        Random random = new Random(2026);
        Instant now = Instant.now();
        int students = 0;

        for (Institute inst : INSTITUTES) {
            User college = account(inst.name() + " Placement Cell", "placements." + inst.slug() + DOMAIN, hash, Role.COLLEGE);
            college.setCollege(inst.name());
            college.setLocation(inst.city());
            college.setBio("Training & placement office of " + inst.name() + ".");
            userRepository.save(college);

            for (String name : inst.students()) {
                createStudent(name, inst, hash, random, now);
                students++;
            }
        }

        User recruiter = account("Priya Kapoor (Recruiter)", "recruiter" + DOMAIN, hash, Role.RECRUITER);
        recruiter.setCollege("TechNova Solutions");
        recruiter.setBio("Campus hiring for backend and platform engineering roles.");
        userRepository.save(recruiter);

        log.info("Demo data created: {} institutes, {} students and 1 recruiter (password '{}', emails end with {})",
                INSTITUTES.size(), students, PASSWORD, DOMAIN);
    }

    private void createStudent(String name, Institute inst, String hash, Random r, Instant now) {
        String handle = name.toLowerCase(Locale.ROOT).replace(' ', '_');
        User u = account(name, handle.replace('_', '.') + DOMAIN, hash, Role.STUDENT);
        u.setCollege(inst.name());
        u.setCourse(inst.course());
        u.setBranch(BRANCHES.get(r.nextInt(BRANCHES.size())));
        u.setGraduationYear(2026 + r.nextInt(4));
        u.setLocation(inst.city());
        u.setBio(BIOS.get(r.nextInt(BIOS.size())));
        u = userRepository.save(u);

        // skill in [0,1) drives everything; skewed so most students sit in the few-hundred range
        double skill = Math.pow(r.nextDouble(), 1.15);
        int target = MIN_TOTAL_SOLVED + (int) Math.round(skill * (MAX_TOTAL_SOLVED - MIN_TOTAL_SOLVED));

        // LeetCode always; the others with decreasing likelihood
        boolean gfg = r.nextDouble() < 0.7, cf = r.nextDouble() < 0.6, cc = r.nextDouble() < 0.5, gh = r.nextDouble() < 0.85;
        double wLc = 0.5, wGfg = gfg ? 0.2 : 0, wCf = cf ? 0.18 : 0, wCc = cc ? 0.12 : 0;
        double wSum = wLc + wGfg + wCf + wCc;

        List<PlatformProfile> profiles = new ArrayList<>();
        Instant synced = now.minus(1 + r.nextInt(20), ChronoUnit.HOURS);

        int lc = (int) Math.round(target * wLc / wSum);
        int lcRating = 1350 + (int) (skill * 900) + r.nextInt(80);
        profiles.add(profile(u, Platform.LEETCODE, handle, synced, PlatformStats.builder()
                .totalSolved(lc).easySolved((int) (lc * 0.42)).hardSolved((int) (lc * 0.13))
                .mediumSolved(lc - (int) (lc * 0.42) - (int) (lc * 0.13))
                .rating(lcRating).maxRating(lcRating + r.nextInt(90))
                .rankTitle(lcRating >= 2150 ? "Guardian" : lcRating >= 1850 ? "Knight" : null)
                .globalRank(Math.max(2_000, (int) ((1 - skill) * 750_000) + r.nextInt(20_000)))
                .contests(4 + (int) (skill * 70) + r.nextInt(8))
                .build()));

        if (gfg) {
            int n = (int) Math.round(target * wGfg / wSum);
            profiles.add(profile(u, Platform.GEEKSFORGEEKS, handle.replace("_", ""), synced, PlatformStats.builder()
                    .totalSolved(n).easySolved((int) (n * 0.5)).hardSolved((int) (n * 0.1))
                    .mediumSolved(n - (int) (n * 0.5) - (int) (n * 0.1))
                    .score(n * 3 + r.nextInt(40))
                    .build()));
        }
        if (cf) {
            int n = (int) Math.round(target * wCf / wSum);
            int rating = 850 + (int) (skill * 1250) + r.nextInt(100);
            profiles.add(profile(u, Platform.CODEFORCES, handle, synced, PlatformStats.builder()
                    .totalSolved(n).rating(rating).maxRating(rating + r.nextInt(120))
                    .rankTitle(codeforcesRank(rating)).contests(3 + (int) (skill * 80) + r.nextInt(6))
                    .build()));
        }
        if (cc) {
            int n = (int) Math.round(target * wCc / wSum);
            int rating = 1250 + (int) (skill * 950) + r.nextInt(90);
            profiles.add(profile(u, Platform.CODECHEF, handle, synced, PlatformStats.builder()
                    .totalSolved(n).rating(rating).maxRating(rating + r.nextInt(100))
                    .rankTitle(codechefStars(rating) + "★").contests(2 + (int) (skill * 50) + r.nextInt(6))
                    .globalRank(Math.max(500, (int) ((1 - skill) * 120_000) + r.nextInt(5_000)))
                    .build()));
        }
        if (gh) {
            profiles.add(profile(u, Platform.GITHUB, handle.replace("_", "-"), synced, PlatformStats.builder()
                    .repos(4 + r.nextInt(35)).followers(r.nextInt(90)).stars((int) (r.nextInt(60) + skill * 140))
                    .build()));
        }
        profileRepository.saveAll(profiles);

        int total = profiles.stream().filter(p -> p.getPlatform().countsSolved())
                .mapToInt(p -> p.getTotalSolved() == null ? 0 : p.getTotalSolved()).sum();
        saveProgress(u, total);
    }

    /** About two months of history, growing to today's total, one point every 3 days. */
    private void saveProgress(User u, int total) {
        LocalDate today = LocalDate.now();
        List<ProgressSnapshot> points = new ArrayList<>();
        for (int daysAgo = 60; daysAgo >= 0; daysAgo -= 3) {
            double fraction = 1 - 0.4 * Math.pow(daysAgo / 60.0, 0.9);
            points.add(new ProgressSnapshot(u, today.minusDays(daysAgo), (int) Math.round(total * fraction)));
        }
        snapshotRepository.saveAll(points);
    }

    private static User account(String name, String email, String hash, Role role) {
        User u = new User();
        u.setName(name);
        u.setEmail(email);
        u.setPassword(hash);
        u.setRole(role);
        u.setPublicProfile(true);
        return u;
    }

    private static PlatformProfile profile(User u, Platform platform, String username, Instant synced, PlatformStats stats) {
        PlatformProfile p = new PlatformProfile(u, platform, username);
        p.applyStats(stats);
        p.markSynced(synced);
        p.markDemo();
        return p;
    }

    private static String codeforcesRank(int rating) {
        if (rating < 1200) return "Newbie";
        if (rating < 1400) return "Pupil";
        if (rating < 1600) return "Specialist";
        if (rating < 1900) return "Expert";
        if (rating < 2100) return "Candidate Master";
        return "Master";
    }

    private static int codechefStars(int rating) {
        if (rating < 1400) return 1;
        if (rating < 1600) return 2;
        if (rating < 1800) return 3;
        if (rating < 2000) return 4;
        return 5;
    }
}
