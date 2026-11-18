import type { Request } from 'express';

export type Role = 'ADMIN' | 'CLIENT';
export interface Identity {
  tenant_id: string;
  user_id: string;
  role: Role;
}

export interface Trace {
  correlationId: string;
  ip: string;
}

export interface BankRequest extends Request {
  identity?: Identity;
  trace: Trace;
  validatedQuery?: unknown;
}

export const userFields = 'id,tenant_id,first_name,last_name,email,role,active,created_at';

export interface User {
  id: string;
  tenant_id: string;
  first_name: string;
  last_name: string;
  email: string;
  role: Role;
  active: boolean;
  created_at: string;
}

export interface Account {
  tenant_id: string;
  id: string;
  number: string;
  owner_id: string;
  currency: string;
  balance: string;
  status: 'ACTIVE' | 'INACTIVE' | 'BLOCKED';
  created_at: string;
}
