# net/: transport, messages, serialization (engineer)

Loaded when a file in `net/` is read. The invariants in the root `CLAUDE.md` apply. Design:
`docs/ARCHITECTURE.md`.

## Job
- The transport abstraction. ENet first, read from `ENetMultiplayerPeer` directly, not through `SceneMultiplayer`
  (`docs/ARCHITECTURE.md` §4), plus an in-process loopback for the host's own client. Own messages only: no RPCs,
  `MultiplayerSpawner` or `MultiplayerSynchronizer`. Steam networking or WebRTC with a
  signaling server may replace it later (NAT traversal ADR in M6), so nothing outside `net/` may depend on ENet.
- Message schemas for intents (client → host) and events (host → client), and their serialization.
- State sync and interpolation data for remote players.

## Map
- `transport/`: `NetTransport` (the interface game code uses), `EnetTransport`, `LoopbackTransport` and
  `LoopbackHub`, `NetFrame` (the 3-byte header and the defensive decode), `NetKindTable` (kind → lane, direction,
  payload cap), `NetRejects` (counts and the summary line). Decisions: `docs/ARCHITECTURE.md` §4 "Transport".

## Rules
- A new message kind is one row in `NetKindTable.game()`: pick its lane (voice takes `VOICE`, unordered), its
  direction and a payload cap. Never pick a channel or transfer mode anywhere else.
- Received bytes go through `NetTransport.receive_bytes` only, whatever the backend, so the host's own client
  decodes exactly what a remote one does. Signals fire from `poll()` only.
- ENet timeouts are set in `EnetTransport` and nowhere else.
- Messages carry only what their schema declares. Never serialize a whole `core/` object or state snapshot:
  filtering happens in `server/`, and a generic serializer would bypass it.
- Deserialize defensively: a malformed or oversized message from a peer is rejected and counted, never trusted;
  log a summary, so one peer cannot flood the log.
- Every schema change updates the protocol section of `docs/ARCHITECTURE.md` in the same PR.
- No game rules here. If a message handler starts deciding outcomes, the decision belongs in `core/`.

## Tests
- Round-trip tests for every schema (serialize, deserialize, compare) in `tests/unit/`.
- Host plus clients on one machine in `tests/integration/` and the bot harness (`bots`, once it exists). Layers
  above `net/` test with a `LoopbackHub`; ENet itself with the headless run
  `tools\run.cmd run tests/integration/net/enet_host_and_two_clients.gd --headless --instances 3` (127.0.0.1 only).
- At finish, `netcode-security-reviewer` reviews every `net/` change.
