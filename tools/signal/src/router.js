// The signalling service's rooms and routing (docs/ARCHITECTURE.md §4.8), with no sockets: the
// JavaScript twin of net/signal/signal_router.gd. The owner numbers its sockets, reports opened(),
// received() and closed(), and sends what each returns. Both replay the shared transcripts in
// tests/fixtures/signal/.
//
// A socket's first accepted message fixes its role: "open" makes it a room's host, "join" a
// joiner. A joiner's messages go only to its room's host, whatever they name; the host's go only to
// a joiner of its own room named in "to"; joiners never see each other. Every message sent on is
// rebuilt from its checked fields, so nothing a sender adds passes through. There is no reclaim:
// the host's socket closing closes the room and its joiners' sockets.
//
// The Durable Object forgets its memory when it hibernates, so the router's whole state is one
// record per socket (record(), restore()), which the Durable Object keeps on that socket.

import * as codec from "./codec.js";

const NONE = "none";
const HOST = "host";
const JOINER = "joiner";

// Placeholders, "not a decision" (the M6 ADR §2.4): forwarded candidates per joiner, each way.
export const MAX_CANDIDATES = 32;
// Attempts at a code no open room holds, before the service answers WHY_BUSY.
export const CODE_ATTEMPTS = 16;

// One message for one socket, and whether the service closes that socket after it.
function outgoing(socket, message, close = false) {
  return { socket, message, close };
}

export class SignalRouter {
  // `iceServers`: what "room" and every "offer" carry (STUN from the configuration, E58).
  // `nextCode`: returns a candidate code, codec.randomCode in service, a fixed list in the
  // transcripts.
  constructor(iceServers, nextCode) {
    this.iceServers = structuredClone(iceServers);
    this.nextCode = nextCode;
    // Socket -> {role, code, number, up, down}.
    this.peers = new Map();
    // Code -> {host, protocol, content, max, closed, next, joiners: Map(number -> socket)}.
    this.rooms = new Map();
    // Sockets whose record() changed since takeChanged().
    this.changed = new Set();
  }

  // A new socket. Numbers are never reused while the router may still hold one: a reused number
  // would inherit the old socket's place in a room.
  opened(socket) {
    if (this.peers.has(socket)) {
      throw new Error(`signal: socket ${socket} opened twice`);
    }
    this.peers.set(socket, { role: NONE, code: "", number: 0, up: 0, down: 0 });
    this.changed.add(socket);
  }

  roomCount() {
    return this.rooms.size;
  }

  // What the service sends for a message from `socket`: `bytes` (a Uint8Array) of a text message
  // (`text` true) or a binary one.
  received(socket, bytes, text = true) {
    const out = [];
    const peer = this.peers.get(socket);
    if (peer === undefined) {
      return out;
    }
    let side = codec.Side.UNSET;
    if (peer.role === HOST) {
      side = codec.Side.HOST;
    } else if (peer.role === JOINER) {
      side = codec.Side.JOINER;
    }
    if (!text) {
      out.push(this.error(socket, codec.WHY_BAD));
      return out;
    }
    const decoded = codec.decode(bytes, side);
    if (decoded.why !== undefined) {
      out.push(this.error(socket, decoded.why));
      return out;
    }
    switch (peer.role) {
      case NONE:
        if (decoded.type === "open") {
          this.open(socket, peer, decoded.fields, out);
        } else {
          this.join(socket, peer, decoded.fields, out);
        }
        break;
      case HOST:
        this.fromHost(socket, peer, decoded, out);
        break;
      case JOINER:
        this.fromJoiner(peer, decoded, out);
        break;
    }
    // What the service adds ("from", its ICE servers) can push a message at the cap over it, and
    // the receiver would drop it unread: the sender hears "too large" instead.
    for (const each of out) {
      if (each.socket !== socket && codec.size(each.message) > codec.MAX_MESSAGE_BYTES) {
        return [this.error(socket, codec.WHY_TOO_LARGE)];
      }
    }
    return out;
  }

  // What the service sends when `socket` went away. Idempotent.
  closed(socket) {
    const out = [];
    const peer = this.peers.get(socket);
    this.peers.delete(socket);
    this.changed.delete(socket);
    if (peer === undefined || !this.rooms.has(peer.code)) {
      return out;
    }
    const room = this.rooms.get(peer.code);
    if (peer.role === JOINER) {
      room.joiners.delete(peer.number);
    } else if (peer.role === HOST) {
      this.rooms.delete(peer.code);
      for (const joiner of room.joiners.values()) {
        this.peers.delete(joiner);
        this.changed.delete(joiner);
        out.push(this.error(joiner, codec.WHY_HOST_LEFT, true));
      }
    }
    return out;
  }

  // What the router keeps for `socket`, as structured-clone data, or null when it holds none.
  record(socket) {
    const peer = this.peers.get(socket);
    if (peer === undefined) {
      return null;
    }
    const record = { ...peer };
    if (peer.role === HOST) {
      const room = this.rooms.get(peer.code);
      record.room = {
        protocol: room.protocol,
        content: room.content,
        max: room.max,
        closed: room.closed,
        next: room.next,
      };
    }
    return record;
  }

  // The sockets whose record() changed since the last call, and forgets them.
  takeChanged() {
    const changed = [...this.changed];
    this.changed.clear();
    return changed;
  }

  // A router holding what `records` ([socket, record] pairs from record()) describe.
  static restore(iceServers, nextCode, records) {
    const router = new SignalRouter(iceServers, nextCode);
    for (const [socket, record] of records) {
      const { room, ...peer } = record;
      router.peers.set(socket, peer);
      if (peer.role === HOST) {
        router.rooms.set(peer.code, { ...room, host: socket, joiners: new Map() });
      }
    }
    // A room's joiners in the order they joined, which is the order of their numbers: the host
    // leaving tells them in that order.
    const joiners = records.filter(([, record]) => record.role === JOINER);
    joiners.sort(([, a], [, b]) => a.number - b.number);
    for (const [socket, record] of joiners) {
      const room = router.rooms.get(record.code);
      if (room === undefined) {
        // Its host's record was lost: the room is gone, and so is the joiner's place in it.
        router.peers.delete(socket);
        continue;
      }
      room.joiners.set(record.number, socket);
    }
    return router;
  }

  open(socket, peer, fields, out) {
    let code = "";
    for (let attempt = 0; attempt < CODE_ATTEMPTS; attempt++) {
      const candidate = this.nextCode();
      if (codec.isCode(candidate) && !this.rooms.has(candidate)) {
        code = candidate;
        break;
      }
    }
    if (code === "") {
      out.push(this.error(socket, codec.WHY_BUSY));
      return;
    }
    this.rooms.set(code, {
      host: socket,
      protocol: fields.protocol,
      content: fields.content,
      max: fields.max,
      closed: false,
      next: 1,
      joiners: new Map(),
    });
    peer.role = HOST;
    peer.code = code;
    this.changed.add(socket);
    out.push(this.send(socket, "room", { code, ice_servers: structuredClone(this.iceServers) }));
  }

  join(socket, peer, fields, out) {
    const code = fields.code;
    const room = this.rooms.get(code);
    if (room === undefined) {
      out.push(this.error(socket, codec.WHY_NO_ROOM));
      return;
    }
    if (room.closed) {
      out.push(this.error(socket, codec.WHY_STARTED));
      return;
    }
    if (room.joiners.size >= room.max) {
      out.push(this.error(socket, codec.WHY_FULL));
      return;
    }
    peer.role = JOINER;
    peer.code = code;
    peer.number = room.next;
    room.next += 1;
    room.joiners.set(peer.number, socket);
    this.changed.add(socket);
    this.changed.add(room.host);
    out.push(this.send(socket, "found", { protocol: room.protocol, content: room.content }));
    out.push(this.send(room.host, "join", { from: peer.number }));
  }

  fromHost(socket, peer, decoded, out) {
    const room = this.rooms.get(peer.code);
    const fields = decoded.fields;
    switch (decoded.type) {
      case "close":
        room.closed = true;
        this.changed.add(socket);
        return;
      case "reopen":
        room.closed = false;
        this.changed.add(socket);
        return;
    }
    const to = fields.to;
    if (!room.joiners.has(to)) {
      out.push(this.error(socket, codec.WHY_NO_JOINER));
      return;
    }
    const joinerSocket = room.joiners.get(to);
    const joiner = this.peers.get(joinerSocket);
    if (decoded.type === "offer") {
      const offer = { id: fields.id, sdp: fields.sdp, ice_servers: structuredClone(this.iceServers) };
      out.push(this.send(joinerSocket, "offer", offer));
      return;
    }
    if (joiner.down >= MAX_CANDIDATES) {
      out.push(this.error(socket, codec.WHY_CANDIDATES));
      return;
    }
    joiner.down += 1;
    this.changed.add(joinerSocket);
    const candidate = { mid: fields.mid, index: fields.index, cand: fields.cand };
    out.push(this.send(joinerSocket, "candidate", candidate));
  }

  // A joiner's message goes to its room's host and nowhere else, whatever it names.
  fromJoiner(peer, decoded, out) {
    const room = this.rooms.get(peer.code);
    const fields = decoded.fields;
    const joinerSocket = room.joiners.get(peer.number);
    if (decoded.type === "answer") {
      out.push(this.send(room.host, "answer", { from: peer.number, sdp: fields.sdp }));
      return;
    }
    if (peer.up >= MAX_CANDIDATES) {
      out.push(this.error(joinerSocket, codec.WHY_CANDIDATES));
      return;
    }
    peer.up += 1;
    this.changed.add(joinerSocket);
    const candidate = { from: peer.number, mid: fields.mid, index: fields.index, cand: fields.cand };
    out.push(this.send(room.host, "candidate", candidate));
  }

  send(socket, type, fields) {
    return outgoing(socket, { t: type, v: codec.VERSION, ...fields });
  }

  error(socket, why, close = false) {
    return outgoing(socket, { t: "error", v: codec.VERSION, why }, close);
  }
}
