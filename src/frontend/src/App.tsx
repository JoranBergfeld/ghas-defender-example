import type { ReactNode } from 'react';
import { BrowserRouter, Link, Route, Routes } from 'react-router-dom';
import ItemList from './components/ItemList';
import LoginForm from './components/LoginForm';
import SearchResults from './components/SearchResults';

function AppShell({ children }: { children: ReactNode }) {
  return (
    <div className="app-shell">
      <header className="site-header">
        <Link className="brand" to="/">
          GHAS Defender Demo
        </Link>
        <nav aria-label="Primary navigation">
          <Link to="/">Items</Link>
          <Link to="/search?q=demo">Search</Link>
          <Link to="/login">Login</Link>
        </nav>
      </header>
      <main>{children}</main>
    </div>
  );
}

export function AppRoutes() {
  return (
    <Routes>
      <Route element={<ItemList />} path="/" />
      <Route element={<SearchResults />} path="/search" />
      <Route element={<LoginForm />} path="/login" />
    </Routes>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <AppShell>
        <AppRoutes />
      </AppShell>
    </BrowserRouter>
  );
}
