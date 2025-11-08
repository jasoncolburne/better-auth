import type { INoncer } from 'better-auth-ts';
import { Base64 } from '../encoding/base64.js';

export class Noncer implements INoncer {
  async generate128(): Promise<string> {
    const entropy = crypto.getRandomValues(new Uint8Array(16));
    const padded = new Uint8Array(18);
    padded[0] = 0x00;
    padded[1] = 0x00;
    padded.set(entropy, 2);
    const base64 = Base64.encode(padded);
    return '0A' + base64.slice(2);
  }
}
