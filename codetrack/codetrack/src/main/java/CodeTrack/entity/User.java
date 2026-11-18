package CodeTrack.entity;

import jakarta.persistence.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.Instant;

@Entity
@Table(name = "users")
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 100)
    private String name;

    @Column(nullable = false, unique = true)
    private String email;

    @Column(nullable = false)
    private String password;

    private String college;
    private String course;
    private String branch;
    private Integer graduationYear;

    @Column(length = 500)
    private String bio;

    private String location;

    // Wrapper types so rows created before these columns existed (NULL) still load.
    @Enumerated(EnumType.STRING)
    @Column(length = 20)
    private Role role;

    private Boolean publicProfile;

    /** Bumped to revoke every JWT issued earlier (sign out everywhere / password change). */
    private Integer tokenVersion;

    @CreationTimestamp
    @Column(updatable = false)
    private Instant createdAt;

    @UpdateTimestamp
    private Instant updatedAt;

    public Long getId() { return id; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }
    public String getCollege() { return college; }
    public void setCollege(String college) { this.college = college; }
    public String getCourse() { return course; }
    public void setCourse(String course) { this.course = course; }
    public String getBranch() { return branch; }
    public void setBranch(String branch) { this.branch = branch; }
    public Integer getGraduationYear() { return graduationYear; }
    public void setGraduationYear(Integer graduationYear) { this.graduationYear = graduationYear; }
    public String getBio() { return bio; }
    public void setBio(String bio) { this.bio = bio; }
    public String getLocation() { return location; }
    public void setLocation(String location) { this.location = location; }
    public Role getRole() { return role == null ? Role.STUDENT : role; }
    public void setRole(Role role) { this.role = role; }
    public boolean isPublicProfile() { return publicProfile == null || publicProfile; }
    public void setPublicProfile(boolean publicProfile) { this.publicProfile = publicProfile; }
    public int getTokenVersion() { return tokenVersion == null ? 0 : tokenVersion; }
    public void bumpTokenVersion() { this.tokenVersion = getTokenVersion() + 1; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
