import { IVerifier, IHasher } from 'better-auth-ts'
import { Redis } from 'ioredis'
import { Secp256r1Verifier } from '../crypto/secp256r1.js'
import { Blake3Hasher } from '../crypto/blake3.js'
import { getSubJson } from './utils.js'

const HSM_IDENTITY = 'BETTER_AUTH_HSM_IDENTITY_PLACEHOLDER'

// needs to be server lifetime + access lifetime. consider a server that just rolled before the hsm
// rotation. it may issue a token 11:59:59 into the new hsm key's existence, but it's authorized with
// the old hsm key. that key is then valid for the access lifetime (15 minutes in our case) before
// it must be refreshed. again for app servers, this time must be server lifetime + access lifetime.
// for auth servers it is different. in this example, the access lifetime is a parameter of the store.
const TWELVE_HOURS_MS = 12 * 60 * 60 * 1000

interface LogEntry {
  id: string
  prefix: string
  previous: string | null
  sequenceNumber: number
  createdAt: string
  taintPrevious: boolean | null
  purpose: string
  publicKey: string
  rotationHash: string
}

interface SignedLogEntry {
  payload: LogEntry
  signature: string
}

export class KeyVerifier {
  private readonly client: Redis
  private readonly verifier: IVerifier
  private readonly hasher: IHasher
  private readonly cache: Map<string, LogEntry>
  private readonly accessLifetime: number

  constructor(redisHost: string, redisDbHsmKeys: number, accessLifetimeInMinutes: number) {
    this.accessLifetime = accessLifetimeInMinutes * 60 * 1000
    this.client = new Redis({
      host: redisHost.split(':')[0],
      port: parseInt(redisHost.split(':')[1]) || 6379,
      db: redisDbHsmKeys,
    })
    this.verifier = new Secp256r1Verifier()
    this.hasher = new Blake3Hasher()
    this.cache = new Map()
  }

  async verify(
    signature: string,
    hsmIdentity: string,
    hsmGenerationId: string,
    message: string
  ): Promise<void> {
    let cachedEntry = this.cache.get(hsmGenerationId)

    if (!cachedEntry) {
      // clear the cache, we are seeing a new key
      this.cache.clear()

      // Fetch all HSM keys from Redis
      const keys = await this.client.keys('*')
      const values = await this.client.mget(...keys)

      // Group by prefix
      const byPrefix: Map<string, Array<[SignedLogEntry, string]>> = new Map()

      for (const value of values) {
        if (!value) continue

        const payloadJson = getSubJson(value, 'payload')
        const record = JSON.parse(value) as SignedLogEntry
        const prefix = record.payload.prefix

        if (!byPrefix.has(prefix)) {
          byPrefix.set(prefix, [])
        }

        byPrefix.get(prefix)!.push([record, payloadJson])
      }

      // Sort by sequence number
      for (const [prefix, records] of byPrefix.entries()) {
        records.sort((a, b) => a[0].payload.sequenceNumber - b[0].payload.sequenceNumber)
        byPrefix.set(prefix, records)
      }

      // Verify data & signatures for all records
      for (const prefix of byPrefix.keys()) {
        const records = byPrefix.get(prefix)!
        for (const [record, payloadJson] of records) {
          const payload = record.payload

          if (payload.sequenceNumber === 0) {
            await this.verifyPrefixAndData(payloadJson, payload)
          } else {
            await this.verifyAddressAndData(payloadJson, payload)
          }

          // Verify signature over payload
          await this.verifier.verify(payloadJson, record.signature, payload.publicKey)
        }
      }

      // Verify chains
      for (const records of byPrefix.values()) {
        let lastId = ''
        let lastRotationHash = ''

        for (let i = 0; i < records.length; i++) {
          const payload = records[i][0].payload

          if (payload.sequenceNumber !== i) {
            throw new Error('bad sequence number')
          }

          if (payload.sequenceNumber !== 0) {
            if (lastId !== payload.previous) {
              throw new Error('broken chain')
            }

            const hash = await this.hasher.sum(payload.publicKey)

            if (hash !== lastRotationHash) {
              throw new Error('bad commitment')
            }
          }

          lastId = payload.id
          lastRotationHash = payload.rotationHash
        }
      }

      // Verify prefix exists
      const records = byPrefix.get(HSM_IDENTITY)
      if (!records) {
        throw new Error('hsm identity not found')
      }

      var tainted = false
      // Cache entries within 12-hour window (iterate backwards)
      for (let i = records.length - 1; i >= 0; i--) {
        const payload = records[i][0].payload

        if (!tainted) {
          this.cache.set(payload.id, payload)
        }

        if (payload.taintPrevious === true) {
          tainted = true
        } else {
          tainted = false
        }

        const createdAt = new Date(payload.createdAt)
        if (createdAt.getTime() + TWELVE_HOURS_MS + this.accessLifetime < Date.now()) {
          break
        }
      }

      cachedEntry = this.cache.get(hsmGenerationId)
      if (!cachedEntry) {
        throw new Error("can't find valid public key")
      }
    }

    if (cachedEntry.prefix !== hsmIdentity) {
      throw new Error('incorrect identity (expected hsm.identity == prefix)')
    }

    if (cachedEntry.purpose !== 'key-authorization') {
      throw new Error('incorrect purpose (expected key-authorization)')
    }

    // Verify message signature
    await this.verifier.verify(message, signature, cachedEntry.publicKey)
  }

  private async verifyPrefixAndData(payloadJson: string, payload: LogEntry): Promise<void> {
    if (payload.id !== payload.prefix) {
      throw new Error('prefix must equal id for sequence 0')
    }

    await this.verifyAddressAndData(payloadJson, payload)
  }

  private async verifyAddressAndData(payloadJson: string, payload: LogEntry): Promise<void> {
    // Serialize payload and replace id with placeholder
    const modifiedPayload = payloadJson.replace(
      new RegExp(payload.id, 'g'),
      '############################################'
    )

    const hash = await this.hasher.sum(modifiedPayload)

    if (hash !== payload.id) {
      throw new Error('id does not match hash of payload')
    }
  }

  async close(): Promise<void> {
    await this.client.quit()
  }
}
