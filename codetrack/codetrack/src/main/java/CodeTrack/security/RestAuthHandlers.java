package CodeTrack.security;

import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.access.AccessDeniedHandler;

/** JSON 401/403 responses instead of Spring Security's default HTML/blank pages. */
public final class RestAuthHandlers {
    private RestAuthHandlers() {}

    public static AuthenticationEntryPoint entryPoint() {
        return (request, response, ex) -> JsonErrorWriter.write(response, 401, "Unauthorized",
                "Please log in to continue (missing, invalid or expired token)");
    }

    public static AccessDeniedHandler accessDenied() {
        return (request, response, ex) -> JsonErrorWriter.write(response, 403, "Forbidden",
                "Your account type is not allowed to do this");
    }
}
