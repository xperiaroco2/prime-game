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
// With a TURN key in the secrets (turn.js), "room" and every host offer to a joiner wait for a
// credential minted for their receiver, and what follows them to the same socket waits too, so
// each socket still gets its messages in the order the router made them (a candidate never
// overtakes its offer).

import * as codec from "./codec.js";
import { SignalRouter } from "./router.js";
import { TIMEOUT_MS, mint, turnFrom, withTurn } from "./turn.js";

// The messages that carry a TURN credential minted for their receiver, when TURN is on: the host's
// own with "room", a joiner's with the host's offer to it (the M6 ADR §2.4), never "found".
const RELAYED = new Set(["room", "offer"]);
// What "room" and every "offer" carry when the configuration names none (E58).
export const DEFAULT_ICE_SERVERS = [{ urls: ["stun:stun.cloudflare.com:3478"] }];
// How long after its last error the service closes a socket it ends (the host left). Godot's
// WebSocketPeer drops a message it reads together with the close (#366's probe), so closing at once
// would lose the reason. LanSignalling.close_grace_ms has the same value.
export const CLOSE_GRACE_MS = 1000;
// The normal closure, and an unexpected condition (RFC 6455 §7.4.1).
const CLOSE_NORMAL = 1000;
const CLOSE_ERROR = 1011;

// The code the service answers a client's close frame with: the client's own when the runtime may
// send it (1000, or 3000-4999, the codes its strict rule allows), else 1000. The runtime's close()
// throws for 1004, 1005 (no status), 1006 and 1015 and anything outside 1000-4999 under either
// rule, and for every other code from 1001 to 2999 under the strict one (workerd's WebSocket::close).
export function closeReplyCode(code) {
  if (Number.isInteger(code) && (code === CLOSE_NORMAL || (code >= 3000 && code <= 4999))) {
    return code;
  }
  return CLOSE_NORMAL;
}

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
    this.fetch = options.fetch ?? ((url, init) => fetch(url, init));
    this.log = options.log ?? ((text) => console.log(text));
    // The TURN key, or null: no TURN, and "room" and every offer carry iceServers alone.
    this.turn = turnFrom(env, this.log);
    this.turnTimeoutMs = options.turnTimeoutMs ?? TIMEOUT_MS;
    // Socket number -> what its last delivery still waiting on a mint settles; none when nothing
    // waits for it.
    this.queues = new Map();
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
    const orphaned = this.settle();
    const socket = this.nextSocket++;
    this.ctx.acceptWebSocket(ws);
    this.sockets.set(socket, ws);
    this.router.opened(socket);
    this.save();
    return orphaned;
  }

  // A message from `ws`: a string (text) or an ArrayBuffer (binary).
  message(ws, data) {
    this.settle();
    const attachment = ws.deserializeAttachment();
    if (ended(attachment)) {
      return Promise.resolve();
    }
    const text = typeof data === "string";
    const bytes = text ? new TextEncoder().encode(data) : new Uint8Array(data);
    const out = this.router.received(attachment.id, bytes, text);
    this.save();
    return this.deliver(out);
  }

  // `ws` closed. Idempotent.
  closed(ws) {
    this.settle();
    const attachment = ws.deserializeAttachment();
    if (attachment === null || attachment === undefined) {
      return Promise.resolve();
    }
    this.sockets.delete(attachment.id);
    if (ended(attachment)) {
      return Promise.resolve();
    }
    // Before anything is sent: an event that throws after this leaves no role on the socket.
    mark(ws, { id: attachment.id, gone: true });
    const out = this.router.closed(attachment.id);
    this.save();
    return this.deliver(out);
  }

  // `ws`'s client sent a close frame with `code` (webSocketClose): the service answers it, as RFC
  // 6455 §5.5.1 asks, even when its own handling throws, and before what the close sends to others
  // is out (that may wait on a credential). Cloudflare's docs say the runtime answers it itself from
  // compatibility date 2026-04-07, but on the first deploy (#513) a close without a status (1005,
  // from a browser's or Node's close()) went unanswered. The likely cause, from workerd's source: the
  // handler answered with the code it was handed, and the runtime's close() throws for 1005 (the redeploy
  // smoke on #513 confirms it). The client's reason is not echoed; nothing reads it.
  clientClosed(ws, code) {
    let sent;
    try {
      sent = this.closed(ws);
    } finally {
      try {
        ws.close(closeReplyCode(code), "");
      } catch (error) {
        this.log(`signal: answering a close (${code}) failed: ${error}`);
      }
    }
    return sent;
  }

  // `ws` failed (webSocketError): the service closes it on a best effort, and it is gone as if its client
  // closed it. The close goes out with a code the runtime can send (CLOSE_ERROR, 1011, it refuses), and a
  // socket that has failed owes its client no handshake, so a close that throws is no error.
  failed(ws) {
    const sent = this.closed(ws);
    try {
      ws.close(closeReplyCode(CLOSE_ERROR), "");
    } catch {
      // The socket is gone already, or the runtime refused the close: nothing more to send.
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

  // Sends `out`, each message after everything still waiting for its socket: at once when nothing
  // waits there and the message needs no credential. A credential's request starts at once, so
  // offers to several joiners wait for the slowest request, not for the sum, and one socket's wait
  // holds back no other socket. The promise settles once `out` is sent; the Durable Object awaits
  // it, so the object stays awake while the API answers.
  deliver(out) {
    const waits = [];
    for (const each of out) {
      const pending = this.queues.get(each.socket);
      const minted = this.turn !== null && RELAYED.has(each.message.t);
      if (pending === undefined && !minted) {
        this.send(each);
        continue;
      }
      const ready = minted ? this.withCredential(each) : each;
      const queued = (pending ?? Promise.resolve())
        .then(() => ready)
        .then((final) => this.send(final))
        .catch((error) => this.log(`signal: a delivery failed: ${error}`))
        .finally(() => {
          if (this.queues.get(each.socket) === queued) {
            this.queues.delete(each.socket);
          }
        });
      this.queues.set(each.socket, queued);
      waits.push(queued);
    }
    return Promise.all(waits).then(() => {});
  }

  // `each` ("room" to a host, "offer" to a joiner) with a credential minted for this message alone
  // added to its ICE servers. If the API fails, or the credential would push the message over the
  // cap, it goes as it would without TURN: a direct connection may still work.
  async withCredential(each) {
    const ws = this.sockets.get(each.socket);
    if (ws === undefined || ended(ws.deserializeAttachment())) {
      return each;
    }
    try {
      const servers = withTurn(each.message.ice_servers, await mint(this.turn, this.fetch, this.turnTimeoutMs));
      const relayed = { ...each.message, ice_servers: servers };
      if (codec.size(relayed) > codec.MAX_MESSAGE_BYTES) {
        throw new Error(`the ${each.message.t} with TURN is over the cap`);
      }
      return { ...each, message: relayed };
    } catch (error) {
      this.log(`signal: "${each.message.t}" goes without TURN: ${error}`);
      return each;
    }
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
    return this.deliver(out);
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
