import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Item } from '../../types';

const apiClientMock = vi.hoisted(() => ({
  get: vi.fn(),
  post: vi.fn(),
  put: vi.fn(),
  delete: vi.fn(),
}));

vi.mock('../../api/client', () => ({
  apiClient: apiClientMock,
}));

import { createItem, deleteItem, listItems, searchItems, updateItem } from '../../api/items';

describe('items api', () => {
  beforeEach(() => {
    apiClientMock.get.mockReset();
    apiClientMock.post.mockReset();
    apiClientMock.put.mockReset();
    apiClientMock.delete.mockReset();
  });

  it('lists items', async () => {
    const items: Item[] = [{ id: 1, name: 'Widget', description: 'Demo widget' }];
    apiClientMock.get.mockResolvedValue({ data: items });

    await expect(listItems()).resolves.toEqual(items);

    expect(apiClientMock.get).toHaveBeenCalledWith('/api/items');
  });

  it('searches items with query parameter', async () => {
    const items: Item[] = [{ id: 2, name: 'Search hit', description: 'Matched item' }];
    apiClientMock.get.mockResolvedValue({ data: items });

    await expect(searchItems('hit')).resolves.toEqual(items);

    expect(apiClientMock.get).toHaveBeenCalledWith('/api/items/search', { params: { q: 'hit' } });
  });

  it('creates items', async () => {
    const item: Item = { id: 3, name: 'New item', description: 'Created item' };
    apiClientMock.post.mockResolvedValue({ data: item });

    await expect(createItem({ name: 'New item', description: 'Created item' })).resolves.toEqual(item);

    expect(apiClientMock.post).toHaveBeenCalledWith('/api/items', {
      name: 'New item',
      description: 'Created item',
    });
  });

  it('updates items by id', async () => {
    const item: Item = { id: 4, name: 'Updated item', description: 'Updated item' };
    apiClientMock.put.mockResolvedValue({ data: item });

    await expect(updateItem(4, { name: 'Updated item', description: 'Updated item' })).resolves.toEqual(
      item,
    );

    expect(apiClientMock.put).toHaveBeenCalledWith('/api/items/4', {
      name: 'Updated item',
      description: 'Updated item',
    });
  });

  it('deletes items by id', async () => {
    apiClientMock.delete.mockResolvedValue({});

    await expect(deleteItem(5)).resolves.toBeUndefined();

    expect(apiClientMock.delete).toHaveBeenCalledWith('/api/items/5');
  });
});
