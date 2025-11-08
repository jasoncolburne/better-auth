import type { IServerRecoveryHashStore } from 'better-auth-ts';

export class ServerRecoveryHashStore implements IServerRecoveryHashStore {
  private hashes: Map<string, string> = new Map();

  async register(identity: string, keyHash: string): Promise<void> {
    if (this.hashes.has(identity)) {
      throw new Error('Identity already registered');
    }
    this.hashes.set(identity, keyHash);
  }

  async rotate(identity: string, oldHash: string, newHash: string): Promise<void> {
    const current = this.hashes.get(identity);
    if (current !== oldHash) {
      throw new Error('Old hash does not match');
    }
    this.hashes.set(identity, newHash);
  }

  async change(identity: string, keyHash: string): Promise<void> {
    if (!this.hashes.has(identity)) {
      throw new Error('Identity not found');
    }
    this.hashes.set(identity, keyHash);
  }
}
