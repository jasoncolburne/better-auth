import { IVerificationKey, IVerificationKeyStore, IVerifier } from 'better-auth-ts'
import { Redis } from 'ioredis'
import { Secp256r1Verifier, VerificationKey } from '../crypto/secp256r1.js'
import { KeyVerifier } from './key-verifier.js'
import { getSubJson } from './utils.js'

const HSM_IDENTITY = 'BETTER_AUTH_HSM_IDENTITY_PLACEHOLDER'

interface KeySigningBody {
  payload: {
    purpose: string
    publicKey: string
    expiration: string
  }
  hsm: {
    identity: string
    generationId: string
  }
}

interface KeySigningResponse {
  body: KeySigningBody
  signature: string
}

export class VerificationKeyStore implements IVerificationKeyStore {
  private readonly client: Redis
  private readonly verifier: KeyVerifier

  constructor(
    redisClient: Redis,
    redisHost: string,
    redisDbHsmKeys: number,
    serverLifetimeHours: number,
    accessLifetimeMinutes: number
  ) {
    this.client = redisClient
    this.verifier = new KeyVerifier(redisHost, redisDbHsmKeys, serverLifetimeHours, accessLifetimeMinutes)
  }

  async get(identity: string): Promise<IVerificationKey> {
    const value = await this.client.get(identity)

    if (value === null) {
      throw 'not found'
    }

    // Parse the response structure
    const responseObj = JSON.parse(value) as KeySigningResponse
    const bodyJson = getSubJson(value, 'body')

    // Verify HSM signature using KeyVerifier
    await this.verifier.verify(
      responseObj.signature,
      responseObj.body.hsm.identity,
      responseObj.body.hsm.generationId,
      bodyJson
    )

    // Validate purpose
    if (responseObj.body.payload.purpose !== 'access') {
      throw new Error('invalid purpose: expected access')
    }

    // Check expiration
    const expirationDate = new Date(responseObj.body.payload.expiration)
    if (expirationDate <= new Date()) {
      throw new Error('key expired')
    }

    // Return the public key from the payload
    const secp256r1Verifier = new Secp256r1Verifier()
    const verificationKey = new VerificationKey(
      responseObj.body.payload.publicKey,
      secp256r1Verifier
    )

    return verificationKey
  }

  async close(): Promise<void> {
    await this.verifier.close()
  }
}
