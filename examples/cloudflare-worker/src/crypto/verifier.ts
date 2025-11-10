import type { IVerifier } from 'better-auth-ts';
import { Base64 } from '../encoding/base64.js';

export class Secp256r1Verifier implements IVerifier {
  async verify(message: string, signature: string, publicKey: string): Promise<void> {
    const params: EcKeyImportParams = {
      name: 'ECDSA',
      namedCurve: 'P-256',
    };

    const publicKeyBytes = Base64.decode(publicKey).subarray(3);
    const publicCryptoKey = await crypto.subtle.importKey(
      'raw',
      publicKeyBytes,
      params,
      true,
      ['verify']
    );

    const signatureBytes = Base64.decode(signature).subarray(2);

    const encoder = new TextEncoder();
    const messageBytes = encoder.encode(message);

    const verifyParams: EcdsaParams = {
      name: 'ECDSA',
      hash: 'SHA-256',
    };

    const ok = await crypto.subtle.verify(verifyParams, publicCryptoKey, signatureBytes, messageBytes);
    if (!ok) {
      throw new Error('Signature verification failed');
    }
  }
}
