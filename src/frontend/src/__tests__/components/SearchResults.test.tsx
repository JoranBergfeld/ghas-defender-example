import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const axiosMocks = vi.hoisted(() => {
  const instance = {
    get: vi.fn(),
    post: vi.fn(),
    put: vi.fn(),
    delete: vi.fn(),
    interceptors: {
      request: {
        use: vi.fn(),
      },
    },
  };

  return {
    create: vi.fn(() => instance),
    instance,
  };
});

vi.mock('axios', () => {
  class AxiosHeaders {
    private values = new Map<string, string>();

    static from() {
      return new AxiosHeaders();
    }

    set(name: string, value: string) {
      this.values.set(name.toLowerCase(), value);
      return this;
    }

    get(name: string) {
      return this.values.get(name.toLowerCase());
    }
  }

  return {
    default: {
      create: axiosMocks.create,
    },
    AxiosHeaders,
  };
});

import SearchResults from '../../components/SearchResults';

describe('SearchResults', () => {
  beforeEach(() => {
    axiosMocks.instance.get.mockReset();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('renders returned HTML-like names as escaped text', async () => {
    const alertSpy = vi.spyOn(window, 'alert').mockImplementation(() => undefined);
    const payload = '<img src=x onerror=alert(1)>';
    axiosMocks.instance.get.mockResolvedValue({
      data: [{ id: 7, name: payload, description: 'Payload item' }],
    });

    render(
      <MemoryRouter initialEntries={[`/search?q=${encodeURIComponent('payload')}`]}>
        <SearchResults />
      </MemoryRouter>,
    );

    expect(await screen.findByText(payload)).toBeInTheDocument();
    expect(screen.getByText('Payload item')).toBeInTheDocument();
    expect(document.body.querySelector('img')).not.toBeInTheDocument();
    expect(document.body.innerHTML).toContain('&lt;img src=x onerror=alert(1)&gt;');
    expect(alertSpy).not.toHaveBeenCalled();
    expect(axiosMocks.instance.get).toHaveBeenCalledWith('/api/items/search', {
      params: { q: 'payload' },
    });
  });
});
