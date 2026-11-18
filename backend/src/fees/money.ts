const maxMinor = 10n ** 20n - 1n;

export function scaled(value: string, places: number): bigint {
  const [whole, fraction = ''] = value.split('.');
  return BigInt(whole + fraction.padEnd(places, '0'));
}

export function asMoney(minor: bigint): string {
  if (minor < 0n || minor > maxMinor) throw new RangeError('Importe fuera del rango');
  const digits = minor.toString().padStart(3, '0');
  return `${digits.slice(0, -2)}.${digits.slice(-2)}`;
}

function roundHalfUp(numerator: bigint, denominator: bigint): bigint {
  return (numerator + denominator / 2n) / denominator;
}

export function convertedAmount(minor: bigint, rate: string): bigint {
  return roundHalfUp(minor * scaled(rate, 10), 10n ** 10n);
}

export function transferFee(minor: bigint, fixed: string, percent: string): bigint {
  return scaled(fixed, 2) + roundHalfUp(minor * scaled(percent, 4), 1_000_000n);
}
