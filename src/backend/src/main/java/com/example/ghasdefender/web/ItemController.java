package com.example.ghasdefender.web;

import com.example.ghasdefender.domain.Item;
import com.example.ghasdefender.repo.ItemRepository;
import com.example.ghasdefender.web.dto.ItemRequest;
import jakarta.persistence.EntityManager;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/items")
public class ItemController {

    private final ItemRepository itemRepository;
    private final EntityManager entityManager;

    public ItemController(ItemRepository itemRepository, EntityManager entityManager) {
        this.itemRepository = itemRepository;
        this.entityManager = entityManager;
    }

    @GetMapping
    public List<Item> list() {
        return itemRepository.findAll();
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Item create(@Valid @RequestBody ItemRequest request) {
        return itemRepository.save(new Item(request.name(), request.description()));
    }

    @PutMapping("/{id}")
    public Item update(@PathVariable Long id, @Valid @RequestBody ItemRequest request) {
        Item item = itemRepository.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Item not found"));
        item.setName(request.name());
        item.setDescription(request.description());
        return itemRepository.save(item);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable Long id) {
        if (!itemRepository.existsById(id)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Item not found");
        }
        itemRepository.deleteById(id);
    }

    @GetMapping("/search")
    @SuppressWarnings("unchecked")
    public List<Item> search(@RequestParam("q") String query) {
        // SEEDED VULN #1 — see scripts/seed-vulnerabilities.md
        return entityManager
                .createNativeQuery("SELECT * FROM items WHERE name LIKE '%" + query + "%'", Item.class)
                .getResultList();
    }
}
