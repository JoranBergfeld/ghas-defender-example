import { apiClient } from './client';
import type { Item } from '../types';

export type ItemInput = Omit<Item, 'id'>;

export async function listItems(): Promise<Item[]> {
  const response = await apiClient.get<Item[]>('/api/items');
  return response.data;
}

export async function searchItems(query: string): Promise<Item[]> {
  const response = await apiClient.get<Item[]>('/api/items/search', { params: { q: query } });
  return response.data;
}

export async function createItem(item: ItemInput): Promise<Item> {
  const response = await apiClient.post<Item>('/api/items', item);
  return response.data;
}

export async function updateItem(id: number, item: ItemInput): Promise<Item> {
  const response = await apiClient.put<Item>(`/api/items/${id}`, item);
  return response.data;
}

export async function deleteItem(id: number): Promise<void> {
  await apiClient.delete(`/api/items/${id}`);
}
