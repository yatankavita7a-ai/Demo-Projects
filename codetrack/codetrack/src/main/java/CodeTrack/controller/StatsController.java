package CodeTrack.controller;

import CodeTrack.dto.CollegeOverviewDto;
import CodeTrack.dto.DashboardDto;
import CodeTrack.dto.LeaderboardEntryDto;
import CodeTrack.dto.PublicProfileDto;
import CodeTrack.security.AuthUser;
import CodeTrack.service.StatsService;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class StatsController {

    private final StatsService statsService;

    public StatsController(StatsService statsService) {
        this.statsService = statsService;
    }

    @GetMapping("/dashboard")
    public DashboardDto dashboard(@AuthenticationPrincipal AuthUser me) {
        return statsService.dashboard(me.id());
    }

    @GetMapping("/leaderboard")
    public List<LeaderboardEntryDto> leaderboard(@AuthenticationPrincipal AuthUser me,
                                                 @RequestParam(required = false) String q,
                                                 @RequestParam(required = false) String college,
                                                 @RequestParam(required = false) String platform,
                                                 @RequestParam(required = false) Integer minSolved,
                                                 @RequestParam(required = false) String sort,
                                                 @RequestParam(required = false) Integer limit) {
        return statsService.leaderboard(new StatsService.LeaderboardQuery(q, college, platform, minSolved, sort, limit), me.id());
    }

    @GetMapping("/college/overview")
    public CollegeOverviewDto collegeOverview(@AuthenticationPrincipal AuthUser me) {
        return statsService.collegeOverview(me.id());
    }

    @GetMapping("/public/users/{id}")
    public PublicProfileDto publicProfile(@PathVariable Long id) {
        return statsService.publicProfile(id);
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "UP");
    }
}
