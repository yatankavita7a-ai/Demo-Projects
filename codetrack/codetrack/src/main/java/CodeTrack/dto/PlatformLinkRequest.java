package CodeTrack.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/** Either a full profile URL or a bare username. */
public record PlatformLinkRequest(
        @NotBlank(message = "Enter a profile URL or username") @Size(max = 300) String input
) {}
