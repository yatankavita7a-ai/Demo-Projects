package CodeTrack.controller;

import CodeTrack.dto.AuthResponse;
import CodeTrack.dto.LoginRequest;
import CodeTrack.dto.RegisterRequest;
import CodeTrack.security.AuthUser;
import CodeTrack.service.UserService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final UserService userService;

    public AuthController(UserService userService) {
        this.userService = userService;
    }

    @PostMapping("/register")
    public ResponseEntity<AuthResponse> register(@Valid @RequestBody RegisterRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(userService.register(request));
    }

    @PostMapping("/login")
    public AuthResponse login(@Valid @RequestBody LoginRequest request) {
        return userService.login(request);
    }

    /** JWTs are stateless, so a normal logout just discards the token client-side; this revokes all of them. */
    @PostMapping("/logout-all")
    public ResponseEntity<Void> logoutAll(@AuthenticationPrincipal AuthUser me) {
        userService.logoutEverywhere(me.id());
        return ResponseEntity.noContent().build();
    }
}
