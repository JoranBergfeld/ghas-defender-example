package com.example.ghasdefender.web;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.ghasdefender.config.CorsConfig;
import com.example.ghasdefender.config.SecurityConfig;
import com.example.ghasdefender.domain.User;
import com.example.ghasdefender.repo.UserRepository;
import com.example.ghasdefender.security.JwtAuthenticationFilter;
import com.example.ghasdefender.security.JwtService;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(AuthController.class)
@Import({SecurityConfig.class, CorsConfig.class, JwtAuthenticationFilter.class})
class AuthControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @MockBean
    private UserRepository userRepository;

    @MockBean
    private JwtService jwtService;

    @Test
    void loginReturnsJwtForValidCredentials() throws Exception {
        User user = new User("demo", passwordEncoder.encode("demo"));
        when(userRepository.findByUsername("demo")).thenReturn(Optional.of(user));
        when(jwtService.generateToken("demo")).thenReturn("signed.jwt.token");

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"username\":\"demo\",\"password\":\"demo\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").value("signed.jwt.token"))
                .andExpect(jsonPath("$.tokenType").value("Bearer"));
    }

    @Test
    void loginReturnsUnauthorizedForBadCredentials() throws Exception {
        User user = new User("demo", passwordEncoder.encode("demo"));
        when(userRepository.findByUsername("demo")).thenReturn(Optional.of(user));

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"username\":\"demo\",\"password\":\"wrong\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void loginReturnsUnauthorizedForMissingUser() throws Exception {
        when(userRepository.findByUsername("missing")).thenReturn(Optional.empty());

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"username\":\"missing\",\"password\":\"demo\"}"))
                .andExpect(status().isUnauthorized());
    }
}
