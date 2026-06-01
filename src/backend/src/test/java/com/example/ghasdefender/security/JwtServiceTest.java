package com.example.ghasdefender.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.example.ghasdefender.config.JwtConfig;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.io.Encoders;
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

    @Test
    void configuredBase64KeyCanSignAndVerifyTokens() {
        SecretKey generatedKey = Jwts.SIG.HS256.key().build();
        String encodedKey = Encoders.BASE64.encode(generatedKey.getEncoded());
        SecretKey configuredKey = new JwtConfig().jwtSigningKey(encodedKey);
        JwtService jwtService = new JwtService(configuredKey);

        String token = jwtService.generateToken("demo");

        assertThat(jwtService.isTokenValid(token)).isTrue();
        assertThat(jwtService.extractUsername(token)).isEqualTo("demo");
    }

    @Test
    void missingConfiguredKeyGeneratesLocalDevelopmentKey() {
        SecretKey generatedKey = new JwtConfig().jwtSigningKey("");
        JwtService jwtService = new JwtService(generatedKey);

        String token = jwtService.generateToken("demo");

        assertThat(jwtService.isTokenValid(token)).isTrue();
    }

    @Test
    void shortConfiguredKeyFailsFast() {
        assertThatThrownBy(() -> new JwtConfig().jwtSigningKey("short"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("JWT_SIGNING_KEY must be at least 256 bits");
    }
}
