package com.example.ghasdefender.config;

import com.example.ghasdefender.security.JwtKeyBootstrap;
import io.jsonwebtoken.security.Keys;
import java.util.Base64;
import javax.crypto.SecretKey;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

@Configuration
public class JwtConfig {

    @Bean
    @Profile("cloud")
    public SecretKey cloudJwtSigningKey(JwtKeyBootstrap jwtKeyBootstrap) {
        return hmacSigningKey(jwtKeyBootstrap.getOrCreateSigningKey());
    }

    @Bean
    @Profile("!cloud")
    public SecretKey localJwtSigningKey(@Value("${app.jwt.signing-key}") String signingKey) {
        return hmacSigningKey(signingKey);
    }

    private SecretKey hmacSigningKey(String base64SigningKey) {
        byte[] decodedKey = Base64.getDecoder().decode(base64SigningKey);
        if (decodedKey.length < 32) {
            throw new IllegalStateException("JWT signing key must decode to at least 32 bytes");
        }
        return Keys.hmacShaKeyFor(decodedKey);
    }
}
