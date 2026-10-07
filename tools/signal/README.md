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
| `src/service.js` | The Durable Object's work: hibernatable sockets, the records in socket attachments, the answer to a client's close, the 1 s close grace, `ICE_SERVERS`, deliveries in order per socket while a TURN credential is minted |
| `src/turn.js` | TURN credentials for the host's `room` and each host offer from Cloudflare's TURN key API (M6-10), only when the TURN secrets are set |
| `src/worker.js` | The Worker and the Durable Object class `Signalling`: the only file that needs the Cloudflare runtime |
| `test/*.test.js` | `node --test`, no npm package: the shared transcripts and decoding cases (`tests/fixtures/signal/`) through the router and the service over fakes, Cloudflare's TURN API a fake `fetch` |
| `smoke.js` | A smoke test of a running service (the Worker, or a `LanSignalling`); `--turn` also checks the TURN credentials' audience |
| `wrangler.toml` | The deploy configuration. No secrets |

`tools/run.sh signal` runs the tests (a `verify` step) with the pinned Node (`tools/runner/pins.py`).

## Deploy (the engineer, once, and after each change to `src/`)

You need Node.js 24 (`node --version` prints `v24.…`; `winget install OpenJS.NodeJS.LTS --version 24.21.0`, the pin in
`tools/runner/pins.py`) and a Cloudflare account. The first `npx wrangler` asks to
download Wrangler: answer `y`. `wrangler login` opens the browser to allow Wrangler on your account. If an older Node
comes first on PATH, put Node 24 first (`$env:Path = "C:\Program Files\nodejs;" + $env:Path`); if PowerShell refuses
`npx.ps1` (its execution policy), type `npx.cmd` instead of `npx`.

```powershell
cd C:\path\to\prime-game\tools\signal
npx wrangler login
npx wrangler deploy
```

The deploy prints the service's address, `https://prime-game-signal.<your-subdomain>.workers.dev`. The game connects
to it as `wss://prime-game-signal.<your-subdomain>.workers.dev/`, the address in `JoinTarget.SERVICE_URL`
(`net/transport/join_target.gd`): `wss://prime-game-signal.xperiaroco-36a.workers.dev/` since the first deploy on
2026-10-07 (#513). On the first deploy Cloudflare may ask you to pick the `workers.dev` subdomain in the dashboard
first.

Then check the deployed service from the same folder:

```powershell
node smoke.js "wss://prime-game-signal.<your-subdomain>.workers.dev/"
```

It ends with `smoke: passed`. It opens a room, joins it, sees a second joiner refused, passes an offer and an answer,
and checks that a joiner hears "the host left" before its socket closes. The host closes its socket without a status
code, as a browser's `close()` does, and waits for the service to answer that close: against the first deploy it
waited in vain. The likely cause is that the Worker answered with the code it received (1005), which the runtime
may not send; `SignalService.clientClosed` now answers with 1000 (ARCHITECTURE §4.8). The smoke after the redeploy
confirms it.

## Configuration and secrets

- **`ICE_SERVERS`** (`wrangler.toml`, `[vars]`): what `room` and every `offer` carry. Today STUN only,
  `stun:stun.cloudflare.com:3478` (E58). The service checks it by the clients' rules and refuses to start with a list
  they would drop. Change it in `wrangler.toml` and deploy again.
- **Secrets:** `TURN_KEY_ID` and `TURN_KEY_API_TOKEN`, the TURN key's id and its API token (below). With neither
  set the service relays nothing: `room` and every `offer` carry `ICE_SERVERS` alone, as before M6-10. One without the
  other is no TURN too, and the Worker logs `no TURN until both ... are set` (each `secret put` goes live at once, so
  this is the state between the two commands below). They never go in `wrangler.toml`. Add each in the dashboard: **Workers
  & Pages** > select `prime-game-signal` > **Settings** > **Variables and Secrets** > **Add** > type **Secret**, its
  name and value > **Deploy**. Or from this folder: `npx wrangler secret put <NAME>`, which asks for the value.
- **`TURN_TTL_SECONDS`** (optional, `[vars]`): how long each credential lasts, 600 (D17's 10 minutes, a
  placeholder) when unset, at most 172800 (48 hours). Cloudflare's FAQ: when a credential expires while its relay is
  in use, "after a short delay, the connection will be disconnected", so a relayed player is dropped this long after
  the host's offer, and a relayed host this long after opening the room. Pick it before relying on TURN.

## TURN (M6-10, the engineer, once)

Only with D17 (b): Cloudflare relays a joiner whose direct connection fails, free up to 1,000 GB a month, then $0.05
per GB (Cloudflare's FAQ: billed on the data Cloudflare sends to the TURN client). Whether Cloudflare asks for a
payment card is found out here; if it does and you decline, skip this section: D17 (a), no relay.

1. Create a TURN key in the Cloudflare dashboard: open `https://dash.cloudflare.com/?to=/:account/calls` (the
   link Cloudflare's page gives; the menu names were not checked) and create a TURN key. Copy its key id and its API
   token (Cloudflare's page calls them `$TURN_KEY_ID` and `$TURN_KEY_API_TOKEN`).
2. Set both secrets and deploy again from this folder; each `secret put` asks for its value. Replace
   `<your-subdomain>` in the last line first (PowerShell refuses a bare `<`):

```powershell
cd C:\path\to\prime-game\tools\signal
npx wrangler secret put TURN_KEY_ID
npx wrangler secret put TURN_KEY_API_TOKEN
npx wrangler deploy
node smoke.js "wss://prime-game-signal.<your-subdomain>.workers.dev/" --turn
```

`smoke.js --turn` ends with `smoke: passed` after `ok   TURN: room and the offer each carry their own credential,
and found none`. It prints the servers' URLs, never a credential. To turn TURN off again, delete both secrets
(`npx wrangler secret delete <NAME>`) and deploy.

## How it runs

- **One Durable Object for every room** (`SIGNALLING.getByName("signalling")`). The protocol names the room in the
  socket's first message, after the socket is open, and a joiner whose `join` failed may try another code on the
  same socket, so a socket cannot be sent to a room's own object when it connects. The free plan's duration, 13,000
  GB-s a day, is about 28 hours a day of one object at 128 MB, so even an object that never hibernated would stay
  within it; requests (100,000 a day, a WebSocket message counting 1/20) are a few per join.
- **TURN** (M6-10, `src/turn.js`): with the two secrets set, the host's `room` and each host `offer` to a joiner wait
  for a credential minted for their receiver (`POST https://rtc.live.cloudflare.com/v1/turn/keys/<key id>/credentials/generate-ice-servers`,
  `{"ttl": 600}`), added after `ICE_SERVERS`: only its `turn:` and `turns:` URLs, none on port 53, split into
  entries of at most 4 URLs with the same username and credential (the protocol's cap; Cloudflare's answer has 6).
  `found`, answers and candidates never carry one, and a joiner gets only its own (the M6 ADR §2.4: "the host's own
  come with `room`"). Each socket has its own queue: what follows a waiting message to the same socket waits for it,
  so a candidate never overtakes its offer, and no other socket waits; each request starts at once. If the API
  fails, answers what the clients would drop, or takes over 5 s, or the credential would push the message over
  16 KB, it goes without TURN and the Worker logs a line (`npx wrangler tail` shows it). A message still waiting
  when the object restarts (a deploy) is lost: its client times out and tries again. The transcript `turn_per_joiner.json` is replayed here only.
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
- `realtime/turn/`: "STUN over UDP | stun.cloudflare.com | 3478/udp"; TURN over UDP 3478 and 443, TCP 3478 and 80,
  TLS 5349 and 443; $0.05 per GB "outbound from Cloudflare to the TURN client" unless used with the Realtime SFU.
- `realtime/turn/generate-credentials/`: create a TURN key in the dashboard (`?to=/:account/calls`) or the API; the
  request (`POST .../v1/turn/keys/$TURN_KEY_ID/credentials/generate-ice-servers`, `Authorization: Bearer
  $TURN_KEY_API_TOKEN`, `{"ttl": 86400}`), its 201 answer `{"iceServers": [...]}` with a STUN entry and a TURN entry
  of 6 URLs, a username and a credential; port 53 "is known to be blocked by web browsers"; "keep your TURN key on the
  server side"; revoking a credential before its TTL.
- `realtime/turn/faq/`: $0.05 per GB with 1,000 GB free, billed on egress; no defined limit on issuing credentials;
  a credential lasts at most 48 hours; an expired one disconnects its allocation "after a short delay". It says
  nothing on whether a payment method is needed.
