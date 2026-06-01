package com.example.ghasdefender.repo;

import com.example.ghasdefender.domain.Item;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ItemRepository extends JpaRepository<Item, Long> {
}
