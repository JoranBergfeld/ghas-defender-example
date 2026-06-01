import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { AUTH_TOKEN_STORAGE_KEY } from '../../api/client';

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

import LoginForm from '../../components/LoginForm';

describe('LoginForm', () => {
  beforeEach(() => {
    window.localStorage.clear();
    axiosMocks.instance.post.mockReset();
  });

  it('stores the auth token after successful login', async () => {
    axiosMocks.instance.post.mockResolvedValue({ data: { token: 'jwt-token' } });
    const user = userEvent.setup();

    render(<LoginForm />);

    await user.type(screen.getByLabelText(/username/i), 'alice');
    await user.type(screen.getByLabelText(/password/i), 'correct-horse-battery-staple');
    await user.click(screen.getByRole('button', { name: /sign in/i }));

    await waitFor(() => {
      expect(window.localStorage.getItem(AUTH_TOKEN_STORAGE_KEY)).toBe('jwt-token');
    });

    expect(axiosMocks.instance.post).toHaveBeenCalledWith('/api/auth/login', {
      username: 'alice',
      password: 'correct-horse-battery-staple',
    });
    expect(screen.getByRole('status')).toHaveTextContent('Signed in successfully.');
  });
});
