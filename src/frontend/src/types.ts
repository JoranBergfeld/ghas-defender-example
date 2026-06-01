export interface Item {
  id: number;
  name: string;
  description: string;
}

export interface User {
  username: string;
  password: string;
}

export interface AuthResponse {
  token: string;
}
