import type { IVerificationKeyStore, IVerificationKey, ISigningKey } from 'better-auth-ts';

export class VerificationKeyStore implements IVerificationKeyStore {
  private keys: Map<string, IVerificationKey> = new Map();

  async get(identity: string): Promise<IVerificationKey> {
    const key = this.keys.get(identity);
    if (!key) {
      throw new Error(`Verification key not found for identity: ${identity}`);
    }
    return key;
  }

  async set(identity: string, value: IVerificationKey): Promise<void> {
    this.keys.set(identity, value);
  }

  async delete(identity: string): Promise<void> {
    this.keys.delete(identity);
  }

  async has(identity: string): Promise<boolean> {
    return this.keys.has(identity);
  }

  async add(identity: string, signingKey: ISigningKey): Promise<void> {
    await this.set(identity, signingKey);
  }
}
