# server/: host logic (engineer)

Loaded when a file in `server/` is read. The invariants in the root `CLAUDE.md` apply. Design:
`docs/ARCHITECTURE.md`.

## Job
- Wrap `core/`: turn client intents into `core/` commands stamped with the host tick (`Match.apply`, then
  `Match.tick` once per physics step), and turn `core/`'s events into per-peer messages.
- Check what the transport knows before an intent reaches `core/`: the sender's peer id (never a field of the
  message), decoding, size and rate. A client never sends state; anything that looks like state is rejected.
- The rules are `core/`'s, not this folder's: the phase's allowlist, life state, hand, reach, range, stamina,
  cooldowns and the movement sanity checks (speed, teleport, jumps) are `core/` rules that `Match` runs on each
  command (`docs/ARCHITECTURE.md` §4.1, §7.1). Never re-implement or skip them here.
- Deliver per peer. `core/` decides who is entitled to each event (§5): send each event (`Match.take_outbox`) to
  exactly its recorded recipients, one message per recipient, *everyone* events included (never the transport's
  broadcast target, which also reaches peers that are not players). Never add a recipient or a field. Snapshots
  and voice routing come from `core/` too (`Match.snapshot_for`, `Match.speakers_for`).
- Carry out the directives whose audience is *server* (`RefuseJoins`, `AllowJoins`, `DisconnectPeer`).
- Load the game mode and read each level's `Marker3D`s in `spawn_<tag>` groups into a `LevelLayout` (2j); answer
  `core/`'s geometric questions through a `WorldQuery` over the host's own `World3D` (M3).
- The host's own local client is just another peer. It receives the same filtered messages through an in-process
  loopback transport, with the same codec, and never reads `core/` state directly. This keeps a dedicated-server
  mode trivial, though the MVP has none (listen server: `docs/ARCHITECTURE.md` §4).
- Voice: forward a frame only along the pairs `core/`'s routing allows.

## Boundaries
- `server/` may use `core/` and the `net/` transport abstraction; it never calls a concrete transport (ENet, Steam,
  WebRTC) directly, and never touches `client/` scenes or UI.
- Debug-only commands (spawn bots, force role, skip phase) are gated to debug builds and never widen what a
  release peer can see.

## Tests
- Integration tests of the transport checks and the per-peer delivery go in `tests/integration/`; the rules
  themselves are unit-tested in `core/`.
- The information-leak test is the most important test in the project: no client ever receives information it is
  not entitled to; it compares what each bot decoded with `Match.view_of` of its peer (§5). When it exists, prove
  it works once by injecting a leak, confirming it fails, and reverting.
- At finish, `netcode-security-reviewer` reviews every `server/` change.
