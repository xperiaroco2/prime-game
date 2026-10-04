// The codec against the decoding cases recorded from Godot (tests/fixtures/signal/decode/), which
// tests/unit/net/signal/signal_codec_test.gd holds SignalCodec to as well, and the encoder.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import * as codec from "../src/codec.js";
import { FOLDER, canonical } from "./transcripts.js";

const encoder = new TextEncoder();
const CASES = JSON.parse(readFileSync(join(FOLDER, "decode", "decode_cases.json"), "utf8")).cases;

test("every decoding case gives what Godot gives", () => {
  const failures = [];
  for (const [index, each] of CASES.entries()) {
    let text = each.raw;
    if (each.pad_to !== undefined) {
      text += " ".repeat(each.pad_to - text.length);
    }
    const decoded = codec.decode(encoder.encode(text), codec.Side[each.side]);
    const got = decoded.why !== undefined ? { why: decoded.why } : { msg: codec.asMessage(decoded) };
    if (canonical(got) !== canonical(each.expect)) {
      failures.push(`case ${index} (${each.raw.slice(0, 60)}): expected ${canonical(each.expect)}, got ${canonical(got)}`);
    }
  }
  assert.deepEqual(failures, []);
});

test("the cases cover every reason a decode gives, and every side", () => {
  const whys = new Set(CASES.map((each) => each.expect.why).filter((why) => why !== undefined));
  assert.deepEqual([...whys].sort(), [codec.WHY_BAD, codec.WHY_NOT_ALLOWED, codec.WHY_TOO_LARGE, codec.WHY_VERSION].sort());
  assert.deepEqual([...new Set(CASES.map((each) => each.side))].sort(), Object.keys(codec.Side).sort());
});

test("a byte outside printable ASCII is a bad message", () => {
  for (const byte of [0x00, 0x08, 0x0b, 0x7f, 0x80, 0xc3, 0xff]) {
    const bytes = encoder.encode('{"t":"join","v":1,"code":"ABCDEF","x":"_"}');
    bytes[bytes.length - 3] = byte;
    assert.equal(codec.decode(bytes, codec.Side.UNSET).why, codec.WHY_BAD, `byte ${byte}`);
  }
});

test("encode writes only the type's fields and refuses what decode refuses", () => {
  const text = codec.encode(codec.Side.JOINER, "answer", { sdp: "v=0", to: 3 });
  assert.equal(text, '{"t":"answer","v":1,"sdp":"v=0"}');
  assert.throws(() => codec.encode(codec.Side.JOINER, "offer", { to: 1, id: 2, sdp: "x" }), /not allowed/);
  assert.throws(() => codec.encode(codec.Side.UNSET, "join", { code: "abcdef" }), /bad message/);
});

test("isCode takes 6 characters of the alphabet only", () => {
  assert.ok(codec.isCode("ABCDEF"));
  for (const code of ["ABCDE", "ABCDEFG", "ABCDE0", "abcdef", "ABCDEO", "ABCDE1", 123456, null]) {
    assert.equal(codec.isCode(code), false, String(code));
  }
});

test("parseGodotJson keeps a __proto__ key as an own key", () => {
  const value = codec.parseGodotJson('{"__proto__":{"code":"ABCDEF"}}');
  assert.equal(Object.getPrototypeOf(value), Object.prototype);
  assert.ok(Object.hasOwn(value, "__proto__"));
  assert.equal(value.code, undefined);
});
