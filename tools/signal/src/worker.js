// The signalling service on Cloudflare (docs/ARCHITECTURE.md §4.8; the M6 ADR §2.4, D18): the
// Worker upgrades a WebSocket and hands it to the one Durable Object that holds every room
// (service.js says why one). This file is the only one that needs the Cloudflare runtime; the
// tests cover what it calls, and the first deploy tries it (tools/signal/README.md).

import { DurableObject } from "cloudflare:workers";
import { SignalService } from "./service.js";

// The Durable Object's name: one object, so every socket meets every room.
const OBJECT_NAME = "signalling";

export class Signalling extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.service = new SignalService(ctx, env);
  }

  async fetch() {
    const [client, server] = Object.values(new WebSocketPair());
    this.service.accept(server);
    return new Response(null, { status: 101, webSocket: client });
  }

  // Awaited: with a TURN key, an offer waits on the API, and the object stays awake until it is sent.
  async webSocketMessage(ws, message) {
    await this.service.message(ws, message);
  }

  // The service answers the close frame (service.js says why the runtime's own answer is not enough).
  async webSocketClose(ws, code) {
    await this.service.clientClosed(ws, code);
  }

  async webSocketError(ws) {
    await this.service.failed(ws);
  }
}

export default {
  async fetch(request, env) {
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("prime-game signalling: connect with a WebSocket\n", { status: 426 });
    }
    if (request.method !== "GET") {
      return new Response("prime-game signalling: expected GET\n", { status: 400 });
    }
    return env.SIGNALLING.getByName(OBJECT_NAME).fetch(request);
  },
};
