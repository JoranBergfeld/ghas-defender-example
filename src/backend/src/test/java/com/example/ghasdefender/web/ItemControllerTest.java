package com.example.ghasdefender.web;

import static org.hamcrest.Matchers.hasSize;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.ghasdefender.config.CorsConfig;
import com.example.ghasdefender.config.PasswordEncoderConfig;
import com.example.ghasdefender.config.SecurityConfig;
import com.example.ghasdefender.domain.Item;
import com.example.ghasdefender.repo.ItemRepository;
import com.example.ghasdefender.security.JwtAuthenticationFilter;
import com.example.ghasdefender.security.JwtService;
import jakarta.persistence.EntityManager;
import jakarta.persistence.Query;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(ItemController.class)
@Import({SecurityConfig.class, PasswordEncoderConfig.class, CorsConfig.class, JwtAuthenticationFilter.class})
class ItemControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private ItemRepository itemRepository;

    @MockBean
    private JwtService jwtService;

    // SEEDED VULN #1 — see scripts/seed-vulnerabilities.md
    @MockBean
    private EntityManager entityManager;

    @Test
    void corsPreflightAllowsLocalFrontendOrigin() throws Exception {
        mockMvc.perform(options("/api/items")
                        .header(HttpHeaders.ORIGIN, "http://localhost:5173")
                        .header(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "GET"))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "http://localhost:5173"));
    }

    @Test
    void listItemsReturnsAllItems() throws Exception {
        when(itemRepository.findAll()).thenReturn(List.of(
                new Item("Demo Item Alpha", "First clean demo item"),
                new Item("Demo Item Beta", "Second clean demo item")
        ));

        mockMvc.perform(get("/api/items"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(2)))
                .andExpect(jsonPath("$[0].name").value("Demo Item Alpha"))
                .andExpect(jsonPath("$[1].name").value("Demo Item Beta"));
    }

    @Test
    void createItemRequiresAuthentication() throws Exception {
        mockMvc.perform(post("/api/items")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Created Item\",\"description\":\"Created through the API\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void createItemPersistsAndReturnsItemForAuthenticatedUser() throws Exception {
        when(itemRepository.save(any(Item.class))).thenAnswer(invocation -> invocation.getArgument(0));

        mockMvc.perform(post("/api/items")
                        .with(user("demo"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Created Item\",\"description\":\"Created through the API\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.name").value("Created Item"))
                .andExpect(jsonPath("$.description").value("Created through the API"));
    }

    @Test
    void searchItemsReturnsRepositoryMatches() throws Exception {
        // SEEDED VULN #1 — controller now uses native query, not the safe repository method
        Query nativeQuery = org.mockito.Mockito.mock(Query.class);
        when(entityManager.createNativeQuery(any(String.class), org.mockito.ArgumentMatchers.eq(Item.class)))
                .thenReturn(nativeQuery);
        when(nativeQuery.getResultList()).thenReturn(List.of(
                new Item("Demo Item Alpha", "First clean demo item")
        ));

        mockMvc.perform(get("/api/items/search").param("q", "Alpha"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].name").value("Demo Item Alpha"));
    }

    @Test
    void searchItemsPassesInjectionTextAsPlainQueryParameter() throws Exception {
        // SEEDED VULN #1 — assert the native query string concatenates user input verbatim
        String injection = "' OR '1'='1";
        Query nativeQuery = org.mockito.Mockito.mock(Query.class);
        when(entityManager.createNativeQuery(
                org.mockito.ArgumentMatchers.contains(injection),
                org.mockito.ArgumentMatchers.eq(Item.class)))
                .thenReturn(nativeQuery);
        when(nativeQuery.getResultList()).thenReturn(List.of());

        mockMvc.perform(get("/api/items/search").param("q", injection))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));

        verify(entityManager).createNativeQuery(
                org.mockito.ArgumentMatchers.contains(injection),
                org.mockito.ArgumentMatchers.eq(Item.class));
    }

    @Test
    void updateItemRequiresAuthentication() throws Exception {
        mockMvc.perform(put("/api/items/42")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Updated Name\",\"description\":\"Updated description\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void updateItemChangesExistingItemForAuthenticatedUser() throws Exception {
        Item existing = new Item("Old Name", "Old description");
        when(itemRepository.findById(42L)).thenReturn(Optional.of(existing));
        when(itemRepository.save(any(Item.class))).thenAnswer(invocation -> invocation.getArgument(0));

        mockMvc.perform(put("/api/items/42")
                        .with(user("demo"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Updated Name\",\"description\":\"Updated description\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Updated Name"))
                .andExpect(jsonPath("$.description").value("Updated description"));
    }

    @Test
    void updateItemReturnsNotFoundForMissingItem() throws Exception {
        when(itemRepository.findById(404L)).thenReturn(Optional.empty());

        mockMvc.perform(put("/api/items/404")
                        .with(user("demo"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Updated Name\",\"description\":\"Updated description\"}"))
                .andExpect(status().isNotFound());
    }

    @Test
    void deleteItemRequiresAuthentication() throws Exception {
        mockMvc.perform(delete("/api/items/42"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void deleteItemRemovesExistingItemForAuthenticatedUser() throws Exception {
        when(itemRepository.existsById(42L)).thenReturn(true);

        mockMvc.perform(delete("/api/items/42").with(user("demo")))
                .andExpect(status().isNoContent());

        verify(itemRepository).deleteById(42L);
    }

    @Test
    void deleteItemReturnsNotFoundForMissingItem() throws Exception {
        when(itemRepository.existsById(404L)).thenReturn(false);

        mockMvc.perform(delete("/api/items/404").with(user("demo")))
                .andExpect(status().isNotFound());
    }
}
