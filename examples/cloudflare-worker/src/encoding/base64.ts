export class Base64 {
  static encode(data: Uint8Array): string {
    // Convert to string for btoa
    let binary = '';
    for (let i = 0; i < data.byteLength; i++) {
      binary += String.fromCharCode(data[i]);
    }
    let base64 = btoa(binary);
    // URL-safe: replace + with -, / with _, strip padding
    base64 = base64.replace(/\//g, '_').replace(/\+/g, '-').replace(/=+$/g, '');
    return base64;
  }

  static decode(base64: string): Uint8Array<ArrayBuffer> {
    // Reverse URL-safe (padding may already be present)
    base64 = base64.replace(/-/g, '+').replace(/_/g, '/');
    // Add padding if needed
    while (base64.length % 4) {
      base64 += '=';
    }
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }
}
