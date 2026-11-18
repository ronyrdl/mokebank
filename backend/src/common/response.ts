import type { Trace } from './types.js';
import type { BankError } from './errors.js';

export function success(data: unknown, trace: Trace, code = 'OK') {
  return { success: true, code, message: 'Operación realizada correctamente', data,
    meta: { correlationId: trace.correlationId } };
}

export function failure(error: BankError, trace: Trace) {
  return { success: false, code: error.code, message: error.message, details: error.details,
    meta: { correlationId: trace.correlationId } };
}
