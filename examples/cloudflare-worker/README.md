# @better-auth/cloudflare-worker

This is a full **Cloudflare Worker** implementation for the [better-auth-ts](https://github.com/jasoncolburne/better-auth-ts) library, providing secure passwordless authentication with end-to-end encryption, recovery, and session management. It uses Web Crypto API for ECDSA (Secp256r1), gzip-compressed tokens, and in-memory stores (with TODO for KV persistence).

## Features

- **Crypto**: Secp256r1 signing/verification with raw ECDSA signatures (padded for compatibility).
- **Encoding**: RFC3339 timestamps (cloned to avoid mutation), gzip-compressed JSON tokens via CompressionStream, URL-safe Base64 (compact, no padding).
- **Storage**: In-memory stores for keys, nonces, recovery hashes, and time-locks; supports device rotation, linking, and recovery (identity preserved post-revoke).
- **Endpoints**: Full auth flow (/account/create, /session/create, /device/rotate, /recovery/change, /foo/bar for access testing).

## 📦 Installation

From the project root:

```bash
cd examples/cloudflare-worker
npm install
```

## 🚀 Development

Build and run locally with workerd:

```bash
npm run build  # Compiles TS to ESM in dist/
npm run dev    # Serves via workerd on http://localhost:8787
```

- Access endpoints at `http://localhost:8080/{path}` (e.g., POST /key/response for pubkey).
- CORS enabled for \* origin.

## 🧪 Testing

### Local Worker Testing

Use curl or a client to test flows (replace `BASE_URL=http://localhost:8080`; generate real hashes/keys client-side):

1. **Get Response Key**:

   ```bash
   curl -X POST $BASE_URL/key/response -H "Content-Type: application/json" -d '{}'
   ```

2. **Create Account** (use recovery pubkey hash):

   ```bash
   RECOVERY_HASH="base64(SHA256(recovery_pubkey))"  # Generate via client
   curl -X POST $BASE_URL/account/create -H "Content-Type: application/json" -d "{\"recoveryHash\": \"$RECOVERY_HASH\"}"  # Full serialized request
   ```

3. **Full Flow**: Use the JS client below or Postman for create → session → access.

### Integration with better-auth-ts Tests

The worker mimics the example server, so uncomment recovery/linking tests in `better-auth-ts/src/tests/integration.test.ts` and run:

- In better-auth-ts dir: `node examples/server.ts` (keep running).
- `npm run test:integration` — tests hit localhost:8080, but adapt Network to 8787 for worker.

### Simple Test Client (`test-client.js`)

Create this file in the worker dir for automated flows (run `node test-client.js` after dev):

```js
// test-client.js - Basic auth flow test
const BASE_URL = "http://localhost:8080";
const fetch = require("node-fetch"); // npm i node-fetch

async function testFlow() {
  // 1. Get response key
  const resKey = await (
    await fetch(`${BASE_URL}/key/response`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    })
  ).text();
  console.log("Response Key:", resKey);

  // Full flow requires serializing BetterAuthClient requests; use for endpoint smoke test
  // e.g., POST /foo/bar with valid access token from session
  console.log("Test complete - implement full client for e2e.");
}

testFlow();
```

## 📁 Project Structure

```
cloudflare-worker/
├── src/
│   ├── crypto/          # Secp256r1 signer/verifier (Web Crypto ECDSA)
│   │   ├── hasher.ts    # SHA-256 hashing
│   │   ├── index.ts
│   │   ├── noncer.ts    # 128-bit nonce generation
│   │   ├── secp256r1.ts # Key gen/sign/verify with padding
│   │   └── verifier.ts  # ECDSA verification
│   ├── encoding/        # Token/timestamp/Base64 handling
│   │   ├── base64.ts    # URL-safe Base64 (compact, no padding)
│   │   ├── identity-verifier.ts
│   │   ├── index.ts
│   │   ├── timestamper.ts # RFC3339 with Date cloning
│   │   └── token-encoder.ts # Gzip-compressed JSON tokens
│   ├── storage/         # In-memory stores (keys, nonces, hashes)
│   │   ├── client-stores.ts # Client-side mocks (for testing; not used in server)
│   │   ├── index.ts
│   │   ├── key-store.ts # Authentication keys with rotation/recovery
│   │   └── server/      # Server stores (time-lock, nonce, recovery)
│   ├── entry.ts         # Worker fetch handler
│   ├── router.ts        # Endpoint routing (/account, /session, etc.)
│   └── server.ts        # BetterAuthServer + AccessVerifier init
├── package.json         # Dependencies (tsup, workerd)
├── tsconfig.json
├── tsup.config.ts       # ESM build config
├── worker.config.capnp  # Workerd config
└── README.md
```

## 🔧 TODOs & Notes

- **Deployment**: Example only works locally
  - **Wrangler**: This was a poc using workerd, thinking to replace with full wrangler support for deployment
- **Persistence**: Replace in-memory Maps with Cloudflare KV/D1 (e.g., in key-store.ts: use `env.KV.put/get`).
- **Client Integration**: client-stores.ts is currently empty and for browser clients (localStorage); extend/implement for js worker (e.g., IndexedDB).
- **Security**: Use Durable Objects for concurrent access; add rate limiting.
- **Instrumentation**: Compression saves bandwidth; monitor gzip overhead for small payloads, look at adding observability to support cloudflare deployments
- **Testing**: Add unit tests (Vitest) for stores/crypto; e2e with Playwright.
  - Currently relying on `better-auth-ts/src/tests/integration.test.ts`
