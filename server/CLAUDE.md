# server/: host logic (engineer)

Loaded when a file in `server/` is read. The invariants in the root `CLAUDE.md` apply. Design:
`docs/ARCHITECTURE.md`.

## Job
- Wrap `core/`: turn validated client intents into `core/` commands and turn `core/` events into per-peer messages.
- Validate every intent before it reaches `core/`: the sender's peer id, the phase of the match, the target, rate
  and range. A client never sends state; anything that looks like state from a client is rejected.
- Filter per peer. Every outgoing message is built for one recipient from what that peer is entitled to know:
  roles, private events, votes before reveal and ability results never reach the wrong peer.
- The host's own local client is just another peer. It receives the same filtered messages through an in-process
  loopback transport, with the same codec, and never reads `core/` state directly. This keeps a dedicated-server
  mode trivial, though the MVP has none (listen server: `docs/ARCHITECTURE.md` §4).
- Host-side movement sanity checks (speed, teleport) live here; the local player's movement stays client-side.
- Voice: apply the `core/` routing decision to each speaker and listener pair before audio is forwarded.

## Boundaries
- `server/` may use `core/` and the `net/` transport abstraction; it never calls a concrete transport (ENet, Steam,
  WebRTC) directly, and never touches `client/` scenes or UI.
- Debug-only commands (spawn bots, force role, skip phase) are gated to debug builds and never widen what a
  release peer can see.

## Tests
- Integration tests of intent validation and filtering go in `tests/integration/`.
- The information-leak test is the most important test in the project: no client ever receives information it is
  not entitled to. When it exists, prove it works once by injecting a leak, confirming it fails, and reverting.
- At finish, `netcode-security-reviewer` reviews every `server/` change.
