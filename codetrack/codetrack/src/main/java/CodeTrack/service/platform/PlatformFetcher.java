package CodeTrack.service.platform;

import CodeTrack.entity.Platform;

/**
 * Fetches public statistics for one platform. Implementations are Spring beans;
 * PlatformService picks the one whose {@link #platform()} matches.
 */
public interface PlatformFetcher {

    Platform platform();

    /**
     * @param username the platform username (already validated: [A-Za-z0-9_.-]{1,64})
     * @throws PlatformFetchException with a short, user-facing message when the user
     *         doesn't exist or the platform can't be reached/parsed
     */
    PlatformStats fetch(String username) throws PlatformFetchException;
}
