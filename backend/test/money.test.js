import { describe, expect, test } from '@jest/globals';
import { asMoney, convertedAmount, scaled, transferFee } from '../dist/fees/money.js';
import { isPublicIp } from '../dist/webhooks/endpoint.js';

describe('Dinero con precisión decimal', () => {
  test('conserva centavos fuera del rango seguro de Number', () => {
    expect(asMoney(scaled('999999999999999999.99', 2))).toBe('999999999999999999.99');
    expect(() => asMoney(scaled('999999999999999999.99', 2) + 1n)).toThrow(RangeError);
    expect(() => asMoney(-1n)).toThrow(RangeError);
  });

  test('redondea la tasa y comisión half-up', () => {
    expect(asMoney(convertedAmount(scaled('25.00', 2), '4000.0000000000'))).toBe('100000.00');
    expect(asMoney(transferFee(scaled('25.00', 2), '1.00', '1.5000'))).toBe('1.38');
    expect(asMoney(convertedAmount(1n, '0.5000000000'))).toBe('0.01');
  });
});

test('clasifica direcciones públicas antes de enviar webhooks', () => {
  for (const host of ['127.0.0.1', '10.0.1.2', '169.254.169.254', '::1', '::ffff:127.0.0.1', 'fc00::1']) {
    expect(isPublicIp(host)).toBe(false);
  }
  expect(isPublicIp('8.8.8.8')).toBe(true);
  expect(isPublicIp('2606:4700:4700::1111')).toBe(true);
});
