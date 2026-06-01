package com.example.ghasdefender.security;

import static org.assertj.core.api.Assertions.assertThat;

import io.jsonwebtoken.Jwts;
import javax.crypto.SecretKey;
import org.junit.jupiter.api.Test;

class JwtServiceTest {

    @Test
    void generatedTokenContainsSubjectAndValidSignature() {
        SecretKey key = Jwts.SIG.HS256.key().build();
        JwtService jwtService = new JwtService(key);

        String token = jwtService.generateToken("demo");

        assertThat(jwtService.isTokenValid(token)).isTrue();
        assertThat(jwtService.extractUsername(token)).isEqualTo("demo");
    }

    @Test
    void invalidTokenIsRejected() {
        SecretKey key = Jwts.SIG.HS256.key().build();
        JwtService jwtService = new JwtService(key);

        assertThat(jwtService.isTokenValid("not-a-jwt")).isFalse();
    }
}
