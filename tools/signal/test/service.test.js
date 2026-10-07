// SignalService, the Durable Object's work, against fakes of the runtime's sockets and state: every
// shared transcript over fake WebSockets, also with the object rebuilt from its sockets'
// attachments after every step (hibernation), the close after the grace, and the configuration.
// TURN (M6-10) over a fake of Cloudflare's API: the transcripts marked turn_only, the minting's
// requests, and the offer without TURN when the API fails.

import assert from "node:assert/strict";
import { test } from "node:test";

import * as codec from "../src/codec.js";
import { CLOSE_GRACE_MS, DEFAULT_ICE_SERVERS, SignalService, closeReplyCode, iceServersFrom } from "../src/service.js";
import * as turn from "../src/turn.js";
import * as transcripts from "./transcripts.js";

// A hibernatable server-side WebSocket: attachments are structured clones, as the runtime keeps
// them; send after close throws, as the runtime's does.
// `strictCodes`: close() checks its code as the Workers runtime's does (workerd's WebSocket::close,
// read for #513): before anything else, and it throws for a code it may not send. Its strict rule
// allows only 1000 and 3000-4999; its legacy rule also refuses 1004, 1005, 1006, 1015 and anything
// outside 1000-4999, so a code the strict rule allows passes both. A close after the first is a
// no-op, as the runtime's is once its close frame is out.
class FakeSocket {
  constructor({ strictCodes = false } = {}) {
    this.attachment = null;
    this.sent = [];
    this.closedWith = null;
    this.strictCodes = strictCodes;
  }

  serializeAttachment(value) {
    this.attachment = structuredClone(value);
  }

  deserializeAttachment() {
    return structuredClone(this.attachment);
  }

  send(text) {
    if (this.closedWith !== null) {
      throw new Error("send on a closed WebSocket");
    }
    this.sent.push(text);
  }

  close(code, reason) {
    if (this.strictCodes) {
      if (code !== undefined && code !== 1000 && !(code >= 3000 && code <= 4999)) {
        throw new TypeError(`Invalid WebSocket close code: ${code}.`);
      }
      if (this.closedWith !== null) {
        return;
      }
    }
    this.closedWith = { code, reason };
  }

  take() {
    const sent = this.sent;
    this.sent = [];
    return sent;
  }
}

// The Durable Object's state: the sockets it accepted and has not seen close.
class FakeState {
  constructor() {
    this.sockets = [];
  }

  acceptWebSocket(ws) {
    this.sockets.push(ws);
  }

  getWebSockets() {
    return [...this.sockets];
  }

  drop(ws) {
    this.sockets = this.sockets.filter((each) => each !== ws);
  }
}

class FakeTimers {
  constructor() {
    this.pending = [];
  }

  set = (callback, ms) => {
    this.pending.push({ callback, ms });
  };

  runAll() {
    const pending = this.pending;
    this.pending = [];
    for (const each of pending) {
      each.callback();
    }
  }
}

// Cloudflare's generate-ice-servers as a fake fetch: it answers the bodies of `minted` in order
// (null, or none left: a 500) and records every request.
class FakeTurnApi {
  constructor(minted = []) {
    this.minted = structuredClone(minted);
    this.requests = [];
  }

  fetch = async (url, init) => {
    this.requests.push({ url, init });
    const body = this.minted.length === 0 ? null : this.minted.shift();
    if (body === null) {
      return { status: 500, json: async () => ({}) };
    }
    return { status: 201, json: async () => body };
  };
}

const TEST_TOKEN = "test-token";

// The Worker's env for a transcript: its ICE servers, and the TURN secrets when it is turn_only.
function envFor(transcript) {
  const env = { ICE_SERVERS: transcript.config.ice_servers };
  if (transcripts.turnOnly(transcript)) {
    env[turn.KEY_ID] = transcript.config.turn.key_id;
    env[turn.API_TOKEN] = TEST_TOKEN;
  }
  return env;
}

// What is wrong with the requests the service made of the fake API, one line each.
function requestFailures(transcript, api) {
  if (!transcripts.turnOnly(transcript)) {
    return api.requests.length === 0 ? [] : [`${api.requests.length} TURN requests with no TURN key`];
  }
  const failures = [];
  if (api.minted.length !== 0) {
    failures.push(`${api.minted.length} minted credentials never asked for`);
  }
  const url = `${turn.API}/${transcript.config.turn.key_id}/credentials/generate-ice-servers`;
  for (const { url: got, init } of api.requests) {
    const request = {
      url: got,
      method: init.method,
      authorization: init.headers.Authorization,
      type: init.headers["Content-Type"],
      body: JSON.parse(init.body),
    };
    const expected = {
      url,
      method: "POST",
      authorization: `Bearer ${TEST_TOKEN}`,
      type: "application/json",
      body: { ttl: turn.TTL_SECONDS },
    };
    if (JSON.stringify(request) !== JSON.stringify(expected)) {
      failures.push(`request ${JSON.stringify(request)}, expected ${JSON.stringify(expected)}`);
    }
  }
  return failures;
}

function serviceFor(state, transcript, timers, codes, api) {
  return new SignalService(state, envFor(transcript), {
    nextCode: codes,
    setTimer: timers.set,
    now: () => 0,
    fetch: api.fetch,
    log: () => {},
  });
}

// Replays one transcript through SignalService; returns what went wrong, one line per wrong step.
// `rebuild`: a new SignalService from the sockets' attachments after every step; "wake" also
// between a socket leaving the runtime's list and its close event, as when the close wakes the
// object.
async function replay(transcript, rebuild) {
  const failures = [];
  const state = new FakeState();
  const timers = new FakeTimers();
  const codes = transcripts.codeSource(transcript);
  const api = new FakeTurnApi(transcript.config.turn?.minted);
  let service = serviceFor(state, transcript, timers, codes, api);
  const sockets = new Map();
  let index = 0;
  for (const step of transcripts.stepsOf(transcript)) {
    index += 1;
    if (step.open !== undefined) {
      const ws = new FakeSocket();
      sockets.set(step.open, ws);
      await service.accept(ws);
    } else if (step.gone !== undefined) {
      const ws = sockets.get(step.gone);
      ws.close(1000, "");
      state.drop(ws);
      if (rebuild === "wake") {
        service = serviceFor(state, transcript, timers, codes, api);
      }
      await service.closed(ws);
    } else {
      await service.message(sockets.get(step.from), step.raw);
    }
    const got = [];
    // The sockets in the order the step's expectation names them, then the rest: a step's sends
    // are compared per socket in order, and across sockets by the expected order.
    const order = [...new Set([...(step.expect ?? []).map((each) => each.to), ...sockets.keys()])];
    for (const name of order) {
      const ws = sockets.get(name);
      for (const text of ws.take()) {
        const close = ws.deserializeAttachment()?.closing !== undefined;
        got.push(transcripts.line(name, JSON.parse(text), close));
      }
    }
    const expected = transcripts.expectedLines(step);
    if (JSON.stringify(got) !== JSON.stringify(expected)) {
      failures.push(`step ${index}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(got)}`);
    }
    // Every close the step asked for is due after the grace, and happens.
    const closes = (step.expect ?? []).filter((each) => each.close).length;
    if (timers.pending.length !== closes || timers.pending.some((each) => each.ms !== CLOSE_GRACE_MS)) {
      failures.push(`step ${index}: ${timers.pending.length} closes due, expected ${closes}`);
    }
    timers.runAll();
    for (const each of step.expect ?? []) {
      const ws = sockets.get(each.to);
      if (!each.close) {
        continue;
      }
      if (ws.closedWith?.code !== 1000) {
        failures.push(`step ${index}: ${each.to} is not closed`);
      }
      // Its client answers the close: the runtime forgets the socket and reports it.
      state.drop(ws);
      await service.closed(ws);
    }
    if (rebuild) {
      service = serviceFor(state, transcript, timers, codes, api);
    }
  }
  return [...failures, ...requestFailures(transcript, api)];
}

for (const [file, transcript] of transcripts.all()) {
  test(`${file} replays over fake sockets`, async () => {
    assert.deepEqual(await replay(transcript, false), []);
  });

  test(`${file} replays with the object rebuilt after every step`, async () => {
    assert.deepEqual(await replay(transcript, true), []);
  });

  test(`${file} replays with the object rebuilt as a close wakes it`, async () => {
    assert.deepEqual(await replay(transcript, "wake"), []);
  });
}

test("a transcript is turn_only exactly when its config has TURN answers", () => {
  for (const [file, transcript] of transcripts.all()) {
    assert.equal(transcripts.turnOnly(transcript), transcript.config.turn !== undefined, file);
  }
});

test("a socket that closed keeps no role after a wake, even while the runtime still lists it", () => {
  const { state, timers, service, host, joiner, env } = hostAndJoiner();
  service.closed(joiner);
  service.closed(host);
  const woken = new SignalService(state, env, { nextCode: () => "ABCDEF", setTimer: timers.set });
  assert.equal(woken.roomCount(), 0);
  const newcomer = new FakeSocket();
  woken.accept(newcomer);
  woken.message(newcomer, codec.encode(codec.Side.UNSET, "join", { code: "ABCDEF" }));
  assert.deepEqual(newcomer.take().map((text) => JSON.parse(text).why), [codec.WHY_NO_ROOM]);
  woken.message(host, codec.encode(codec.Side.HOST, "offer", { to: 1, id: 2, sdp: "v=0" }));
  assert.deepEqual([...host.take(), ...joiner.take()], []);
});

test("a failed socket is gone and closed", () => {
  const { state, timers, service, host, joiner, env } = hostAndJoiner();
  service.failed(joiner);
  assert.equal(joiner.closedWith.code, 1011);
  assert.deepEqual(joiner.deserializeAttachment(), { id: 2, gone: true });
  new SignalService(state, env, { setTimer: timers.set }).message(
    host,
    codec.encode(codec.Side.HOST, "offer", { to: 1, id: 2, sdp: "v=0" }),
  );
  assert.deepEqual(host.take().map((text) => JSON.parse(text).why), [codec.WHY_NO_JOINER]);
  assert.deepEqual(joiner.take(), []);
});

// #513: the deployed Worker never answered a host's close without a status (Node's and a browser's
// close() with no code; the handler gets 1005), so the client waited for its close for ever.
test("a client's close without a status is answered, and the joiner hears the host left", async () => {
  const { state, timers, service, host, joiner } = hostAndJoiner({ strictCodes: true });
  state.drop(host);
  await service.clientClosed(host, 1005);
  assert.deepEqual(host.closedWith, { code: 1000, reason: "" });
  assert.deepEqual(joiner.take().map((text) => JSON.parse(text).why), [codec.WHY_HOST_LEFT]);
  assert.deepEqual(timers.pending.map((each) => each.ms), [CLOSE_GRACE_MS]);
  timers.runAll();
  assert.equal(joiner.closedWith.code, 1000);
});

test("every close a client may send is answered with a code the runtime sends", async () => {
  const answers = { 1000: 1000, 1001: 1000, 1005: 1000, 1006: 1000, 1011: 1000, 3000: 3000, 4999: 4999 };
  for (const [code, answer] of Object.entries(answers)) {
    const { state, service, host, joiner } = hostAndJoiner({ strictCodes: true });
    state.drop(host);
    await service.clientClosed(host, Number(code));
    assert.deepEqual(host.closedWith, { code: answer, reason: "" }, `a close with ${code}`);
    assert.deepEqual(joiner.take().map((text) => JSON.parse(text).why), [codec.WHY_HOST_LEFT], `a close with ${code}`);
  }
});

test("closeReplyCode keeps 1000 and 3000-4999 and turns every other code into 1000", () => {
  for (const code of [1000, 3000, 4000, 4999]) {
    assert.equal(closeReplyCode(code), code);
  }
  for (const code of [1001, 1004, 1005, 1006, 1011, 1015, 2999, 5000, 0, -1, undefined, null, NaN, 3000.5, "3000"]) {
    assert.equal(closeReplyCode(code), 1000, String(code));
  }
});

test("a close the runtime answered already is no error, and the joiner hears it once", async () => {
  const { state, service, host, joiner } = hostAndJoiner({ strictCodes: true });
  host.close(1000, "");
  state.drop(host);
  await service.clientClosed(host, 1000);
  assert.deepEqual(host.closedWith, { code: 1000, reason: "" });
  assert.deepEqual(joiner.take().map((text) => JSON.parse(text).why), [codec.WHY_HOST_LEFT]);
});

test("a close is answered even when the service's handling of it throws", () => {
  const { state, service, host } = hostAndJoiner({ strictCodes: true });
  state.drop(host);
  host.deserializeAttachment = () => {
    throw new Error("a broken attachment");
  };
  assert.throws(() => service.clientClosed(host, 1005), /a broken attachment/);
  assert.deepEqual(host.closedWith, { code: 1000, reason: "" });
});

test("an answer to a close that fails is logged, and the close still goes through", async () => {
  const lines = [];
  const { state, service, host, joiner } = hostAndJoiner({}, (text) => lines.push(text));
  state.drop(host);
  host.close = () => {
    throw new Error("the socket is gone");
  };
  await service.clientClosed(host, 1005);
  assert.deepEqual(lines, ["signal: answering a close (1005) failed: Error: the socket is gone"]);
  assert.deepEqual(joiner.take().map((text) => JSON.parse(text).why), [codec.WHY_HOST_LEFT]);
});

test("joiners whose host went away while the object was out of memory hear it at the next event", () => {
  const { state, timers, host, joiner, env } = hostAndJoiner();
  state.drop(host);
  const woken = new SignalService(state, env, { setTimer: timers.set, now: () => 0 });
  assert.deepEqual(joiner.sent, []);
  woken.accept(new FakeSocket());
  assert.deepEqual(joiner.take().map((text) => JSON.parse(text).why), [codec.WHY_HOST_LEFT]);
  assert.deepEqual(joiner.deserializeAttachment(), { id: 2, closing: CLOSE_GRACE_MS });
  timers.runAll();
  assert.equal(joiner.closedWith.code, 1000);
  woken.message(joiner, codec.encode(codec.Side.JOINER, "answer", { sdp: "v=0" }));
  assert.deepEqual(joiner.take(), []);
});

test("a socket the service is closing is ignored, and its close is no event", () => {
  const { state, timers, service, host, joiner } = hostAndJoiner();
  host.close(1000, "");
  state.drop(host);
  service.closed(host);
  assert.deepEqual(joiner.take().map((text) => JSON.parse(text).why), [codec.WHY_HOST_LEFT]);
  service.message(joiner, codec.encode(codec.Side.JOINER, "answer", { sdp: "v=0" }));
  service.closed(joiner);
  assert.deepEqual(joiner.take(), []);
  assert.equal(timers.pending.length, 1);
  timers.runAll();
  assert.equal(joiner.closedWith.code, 1000);
});

test("a close lost with the object's memory happens when the object wakes", () => {
  const { state, timers, host, joiner, env } = hostAndJoiner();
  let service = new SignalService(state, env, { setTimer: timers.set, now: () => 5000 });
  host.close(1000, "");
  state.drop(host);
  service.closed(host);
  timers.pending = [];
  service = new SignalService(state, env, { setTimer: timers.set, now: () => 5400 });
  assert.deepEqual(timers.pending.map((each) => each.ms), [CLOSE_GRACE_MS - 400]);
  service = new SignalService(state, env, { setTimer: timers.set, now: () => 9000 });
  assert.equal(timers.pending.at(-1).ms, 0);
  timers.runAll();
  assert.equal(joiner.closedWith.code, 1000);
});

test("a socket the service ends is marked closing even when the send fails", () => {
  const { state, service, host, joiner } = hostAndJoiner();
  joiner.close(1000, "");
  state.drop(host);
  service.closed(host);
  assert.equal(joiner.deserializeAttachment().closing, 5000 + CLOSE_GRACE_MS);
});

test("a send to a socket its client closed is skipped", () => {
  const { service, host, joiner } = hostAndJoiner();
  joiner.close(1000, "");
  service.message(host, codec.encode(codec.Side.HOST, "offer", { to: 1, id: 2, sdp: "v=0" }));
  assert.deepEqual(joiner.sent, []);
});

test("a binary message is a bad message", () => {
  const { service, host } = hostAndJoiner();
  service.message(host, new TextEncoder().encode('{"t":"close","v":1}').buffer);
  assert.deepEqual(host.take().map((text) => JSON.parse(text).why), [codec.WHY_BAD]);
});

test("a text message is checked as its UTF-8 bytes", () => {
  const { service, host } = hostAndJoiner();
  service.message(host, '{"t":"close","v":1,"x":"é"}');
  assert.deepEqual(host.take().map((text) => JSON.parse(text).why), [codec.WHY_BAD]);
});

test("random codes are codes, and socket numbers go on after a wake", () => {
  const state = new FakeState();
  const env = {};
  let service = new SignalService(state, env);
  const host = new FakeSocket();
  service.accept(host);
  service.message(host, codec.encode(codec.Side.UNSET, "open", { protocol: 7, content: "0123456789abcdef", max: 2 }));
  const room = JSON.parse(host.take()[0]);
  assert.ok(codec.isCode(room.code));
  assert.deepEqual(room.ice_servers, DEFAULT_ICE_SERVERS);
  service = new SignalService(state, env);
  const joiner = new FakeSocket();
  service.accept(joiner);
  assert.equal(joiner.deserializeAttachment().id, 2);
});

test("randomCode draws again above 247, so every character is equally likely", () => {
  const bytes = [[248, 255, 0, 30, 31, 61], [62, 247]];
  const code = codec.randomCode(() => bytes.shift());
  assert.equal(code, "2Z2Z2Z");
});

test("the ICE servers come from the configuration, checked", () => {
  assert.deepEqual(iceServersFrom({}), DEFAULT_ICE_SERVERS);
  assert.deepEqual(iceServersFrom({ ICE_SERVERS: "" }), DEFAULT_ICE_SERVERS);
  const turn = [{ urls: ["turn:example.org:3478"], username: "u", credential: "c", extra: 1 }];
  assert.deepEqual(iceServersFrom({ ICE_SERVERS: turn }), [
    { urls: ["turn:example.org:3478"], username: "u", credential: "c" },
  ]);
  assert.deepEqual(iceServersFrom({ ICE_SERVERS: JSON.stringify([]) }), []);
  assert.throws(() => iceServersFrom({ ICE_SERVERS: [{ urls: ["http://example.org"] }] }), /ICE_SERVERS/);
  assert.throws(() => iceServersFrom({ ICE_SERVERS: "[" }));
});

// A host with a room "ABCDEF" and one joiner in it, through a SignalService over fakes. `sockets`:
// FakeSocket's options for both; `log`: the service's log.
function hostAndJoiner(sockets = {}, log = () => {}) {
  const state = new FakeState();
  const timers = new FakeTimers();
  const env = { ICE_SERVERS: [] };
  const service = new SignalService(state, env, { nextCode: () => "ABCDEF", setTimer: timers.set, now: () => 5000, log });
  const host = new FakeSocket(sockets);
  const joiner = new FakeSocket(sockets);
  service.accept(host);
  service.accept(joiner);
  service.message(host, codec.encode(codec.Side.UNSET, "open", { protocol: 7, content: "0123456789abcdef", max: 2 }));
  service.message(joiner, codec.encode(codec.Side.UNSET, "join", { code: "ABCDEF" }));
  host.take();
  joiner.take();
  return { state, timers, service, host, joiner, env };
}

// Cloudflare's API answering a fresh credential for `url`s; `wait` (a promise), when given, holds
// every answer back until it settles.
function credentials(urls, wait = null) {
  let count = 0;
  return async () => {
    count += 1;
    const user = `u${count}`;
    if (wait !== null) {
      await wait;
    }
    return { status: 201, json: async () => ({ iceServers: [{ urls, username: user, credential: "c" }] }) };
  };
}

function answering(body, status = 201) {
  return async () => ({ status, json: async () => structuredClone(body) });
}

const TURN_URLS = ["turn:t.example:3478?transport=udp", "turns:t.example:443?transport=tcp"];
const OPEN = codec.encode(codec.Side.UNSET, "open", { protocol: 7, content: "0123456789abcdef", max: 2 });
const OFFER = codec.encode(codec.Side.HOST, "offer", { to: 1, id: 2, sdp: "v=0" });
const CANDIDATE = codec.encode(codec.Side.HOST, "candidate", { to: 1, mid: "0", index: 0, cand: "c" });

// A host with a room "ABCDEF" and one joiner, with a TURN key and `api` as Cloudflare's API; the
// room's own credential is taken.
async function turnHostAndJoiner(api, options = {}) {
  const state = new FakeState();
  const env = { ICE_SERVERS: [], [turn.KEY_ID]: "k", [turn.API_TOKEN]: "t", ...options.env };
  const logged = options.logged ?? [];
  const service = new SignalService(state, env, {
    nextCode: () => "ABCDEF",
    setTimer: () => {},
    fetch: api,
    log: (text) => logged.push(text),
    turnTimeoutMs: options.turnTimeoutMs,
  });
  const host = new FakeSocket();
  const joiner = new FakeSocket();
  await service.accept(host);
  await service.accept(joiner);
  await service.message(host, OPEN);
  await service.message(joiner, codec.encode(codec.Side.UNSET, "join", { code: "ABCDEF" }));
  host.take();
  joiner.take();
  return { service, host, joiner, logged };
}

function usersIn(servers) {
  return servers.filter((each) => each.username !== undefined).map((each) => each.username);
}

test("with no TURN key the service never calls the API, and room and offers carry the configured servers", async () => {
  const state = new FakeState();
  let calls = 0;
  const options = { nextCode: () => "ABCDEF", fetch: async () => calls++ };
  const service = new SignalService(state, { ICE_SERVERS: [] }, options);
  const host = new FakeSocket();
  const joiner = new FakeSocket();
  service.accept(host);
  service.accept(joiner);
  service.message(host, OPEN);
  service.message(joiner, codec.encode(codec.Side.UNSET, "join", { code: "ABCDEF" }));
  service.message(host, OFFER);
  // All of it sent at once, as before M6-10.
  assert.deepEqual(JSON.parse(host.take()[0]).ice_servers, []);
  assert.deepEqual(JSON.parse(joiner.take()[1]).ice_servers, []);
  assert.equal(calls, 0);
});

test("room and an offer go without TURN when the API fails, and the failure is logged", async () => {
  for (const api of [
    answering({}, 500),
    answering({ iceServers: "x" }),
    answering({ iceServers: [{ urls: ["stun:s:1"] }] }),
    answering({ iceServers: [{ urls: TURN_URLS }] }),
    async () => {
      throw new Error("network down");
    },
  ]) {
    const { service, host, joiner, logged } = await turnHostAndJoiner(api);
    await service.message(host, OFFER);
    assert.deepEqual(JSON.parse(joiner.take()[0]).ice_servers, []);
    assert.deepEqual(logged.map((text) => /"(room|offer)" goes without TURN/.exec(text)?.[1]), ["room", "offer"]);
  }
});

test("an API that does not answer in time is aborted, and the offer goes without TURN", async () => {
  const api = (url, init) =>
    new Promise((resolve, reject) => init.signal.addEventListener("abort", () => reject(new Error("aborted"))));
  const { service, host, joiner, logged } = await turnHostAndJoiner(api, { turnTimeoutMs: 5 });
  await service.message(host, OFFER);
  assert.deepEqual(JSON.parse(joiner.take()[0]).ice_servers, []);
  assert.match(logged.at(-1), /"offer" goes without TURN: Error: aborted/);
});

test("what the host sends a joiner after an offer waits for that offer's credential", async () => {
  let release;
  const gate = new Promise((resolve) => (release = resolve));
  const { service, host, joiner } = await turnHostAndJoiner(credentials(TURN_URLS));
  service.fetch = credentials(TURN_URLS, gate);
  const offered = service.message(host, OFFER);
  const candidate = service.message(host, CANDIDATE);
  assert.deepEqual(joiner.sent, []);
  release();
  await Promise.all([offered, candidate]);
  assert.deepEqual(joiner.take().map((text) => JSON.parse(text).t), ["offer", "candidate"]);
  assert.equal(service.queues.size, 0);
});

test("a credential being minted holds back no other socket, and offers to several joiners mint at once", async () => {
  let release;
  const gate = new Promise((resolve) => (release = resolve));
  let asked = 0;
  const slow = credentials(TURN_URLS, gate);
  const state = new FakeState();
  const env = { ICE_SERVERS: [], [turn.KEY_ID]: "k", [turn.API_TOKEN]: "t" };
  const codes = ["AAAAAA", "BBBBBB"];
  const service = new SignalService(state, env, {
    nextCode: () => codes.shift(),
    fetch: (url, init) => {
      asked += 1;
      return slow(url, init);
    },
    log: () => {},
  });
  const [host, first, second, otherHost] = [new FakeSocket(), new FakeSocket(), new FakeSocket(), new FakeSocket()];
  for (const ws of [host, first, second, otherHost]) {
    service.accept(ws);
  }
  const roomOpened = service.message(host, OPEN);
  service.message(first, codec.encode(codec.Side.UNSET, "join", { code: "AAAAAA" }));
  service.message(second, codec.encode(codec.Side.UNSET, "join", { code: "AAAAAA" }));
  // The host's room waits on its credential; the joiners hear "found" at once.
  assert.deepEqual(host.sent, []);
  assert.deepEqual([first.take(), second.take()].map((sent) => JSON.parse(sent[0]).t), ["found", "found"]);
  const offers = [
    service.message(host, codec.encode(codec.Side.HOST, "offer", { to: 1, id: 2, sdp: "v=0" })),
    service.message(host, codec.encode(codec.Side.HOST, "offer", { to: 2, id: 3, sdp: "v=0" })),
  ];
  assert.equal(asked, 3);
  // Another room's host, with its own mint waiting, and a stranger's bad message, answered at once.
  const stranger = new FakeSocket();
  service.accept(stranger);
  service.message(stranger, "{");
  assert.deepEqual(stranger.take().map((text) => JSON.parse(text).why), [codec.WHY_BAD]);
  release();
  await Promise.all([roomOpened, ...offers]);
  assert.equal(JSON.parse(host.take()[0]).t, "room");
  assert.deepEqual(usersIn(JSON.parse(first.take()[0]).ice_servers), ["u2"]);
  assert.deepEqual(usersIn(JSON.parse(second.take()[0]).ice_servers), ["u3"]);
});

test("an offer to a joiner that left while its credential was minted is not sent", async () => {
  let release;
  const gate = new Promise((resolve) => (release = resolve));
  const { service, host, joiner } = await turnHostAndJoiner(credentials(TURN_URLS));
  service.fetch = credentials(TURN_URLS, gate);
  const offered = service.message(host, OFFER);
  joiner.close(1000, "");
  const gone = service.closed(joiner);
  release();
  await Promise.all([offered, gone]);
  assert.deepEqual(joiner.sent, []);
});

test("a credential that would push the offer over the cap leaves it out", async () => {
  // About 4 KB of TURN entries: they fit an offer with a short sdp, not one with the longest.
  const urls = Array.from({ length: 8 }, (_, i) => `turn:${"h".repeat(500)}${i}:3478`);
  assert.doesNotThrow(() => turn.withTurn([], [{ urls: urls.slice(0, 4) }, { urls: urls.slice(4) }]));
  const { service, host, joiner, logged } = await turnHostAndJoiner(credentials(urls));
  const longest = codec.encode(codec.Side.HOST, "offer", { to: 1, id: 2, sdp: "s".repeat(codec.MAX_SDP) });
  await service.message(host, longest);
  assert.deepEqual(JSON.parse(joiner.take()[0]).ice_servers, []);
  assert.match(logged.at(-1), /over the cap/);
});

test("the request asks for the configured TTL", async () => {
  const requests = [];
  const api = credentials(TURN_URLS);
  const record = (url, init) => {
    requests.push(JSON.parse(init.body));
    return api(url, init);
  };
  await turnHostAndJoiner(record, { env: { [turn.TTL_VAR]: "3600" } });
  assert.deepEqual(requests, [{ ttl: 3600 }]);
});

test("the TURN key is both secrets or neither, and its TTL a whole number of seconds up to 48 hours", () => {
  const logged = [];
  const log = (text) => logged.push(text);
  assert.equal(turn.turnFrom({}, log), null);
  assert.equal(turn.turnFrom({ [turn.KEY_ID]: "", [turn.API_TOKEN]: "" }, log), null);
  assert.deepEqual(logged, []);
  const key = { [turn.KEY_ID]: "k", [turn.API_TOKEN]: "t" };
  assert.deepEqual(turn.turnFrom(key, log), { keyId: "k", token: "t", ttl: 600 });
  // One secret alone, as between the engineer's two `secret put`: no TURN, logged.
  assert.equal(turn.turnFrom({ [turn.KEY_ID]: "k" }, log), null);
  assert.equal(turn.turnFrom({ [turn.API_TOKEN]: "t" }, log), null);
  assert.equal(logged.length, 2);
  assert.match(logged[0], /no TURN until both/);
  assert.equal(turn.turnFrom({ ...key, [turn.TTL_VAR]: 3600 }, log).ttl, 3600);
  assert.equal(turn.turnFrom({ ...key, [turn.TTL_VAR]: "7200" }, log).ttl, 7200);
  for (const bad of [0, -1, 1.5, "x", 48 * 3600 + 1]) {
    assert.throws(() => turn.turnFrom({ ...key, [turn.TTL_VAR]: bad }, log), /TURN_TTL_SECONDS/);
  }
});

test("a credential keeps only TURN URLs off port 53, at most 4 to an entry, after the configured servers", async () => {
  const urls = [
    "stun:stun.example:3478",
    "turn:t.example:3478?transport=udp",
    "turn:t.example:53?transport=udp",
    "turn:t.example:53",
    "turn:t.example:5300?transport=udp",
    "turn:t.example:443?transport=udp",
    "turn:t.example:80?transport=tcp",
    "turns:t.example:443?transport=tcp",
  ];
  const body = { iceServers: [{ urls: ["stun:stun.example:3478"] }, { urls, username: "u", credential: "c" }] };
  const minted = await turn.mint({ keyId: "k", token: "t", ttl: 600 }, answering(body));
  const kept = [
    "turn:t.example:3478?transport=udp",
    "turn:t.example:5300?transport=udp",
    "turn:t.example:443?transport=udp",
    "turn:t.example:80?transport=tcp",
  ];
  assert.deepEqual(minted, [
    { urls: kept, username: "u", credential: "c" },
    { urls: ["turns:t.example:443?transport=tcp"], username: "u", credential: "c" },
  ]);
  const base = [{ urls: ["stun:stun.cloudflare.com:3478"] }];
  const servers = turn.withTurn(base, Array.from({ length: 9 }, () => minted[1]));
  assert.equal(servers.length, codec.MAX_ICE_SERVERS);
  assert.deepEqual(servers[0], base[0]);
  const tooLong = [{ urls: ["turn:a:1"], username: "x".repeat(codec.MAX_ICE_TEXT + 1) }];
  assert.throws(() => turn.withTurn(base, tooLong), /drop/);
  const full = Array.from({ length: codec.MAX_ICE_SERVERS }, () => base[0]);
  assert.throws(() => turn.withTurn(full, minted), /no room for TURN/);
});
