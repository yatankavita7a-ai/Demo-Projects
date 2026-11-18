package CodeTrack.security;

import CodeTrack.entity.User;
import CodeTrack.repository.UserRepository;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

/**
 * Reads "Authorization: Bearer <jwt>", validates it, checks the user still exists and the
 * token hasn't been revoked, then authenticates the request as an {@link AuthUser}.
 * Invalid tokens simply leave the request unauthenticated; Spring Security then returns 401
 * for protected endpoints.
 */
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtService jwtService;
    private final UserRepository userRepository;

    public JwtAuthenticationFilter(JwtService jwtService, UserRepository userRepository) {
        this.jwtService = jwtService;
        this.userRepository = userRepository;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")
                && SecurityContextHolder.getContext().getAuthentication() == null) {
            authenticate(header.substring(7).trim(), request);
        }
        chain.doFilter(request, response);
    }

    private void authenticate(String token, HttpServletRequest request) {
        try {
            Claims claims = jwtService.parse(token);
            Number uid = claims.get("uid", Number.class);
            Number tv = claims.get("tv", Number.class);
            if (uid == null) return;
            User user = userRepository.findById(uid.longValue()).orElse(null);
            if (user == null
                    || !user.getEmail().equalsIgnoreCase(claims.getSubject())
                    || user.getTokenVersion() != (tv == null ? 0 : tv.intValue())) {
                return; // deleted user, changed email, or revoked token
            }
            AuthUser principal = new AuthUser(user.getId(), user.getEmail(), user.getRole());
            var auth = new UsernamePasswordAuthenticationToken(principal, null,
                    List.of(new SimpleGrantedAuthority("ROLE_" + user.getRole().name())));
            auth.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
            SecurityContextHolder.getContext().setAuthentication(auth);
        } catch (JwtException | IllegalArgumentException e) {
            // invalid/expired token -> stay anonymous
        }
    }
}
