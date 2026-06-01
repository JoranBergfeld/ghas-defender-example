package com.example.ghasdefender.web;

import static org.hamcrest.Matchers.hasSize;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.ghasdefender.domain.Item;
import com.example.ghasdefender.repo.ItemRepository;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(ItemController.class)
@AutoConfigureMockMvc(addFilters = false)
class ItemControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private ItemRepository itemRepository;

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
    void createItemPersistsAndReturnsItem() throws Exception {
        when(itemRepository.save(any(Item.class))).thenAnswer(invocation -> invocation.getArgument(0));

        mockMvc.perform(post("/api/items")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Created Item\",\"description\":\"Created through the API\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.name").value("Created Item"))
                .andExpect(jsonPath("$.description").value("Created through the API"));
    }

    @Test
    void searchItemsReturnsRepositoryMatches() throws Exception {
        when(itemRepository.searchByName("Alpha")).thenReturn(List.of(
                new Item("Demo Item Alpha", "First clean demo item")
        ));

        mockMvc.perform(get("/api/items/search").param("q", "Alpha"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].name").value("Demo Item Alpha"));
    }

    @Test
    void searchItemsPassesInjectionTextAsPlainQueryParameter() throws Exception {
        String injection = "' OR '1'='1";
        when(itemRepository.searchByName(injection)).thenReturn(List.of());

        mockMvc.perform(get("/api/items/search").param("q", injection))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));

        verify(itemRepository).searchByName(injection);
    }
}
