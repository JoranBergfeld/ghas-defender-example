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

    static from(headers?: unknown) {
      const instance = new AxiosHeaders();
      if (headers && typeof headers === 'object') {
        Object.entries(headers as Record<string, string>).forEach(([key, value]) => {
          instance.set(key, value);
        });
      }
      return instance;
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

import { API_BASE_URL, AUTH_TOKEN_STORAGE_KEY, apiClient } from '../../api/client';

describe('api client', () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it('uses the configured API base URL', () => {
    expect(axiosMocks.create).toHaveBeenCalledWith({
      baseURL: API_BASE_URL,
      headers: { 'Content-Type': 'application/json' },
    });
  });

  it('adds Authorization header when token is present', () => {
    window.localStorage.setItem(AUTH_TOKEN_STORAGE_KEY, 'test-token');
    const interceptor = axiosMocks.instance.interceptors.request.use.mock.calls[0][0] as (
      config: { headers?: Record<string, string> }
    ) => { headers?: Record<string, string> };

    const result = interceptor({ headers: {} });

    expect(result.headers?.Authorization).toBe('Bearer test-token');
  });

  it('exports the axios instance for typed API modules', () => {
    expect(apiClient).toBe(axiosMocks.instance);
  });
});
