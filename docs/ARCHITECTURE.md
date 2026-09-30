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
| Lobby | `all_ready`: every player is ready, and the settings fit the map for the current player count (packages, circles, knives and players within the map's spawn points, the demands per spawn tag of §9.4, for any draw of the task types; circles within the palette's colours; 1 to 10 players) | Countdown | |
| Countdown | `cancelled`: a `SetReady(false)`, a join or a leave | Lobby | none: ready flags and positions stay, so after a leave `all_ready` fires on entry and restarts the 5 s |
| Countdown | `countdown_done`: the end tick is reached | Loading | |
| Loading | `all_loaded`: every player of the frozen roster confirmed. A leave, or a client's missing `LoadAck` at the loading deadline, drops that player from the roster. The host (peer 1) is never dropped, so the roster is never empty: if its own load fails, `server/` ends the session, which clients see as the host lost (#40) | Round | the deal (§3.3): `DealRoles`, `DealTasks`, `SpawnItems` (knives), `PlacePlayers`; `StartClock` |
| Round | `won(winner)`: a win condition (§3.4) | End | `EndMatch`: `MatchEnded`. The clock stops because End's clock does not run |
| End | `back`: the host's `ReturnToLobby` | Lobby | `ResetMatch`: the match state reset from the roster, everyone un-ready; then `PlacePlayers` in the lobby. In this order: placed first, the ghosts would still be ghosts when `PlayersPlaced` goes to everyone |

The lobby shows why `all_ready` cannot fire (for example more packages than spawn points): every `SettingsChanged`
carries the demands against the map's markers and each shortfall (`FitCheck`, 2b). The host leaving ends the
session in every phase (§3.5); it has no row, because `core/` runs on the host and stops with it.

**Placement on a scene change.** The `End → Lobby` row and the deal place every player at a spawn point of the new
scene and set the host's position for them: `PlayersPlaced` tells everyone where (positions are public), and each
player gets a private `Correction` with its own new epoch, because a public epoch would count a player's corrections,
which mostly come from hidden stamina. A joiner is placed at a lobby spawn point, the first `lobby_player` marker in
level order with no player within 1 m (the first marker when all are taken; a placeholder, "not a decision"), and
gets its spot and epoch in `Welcome`. Claims still in flight from the old scene carry the old epoch and are dropped as stale (§7). A cancelled
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
  (`roles`, `task_types`, `circles`, `tasks`, `packages`, `knives`, `spawns`), named in the data of the part that
  draws (§9.4), gets its own `RandomNumberGenerator`, seeded by a fixed mixing function of the match seed and the
  purpose's name (for example SplitMix64 over the seed and an FNV-1a hash of the name; not `String.hash()`, whose
  algorithm is no documented contract). In GDScript `>>` on `int` is arithmetic, so
  the implementation masks after each shift, and its unit test pins known outputs. A new purpose never shifts the
  draws of the existing ones. Shuffles are our own Fisher–Yates over the injected RNG (`Array.shuffle()` uses the
  global one), and inputs are iterated in a stable order: players by peer id, spawn points in their level order.
- **The deal** (the actions of the `all_loaded` row, §9.4), in this order: roles (`DealRoles`: dissidents = max(0,
  min(setting, N−1)), drawn from the roster in peer-id order with the `roles` stream; each player learns its own role,
  and each dissident the dissidents); then `DealTasks` (the engineer's decision of 2026-09-30, #79): it draws *tasks*
  different task types from the mode's task types minus the host's bans (`task_types`), and runs each drawn type's deal
  once, in the mode's order. Tasks are shared: nobody owns one. Delivery's deal: circle positions and colours (one
  circle per package, over the map's circle spawn points), package positions, and one task of *packages* packages, each
  bound to a random circle of its own, whose colour it takes (`tasks`). Then `TaskProgress` (the subtasks done and in
  total, 0 done unless a package spawned in its circle) to everyone; knife positions (`SpawnItems`); player spawn points
  (`PlacePlayers`). Item and station ids are assigned in spawn-point order and `ItemSpawned` and `StationPlaced` are
  emitted in id order, so an id follows the level, not the draw. Packages and knives share spawn points when their item
  kinds name the same spawn tag; a marker carries one tag, and a deal puts at most one item on a marker (§9.6):
  `SpawnItems` and Delivery's packages skip the markers where an item already rests (`Items.free_markers`, which every
  placing part uses). Each placing part emits all its `ItemSpawned` first, then raises `item_rested` (spawn) for each
  item in id order. A package that spawns inside its own circle is delivered at once, by the rule; the `package` and
  `circle` tags keep the two kinds of spawn points apart.
- **Exact numbers.** Health and stamina are integers in thousandths, so a replay on another machine matches exactly.
  Positions are the claims as received.
- **Replay.** The command log holds everything `core/` is given: the session seed, the game mode's path and a hash
  of its content (every resource it loads, sub-resources included), every command with its tick and order (the ones
  `server/` originates too: `PeerConnected`, `PeerLeft` with their peer ids, `ItemRested` #37, and in debug builds
  `ForceRole`, §9.4 `DealRoles`), the levels' `LevelLayout`s (§9.1), and every `WorldQuery` answer. A replay reads the answers from the log instead of asking the
  level, and refuses to run when the mode's hash differs (after an edit in `content/`, say the knife's damage, it
  would silently diverge); unit tests use a fake `WorldQuery`. Seeds and RNG state never leave the host (§5).

### 3.4 Win conditions (base mode)
Content parts (§9.5), checked in Round only, in the mode's order, after every fact and at the end of every step
(§9.2):
- **Crew:** every task done, that is every subtask done (in the MVP a subtask is one package delivered) →
  `won(crew)`. A task with no subtasks is done, and with no tasks every task is done (the engineer's rule of
  2026-09-30, #79).
- **Dissidents:** no crew member alive (dead or left) → `won(dissidents)`; the clock reaches its end with a subtask
  not done → `won(dissidents)`, with 0 dissidents too.

"The first win condition met ends the round" (MVP rules) also orders the effects inside one command. A hit that
kills the last crew member, whose package then drops into its circle, meets "no crew alive" before the delivery:
the dissidents win. The same holds for the last crew member leaving with the last package over its circle. The
check after every fact is what makes this so: a death or a leave raises its fact before the held item drops (§9.2).
2g (#63) tests both cases with fixture win conditions in the base mode's order:
`tests/unit/life/life_rules_test.gd` and `tests/unit/match/phases/round_phase_test.gd`. 2h (#64) tests them again
with the real win conditions and Delivery (`tests/unit/win/none_alive_test.gd`), with the control that the same
package put down wins for the crew.

Each win condition's side and conditions are data (`content/win_conditions/`, §9.5); `EndMatch` then tells
everyone the side, and nothing else (§5). Built in 2h (#64): `core/win/`, tested through seeded matches in
`tests/unit/win/` (the crew wins on the last delivery only, a delivery on the end tick counts, time up with 0
dissidents, no crew alive by a death or a leave, End widens nothing).

### 3.5 Joining, leaving and the host
| Phase | A client joins (its `Hello` is accepted) | A client leaves |
|---|---|---|
| Lobby | `Welcome` to it, then `PlayerJoined` and `SettingsChanged` to everyone (it included) | dropped from the roster; `PlayerLeft`, `SettingsChanged` |
| Countdown | as in Lobby, and `cancelled` | as in Lobby, and `cancelled` |
| Loading | refused: `core/` emits `RefuseJoins` on entering Loading and `AllowJoins` on entering Lobby, and `server/` sets `refuse_new_connections`. A peer whose connection completed anyway gets `DisconnectPeer` | dropped from the roster; `PlayerLeft` |
| Round | refused, as in Loading | life state `left`, which counts as dead for the win conditions; the avatar is removed and no body stays (a ghost's body stays); in this order `PlayerLeft` (everyone else), the fact `player_left`, then the held item comes to rest on the floor below where the player stood (§7.1). 2g (#63): `RoundPhase` hands it to `LifeRules.leave`, after forgetting a newcomer that never joined (`JoinRules.forget_newcomer`) |
| End | refused, as in Loading | life state `left`; `PlayerLeft`. `ResetMatch` drops the player from the roster |

- **The join** (2b, `JoinRules`): `server/`'s `PeerConnected` makes a peer a *newcomer*, and only a newcomer's
  `Hello` is taken, once. Checked in order: the version equals the host's (`JoinRules.PROTOCOL_VERSION`), else
  `Rejected` (`wrong_version`) and `DisconnectPeer`; the roster has fewer than the mode's maximum of players, else
  `Rejected` (`full`) and `DisconnectPeer`. A newcomer's leave is forgotten silently, and so is the late `PeerLeft`
  of a peer that a directive disconnected.
- **Names** (the engineer's decision of 2026-09-30, #58): the host names every joiner `Player<n>`, with n counted
  by accepted joins over the whole session (`MatchState.joins`): Player1, Player2, and so on. The host's own
  client normally joins first and so is Player1, but the rule is only the join order. A number is never
  reused: Player1 to Player3 join, Player2 leaves, and the next joiner becomes Player4. `ResetMatch` keeps the
  count, so it runs on through End → Lobby. The name in `Hello` is ignored in the MVP. After the MVP a player sets
  their own name and body colour, and a reconnecting player gets their old number back (#73).
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
  (`NetTransport.receive_bytes` and its helper `_decoded`; a superseded LATEST packet is checked the same way but
  not delivered).
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
- **The LATEST lane delivers only the newest** message per sender and kind per `poll()`, between two of that
  sender's reliable messages (#70). After a peer's main thread froze, its backlog arrives in one poll: 50 to 100
  packets, each up to 5 s old (#21). The inbox drops every valid LATEST message that a newer one of the same kind
  from the same peer follows in the same poll, so no consumer ever handles the backlog, and each consumer gets the
  rule without code of its own. The newest keeps its place among the poll's other messages. A valid RELIABLE
  message from that peer in between separates the two, so each intent or event is still handled after the state
  sent just before it: a client that walked to a package during the host's freeze and sent `PickUp` has it checked
  against the claim it sent before the `PickUp`, not the one from before the freeze. A join or leave of that peer
  in between separates them too (two connections, maybe with the same id). VOICE, on its own unordered channel,
  separates nothing, and neither does a malformed packet. A dropped message is still checked like any packet (what
  is malformed stays a reject) and counted in `latest_superseded`, not as a reject. RELIABLE and VOICE messages are
  never merged. So a LATEST message must stand alone: nothing may be lost when a newer one replaces it (a one-off
  event goes RELIABLE, or the state carries it, a counter say). The merge is by sender and kind, not by subject:
  a host-to-client LATEST kind holds what it describes for every player that recipient may see (filtered by
  `server/`) in one message, never one message per player, or only the last player's would arrive in a poll that
  holds several.
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
  acknowledgement; a crash is noticed that late. ENet runs only on the main thread, so a frozen process sends and
  acknowledges nothing, and the spike's 2 to 4 s dropped it. #21 found a common freeze: on Windows a windowed D3D12
  Godot process can freeze about 5 s (5.0 to 5.2 s) when another one on the same PC is killed or starts. Keep the
  minimum at 10 s or more; a servicing thread or an extra keepalive would not help (ENet already pings every
  500 ms, and a thread would keep a hung game "connected").
- Checked by `tests/unit/net/transport/` and two headless runs of three processes on 127.0.0.1, which `verify`, and
  so CI, runs on a free port (`-- --port=<p>`; AGENT_WORKFLOW §11):
  - a host (with its own client) and two clients:
    `tools\run.cmd run tests/integration/net/enet_host_and_two_clients.gd --headless --instances 3`;
  - the freeze (#70): the host blocks its main thread for 5.2 s, then a client does; no drop, every reliable
    message in order, at most one LATEST message per peer per poll between that peer's reliable messages, and
    each thaw's backlog merged:
    `tools\run.cmd run tests/integration/net/enet_freeze.gd --headless --instances 3 -- --port=<p>` (the port
    is required). On one PC the thawed host's newest message from each of two clients was about 1 s old and the
    freeze's last second of unreliable packets never arrived, probably because its socket buffer filled; the
    thawed client's, from one sender, was 2 to 40 ms old.

*Open (M3):* intent and event schemas, their payload encoding and their rows in `NetKindTable.game()`, rate limits,
and what the host does with a peer that keeps sending rejected packets. A `MoveClaim` on the LATEST lane would lose
a merged claim's `jumped` (and its sprint and movement-input flags for the ticks it covered), so its lane and how a
jump survives a merge are part of its schema. If a claim carries a cumulative jump count instead, the host honours a
rise in it as one jump allowance per claim, checked against the last landing floor it knows, with stamina charged
per counted jump: the take-off positions of merged claims are lost, so the count alone never grants several jump
heights. The intents are not affected: a peer's reliable message separates the claims merged around it. The protocol version travels in `Hello`
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
- A 2–4 s ENet timeout drops any peer whose main thread freezes that long (level loads, breakpoints, the #21 D3D12
  freeze): use a longer timeout or reconnection. Cache `get_unique_id()`: it errors after the connection closes.
- Broadcast only public message types; everything else is built per peer by `server/` (§5).
- #21: on one machine, a hard-killed windowed client made the host lose the other client too. The cause was a 5 s
  freeze of another windowed D3D12 process on the same PC, not the network: between two machines 12 hard kills
  were all clean. `EnetTransport`'s 10 to 20 s timeout rides the freeze out (Timeouts above), and #70 merges the
  backlog. Kill tests with several windows on one PC run headless, off-screen or with `--rendering-driver vulkan`,
  or expect a 5 s hitch; whether Windows keeps `d3d12` as its default is the humans' decision.

### 4.1 Intents (MVP, #32)
What each intent means and who may send it; the schemas are M3. The sender is always the peer id the transport
reports, never a field of the message. `server/` checks what the transport knows (sender, decoding, size, rate) and
passes the intent to `core/` as a command stamped with the host tick; `core/` checks the phase's allowlist (§3.1)
and the rules below. A rejected intent gets `Rejected` to the sender, whose reason depends only on facts the sender
is entitled to (§5).

| Intent | Who, in which phase | The host validates |
|---|---|---|
| `Hello(name, version)` | a connected peer that is not yet a player, once; Lobby or Countdown | the version (an int) equals the host's, or `wrong_version` and `DisconnectPeer`; room in the roster, or `full` and `DisconnectPeer`. The name is ignored in the MVP: the host names the joiner `Player<n>` (§3.5; own names: #73). Accepted, it is the join (§3.5) |
| `SetReady(ready)` | any player; Lobby (true or false), Countdown (false only: true is `not_accepted`) | `ready` is a bool, or `bad_args`; that it changes the player's state, or `unchanged` |
| `ChangeSettings(settings, map)` | the host (peer 1) only; Lobby only | `settings` names only the settings that change; each is a declared setting (`unknown_setting`) with a value of its kind (§9.1; else `unknown_setting`): an int within its bounds (`out_of_bounds`), or for `banned_task_types` an array of the mode's task type ids (another id: `out_of_bounds`), which replaces the set. Then the settings as they would be must suit the deal: `tasks` at most the task types not banned, and at least one type not banned (`out_of_bounds`; #79, placeholder rules). The optional `map` is one of the mode's maps (`unknown_map`). All or nothing. Whether they fit the map is checked at `all_ready` |
| `LoadAck(match_id)` | each player of the frozen roster, once; Loading | the current match id (the match's index in the session): an ack of another match is dropped silently; a second ack is `unchanged` |
| `MoveClaim(epoch, client_tick, position, velocity, facing, sprint, moving, jumped, on_floor)` | living players in Lobby, Countdown and Round; ghosts in Round | the current epoch and a rising client tick (else dropped as stale); finite values; the client tick rising at a bounded rate; speed for the life state and stamina; jumps; height (§7, §7.1). `client_tick` counts 20 Hz core ticks of the client's own clock (`Ticks.RATE`), not physics frames. `moving`: the player gave movement input, which sprint stamina counts (§7.1). A claim that fails a check gets `Correction`, not `Rejected` |
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
| `Welcome` | your peer id, spawn point and epoch; the roster with names (the host's `Player<n>`, §3.5) and ready flags; the whole-number settings (the bans of task types follow in the `SettingsChanged` after it) and the map; the phase; the other players' positions | the joiner | its `Hello` is accepted |
| `PlayerJoined` | peer, name (the host's `Player<n>`, §3.5), spawn point | everyone | its `Hello` is accepted, after its `Welcome` |
| `PlayerLeft` | peer | everyone | a player leaves in any phase, or misses the loading deadline |
| `ReadyChanged` | peer, ready | everyone | `SetReady`; everyone un-ready on `End → Lobby` |
| `SettingsChanged` | settings (the whole numbers, and the banned task types) and map; the player count; the derived demands per spawn tag (§9.4: in the MVP packages, circles, knives, player spawns, for any draw of the task types) against the map's markers, the package count among them; colours per station kind against its palette; every shortfall that holds `all_ready` back | everyone | `ChangeSettings`, and a join or leave in Lobby or Countdown (the demands change) |
| `PhaseChanged` | phase; the countdown's or the match clock's end as a host tick, if it runs | everyone | every transition |
| `CountdownCancelled` | reason: un-ready, join or leave | everyone | `cancelled` |
| `PlayersPlaced` | per player: spawn point | everyone | `End → Lobby`; the deal (§3.2) |
| `LoadMatch` | match id, map, the whole-number settings | everyone | entering Loading |
| `PlayerLoaded` | peer | everyone | a valid `LoadAck` |
| `RoundStarted` | start tick | everyone | the deal |
| `RoleAssigned` | your role | that player | the deal |
| `Teammates` | a role and the peer ids of its players | each player of that role, for a role that knows its teammates (the dissidents) | the deal |
| `StationPlaced` | station, station kind (in the MVP the delivery circle), colour, position | everyone | the deal, in station-id order |
| `ItemSpawned` | item, kind, position; a package's circle and colour | everyone | the deal, in item-id order |
| `ItemPickedUp` | peer, item | everyone | `PickUp` |
| `ItemPlaced` | item, rest position, cause: put down, swap, death or leave | everyone | an item comes to rest |
| `PackageDelivered` | item, its circle (now shown as done) | everyone | the delivery check (§7.1) |
| `TaskProgress` | subtasks done, subtasks in total, over every task of the match | everyone | the deal, after the task types dealt (so the HUD shows the total from the start); a subtask is done |
| `Swung` | peer, facing (the zone's horizontal direction, a unit vector or zero when it has none: of the `Use`'s facing, or the last accepted claim's when the `Use` had no finite, non-zero one) | everyone | a valid `Use` of a knife (`Strike`), whether or not it touched anyone; before any `Damaged` |
| `Damaged` | amount, your health (thousandths, §3.3); no attacker | the victim | a hit on them |
| `SelfStatus` | health and stamina (thousandths, §3.3), whether sprint is available | that player | on change, at most once per tick: at the end of the tick, with its final numbers (`SelfStatusFeed`) |
| `Died` | peer, body position | everyone, the dead player included | health reaches 0; no event names a killer or a cause |
| `Correction` | epoch, position, velocity | that player | a `MoveClaim` that fails a check (§7.1); a placement (§3.2); a death: the ghost at its body (§7.1 Ghosts) |
| `Rejected` | the intent's sequence number, reason | the sender (*sender*: a present player, or a peer that is not a player: a newcomer whose `Hello` was not accepted yet, or a peer being disconnected whose intent was in flight) | any rejected intent; an applied intent whose outcome was dropped (`outcome_dropped`, §3.1) |
| `MatchEnded` | the winning side (crew or dissidents), nothing else: no names, no roles | everyone | `won` |

Directives to `server/` have the audience *server* and reach no peer: `RefuseJoins`, `AllowJoins`,
`DisconnectPeer(peer)`. Built in 2b (#58): the events from `Welcome` to `PlayerLoaded` above, `ReadyChanged`,
`CountdownCancelled` and the three directives; `DisconnectPeer` follows the `Rejected` it explains, and `server/`
sends what came before it (§4, `disconnect_peer`). Built in 2g (#63): `Swung`, `Damaged` and `Died`. Built in 2h
(#64): `MatchEnded`, and `RoundStarted` is emitted (`StartClock`; the class came with 2c's deal events).

## 5. Per-peer information filtering

- Each outgoing message is built for one recipient from what that peer is entitled to know.
- The information-leak test (bot harness, M3) asserts that no client ever receives anything it is not entitled to.
  It is the most important test in the project. Once it exists, prove it: inject a leak, see it fail, revert.
- `tools\run.cmd bots` (M3) starts a headless host and N headless bot clients that play a full scripted match, then
  asserts: the match ends, the winner is correct, no errors are logged, and no client received information it was
  not entitled to. It joins `verify` and CI. `host` and `join` launch a local host and clients for the humans'
  playtests.

**How entitlement is expressed** (#32; [ADR](decisions/2026-09-29-match-loop-intents-events-and-entitlement.md)):
- **Per event type.** Each event class declares its audience as a rule in `core/`: *everyone*, *only(peer)* (a
  present player), *role(r)*, *life(ghost)*, *server* (a directive, §4.2), or *sender(peer)*, which only `Rejected`
  uses, because only it may reach a connected peer that is not a player yet (the engineer's answer on #49). The rule is evaluated when the event is emitted, against
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
- **Never leaves the host:** seeds and RNG state; another player's role (the end screen shows none either),
  health, stamina and damage; ghosts, for the living. Tasks are shared (#79): what a client learns of them is all
  public (`StationPlaced`, `ItemSpawned` with a package's circle and colour, `PackageDelivered`, `TaskProgress`);
  no task has an owner, and a subtask's detail stays in `subtask_done` (internal to the task type, not secret). No event names a killer; a player who
  watches the swings and positions (both public by the rules) may still work it out.
- **Widening** follows from evaluating audiences at emission. Death: the player's life state becomes ghost, so from
  the next tick their snapshots include the ghosts and their voice joins the dead (§6); they learn no roles (2g
  tests the snapshots and the invariant below in `tests/unit/life/life_rules_test.gd`). End
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
  another player's health, stamina or damage; every player receives the same task events; no message holds a seed.

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
- **Built in 2i** (#65, `core/voice/`): `SilentVoice`, `ProximityVoice` and `RoundVoice` (§9.4); the base mode's
  data names one per phase with the numbers of §9.5. A distance is between the two players' last accepted
  positions (§7.1), in 3D, and a radius includes its edge, as the M1 spike's routing measured them (#15,
  `distance_to(...) <= cutoff`, which the engineer listened to and accepted); 3D also matches the listener's fade.
  A horizontal radius (a player on the floor above heard like one beside) stays a possible later change. The
  living never hear a ghost under any rule: `VoiceRule.speakers_of` drops that pair before asking the rule, as
  snapshots hide ghosts from the living (§5), so no mode's data can route a ghost's voice to the living.
  Tests: `tests/unit/voice/`.
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
  script defaults are 0 so no number is repeated in code. `core/` has the same numbers in the mode's `PlayerRules`
  (§9.5, 2d); the client takes them from the mode when it joins a host (M3), and later content from the designer.
- Stamina is behind `StaminaSource`: the controller asks before a sprint or a jump and reports each physics step;
  a step counts as moving only while the player gives movement input, so a push is free (§7.1 Stamina).
  `LocalStamina` predicts with `core/`'s rule (`StaminaLedger`, 2d) and is the only copy of it on the client, until
  the client follows `SelfStatus` (M3).
- A ghost (`ghost = true`) takes the living's path: the same capsule, gravity, floor, steps, slopes and jump, at the
  living's walk and sprint speeds times `ghost_speed_factor`. `StaminaSource` never refuses a ghost and records
  nothing for it. There is no flight (the engineer's correction of 2026-09-30, #46).
- Physics layers (`PhysicsLayers`, named in `project.godot`): 1 `world` (level geometry, Godot's default layer),
  2 `living_players`, 3 `ghosts`. The living and ghosts collide with the world only; a living player finds the
  other living players with a contact search on layer 2 and pushes them (§7.1 "Pushing apart"). Other living players
  are `RemotePlayerBody` kinematic capsules that only their owner's data moves.
- Steps: `move_and_slide` stops a capsule at any ledge, so the controller lifts itself onto a ledge up to the step
  height and glides over the edge until it snaps onto the top. What blocks it must be a ledge: a walkable blocker (a
  ramp, a low edge under the rounded bottom) is left to `move_and_slide`, and a ledge whose top is steeper than
  `floor_max_angle` (a steep slope, a round prop) is no step. Only the body jumps up; the view eases after it and
  lags at most one step height. A jump's take-off speed is solved for the physics step so the ballistic peak is the
  jump height.
- For the host's movement checks (`MovementRule`, 2d, covers both): the controller crosses a ledge's edge `STEP_CLEARANCE` (0.01 m)
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
- **Stamina** belongs to `core/` (ghosts are exempt, see Ghosts below). The client predicts its own from the published
  numbers to draw the HUD and gate Shift, and follows `SelfStatus`. `core/` keeps a ledger per player: the host tick up
  to which stamina is settled. A claim settles the ticks it covers (its client-tick delta, never past the current host
  tick): a covered tick in the sprint state in which the player gave movement input and moved horizontally costs 1/20 of
  the per-second cost, and every other covered tick regenerates. Only the player's own movement counts (the engineer's
  decision of 2026-09-30, #46): a pushed player holding sprint without movement input pays nothing for the push.
  `PlayerController` reports a step as moving only while it gives movement input; `core/`'s stamina
  (`StaminaLedger`, 2d) counts the same way: a claim says whether movement input was held (`moving`). Before a
  jump or a hit is checked, the ticks not yet settled are settled with the last claim's sprint state and movement-input
  flag, so an idle player is not refused on stale stamina; a later claim settles only what is left. A jump claim
  first settles its own covered ticks with its own flags, so a sprint that ends in a jump is paid. The sprint state
  (Q7) starts when the claim holds the sprint flag and stamina is at least the start threshold, and lasts while the flag
  is held and stamina is above 0. An accepted jump or hit costs its amount at once. The allowed horizontal speed is the
  sprint speed in the sprint state, else the walk speed, plus the push allowance (Pushing apart below), measured over
  the client's tick delta (lesson above). Faster: `Correction` with a new epoch. Prevents: a client that never spends
  stamina, or spaces its claims out to regenerate between them, sprinting forever.
- **Jumps** are accepted only when the host has the player on the floor (the floor found by `WorldQuery` within
  step height plus `STEP_CLEARANCE` below the last accepted feet; the last claim need not say `on_floor`, because claims go at 20 Hz and
  the client's physics at 60 Hz, so a landing and a jump can fall within one claim) and stamina covers the cost (a
  ghost's jump needs none). Until the next landing
  the height above the floor is bounded by the jump height; a rise without an accepted jump beyond step height is
  corrected. Prevents: free or endless jumps, and flying.
- **The movement checks** (`MovementRule` in `core/movement/`, the ledger in `core/stamina/`; 2d, #60). Every
  tolerance is a constant of `MovementRule`, a placeholder "not a decision" unless it copies the client:
  - A claim of another epoch, or whose client tick does not rise, is dropped: no `Correction`, so one correction
    does not cascade. Every other failed check sends `Correction` with a new epoch and the host's position to that
    player only, and changes nothing else (stamina settled up to now aside, §9.2).
  - Well formed: an int client tick and finite position, velocity and facing. The velocity is not bounded: it only
    feeds the other clients' interpolation.
  - The client tick's rate: `client_tick` counts 20 Hz core ticks of the client's own clock, not its physics frames
    (60 Hz), so the M3 client derives it from a 20 Hz counter (or its physics frame divided by 3). A player earns
    one tick of credit per host tick and keeps at most `MAX_TICK_CREDIT`
    (200 ticks, 10 s); a claim may cover no more client ticks than its credit. So a catch-up burst after a stall
    (#70: 50 to 100 claims in one host tick after 5 s, or, merged by the LATEST lane (§4), one claim covering
    them all) passes, a client that runs its tick ahead gets
    `TICK_LEAD` (10 ticks) at most, and no claim buys distance by inflating its tick delta. A claim past its credit
    is corrected and the next claim starts a new client-tick baseline (credit not refilled), so a client whose ticks
    ran ahead of a stalled host's is corrected once, not on every later claim. A placement (§3.2)
    restarts the credit and the client-tick baseline, and settles the ticks since the last claim as standing still.
  - Speed: per covered tick the state's speed (a tick not settled yet takes the state the next tick would have;
    a living player's claim without movement input gets the walk speed, since only input pays for sprint),
    times `ghost_speed_factor` for a ghost; for the living plus `sprint_speed` (Pushing apart below; proposed for M4,
    used provisionally); plus `DISTANCE_SLACK_M` (0.05 m) per claim.
  - Height, from the last landing's floor (a claim on the floor with a `WorldQuery` floor within step height plus
    `STEP_CLEARANCE` below its feet, which a ledge crossing needs; `FLOOR_PROBE_M` above the feet is where the query
    starts): after an accepted jump, the jump height
    plus `capsule_radius * (1 - cos 45°) + STEP_CLEARANCE` (about 0.127 m, §7) from the take-off, the higher of its
    floor and its feet; without one, the step height plus `STEP_CLEARANCE` (0.01 m) plus the claim's horizontal
    travel times tan 45° (slopes and stairs up to the client's `floor_max_angle`). Positions are 32-bit floats:
    `HEIGHT_SLACK_M` (1 mm) on top. Falling is not bounded.
  - Cost: two `WorldQuery.floor_below` calls per jump and one per claim on the floor, each recorded in the command
    log. `server/`'s `floor_below` (M3) should look below the whole capsule footprint, not one ray at the origin: on a
    ledge's edge a ray from the feet misses the ledge, and a jump from there would be corrected.
- **Pushing apart** (the engineer's decision of 2026-09-30, #46; the rule is in the MVP rules, "Collisions"). Living
  players never pass through each other, but a body cannot block a passage. Each client moves only its own player
  against the other living players' capsules at their interpolated positions; the host tolerates overlap and never
  corrects it. `PlayerController` does not collide with players: each physics step a contact search on the living
  layer finds the capsules it touches, and for each one:
  - Walking into it pushes: the part of the motion into it slows to `push_speed_factor`, and the pusher drifts to its
    own right at `push_side_bias` of that speed, so a perfectly straight contact slides off instead of freezing. The
    pusher stops advancing once it is `push_max_overlap` deep in the other capsule (numbers in `PlayerTuning`).
  - Any other overlap is left at once (at most at sprint speed). That is how the pushed player's client moves its
    player: from the pusher's interpolated motion, at the pusher's reduced speed.
  - Head-on both push, and neither goes deeper than the overlap limit, so neither advances; the round capsules and
    the drift slide them apart. Each drifts to its own right, so they pass each other on opposite sides.
  - A ghost runs no search, and its layer is not searched: ghosts push nobody and nobody pushes them.

  Speed: a pushed player moves faster than its own walk or sprint without cheating (walking sideways at 4.5 m/s
  while a sprinter pushes it at 3.5 m/s is about 5.7 m/s, and two pushers add up). `PlayerController._push_apart`
  caps the push-out at `sprint_speed`, so the host's speed bound for a living player is its state's speed plus
  `sprint_speed` (proposed for M4, not decided; a test pins the cap). Ghosts get no allowance: they are never pushed.

  Prevents: two clients that see each other late snapping each other back and forth, and a player blocking a doorway.
  Accepted: a modified client can walk through players. Latency: the pusher sees the pushed player's capsule a round
  trip late (its own motion reaches the other client, which moves, and that motion comes back: about 0.2 s with
  100 ms interpolation on each side). Over a network the overlap limit, not the push speed factor, sets how fast a
  straight push goes: at most `push_max_overlap` per round trip, 1 m/s at 0.2 s instead of 2.25 m/s. The
  two-client tests (`player_controller_push_test.gd`) run with that delay. *Open (M4):* the playtest over a network
  decides whether that is enough; the options are a larger limit (deeper visible overlap) or drawing the pushed
  capsule moved ahead on the pusher's client (display only).
- **Ghosts** move like the living and get the same movement checks (floor, jumps, step height), with the walk and
  sprint speeds times the ghost speed factor (1.3), and stamina never limits them: a ghost's claims neither need nor
  spend it. They collide with the level client-side, not with the living or with other ghosts. `PickUp`, `PutDown`
  and `Use` from a ghost are rejected (`not_accepted`: Round accepts them from the living only). A ghost appears at
  its body (MVP rules): 2g (#63) sets its position to the body's rest position with a new epoch and sends it a
  `Correction`, always, even when it died on the floor. The movement rule treats that like a placement: claims in
  flight from the living player are dropped as stale, and its first claim as a ghost starts a new client-tick
  baseline on the floor at the body. The engineer corrected this on 2026-09-30 (#46): ghosts do not fly, so the
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
  2g (#63, `Strike` in `core/combat/strike.gd`) measures it so: the zone is a horizontal sector with its apex at the
  attacker's feet (the last accepted position), `reach_m` long and `angle_deg` wide around the horizontal part of
  the facing; a target's capsule has a point in it when its circle of `capsule_radius_m` around the target's
  position touches the sector (so an overlapping capsule touches the apex whatever the facing); it overlaps
  vertically when the two feet are at most `capsule_height_m` apart; the line of sight runs from the attacker's eye
  (`Items.eye_of`, the floor below plus the eye height) to the middle of the target's capsule. A facing with no
  horizontal part leaves only the apex; a `Use` without a finite facing takes the last accepted claim's. The
  cooldown is a `Cooldown` cost with the key `hit` in the knife's rule, recorded per player in `MatchState`.
- **Pick up and swap.** The client names the item; the host checks reach and line of sight from its own positions.
  With a full hand, the held item is put down where the picked-up one lay, a spot already known to be valid.
  2e (#61) measures the reach from the feet (the last accepted position) and the sight from the eye to just above
  the item (`Items.lifted`, 5 cm), so the floor or crate it lies on does not block the line.
- **Put down.** The client sends only its facing. The host places the item at the put-down distance along the
  horizontal facing, through `WorldQuery`: stopped before a wall and dropped to the floor. Prevents: a package put
  straight onto its circle across the map, or into a wall. 2e (#61) asks `rest_position` from the eye towards the
  point at that distance, so an item goes over what the player sees over (a low crate) and is stopped by a wall; a
  facing straight up or down puts it at the feet. The eye of the item rules (`Items.eye_of`) is the floor below
  the last accepted position plus the eye height, so a jump does not raise it: nobody puts a package, or sees one,
  over a partition from the top of a jump.
- **Drops.** An item dropped at a death or a leave, and a body, come to rest on the floor below the player's last
  position (through `WorldQuery`), never in mid-air. `Items.drop_held` (2e, #61) drops the item, asking the floor
  from 5 cm above the feet so a ray that starts on the floor still finds it; a level with no floor there is a
  level bug: the item rests at that position and the match logs an error. The body (`LifeRules.die`, 2g #63) is
  found the same way, with the same fallback, and the item then drops at the body.
- **Delivery.** The rule is "the package rests inside its circle, however it got there". So one check runs whenever
  an item comes to rest: a put-down, a swap, a drop at a death or a leave, the spawn, and later a throw, whose rest
  `server/` reports from its physics (`ItemRested`, #37). A package resting inside its own circle is delivered: it
  stops being interactive (`PickUp` is rejected) and its circle is shown as done. Holding a package over its circle
  never counts, because it is not at rest. A circle is an invisible cylinder standing on the floor at its marker
  (the engineer's decision of 2026-09-30, #79): radius 1 m (game design, in the data) and height 2 m (a
  placeholder). The package counts when its rest position is inside: within the radius horizontally, edge
  included, and from the marker's height up to that plus the height, both included (1 mm below the marker
  still counts: float noise between a physics floor and a hand-placed marker). The rest position is the one
  point `core/` knows of an item: the centre of its base on the surface it rests on, as `WorldQuery` placed it (or
  `server/` reports it, #37), not the centre of its mesh. So a package on a crate inside the circle counts, one on
  a floor below the marker does not. The check reads only that position; it asks no geometry of its own.

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
    **bodies** (peer → rest position, written by `LifeRules.die` before `player_died`; 2g); two tables keyed by names from the data,
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
    marker with two tags; a lobby with fewer `lobby_player` markers than the mode's maximum of players; a level
    without a layout. `Match` runs this part (`LayoutCheck`, 2b) on creation, with the tags each row's actions
    demand at the default settings and the maximum of players (§9.4). The content test runs it with the layouts of
    the mode's levels, read by the marker reader (2j, `server/levels/marker_reader.gd`), and checks that the
    greybox fits 10 players at the default settings and at the most packages
    (`tests/unit/content/content_modes_test.gd`).
- **Where a value comes from.** A part reads its own settings. A value the host changes in the lobby is a **match
  setting**: the mode declares it (`SettingSpec`: id, kind, default, bounds), and a part names it in a property
  ending in `_setting` (`count_setting = knives`). A part never reads another part's settings. Two kinds: a whole
  number (`MatchState.settings`), or a set of the mode's task type ids (`MatchState.id_sets`, empty by default, no
  numbers; the host's bans, `banned_task_types`, #79). A part lists its properties that hold a set
  (`ContentPart.set_settings`); the mode check refuses any other `_setting` property that names a set, so a part that
  reads a number never reads a set as 0. A transition action checks the settings together through
  `RuleEffect.settings_problem`, which `ChangeSettings` asks before applying any (§4.1). So the knife's numbers sit in
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
| `item_rested` | an item comes to rest: put down, swapped, dropped at a death or a leave, spawned; later thrown (`ItemRested`, #37) | the item, the cause (`put_down`, `swap`, `death`, `leave`, `spawn`), the rest position |
| `player_died` | a player's health reaches 0, before the held item drops | the player, the body position; no killer, as no event names one (§4.2) |
| `player_left` | a player leaves while the life state counts (Round, §3.5), before the held item drops | the player |
| `subtask_done` | a task type completes a subtask | the task; **its task type's detail** (`detail`; Delivery: the subtask's index and its package; no event carries it). A task has no owner (#79) |
| `clock_ended` | the match clock reaches its end (§3.3) | nothing more |

A reaction that copies a hidden field into an event whose audience is wider than that field's (a later mode's fact
that names a role, copied into an event to everyone) is a leak. Its entry must say so, and the reviewer of its PR
checks it against the §5 invariants. `subtask_done`'s detail is internal to its task type and in no event's schema,
but since #79 nothing in it is secret: Delivery's package and its index are public through `ItemSpawned` and
`PackageDelivered`.

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
`core/combat/`, `core/tasks/`, … as split in stage 2; the deal's actions in `core/deal/`, 2c). 2a creates the base class of every kind in this table but the
bot scenario's (2j), so stage-2 tasks that run in parallel share them instead of each inventing one; the parts and
phase classes come in the task each row names.

**What the later stage-2 tasks build on (2a, #49).** Each adds its own files and never edits `Match`:
- A part runs with a `MatchContext`: the `MatchState`, the mode, the `WorldQuery`, the tick; the actor and its
  intent (an action), the `Fact` (a reaction or a task type's check), or the outcome and its argument (a transition
  action, whose `layout` is the level being entered); and `emit`, `reject`, `raise_fact`, `report_outcome`,
  `rng(purpose)`, `setting(id)` and `error`. Names: `Intents`, `Facts`, `RejectReasons`.
- Events are `MatchEvent` subclasses in `core/events/`, each with its `audience()` (`Audience`: everyone, only,
  role, life, server, and sender for `Rejected`, 2b) and a `const AUDIENCE_KIND`, from which `ModeCheck` warns
  about role-owned public events.
- `Phase` (handled intents, outcomes, settings check, end tick, enter, exit, tick, intents, peers connecting and
  leaving); 2b (#58) filled the base mode's Lobby, Countdown, Loading and End classes, with `JoinRules` (joins,
  leaves, the ready flag) and `FitCheck` (the fit check) beside them in `core/match/phases/`, and
  `MatchState.newcomers` for the connected peers not yet players and `MatchState.joins` for the `Player<n>` names
  (§3.5); `MovementRule` (`core/movement/`) takes `MoveClaim`s, with the checks of §7.1 since 2d.
- `MatchState`: players (`PlayerState`, life ALIVE, GHOST or LEFT), settings and `id_sets` (§9.1), map, items
  (`ItemState`: ground, hand or locked), tasks (`MatchTask`: its task type and `TaskState`, no owner), stations,
  bodies, the cooldown and counter tables, `part_state`, the clock, the winner, `RngStreams`, and `reset_match` for
  `ResetMatch`.
- server/ and the tests drive `Match`: `start`, then per tick `apply` for each command and `tick`; `take_outbox`
  (events with recipients), `snapshot_for`, `speakers_for`, `view_of`, `command_log` and `Match.replay` (a replay
  that diverged from the recorded `WorldQuery` answers says so in `diagnostics`).
- The loop's own guards: only a phase class takes an intent from a newcomer (ModeCheck); an outcome reported while
  a row's actions or the old phase's exit run is an error, not the next phase's outcome; a step stops after 16
  transitions. `TickSystem` and `TaskType` declare `reported_outcomes()`, so ModeCheck requires their rows.
- No range rule (InReach 2e, Strike 2g) and no `server/` wiring (M3) lands before 2d (#60), which checks every
  claimed position (§7.1).
- What 2d adds for the others: `StaminaLedger` (`core/stamina/`: settle, `settle_ahead` before a check, `covers`,
  `spend`), `StaminaCost`, and `SelfStatusFeed.touch(state, peer)`: a rule that changes a player's health or stamina
  (2g's `Strike` for the victim) touches it, and `Match.tick` sends one `SelfStatus` per changed player at the end of
  the tick. That call is the one line 2d added to `Match`: nothing else runs after a tick's commands.
- **Items** (`core/items/items.gd`, 2e #61) is the one place that moves an item between the ground and a hand:
  `take` (the pick-up and the swap), `place` (an item comes to rest: `ItemPlaced`, then `item_rested`; the life rule, 2g, places a dead player's item
  at its body after `player_died`), `drop_held` (a leaving player's item to the floor below its last accepted
  position; the life rule calls it after the life state changed and `player_left` was raised) and `raise_rested` (`item_rested` for an item
  announced by its own event: after `ItemSpawned`, 2c's `SpawnItems` and 2f's Delivery deal call it with
  `Items.SPAWN`). The causes are constants there. Each condition names its own rejection reason as a constant.
- **Tasks** (`core/tasks/`, 2f #62; shared since #79): a task type marks a subtask done in its own task state, then
  calls `Tasks.subtask_done(ctx, task, detail)`, which emits `TaskProgress` (everyone; `Tasks.progress` counts the
  subtasks done and in total over every task), then raises `subtask_done`. `Tasks.all_done` is "every task done"
  for `AllSubtasksDone`. Delivery (`core/tasks/delivery.gd`, with its task state as the inner class
  `Delivery.State`) is the example for #36. `StationKind.radius_m` and `height_m` have a neutral default of 0,
  which the mode check refuses: the data sets them.
- **Win** (`core/win/`, 2h #64): the win conditions' parts `AllSubtasksDone`, `NoneAlive` and `ClockEnded`, and the
  transition actions `StartClock` and `EndMatch`. `Match` itself counts the clock and raises `clock_ended` (2a);
  `StartClock` only sets `MatchState.clock_ticks_left`, and `EndMatch` sets `MatchState.winner`, which
  `ResetMatch` clears.
- **Life** (`core/life/life_rules.gd`, 2g #63) is the one place that lowers health or changes the life state in a
  round: `LifeRules.damage` (`Damaged` to the victim, its `SelfStatus` touched; at 0 health `die`), `die` (the body
  on the floor below into `MatchState.bodies`, life ghost at the body with a new epoch; then `Died` (everyone),
  `Correction` (the ghost), `player_died`, and only then `Items.place` at the body with `Items.DEATH`) and `leave` (life
  left; `PlayerLeft`, `player_left`, then the drop with `Items.LEAVE`). A later weapon or a trap calls `damage`; the
  class is `LifeRules`, not `Life`, which would shadow `PlayerState.Life`.
- Two class names differ from their kind: `GameRole` and `RuleEffect` (a global `Role` or `Effect` would shadow an
  enum of `NetTransport` or GdUnit4).

| Kind | Answers | Class in `core/` | Data | MVP instances |
|---|---|---|---|---|
| Game mode | which phases, rules and settings a match has | `GameMode`, with `PhaseSpec` (its allowlist of `AcceptSpec`s), `Transition`, `SettingSpec` (a whole number or a set of task types), `SideSpec`, `PlayerRules` | `content/modes/` | the base mode |
| Phase class | what a phase does itself: its own intents, timers and outcomes | `Phase` subclasses (`RefCounted`; a fresh object per entry, §9.1) | named by a `PhaseSpec`, with its settings | Lobby, Countdown, Loading, Round, End |
| Rule | trigger → conditions → effects; an **action** is a rule on an intent, a **reaction** a rule on a fact | `Rule` | inside its owner | PickUp, PutDown, the knife's Use |
| Condition, cost | *only if*; a cost is also paid | `Condition`, `Cost` subclasses | inside a rule or a win condition | §9.4 |
| Effect, transition action | *what happens*; a transition action is an effect that a transition row runs, with no actor | `RuleEffect` subclasses | inside a rule or a row | §9.4 |
| Tick system | what runs every tick of a phase, in the phase's order | `TickSystem` subclasses | listed per phase | TaskTicks |
| Voice rule | who hears whom in a phase (§6) | `VoiceRule` subclasses | one per phase | Silent, Proximity, RoundVoice |
| Role | a side, what it knows, its abilities; a display name | `GameRole`, `RoleQuota` | `content/roles/` | Crew, Dissident |
| Item kind | a thing a player can hold, and what using it does; a display name (the HUD's held item) and its spawn tag | `ItemKind` | `content/items/` | Package, Knife |
| Task type | how its one shared task is dealt and done, with its own subtasks setting; what it demands of the map | `TaskType` subclasses, each with its `TaskState` (§9.1) | `content/tasks/` | Delivery |
| Task station | a place where a task is done, placed by its task type | `StationKind` (spawn tag, radius, height, colour palette) | inside its task type | the delivery circle |
| Win condition | which side wins, and when | `WinCondition` | `content/win_conditions/` | three (§9.5) |
| Interactable | a thing in the world that a player targets with an intent | v0: an item on the ground (`PickUp`). Fixed ones (a button) and bodies come with `Interact`, v1 (§9.8) | | packages and knives on the ground |
| Spawn point | where the deal may place something | `LevelLayout` in `core/content/` (2a): the markers by tag, in level order; `server/`'s marker reader (`MarkerReader`, 2j) fills it | markers in `levels/` (§9.6) | tags `lobby_player`, `round_player`, `package`, `knife`, `circle` |
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
  is one new script: the class, with its `TaskState` as an inner class (§9.8). Its interface (#79):
  `deal(ctx)` deals one shared task of the type (nobody owns it) and reads the type's own subtasks setting;
  `add_demands(settings, players, into)` says what that one task needs of the map (per spawn tag and colours) for
  the fit check of §9.4; `on_fact`, `tick` and `emits` as before.

### 9.4 Parts (v0)
**Conditions and costs** (a failed one rejects an intent with its reason, which reveals only what the column says):

| Part | Passes when | Settings | Rejects with | Built in |
|---|---|---|---|---|
| `ItemOnGround` | the rule's item (the intent's `item`) exists, lies on the ground (not held) and is interactive (not locked, as a delivered package is) | none | `unavailable`: whether an item is held or delivered is public | 2e (#61) |
| `InReach` | the item's rest position is within `reach_m` of the actor's last accepted position, its feet (§7.1) | `reach_m` (0.1 to 10; no default: the data sets it, the base mode 2) | `out_of_reach` | 2e (#61) |
| `InSight` | the line from the actor's eye (the floor below its last accepted position raised by `PlayerRules.eye_height_m`, §7.1) to just above the item's rest position is clear (`WorldQuery.line_of_sight`) | none | `blocked` | 2e (#61) |
| `HoldsItem` | the actor has an item in hand | none | `empty_hand` | 2e (#61) |
| `ActorRole` | the actor's role is one of the listed (no MVP use) | `roles` | `not_allowed`: the actor knows its own role | with the first mechanic that needs it (#34) |
| `AllSubtasksDone` | every task is done (`Tasks.all_done`): a task with no subtasks is done, and with no tasks it holds (the engineer's rule of 2026-09-30, #79) | none | (facts only) | 2h (#64, `core/win/all_subtasks_done.gd`) |
| `NoneAlive` | no player of the side is alive: each is a ghost or has left. A player's side is its role's; a player without a role of the mode is on no side, and with no player of the side it holds (the base mode's deal always leaves at least one crew member). It reads every player's role, which is hidden, but only as a win condition, whose `won` reaches no peer (§9.2) | `side` (a side of the mode) | (facts only) | 2h (#64, `core/win/none_alive.gd`) |
| `ClockEnded` | the match clock has reached its end (`MatchState.clock_ended`, set when `Match` raises `clock_ended`); before `StartClock` there is no end | none | (facts only) | 2h (#64, `core/win/clock_ended.gd`) |
| `Cooldown` (cost) | this player never paid this key, or at least `seconds` (in host ticks, toward zero, §3.3) passed since it last did; paying records the tick in `MatchState`'s cooldown table. Per player, not per item: a second knife does not skip it | `key` (no default: the data names it), `seconds` (0 to 600; 0) | `too_soon`: its own timing | 2g (#63, `core/combat/cooldown.gd`) |
| `StaminaCost` (cost) | the actor's stamina, settled first (§7.1), is at least `amount` (a ghost's always is); paying spends it and emits `SelfStatus` (the actor, at the end of the tick) | `amount` (whole points, 0 to `PlayerRules`' stamina maximum) | `tired`: its own stamina | 2d (#60) |

**Effects in rules:**

| Part | What it does | Settings | Emits (audience); raises | Built in |
|---|---|---|---|---|
| `TakeIntoHand` | the item goes into the actor's hand; a held item is swapped: it rests where the picked-up one lay (§7.1). An item not on the ground (a rule without `ItemOnGround`) is a rule error, logged, and nothing moves; the sender gets `Rejected` (`unavailable`) | none | `ItemPickedUp` (everyone); for a swap `ItemPlaced` (swap, everyone), then `item_rested` | 2e (#61) |
| `PutDownInFront` | the held item rests `distance_m` along the horizontal facing, stopped before a wall and dropped to the floor (`WorldQuery.rest_position` from the actor's eye, taken from the floor below, §7.1); a facing with no horizontal direction puts it at the feet | `distance_m` (0.3 to 3; no default: the data sets it, the base mode 1) | `ItemPlaced` (put down, everyone); `item_rested` | 2e (#61) |
| `Strike` | picks the targets as in §7.1 (living, not the attacker, within reach and half the angle, overlapping vertically, in line of sight from the eye) and damages each through the life rule (`LifeRules.damage`), in peer-id order; at 0 health a target dies there | `angle_deg` (1 to 360), `reach_m` (0.1 to 10), `damage` (whole points, 1 to 1000); no defaults: the data sets them (the knife 30, 1.5, 50) | `Swung` (everyone), even with no target, before any damage; per target `Damaged` and `SelfStatus` (the victim). A death: `Died` (everyone), `Correction` (the dead: its ghost at the body), `player_died`, then the drop: `ItemPlaced` (death, everyone), `item_rested` | 2g (#63, `core/combat/strike.gd`) |
| `ReportOutcome` | reports an outcome of the current phase (a meeting button, #35; no MVP use) | `outcome`, `argument` | an outcome (§3.1), which reaches no peer (§9.2) | with the first mechanic that needs it (#35); 2a builds the outcome reporting it calls |

**Transition actions** (effects that a transition row runs; the base mode's rows are in §9.5):

| Part | What it does | Settings | Emits (audience) | Built in |
|---|---|---|---|---|
| `DealRoles` | each quota in order draws its players from the present players not drawn yet, taken in peer-id order and shuffled with its RNG purpose; everyone else gets the default role. Roles forced by a debug command or a scenario (debug builds only, §8) come as data, because `core/` cannot tell a debug build: the command `ForceRole` (peer, role id; an empty id clears it), which only `server/`'s debug path or the scenario runner sends, in any phase and after the peer connected, since ENet names a peer only then; it sets `MatchState.forced_roles`, which `ResetMatch` keeps, for the deals that follow, and is in the command log like every command; a role the mode lacks is a match error and ignored. Each present peer with a forced role gets it before the draws, and a forced role counts toward its quota (the engineer's answer A on #30: `dissidents` 1 with bot 2 forced to dissident makes bot 2 the only dissident), so a quota draws its count minus the players forced to its role, never below 0; a forced role the mode lacks is a match error and ignored (2j) | `quotas` (`RoleQuota`: role, `count_setting`, `leave_at_least` (0 to 10; class default 0, the mode writes its number): the count is max(0, min(setting, N − leave_at_least)), and never more than are left), `default_role`, `rng_purpose` (`roles`) | `RoleAssigned` (that player), in peer-id order; then, per role of the mode that knows its teammates and has players, in the mode's order, `Teammates` (every player of that role); a forced role is told like a drawn one | 2c (#59); forced roles 2j (#66, `tests/unit/deal/deal_roles_test.gd`) |
| `DealTasks` | draws `tasks_setting` different task types at random (`rng_purpose`) from the mode's task types minus those in `banned_setting`, and runs each drawn type's `TaskType.deal` once, in the mode's order (§9.5, Delivery): one shared task each, owned by nobody (#79). Then `TaskProgress`. More tasks than types left (a check that did not run) is an error, and it deals the types left. Refuses in `ChangeSettings` (`settings_problem`): `tasks` above the types not banned, or every type banned (`out_of_bounds`). Mode check: `tasks_setting` a whole number whose maximum is at most the mode's task types, `banned_setting` a set of task types, `rng_purpose` not empty | `tasks_setting` (`tasks`), `banned_setting` (`banned_task_types`), `rng_purpose` (`task_types`) | the task types' events (Delivery: `StationPlaced`, `ItemSpawned`), then `TaskProgress` (everyone) | 2c (#59), shared and drawn in #79; tested with fake task types; Delivery's deal in 2f (#62) |
| `SpawnItems` | places `count_setting` items of `kind` on distinct random markers of the kind's spawn tag, skipping the markers where an item already rests (at most one item per marker in a deal, such as a package of Delivery's deal on a shared tag), into `MatchState`'s items; ids follow the markers' level order. Too few free markers (a fit check that did not run) is an error, and it places none | `kind`, `count_setting`, `rng_purpose` (`knives`) | `ItemSpawned` (everyone), in id order; then `item_rested` (spawn) for each, in id order | 2c (#59) |
| `PlacePlayers` | places every player at a distinct random marker of `tag` (§3.2) | `tag`, RNG purpose (`spawns`) | `PlayersPlaced` (everyone); `Correction` with a new epoch (each player) | 2a (#49) |
| `StartClock` | sets the match clock's end to now plus the setting (whole minutes, in ticks toward zero: 10 min is 12000); the last action of the deal's row, so the round's `PhaseChanged` announces the end tick. Mode check: a whole-number setting (not a set of ids) whose minimum is at least 1, since a 0-minute clock never ends | `minutes_setting` (`match_duration`) | `RoundStarted` (everyone), with the start tick | 2h (#64, `core/win/start_clock.gd`) |
| `EndMatch` | records the side of the `won` outcome as the winner (`MatchState.winner`). An argument that is no side of the mode is a rule error, logged, and nothing is recorded or emitted | none | `MatchEnded` (everyone): the side only | 2h (#64, `core/win/end_match.gd`) |
| `ResetMatch` | resets the match state from the roster: items, stations, tasks and their task states, bodies, roles, life, health, stamina, cooldowns, counters, per-part state, the clock and the winner; drops the players who left; keeps the session's join count (§3.5); everyone un-ready. Runs before the row's `PlacePlayers` | none | `ReadyChanged` (everyone), per player | 2b (#58, `core/match/reset_match.gd`) |

**Demands.** Every placing action, and every task type through `DealTasks`, answers one question: given the settings
and the player count, how many markers of which spawn tag does it need (and, for a station kind, how many colours).
2a defines that interface on `Effect` and `TaskType`, with no demand by default. `DealTasks` asks each task type not
banned for the demand of its one task; it reads the mode's task types from `Demands.mode` and the bans from
`Demands.id_sets`, because an effect's `add_demands` is given neither, so a `Demands` is always built for a mode
(`Demands.new(mode)`, 2c) with the set settings (`LayoutCheck.demands_of`). Which types a match draws is random, so
the fit check must hold for any draw (#79): per spawn tag `DealTasks` demands the sum of the *tasks* largest demands
of that tag among the types left, and per station kind the same over colours. Any draw of *tasks* types sums, per
tag, at most that, so a map that fits it fits every draw; with one type in the pool it is exactly that type's demand.
The price is a stricter check than a given draw needs when the types' demands differ. `all_ready` (2b,
`FitCheck`) sums the demands per tag over every row into a phase on the map (`LayoutCheck.demands_of`), compares
each sum with the chosen map's markers of that tag and each colour count with its palette (`Demands.shortfalls`,
§3.2, §9.6), checks the player count against the mode's bounds, and `SettingsChanged` shows them.

**Tick systems, phase classes and voice rules:**

| Part | Kind | What it does | Settings | Emits (audience) | Built in |
|---|---|---|---|---|---|
| `TaskTicks` | tick system | runs the tick of each task type that has one, in the mode's order (none in the MVP; #36) | none | the task types' events | 2f (#62) |
| `Lobby` | phase class | allows joins; `Hello` (the join, §3.5), `SetReady`, `ChangeSettings`; leaves (§3.5); reports `all_ready` (§3.2) after a `SetReady`, a settings change (numbers and the bans of task types, #79), a leave and on entry. Rejects (§4.1): `wrong_version`, `full`, `bad_args`, `unchanged`, `unknown_setting`, `out_of_bounds` (a bound, an unknown task type id, or a row action's `settings_problem`), `unknown_map` | none | `Welcome` (the joiner); `PlayerJoined`, `PlayerLeft`, `ReadyChanged`, `SettingsChanged` (everyone); `AllowJoins`, `DisconnectPeer` (server); `Rejected` (the sender) | 2b (#58) |
| `Countdown` | phase class | as Lobby for joins, leaves and `SetReady(false)`, each reporting `cancelled`; `countdown_done` on its end tick, `seconds` after entry | `seconds` (0 to 60; the class default 0) | as Lobby, and `CountdownCancelled` (everyone); its end tick goes out in `PhaseChanged` | 2b (#58) |
| `Loading` | phase class | refuses joins; `LoadMatch`; takes `LoadAck`s (another match's dropped, a second `unchanged`); at the deadline drops who did not confirm, never the host; a leave drops too; reports `all_loaded` | `deadline_seconds` (5 to 600; required, since a missing deadline would drop every client at once) | `LoadMatch`, `PlayerLoaded`, `PlayerLeft` (everyone); `RefuseJoins`, `DisconnectPeer` (server) | 2b (#58) |
| `Round` | phase class | nothing of its own: its intents go to rules, a leave to the life rule (§3.5, `LifeRules.leave`; a newcomer's leave is forgotten); a connection gets `DisconnectPeer` (2b) | none | `DisconnectPeer` (server); a leave: `PlayerLeft` (everyone), `player_left`, the drop's `ItemPlaced` (leave, everyone) and `item_rested` | 2a (#49); the leave 2g (#63) |
| `End` | phase class | `ReturnToLobby` from the host reports `back`; a leave sets life `left` (§3.5); a connection gets `DisconnectPeer` | none | `PlayerLeft` (everyone); `DisconnectPeer` (server) | 2b (#58) |
| `Silent` | voice rule | nobody hears anybody | none | the routing per tick (§5) | 2i (#65, `SilentVoice`) |
| `Proximity` | voice rule | every pair of present players within the radius (3D, §6); the living never hear a ghost (§5, for every rule) | `radius_m` (0.5 to 100; the class default 0, which the mode check refuses) | the routing per tick | 2i (#65, `ProximityVoice`) |
| `RoundVoice` | voice rule | the living hear the living within `living_m`; a ghost hears the living within `ghost_hears_living_m` and ghosts within `ghost_hears_ghost_m`, measured from the ghost; the living never hear the dead; a player who left hears and is heard by nobody (§6) | the three radii (each 0.5 to 100; the class defaults 0, which the mode check refuses) | the routing per tick | 2i (#65) |

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
- Written in `content/modes/base_mode.tres`, over neutral class defaults (0), so the designer sees every number
  there (the engineer's answer on #49): players, the match settings and the phase settings. The Godot saver drops
  a value equal to its class default, so a bound of 0 (`dissidents` and `knives` from 0) is the default itself.
- players 1 to 10. Match settings, default (bounds): `match_duration` 10 min (1 to 60); `tasks` 1 (1 to 1, the
  number of the mode's task types; #79); `banned_task_types` (a set of task types, empty; with one type nothing can
  be banned); `packages`, Delivery's subtasks, 6 (1 to 10, a placeholder, "not a decision"); `dissidents` 1 (0 to
  9, lowered to N − 1 by the deal); `knives` 2 (0 or more; the map's `knife` markers bound it at `all_ready`).
- `PlayerRules`, value (bounds): health 100 (1 to 1000); stamina 100 (1 to 1000), regenerating 15 per second (0 to
  1000); walk 4.5 m/s (0.5 to 20); sprint 7 m/s (at least walk, to 30) for 20 per second (0 to 1000), from 20 (0 to
  the maximum); jump 1 m (0 to 5) for 10 (0 to the maximum); ghosts walk and sprint at those speeds × 1.3
  (`ghost_speed_factor`: the engineer's decision of 2026-09-30; the bounds 1 to 3 are proposed, not confirmed);
  capsule radius 0.4 m (0.1 to 1) × height 1.8 m (0.5 to 3); eye 1.6 m (below the height); step 0.3 m (0 to 1).
  Health and stamina are whole points here, thousandths inside `core/` (§3.3). `PlayerRules`' class defaults are 0,
  so each number is written in `base_mode.tres` (`PlayerRules_base`), and a mode that leaves one out fails the mode
  check (2d, #60; the engineer's answer (1) on #58). Pushing (§7.1) is not in `PlayerRules`: `push_speed_factor`,
  `push_side_bias` and `push_max_overlap` are client feel tuning in `client/player/player_tuning.tres` (engineer),
  placeholders, never checked by the host; every client must ship the same values.
- Sides: `crew` ("Crew"), `dissidents` ("Dissidents"). Roles: Crew, Dissident. Item kinds: Package, Knife.
- Actions: PickUp, PutDown. Reactions: none. Task types: Delivery. Win conditions, in order: every task done, no crew
  alive, time up.
- Phases (accepts; tick systems; win conditions; clock; voice; level): Lobby (§3.2; none; no; stopped; Proximity
  8 m; lobby), Countdown 5 s (§3.2; none; no; stopped; Proximity 8 m; lobby), Loading 60 s (`LoadAck`; none; no;
  stopped; Silent; map), Round (`MoveClaim` from the living and ghosts, `PickUp`, `PutDown` and `Use` from the living;
  TaskTicks; yes; runs; RoundVoice; map), End (`ReturnToLobby` from the host; none; no; stopped; Silent; map).
  Snapshots in Lobby, Countdown and Round.
  RoundVoice's three radii: 8 m each.
- Transitions: §3.2. Their actions: `Loading, all_loaded → Round`: `DealRoles` (Dissident by `dissidents`, leaving
  at least 1; default Crew), `DealTasks` (`tasks`, `banned_task_types`, `task_types`), `SpawnItems` (Knife by
  `knives`), `PlacePlayers` (`round_player`),
  `StartClock`. `Round, won → End`: `EndMatch`. `End, back → Lobby`: `ResetMatch`, `PlacePlayers`
  (`lobby_player`).

Produces: the events of its phases and parts. Visible to: as each of them says.
Status: designed in #33; the skeleton in 2a (#49), filled by 2b to 2i. 2b (#58) built the phases Lobby, Countdown,
Loading and End, the join rules, the fit check, the mode check with layouts and the `End, back → Lobby` row's
`ResetMatch`. 2e (#61) added the Package, PickUp and PutDown, and Round's `PickUp` and `PutDown` from the living;
2g (#63) added Round's `Use` from the living together with the knife's rule, because the mode check refuses an
accepted intent that no rule handles. 2f (#62) added Delivery to the task types and TaskTicks to Round. 2c (#59) added Crew, Dissident,
the Knife and the `Loading, all_loaded → Round` actions, whose `DealTasks` deals Delivery. #79 made the tasks
shared and drawn: the settings `tasks`, `banned_task_types` and `packages`. Tests: the mode check of 2a,
the base mode's numbers and `End → Lobby` order, and the whole deal run by a match entering the round
(`tests/unit/content/content_modes_test.gd`, §9.1); the phases with a mode built in code
(`tests/unit/match/phases/`, `tests/unit/match/reset_match_test.gd`, `tests/unit/content/layout_check_test.gd`); the
scenarios in `content/scenarios/` (2j, #66: `tests/scenarios/scenarios_test.gd`, §9.7), on the flat lobby and
greybox of §9.6.
2i (#65) gave every phase its voice rule. 2h (#64) added the win conditions, `StartClock` (last in the
`Loading, all_loaded → Round` row) and `EndMatch` (`Round, won → End`); `content_modes_test.gd` plays a whole
match from this data to the end and back to the lobby, twice, and a round
with 0 dissidents set in its lobby.
Voice rules through the phases: `tests/unit/voice/voice_by_phase_test.gd`.

#### Crew (role)
What it does: the side that wins only when every task is done (§3.4).
Settings: id `crew`; display name "Crew"; side `crew`; knows its teammates: no; actions: none. The default role of
`DealRoles`.
Produces: `RoleAssigned(crew)`.
Visible to: that player only (§5); `MatchEnded` names only the winning side, never a player's role.
Status: designed in #33; built in 2c (#59): `content/roles/crew.tres`. Tests:
`tests/unit/deal/deal_roles_test.gd`, `tests/unit/content/content_modes_test.gd`.

#### Dissident (role)
What it does: the side that wins when time is up or no crew member is alive; dissidents know each other.
Settings: id `dissident`; display name "Dissident"; side `dissidents`; knows its teammates: yes; actions: none.
Dealt by the quota `dissidents`, leaving at least one other player.
Produces: `RoleAssigned(dissident)`; `Teammates(dissident, peers)`.
Visible to: `RoleAssigned` to that player; `Teammates` to each dissident, and to nobody else.
Status: designed in #33; built in 2c (#59): `content/roles/dissident.tres`. Tests:
`tests/unit/deal/deal_roles_test.gd`, `tests/unit/content/content_modes_test.gd`.

#### Delivery (task type)
What it does: one shared task of `packages` packages (the engineer's decision of 2026-09-30, #79); a subtask is done
when its package rests inside its own circle, however it got there (§7.1). Nobody owns the task: any living player
delivers any package.
Settings: `package`: the Package item kind; `circle`: a station kind (spawn tag `circle`, radius 1 m (0.2 to 10;
game design, in the data, not a lobby setting), height 2 m (0.1 to 10; a placeholder, "not a decision"), a colour
palette: 10 distinct colours, provisional, one per package at the most `packages` allows); `subtasks_setting`:
`packages` (its own subtasks setting: 1 to 10, default 6, a placeholder); RNG purposes `circles_rng`,
`packages_rng`, `tasks_rng` (`circles`, `packages`, `tasks`). One circle per package, fixed, not a setting.
- Deal (when `DealTasks` draws it): N packages and N circles, N the `packages` setting, whatever the player count.
  Circles on distinct random `circle` markers with distinct random palette colours (`circles`), packages on
  distinct random free `package` markers (`packages`; `Items.free_markers`), then each package, in id order,
  bound to a random circle of its own whose colour it takes (`tasks`; §3.3). Ids follow spawn-point order; subtask
  i is the i-th package. Emitted: every `StationPlaced`, then every `ItemSpawned` (with its circle and colour), in
  id order. Then `item_rested` (spawn) for each package, so one that spawned in its own circle counts at once,
  during the deal row's actions. With N = 0 the task has no subtasks and is done. A map without the markers or a
  palette without the colours deals nothing and logs a match error (the fit check at `all_ready` keeps a match
  from getting there).
- Demands (§9.4): as many `circle` and `package` markers as packages, and as many palette colours as circles, since
  colours never repeat; the player count does not matter. More circles than colours fails the fit check at
  `all_ready` like a missing marker; the lobby shows it. The binding itself is the circle id in `ItemSpawned`; the
  colour is what players see. The mode check refuses a circle station kind and a package item kind with the same
  spawn tag.
- Check, on `item_rested`: a package of an undone subtask that rests on the ground inside its circle's cylinder
  (`Delivery.rests_in`, §7.1: its rest position within the radius horizontally, and from the marker's height up to
  that plus the height, edges included) is delivered: locked (no longer interactive), its circle done, its subtask
  done; then `PackageDelivered`, `TaskProgress` and `subtask_done` (detail: the subtask's index and its package), in
  that order. Any other item in a circle, or a package in another package's circle, does nothing.

Produces: `StationPlaced` and `ItemSpawned` (with the circle and colour) in id order, `PackageDelivered`,
`TaskProgress` (the subtasks done and in total, over every task); `item_rested` (spawn), `subtask_done`. Its task
state (`Delivery.State`): per subtask its package, its circle and whether it is done. It has no tick.
Visible to: everyone, all of it: the task is shared, so every player learns the same (a ghost too; a player who
left, nothing). `PackageDelivered` names the item and the circle, never the task.
Status: designed in #33; built in 2f (#62): `core/tasks/delivery.gd`, `content/tasks/delivery.tres` (provisional);
shared, with the cylinder, in #79. DealTasks (2c, #59) calls its deal, and its packages take only free markers
(`Items.free_markers`). Tests: `tests/unit/tasks/delivery_deal_test.gd` (the deal, the demands, the mode check, no
private task event), `tests/unit/tasks/delivery_test.gd` (the check and the cylinder),
`tests/unit/content/delivery_content_test.gd` (the base mode's task settings, the circle and its palette),
`tests/unit/content/layout_check_test.gd` (its demands reach the fit check).

#### Package (item kind)
What it does: the item a Delivery subtask moves; any living player may carry any package.
Settings: id `package`; display name "Package"; spawn tag `package`; actions: none, so `Use` with a package in
hand is rejected (`nothing_to_do`). Placed by Delivery.
Produces: `ItemSpawned`, `ItemPickedUp`, `ItemPlaced`; once delivered, `PackageDelivered`, and `PickUp` gets
`unavailable`.
Visible to: everyone.
Status: designed in #33; built in 2e (#61, `content/items/package.tres`) and 2f (#62, Delivery). Tests: the parts'
in `tests/unit/items/` (a package built in code); its delivery in `tests/unit/tasks/delivery_test.gd`.

#### Knife (item kind)
What it does: the MVP's weapon: `Use` strikes in front of the holder.
Settings: id `knife`; display name "Knife"; spawn tag `knife`; actions: one rule on `Use` with costs `Cooldown`
(key `hit`, 0.5 s) and `StaminaCost` (25), and the effect `Strike` (30°, 1.5 m, 50 damage). The cooldown key is per
player, so swapping to a second knife does not skip the interval (§7.1). Placed by `SpawnItems` (`knives`).
Produces: `ItemSpawned`, `ItemPickedUp`, `ItemPlaced`; on `Use`: `Swung`, `Damaged`, `SelfStatus` (the attacker's
stamina, the victim's health), and on a death `Died`, the ghost's `Correction` and the dropped item's `ItemPlaced`.
Visible to: `Swung` and `Died` everyone; `Damaged` only the victim; the attacker gets no confirmation of a hit; a
refusal (`too_soon`, `tired`) only the attacker. The public `Swung` reveals no role: the rule belongs to the item
kind, which any living player may hold (§9.2).
Status: designed in #33; the item kind (id, name, spawn tag) and its `SpawnItems` in 2c (#59):
`content/items/knife.tres`, tested by `tests/unit/deal/spawn_items_test.gd` and
`tests/unit/content/content_modes_test.gd`; the parts built in 2g (#63): `Cooldown`, `Strike` (`core/combat/`) and
the life rule (`core/life/`), and the rule in `knife.tres` with `Use` from the living in Round's allowlist
(provisional under the MVP content ADR, for the engineer's approval).
Tests: `tests/unit/content/content_modes_test.gd` (the rule's numbers, and a base-mode round where the living
strike and a ghost's `Use` is `not_accepted`), `tests/unit/combat/strike_test.gd` (the zone, sight, order, who
learns what), `tests/unit/combat/cooldown_test.gd`, `tests/unit/life/life_rules_test.gd` (death, the ghost,
widening, the §3.4 order), `tests/unit/match/phases/round_phase_test.gd` (leaving mid-round).

#### Every task done (win condition)
What it does: the crew's only win.
Settings: side `crew`; conditions: `AllSubtasksDone`.
Produces: `won(crew)`, then `EndMatch`: `MatchEnded(crew)`.
Visible to: everyone, the side only.
Status: designed in #33; built in 2h (#64): `content/win_conditions/every_task_done.tres`. Tests:
`tests/unit/win/all_subtasks_done_test.gd`, `tests/unit/win/clock_ended_test.gd` (a delivery on the end tick),
`tests/unit/content/content_modes_test.gd` (the base mode's data).

#### No crew alive (win condition)
What it does: the dissidents win when every crew member is dead or has left.
Settings: side `dissidents`; conditions: `NoneAlive` (side `crew`).
Produces: `won(dissidents)`, then `MatchEnded(dissidents)`.
Visible to: everyone, the side only.
Status: designed in #33; built in 2h (#64): `content/win_conditions/no_crew_alive.tres`. Tests:
`tests/unit/win/none_alive_test.gd` (a death, a leave, the §3.4 order), `tests/unit/content/content_modes_test.gd`.

#### Time up (win condition)
What it does: the dissidents win when the clock ends with a subtask not done, with 0 dissidents too.
Settings: side `dissidents`; conditions: `ClockEnded`, `AllSubtasksDone` negated.
Produces: `won(dissidents)`, then `MatchEnded(dissidents)`.
Visible to: everyone, the side only.
Status: designed in #33; built in 2h (#64): `content/win_conditions/time_up.tres`. Tests:
`tests/unit/win/clock_ended_test.gd` (0 dissidents too), `tests/unit/win/end_match_test.gd`,
`tests/unit/content/content_modes_test.gd` (0 dissidents set through the base lobby).

#### PickUp (action)
What it does: takes an item from the ground into the hand, swapping a held one (§7.1).
Settings: a rule on the base mode: trigger `PickUp`; conditions `ItemOnGround`, `InReach` (2 m), `InSight`;
effects `TakeIntoHand`.
Produces: `ItemPickedUp`; with a full hand, `ItemPlaced` (swap) and `item_rested` for the swapped item, so a package
swapped onto its circle is delivered.
Visible to: everyone; a refusal (`unavailable`, `out_of_reach`, `blocked`) only the sender. A mode rule: its public
events reveal no role.
Status: designed in #33; built in 2e (#61). Tests: `tests/unit/items/take_into_hand_test.gd`,
`tests/unit/content/item_intents_test.gd` (only the living may send it).

#### PutDown (action)
What it does: puts the held item down in front of the player (§7.1).
Settings: a rule on the base mode: trigger `PutDown`; conditions `HoldsItem`; effects `PutDownInFront` (1 m).
Produces: `ItemPlaced` (put down); `item_rested`.
Visible to: everyone; a refusal (`empty_hand`) only the sender. A mode rule: its public events reveal no role.
Status: designed in #33; built in 2e (#61). Tests: `tests/unit/items/put_down_in_front_test.gd`; the drops at a
death or a leave: `tests/unit/items/items_test.gd`.

#### Use (action; the knife's hit)
What it does: uses the held item, as its kind's rule says; in the MVP only the knife has one (above). It replaces
#32's `Hit` intent, so that a new held item is data, not a new intent.
Settings, Produces, Visible to: the knife's. A ghost's `Use` is `not_accepted` (Round accepts it from the living
only); an empty hand, or a package, is `nothing_to_do`.
Status: designed in #33; built in 2g (#63), as the knife's. Tests: the knife's; a ghost's `Use`:
`tests/unit/life/life_rules_test.gd`, `tests/unit/content/content_modes_test.gd` (the base mode),
`tests/unit/content/item_intents_test.gd` (only the living, in every mode); a package's: `tests/unit/items/items_test.gd`.

#### Sprint (not a part in v0)
What it does: the `sprint` flag of `MoveClaim`, settled by the movement rule for every tick a claim covers (§7.1),
with the numbers in `PlayerRules`: 7 m/s, 20 per second, from 20. A tick costs only when the claim's `moving` flag
says the player gave movement input and it moved horizontally. A ghost sprints at 7 × 1.3 m/s for free.
Why not a part: a rule fires once per trigger, while sprint cost and speed apply to every covered tick of a
continuous claim. A mechanic that changes movement (a faster role, a slowing item) needs a movement modifier that the
movement rule reads: a new kind, v1 (§10).
Visible to: the player's own stamina in `SelfStatus`; speed is public through positions.
Status: designed in #33; built in 2d (#60): `MovementRule` and `StaminaLedger`. Tests:
`tests/unit/movement/movement_rule_test.gd`, `tests/unit/stamina/stamina_ledger_test.gd`.

#### Jump (not a part in v0)
What it does: the `jumped` flag of `MoveClaim`, accepted as in §7.1 with the numbers in `PlayerRules`: 1 m for 10.
A ghost jumps as high, for free.
Why not a part: as for sprint.
Visible to: as for sprint.
Status: designed in #33; built in 2d (#60): `MovementRule`. Tests: `tests/unit/movement/movement_rule_jump_test.gd`.

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
  under the MVP content ADR, with the engineer's approval in 2j's PR. As built (#66; the sizes and spacings are
  placeholders, "not a decision"): each is one `StaticBody3D` floor (a box collider whose top is at y = 0, with a
  matching mesh so `shot` shows it) and markers at y = 0. The lobby is 30 × 30 m with 10 `lobby_player` markers
  2 m apart; the greybox is 60 × 60 m with 10 `round_player` markers 2 m apart around the centre, 10 `package`
  markers along z = −12 and 10 `circle` markers along z = 12 (4 m apart, so no package spawns in a circle), and
  4 `knife` markers along z = −5: every tag for 10 players at the default settings and at the most packages. The
  content test checks that fit and that both levels are flat, which the scenarios' fake world assumes.
- A kind that other modes can reuse (a role, an item kind, a task type, a win condition) gets its own file; a rule,
  a phase spec, a row or a station is a sub-resource of its owner.
- **Markers.** A spawn point is a `Marker3D` in the level scene, in the persistent group `spawn_<tag>` of its one tag
  (the editor's Groups dock: `spawn_package`); a marker in two such groups is a load error. Packages and knives share
  spawn points when their item kinds name the same tag (say `item`), which is content data; a deal puts at most one
  item on a marker. A `circle` marker sits exactly on the floor a package rests on: its circle's cylinder starts at
  the marker's height, so a marker even a little above the floor leaves packages below the cylinder (§7.1); a
  `package` marker also sits on the floor.
  One tag per marker keeps the `all_ready` fit check exact: the demands per tag are summed and
  compared with that tag's markers, and a deal that passed it always finds its markers. `server/` reads the markers in
  scene-tree order, the level order of §3.3 (`MarkerReader`, 2j): each where the scene puts it, through its
  `Node3D` parents; a marker in two `spawn_` groups, a `spawn_` group on a node that is not a `Marker3D` and a
  group named `spawn_` alone are load errors. The markers of the station kinds' spawn tags (`circle`) are snapped
  down to the floor that the host's `WorldQuery` finds below them (asked from 0.1 m above, so a marker a hair under
  the floor still finds it), and one with no floor below is a load error (the engineer's answer on #82, item 3).
  This convention is provisional until 4e settles it with the designer (§10).
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

As built in 2j (#66; `core/content/scenario/`: `BotScenario`, `BotScript`, `NeverEvent`, `ScenarioTarget`, and
one class per step, `StepJoin` to `StepLeave`, whose `problems()` report an unplayable setup before a run):
- `Join` also takes `expect_rejected` (it sends `Hello`). `Ready`, `Setting`, `ReturnToLobby`, `PickUp`, `PutDown`
  and `Use` are done by their own answer: the bot's `ReadyChanged`, a `SettingsChanged` holding the value, the
  `PhaseChanged` to `lobby`, its `ItemPickedUp` of that item, `ItemPlaced` (put down) of the item it held, and
  `until` naming this bot when the event has a `peer`.
- `WaitFor` and `ExpectNone` look at the events from their own start; `Expect` also at those since the previous
  step started, so it sees what arrived with the previous step's answer (a `PackageDelivered` after a
  `PutDown`). `Expect` with `within` 0 checks only what already arrived. A bot runs its steps in one tick until
  one waits or sends; before its `Welcome` only `Join` runs, so a `Join` is a script's first step, at most once.
- `LoadAck` answers the `LoadMatch` that arrives while it is the bot's current step; one that arrived during an
  earlier step was acknowledged at once, and the `LoadAck` step then fails, saying so. A `Join` refused in Loading
  cannot be scripted in the core runner: `server/` refuses it at the transport, so the step fails.
- `WalkTo` claims one host tick of travel per tick (client ticks rising by one), at sprint speed only while the
  last `SelfStatus` says sprint is available (a ghost always, at 1.3 times), and stops exactly `stop_m` short.
  `Jump` claims a jump where the bot stands, on the floor. The setup's forced roles go in one `ForceRole` per bot
  right after the joins at the start, and its settings in one `ChangeSettings` from bot 1 after them.
- `fields` match a subset of the event's payload (then its properties, so `peer` works on `SelfStatus`): text as
  text, numbers and vectors approximately, and `peer` holds a bot's number. `never` names an event, fields and a
  bot (0: every bot).

- **Targets come from the bot's own view**, the events and snapshots its client received: `package(n)` (the n-th
  package in item-id order, from 1; tasks are shared, #79), `circle_of_held`, `nearest(kind)`, `bot(i)` (where it last saw
  that player), `point(x, y, z)`. A target the bot cannot know fails the scenario, so a scenario also proves that the
  mechanic is playable with what a player is told.
- **Failures:** a step that sends an intent fails on a `Rejected` it did not expect and names the reason; a step that
  does not finish within the time limit fails; a `Correction` outside a placement (§3.2) fails, because an honest bot
  is never corrected, so every scenario also checks the host's movement rules against honest movement. A field that
  names a player is written as the bot's number; the runner maps it to the peer id (the core runner: bot 1 is
  peer 1, bot i is peer 1000 + i, so a scenario that confuses the two fails).
- **Always asserted:** the expected ends within the time limit; no `ERROR:` line in the log; the §5 invariants on
  every bot's stream; over the network, the leak test (§5): the reliable events a bot decoded are exactly its peer's
  events in `Match.view_of`, in order, and every snapshot and voice frame it decoded is in `view_of`, which is a
  subset check, because the unreliable lanes (`LATEST`, `VOICE`) may lose some.
- **Runners:**
  - *Core* (stage 2j, #66): `tests/harness/` (`ScenarioRunner`, `ScenarioBot`, `ScenarioInvariants`) drives `Match`
    directly, as `server/` would. Each host tick every bot acts on what it received so far, its commands are
    applied in bot order with the tick's stamp, the tick runs, and each event goes to exactly its recorded
    recipients (`take_outbox`), so a bot holds its peer's `view_of`, which the runner asserts at the end. It
    stands in for `server/`: joins (`PeerConnected`, then `Hello`), `RefuseJoins` and `AllowJoins`, and
    `DisconnectPeer`, after which the bot is gone and its `PeerLeft` follows on the next tick. Until `server/`'s
    `WorldQuery` exists (M3) a flat fake answers the geometry (`FlatWorldQuery`, one floor at y = 0): the levels
    give their markers only, read into `LevelLayout`s by `server/`'s `MarkerReader`. The §5 invariants are
    checked from the match state's truth after every step and tick, never from an event's `audience()`: proven by
    declaring `Teammates` to everyone, which fails the suite. No `error:` line in `Match.diagnostics` (every match
    error of `core/`) stands in for the log's `ERROR:` lines. The MVP's scenarios play on the flat, marker-only
    lobby and map (§9.6). One GdUnit4 suite, `tests/scenarios/scenarios_test.gd`, runs every scenario in
    `content/scenarios/` and replays each match from its command log (the same events to the same peers), so
    `test` and `verify` run them from stage 2 on; `tests/scenarios/scenario_runner_test.gd` sees each kind of
    failure fail once.
  - *Bots* (M3, 3d): `tools\run.cmd bots [scenario]` starts a headless host, whose own client is bot 1, and the other
    bots as headless clients: over `LoopbackHub` in one process by default, or over ENet on 127.0.0.1 with
    `--instances`. The same files; it joins `verify` with the leak test (§5).
- **Reproducing a failure:** the runner prints the bot, the step, that bot's last events and the seed; the command log
  replays the match (§3.3).
- **The MVP's scenarios** (2j, #66; provisional under the MVP content ADR, for the engineer's approval), in
  `content/scenarios/`: `crew_delivers_every_package` (3 crew deliver the 6 packages; a delivered package's
  `PickUp` is `unavailable`; the crew never get `Teammates`), `dissident_kills_the_crew` (a forced dissident takes
  a knife and kills both crew; `too_soon`; a ghost's `PickUp` is `not_accepted`; the ghost walks),
  `dissidents_win_by_the_clock` (a 1-minute match that runs out; a jump, a sprint that runs out of stamina),
  `late_join_cancels_the_countdown`, `dropped_at_the_loading_deadline` and `refusals` (`empty_hand`,
  `nothing_to_do`, `out_of_reach`, `too_soon`, `tired`, a swap). The first three expect the ends `crew`,
  `dissidents` and `dissidents` (2h's win conditions); the other three `none`.

### 9.8 The extensibility test
Each later mechanic, on paper, against v0. The test counts classes in `core/`; the last paragraph says what each
costs outside it.

| Mechanic | Data | New part classes | New event classes | What else changes, and why |
|---|---|---|---|---|
| Zone task (#36): stand in a zone for N seconds | a task type `.tres` (N, the zone radius; #36's questions, reset or pause and shared zones, become settings), a zone station kind, `zone` markers in the map, the mode's task types | one task type (one script, §9.3): its deal places the zones and binds each subtask to one; its tick (through `TaskTicks`) advances the time in the zone, kept in its task state, for each subtask whose counted player is alive inside the zone. Who counts (any living player, or only those inside the zone) is #36's question | none for placement and progress: `StationPlaced` and `TaskProgress` are generic. One more if #36 wants the time in the zone shown live, and one if a zone is shown as done to everyone (`PackageDelivered` is Delivery's) | none: `DealTasks` draws among the mode's task types (#79), and the zone task brings its own subtasks setting |
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
existing part's behaviour; the change to an existing part is a new setting (`PlacePlayers`' `who`).
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
| How `MarkerReader` finds the floor under a `circle` marker in M3: `read_levels` reads every level of the mode before `Match.new`, from a copy outside any physics space, so the host's `WorldQuery` (§7.1, one space holding the loaded level) cannot answer it; either the reader computes the floor from the scene's own static colliders, or it reads each level once it is in the host's space (§9.6) | M3, before `server/` hosts a match |
| Lag compensation for hits (§7.1) | after the MVP playtest |
| Hiding positions behind walls (§5; not wanted now) | only if a human asks |
| Wire format of the message layer: schemas, encoding, versioning, reliability | M3 |
| The host's per-send ENet cost and upload for voice (ENet between two machines: settled by #21, §4) | M3 or M5 |
| Voice integration: occlusion, dead chat, meetings, radios, push-to-talk or voice activity, echo cancellation, device latency | M5 |
| Internet play without a VPN (NAT traversal): Steam networking vs WebRTC with a signaling server | M6 ADR |
