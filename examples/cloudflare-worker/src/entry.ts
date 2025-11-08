import { WorkerServer } from './server.js';
import { WorkerRouter } from './router.js';

export default {
  async fetch(request: Request): Promise<Response> {
    const server = await WorkerServer.getInstance();
    const router = new WorkerRouter(server);
    return router.handleRequest(request);
  },
};
