import { IHasher } from 'better-auth-ts'
import { blake3 } from '@noble/hashes/blake3.js'
import { Base64 } from '../encoding/base64.js'
import { TextEncoder } from 'util'

export class Blake3Hasher implements IHasher {
  async sum(message: string): Promise<string> {
    const encoder = new TextEncoder()
    const messageBytes = encoder.encode(message)
    const hashBytes = blake3(messageBytes)

    // Encode as Base64 with padding
    const padded = new Uint8Array([0, ...hashBytes])
    const base64 = Base64.encode(padded)

    return `E${base64.substring(1)}`
  }
}
