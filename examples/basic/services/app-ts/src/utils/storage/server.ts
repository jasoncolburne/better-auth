import { IServerTimeLockStore } from 'better-auth-ts'

export class ServerTimeLockStore implements IServerTimeLockStore {
  private readonly nonces: Map<string, Date>

  constructor(public readonly lifetimeInSeconds: number) {
    this.nonces = new Map<string, Date>()
  }

  async reserve(value: string): Promise<void> {
    const validAt = this.nonces.get(value)

    if (typeof validAt !== 'undefined') {
      const now = new Date()
      if (now < validAt) {
        throw 'value reserved too recently'
      }
    }

    const newValidAt = new Date()
    newValidAt.setSeconds(newValidAt.getSeconds() + this.lifetimeInSeconds)

    this.nonces.set(value, newValidAt)
  }
}
