// Token attributes compatible with integration tests.
// Defines user permissions for generated access tokens.
export interface CloudflareTokenAttributes {
  permissionsByRole: Record<string, string[]>;
}
import {
  BetterAuthServer,
  AccessVerifier,
  ServerResponse,
} from 'better-auth-ts';
import { ServerAuthenticationKeyStore, ServerAuthenticationNonceStore, ServerRecoveryHashStore, ServerTimeLockStore } from './storage/server/index.js';
import { VerificationKeyStore } from './storage/key-store.js';
import { Hasher, Noncer, Secp256r1, Secp256r1Verifier } from './crypto/index.js';
import { IdentityVerifier, Rfc3339, TokenEncoder } from './encoding/index.js';

declare global {
  interface CloudflareStores {
    verificationKey: VerificationKeyStore;
    keyHash: ServerTimeLockStore;
    authenticationKey: ServerAuthenticationKeyStore;
    authenticationNonce: ServerAuthenticationNonceStore;
    recoveryHash: ServerRecoveryHashStore;
    accessNonce: ServerTimeLockStore;
    responseKey: Secp256r1;
    accessKey: Secp256r1;
  }
  // @ts-ignore
  var __stores: CloudflareStores | undefined;
}

export interface CloudflareTokenAttributes {
  permissionsByRole: Record<string, string[]>;
}

export class WorkerServer {
  private static instance: WorkerServer;

  private readonly ba: BetterAuthServer;
  private readonly av: AccessVerifier;
  private readonly responseKey: Secp256r1;
  private readonly accessKey: Secp256r1;

  private constructor() {
    const hasher = new Hasher();
    const verifier = new Secp256r1Verifier();
    const noncer = new Noncer();
    const identityVerifier = new IdentityVerifier(hasher);
    const timestamper = new Rfc3339();
    const tokenEncoder = new TokenEncoder();

    // TODO: replace in-memory maps with a Cloudflare KV or Durable Object for persistence
    if (!globalThis.__stores) {
      globalThis.__stores = {
        verificationKey: new VerificationKeyStore(),
        keyHash: new ServerTimeLockStore(12 * 3600),
        authenticationKey: new ServerAuthenticationKeyStore(),
        authenticationNonce: new ServerAuthenticationNonceStore(60),
        recoveryHash: new ServerRecoveryHashStore(),
        accessNonce: new ServerTimeLockStore(30),
        responseKey: new Secp256r1(),
        accessKey: new Secp256r1(),
      };
    }

    this.responseKey = globalThis.__stores.responseKey;
    this.accessKey = globalThis.__stores.accessKey;

    this.ba = new BetterAuthServer({
      crypto: {
        hasher,
        verifier,
        noncer,
        keyPair: {
          access: this.accessKey,
          response: this.responseKey,
        },
      },
      encoding: {
        identityVerifier,
        timestamper,
        tokenEncoder,
      },
      expiry: {
        accessInMinutes: 15,
        refreshInHours: 12,
      },
      store: {
        access: {
          verificationKey: globalThis.__stores.verificationKey,
          keyHash: globalThis.__stores.keyHash,
        },
        authentication: {
          key: globalThis.__stores.authenticationKey,
          nonce: globalThis.__stores.authenticationNonce,
        },
        recovery: {
          hash: globalThis.__stores.recoveryHash,
        },
      },
    });

    this.av = new AccessVerifier({
      crypto: { verifier },
      encoding: { tokenEncoder, timestamper },
      store: {
        access: {
          nonce: globalThis.__stores.accessNonce,
          key: globalThis.__stores.verificationKey,
        },
      },
    });
  }

  static async getInstance(): Promise<WorkerServer> {
    if (!WorkerServer.instance) {
      WorkerServer.instance = new WorkerServer();
      await WorkerServer.instance.initialize();
    }
    return WorkerServer.instance;
  }

  async initialize(): Promise<void> {
    await this.responseKey.generate();
    await this.accessKey.generate();
    const identity = await this.accessKey.identity();
    const stores = globalThis.__stores!;
    await stores.verificationKey.add(identity, this.accessKey);
  }

  async handleWrapped(body: string, logic: (message: string) => Promise<string>): Promise<string> {
    try {
      return await logic(body);
    } catch (error) {
      console.error(error);
      return JSON.stringify({ error: 'an error occurred' });
    }
  }

  async respondToAccessRequest(message: string, badNonce: boolean): Promise<string> {
    const [requestData, _token, requestNonce] = await this.av.verify<
      { foo: string; bar: string },
      CloudflareTokenAttributes
    >(message);
    const request = requestData;
    const serverIdentity = await this.responseKey.identity();
    const nonce = badNonce ? '0A0123456789' : requestNonce;

    const response = new ServerResponse(
      { wasFoo: request.foo, wasBar: request.bar },
      serverIdentity,
      nonce
    );
    await response.sign(this.responseKey);
    return await response.serialize();
  }

  get betterAuthServer() {
    return this.ba;
  }

  get accessVerifier() {
    return this.av;
  }

  get publicResponseKey() {
    return this.responseKey;
  }
}
