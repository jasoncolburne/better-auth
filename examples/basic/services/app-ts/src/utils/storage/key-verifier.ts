import { IVerifier, IHasher } from 'better-auth-ts'
import { Redis } from 'ioredis'
import { Secp256r1Verifier } from '../crypto/secp256r1.js'
import { Blake3Hasher } from '../crypto/blake3.js'
import { getSubJson } from './utils.js'

const HSM_IDENTITY = 'BETTER_AUTH_HSM_IDENTITY_PLACEHOLDER'

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

interface ExpiringEntry {
  entry: LogEntry
  expiration: Date | null
}

export class KeyVerifier {
  private readonly client: Redis
  private readonly verifier: IVerifier
  private readonly hasher: IHasher
  private readonly cache: Map<string, ExpiringEntry>
  private readonly serverLifetime: number
  private readonly accessLifetime: number

  constructor(
    redisHost: string,
    redisDbHsmKeys: number,
    serverLifetimeHours: number,
    accessLifetimeMinutes: number
  ) {
    this.serverLifetime = serverLifetimeHours * 60 * 60 * 1000
    this.accessLifetime = accessLifetimeMinutes * 60 * 1000
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
        let lastCreatedAt = new Date(0)

        for (let i = 0; i < records.length; i++) {
          const payload = records[i][0].payload

          if (payload.sequenceNumber !== i) {
            throw new Error('bad sequence number')
          }

          // Validate timestamp ordering
          const createdAt = new Date(payload.createdAt)
          if (createdAt >= new Date()) {
            throw new Error('future timestamp')
          }

          if (payload.sequenceNumber !== 0) {
            if (lastId !== payload.previous) {
              throw new Error('broken chain')
            }

            if (createdAt <= lastCreatedAt) {
              throw new Error('non-increasing timestamp')
            }

            const hash = await this.hasher.sum(payload.publicKey)

            if (hash !== lastRotationHash) {
              throw new Error('bad commitment')
            }
          }

          lastId = payload.id
          lastRotationHash = payload.rotationHash
          lastCreatedAt = createdAt
        }
      }

      // Verify prefix exists
      const records = byPrefix.get(HSM_IDENTITY)
      if (!records) {
        throw new Error('hsm identity not found')
      }

      var tainted = false
      var expiration: Date | null = null
      // Cache entries within 12-hour window (iterate backwards)
      for (let i = records.length - 1; i >= 0; i--) {
        const payload = records[i][0].payload

        if (!tainted) {
          this.cache.set(payload.id, {
            entry: payload,
            expiration: expiration
          })
        }

        if (payload.taintPrevious === true) {
          tainted = true
        } else {
          tainted = false
        }

        const createdAt = new Date(payload.createdAt)
        const exp = createdAt.getTime() + this.serverLifetime + this.accessLifetime
        expiration = new Date(exp)

        if (exp < Date.now()) {
          break
        }
      }

      cachedEntry = this.cache.get(hsmGenerationId)
      if (!cachedEntry) {
        throw new Error("can't find valid public key")
      }
    }

    if (cachedEntry.entry.prefix !== hsmIdentity) {
      throw new Error('incorrect identity (expected hsm.identity == prefix)')
    }

    if (cachedEntry.entry.purpose !== 'key-authorization') {
      throw new Error('incorrect purpose (expected key-authorization)')
    }

    if (cachedEntry.expiration !== null && cachedEntry.expiration < new Date()) {
      throw new Error('expired key')
    }

    // Verify message signature
    await this.verifier.verify(message, signature, cachedEntry.entry.publicKey)
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
