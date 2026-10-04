// The signalling protocol's messages (docs/ARCHITECTURE.md §4.8): the JavaScript twin of
// net/signal/signal_codec.gd. decode() checks a message from one side against that side's types and
// fields and returns only the fields it knows, rebuilt, so nothing a sender adds is ever forwarded.
// The shared transcripts (tests/fixtures/signal/) and decoding cases (tests/fixtures/signal/decode/)
// hold both to the same results.
//
// JSON is read by parseGodotJson(), not JSON.parse: Godot's parser accepts what JSON.parse refuses
// (a trailing comma, a leading zero, "1.", a raw tab or line break inside a string) and refuses what
// it accepts (a lone UTF-16 surrogate, nesting deeper than 1024), and a message must get the same
// answer from the Worker as from LanSignalling.

export const Side = Object.freeze({
  // To the service, from a socket that has no role yet: only "open" and "join".
  UNSET: 0,
  // To the service, from a room's host.
  HOST: 1,
  // To the service, from a joiner.
  JOINER: 2,
  // From the service to a room's host.
  TO_HOST: 3,
  // From the service to a joiner.
  TO_JOINER: 4,
});

export const VERSION = 1;
// Placeholders, "not a decision" (the M6 ADR §2.4).
export const MAX_MESSAGE_BYTES = 16384;
export const CODE_LENGTH = 6;
// 31 characters that cannot be misread: no 0, O, 1, I or L.
export const CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
export const MAX_ICE_SERVERS = 8;
export const MAX_ICE_URLS = 4;
export const MAX_ICE_TEXT = 512;
export const MAX_SDP = 12288;
export const MAX_CAND = 1024;
export const MAX_MID = 64;
export const MAX_WHY = 64;
export const MAX_JOINERS = 255;
export const MAX_ID = 2147483647;
// Godot's Variant::MAX_RECURSION_DEPTH: a value nested deeper fails its JSON parse.
export const MAX_JSON_DEPTH = 1024;

export const WHY_VERSION = "update the game";
export const WHY_BAD = "bad message";
export const WHY_TOO_LARGE = "too large";
export const WHY_NOT_ALLOWED = "not allowed";
export const WHY_NO_ROOM = "no such room";
export const WHY_STARTED = "the match has started";
export const WHY_FULL = "the room is full";
export const WHY_NO_JOINER = "no such joiner";
export const WHY_CANDIDATES = "too many candidates";
export const WHY_HOST_LEFT = "the host left";
export const WHY_BUSY = "no free code";

const U16 = "u16";
const ID = "id";
const MAX = "max";
const CODE = "code";
const CONTENT = "content";
const SDP = "sdp";
const MID = "mid";
const INDEX = "index";
const CAND = "cand";
const ICE = "ice";
const WHY = "why";

// Side -> type -> field -> kind, fields in the GDScript table's order. Every field is required.
const TYPES = new Map([
  [Side.UNSET, new Map([
    ["open", [["protocol", U16], ["content", CONTENT], ["max", MAX]]],
    ["join", [["code", CODE]]],
  ])],
  [Side.HOST, new Map([
    ["offer", [["to", ID], ["id", ID], ["sdp", SDP]]],
    ["candidate", [["to", ID], ["mid", MID], ["index", INDEX], ["cand", CAND]]],
    ["close", []],
    ["reopen", []],
  ])],
  [Side.JOINER, new Map([
    ["answer", [["sdp", SDP]]],
    ["candidate", [["mid", MID], ["index", INDEX], ["cand", CAND]]],
  ])],
  [Side.TO_HOST, new Map([
    ["room", [["code", CODE], ["ice_servers", ICE]]],
    ["join", [["from", ID]]],
    ["answer", [["from", ID], ["sdp", SDP]]],
    ["candidate", [["from", ID], ["mid", MID], ["index", INDEX], ["cand", CAND]]],
    ["error", [["why", WHY]]],
  ])],
  [Side.TO_JOINER, new Map([
    ["found", [["protocol", U16], ["content", CONTENT]]],
    ["offer", [["id", ID], ["sdp", SDP], ["ice_servers", ICE]]],
    ["candidate", [["mid", MID], ["index", INDEX], ["cand", CAND]]],
    ["error", [["why", WHY]]],
  ])],
]);
// Every type of the protocol: one that is not the sender's is "not allowed", any other "bad".
const KNOWN_TYPES = new Set([
  "open", "room", "join", "found", "offer", "answer", "candidate", "close", "reopen", "error",
]);

// A decoded message: { type, fields } when valid, else { why } with one of the WHY_ reasons.
// `bytes` is a Uint8Array (a text message's UTF-8 bytes), `side` one of Side.
export function decode(bytes, side) {
  if (bytes.length > MAX_MESSAGE_BYTES) {
    return { why: WHY_TOO_LARGE };
  }
  if (!printable(bytes)) {
    return { why: WHY_BAD };
  }
  let raw;
  try {
    raw = parseGodotJson(String.fromCharCode(...bytes));
  } catch {
    return { why: WHY_BAD };
  }
  if (!isObject(raw)) {
    return { why: WHY_BAD };
  }
  if (integer(get(raw, "v"), 0, MAX_ID) !== VERSION) {
    return { why: WHY_VERSION };
  }
  const type = get(raw, "t");
  if (typeof type !== "string" || !KNOWN_TYPES.has(type)) {
    return { why: WHY_BAD };
  }
  const specs = TYPES.get(side).get(type);
  if (specs === undefined) {
    return { why: WHY_NOT_ALLOWED };
  }
  const fields = {};
  for (const [name, kind] of specs) {
    const value = checked(get(raw, name), kind);
    if (value === null) {
      return { why: WHY_BAD };
    }
    fields[name] = value;
  }
  return { type, fields };
}

// The whole message (type and "v" included), as the router sends it.
export function asMessage(decoded) {
  return { t: decoded.type, v: VERSION, ...decoded.fields };
}

// The text of a message of `type` with `fields` as `side` sends it, or throws when decode() would
// refuse it. Only the type's fields reach the text.
export function encode(side, type, fields) {
  const text = JSON.stringify({ t: type, v: VERSION, ...fields });
  const check = decode(new TextEncoder().encode(text), side);
  if (check.why !== undefined) {
    throw new Error(`signal: refused to encode ${type} from side ${side}: ${check.why}`);
  }
  return JSON.stringify(asMessage(check));
}

// A random room code: `randomBytes(n)` returns n random bytes (crypto.getRandomValues in service).
// Bytes from 248 up are drawn again, so each of the 31 characters is equally likely.
export function randomCode(randomBytes) {
  let code = "";
  while (code.length < CODE_LENGTH) {
    for (const byte of randomBytes(CODE_LENGTH)) {
      if (byte < 248 && code.length < CODE_LENGTH) {
        code += CODE_ALPHABET[byte % CODE_ALPHABET.length];
      }
    }
  }
  return code;
}

export function isCode(value) {
  if (typeof value !== "string" || value.length !== CODE_LENGTH) {
    return false;
  }
  for (const character of value) {
    if (!CODE_ALPHABET.includes(character)) {
      return false;
    }
  }
  return true;
}

// The bytes of `message` as the service sends it (compact JSON; every text it holds is ASCII).
export function size(message) {
  return new TextEncoder().encode(JSON.stringify(message)).length;
}

function isObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// An own key only: a GDScript Dictionary has no prototype to read "constructor" from.
function get(object, key) {
  return Object.hasOwn(object, key) ? object[key] : null;
}

function checked(value, kind) {
  switch (kind) {
    case U16:
      return integer(value, 0, 65535);
    case ID:
      return integer(value, 1, MAX_ID);
    case MAX:
      return integer(value, 1, MAX_JOINERS);
    case INDEX:
      return integer(value, 0, 255);
    case CODE:
      return isCode(value) ? value : null;
    case CONTENT:
      return typeof value === "string" && value.length === 16 && isLowerHex(value) ? value : null;
    case SDP:
      return text(value, 1, MAX_SDP, true);
    case MID:
      return text(value, 0, MAX_MID, false);
    case CAND:
      return text(value, 0, MAX_CAND, false);
    case WHY:
      return text(value, 1, MAX_WHY, false);
    case ICE:
      return iceServers(value);
  }
  return null;
}

// A JSON number with no fraction within [low, high], or null.
function integer(value, low, high) {
  if (typeof value !== "number" || !Number.isFinite(value) || !Number.isInteger(value)) {
    return null;
  }
  if (value < low || value > high) {
    return null;
  }
  // -0 is 0, as int(-0.0) is in GDScript.
  return value + 0;
}

// A string of printable ASCII of `low` to `high` characters, or null. SDP alone has line breaks.
function text(value, low, high, lines) {
  if (typeof value !== "string" || value.length < low || value.length > high) {
    return null;
  }
  for (let at = 0; at < value.length; at++) {
    const code = value.charCodeAt(at);
    if (code < 0x20 || code > 0x7e) {
      if (!(lines && (code === 0x0a || code === 0x0d))) {
        return null;
      }
    }
  }
  return value;
}

function isLowerHex(value) {
  for (const character of value) {
    if (!"0123456789abcdef".includes(character)) {
      return false;
    }
  }
  return true;
}

// The ICE servers rebuilt from known keys only ("urls", "username", "credential"), or null.
function iceServers(value) {
  if (!Array.isArray(value) || value.length > MAX_ICE_SERVERS) {
    return null;
  }
  const servers = [];
  for (const entry of value) {
    if (!isObject(entry)) {
      return null;
    }
    const rawUrls = get(entry, "urls");
    if (!Array.isArray(rawUrls) || rawUrls.length === 0 || rawUrls.length > MAX_ICE_URLS) {
      return null;
    }
    const urls = [];
    for (const url of rawUrls) {
      const checkedUrl = text(url, 1, MAX_ICE_TEXT, false);
      if (checkedUrl === null || !iceScheme(checkedUrl)) {
        return null;
      }
      urls.push(checkedUrl);
    }
    const server = { urls };
    for (const key of ["username", "credential"]) {
      if (Object.hasOwn(entry, key)) {
        const checkedText = text(entry[key], 0, MAX_ICE_TEXT, false);
        if (checkedText === null) {
          return null;
        }
        server[key] = checkedText;
      }
    }
    servers.push(server);
  }
  return servers;
}

function iceScheme(url) {
  return ["stun:", "stuns:", "turn:", "turns:"].some((scheme) => url.startsWith(scheme));
}

function printable(bytes) {
  for (const byte of bytes) {
    if ((byte < 0x20 || byte > 0x7e) && byte !== 0x09 && byte !== 0x0a && byte !== 0x0d) {
      return false;
    }
  }
  return true;
}

// --- Godot's JSON (core/io/json.cpp in 4.7.2), for printable ASCII input ------------------------

// Parses `source` as Godot's JSON.parse does, or throws. Numbers are doubles; objects are plain
// objects with own keys (the last of a repeated key wins); a value deeper than MAX_JSON_DEPTH (the
// top one at depth 0) fails.
export function parseGodotJson(source) {
  const reader = new GodotJsonReader(source);
  const value = reader.value(reader.token(), 0);
  if (reader.token().type !== "eof") {
    throw new SyntaxError("expected the end");
  }
  return value;
}

// Sticky: matched at `lastIndex`, so no token copies the rest of the message.
const NUMBER = /-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/y;
const IDENTIFIER = /[A-Za-z_][A-Za-z0-9_]*/y;
const PUNCTUATION = new Set(["{", "}", "[", "]", ":", ","]);

class GodotJsonReader {
  constructor(source) {
    this.source = source;
    this.at = 0;
  }

  // The next token: {type: "eof" | a punctuation character | "string" | "number" | "identifier", value}.
  token() {
    const source = this.source;
    // Godot skips every character up to and including space.
    while (this.at < source.length && source.charCodeAt(this.at) <= 32) {
      this.at++;
    }
    if (this.at >= source.length) {
      return { type: "eof" };
    }
    const character = source[this.at];
    if (PUNCTUATION.has(character)) {
      this.at++;
      return { type: character };
    }
    if (character === '"') {
      return { type: "string", value: this.string() };
    }
    if (character === "-" || (character >= "0" && character <= "9")) {
      NUMBER.lastIndex = this.at;
      const match = NUMBER.exec(source);
      if (match === null) {
        throw new SyntaxError("bad number");
      }
      this.at += match[0].length;
      return { type: "number", value: godotStrtod(match[0]) };
    }
    IDENTIFIER.lastIndex = this.at;
    const match = IDENTIFIER.exec(source);
    if (match === null) {
      throw new SyntaxError("unexpected character");
    }
    this.at += match[0].length;
    return { type: "identifier", value: match[0] };
  }

  // A string's text from the opening quote at `this.at`; raw control characters are kept.
  string() {
    const source = this.source;
    let out = "";
    this.at++;
    for (;;) {
      if (this.at >= source.length) {
        throw new SyntaxError("unterminated string");
      }
      const character = source[this.at++];
      if (character === '"') {
        return out;
      }
      if (character !== "\\") {
        out += character;
        continue;
      }
      if (this.at >= source.length) {
        throw new SyntaxError("unterminated string");
      }
      const escape = source[this.at++];
      switch (escape) {
        case "b": out += "\b"; break;
        case "f": out += "\f"; break;
        case "n": out += "\n"; break;
        case "r": out += "\r"; break;
        case "t": out += "\t"; break;
        case '"': out += '"'; break;
        case "\\": out += "\\"; break;
        case "/": out += "/"; break;
        case "u": {
          const unit = this.hex4();
          if (unit >= 0xdc00 && unit <= 0xdfff) {
            throw new SyntaxError("a trail surrogate alone");
          }
          if (unit >= 0xd800 && unit <= 0xdbff) {
            if (source[this.at] !== "\\" || source[this.at + 1] !== "u") {
              throw new SyntaxError("a lead surrogate alone");
            }
            this.at += 2;
            const trail = this.hex4();
            if (trail < 0xdc00 || trail > 0xdfff) {
              throw new SyntaxError("a lead surrogate alone");
            }
            out += String.fromCharCode(unit, trail);
          } else {
            out += String.fromCharCode(unit);
          }
          break;
        }
        default:
          throw new SyntaxError("bad escape");
      }
    }
  }

  hex4() {
    const digits = this.source.slice(this.at, this.at + 4);
    if (!/^[0-9A-Fa-f]{4}$/.test(digits)) {
      throw new SyntaxError("bad \\u escape");
    }
    this.at += 4;
    return parseInt(digits, 16);
  }

  value(token, depth) {
    if (depth > MAX_JSON_DEPTH) {
      throw new SyntaxError("too deep");
    }
    switch (token.type) {
      case "{":
        return this.object(depth);
      case "[":
        return this.array(depth);
      case "string":
      case "number":
        return token.value;
      case "identifier":
        if (token.value === "true") return true;
        if (token.value === "false") return false;
        if (token.value === "null") return null;
        break;
    }
    throw new SyntaxError("expected a value");
  }

  // A trailing comma is accepted, as Godot does.
  array(depth) {
    const array = [];
    let needComma = false;
    for (;;) {
      const token = this.token();
      if (token.type === "eof") {
        throw new SyntaxError("unterminated array");
      }
      if (token.type === "]") {
        return array;
      }
      if (needComma) {
        if (token.type !== ",") {
          throw new SyntaxError("expected ','");
        }
        needComma = false;
        continue;
      }
      array.push(this.value(token, depth + 1));
      needComma = true;
    }
  }

  object(depth) {
    const object = {};
    let needComma = false;
    for (;;) {
      const token = this.token();
      if (token.type === "eof") {
        throw new SyntaxError("unterminated object");
      }
      if (token.type === "}") {
        return object;
      }
      if (needComma) {
        if (token.type !== ",") {
          throw new SyntaxError("expected ','");
        }
        needComma = false;
        continue;
      }
      if (token.type !== "string") {
        throw new SyntaxError("expected a key");
      }
      if (this.token().type !== ":") {
        throw new SyntaxError("expected ':'");
      }
      const value = this.value(this.token(), depth + 1);
      // defineProperty: a "__proto__" key is an own key, as JSON.parse makes it.
      Object.defineProperty(object, token.value, {
        value, enumerable: true, writable: true, configurable: true,
      });
      needComma = true;
    }
  }
}

// Godot's built_in_strtod (core/string/ustring.cpp), which its JSON reader uses, for a number token
// NUMBER matched: not a correctly rounded parse. It keeps the first 18 mantissa digits, leading zeros
// included, gathers them in two 9-digit ints, and scales by a product of 10^(2^k) powers, which
// overflows to infinity past 10^308 (so 1e-320 is 0). The exponent is a 32-bit int that wraps, and
// one beyond 511 either way is taken as 511 (Godot prints a warning). Godot does this in C++ ints
// and doubles; the same steps in JavaScript doubles and int32s give the same bits.
const POWERS_OF_10 = [10, 100, 1e4, 1e8, 1e16, 1e32, 1e64, 1e128, 1e256];
const MAX_EXPONENT = 511;
const MAX_MANTISSA_DIGITS = 18;

export function godotStrtod(text) {
  let at = 0;
  const negative = text[at] === "-";
  if (negative) {
    at++;
  }
  const start = at;
  let point = -1;
  let size = 0;
  for (;; size++) {
    const character = text[at];
    if (!(character >= "0" && character <= "9")) {
      if (character !== "." || point >= 0) {
        break;
      }
      point = size;
    }
    at++;
  }
  const exponentAt = at;
  if (point < 0) {
    point = size;
  } else {
    size -= 1;
  }
  let fractionExponent;
  if (size > MAX_MANTISSA_DIGITS) {
    fractionExponent = point - MAX_MANTISSA_DIGITS;
    size = MAX_MANTISSA_DIGITS;
  } else {
    fractionExponent = point - size;
  }
  let p = start;
  const digit = () => {
    let character = text[p++];
    if (character === ".") {
      character = text[p++];
    }
    return character.charCodeAt(0) - 48;
  };
  let high = 0;
  for (; size > 9; size--) {
    high = 10 * high + digit();
  }
  let low = 0;
  for (; size > 0; size--) {
    low = 10 * low + digit();
  }
  let fraction = 1.0e9 * high + low;
  let exponent = 0;
  let exponentNegative = false;
  p = exponentAt;
  if (text[p] === "e" || text[p] === "E") {
    p++;
    if (text[p] === "-") {
      exponentNegative = true;
      p++;
    } else if (text[p] === "+") {
      p++;
    }
    for (; p < text.length; p++) {
      exponent = (Math.imul(exponent, 10) + (text.charCodeAt(p) - 48)) | 0;
    }
  }
  exponent = exponentNegative ? (fractionExponent - exponent) | 0 : (fractionExponent + exponent) | 0;
  // As unsigned, so -(-2^31) is 2^31 and is taken as 511, as Godot's build does.
  const scaleDown = exponent < 0;
  let magnitude = scaleDown ? -exponent >>> 0 : exponent;
  if (magnitude > MAX_EXPONENT) {
    magnitude = MAX_EXPONENT;
  }
  let scale = 1.0;
  for (let index = 0; magnitude !== 0; magnitude >>>= 1, index++) {
    if (magnitude & 1) {
      scale *= POWERS_OF_10[index];
    }
  }
  fraction = scaleDown ? fraction / scale : fraction * scale;
  return negative ? -fraction : fraction;
}
