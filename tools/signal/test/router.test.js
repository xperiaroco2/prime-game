// SignalRouter replays every shared transcript (tests/fixtures/signal/), as
// tests/unit/net/signal/signal_router_test.gd does for the GDScript router: after each step,
// exactly the expected messages to exactly the expected sockets, in order. The forged ones are the
// M6 ADR §5 check: a joiner's offer, a candidate with a "to", close and reopen never reach another
// joiner, and change no room.

import assert from "node:assert/strict";
import { test } from "node:test";

import * as codec from "../src/codec.js";
import { SignalRouter } from "../src/router.js";
import * as transcripts from "./transcripts.js";

const encoder = new TextEncoder();

test("there is a transcript per flow and per forged type", () => {
  assert.deepEqual([...transcripts.all().keys()], transcripts.NAMES);
});

for (const [file, transcript] of transcripts.all()) {
  if (transcripts.turnOnly(transcript)) {
    // The router never mints: service.test.js replays it.
    continue;
  }
  test(`${file} replays`, () => {
    assert.deepEqual(replay(transcript, false), []);
  });

  test(`${file} replays with the router rebuilt from its records after every step`, () => {
    assert.deepEqual(replay(transcript, true), []);
  });
}

test("a binary message is a bad message", () => {
  const router = new SignalRouter([], () => "ABCDEF");
  router.opened(1);
  const text = codec.encode(codec.Side.UNSET, "join", { code: "ABCDEF" });
  const out = router.received(1, encoder.encode(text), false);
  assert.equal(out.length, 1);
  assert.equal(out[0].message.why, codec.WHY_BAD);
});

test("a message from an unknown or closed socket is ignored", () => {
  const router = new SignalRouter([], () => "ABCDEF");
  const text = encoder.encode(codec.encode(codec.Side.UNSET, "join", { code: "ABCDEF" }));
  assert.deepEqual(router.received(7, text), []);
  router.opened(7);
  router.closed(7);
  assert.deepEqual(router.received(7, text), []);
  assert.deepEqual(router.closed(7), []);
});

test("no free code is an error and no room", () => {
  const router = new SignalRouter([], () => "ABCDEF");
  const open = { protocol: 7, content: "0123456789abcdef", max: 9 };
  const text = encoder.encode(codec.encode(codec.Side.UNSET, "open", open));
  router.opened(1);
  router.opened(2);
  assert.equal(router.received(1, text)[0].message.t, "room");
  assert.equal(router.received(2, text)[0].message.why, codec.WHY_BUSY);
  assert.equal(router.roomCount(), 1);
});

test("a socket opened twice throws", () => {
  const router = new SignalRouter([], () => "ABCDEF");
  router.opened(1);
  assert.throws(() => router.opened(1));
});

test("a joiner whose host's record is lost is dropped on restore", () => {
  const router = SignalRouter.restore([], () => "", [
    [2, { role: "joiner", code: "ABCDEF", number: 1, up: 0, down: 0 }],
  ]);
  assert.equal(router.record(2), null);
  assert.equal(router.roomCount(), 0);
});

// Replays one transcript; returns what went wrong, one line per wrong step. `rebuild`: after every
// step, a new router from the old one's records, as the Durable Object after hibernation.
function replay(transcript, rebuild) {
  const failures = [];
  const ice = transcript.config.ice_servers;
  const codes = transcripts.codeSource(transcript);
  let router = new SignalRouter(ice, codes);
  const sockets = new Map();
  const names = new Map();
  let index = 0;
  for (const step of transcripts.stepsOf(transcript)) {
    index += 1;
    let out = [];
    if (step.open !== undefined) {
      const socket = sockets.size + 1;
      sockets.set(step.open, socket);
      names.set(socket, step.open);
      router.opened(socket);
    } else if (step.gone !== undefined) {
      out = router.closed(sockets.get(step.gone));
    } else {
      out = router.received(sockets.get(step.from), encoder.encode(step.raw));
    }
    const got = out.map((each) => transcripts.line(names.get(each.socket), each.message, each.close));
    const expected = transcripts.expectedLines(step);
    if (JSON.stringify(got) !== JSON.stringify(expected)) {
      failures.push(`step ${index}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(got)}`);
    }
    if (rebuild) {
      const records = [];
      for (const socket of names.keys()) {
        const record = router.record(socket);
        if (record !== null) {
          records.push([socket, structuredClone(record)]);
        }
      }
      router = SignalRouter.restore(ice, codes, records);
    }
  }
  return failures;
}
