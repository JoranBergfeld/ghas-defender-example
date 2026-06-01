package com.example.ghasdefender.repo;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

@DataJpaTest
@ActiveProfiles("local")
class ItemRepositoryTest {

    @Autowired
    private ItemRepository itemRepository;

    @Test
    void flywaySeedsThreeDemoItems() {
        assertThat(itemRepository.findAll())
                .extracting("name")
                .containsExactlyInAnyOrder("Demo Item Alpha", "Demo Item Beta", "Demo Item Gamma");
    }

    @Test
    void searchByNameFindsMatchingItems() {
        assertThat(itemRepository.searchByName("Alpha"))
                .extracting("name")
                .containsExactly("Demo Item Alpha");
    }

    @Test
    void searchByNameTreatsInjectionTextAsData() {
        assertThat(itemRepository.searchByName("' OR '1'='1"))
                .isEmpty();
    }
}
