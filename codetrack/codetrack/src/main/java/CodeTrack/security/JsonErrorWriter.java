package CodeTrack.security;

import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.time.Instant;

/** Writes the same JSON error shape as GlobalExceptionHandler from inside the security filter chain. */
final class JsonErrorWriter {
    private JsonErrorWriter() {}

    static void write(HttpServletResponse response, int status, String error, String message) throws IOException {
        response.setStatus(status);
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        response.getWriter().write("{\"status\":" + status
                + ",\"error\":\"" + error + "\""
                + ",\"message\":\"" + message.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
                + ",\"timestamp\":\"" + Instant.now() + "\"}");
    }
}
