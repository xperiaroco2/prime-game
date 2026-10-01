# Architecture

| | |
|---|---|
| **Owner** | The engineer. The **content API** section is the contract with the designer: changes to it are reviewed by both. |
| **Status** | Skeleton (M0). The boundaries below are locked ([KICKOFF §3](history/KICKOFF.md); stack: [ADR](decisions/2026-09-29-technical-stack-from-the-brief.md)). Everything marked *open* is designed before M2 (core and content API) or in the milestone named. The match loop, intents, events and entitlement (§3, §4.1, §4.2, §5, §7.1): M2 design, #32. The content API v0 and bot scenarios (§9): M2 design, #33; built in stage 2 from 2a (#49) on. The wire schemas, the codec, the host session and the M3 client and bots (§4.3 to §4.6): M3 design, #89, accepted ([ADR](decisions/2026-09-30-wire-format-and-host-session.md)); built in M3. Vision revision 1 ([ADR](decisions/2026-10-01-vision-revision-1.md), #126) replaces ghosts, the one hand slot, `no_crew_alive` and the meetings mode: the sections that describe them describe the code as built until the M4 rework updates them (the ADR's Consequences list each section). The windowed client (§4.7) and the split of that rework into M4 issues: M4 design, #125, accepted ([ADR](decisions/2026-10-01-m4-first-person-client.md)). |
| **Rules for agents** | The invariants are repeated in the root `CLAUDE.md`, so they survive compaction. Area rules: `core/`, `server/`, `net/`, `client/`, `voice/` `CLAUDE.md`. |

## 1. Layers and boundaries

| Folder | Contains | May use | Owner |
|---|---|---|---|
| `core/` | Pure rules: match state machine, intent validation rules (movement checks included), win conditions, who is entitled to each event and entity (§5), voice routing rules, content-API primitives. `RefCounted` only; no Nodes, scenes, networking or audio | nothing outside `core/` | engineer |
| `server/` | Host logic: wraps `core/`, checks the sender, format and rate of intents, builds one message per recipient from `core/`'s entitlement, answers `core/`'s geometric questions (`WorldQuery`, §7.1) | `core/`, the `net/` abstraction | engineer |
| `net/` | Transport abstraction (ENet first), message schemas, serialization, sync | nothing game-specific | engineer |
| `client/` | Scenes, player controller, UI, camera, audio playback, dev console | the filtered view it receives; `net/` to send intents; `core/`'s content definitions and constants (its own copy of the mode: which maps exist, which phase accepts which intent), never `core/` state (`Match`, `MatchState`, `view_of`; [ADR](decisions/2026-09-30-wire-format-and-host-session.md), review answers) | engineer |
| `voice/` | Capture, Opus encode and decode, jitter buffer, playback plumbing | `net/`, `client/` playback | engineer |
| `content/` | Game modes, roles, abilities, items, sabotages, task types and win conditions as `Resource`s built from content-API parts (§9); bot scenarios (§9.7), whose data classes are part of the content API | the content API only | designer |
| `levels/` | Maps from reusable room, prop, interactable and task-station sub-scenes | the content API only | designer |
| `tools/`, `tests/` | Task runner, checks, bot harness; unit, integration and bot-match tests | everything (tests) | engineer |

Changing a boundary is a stop-and-ask item and gets an ADR.
Decided for M4 (E18, §4.7): `client/app/` alone also names `server/`, through the `HostNode` façade only, to host the
session its own client joins; no `client/` file names `HostSession` or reads `.game`.

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
- **More phases** (later): a mode may add its own, such as the deathmatch mode that vision revision 1 parks; the
  meetings mode (#35) is closed by that revision.

### 3.1 The loop, and how a game mode supplies its phases
- `core/` has one loop, `Match`, that knows no game mode. It owns the `MatchState`: the roster, the settings, each
  player's life state (alive, downed, dead, left), position, hand slot, health and stamina, the items, the tasks with
  their stations and per-task state, the bodies, the cooldown and counter tables, the per-part state, the match clock
  and the RNG streams (§9.1 says what each holds). The match state outlives phases, so a mode that leaves Round for a
  phase of its own and returns keeps everything. What lives only as long as one phase (the countdown's end tick, the
  loading acks) is in that phase's own object, created on entry (§9.1).
- A **game mode** is data (a `GameMode` `Resource`, §9). It lists:
  - the phases, each an id plus a phase class and its parameters, and the first phase;
  - per phase: the intents it accepts and from whom (an allowlist); its **tick systems** in the order they run (the
    base mode's Round: task types that tick; the other phases have none); whether it checks the win conditions (the
    base mode's Round only; §9.2 says when); whether the match clock runs; which voice rule applies (§6); which level
    is loaded; and whether snapshots are sent. Stamina and cooldowns need no tick system: they are settled when used
    (§7.1, §9.4);
  - a **transition table** of rows *from phase, outcome → to phase, actions*.
- An intent the phase's allowlist does not name, or from a sender it does not name, is rejected (`not_accepted`;
  the senders are a newcomer, any player, the living, the downed or the host). Two exceptions (3e, #97; §4.3): a refused
  `MoveClaim` is dropped without `Rejected` (E15), and a refused `Hello` from a peer that is not a player gets
  `joins_closed`, with `DisconnectPeer` when it is a newcomer (E14). An accepted intent goes to the phase class, or to the
  content part that handles it (an action such as pick up or a throw #37; §9.2: the rule of the
  held item, the role or the mode): a new action is a part plus an allowlist entry, not an edit of the phase class.
- A **phase class** handles its own commands and timers (the countdown, the loading deadline), emits
  events, and reports **outcomes**: named triggers such as `all_ready`, `cancelled` or `won`. Any content part may
  report an outcome as well, so a new trigger (a button in the level, say) needs no change to the phase it runs in.
- After every command, every tick, and every phase entry, `Match` takes the first outcome reported in that step, looks
  it up in the table, runs the row's actions (effects such as the deal's `DealRoles`, §9.4), exits the phase and enters
  the next. Rows are keyed by an outcome, so a transition without a trigger cannot be written; an outcome without a row
  fails loudly, and a unit test drives every row. Checking on entry means a phase whose condition already holds (every
  player ready when the Lobby is re-entered) moves on without waiting for another command. A later outcome in the same
  step is dropped and logged in every build: a condition (`all_ready`, `won`) is re-checked at the next step anyway. A
  one-off trigger (a button's intent) comes from the rule of the intent that starts its step, so it is first unless an
  earlier effect of the same command already ended the phase; then its sender gets `Rejected` with the reason
  `outcome_dropped`, so the loss is visible. That reason means "applied, but the outcome was dropped": unlike a refusal
  (§9.2), the rule's costs were paid and its effects ran.
- A mode with more phases (the parked deathmatch, say) is then data plus its phase classes, with rows out of Round
  and back. The deal runs only on `Loading, all_loaded → Round`, so returning to Round deals nothing, and a phase
  whose clock does not run pauses the match clock by its phase flag. `Match` does not change.
- **Life states** (vision revision 1; built in M4-1, #137, and M4-2, #138): `PlayerState.Life` is ALIVE, DOWNED,
  DEAD and LEFT, and `is_alive()` means ALIVE only. 0 health knocks a living player down for the knockdown time
  (`LifeRules.knock_down`); when it runs out the player dies (`LifeTicks`, §9.4); a player who leaves mid-round is
  left (§3.5). `PlayerState.life_deadline` is the host tick at which the current life state runs out (the knockdown's
  end; M4-3 the respawn). `AcceptSpec.From` names a newcomer (1), any player (2), the living (4), the host (16) and the
  downed (32). Bit 8 was the ghosts' and is never reused; a mode still written for ghosts would silently refuse the
  downed's claims, so the mode check refuses a sender bit that names nobody. The dead send no intents as players:
  `Match` accepts none from them under PLAYER, LIVING or DOWNED (M4-2), so an intent in flight at a death reaches no
  rule. HOST still accepts the host's own player dead for the session's controls (`ReturnToLobby` on the end screen,
  where whoever died in the round is dead until `ResetMatch`), never for a player's action (`MoveClaim`, `PickUp`,
  `PutDown`, `Use`: `Intents.PLAYER_ACTIONS`). A flag for the dead is added only when a mode needs one.

### 3.2 Base mode: phases and transitions
A **player** is a peer whose `Hello` was accepted; *everyone* in an audience means every player (§5). A connected
peer without an accepted `Hello` is in no rule, receives nothing but a `Rejected`, and `server/` drops it after the
hello deadline.

| Phase | On enter | Accepts (§4.1) | Voice (§6) | Clock |
|---|---|---|---|---|
| Lobby | joins allowed | `Hello`, `MoveClaim`, `SetReady`, `ChangeSettings` (host); leave | proximity | stopped |
| Countdown | its end tick: now + 5 s | `Hello`, `MoveClaim`, `SetReady(false)`; leave | proximity | stopped |
| Loading | the roster is frozen; joins refused; `LoadMatch`; the loading deadline | `LoadAck`; leave | nobody | stopped |
| Round | the deal has run (below); `LifeTicks` lets the downed die at the end of their knockdown | living: `MoveClaim`, `PickUp`, `PutDown`, `Use`; downed: `MoveClaim` (the crawl, §7.1); dead: nothing; leave | round rule | runs |
| End | frozen: no movement, no snapshots | `ReturnToLobby` (host); leave | nobody | stopped |

| From | Outcome: its trigger | To | Actions |
|---|---|---|---|
| (start) | the host creates the session | Lobby | |
| Lobby | `all_ready`: every player is ready, and the settings fit the map for the current player count (packages, circles, knives and players within the map's spawn points, the demands per spawn tag of §9.4, for any draw of the task types; circles within the palette's colours; 1 to 10 players) | Countdown | |
| Countdown | `cancelled`: a `SetReady(false)`, a join or a leave | Lobby | none: ready flags and positions stay, so after a leave `all_ready` fires on entry and restarts the 5 s |
| Countdown | `countdown_done`: the end tick is reached | Loading | |
| Loading | `all_loaded`: every player of the frozen roster confirmed. A leave, or a client's missing `LoadAck` at the loading deadline, drops that player from the roster. The host (peer 1) is never dropped, so the roster is never empty: if its own load fails, `server/` ends the session, which clients see as the host lost (#40) | Round | the deal (§3.3): `DealRoles`, `DealTasks`, `SpawnItems` (knives), `PlacePlayers`; `StartClock` |
| Round | `won(winner)`: a win condition (§3.4) | End | `EndMatch`: `MatchEnded`. The clock stops because End's clock does not run |
| End | `back`: the host's `ReturnToLobby` | Lobby | `ResetMatch`: the match state reset from the roster, everyone un-ready; then `PlacePlayers` in the lobby. In this order: placed first, a downed or dead player would be placed in the lobby still downed or dead, a dead one with no avatar in anyone's snapshot |

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
  clock's end as a host tick (`PhaseChanged`), so a clock paused by a phase whose clock does not run is
  re-announced on resume.
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
- **Dissidents:** no crew present (every crew member has left; vision revision 1, M4-2) → `won(dissidents)`; the
  clock reaches its end with a subtask not done → `won(dissidents)`, with 0 dissidents too. A downed or dead crew
  member is still present: killing takes time from the crew, and every crew member down at once does not end the
  round.

"The first win condition met ends the round" (MVP rules) also orders the effects inside one command. The last crew
member leaving with the last package over its circle meets "no crew present" before the delivery: the dissidents
win. The check after every fact is what makes this so: a leave raises `player_left` before the held item drops
(§9.2). A death ends nothing by itself, so a downed carrier who dies over its circle drops the package in and
delivers (V4): `player_died` comes first and meets no win condition, then the drop counts. M4-2 tests both with
fixture win conditions in the base mode's order (`tests/unit/life/life_rules_test.gd`,
`tests/unit/match/phases/round_phase_test.gd`) and again with the real win conditions and Delivery
(`tests/unit/win/none_alive_test.gd`), with the control that the same package put down wins for the crew.

Each win condition's side and conditions are data (`content/win_conditions/`, §9.5); `EndMatch` then tells
everyone the side, and nothing else (§5). Built in 2h (#64): `core/win/`, tested through seeded matches in
`tests/unit/win/` (the crew wins on the last delivery only, a delivery on the end tick counts, time up with 0
dissidents, no crew present only once every crew member left, End widens nothing; M4-2).

### 3.5 Joining, leaving and the host
| Phase | A client joins (its `Hello` is accepted) | A client leaves |
|---|---|---|
| Lobby | `Welcome` to it, then `PlayerJoined` and `SettingsChanged` to everyone (it included) | dropped from the roster; `PlayerLeft`, `SettingsChanged` |
| Countdown | as in Lobby, and `cancelled` | as in Lobby, and `cancelled` |
| Loading | refused: `core/` emits `RefuseJoins` on entering Loading and `AllowJoins` on entering Lobby, and `server/` sets `refuse_new_connections`. A peer whose connection completed anyway gets `DisconnectPeer`. Entering Loading also disconnects every newcomer still waiting (`DisconnectPeer`, no `Rejected`), and a `Hello` that arrives now gets `Rejected` (`joins_closed`) (E14, 3e) | dropped from the roster; `PlayerLeft` |
| Round | refused, as in Loading | life state `left`, which "no crew present" counts (§3.4); the avatar is removed and no body stays: a downed player who leaves leaves none, and a dead player's body is removed (the engineer's answer 1 on PR #133); in this order `PlayerLeft` (everyone else), the fact `player_left`, then the held item comes to rest on the floor below where the player stood (§7.1). 2g (#63): `RoundPhase` hands it to `LifeRules.leave`, after forgetting a newcomer that never joined (`JoinRules.forget_newcomer`) |
| End | refused, as in Loading | life state `left`; `PlayerLeft`. `ResetMatch` drops the player from the roster |

- **The join** (2b, `JoinRules`): `server/`'s `PeerConnected` makes a peer a *newcomer*, and only a newcomer's
  `Hello` is taken, once. Checked in order: the version equals the host's (`JoinRules.PROTOCOL_VERSION`), else
  `Rejected` (`wrong_version`) and `DisconnectPeer`; the content hash equals the host's (`Match.content_hash`, which
  `server/` passes to `Match.new` with the seed; §4.3, E1, 3e), else `Rejected` (`wrong_content`) and
  `DisconnectPeer`; the roster has fewer than the mode's maximum of players, else
  `Rejected` (`full`) and `DisconnectPeer`. A newcomer's leave is forgotten silently, and so is the late `PeerLeft`
  of a peer that a directive disconnected.
- **Names** (the engineer's decision of 2026-09-30, #58): the host names every joiner `Player<n>`, with n counted
  by accepted joins over the whole session (`MatchState.joins`): Player1, Player2, and so on. The host's own
  client normally joins first and so is Player1, but the rule is only the join order. A number is never
  reused: Player1 to Player3 join, Player2 leaves, and the next joiner becomes Player4. `ResetMatch` keeps the
  count, so it runs on through End → Lobby. The name in `Hello` is ignored in the MVP. After the MVP a player sets
  their own name and body colour, and a reconnecting player gets their old number back (#73).
- A client's missed loading deadline: `core/` emits `Disconnecting(load_deadline)` to p, then `DisconnectPeer(p)`
  for `server/`, and treats p as leaving; p's client ends with that reason, not `host_lost` (#119, M4-6).
- **The host is lost:** there is no `core/` event: `core/` runs on the host. How a client notices is a transport
  signal (#40); the client returns to the main menu with a message.

## 4. Protocol

**Model** ([ADR](decisions/2026-09-29-listen-server-and-message-layer.md)):
- Listen server: one player hosts as peer 1 and plays; no dedicated server. The host's own client talks to the host
  through an in-process loopback transport, with the same codec and per-peer filter as every other client.
- Own messages over `MultiplayerPeer` (ENet first), not RPCs, `MultiplayerSpawner` or `MultiplayerSynchronizer`:
  every outgoing message is built per recipient in one place, which the leak test checks (§5).
- The host leaving or crashing ends the match; clients return to the main menu with a message. No host migration
  and no reconnection in the MVP. A client leaving mid-match counts toward "no crew present" (§3.4), and its held
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
  `NetKindTable.game()`, is built from the message schemas' rows (`WireSchema`, §4.3, 3d).
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
  Godot process can freeze about 5 s (5.0 to 5.2 s) when another one on the same PC is killed or starts (Vulkan,
  the Windows driver since #124, did not freeze in 10 such runs; other freezes remain). Keep the minimum at 10 s or
  more; a servicing thread or an extra keepalive would not help (ENet already pings every 500 ms, and a thread
  would keep a hung game "connected"). ENet resends with a doubling delay from the measured
  round trip and, at a resend check, drops a peer once the oldest unacknowledged send is past the maximum, or
  past the minimum after the command's 6th attempt (timeout limit 32), so a drop comes between 10 s and about
  20 s (with ENet's default of 5 s: 5 to 10 s). Right after a connection, before a round trip is measured, it
  starts from 500 ms (checks at 0.5, 1.5, 3.5, 7.5, 15.5 and 31.5 s) and, with EnetTransport's 10 to 20 s,
  drops only after about 31.5 s (#95).
- **The backlog in one poll:** ENet reads at most 256 datagrams per service and `ENetMultiplayerPeer.poll()`
  services once, so after a freeze one service took only the oldest part of the backlog (on the Linux CI runner
  the thawed host's newest pose was up to 3.1 s old, #95). `EnetTransport.poll` services until one reads fewer
  (at most 16 times), so the LATEST merge sees the whole backlog.
- Checked by `tests/unit/net/transport/` and three headless runs on 127.0.0.1, which `verify`, and so CI, runs on
  a free port (`-- --port=<p>`; AGENT_WORKFLOW §11):
  - a host (with its own client) and two clients:
    `tools\run.cmd run tests/integration/net/enet_host_and_two_clients.gd --headless --instances 3`;
  - the freeze (#70): the host blocks its main thread for 5.2 s, then a client does; no drop, every reliable
    message in order, at most one LATEST message per peer per poll between that peer's reliable messages, and
    each thaw's backlog merged:
    `tools\run.cmd run tests/integration/net/enet_freeze.gd --headless --instances 3 -- --port=<p>` (the port
    is required). Before #95 the thawed host's newest message was about 1 s old on one PC and up to 3.1 s on the
    CI runner: the rest of the backlog came a poll later (above), not lost;
  - the stall (#95), one process with three hosts and a client each (`<p>` to `<p> + 2`): a side that is not
    polled is frozen to the other. Each side must have EnetTransport's timeouts on its peer when it reports the
    connection (`applied_timeouts`: the proof that both sides set them from the start), the running side must
    drop a stalled one after 10 to 20 s (the client's timeout on its host, and the host's on its client), and a
    backlog of 320 datagrams arrives in one poll. A host stalled at the moment of connection is also kept past
    10 s, which guards only against a too-low maximum: ENet waits about 31.5 s there with any timeout:
    `tools\run.cmd run tests/integration/net/enet_stall.gd --headless -- --port=<p>`.

*Designed for M3 (#89; accepted 2026-10-01):* the schemas of every intent, event, the snapshot and the voice frame, and their
rows in `NetKindTable.game()` (§4.3); the codec (§4.4); rate limits and what the host does with a peer that keeps
sending rejected packets (§4.5). `MoveClaim` stays on the LATEST lane and carries a cumulative jump count, so a jump
survives a merge (§4.3). The protocol version travels in `Hello` (§4.3), not in the transport's `ADMIT`. The
engineer took the recommendation of every choice E1 to E17 (E10 (b), E14 (a) with the client rule of (b)); the
[ADR](decisions/2026-09-30-wire-format-and-host-session.md) lists their options. The designer took D1 to D3 (a) (#96).
Every schema change updates §4.3 in the same PR.

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
  backlog. Vulkan is now the Windows rendering driver (`docs/decisions/2026-10-01-vulkan-on-windows.md`, #124):
  `--rendering-driver vulkan` never froze in 10 such runs. A windowed run with `--rendering-driver d3d12` still
  meets the freeze, and the 10 s minimum stays (a freeze can come from elsewhere). Review the driver before M6.

### 4.1 Intents (MVP, #32)
What each intent means and who may send it; the wire schemas are §4.3. The sender is always the peer id the transport
reports, never a field of the message. `server/` checks what the transport knows (sender, decoding, size, rate) and
passes the intent to `core/` as a command stamped with the host tick; `core/` checks the phase's allowlist (§3.1)
and the rules below. A rejected intent gets `Rejected` to the sender, whose reason depends only on facts the sender
is entitled to (§5). The fields each intent carries, with their Variant types, are `Intents.FIELDS` (3e, #97), the
list below in code: the rules read `MatchCommand.args` only through it (`MatchCommand.field` and its typed getters,
which read a field the intent does not declare as absent; `Match` records each such read as a match error in
`diagnostics`, which the tests and the bots runner see), and 3d checks the wire table against it (§4.4). A
`MoveClaim`'s `jumps` outside the wire's u16 is malformed in core itself (`MovementRule.MAX_JUMPS`).

| Intent | Who, in which phase | The host validates |
|---|---|---|
| `Hello(version, content)` | a connected peer that is not yet a player, once; Lobby or Countdown. In another phase a newcomer's `Hello` gets `joins_closed` and `DisconnectPeer`, another non-player's `joins_closed` (E14, 3e) | the version (an int) equals the host's, or `wrong_version` and `DisconnectPeer`; `content` (an int, the content hash, §4.3) equals the host's (`Match.content_hash`), or `wrong_content` and `DisconnectPeer` (E1, 3e); room in the roster, or `full` and `DisconnectPeer`. No name: the host names the joiner `Player<n>` (§3.5; own names: #73), and a `name` a client sends is ignored. Accepted, it is the join (§3.5) |
| `SetReady(ready)` | any player; Lobby (true or false), Countdown (false only: true is `not_accepted`) | `ready` is a bool, or `bad_args`; that it changes the player's state, or `unchanged` |
| `ChangeSettings(settings, map)` | the host (peer 1) only; Lobby only | `settings` names only the settings that change; each is a declared setting (`unknown_setting`) with a value of its kind (§9.1; else `unknown_setting`): an int within its bounds (`out_of_bounds`), or for `banned_task_types` an array of the mode's task type ids (another id: `out_of_bounds`), which replaces the set. Then the settings as they would be must suit the deal: `tasks` at most the task types not banned, and at least one type not banned (`out_of_bounds`; #79, placeholder rules). The optional `map` is one of the mode's maps (`unknown_map`). All or nothing. Whether they fit the map is checked at `all_ready` |
| `LoadAck(match_id)` | each player of the frozen roster, once; Loading | the current match id (the match's index in the session): an ack of another match is dropped silently; a second ack is `unchanged` |
| `MoveClaim(epoch, client_tick, position, velocity, facing, sprint, moving, jumps, on_floor)` | living players in Lobby, Countdown and Round; the downed in Round (the crawl, §7.1); never the dead; in another phase, or from another sender, dropped without `Rejected` (E15, 3e) | the current epoch and a rising client tick (else dropped as stale); finite values; the client tick rising at a bounded rate; speed for the life state and stamina; jumps; height (§7, §7.1). `client_tick` counts 20 Hz core ticks of the client's own clock (`Ticks.RATE`), not physics frames. `moving`: the player gave movement input, which sprint stamina counts (§7.1). A claim that fails a check gets `Correction`, not `Rejected`. `jumps` (3e, E2): the client's count of jumps since it adopted the epoch, which survives the LATEST merge (§4.3, §7.1) |
| `PickUp(item)` | a living player; Round | the item lies on the ground (not held, not delivered); pick-up reach from the host's position of the player; line of sight; a full hand swaps (§7.1) |
| `PutDown(facing)` | a living player with an item in hand; Round | nothing from the client but the facing: the host computes the placement (§7.1) |
| `Use(facing)` | a living player; Round | the first `Use` rule of the held item's kind, the actor's role or the mode (§9.2); none: `nothing_to_do` (an empty hand, or a package in the MVP). The knife's rule: its minimum interval since this player's last hit, whatever weapon that was; stamina of at least the hit's cost; the host picks the targets (§7.1) |
| `ReturnToLobby()` | the host only; End | |

A connection and a leave are not intents: the transport reports them, and `server/` passes `PeerConnected(peer)` and
`PeerLeft(peer)` to `core/`. The join is the accepted `Hello`; `server/` disconnects a peer that sent none within
the hello deadline. Debug commands (§8) are outside this table and exist in debug builds only: `ForceRole` (§9.4
`DealRoles`, 2j) is a command that `server/` originates, and on the wire (M3) it is a debug-only kind that only the
host's own client may send (§4.3, E17).

### 4.2 Events (MVP, #32)
Who receives each event is its audience (§5). A snapshot is not an event: §5 says what it holds for each peer. The
wire schemas of the events and the snapshot are §4.3.

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
| `KnockedDown` | peer, where it lies (the floor below its last accepted position) | everyone, the downed player included | health reaches 0 (`LifeRules.knock_down`, M4-2); no attacker or cause. It tells the attacker its hit knocked down: an accepted exception to "no hit confirmation" (vision revision 1) |
| `Died` | peer, body position | everyone, the dead player included | a downed player's knockdown time runs out (`LifeTicks`, M4-2); no event names a killer or a cause |
| `Correction` | epoch, position, velocity | that player | a `MoveClaim` that fails a check (§7.1); a placement (§3.2); a knockdown: the downed player where it lies, with a new epoch (§7.1 The crawl). None at a death: the dead send no claims |
| `Rejected` | the intent's sequence number, reason | the sender (*sender*: a present player, or a peer that is not a player: a newcomer whose `Hello` was not accepted yet, or a peer being disconnected whose intent was in flight) | any rejected intent but a `MoveClaim` (dropped, E15); an applied intent whose outcome was dropped (`outcome_dropped`, §3.1) |
| `MatchEnded` | the winning side (crew or dissidents), nothing else: no names, no roles | everyone | `won` |
| `Disconnecting` | reason: `load_deadline` (the only one today) | that player (`peer` is its subject, as `Correction`'s, although the payload names none) | right before the `DisconnectPeer` it explains: a missed loading deadline (#119, the M4 ADR's E21) |

Directives to `server/` have the audience *server* and reach no peer: `RefuseJoins`, `AllowJoins`,
`DisconnectPeer(peer)`. Built in 2b (#58): the events from `Welcome` to `PlayerLoaded` above, `ReadyChanged`,
`CountdownCancelled` and the three directives; `DisconnectPeer` follows the `Rejected` it explains, and `server/`
sends what came before it (§4, `disconnect_peer`). Built in 2g (#63): `Swung`, `Damaged` and `Died`; M4-2 (#138):
`KnockedDown`, and `Died` moved to the end of the knockdown. Built in 2h
(#64): `MatchEnded`, and `RoundStarted` is emitted (`StartClock`; the class came with 2c's deal events). 3e (#97): the
reasons `wrong_content` (E1) and `joins_closed` (E14), and `DisconnectPeer` for Loading's waiting newcomers. M4-6
(#142): `Disconnecting`, which `LeakCheck.FOR_ONE` lists by hand (§4.6).

### 4.3 Wire schemas (M3 design, #89)
[ADR](decisions/2026-09-30-wire-format-and-host-session.md); built in 3d (#98): every row below is a row of
`WireSchema` (`net/messages/`), and `WireBudget` is `server/wire_budget.gd`. Each message is one row: its kind
byte (the frame header, §4 Transport), its direction (C→H: a client to the host; H→C: the host to a client), its lane,
its fields in order and its payload cap. **The field names are `core/`'s**: an intent's are the `args` its rules read
(`MatchCommand`), an event's are the keys of its `to_dict()`. So a decoded message compares equal with what `core/`
emitted, which the leak test needs (§4.6).

**Wire types.** Little-endian; sizes in bytes.

| Type | Bytes | Encoding | The decoder rejects |
|---|---|---|---|
| `u8`, `u16`, `u32` | 1, 2, 4 | unsigned | fewer bytes left than the type needs, checked before reading |
| `s32`, `s64` | 4, 8 | two's complement | as above |
| `bool` | 1 | 0 or 1 | any other byte |
| `f32` | 4 | IEEE 754 single precision | NaN and ±infinity |
| `vec3` | 12 | 3 × `f32`: x, y, z | a component that is not finite |
| `colour` | 16 | 4 × `f32`: r, g, b, a | as `vec3` |
| `peer` | 4 | `u32` | 0, and anything above 2^31 − 1 |
| `item`, `station` | 2 | `u16`; where optional, 0xFFFF is none (-1) | 0xFFFF where not optional |
| `tick` | 4 | `u32`; where optional, 0xFFFFFFFF is none (-1) | 0xFFFFFFFF where not optional |
| `id` | 1 + n | `u8` n, then n bytes of `a-z`, `0-9` and `_`, n from 1 to 32 | another length or byte |
| `path` | 1 + n | `u8` n, then `res://` and bytes of `A-Z a-z 0-9 _ - . /`, n up to 255 | another prefix, `..`, another byte |
| `text` | 1 + n | `u8` n, then n bytes of printable ASCII (0x20 to 0x7E), n up to 64 | another byte (UTF-8 names come with #73) |
| `note` | 2 + n | `u16` n, then n bytes of printable ASCII, n up to 320 (a shortfall: `core/`'s longest names a 255-byte map path, E16) | as `text` |
| `list<T>` | 1 + Σ | `u8` count, then the items | a count over the field's maximum |
| `map<K, V>` | 1 + Σ | `u8` count, then key and value pairs, keys strictly ascending (by bytes for `id`, by number for `peer`) | a count over the maximum; a key out of order or repeated |
| `opus` | the rest | the rest of the payload, opaque: the host never decodes it | empty, or over the cap |

Maxima: 16 players on the wire (the base mode allows 10), so a list or map of players holds at most 16 entries (a
snapshot's avatars at most 15: never the viewer's own); a map of settings, spawn tags or station kinds at most 32; a
set of task types at most 16 ids; shortfalls at most 32. The sizes below are the MVP's with 10 players, then the cap.
These maxima bound the decoder, not the payload: at the maxima some kinds exceed their caps (`SettingsChanged`'s
`id_sets` alone could reach about 18 KB). How big they get depends on the content, so the content is checked
(E16): `WireBudget` (`server/`, 3d) computes, from a game mode, the worst case of every kind whose size its content
sets (`Welcome`, `SettingsChanged`, `LoadMatch`, `ChangeSettings`, `StationPlaced`, `ItemSpawned`, `Teammates`,
`PlayersPlaced`), with the mode's own ids, settings, map paths, `max_players` and shortfalls (at most one per demanded
spawn tag and station kind, plus the player count and the layout, each a full `note`). A mode over a cap is refused
when the host starts, with the kind named; a test runs it over every mode in `content/`, so `verify` catches a
content edit before a playtest instead of the encoder refusing a reliable event in one.

**Intents** (C→H). Every RELIABLE intent carries `seq`, the client's own rising number that a `Rejected` names.
`Hello`'s is 0 (its layout is frozen, below). `MoveClaim` has none: a failed check gets `Correction`. A client stops
claiming when its own copy of the mode says the new phase does not accept `MoveClaim` (§3.1).
- **Before its `Welcome`** a client treats any `Rejected` as the end of its join, with a message naming the reason.
  Before 3e a `Hello` that the phase refuses (Loading, Round, End) got `not_accepted` with seq 0 and nothing
  disconnected the newcomer, so it would linger until the hello deadline and read `host_lost`. Since 3e (#97, E14 (a))
  it gets a reason of its own, `joins_closed`, followed by `DisconnectPeer` while the sender is a newcomer (a peer
  already disconnected gets none), and the entry into Loading disconnects every newcomer still waiting (their `Hello`
  can no longer be accepted this match).
- **After its `Welcome`** a `Rejected(not_accepted)` with seq 0 can only answer a `MoveClaim` in flight when the phase
  changed, and a client ignores it. Since 3e (#97, E15 (a)) it is not emitted: a refused `MoveClaim` is dropped by
  `core/` (a claim has no seq to name), so a looping client's claims do not fill the command log and the outbox with
  `Rejected` events that every client ignores.

| Kind | Intent | Lane | Fields | Bytes; cap |
|---|---|---|---|---|
| 1 | `Hello` | RELIABLE | `version: u16`, `content: s64` (the content hash, E1) | 10; 8192 |
| 2 | `SetReady` | RELIABLE | `seq: u32`, `ready: bool` | 5; 5 |
| 3 | `ChangeSettings` | RELIABLE | `seq: u32`; `settings: map<id, setting>`, where a setting is `u8` 0 then `s32` (a whole number), or `u8` 1 then `list<id>` (a set of task types, which replaces the set); `has_map: bool`, then `map: path` when true (the args hold `map` only then) | 20 for one number; 2048 |
| 4 | `LoadAck` | RELIABLE | `seq: u32`, `match_id: u32` | 8; 8 |
| 5 | `MoveClaim` | LATEST | `epoch: u32`, `client_tick: u32`, `position: vec3`, `velocity: vec3`, `facing: vec3`, flags `u8` (1 `sprint`, 2 `moving`, 4 `on_floor`; other bits 0), `jumps: u16` (below) | 47; 47 |
| 6 | `PickUp` | RELIABLE | `seq: u32`, `item: item` | 6; 6 |
| 7 | `PutDown` | RELIABLE | `seq: u32`, `facing: vec3` | 16; 16 |
| 8 | `Use` | RELIABLE | `seq: u32`, `facing: vec3` | 16; 16 |
| 9 | `ReturnToLobby` | RELIABLE | `seq: u32` | 4; 4 |

**Debug commands** (C→H, E17): only in a debug build's table. `server/` takes them from the host's own client (peer 1)
only and turns each into the command it names; from another peer, or on a release host, whose table lacks the kind,
the message is malformed (§4.5). They are not intents: `core/` does not answer them with `Rejected` (§3.3 lists them
among the commands `server/` originates), and the seq only orders them in the client's log.

| Kind | Command | Lane | Fields | Bytes; cap |
|---|---|---|---|---|
| 24 | `ForceRole` (§9.4 `DealRoles`, 2j) | RELIABLE | `seq: u32`, `peer: peer` (the player whose role is forced, which becomes the command's peer), `has_role: bool`, then `role: id` when true; false clears the forced role (the command's `role` is then `""`, as `Match` reads it). `role` decodes as a `String`, not a `StringName`: `Match` reads it with `get_string`, which returns its default for a `StringName` | 19 for `dissident`; 42 |

**Events** (H→C), all RELIABLE: one-off facts, and state sent only on change. `SelfStatus` is such state: on LATEST,
losing the last change (stamina back to full) would leave a stale number on the HUD for good. Audiences: §4.2; a
directive has no row, because it reaches no peer.

| Kind | Event | Fields | Bytes; cap |
|---|---|---|---|
| 32 | `Rejected` | `seq: u32`, `reason: id` | 17; 37 |
| 33 | `Welcome` | `peer: peer`, `spot: vec3`, `epoch: u32`, `roster: list<peer: peer, name: text, ready: bool>`, `settings: map<id, s32>`, `map: path`, `phase: id`, `positions: map<peer, vec3>` | 410; 2048 |
| 34 | `PlayerJoined` | `peer: peer`, `name: text`, `spot: vec3` | 25; 81 |
| 35 | `PlayerLeft` | `peer: peer` | 4; 4 |
| 36 | `ReadyChanged` | `peer: peer`, `ready: bool` | 5; 5 |
| 37 | `SettingsChanged` | `settings: map<id, s32>`, `id_sets: map<id, list<id>>`, `map: path`, `players: u8`, `needed_markers: map<id, s32>`, `map_markers: map<id, s32>`, `needed_colours: map<id, s32>`, `palettes: map<id, s32>`, `shortfalls: list<note>` | 250 with no shortfall; 8192 |
| 38 | `PhaseChanged` | `phase: id`, `end_tick: tick` (optional) | 10; 37 |
| 39 | `CountdownCancelled` | `reason: id` | 9; 33 |
| 40 | `PlayersPlaced` | `spots: map<peer, vec3>` | 161; 257 |
| 41 | `LoadMatch` | `match_id: u32`, `map: path`, `settings: map<id, s32>` | 107; 2048 |
| 42 | `PlayerLoaded` | `peer: peer` | 4; 4 |
| 43 | `RoundStarted` | `start_tick: tick` | 4; 4 |
| 44 | `RoleAssigned` | `role: id` | 10; 33 |
| 45 | `Teammates` | `role: id`, `peers: list<peer>` | 19 for two; 98 |
| 46 | `StationPlaced` | `station: station`, `kind: id`, `colour: colour`, `position: vec3` | 37; 63 |
| 47 | `ItemSpawned` | `item: item`, `kind: id`, `position: vec3`, `has_station: bool`, then `station: station` and `colour: colour` when true (a package; the fields exist only then, as in `to_dict()`) | 41; 66 |
| 48 | `ItemPickedUp` | `peer: peer`, `item: item` | 6; 6 |
| 49 | `ItemPlaced` | `item: item`, `position: vec3`, `cause: id` | 23; 47 |
| 50 | `PackageDelivered` | `item: item`, `station: station` | 4; 4 |
| 51 | `TaskProgress` | `done: u16`, `total: u16` | 4; 4 |
| 52 | `Swung` | `peer: peer`, `facing: vec3` | 16; 16 |
| 53 | `Damaged` | `amount: s32`, `health: s32` (thousandths, §3.3) | 8; 8 |
| 54 | `SelfStatus` | `health: s32`, `stamina: s32`, `sprint_available: bool` | 9; 9 |
| 55 | `Died` | `peer: peer`, `position: vec3` | 16; 16 |
| 56 | `Correction` | `epoch: u32`, `position: vec3`, `velocity: vec3` | 28; 28 |
| 57 | `MatchEnded` | `side: id` (the winning `SideSpec`'s id; audience *everyone*, 2h) | 11; 33 |
| 58 | `Disconnecting` | `reason: id` (`load_deadline`; audience *only* that player, M4-6, #119) | 14; 33 |
| 59 | `KnockedDown` | `peer: peer`, `position: vec3` (audience *everyone*, M4-2, #138) | 16; 16 |

**State and voice.**

| Kind | Message | Dir | Lane | Fields | Bytes; cap |
|---|---|---|---|---|---|
| 96 | `Snapshot` | H→C | LATEST | `tick: tick` (the host tick whose state it shows); `avatars: map<peer, avatar>`, an avatar being `position: vec3`, `velocity: vec3`, `facing: vec3`, flags `u8` (1 `downed`, M4-2; other bits 0), `held_item: item` (optional). Every living or downed player's avatar, never a dead one's (§5) | 392; 1024 (15 avatars: 650) |
| 112 | `VoiceUp` | C→H | VOICE | `seq: u16` (the speaker's frame counter), `opus` (one 20 ms frame, 1 to 500 bytes) | 47; 502 |
| 113 | `VoiceDown` | H→C | VOICE | `speaker: peer`, `seq: u16` (renumbered per speaker and listener, §4.5), `tick: tick` (the host tick whose routing let it through, E11), `opus` | 55; 510 |

The rules of the table:
- **Kinds.** 0 is the transport's `ADMIT`; 1 to 23 are intents, 24 to 31 debug commands (a debug build's table only,
  E17), 32 to 95 events, 96 to 111 state, 112 to 127 voice.
- **Frozen:** two whole rows never change. Kind 1 (`Hello`): C→H, RELIABLE, `version: u16` as its first two bytes,
  and its cap at `NetKindTable.MAX_PAYLOAD` (8192), which never shrinks. Kind 32 (`Rejected`): H→C, RELIABLE,
  `seq: u32` then `reason: id`, cap 37. A client of any version can then send its version and read
  `Rejected(wrong_version)` (§3.5), instead of timing out at the hello deadline on a host that drops its packets as
  malformed or over the cap. The host decodes `Hello` in two steps: the version, and the rest only when the version is
  its own; another version reaches `core/` as `{version}` alone and the rest of its payload is ignored, whatever its
  length (#73's name makes a later `Hello` longer than this one). 3d's version test pins both rows byte for byte and
  decodes a synthetic longer `Hello` of another version to `{version}`.
- **The version.** `JoinRules.PROTOCOL_VERSION` (`core/`) and the codec's version are one number, which a unit test
  pins. Every change to a row (a kind, lane, direction, cap, field, its type or its order) bumps it in the same PR.
  It was 2 when M4-6 (#142) added `Disconnecting` (58), and is 3 since M4-2 (#138) added `KnockedDown` (59) and
  renamed the avatar's flag `downed`; M4's protocol PRs each set it to their base's plus one at the rebase before the
  merge (the M4 ADR §4).
- **The content** (E1). `Hello.content` is the content hash: the game mode's (`ContentHash.of`, §3.3) combined with
  `FileAccess.get_sha256` of every level file the mode names (the lobby and the maps). `ContentHash` covers scripts
  and levels only by path, so without the files a designer's branch that moved a wall or a crate would join `main`
  and meet the same unexplained corrections and refused pick-ups (the host's `WorldQuery` answers from its level, the
  client walks its own). Any byte of a level counts, a light included: a false alarm costs a rebuild, a miss costs a
  playtest. An exported build, which may convert scenes, is M6's to check. The host's `server/` and each client compute
  it when they load the mode, and `Match` gets the host's with the seed. `JoinRules` compares it with the host's: another one gets `Rejected(wrong_content)` and `DisconnectPeer`. Prevents: the designer
  hosts a playtest from a branch with edited `PlayerRules`, the engineer joins from `main`, and the engineer's client
  predicts other speeds and stamina and is corrected over and over with nothing saying why. `Hello`'s name is not on
  the wire in the MVP (the host names every joiner, §3.5); #73 adds it with a version bump.
  The level files are walked (#118): every scene and resource a level reaches through
  `ResourceLoader.get_dependencies`, recursively and each once (a cycle, a piece two levels share), is hashed too,
  sorted by `res://` path, so a wall moved inside a room the map instances counts. A dependency with a known uid is
  the file the uid names, as Godot loads it, else its fallback path; a missing file is hashed as `missing`, and
  `ContentFingerprint.of` logs a warning naming it, on the host and on each client. Left out: scripts (`ContentHash` covers them by path) and Godot's generated
  files under `res://.godot/`; an imported asset counts by its source bytes and its `.import` settings. Levels that
  instance nothing hash as they did before the walk.
- **Ids** on the wire are the content's own names (`crew`, `knife`, `match_duration`) (E5), so a content difference
  shows up as an unknown id, never as the wrong thing. The mode check (§9.1) refuses an id outside the wire's alphabet
  (3e): a change to the content API that the designer took (D1 (a) in the ADR): ids lowercase snake_case of at most 32
  characters, which every MVP id already is. The ids that reach an `id` field, and who checks each: from the content,
  checked by the mode check (3e): role ids, side ids, item and station kinds, setting ids, spawn tags, phase ids, and the reject
  reasons that conditions and costs name (§9.4); from `core/`'s constants, checked by 3d's table-against-core test:
  `RejectReasons`, `CountdownCancelledEvent`'s reasons, the `Items` causes (`put_down`, `swap`, `death`, `leave`,
  `spawn`). An id that neither covers is a bug that the encoder refuses and logs.
- **Lossless** (E6). Every float is an `f32`, as the standard build's `Vector3` and `Color` hold it, so
  decode(encode(x)) == x and the leak test compares exactly.
- **The snapshot holds avatars only** (E3). Items and bodies change only through reliable events (`ItemSpawned`,
  `ItemPickedUp`, `ItemPlaced`, `PackageDelivered`, `Died`), which the client folds into its view (§4.6); a held item
  follows its holder's avatar. `core/`'s snapshot keeps items and bodies for `view_of` and the unit tests; the leak
  test compares the avatars. Prevents: a snapshot of every item and body (about 920 bytes with 10 players and 20 items)
  outgrowing the 1024-byte unreliable cap as a map gets more knives, with no way to split it, because the LATEST merge
  keeps only the last part.
- **`MoveClaim` and the jump** (E2). `MoveClaim` stays on LATEST and carries `jumps`: the number of jumps the client
  made since it adopted the claim's epoch (0 after `Welcome`, after every `Correction` and after every placement). The
  movement rule compares it with the last accepted claim's count in that epoch: a rise d ≥ 1 is one jump allowance,
  from the floor under the last accepted position (§7.1), and costs d times the jump cost (stamina settled first; not
  covered: `Correction`); a fall within an epoch is `Correction`. `jumps` replaces `jumped` (3e). Prevents: the LATEST
  merge keeps the newest claim of a burst, a jump in an older one is lost, and the player is corrected to the ground
  for a jump the host never saw. Accepted: a merged burst grants one jump height, because the take-off points of the
  merged claims are lost, so a player who climbed and jumped during a host freeze may be corrected once; and the covered
  ticks are settled with the newest claim's sprint and movement flags, so a sprint during a freeze may go unpaid.
- **Sizes.** The host sends each remote player a snapshot per tick: about 430 bytes on the wire with 10 players, so
  9 × 20 × 430 ≈ 0.6 Mbit/s of upload. A client's claims are about 1.8 KB/s with headers. A payload over its cap is never
  truncated: the encoder refuses it and logs an error (a bug in `core/`, the content or the table). 3d's tests: every
  mode in `content/` passes `WireBudget` (above); a payload built with 32-character ids, a 255-byte map path and the
  longest shortfall of each kind encodes within its cap or is refused by `WireBudget` first; and a synthetic mode at
  the declared maxima is refused with the kind named.
- **Voice batching** (M5). One frame per `VoiceDown`. If M5 confirms the per-send ENet cost (§6), a batch of several
  speakers' frames to one listener is a new row.

### 4.4 The codec (M3 design, #89)
- **One table** in `net/messages/` declares each row of §4.3: kind, name, direction, lane, cap and the fields with their
  wire types (E4). `NetKindTable.game()` is built from it, so a kind's lane is still declared once. A generic encoder
  and decoder walk the fields. `net/` references no `core/` class (§1): the names are strings, and a unit test in
  `tests/` checks the table against `core/`: every intent of `Intents.ALL` and every event class with a peer audience
  has a row whose fields are the intent's declared fields or the keys its `to_dict()` returns, each debug row (§4.3)
  matches the fields of the command it names (`ForceRole`'s, declared in `Intents.FIELDS` too), no row has a field that
  names a seed, and the table as a release build builds it (debug off) has no debug kind. The comparison leaves out the
  wire's own fields: `seq`, the presence flags (`has_map`, `has_station`, `has_role`) and `ForceRole`'s `peer`, which
  becomes `MatchCommand.peer`, not an arg. Before 3e an intent declared no fields: its rules read `args` where they
  needed them (`MovementRule`, `JoinRules.hello`, the lobby's settings), and
  `MatchCommand.get_bool` returns its default for a missing key, so a wire `jumps` against a rule that reads `jumped`
  would silently mean "never jumped". 3e (#97) therefore added `Intents.FIELDS` (intent → field → Variant type), which
  the rules read through (a read of an undeclared field is a match error, §4.1), and 3d's test compares the table with
  it.
- **Encoding** writes each field with `PackedByteArray.encode_*` into a buffer sized from the fields (or
  `StreamPeerBuffer.put_*`, little-endian unless `big_endian` is set). Never `var_to_bytes` or `bytes_to_var`, even
  without objects: their framing is as large as an Opus frame, they take any Variant type where a field expects one,
  and `bytes_to_var` ignores trailing bytes (§4 lessons). The encoder checks its input by the decoder's rules (an id
  with a capital letter, a vector that is not finite, a count over its maximum, a payload over its cap) and refuses
  to send, with an error in the log.
- **Decoding trusts nothing.** A reader over the payload checks that enough bytes are left before every `decode_*`
  (the 4.7.2 docs say `decode_u32` and its siblings "fail" when too few are left, so reading first could print engine
  errors that one peer can repeat at will), and fails the whole message at the first problem: a type rule of §4.3, a
  count over its maximum, map keys out of order, unknown flag bits, or bytes left after the last field (`NetFrame` has
  checked the frame's own size). A failed message is dropped and counted per peer (`bad_payload`, §4.5), and nothing
  of it reaches `core/`.
- **Decoded shapes.** An intent becomes the `args` of a `MatchCommand` (the flags as the bools `sprint`, `moving` and
  `on_floor`). An event becomes its name and a Dictionary equal to its `to_dict()`, with the same Variant types
  (`StringName` ids, `String` paths and text, `int`, `Vector3`, `Color`, typed collections); 3d pins with a test that
  `==` holds between them, or compares through one canonical form if typed and untyped collections differ. A snapshot
  becomes `{tick, avatars}`, its avatars in the shape of `Snapshots.for_peer`'s. A voice frame becomes its fields and
  the opaque bytes.
- **Tests** (3d): a round trip of every row, decode(encode(x)) == x; a fuzz test that feeds each decoder every
  truncation, every single-byte change and random payloads, and asserts a clean reject with no engine error line; the
  table checked against `core/` (above); the version pinned (§4.3).
  Built as `tests/unit/net/messages/` and `tests/unit/server/wire_budget_test.gd` (3d, #98). What the build pinned:
  - A single-byte change can make another valid message (a float, a letter of an id), so the fuzz accepts either a
    reject or a message the encoder writes back byte for byte; a truncated row that ends in `opus` is still a valid,
    shorter frame. The bytes of an Opus frame, which the codec never reads, get one change each, not all 255.
  - `decode_*` past the end does print an engine error (`ERROR: Condition "p_offset < 0 || ..."`): with the reader's
    bounds check removed the fuzz fails on those lines, which a `Logger` collects.
  - `==` holds between typed and untyped Dictionaries and Arrays and ignores key order; a `String` key equals a
    `StringName` key, but a `String` value does not equal a `StringName` value; a `PackedStringArray` inside a
    Dictionary never equals an `Array`, and `==` between the two at the top level is a script error. So the decoder
    builds exactly `to_dict()`'s Variant types (typed Dictionaries where `core/` types them, `PackedStringArray`,
    `PackedInt32Array`, `Array[Dictionary]`), and the codec's tests compare types as well as values.
  - Decoded shapes that `to_dict()` does not set: `ChangeSettings.settings` is an untyped Dictionary of `StringName`
    ids to an `int` or a `PackedStringArray`; a snapshot's `avatars` are untyped, as `Snapshots.for_peer` builds them.
  - At the declared maxima `ChangeSettings`, `Welcome` and `SettingsChanged` exceed their caps; `LoadMatch` (1445
    bytes) does not, and the snapshot's 15 avatars take 650 bytes of its 1024.
  - `wire_core_test.gd` compares the table with `Intents.FIELDS` (names and decoded Variant types, `ForceRole`
    included) and applies decoded `ForceRole`, `Hello` and `ChangeSettings` to a `Match`. A decoded `ForceRole`'s
    role must stay a `String`: `Match` reads it with `get_string`, which gives "" for a `StringName`, so the role
    would silently go unforced.

### 4.5 The host session (M3 design, #89)
`HostSession` (`server/`, 3f) is a `RefCounted` that owns the `Match`, the hosting transport (the host's own client
linked through `own_client_of`), the levels' collision worlds (3c, below) and the bookkeeping per peer. A thin `Node`
calls `step(now_usec)` from `_physics_process` with `Time.get_ticks_usec()`, before the own client's nodes
(`process_physics_priority`); tests and the bots runner call it with a clock of their own (§4.6). The host's own
client is a `ClientSession` on the loopback like any other (§4.6) and reads nothing of `HostSession`.

**Starting.** (1) Load the game mode and every level it names (the lobby and the maps), build each level's collision
world (3c, below), then read the markers with `MarkerReader.read_levels` (2j) through the host's `WorldQuery`, which
`read_levels` points at each level with `use_level(path)` before reading it (3c; the flat fake ignores it). So the
`circle` markers snap to the floor the host plays on: option (b) of §10's reader question, recommended on #66. A
level with load errors stops the host with the errors shown. (2) The session seed: 8 bytes of
`Crypto.generate_random_bytes`, the operating system's entropy, never the time (§3.3). (3) `Match.new`; a refused
mode stops the host with the refusals shown. `keep_history` stays off (the bots runner turns it on). (4) Host on the
transport and link the own client, then `Match.start(0)`: host tick 0 is the session's start (hosting first, so the
start slice's `RefuseJoins` or `AllowJoins` reaches the transport).

**Host ticks come from the clock:** tick = ⌊(now − start) × `Ticks.RATE` / 10^6⌋, in microseconds. Not a count of
physics frames: Godot runs at most `Engine.max_physics_steps_per_frame` physics steps per rendered frame and drops the
rest, so after a 5 s freeze a frame count falls behind the clients' clocks for good (the M1 lesson "stamp from the
host clock and skip ticks", §7). With physics at 60 Hz (the default) a core tick falls due about every third step.

**One step**, in this order (each choice names what it prevents):

| # | What | Why |
|---|---|---|
| 1 | **Catch up.** t = the tick of now. If the queue holds commands read in an earlier step (no tick was due then) and `ticked_through() + 1` < t, they are applied first, stamped with `ticked_through() + 1`, and that tick runs (when `ticked_through() + 1` = t they join step 4's batch, stamped the same). Then every tick up to t − 1 runs with no command (`Match.tick`). After each tick its outbox is delivered (5) and the voice routing table is refreshed | After a 5 s host freeze that is about 100 ticks: the phase timers and the match clock run through the freeze, and the claims that waited in the socket are then applied at t with the credit of those ticks (§7.1). Prevents: the first claim after a host freeze corrected for covering more client ticks than the host counted (#84's note) |
| 2 | **Refill** every peer's budgets for the host time elapsed since the last refill | Before any packet of this step is read, so a thawed peer's backlog meets a full budget (the M1 lesson, §7) |
| 3 | **Poll** the transport. `peer_joined(p)`: queue `PeerConnected(p)` and start p's hello deadline. `peer_left(p)`: queue `PeerLeft(p)`. A packet: over p's budget, dropped and counted (`over_budget`); else decoded (§4.4): malformed, counted (`bad_payload`); an intent, queued with its `seq`; a debug command (§4.3, E17), queued as the command it names when p is 1, else counted as malformed; a `VoiceUp`, relayed at once (below) | The transport's signals fire in arrival order, and the loopback's messages and the network's share one inbox, so the queue is by arrival with no merging (§3.3): the host's own client gets no priority beyond the order in which the host reads its inbox (its messages of the previous frame before the network's read in this one, at most one frame). Voice at once: holding it for the next tick adds up to 50 ms |
| 4 | **Apply**, when tick t has not run yet: every queued command in queue order, stamped with t (`Match.apply`), then `Match.tick(t)`. Otherwise the queue waits for the next due tick | `Match.apply` takes only the next tick to run (§3.3); a command is stamped when it is applied, so none is stamped with a tick that ran already |
| 5 | **Deliver** `take_outbox()` in order. An event is encoded once and sent to each recipient in peer-id order, skipping a peer this session disconnected (its `send` would fail with `ERR_DOES_NOT_EXIST`, expected, not an error) and a peer whose leave is pending (a reused id, "One outbox slice per call" below); a directive is carried out in its place: `RefuseJoins` and `AllowJoins` set `set_refuse_new_connections`; `DisconnectPeer(p)` calls `disconnect_peer(p)` after everything before it was sent, the `Rejected` that explains it included, and is dropped while p's leave is pending (it answers the connection that left, not one that took its id) | The recipients are `core/`'s, never the transport's broadcast target, which also reaches peers that are not players (§5). ENet's `peer_disconnect_later` keeps what was queued (§4). A `DisconnectPeer` of the host (peer 1) would be a `core/` bug (§3.2): the host ends the session |
| 6 | **Snapshots**, when a tick ran in this step: for each present player p, `snapshot_for(p)`; empty means the phase sends none; else `{tick: t, avatars}` (§4.3) to p on LATEST, after the tick's events. The voice routing table is refreshed after every `Match.tick` call, in step 1 as here (below) | A client sees a tick's events before its snapshot (both on channel 0). Catch-up ticks send none: only the newest state counts |
| 7 | **Deadlines.** A peer connected longer than the hello deadline (10 s, a placeholder, "not a decision") with no `Welcome` sent to it is disconnected (`disconnect_peer`) | Checked only in a step that ran 4, so a `Hello` that waited out a host freeze, or was read in a step with no tick due, is applied first. 10 s outlasts a 5 s freeze of either side. The late `PeerLeft` is a newcomer's, which `core/` forgets (§3.5) |

So a command is stamped with the tick that was due when the host read it, and the replay's order is the queue's.
Accepted in step 1: a command that waited in the socket during a host freeze is stamped when the host reads it, so a
`SetReady(false)` or a `LoadAck` sent during the freeze can lose to the countdown's end or the loading deadline.

**One outbox slice per call.** `HostSession` takes `take_outbox()` after every `Match.apply` and every `Match.tick`
call (steps 1 and 4), keeping each slice with the call that emitted it, and delivers the slices in order (5). Three
rules need the slices. (1) A reused peer id: from `peer_left(p)` until the call that applies `PeerLeft(p)`, p is left
out as a recipient of every slice taken before that call, as the voice relay does (below). Otherwise an event `core/`
addressed to the departed player, emitted by a command applied before its `PeerLeft`, would reach a new connection
that took p's id in the same poll and has not sent `Hello`. Slices taken after that call address the new p, which
`core/` knows as a newcomer. 3f's test of a leave and a join with one id between two ticks covers events too. (2) The
bots runner's invariants: in a debug build `HostSession` calls an observer, which only the bots runner sets, with
each slice and its command (none for a tick), before anything is delivered or applied next. So `ScenarioInvariants`
runs as in the core runner: `sender` is the command's peer, `check_event` sees the state right after the call that
emitted the event, and `check_tick` runs after every `Match.tick` call, catch-up ticks included (§4.6). (3) A failed
deal (below) is found before the slice is delivered.

**Voice relay.** The routing table holds `speakers_for(l)` for every present player l, refreshed after every
`Match.tick` call (catch-up ticks included: a catch-up that crosses Round → End must not relay under Round's routing),
so between two ticks it is the routing that `view_of` records for the last one (§5). A `VoiceUp` from speaker s goes, as
a `VoiceDown` (s, the stream's next seq, `ticked_through()`, the bytes unchanged), to each listener l ≠ s whose entry
holds s; one from a peer that is not a present player is dropped. Between two ticks the transport's word on a leave
wins: on `peer_left(p)`, p leaves the table at once as speaker and listener until the refresh after the tick that
applied its `PeerLeft`. Peer ids are chosen by clients and can be reused (§4), so a new connection with a departing
player's id must not speak or hear as that player before `core/` has seen the leave; the new peer is a newcomer, absent
from `speakers_for`, until its `Hello` is accepted. 3f tests a leave and a join with one id between two ticks. The seq
is renumbered per speaker and listener, so a listener cannot tell how much s sent to others (§6); the speaker's own seq
only orders one poll's frames. After a freeze of the host or of the speaker, at most the newest 5 frames (100 ms; a
placeholder) per speaker in one poll are relayed and the older ones dropped and counted: 5 s of backlog played late is
worse than a gap (M5 tunes it). Unreliable messages go only to players, and a player has sent its `Hello`, so none
overtakes the `ADMIT` (§4 Joining). The host never decodes Opus. M3 relays the bots' synthetic frames; capture and
playback are M5.

**Rate limits and malformed packets** (E7; the numbers are placeholders, "not a decision"). The accident they bound:
a client bug sends an intent every frame; every command, and every `WorldQuery` answer it causes, stays in the command
log for the whole match (§3.3), so one looping client grows the host's memory and work without end.
- Per peer, three token buckets, refilled for the host time elapsed in step 2, before the poll:
  - **voice frames** (`VoiceUp`): 500, refilled at 50 per second (one 20 ms frame each); the relay's newest 5 per
    speaker per poll bounds a backlog further;
  - **reliable intents**: 100, refilled at 20 per second;
  - **bytes** of every other message (the reliable intents and `MoveClaim`): 64 KiB, refilled at 16 KiB/s.

  An honest client sends about 50 frames, a few intents and about 1 KB of claims per second, so each bucket holds
  more than 10 s of it: a thawed peer's burst passes (the 5 s freeze of #21, and `MAX_TICK_CREDIT`'s 10 s). Voice has
  its own bucket so that a player talking at a high Opus bitrate never drains the budget that a `SetReady` or a
  `LoadAck` needs: a reliable intent dropped on a budget is acknowledged by ENet and never answered, and the client's
  state would diverge silently, which only a looping client may cause. `MoveClaim` is bounded by the LATEST merge as
  well (one per poll). A message over a budget is dropped before decoding and counted (`over_budget`). Nobody is
  disconnected for its rate: a freeze would trigger it too.
- Malformed: a peer whose messages the transport or the codec rejected 50 times within 10 s is disconnected, with one
  log line that names the peer and the reasons. An honest client of the same version sends none, and the margin covers
  a rare corrupted packet. A `Rejected` from `core/` (a swing `too_soon`) is a rule's answer, not a malformed packet,
  and is not counted. The transport signals each reject with its peer (`packet_rejected`, 3f), in the inbox's order.
- The host's own client (peer 1) is exempt from the budgets, the malformed-packet disconnect and the hello deadline:
  the transport refuses `disconnect_peer(1)` (§4). A codec bug that makes peer 1's messages malformed logs an error
  at the threshold and ends the session (3f tests it).
- The counters join the transport's summary line (at most one per 10 s, §4).

**Loading a level and `LoadAck`.**
- **Clients**, the host's own included: on `LoadMatch` a client loads the map only if its own copy of the mode lists
  that path (never a path from the wire alone), with `ResourceLoader.load_threaded_request` and a
  `load_threaded_get_status` check every frame, so its transport keeps polling while the level loads. It instantiates
  the scene, replaces the lobby and sends `LoadAck(match_id)`. A failed load leaves the session with a message; the
  host's own failed load ends the session (§3.2). On the host, instantiating the scene blocks the main thread it shares
  with `HostSession`; the next step's catch-up covers the pause like any host freeze.
- **The host's collision worlds** are built when the session starts, so loading asks nothing of `server/`: the host's
  own `LoadAck` means that its client loaded, and `WorldQuery` already answers for every level.

**`WorldQuery` over the host's own worlds** (3c; §7.1).
- **The world** (E8). Per level, a `World3D.new()` whose `space` gets one static body per `StaticBody3D` of layer 1
  (`world`) in the level's scene, through `PhysicsServer3D`: `body_create`, `body_set_mode` (static), `body_add_shape`
  with each `CollisionShape3D`'s shape RID and its transform composed up to the scene's root, `body_set_space`. The
  scene is instantiated only to be read, never added to a tree, then freed. Queries go through
  `World3D.direct_space_state` with the mask of layer 1. Prevents: the answers depending on the host's client scene (a
  headless host has none, and it holds player capsules), and a second live copy of the level's meshes and scripts.
  The cost: CSG and `GridMap` build their collision only inside a tree, so the builder logs an error for such a node
  with collision, and a level that relies on one fails 3c's check instead of letting players walk where the host sees
  nothing. The level conventions (4e) then give collision as `StaticBody3D` nodes (the designer took D2 (a), 2026-10-01,
  #96; `levels/CLAUDE.md`).
- **Which level** (E9). `Match` tells the port the level of the phase it enters, before a row's actions run:
  `WorldQuery.use_level(path)` on start and in each transition (built in 3e, #97: the path of the lobby or the map,
  empty for a phase with no level; `RecordingWorldQuery` forwards it without recording an answer, the flat fake and
  the replay ignore it). Prevents: a
  row action that asks geometry (none does in the MVP) getting the old level's answer, as it would if `server/`
  switched levels between steps.
- **The answers.** `line_of_sight(a, b)`: `intersect_ray` from a to b hits nothing. Two floor answers (E10 (b)): `floor_below(p)`, one downward ray at p, for items and bodies (`Items`'s drop and
  put-down, the body in `LifeRules`); and `stand_floor_below(p)` (in the port since 3e, #97), p's x and z at the height
  of the highest floor under five downward rays, at p and at four points on a circle of the capsule's radius around
  it, for a player's standing (`MovementRule`'s take-off and landing, the reach's eye height), so a player on a
  ledge's edge stands on the ledge (§7.1's note). Prevents: a package put down within a capsule radius of a low ledge
  resting at the ledge's height beside it, which the delivery check reads (§7.1), so the same drop counts or not by the
  ledge. `rest_position(a, b)`: a ray from a to b, stopped 0.2 m (a placeholder) before
  the first hit, then `floor_below`. `core/` records every answer in the command log (§3.3).
- **A fresh space.** Whether a space answers queries before its first physics step under Jolt is unproven (#32's
  gotcha). 3c probes it first: build a world, query it in the same frame, and again after one physics step. If the first
  query misses, the host waits one physics step after building the worlds, before `MarkerReader` asks them for the
  markers' floor and before `Match.start`. Either way the worlds exist before the first claim can arrive. Physics runs
  on the main thread (`project.godot` sets no physics thread), where the 4.7.2 docs allow `direct_space_state` outside
  `_physics_process`; stepping from `_physics_process` keeps it legal if that setting changes.
  **Probed in 3c (#99), Godot 4.7.2 with Jolt Physics:** the first query hits. A `World3D.new()` space with one static
  box added through `PhysicsServer3D` (`body_set_state` of the transform, then `body_set_space`) answers
  `intersect_ray` in the same frame, before any physics step, and again after one step: the host needs no wait, and 3c
  wires in no fallback. Shown by `tools\run.cmd test tests/integration/server/level_world_test.gd` (passed on
  2026-10-01), whose `test_a_fresh_space_answers_a_ray_before_and_after_one_physics_step` asserts both hits.
- **Built in 3c (#99).** `LevelWorld` (`server/level_world.gd`: `build(path)`, `from_packed(scene, path)`,
  `from_scene(root, path)`, `errors`) builds one level's world as above, and also reports a `CollisionPolygon3D` of a
  layer-1 body, which it does not read, any other physics body on layer 1 (a `RigidBody3D`, a `CharacterBody3D`), a
  scene that cannot be instantiated and a level that gives the world no layer-1 body; a disabled shape and a body on
  other layers are left out. Only a root CSG node with `use_collision` and a `GridMap` whose used items have shapes
  count as collision. An `AnimatableBody3D` is a `StaticBody3D`: built where the scene puts it, it never moves on the
  host. `HostWorldQuery` (`server/host_world_query.gd`: `for_mode(mode)` builds every level of the mode with its capsule
  radius, `errors`; `add_level`, `use_level`) answers as above; with no level (an empty or unknown path) it answers like
  an empty world. A floor answer keeps the point's x and z. A ray that starts inside a shape does not hit it
  (`hit_from_inside` is off: sight from inside a wall is clear, within §7.1's limit that the host does not check walls),
  and one that starts exactly on a surface may miss it, so callers ask from a little above the point, as `core/` does.
  `MarkerReader.read_levels` calls `use_level(path)` before reading each level. Tests: `tests/integration/server/`
  (fixture levels with a wall, a ledge and a low crate in `tests/fixtures/levels/`, a package put down beside the ledge
  through a `Match`, and 2j's flat levels).

**The command log and replays** (E13). The host keeps the log in memory (§3.3). A debug-build host writes the session's
log to `user://replays/` when the session ends (never after each match) and keeps the last 10: the log holds the session
seed, from which every later match's seed is derived (§3.3), so a log written after match 1 would let the host's human
or agent, debugging mid-playtest, replay it and read every role of match 2; the bots runner writes a failed scenario's
log next to its report, so `Match.replay` reproduces the failure with the same build and content (3f adds `CommandLog`'s
reading back). The log holds the seed: it stays on the host's disk and is never sent (§5).

**A failed deal is fatal** (the engineer's answer on #90, item 2, 2026-09-30). `core/` has no guard for a deal that
cannot complete: a `Delivery` deal that could not place its packages or circles logs a match error
(`Match.record_error`, kept in `Match.diagnostics`) and the round starts anyway, with no tasks, which every task done
turns into an instant crew win (§3.4). Which row deals, and which phase it enters, is the game mode's data (invariant
5), so `server/` keys on neither: `Match` counts the errors recorded while a transition row runs (its actions and
the exit, `Match.row_error_count()`, built in 3e, #97), and `HostSession` reads the count after every `Match.apply` and `Match.tick` call.
A new one ends the session with that error shown to the host's human, before that call's slice is delivered (above).
So any row whose actions fail is fatal, a deal or not; an error outside a row, such as a `ForceRole` naming a role the
mode lacks in the same host tick, is logged and the session goes on. The bots runner already fails a scenario on any
match error (§9.7). 3f tests it with a fixture mode whose deal logs an error.

**Ending.** The host quits, its own client's load fails, or the deal fails (above): `close()`, and every client sees
`host_lost` (#40).

**Built in 3f (#100).** The API that 3h and 3i use; the rest is in `server/CLAUDE.md` and the class comments.
- `HostSession` (`server/host_session.gd`): `HostSession.new(transport, schema)` on a transport not yet hosting.
  `start(mode, port, max_clients, now_usec)` (the real levels and a `Crypto` seed) or `start_with(mode, world,
  layouts, port, max_clients, now_usec, seed)` (tests and runners on flat levels) returns false with `errors` when
  refused, and may be retried; `game` is set only once a start succeeded. Then `step(now_usec)` every frame on the
  clock `now_usec` came from, and `close()`; `ended(reason)` fires once (`closed`, `row_error`,
  `own_client_malformed`, `own_client_disconnected`), after the transport closed. `own_client` is peer 1's transport:
  the owner runs the own `ClientSession` on it, so `server/` names nothing of `client/`. Settings:
  `hello_deadline_usec`, `replay_dir` (`user://replays`; empty writes no log).
- **The observer** (debug builds only), for the bots runner (3h): a `Callable` called after every `Match` call (the
  start, each `apply`, each `tick`, catch-up ticks included) with `(at_tick: int, command: MatchCommand, slice:
  Array[EmittedEvent])`, `command` null for a tick and the start, before the slice is delivered or anything else is
  applied; `session.game` is the match right after the call. It must not step the session.
- `HostNode` (`server/host_node.gd`): steps the session with `HostNode.now_usec()` from `_physics_process`
  (priority -100, also while paused); start the session with the same clock. Leaving the tree closes the session.
- Each slice is delivered as soon as it is taken (the order of step 5; the recipients skipped are those of that
  moment). Voice is relayed right after the poll, before step 4, stamped with `ticked_through()`.
- The loading deadline's `DisconnectPeer` has no `Rejected` before it in `core/` (§3.2), but a `Disconnecting`
  (#119): the dropped player gets every event addressed to it before the directive, that one last, and its
  `ClientSession` ends with its reason when the transport then reports the host lost.

### 4.6 The client, the bots and the leak test in M3 (#89)
- **`ClientSession`** (`client/net/`, 3g) is what every client runs: the host's own over the loopback, a remote one
  over ENet, and every bot. It decodes each message (§4.4) into a **decoded view** shaped like `core/`'s `PeerView`
  (§5): the events in order as (name, fields), the snapshots by tick, the voice frames as (speaker, tick, bytes). From
  it, it keeps what a player may know: its peer id and epoch, the phase, the roster, the settings; the items, stations,
  bodies and each player's life folded from the events (cleared on `LoadMatch` and on entering the lobby); the
  avatars of the newest
  snapshot; its own `SelfStatus`. It sends `Hello` on `connected`, intents with a rising `seq`, one `MoveClaim` per
  client tick (20 Hz) with its epoch, client tick and jump count, and `LoadAck` after loading. It never reads `core/`
  state (invariant 2).
  Built in 3g (#101) as `client/net/`: `ClientSession`, `DecodedView` (the record, in `PeerView`'s shape) and
  `ClientModel` (the fold). What the build pinned:
  - The owner calls `step(now_usec)` every frame, like `HostSession`: it polls the transport, advances a threaded load
    and sends the claim that is due. The client tick counts `Ticks.RATE` ticks from the first step; a step sends at
    most one claim, so after a freeze one claim carries the newest client tick. The mover gives the claim's motion
    (`set_motion`, `count_jump`) and adopts each `Correction` (the `corrected` signal); `Welcome` and `Correction`
    reset the jump count and put the claims at the host's position.
  - A client claims when its own copy of the current phase accepts `MoveClaim` from it: a player, living or downed
    by its own life fold, and the host's own player as peer 1 (`AcceptSpec.From`); never while dead, whatever the
    phase accepts (the dead send no intents). Before `Welcome` it claims nothing.
  - **The life fold** (E25, M4-2 #138): `ClientModel.life_of(peer)` is living unless a `KnockedDown` (downed), a
    `Died` (dead, with its body) or a `PlayerLeft` (left, its body removed, E26) of this match said otherwise;
    `is_alive(peer)` is `life_of(peer)` living. `ClientModel.Life` is the client's own enum, so no `client/` file
    names a `core/` state class. Tests: `tests/unit/client/net/client_model_test.gd` and
    `client_session_claims_test.gd` (a dead client stops claiming even where every player may).
  - It ends (`ended(reason)`, the transport closed) on a `Rejected` before `Welcome` (its reason), `host_lost`,
    `connect_failed`, `unknown_map` (a `LoadMatch` map its own mode does not list), `load_failed` and `left`; since
    M4-6 (#119) a `host_lost` after a `Disconnecting` ends with the `Disconnecting`'s reason (`load_deadline`).
    `EndReasons` (`client/app/`) says each in words.
    `map_loaded(path, scene)` fires before `LoadAck` goes out, so its owner instantiates the scene in the handler; a
    bot (`load_levels` off) checks the map and acknowledges without loading.
  - "Entering the lobby" is entering a phase whose level is the lobby from one whose level is not (End to Lobby): the
    model then clears a match's facts (items, stations, bodies, loads, role, teammates, tasks, the winner and the
    avatars), as on `LoadMatch`, and keeps the roster and the settings.
  - The decoded view is recorded only with `keep_history` on (off by default, like `Match`'s: 12000 snapshots in a
    10-minute match); the bots and the leak test turn it on. The model is always kept.
  - `Hello`'s content hash is `ContentFingerprint.of(ContentHash.of(mode), mode.lobby_level, mode.maps)`
    (`net/messages/`), which #100's host computes the same way. It takes the mode's parts, not the mode: `net/` names
    no `core/` class (a test pins it). Each level's file and every scene and resource it reaches are hashed (§4.3).
  - The model keeps its own copy of a snapshot's avatars: the view records the decoded one unchanged. A threaded load
    the session no longer waits for (it ended, or a newer `LoadMatch` came) is collected by `step()` once done.
  - Tested in `tests/unit/client/net/` against host messages encoded with the codec from `core/`'s own events over a
    `LoopbackHub`; the end-to-end tests against `HostSession` are 3f's (#100,
    `tests/integration/server/host_session_end_to_end_test.gd` and its siblings), the bots 3h's.
- **Bots** (`tests/harness/`, 3h): a bot is a `ClientSession`, a scenario script and an honest mover. The script is the
  core runner's (2j): on `main` `ScenarioRunner` holds both the §9.7 steps (`_run_step` and a method per step) and its
  stand-in for `server/` (`_queue`, `_deliver`, `_carry_out`), and `ScenarioBot.receive` takes `MatchEvent` objects. 3h
  splits the steps from the stand-in and has `ScenarioBot` learn from (name, fields), which the core runner takes from
  `to_dict()` and a network bot from its decoded view, so both runners play the same steps the same way, and
  `ScenarioInvariants` checks §5 in both (in the bots runner per `Match` call, through `HostSession`'s observer,
  §4.5). The mover moves its position toward the target at the walk or sprint speed of the mode's `PlayerRules` on
  the flat levels (2j), at the crawl speed with no sprint while downed, claims every client tick, counts its jumps
  and adopts every `Correction`; a dead bot claims nothing, and a `WalkTo` of a dead bot fails (M4-2). It acknowledges `LoadMatch` as §9.7 says, without loading the scene: a bot needs no geometry of its own.
  A scenario's forced roles go as the core runner sends them, one `ForceRole` per bot right after the joins, but on the
  wire: bot 1, the host's own client (peer 1), sends the debug kind (§4.3, E17) naming each bot's peer id, so the bots
  run in debug builds only. **Bot numbers to peer ids:** a scenario names players by bot number (§9.7), and nothing on
  the wire tells bot 1 which peer is bot i: the host names every joiner `Player<n>`, and over ENet the clients choose
  their ids (§4.5). So each runner owns a map from bot number to peer id, which `peer_of`, `matches` and
  `ScenarioInvariants` (its `never` check) take in place of today's static `ScenarioRunner.peer_of` (3h). The core
  runner keeps 1 and 1000 + i; the one-process bots runner fills the map as it connects each bot's loopback client
  (`LoopbackHub` hands out the ids). Over ENet each instance writes its peer id to `tools/out/bots/<scenario>/peer-<i>`
  on `connected`; bot 1 waits for all of them (up to the scenario's time limit), writes the whole map to `peers` there,
  and only then sends the `ForceRole`s; every other bot reads `peers` before its first step. Learning ids out of band
  is harmless: peer ids are public in the roster. A bot that joins later gets its `ForceRole` once its id is known,
  after it connected (§9.4). Its voice is synthetic: frames of varying length holding its peer id and a counter, so a
  listener also checks that the relay changed no frame and named the right speaker.
  **Built in 3h (#102)** in `tests/harness/`: `ScenarioPlay` holds the steps and the runner's hooks (send, connect,
  claim, travel, jump, leave, answer a load, stand); `ScenarioRunner` (core) and `NetPlay` (network bots) supply
  them; `ScenarioPeers` is each runner's map. In `bots/`: `BotClient` (a `ClientSession` that holds its automatic
  `LoadAck` back while the bot's step is `LoadAck`, since a bot loads no scene and would acknowledge at once),
  `BotsRunner` (one process), `BotsEnet` (one instance over ENet), `LeakCheck`, `BotWatcher` (the lurker and the
  refused bot), `ViewFile` and the entry `bots_main.gd`. What the build pinned:
  - A network bot's intent reaches `Match` one host tick or so after the core runner's would (the host reads it in
    its next step), so a step's timing differs by that much between the runners; the six MVP scenarios pass in both.
  - The mover claims one client tick of travel per client tick: when the bot walks, it advances by the client ticks
    since its last move (one per tick on the simulated clock), and its `ClientSession` claims the position on the
    next client tick. Standing, it claims where it stands with no velocity.
  - Bot 1 sends the `ForceRole`s once it knows the peer of every bot that joins at the start, then the setup's
    `ChangeSettings`, as the core runner does at tick 0; a later joiner's `ForceRole` goes once it connected.
  - `ScenarioBot` matches a `peer` field of an event for one peer whose payload names none (`RoleAssigned`,
    `Damaged`, `SelfStatus`, `Correction`, `Rejected`) against the bot that received it: it is that event's subject.
  - A bot the host disconnects (`core/`'s `DisconnectPeer` in the core runner, its session's end in the bots runner)
    acts no more, but the `WaitFor` and `Expect` steps left in its script are checked on what it received, and any
    step still left fails (M4-6): so `dropped_at_the_loading_deadline`'s third bot waits for its
    `Disconnecting(load_deadline)`, which arrives just before the disconnect.
- **The runners** (§9.7; E12):
  - `tools\run.cmd bots [scenario ...]` runs every scenario in `content/scenarios/`, or those named, in one headless
    process over `LoopbackHub`: a `HostSession` with `keep_history` on, bot 1 its own client, the others loopback
    clients, all stepped by a simulated clock (60 steps per simulated second) as fast as the machine runs. A
    10-minute scenario takes seconds and runs the same every time.
  - `--instances N` runs one scenario over ENet on 127.0.0.1, on a free port as `verify`'s `enet` step: instance 1
    hosts with bot 1, instances 2 to N run one bot each, on the real clock. Each bot writes its decoded view and its
    peer id to `tools/out/bots/<scenario>/bot-<i>.bin` when its script ends (`FileAccess.store_var`: a local file,
    lossless, not the wire); the host waits for them (up to the scenario's time limit) and compares.
  - The one-process `bots` joins `verify` after `freeze` and `stall`, and so CI (all six MVP scenarios: about 8 s);
    the ENet run joins it too as `bots-enet`: `dissident_kills_the_crew` with 3 instances took 18 s (2026-10-01).
    M4-2 (#138) rewrote that scenario to knock both crew bots down, let them die and end by time up in a one-minute
    match (the shortest `match_duration`), so it now takes about 67 s.
  - Over ENet each bot writes its view file when its script is done and it decoded the expected ends (or its
    session ended), and keeps stepping until the host closes; the match goes on meanwhile, so the host compares each
    file's events with `view_of` as a prefix (a leak is still an event `view_of` lacks) that must reach `view_of`'s
    last `MatchEnded`, and its own bot, the lurker and the refused bot exactly. The one-process runner compares
    every bot that did not leave exactly.
  - A scenario step that needs two events in one poll (an `Expect` with `within_s` 0 right after a `WaitFor`) is
    exact in one process but timing-dependent over ENet, where a poll may split them:
    `dropped_at_the_loading_deadline --instances 3` failed once in four runs (2026-10-01), then passed 3 times. The
    ENet runs checked to pass: `dissident_kills_the_crew` (the `verify` step), `late_join_cancels_the_countdown`
    and `crew_delivers_every_package`. The bot's own placement check does not depend on polls: core/ emits one
    `Correction` after each placement of a player and after its knockdown (M4-2), and the bot expects exactly that
    one; a death sends none.
- **The information-leak test** (§5) compares what each bot b decoded with `view_of(b)`:
  - events: b's decoded events are `view_of(b)`'s, in order, as (name, `to_dict()`); for a bot that left, a prefix;
  - snapshots: each decoded snapshot's avatars equal the avatars of `view_of(b).snapshots[tick]`; a tick that `view_of`
    lacks is a leak (a subset check, because LATEST may drop), and so is a second snapshot of one tick
    (`DecodedView` keeps it apart, `repeated_snapshots`, instead of overwriting the first);
  - voice: each decoded frame's speaker is in `view_of(b).speakers[tick]` for its tick (a subset check);
  - what only one process can promise (#115's review): the host sends one snapshot per peer per step and every
    client polls once per step, so no transport of a bot or watcher may count a superseded LATEST message
    (`latest_superseded`); else a snapshot sent *before* the bot's own in the same step would be dropped unseen.
    Over ENet only the host's own in-process bot is held to it (a remote bot's real network may bunch two
    snapshots in one poll). And each speaker's `VoiceDown` seqs, by tick, run 0, 1, 2, ... without a gap
    (wrapping at 65536): the relay renumbers per speaker and listener and the loopback loses nothing, so a relay
    that forwards the speaker's own seq (how long it talked to others) fails. Every runner also fails on a packet
    its transport rejected or a message that did not decode (over ENet, bot 1's over its whole run), and the
    one-process runner on a message the host counted over budget or a packet the host's transport rejected;
  - peers that are not players: every scenario also runs a **lurker**, a bot that connects in Lobby and never sends
    `Hello`, and one **refused** bot (`wrong_version`). The lurker decodes nothing and the refused bot exactly its
    `Rejected`, which is `view_of` of each; neither decodes a `Snapshot` or a `VoiceDown`. The runner raises the hello
    deadline (a `HostSession` setting) for the lurker, so it stays connected through the lobby's and the countdown's
    events, snapshots and voice until the entry into Loading disconnects it (E14): a lurker that lost its connection
    with no `DisconnectPeer` of `core/` (a hello deadline, a dropped transport) fails, and so does one whose
    `DisconnectPeer` came at a tick with no `LoadMatch` (core/ cutting newcomers off before they saw anything). The
    refused bot must decode exactly one `Rejected` (`wrong_version`) and be disconnected by `core/`, and a watcher
    `core/` disconnected that is still connected fails (`server/` did not carry it out). Prevents: a `server/`
    refactor that sends *everyone* events, snapshots or voice to the transport's peers instead of `core/`'s
    recipients, which the entitlement ADR rejected because it reaches peers that are not players, passing a test in
    which every bot is a player within one tick;
  - the §5 invariants, which read each event's own fields in `Match.emitted()`, not its audience. Some events carry no
    peer in their `to_dict()` (`RoleAssigned`, `Damaged`, `SelfStatus`, `Correction`, `Rejected`), so the invariants
    read the `MatchEvent` objects of `view_of(b).events`, which the positional equality above has matched to what b
    decoded: every event for one peer that b decoded names b as its subject, and a view with no peer id that decoded
    anything fails. The events for one peer are a hand-written list in `LeakCheck.FOR_ONE` (`Welcome`,
    `RoleAssigned`, `Damaged`, `SelfStatus`, `Correction`, `Rejected`, and since M4-6 `Disconnecting`), which does
    not trust the declarations, plus any event whose class declares `AUDIENCE_KIND` `ONLY` or `SENDER`; a test fails when such a class is missing
    from the list. Proven on #115: `Correction` declared *everyone* failed 5 of 6 scenarios (`refusals` has one
    bot), where the declaration-only check of an earlier commit passed it. A crew bot decodes no `Teammates`; a dissident's `Teammates` names
    that match's dissidents only; no bot decodes a dead player's avatar, or a downed or dead speaker's voice frame, a
    downed bot hears only the living and a dead bot nobody; every event a bot decodes while dead is for it alone (the
    subject check) or also reached every living peer present then, so nothing reaches only the dead (M4-2, the
    recipients from `Match.emitted()`, which each bot's decoded events are checked against); the bots present for a
    whole round decode the same task events; no decoded message has a field that names a seed; a peer that is not a
    player decodes at most a `Rejected`, none unless it sent a `Hello`. `keep_history` costs memory (§5), so scenarios
    stay short, or 3h compares per tick over a window and drops what it compared.
  - **Proven once** (3h): inject a leak that the comparison catches (`server/` sends every `RoleAssigned` to everyone),
    one that only the invariants catch (`Teammates` declared *everyone* in `core/`) and one that only the lurker
    catches (`server/` sends *everyone* events to the transport's peers instead of `core/`'s recipients), see the test
    fail on each, revert, and record all three in the PR. **Done in 3h (#102)** with `tools\run.cmd bots`: the first
    failed 5 of the 6 scenarios on the comparison alone (`refusals` has one bot, which gets its own `RoleAssigned`
    anyway); the second failed on `ScenarioInvariants` through the observer (`peer 2 (crew) learned the role of peer
    1`); the third failed every scenario, and in `refusals` only on the lurker and the refused bot. In the scenarios
    with more bots it also reaches a bot that is connected and has not sent its `Hello` yet, a peer that is not a
    player for that moment. Over ENet (`--instances 3`, `dissident_kills_the_crew`) the first leak failed on the
    comparison of each of the three bots, the remote ones compared as a prefix. After #115's review two more:
    `server/` sending peer 1's snapshot to every present peer before each peer's own failed all 6 scenarios on the
    superseded LATEST messages of every bot (before the fix all 6 passed), and over ENet on bot 1's; the relay
    forwarding the speaker's own seq failed 4 of 6 on the voice streams (`refusals` has one bot; in
    `dropped_at_the_loading_deadline` no stream is interrupted). `tests/scenarios/bots_runner_test.gd` sees each check
    of a bot in `LeakCheck` (events, subject, the three `Teammates` checks, snapshots and a second one of a tick, a
    dead player's avatar and voice, the voice invariant, an event that reached the dead and not every living peer,
    voice frames and seqs, seeds, task events, lost packets, a view with no peer, a prefix short of the last
    `MatchEnded`) and the watcher's checks fail on a planted leak. **M4-2 (#138)** planted `Snapshots.for_peer`
    sending dead avatars to the dead (the old ghost rule): `bots dissident_kills_the_crew` failed on
    `ScenarioInvariants` (`peer 2 sees dead 3 in its snapshot`), and with that check switched off on `LeakCheck`
    alone (`it decoded the avatar of dead 3 at tick 518`, for both dead bots), then passed with the plant reverted.
- **`host` and `join`** (3i): `tools\run.cmd host [--port P] [--clients N]` starts a host with its own client and,
  with `--clients`, N local clients joined to it; `tools\run.cmd join <address> [--port P]` joins one. In M3 they ran
  headless sessions that print the roster, the phase and the counters: a connectivity check between two machines, as
  #21 ran; with `--headless` they still do. Since #149 (M4-6) they open the game in windows (§4.7). The default port
  is a placeholder. Several windows on one PC
  met the D3D12 freeze of §4; Windows now renders with Vulkan (#124), which did not meet it in 10 runs on one PC.
  **Built in 3i (#103)** as `tools/run/headless_session.gd` (a `SceneTree` script under `tools/`, which may use
  everything (§1), so it composes `server/` and `client/` in one process without a new boundary; the host's own
  `ClientSession` still reads only `own_client`) and the runner's `hostjoin.py`. `--host` starts `HostSession.start`
  with `content/modes/base_mode.tres`, the transport's `max_clients` one above the mode's remote players (so the one
  too many hears `full` from `core/`, not a silent refusal by ENet), a `HostNode`, and the own `ClientSession`;
  `--local` binds 127.0.0.1, else every interface. `--join=<address>` runs a `ClientSession` over `EnetTransport` with
  the default `load_levels`. Each prints the roster, the phase and the counters from its `ClientModel`, transport and
  `HostSession` (the runner's `--clients` start after the host printed `session: hosting`), and stops cleanly on the
  runner's stop file (Ctrl+C, `--seconds`), or by itself once the runner's alive file is gone or stale (a killed
  runner). A join that ends or is stopped before `Welcome` exits 1 with its reason in words, as does a welcomed client
  that ends for anything but `host_lost`; the host exits 1 when it cannot start, its session ends for an error or its
  own client ends. The default port, 24600, is a placeholder, "not a decision". Usage: `docs/AGENT_WORKFLOW.md` §11.
  Since M4-6 (#142) its arguments are `LaunchOptions` and its end texts `EndReasons`, both in `client/app/`, which
  the game reads alike.
  Tests: `tests/unit/tools/headless_session_test.gd` (the roster line, the refusal texts, the exit codes),
  `tests/unit/client/app/launch_options_test.gd` (the arguments) and
  `tools/runner/tests/test_hostjoin.py` (the supervision, and a real host with two local clients reaching the lobby
  roster Player1 to Player3).
  Since #149 (M4-6, E20) `host` and `join` run this session with `--headless`, and by default in a shell where
  `CLAUDECODE` is set (an agent's); otherwise they open the game in windows (§4.7).

### 4.7 The game client (M4 design, #125)
Decided in the [M4 ADR](decisions/2026-10-01-m4-first-person-client.md) (Accepted): the engineer's choices E18 to E33
and the designer's D4 to D10 each took its recommendation, which this section follows (for E32 and D10 the
recommendation was (b)). It is the client
that M4-6 to M4-9 build; the core rework of vision revision 1 (M4-1 to M4-5) rewrites §3 to §9 in the issues that
change their code, and the client reads the events those issues add (the ADR's §4 lists them).

**One process, one persistent root** (E19). The main scene `client/app/game.tscn` (`application/run/main_scene`)
lives for the whole process:

| Node | What it is |
|---|---|
| `Game` | `client/app/game.gd`: the menu's choices, the sessions, the level swap, leaving and quitting, the end reasons |
| `HostNode` | on a host only: steps `HostSession` (§4.5) at `process_physics_priority` -100 |
| `SessionNode` | steps the `ClientSession` at priority -90 |
| `World` | a `Node3D`: `Level` (the lobby or the map instance), the views of stations, items and bodies, `Avatars` (a `RemotePlayerBody` per other player) and `Player` (the local `PlayerController` and its cameras) |
| `Ui` | a `CanvasLayer`: the main menu, the lobby panel, the loading screen, the HUD, the task screen, the end screen, messages |

Levels are swapped under `World`. Nothing calls `SceneTree.change_scene_to_*`: it removes the current scene at once
and frees it at the end of the frame (4.7.2), so a `HostNode` inside it would close the session (`_exit_tree`) and
every client would see `host_lost` at the first map load. There is no autoload, which `check` and every test run
would load.

**Who owns what** (E18). Hosting (the menu's Host, or `--host` after `--`) does what `tools/run/headless_session.gd`
does in M3: an `EnetTransport` with the game's kind table, `HostSession.start(mode, port, mode.max_players,
HostNode.now_usec())`, a `HostNode`, then the own `ClientSession` on `own_client`. Joining is an `EnetTransport`, a
`ClientSession` and `join(address, port)`. The mode is `content/modes/base_mode.tres`. `client/app/` is the only part
of `client/` that names `server/`, and only through `HostNode` as a narrow façade: `HostNode.host(transport, mode,
port)` builds and starts the `HostSession` and keeps it private; the game reads only `own_client`, `errors`,
`end_reason`, `ended` and a debug build's counters, and calls `close()`. A source test over every `client/` file,
`app/` included, strips comments and strings and fails on the identifiers `HostSession`, `Match`, `MatchState`,
`PeerView` and `Snapshots` (case-sensitive, word-bounded: `SnapshotBuffer` passes) and on any `.game` access, like
`net/`'s "names no `core/` class"; it is seen rejecting a planted `Snapshots.for_peer` call and `_host.game`. So the
host's own player sees only what its `ClientSession` decoded.

**One physics frame.**

| Priority | Node | What it does |
|---|---|---|
| -100 | `HostNode`, on a host | `HostSession.step` (§4.5); its messages to the own client are read in this frame |
| -90 | `SessionNode` | `ClientSession.step`: poll, decode, fold into `ClientModel`, fire the signals (a `Correction` teleports the player before it moves), advance a map load, send the `MoveClaim` due |
| -80 | `Avatars` | place every remote body at its interpolated pose, so the local push search sees this frame's capsules (`sync_to_physics` off, below) |
| 0 | `Player` | read input, move, then `set_motion` for the next claim (one physics frame, 1/60 s, old when it is sent) |
| `_process` | the views, the cameras, `Ui` | draw from `ClientModel` and the interpolated poses |

**The flow.**

| State (`ClientModel` and the session) | Screen | Level under `World` | The local player |
|---|---|---|---|
| no session | main menu: address, port, Host, Join, Quit, and why the last session ended | none | none |
| connecting, no `Welcome` yet | "Connecting to <address>", Cancel | none | none |
| Lobby, Countdown | lobby panel: the roster with ready flags, Ready, the countdown; on the host the settings and their shortfalls | the mode's `lobby_level` | walks and claims |
| Loading | loading screen: who has loaded (`PlayerLoaded`) | the map, once `map_loaded` | frozen (Loading accepts no claim) |
| Round | HUD; the task screen while Tab is held | the map | by its life (below) |
| End | end screen: black, "The <side's display name> won"; the host's Back to lobby | the map, not drawn | frozen |
| ended | main menu with the reason in words | none | none |

- **The level** follows the current phase's `PhaseSpec.level` in the client's own copy of the mode. `LOBBY`: the
  mode's `lobby_level`, loaded synchronously at `Welcome` and when a lobby phase follows a map phase (End → Lobby,
  where `ClientModel` clears the match's facts, as built). `MAP`: the scene that `ClientSession.map_loaded` hands
  over, instanced in the handler, before the session sends `LoadAck`. On the host the instancing blocks the main
  thread it shares with `HostSession`, and the next step's catch-up covers it (§4.5).
- **Placement:** `Welcome`'s spot teleports the local player on `ClientSession.welcomed`, from
  `model.spots[own_peer]` (`Welcome` fires no `corrected`), and every `Correction` (a placement, a knockdown, a
  respawn, a failed check) through `ClientSession.corrected`.
- **The lobby panel:** Ready sends `SetReady`; on the host one control per `SettingSpec` of the client's own mode (its
  display name, a whole number within its bounds, or check boxes for the banned task types) sends `ChangeSettings`
  with that setting only; the demands and shortfalls come from `SettingsChanged`. The countdown and the match clock
  show `end_tick` minus the estimated host tick (Movement, below).
- **The end screen** shows the winning side's `SideSpec.display_name` from the client's own mode and nothing else
  (§3.2: no names, no roles).
- **Leaving:** Esc opens Leave and Quit. A client's Leave calls `ClientSession.leave()`; the host's asks for a
  confirmation, then frees the `HostNode`, which closes the session (every client sees `host_lost`). Closing the
  window does the same (`SceneTree.auto_accept_quit` off, `NOTIFICATION_WM_CLOSE_REQUEST` handled).
- **Every end shows why.** On `ClientSession.ended` or `HostSession.ended`, `Game` frees the sessions, the level and
  the views and returns to the main menu with the reason in words from one table, `client/app/end_reasons.gd`, which
  `tools/run/headless_session.gd` then uses instead of its own: the refusals (`wrong_version`, `wrong_content`,
  `joins_closed`, `full`, `connect_failed`), `host_lost`, `unknown_map`, `load_failed`, `left`, the host's own ends
  (`closed`, `row_error`, `own_client_malformed`, `own_client_disconnected`) and `load_deadline`.
- **A drop at the loading deadline** (#119, E21): the Loading phase emits `Disconnecting(reason)`, `load_deadline`,
  to the dropped player right before its `DisconnectPeer`, and `ClientSession` ends with that reason. ENet's
  `peer_disconnect_later` delivers it first (§4 Transport).
- **The command line:** `--host [--local]`, `--join=<address>` and `--port=<p>` after `--` skip the menu, with the
  runner's `--stop-file` and `--alive-file`; the parser moves from `tools/run/headless_session.gd` to `client/app/`.

**Built in M4-6 (#142)**, the shell: `client/app/` holds `Game` (`game.gd`, `game.tscn`, the main scene),
`GameFlow` (the flow table above as a pure class: the screen and the level per session state and phase, read from
the client's own `PhaseSpec`: a lobby level shows the lobby panel, a phase that accepts `LoadAck` the loading screen,
one that accepts `ReturnToLobby` or a match with a winner the end screen, any other map phase the round),
`SessionNode` (-90), `LaunchOptions` (the command line, which `headless_session.gd` also reads) and `EndReasons`
(the reasons in words; it writes the host's own reasons as ids, since `client/` may not name `HostSession`, and a
test pins them to `server/`'s). `client/ui/` holds the screens, built in code under `GameUi` (the `Ui` layer):
`MainMenu`, `ConnectingScreen`, `LobbyPanel`, `LoadingScreen`, `EndScreen` and `EscMenu`. `client/world/avatar_views.gd`
(`Avatars`, -80) shows a `RemotePlayerBody` per other player at the newest snapshot's position, which M4-7 replaces
with `SnapshotBuffer`'s poses. What the build pinned:
- `HostNode` is the façade: `HostNode.host(transport, mode, port)` (and a clock for tests), `is_running()`,
  `own_client`, `errors`, `end_reason`, `ended`, `counters()` (debug builds only), `skip_replay()` and `close()`; the
  session is private. The source test also fails on a path into `server/` (a preload; `app/` may name
  `host_node.gd`) and on `._session`, HostNode's private field.
- The countdown shows `end_tick` minus the newest snapshot's tick, M4-7's estimate's stand-in; the local player stands
  still (no physics step) outside the lobby and the round, and claims only where `Welcome` and each `Correction` put
  it until M4-7 sends its motion.
- The mouse is freed whenever a screen other than the round shows (`GameFlow.frees_pointer`); loading and the end
  read no device input, and under the Esc menu the held keys are cleared. Welcome and each `Correction` place the
  player through `PlayerController.teleport()`.
- Every end goes through one function: the `HostNode` leaves the tree (closing the session), the client leaves, the
  level, the views and the player are freed, and the menu says "The last session ended: <words>". The host's Leave
  and Quit, and closing the host's window, ask first (`EscMenu`); a client's Leave does not.
- A `Range` emits `value_changed` only inside the tree; the lobby panel's controls send one `ChangeSettings` with
  that setting only and are refreshed from `SettingsChanged` without a signal.
- Tests: `tests/unit/client/app/` (`GameFlow`, `LaunchOptions`, `EndReasons`, and E18's source test, seen failing
  on a planted `_host._session.game` in `game.gd` and a `HostNode` named in `client/ui/`),
  `tests/unit/client/ui/screens_test.gd`, and `tests/integration/client/app/game_loop_test.gd`: three `Game` roots
  over a `LoopbackHub` on a simulated clock through the lobby, the host's setting, Ready, the countdown, loading, the
  round, time up, the end screen and back, a client's Leave and the host's close (about 5 s). The screens' `shot`s:
  `client/dev/<screen>_preview.tscn` (`screen_preview.gd`, a fake `ClientModel`).
- The runner's windows for `host` and `join` (E20) came with #149, the rest of M4-6: below.

**Movement on the network.**
- **Claims:** every physics step the controller calls `set_motion` (its position and velocity; as the facing, the
  camera's 3D look vector, at most 89° up or down; whether it sprints, gives movement input and stands on the floor)
  and `count_jump` at a jump; `ClientSession` sends one claim per 20 Hz client tick (§4.6). The facing's pitch needs
  no wire or `core/` change (E22): `Strike.horizontal`, `Swung` and `PutDownInFront` flatten it, and `MovementRule`
  only requires it finite; the snapshot's avatar then carries it, for remote heads and the spectate camera. Snapshots
  stay at 20 Hz, since the spectate camera is built from them. A relayed facing can be degenerate even in honest play
  (a bot falling straight down claims (0, -1, 0)): `MovementRule` stores a unit facing, keeps the last one when a
  claim's has no direction and clamps the pitch to ±89° (built in M4-2, §7.1), and every camera, head or basis the client builds from a
  remote facing still guards against a zero or vertical vector (the M4 ADR's §3, Host trust).
- **Numbers:** the controller's speeds, jump height, capsule, eye and step height, stamina and crawl speed come from
  the client's own copy of the mode's `PlayerRules` when its session starts (the content hash makes it the host's);
  `client/player/player_tuning.tres` keeps only client feel (the push factors, the view's easing). Prevents: a walk
  speed changed in `base_mode.tres` but not in `player_tuning.tres`, and every claim corrected.
- **Stamina** (E24): `PredictedStamina`, the rule `LocalStamina` holds today (the client's only copy of
  `StaminaLedger`'s), predicts between `SelfStatus` updates and takes each one's numbers as it arrives; the HUD shows
  the prediction, and sprint and jump are gated by it.
- **Remote players** (E23): `SnapshotBuffer` (pure, unit-tested) keeps the newest snapshots by host tick, estimates
  the host tick from a sliding window of arrivals (not an all-time maximum, §7's lesson), and gives each remote
  player's position and facing, interpolated linearly, and its newest velocity, used only to pick an animation, so a
  claimed velocity never moves a body on another screen, at the estimate minus a delay: one tick plus the jitter seen
  over the window, from 100 ms to 250 ms (placeholders, "not a decision"). Past the newest snapshot a player holds
  still (no extrapolation); a placement or a respawn snaps. The bodies stay `AnimatableBody3D` capsules on the living
  layer, with `sync_to_physics` off: they are teleported, not animated platforms, and with it on (the default) a
  transform set in `_physics_process` is applied as kinematic motion during the physics step, so the local push
  search at priority 0 would still see the previous frame's capsules. M4-7's two-client push test asserts that the
  push search sees the pose set at -80 in the same frame.
- **The crawl** (M4-9): a downed controller moves at the crawl speed, with no sprint and no jump, up the step height,
  colliding with the level only and pushing nobody; it keeps the standing capsule for collision (the host's floor
  checks use it), and only its mesh lies down. Physics layer 3 becomes `downed` (`PhysicsLayers`), which no push
  search looks at: the downed collide with no player.

**The revision in 3D.**
- **The life fold** (E25): `ClientModel` keeps each player's life from the public events (`KnockedDown` downed,
  `Revived` living, `Died` dead with a body, `Respawned` living with the body removed, `PlayerLeft` gone with any
  body; everyone living at `RoundStarted` and in the lobby). `life_of(peer)` (built in M4-2 with the knockdown,
  the death and the leave; `is_alive()` now reads it, no longer "has no body", which would keep a respawned player
  dead). `ClientSession` claims while its own copy of the phase accepts
  `MoveClaim` from its life, and never while dead. Each fold lands in the core issue that adds its event, because the
  bots are `ClientSession`s.
- **The own player**, by life:

  | Life | Controller | Camera | Inputs | HUD |
  |---|---|---|---|---|
  | Living | walks, sprints, jumps, pushes (§7.1) | first person, the hand item in view | all (the ADR's controls) | health, stamina, hand, belt, a package's destination, task progress, clock, own role, invulnerability |
  | Downed | crawls, keeps its items; holds still and claims no displacement from a `RaiseStarted` naming it until `RaiseStopped` or `Revived` (the host corrects any, answer 8) | third person above the body | crawl, look, give up | the knockdown countdown (paused while raised), who raises them |
  | Dead | off: no avatar, no claims | the spectate camera | next and previous target | the respawn countdown, whom they watch; nothing of the target's |

- **The downed camera** (answer 9 (a)): a `SpringArm3D` whose pivot is on the body at the mode's standing eye height
  (`PlayerRules.eye_height_m`), pointing back along the look, never above its pivot (the arm's pitch is clamped to
  level or lower), with `collision_mask` the world layer and a small sphere `shape`, so it stops before a wall rather
  than looking through it. Its length is a placeholder (2 m, "not a decision"). The arm alone would still see past
  the end of a short wall the body lies against, more than standing at the body would (vision revision 1): so while
  this camera is in use (the own player downed, or a spectator watching a downed target) every remote avatar, item
  and body view with no line of sight from the pivot is hidden, one ray per object per physics frame against the
  world layer; the level stays drawn, since it is public.
- **Countdowns** (V13) follow from public events and the mode's numbers: the knockdown's from `KnockedDown` of the
  own player, paused from `RaiseStarted` to `RaiseStopped` or `Revived`; the respawn's from `Died`; a raise's progress
  from `RaiseStarted`, for the raiser and the raised. An event's host tick is `SnapshotBuffer`'s estimated host tick
  at the moment the event arrives (the estimate the clock already uses). Not "the first snapshot after it": events
  travel RELIABLE and snapshots LATEST, ENet orders nothing across channels, and a lost and resent `KnockedDown`
  arrives after several later snapshots, so that rule would start the countdown late by the resend delay. With the
  estimate a resent event is late by the same delay, and an on-time one is off by the estimate's error; both are
  display-only, since the host keeps every deadline.
- **Spectating** (V1, V9, answer 6): the camera is built from `ClientModel` only, with the same interpolated poses as
  the avatars: the target's eye and facing (yaw and pitch) for a living target, the downed camera above a downed
  target's body. The first target is a random living player other than the own one, drawn with the client's own
  `RandomNumberGenerator` (the purpose `spectate`: seeded from the system's entropy in the game, by the test in a
  test), else a random downed one, else the camera stays above the own body. Next and previous cycle through the
  living and downed players in peer-id order; when the target goes down, dies or leaves, the camera draws a new first
  target. Nothing about the target is sent, and the client has no HUD, health, stamina, role or private event of it.
  The dead keep receiving every snapshot (none holds a dead player's avatar): the camera is built from them.
- **What the dead hear** (V11): no voice (the host routes none); the world's sounds where the camera is (Godot's
  listener follows the current camera, so positional sounds play around the target); lift music from an
  `AudioStreamPlayer` that only the dead player's client plays. M4's world sounds are placeholders for `Swung`,
  `ItemPickedUp` and `ItemPlaced` at their positions.
- **A hearing range** (E33 (a)): a world sound plays only within about 12 m of the listener's camera (a placeholder,
  "not a decision"), for the living, the downed and the dead alike: a pure sound chooser (unit-tested) drops an event
  from farther away, and each `AudioStreamPlayer3D` sets `max_distance`. The events reach everyone with a position,
  so an uncut sound would tell every client through the walls where a package was just put down. Occlusion is M5's.
- **Respawn:** `Respawned` of the own player and its `Correction` put the controller at the marker in first person
  again; the spectate camera and the lift music stop. After `Revived` the controller stands up where it lay, in first
  person; whether a revive also sends a `Correction` is M4-4's to decide, and the client adopts one like any other.
- **Others:** a `RemotePlayerBody` shows its facing (a head that turns and nods), the hand item at a hand attach
  point, the belt item at a belt attach point, a two-handed package held in front, the downed pose and its layer, and
  invulnerability (the avatar's flag). A body (`Died`) is a view of its own, removed at `Respawned` or `PlayerLeft`.
- **Hands:** the own hand item is drawn in the first-person view and the belt item on the HUD. Every item is drawn
  from `ClientModel`'s fold of the item events: on the ground where it lies, or at its holder's hand or belt. The own
  slots and the own invulnerability come from events only, since the own avatar never arrives.
- **Interactions:** the camera's ray picks the candidate, the first item or downed player along it in the client's
  own level; the hint and the key then apply only if the mode's `InReach` of `PickUp` holds, measured as the host
  measures it (2 m from the feet, not along the ray from the eye 1.6 m higher), so a crate-top item the host would
  refuse gets no hint and a floor item it would accept does. M4-8's target-choice test checks both against a fixture
  world. The keys send `PickUp(item)`,
  `Raise(target)` and `StopRaise()`, `PutDown(facing)`, `Use(facing)`, `Swap()` and `GiveUp()`; the host checks each
  again (§7.1), and the client predicts nothing of an action's outcome.
- **The HUD:** health and stamina (`SelfStatus`, the stamina predicted), the hand and belt items by their kinds'
  display names, a package's destination (a swatch of its circle's colour and a marker over that circle, drawn
  through walls too, since circles are fixed, public places: D10 (b)), the shared progress (`TaskProgress`), the match
  clock, the own role by its display name and, for a dissident, its teammates (`Teammates`), invulnerability, and
  what the crosshair would do. **The task screen** (Tab), for the living, the downed and the dead: each task of the
  match (`TaskState`) with its type's display name and description from the client's own mode, and its shared
  progress; no map. **A circle** is a translucent cylinder of its station kind's radius and height in
  `StationPlaced`'s colour, dimmed once `PackageDelivered` names it.

**What the client renders** follows the ADR's checklist (its §3), which `netcode-security-reviewer` checks on every
M4 client PR: only the own model, the interpolated poses and the own mode; spectating from the public snapshot only;
the downed camera at or below eye height, never through the level, and showing nothing out of sight of the body's
eye; no screen with an item's or a player's
position, and no name or marker over a player or an item drawn through walls (`no_depth_test` is for the fixed,
public circles only, the destination marker of D10 (b) included); a role named only on its own player's screen
(a dissident's teammates on theirs); no hit confirmation for
the attacker beyond the accepted exceptions; hidden information in debug builds only (the debug overlay, F3).
World sounds play within the hearing range only (E33).

**What stays headless:** `HostSession`, `ClientSession`, `ClientModel`, `DecodedView`, the bots runner and the leak
test, `host` and `join` with `--headless`, and every GdUnit4 suite. A bot loads no scene.

**`host` and `join` with windows** (E20): `tools\run.cmd host [--clients N]` and `join <address>` run the game scene
in windows, tiled on one PC with `--position`, with Vulkan as everywhere on Windows; `--headless` runs the M3
session of §4.6. In a shell where `CLAUDECODE` is set (an agent's) the default stays headless, so an unattended run
never opens a window on a human's screen.

**Built in #149 (M4-6)** in `tools/runner/hostjoin.py`: each window is `client/app/game.tscn` with the arguments of
`LaunchOptions` after `--` (`--host [--local]` or `--join=<address>`, `--port=`, the runner's stop and alive files),
so it skips the menu, and stops cleanly for the runner as the headless session does. The console exe (`GODOT_BIN`)
opens them, since the runner reads each process's lines (the host's `session: hosting` starts the clients; a host
that prints `session: cannot host` stays at its menu and gets none). A host and its `--clients` are tiled in a grid
over the primary screen's work area (`--position` and `--resolution`, 16:9, below each title bar and inside its
frame; a lone window goes where the system puts it); a windowed host on every interface prints what to type on
another PC. `--windows` opens windows where `CLAUDECODE` is set; agents never pass it. They run until Ctrl+C,
`--seconds` or every window closed. A window never welcomed into a lobby fails the run with the game's `cannot host`
or `ended:` line, since the game exits 0 from its menu.
Tests: `tools/runner/tests/test_hostjoin.py` builds the command lines without starting Godot (the defaults, the
tiles, `--headless`), and `verify`'s `game` step runs `game.tscn` headless through that command line: a host
(`--local --no-replay`) and one client over ENet on a free port of 127.0.0.1, both welcomed into the lobby, then
both stopped through the stop file with exit 0 and no engine error line (about 5 s).

**Tests.** The logic lives outside scenes where it can (the flow, the launch options, the end reasons,
`SnapshotBuffer`, `PredictedStamina`, the countdowns, the spectate targets, the HUD's texts), unit-tested headless in
`tests/unit/client/`. `tests/integration/client/` drives physics headless: the real `PlayerController` walking,
sprinting, jumping and climbing steps through a `ClientSession` over a `LoopbackHub` to a `HostSession` on a fixture
level is corrected 0 times; the downed camera against a fixture wall never rises above eye height or passes the wall,
and an item visible from the arm's end but not from the pivot is hidden;
the two-client push runs over the loopback with the interpolation delay. Input and UI cannot run headless: every
screen and view gets a `shot` of its preview scene in `client/dev/`, and the playtests of the ADR's §6 check the
rest.

## 5. Per-peer information filtering

- Each outgoing message is built for one recipient from what that peer is entitled to know.
- The information-leak test (bot harness, M3) asserts that no client ever receives anything it is not entitled to,
  connected peers that are not players included: they receive at most a `Rejected`, none unless they sent a `Hello`
  (§4.6's lurker). It is the most important test in the project. Once it exists, prove it: inject a leak, see it
  fail, revert.
- `tools\run.cmd bots` (M3) starts a headless host and N headless bot clients that play a full scripted match, then
  asserts: the match ends, the winner is correct, no errors are logged, and no client received information it was
  not entitled to. It joins `verify` and CI. `host` and `join` launch a local host and clients for the humans'
  playtests. Their design, and the leak test's exact comparisons: §4.6.

**How entitlement is expressed** (#32; [ADR](decisions/2026-09-29-match-loop-intents-events-and-entitlement.md)):
- **Per event type.** Each event class declares its audience as a rule in `core/`: *everyone*, *only(peer)* (a present
  player), *role(r)*, *life(state)* (no MVP event uses it), *server* (a directive, §4.2), or *sender(peer)*, which only
  `Rejected` uses, because only it may reach a connected peer that is not a player yet (the engineer's answer on #49).
  The rule is evaluated when the event is emitted, against the state after the command. An event has one audience: when
  parts of a fact have different audiences, `core/` emits separate events (a hit: public `Swung`, private `Damaged`).
- **Per entity for snapshots.** Every tick `core/` builds each peer's snapshot from visibility rules per entity: a
  living or downed player's avatar (position, velocity, facing, the flag `downed`, held item) reaches every player of
  the match, the dead included, whose spectate camera is built from it (§4.7); a dead player has no avatar, so no
  snapshot holds one (M4-2, #138); bodies and items reach everyone. Nobody gets their own avatar: it moves client-side, and `Correction` settles disagreement. Private numbers are never avatar
  fields; they travel in `SelfStatus`.
- **`core/` says who is entitled; `server/` delivers.** The rule is game logic, like voice routing (§6). `server/`
  asks `core/` for each event's recipients and builds one message per recipient, *everyone* events included: it sends
  them to each player in turn, never to the transport's broadcast target, which would also reach a peer that is not
  a player (no accepted `Hello` yet, or a straggler about to be disconnected). It never adds a recipient or a field
  (`core/CLAUDE.md` and `server/CLAUDE.md` say so since 2a).
- **Never leaves the host:** seeds and RNG state; another player's role (the end screen shows none either), health,
  stamina and damage; whom a dead player watches (it never leaves the dead player's client, §4.7). Tasks are shared (#79): what a client learns of them is
  all public (`StationPlaced`, `ItemSpawned` with a package's circle and colour, `PackageDelivered`, `TaskProgress`); no
  task has an owner, and a subtask's detail stays in `subtask_done` (internal to the task type, not secret). No event
  names a killer; a player who watches the swings and positions (both public by the rules) may still work it out.
- **Widening** follows from evaluating audiences at emission. A knockdown and a death widen nothing: the downed are
  public, a dead player gets the same public snapshots as everyone (minus the dead), and the dead learn no roles and
  no event that a living peer present then does not get (the leak test checks it, §4.6; M4-2 tests the snapshots in
  `tests/unit/life/life_rules_test.gd`). End widens nothing: `MatchEnded` names only the winning
  side, and each player knows from its own role whether it won. A later mode that reveals roles would add an event with
  its own audience. A joiner's `Welcome` holds public facts only.
- **Knowledge never shrinks.** A peer keeps what it was sent. What a dead player saw while spectating, all of it
  public, is fair game after the respawn (vision revision 1, V1): nothing is narrowed then.
- **Projection.** `Match` records the recipients of every event it emits, and per tick each peer's snapshot and the
  voice routing (who hears whom). `Match.view_of(peer)` returns that peer's events in order, its snapshot for every
  tick, and the speakers it may hear per tick: everything an honest client of that peer can know. The per-tick
  snapshots and speakers are recorded only with `Match.keep_history` on (off by default: about 1 GiB for 10 players
  over 10 minutes); the tests and the leak test turn it on, a real host does not. The M3 leak test
  compares what each bot actually decoded (voice frames included) with `view_of` of its peer; anything received that
  `view_of` does not hold is a leak (§4.6: the events exactly, the snapshots' avatars and the voice frames as
  subsets).
- **Invariants that do not trust the declarations.** A wrong audience (say `Teammates` declared *everyone*) would
  pass the comparison above, because both sides read the same declaration. So unit tests and the leak test also
  assert facts written independently of them: for the whole session, a crew member knows one role, its own, and a
  dissident knows the dissidents' roles only; no snapshot holds a dead player's avatar; the voice invariant (§6): no
  peer gets a downed or dead speaker's voice frame, a downed peer gets only the living's and a dead peer none;
  nothing reaches only the dead: every event a dead peer gets is for it alone or also reaches every living peer
  present then (`ScenarioInvariants` and `LeakCheck`, M4-2, each seen failing on a plant in `tests/scenarios/` and
  the first on `bots`, §4.6); nobody gets another player's health, stamina or damage; every player receives the same
  task events; no message holds a seed.

Rejected ways of expressing it (per field, per content part, filtering in `server/`): the ADR.

## 6. Voice pipeline

capture → encode (Opus) → routing decision per speaker and listener (`core/` rules, applied by the host's
`server/`) → listener → decode → jitter buffer → `AudioStreamPlayer3D` on the speaker's avatar.
- Routing inputs: distance, walls (occlusion), life (the voice invariant below), items such as radios, role
  abilities. Dead chat and meetings, in the brief, are gone (vision revision 1).
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
  data names each phase's rule (§3.1), so a new mode's rule is one more rule, not a change to the loop.

  | Phase | Who hears whom | |---|---| | Lobby, Countdown | every pair within the voice radius | | Loading | nobody: the
  old scene's positions are gone, and the phase lasts seconds | | Round | the living hear the living within the voice
  radius; a downed player hears the living within it, measured from where it lies; nobody hears the downed or the dead,
  and the dead hear nobody | | End | nobody: the game is frozen |

  A player who left hears nobody and is heard by nobody.
- **The voice invariant** (vision revision 1; built in M4-1, #137): nobody hears a downed or dead player, under
  any voice rule, and a dead player hears nobody. `VoiceRule.speakers_of` drops every speaker who is not living
  and gives a dead listener nobody before it asks the phase's rule, so no mode's data can route their voice; it
  replaces 2i's "the living never hear a ghost". Tests: `tests/unit/content/voice_rule_test.gd`, under
  `FixtureEveryoneHears`, a rule that lets everyone hear everyone; the leak test's checks (§5).
- **Built in 2i** (#65, `core/voice/`): `SilentVoice`, `ProximityVoice` and `RoundVoice` (§9.4); the base mode's
  data names one per phase with the numbers of §9.5. A distance is between the two players' last accepted
  positions (§7.1), in 3D, and a radius includes its edge, as the M1 spike's routing measured them (#15,
  `distance_to(...) <= cutoff`, which the engineer listened to and accepted); 3D also matches the listener's fade.
  A horizontal radius (a player on the floor above heard like one beside) stays a possible later change. M4-1
  removed `RoundVoice`'s ghost radii: it keeps `living_m`. Tests: `tests/unit/voice/`.
- *Open (M5):* occlusion, radios, push-to-talk or voice activity, echo cancellation, and
  lowering the device latency (options in the ADR).

## 7. Movement

Client-side movement for the local player; the host checks speed and teleports; remote players are interpolated.
*Open (M4):* snapshot rate, tolerances, correction policy. The core tick rate is set in §3.3; what the host checks, in
§7.1. The snapshot's wire format (avatars only) is §4.3; M3 sends one every tick in the phases that send snapshots,
a placeholder rate that M4 may reduce.
The M4 design (§4.7, E22, E23) keeps 20 Hz snapshots, draws remote players behind an estimated host tick with an
adaptive delay, and leaves the tolerances to #76 and the M4 playtests.

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
  living's walk and sprint speeds times a factor in `PlayerTuning`. `StaminaSource` never refuses a ghost and records
  nothing for it. There is no flight (the engineer's correction of 2026-09-30, #46). This is the client as built; the
  host no longer accepts it: since M4-2 (#138) a downed player crawls (§7.1 The crawl), and M4-9 replaces the
  client's ghost mode with the crawl.
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
  when physics runs on a separate thread, so the host ticks `core/` from its physics step; whether a new space answers
  queries before its first step was probed in 3c (#99): it does (§4.5).
- **Positions.** `core/` keeps each player's last accepted `MoveClaim` (position, velocity, facing, on floor). Every
  range rule (reach, hit zone, circle, voice) reads those, never a position inside another intent. Prevents: a client
  claiming to stand next to what it wants to grab.
- **Stamina** belongs to `core/` (only the living sprint; the downed regenerate, see The crawl below). The client predicts its own from the published
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
  the client's physics at 60 Hz, so a landing and a jump can fall within one claim) and stamina covers the cost; a
  downed player's new jump is always corrected (The crawl below). Until the next landing
  the height above the floor is bounded by the jump height; a rise without an accepted jump beyond step height is
  corrected. Prevents: free or endless jumps, and flying. A claim carries `jumps`, the client's count of jumps since
  it adopted the epoch (3e, E2; §4.3): a rise d ≥ 1 over the last accepted claim's count in the epoch is one jump,
  which stamina must cover d times; a count that falls within an epoch is corrected; the count restarts at 0 with
  every new epoch. So a jump in a claim that the LATEST lane merged away or lost still counts in the next one.
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
    for the living plus `sprint_speed` (Pushing apart below; proposed for M4, used provisionally); for the downed the
    crawl speed alone, with no sprint and no push allowance (M4-2); plus `DISTANCE_SLACK_M` (0.05 m) per claim.
  - Height, from the last landing's floor (a claim on the floor with a `WorldQuery` floor within step height plus
    `STEP_CLEARANCE` below its feet, which a ledge crossing needs; `FLOOR_PROBE_M` above the feet is where the query
    starts): after an accepted jump, the jump height
    plus `capsule_radius * (1 - cos 45°) + STEP_CLEARANCE` (about 0.127 m, §7) from the take-off, the higher of its
    floor and its feet; without one, the step height plus `STEP_CLEARANCE` (0.01 m) plus the claim's horizontal
    travel times tan 45° (slopes and stairs up to the client's `floor_max_angle`). Positions are 32-bit floats:
    `HEIGHT_SLACK_M` (1 mm) on top. Falling is not bounded.
  - Cost: two `WorldQuery.stand_floor_below` calls per jump and one per claim on the floor, each recorded in the
    command log. The movement rule's floor (`stand_floor_below`, 3e) looks below the whole capsule footprint, not one
    ray at the origin: on a ledge's edge a ray from the feet misses the ledge, and a jump from there would be
    corrected (§4.5, E10). The item rules' eye (`Items.eye_of`) stands on the same floor; an item's or a body's
    floor is one ray (`floor_below`).
  - The facing (M4-2, #138; the M4 ADR §3, Host trust): it is a claim relayed to everyone in the snapshots, and an
    honest one can be degenerate (a bot falling straight down claims (0, -1, 0); a standing client may claim zero).
    An accepted claim stores a unit facing (`MovementRule.stored_facing`): a claim with no direction keeps the last
    one, one straight up or down keeps the last yaw, and the pitch is clamped to ±89° (`MAX_PITCH_DEG`). Tests:
    `tests/unit/movement/movement_rule_test.gd`.
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
  - A ghost (the client's downed until M4-9) runs no search, and its layer is not searched: the downed push nobody
    and nobody pushes them.

  Speed: a pushed player moves faster than its own walk or sprint without cheating (walking sideways at 4.5 m/s
  while a sprinter pushes it at 3.5 m/s is about 5.7 m/s, and two pushers add up). `PlayerController._push_apart`
  caps the push-out at `sprint_speed`, so the host's speed bound for a living player is its state's speed plus
  `sprint_speed` (proposed for M4, not decided; a test pins the cap). The downed get no allowance: they are never
  pushed.

  Prevents: two clients that see each other late snapping each other back and forth, and a player blocking a doorway.
  Accepted: a modified client can walk through players. Latency: the pusher sees the pushed player's capsule a round
  trip late (its own motion reaches the other client, which moves, and that motion comes back: about 0.2 s with
  100 ms interpolation on each side). Over a network the overlap limit, not the push speed factor, sets how fast a
  straight push goes: at most `push_max_overlap` per round trip, 1 m/s at 0.2 s instead of 2.25 m/s. The
  two-client tests (`player_controller_push_test.gd`) run with that delay. *Open (M4):* the playtest over a network
  decides whether that is enough; the options are a larger limit (deeper visible overlap) or drawing the pushed
  capsule moved ahead on the pusher's client (display only).
- **The crawl** (vision revision 1; M4-2, #138, replacing the ghosts' movement). A downed player's claims get the
  movement checks with the crawl's bounds: the allowed travel is `PlayerRules.crawl_speed_mps` times the ticks covered
  (plus the slack), with no sprint ticks and no push allowance; a new jump is corrected; the rise is the step height
  (plus `STEP_CLEARANCE` and the slope allowance) above the last landing. The downed are never in the sprint state and
  spend no stamina; it regenerates as usual. They collide with the level client-side and with no player. `PickUp`,
  `PutDown` and `Use` from the downed are rejected (`not_accepted`: Round accepts them from the living only); the dead
  send no intent that is accepted (§3.1). The knockdown places the downed player where it stood, on the floor below
  its last accepted position, with a new epoch and a `Correction` (`LifeRules.knock_down`), even on the floor. The
  movement rule treats that like a placement: walking claims in flight are dropped as stale instead of failing the
  crawl check, and its first claim as downed starts a new client-tick baseline there. A death sends no `Correction`:
  the dead claim nothing. Tests: `tests/unit/movement/`, `tests/unit/stamina/stamina_ledger_test.gd`,
  `tests/unit/life/life_rules_test.gd`.
- **Walls.** The MVP host does not check movement through walls (nobody asked for cheat protection). It does check
  walls for hits, pick-ups and placement, because there an honest client would otherwise stab or grab through a thin
  wall.
- **Hits** (the knife's `Use`: `Strike`, §9.4). The host picks the targets: every living player other than the
  attacker (strikes skip the downed and the dead) whose capsule has a point within
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
- **Drops.** An item dropped at a death or a leave, a downed player, and a body, come to rest on the floor below the
  player's last position (through `WorldQuery`), never in mid-air. `Items.drop_held` (2e, #61) drops the item, asking the floor
  from 5 cm above the feet so a ray that starts on the floor still finds it; a level with no floor there is a
  level bug: the item rests at that position and the match logs an error. Where a knocked-down player lies
  (`LifeRules.knock_down`) and its body at the death (`LifeRules.die`; M4-2) are found the same way, with the same
  fallback, and at the death the item then drops at the body. Nothing drops at a knockdown.
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
only, so the designer can test a mechanic alone. A debug command reaches `core/` as a command that `server/`
originates (`ForceRole`, 2j); on the wire (M3 design) it is a kind that only a debug build's table has and only the
host's own client may send (§4.3, E17).

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
    **bodies** (peer → rest position, written by `LifeRules.die` before `player_died`, from the death until the
    respawn (M4-3) or the leave; M4-2); two tables keyed by names from the data,
    **cooldowns** (the tick at which a player last paid a key, such as `hit`) and **counters** (an integer per player
    and key, such as uses left, #34); and a **per-part state** table, one `RefCounted` per key that a part class
    declares, for state a new part class needs that fits none of the above. So a new part adds state without a new
    field in `MatchState`. `ResetMatch` clears all of it.
  - **The phase object.** A `PhaseSpec` names a phase class (a script) and its settings. On each entry into the
    phase `Match` creates a fresh object of that class (`RefCounted`, not a `Resource`) and drops it on exit. It holds
    what lives as long as the phase: the countdown's end tick, Loading's acks and deadline. A
    result that must outlive the phase leaves as the outcome's argument (a tally, to a transition action) or goes
    into `MatchState`.
  - **Nothing else.** A part that needs state and fits neither is a design error to raise in its PR.
- **`core/` loads no files.** `server/` (and the tests) load the game mode, read each level's markers into a
  `LevelLayout` (§9.6), and hand both to `Match`. The command log records the layouts and the mode's hash, so a
  replay needs no level (§3.3).
- **Checked on load**, in two parts. `Match` refuses a mode with errors, listing them all.
  - *The mode alone:* a phase, outcome, intent, setting, role, side or item kind that a part names but the mode does
    not declare; an outcome a phase can report without a row (§3.1); an accepted intent that neither the phase class
    nor any rule handles; two rules on one trigger in one owner; a number outside its part's bounds; an id outside the
    wire's alphabet (3e, #97; §4.3, E5): every `id`, `side`, `spawn_tag` and `tag` a part holds, and every
    condition's rejection reason, is 1 to 32 characters of `a-z`, `0-9` and `_` (D1 (a), the designer's answer on
    #96). A unit test
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
| `player_died` | a downed player dies (its knockdown ran out, M4-2), before the held item drops | the player, the body position; no killer, as no event names one (§4.2). A knockdown raises no fact |
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
  in it. The check after every fact orders the effects of one command (§3.4): the last crew member leaving raises
  `player_left` before its package drops into its circle, so "no crew present" is reported first, while a death's
  `player_died` meets no win condition and the dropped package then delivers. The check at the step's end catches a
  change that raised no fact.
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
  `rng(purpose)`, `setting(id)` and `error`. Names: `Intents` (with `Intents.FIELDS`, each intent's fields, 3e),
  `Facts`, `RejectReasons`.
- Events are `MatchEvent` subclasses in `core/events/`, each with its `audience()` (`Audience`: everyone, only,
  role, life, server, and sender for `Rejected`, 2b) and a `const AUDIENCE_KIND`, from which `ModeCheck` warns
  about role-owned public events.
- `Phase` (handled intents, outcomes, settings check, end tick, enter, exit, tick, intents, peers connecting and
  leaving); 2b (#58) filled the base mode's Lobby, Countdown, Loading and End classes, with `JoinRules` (joins,
  leaves, the ready flag) and `FitCheck` (the fit check) beside them in `core/match/phases/`, and
  `MatchState.newcomers` for the connected peers not yet players and `MatchState.joins` for the `Player<n>` names
  (§3.5); `MovementRule` (`core/movement/`) takes `MoveClaim`s, with the checks of §7.1 since 2d.
- `MatchState`: players (`PlayerState`, life ALIVE, DOWNED, DEAD or LEFT, and `life_deadline`, M4-2), settings and
  `id_sets` (§9.1), map, items (`ItemState`: ground, hand or locked), tasks (`MatchTask`: its task type and `TaskState`,
  no owner), stations, bodies, the cooldown and counter tables, `part_state`, the clock, the winner, `RngStreams`, and
  `reset_match` for `ResetMatch`.
- server/ and the tests drive `Match`: `Match.new(mode, seed, world, layouts, content_hash)` (the host's content
  hash, 3e), `start`, then per tick `apply` for each command and `tick`; `take_outbox` (events with recipients),
  `snapshot_for`, `speakers_for`, `view_of`, `row_error_count` (3e, §4.5), `command_log` and `Match.replay` (a
  replay that diverged from the recorded `WorldQuery` answers says so in `diagnostics`).
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
- **Life** (`core/life/life_rules.gd`, 2g #63, reworked in M4-2 #138) is the one place that lowers health or changes
  the life state in a round: `LifeRules.damage` (`Damaged` to the victim, its `SelfStatus` touched; at 0 health
  `knock_down`), `knock_down` (life downed on the floor below the last accepted position, with a new epoch and
  `life_deadline` the knockdown time later; then `KnockedDown` (everyone) and `Correction` (the downed player);
  nothing drops, no body, no fact), `die` (from downed: the body on the floor below into `MatchState.bodies`, life
  dead; then `Died` (everyone), `player_died`, and only then `Items.place` at the body with `Items.DEATH`; no
  `Correction`) and `leave` (life left, a dead player's body removed; `PlayerLeft`, `player_left`, then the drop with
  `Items.LEAVE`). `LifeTicks` (`core/life/life_ticks.gd`), a tick system, calls `die` for each downed player whose
  `life_deadline` has come, in peer-id order; M4-3 adds the respawn and M4-4 the raise's pause to it. A later weapon
  or a trap calls `damage`; the class is `LifeRules`, not `Life`, which would shadow `PlayerState.Life`.
- Two class names differ from their kind: `GameRole` and `RuleEffect` (a global `Role` or `Effect` would shadow an
  enum of `NetTransport` or GdUnit4).

| Kind | Answers | Class in `core/` | Data | MVP instances |
|---|---|---|---|---|
| Game mode | which phases, rules and settings a match has | `GameMode`, with `PhaseSpec` (its allowlist of `AcceptSpec`s), `Transition`, `SettingSpec` (a whole number or a set of task types), `SideSpec`, `PlayerRules` | `content/modes/` | the base mode |
| Phase class | what a phase does itself: its own intents, timers and outcomes | `Phase` subclasses (`RefCounted`; a fresh object per entry, §9.1) | named by a `PhaseSpec`, with its settings | Lobby, Countdown, Loading, Round, End |
| Rule | trigger → conditions → effects; an **action** is a rule on an intent, a **reaction** a rule on a fact | `Rule` | inside its owner | PickUp, PutDown, the knife's Use |
| Condition, cost | *only if*; a cost is also paid | `Condition`, `Cost` subclasses | inside a rule or a win condition | §9.4 |
| Effect, transition action | *what happens*; a transition action is an effect that a transition row runs, with no actor | `RuleEffect` subclasses | inside a rule or a row | §9.4 |
| Tick system | what runs every tick of a phase, in the phase's order | `TickSystem` subclasses | listed per phase | LifeTicks, TaskTicks |
| Voice rule | who hears whom in a phase (§6) | `VoiceRule` subclasses | one per phase | Silent, Proximity, RoundVoice |
| Role | a side, what it knows, its abilities; a display name | `GameRole`, `RoleQuota` | `content/roles/` | Crew, Dissident |
| Item kind | a thing a player can hold, and what using it does; a display name (the HUD's held item) and its spawn tag | `ItemKind` | `content/items/` | Package, Knife |
| Task type | how its one shared task is dealt and done, with its own subtasks setting; what it demands of the map | `TaskType` subclasses, each with its `TaskState` (§9.1) | `content/tasks/` | Delivery |
| Task station | a place where a task is done, placed by its task type | `StationKind` (spawn tag, radius, height, colour palette) | inside its task type | the delivery circle |
| Win condition | which side wins, and when | `WinCondition` | `content/win_conditions/` | three (§9.5) |
| Interactable | a thing in the world that a player targets with an intent | v0: an item on the ground (`PickUp`). Fixed ones (a button) and bodies come with `Interact`, v1 (§9.8) | | packages and knives on the ground |
| Spawn point | where the deal may place something | `LevelLayout` in `core/content/` (2a): the markers by tag, in level order; `server/`'s marker reader (`MarkerReader`, 2j) fills it | markers in `levels/` (§9.6) | tags `lobby_player`, `round_player`, `package`, `knife`, `circle` |
| Bot scenario | a scripted match that exercises a mechanic | `BotScenario`, its steps and targets: data only, in `core/content/scenario/`; the runners in `tests/harness/` | `content/scenarios/` | §9.7 |

- **`PhaseSpec`**: the phase id; the phase class with its settings; the intents it accepts and from whom (a newcomer,
  any player, the living, the downed, the host; §3.1); its tick systems in order; whether it checks win conditions;
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
| `InSight` | the line from the actor's eye (the floor it stands on at its last accepted position, `WorldQuery.stand_floor_below`, raised by `PlayerRules.eye_height_m`, §7.1) to just above the item's rest position is clear (`WorldQuery.line_of_sight`) | none | `blocked` | 2e (#61) |
| `HoldsItem` | the actor has an item in hand | none | `empty_hand` | 2e (#61) |
| `ActorRole` | the actor's role is one of the listed (no MVP use) | `roles` | `not_allowed`: the actor knows its own role | with the first mechanic that needs it (#34) |
| `AllSubtasksDone` | every task is done (`Tasks.all_done`): a task with no subtasks is done, and with no tasks it holds (the engineer's rule of 2026-09-30, #79) | none | (facts only) | 2h (#64, `core/win/all_subtasks_done.gd`) |
| `NoneAlive` | no player of the side is present: each has left (M4-2: the downed and the dead still count; the name stays from "no crew alive"). A player's side is its role's; a player without a role of the mode is on no side, and with no player of the side it holds (the base mode's deal always leaves at least one crew member). It reads every player's role, which is hidden, but only as a win condition, whose `won` reaches no peer (§9.2) | `side` (a side of the mode) | (facts only) | 2h (#64, `core/win/none_alive.gd`) |
| `ClockEnded` | the match clock has reached its end (`MatchState.clock_ended`, set when `Match` raises `clock_ended`); before `StartClock` there is no end | none | (facts only) | 2h (#64, `core/win/clock_ended.gd`) |
| `Cooldown` (cost) | this player never paid this key, or at least `seconds` (in host ticks, toward zero, §3.3) passed since it last did; paying records the tick in `MatchState`'s cooldown table. Per player, not per item: a second knife does not skip it | `key` (no default: the data names it), `seconds` (0 to 600; 0) | `too_soon`: its own timing | 2g (#63, `core/combat/cooldown.gd`) |
| `StaminaCost` (cost) | the actor's stamina, settled first (§7.1), is at least `amount`; paying spends it and emits `SelfStatus` (the actor, at the end of the tick) | `amount` (whole points, 0 to `PlayerRules`' stamina maximum) | `tired`: its own stamina | 2d (#60) |

**Effects in rules:**

| Part | What it does | Settings | Emits (audience); raises | Built in |
|---|---|---|---|---|
| `TakeIntoHand` | the item goes into the actor's hand; a held item is swapped: it rests where the picked-up one lay (§7.1). An item not on the ground (a rule without `ItemOnGround`) is a rule error, logged, and nothing moves; the sender gets `Rejected` (`unavailable`) | none | `ItemPickedUp` (everyone); for a swap `ItemPlaced` (swap, everyone), then `item_rested` | 2e (#61) |
| `PutDownInFront` | the held item rests `distance_m` along the horizontal facing, stopped before a wall and dropped to the floor (`WorldQuery.rest_position` from the actor's eye, taken from the floor it stands on, §7.1); a facing with no horizontal direction puts it at the feet | `distance_m` (0.3 to 3; no default: the data sets it, the base mode 1) | `ItemPlaced` (put down, everyone); `item_rested` | 2e (#61) |
| `Strike` | picks the targets as in §7.1 (living, never downed, not the attacker, within reach and half the angle, overlapping vertically, in line of sight from the eye) and damages each through the life rule (`LifeRules.damage`), in peer-id order; at 0 health a target is knocked down there (M4-2) | `angle_deg` (1 to 360), `reach_m` (0.1 to 10), `damage` (whole points, 1 to 1000); no defaults: the data sets them (the knife 30, 1.5, 50) | `Swung` (everyone), even with no target, before any damage; per target `Damaged` and `SelfStatus` (the victim). A knockdown: `KnockedDown` (everyone), `Correction` (the downed); nothing drops (M4-2) | 2g (#63, `core/combat/strike.gd`) |
| `ReportOutcome` | reports an outcome of the current phase (a button in the level, say; no MVP use) | `outcome`, `argument` | an outcome (§3.1), which reaches no peer (§9.2) | with the first mechanic that needs it; 2a builds the outcome reporting it calls |

**Transition actions** (effects that a transition row runs; the base mode's rows are in §9.5):

| Part | What it does | Settings | Emits (audience) | Built in |
|---|---|---|---|---|
| `DealRoles` | each quota in order draws its players from the present players not drawn yet, taken in peer-id order and shuffled with its RNG purpose; everyone else gets the default role. Roles forced by a debug command or a scenario (debug builds only, §8) come as data, because `core/` cannot tell a debug build: the command `ForceRole` (peer, role id; an empty id clears it), which only `server/`'s debug path (from M3 also built from peer 1's debug-kind message, §4.3 E17) or the scenario runner sends, in any phase and after the peer connected, since ENet names a peer only then; it sets `MatchState.forced_roles`, which `ResetMatch` keeps, for the deals that follow, and is in the command log like every command; a role the mode lacks is a match error and ignored. Each present peer with a forced role gets it before the draws, and a forced role counts toward its quota (the engineer's answer A on #30: `dissidents` 1 with bot 2 forced to dissident makes bot 2 the only dissident), so a quota draws its count minus the players forced to its role, never below 0; a forced role the mode lacks is a match error and ignored (2j) | `quotas` (`RoleQuota`: role, `count_setting`, `leave_at_least` (0 to 10; class default 0, the mode writes its number): the count is max(0, min(setting, N − leave_at_least)), and never more than are left), `default_role`, `rng_purpose` (`roles`) | `RoleAssigned` (that player), in peer-id order; then, per role of the mode that knows its teammates and has players, in the mode's order, `Teammates` (every player of that role); a forced role is told like a drawn one | 2c (#59); forced roles 2j (#66, `tests/unit/deal/deal_roles_test.gd`) |
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
| `LifeTicks` | tick system | each downed player whose knockdown time has run out (`PlayerState.life_deadline`) dies (`LifeRules.die`), in peer-id order; M4-3 adds the respawn, M4-4 the raise's pause | none (the knockdown time is `PlayerRules.knockdown_s`, E27) | a death's `Died` (everyone), then the dropped item's `ItemPlaced` (death, everyone); the facts `player_died`, `item_rested` | M4-2 (#138, `core/life/life_ticks.gd`) |
| `TaskTicks` | tick system | runs the tick of each task type that has one, in the mode's order (none in the MVP; #36) | none | the task types' events | 2f (#62) |
| `Lobby` | phase class | allows joins; `Hello` (the join, §3.5), `SetReady`, `ChangeSettings`; leaves (§3.5); reports `all_ready` (§3.2) after a `SetReady`, a settings change (numbers and the bans of task types, #79), a leave and on entry. Rejects (§4.1): `wrong_version`, `full`, `bad_args`, `unchanged`, `unknown_setting`, `out_of_bounds` (a bound, an unknown task type id, or a row action's `settings_problem`), `unknown_map` | none | `Welcome` (the joiner); `PlayerJoined`, `PlayerLeft`, `ReadyChanged`, `SettingsChanged` (everyone); `AllowJoins`, `DisconnectPeer` (server); `Rejected` (the sender) | 2b (#58) |
| `Countdown` | phase class | as Lobby for joins, leaves and `SetReady(false)`, each reporting `cancelled`; `countdown_done` on its end tick, `seconds` after entry | `seconds` (0 to 60; the class default 0) | as Lobby, and `CountdownCancelled` (everyone); its end tick goes out in `PhaseChanged` | 2b (#58) |
| `Loading` | phase class | refuses joins; `LoadMatch`; takes `LoadAck`s (another match's dropped, a second `unchanged`); at the deadline drops who did not confirm, never the host; a leave drops too; reports `all_loaded` | `deadline_seconds` (5 to 600; required, since a missing deadline would drop every client at once) | `LoadMatch`, `PlayerLoaded`, `PlayerLeft` (everyone); `Disconnecting` (the dropped player, M4-6); `RefuseJoins`, `DisconnectPeer` (server) | 2b (#58) |
| `Round` | phase class | nothing of its own: its intents go to rules, a leave to the life rule (§3.5, `LifeRules.leave`; a newcomer's leave is forgotten); a connection gets `DisconnectPeer` (2b) | none | `DisconnectPeer` (server); a leave: `PlayerLeft` (everyone), `player_left`, the drop's `ItemPlaced` (leave, everyone) and `item_rested` | 2a (#49); the leave 2g (#63) |
| `End` | phase class | `ReturnToLobby` from the host reports `back`; a leave sets life `left` (§3.5); a connection gets `DisconnectPeer` | none | `PlayerLeft` (everyone); `DisconnectPeer` (server) | 2b (#58) |
| `Silent` | voice rule | nobody hears anybody | none | the routing per tick (§5) | 2i (#65, `SilentVoice`) |
| `Proximity` | voice rule | every pair of present players within the radius (3D, §6), under the voice invariant (§6, for every rule): nobody hears the downed or the dead | `radius_m` (0.5 to 100; the class default 0, which the mode check refuses) | the routing per tick | 2i (#65, `ProximityVoice`) |
| `RoundVoice` | voice rule | a living or downed listener hears a living speaker within `living_m`, measured from the listener's last accepted position (where a downed player lies); under the voice invariant nobody hears the downed or the dead, the dead hear nobody, and a player who left hears and is heard by nobody (§6) | `living_m` (0.5 to 100; the class default 0, which the mode check refuses) | the routing per tick | 2i (#65); the ghost radii removed in M4-1 (#137) |

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
  1000); walk 4.5 m/s (0.5 to 20); sprint 7 m/s (at least walk, to 30) for 20 per second (0 to 1000), from 20 (0 to the
  maximum); jump 1 m (0 to 5) for 10 (0 to the maximum); the downed crawl at 1 m/s (`crawl_speed_mps`, 0.1 to the
  walk speed) for a knockdown of 10 s (`knockdown_s`, 1 to 120; vision revision 1's numbers, M4-2, the bounds
  placeholders, "not a decision"); capsule radius 0.4 m (0.1 to 1) × height 1.8 m (0.5 to 3); eye 1.6 m (below the height); step 0.3 m (0 to
  1). Health and stamina are whole points here, thousandths inside `core/` (§3.3). `PlayerRules`' class defaults are 0,
  so each number is written in `base_mode.tres` (`PlayerRules_base`), and a mode that leaves one out fails the mode
  check (2d, #60; the engineer's answer (1) on #58). Pushing (§7.1) is not in `PlayerRules`: `push_speed_factor`,
  `push_side_bias` and `push_max_overlap` are client feel tuning in `client/player/player_tuning.tres` (engineer),
  placeholders, never checked by the host; every client must ship the same values.
- Sides: `crew` ("Engineers"), `dissidents` ("Dissidents"). Roles: `crew` ("Engineer"), Dissident. The ids stay
  `crew` (vision revision 1's names, M4-1). Item kinds: Package, Knife.
- Actions: PickUp, PutDown. Reactions: none. Task types: Delivery. Win conditions, in order: every task done, no crew
  present, time up.
- Phases (accepts; tick systems; win conditions; clock; voice; level): Lobby (§3.2; none; no; stopped; Proximity 8 m;
  lobby), Countdown 5 s (§3.2; none; no; stopped; Proximity 8 m; lobby), Loading 60 s (`LoadAck`; none; no; stopped;
  Silent; map), Round (`MoveClaim` from the living and the downed, `PickUp`, `PutDown` and `Use` from the living;
  LifeTicks, TaskTicks; yes; runs; RoundVoice; map), End (`ReturnToLobby` from the host; none; no; stopped; Silent; map). Snapshots
  in Lobby, Countdown and Round. RoundVoice's `living_m`: 8 m.
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
accepted intent that no rule handles. 2f (#62) added Delivery to the task types and TaskTicks to Round; M4-2 (#138)
LifeTicks before it, the crawl speed and the knockdown time. 2c (#59) added Crew, Dissident,
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
Settings: id `crew`; display name "Engineer" (its side's "Engineers"; vision revision 1, M4-1); side `crew`; knows
its teammates: no; actions: none. The default role of `DealRoles`.
Produces: `RoleAssigned(crew)`.
Visible to: that player only (§5); `MatchEnded` names only the winning side, never a player's role.
Status: designed in #33; built in 2c (#59): `content/roles/crew.tres`; named Engineer in M4-1 (#137). Tests:
`tests/unit/deal/deal_roles_test.gd`, `tests/unit/content/content_modes_test.gd` (which pins both names).

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
Visible to: everyone, all of it: the task is shared, so every player learns the same (the downed and the dead too;
a player who left, nothing). `PackageDelivered` names the item and the circle, never the task.
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
stamina, the victim's health), and on a knockdown `KnockedDown` and the downed player's `Correction` (M4-2).
Visible to: `Swung` and `KnockedDown` everyone; `Damaged` only the victim; the attacker gets no confirmation of a hit
but the public knockdown (an accepted exception, vision revision 1); a
refusal (`too_soon`, `tired`) only the attacker. The public `Swung` reveals no role: the rule belongs to the item
kind, which any living player may hold (§9.2).
Status: designed in #33; the item kind (id, name, spawn tag) and its `SpawnItems` in 2c (#59):
`content/items/knife.tres`, tested by `tests/unit/deal/spawn_items_test.gd` and
`tests/unit/content/content_modes_test.gd`; the parts built in 2g (#63): `Cooldown`, `Strike` (`core/combat/`) and
the life rule (`core/life/`), and the rule in `knife.tres` with `Use` from the living in Round's allowlist
(provisional under the MVP content ADR, for the engineer's approval).
Tests: `tests/unit/content/content_modes_test.gd` (the rule's numbers, and a base-mode round where the living
strike and a downed player's `Use` is `not_accepted`), `tests/unit/combat/strike_test.gd` (the zone, sight, order,
who learns what), `tests/unit/combat/cooldown_test.gd`, `tests/unit/life/life_rules_test.gd` (every life
transition, the crawl, the dead, the §3.4 order; M4-2), `tests/unit/match/phases/round_phase_test.gd` (leaving
mid-round).

#### Every task done (win condition)
What it does: the crew's only win.
Settings: side `crew`; conditions: `AllSubtasksDone`.
Produces: `won(crew)`, then `EndMatch`: `MatchEnded(crew)`.
Visible to: everyone, the side only.
Status: designed in #33; built in 2h (#64): `content/win_conditions/every_task_done.tres`. Tests:
`tests/unit/win/all_subtasks_done_test.gd`, `tests/unit/win/clock_ended_test.gd` (a delivery on the end tick),
`tests/unit/content/content_modes_test.gd` (the base mode's data).

#### No crew present (win condition)
What it does: the dissidents win when every crew member has left (vision revision 1, V10). A downed or dead crew
member is still present: killing takes time from the crew, it does not end the round.
Settings: side `dissidents`; conditions: `NoneAlive` (side `crew`; the class keeps its old name).
Produces: `won(dissidents)`, then `MatchEnded(dissidents)`.
Visible to: everyone, the side only.
Status: designed in #33; built in 2h (#64) as "no crew alive"; replaced in M4-2 (#138):
`content/win_conditions/no_crew_present.tres` (provisional), in `no_crew_alive.tres`'s place in the order. Tests:
`tests/unit/win/none_alive_test.gd` (a knockdown and a death end nothing, the leaves, the §3.4 order),
`tests/unit/content/content_modes_test.gd`.

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
Settings, Produces, Visible to: the knife's. A downed or dead player's `Use` is `not_accepted` (Round accepts it
from the living only); an empty hand, or a package, is `nothing_to_do`.
Status: designed in #33; built in 2g (#63), as the knife's. Tests: the knife's; a downed or dead player's `Use`:
`tests/unit/life/life_rules_test.gd`, `tests/unit/content/content_modes_test.gd` (the base mode),
`tests/unit/content/item_intents_test.gd` (only the living, in every mode); a package's: `tests/unit/items/items_test.gd`.

#### Sprint (not a part in v0)
What it does: the `sprint` flag of `MoveClaim`, settled by the movement rule for every tick a claim covers (§7.1),
with the numbers in `PlayerRules`: 7 m/s, 20 per second, from 20. A tick costs only when the claim's `moving` flag
says the player gave movement input and it moved horizontally. The downed never sprint: they crawl at 1 m/s (§7.1
The crawl, M4-2).
Why not a part: a rule fires once per trigger, while sprint cost and speed apply to every covered tick of a
continuous claim. A mechanic that changes movement (a faster role, a slowing item) needs a movement modifier that the
movement rule reads: a new kind, v1 (§10).
Visible to: the player's own stamina in `SelfStatus`; speed is public through positions.
Status: designed in #33; built in 2d (#60): `MovementRule` and `StaminaLedger`. Tests:
`tests/unit/movement/movement_rule_test.gd`, `tests/unit/stamina/stamina_ledger_test.gd`.

#### Jump (not a part in v0)
What it does: the `jumps` count of `MoveClaim` (3e; `jumped` until then), accepted as in §7.1 with the numbers in
`PlayerRules`: 1 m for 10 per jump.
The downed never jump: a new jump of theirs is corrected (§7.1 The crawl, M4-2).
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
  win_conditions/every_task_done.tres, no_crew_present.tres, time_up.tres
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
  fails when the intent succeeds or is refused with another reason. So a scenario can script a downed player's `PickUp`,
  a second swing within the interval (`too_soon`), a swing without stamina (`tired`) or a `PickUp` of a delivered
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
| `WalkTo(target, sprint, stop_m)` | sends honest `MoveClaim`s at walk or sprint speed (at the crawl speed with no sprint while downed, M4-2; a dead bot cannot walk and fails the step), straight towards the target; a level with walls needs waypoints | it is within `stop_m` (0.5) of the target: 1 m before a circle, the put-down distance, to deliver |
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
  last `SelfStatus` says sprint is available (a downed bot never: it crawls), and stops exactly `stop_m` short. A dead
  bot claims nothing at all, standing or walking (M4-2).
  `Jump` claims a jump where the bot stands, on the floor: the bot's jump count in its epoch plus one (3e; D3 (a),
  the designer's answer on #96: the step names what a player does, not the count the wire carries). The setup's forced roles go in one `ForceRole` per bot
  right after the joins at the start, and its settings in one `ChangeSettings` from bot 1 after them.
- `fields` match a subset of the event's payload, as the bot received it (name and fields): text as text, numbers
  and vectors approximately, and `peer` holds a bot's number, mapped through the runner's `ScenarioPeers`; an event
  for one peer whose payload names none (`SelfStatus`) matches `peer` as the bot that received it (3h). `never` names an event, fields and a
  bot (0: every bot).

- **Targets come from the bot's own view**, the events and snapshots its client received: `package(n)` (the n-th
  package in item-id order, from 1; tasks are shared, #79), `circle_of_held`, `nearest(kind)`, `bot(i)` (where it last saw
  that player), `point(x, y, z)`. A target the bot cannot know fails the scenario, so a scenario also proves that the
  mechanic is playable with what a player is told.
- **Failures:** a step that sends an intent fails on a `Rejected` it did not expect and names the reason; a step that
  does not finish within the time limit fails; a `Correction` outside a placement (§3.2) or the bot's own knockdown
  (M4-2) fails, because an honest bot is never corrected, so every scenario also checks the host's movement rules against honest movement. A field that
  names a player is written as the bot's number; the runner maps it to the peer id (the core runner: bot 1 is
  peer 1, bot i is peer 1000 + i, so a scenario that confuses the two fails; the bots runner: the ids its clients
  got, §4.6).
- **Always asserted:** the expected ends within the time limit; no `ERROR:` line in the log; the §5 invariants on
  every bot's stream; over the network, the leak test (§5): the reliable events a bot decoded are exactly its peer's
  events in `Match.view_of`, in order, and every snapshot and voice frame it decoded is in `view_of`, which is a
  subset check, because the unreliable lanes (`LATEST`, `VOICE`) may lose some.
- **Runners:**
  - *Core* (stage 2j, #66): `tests/harness/` (`ScenarioRunner` on `ScenarioPlay`'s steps since 3h, `ScenarioBot`,
    `ScenarioInvariants`, `ScenarioPeers`) drives `Match`
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
  - *Bots* (M3, 3h): `tools\run.cmd bots [scenario]` starts a headless host, whose own client is bot 1, and the other
    bots as headless clients: over `LoopbackHub` in one process by default, stepped by a simulated clock, or over ENet
    on 127.0.0.1 with `--instances`, on the real clock. It plays the core runner's steps and checks its
    `ScenarioInvariants` (per `Match` call, through `HostSession`'s observer, §4.5), with `HostSession` in the place
    of the runner's stand-in for `server/` (§4.6). The same files; it joins `verify` with the leak test (§5). Each bot sees only its `ClientSession`'s decoded view (§4.6).
    Built in 3h (#102): `tests/harness/bots/`, `tools\run.cmd bots`, tested by `tests/scenarios/bots_runner_test.gd`.
- **Reproducing a failure:** the runner prints the bot, the step, that bot's last events and the seed; the command log
  replays the match (§3.3).
- **The MVP's scenarios** (2j, #66; provisional under the MVP content ADR, for the engineer's approval), in
  `content/scenarios/`: `crew_delivers_every_package` (3 crew deliver the 6 packages; a delivered package's
  `PickUp` is `unavailable`; the crew never get `Teammates`), `dissident_kills_the_crew` (rewritten in M4-2: a
  forced dissident takes a knife and knocks both crew down; `too_soon`; a downed bot is not hit again, its `PickUp` is
  `not_accepted`, and it crawls; both die at the end of their knockdown and a dead bot's `PickUp` is `not_accepted`;
  the one-minute match ends by time up, every crew member dead but present; the `bots-enet` step),
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
| `Interact(target)`: fixed interactables and bodies as targets (§9.8) | with the first mechanic that needs it |
| Movement modifiers, which would make sprint and jump parts (§9.5) | when a mechanic changes movement |
| Which `Use` rule wins when the held item and the actor's role both have one; v0: the item (§9.2) | #38, before a role has a `Use` ability (#34) |
| How levels mark spawn points: groups on `Marker3D` or an engine marker scene (§9.6); and give collision the host can read (`StaticBody3D`, not CSG or `GridMap`, with E8 (a): §4.5) | 4e, with the designer |
| How `MarkerReader` finds the floor under a `circle` marker in M3: `read_levels` reads every level of the mode before `Match.new`, from a copy outside any physics space, so the host's `WorldQuery` (§7.1, one space holding the loaded level) cannot answer it; either the reader computes the floor from the scene's own static colliders, or it reads each level once it is in the host's space (§9.6). #89 proposes the second: the host builds every level's world first and `read_levels` points the host's `WorldQuery` at each level (§4.5 Starting) | Settled: the second, built in 3c (#99, §4.5) |
| Lag compensation for hits (§7.1) | after the MVP playtest |
| Hiding positions behind walls (§5; not wanted now) | only if a human asks |
| Wire format of the message layer: schemas, encoding, versioning, reliability | designed in #89 (§4.3 to §4.6, E1 to E17 for the engineer); built in M3 (3c to 3i) |
| The host's per-send ENet cost and upload for voice (ENet between two machines: settled by #21, §4) | M3 or M5 |
| Voice integration: occlusion, radios, push-to-talk or voice activity, echo cancellation, device latency | M5 |
| Internet play without a VPN (NAT traversal): Steam networking vs WebRTC with a signaling server | M6 ADR |
| The M4 client's choices E18 to E33 and the designer's D4 to D10, the level conventions included ([ADR](decisions/2026-10-01-m4-first-person-client.md), §4.7) | Settled: every recommendation, E32 (b) and D10 (b) included (PR #136) |
