package com.example.ghasdefender.web;

import com.example.ghasdefender.domain.Item;
import com.example.ghasdefender.repo.ItemRepository;
import com.example.ghasdefender.web.dto.ItemRequest;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/items")
public class ItemController {

    private final ItemRepository itemRepository;

    public ItemController(ItemRepository itemRepository) {
        this.itemRepository = itemRepository;
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

    @GetMapping("/search")
    public List<Item> search(@RequestParam("q") String query) {
        return itemRepository.searchByName(query);
    }
}
