import type { ITokenEncoder } from 'better-auth-ts';
import { Base64 } from './base64.js';

export class TokenEncoder implements ITokenEncoder {
  async signatureLength(token: string): Promise<number> {
    if (token.length < 2) {
      throw new Error('token too short');
    }
    if (!token.startsWith('0I')) {
      throw new Error('incorrect token format, expected to start with 0I');
    }
    // Signature is 66 raw bytes (2 zero padding + 64-byte raw ECDSA), base64 => 88 chars.
    return 88;
  }

  async encode(object: string): Promise<string> {
    // Compress JSON string with gzip, then URL-safe base64 (strip padding).
    const encoder = new TextEncoder();
    const jsonBytes = encoder.encode(object);

    const cs = new CompressionStream('gzip')
    const compressedStream = new Blob([jsonBytes]).stream().pipeThrough(cs)
    const compressedBuffer = await new Response(compressedStream).arrayBuffer()
    const compressedToken = new Uint8Array(compressedBuffer)

    const base64 = Base64.encode(compressedToken);
    return base64;
  }

  async decode(rawToken: string): Promise<string> {
    // Base64 decode, decompress gzip, decode to JSON string.
    let token = rawToken;
    while (token.length % 4 !== 0) {
      token += '=';
    }
    const compressedBytes = Base64.decode(token);

    const ds = new DecompressionStream('gzip')
    const decompressedStream = new Blob([compressedBytes]).stream().pipeThrough(ds)
    const decompressedBuffer = await new Response(decompressedStream).arrayBuffer()
    const objectBytes = new Uint8Array(decompressedBuffer)
    const decoder = new TextDecoder('utf-8')
    const objectString = decoder.decode(objectBytes)

    return objectString
  }
}
