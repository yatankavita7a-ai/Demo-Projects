package CodeTrack.exception;

import org.springframework.http.HttpStatus;

/** Thrown by services to produce a JSON error with a specific HTTP status. */
public class ApiException extends RuntimeException {
    private final HttpStatus status;

    public ApiException(HttpStatus status, String message) {
        super(message);
        this.status = status;
    }

    public HttpStatus getStatus() { return status; }
}
