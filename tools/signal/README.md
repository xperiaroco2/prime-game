# The signalling service (Cloudflare Worker)

How a host and a joiner find each other before WebRTC connects, on the internet: the
[M6 design](../../docs/decisions/2026-10-04-m6-playable-over-the-internet.md) §2.4 (D18, D23, E53, E55, E58) and
[ARCHITECTURE §4.8](../../docs/ARCHITECTURE.md). On a LAN and in every test the host serves the same protocol itself
(`LanSignalling`). The Worker runs on the engineer's Cloudflare account, on the Workers Free plan, and only the
engineer deploys it. Agents never run `wrangler`.

## Files

| File | What it is |
|---|---|
| `src/codec.js` | The messages and their checks: `SignalCodec`'s rules, with a JSON reader that accepts and refuses exactly what Godot's does |
| `src/router.js` | Rooms and routing with no sockets: `SignalRouter`'s rules, its state kept as one record per socket |
| `src/service.js` | The Durable Object's work: hibernatable sockets, the records in socket attachments, the 1 s close grace, `ICE_SERVERS` |
| `src/worker.js` | The Worker and the Durable Object class `Signalling`: the only file that needs the Cloudflare runtime |
| `test/*.test.js` | `node --test`, no npm package: the shared transcripts and decoding cases (`tests/fixtures/signal/`) through the router and the service over fakes |
| `smoke.js` | A smoke test of a running service (the Worker, or a `LanSignalling`) |
| `wrangler.toml` | The deploy configuration. No secrets |

`tools/run.sh signal` runs the tests (a `verify` step) with the pinned Node (`tools/runner/pins.py`).

## Deploy (the engineer, once, and after each change to `src/`)

You need Node.js 24 (`node --version` prints `v24.…`; `winget install OpenJS.NodeJS.LTS --version 24.21.0`, the pin in
`tools/runner/pins.py`) and a Cloudflare account. The first `npx wrangler` asks to
download Wrangler: answer `y`. `wrangler login` opens the browser to allow Wrangler on your account.

```powershell
cd C:\path\to\prime-game\tools\signal
npx wrangler login
npx wrangler deploy
```

The deploy prints the service's address, `https://prime-game-signal.<your-subdomain>.workers.dev`. The game connects
to it as `wss://prime-game-signal.<your-subdomain>.workers.dev/` (M6-7 puts that address in the game). On the first
deploy Cloudflare may ask you to pick the `workers.dev` subdomain in the dashboard first.

Then check the deployed service from the same folder:

```powershell
node smoke.js wss://prime-game-signal.<your-subdomain>.workers.dev/
```

It ends with `smoke: passed`. It opens a room, joins it, sees a second joiner refused, passes an offer and an answer,
and checks that a joiner hears "the host left" before its socket closes.

## Configuration and secrets

- **`ICE_SERVERS`** (`wrangler.toml`, `[vars]`): what `room` and every `offer` carry. Today STUN only,
  `stun:stun.cloudflare.com:3478` (E58). The service checks it by the clients' rules and refuses to start with a list
  they would drop. Change it in `wrangler.toml` and deploy again.
- **Secrets:** none today. TURN credentials (M6-10, only if D17 (b)) will need a TURN key: its id and API token
  are secrets and never go in `wrangler.toml`. Add each in the dashboard: **Workers & Pages** > select
  `prime-game-signal` > **Settings** > **Variables and Secrets** > **Add** > type **Secret**, its name and value >
  **Deploy**. Or from this folder: `npx wrangler secret put <NAME>`, which asks for the value.

## How it runs

- **One Durable Object for every room** (`SIGNALLING.getByName("signalling")`). The protocol names the room in the
  socket's first message, after the socket is open, and a joiner whose `join` failed may try another code on the
  same socket, so a socket cannot be sent to a room's own object when it connects. The free plan's duration, 13,000
  GB-s a day, is about 28 hours a day of one object at 128 MB, so even an object that never hibernated would stay
  within it; requests (100,000 a day, a WebSocket message counting 1/20) are a few per join.
- **TURN** is not here yet: M6-10 adds per-joiner credentials, only when a TURN key is configured. Until then every
  `offer` carries the same `ICE_SERVERS` as `room`.
- **Hibernation:** the object accepts sockets with the WebSocket Hibernation API, so an idle room costs no duration.
  The object may leave memory while sockets stay open; its constructor then runs again. Everything the router knows
  is in each socket's attachment (its number and the router's record; a host's also holds its room), and the
  constructor rebuilds the router from them. The tests rebuild it after every step of every transcript.
- **Closing after an error:** a joiner whose host left gets `error {why: "the host left"}`, and its socket is closed
  1 s later. Godot's `WebSocketPeer` drops a message it reads together with the close, as `LanSignalling` found.
- **The Durable Object glue** (`src/worker.js`) has no test: the first deploy and `smoke.js` try it.

## Cloudflare facts used (developers.cloudflare.com, read 2026-10-04)

- `durable-objects/platform/limits/`: the Workers Free plan has only Durable Objects with the SQLite storage backend.
- `durable-objects/platform/pricing/`: Free: 100,000 requests a day, 13,000 GB-s of duration a day, 5 GB stored;
  incoming WebSocket messages count 20 to 1 as requests; an object idle and eligible for hibernation is not billed
  for duration.
- `durable-objects/best-practices/websockets/`: `ctx.acceptWebSocket`, `webSocketMessage`, `webSocketClose`,
  `serializeAttachment` (at most 16,384 bytes), in-memory state reset on hibernation and the constructor run again;
  timers keep the object awake; from compatibility date 2026-04-07 the runtime answers a client's close frame.
- `durable-objects/examples/websocket-hibernation-server/`: the Worker forwarding the upgrade with
  `getByName(...).fetch(request)`, `WebSocketPair`, the 101 response, `new_sqlite_classes` in `[[migrations]]`.
- `workers/wrangler/configuration/`: `name`, `main`, `compatibility_date`, `workers_dev`, `[vars]` (TOML values reach
  `env` as JSON values), `[[durable_objects.bindings]]`; "Do not use `vars` to store sensitive information". It
  recommends `wrangler.jsonc` for new projects; the issue asked for `wrangler.toml`, which Wrangler still reads.
- `workers/configuration/secrets/`: the dashboard path above and `npx wrangler secret put`.
- `realtime/turn/`: "STUN over UDP | stun.cloudflare.com | 3478/udp".
