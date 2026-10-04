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
  payload cap), `LaneOrder` (the 4-byte LATEST header that keeps LATEST in order with RELIABLE on WebRTC, M6 §2.2),
  `NetRejects` (counts and the summary line; `server/` adds its drops with `count_rejected`), and the
  `packet_rejected(peer, reason)` signal per reject. Decisions: `docs/ARCHITECTURE.md` §4 "Transport".
- `messages/`: `WireSchema` (every row of §4.3, the version, `encode`/`decode`; `NetKindTable.game()` is built from
  it), `WireRow` (`fixed_offset`: where a fixed-size field starts, so a caller patches it in place without a byte
  index), `WireField` (a field's wire type, its checks, its write and read), `WireMessage` (a name, the fields, `seq`
  and ForceRole's `peer`), `WireReader` (bounds-checked) and `WireWriter`. `WireBudget` is `server/`'s.
  `ContentFingerprint` (3g): the content hash `Hello` carries (§4.3, E1), from the mode's parts the caller passes;
  it hashes the level files and every scene and resource they reach, scripts left out (#118).

## Rules
- A new message kind is one row in `WireSchema` (`NetKindTable.game()` is built from it): pick its lane (voice takes
  `VOICE`, unordered), its direction and a payload cap. Never pick a channel or transfer mode anywhere else.
- The LATEST lane delivers only the newest message per sender and kind per poll between two of that sender's
  reliable messages (the backlog after a freeze, #70): a LATEST message must stand alone. Anything that must not be
  lost when a newer one replaces it goes RELIABLE. The merge ignores the subject: a host-to-client LATEST kind holds
  what it describes for every player the recipient may see in one message, never one message per player.
- Received bytes go through `NetTransport.receive_bytes` and its helper `_decoded` only, whatever the backend, so
  the host's own client decodes exactly what a remote one does (a superseded LATEST packet is checked the same way
  but not delivered). Signals fire from `poll()` only.
- ENet timeouts are set in `EnetTransport` and nowhere else. The peer timeout stays at 10 s or more: a windowed
  D3D12 process can freeze 5 s (#21); Vulkan, the Windows driver since #124, did not, but other freezes remain.
- `EnetTransport.poll` services ENet until the socket is drained: one service reads at most 256 datagrams, and a
  freeze's backlog is bigger (#95). Never go back to a single `ENetMultiplayerPeer.poll()` per poll.
- Peer ids are chosen by clients: never treat one as secret or as unique over time (§4).
- Messages carry only what their schema declares. Never serialize a whole `core/` object or state snapshot:
  filtering happens in `server/`, and a generic serializer would bypass it.
- Deserialize defensively: a malformed or oversized message from a peer is rejected and counted, never trusted;
  log a summary, so one peer cannot flood the log.
- Every schema change updates the protocol section of `docs/ARCHITECTURE.md` in the same PR.
- No game rules here. If a message handler starts deciding outcomes, the decision belongs in `core/`.

## Messages (`docs/ARCHITECTURE.md` §4.3, §4.4; built in 3d, #98)
- One declarative table in `messages/` holds every row (kind, name, direction, lane, cap, fields with wire types);
  `NetKindTable.game()` is built from it. Field names are `core/`'s (`MatchCommand.args`, each event's `to_dict()`),
  written as strings: `net/` references no `core/` class.
- Wire types only (§4.3): little-endian integers, `f32` for every float (lossless for `Vector3` and `Color`), ids of
  `a-z 0-9 _`, `res://` paths, printable-ASCII text and notes (shortfalls), counted lists and maps with ascending
  keys. Never `var_to_bytes` or `bytes_to_var` on the wire, even without objects. Content sets how big some kinds
  get: `WireBudget` (`server/`) refuses a mode that could exceed a cap (§4.3, E16).
- Decode through the bounds-checked reader only: check the bytes left before every `decode_*`, reject the whole
  message at the first problem (a type rule, a count, a key order, unknown flag bits, trailing bytes), and count it.
- The encoder checks its input by the same rules and refuses, with an error, what the decoder would reject or what
  exceeds the cap; it never truncates.
- Rows 1 (`Hello`: C→H, RELIABLE, its version first, cap 8192) and 32 (`Rejected`: H→C, RELIABLE, cap 37) never
  change, cap and lane included. A `Hello` of another version decodes to its version alone, whatever its length. Any
  other change to a row bumps the protocol version, which equals `core/`'s `JoinRules.PROTOCOL_VERSION` (a test pins
  them).
- A kind sent only on change (`SelfStatus`) is RELIABLE: on LATEST a lost last change stays stale for good.
- Debug commands (kinds 24 to 31: `ForceRole`, `ForceClock`) are rows of a debug build's table only: a release
  build neither sends nor decodes them (§4.3, E17).

## Tests
- Round-trip tests for every schema (serialize, deserialize, compare) in `tests/unit/`, a fuzz test of every decoder
  (truncations, single-byte changes, random payloads: a clean reject and no engine error line), and the table
  checked against `core/`'s intents and events (§4.4).
- Host plus clients on one machine in `tests/integration/` and the bot harness (`bots`). Layers
  above `net/` test with a `LoopbackHub`; ENet itself with the headless run
  `tools\run.cmd run tests/integration/net/enet_host_and_two_clients.gd --headless --instances 3` (127.0.0.1 only),
  and the 5.2 s freeze of the host and of a client,
  `tools\run.cmd run tests/integration/net/enet_freeze.gd --headless --instances 3 -- --port=<p>` (#70), and the
  timeouts and the backlog in one process (#95),
  `tools\run.cmd run tests/integration/net/enet_stall.gd --headless -- --port=<p>`. `verify` and CI run all three on
  a free port.
- At finish, `netcode-security-reviewer` reviews every `net/` change.
