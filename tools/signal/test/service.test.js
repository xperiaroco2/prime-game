// SignalService, the Durable Object's work, against fakes of the runtime's sockets and state: every
// shared transcript over fake WebSockets, also with the object rebuilt from its sockets'
// attachments after every step (hibernation), the close after the grace, and the configuration.

import assert from "node:assert/strict";
import { test } from "node:test";

import * as codec from "../src/codec.js";
import { CLOSE_GRACE_MS, DEFAULT_ICE_SERVERS, SignalService, iceServersFrom } from "../src/service.js";
import * as transcripts from "./transcripts.js";

// A hibernatable server-side WebSocket: attachments are structured clones, as the runtime keeps
// them; send after close throws, as the runtime's does.
class FakeSocket {
  constructor() {
    this.attachment = null;
    this.sent = [];
    this.closedWith = null;
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

function serviceFor(state, transcript, timers, codes) {
  return new SignalService(state, { ICE_SERVERS: transcript.config.ice_servers }, {
    nextCode: codes,
    setTimer: timers.set,
    now: () => 0,
  });
}

// Replays one transcript through SignalService; returns what went wrong, one line per wrong step.
// `rebuild`: a new SignalService from the sockets' attachments after every step; "wake" also
// between a socket leaving the runtime's list and its close event, as when the close wakes the
// object.
function replay(transcript, rebuild) {
  const failures = [];
  const state = new FakeState();
  const timers = new FakeTimers();
  const codes = transcripts.codeSource(transcript);
  let service = serviceFor(state, transcript, timers, codes);
  const sockets = new Map();
  let index = 0;
  for (const step of transcripts.stepsOf(transcript)) {
    index += 1;
    if (step.open !== undefined) {
      const ws = new FakeSocket();
      sockets.set(step.open, ws);
      service.accept(ws);
    } else if (step.gone !== undefined) {
      const ws = sockets.get(step.gone);
      ws.close(1000, "");
      state.drop(ws);
      if (rebuild === "wake") {
        service = serviceFor(state, transcript, timers, codes);
      }
      service.closed(ws);
    } else {
      service.message(sockets.get(step.from), step.raw);
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
      service.closed(ws);
    }
    if (rebuild) {
      service = serviceFor(state, transcript, timers, codes);
    }
  }
  return failures;
}

for (const [file, transcript] of transcripts.all()) {
  test(`${file} replays over fake sockets`, () => {
    assert.deepEqual(replay(transcript, false), []);
  });

  test(`${file} replays with the object rebuilt after every step`, () => {
    assert.deepEqual(replay(transcript, true), []);
  });

  test(`${file} replays with the object rebuilt as a close wakes it`, () => {
    assert.deepEqual(replay(transcript, "wake"), []);
  });
}

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

// A host with a room "ABCDEF" and one joiner in it, through a SignalService over fakes.
function hostAndJoiner() {
  const state = new FakeState();
  const timers = new FakeTimers();
  const env = { ICE_SERVERS: [] };
  const service = new SignalService(state, env, { nextCode: () => "ABCDEF", setTimer: timers.set, now: () => 5000 });
  const host = new FakeSocket();
  const joiner = new FakeSocket();
  service.accept(host);
  service.accept(joiner);
  service.message(host, codec.encode(codec.Side.UNSET, "open", { protocol: 7, content: "0123456789abcdef", max: 2 }));
  service.message(joiner, codec.encode(codec.Side.UNSET, "join", { code: "ABCDEF" }));
  host.take();
  joiner.take();
  return { state, timers, service, host, joiner, env };
}
