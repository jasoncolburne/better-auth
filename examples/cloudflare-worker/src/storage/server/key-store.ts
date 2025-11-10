import type { IServerAuthenticationKeyStore } from 'better-auth-ts';
import type { IHasher } from 'better-auth-ts';
import { Hasher } from '../../crypto/hasher.js';

export class ServerAuthenticationKeyStore implements IServerAuthenticationKeyStore {
  private identities: Map<string, Set<string>> = new Map();
  private devices: Map<string, [string, string]> = new Map(); // key: identity + device, value: [publicKey, rotationHash]
  private hasher: IHasher;

  constructor(hasher: IHasher = new Hasher()) {
    this.hasher = hasher;
  }

  async register(identity: string, device: string, publicKey: string, rotationHash: string, existingIdentity: boolean): Promise<void> {
    const idKey = identity + device;
    if (this.devices.has(idKey)) {
      throw new Error('Device already registered');
    }
    if (!existingIdentity && this.identities.has(identity)) {
      throw new Error('Identity already exists');
    }
    if (!this.identities.has(identity)) {
      this.identities.set(identity, new Set());
    }
    this.devices.set(idKey, [publicKey, rotationHash]);
    this.identities.get(identity)!.add(device);
  }

  async rotate(identity: string, device: string, publicKey: string, rotationHash: string): Promise<void> {
    const idKey = identity + device;
    const current = this.devices.get(idKey);
    if (!current) {
      throw new Error('Device not found');
    }
    const expectedRotation = await this.hasher.sum(publicKey);
    if (current[1] !== expectedRotation) {
      throw new Error('Rotation hash mismatch');
    }
    this.devices.set(idKey, [publicKey, rotationHash]);
  }

  async public(identity: string, device: string): Promise<string> {
    const idKey = identity + device;
    const entry = this.devices.get(idKey);
    if (!entry) {
      throw new Error('Device not found');
    }
    return entry[0];
  }

  async revokeDevice(identity: string, device: string): Promise<void> {
    const idKey = identity + device;
    this.devices.delete(idKey);
    const idSet = this.identities.get(identity);
    if (idSet) {
      idSet.delete(device);
      if (idSet.size === 0) {
        this.identities.delete(identity);
      }
    }
  }

  async revokeDevices(identity: string): Promise<void> {
    const idSet = this.identities.get(identity);
    if (idSet) {
      for (const device of idSet) {
        this.devices.delete(identity + device);
      }
      this.identities.delete(identity);
    }
  }

  async deleteIdentity(identity: string): Promise<void> {
    await this.revokeDevices(identity);
  }

  async ensureActive(identity: string, device: string): Promise<void> {
    const idKey = identity + device;
    if (!this.devices.has(idKey)) {
      throw new Error('Device not active');
    }
    const idSet = this.identities.get(identity);
    if (!idSet || !idSet.has(device)) {
      throw new Error('Device not active');
    }
  }
}
