import { useEffect, useState } from 'react';
import { listItems } from '../api/items';
import type { Item } from '../types';

export default function ItemList() {
  const [items, setItems] = useState<Item[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let isCurrent = true;

    async function loadItems() {
      try {
        const loadedItems = await listItems();
        if (isCurrent) {
          setItems(loadedItems);
          setError(null);
        }
      } catch {
        if (isCurrent) {
          setError('Could not load items.');
        }
      } finally {
        if (isCurrent) {
          setIsLoading(false);
        }
      }
    }

    loadItems();

    return () => {
      isCurrent = false;
    };
  }, []);

  if (isLoading) {
    return <p role="status">Loading items...</p>;
  }

  if (error) {
    return <p role="alert">{error}</p>;
  }

  return (
    <section aria-labelledby="items-heading" className="page-section">
      <div className="section-heading">
        <p className="eyebrow">Inventory</p>
        <h1 id="items-heading">Items</h1>
      </div>

      {items.length === 0 ? (
        <p>No items found.</p>
      ) : (
        <div className="card-grid">
          {items.map((item) => (
            <article className="card" key={item.id}>
              <h2>{item.name}</h2>
              <p>{item.description}</p>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}
