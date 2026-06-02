package com.example.ghasdefender.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.azure.core.exception.ResourceNotFoundException;
import com.azure.security.keyvault.secrets.SecretClient;
import com.azure.security.keyvault.secrets.models.KeyVaultSecret;
import java.security.SecureRandom;
import java.util.Base64;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

class JwtKeyBootstrapTest {

    @Test
    void returnsExistingSecretWithoutWritingANewVersion() {
        SecretClient secretClient = org.mockito.Mockito.mock(SecretClient.class);
        String existingKey = Base64.getEncoder().encodeToString("0123456789abcdef0123456789abcdef".getBytes());
        when(secretClient.getSecret(JwtKeyBootstrap.SECRET_NAME))
                .thenReturn(new KeyVaultSecret(JwtKeyBootstrap.SECRET_NAME, existingKey));

        JwtKeyBootstrap bootstrap = new JwtKeyBootstrap(secretClient, new SecureRandom(new byte[] {1, 2, 3, 4}));

        String actualKey = bootstrap.getOrCreateSigningKey();

        assertThat(actualKey).isEqualTo(existingKey);
        verify(secretClient, never()).setSecret(any(KeyVaultSecret.class));
    }

    @Test
    void createsSecretWhenItIsAbsent() {
        SecretClient secretClient = org.mockito.Mockito.mock(SecretClient.class);
        when(secretClient.getSecret(JwtKeyBootstrap.SECRET_NAME))
                .thenThrow(new ResourceNotFoundException("missing secret", null));
        when(secretClient.setSecret(any(KeyVaultSecret.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        JwtKeyBootstrap bootstrap = new JwtKeyBootstrap(secretClient, new SecureRandom(new byte[] {5, 6, 7, 8}));

        String generatedKey = bootstrap.getOrCreateSigningKey();

        byte[] decodedKey = Base64.getDecoder().decode(generatedKey);
        assertThat(decodedKey).hasSize(32);

        ArgumentCaptor<KeyVaultSecret> captor = ArgumentCaptor.forClass(KeyVaultSecret.class);
        verify(secretClient).setSecret(captor.capture());
        assertThat(captor.getValue().getName()).isEqualTo(JwtKeyBootstrap.SECRET_NAME);
        assertThat(captor.getValue().getValue()).isEqualTo(generatedKey);
    }
}
