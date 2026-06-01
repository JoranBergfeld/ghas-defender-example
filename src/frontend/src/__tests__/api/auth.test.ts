import { beforeEach, describe, expect, it, vi } from 'vitest';

const apiClientMock = vi.hoisted(() => ({
  post: vi.fn(),
}));

vi.mock('../../api/client', () => ({
  apiClient: apiClientMock,
}));

import { login } from '../../api/auth';

describe('auth api', () => {
  beforeEach(() => {
    apiClientMock.post.mockReset();
  });

  it('posts credentials to login endpoint', async () => {
    apiClientMock.post.mockResolvedValue({ data: { token: 'jwt-token' } });

    await expect(login({ username: 'alice', password: 'correct-horse-battery-staple' })).resolves.toEqual({
      token: 'jwt-token',
    });

    expect(apiClientMock.post).toHaveBeenCalledWith('/api/auth/login', {
      username: 'alice',
      password: 'correct-horse-battery-staple',
    });
  });
});
