# Architecture

| | |
|---|---|
| **Owner** | The engineer. The **content API** section is the contract with the designer: changes to it are reviewed by both. |
| **Status** | Skeleton (M0). The boundaries below are locked ([KICKOFF §3](history/KICKOFF.md); stack: [ADR](decisions/2026-09-29-technical-stack-from-the-brief.md)). Everything marked *open* is designed before M2 (core and content API) or in the milestone named. The match loop, intents, events and entitlement (§3, §4.1, §4.2, §5, §7.1): M2 design, #32. |
| **Rules for agents** | The invariants are repeated in the root `CLAUDE.md`, so they survive compaction. Area rules: `core/`, `server/`, `net/`, `client/`, `voice/` `CLAUDE.md`. |

## 1. Layers and boundaries

| Folder | Contains | May use | Owner |
|---|---|---|---|
| `core/` | Pure rules: match state machine, intent validation rules (movement checks included), win conditions, who is entitled to each event and entity (§5), voice routing rules, content-API primitives. `RefCounted` only; no Nodes, scenes, networking or audio | nothing outside `core/` | engineer |
| `server/` | Host logic: wraps `core/`, checks the sender, format and rate of intents, builds one message per recipient from `core/`'s entitlement, answers `core/`'s geometric questions (`WorldQuery`, §7.1) | `core/`, the `net/` abstraction | engineer |
| `net/` | Transport abstraction (ENet first), message schemas, serialization, sync | nothing game-specific | engineer |
| `client/` | Scenes, player controller, UI, camera, audio playback, dev console | the filtered view it receives; `net/` to send intents | engineer |
| `voice/` | Capture, Opus encode and decode, jitter buffer, playback plumbing | `net/`, `client/` playback | engineer |
| `content/` | Roles, abilities, items, sabotages, task types as `Resource`s built from content-API parts | the content API only | designer |
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
  player's life state (alive, ghost, left), position, hand slot, health and stamina, the items, the tasks, the match
  clock and the RNG streams. The match state outlives phases, so Round → Meeting → Round keeps everything.
- A **game mode** is data (a `Resource`; its kind belongs to the content API, #33). It lists:
  - the phases, each an id plus a phase class and its parameters, and the first phase;
  - per phase: the intents it accepts (an allowlist); its **tick systems** in the order they run, and which of them
    also run after every command (the base mode's Round: stamina, cooldowns, task types that tick, the match clock,
    then the win conditions, which also run after every command; the other phases have none); whether the match
    clock runs; and which voice rule applies (§6);
  - a **transition table** of rows *from phase, outcome → to phase, actions*.
- An intent the phase's allowlist does not name is rejected. An accepted intent goes to the phase class, or to the
  content part that handles it (an action such as pick up, a throw #37, or a body report #35): a new action is a part
  plus an allowlist entry, not an edit of the phase class.
- A **phase class** handles its own commands and timers (the countdown, the loading deadline, a vote timer), emits
  events, and reports **outcomes**: named triggers such as `all_ready`, `cancelled` or `won`. Any content part may
  report an outcome as well, so a new trigger (a meeting button, #35) needs no change to the phase it runs in.
- After every command, every tick, and every phase entry, `Match` takes the first outcome reported in that step,
  looks it up in the table, runs the row's actions
  (content parts, such as `deal`), exits the phase and enters the next. Rows are keyed by an outcome, so a transition
  without a trigger cannot be written; an outcome without a row fails loudly, and a unit test drives every row.
  Checking on entry means a phase whose condition already holds (every player ready when the Lobby is re-entered)
  moves on without waiting for another command. A later outcome in the same step is dropped, logged in every build,
  and the intent that caused it gets `Rejected`: a condition (`all_ready`, `won`) is re-checked at the next step
  anyway, and a one-off trigger (a meeting button, #35) is refused visibly instead of lost.
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
| Round | the deal has run (below) | living: `MoveClaim`, `PickUp`, `PutDown`, `Hit`; ghosts: `MoveClaim`; leave | round rule | runs |
| End | frozen: no movement, no snapshots; `MatchEnded` | `ReturnToLobby` (host); leave | nobody | stopped |

| From | Outcome: its trigger | To | Actions |
|---|---|---|---|
| (start) | the host creates the session | Lobby | |
| Lobby | `all_ready`: every player is ready, and the settings fit the map for the current player count (packages, circles, knives and players within the map's spawn points; 1 to 10 players) | Countdown | |
| Countdown | `cancelled`: a `SetReady(false)`, a join or a leave | Lobby | none: ready flags and positions stay, so after a leave `all_ready` fires on entry and restarts the 5 s |
| Countdown | `countdown_done`: the end tick is reached | Loading | |
| Loading | `all_loaded`: every player of the frozen roster confirmed. A leave, or a client's missing `LoadAck` at the loading deadline, drops that player from the roster. The host (peer 1) is never dropped, so the roster is never empty: if its own load fails, `server/` ends the session, which clients see as the host lost (#40) | Round | `deal`; start the clock |
| Round | `won(winner)`: a win condition (§3.4) | End | stop the clock |
| End | `back`: the host's `ReturnToLobby` | Lobby | reset the match state from the roster; everyone un-ready and placed in the lobby |

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
  priority. (2) The phase's own timers. (3) The current phase's tick systems in the mode's order; the base mode's Round
  ends with the match clock and then the win conditions, so a delivery in the last tick counts.
- **The match clock** counts only the ticks of phases whose clock runs. Every entry into such a phase announces the
  clock's end as a host tick (`PhaseChanged`), so a clock paused for a meeting (#35) is re-announced on resume.
- **Seeds.** `server/` takes one 64-bit session seed from the operating system's entropy (never the time) when the
  host starts and gives it to `Match`; match *k* uses a seed derived from the session seed and *k*. Each purpose
  (`roles`, `circles`, `tasks`, `packages`, `knives`, `spawns`) gets its own `RandomNumberGenerator`, seeded by a fixed mixing
  function of the match seed and the purpose's name (for example SplitMix64 over the seed and an FNV-1a hash of the
  name; not `String.hash()`, whose algorithm is no documented contract). In GDScript `>>` on `int` is arithmetic, so
  the implementation masks after each shift, and its unit test pins known outputs. A new purpose never shifts the
  draws of the existing ones. Shuffles are our own Fisher–Yates over the injected RNG (`Array.shuffle()` uses the
  global one), and inputs are iterated in a stable order: players by peer id, spawn points in their level order.
- **The deal** (the action on `all_loaded`), in this order: roles (dissidents = min(setting, N−1), drawn from the
  roster); circle positions and colours (one circle per package, over the map's circle spawn points); package
  positions; tasks (per player in peer-id order, *tasks per player* tasks of *subtasks* packages, each package drawn
  from the placed ones and bound to a random circle of its own, whose colour it takes); knife positions; player spawn
  points. Item and circle ids are assigned in spawn-point order and `ItemSpawned` and `CirclePlaced` are emitted in id
  order, so an id says nothing about its owner or task. Whether packages and knives share spawn points is level data
  (#33). A package that spawns inside its own circle is delivered at once, by the rule; level data keeps the two
  kinds of spawn points apart.
- **Exact numbers.** Health and stamina are integers in thousandths, so a replay on another machine matches exactly.
  Positions are the claims as received.
- **Replay.** The command log holds everything `core/` is given: the session seed, every command with its tick and
  order (the ones `server/` originates too: `PeerConnected`, `PeerLeft` with their peer ids, `ItemRested` #37), and
  every `WorldQuery` answer. A replay reads the answers from the log instead of asking the level; unit tests use a
  fake `WorldQuery`. Seeds and RNG state never leave the host (§5).

### 3.4 Win conditions (base mode)
Content parts (#33), run in Round only, as its last tick system and after every command, in the mode's order:
- **Crew:** every task done, that is every subtask done (in the MVP a subtask is one package delivered) →
  `won(crew)`.
- **Dissidents:** no crew member alive (dead or left) → `won(dissidents)`; the clock reaches its end with a subtask
  not done → `won(dissidents)`, with 0 dissidents too.

"The first win condition met ends the round" (MVP rules) also orders the effects inside one command. A hit that
kills the last crew member, whose package then drops into its circle, meets "no crew alive" before the delivery:
the dissidents win. The same holds for the last crew member leaving with the last package over its circle.

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
  `tools\run.cmd run tests/integration/net/enet_host_and_two_clients.gd --headless --instances 3`. It is not
  part of `verify` yet.

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
| `Hit(facing)` | a living player with a weapon in hand; Round | the held weapon's minimum interval since this player's last hit, whatever weapon that was; stamina of at least the hit's cost; the host picks the targets (§7.1) |
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
| `SettingsChanged` | settings, the derived package count | everyone | `ChangeSettings`, and a join or leave in Lobby or Countdown (the count changes) |
| `PhaseChanged` | phase; the countdown's or the match clock's end as a host tick, if it runs | everyone | every transition |
| `CountdownCancelled` | reason: un-ready, join or leave | everyone | `cancelled` |
| `PlayersPlaced` | per player: spawn point | everyone | `End → Lobby`; the deal (§3.2) |
| `LoadMatch` | match id, map, settings | everyone | entering Loading |
| `PlayerLoaded` | peer | everyone | a valid `LoadAck` |
| `RoundStarted` | start tick | everyone | the deal |
| `RoleAssigned` | your role | that player | the deal |
| `DissidentTeam` | the dissidents' peer ids | each dissident | the deal |
| `TasksAssigned` | your tasks, each with its packages | that player | the deal |
| `CirclePlaced` | circle, colour, position | everyone | the deal, in circle-id order |
| `ItemSpawned` | item, kind, position; a package's circle and colour | everyone | the deal, in item-id order |
| `ItemPickedUp` | peer, item | everyone | `PickUp` |
| `ItemPlaced` | item, rest position, cause: put down, swap, death or leave | everyone | an item comes to rest |
| `PackageDelivered` | item, its circle (now shown as done) | everyone | the delivery check (§7.1) |
| `TaskProgress` | subtasks done, subtasks in total | everyone | a subtask is done |
| `TaskUpdated` | task, its subtasks done | the task's owner | one of its subtasks is done |
| `Swung` | peer, facing | everyone | a valid `Hit`, whether or not it touched anyone |
| `Damaged` | amount, your health | the victim | a hit on them |
| `SelfStatus` | health, stamina, whether sprint is available | that player | on change, at most once per tick |
| `Died` | peer, body position | everyone | health reaches 0; no event names a killer or a cause |
| `Correction` | epoch, position, velocity | that player | a rejected `MoveClaim` (§7); a placement (§3.2) |
| `Rejected` | the intent's sequence number, reason | the sender | any rejected intent |
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
  a player (no accepted `Hello` yet, or a straggler about to be disconnected). It never adds a recipient or a field. `core/CLAUDE.md` still says "`core/` never decides who may
  see an event"; stage 2a rewords it.
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
  tick, and the speakers it may hear per tick: everything an honest client of that peer can know. The M3 leak test
  compares what each bot actually decoded (voice frames included) with `view_of` of its peer; anything received that
  `view_of` does not hold is a leak.
- **Invariants that do not trust the declarations.** A wrong audience (say `DissidentTeam` declared *everyone*) would
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
- **Stamina** belongs to `core/`. The client predicts its own from the published numbers to draw the HUD and gate
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
  `WorldQuery` within step height) and stamina covers the cost. Until the next landing the height above the floor is
  bounded by the jump height; a rise without an accepted jump beyond step height is corrected. Prevents: free or
  endless jumps, and flying.
- **Pushing apart.** Each client moves only its own player and collides it with the other living players' capsules
  at their interpolated positions: pushing apart is each client resolving its own overlap. The host tolerates overlap
  and never corrects it. Prevents: two clients that see each other 100 ms late snapping each other back and forth.
  Accepted: a modified client can walk through players. Ghosts are outside this by construction: a living client
  never receives a ghost's position, so it cannot bump into one.
- **Ghosts** fly without gravity, faster than the living (the host bounds their 3D speed and teleports only), and
  collide with the level's walls client-side, not with the living or with other ghosts. `PickUp`, `PutDown` and `Hit`
  from a ghost are rejected.
- **Walls.** The MVP host does not check movement through walls (nobody asked for cheat protection). It does check
  walls for hits, pick-ups and placement, because there an honest client would otherwise stab or grab through a thin
  wall.
- **Hits.** The host picks the targets: every living player other than the attacker whose capsule has a point within
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

A mechanic is data: a `Resource` composed from parts the engine provides. Adding a mechanic should usually mean
adding data plus at most one new effect class, never changing the core loop: that is the test of this API. The
designer's agent uses **only** the parts listed here. A missing part becomes an `engine-request` issue; the engineer adds it with tests and lists it
here in the same PR.

| Kind | Answers | Parts available |
|---|---|---|
| Trigger | *when* something happens (a phase starts, a player uses an ability, a task completes, …) | none yet |
| Condition | *only if* (alive, role, distance, cooldown ready, …) | none yet |
| Effect | *what happens* (kill, reveal to someone, a sabotage, change who hears whom, …) | none yet |
| Interactable | a thing in the world players use | none yet |
| Task station | a place where a task is done | none yet |

The examples in the "Answers" column only explain the kinds; none of them is a decided part.

Each part, once it exists, gets one entry:

```
### <PartName> (<kind>)
What it does: one sentence.
Settings: name: type (allowed values, default).
Produces: events or state changes.
Visible to: who learns the result, and when.
Since: PR link. Tests: path.
```

*Open (pre-M2, one design run):* the composition model itself (how triggers, conditions and effects chain), where
the `Resource` classes live, how bot scenarios exercise a mechanic (format and location), and the first set of
parts, drawn from the designer's GDD.

## 10. Open questions

| Question | When |
|---|---|
| Composition model and first content-API parts | M2 design (#33) |
| Bot-scenario format and location | M2 design (#33) |
| Lag compensation for hits (§7.1) | after the MVP playtest |
| Hiding positions behind walls (§5; not wanted now) | only if a human asks |
| Wire format of the message layer: schemas, encoding, versioning, reliability | M3 |
| ENet between two machines (#21); the host's per-send ENet cost and upload for voice | before M3 depends on ENet; M3 or M5 |
| Voice integration: occlusion, dead chat, meetings, radios, push-to-talk or voice activity, echo cancellation, device latency | M5 |
| Internet play without a VPN (NAT traversal): Steam networking vs WebRTC with a signaling server | M6 ADR |
