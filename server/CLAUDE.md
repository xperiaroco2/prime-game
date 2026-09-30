# server/: host logic (engineer)

Loaded when a file in `server/` is read. The invariants in the root `CLAUDE.md` apply. Design:
`docs/ARCHITECTURE.md`.

## Job
- Wrap `core/`: turn client intents into `core/` commands stamped with the host tick (`Match.apply`, then
  `Match.tick` once per host tick, driven from the physics step), and turn `core/`'s events into per-peer messages.
- Check what the transport knows before an intent reaches `core/`: the sender's peer id (never a field of the
  message), decoding, size and rate. A client never sends state; anything that looks like state is rejected.
- The rules are `core/`'s, not this folder's: the phase's allowlist, life state, hand, reach, range, stamina,
  cooldowns and the movement sanity checks (speed, teleport, jumps) are `core/` rules that `Match` runs on each
  command (`docs/ARCHITECTURE.md` §4.1, §7.1). Never re-implement or skip them here.
- Deliver per peer. `core/` decides who is entitled to each event (§5): send each event (`Match.take_outbox`) to
  exactly its recorded recipients, one message per recipient, *everyone* events included (never the transport's
  broadcast target, which also reaches peers that are not players). Never add a recipient or a field. Snapshots
  and voice routing come from `core/` too (`Match.snapshot_for`, `Match.speakers_for`).
- Only `server/` makes `PeerConnected` and `PeerLeft`, from what the transport reports; never build a command of
  those kinds (or any kind that is not in `Intents.ALL`) from a client's message. `Match` does not check who made
  a command. It keeps every command in its log (about 20 MiB per player per 10 minutes at 20 Hz) and records
  per-tick views only with `keep_history`, which a host leaves off.
- Carry out the directives whose audience is *server* (`RefuseJoins`, `AllowJoins`, `DisconnectPeer`), in the
  outbox's order: a `DisconnectPeer` comes after the `Rejected` that explains it, which must be sent first.
  Pass `PeerConnected` as soon as the transport admits a peer: `core/` takes a `Hello` only from a peer it knows is
  connected. A `Rejected` may go to such a peer before its `Hello` is accepted (audience *sender*).
- Load the game mode and read each level's `Marker3D`s in `spawn_<tag>` groups into a `LevelLayout` with
  `MarkerReader` (`server/levels/`, 2j): scene-tree order, load errors listed (two tags, not a marker), station
  markers (`circle`) snapped to the floor below through the `WorldQuery`. Refuse a level with load errors. Answer
  `core/`'s geometric questions through a `WorldQuery` over the host's own `World3D` (M3, below).
- The host's own local client is just another peer. It receives the same filtered messages through an in-process
  loopback transport, with the same codec, and never reads `core/` state directly. This keeps a dedicated-server
  mode trivial, though the MVP has none (listen server: `docs/ARCHITECTURE.md` §4).
- Voice: forward a frame only along the pairs `core/`'s routing allows.

## The host session (M3 design, proposed: `docs/ARCHITECTURE.md` §4.5)
- Host ticks come from the host's clock (`Time.get_ticks_usec()`), never from a count of physics frames, which falls
  behind for good after a freeze. Each physics step, in order: apply commands left from an earlier step at the next
  tick, then run the ticks a freeze skipped with no commands; refill the per-peer budgets; poll; apply the queued
  commands stamped with the due tick, then `Match.tick`; deliver the outbox; send the snapshots; check the hello
  deadlines. Deliver the outbox and refresh the voice routing after every `Match.tick` call, catch-up ticks
  included. Catching up before applying is what lets the first claim after a host freeze pass (#84).
- One queue by arrival: the transport's signal order, the loopback's messages and the network's alike. Stamp a
  command when it is applied, with the tick it is applied on.
- Encode an event once and send it to each recipient in turn, skipping peers this session already disconnected. Carry
  out a directive where it stands in the outbox.
- Snapshots: only for a tick run in this step (never for catch-up ticks), to present players, after that tick's
  events; an empty `snapshot_for` sends nothing. Unreliable messages go only to players: a player has sent its
  `Hello`, so nothing overtakes the transport's `ADMIT`.
- Voice: relay a `VoiceUp` at once, along the routing table refreshed after every tick, as a `VoiceDown` with the
  stream's own seq (per speaker and listener; never the speaker's) and `ticked_through()`. Never decode Opus. Drop
  frames from a peer that is not a present player; after a freeze relay only the newest few per speaker. On
  `peer_left(p)` drop p from the relay at once, as speaker and listener: ids are reused.
- Budgets per peer (voice frames, reliable intents, bytes of the rest) are refilled for the host time elapsed, before
  the poll; a message over one is dropped before decoding and counted, and nobody is disconnected for its rate. A
  peer that keeps sending malformed messages is disconnected with one log line (the threshold: §4.5). A `Rejected`
  from `core/` is not malformed.
- The hello deadline: a peer that has had no `Welcome` 10 s after it connected is disconnected.
- Peer 1 (the host's own client) is exempt from budgets, the malformed disconnect and the hello deadline: never
  `disconnect_peer(1)`; a broken own client ends the session.
- `WorldQuery`: per level a `World3D.new()` holding the level's static colliders (layer 1) through `PhysicsServer3D`,
  built when the session starts; the level is the one `Match` names (`use_level`). Never the client's scene.
- The session seed comes from `Crypto.generate_random_bytes`. The seed and the command log never leave the host.

## Boundaries
- `server/` may use `core/` and the `net/` transport abstraction; it never calls a concrete transport (ENet, Steam,
  WebRTC) directly, and never touches `client/` scenes or UI.
- Debug-only commands (spawn bots, force role, skip phase) are gated to debug builds and never widen what a
  release peer can see.

## Tests
- Integration tests of the transport checks and the per-peer delivery go in `tests/integration/`; the rules
  themselves are unit-tested in `core/`.
- The information-leak test is the most important test in the project: no client ever receives information it is
  not entitled to; it compares what each bot decoded with `Match.view_of` of its peer (§5, §4.6). When it exists,
  prove it works once by injecting a leak, confirming it fails, and reverting.
- Drive the host session with a clock of the test's own: a host freeze is a jump of that clock.
- At finish, `netcode-security-reviewer` reviews every `server/` change.
