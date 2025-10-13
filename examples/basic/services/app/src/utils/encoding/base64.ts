import { TextDecoder, TextEncoder } from 'util'

export class Base64 {
  private static readonly encoder = new TextEncoder()
  private static readonly decoder = new TextDecoder()

  static encode(data: Uint8Array): string {
    let base64: string

    if (typeof Buffer !== 'undefined') {
      base64 = Buffer.from(data).toString('base64')
    } else {
      const binary = String.fromCharCode(...data)
      base64 = globalThis.btoa(binary)
    }

    return base64.replaceAll('/', '_').replaceAll('+', '-')
  }

  static decode(base64: string): Uint8Array {
    if (typeof Buffer !== 'undefined') {
      return new Uint8Array(Buffer.from(base64, 'base64'))
    } else {
      const binary = globalThis.atob(base64)
      return new Uint8Array(binary.split('').map(c => c.charCodeAt(0)))
    }
  }
}
