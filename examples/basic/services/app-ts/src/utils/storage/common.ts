import { IVerificationKey, IVerificationKeyStore, IVerifier } from 'better-auth-ts'
import { Redis } from 'ioredis'
import { Secp256r1Verifier, VerificationKey } from '../crypto/secp256r1.js'

const HSM_PUBLIC_KEY = '1AAIAjIhd42fcH957TzvXeMbgX4AftiTT7lKmkJ7yHy3dph9'

interface HsmResponseBody {
  payload: {
    purpose: string
    publicKey: string
    expiration: string
  }
  hsmIdentity: string
}

interface HsmResponse {
  body: HsmResponseBody
  signature: string
}

export class VerificationKeyStore implements IVerificationKeyStore {
  private readonly client: Redis
  private readonly verifier: IVerifier

  constructor(redisClient: Redis) {
    this.client = redisClient
    this.verifier = new Secp256r1Verifier()
  }

  async get(identity: string): Promise<IVerificationKey> {
    const value = await this.client.get(identity)

    if (value === null) {
      throw 'not found'
    }

    // Parse as plain object to extract body substring
    const hsmResponseObj = JSON.parse(value) as any

    // Extract the raw body JSON substring from the original value string
    // Find "body": and extract until the matching closing brace
    const bodyStart = value.indexOf('"body":') + '"body":'.length
    let braceCount = 0
    let inBody = false
    let bodyEnd = -1

    for (let i = bodyStart; i < value.length; i++) {
      const char = value[i]
      if (char === '{') {
        inBody = true
        braceCount++
      } else if (char === '}') {
        braceCount--
        if (inBody && braceCount === 0) {
          bodyEnd = i + 1
          break
        }
      }
    }

    if (bodyEnd === -1) {
      throw new Error('failed to extract body from HSM response')
    }

    const bodyJson = value.substring(bodyStart, bodyEnd)
    const signature = hsmResponseObj.signature

    if (!signature) {
      throw new Error('missing signature in HSM response')
    }

    // Parse body to validate contents
    // Verify the signature over the raw body JSON
    await this.verifier.verify(bodyJson, signature, HSM_PUBLIC_KEY)

    const body = JSON.parse(bodyJson) as HsmResponseBody

    // Verify HSM identity
    if (body.hsmIdentity !== HSM_PUBLIC_KEY) {
      throw new Error('invalid HSM identity')
    }

    // Validate purpose
    if (body.payload.purpose !== 'access') {
      throw new Error('invalid purpose: expected access')
    }

    // Check expiration
    const expirationDate = new Date(body.payload.expiration)
    if (expirationDate <= new Date()) {
      throw new Error('key expired')
    }

    // Return the public key from the payload
    const verificationKey = new VerificationKey(body.payload.publicKey, this.verifier)

    return verificationKey
  }
}
