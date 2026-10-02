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
  those kinds (or any kind that is not in `Intents.ALL`) from a client's message, except a debug kind from peer 1
  in a debug build, which becomes the command it names (Boundaries below; §4.3, E17). `Match` does not check who made
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

## The host session (`docs/ARCHITECTURE.md` §4.5; built in 3f, #100)
- `HostSession` (`host_session.gd`): `start(mode, port, max_clients, now_usec)` (or `start_with` with given worlds
  and layouts), then `step(now_usec)` per frame and `close()`. It links `own_client` (peer 1's transport); the owner
  runs the own `ClientSession` on it. `HostNode` steps it from `_physics_process`, also while paused; start it with
  `HostNode.now_usec()` and never reparent the node (leaving the tree closes the session). For the game `HostNode`
  is the façade (§4.7, E18): `HostNode.host(transport, mode, port)` builds and starts a private session, and the game
  uses only `is_running()`, `own_client`, `errors`, `end_reason`, `ended`, `counters()` (debug builds), `skip_replay()`
  and `close()`; `tools/` and the tests hand a `HostSession` to `HostNode.new` instead. Parts: `PeerBudget`,
  `VoiceRelay`, `ReplayFiles`. Its observer (debug builds) gets `(at_tick, command, slice)` after every `Match` call,
  catch-up ticks included: the bots runner's hook, never a reason to change `HostSession` for 3h.
- Host ticks come from the host's clock (`Time.get_ticks_usec()`), never from a count of physics frames, which falls
  behind for good after a freeze. Each physics step, in order: apply commands left from an earlier step at the next
  tick, then run the ticks a freeze skipped with no commands; refill the per-peer budgets; poll; apply the queued
  commands stamped with the due tick, then `Match.tick`; deliver the outbox; send the snapshots; check the hello
  deadlines. Deliver the outbox and refresh the voice routing after every `Match.tick` call, catch-up ticks
  included. Catching up before applying is what lets the first claim after a host freeze pass (#84).
- One queue by arrival: the transport's signal order, the loopback's messages and the network's alike. Stamp a
  command when it is applied, with the tick it is applied on.
- Take the outbox after every `Match.apply` and `Match.tick` call, one slice per call. Encode an event once and send it
  to each recipient in turn, skipping peers this session already disconnected, and skipping p in slices taken after
  `peer_left(p)` but before the call that applied `PeerLeft(p)` (ids are reused). Carry out a directive where it
  stands in the outbox.
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
  built when the session starts, before `MarkerReader` reads the markers through them (`use_level` per level); then
  the level is the one `Match` names (`use_level`). Never the client's scene. Built (3c):
  `HostWorldQuery.for_mode(mode)` (`host_world_query.gd`) builds every level's `LevelWorld` (`level_world.gd`); refuse
  the host on its `errors`, then pass it to `MarkerReader.read_levels` and `Match.new`. A fresh world answers at once.
- An error recorded while a transition row runs (`Match.row_error_count()` grew in a `Match` call) ends the session
  before that call's events are delivered (the engineer's answer on #90): a deal that could not place its tasks would
  start a round that the crew wins at once. Key on no phase or outcome id: those are the mode's data.
- The session seed comes from `Crypto.generate_random_bytes`. The seed and the command log never leave the host.

## Boundaries
- `server/` may use `core/` and the `net/` transport abstraction; it never calls a concrete transport (ENet, Steam,
  WebRTC) directly, and never touches `client/` scenes or UI.
- Debug-only commands (spawn bots, force role, skip phase) are gated to debug builds and never widen what a
  release peer can see. On the wire they are kinds only a debug build's table has, taken from peer 1 only and turned
  into the command they name (`ForceRole`, `ForceClock`); from another peer they are malformed (§4.3, E17).

## Tests
- Integration tests of the transport checks and the per-peer delivery go in `tests/integration/`; the rules
  themselves are unit-tested in `core/`.
- The information-leak test is the most important test in the project: no client ever receives information it is
  not entitled to; it compares what each bot decoded with `Match.view_of` of its peer (§5, §4.6), in `bots`. 3h
  (#102) proved it once with three injected leaks (§4.6); a new kind of leak gets the same proof: inject it, see
  `bots` fail, revert. A connected peer that is not a player receives at most a `Rejected`, none unless it sent a
  `Hello` (so a lurker receives nothing): never an *everyone*
  event, snapshot or voice.
- Drive the host session with a clock of the test's own: a host freeze is a jump of that clock.
- At finish, `netcode-security-reviewer` reviews every `server/` change.
