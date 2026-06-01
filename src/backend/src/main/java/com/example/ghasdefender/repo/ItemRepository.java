package com.example.ghasdefender.repo;

import com.example.ghasdefender.domain.Item;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

public interface ItemRepository extends JpaRepository<Item, Long> {

    @Query("SELECT i FROM Item i WHERE i.name LIKE %?1%")
    List<Item> searchByName(String query);
}
