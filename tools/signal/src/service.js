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
//
// With a TURN key in the secrets (turn.js), every host offer to a joiner waits for a credential
// minted for it, and everything sent after that offer waits too, so each socket still gets its
// messages in the order the router made them (a candidate never overtakes its offer).

import * as codec from "./codec.js";
import { SignalRouter } from "./router.js";
import { mint, turnFrom, withTurn } from "./turn.js";

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
  // runtime's clock, timer, random bytes, fetch and log in tests.
  constructor(ctx, env, options = {}) {
    this.ctx = ctx;
    this.now = options.now ?? (() => Date.now());
    this.setTimer = options.setTimer ?? ((callback, ms) => setTimeout(callback, ms));
    const randomBytes = options.randomBytes ?? ((n) => crypto.getRandomValues(new Uint8Array(n)));
    this.nextCode = options.nextCode ?? (() => codec.randomCode(randomBytes));
    this.iceServers = iceServersFrom(env);
    // The TURN key, or null: no TURN, and every offer carries iceServers alone.
    this.turn = turnFrom(env);
    this.fetch = options.fetch ?? ((url, init) => fetch(url, init));
    this.log = options.log ?? ((text) => console.log(text));
    // What the last delivery still waiting on a mint settles, or null when nothing waits.
    this.tail = null;
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

  // A new socket the Worker upgraded: the service accepts it with hibernation. The methods that
  // take an event return a promise that settles once what the event sends is sent.
  accept(ws) {
    this.settle();
    const socket = this.nextSocket++;
    this.ctx.acceptWebSocket(ws);
    this.sockets.set(socket, ws);
    this.router.opened(socket);
    this.save();
    return this.tail ?? Promise.resolve();
  }

  // A message from `ws`: a string (text) or an ArrayBuffer (binary).
  message(ws, data) {
    this.settle();
    const attachment = ws.deserializeAttachment();
    if (ended(attachment)) {
      return this.tail ?? Promise.resolve();
    }
    const text = typeof data === "string";
    const bytes = text ? new TextEncoder().encode(data) : new Uint8Array(data);
    const out = this.router.received(attachment.id, bytes, text);
    this.save();
    return this.inOrder(out);
  }

  // `ws` closed. Idempotent.
  closed(ws) {
    this.settle();
    const attachment = ws.deserializeAttachment();
    if (attachment === null || attachment === undefined) {
      return this.tail ?? Promise.resolve();
    }
    this.sockets.delete(attachment.id);
    if (ended(attachment)) {
      return this.tail ?? Promise.resolve();
    }
    // Before anything is sent: an event that throws after this leaves no role on the socket.
    mark(ws, { id: attachment.id, gone: true });
    const out = this.router.closed(attachment.id);
    this.save();
    return this.inOrder(out);
  }

  // `ws` failed (webSocketError): the service closes it, and it is gone as if its client closed it.
  failed(ws) {
    const sent = this.closed(ws);
    try {
      ws.close(CLOSE_ERROR, "");
    } catch {
      // Already closed.
    }
    return sent;
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

  // Sends `out` after everything sent before it: at once, unless an earlier offer still waits on
  // its mint. The promise settles once `out` is sent; the Durable Object awaits it, so the object
  // stays awake while the API answers.
  inOrder(out) {
    if (this.tail === null) {
      const rest = this.deliver(out);
      return rest === undefined ? Promise.resolve() : this.track(rest);
    }
    return this.track(this.tail.then(() => this.deliver(out)));
  }

  track(promise) {
    const tail = promise
      .catch((error) => this.log(`signal: a delivery failed: ${error}`))
      .finally(() => {
        if (this.tail === tail) {
          this.tail = null;
        }
      });
    this.tail = tail;
    return tail;
  }

  // Sends `out` in order; returns undefined when all of it is sent, or a promise when an offer
  // waits on its TURN credential (the rest is sent after it).
  deliver(out) {
    for (let at = 0; at < out.length; at++) {
      const each = out[at];
      if (this.turn !== null && each.message.t === "offer") {
        return this.withCredential(each).then(() => this.deliver(out.slice(at + 1)));
      }
      this.send(each);
    }
    return undefined;
  }

  // The host's offer to one joiner, with a credential minted for this offer alone added to its ICE
  // servers. If the API fails, or the credential would push the offer over the cap, the offer goes
  // as it would without TURN: the joiner may still connect directly.
  async withCredential(each) {
    const ws = this.sockets.get(each.socket);
    if (ws === undefined || ended(ws.deserializeAttachment())) {
      return;
    }
    let message = each.message;
    try {
      const servers = withTurn(message.ice_servers, await mint(this.turn, this.fetch));
      const relayed = { ...message, ice_servers: servers };
      if (codec.size(relayed) > codec.MAX_MESSAGE_BYTES) {
        throw new Error("the offer with TURN is over the cap");
      }
      message = relayed;
    } catch (error) {
      this.log(`signal: an offer goes without TURN: ${error.message}`);
    }
    this.send({ ...each, message });
  }

  send(each) {
    const ws = this.sockets.get(each.socket);
    if (ws === undefined) {
      return;
    }
    // A socket the service is closing is no one's any more: nothing more goes to it.
    if (ended(ws.deserializeAttachment())) {
      return;
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

  // Tells the joiners the rebuilt router found without a room that their host left, once, at the
  // first event after a wake: the host's socket went away while the object was out of memory.
  settle() {
    const out = this.router.orphans.map((socket) => ({
      socket,
      message: { t: "error", v: codec.VERSION, why: codec.WHY_HOST_LEFT },
      close: true,
    }));
    this.router.orphans = [];
    this.inOrder(out);
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
