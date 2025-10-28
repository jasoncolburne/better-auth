import http from 'http'
import { AccessVerifier, ISigningKey, ServerResponse } from 'better-auth-ts'
import { Secp256r1, Secp256r1Verifier } from './utils/crypto/secp256r1.js'
import { VerificationKeyStore } from './utils/storage/common.js'
import { ServerTimeLockStore } from './utils/storage/server.js'
import { Rfc3339Nano } from './utils/encoding/timestamper.js'
import { TokenEncoder } from './utils/encoding/token_encoder.js'
import { Redis } from 'ioredis'

interface TokenAttributes {
  permissionsByRole: Record<string, string[]>
}

interface RequestPayload {
  foo: string
  bar: string
}

interface ResponsePayload {
  wasFoo: string
  wasBar: string
  serverName: string
}

interface AppState {
  verifier?: AccessVerifier
  authenticated: boolean
  responseKey?: ISigningKey
  accessClient?: Redis
  revokedDevicesClient?: Redis
  server?: http.Server
}

class Logger {
  static log(message: string) {
    console.log(`${new Date()}: ${message}`)
  }
}

class ApplicationServer {
  private state: AppState = {
    authenticated: false,
  }

  async quitAccessClient() {
    await this.state.accessClient?.quit()
    await this.state.revokedDevicesClient?.quit()
  }

  terminate(callback: () => void) {
    this.state.server?.close(callback)
  }

  async initialize(): Promise<void> {
    const redisHost = process.env.REDIS_HOST || 'redis:6379'
    Logger.log(`Connecting to Redis at ${redisHost}`)

    const redisDbAccessKeys = parseInt(process.env.REDIS_DB_ACCESS_KEYS || '0')
    const redisDbResponseKeys = parseInt(process.env.REDIS_DB_RESPONSE_KEYS || '1')
    const redisDbRevokedDevices = parseInt(process.env.REDIS_DB_REVOKED_DEVICES || '3')

    // Connect to Redis DB 0 to read access keys
    const accessClient = new Redis(redisHost, { db: redisDbAccessKeys })

    // Connect to Redis DB 3 to check revoked devices
    const revokedDevicesClient = new Redis(redisHost, { db: redisDbRevokedDevices })

    // Connect to Redis DB 1 to write/read response keys
    const responseClient = new Redis(redisHost, { db: redisDbResponseKeys })

    // Create verification key store and add all access keys
    const verifier = new Secp256r1Verifier()
    const verificationKeyStore = new VerificationKeyStore(accessClient)

    // Create an in-memory nonce store with 30 second window
    const accessNonceStore = new ServerTimeLockStore(30000)

    // Create AccessVerifier
    this.state.verifier = new AccessVerifier({
      crypto: {
        verifier,
      },
      encoding: {
        tokenEncoder: new TokenEncoder(),
        timestamper: new Rfc3339Nano(),
      },
      store: {
        access: {
          nonce: accessNonceStore,
          key: verificationKeyStore,
        },
      },
    })

    Logger.log('AccessVerifier initialized')

    // Generate app response key
    const appResponseKey = new Secp256r1()
    await appResponseKey.generate()
    const appResponsePublicKey = await appResponseKey.public()

    // Sign response key with HSM
    const hsmHost = process.env.HSM_HOST || 'hsm'
    const hsmPort = process.env.HSM_PORT || '11111'
    const hsmURL = `http://${hsmHost}:${hsmPort}`

    const responseTTL = 12 * 60 * 60 + 60 // 12 hours + 1 minute in seconds
    const responseExpiration = new Date(Date.now() + responseTTL * 1000).toISOString()
    const responsePayload = {
      purpose: 'response',
      publicKey: appResponsePublicKey,
      expiration: responseExpiration
    }

    var authorization: string
    const signResponse = await fetch(`${hsmURL}/sign`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        payload: responsePayload
      })
    })

    if (signResponse.ok) {
      authorization = (await signResponse.text()).trimEnd()
      Logger.log(`Response key HSM authorization (CESR): ${authorization}`)
    } else {
      throw 'hsm response not ok'
    }

    // Store response key in Redis DB 1 with 12 hour 1 minute TTL: SET <publicKey> <publicKey> EX 43260
    await responseClient.set(appResponsePublicKey, authorization, 'EX', responseTTL)
    Logger.log(`Registered app response key in Redis DB 1 (TTL: 12 hours): ${appResponsePublicKey.substring(0, 20)}...`)

    this.state.responseKey = appResponseKey
    await responseClient.quit()
    this.state.accessClient = accessClient
    this.state.revokedDevicesClient = revokedDevicesClient

    Logger.log('Application server initialized')
  }

  async handleHealth(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(
      JSON.stringify({
        status: 'healthy',
      })
    )
  }

  readRequestBody(req: http.IncomingMessage): Promise<string> {
    return new Promise((resolve, reject) => {
      let data = '';
      req.on('data', chunk => {
        data += chunk;
      });
      req.on('end', () => {
        resolve(data);
      });
      req.on('error', (err) => {
        reject(err);
      });
    });
  }
  async handleFooBar(
    req: http.IncomingMessage,
    res: http.ServerResponse
  ): Promise<void> {
    const message = await this.readRequestBody(req)

    const [request, token, nonce] = await this.state.verifier!.verify<
      RequestPayload,
      TokenAttributes
    >(message)

    // Check if device is revoked
    const isRevoked = await this.state.revokedDevicesClient!.exists(token.device)
    if (isRevoked) {
      res.writeHead(403, { 'Content-Type': 'application/json' })
      res.end('{"error":"device revoked"}')
      return
    }

    const userPermissions = token.attributes.permissionsByRole['user']
    if (typeof userPermissions === 'undefined' || !userPermissions.includes('read')) {
      res.writeHead(401, { 'Content-Type': 'application/json' })
      res.end('{"error":"unauthorized"}')
      return
    }

    const serverIdentity = await this.state.responseKey!.identity()

    const response = new ServerResponse<ResponsePayload>(
      {
        wasFoo: request.foo,
        wasBar: request.bar,
        serverName: 'typescript'
      },
      serverIdentity,
      nonce
    )

    await response.sign(this.state.responseKey!)
    const reply = await response.serialize()

    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(reply)
  }

  private corsHandler(req: http.IncomingMessage, res: http.ServerResponse): void {
    res.writeHead(200, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    })
    res.end()
  }

  startServer(port: number): void {
    const server = http.createServer(async (req, res) => {
      // Handle CORS preflight
      if (req.method === 'OPTIONS') {
        this.corsHandler(req, res)
        return
      }

      // Add CORS headers to all responses
      res.setHeader('Access-Control-Allow-Origin', '*')
      res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization')

      try {
        switch (req.url) {
          case '/health':
            await this.handleHealth(req, res)
            break
          case '/foo/bar':
            await this.handleFooBar(req, res)
            break
          default:
            res.writeHead(404, { 'Content-Type': 'application/json' })
            res.end(JSON.stringify({ error: 'not found' }))
        }
      } catch (error) {
        console.error('Error handling request:', error)
        res.writeHead(500, { 'Content-Type': 'application/json' })
        res.end(JSON.stringify({ error: 'internal server error' }))
      }
    })

    this.state.server = server

    server.listen(port, '0.0.0.0', () => {
      Logger.log(`Application server running on port ${port}`)
    })
  }
}

async function main(): Promise<void> {
  const port = 80

  const app = new ApplicationServer()
  await app.initialize()

  process.on('SIGTERM', async () => {
    console.log('SIGTERM received, starting graceful shutdown...')
    app.terminate(async () => {
      await app.quitAccessClient()
      process.exit(0)
    });
  })

  app.startServer(port)
}

main().catch((error) => {
  console.error('Failed to start application server:', error)
  process.exit(1)
})
