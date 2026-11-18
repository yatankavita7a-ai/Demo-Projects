package CodeTrack.service;

import CodeTrack.dto.*;
import CodeTrack.entity.Role;
import CodeTrack.entity.User;
import CodeTrack.exception.ApiException;
import CodeTrack.repository.PlatformProfileRepository;
import CodeTrack.repository.ProgressSnapshotRepository;
import CodeTrack.repository.UserRepository;
import CodeTrack.security.JwtService;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Locale;

@Service
public class UserService {

    private final UserRepository userRepository;
    private final PlatformProfileRepository platformProfileRepository;
    private final ProgressSnapshotRepository snapshotRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;

    public UserService(UserRepository userRepository, PlatformProfileRepository platformProfileRepository,
                       ProgressSnapshotRepository snapshotRepository, PasswordEncoder passwordEncoder,
                       JwtService jwtService) {
        this.userRepository = userRepository;
        this.platformProfileRepository = platformProfileRepository;
        this.snapshotRepository = snapshotRepository;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
    }

    @Transactional
    public AuthResponse register(RegisterRequest req) {
        String email = normalizeEmail(req.email());
        if (userRepository.existsByEmail(email)) {
            throw new ApiException(HttpStatus.CONFLICT, "An account with this email already exists");
        }
        User user = new User();
        user.setName(req.name().trim());
        user.setEmail(email);
        user.setPassword(passwordEncoder.encode(req.password()));
        user.setCollege(blankToNull(req.college()));
        user.setRole(parseRole(req.role()));
        user.setPublicProfile(true);
        try {
            user = userRepository.saveAndFlush(user);
        } catch (DataIntegrityViolationException e) { // two registrations racing for the same email
            throw new ApiException(HttpStatus.CONFLICT, "An account with this email already exists");
        }
        return new AuthResponse(jwtService.generateToken(user), UserDto.from(user));
    }

    @Transactional(readOnly = true)
    public AuthResponse login(LoginRequest req) {
        User user = userRepository.findByEmail(normalizeEmail(req.email()))
                .filter(u -> passwordEncoder.matches(req.password(), u.getPassword()))
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "Invalid email or password"));
        return new AuthResponse(jwtService.generateToken(user), UserDto.from(user));
    }

    @Transactional(readOnly = true)
    public UserDto getMe(Long userId) {
        return UserDto.from(load(userId));
    }

    @Transactional
    public UserDto updateMe(Long userId, UpdateProfileRequest req) {
        User user = load(userId);
        user.setName(req.name().trim());
        user.setCollege(blankToNull(req.college()));
        user.setCourse(blankToNull(req.course()));
        user.setBranch(blankToNull(req.branch()));
        user.setGraduationYear(req.graduationYear());
        user.setBio(blankToNull(req.bio()));
        user.setLocation(blankToNull(req.location()));
        if (req.publicProfile() != null) user.setPublicProfile(req.publicProfile());
        return UserDto.from(userRepository.saveAndFlush(user));
    }

    /** Changes the password and revokes all existing tokens; returns a fresh token. */
    @Transactional
    public AuthResponse changePassword(Long userId, ChangePasswordRequest req) {
        User user = load(userId);
        if (!passwordEncoder.matches(req.currentPassword(), user.getPassword())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Current password is incorrect");
        }
        user.setPassword(passwordEncoder.encode(req.newPassword()));
        user.bumpTokenVersion();
        user = userRepository.saveAndFlush(user);
        return new AuthResponse(jwtService.generateToken(user), UserDto.from(user));
    }

    /** Signs the user out of every device by invalidating all issued tokens. */
    @Transactional
    public void logoutEverywhere(Long userId) {
        User user = load(userId);
        user.bumpTokenVersion();
        userRepository.save(user);
    }

    @Transactional
    public void deleteAccount(Long userId, String password) {
        User user = load(userId);
        if (!passwordEncoder.matches(password, user.getPassword())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Password is incorrect");
        }
        platformProfileRepository.deleteByUserId(userId);
        snapshotRepository.deleteByUserId(userId);
        userRepository.delete(user);
    }

    private User load(Long userId) {
        return userRepository.findById(userId)
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "Account no longer exists"));
    }

    private static Role parseRole(String role) {
        if (role == null || role.isBlank()) return Role.STUDENT;
        try {
            return Role.valueOf(role.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Account type must be STUDENT, COLLEGE or RECRUITER");
        }
    }

    private static String normalizeEmail(String email) {
        return email.trim().toLowerCase(Locale.ROOT);
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
