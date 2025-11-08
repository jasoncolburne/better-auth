import type { IServerAuthenticationNonceStore } from 'better-auth-ts';
import { Noncer } from '../../crypto/noncer.js';

export class ServerAuthenticationNonceStore implements IServerAuthenticationNonceStore {
  readonly lifetimeInSeconds: number;
  private nonces: Map<string, { identity: string; expires: Date }> = new Map();
  private noncer = new Noncer();

  constructor(lifetimeInSeconds: number = 60) {
    this.lifetimeInSeconds = lifetimeInSeconds;
  }

  async generate(identity: string): Promise<string> {
    const nonce = await this.noncer.generate128();
    const expires = new Date(Date.now() + this.lifetimeInSeconds * 1000);
    this.nonces.set(nonce, { identity, expires });
    return nonce;
  }

  async validate(nonce: string): Promise<string> {
    const entry = this.nonces.get(nonce);
    if (!entry) {
      throw new Error('Nonce not found');
    }
    if (new Date() > entry.expires) {
      this.nonces.delete(nonce);
      throw new Error('Nonce expired');
    }
    this.nonces.delete(nonce);
    return entry.identity;
  }
}
