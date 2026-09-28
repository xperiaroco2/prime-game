# net/: transport, messages, serialization (engineer)

Loaded when a file in `net/` is read. The invariants in the root `CLAUDE.md` apply. Design:
`docs/ARCHITECTURE.md`.

## Job
- The transport abstraction. Godot high-level multiplayer over ENet first. Steam networking or WebRTC with a
  signaling server may replace it later (NAT traversal ADR in M6), so nothing outside `net/` may depend on ENet.
- Message schemas for intents (client → host) and events (host → client), and their serialization.
- State sync and interpolation data for remote players.

## Rules
- Messages carry only what their schema declares. Never serialize a whole `core/` object or state snapshot:
  filtering happens in `server/`, and a generic serializer would bypass it.
- Deserialize defensively: a malformed or oversized message from a peer is rejected and logged, never trusted.
- Every schema change updates the protocol section of `docs/ARCHITECTURE.md` in the same PR.
- No game rules here. If a message handler starts deciding outcomes, the decision belongs in `core/`.

## Tests
- Round-trip tests for every schema (serialize, deserialize, compare) in `tests/unit/`.
- Host plus clients on one machine in `tests/integration/` and the bot harness (`bots`, once it exists).
- At finish, `netcode-security-reviewer` reviews every `net/` change.
