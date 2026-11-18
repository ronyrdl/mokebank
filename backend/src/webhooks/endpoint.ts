import { lookup } from 'node:dns/promises';
import { addAbortListener } from 'node:events';
import { BlockList, isIP } from 'node:net';
import { request } from 'node:https';
import { BankError } from '../common/errors.js';

const ipv4 = new BlockList();
for (const [address, prefix] of [
  ['0.0.0.0', 8], ['10.0.0.0', 8], ['100.64.0.0', 10], ['127.0.0.0', 8],
  ['169.254.0.0', 16], ['172.16.0.0', 12], ['192.0.0.0', 24], ['192.0.2.0', 24],
  ['192.88.99.0', 24], ['192.168.0.0', 16], ['198.18.0.0', 15], ['198.51.100.0', 24],
  ['203.0.113.0', 24], ['224.0.0.0', 3],
] as const) ipv4.addSubnet(address, prefix);

const globalV6 = new BlockList();
globalV6.addSubnet('2000::', 3, 'ipv6');
const specialV6 = new BlockList();
for (const [address, prefix] of [['2001::', 23], ['2001:db8::', 32], ['2002::', 16], ['3fff::', 20]] as const) {
  specialV6.addSubnet(address, prefix, 'ipv6');
}

export function isPublicIp(address: string): boolean {
  const family = isIP(address);
  if (family === 4) return !ipv4.check(address, 'ipv4');
  return family === 6 && globalV6.check(address, 'ipv6') && !specialV6.check(address, 'ipv6');
}

export async function resolveEndpoint(value: string, signal = AbortSignal.timeout(5000)) {
  const invalid = () => new BankError(400, 'INVALID_WEBHOOK_URL', 'El webhook requiere un destino HTTPS público');
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw invalid();
  }
  const host = url.hostname.replace(/^\[|\]$/g, '');
  if (url.protocol !== 'https:' || url.port || url.username || url.password || url.hash) throw invalid();
  let addresses;
  try {
    const family = isIP(host);
    if (family) addresses = [{ address: host, family }];
    else {
      signal.throwIfAborted();
      let abort: ReturnType<typeof addAbortListener> | undefined;
      try {
        const timeout = new Promise<never>((_, reject) => {
          abort = addAbortListener(signal, () => reject(signal.reason));
        });
        addresses = await Promise.race([lookup(host, { all: true }), timeout]);
      } finally {
        abort?.[Symbol.dispose]();
      }
    }
  } catch {
    throw invalid();
  }
  if (!addresses.length || addresses.some(entry => !isPublicIp(entry.address))) throw invalid();
  return { url, target: addresses[0] };
}

export async function sendWebhook(value: string, body: string, headers: Record<string, string>, timeout: number) {
  const signal = AbortSignal.timeout(timeout);
  const { url, target } = await resolveEndpoint(value, signal);
  signal.throwIfAborted();
  return new Promise<number>((resolve, reject) => {
    const req = request(url, {
      method: 'POST',
      agent: false,
      family: target.family,
      signal,
      lookup: (_hostname, _options, callback) => callback(null, target.address, target.family),
      headers: { ...headers, 'content-type': 'application/json', 'content-length': String(Buffer.byteLength(body)) },
    }, res => {
      resolve(res.statusCode ?? 502);
      res.destroy();
    });
    req.on('error', reject);
    req.end(body);
  });
}
