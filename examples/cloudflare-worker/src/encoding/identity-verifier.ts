import type { IIdentityVerifier } from 'better-auth-ts';
import type { IHasher } from 'better-auth-ts';
import { Hasher } from '../crypto/hasher.js';
import { InvalidIdentityError } from 'better-auth-ts';

export class IdentityVerifier implements IIdentityVerifier {
  private hasher: IHasher;

  constructor(hasher: IHasher = new Hasher()) {
    this.hasher = hasher;
  }

  async verify(identity: string, publicKey: string, rotationHash: string, extraData?: string): Promise<void> {
    const suffix = extraData || '';
    const computed = await this.hasher.sum(publicKey + rotationHash + suffix);
    if (computed !== identity) {
      const debug = `hash(${publicKey.slice(0, 8)}... + ${rotationHash.slice(0, 8)}... + ${suffix}) = ${computed.slice(0, 8)}... (expected ${identity.slice(0, 8)}...)`;
      throw new InvalidIdentityError(debug);
    }
  }
}
