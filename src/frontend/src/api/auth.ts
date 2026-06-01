import { apiClient } from './client';
import type { AuthResponse, User } from '../types';

export async function login(credentials: User): Promise<AuthResponse> {
  const response = await apiClient.post<AuthResponse>('/api/auth/login', credentials);
  return response.data;
}
