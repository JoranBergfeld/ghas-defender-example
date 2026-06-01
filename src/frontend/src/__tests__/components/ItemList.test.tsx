import { render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

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

import ItemList from '../../components/ItemList';

describe('ItemList', () => {
  beforeEach(() => {
    axiosMocks.instance.get.mockReset();
  });

  it('renders items returned by the backend', async () => {
    axiosMocks.instance.get.mockResolvedValue({
      data: [
        { id: 1, name: 'Demo item', description: 'First backend item' },
        { id: 2, name: 'Second item', description: 'Another backend item' },
      ],
    });

    render(<ItemList />);

    expect(screen.getByRole('status')).toHaveTextContent('Loading items...');
    expect(await screen.findByText('Demo item')).toBeInTheDocument();
    expect(screen.getByText('First backend item')).toBeInTheDocument();
    expect(screen.getByText('Second item')).toBeInTheDocument();
    expect(axiosMocks.instance.get).toHaveBeenCalledWith('/api/items');
  });

  it('renders an empty state when no items are returned', async () => {
    axiosMocks.instance.get.mockResolvedValue({ data: [] });

    render(<ItemList />);

    expect(await screen.findByText('No items found.')).toBeInTheDocument();
  });
});
