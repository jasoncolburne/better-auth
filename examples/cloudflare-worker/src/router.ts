import { WorkerServer } from './server.js';

export class WorkerRouter {
  constructor(private readonly server: WorkerServer) { }

  async handleRequest(request: Request): Promise<Response> {
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 200,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
        },
      });
    }

    if (request.method !== 'POST') {
      return new Response('Method Not Allowed', { status: 405 });
    }

    const path = new URL(request.url).pathname;
    const body = await request.text();
    const ba = this.server.betterAuthServer;

    const ok = (output: string): Response =>
      new Response(output, {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      });

    switch (path) {
      case '/account/create':
        return ok(await this.server.handleWrapped(body, m => ba.createAccount(m)));
      case '/account/recover':
        return ok(await this.server.handleWrapped(body, m => ba.recoverAccount(m)));
      case '/account/delete':
        return ok(await this.server.handleWrapped(body, m => ba.deleteAccount(m)));
      case '/session/request':
        return ok(await this.server.handleWrapped(body, m => ba.requestSession(m)));
      case '/session/create':
        return ok(await this.server.handleWrapped(body, m =>
          ba.createSession(m, {
            permissionsByRole: { user: ['read', 'write'] },
          })
        ));
      case '/session/refresh':
        return ok(await this.server.handleWrapped(body, m => ba.refreshSession(m)));
      case '/device/link':
        return ok(await this.server.handleWrapped(body, m => ba.linkDevice(m)));
      case '/device/unlink':
        return ok(await this.server.handleWrapped(body, m => ba.unlinkDevice(m)));
      case '/device/rotate':
        return ok(await this.server.handleWrapped(body, m => ba.rotateDevice(m)));
      case '/recovery/change':
        return ok(await this.server.handleWrapped(body, m => ba.changeRecoveryKey(m)));
      case '/key/response':
        return ok(await this.server.handleWrapped(body, async () => this.server.publicResponseKey.public()));
      case '/foo/bar':
        return ok(await this.server.handleWrapped(body, m => this.server.respondToAccessRequest(m, false)));
      case '/bad/nonce':
        return ok(await this.server.handleWrapped(body, m => this.server.respondToAccessRequest(m, true)));
      default:
        return new Response('Not Found', { status: 404 });
    }
  }
}
