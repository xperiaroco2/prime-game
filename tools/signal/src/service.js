// The Durable Object's work, apart from the Cloudflare runtime so Node tests it with fakes
// (test/service.test.js): sockets in, SignalRouter's messages out, the way
// net/signal/lan_signalling.gd serves the same router over ws:// on a LAN.
//
// One Durable Object serves every room (worker.js): the protocol names the room in the first
// message, after the socket is open, and a socket whose join failed may try another code, so the
// socket cannot be routed to a room's own object when it connects.
//
// It uses the WebSocket Hibernation API: the object may leave memory while its sockets stay open,
// and the constructor runs again on the next event. So nothing lives only in memory: each socket's
// attachment holds its number and the router's record for it (SignalRouter.record), and a new
// SignalService rebuilds the router from them. A socket the router is done with says so in its
// attachment, "closing" (closed after the grace) or "gone" (closed, or failed), so no rebuild
// gives it back a role.

import * as codec from "./codec.js";
import { SignalRouter } from "./router.js";

// What "room" and every "offer" carry when the configuration names none (E58).
export const DEFAULT_ICE_SERVERS = [{ urls: ["stun:stun.cloudflare.com:3478"] }];
// How long after its last error the service closes a socket it ends (the host left). Godot's
// WebSocketPeer drops a message it reads together with the close (#366's probe), so closing at once
// would lose the reason. LanSignalling.close_grace_ms has the same value.
export const CLOSE_GRACE_MS = 1000;
// The normal closure, and an unexpected condition (RFC 6455 §7.4.1).
const CLOSE_NORMAL = 1000;
const CLOSE_ERROR = 1011;

// The ICE servers of the configuration (`ICE_SERVERS` in wrangler.toml's [vars], a list or its
// JSON text), checked by the codec's rules for "room", or the default. A bad list throws, so a
// misconfigured deploy fails at its first connection instead of sending what clients drop.
export function iceServersFrom(env) {
  let value = env.ICE_SERVERS;
  if (value === undefined || value === null || value === "") {
    return structuredClone(DEFAULT_ICE_SERVERS);
  }
  if (typeof value === "string") {
    value = JSON.parse(value);
  }
  const room = { t: "room", v: codec.VERSION, code: "AAAAAA", ice_servers: value };
  const decoded = codec.decode(new TextEncoder().encode(JSON.stringify(room)), codec.Side.TO_HOST);
  if (decoded.why !== undefined) {
    throw new Error(`signal: ICE_SERVERS is not a list the clients accept (${decoded.why})`);
  }
  return decoded.fields.ice_servers;
}

export class SignalService {
  // `ctx`: the Durable Object's state (acceptWebSocket, getWebSockets). `options` replaces the
  // runtime's clock, timer and random bytes in tests.
  constructor(ctx, env, options = {}) {
    this.ctx = ctx;
    this.now = options.now ?? (() => Date.now());
    this.setTimer = options.setTimer ?? ((callback, ms) => setTimeout(callback, ms));
    const randomBytes = options.randomBytes ?? ((n) => crypto.getRandomValues(new Uint8Array(n)));
    this.nextCode = options.nextCode ?? (() => codec.randomCode(randomBytes));
    this.iceServers = iceServersFrom(env);
    this.closeGraceMs = options.closeGraceMs ?? CLOSE_GRACE_MS;
    // Socket number -> its WebSocket, for this life of the object.
    this.sockets = new Map();
    this.nextSocket = 1;
    const records = [];
    for (const ws of ctx.getWebSockets()) {
      const attachment = ws.deserializeAttachment();
      if (attachment === null || attachment === undefined) {
        continue;
      }
      this.nextSocket = Math.max(this.nextSocket, attachment.id + 1);
      if (attachment.gone) {
        continue;
      }
      this.sockets.set(attachment.id, ws);
      if (attachment.closing !== undefined) {
        // The timer died with the object's memory: close it when the grace would have ended.
        this.closeLater(ws, attachment.closing - this.now());
      } else if (attachment.record !== null && attachment.record !== undefined) {
        records.push([attachment.id, attachment.record]);
      }
    }
    this.router = SignalRouter.restore(this.iceServers, this.nextCode, records);
  }

  // A new socket the Worker upgraded: the service accepts it with hibernation.
  accept(ws) {
    this.settle();
    const socket = this.nextSocket++;
    this.ctx.acceptWebSocket(ws);
    this.sockets.set(socket, ws);
    this.router.opened(socket);
    this.save();
  }

  // A message from `ws`: a string (text) or an ArrayBuffer (binary).
  message(ws, data) {
    this.settle();
    const attachment = ws.deserializeAttachment();
    if (ended(attachment)) {
      return;
    }
    const text = typeof data === "string";
    const bytes = text ? new TextEncoder().encode(data) : new Uint8Array(data);
    const out = this.router.received(attachment.id, bytes, text);
    this.save();
    this.deliver(out);
  }

  // `ws` closed. Idempotent.
  closed(ws) {
    this.settle();
    const attachment = ws.deserializeAttachment();
    if (attachment === null || attachment === undefined) {
      return;
    }
    this.sockets.delete(attachment.id);
    if (ended(attachment)) {
      return;
    }
    // Before anything is sent: an event that throws after this leaves no role on the socket.
    mark(ws, { id: attachment.id, gone: true });
    const out = this.router.closed(attachment.id);
    this.save();
    this.deliver(out);
  }

  // `ws` failed (webSocketError): the service closes it, and it is gone as if its client closed it.
  failed(ws) {
    this.closed(ws);
    try {
      ws.close(CLOSE_ERROR, "");
    } catch {
      // Already closed.
    }
  }

  roomCount() {
    return this.router.roomCount();
  }

  // Each changed socket's record onto its socket, before anything is sent.
  save() {
    for (const socket of this.router.takeChanged()) {
      const ws = this.sockets.get(socket);
      if (ws !== undefined) {
        ws.serializeAttachment({ id: socket, record: this.router.record(socket) });
      }
    }
  }

  deliver(out) {
    for (const each of out) {
      const ws = this.sockets.get(each.socket);
      if (ws === undefined) {
        continue;
      }
      // A socket the service is closing is no one's any more: nothing more goes to it.
      if (ended(ws.deserializeAttachment())) {
        continue;
      }
      try {
        ws.send(JSON.stringify(each.message));
      } catch {
        // Its client is gone, and its close event will follow; a socket the router ended is
        // still marked below, so no rebuild gives it back its role.
      }
      if (each.close) {
        mark(ws, { id: each.socket, closing: this.now() + this.closeGraceMs });
        this.closeLater(ws, this.closeGraceMs);
      }
    }
  }

  // Tells the joiners the rebuilt router found without a room that their host left, once, at the
  // first event after a wake: the host's socket went away while the object was out of memory.
  settle() {
    const out = this.router.orphans.map((socket) => ({
      socket,
      message: { t: "error", v: codec.VERSION, why: codec.WHY_HOST_LEFT },
      close: true,
    }));
    this.router.orphans = [];
    this.deliver(out);
  }

  closeLater(ws, ms) {
    this.setTimer(() => {
      try {
        ws.close(CLOSE_NORMAL, "");
      } catch {
        // Already closed by its client.
      }
    }, Math.max(0, ms));
  }
}

// Whether the router is done with the socket of `attachment`.
function ended(attachment) {
  return attachment === null || attachment === undefined || attachment.gone === true || attachment.closing !== undefined;
}

function mark(ws, attachment) {
  try {
    ws.serializeAttachment(attachment);
  } catch {
    // A socket already closed keeps no attachment, and is not listed after a wake.
  }
}
