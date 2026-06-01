package com.example.ghasdefender.web.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record ItemRequest(
        @NotBlank @Size(max = 255) String name,
        @NotBlank @Size(max = 1000) String description
) {
}
