import Pako from 'pako'
import { ITokenEncoder } from 'better-auth-ts'
import { Base64 } from './base64.js'
import { TextDecoder, TextEncoder } from 'util'

export class TokenEncoder implements ITokenEncoder {
  async signatureLength(token: string): Promise<number> {
    if (token.length < 2) {
      throw 'token too short'
    }

    if (!token.startsWith('0I')) {
      throw 'incorrect token format'
    }

    return 88
  }

  async encode(object: string): Promise<string> {
    const encoder = new TextEncoder()
    const tokenBytes = encoder.encode(object)
    const compressedToken = Pako.gzip(tokenBytes, { level: 9 })
    const token = Base64.encode(compressedToken).replaceAll('=', '')

    return token
  }

  async decode(rawToken: string): Promise<string> {
    let token = rawToken

    while (token.length % 4 !== 0) {
      token += '='
    }

    const compressedToken = Base64.decode(token)
    const objectBytes = Pako.ungzip(compressedToken)

    const decoder = new TextDecoder('utf-8')
    const objectString = decoder.decode(objectBytes)

    return objectString
  }
}
