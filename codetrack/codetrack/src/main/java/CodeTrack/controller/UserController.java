package CodeTrack.controller;

import CodeTrack.dto.*;
import CodeTrack.security.AuthUser;
import CodeTrack.service.UserService;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

/** Everything here acts on the caller's own account only; the user id always comes from the token. */
@RestController
@RequestMapping("/api/users/me")
public class UserController {

    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    @GetMapping
    public UserDto me(@AuthenticationPrincipal AuthUser me) {
        return userService.getMe(me.id());
    }

    @PutMapping
    public UserDto update(@AuthenticationPrincipal AuthUser me, @Valid @RequestBody UpdateProfileRequest request) {
        return userService.updateMe(me.id(), request);
    }

    @PutMapping("/password")
    public AuthResponse changePassword(@AuthenticationPrincipal AuthUser me,
                                       @Valid @RequestBody ChangePasswordRequest request) {
        return userService.changePassword(me.id(), request);
    }

    @DeleteMapping
    public ResponseEntity<Void> delete(@AuthenticationPrincipal AuthUser me,
                                       @Valid @RequestBody PasswordConfirmRequest request) {
        userService.deleteAccount(me.id(), request.password());
        return ResponseEntity.noContent().build();
    }
}
