import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { searchItems } from '../api/items';
import type { Item } from '../types';

export default function SearchResults() {
  const [searchParams] = useSearchParams();
  const query = searchParams.get('q') ?? '';
  const [items, setItems] = useState<Item[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let isCurrent = true;
    const trimmedQuery = query.trim();

    if (!trimmedQuery) {
      setItems([]);
      setError(null);
      setIsLoading(false);
      return () => {
        isCurrent = false;
      };
    }

    async function runSearch() {
      setIsLoading(true);
      try {
        const results = await searchItems(trimmedQuery);
        if (isCurrent) {
          setItems(results);
          setError(null);
        }
      } catch {
        if (isCurrent) {
          setError('Could not load search results.');
        }
      } finally {
        if (isCurrent) {
          setIsLoading(false);
        }
      }
    }

    runSearch();

    return () => {
      isCurrent = false;
    };
  }, [query]);

  if (!query.trim()) {
    return (
      <section aria-labelledby="search-heading" className="page-section">
        <div className="section-heading">
          <p className="eyebrow">Search</p>
          <h1 id="search-heading">Search results</h1>
        </div>
        <p>Enter a search term in the URL with ?q=term.</p>
      </section>
    );
  }

  return (
    <section aria-labelledby="search-heading" className="page-section">
      <div className="section-heading">
        <p className="eyebrow">Search</p>
        <h1 id="search-heading">Search results</h1>
        <p>
          Showing matches for <strong>{query}</strong>
        </p>
      </div>

      {isLoading ? <p role="status">Loading search results...</p> : null}
      {error ? <p role="alert">{error}</p> : null}
      {!isLoading && !error && items.length === 0 ? <p>No results found.</p> : null}

      {items.length > 0 ? (
        <div className="card-grid">
          {items.map((item) => (
            <article className="card" key={item.id}>
              <h2>{item.name}</h2>
              {/* SEEDED VULN #2 — see scripts/seed-vulnerabilities.md */}
              <p dangerouslySetInnerHTML={{ __html: item.description }} />
            </article>
          ))}
        </div>
      ) : null}
    </section>
  );
}
