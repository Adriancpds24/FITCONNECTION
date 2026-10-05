import crypto from 'crypto';

function timeCounter(timeStepSec: number): bigint {
  return BigInt(Math.floor(Date.now() / 1000 / timeStepSec));
}

function hotpToken(secret: Buffer, counter: bigint): string {
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64BE(counter);
  const hmac = crypto.createHmac('sha1', secret).update(buf).digest();
  const offset = hmac[hmac.length - 1]! & 0xf;
  const code =
    ((hmac[offset]! & 0x7f) << 24) |
    ((hmac[offset + 1]! & 0xff) << 16) |
    ((hmac[offset + 2]! & 0xff) << 8) |
    (hmac[offset + 3]! & 0xff);
  return String(code % 1_000_000).padStart(6, '0');
}

export function generateTotpSecretBytes(length = 20): Buffer {
  return crypto.randomBytes(length);
}

/** RFC 4648 base32 (no padding), for otpauth:// URLs. */
export function bufferToBase32(buf: Buffer): string {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  let bits = 0;
  let value = 0;
  let output = '';
  for (let i = 0; i < buf.length; i += 1) {
    value = (value << 8) | buf[i]!;
    bits += 8;
    while (bits >= 5) {
      output += alphabet[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) {
    output += alphabet[(value << (5 - bits)) & 31];
  }
  return output;
}

export function verifyTotpCode(secretBase64: string, code: string, window = 1): boolean {
  const digits = String(code ?? '').replace(/\D/g, '');
  if (digits.length !== 6) return false;
  let secret: Buffer;
  try {
    secret = Buffer.from(secretBase64, 'base64');
  } catch {
    return false;
  }
  if (secret.length < 10) return false;

  const counter = timeCounter(30);
  for (let w = -window; w <= window; w += 1) {
    const c = counter + BigInt(w);
    if (hotpToken(secret, c) === digits) return true;
  }
  return false;
}

export function totpCodeForNow(secretBase64: string): string {
  const secret = Buffer.from(secretBase64, 'base64');
  return hotpToken(secret, timeCounter(30));
}
