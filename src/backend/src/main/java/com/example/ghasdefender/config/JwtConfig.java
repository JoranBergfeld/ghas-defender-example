package com.example.ghasdefender.config;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import java.nio.charset.StandardCharsets;
import javax.crypto.SecretKey;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.util.StringUtils;

@Configuration
public class JwtConfig {

    private static final Logger LOGGER = LoggerFactory.getLogger(JwtConfig.class);
    private static final int MINIMUM_HMAC_KEY_BYTES = 32;

    @Bean
    public SecretKey jwtSigningKey(@Value("${app.security.jwt.signing-key:}") String configuredKey) {
        if (StringUtils.hasText(configuredKey)) {
            byte[] keyBytes = decodeConfiguredKey(configuredKey);
            if (keyBytes.length < MINIMUM_HMAC_KEY_BYTES) {
                throw new IllegalStateException("JWT_SIGNING_KEY must be at least 256 bits");
            }
            return Keys.hmacShaKeyFor(keyBytes);
        }

        LOGGER.warn("JWT_SIGNING_KEY is not set; generated tokens will be invalid after application restart");
        return Jwts.SIG.HS256.key().build();
    }

    private byte[] decodeConfiguredKey(String configuredKey) {
        try {
            return Decoders.BASE64.decode(configuredKey);
        } catch (IllegalArgumentException ex) {
            return configuredKey.getBytes(StandardCharsets.UTF_8);
        }
    }
}
