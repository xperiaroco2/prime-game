// A smoke test of a running signalling service, the deployed Worker or a LanSignalling:
//   node tools/signal/smoke.js wss://prime-game-signal.<subdomain>.workers.dev/
// A host opens a room for one joiner; a joiner joins, a second is refused as the room is full and
// may not send an offer; an offer and an answer go through; the host leaves, and the joiner hears
// "the host left" before the service closes its socket. Exit 0 when every step passes, else 1. It
// uses Node's own WebSocket (Node 22 and newer) and no package.

const TIMEOUT_MS = 10000;

class Peer {
  constructor(name, url) {
    this.name = name;
    this.inbox = [];
    this.waiters = [];
    this.closed = false;
    this.socket = new WebSocket(url);
    this.socket.addEventListener("message", (event) => {
      this.inbox.push(JSON.parse(event.data));
      this.wake();
    });
    this.socket.addEventListener("close", () => {
      this.closed = true;
      this.wake();
    });
    this.socket.addEventListener("error", () => {
      this.closed = true;
      this.wake();
    });
  }

  wake() {
    for (const waiter of this.waiters.splice(0)) {
      waiter();
    }
  }

  async until(check, what) {
    const deadline = Date.now() + TIMEOUT_MS;
    for (;;) {
      if (check()) {
        return;
      }
      const left = deadline - Date.now();
      if (left <= 0) {
        throw new Error(`${this.name}: no ${what} within ${TIMEOUT_MS} ms`);
      }
      await new Promise((resolve) => {
        this.waiters.push(resolve);
        setTimeout(resolve, left);
      });
    }
  }

  async opened() {
    await this.until(() => this.socket.readyState === WebSocket.OPEN || this.closed, "connection");
    if (this.closed) {
      throw new Error(`${this.name}: could not connect`);
    }
  }

  send(message) {
    this.socket.send(JSON.stringify({ v: 1, ...message }));
  }

  // The next message, which must be of type `type` (and, for an error, carry `why`).
  async next(type, why) {
    await this.until(() => this.inbox.length > 0, `"${type}"`);
    const message = this.inbox.shift();
    if (message.t !== type || (why !== undefined && message.why !== why)) {
      throw new Error(`${this.name}: expected ${type}${why ? ` (${why})` : ""}, got ${JSON.stringify(message)}`);
    }
    return message;
  }
}

async function smoke(url) {
  const host = new Peer("host", url);
  await host.opened();
  host.send({ t: "open", protocol: 1, content: "0000000000000000", max: 1 });
  const room = await host.next("room");
  console.log(`ok   room ${room.code}, ICE servers ${JSON.stringify(room.ice_servers)}`);

  const joiner = new Peer("joiner", url);
  await joiner.opened();
  joiner.send({ t: "join", code: room.code });
  await joiner.next("found");
  const join = await host.next("join");
  console.log(`ok   a joiner found the room; the host heard joiner ${join.from}`);

  const second = new Peer("second joiner", url);
  await second.opened();
  second.send({ t: "join", code: room.code });
  await second.next("error", "the room is full");
  second.send({ t: "offer", to: join.from, id: 2, sdp: "v=0" });
  await second.next("error", "not allowed");
  console.log("ok   a second joiner: the room is full, and its offer is not allowed");

  host.send({ t: "offer", to: join.from, id: 2, sdp: "v=0\r\n" });
  const offer = await joiner.next("offer");
  joiner.send({ t: "answer", sdp: "v=0\r\n" });
  await host.next("answer");
  console.log(`ok   an offer (ICE servers ${JSON.stringify(offer.ice_servers)}) and an answer went through`);

  host.socket.close();
  await host.until(() => host.closed, "close of its own socket");
  await joiner.next("error", "the host left");
  const left = Date.now();
  await joiner.until(() => joiner.closed, "close after \"the host left\"");
  console.log(`ok   the host left: the joiner heard it, and its socket closed ${Date.now() - left} ms later`);
  second.socket.close();
}

const url = process.argv[2];
if (url === undefined) {
  console.error("usage: node tools/signal/smoke.js <wss:// or ws:// URL of the service>");
  process.exit(2);
}
try {
  await smoke(url);
  console.log("smoke: passed");
  process.exit(0);
} catch (error) {
  console.error(`smoke: FAILED: ${error.message}`);
  process.exit(1);
}
