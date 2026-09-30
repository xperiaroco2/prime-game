# Architecture

| | |
|---|---|
| **Owner** | The engineer. The **content API** section is the contract with the designer: changes to it are reviewed by both. |
| **Status** | Skeleton (M0). The boundaries below are locked ([KICKOFF §3](history/KICKOFF.md); stack: [ADR](decisions/2026-09-29-technical-stack-from-the-brief.md)). Everything marked *open* is designed before M2 (core and content API) or in the milestone named. The match loop, intents, events and entitlement (§3, §4.1, §4.2, §5, §7.1): M2 design, #32. The content API v0 and bot scenarios (§9): M2 design, #33; built in stage 2 from 2a (#49) on. |
| **Rules for agents** | The invariants are repeated in the root `CLAUDE.md`, so they survive compaction. Area rules: `core/`, `server/`, `net/`, `client/`, `voice/` `CLAUDE.md`. |

## 1. Layers and boundaries

| Folder | Contains | May use | Owner |
|---|---|---|---|
| `core/` | Pure rules: match state machine, intent validation rules (movement checks included), win conditions, who is entitled to each event and entity (§5), voice routing rules, content-API primitives. `RefCounted` only; no Nodes, scenes, networking or audio | nothing outside `core/` | engineer |
| `server/` | Host logic: wraps `core/`, checks the sender, format and rate of intents, builds one message per recipient from `core/`'s entitlement, answers `core/`'s geometric questions (`WorldQuery`, §7.1) | `core/`, the `net/` abstraction | engineer |
| `net/` | Transport abstraction (ENet first), message schemas, serialization, sync | nothing game-specific | engineer |
| `client/` | Scenes, player controller, UI, camera, audio playback, dev console | the filtered view it receives; `net/` to send intents | engineer |
| `voice/` | Capture, Opus encode and decode, jitter buffer, playback plumbing | `net/`, `client/` playback | engineer |
| `content/` | Game modes, roles, abilities, items, sabotages, task types and win conditions as `Resource`s built from content-API parts (§9); bot scenarios (§9.7), whose data classes are part of the content API | the content API only | designer |
| `levels/` | Maps from reusable room, prop, interactable and task-station sub-scenes | the content API only | designer |
| `tools/`, `tests/` | Task runner, checks, bot harness; unit, integration and bot-match tests | everything (tests) | engineer |

Changing a boundary is a stop-and-ask item and gets an ADR.

## 2. Data flow

```
client (local player)                host                                         every client
  input ──► intent ──► net ──► server: validate ──► core: command ──► events
                                     server: filter per peer ◄───────────┘
                                           │  one message per recipient
                                           └──► net ──► client: filtered view ──► UI, avatars, audio
```

- Clients send **intents**, never state. The host's own client is a normal recipient of the filtered stream.
- `core/` is deterministic: the same seed and commands give the same events, so a match can be replayed in tests
  (§3.3).
- `server/` checks what the transport knows (sender, decoding, size, rate); `core/` checks the rules (phase, life
  state, hand, reach, stamina, cooldowns) and says who is entitled to each event (§4.1, §5).

## 3. Match state machine

The game mode defines its phases, as an explicit state machine
([ADR](decisions/2026-09-29-game-modes-define-the-phases.md)). Designed in #32
([ADR](decisions/2026-09-29-match-loop-intents-events-and-entitlement.md)); the rules and every number named here are
in the [MVP rules](decisions/2026-09-29-mvp-rules.md), and the numbers are placeholders, "not a decision".
- **Base mode:** Lobby → Countdown → Loading → Round → End → Lobby. Roles are dealt and packages scattered on the
  way into Round.
- **Meetings mode** (later, #35): adds Meeting → Vote → Resolution.

### 3.1 The loop, and how a game mode supplies its phases
- `core/` has one loop, `Match`, that knows no game mode. It owns the `MatchState`: the roster, the settings, each
  player's life state (alive, ghost, left), position, hand slot, health and stamina, the items, the tasks with their
  stations and per-task state, the bodies, the cooldown and counter tables, the per-part state, the match clock and
  the RNG streams (§9.1 says what each holds). The match state outlives phases, so Round → Meeting → Round keeps
  everything. What lives only as long as one phase (the countdown's end tick, the loading acks) is in that phase's
  own object, created on entry (§9.1).
- A **game mode** is data (a `GameMode` `Resource`, §9). It lists:
  - the phases, each an id plus a phase class and its parameters, and the first phase;
  - per phase: the intents it accepts and from whom (an allowlist); its **tick systems** in the order they run (the
    base mode's Round: task types that tick; the other phases have none); whether it checks the win conditions (the
    base mode's Round only; §9.2 says when); whether the match clock runs; which voice rule applies (§6); which level
    is loaded; and whether snapshots are sent. Stamina and cooldowns need no tick system: they are settled when used
    (§7.1, §9.4);
  - a **transition table** of rows *from phase, outcome → to phase, actions*.
- An intent the phase's allowlist does not name, or from a sender it does not name, is rejected (`not_accepted`;
  the senders are a newcomer, any player, the living, ghosts or the host). An accepted intent goes to the phase class, or to the
  content part that handles it (an action such as pick up, a throw #37, or a body report #35; §9.2: the rule of the
  held item, the role or the mode): a new action is a part plus an allowlist entry, not an edit of the phase class.
- A **phase class** handles its own commands and timers (the countdown, the loading deadline, a vote timer), emits
  events, and reports **outcomes**: named triggers such as `all_ready`, `cancelled` or `won`. Any content part may
  report an outcome as well, so a new trigger (a meeting button, #35) needs no change to the phase it runs in.
- After every command, every tick, and every phase entry, `Match` takes the first outcome reported in that step,
  looks it up in the table, runs the row's actions
  (effects such as the deal's `DealRoles`, §9.4), exits the phase and enters the next. Rows are keyed by an outcome,
  so a transition without a trigger cannot be written; an outcome without a row fails loudly, and a unit test drives
  every row. Checking on entry means a phase whose condition already holds (every player ready when the Lobby is
  re-entered) moves on without waiting for another command. A later outcome in the same step is dropped and logged in
  every build: a condition (`all_ready`, `won`) is re-checked at the next step anyway. A one-off trigger (a meeting
  button, #35) comes from the rule of the intent that starts its step, so it is first unless an earlier effect of the
  same command already ended the phase; then its sender gets `Rejected` with the reason `outcome_dropped`, so the
  loss is visible. That reason means "applied, but the outcome was dropped": unlike a refusal (§9.2), the rule's
  costs were paid and its effects ran.
- The meetings mode (#35) is then data plus the classes Meeting, Vote and Resolution, with rows such as
  `Round, meeting_called → Meeting`, `Resolution, resume → Round` and `Resolution, won → End`. The deal runs only on
  `Loading, all_loaded → Round`, so returning to Round deals nothing; Meeting stops the clock by its phase flag.
  `Match` does not change.

### 3.2 Base mode: phases and transitions
A **player** is a peer whose `Hello` was accepted; *everyone* in an audience means every player (§5). A connected
peer without an accepted `Hello` is in no rule, receives nothing but a `Rejected`, and `server/` drops it after the
hello deadline.

| Phase | On enter | Accepts (§4.1) | Voice (§6) | Clock |
|---|---|---|---|---|
| Lobby | joins allowed | `Hello`, `MoveClaim`, `SetReady`, `ChangeSettings` (host); leave | proximity | stopped |
| Countdown | its end tick: now + 5 s | `Hello`, `MoveClaim`, `SetReady(false)`; leave | proximity | stopped |
| Loading | the roster is frozen; joins refused; `LoadMatch`; the loading deadline | `LoadAck`; leave | nobody | stopped |
| Round | the deal has run (below) | living: `MoveClaim`, `PickUp`, `PutDown`, `Use`; ghosts: `MoveClaim`; leave | round rule | runs |
| End | frozen: no movement, no snapshots | `ReturnToLobby` (host); leave | nobody | stopped |

| From | Outcome: its trigger | To | Actions |
|---|---|---|---|
| (start) | the host creates the session | Lobby | |
| Lobby | `all_ready`: every player is ready, and the settings fit the map for the current player count (packages, circles, knives and players within the map's spawn points, the demands per spawn tag of §9.4; circles within the palette's colours; 1 to 10 players) | Countdown | |
| Countdown | `cancelled`: a `SetReady(false)`, a join or a leave | Lobby | none: ready flags and positions stay, so after a leave `all_ready` fires on entry and restarts the 5 s |
| Countdown | `countdown_done`: the end tick is reached | Loading | |
| Loading | `all_loaded`: every player of the frozen roster confirmed. A leave, or a client's missing `LoadAck` at the loading deadline, drops that player from the roster. The host (peer 1) is never dropped, so the roster is never empty: if its own load fails, `server/` ends the session, which clients see as the host lost (#40) | Round | the deal (§3.3): `DealRoles`, `DealTasks`, `SpawnItems` (knives), `PlacePlayers`; `StartClock` |
| Round | `won(winner)`: a win condition (§3.4) | End | `EndMatch`: `MatchEnded`. The clock stops because End's clock does not run |
| End | `back`: the host's `ReturnToLobby` | Lobby | `ResetMatch`: the match state reset from the roster, everyone un-ready; `PlacePlayers` in the lobby |

The lobby shows why `all_ready` cannot fire (for example more packages than spawn points). The host leaving ends the
session in every phase (§3.5); it has no row, because `core/` runs on the host and stops with it.

**Placement on a scene change.** The `End → Lobby` row and the deal place every player at a spawn point of the new
scene and set the host's position for them: `PlayersPlaced` tells everyone where (positions are public), and each
player gets a private `Correction` with its own new epoch, because a public epoch would count a player's corrections,
which mostly come from hidden stamina. A joiner is placed at a lobby spawn point and gets its spot and epoch in
`Welcome`. Claims still in flight from the old scene carry the old epoch and are dropped as stale (§7). A cancelled
countdown changes no scene and places nobody.

### 3.3 Time and randomness
- **Ticks.** The host runs `core/` at the core tick rate (20 Hz), from its physics step (§7.1). `server/` stamps each
  command with the host tick on which it applies; `core/` never reads a clock. Durations in data are seconds,
  converted to ticks when the mode's data and the settings are loaded into `Match`: the countdown is 100 ticks, the
  knife's interval 10. Per-tick amounts (sprint cost, regeneration) are rounded toward zero once, at that conversion.
- **Order inside a tick:** (1) the commands, in the order the host received them, with an outcome check after each.
  `server/` puts the loopback's messages and the network's in one queue by arrival, so the host's own client gets no
  priority. (2) The phase's own timers. (3) The current phase's tick systems in the mode's order, then the match
  clock if the phase's clock runs. The win conditions are checked after every fact and at the end of every step
  (§9.2), so a delivery in the last tick counts: its command came before the clock ended.
- **The match clock** counts only the ticks of phases whose clock runs. Every entry into such a phase announces the
  clock's end as a host tick (`PhaseChanged`), so a clock paused for a meeting (#35) is re-announced on resume.
- **Seeds.** `server/` takes one 64-bit session seed from the operating system's entropy (never the time) when the
  host starts and gives it to `Match`; match *k* uses a seed derived from the session seed and *k*. Each purpose
  (`roles`, `circles`, `tasks`, `packages`, `knives`, `spawns`), named in the data of the part that draws (§9.4),
  gets its own `RandomNumberGenerator`, seeded by a fixed mixing
  function of the match seed and the purpose's name (for example SplitMix64 over the seed and an FNV-1a hash of the
  name; not `String.hash()`, whose algorithm is no documented contract). In GDScript `>>` on `int` is arithmetic, so
  the implementation masks after each shift, and its unit test pins known outputs. A new purpose never shifts the
  draws of the existing ones. Shuffles are our own Fisher–Yates over the injected RNG (`Array.shuffle()` uses the
  global one), and inputs are iterated in a stable order: players by peer id, spawn points in their level order.
- **The deal** (the actions of the `all_loaded` row, §9.4), in this order: roles (`DealRoles`: dissidents =
  min(setting, N−1), drawn from the roster); then `DealTasks`, which runs Delivery's deal: circle positions and
  colours (one circle per package, over the map's circle spawn points), package positions, and tasks (per player in
  peer-id order, *tasks per player* tasks of *subtasks* packages, each package drawn from the placed ones and bound to
  a random circle of its own, whose colour it takes); knife positions (`SpawnItems`); player spawn points
  (`PlacePlayers`). Item and station ids are assigned in spawn-point order and `ItemSpawned` and `StationPlaced` are
  emitted in id order, so an id says nothing about its owner or task. Packages and knives share spawn points when
  their item kinds name the same spawn tag; a marker carries one tag, and a deal puts at most one item on a marker
  (§9.6). A package that spawns inside its own circle is delivered at once, by the rule; the `package` and `circle`
  tags keep the two kinds of spawn points apart.
- **Exact numbers.** Health and stamina are integers in thousandths, so a replay on another machine matches exactly.
  Positions are the claims as received.
- **Replay.** The command log holds everything `core/` is given: the session seed, the game mode's path and a hash
  of its content (every resource it loads, sub-resources included), every command with its tick and order (the ones
  `server/` originates too: `PeerConnected`, `PeerLeft` with their peer ids, `ItemRested` #37), the levels'
  `LevelLayout`s (§9.1), and every `WorldQuery` answer. A replay reads the answers from the log instead of asking the
  level, and refuses to run when the mode's hash differs (after an edit in `content/`, say the knife's damage, it
  would silently diverge); unit tests use a fake `WorldQuery`. Seeds and RNG state never leave the host (§5).

### 3.4 Win conditions (base mode)
Content parts (§9.5), checked in Round only, in the mode's order, after every fact and at the end of every step
(§9.2):
- **Crew:** every task done, that is every subtask done (in the MVP a subtask is one package delivered) →
  `won(crew)`.
- **Dissidents:** no crew member alive (dead or left) → `won(dissidents)`; the clock reaches its end with a subtask
  not done → `won(dissidents)`, with 0 dissidents too.

"The first win condition met ends the round" (MVP rules) also orders the effects inside one command. A hit that
kills the last crew member, whose package then drops into its circle, meets "no crew alive" before the delivery:
the dissidents win. The same holds for the last crew member leaving with the last package over its circle. The
check after every fact is what makes this so: a death or a leave raises its fact before the held item drops (§9.2).

### 3.5 Joining, leaving and the host
| Phase | A client joins (its `Hello` is accepted) | A client leaves |
|---|---|---|
| Lobby | `PlayerJoined` to everyone, `Welcome` to it | `PlayerLeft` |
| Countdown | as in Lobby, and `cancelled` | as in Lobby, and `cancelled` |
| Loading | refused: `core/` emits `RefuseJoins` on entering Loading and `AllowJoins` on entering Lobby, and `server/` sets `refuse_new_connections`. A peer whose connection completed anyway gets `DisconnectPeer` | dropped from the roster; `PlayerLeft` |
| Round | refused, as in Loading | life state `left`, which counts as dead for the win conditions; the avatar is removed and no body stays; the held item comes to rest on the floor below where the player stood (§7.1); `PlayerLeft` |
| End | refused, as in Loading | `PlayerLeft` |

- A client's missed loading deadline: `core/` emits `DisconnectPeer(p)` for `server/` and treats p as leaving.
- **The host is lost:** there is no `core/` event: `core/` runs on the host. How a client notices is a transport
  signal (#40); the client returns to the main menu with a message.

## 4. Protocol

**Model** ([ADR](decisions/2026-09-29-listen-server-and-message-layer.md)):
- Listen server: one player hosts as peer 1 and plays; no dedicated server. The host's own client talks to the host
  through an in-process loopback transport, with the same codec and per-peer filter as every other client.
- Own messages over `MultiplayerPeer` (ENet first), not RPCs, `MultiplayerSpawner` or `MultiplayerSynchronizer`:
  every outgoing message is built per recipient in one place, which the leak test checks (§5).
- The host leaving or crashing ends the match; clients return to the main menu with a message. No host migration
  and no reconnection in the MVP. A client leaving mid-match counts as dead for the win conditions, and its held
  item drops where it stood. Nobody joins during a match (`NetTransport.set_refuse_new_connections`).
- The game scene loads with threaded loading and a longer ENet timeout; the round starts when every peer still in
  the roster confirmed it loaded (§3.2).
- The MVP is played over a LAN or a VPN (Radmin VPN, ZeroTier, Tailscale), plus a UPnP attempt. Internet play
  without a VPN is the M6 ADR.

**Transport** (`net/transport/`, #40):
- `NetTransport` is all game code sees: `host`, `join`, `poll`, `send(to_peer, kind, payload)`, `close`, `own_id`,
  `peers`, `set_refuse_new_connections`, `disconnect_peer`; signals `connected`, `connect_failed`, `peer_joined`,
  `peer_left`, `host_lost` and `packet_received`, fired only from `poll()`. A client sends only to the host (peer 1).
  The host's own client is peer 1 too.
- **`disconnect_peer(p)`** carries out `core/`'s `DisconnectPeer` (§3): p leaves `peers()` and `send` at once,
  `peer_left(p)` follows on the next poll like any leave, and p sees `host_lost` (a client cannot tell a kick from
  the host leaving) after whatever was sent to it before the call, a reason for example: ENet uses
  `peer_disconnect_later`, because a plain disconnect drops its queue. Until p acknowledges or times out (up to
  20 s) it keeps its ENet slot and id. The host's own client cannot be disconnected: the host ends the session
  instead.
  `set_refuse_new_connections` is what `server/` calls on `RefuseJoins` and `AllowJoins`.
- `EnetTransport` reads `ENetMultiplayerPeer` directly (no `SceneMultiplayer`); `create_server` keeps
  `max_channels` 0 and clients ask for `NetKindTable.CHANNEL_COUNT` channels. `LoopbackTransport` carries the same
  frames in process: `own_client_of(host)` is the host's own client on any hosting transport, and a `LoopbackHub`
  runs a host and clients in one process for headless tests. Every backend hands received bytes to one decode path
  (`NetTransport.receive_bytes`).
- **Frame:** `[kind: u8][payload size: u16 LE][payload]`. The payload is opaque to the transport; the schemas
  decode it, never into objects. `receive_bytes` rejects anything from a peer that is not connected (a client
  accepts only the host); `NetFrame.decode` rejects: shorter than the header, over the packet cap, an unknown kind
  (0 is never valid), the wrong direction, the wrong channel or transfer mode for the kind, a payload over the
  kind's cap, a truncated packet and trailing bytes. `NetRejects` counts rejections by reason, and by peer between
  summaries; the transport logs one summary line per 10 s at most, and one when the session ends.
- **One table** (`NetKindTable`) binds each kind to a lane, a direction and a payload cap. Lanes: `RELIABLE`
  (channel 0, reliable), `LATEST` (channel 0, unreliable ordered) and `VOICE` (channel 1, unreliable unordered).
  Unreliable payloads are capped at 1024 bytes so ENet never fragments them. The game's table,
  `NetKindTable.game()`, is empty until the schemas add rows.
- **Joining:** a client counts as connected only when the host's `ADMIT` arrives (a 3-byte frame of kind 0). ENet
  finishes its handshake before the host's code sees the peer, so Godot's `refuse_new_connections` (a silent reset)
  left a refused client "connected" until a timeout. A refusing host disconnects the new peer instead, and the
  client gets `connect_failed` at once; with no answer at all (no host, or a full one) the join gives up after 5 s.
  Unreliable packets can overtake the `ADMIT` and are then rejected as from an unknown peer: the host sends a
  new peer only reliable messages until that peer has sent its first message.
- **Peer ids are chosen by the client** (Godot refuses only 0, 1 and ids in use): they are neither secret nor
  unique over time. The host disconnects an arrival with an id of 1 or less (a negative target means "everyone but"
  to `MultiplayerPeer`, so a forged id -5 would receive everyone's messages; the headless run checks it) and one
  whose id is still leaving in the same poll. `send` accepts positive peer ids only.
- **The host is gone:** the client's `host_lost` fires once, on `peer_disconnected` for peer 1 or on the connection
  status dropping to disconnected, whichever comes first. After it the transport is closed. The inbox counts
  sessions, so a handler that closes and joins or hosts again never sees the old session's leftover events.
- **Timeouts** live in one place, `EnetTransport`: an ENet peer is dropped after 10 to 20 s without an
  acknowledgement (the spike's 2 to 4 s dropped peers during main-thread freezes); a crash is noticed that late.
- Checked by `tests/unit/net/transport/` and a headless run of a host (with its own client) and two clients, one
  process each, on 127.0.0.1:
  `tools\run.cmd run tests/integration/net/enet_host_and_two_clients.gd --headless --instances 3`. `verify`, and
  so CI, runs it on a free port (`-- --port=<p>`; AGENT_WORKFLOW §11).

*Open (M3):* intent and event schemas, their payload encoding and their rows in `NetKindTable.game()`, rate limits,
and what the host does with a peer that keeps sending rejected packets. The protocol version travels in `Hello`
(§4.1), not in the transport's `ADMIT`.
Every schema change updates this section in the same PR.

Lessons from the M1 spike (#13, #15; [voice ADR](decisions/2026-09-29-voice-approach.md)):
- Read packets from `ENetMultiplayerPeer` directly. `SceneMultiplayer` parses RPC, spawn and sync commands even if we
  send none, so any `@rpc` method under its root becomes callable by clients.
- Godot 4.7.2 `ENetMultiplayerPeer.create_server` passes `max_channels` as the host's incoming bandwidth
  (godotengine/godot#123963). Keep it 0 on the server and let clients ask for channels, or unreliable packets are
  throttled to 1/32.
- Bind each message type to its channel and reliability. Voice uses its own unreliable **unordered** channel;
  unreliable ordered drops reordered frames before the jitter buffer sees them.
- Decode defensively: a size cap, type and length checks, finite vectors, `bytes_to_var` without objects. Compare
  the re-encoded size, because `bytes_to_var` ignores trailing bytes.
- Count rejected and malformed packets and log a summary: one client can flood per-packet log lines.
- Budget floods by bytes, not messages. `var_to_bytes` framing is as large as an Opus frame: use a compact header.
- A 2–4 s ENet timeout drops any peer whose main thread freezes that long (level loads, breakpoints): use a longer
  timeout or reconnection. Cache `get_unique_id()`: it errors after the connection closes.
- Broadcast only public message types; everything else is built per peer by `server/` (§5).
- #21 (open): on one machine, a hard-killed windowed client can make the host lose the other client too. Test
  between machines before M3 depends on ENet.

### 4.1 Intents (MVP, #32)
What each intent means and who may send it; the schemas are M3. The sender is always the peer id the transport
reports, never a field of the message. `server/` checks what the transport knows (sender, decoding, size, rate) and
passes the intent to `core/` as a command stamped with the host tick; `core/` checks the phase's allowlist (§3.1)
and the rules below. A rejected intent gets `Rejected` to the sender, whose reason depends only on facts the sender
is entitled to (§5).

| Intent | Who, in which phase | The host validates |
|---|---|---|
| `Hello(name, version)` | a connected peer that is not yet a player, once; Lobby or Countdown | the name's length and characters; the version equals the host's, or the peer gets `DisconnectPeer`. Accepted, it is the join (§3.5) |
| `SetReady(ready)` | any player; Lobby (true or false), Countdown (false only) | that it changes the player's state |
| `ChangeSettings(settings)` | the host (peer 1) only; Lobby only | each value within its bounds; whether they fit the map is checked at `all_ready` |
| `LoadAck(match_id)` | each player of the frozen roster, once; Loading | the current match id: an ack from an earlier match is dropped |
| `MoveClaim(epoch, client_tick, position, velocity, facing, sprint, jumped, on_floor)` | living players in Lobby, Countdown and Round; ghosts in Round | the current epoch (else dropped as stale); speed for the life state and stamina; jumps; no teleport; the client tick rising at a bounded rate (§7, §7.1) |
| `PickUp(item)` | a living player; Round | the item lies on the ground (not held, not delivered); pick-up reach from the host's position of the player; line of sight; a full hand swaps (§7.1) |
| `PutDown(facing)` | a living player with an item in hand; Round | nothing from the client but the facing: the host computes the placement (§7.1) |
| `Use(facing)` | a living player; Round | the first `Use` rule of the held item's kind, the actor's role or the mode (§9.2); none: `nothing_to_do` (an empty hand, or a package in the MVP). The knife's rule: its minimum interval since this player's last hit, whatever weapon that was; stamina of at least the hit's cost; the host picks the targets (§7.1) |
| `ReturnToLobby()` | the host only; End | |

A connection and a leave are not intents: the transport reports them, and `server/` passes `PeerConnected(peer)` and
`PeerLeft(peer)` to `core/`. The join is the accepted `Hello`; `server/` disconnects a peer that sent none within
the hello deadline. Debug commands (§8) are outside this table and exist in debug builds only.

### 4.2 Events (MVP, #32)
Who receives each event is its audience (§5). A snapshot is not an event: §5 says what it holds for each peer.

| Event | Payload | Audience | When |
|---|---|---|---|
| `Welcome` | your peer id, spawn point and epoch; the roster with names and ready flags; the settings; the phase; the players' positions | the joiner | its `Hello` is accepted |
| `PlayerJoined` | peer, name, spawn point | everyone | its `Hello` is accepted |
| `PlayerLeft` | peer | everyone | a player leaves in any phase, or misses the loading deadline |
| `ReadyChanged` | peer, ready | everyone | `SetReady`; everyone un-ready on `End → Lobby` |
| `SettingsChanged` | settings; the derived demands per spawn tag (§9.4: in the MVP packages, circles, knives, player spawns) against the map's markers, the package count among them | everyone | `ChangeSettings`, and a join or leave in Lobby or Countdown (the demands change) |
| `PhaseChanged` | phase; the countdown's or the match clock's end as a host tick, if it runs | everyone | every transition |
| `CountdownCancelled` | reason: un-ready, join or leave | everyone | `cancelled` |
| `PlayersPlaced` | per player: spawn point | everyone | `End → Lobby`; the deal (§3.2) |
| `LoadMatch` | match id, map, settings | everyone | entering Loading |
| `PlayerLoaded` | peer | everyone | a valid `LoadAck` |
| `RoundStarted` | start tick | everyone | the deal |
| `RoleAssigned` | your role | that player | the deal |
| `Teammates` | a role and the peer ids of its players | each player of that role, for a role that knows its teammates (the dissidents) | the deal |
| `TasksAssigned` | your tasks: per task its id and task type, and per subtask its target, an item id or a station id (Delivery: the package; its circle is in `ItemSpawned`) | that player | the deal |
| `StationPlaced` | station, station kind (in the MVP the delivery circle), colour, position | everyone | the deal, in station-id order |
| `ItemSpawned` | item, kind, position; a package's circle and colour | everyone | the deal, in item-id order |
| `ItemPickedUp` | peer, item | everyone | `PickUp` |
| `ItemPlaced` | item, rest position, cause: put down, swap, death or leave | everyone | an item comes to rest |
| `PackageDelivered` | item, its circle (now shown as done) | everyone | the delivery check (§7.1) |
| `TaskProgress` | subtasks done, subtasks in total | everyone | a subtask is done |
| `TaskUpdated` | task, its subtasks done | the task's owner | one of its subtasks is done |
| `Swung` | peer, facing | everyone | a valid `Use` of a knife (`Strike`), whether or not it touched anyone |
| `Damaged` | amount, your health | the victim | a hit on them |
| `SelfStatus` | health, stamina, whether sprint is available | that player | on change, at most once per tick |
| `Died` | peer, body position | everyone | health reaches 0; no event names a killer or a cause |
| `Correction` | epoch, position, velocity | that player | a rejected `MoveClaim` (§7); a placement (§3.2) |
| `Rejected` | the intent's sequence number, reason | the sender | any rejected intent; an applied intent whose outcome was dropped (`outcome_dropped`, §3.1) |
| `MatchEnded` | the winning side (crew or dissidents), nothing else: no names, no roles | everyone | `won` |

Directives to `server/` have the audience *server* and reach no peer: `RefuseJoins`, `AllowJoins`,
`DisconnectPeer(peer)`.

## 5. Per-peer information filtering

- Each outgoing message is built for one recipient from what that peer is entitled to know.
- The information-leak test (bot harness, M3) asserts that no client ever receives anything it is not entitled to.
  It is the most important test in the project. Once it exists, prove it: inject a leak, see it fail, revert.
- `tools\run.cmd bots` (M3) starts a headless host and N headless bot clients that play a full scripted match, then
  asserts: the match ends, the winner is correct, no errors are logged, and no client received information it was
  not entitled to. It joins `verify` and CI. `host` and `join` launch a local host and clients for the humans'
  playtests.

**How entitlement is expressed** (#32; [ADR](decisions/2026-09-29-match-loop-intents-events-and-entitlement.md)):
- **Per event type.** Each event class declares its audience as a rule in `core/`: *everyone*, *only(peer)*,
  *role(r)*, *life(ghost)*, or *server* (a directive, §4.2). The rule is evaluated when the event is emitted, against
  the state after the command. An event has one audience: when parts of a fact have different audiences, `core/`
  emits separate events (a hit: public `Swung`, private `Damaged`).
- **Per entity for snapshots.** Every tick `core/` builds each peer's snapshot from visibility rules per entity: a
  living player's avatar (position, velocity, facing, held item) reaches every player of the match; a ghost reaches
  the dead only; bodies and items reach everyone. Nobody gets their own avatar: it moves client-side, and `Correction`
  settles disagreement. Private numbers are never avatar fields; they travel in `SelfStatus`.
- **`core/` says who is entitled; `server/` delivers.** The rule is game logic, like voice routing (§6). `server/`
  asks `core/` for each event's recipients and builds one message per recipient, *everyone* events included: it sends
  them to each player in turn, never to the transport's broadcast target, which would also reach a peer that is not
  a player (no accepted `Hello` yet, or a straggler about to be disconnected). It never adds a recipient or a field
  (`core/CLAUDE.md` and `server/CLAUDE.md` say so since 2a).
- **Never leaves the host:** seeds and RNG state; another player's role (the end screen shows none either), tasks,
  health, stamina and damage; ghosts, for the living. No event names a killer; a player who watches the swings and positions (both
  public by the rules) may still work it out.
- **Widening** follows from evaluating audiences at emission. Death: the player's life state becomes ghost, so from
  the next tick their snapshots include the ghosts and their voice joins the dead (§6); they learn no roles. End
  widens nothing: `MatchEnded` names only the winning side, and each player knows from its own role whether it won.
  A later mode that reveals roles would add an event with its own audience. A joiner's `Welcome` holds public facts only.
- **Knowledge never shrinks.** A peer keeps what it was sent. Resurrection (#34) narrows only what is sent from then
  on: a revived player remembers where the ghosts were, and #34 decides whether that matters.
- **Projection.** `Match` records the recipients of every event it emits, and per tick each peer's snapshot and the
  voice routing (who hears whom). `Match.view_of(peer)` returns that peer's events in order, its snapshot for every
  tick, and the speakers it may hear per tick: everything an honest client of that peer can know. The per-tick
  snapshots and speakers are recorded only with `Match.keep_history` on (off by default: about 1 GiB for 10 players
  over 10 minutes); the tests and the leak test turn it on, a real host does not. The M3 leak test
  compares what each bot actually decoded (voice frames included) with `view_of` of its peer; anything received that
  `view_of` does not hold is a leak.
- **Invariants that do not trust the declarations.** A wrong audience (say `Teammates` declared *everyone*) would
  pass the comparison above, because both sides read the same declaration. So unit tests and the leak test also
  assert facts written independently of them: for the whole session, a crew member knows one role, its own, and a
  dissident knows the dissidents' roles only; a living peer never gets a ghost's entity or voice frame; nobody gets
  another player's health, stamina, damage or tasks; no message holds a seed.

Rejected ways of expressing it (per field, per content part, filtering in `server/`): the ADR.

## 6. Voice pipeline

capture → encode (Opus) → routing decision per speaker and listener (`core/` rules, applied by the host's
`server/`) → listener → decode → jitter buffer → `AudioStreamPlayer3D` on the speaker's avatar.
- Routing inputs from the brief: distance, walls (occlusion), death (dead chat), meetings (everyone), items such as
  radios, role abilities.
- **Decided by the M1 spike** ([voice ADR](decisions/2026-09-29-voice-approach.md): **go**; numbers in #15
  and #16):
  - Codec: TwoVoIP (`two-voip-godot-4`) **v6.5** on Windows with Godot 4.7.2: 48 kHz mono, 20 ms frames,
    24 kbit/s, RNNoise. v6.6 crashes the editor on import (goatchurchprime/two-voip-godot-4#107).
  - Audio is **relayed through the host**, which routes each frame and never decodes it. Clients then receive only
    the voice they are entitled to (§5), and no peer-to-peer connection is needed.
  - Falloff happens on the listener: the `AudioStreamPlayer3D`'s `max_distance` equals the host's cutoff, so the
    sound fades to about zero where delivery stops. Only the host's rule decides who hears; the fade is cosmetic.
  - Measured: mouth to ear 365–375 ms on one machine, of which ~70 % is the audio devices and Windows, which
    Godot does not see. The game's own path is ~85 ms, plus ~23 ms for RNNoise. CPU for 10 players talking at once:
    ≤ 11 % of one core. A speaker uploads ~54 kbit/s on the wire.
- Lessons for M5:
  - Voice routing follows the same visibility rules as snapshots.
  - Stop sending during silence (voice activity detection or Opus DTX). A silent player's steady stream costs
    bandwidth and decodes, and shows roughly where they are once snapshots are filtered.
  - The host renumbers each speaker→listener stream. Forwarding the speaker's own sequence number shows a listener
    how much the speaker sent to others.
  - Replace the fixed 60 ms prebuffer with an adaptive one: over Wi-Fi the playback queue doubled to 75 ms.
  - After a listener leaves the cutoff, the audio already queued still plays at the last gain: flush or fade it.
  - Check whether TwoVoIP enables Opus in-band FEC; `decode_fec` may only conceal a lost frame.
  - Measure the host's per-send ENet cost with many listeners. In the spike, relaying one frame to one listener,
    ENet send included, cost 111–167 µs against 10 µs without the send, unexplained. At 81 sends per 20 ms that
    would be ~40 % of one core.
  - Godot 4.7.2 WASAPI reads only mono or stereo microphones; laptop arrays need 4.8 (#22). There is no
    input-latency API in 4.7.
- **Routing per phase in the base mode** (#32; radii in the [MVP rules](decisions/2026-09-29-mvp-rules.md)). The mode's
  data names each phase's rule (§3.1), so a meeting-wide rule (#35) is one more rule, not a change to the loop.

  | Phase | Who hears whom |
  |---|---|
  | Lobby, Countdown | every pair within the voice radius |
  | Loading | nobody: the old scene's positions are gone, and the phase lasts seconds |
  | Round | the living hear the living within the voice radius; a ghost hears the living and other ghosts only by distance, each within its own radius, measured from the ghost; the living never hear the dead |
  | End | nobody: the game is frozen |

  A player who left hears nobody and is heard by nobody.
- *Open (M5):* occlusion, dead chat, meetings, radios, push-to-talk or voice activity, echo cancellation, and
  lowering the device latency (options in the ADR).

## 7. Movement

Client-side movement for the local player; the host checks speed and teleports; remote players are interpolated.
*Open (M4):* snapshot rate and format, tolerances, correction policy. The core tick rate is set in §3.3; what the
host checks, in §7.1.

Lessons from the M1 spike (#13, #14):
- A starting point: 20 Hz snapshots, remote players drawn 2 ticks (100 ms) behind an estimated host clock. The
  delay must cover one tick interval plus the jitter; 100 ms covers about 30 ms of jitter. With 100 ms of jitter it
  starved 25 % of frames: M4 needs an adaptive delay.
- Stamp snapshots from the host clock and skip ticks; never count sends, or tick time falls behind for good after a
  host hitch. Estimate the host clock from a sliding window of arrivals, not an all-time maximum.
- The host's movement check should compare distance with the *client's* tick delta and separately bound the
  client's tick rate. The spike's budget, refilled from host time, rejected an honest player after a network stall. If a budget is used,
  refill it before reading a frame's packets.
- A correction is a reliable placement with an epoch. Moves in flight from the old epoch are dropped as stale, so
  one correction does not cascade.
- Client-side movement is a claim: walls and height need their own host checks (a ray or navmesh test) if they
  matter. Inputs expire or are bound to a tick, so a killed client's last intent does not keep it moving.

The local player's controller (#46, `client/player/`):
- `PlayerController` is a `CharacterBody3D` with its origin at the feet. Its numbers (speeds, jump height, capsule,
  eye and step height, stamina) live in one resource, `client/player/player_tuning.tres` (`PlayerTuning`), whose
  script defaults are 0 so no number is repeated in code. `core/` (stage 2d) and later content take them over.
- Stamina is behind `StaminaSource`: the controller asks before a sprint or a jump and reports each physics step.
  `LocalStamina` is a stand-in for `core/`'s stamina and the only copy of the rule on the client.
- A ghost (`ghost = true`) takes the living's path: the same capsule, gravity, floor, steps, slopes and jump, at the
  living's walk and sprint speeds times `ghost_speed_factor`. `StaminaSource` never refuses a ghost and records
  nothing for it. There is no flight (the engineer's correction of 2026-09-30, #46).
- Physics layers (`PhysicsLayers`, named in `project.godot`): 1 `world` (level geometry, Godot's default layer),
  2 `living_players`, 3 `ghosts`. The living collide with the world and the living; a ghost only with the world.
  Other living players are `RemotePlayerBody` kinematic capsules that only their owner's data moves.
- Steps: `move_and_slide` stops a capsule at any ledge, so the controller lifts itself onto a ledge up to the step
  height and glides over the edge until it snaps onto the top. What blocks it must be a ledge: a walkable blocker (a
  ramp, a low edge under the rounded bottom) is left to `move_and_slide`, and a ledge whose top is steeper than
  `floor_max_angle` (a steep slope, a round prop) is no step. Only the body jumps up; the view eases after it and
  lags at most one step height. A jump's take-off speed is solved for the physics step so the ballistic peak is the
  jump height.
- For the host's movement checks (M4 tolerances): the controller crosses a ledge's edge `STEP_CLEARANCE` (0.01 m)
  above its top, so a rise without a jump can reach step height + 0.01 m, and a jump from mid-crossing peaks as much
  over the jump height. A capsule's rounded bottom also rolls onto a ledge corner, so a jump can land the feet up to
  `capsule_radius * (1 - cos(floor_max_angle))` (about 0.12 m) above the jump height. The tolerances must cover both.

### 7.1 Authority for the MVP's mechanics (#32)
Each choice names the failure it prevents. Numbers: the [MVP rules](decisions/2026-09-29-mvp-rules.md) (placeholders,
"not a decision"), including the player's capsule, eye height and step height; tolerances: M4.
- **Geometry through a port.** `WorldQuery` is an abstract `RefCounted` in `core/` that answers the geometric
  questions of the rules: line of sight between two points, the floor below a point, and where an item placed from A
  towards B comes to rest. `server/` implements it over its own `World3D` holding the level's static colliders, never
  the client's scene, so a headless host and bots work the same; tests use a fake. `core/` stays pure, and every rule
  is still in one place. The 4.7.2 API limits `World3D.direct_space_state` to `_physics_process` on the main thread
  when physics runs on a separate thread, so the host ticks `core/` from its physics step; stage 2 checks that a new
  space answers queries before its first step.
- **Positions.** `core/` keeps each player's last accepted `MoveClaim` (position, velocity, facing, on floor). Every
  range rule (reach, hit zone, circle, voice) reads those, never a position inside another intent. Prevents: a client
  claiming to stand next to what it wants to grab.
- **Stamina** belongs to `core/` (ghosts are exempt, see Ghosts below). The client predicts its own from the published numbers to draw the HUD and gate
  Shift, and follows `SelfStatus`. `core/` keeps a ledger per player: the host tick up to which stamina is settled.
  A claim settles the ticks it covers (its client-tick delta, never past the current host tick): a covered tick in
  the sprint state in which the player moved horizontally costs 1/20 of the per-second cost, and every other covered
  tick regenerates. Before a jump or a hit is checked, the ticks not yet settled are settled with the last claim's
  sprint state, so an idle player is not refused on stale stamina; a later claim settles only what is left. The sprint state (Q7) starts when the claim holds the sprint flag and
  stamina is at least the start threshold, and lasts while the flag is held and stamina is above 0. An accepted jump
  or hit costs its amount at once. The allowed horizontal speed is the sprint speed in the sprint state, else the
  walk speed, measured over the client's tick delta (lesson above). Faster: `Correction` with a new epoch. Prevents:
  a client that never spends stamina, or spaces its claims out to regenerate between them, sprinting forever.
- **Jumps** are accepted only when the host has the player on the floor (the last claim, and the floor found by
  `WorldQuery` within step height) and stamina covers the cost (a ghost's jump needs none). Until the next landing the height above the floor is
  bounded by the jump height; a rise without an accepted jump beyond step height is corrected. Prevents: free or
  endless jumps, and flying.
- **Pushing apart.** Each client moves only its own player and collides it with the other living players' capsules
  at their interpolated positions: pushing apart is each client resolving its own overlap. The host tolerates overlap
  and never corrects it. Prevents: two clients that see each other 100 ms late snapping each other back and forth.
  Accepted: a modified client can walk through players. Ghosts are outside this by construction: a living client
  never receives a ghost's position, so it cannot bump into one.
- **Ghosts** move like the living and get the same movement checks (floor, jumps, step height), with the walk and
  sprint speeds times the ghost speed factor (1.3), and stamina never limits them: a ghost's claims neither need nor
  spend it. They collide with the level client-side, not with the living or with other ghosts. `PickUp`, `PutDown`
  and `Use` from a ghost are rejected. The engineer corrected this on 2026-09-30 (#46): ghosts do not fly, so the
  host no longer bounds a 3D flight speed. A side effect, not decided yet: with the same jump and 30% more speed, a
  ghost jumps 30% farther; the recommendation is to accept it and keep gaps only a ghost could cross out of the map.
- **Walls.** The MVP host does not check movement through walls (nobody asked for cheat protection). It does check
  walls for hits, pick-ups and placement, because there an honest client would otherwise stab or grab through a thin
  wall.
- **Hits** (the knife's `Use`: `Strike`, §9.4). The host picks the targets: every living player other than the
  attacker whose capsule has a point within
  the weapon's reach of the attacker's position and within half the weapon's angle of the facing, overlapping
  vertically, and in line of sight from the attacker's eye. Each takes the weapon's damage; the zone lives in the
  weapon's data. The minimum interval between hits is per player, so swapping to a second knife does not skip it.
  The facing is a claim, which is harmless because the reach is the host's. No lag compensation in the MVP: at walk
  speed a target is up to ~0.5 m ahead of what the attacker saw (100 ms of interpolation) against a 1.5 m reach. The
  playtest decides; rewinding targets to the attacker's view is the fallback. Prevents: hits on someone far away,
  behind a wall, without a weapon, or without stamina.
- **Pick up and swap.** The client names the item; the host checks reach and line of sight from its own positions.
  With a full hand, the held item is put down where the picked-up one lay, a spot already known to be valid.
- **Put down.** The client sends only its facing. The host places the item at the put-down distance along the
  horizontal facing, through `WorldQuery`: stopped before a wall and dropped to the floor. Prevents: a package put
  straight onto its circle across the map, or into a wall.
- **Drops.** An item dropped at a death or a leave, and a body, come to rest on the floor below the player's last
  position (through `WorldQuery`), never in mid-air.
- **Delivery.** The rule is "the package rests inside its circle, however it got there". So one check runs whenever
  an item comes to rest: a put-down, a swap, a drop at a death or a leave, the spawn, and later a throw, whose rest
  `server/` reports from its physics (`ItemRested`, #37). A package resting within its own circle's radius, on the
  circle's floor, is delivered: it stops being interactive (`PickUp` is rejected) and its circle is shown as done.
  Holding a package over its circle never counts, because it is not at rest.

## 8. Debug tooling

A dev console and debug commands (spawn bots, force role, skip phase, show hidden info locally) in debug builds
only, so the designer can test a mechanic alone.

## 9. Content API (the engineer–designer contract)

A mechanic is data: `Resource`s composed from parts the engine provides. Adding a mechanic should usually mean
adding data plus at most one new part class, never changing the core loop: that is the test of this API (§9.8). The
designer's agent uses **only** the parts listed here. A missing part becomes an `engine-request` issue; the engineer
adds it with tests and lists it here in the same PR.

**v0** (#33, [ADR](decisions/2026-09-29-content-api-v0.md), accepted by the engineer) is built in stage 2; the
designer reviews it before v1 (#38). 2a (#49) built the base class of every kind, the loop and `PlacePlayers`. Every part names the stage-2 task that builds it (#32's handoff, 2a to 2j); a
part is usable in data once its row or entry names the PR that built it. Every number is a placeholder from the
[MVP rules](decisions/2026-09-29-mvp-rules.md), "not a decision".

### 9.1 Definitions and state
- **Definitions are data.** Each kind (§9.3) is a `Resource` class in `core/`; its instances are `.tres` files in
  `content/`, or sub-resources inside one. The phase class is the exception: its `PhaseSpec` is the `Resource`. A part's settings are its exported properties, in the units a person
  thinks in: seconds, metres, degrees, whole points. `Match` converts them with the one rounding rule of §3.3.
- **Definitions hold no match state.** Godot shares loaded resources: a later load of the same path returns the
  cached instance (4.7.2 `Resource` docs). A counter on a part would leak between matches, between unit tests in one
  process, and into replays. So every part (condition, effect, tick system, voice rule, task type, win condition) is
  a stateless definition, and what changes has one of three homes:
  - **`MatchState`** (§3.1), for what outlives a phase: players; items (kind, where: on the ground, in a hand or
    locked, position); tasks, each with a **task state** object (`RefCounted`) that its task type creates in its deal
    and alone reads and writes (Delivery: which subtasks are done; #36: the time in the zone per subtask); stations;
    **bodies** (peer → rest position, from `player_died`; 2g); two tables keyed by names from the data,
    **cooldowns** (the tick at which a player last paid a key, such as `hit`) and **counters** (an integer per player
    and key, such as uses left, #34); and a **per-part state** table, one `RefCounted` per key that a part class
    declares, for state a new part class needs that fits none of the above. So a new part adds state without a new
    field in `MatchState`. `ResetMatch` clears all of it.
  - **The phase object.** A `PhaseSpec` names a phase class (a script) and its settings. On each entry into the
    phase `Match` creates a fresh object of that class (`RefCounted`, not a `Resource`) and drops it on exit. It holds
    what lives as long as the phase: the countdown's end tick, Loading's acks and deadline, later #35's votes. A
    result that must outlive the phase leaves as the outcome's argument (a tally, to a transition action) or goes
    into `MatchState`.
  - **Nothing else.** A part that needs state and fits neither is a design error to raise in its PR.
- **`core/` loads no files.** `server/` (and the tests) load the game mode, read each level's markers into a
  `LevelLayout` (§9.6), and hand both to `Match`. The command log records the layouts and the mode's hash, so a
  replay needs no level (§3.3).
- **Checked on load**, in two parts. `Match` refuses a mode with errors, listing them all.
  - *The mode alone:* a phase, outcome, intent, setting, role, side or item kind that a part names but the mode does
    not declare; an outcome a phase can report without a row (§3.1); an accepted intent that neither the phase class
    nor any rule handles; two rules on one trigger in one owner; a number outside its part's bounds. A unit test
    (2a, `tests/unit/content/content_modes_test.gd`) loads every mode in `content/modes/` and runs this part
    (`ModeCheck`).
  - *With the layouts* that `server/` or a test hands in: a spawn tag that a part places on and a map lacks; a
    marker with two tags; a lobby with fewer `lobby_player` markers than the mode's maximum of players. `Match` runs
    this part on creation. The content test runs it with the layouts of the mode's levels, read by the marker reader
    (2j); until 2j it runs the first part only.
- **Where a value comes from.** A part reads its own settings. A value the host changes in the lobby is a **match
  setting**: the mode declares it (`SettingSpec`: id, default, bounds), and a part names it in a property ending in
  `_setting` (`count_setting = knives`). A part never reads another part's settings. So the knife's numbers sit in
  the knife's own rule (§9.5), and a second weapon is a second item kind with its own numbers.

### 9.2 Rules: trigger → conditions → effects
A **rule** is the unit of behaviour: `trigger`, then `conditions`, then `effects`.
- **Trigger** (*when*): the name of an intent (`PickUp`, `PutDown`, `Use`) or of a **fact** (table below). A trigger
  with settings of its own ("every 2 s") would become a class; v0 has none.
- **Conditions** (*only if*) are checked in order and change nothing, apart from settling stamina up to now, which
  only applies ticks that have passed (§7.1). The first that fails stops the rule: for an intent, the sender gets
  `Rejected` with that condition's reason; for a fact, nothing happens. Every condition has `negate: bool` (false); a
  negated condition rejects with `not_allowed`. A **cost** is a condition that is also paid (stamina, a cooldown,
  later a use): all conditions and costs are checked first, then every cost is paid in order, then the effects run,
  so a refused intent pays nothing. (`outcome_dropped`, §3.1, is sent after an applied intent, not a refusal.)
- **Effects** (*what happens*) run in order. An effect changes `MatchState` only through `core/`'s own rules (life,
  items, stamina), emits events, raises facts, and may report an outcome (`ReportOutcome`, §3.1).
- **A fact is handled at once, depth first.** When an effect raises one, the rules on it run (the mode's reactions,
  then each task type's check, in the mode's order), then the current phase's win conditions are checked, and only
  then does the raising effect go on. A chain deeper than 16 facts is a bug: `Match` stops it with an error in every
  build.

| Fact | Raised when | The rule sees (**hidden** fields in bold) |
|---|---|---|
| `item_rested` | an item comes to rest: put down, swapped, dropped at a death or a leave, spawned; later thrown (`ItemRested`, #37) | the item, the cause, the rest position |
| `player_died` | a player's health reaches 0, before the held item drops | the player, the body position; no killer, as no event names one (§4.2) |
| `player_left` | a player leaves while the life state counts (Round, §3.5), before the held item drops | the player |
| `subtask_done` | a task type completes a subtask | the task; **its owner** and **its task type's detail** (private: `TaskUpdated` only) |
| `clock_ended` | the match clock reaches its end (§3.3) | nothing more |

A reaction that copies a hidden field into an event whose audience is wider than that field's (a mode reaction
that announces `subtask_done`'s owner to everyone) is a leak. Its entry must say so, and the reviewer of its PR
checks it against the §5 invariants.

**The owner of a rule decides whom it applies to**, so the rule needs no condition for that:

| Owner | Holds | Applies |
|---|---|---|
| Item kind | `actions`: rules on intents | while a player holds an item of that kind (the knife's `Use`) |
| Role | `actions` (abilities) | to the players with that role (none in the MVP) |
| Game mode | `actions`, and `reactions` (rules on facts) | to every player, and to every fact (no reactions in the MVP) |
| Task type | its own check of facts, in its class | to its tasks (Delivery on `item_rested`) |

- **An intent** that the phase accepts from this sender (§3.1) goes to the phase class if the class handles it
  (`Hello`, `SetReady`, `LoadAck`, …); `MoveClaim` goes to the movement rule (§7.1); any other goes to the first rule
  with that trigger among the held item's actions, the actor's role's actions and the mode's actions. If there is
  none: `Rejected` (`nothing_to_do`). So the item in hand decides what `Use` does, and a new item needs no new
  intent; a role's ability on `Use` fires only when the held item has no `Use` rule. That precedence is a gameplay
  rule, provisional for the designer (#38): a #34 medic holding a knife would stab, not revive.
- **Win conditions** (`WinCondition`: a side and its conditions) are checked in the mode's order, in phases whose
  spec says so (Round in the base mode): after every fact, and at the end of every step (a command, a tick, a phase
  entry). The first that holds reports `won(side)`, and once a step has an outcome no win condition is checked again
  in it. The check after every fact orders the effects of one command (§3.4): a hit that kills the last crew member
  raises `player_died` before the victim's package drops into its circle, so "no crew alive" is reported first. The
  check at the step's end catches a change that raised no fact.
- **Outcomes** come from phase classes, win conditions and `ReportOutcome`; the first in a step wins (§3.1). An
  outcome and its argument reach no peer: `PhaseChanged` names only the new phase, and only an event that a
  transition action emits can carry the argument (`EndMatch`: the side of `won`), with that event's audience.
- **Events and who sees them.** An effect emits event classes (§4.2), and each event class declares its audience,
  evaluated at emission (§5). Neither the data nor an effect chooses recipients: a mechanic that needs a new audience
  needs a new event class, which is an engine request. Each part lists every event it can emit, so reviewing a part
  shows what it reveals.
- **Rejection reasons** depend only on facts the sender is entitled to (§4.1). Each condition and cost names its
  reason. A condition that reads another player's hidden state (a role, health) must say so in its entry, because
  its refusal tells the sender something; v0 has none.
- **A public event can reveal its rule's owner.** A rule owned by a role, or gated by `ActorRole`, that emits an
  event to everyone tells everyone who watches it fire that the actor has that role (a blade only dissidents may use:
  whoever is seen swinging it is a dissident). That may be the design, but it must be chosen: each rule entry says
  whether its public events reveal the owner's role, and `Match` validation logs a warning for a role-owned or
  `ActorRole`-gated rule with an effect whose event goes to everyone. v0 has none.
- **Determinism.** Rules, conditions and effects run in data order, and players in peer-id order. A part that draws
  randomness names its RNG purpose in its data (§3.3), so a new part never shifts the draws of the others.

### 9.3 Kinds and where they live
The base classes and the kinds are in `core/content/` (the bot-scenario data classes in `core/content/scenario/`);
`Match`, `MatchState` and `Phase` in `core/match/`; each part beside the rules it implements (`core/items/`,
`core/combat/`, `core/tasks/`, … as split in stage 2). 2a creates the base class of every kind in this table but the
bot scenario's (2j), so stage-2 tasks that run in parallel share them instead of each inventing one; the parts and
phase classes come in the task each row names.

**What the later stage-2 tasks build on (2a, #49).** Each adds its own files and never edits `Match`:
- A part runs with a `MatchContext`: the `MatchState`, the mode, the `WorldQuery`, the tick; the actor and its
  intent (an action), the `Fact` (a reaction or a task type's check), or the outcome and its argument (a transition
  action, whose `layout` is the level being entered); and `emit`, `reject`, `raise_fact`, `report_outcome`,
  `rng(purpose)`, `setting(id)` and `error`. Names: `Intents`, `Facts`, `RejectReasons`.
- Events are `MatchEvent` subclasses in `core/events/`, each with its `audience()` (`Audience`: everyone, only,
  role, life, server) and a `const AUDIENCE_KIND`, from which `ModeCheck` warns about role-owned public events.
- `Phase` (handled intents, outcomes, settings check, end tick, enter, exit, tick, intents, peers connecting and
  leaving); the base mode's Lobby, Countdown, Loading and End classes are skeletons that 2b fills; `MovementRule`
  (`core/movement/`) takes `MoveClaim`s and checks only the epoch until 2d.
- `MatchState`: players (`PlayerState`, life ALIVE, GHOST or LEFT), settings, map, items (`ItemState`: ground,
  hand or locked), tasks (`MatchTask` with its `TaskState`), stations, bodies, the cooldown and counter tables,
  `part_state`, the clock, the winner, `RngStreams`, and `reset_match` for `ResetMatch`.
- server/ and the tests drive `Match`: `start`, then per tick `apply` for each command and `tick`; `take_outbox`
  (events with recipients), `snapshot_for`, `speakers_for`, `view_of`, `command_log` and `Match.replay` (a replay
  that diverged from the recorded `WorldQuery` answers says so in `diagnostics`).
- The loop's own guards: only a phase class takes an intent from a newcomer (ModeCheck); an outcome reported while
  a row's actions or the old phase's exit run is an error, not the next phase's outcome; a step stops after 16
  transitions. `TickSystem` and `TaskType` declare `reported_outcomes()`, so ModeCheck requires their rows.
- No range rule (InReach 2e, Strike 2g) and no `server/` wiring (M3) lands before 2d: until then `MovementRule`
  stores a claimed position unchecked.
- Two class names differ from their kind: `GameRole` and `RuleEffect` (a global `Role` or `Effect` would shadow an
  enum of `NetTransport` or GdUnit4).

| Kind | Answers | Class in `core/` | Data | MVP instances |
|---|---|---|---|---|
| Game mode | which phases, rules and settings a match has | `GameMode`, with `PhaseSpec` (its allowlist of `AcceptSpec`s), `Transition`, `SettingSpec`, `SideSpec`, `PlayerRules` | `content/modes/` | the base mode |
| Phase class | what a phase does itself: its own intents, timers and outcomes | `Phase` subclasses (`RefCounted`; a fresh object per entry, §9.1) | named by a `PhaseSpec`, with its settings | Lobby, Countdown, Loading, Round, End |
| Rule | trigger → conditions → effects; an **action** is a rule on an intent, a **reaction** a rule on a fact | `Rule` | inside its owner | PickUp, PutDown, the knife's Use |
| Condition, cost | *only if*; a cost is also paid | `Condition`, `Cost` subclasses | inside a rule or a win condition | §9.4 |
| Effect, transition action | *what happens*; a transition action is an effect that a transition row runs, with no actor | `RuleEffect` subclasses | inside a rule or a row | §9.4 |
| Tick system | what runs every tick of a phase, in the phase's order | `TickSystem` subclasses | listed per phase | TaskTicks |
| Voice rule | who hears whom in a phase (§6) | `VoiceRule` subclasses | one per phase | Silent, Proximity, RoundVoice |
| Role | a side, what it knows, its abilities; a display name | `GameRole`, `RoleQuota` | `content/roles/` | Crew, Dissident |
| Item kind | a thing a player can hold, and what using it does; a display name (the HUD's held item) and its spawn tag | `ItemKind` | `content/items/` | Package, Knife |
| Task type | how tasks are dealt and done; what it demands of the map | `TaskType` subclasses, each with its `TaskState` (§9.1) | `content/tasks/` | Delivery |
| Task station | a place where a task is done, placed by its task type | `StationKind` (spawn tag, radius, colour palette) | inside its task type | the delivery circle |
| Win condition | which side wins, and when | `WinCondition` | `content/win_conditions/` | three (§9.5) |
| Interactable | a thing in the world that a player targets with an intent | v0: an item on the ground (`PickUp`). Fixed ones (a button) and bodies come with `Interact`, v1 (§9.8) | | packages and knives on the ground |
| Spawn point | where the deal may place something | `LevelLayout` in `core/content/` (2a): the markers by tag, in level order; `server/`'s marker reader fills it (2j) | markers in `levels/` (§9.6) | tags `lobby_player`, `round_player`, `package`, `knife`, `circle` |
| Bot scenario | a scripted match that exercises a mechanic | `BotScenario`, its steps and targets: data only, in `core/content/scenario/`; the runners in `tests/harness/` | `content/scenarios/` | §9.7 |

- **`PhaseSpec`**: the phase id; the phase class with its settings; the intents it accepts and from whom (a
  newcomer, any player, the living, ghosts, the host); its tick systems in order; whether it checks win conditions;
  whether the match clock runs; its voice rule; its level (the lobby or the map); whether snapshots are sent.
- **`Transition`**: from phase, outcome, to phase, and its actions (effects) in order, which see the outcome and its
  argument (`EndMatch` reads the side of `won`).
- **`GameMode`**: players (minimum, maximum); its match settings; `PlayerRules` (health, stamina, speeds, capsule);
  its sides (`SideSpec`: id and display name, which `MatchEnded`'s end screen shows); its roles; its item kinds; the
  lobby level and the maps (paths that `server/` loads); its actions and reactions; its task types and win
  conditions, in order; its phases, the first phase and the transitions. Validation (§9.1) refuses a role, side or
  item kind that a part names and these lists lack.
- **Task types are classes** with settings, not composed rules: Delivery's deal and its check depend on each other
  (which package belongs to which circle). The rules around a task (pick up, put down) are composed. A new task type
  is one new script: the class, with its `TaskState` as an inner class (§9.8). It declares what it demands of the map
  (per spawn tag, from the settings and the player count) for the fit check of §9.4.

### 9.4 Parts (v0)
**Conditions and costs** (a failed one rejects an intent with its reason, which reveals only what the column says):

| Part | Passes when | Settings | Rejects with | Built in |
|---|---|---|---|---|
| `ItemOnGround` | the rule's item exists, lies on the ground (not held) and is interactive (not locked, as a delivered package is) | none | `unavailable`: whether an item is held or delivered is public | 2e |
| `InReach` | the item is within reach of the actor's last accepted position (§7.1) | `reach_m` (0.1 to 10; 2) | `out_of_reach` | 2e |
| `InSight` | the line from the actor's eye to the item is clear (`WorldQuery`) | none | `blocked` | 2e |
| `HoldsItem` | the actor has an item in hand | none | `empty_hand` | 2e |
| `ActorRole` | the actor's role is one of the listed (no MVP use) | `roles` | `not_allowed`: the actor knows its own role | with the first mechanic that needs it (#34) |
| `AllSubtasksDone` | every subtask of every task is done | none | (facts only) | 2h |
| `NoneAlive` | no player of the side is alive: each is a ghost or has left | `side` | (facts only) | 2h |
| `ClockEnded` | the match clock has reached its end | none | (facts only) | 2h |
| `Cooldown` (cost) | this player never paid this key, or at least `seconds` passed since it last did; paying records the tick | `key`, `seconds` (0 to 600) | `too_soon`: its own timing | 2g |
| `StaminaCost` (cost) | the actor's stamina, settled first (§7.1), is at least `amount`; paying spends it and emits `SelfStatus` (the actor) | `amount` (whole points, 0 to `PlayerRules`' stamina maximum) | `tired`: its own stamina | 2d |

**Effects in rules:**

| Part | What it does | Settings | Emits (audience); raises | Built in |
|---|---|---|---|---|
| `TakeIntoHand` | the item goes into the actor's hand; a held item is swapped: it rests where the picked-up one lay (§7.1) | none | `ItemPickedUp` (everyone); for a swap `ItemPlaced` (swap, everyone), then `item_rested` | 2e |
| `PutDownInFront` | the held item rests `distance_m` along the horizontal facing, stopped before a wall and dropped to the floor (`WorldQuery`, §7.1) | `distance_m` (0.3 to 3; 1) | `ItemPlaced` (put down, everyone); `item_rested` | 2e |
| `Strike` | picks the targets as in §7.1 (living, not the attacker, within reach and half the angle, overlapping vertically, in line of sight from the eye) and damages each, in peer-id order; at 0 health a target dies (the life rule, 2g) | `angle_deg` (1 to 360; 30), `reach_m` (0.1 to 10; 1.5), `damage` (whole points, 1 to 1000; 50) | `Swung` (everyone), even with no target; per target `Damaged` and `SelfStatus` (the victim). A death: `Died` (everyone), `player_died`, then the drop: `ItemPlaced` (death, everyone), `item_rested` | 2g |
| `ReportOutcome` | reports an outcome of the current phase (a meeting button, #35; no MVP use) | `outcome`, `argument` | an outcome (§3.1), which reaches no peer (§9.2) | with the first mechanic that needs it (#35); 2a builds the outcome reporting it calls |

**Transition actions** (effects that a transition row runs; the base mode's rows are in §9.5):

| Part | What it does | Settings | Emits (audience) | Built in |
|---|---|---|---|---|
| `DealRoles` | each quota draws its players from the roster; everyone else gets the default role. Roles forced by a debug command or a scenario (debug builds only, §8) replace the draws | `quotas` (`RoleQuota`: role, `count_setting`, `leave_at_least` (0 to 10; 1): the count is max(0, min(setting, N − leave_at_least))), `default_role`, RNG purpose (`roles`) | `RoleAssigned` (that player); `Teammates` (each player of a role that knows its teammates) | 2c |
| `DealTasks` | gives each player `tasks_setting` tasks, dealt by the mode's task types through the `TaskType` interface of 2a (§9.5, Delivery); with one task type, it deals them all | `tasks_setting` (`tasks_per_player`) | the task types' events | 2c, tested with a fake task type; Delivery's deal in 2f |
| `SpawnItems` | places `count_setting` items of `kind` on distinct random markers of the kind's spawn tag, at most one item per marker in a deal, into `MatchState`'s items (2a) | `kind`, `count_setting`, RNG purpose (`knives`) | `ItemSpawned` (everyone), in id order; `item_rested` (spawn) | 2c |
| `PlacePlayers` | places every player at a distinct random marker of `tag` (§3.2) | `tag`, RNG purpose (`spawns`) | `PlayersPlaced` (everyone); `Correction` with a new epoch (each player) | 2a (#49) |
| `StartClock` | sets the match clock's end to now plus the setting | `minutes_setting` (`match_duration`) | `RoundStarted` (everyone) | 2h |
| `EndMatch` | records the side of the `won` outcome as the winner | none | `MatchEnded` (everyone): the side only | 2h |
| `ResetMatch` | resets the match state from the roster: items, stations, tasks and their task states, bodies, roles, life, health, stamina, cooldowns, counters, per-part state, the clock and the winner; everyone un-ready | none | `ReadyChanged` (everyone), per player | 2b |

**Demands.** Every placing action, and every task type through `DealTasks`, answers one question: given the settings
and the player count, how many markers of which spawn tag does it need (and, for a station kind, how many colours).
2a defines that interface on `Effect` and `TaskType`, with no demand by default. `all_ready` (2b) sums the demands per
tag over every row into a phase on the map, compares each sum with the chosen map's markers of that tag (§3.2,
§9.6), and `SettingsChanged` shows them.

**Tick systems, phase classes and voice rules:**

| Part | Kind | What it does | Settings | Emits (audience) | Built in |
|---|---|---|---|---|---|
| `TaskTicks` | tick system | runs the tick of each task type that has one, in the mode's order (none in the MVP; #36) | none | the task types' events | 2f |
| `Lobby` | phase class | allows joins; `Hello` (the join), `SetReady`, `ChangeSettings`; leaves (§3.5); reports `all_ready` (§3.2) | none | `Welcome` (the joiner); `PlayerJoined`, `PlayerLeft`, `ReadyChanged`, `SettingsChanged` (everyone); `AllowJoins` (server) | 2b |
| `Countdown` | phase class | as Lobby for joins, leaves and `SetReady(false)`, each reporting `cancelled`; `countdown_done` `seconds` after entry | `seconds` (0 to 60; 5) | as Lobby, and `CountdownCancelled` (everyone); its end tick goes out in `PhaseChanged` | 2b |
| `Loading` | phase class | refuses joins; `LoadMatch`; takes `LoadAck`s; at the deadline drops who did not confirm; reports `all_loaded` | `deadline_seconds` (5 to 600; 60) | `LoadMatch`, `PlayerLoaded`, `PlayerLeft` (everyone); `RefuseJoins`, `DisconnectPeer` (server) | 2b |
| `Round` | phase class | nothing of its own: its intents go to rules, a leave to the life rule (§3.5) | none | none of its own | 2a (#49) |
| `End` | phase class | `ReturnToLobby` from the host reports `back`; leaves (§3.5) | none | `PlayerLeft` (everyone) | 2b |
| `Silent` | voice rule | nobody hears anybody | none | the routing per tick (§5) | 2i |
| `Proximity` | voice rule | every pair of players within the radius | `radius_m` (0.5 to 100; 8) | the routing per tick | 2i |
| `RoundVoice` | voice rule | the living hear the living within `living_m`; a ghost hears the living within `ghost_hears_living_m` and ghosts within `ghost_hears_ghost_m`, measured from the ghost; the living never hear the dead; a player who left hears and is heard by nobody (§6) | the three radii (each 0.5 to 100; 8, 8, 8) | the routing per tick | 2i |

The match clock itself is not a part: `Match` counts it in phases whose clock runs, after their tick systems
(§3.3), and raises `clock_ended`.

### 9.5 The MVP's content (provisional)
The first content, one entry each. It is provisional: built by the engineer's agent under the
[MVP content ADR](decisions/2026-09-29-mvp-content-built-by-the-engineer.md), reviewed by the designer in #38. Every
new part or piece of content gets an entry in this format:

```
#### <Name> (<kind>)
What it does: one sentence.
Settings: name: value or type (allowed values, default).
Produces: events (audience), facts, outcomes, state changes.
Visible to: who learns the result, and when.
Status: designed in #33 · built in <PR>. Tests: path.
```

#### Base mode (game mode)
What it does: the MVP match, Lobby → Countdown → Loading → Round → End → Lobby (§3.2).
Settings:
- players 1 to 10. Match settings, default (bounds): `match_duration` 10 min (1 to 60); `tasks_per_player` 2 (1 to
  10); `subtasks_per_task` 2 (1 to 10); `dissidents` 1 (0 to 9, lowered to N − 1 by the deal); `knives` 2 (0 or more;
  the map's `knife` markers bound it at `all_ready`).
- `PlayerRules`, value (bounds): health 100 (1 to 1000); stamina 100 (1 to 1000), regenerating 15 per second (0 to
  1000); walk 4.5 m/s (0.5 to 20); sprint 7 m/s (at least walk, to 30) for 20 per second (0 to 1000), from 20 (0 to
  the maximum); jump 1 m (0 to 5) for 10 (0 to the maximum); ghosts walk and sprint at those speeds × 1.3 (the
  engineer's decision of 2026-09-30; the bounds 1 to 3 are proposed, not confirmed); capsule radius 0.4 m (0.1 to 1) × height 1.8 m (0.5 to 3); eye 1.6 m (below
  the height); step 0.3 m (0 to 1). Health and stamina are whole points here, thousandths inside `core/` (§3.3).
- Sides: `crew` ("Crew"), `dissidents` ("Dissidents"). Roles: Crew, Dissident. Item kinds: Package, Knife.
- Actions: PickUp, PutDown. Reactions: none. Task types: Delivery. Win conditions, in order: every task done, no crew
  alive, time up.
- Phases (accepts; tick systems; win conditions; clock; voice; level): Lobby (§3.2; none; no; stopped; Proximity
  8 m; lobby), Countdown 5 s (§3.2; none; no; stopped; Proximity 8 m; lobby), Loading 60 s (`LoadAck`; none; no;
  stopped; Silent; map), Round (`MoveClaim` from the living and ghosts, `PickUp`, `PutDown` and `Use` from the living;
  TaskTicks; yes; runs; RoundVoice; map), End (`ReturnToLobby` from the host; none; no; stopped; Silent; map).
  Snapshots in Lobby, Countdown and Round.
- Transitions: §3.2. Their actions: `Loading, all_loaded → Round`: `DealRoles` (Dissident by `dissidents`, leaving
  at least 1; default Crew), `DealTasks`, `SpawnItems` (Knife by `knives`), `PlacePlayers` (`round_player`),
  `StartClock`. `Round, won → End`: `EndMatch`. `End, back → Lobby`: `ResetMatch`, `PlacePlayers`
  (`lobby_player`).

Produces: the events of its phases and parts. Visible to: as each of them says.
Status: designed in #33; the skeleton in 2a (#49), filled by 2b to 2i. Tests: the mode check of 2a
(`tests/unit/content/content_modes_test.gd`, §9.1), the scenarios
in `content/scenarios/` (2j).

#### Crew (role)
What it does: the side that wins only when every task is done (§3.4).
Settings: id `crew`; display name "Crew"; side `crew`; knows its teammates: no; actions: none. The default role of
`DealRoles`.
Produces: `RoleAssigned(crew)`.
Visible to: that player only (§5); `MatchEnded` names only the winning side, never a player's role.
Status: designed in #33; built in 2c. Tests: (2c), a path once built.

#### Dissident (role)
What it does: the side that wins when time is up or no crew member is alive; dissidents know each other.
Settings: id `dissident`; display name "Dissident"; side `dissidents`; knows its teammates: yes; actions: none.
Dealt by the quota `dissidents`, leaving at least one other player.
Produces: `RoleAssigned(dissident)`; `Teammates(dissident, peers)`.
Visible to: `RoleAssigned` to that player; `Teammates` to each dissident, and to nobody else.
Status: designed in #33; built in 2c. Tests: (2c), a path once built.

#### Delivery (task type)
What it does: a task of `subtasks_per_task` packages; a subtask is done when its package rests inside its own
circle, however it got there (§7.1).
Settings: `package`: the Package item kind; `circle`: a station kind (spawn tag `circle`, radius 1 m (0.2 to 10),
a colour palette: a list of distinct colours); `subtasks_setting`: `subtasks_per_task`; RNG purposes `circles`,
`packages`, `tasks`. One circle per package is fixed in v0, not a setting (MVP rules: each package its own colour
and circle).
- Deal: players × tasks per player × subtasks packages. Circles on `circle` markers with colours, packages on
  `package` markers, then per player in peer-id order its tasks, each package bound to a circle of its own whose
  colour it takes (§3.3). Then `item_rested` (spawn) for each package, so one that spawned in its own circle counts.
- Demands (§9.4): as many `circle` and `package` markers as packages, and as many palette colours as circles, since
  colours never repeat. More circles than colours fails the fit check at `all_ready` like a missing marker; the
  lobby shows it. The binding itself is the circle id in `ItemSpawned`; the colour is what players see.
- Check, on `item_rested`: a package of an undone subtask that rests within its circle's radius, on the circle's
  floor, is delivered: locked (no longer interactive), its circle done, its subtask done (`subtask_done`).

Produces: `StationPlaced` and `ItemSpawned` (with the circle and colour) in id order, `TasksAssigned` (per subtask
its package), `PackageDelivered`, `TaskProgress`, `TaskUpdated`; `subtask_done`. Its task state: which subtasks are
done.
Visible to: everyone, except `TasksAssigned` and `TaskUpdated`, which reach only the task's owner.
Status: designed in #33; built in 2f. Tests: (2f), a path once built.

#### Package (item kind)
What it does: the item a Delivery subtask moves; any living player may carry any package.
Settings: id `package`; display name "Package"; spawn tag `package`; actions: none, so `Use` with a package in
hand is rejected (`nothing_to_do`). Placed by Delivery.
Produces: `ItemSpawned`, `ItemPickedUp`, `ItemPlaced`; once delivered, `PackageDelivered`, and `PickUp` gets
`unavailable`.
Visible to: everyone.
Status: designed in #33; built in 2e and 2f. Tests: (2e and 2f), a path once built.

#### Knife (item kind)
What it does: the MVP's weapon: `Use` strikes in front of the holder.
Settings: id `knife`; display name "Knife"; spawn tag `knife`; actions: one rule on `Use` with costs `Cooldown`
(key `hit`, 0.5 s) and `StaminaCost` (25), and the effect `Strike` (30°, 1.5 m, 50 damage). The cooldown key is per
player, so swapping to a second knife does not skip the interval (§7.1). Placed by `SpawnItems` (`knives`).
Produces: `ItemSpawned`, `ItemPickedUp`, `ItemPlaced`; on `Use`: `Swung`, `Damaged`, `SelfStatus` (the attacker's
stamina, the victim's health), and on a death `Died` and the dropped item's `ItemPlaced`.
Visible to: `Swung` and `Died` everyone; `Damaged` only the victim; the attacker gets no confirmation of a hit; a
refusal (`too_soon`, `tired`) only the attacker. The public `Swung` reveals no role: the rule belongs to the item
kind, which any living player may hold (§9.2).
Status: designed in #33; built in 2g. Tests: (2g), a path once built.

#### Every task done (win condition)
What it does: the crew's only win.
Settings: side `crew`; conditions: `AllSubtasksDone`.
Produces: `won(crew)`, then `EndMatch`: `MatchEnded(crew)`.
Visible to: everyone, the side only.
Status: designed in #33; built in 2h. Tests: (2h), a path once built.

#### No crew alive (win condition)
What it does: the dissidents win when every crew member is dead or has left.
Settings: side `dissidents`; conditions: `NoneAlive` (side `crew`).
Produces: `won(dissidents)`, then `MatchEnded(dissidents)`.
Visible to: everyone, the side only.
Status: designed in #33; built in 2h. Tests: (2h), a path once built.

#### Time up (win condition)
What it does: the dissidents win when the clock ends with a subtask not done, with 0 dissidents too.
Settings: side `dissidents`; conditions: `ClockEnded`, `AllSubtasksDone` negated.
Produces: `won(dissidents)`, then `MatchEnded(dissidents)`.
Visible to: everyone, the side only.
Status: designed in #33; built in 2h. Tests: (2h), a path once built.

#### PickUp (action)
What it does: takes an item from the ground into the hand, swapping a held one (§7.1).
Settings: a rule on the base mode: trigger `PickUp`; conditions `ItemOnGround`, `InReach` (2 m), `InSight`;
effects `TakeIntoHand`.
Produces: `ItemPickedUp`; with a full hand, `ItemPlaced` (swap) and `item_rested` for the swapped item, so a package
swapped onto its circle is delivered.
Visible to: everyone; a refusal (`unavailable`, `out_of_reach`, `blocked`) only the sender. A mode rule: its public
events reveal no role.
Status: designed in #33; built in 2e. Tests: (2e), a path once built.

#### PutDown (action)
What it does: puts the held item down in front of the player (§7.1).
Settings: a rule on the base mode: trigger `PutDown`; conditions `HoldsItem`; effects `PutDownInFront` (1 m).
Produces: `ItemPlaced` (put down); `item_rested`.
Visible to: everyone; a refusal (`empty_hand`) only the sender. A mode rule: its public events reveal no role.
Status: designed in #33; built in 2e. Tests: (2e), a path once built.

#### Use (action; the knife's hit)
What it does: uses the held item, as its kind's rule says; in the MVP only the knife has one (above). It replaces
#32's `Hit` intent, so that a new held item is data, not a new intent.
Settings, Produces, Visible to: the knife's.
Status: designed in #33; built in 2g. Tests: (2g), a path once built.

#### Sprint (not a part in v0)
What it does: the `sprint` flag of `MoveClaim`, settled by the movement rule for every tick a claim covers (§7.1),
with the numbers in `PlayerRules`: 7 m/s, 20 per second, from 20.
Why not a part: a rule fires once per trigger, while sprint cost and speed apply to every covered tick of a
continuous claim. A mechanic that changes movement (a faster role, a slowing item) needs a movement modifier that the
movement rule reads: a new kind, v1 (§10).
Visible to: the player's own stamina in `SelfStatus`; speed is public through positions.
Status: designed in #33; built in 2d. Tests: (2d), a path once built.

#### Jump (not a part in v0)
What it does: the `jumped` flag of `MoveClaim`, accepted as in §7.1 with the numbers in `PlayerRules`: 1 m for 10.
Why not a part: as for sprint.
Visible to: as for sprint.
Status: designed in #33; built in 2d. Tests: (2d), a path once built.

### 9.6 Where the MVP's data and scenes live (provisional)
```
content/
  modes/base_mode.tres             the base mode: phases, rows, PickUp, PutDown and voice rules inside it
  roles/crew.tres, roles/dissident.tres
  items/package.tres, items/knife.tres        the knife's Use rule inside it
  tasks/delivery.tres              with its circle station inside it
  win_conditions/every_task_done.tres, no_crew_alive.tres, time_up.tres
  scenarios/                       bot scenarios (§9.7), one per file
levels/
  lobby/lobby.tscn                 the lobby: floor, walls, lobby_player markers
  greybox/greybox.tscn             the MVP map: rooms and round_player, package, knife and circle markers
```
- **Provisional.** The engineer's agent builds them under the MVP content ADR, each PR with the engineer's approval;
  the designer adopts or replaces them in #38, and the level conventions of M4 (`new-level-piece`) may move the
  scenes.
- **The levels in stage 2.** The base mode names its lobby and map from 2a on, and the checks with layouts (§9.1)
  and the scenarios (§9.7) need them before M4. So 2j adds both scenes at these paths as flat, marker-only levels: a
  floor collider and the markers, enough for every tag at 10 players with the default settings, and no rooms. 4e
  dresses the same files, so the mode's paths never change and `content/` never points into `tests/`. Both come
  under the MVP content ADR, with the engineer's approval in 2j's PR.
- A kind that other modes can reuse (a role, an item kind, a task type, a win condition) gets its own file; a rule,
  a phase spec, a row or a station is a sub-resource of its owner.
- **Markers.** A spawn point is a `Marker3D` in the level scene, in the persistent group `spawn_<tag>` of its one tag
  (the editor's Groups dock: `spawn_package`); a marker in two such groups is a load error. Packages and knives share
  spawn points when their item kinds name the same tag (say `item`), which is content data; a deal puts at most one
  item on a marker. One tag per marker keeps the `all_ready` fit check exact: the demands per tag are summed and
  compared with that tag's markers, and a deal that passed it always finds its markers. `server/` reads the markers in
  scene-tree order, the level order of §3.3. This convention is provisional until 4e settles it with the designer
  (§10).
- **Tests and content.** A part's unit tests build their data in code or in `tests/fixtures/` and never load
  `content/` or `levels/`. Only the mode check (§9.1) and the scenarios load them, so a change to `content/` can
  break a scenario, which is what scenarios are for, and never a part's unit test.

### 9.7 Bot scenarios
A bot scenario is a scripted match that shows a mechanic working end to end, played only with what each player is
told. One format runs in two runners.
- **Format:** a `BotScenario` resource, `content/scenarios/<name>.tres`, written by whoever owns the mechanic: the
  designer from M3 (`docs/AGENT_WORKFLOW.md` §12), the engineer's agent for the MVP. Its classes (the scenario, its
  steps and targets) are data only and live in `core/content/scenario/` (§9.3), so `content/` still uses only the
  content API; the runners live in `tests/harness/`. It holds:
  - the setup: the mode; the map, one of the mode's maps; the seed; the number of bots (bot 1 is the host's own
    client); the match settings that differ from the defaults; roles forced per bot (debug builds only, invariant 8;
    otherwise the deal draws them from the seed). By default every bot joins (sends `Hello`) at the start and
    acknowledges every `LoadMatch` at once; the steps `Join` and `LoadAck` change that for one bot;
  - one script per bot, whose steps run in order; the bots run at the same time;
  - the expected ends, one per match the scenario plays, in order: a winning side, or `none`. `none` passes when every
    script has finished within the time limit and no further `MatchEnded` arrived. Steps may follow an end, so a
    scenario can go back to the lobby and play a second match (seed *k*+1, §3.3). A time limit for the whole run;
  - `never`: events that one bot, or every bot, must never receive.
- **Steps** are a closed list, like parts: the engineer adds a step and lists it here. Every step that sends an intent
  takes `expect_rejected` (a reason, empty by default): with it, the step is done when that `Rejected` arrives, and
  fails when the intent succeeds or is refused with another reason. So a scenario can script a ghost's `PickUp`, a
  second swing within the interval (`too_soon`), a swing without stamina (`tired`) or a `PickUp` of a delivered
  package (`unavailable`).

| Step | The bot | Done when |
|---|---|---|
| `Join(at_s)` | sends `Hello` `at_s` seconds after the start instead of at once (a late join that cancels the countdown, or one refused in Loading) | its `Welcome` arrives |
| `LoadAck(skip)` | answers the next `LoadMatch`: with `skip`, never, so the loading deadline drops it | the ack is sent, or skipped |
| `Ready(ready)` | sends `SetReady` | its `ReadyChanged` arrives |
| `Setting(id, value)` | (the host's bot) sends `ChangeSettings` | `SettingsChanged` arrives |
| `ReturnToLobby` | (the host's bot) sends `ReturnToLobby` | `PhaseChanged` to the lobby arrives |
| `WaitFor(event, fields)` | waits | it receives a matching event |
| `Wait(seconds)` | waits | the time has passed |
| `WalkTo(target, sprint, stop_m)` | sends honest `MoveClaim`s at walk or sprint speed (a ghost's speed as a ghost; ghosts do not fly since the engineer's correction of 2026-09-30), straight towards the target; a level with walls needs waypoints | it is within `stop_m` (0.5) of the target: 1 m before a circle, the put-down distance, to deliver |
| `PickUp(target)` | faces the item and sends `PickUp` | its `ItemPickedUp` arrives |
| `PutDown(towards)` | faces the target and sends `PutDown` | its `ItemPlaced` arrives |
| `Use(towards, until)` | faces the target and sends `Use` | the event `until` names arrives for this bot (default `Swung`, the knife's; an item whose `Use` emits something else names that) |
| `Jump` | claims a jump | the claim is sent |
| `Expect(event, fields, within)` | checks | it received a matching event since its previous step, or within `within` seconds |
| `ExpectNone(event, fields, for_s)` | checks | no matching event arrived for `for_s` seconds; the first one fails the step |
| `Leave` | disconnects | at once |

- **Targets come from the bot's own view**, the events and snapshots its client received: `my_package(n)` (the n-th
  package of its tasks), `circle_of_held`, `nearest(kind)`, `bot(i)` (where it last saw that player), `point(x, y,
  z)`. A target the bot cannot know fails the scenario, so a scenario also proves that the mechanic is playable with
  what a player is told.
- **Failures:** a step that sends an intent fails on a `Rejected` it did not expect and names the reason; a step that
  does not finish within the time limit fails; a `Correction` outside a placement (§3.2) fails, because an honest bot
  is never corrected, so every scenario also checks the host's movement rules against honest movement. A field that
  names a player is written as the bot's number; the runner maps it to the peer id.
- **Always asserted:** the expected ends within the time limit; no `ERROR:` line in the log; the §5 invariants on
  every bot's stream; over the network, the leak test (§5): the reliable events a bot decoded are exactly its peer's
  events in `Match.view_of`, in order, and every snapshot and voice frame it decoded is in `view_of`, which is a
  subset check, because the unreliable lanes (`LATEST`, `VOICE`) may lose some.
- **Runners:**
  - *Core* (stage 2j): `tests/harness/` drives `Match` directly. Steps become commands stamped with host ticks, each
    bot's view is `view_of(peer)`, and until `server/`'s `WorldQuery` exists (M3) a flat fake answers the geometry:
    the levels give their markers only, read into `LevelLayout`s by the reader that `server/` will use (2j builds it
    in `server/`, which tests may use). The MVP's scenarios play on the flat, marker-only lobby and map that 2j adds
    in `levels/` (§9.6). One GdUnit4 suite, `tests/scenarios/scenarios_test.gd`, runs every scenario in
    `content/scenarios/`, so `test` and `verify` run them from stage 2 on.
  - *Bots* (M3, 3d): `tools\run.cmd bots [scenario]` starts a headless host, whose own client is bot 1, and the other
    bots as headless clients: over `LoopbackHub` in one process by default, or over ENet on 127.0.0.1 with
    `--instances`. The same files; it joins `verify` with the leak test (§5).
- **Reproducing a failure:** the runner prints the bot, the step, that bot's last events and the seed; the command log
  replays the match (§3.3).

### 9.8 The extensibility test
Each later mechanic, on paper, against v0. The test counts classes in `core/`; the last paragraph says what each
costs outside it.

| Mechanic | Data | New part classes | New event classes | What else changes, and why |
|---|---|---|---|---|
| Zone task (#36): stand in a zone for N seconds | a task type `.tres` (N, the zone radius; #36's questions, reset or pause and shared zones, become settings), a zone station kind, `zone` markers in the map, the mode's task types | one task type (one script, §9.3): its deal places the zones and binds each subtask to one; its tick (through `TaskTicks`) advances the time in the zone, kept in its task state, for each subtask whose counted player is alive inside the zone. Who counts (only the owner, or anyone as for Delivery) is #36's question | none for placement and progress: `StationPlaced`, `TasksAssigned` (per subtask its zone), `TaskProgress` and `TaskUpdated` are generic. One more if #36 wants the owner to see the time in the zone live, and one if a zone is shown as done to everyone (`PackageDelivered` is Delivery's) | `DealTasks` splits *tasks per player* between two task types: a mix setting, a change to one part's settings |
| Resurrection (#34), as an item | an item kind whose `Use` rule has the conditions `BodyInFront` and `ActorRole` (if only some roles may), the costs `Cooldown` and `Uses` (if the count is limited) and the effect `Revive`; `SpawnItems` for it in the deal | two or three: `BodyInFront` (a condition: a body within reach and angle, in line of sight; else `no_body`, which reveals nothing, as bodies are public), because an effect cannot refuse, and without it a `Use` with no body pays its costs and does nothing; `Revive` (the player of that body becomes alive at the body; which body and how much health are #34's questions and become its settings); `Uses` (a cost over the counters table), which every limited ability reuses | `Revived` (everyone: the body and the avatar are public anyway) | `Revive` places the player: a `Correction` with a new epoch, or its next claim from the ghost's position is a teleport. Bodies are already in `MatchState` (§9.1, 2g). Audiences are evaluated at emission, so the revived player's snapshots and voice narrow at once, and it keeps what it saw as a ghost (§5). Which `Use` wins when a medic holds a knife is #38's (§9.2). As an action at a body without an item, it needs `Interact` (below) |
| Meetings mode (#35) | a new mode `.tres` that reuses the base mode's roles, items, Delivery and win conditions, with the phases Meeting, Vote and Resolution, rows such as `Round, meeting_called → Meeting`, `Resolution, resume → Round` and `Resolution, won → End`, a clock stopped by the phase spec and a meeting voice rule | several, because a meeting is a system, not one mechanic: `Interact` (below) for a button and a body report, whose rules report `meeting_called` with `ReportOutcome`; `CastVote`'s effect; a tally as a transition action, fed by the Vote phase object's votes through the outcome's argument (§9.1); a meeting-wide voice rule; the phase classes Meeting, Vote and Resolution (fewer if one timed phase class serves several) | the vote events, each with its audience (a cast vote hidden until the reveal; the reveal; the result) | a new intent, `CastVote(target)`, with its row in §4.1. `PlacePlayers` gains a `who` setting (everyone, or only the living) to seat players for a meeting. Nothing in `Match` or the base mode: phases, rows, outcomes, the clock and the voice rule per phase are data (§3.1) |
| Physics throwing (#37) | a `Throw` rule on the mode, for any held item | one: the `Throw` effect, which takes the item out of the hand into a *flying* state | a public `ItemThrown`, and a directive (audience *server*) that tells `server/` to simulate the flight | a new intent, `Throw(facing)` (a new verb for every item, unlike `Use`), with its row in §4.1; the flying state in `MatchState`; `server/` simulates the flight and reports `ItemRested`, which raises `item_rested`, so delivery works unchanged. How the flight is shown is #37's: `core/` builds the snapshots but does not know an item's position in flight, so either `server/` reports the positions as logged commands, or clients draw the arc from `ItemThrown` until `ItemPlaced`. Damage on impact needs an impact fact: #37 decides |

**`Interact(target)`** (v1, with the first mechanic that needs it, #34 or #35): one intent that names a thing in the
world by id, and owners for fixed interactables (a marker kind in `levels/`, such as a meeting button) and for
bodies. It changes the intent catalogue (§4.1) and the owners once; after it, a new interactable is data plus at
most one effect.

**Verdict.** Inside `core/`: the zone task passes, with one class, unless #36 wants live progress or a public "zone
done", which add an event class each. Resurrection as an item does not pass the letter of the test: it needs two part
classes (three with a use limit) and one event class, because a body is a new kind of target (a condition selects
it) and a revival is a new public fact (an event). The meetings mode is several parts, as a system. Throwing and
`Interact` each change the engine once, for the reasons given. None of them changes `Match`, the phase loop or an
existing part's behaviour; the changes to existing parts are new settings (`DealTasks`' mix, `PlacePlayers`' `who`).
Outside `core/`, every new event class and intent also costs a wire schema row (M3, §4) and its presentation on the
client (M4). That is the price of any mechanic that shows something new, not a gap in the content API.

## 10. Open questions

| Question | When |
|---|---|
| Content API v1: the designer's review of v0 (§9) | #38, before M7 |
| `Interact(target)`: fixed interactables and bodies as targets (§9.8) | with the first mechanic that needs it (#34 or #35) |
| Movement modifiers, which would make sprint and jump parts (§9.5) | when a mechanic changes movement |
| Which `Use` rule wins when the held item and the actor's role both have one; v0: the item (§9.2) | #38, before a role has a `Use` ability (#34) |
| How levels mark spawn points: groups on `Marker3D` or an engine marker scene (§9.6) | 4e, with the designer |
| Lag compensation for hits (§7.1) | after the MVP playtest |
| Hiding positions behind walls (§5; not wanted now) | only if a human asks |
| Wire format of the message layer: schemas, encoding, versioning, reliability | M3 |
| ENet between two machines (#21); the host's per-send ENet cost and upload for voice | before M3 depends on ENet; M3 or M5 |
| Voice integration: occlusion, dead chat, meetings, radios, push-to-talk or voice activity, echo cancellation, device latency | M5 |
| Internet play without a VPN (NAT traversal): Steam networking vs WebRTC with a signaling server | M6 ADR |
