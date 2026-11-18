package CodeTrack.dto;

import CodeTrack.entity.Role;
import CodeTrack.entity.User;

import java.time.Instant;

public record UserDto(Long id, String name, String email, String college, String course, String branch,
                      Integer graduationYear, String bio, String location, Role role,
                      boolean publicProfile, Instant createdAt) {
    public static UserDto from(User u) {
        return new UserDto(u.getId(), u.getName(), u.getEmail(), u.getCollege(), u.getCourse(), u.getBranch(),
                u.getGraduationYear(), u.getBio(), u.getLocation(), u.getRole(), u.isPublicProfile(), u.getCreatedAt());
    }
}
