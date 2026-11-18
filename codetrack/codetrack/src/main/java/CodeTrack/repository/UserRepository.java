package CodeTrack.repository;

import CodeTrack.entity.Role;
import CodeTrack.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;
import java.util.Optional;

public interface UserRepository extends JpaRepository<User, Long> {
    Optional<User> findByEmail(String email);

    boolean existsByEmail(String email);

    /** Students who opted into a public profile (rows with NULL role/publicProfile predate those columns and default to student/public). */
    @Query("select u from User u where (u.role is null or u.role = :role) and (u.publicProfile is null or u.publicProfile = true)")
    List<User> findPublicByRole(Role role);
}
