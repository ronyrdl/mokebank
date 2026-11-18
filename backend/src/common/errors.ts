export class BankError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly details: unknown = {},
  ) {
    super(message);
  }
}

export function notFound(message = 'Recurso no encontrado'): never {
  throw new BankError(404, 'NOT_FOUND', message);
}

export function forbidden(): never {
  throw new BankError(403, 'FORBIDDEN', 'Permisos insuficientes');
}

export function unauthorized(): never {
  throw new BankError(401, 'INVALID_CREDENTIALS', 'Credenciales inválidas o sesión vencida');
}
