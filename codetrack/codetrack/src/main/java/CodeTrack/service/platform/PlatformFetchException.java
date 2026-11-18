package CodeTrack.service.platform;

/** A fetch failure whose message is safe to show to the user (e.g. "User not found on Codeforces"). */
public class PlatformFetchException extends Exception {
    public PlatformFetchException(String message) { super(message); }
    public PlatformFetchException(String message, Throwable cause) { super(message, cause); }
}
