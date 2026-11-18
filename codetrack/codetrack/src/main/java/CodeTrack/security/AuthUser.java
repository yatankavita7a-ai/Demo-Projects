package CodeTrack.security;

import CodeTrack.entity.Role;

/** The authenticated principal placed in the SecurityContext by {@link JwtAuthenticationFilter}. */
public record AuthUser(Long id, String email, Role role) {}
