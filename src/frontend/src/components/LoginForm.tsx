import { FormEvent, useState } from 'react';
import { login } from '../api/auth';
import { AUTH_TOKEN_STORAGE_KEY } from '../api/client';

export default function LoginForm() {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setIsSubmitting(true);
    setMessage(null);
    setError(null);

    try {
      const response = await login({ username, password });
      window.localStorage.setItem(AUTH_TOKEN_STORAGE_KEY, response.token);
      setMessage('Signed in successfully.');
      setPassword('');
    } catch {
      setError('Sign in failed. Check the username and password.');
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <section aria-labelledby="login-heading" className="page-section narrow">
      <div className="section-heading">
        <p className="eyebrow">Admin</p>
        <h1 id="login-heading">Sign in</h1>
      </div>

      <form className="form-card" onSubmit={handleSubmit}>
        <label htmlFor="username">Username</label>
        <input
          autoComplete="username"
          id="username"
          name="username"
          onChange={(event) => setUsername(event.target.value)}
          required
          type="text"
          value={username}
        />

        <label htmlFor="password">Password</label>
        <input
          autoComplete="current-password"
          id="password"
          name="password"
          onChange={(event) => setPassword(event.target.value)}
          required
          type="password"
          value={password}
        />

        <button disabled={isSubmitting} type="submit">
          {isSubmitting ? 'Signing in...' : 'Sign in'}
        </button>
      </form>

      {message ? <p role="status">{message}</p> : null}
      {error ? <p role="alert">{error}</p> : null}
    </section>
  );
}
