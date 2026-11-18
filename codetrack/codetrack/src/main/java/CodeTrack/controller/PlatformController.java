package CodeTrack.controller;

import CodeTrack.dto.PlatformLinkRequest;
import CodeTrack.dto.PlatformProfileDto;
import CodeTrack.security.AuthUser;
import CodeTrack.service.PlatformService;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/platforms")
public class PlatformController {

    private final PlatformService platformService;

    public PlatformController(PlatformService platformService) {
        this.platformService = platformService;
    }

    @GetMapping
    public List<PlatformProfileDto> list(@AuthenticationPrincipal AuthUser me) {
        return platformService.list(me.id());
    }

    @PutMapping("/{platform}")
    public PlatformProfileDto link(@AuthenticationPrincipal AuthUser me, @PathVariable String platform,
                                   @Valid @RequestBody PlatformLinkRequest request) {
        return platformService.link(me.id(), platform, request.input());
    }

    @DeleteMapping("/{platform}")
    public ResponseEntity<Void> unlink(@AuthenticationPrincipal AuthUser me, @PathVariable String platform) {
        platformService.unlink(me.id(), platform);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/sync")
    public List<PlatformProfileDto> syncAll(@AuthenticationPrincipal AuthUser me) {
        return platformService.syncAll(me.id());
    }

    @PostMapping("/{platform}/sync")
    public PlatformProfileDto sync(@AuthenticationPrincipal AuthUser me, @PathVariable String platform) {
        return platformService.sync(me.id(), platform);
    }
}
