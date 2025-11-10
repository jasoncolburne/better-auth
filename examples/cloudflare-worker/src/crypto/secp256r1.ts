import type { ISigningKey, IVerifier } from 'better-auth-ts';
import { Base64 } from '../encoding/base64.js'; // Assume Base64 is implemented
import { Secp256r1Verifier } from './verifier.js';

export class Secp256r1 implements ISigningKey {
  private keyPair: CryptoKeyPair | null = null;

  async generate(): Promise<void> {
    this.keyPair = await crypto.subtle.generateKey(
      {
        name: 'ECDSA',
        namedCurve: 'P-256',
      },
      true,
      ['sign', 'verify']
    ) as CryptoKeyPair;
  }

  async sign(message: string): Promise<string> {
    if (!this.keyPair) {
      throw new Error('Key not generated');
    }

    const encoder = new TextEncoder();
    const data = encoder.encode(message);

    const signature = await crypto.subtle.sign(
      { name: 'ECDSA', hash: 'SHA-256' },
      this.keyPair.privateKey,
      data
    ) as ArrayBuffer;

    // Assume raw signature is 64 bytes (r + s, 32 each); prepend two 0x00
    const sigBytes = new Uint8Array(signature);
    const padded = new Uint8Array([0, 0, ...sigBytes])

    const base64 = Base64.encode(padded);
    return '0I' + base64.slice(2);

  }

  async public(): Promise<string> {
    if (!this.keyPair) {
      throw new Error('Key not generated');
    }

    const publicKeyData = await crypto.subtle.exportKey('raw', this.keyPair.publicKey) as ArrayBuffer;
    const pubBytes = new Uint8Array(publicKeyData); // 65 bytes uncompressed

    const out = new Uint8Array(33);
    out[0] = pubBytes[64] & 1 ? 0x03 : 0x02;
    out.set(pubBytes.subarray(1, 33), 1);
    return '1AAI' + Base64.encode(out);
  }

  async identity(): Promise<string> {
    return await this.public();
  }

  verifier(): IVerifier {
    return new Secp256r1Verifier();
  }

  async verify(message: string, signature: string): Promise<void> {
    const pub = await this.public();
    const verifier = this.verifier();
    await verifier.verify(message, signature, pub);
  }
}
