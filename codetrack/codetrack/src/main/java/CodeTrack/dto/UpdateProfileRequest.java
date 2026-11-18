package CodeTrack.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record UpdateProfileRequest(
        @NotBlank(message = "Name is required") @Size(max = 100, message = "Name must be at most 100 characters") String name,
        @Size(max = 150, message = "College must be at most 150 characters") String college,
        @Size(max = 100, message = "Course must be at most 100 characters") String course,
        @Size(max = 100, message = "Branch must be at most 100 characters") String branch,
        @Min(value = 1990, message = "Enter a valid graduation year") @Max(value = 2100, message = "Enter a valid graduation year") Integer graduationYear,
        @Size(max = 500, message = "Bio must be at most 500 characters") String bio,
        @Size(max = 100, message = "Location must be at most 100 characters") String location,
        Boolean publicProfile
) {}
