import { IVerificationKey, IVerificationKeyStore, IVerifier } from 'better-auth-ts'
import { Redis } from 'ioredis'
import { Secp256r1Verifier, VerificationKey } from '../crypto/secp256r1.js'

export class VerificationKeyStore implements IVerificationKeyStore {
  private readonly client: Redis
  private readonly verifier: IVerifier

  constructor(redisClient: Redis) {
    this.client = redisClient
    this.verifier = new Secp256r1Verifier()
  }

  async get(identity: string): Promise<IVerificationKey> {
    const key = await this.client.get(identity)

    if (key === null) {
      throw 'not found'
    }

    const verificationKey = new VerificationKey(key, this.verifier)

    return verificationKey
  }
}
