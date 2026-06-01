package com.example.ghasdefender;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.ghasdefender.repo.UserRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("local")
class BackendApplicationTests {

    @Autowired
    private UserRepository userRepository;

    @Test
    void contextLoads() {
    }

    @Test
    void flywaySeedsDemoUserWithBcryptPassword() {
        BCryptPasswordEncoder encoder = new BCryptPasswordEncoder();

        assertThat(userRepository.findByUsername("demo"))
                .isPresent()
                .get()
                .satisfies(user -> assertThat(encoder.matches("demo", user.getPasswordHash())).isTrue());
    }
}
