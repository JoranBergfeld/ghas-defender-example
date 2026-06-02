package com.example.ghasdefender.security;

import com.azure.core.exception.ResourceNotFoundException;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.security.keyvault.secrets.SecretClient;
import com.azure.security.keyvault.secrets.SecretClientBuilder;
import com.azure.security.keyvault.secrets.models.KeyVaultSecret;
import java.security.SecureRandom;
import java.util.Base64;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

@Component
@Profile("cloud")
public class JwtKeyBootstrap {

    public static final String SECRET_NAME = "jwt-signing-key";
    private static final int SIGNING_KEY_BYTES = 32;

    private final SecretClient secretClient;
    private final SecureRandom secureRandom;

    public JwtKeyBootstrap(@Value("${AZURE_KEY_VAULT_URI:}") String keyVaultUri) {
        this(createSecretClient(keyVaultUri), new SecureRandom());
    }

    JwtKeyBootstrap(SecretClient secretClient, SecureRandom secureRandom) {
        this.secretClient = secretClient;
        this.secureRandom = secureRandom;
    }

    public String getOrCreateSigningKey() {
        try {
            return secretClient.getSecret(SECRET_NAME).getValue();
        } catch (ResourceNotFoundException ex) {
            String generatedKey = generateSigningKey();
            secretClient.setSecret(new KeyVaultSecret(SECRET_NAME, generatedKey));
            return generatedKey;
        }
    }

    private String generateSigningKey() {
        byte[] key = new byte[SIGNING_KEY_BYTES];
        secureRandom.nextBytes(key);
        return Base64.getEncoder().encodeToString(key);
    }

    private static SecretClient createSecretClient(String keyVaultUri) {
        if (!StringUtils.hasText(keyVaultUri)) {
            throw new IllegalStateException("AZURE_KEY_VAULT_URI must be set when the cloud profile is active");
        }

        return new SecretClientBuilder()
                .vaultUrl(keyVaultUri)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();
    }
}
