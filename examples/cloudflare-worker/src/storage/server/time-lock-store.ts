import type { IServerTimeLockStore } from 'better-auth-ts';

export class ServerTimeLockStore implements IServerTimeLockStore {
  readonly lifetimeInSeconds: number;
  private locks: Map<string, Date> = new Map();

  constructor(lifetimeInSeconds: number) {
    this.lifetimeInSeconds = lifetimeInSeconds;
  }

  async reserve(value: string): Promise<void> {
    const now = new Date();
    const entry = this.locks.get(value);
    if (entry && now < new Date(entry.getTime() + this.lifetimeInSeconds * 1000)) {
      throw new Error('Value is still alive in the store');
    }
    const unlockTime = new Date(now.getTime() + this.lifetimeInSeconds * 1000);
    this.locks.set(value, unlockTime);
  }
}
