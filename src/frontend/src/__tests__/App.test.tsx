import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';

vi.mock('../components/ItemList', () => ({
  default: () => <h1>Items route</h1>,
}));

vi.mock('../components/SearchResults', () => ({
  default: () => <h1>Search route</h1>,
}));

vi.mock('../components/LoginForm', () => ({
  default: () => <h1>Login route</h1>,
}));

import { AppRoutes } from '../App';

describe('AppRoutes', () => {
  it('renders the item list route at root', () => {
    render(
      <MemoryRouter initialEntries={['/']}>
        <AppRoutes />
      </MemoryRouter>,
    );

    expect(screen.getByRole('heading', { name: 'Items route' })).toBeInTheDocument();
  });

  it('renders the search route', () => {
    render(
      <MemoryRouter initialEntries={['/search?q=demo']}>
        <AppRoutes />
      </MemoryRouter>,
    );

    expect(screen.getByRole('heading', { name: 'Search route' })).toBeInTheDocument();
  });

  it('renders the login route', () => {
    render(
      <MemoryRouter initialEntries={['/login']}>
        <AppRoutes />
      </MemoryRouter>,
    );

    expect(screen.getByRole('heading', { name: 'Login route' })).toBeInTheDocument();
  });
});
