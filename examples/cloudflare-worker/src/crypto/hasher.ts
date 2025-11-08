import type { IHasher } from 'better-auth-ts';
import { Base64 } from '../encoding/base64.js';
import { blake3 } from '@noble/hashes/blake3.js';

export class Hasher implements IHasher {
  async sum(message: string): Promise<string> {
    const encoder = new TextEncoder();
    const bytes = encoder.encode(message);
    const hash = blake3(bytes); // 32-byte Uint8Array
    const padded = new Uint8Array(33);
    padded[0] = 0x00;
    padded.set(hash, 1);
    const base64 = Base64.encode(padded);
    return 'E' + base64.substring(1);
  }
}
