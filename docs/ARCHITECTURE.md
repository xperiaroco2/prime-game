# Architecture

| | |
|---|---|
| **Owner** | The engineer. The **content API** section is the contract between engine and content; since #518 the engineer owns both sides, and the optional designer reviews a change to it only when he wants to. |
| **Status** | Skeleton (M0). The boundaries below are locked ([KICKOFF §3](history/KICKOFF.md); stack: [ADR](decisions/2026-09-29-technical-stack-from-the-brief.md)). Everything marked *open* is designed before M2 (core and content API) or in the milestone named. The match loop, intents, events and entitlement (§3, §4.1, §4.2, §5, §7.1): M2 design, #32. The content API v0 and bot scenarios (§9): M2 design, #33; built in stage 2 from 2a (#49) on. The wire schemas, the codec, the host session and the M3 client and bots (§4.3 to §4.6): M3 design, #89, accepted ([ADR](decisions/2026-09-30-wire-format-and-host-session.md)); built in M3. Vision revision 1 ([ADR](decisions/2026-10-01-vision-revision-1.md), #126) replaces ghosts, the one hand slot, `no_crew_alive` and the meetings mode: the sections that describe them describe the code as built until the M4 rework updates them (the ADR's Consequences list each section). The windowed client (§4.7) and the split of that rework into M4 issues: M4 design, #125, accepted ([ADR](decisions/2026-10-01-m4-first-person-client.md)). |
| **Rules for agents** | The invariants are repeated in the root `CLAUDE.md`, so they survive compaction. Area rules: `core/`, `server/`, `net/`, `client/`, `voice/` `CLAUDE.md`. |

## 1. Layers and boundaries

| Folder | Contains | May use | Owner |
|---|---|---|---|
| `core/` | Pure rules: match state machine, intent validation rules (movement checks included), win conditions, who is entitled to each event and entity (§5), voice routing rules, content-API primitives. `RefCounted` only; no Nodes, scenes, networking or audio | nothing outside `core/` | engineer |
| `server/` | Host logic: wraps `core/`, checks the sender, format and rate of intents, builds one message per recipient from `core/`'s entitlement, answers `core/`'s geometric questions (`WorldQuery`, §7.1) | `core/`, the `net/` abstraction | engineer |
| `net/` | Transport abstraction (ENet first), message schemas, serialization, sync | nothing game-specific | engineer |
| `client/` | Scenes, player controller, UI, camera, audio playback, dev console | the filtered view it receives; `net/` to send intents; `core/`'s content definitions and constants (its own copy of the mode: which maps exist, which phase accepts which intent), never `core/` state (`Match`, `MatchState`, `view_of`; [ADR](decisions/2026-09-30-wire-format-and-host-session.md), review answers); `voice/`'s plumbing (E46 (a), [M5 ADR](decisions/2026-10-02-m5-voice-integrated-with-the-rules.md)) | engineer |
| `voice/` | Capture, Opus encode and decode, jitter buffer, playback plumbing | nothing outside `voice/` but the engine and the TwoVoIP addon by class name (E46 (a)): no `client/`, `net/` or `core/` state, no `ClientSession` or `ClientModel`; `client/` decides what is played | engineer |
| `content/` | Game modes, roles, abilities, items, sabotages, task types and win conditions as `Resource`s built from content-API parts (§9); bot scenarios (§9.7), whose data classes are part of the content API | the content API only | engineer (#518) |
| `levels/` | Maps from reusable room, prop, interactable and task-station sub-scenes | the content API only | engineer (#518) |
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
  player's life state (alive, downed, dead, left), position, hand and belt, health and stamina, the items, the tasks with
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
  the senders are a newcomer, any player, the living, the downed or the host; a player who left, still on the roster in
  Round and End, is refused under every one, and the dead only take the host's session controls; tests:
  `tests/unit/match/match_test.gd` and `match_accepts_test.gd`). Two exceptions (3e, #97; §4.3): a refused
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
  (`LifeRules.knock_down`); when it runs out the player dies (`LifeTicks`, §9.4), and the respawn time later it
  respawns at a `respawn` marker, invulnerable for a while (M4-3, #139); a player who leaves mid-round is left (§3.5).
  `PlayerState.life_deadline` is the host tick at which the current life state runs out (the knockdown's end; the
  respawn's). `AcceptSpec.From` names a newcomer (1), any player (2), the living (4), the host (16) and the
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
| Round | the deal has run (below); `LifeTicks` lets the downed die at the end of their knockdown and the dead respawn; `ChannelTicks` runs the raises (M4-4) | living: `MoveClaim`, `PickUp`, `PutDown`, `Use`, `Raise`, `StopRaise`, `Swap` (M4-5); downed: `MoveClaim` (the crawl, §7.1.7), `GiveUp`; dead: nothing; leave | round rule | runs |
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
  (`roles`, `task_types`, `circles`, `tasks`, `packages`, `zones`, `knives`, `spawns`), named in the data of the part that
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
  bound to a random circle of its own, whose colour it takes (`tasks`). The zone task's deal (#647, §9.5.17): one task
  of *zones* zones on distinct random zone spawn points, each in a distinct random palette colour (both `zones`); zone
  *i* is subtask *i* in station-id order. Then each task's `TaskState` (its id, type and
  subtasks done and in total: the task screen's data, M4-5) and `TaskProgress` (the subtasks done and in total over
  every task, 0 done unless a package spawned in its circle) to everyone; knife positions (`SpawnItems`); player spawn points
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
  `server/` originates too: `PeerConnected`, `PeerLeft` with their peer ids, and in debug builds `ForceRole`, §9.4
  `DealRoles`), the levels' `LevelLayout`s (§9.1), and every `WorldQuery` answer (a throw's flight adds only answers,
  no command of `server/`'s: §7.1.16, proposed). A replay reads the answers from the log instead of asking the
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
win. The check after every fact is what makes this so: a leave raises `player_left` before the carried items drop
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
| Round | refused, as in Loading | life state `left`, which "no crew present" counts (§3.4); the avatar is removed and no body stays: a downed player who leaves leaves none, and a dead player's body is removed (the engineer's answer 1 on PR #133); in this order `PlayerLeft` (everyone else), the fact `player_left`, then the hand item and then the belt item come to rest on the floor below where the player stood (§7.1, M4-5). 2g (#63): `RoundPhase` hands it to `LifeRules.leave`, after forgetting a newcomer that never joined (`JoinRules.forget_newcomer`) |
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
- **A return** (M7, designed in #73, [ADR](decisions/2026-10-09-returning-players-keep-their-number.md); proposed, not
  built): a client sends a return key in `Hello`, made from a random secret in its settings file and the room code or
  address it joins (so a key one host learns works nowhere else); the host binds a new key to the joiner's number,
  and a later `Hello` with that key, while no present player holds the number, gets the number back instead of the
  next one. Only where joins are allowed (Lobby, Countdown): every other phase still refuses joins, so a player who
  left a round returns in the next lobby. The key reaches no other peer (§5 gains it with 73-A); the name and the
  colour follow #550's and #551's rules as for any joiner.
- **The host is lost:** there is no `core/` event: `core/` runs on the host. How a client notices is a transport
  signal (#40); the client returns to the main menu with a message.

## 4. Protocol

**Model** ([ADR](decisions/2026-09-29-listen-server-and-message-layer.md)):
- Listen server: one player hosts as peer 1 and plays; no dedicated server. The host's own client talks to the host
  through an in-process loopback transport, with the same codec and per-peer filter as every other client.
- Own messages over `MultiplayerPeer` (ENet first), not RPCs, `MultiplayerSpawner` or `MultiplayerSynchronizer`:
  every outgoing message is built per recipient in one place, which the leak test checks (§5).
- The host leaving or crashing ends the match; clients return to the main menu with a message. No host migration
  and no reconnection in the MVP (M7's design gives a returning player its old number in the lobby only, §3.5). A
  client leaving mid-match counts toward "no crew present" (§3.4), and its held item drops where it stood. Nobody
  joins during a match (`NetTransport.set_refuse_new_connections`).
- The game scene loads with threaded loading and a longer ENet timeout; the round starts when every peer still in
  the roster confirmed it loaded (§3.2).
- The MVP is played over a LAN or a VPN (Radmin VPN, ZeroTier, Tailscale); no UPnP attempt was built. Internet play
  without a VPN is the M6 ADR ([the M6 design](decisions/2026-10-04-m6-playable-over-the-internet.md), #346, accepted:
  WebRTC with our own signalling, D16 (a); ENet direct join kept, no UPnP, E61).

**Transport** (`net/transport/`, #40):
- `NetTransport` is all game code sees: `host`, `join`, `poll`, `send(to_peer, kind, payload)`, `close`, `own_id`,
  `peers`, `set_refuse_new_connections`, `disconnect_peer`; signals `connected`, `connect_failed(reason)`,
  `peer_joined`, `peer_left`, `host_lost` and `packet_received`, fired only from `poll()`. A client sends only to the
  host (peer 1). The host's own client is peer 1 too. `connect_failed`'s reason is one of `NetTransport`'s `JOIN_`
  ids, as precise as the backend can tell (M6-4, #370): ENet and the loopback cannot tell a refusal from no answer
  and give `connect_failed`; WebRTC adds `no_room`, `joins_closed`, `full` (the service's answers),
  `service_unreachable` (its socket closed, or not open after the Signaller's 5 s connect timeout, §4.8),
  `service_refused` and `host_unreachable` (no direct path, or no answer in 15 s).
  `ClientSession` ends with it, and `EndReasons` (`client/app/`) says each in words.
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
- **`LaneOrder`** (`net/transport/`, M6-3, #365; [the M6 design](decisions/2026-10-04-m6-playable-over-the-internet.md)
  §2.2, E49) restores ENet's channel-0 order of LATEST against RELIABLE for a backend whose channels do not keep it
  (WebRTC's data channels, a later Steam backend; ENet and the loopback do not use it). Without it a `MoveClaim`
  sent just before a `PickUp` can arrive after it, and the host refuses the `PickUp`, only over the internet. The
  sender prefixes each LATEST packet with `[reliable_sent: u16][latest_seq: u16]` (LE, wrapping, compared in
  serial-number order): the packets written to that peer's RELIABLE channel before it, `ADMIT` included
  (`count_reliable_sent`), and a per-peer LATEST counter (`stamp_latest`). RELIABLE and VOICE carry no header, and
  the header sits below `NetFrame`: the frame handed on has none, and the payload caps are unchanged. The receiver
  reads LATEST before RELIABLE in each poll and calls `read_reliable` for every RELIABLE packet before decoding it;
  `read_latest` delivers a packet whose `reliable_sent` equals that count and whose seq is newer, holds one that is
  ahead until its reliable packet is read (`read_reliable` returns the held frames it releases, which go to the
  inbox right after that reliable packet), and drops one that is behind or not newer. At `HOLD_CAP` (8, a
  placeholder) held packets one packet of the arriving one's kind, the arriving one included, is dropped: first the
  oldest that a newer one waiting for the same reliable packet follows (the inbox's merge would drop it anyway),
  else the oldest (the M6 ADR's §2.2 rule; it loses the claim between two reliable packets only with 8 in flight), and with
  none of that kind held the arriving one. The dropped frame comes back in `Read.superseded`: the backend decodes
  it without delivering it and counts it in `latest_superseded` when valid, as the inbox does. A per-peer clock
  starts when the hold turns non-empty and restarts at each release; past `STALL_MS` (20 s, the silence rule),
  judged after both channels were read, `stalled_peers` names the peer once and forgets it, and the backend counts
  `ORDER_STALLED` and disconnects it (a client ends as `host_lost`); a full hold alone never disconnects. Rejects:
  a LATEST packet shorter than the header (`ORDER_HEADER_SHORT`), longer than the header and the longest frame
  (`TOO_LARGE`), or from a peer it does not know (`UNKNOWN_PEER`). Peers are explicit: `add_peer` when a connection
  opens, `forget` at once when it leaves or is disconnected, which discards its held packets undelivered, so a
  late packet never brings an old connection's counts back. `count_reliable_sent` counts only packets the channel
  accepted. The class is pure (the caller passes the time); `WebRtcTransport` (below) uses it, and its stall clock
  is the silence rule's (`STALL_MS` equals `WebRtcTransport.SILENCE_MS`, which a test pins, so the class names no
  backend).
- **The WebRTC library** (M6-2, #367; [the M6 design](decisions/2026-10-04-m6-playable-over-the-internet.md) E57):
  webrtc-native 1.2.2 in `addons/webrtc_native/` (the `.gdextension` as shipped and its `.uid`, the Windows and
  Linux x86_64 libraries, their license files; credits: `docs/credits/webrtc_native.md`). Godot loads it at start
  in the editor, a Windows export, CI and a cloud session, and it makes its `WebRTCLibPeerConnection` the
  implementation behind the engine's `WebRTCPeerConnection`. So `WebRtcTransport` (`net/transport/`, M6-4) creates
  `WebRTCPeerConnection`s and their `WebRTCDataChannel`s with `new()` and `create_data_channel`, names no class of
  the addon, and is the only code that reaches WebRTC; nothing outside `net/` does. Without the extension those
  calls return nothing usable (`create_data_channel` gives null): the smoke test
  `tests/unit/net/transport/webrtc_native_addon_test.gd` fails then, so `verify` catches a lost or unloadable addon.
  The library sets itself up when a process makes its first connection, and again after its last one is gone; a
  new connection's offer waits for that (#472, measured on the engineer's PC, 16 logical CPUs): about 30 ms when
  idle, but 9 to 11 s for a GdUnit process's first offer under `tools\run.cmd load --loops 128`, and often 0.5 to
  1 s there whenever no other connection was open, against under 10 ms while one was. So every WebRTC run of
  `verify` keeps one connection open for its whole run (`tests/integration/net/webrtc_warm_up.gd`) and makes no
  other before it is set up: `webrtc_transport_test.gd` and `webrtc_silence.gd` poll it frame by frame (#472);
  `webrtc_host_and_two_clients`, `webrtc_freeze`, `webrtc_stall`, each process of the WebRTC bots and the chaos
  run over WebRTC block in its `wait()` (at most `READY_WITHIN_MS`, 30 s) before they host or join; the twins and
  the bots print how long the setup and each join took (#510). Before #510 their first join carried the setup:
  under 128 busy loops `webrtc_host_and_two_clients` failed 3 of 5 runs (both first joins `host_unreachable` after
  17 to 22 s, so the retries got ids 4 and 5), `webrtc_freeze` lost both first joins the same way in 1 of 4, a
  `webrtc_stall` join took 9.9 s, and 3 of 4 `bots-webrtc` runs lost a join for good. After it, in 3 runs of each,
  the setup took 0.5 to 10 s and no join failed or took over 3.1 s; what still fails under that load is not a
  join: `bots-webrtc` 2 of 3 (an honest bot corrected outside a placement, as in 1 of the 4 runs before) and both
  chaos runs (`chaos-webrtc` and `chaos` over ENet alike take 90 to 100 s there, past their 60 s).
- **`WebRtcTransport`** (`net/transport/`, M6-4, #370; [the M6 design](decisions/2026-10-04-m6-playable-over-the-internet.md)
  §2.1 to §2.3, §2.6; E48, E50, E54, E56), the second network backend: a star, never a mesh. The host holds one
  `WebRTCPeerConnection` per client and reads it directly (no `WebRTCMultiplayerPeer`, E48); the host's own client
  stays a `LoopbackTransport`.
  - **Signalling** goes through a `Signaller` to the service at `signal_url` (the Worker, or a `LanSignalling` on the
    LAN and in every headless test). `host()` opens a room (`room_protocol` and `room_content` go into `open`;
    `room_opened(code)` and `room_code()` give its code; the port is unused); `join(code, _)` joins one, and
    `found_protocol`/`found_content` keep the service's advisory `found` for the menu (M6-7). Per joiner the host
    assigns the next peer id (2 upward, never reused in a session, E50), creates the connection with the ICE servers
    the service gave it, and offers (the offer's attempt id is that peer id); it applies one answer per offer, and a
    second one, an answer or candidate it cannot apply, or a failed description closes that connection (an admitted
    peer leaves). The joiner applies one offer per attempt. Half-made connections, and ones the host is closing,
    count against `max_clients` (`connection_count()`); a full or refusing host answers a joiner nothing, and
    refusing joins drops the connections still being made and also sends `close` to the service (`reopen` when it allows them again), so a code typed during a
    match is answered `joins_closed`. Once admitted, the client closes its signalling socket, which frees its place in
    the room. Tests set `local_candidates`: only IPv4 host candidates are signalled, rewritten to 127.0.0.1.
  - **Channels:** three negotiated data channels per connection, created by both sides with the same options
    (`CHANNEL_IDS`): RELIABLE id 1 (reliable, ordered), LATEST id 2 and VOICE id 3 (`ordered: false`,
    `maxRetransmits: 0`). Each packet reaches the inbox with its channel's lane, so `NetFrame.decode`'s lane check
    stays. LATEST packets carry `LaneOrder`'s header (`stamp_latest`; every packet RELIABLE took, `ADMIT` included, is
    counted with `count_reliable_sent`; an empty packet is refused, `ERR_INVALID_DATA`, since the peer never reads an
    empty message and counting one would hold every later LATEST packet one reliable packet too long, #429); each
    poll reads every connection's LATEST channel, then RELIABLE (each packet
    counted with `read_reliable` before anything else, the frames it releases pushed right after it), then VOICE. A
    LATEST packet `LaneOrder` rejects, and the frames its full hold drops, go to the inbox as `REJECTED` and
    `SUPERSEDED` items, so they are counted in the inbox's order (the latter through `_decoded`, into
    `latest_superseded` when valid).
  - **Admission:** once every channel is open the host sends `ADMIT` on RELIABLE: a kind-0 frame whose payload is
    the peer id (u32, 7 bytes in all), and `peer_joined` follows. The client's first RELIABLE packet must be it; it
    learns its id there, and an id of 1 or less, or anything else, ends the join with `connect_failed`. A host that
    refuses joins when a connection opens closes it instead.
  - **Keepalive and the silence rule** (the M6 ADR §2.6): WebRTC's own keepalives run on libdatachannel's threads, so a hung main
    thread stays `CONNECTED` (M6-1). `poll()` sends each live peer exactly `[0, 0, 0]` on VOICE when nothing went to
    it for `KEEPALIVE_MS` (1 s), from the main thread only; the receiver consumes exactly that packet on VOICE before
    the inbox (and the round trip's probes below), and any other kind-0 packet reaches the inbox, which rejects it
    (`UNKNOWN_KIND`). After every channel
    was read (the backlog drained first, so a thawed side drops nobody), a peer heard nothing from for `SILENCE_MS`
    (20 s), keepalives included, leaves: `peer_left` on the host, `host_lost` on a client. So does a connection in
    `FAILED` or `CLOSED` (judged after its channels were read, so what came with the end comes first, as on ENet;
    the fault shim's late RELIABLE packets too), and a channel not open under a live connection: on a client at once (it is how
    `disconnect_peer` ends it); on the host after `CHANNEL_GRACE_MS` (1 s) with the connection still up, counted as
    `CHANNEL_CLOSED` (a client's own close resets its channels just before its connection ends, and under load the
    host read the first a poll before the second: 1 run in 10). `DISCONNECTED` is transient. A join not admitted
    `JOIN_TIMEOUT_MS` (15 s) after `join()` gives up with `host_unreachable` (no offer came, or the channels never
    opened); the host closes a half-made connection after as long. A join whose socket to the service has not opened
    by `Signaller.CONNECT_TIMEOUT_MS` (5 s, §4.8) gives up before that with `service_unreachable` (#431, #461): on
    Windows the engine reports a refused connect only at its TCP connect timeout
    (`network/limits/tcp/connect_timeout_seconds`, 30 s; `WebSocketPeer` and `StreamPeerTCP` alike), though the OS
    refuses a closed 127.0.0.1 port in about 2 s, and a service that takes the connection but never answers the
    handshake reports nothing. On Linux the refused socket closes at once (`service_unreachable` too).
  - **Never a send on a closed channel:** each write checks the channel's `get_ready_state()` first (a closed one
    prints an engine `ERROR:` line, M6-1). A leaving peer's channels are drained and discarded until it is gone.
  - **`disconnect_peer`** never blocks: the reason the caller sent goes out first; the next `poll()` closes that
    peer's RELIABLE channel once its buffered amount is 0, and the connection once the client closed its side (its
    connection or another channel closed) or `CLOSE_WAIT_MS` (5 s) passed. Held LATEST packets are discarded at once,
    and nothing more is sent to it. A leave the host decides (silence, a stall, a closed channel) closes the
    connection at once.
  - **The own connection** (the design's §3 item 4, #431; every backend has `own_route()` and
    `own_round_trip_ms()`, a client's own only, NONE and -1 on a host): webrtc-native 1.2.2 registers no method of its
    own, so neither the selected candidate pair (host, srflx or relay) nor a round trip can be read
    (`webrtc_native_addon_test` pins it). The kind follows from the ICE servers the offer brought (`route_of`):
    `DIRECT` without a TURN server (no relay candidate exists), `DIRECT_OR_RELAYED` with one. With
    `measure_round_trip` set (the client's F3 while it shows) a client pings the host on VOICE once admitted and every
    `PING_INTERVAL_MS` (1 s, a placeholder; a ping counts as a keepalive): a kind-0 frame of 5 bytes, `PING` and its
    clock in ms (u32), 8 in all (`PING_BYTES`). The host answers the pings of one poll once, after the reads, with
    `PONG` and the last stamp read; the client takes `now - stamp` (dropped when later than now or older than
    `SILENCE_MS`) into a smoothed round trip (gain 1/8). Both are consumed before the inbox; one the wrong way, or
    malformed, reaches it and is rejected. Off by default, so the silence twin's upload is keepalives alone. A client
    that stops measuring forgets its figure (the line reads "not measured yet" after F3 is reopened). A sample
    includes up to a frame on each side, as ENet's acknowledgements do. The host's answers are bounded only by its
    poll rate, and `PeerBudget` never counts a ping (hobby project: no limit added). ENet: `DIRECT` and its smoothed
    `PEER_ROUND_TRIP_TIME`; the loopback: `LOCAL`, no round trip.
  - **`take_upload()`** counts each packet a channel took (the header included) plus `PACKET_OVERHEAD_BYTES`, E56's
    108 B, one datagram each; SCTP's acknowledgements are left out (the transport never sees them).
  - **The fault shim** (`FaultShim`, `use_faults`, debug builds only and off by default; the design's §5): on what
    that side receives, RELIABLE arrives `reliable_delay_ms` late in order, counted from the poll before it was read
    (so a backlog read after a freeze is not held back again), one packet `delay_next_reliable(ms)` late instead
    (holding back the ones behind it, as SCTP would), and LATEST is dropped and duplicated at seeded rates, and at the
    rate `latest_late` a copy arrives `latest_delay_ms` late, holding back the LATEST packets behind it (M6-6). The
    freeze twin runs with it on (50 ms, 10 % dropped, 10 % duplicated), the stall twin delays one beat by 3 s while
    LATEST flows, and the bots and chaos bots over WebRTC (§4.6.7) make one LATEST packet in five that a client receives
    120 ms late: more than RELIABLE's 50 ms plus a 20 Hz interval, so a LATEST packet sent just before a reliable one
    arrives after it, the one case only `LaneOrder`'s "behind" rule handles (with RELIABLE late alone, the rule
    removed passed `bots-webrtc`). LATEST never overtakes LATEST: with each packet 0 to 200 ms late at random, the
    first claim of an epoch was often overtaken, which §7.1 takes as one tick, and an honest chaos bot was corrected
    (1 of 5 runs under load). Until #429 only clients lost LATEST and got it late: a host that lost a `MoveClaim`
    right before a reliable `PickUp` (or dropped a late one behind it, the rule at work) checked the `PickUp` against
    the claim before and refused an honest bot (`out_of_reach`, 1 of 3 chaos runs), and a host that lost an epoch's
    first claim took the next as one tick and corrected an honest bot (1 of 10 chaos runs under load). Since #429 the
    client sends those claims on `MoveClaimReliable` (§4.3, §7.1.15 Lost claims), and every side's shim, the host's
    included, drops 10 % of LATEST and makes 20 % of it 120 ms late.
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
  drops only after about 31.5 s (#95): that holds only for a client that connects within its process's first
  500 ms (as `enet_stall` usually does). ENet's clock is Godot's (milliseconds since the process started; read
  in the engine's `enet_godot.cpp` and shown by the #443 probe, a round trip of 500/0 against 7/4, not in
  the API dump), so a client that connects later, as every real game client does from a menu, pings at once
  and measures the round trip from the answer: it drops a host that stops at the connection after about 10 to
  12 s (#443: 11.8 s after a 600 ms start).
- **The backlog in one poll:** ENet reads at most 256 datagrams per service and `ENetMultiplayerPeer.poll()`
  services once, so after a freeze one service took only the oldest part of the backlog (on the Linux CI runner
  the thawed host's newest pose was up to 3.1 s old, #95). `EnetTransport.poll` services until one reads fewer
  (at most 16 times), so the LATEST merge sees the whole backlog.
- Checked by `tests/unit/net/transport/`, `tests/integration/net/webrtc_transport_test.gd` (WebRTC against forged
  peers in one process: a half-made connection against the maximum, a second answer, an `ADMIT` of the host's id,
  keepalives and other kind-0 packets, the join's reasons (a closed service port and a service that never answers
  the handshake: `service_unreachable` on every OS, with the shipped timeouts too, #461), a peer's last message
  before its leave, a kick's reason read with the closed channel, ids not reused, a channel closed under a live
  connection; the round trip's pings only while measuring, one answer per poll, probes the wrong way rejected;
  a warm-up connection lives as long as the suite, and only the joins a test expects to give up have the short
  join timeout, since a join under load took up to 1.7 s, #472),
  `tests/integration/net/webrtc_warm_up_test.gd` (`WebRtcWarmUp.wait()`: ready, its bound's timeout named, a
  failed setup returned at once, #510), `tests/unit/net/transport/webrtc_route_test.gd` (the kind from the ICE servers) and seven headless runs on
  127.0.0.1, which `verify`, and so CI, runs on a free port (`-- --port=<p>`; AGENT_WORKFLOW §11): the three ENet
  runs below (the host and two clients also check each side's own connection), and their WebRTC
  twins with `LanSignalling` on that port, no ICE servers and host candidates only (M6-4, #370):
  `webrtc_host_and_two_clients.gd` (`--instances 3`: the ids 2 and 3, then 4, `disconnect_peer` after a last
  message, every peer's own id on every lane, which caught the design's §5 plant of a swapped id-to-connection map,
  the upload by E56, a join while refusing answered `joins_closed`), `webrtc_freeze.gd` (`--instances 3`, the fault
  shim on), `webrtc_stall.gd` (one process: a stalled host and a stalled client dropped by the silence rule, 20 s
  after their last packet; a reliable packet 3 s late keeps its peer) and `webrtc_silence.gd` (one process: a dead
  client and a silent Lobby kept for 30 s, keepalives alone, one a second, counted by E56; the room opens only
  once a warm-up connection is set up, so the library's setup no longer counts against the joins'
  `JOIN_TIMEOUT_MS`: the likely cause of two `host_unreachable` failures at 16.1 s under load, #472; the other
  three twins set it up the same way in each process before they host or join, #510):
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
    10 s, which guards only against a too-low maximum: ENet waits about 31.5 s there with any timeout when the
    client connects in its process's first 500 ms, and about 10 to 12 s when it connects later (above):
    `tools\run.cmd run tests/integration/net/enet_stall.gd --headless -- --port=<p>`. A drop comes only inside
    the running side's poll, and a frame hitch on a loaded PC delays that poll, so the window's top is judged at
    its last poll before the drop and the bottom at the drop (`tests/harness/net/stall_watch.gd`, tested by
    `tests/unit/net/stall_watch_test.gd`; #443: a drop 649 ms over the top beside two other verifies).

*Designed for M3 (#89; accepted 2026-10-01):* the schemas of every intent, event, the snapshot and the voice frame, and their
rows in `NetKindTable.game()` (§4.3); the codec (§4.4); rate limits and what the host does with a peer that keeps
sending rejected packets (§4.5). `MoveClaim` stays on the LATEST lane and carries a cumulative jump count, so a jump
survives a merge (§4.3); since #429 the claims that must not be lost travel on its RELIABLE twin, `MoveClaimReliable`.
The protocol version travels in `Hello` (§4.3), not in the transport's `ADMIT`. The engineer took the
recommendation of every choice E1 to E17 (E10 (b), E14 (a) with the client rule of (b)); the
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
`MoveClaim`'s `jumps` outside the wire's u16, or a mask outside its u32, is malformed in core itself
(`MovementRule.MAX_JUMPS`, `MAX_MASK`).

| Intent | Who, in which phase | The host validates |
|---|---|---|
| `Hello(version, content)` | a connected peer that is not yet a player, once; Lobby or Countdown. In another phase a newcomer's `Hello` gets `joins_closed` and `DisconnectPeer`, another non-player's `joins_closed` (E14, 3e) | the version (an int) equals the host's, or `wrong_version` and `DisconnectPeer`; `content` (an int, the content hash, §4.3) equals the host's (`Match.content_hash`), or `wrong_content` and `DisconnectPeer` (E1, 3e); room in the roster, or `full` and `DisconnectPeer`. No name: the host names the joiner `Player<n>` (§3.5; own names: #73), and a `name` a client sends is ignored. Accepted, it is the join (§3.5) |
| `SetReady(ready)` | any player; Lobby (true or false), Countdown (false only: true is `not_accepted`) | `ready` is a bool, or `bad_args`; that it changes the player's state, or `unchanged` |
| `ChangeSettings(settings, map)` | the host (peer 1) only; Lobby only | `settings` names only the settings that change; each is a declared setting (`unknown_setting`) with a value of its kind (§9.1; else `unknown_setting`): an int within its bounds (`out_of_bounds`), or for `banned_task_types` an array of the mode's task type ids (another id: `out_of_bounds`), which replaces the set. Then the settings as they would be must suit the deal: `tasks` at most the task types not banned, and at least one type not banned (`out_of_bounds`; #79, placeholder rules). The optional `map` is one of the mode's maps (`unknown_map`). All or nothing. Whether they fit the map is checked at `all_ready` |
| `LoadAck(match_id)` | each player of the frozen roster, once; Loading | the current match id (the match's index in the session): an ack of another match is dropped silently; a second ack is `unchanged` |
| `MoveClaim(epoch, client_tick, position, velocity, facing, sprint, moving, jumps, on_floor, sprint_ticks, moved_ticks)` | living players in Lobby, Countdown and Round; the downed in Round (the crawl, §7.1.7); never the dead; in another phase, or from another sender, dropped without `Rejected` (E15, 3e) | the current epoch and a rising client tick (else dropped as stale); finite values; the client tick rising at a bounded rate; speed for the life state and stamina; jumps; height (§7, §7.1). `client_tick` counts 20 Hz core ticks of the client's own clock (`Ticks.RATE`), not physics frames. `sprint` and `moving`: the sprint state and movement input in any physics step since the client's last claim (#155). `sprint_ticks` and `moved_ticks` (#155): the same per client tick, bit i for client tick `client_tick - i`, so a claim the LATEST merge superseded still has each of its ticks settled as sent; the host reads only the bits of the ticks the claim covers (older ones take bit 31), and a mask outside the u32 is malformed in core itself (`MovementRule.MAX_MASK`, a `Correction`). A claim that fails a check gets `Correction`, not `Rejected`. `jumps` (3e, E2): the client's count of jumps since it adopted the epoch, which survives the LATEST merge (§4.3, §7.1) |
| `PickUp(item)` | a living player; Round | the item lies on the ground (not carried, not delivered); pick-up reach from the host's position of the player; line of sight. It goes to the hand; a one-handed hand item moves to an empty belt, any other hand item rests where the picked one lay (§7.1.11, M4-5) |
| `PutDown(facing)` | a living player with an item in hand; Round | nothing from the client but the facing: the host computes the placement (§7.1.12). Only the hand item: a belt item alone is `empty_hand` |
| `Use(facing)` | a living player; Round | the first `Use` rule of the hand item's kind (never the belt item's), the actor's role or the mode (§9.2); none: `nothing_to_do` (an empty hand, or a package in the MVP). The knife's rule: its minimum interval since this player's last hit, whatever weapon that was; stamina of at least the hit's cost; the host picks the targets (§7.1.10) |
| `ReturnToLobby()` | the host only; End | |
| `Raise(target)` | a living player; Round (M4-4, E28: sent on pressing E over a downed player) | the base mode's raise rule (§9.5), its conditions at the start and again every tick: the target is downed (`not_downed`); neither the sender nor the target is in a running channel (`busy`: one raiser at a time, the engineer's answer 4 on PR #133); the target lies within the pick-up's 2 m of the sender's last accepted position (`out_of_reach`) and in its line of sight (`blocked`). A raiser may hold the package. Accepted, the raise runs until it completes or stops (§9.4 `RaiseDowned`) |
| `StopRaise()` | a living player; Round (M4-4: sent on releasing E) | the sender raises someone (`not_channeling`: a late one after the raise completed or stopped); applied, the raise stops |
| `GiveUp()` | a downed player; Round (M4-4) | nothing more: the player dies at once, and a raise of it stops first (§9.4 `Die`) |
| `Swap()` | a living player; Round (M4-5, the ADR's controls: X); the downed and the dead get `not_accepted` | an item in the hand or on the belt (`nothing_to_swap`); no two-handed item in the hand (`two_handed`: a package carrier cannot draw a belted knife, V13). Applied, the hand and belt items change places, either of which may be empty, and a raise the sender runs stops (§9.2) |

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
| `ItemPickedUp` | peer, item; `belted`: the one-handed hand item this pickup moved to the belt, or none (M4-5, E29) | everyone | `PickUp` |
| `Swapped` | peer | everyone | a `Swap` (M4-5): the peer's hand and belt items changed places. With `ItemPickedUp`'s `belted` and `ItemPlaced` it tells every client every player's two slots, its own included (its avatar is never sent to it) |
| `ItemPlaced` | item, rest position, cause: put down, swap (a pickup's hand item that did not go to the belt), death or leave (at a death or a leave the hand item's comes first, then the belt item's) | everyone | an item comes to rest |
| `PackageDelivered` | item, its circle (now shown as done) | everyone | the delivery check (§7.1.14) |
| `TaskState` | task, its task type's id, its subtasks done and in total (M4-5, E30) | everyone: the task screen is every player's, living, downed or dead | the deal, for each task in id order, after the task types dealt; a subtask of that task is done, before `TaskProgress` |
| `TaskProgress` | subtasks done, subtasks in total, over every task of the match | everyone | the deal, after the task types dealt and their `TaskState`s (so the HUD shows the total from the start); a subtask is done |
| `ZoneProgress` | a zone's station, its ticks so far (after this tick's gain), the ticks it needs, whether it counts now, and the host tick (#647, ZE4) | everyone: it names no player, and counting is role-blind (ZD3) | the zone task's tick (§9.5.17): a zone whose counting changed since its last one, at most once per zone per 5 ticks (a change inside the window goes out at its end with that tick's state), and a zone done, in its own tick, before its task's `TaskState` and `TaskProgress` |
| `Swung` | peer, facing (the zone's horizontal direction, a unit vector or zero when it has none: of the `Use`'s facing, or the last accepted claim's when the `Use` had no finite, non-zero one) | everyone | a valid `Use` of a knife (`Strike`), whether or not it touched anyone; before any `Damaged` |
| `Damaged` | amount, your health (thousandths, §3.3); no attacker | the victim | a hit on them |
| `SelfStatus` | health and stamina (thousandths, §3.3), whether sprint is available, and the client tick of the last `MoveClaim` the host settled for that player in its epoch (-1: none since its placement; #155) | that player | on change of the numbers, at most once per tick: at the end of the tick, with its final numbers (`SelfStatusFeed`); a new claim tick alone sends none |
| `KnockedDown` | peer, where it lies (the floor below its last accepted position) | everyone, the downed player included | health reaches 0 (`LifeRules.knock_down`, M4-2); no attacker or cause. It tells the attacker its hit knocked down: an accepted exception to "no hit confirmation" (vision revision 1) |
| `Died` | peer, body position | everyone, the dead player included | a downed player's knockdown time runs out (`LifeTicks`, M4-2) or it gives up (`GiveUp`, M4-4); no event names a killer or a cause. The body stays until its player respawns or leaves |
| `RaiseStarted` | raiser, target | everyone | a `Raise` is accepted (M4-4): the target's knockdown pauses and it is held in place |
| `RaiseStopped` | raiser, target; no cause | everyone | a raise stops before completing (M4-4): `StopRaise`, any other applied action of the raiser, the raiser out of reach or sight, hit, downed or leaving, the target giving up or leaving. The knockdown runs on from where it paused. A raise stopped by a hit tells the attacker the hit landed: an accepted exception to "no hit confirmation" (the engineer's answer 7 on PR #133) |
| `Revived` | peer | everyone, the revived player included | a raise completes (M4-4): the player stands where it lay with the raise's revive health, its stamina kept, invulnerable for `PlayerRules.invulnerable_s`. It ends the raise (no `RaiseStopped`); no `Correction` (it was held in place) |
| `Respawned` | peer, the respawn marker it stands on | everyone, the respawned player included | a dead player's respawn time runs out (`LifeTicks`' `Respawn`, M4-3): it is living again with full health and stamina and empty hands, and invulnerable for `PlayerRules.invulnerable_s`. It removes the player's body (E26: no event of its own); before the respawned player's `Correction`. Names no cause of the death |
| `Correction` | epoch, position, velocity | that player | a `MoveClaim` that fails a check (§7.1); a placement (§3.2); a knockdown: the downed player where it lies, with a new epoch (§7.1.7 The crawl); a respawn: at the marker, with a new epoch, after `Respawned` (M4-3). None at a death (the dead send no claims) or a revive (the raise held the player in place, M4-4) |
| `Rejected` | the intent's sequence number, reason | the sender (*sender*: a present player, or a peer that is not a player: a newcomer whose `Hello` was not accepted yet, or a peer being disconnected whose intent was in flight) | any rejected intent but a `MoveClaim` (dropped, E15); an applied intent whose outcome was dropped (`outcome_dropped`, §3.1) |
| `MatchEnded` | the winning side (crew or dissidents), nothing else: no names, no roles | everyone | `won` |
| `Disconnecting` | reason: `load_deadline` (the only one today) | that player (`peer` is its subject, as `Correction`'s, although the payload names none) | right before the `DisconnectPeer` it explains: a missed loading deadline (#119, the M4 ADR's E21) |

Directives to `server/` have the audience *server* and reach no peer: `RefuseJoins`, `AllowJoins`,
`DisconnectPeer(peer)`. Built in 2b (#58): the events from `Welcome` to `PlayerLoaded` above, `ReadyChanged`,
`CountdownCancelled` and the three directives; `DisconnectPeer` follows the `Rejected` it explains, and `server/`
sends what came before it (§4, `disconnect_peer`). Built in 2g (#63): `Swung`, `Damaged` and `Died`; M4-2 (#138):
`KnockedDown`, and `Died` moved to the end of the knockdown; M4-3 (#139): `Respawned`; M4-4 (#140): `RaiseStarted`,
`RaiseStopped` and `Revived`; M4-5 (#141): `Swapped`, `TaskState` and `ItemPickedUp`'s `belted`. Built in 2h
(#64): `MatchEnded`, and `RoundStarted` is emitted (`StartClock`; the class came with 2c's deal events). 3e (#97): the
reasons `wrong_content` (E1) and `joins_closed` (E14), and `DisconnectPeer` for Loading's waiting newcomers. M4-6
(#142): `Disconnecting`, which `LeakCheck.FOR_ONE` lists by hand (§4.6.4). #647 (M7-Z1): `ZoneProgress`.

### 4.3 Wire schemas (M3 design, #89)
[ADR](decisions/2026-09-30-wire-format-and-host-session.md); built in 3d (#98): every row below is a row of
`WireSchema` (`net/messages/`), and `WireBudget` is `server/wire_budget.gd`. Each message is one row: its kind
byte (the frame header, §4 Transport), its direction (C→H: a client to the host; H→C: the host to a client), its lane,
its fields in order and its payload cap. **The field names are `core/`'s**: an intent's are the `args` its rules read
(`MatchCommand`), an event's are the keys of its `to_dict()`. So a decoded message compares equal with what `core/`
emitted, which the leak test needs (§4.6.4).

#### 4.3.1 Wire types
Little-endian; sizes in bytes.

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
| `sized_opus` | 2 + n | a u16 length, then that many opaque bytes (a `VoiceBatch` frame's, M5-4b) | 0, or over the field's maximum (500) |

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

#### 4.3.2 Intents (C→H)
Every RELIABLE intent carries `seq`, the client's own rising number that a `Rejected` names.
`Hello`'s is 0 (its layout is frozen, below). `MoveClaim` has none: a failed check gets `Correction`; nor has its
RELIABLE twin `MoveClaimReliable`, which is a claim too. A client stops
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
| 5 | `MoveClaim` | LATEST | `epoch: u32`, `client_tick: u32`, `position: vec3`, `velocity: vec3`, `facing: vec3`, flags `u8` (1 `sprint`, 2 `moving`, 4 `on_floor`; other bits 0), `jumps: u16` (below), `sprint_ticks: u32`, `moved_ticks: u32` (bit i: client tick `client_tick - i`, #155) | 55; 55 |
| 6 | `PickUp` | RELIABLE | `seq: u32`, `item: item` | 6; 6 |
| 7 | `PutDown` | RELIABLE | `seq: u32`, `facing: vec3` | 16; 16 |
| 8 | `Use` | RELIABLE | `seq: u32`, `facing: vec3` | 16; 16 |
| 9 | `ReturnToLobby` | RELIABLE | `seq: u32` | 4; 4 |
| 10 | `Raise` | RELIABLE | `seq: u32`, `target: peer` (M4-4, #140, E28) | 8; 8 |
| 11 | `StopRaise` | RELIABLE | `seq: u32` (M4-4) | 4; 4 |
| 12 | `GiveUp` | RELIABLE | `seq: u32` (M4-4) | 4; 4 |
| 13 | `Swap` | RELIABLE | `seq: u32` (M4-5, #141) | 4; 4 |
| 14 | `MoveClaimReliable` | RELIABLE | the fields of `MoveClaim` (5), in its order; no `seq`. `MoveClaim`'s RELIABLE twin (#429): the client sends every epoch's first claim on it, and its last sent claim again, exactly as sent, right before a player action (§7.1.15 Lost claims). The host hands it to `core/` as the `MoveClaim` command (`WireRow.command`), so it passes the same checks and gets no `Rejected` (E15's silent drop kept) | 55; 55 |

#### 4.3.3 Debug commands (C→H, E17)
Only in a debug build's table. `server/` takes them from the host's own client (peer 1)
only and turns each into the command it names; from another peer, or on a release host, whose table lacks the kind,
the message is malformed (§4.5). They are not intents: `core/` does not answer them with `Rejected` (§3.3 lists them
among the commands `server/` originates), and the seq only orders them in the client's log.

| Kind | Command | Lane | Fields | Bytes; cap |
|---|---|---|---|---|
| 24 | `ForceRole` (§9.4 `DealRoles`, 2j) | RELIABLE | `seq: u32`, `peer: peer` (the player whose role is forced, which becomes the command's peer), `has_role: bool`, then `role: id` when true; false clears the forced role (the command's `role` is then `""`, as `Match` reads it). `role` decodes as a `String`, not a `StringName`: `Match` reads it with `get_string`, which returns its default for a `StringName` | 19 for `dissident`; 42 |
| 25 | `ForceClock` (§9.7 `clock_s`, M4-3) | RELIABLE | `seq: u32`, `peer: peer` (the sender itself, the host's own player, as every debug kind names a player), `seconds: u16`: the length of the match clocks that `StartClock` starts from now on, in place of the `match_duration` setting's whole minutes (`MatchState.forced_clock_s`); 0 clears it, and `ResetMatch` keeps it, as a forced role | 10; 10 |

#### 4.3.4 Events (H→C)
All RELIABLE: one-off facts, and state sent only on change. `SelfStatus` is such state: on LATEST,
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
| 48 | `ItemPickedUp` | `peer: peer`, `item: item`, `belted: item` (optional: the hand item moved to the belt, M4-5, E29) | 8; 8 |
| 49 | `ItemPlaced` | `item: item`, `position: vec3`, `cause: id` | 23; 47 |
| 50 | `PackageDelivered` | `item: item`, `station: station` | 4; 4 |
| 51 | `TaskProgress` | `done: u16`, `total: u16` | 4; 4 |
| 52 | `Swung` | `peer: peer`, `facing: vec3` | 16; 16 |
| 53 | `Damaged` | `amount: s32`, `health: s32` (thousandths, §3.3) | 8; 8 |
| 54 | `SelfStatus` | `health: s32`, `stamina: s32`, `sprint_available: bool`, `claim_tick: s64` (a client tick, a u32, or -1 for none; #155) | 17; 17 |
| 55 | `Died` | `peer: peer`, `position: vec3` | 16; 16 |
| 56 | `Correction` | `epoch: u32`, `position: vec3`, `velocity: vec3` | 28; 28 |
| 57 | `MatchEnded` | `side: id` (the winning `SideSpec`'s id; audience *everyone*, 2h) | 11; 33 |
| 58 | `Disconnecting` | `reason: id` (`load_deadline`; audience *only* that player, M4-6, #119) | 14; 33 |
| 59 | `KnockedDown` | `peer: peer`, `position: vec3` (audience *everyone*, M4-2, #138) | 16; 16 |
| 60 | `Respawned` | `peer: peer`, `position: vec3` (audience *everyone*, M4-3, #139) | 16; 16 |
| 61 | `RaiseStarted` | `raiser: peer`, `target: peer` (audience *everyone*, M4-4, #140) | 8; 8 |
| 62 | `RaiseStopped` | `raiser: peer`, `target: peer`: no cause (audience *everyone*, M4-4) | 8; 8 |
| 63 | `Revived` | `peer: peer` (audience *everyone*, M4-4) | 4; 4 |
| 64 | `Swapped` | `peer: peer` (audience *everyone*, M4-5, #141) | 4; 4 |
| 65 | `TaskState` | `task: u8`, `type: id`, `done: u16`, `total: u16` (audience *everyone*, M4-5, E30) | 14 for `delivery`; 38 |
| 66 | `ZoneProgress` | `station: station`, `ticks: u16`, `needed: u16`, `counting: bool`, `tick: tick` (audience *everyone*, #647; ZE4 and ZE6 of the [zone task ADR](decisions/2026-10-09-m7-zone-task.md); `needed` is at most 12,000, 600 s) | 11; 11 |

#### 4.3.5 State and voice

| Kind | Message | Dir | Lane | Fields | Bytes; cap |
|---|---|---|---|---|---|
| 96 | `Snapshot` | H→C | LATEST | `tick: tick` (the host tick whose state it shows); `avatars: map<peer, avatar>`, an avatar being `position: vec3`, `velocity: vec3`, `facing: vec3`, flags `u8` (1 `downed`, M4-2; 2 `invulnerable`, M4-3: strikes skip the player at that tick; other bits 0), `held_item: item` (optional), `belt_item: item` (optional, M4-5). Every living or downed player's avatar, never a dead one's (§5) | 410 (9 avatars); 1024 (15 avatars: 680) |
| 112 | `VoiceUp` | C→H | VOICE | `seq: u16` (the speaker's frame counter), `opus` (one 20 ms frame, 1 to 500 bytes) | 47; 502 |
| 114 | `VoiceBatch` | H→C | VOICE | `tick: tick` (the host tick whose routing let its frames through, E11); `frames: list<frame>` (1 to 113 in practice, the cap bounds it first), a frame being `speaker: peer`, `seq: u16` (renumbered per speaker and listener, §4.5) and `opus: sized_opus` (a u16 length, then 1 to 500 bytes). One poll's frames for one listener (M5-4b, #374); each frame decodes to the `VoiceDown` (speaker, seq, tick, opus) it stands for. Kind 113, protocol 7's single-frame `VoiceDown`, is retired | 58 (one 45 B frame), 9 frames: 482; 1024 |

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
  It was 2 when M4-6 (#142) added `Disconnecting` (58), 3 when M4-2 (#138) added `KnockedDown` (59) and
  renamed the avatar's flag `downed`, 4 when M4-3 (#139) added `Respawned` (60), the avatar's flag
  `invulnerable` and the debug row `ForceClock` (25), 5 when M4-4 (#140) added `Raise`, `StopRaise` and
  `GiveUp` (10 to 12) and `RaiseStarted`, `RaiseStopped` and `Revived` (61 to 63), 6 when M4-5 (#141)
  added `Swap` (13), `Swapped` (64) and `TaskState` (65), `ItemPickedUp`'s `belted` and the avatar's
  `belt_item`, 7 when #155 added `MoveClaim`'s `sprint_ticks` and `moved_ticks` and `SelfStatus`'s
  `claim_tick`, 8 when M6-8 (#374) added `VoiceBatch` (114), 9 when #429 added `MoveClaimReliable` (14), and is
  11 on `release/m7` since #647 added `ZoneProgress` (66): `release/m6.2` already speaks 10 (#550, `Hello`'s `name`)
  with another table, so whichever of the two releases lands on `main` second meets a conflict on the constant and
  takes the next number. M4's protocol PRs each set
  it to their base's plus one at the rebase before the merge (the M4 ADR §4).
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
  `spawn`, `thrown`). An id that neither covers is a bug that the encoder refuses and logs.
- **Lossless** (E6). Every float is an `f32`, as the standard build's `Vector3` and `Color` hold it, so
  decode(encode(x)) == x and the leak test compares exactly.
- **The snapshot holds avatars only** (E3). Items and bodies change only through reliable events (`ItemSpawned`,
  `ItemPickedUp`, `Swapped`, `ItemPlaced`, `PackageDelivered`, `Died`), which the client folds into its view (§4.6.1);
  a carried item follows its holder's avatar, in the hand or on the belt (the avatar's `held_item` and `belt_item`). `core/`'s snapshot keeps items and bodies for `view_of` and the unit tests; the leak
  test compares the avatars. Prevents: a snapshot of every item and body (about 920 bytes with 10 players and 20 items)
  outgrowing the 1024-byte unreliable cap as a map gets more knives, with no way to split it, because the LATEST merge
  keeps only the last part.
- **`MoveClaim` and the jump** (E2). `MoveClaim` stays on LATEST and carries `jumps`: the number of jumps the client
  made since it adopted the claim's epoch (0 after `Welcome`, after every `Correction` and after every placement). The
  movement rule compares it with the last accepted claim's count in that epoch: a rise d ≥ 1 is one jump allowance,
  from the floor under the last accepted position (§7.1.4), and costs d times the jump cost (stamina settled first; not
  covered: `Correction`); a fall within an epoch is `Correction`. `jumps` replaces `jumped` (3e). Prevents: the LATEST
  merge keeps the newest claim of a burst, a jump in an older one is lost, and the player is corrected to the ground
  for a jump the host never saw. Accepted: a merged burst grants one jump height, because the take-off points of the
  merged claims are lost, so a player who climbed and jumped during a host freeze may be corrected once. The covered
  ticks are settled with the flags `sprint_ticks` and `moved_ticks` give each of them (#155), which hold the last
  32 client ticks (1.6 s); a covered tick older than that, after a longer freeze, takes the oldest bit.
  `MoveClaimReliable` (14) carries the same fields, so its count and masks are read the same way.
- **Sizes.** The host sends each remote player a snapshot per tick: about 430 bytes on the wire with 10 players, so
  9 × 20 × 430 ≈ 0.6 Mbit/s of upload. A client's claims are about 2 KB/s with headers. A payload over its cap is never
  truncated: the encoder refuses it and logs an error (a bug in `core/`, the content or the table). 3d's tests: every
  mode in `content/` passes `WireBudget` (above); a payload built with 32-character ids, a 255-byte map path and the
  longest shortfall of each kind encodes within its cap or is refused by `WireBudget` first; and a synthetic mode at
  the declared maxima is refused with the kind named.
- **Voice batching** (M5-4b, built in M6-8, #374; protocol 8). One `VoiceBatch` per listener per poll holds every
  frame it hears in that poll, in the relay's order (per speaker in peer-id order, each speaker's in its seq order);
  frames that would pass the 1024-byte cap start a second batch. `sized_opus` is the only Opus type that may stand
  before another field (`opus`, the rest of the payload, is a row's last field only). The client turns each frame
  back into a `VoiceDown` (`DecodedView.voice_downs`), so `voice_received` and the leak test stay per frame.

### 4.4 The codec (M3 design, #89)
- **One table** in `net/messages/` declares each row of §4.3: kind, name, direction, lane, cap and the fields with their
  wire types (E4). `NetKindTable.game()` is built from it, so a kind's lane is still declared once. A generic encoder
  and decoder walk the fields. `net/` references no `core/` class (§1): the names are strings, and a unit test in
  `tests/` checks the table against `core/`: every intent of `Intents.ALL` and every event class with a peer audience
  has a row whose fields are the intent's declared fields or the keys its `to_dict()` returns, each debug row (§4.3)
  matches the fields of the command it names (`ForceRole`'s and `ForceClock`'s, declared in `Intents.FIELDS` too), no
  row has a field that names a seed, and the table as a release build builds it (debug off) has no debug kind. The
  comparison leaves out the wire's own fields: `seq`, the presence flags (`has_map`, `has_station`, `has_role`) and the
  debug rows' `peer`, which becomes `MatchCommand.peer`, not an arg. Before 3e an intent declared no fields: its rules
  read `args` where they
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
    bytes) does not, and the snapshot's 15 avatars take 680 bytes of its 1024 (45 bytes each with its key, the belt
    item included: M4-5 rechecked it).
  - `wire_core_test.gd` compares the table with `Intents.FIELDS` (names and decoded Variant types, `ForceRole`
    included) and applies decoded `ForceRole`, `Hello` and `ChangeSettings` to a `Match`. A decoded `ForceRole`'s
    role must stay a `String`: `Match` reads it with `get_string`, which gives "" for a `StringName`, so the role
    would silently go unforced.

### 4.5 The host session (M3 design, #89)
`HostSession` (`server/`, 3f) is a `RefCounted` that owns the `Match`, the hosting transport (the host's own client
linked through `own_client_of`), the levels' collision worlds (3c, below) and the bookkeeping per peer. A thin `Node`
calls `step(now_usec)` from `_physics_process` with `Time.get_ticks_usec()`, before the own client's nodes
(`process_physics_priority`); tests and the bots runner call it with a clock of their own (§4.6). The host's own
client is a `ClientSession` on the loopback like any other (§4.6.1) and reads nothing of `HostSession`.

#### 4.5.1 Starting
(1) Load the game mode and every level it names (the lobby and the maps), build each level's collision
world (3c, below), then read the markers with `MarkerReader.read_levels` (2j) through the host's `WorldQuery`, which
`read_levels` points at each level with `use_level(path)` before reading it (3c; the flat fake ignores it). So the
`circle` markers snap to the floor the host plays on: option (b) of §10's reader question, recommended on #66. A
level with load errors stops the host with the errors shown. (2) The session seed: 8 bytes of
`Crypto.generate_random_bytes`, the operating system's entropy, never the time (§3.3). (3) `Match.new`; a refused
mode stops the host with the refusals shown. `keep_history` stays off (the bots runner turns it on). (4) Host on the
transport and link the own client, then `Match.start(0)`: host tick 0 is the session's start (hosting first, so the
start slice's `RefuseJoins` or `AllowJoins` reaches the transport).

#### 4.5.2 Host ticks come from the clock
Tick = ⌊(now − start) × `Ticks.RATE` / 10^6⌋, in microseconds. Not a count of
physics frames: Godot runs at most `Engine.max_physics_steps_per_frame` physics steps per rendered frame and drops the
rest, so after a 5 s freeze a frame count falls behind the clients' clocks for good (the M1 lesson "stamp from the
host clock and skip ticks", §7). With physics at 60 Hz (the default) a core tick falls due about every third step.

#### 4.5.3 One step, in this order (each choice names what it prevents)

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

#### 4.5.4 One outbox slice per call
`HostSession` takes `take_outbox()` after every `Match.apply` and every `Match.tick`
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

#### 4.5.5 Voice relay
The routing table holds `speakers_for(l)` for every present player l, refreshed after every
`Match.tick` call (catch-up ticks included: a catch-up that crosses Round → End must not relay under Round's routing),
so between two ticks it is the routing that `view_of` records for the last one (§5). A `VoiceUp` from speaker s goes, as
a frame (s, the stream's next seq, the bytes unchanged) of the `VoiceBatch` stamped `ticked_through()`, to each listener
l ≠ s whose entry holds s; one from a peer that is not a present player is dropped. Between two ticks the transport's word on a leave
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

The send path encodes each frame once (#245) and batches per listener (M5-4b, #374): `VoiceRelay.flush` gives one
`Outgoing` per frame with its listeners in peer-id order and each one's stream seq; `HostSession` encodes the frame's
record (speaker, seq, length, bytes) once (if any listener is reachable), gives every reachable listener a copy with its
own seq written in place in that listener's batch at the offset the schema gives (`VoiceBatchEncoder`, `WireField.fixed_offset` of the record:
the fixed sizes of the parts before it), then sends each listener, in peer-id order, its copies behind the tick and a
count in as few `VoiceBatch`es as the cap and `MAX_BATCH_FRAMES` allow, each byte for byte what `WireSchema.encode`
gives for that batch. A row change that moves the seq behind a part of varying size, or widens it, makes every copy a
full encoding (slower, never corrupt) and fails `voice_batch_encoder_test`. Tests: `tests/unit/server/voice_relay_test.gd`,
`voice_batch_encoder_test.gd` (every batch against the codec for several speakers, ticks, frame sizes and seqs, filled to
the cap and to the most frames, and through `VoiceRelay` across the u16 wrap), `tests/unit/net/messages/wire_schema_test.gd` (the offsets),
`tests/integration/server/host_session_voice_test.gd` (also a listener after one that is unreachable while the relay
still routes it: its own stream's seq, seen failing when every copy took the first listener's seq or was sent unpatched;
no public path makes such a listener today, so the test marks it by hand) and the leak test in `bots`, `bots-enet` and
`bots --chaos` (§4.6.5).

#### 4.5.6 Rate limits and malformed packets
(E7; the numbers are placeholders, "not a decision"). The accident they bound:
a client bug sends an intent every frame; every command, and every `WorldQuery` answer it causes, stays in the command
log for the whole match (§3.3), so one looping client grows the host's memory and work without end.
- Per peer, three token buckets, refilled for the host time elapsed in step 2, before the poll:
  - **voice frames** (`VoiceUp`): 500, refilled at 50 per second (one 20 ms frame each); the relay's newest 5 per
    speaker per poll bounds a backlog further;
  - **reliable intents**: 100, refilled at 20 per second; `MoveClaimReliable` is one of them (#429): reliable
    twins are never merged, so this bucket, not the bytes, bounds what they put in the command log;
  - **bytes** of every other message (the reliable intents and `MoveClaim`): 64 KiB, refilled at 16 KiB/s.

  An honest client sends about 50 frames, a few intents and about 1 KB of claims per second, so each bucket holds
  more than 10 s of it (a twin before each player action doubles what an action costs, and each `Correction` costs
  one twin, so 10 actions a second, or a correction on every claim (20 a second), is where an honest client would
  meet the bucket):
  a thawed peer's burst passes (the 5 s freeze of #21, and `MAX_TICK_CREDIT`'s 10 s). Voice has
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

#### 4.5.7 The host's counters
(debug builds only; the M5 ADR's E47 as amended, its §3 item 11 and §4; built in M5-4,
#218). `HostNode.counters()` gives the budgets' and the codec's counts (`over_budget`, `bad_payloads`,
`malformed_disconnects`), which the F3 overlay may show at any time; its `over_budget` leaves out the voice frames
over budget (`HostSession.over_budget_but_voice()`), which only the relay's counters give. The voice relay's are apart:
`HostSession.relay_counters()` (and `HostNode.relay_counters()`) gives, as totals since the session started,
`voice_relayed` (frames of present players the relay passed on, after the newest 5 per poll, heard or not),
`voice_sent` (frames the transport took, one per listener a frame went to), `voice_batches` (the `VoiceBatch`es that
carried them: the sends), `voice_dropped` (a backlog's old part), `voice_over_budget` (of
`over_budget`, the frames over a speaker's voice bucket), `voice_relay_usec` (`Time.get_ticks_usec` around a poll's
flush, encoding and sends, in polls that held frames), `voice_send_usec` (around each `VoiceBatch`'s `send` alone),
and the upload apart: `voice_up_*`, `snapshot_up_*` and `other_up_*` bytes and datagrams, with `snapshots_sent` and
`session_ms`. `RelayMeter` (`server/relay_meter.gd`) keeps them; a release build has none. The upload comes from
`NetTransport.take_upload()`, taken before and after the voice sends and the snapshot sends: `EnetTransport` pops
ENet's host statistics (`ENetConnection.pop_statistic`, sent data and datagrams, ENet's headers included, IP and UDP
not), and Godot 4.7.2's `put_packet` flushes, so each send is one datagram at once and each part gets exactly what
went out during it (events, and acknowledgements and pings sent while polling, count as other; one that rides in a
datagram a send flushes counts with that send); the loopback counts the frames sent to linked peers, a stand-in for
the tests; the host's own client never counts. The F3 overlay shows the relay's
counters only while the client's own copy of the phase has the class `LobbyPhase`, `CountdownPhase` or `EndPhase`
(`DebugOverlay.shows_relay`; any other phase class, a later one included, shows only a note): live during a Round they
would tell the host's player how many hear them (`voice_sent` rising by one per frame says exactly one unseen player
is within 8 m). The bots runner's ENet host prints them every 5 s and at the end of its run (`RelayReport`, §4.6.3).
Tests: `tests/integration/server/host_session_counters_test.gd` (with `HostNode.counters()`'s `over_budget` leaving out
a voice frame over budget, seen failing with the session's `over_budget`), `host_node_test.gd`,
`tests/unit/net/transport/loopback_transport_test.gd`, `tests/integration/net/enet_host_and_two_clients.gd` (ENet's
datagrams counted at once), `tests/unit/client/ui/debug_overlay_test.gd` and
`tests/integration/client/player/player_network_test.gd` (a host `Game` shows them in the lobby and none in the
round).

#### 4.5.8 Loading a level and `LoadAck`
- **Clients**, the host's own included: on `LoadMatch` a client loads the map only if its own copy of the mode lists
  that path (never a path from the wire alone), with `ResourceLoader.load_threaded_request` and a
  `load_threaded_get_status` check every frame, so its transport keeps polling while the level loads. It instantiates
  the scene, replaces the lobby and sends `LoadAck(match_id)`. A failed load leaves the session with a message; the
  host's own failed load ends the session (§3.2). On the host, instantiating the scene blocks the main thread it shares
  with `HostSession`; the next step's catch-up covers the pause like any host freeze.
- **The host's collision worlds** are built when the session starts, so loading asks nothing of `server/`: the host's
  own `LoadAck` means that its client loaded, and `WorldQuery` already answers for every level.

#### 4.5.9 `WorldQuery` over the host's own worlds (3c; §7.1)
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
  ledge's edge stands on the ledge (§7.1.5's note). Prevents: a package put down within a capsule radius of a low ledge
  resting at the ledge's height beside it, which the delivery check reads (§7.1.14), so the same drop counts or not by the
  ledge. `rest_position(a, b)`: a ray from a to b, stopped 0.2 m (a placeholder) before
  the first hit, then `floor_below`. `sweep(a, b, r)` (37a, #641; TE2 of the throwing ADR): a sphere of radius r,
  first `intersect_shape` at a (a `PhysicsShapeQueryParameters3D` holding a `SphereShape3D`, mask of layer 1), which
  answers a when it finds anything, since `cast_motion` ignores a shape the sphere starts in; then a plus the segment
  times `cast_motion`'s safe fraction (b when nothing is in the way; an r of 0 or less is the ray's hit). Jolt finds a
  sphere touching a box clear and one 1 mm into it overlapping (`host_world_query_sweep_test.gd`), so
  `WorldQuery.THROW_RADIUS_MARGIN_M` is 0.01 m: a throw radius at most `min(capsule_radius_m, capsule_height_m -
  eye_height_m)` less it leaves the sphere at a pressed capsule's eye clear of the wall or ceiling (a technical
  constant, not a game number). `core/` records every answer in the command log (§3.3).
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
  (`hit_from_inside` is off: sight from inside a wall is clear, within §7.1.9's limit that the host does not check walls),
  and one that starts exactly on a surface may miss it, so callers ask from a little above the point, as `core/` does.
  `MarkerReader.read_levels` calls `use_level(path)` before reading each level. Tests: `tests/integration/server/`
  (fixture levels with a wall, a ledge and a low crate in `tests/fixtures/levels/`, a package put down beside the ledge
  through a `Match`, and 2j's flat levels).

#### 4.5.10 The command log and replays (E13)
The host keeps the log in memory (§3.3). A debug-build host writes the session's
log to `user://replays/` when the session ends (never after each match) and keeps the last 10: the log holds the session
seed, from which every later match's seed is derived (§3.3), so a log written after match 1 would let the host's human
or agent, debugging mid-playtest, replay it and read every role of match 2; the bots runner writes a failed scenario's
log next to its report, so `Match.replay` reproduces the failure with the same build and content (3f adds `CommandLog`'s
reading back). The log holds the seed: it stays on the host's disk and is never sent (§5). A host started from a task
worktree writes into that worktree's own `user://` (#182, `docs/AGENT_WORKFLOW.md` §11.18), not the main checkout's.

#### 4.5.11 A failed deal is fatal
(the engineer's answer on #90, item 2, 2026-09-30). `core/` has no guard for a deal that
cannot complete: a `Delivery` deal that could not place its packages or circles logs a match error
(`Match.record_error`, kept in `Match.diagnostics`) and the round starts anyway, with no tasks, which every task done
turns into an instant crew win (§3.4). Which row deals, and which phase it enters, is the game mode's data (invariant
5), so `server/` keys on neither: `Match` counts the errors recorded while a transition row runs (its actions and
the exit, `Match.row_error_count()`, built in 3e, #97), and `HostSession` reads the count after every `Match.apply` and `Match.tick` call.
A new one ends the session with that error shown to the host's human, before that call's slice is delivered (above).
So any row whose actions fail is fatal, a deal or not; an error outside a row, such as a `ForceRole` naming a role the
mode lacks in the same host tick, is logged and the session goes on. The bots runner already fails a scenario on any
match error (§9.7). 3f tests it with a fixture mode whose deal logs an error.

#### 4.5.12 Ending
The host quits, its own client's load fails, or the deal fails (above): `close()`, and every client sees
`host_lost` (#40).

#### 4.5.13 Built in 3f (#100)
The API that 3h and 3i use; the rest is in `server/CLAUDE.md` and the class comments.
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

#### 4.6.1 `ClientSession` (`client/net/`, 3g)
Is what every client runs: the host's own over the loopback, a remote one
over ENet, and every bot. It decodes each message (§4.4) into a **decoded view** shaped like `core/`'s `PeerView`
(§5): the events in order as (name, fields), the snapshots by tick, the voice frames as (speaker, tick, bytes). From
it, it keeps what a player may know: its peer id and epoch, the phase, the roster, the settings; the items, stations,
bodies and each player's life folded from the events (cleared on `LoadMatch` and on entering the lobby); the
avatars of the newest
snapshot; its own `SelfStatus`. It sends `Hello` on `connected`, intents with a rising `seq`, one `MoveClaim` per
client tick (20 Hz) with its epoch, client tick and jump count (the first of each epoch, and the last one again
right before a player action, on its RELIABLE twin `MoveClaimReliable`, #429), and `LoadAck` after loading. It
never reads `core/`
state (invariant 2).
Built in 3g (#101) as `client/net/`: `ClientSession`, `DecodedView` (the record, in `PeerView`'s shape) and
`ClientModel` (the fold). What the build pinned:
- The owner calls `step(now_usec)` every frame, like `HostSession`: it polls the transport, advances a threaded load
  and sends the claim that is due. The game's `SessionNode` gives it the physics steps run as its clock (the
  physics step divided by 3), not the real clock: catch-up steps after a hitch would put 4 or more physics steps
  of travel in a claim of one client tick, past the crawl's allowance. So the client tick follows physics steps
  on purpose, and `SessionNode` checks that the physics rate is a multiple of `Ticks.RATE`. After a hitch longer
  than Godot's catch-up (8 steps a frame) the steps would trail real time for good, and the host's stamina ledger
  with them (the next sprint-jump would settle phantom sprint ticks and be refused): right after a claim went
  out, steps trailing the real clock by 3 or more jump forward by whole client ticks, and the next claim covers
  those ticks with one tick's travel (M4-9, the netcode review of PR #154; `session_node_test.gd`). While the
  client sends no claims (`claims_accepted()` false: before the Welcome, in Loading, while dead) the steps are
  re-synced the same way before every step, since its next claim follows a placement, whose credit
  (`TICK_LEAD`) a jump after the first claim would overrun (M4-9's netcode review). The client
  tick counts `Ticks.RATE` ticks from the first step; a step sends at
  most one claim, so after a freeze one claim carries the newest client tick. The mover gives the claim's motion
  (`set_motion`, `count_jump`; `set_facing` for a turn outside its physics step, the respawn's level look, #191)
  and adopts each `Correction` (the `corrected` signal); `Welcome` and `Correction`
  reset the jump count and put the claims at the host's position.
- A client claims when its own copy of the current phase accepts `MoveClaim` from it: a player, living or downed
  by its own life fold, and the host's own player as peer 1 (`AcceptSpec.From`); never while dead, whatever the
  phase accepts (the dead send no intents). Before `Welcome` it claims nothing.
- It ends (`ended(reason)`, the transport closed) on a `Rejected` before `Welcome` (its reason), `host_lost`,
  `connect_failed`, `unknown_map` (a `LoadMatch` map its own mode does not list), `load_failed` and `left`; since
  M4-6 (#119) a `host_lost` after a `Disconnecting` ends with the `Disconnecting`'s reason (`load_deadline`).
  `EndReasons` (`client/app/`) says each in words.
  `map_loaded(path, scene)` fires before `LoadAck` goes out, so its owner instantiates the scene in the handler; a
  bot (`load_levels` off) checks the map and acknowledges without loading.
- "Entering the lobby" is entering a phase whose level is the lobby from one whose level is not (End to Lobby): the
  model then clears a match's facts (items, stations, bodies, loads, role, teammates, tasks, the winner and the
  avatars), as on `LoadMatch`, and keeps the roster and the settings. It then folds no snapshot of a host tick at
  or below a floor (#251): the host tick estimated at the change (`host_tick_now`, which `AvatarViews` sets to its
  `host_tick()`; a bot has none) or the newest snapshot held, the higher. A round snapshot sent before the
  `PhaseChanged` (unreliable lane) can arrive after it (reliable lane), usually newer than every snapshot held
  (tick T-1 delayed past the change of tick T), so the newest held alone does not reject it, and the wire carries
  no tick of the change (`PhaseChanged` has `phase` and `end_tick`; the engineer chose no wire change). The host
  tick runs on across matches, so the floor never holds back a later match's snapshots.
- The decoded view is recorded only with `keep_history` on (off by default, like `Match`'s: 12000 snapshots in a
  10-minute match); the bots and the leak test turn it on. The model is always kept. A decoded voice frame costs
  about 250 B there (measured with M5-1's 30 to 60 B frames, #215): the four bots of `crew_delivers_every_package`
  keep about 1 MB over its 25 s, but ten bots each hearing nine talkers for 10 minutes would keep 0.4 to 0.7 GB
  (talk spurts to continuous), so bot scenarios stay short.
- `Hello`'s content hash is `ContentFingerprint.of(ContentHash.of(mode), mode.lobby_level, mode.maps)`
  (`net/messages/`), which #100's host computes the same way. It takes the mode's parts, not the mode: `net/` names
  no `core/` class (a test pins it). Each level's file and every scene and resource it reaches are hashed (§4.3).
- The model keeps its own copy of a snapshot's avatars: the view records the decoded one unchanged. A threaded load
  the session no longer waits for (it ended, or a newer `LoadMatch` came) is collected by `step()` once done.
- Tested in `tests/unit/client/net/` against host messages encoded with the codec from `core/`'s own events over a
  `LoopbackHub`; the end-to-end tests against `HostSession` are 3f's (#100,
  `tests/integration/server/host_session_end_to_end_test.gd` and its siblings), the bots 3h's.

##### 4.6.1.1 The life fold (E25, M4-2 #138)
`ClientModel.life_of(peer)` is living unless a `KnockedDown` (downed), a
`Died` (dead, with its body) or a `PlayerLeft` (left, its body removed, E26) of this match said otherwise, and no
`Respawned` (living again, its body removed; M4-3 #139) or `Revived` (living again where it lay; M4-4 #140)
undid it; `raiser_of(peer)` and `raised_by(raiser)` follow the raises (`RaiseStarted` until `RaiseStopped`,
`Revived`, a leave of either or a new match; M4-4); `is_invulnerable(peer)` reads the newest
snapshot's avatar flag (the own player's never arrives);
`is_alive(peer)` is `life_of(peer)` living. `ClientModel.Life` is the client's own enum, so no `client/` file
names a `core/` state class. Tests: `tests/unit/client/net/client_model_test.gd` and
`client_session_claims_test.gd` (a dead client stops claiming even where every player may).

##### 4.6.1.2 The slots and the tasks (E25 for M4-5, #141)
Each `ClientModel.Item` holds its holder and whether it is
`belted`, from `ItemPickedUp` (the picked item to the picker's hand, its `belted` item to its belt), `Swapped`
(the swapper's two items change places) and `ItemPlaced` or `PackageDelivered` (resting); `hand_item(peer)` and
`belt_item(peer)` read them for every player, the own one included, whose avatar never arrives. `TaskState`
fills `tasks` (task id to its type's id, done and total: the task screen's rows, E30); a new match clears them.
`ZoneProgress` (#650, the zone task ADR's ZE8) sets its station's `ticks`, `needed`, `counting` and `progress_tick`
(the event's host tick), and `done` once `ticks` reaches `needed`, as `PackageDelivered` sets a circle's; nothing
else changes them (no prediction). Tests: `client_model_test.gd`.

#### 4.6.2 Bots (`tests/harness/`, 3h)
A bot is a `ClientSession`, a scenario script and an honest mover. The script is the
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
listener also checks that the relay changed no frame and named the right speaker. **Since M5-1 (#215)** it sends
like a player's gate (the M5 ADR §5): one frame per 20 ms of the runner's clock (50 a second, E38), each 30 to 60 B
with the peer id and the counter first (`LeakCheck.voice_frame`), in talk spurts by default (`BotVoice`: a spurt of
0.8 to 1.7 s, then a silence of 0.3 to 0.9 s, both lengths and the start shifted per bot; placeholders, "not a
decision"), so every scenario starts and stops streams; continuously when the scenario's `voice` says so (§9.7),
the load M5-4's `voice_load` measures. After a hitch of the clock at most the newest 5 frames go out at once (the
relay's newest 5 per poll). It talks in every phase and life state, as a modified client may: the host must route
none of it where nobody hears it (§6), which the leak test checks. The perf harness (§9.7) talks the same way, so
its voice numbers from before M5-1 (20 frames a second of 8 to 14 B) do not compare with later ones.
**Built in 3h (#102)** in `tests/harness/`: `ScenarioPlay` holds the steps and the runner's hooks (send, connect,
claim, travel, jump, leave, answer a load, stand); `ScenarioRunner` (core) and `NetPlay` (network bots) supply
them; `ScenarioPeers` is each runner's map. In `bots/`: `BotClient` (a `ClientSession` that holds its automatic
`LoadAck` back while the bot's step is `LoadAck`, since a bot loads no scene and would acknowledge at once, and
with `hold_claims` its `MoveClaim` until its bot moved, #284),
`BotsRunner` (one process), `BotsEnet` (one instance over ENet), `LeakCheck`, `BotWatcher` (the lurker and the
refused bot), `ViewFile` and the entry `bots_main.gd`. What the build pinned:
- A network bot's intent reaches `Match` one host tick or so after the core runner's would (the host reads it in
  its next step), so a step's timing differs by that much between the runners; the six MVP scenarios pass in both.
- The mover claims one client tick of travel per client tick. Since #284 the bots runner and the ENet runner
  (`NetPlay.claims_after_moves`) poll every client, let the bots act and move, and only then claim
  (`BotClient.hold_claims`, `claim_clients`): a walk advances by the client ticks since the bot's last move or its
  client's last claim, the later, which is exactly what that frame's claim covers (one tick after a `Welcome` or a
  placement, and a walk of more than one tick walks instead of sprinting: the predicted stamina pays for one).
  Standing, it claims where it stands with no velocity. Until #284 every client claimed as it polled, before its
  bot moved, and the bot then advanced by every client tick since its last move: after a stall of the process
  the next claim covered one client tick or a few and carried the stall's travel. On a loaded machine
  (`bots-enet` beside 32 busy loops on 16 cores) 0.45 m walked in a claim of one client tick against 0.275 m
  allowed, or 0.15 m crawled against 0.056 m (one tick) and 0.111 m (two), and the host rightly corrected an
  honest bot (7 of 12 loaded runs, 2026-10-04). The chaos runner, a `BotsRunner`, claims after the moves too (its
  hostile acts after the honest claims of the frame went out, as before). The perf and playcheck runners keep
  claiming as they poll, so their bots move one client tick at most per frame (a stall slows them down).
  `tests/scenarios/bots_stall_test.gd` stalls the one-process runner's clock (`BotsRunner._frame_usec`) in the
  middle of a walk (60 ms to 1.5 s: no correction; 120 ms and more corrected before the fix), and pins the
  accepted limit of §7.1.5: a stall right after the first claim of an epoch costs nothing up to `TICK_LEAD` (0.5 s)
  and corrects the bots once past it. `tests/scenarios/bots_enet_test.gd` covers the ENet runner's start below.
- Bot 1 sends the `ForceRole`s once it knows the peer of every bot that joins at the start, then the setup's
  `ChangeSettings`, as the core runner does at tick 0; a later joiner's `ForceRole` goes once it connected.
- Over ENet bot 1 takes its first step only once every bot that joins at the start is in its lobby (their
  `PlayerJoined`), as both one-process runners join them all before the first tick; a remote bot that joins at
  the start and whose join failed unanswered (`connect_failed` after `EnetTransport.JOIN_TIMEOUT_MS`) joins again
  (that instance logs `joins again`). Under load an instance's process can start seconds before or after the
  host's: until #284 a bot gave up on a host that was not listening yet and sat out the run, and bot 1 readied
  alone, so the round started without the others (a lone dissident wins at once) or a late joiner cancelled the
  countdown after bot 1's Ready (3 of the same 12 runs). Only a join that failed half of `JOIN_TIMEOUT_MS` or
  more after it started is tried again: a host that refuses a join answers at once, before the admission with
  `connect_failed` within a poll or two (§4 "Joining") and after it with `host_lost` (a rejected `Hello`), and
  both stay failures. A join `_join_again` does not join again is lost for good (`NetPlay._lost_join`, #483): its
  bot's step fails at once, naming the reason it ended and those of its earlier joins; a remote bot then writes its
  view file with that line at once, and the host reports it as that bot's failure when its own time limit ends
  the run (it reads the view files only then). A runner that
  never calls `_join_again` (`PerfRun`) joins nobody again, so every lost join of it fails at once. Since #318 both
  live in `NetPlay` (`_lobby_full`, `_join_again`) and the chaos run's ENet
  variant and the playcheck bots use them too (below and §4.7's `playcheck`): `_lobby_full` asks of one bot that
  every other player that joins at the start has a known peer id and is in that bot's decoded lobby (its
  `Welcome`'s positions or a `PlayerJoined`); peer ids alone, which `connected` gives before the `Hello` is
  admitted, were the weaker gate those two runners had. `_join_again` judges a join on `_join_clock_usec()`,
  the runner's clock, the real one in a runner on a simulated clock (the chaos run): `JOIN_TIMEOUT_MS` is real
  time. Tests: `tests/scenarios/chaos_enet_start_test.gd` and `tests/scenarios/playcheck_bots_test.gd`, each the
  gate (peer ids alone fail it), a rejoin after an unanswered join and none after a join refused at once; the
  chaos one also drives `play_frame` and the lobby reason of a run out of time. Beside 32 busy loops on 16
  cores (2026-10-04) `bots --chaos --enet` passed 10 of 10 runs, and `playcheck spectate` 18 of 20: its bots
  played in all 20, and both reds were a window that did not exit within `hostjoin`'s 10 s grace after the
  stop (#354; since then a window gets 30 s, §4.7's `playcheck`).
- `ScenarioBot` matches a `peer` field of an event for one peer whose payload names none (`RoleAssigned`,
  `Damaged`, `SelfStatus`, `Correction`, `Rejected`) against the bot that received it: it is that event's subject.
- A bot the host disconnects (`core/`'s `DisconnectPeer` in the core runner, its session's end in the bots runner)
  acts no more, but the `WaitFor` and `Expect` steps left in its script are checked on what it received, and any
  step still left fails (M4-6): so `dropped_at_the_loading_deadline`'s third bot waits for its
  `Disconnecting(load_deadline)`, which arrives just before the disconnect.

#### 4.6.3 The runners (§9.7; E12)
- `tools\run.cmd bots [scenario ...]` runs every scenario in `content/scenarios/` but the measurements
  (`BotScenario.measurement`, M5-4's `voice_load`), or those named, in one headless process over `LoopbackHub`: a
  `HostSession` with `keep_history` on, bot 1 its own client, the others loopback clients, all stepped by a
  simulated clock (60 steps per simulated second) as fast as the machine runs. A 10-minute scenario takes seconds
  and runs the same every time.
- `--instances N` runs one scenario over ENet on 127.0.0.1, on a free port as `verify`'s `enet` step: instance 1
  hosts with bot 1, instances 2 to N run one bot each, on the real clock. Each bot writes its decoded view and its
  peer id to `tools/out/bots/<scenario>/bot-<i>.bin` when its script ends (`FileAccess.store_var`: a local file,
  lossless, not the wire); the host waits for them (up to the scenario's time limit) and compares. The host prints
  its relay counters (§4.5 "The host's counters") every 5 s of the run and every total at the end, in instance 1's
  log (`tools/out/logs/run/bots_main-1.log`): the frames sent and the `VoiceBatch`es carrying them per 20 ms, the
  relay's microseconds per 20 ms and per send (a batch), the send alone, and the upload in Mbit/s on the wire (28 B of IP and UDP added per datagram), voice,
  snapshots and the rest apart (`RelayReport`, M5-4).
- The one-process `bots` joins `verify` after `freeze` and `stall`, and so CI (every scenario: about 8 s with the six
  MVP scenarios, a few seconds more with M4-3's respawn scenario);
  the ENet run joins it too as `bots-enet`: `dissident_kills_the_crew` with 3 instances took 18 s (2026-10-01).
  M4-2 (#138) rewrote that scenario to knock both crew bots down, let them die and end by time up in a one-minute
  match (the shortest `match_duration`), so it took about 67 s. M4-3 (#139) brought it back under a minute
  without changing what it proves: the scenario forces a 40 s clock (`clock_s`, the debug command `ForceClock`),
  so it still knocks down, kills and ends by time up over ENet, in about 48 s; its 55 s time limit fails a run
  whose ForceClock was lost (the 1-minute clock). With M5-1's voice (50 frames a second in spurts, #215) the
  one-process run of the 14 scenarios took 34 to 51 s on the engineer's machine while other worktrees ran their
  checks (25 s before M5-1 on the same busy machine; the runner's limit is 300 s), and `bots-enet` 48 to 49 s
  (2026-10-03).
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

#### 4.6.4 The information-leak test (§5)
Compares what each bot b decoded with `view_of(b)`:
- events: b's decoded events are `view_of(b)`'s, in order, as (name, `to_dict()`); for a bot that left, a prefix;
- snapshots: each decoded snapshot's avatars equal the avatars of `view_of(b).snapshots[tick]`; a tick that `view_of`
  lacks is a leak (a subset check, because LATEST may drop), and so is a second snapshot of one tick
  (`DecodedView` keeps it apart, `repeated_snapshots`, instead of overwriting the first);
- voice: each decoded frame's speaker is in `view_of(b).speakers[tick]` for its tick (a subset check); and, apart
  from the voice rule, the distance invariant (M5-1, #215, below and §5). Since protocol 8 every frame arrives in a
  `VoiceBatch` and is checked as the `VoiceDown` it stands for; a batch with no frame fails too (M5-4b, #374: proven
  with a planted relay that batched a frame to listeners whose routing lacked its speaker, seen failing in
  `voice_beyond_the_radius` with "voice of 2 under tick 124, which view_of does not allow", then reverted);
- what only one process can promise (#115's review): the host sends one snapshot per peer per step and every
  client polls once per step, so no transport of a bot or watcher may count a superseded LATEST message
  (`latest_superseded`); else a snapshot sent *before* the bot's own in the same step would be dropped unseen.
  Over ENet only the host's own in-process bot is held to it (a remote bot's real network may bunch two
  snapshots in one poll). And each speaker's `VoiceDown` seqs, by tick, run 0, 1, 2, ... without a gap (wrapping
  at 65536), across the silences of the bots' talk spurts too (M5-1): the relay renumbers per speaker and listener
  and the loopback loses nothing, so a relay that forwards the speaker's own seq (how long it talked to others)
  fails. Every runner also fails on a packet its transport rejected or a message that did not decode (over ENet,
  bot 1's over its whole run), and the one-process runner on a message the host counted over budget or a packet
  the host's transport rejected;
- peers that are not players: every scenario also runs a **lurker**, a bot that connects in Lobby and never sends
  `Hello`, and one **refused** bot (`wrong_version`). The lurker decodes nothing and the refused bot exactly its
  `Rejected`, which is `view_of` of each; neither decodes a `Snapshot` or a `VoiceBatch`, even an empty one. The runner raises the hello
  deadline (a `HostSession` setting) for the lurker, so it stays connected through the lobby's and the countdown's
  events, snapshots and voice until the entry into Loading disconnects it (E14): a lurker that lost its connection
  with no `DisconnectPeer` of `core/` (a hello deadline, a dropped transport) fails, and so does one whose
  `DisconnectPeer` came at a tick with no `LoadMatch` (core/ cutting newcomers off before they saw anything). The
  refused bot must decode exactly one `Rejected` (`wrong_version`) and be disconnected by `core/`, and a watcher
  `core/` disconnected that is still connected fails (`server/` did not carry it out). A watcher that never
  connected fails with why: its `connect_failed` reason ("connect_failed, reason service_unreachable", `host_unreachable`,
  ...; "the backend gave no precise reason" for ENet and the loopback) or "still joining when the run ended" (#483).
  Prevents: a `server/` refactor that sends *everyone* events, snapshots or voice to the transport's peers instead of
  `core/`'s recipients, which the entitlement ADR rejected because it reaches peers that are not players, passing a
  test in which every bot is a player within one tick;
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
  downed bot hears only the living and a dead bot nobody; no bot decodes a frame of a speaker farther away than the
  hearing radius of the phase at the frame's tick (`VoiceRule.radius_of` the mode's rule for it), between the two
  last accepted positions after that tick, which `LeakCheck.record_tick` records per tick with the radius, in 3D,
  compared as `VoiceRule.within` compares them (`ScenarioInvariants.distance_problem`: the distance squared
  against the radius squared, written again, never a call of the rule), and none under a radius of 0; a tick it
  never recorded or a speaker that was not present then fails too (the distance invariant, M5-1, #215, E45: the
  relay stamps a frame with the tick whose routing it used, refreshed right after that tick from the same state,
  so bots exactly 8 m apart, as the greybox's spawns put them, pass); every event a bot decodes while dead is for
  it alone (the subject check) or also reached every living peer present then, so nothing reaches only the dead
  (M4-2, the recipients from `Match.emitted()`, which each bot's decoded events are checked against); the bots
  present for a whole round decode the same task events; no decoded message has a field that names a seed; a peer
  that is not a player decodes at most the `Rejected`s of its own intents; one that sends nothing (the lurker)
  decodes nothing. `keep_history` costs memory (§5), so scenarios stay short, or 3h compares per tick over a
  window and drops what it compared.

##### 4.6.4.1 Proven once (3h)
Inject a leak that the comparison catches (`server/` sends every `RoleAssigned` to everyone),
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
**M4-5 (#141)** added `TaskState` to the task events every bot decodes alike (`LeakCheck.TASK_EVENTS`:
`StationPlaced`, `ItemSpawned`, `PackageDelivered`, `TaskState`, `TaskProgress`; also `ScenarioInvariants.TASK_EVENTS`), and
planted `TaskState` declared to the living only (`Audience.of_life(ALIVE)`): `bots
crew_downed_before_a_delivery`, where a crew bot is downed before another delivers, failed on
`ScenarioInvariants` (`TaskState reached [1, 2], not every present player [1, 2, 3]`), with `TaskState` out of
its `TASK_EVENTS` on `LeakCheck` alone (`bot 1 and bot 3 decoded different task events in match 0`), and with it
out of both lists passed: the check sees the plant only through a bot that is not living as a `TaskState` goes
out (at the deal everyone is). The bots' network runner had a bug that scenario's sibling found: a bot that
stood erased its last move tick, so a `WalkTo` after a step answered within the walk's last client tick claimed
two ticks of travel in one and was corrected (`two_handed_pickup_with_a_full_belt`, seed 455000000007); standing
now keeps the walk's own client tick (`NetPlay._stand`), and a dead bot keeps none, so its first walk after
`Respawned` claims one tick, not its whole death (`crew_walks_after_a_respawn`).
**#647 (M7-Z1)** added `ZoneProgress` to both `TASK_EVENTS` lists; its plant (declared to the zone's first player
inside only) waited for a scenario that plays zones (M7-Z3, the [zone task ADR](decisions/2026-10-09-m7-zone-task.md)
§7). **#649 (M7-Z3)** planted it (`ZoneProgressEvent.audience()` as `Audience.only` of the first living player
`ZoneTask` counted in the zone): `bots crew_works_every_zone zone_paused_by_a_knockdown dissident_works_a_zone_alone`
and the core runner's `scenarios_test.gd` failed on `ScenarioInvariants` alone (`invariant at tick 118: ZoneProgress
reached [2], not every present player [1, 2, 3]`; every MVP scenario, which bans the zone task, passed); with
`ZoneProgress` out of `ScenarioInvariants.TASK_EVENTS` and `crew_works_every_zone`'s dissident waiting for
`TaskProgress` instead (so every script ends and the leak test runs), `LeakCheck` failed on its own (`bot 1 and bot 2
decoded different task events in match 0`, besides `decoded ZoneProgress, an event for one peer with no int
peer`). Reverted.
**M5-1 (#215)** planted `RoundVoice.hears` ignoring its radius (every present living speaker heard at any
distance, `hearing_radius_m()` still 8): `bots voice_beyond_the_radius` failed on `ScenarioInvariants`
(`invariant at tick 125: peer 1 hears 2 from 8.130 m, beyond the phase's hearing radius of 8.000 m`, and peer 2
hearing 1), and with that check switched off on `LeakCheck` alone for both bots (`it heard 2 at tick 125 from
8.130 m`, 67 and 76 frames beyond the radius), with no routing failure: `view_of` reads the same rule; then
passed with the plant reverted. The plant stays as a test: `bots_runner_test.gd` plays the scenario under
`FixtureRoundVoicePastItsRadius` (ScenarioInvariants fail; with them left out, through the runner's
`_check_invariants` hook, LeakCheck fails both bots while `view_of` allows every frame decoded), and
`scenario_runner_test.gd` in the core runner. They also see the distance checks fail on a planted frame or
routing beyond 8 m, in 3D, under a radius of 0, on a tick never recorded and from a speaker not present, and agree
with `VoiceRule.within` a few float steps either side of the edge (a comparison through a 32-bit `distance_to`
fails that sweep).

#### 4.6.5 Chaos bots
(#188; item 6 of the [AI productivity ADR](decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md),
P11): invariant 1 (the host validates every intent) against what a modified client can send, in
`tests/harness/chaos/`. `ChaosRun` is a `BotsRunner` whose match (`ChaosScenario`, built in code: four bots, the
default draw of one package and one zone since #649; bot 4 walks into the zone and freezes, bot 1 then knocks it
down, bot 2 delivers and bot 3 holds the zone) carries two chaos peers that are never peer 1: a
**hostile but valid** player, bot 4's own connection (`ChaosHostile`), which plays the whole round as living,
downed and (`--long`) dead, and stays under the malformed limit; and a **malformed** peer (`ChaosMalformed`)
that never sends `Hello`, so it is in no rule and invisible to the players (§3.2), until the host disconnects
it. Each peer's inputs come from a seeded `RandomNumberGenerator`; one rule per input class, each from the
sections named:
1. malformed frames (too short, too large, an unknown kind, random bytes behind one, the wrong direction or lane,
   a payload over its kind's cap, truncated, trailing bytes) and payloads the codec rejects (a bool not 0 or 1,
   item 0xFFFF, peer 0, a NaN or infinite float, unknown flag bits, a capital in an id, bytes after the last
   field, an empty Opus frame), and `ForceRole` (kind 24) and `ForceClock` (kind 25) from a peer other than 1: counted under the reason
   `ChaosFrames` names (§4 Transport, §4.3, §4.4, E17), with no reply; no role changes (the forced roles hold);
2. a burst past the reliable-intents bucket (130 refused intents in one frame) and past the voice bucket
   (530 frames): `OVER_BUDGET`, no reply, no disconnect (§4.5);
3. the malformed peer: disconnected at the 50th malformed message within 10 s, with exactly one log line naming
   it (`ChaosLog`, a `Logger`), what it sent after it in that poll counted `UNKNOWN_PEER` (§4, §4.5);
4. well-formed intents the phase or the rules refuse (§3.1, §3.2, §4.1; never one a race could turn into an
   action): exactly `Rejected(seq, reason)` to the sender, nothing else emitted, no reject counted, the reason
   `ChaosOracle`'s, written from §3.2's table, not from the code: `not_accepted` for the wrong phase or life
   state, `unchanged`, `unavailable`, `empty_hand`, `nothing_to_do`, `nothing_to_swap`, `not_channeling`,
   `not_downed`, `out_of_reach` (a `PickUp` of an item resting more than 8 m away, half of them right after a
   claim that teleports the hostile next to it: reach is measured from the host's last accepted position, §7.1,
   §9.4), and no reply to a `LoadAck` of another match;
5. hostile `MoveClaim`s (a teleport, a speed over the cap, a client tick past the credit, jumps 65535 where it
   stands, another epoch, a client tick that does not rise; NaN and infinity are class 1 on the wire), each with
   the per-tick masks (protocol v7, #155) of a client that walked every tick (`sprint_ticks` 0, `moved_ticks` all
   ones: `ChaosFrames.HONEST_MOVED_TICKS`), so the shape alone calls for the answer (a mask outside the u32 the
   encoder refuses, and core corrects; bits older than the covered ticks count for nothing: both
   `movement_rule_masks_test.gd`, not chaos shapes): a `Correction` (its epoch plus one, the old position) to
   the sender alone when the phase takes its claims and the epoch is its own, else nothing (§7.1, E15); the
   position never changes; never `Rejected`. A repeated client tick right after a placement is the first claim of
   a new baseline, checked as one tick and corrected: either answer passes. **The freeze** (#649, the zone task
   ADR's freeze row, ZE10): bot 4 stands in the zone a second, then its client sends no claim for 200 ticks while
   it polls on (`ChaosRun.claim_clients` holds them while `ChaosScenario.FREEZE` is its step, in every run), and
   then one claim spends the stored credit to walk about 30 m away; `ChaosRun` checks on the host's state that the
   zone gained at most `ZoneTask.STALE_TICKS` (10) after its last accepted claim, in frames where no other living
   player stood in a zone (planted "stale claims count", it gained 168 and failed in all three runs; reverted).
   The hostile sends no claim in the round until that walk away, nor while its host position or a nonzero
   velocity has not caught up with its bot's, nor near a zone: a `Correction` or a `LATEST` claim superseding its
   walk would move it, and change what every honest bot sees, from the baseline's (seed 3 caught the last).
   Over the loopback, `ChaosRun` fails a run in which no hostile claim went out while its client knew it alive in
   the round (`ChaosHostile.round_alive_claims`, in each passed run's summary line; 13 to 27 over seeds 188001 to
   188010; a plant that kept the hostile quiet all round failed), so a quiet rule gone wrong cannot silence class 5
   unseen. Over a network it only prints the count: over WebRTC seed 7 sent none (188001 sent 13), not looked into.
   The run does not play the freeze with refused claims (a far claim, a past-credit tick or another epoch sent
   during the freeze, hoping each `Correction` keeps the claim young): `MovementRule.claim_age` reads only an
   accepted claim, covered by `movement_rule_claim_age_test.gd` (a refused claim does not renew it), not end to
   end;
6. repeated, replayed and out-of-order seqs (and `Hello`'s seq 0 from a player): every copy gets its own rule
   answer echoing the seq it carried (4 checks each copy);
7. no honest bot decodes the malformed peer's voice, nor the hostile's while it is downed or dead or in Loading
   or End (§6; the leak test's voice checks run too);
8. a second chaos run that differs only in hidden roles (bot 1 and bot 3 swapped by bot 1's `ForceRole`) gives
   the hostile the same `Rejected` stream (§4.1). Its refusals name the swapped players: `Raise` targets any
   player (none downed: `not_downed` whatever the role) and `PickUp` names the items others carry
   (`unavailable`), bot 1's knife among them.

4 to 7 are checked per `Match` call through `HostSession`'s observer, on the state the command met. In one
process the host's counts per chaos peer are replayed exactly from what it sent (`ChaosBudget`: `PeerBudget`'s
buckets refilled per host step, the 50-in-10 s count) and compared reason by reason with the host transport's,
which `CountingLoopback` keeps for the whole run (`RejectLedger`: `NetRejects` keeps per-peer counts only between
two summary lines); and the honest bots' decoded views (events, snapshots, voice but the hostile's) equal a
**baseline** run with the same seed and roster whose chaos peers are joined but idle. The leak test stays whole:
every bot, the lurker and the refused bot get `LeakCheck` and `check_counters` unchanged, the malformed peer
`check_bot` (its decoded events exactly `view_of`'s `Rejected`s) and, whatever `view_of` says, no snapshot, no
voice and no event but a `not_accepted` `Rejected` of an intent it sent; only the host's two counts (`host_problems`:
nothing rejected, nothing over budget) are exempt, for the two chaos peers' ids only, through the ledger
(`ChaosRun.host_problems`; the engineer's approval is asked on the PR). Over ENet (`--enet`: the same run in one
process on 127.0.0.1, `CountingEnet` and `ChaosEnet`) only the invariants hold: no crash, no engine error line,
the leak check (no superseded-LATEST or voice-seq check: a network bunches and drops), the counters, 4 to 7, and
each chaos peer's host counts per reason bounded by the chaos packets it sent for that reason (`check_bounded`:
a reject of bot 4's own honest traffic still fails; `OVER_BUDGET` and `UNKNOWN_PEER` are left to the network).
Over ENet the bots play once bot 1's lobby is full, and a bot whose join went unanswered joins again, as in
`BotsEnet` (#318; `ChaosRun._may_play`). A join lost for good (any end `_join_again` does not retry: over WebRTC
every reason but `no_room` and `service_unreachable`, over ENet a `connect_failed` sooner than half the join timeout,
and `host_lost` before the `Welcome`) fails its bot's step in `play_frame` before any bot acts, naming the reason and
those of the bot's earlier joins (`NetPlay._lost_join`, #483: `its join was lost for good (host_unreachable)`); a
join that waits for its retry does not start play. Over the network a bot joins at most `ChaosRun.MAX_JOINS` (3)
times, so a join retried without end fails too. Until #483 such a run played on without the bot, and over WebRTC,
paced to the real clock, the runner killed it at 60 s, before its 90 s time limit, with no reason printed. Since
#508 the runner's kill is 120 s per seed over ENet or WebRTC (`bots.CHAOS_NETWORK_SECONDS_PER_SEED`; 60 s over the
loopback), so a seed that stalls for any other reason fails at `ChaosScenario.TIME_LIMIT_S` with the scenario's
reason (`not done within the time limit (90.0 s)`; 2026-10-07, a planted stall, bot 3 waiting 200 s in End,
failed so at 90.6 s over WebRTC, and with `--seconds 60` was killed with no reason). The
malformed peer sends its `ForceRole` naming bot 2 only once bot 2's peer id is known, so none names peer 0 (which
the encoder refuses with an error line).

##### 4.6.5.1 Runs
`tools\run.cmd bots --chaos [--seed N] [--runs K] [--long] [--enet]` (`chaos_main.gd`): per seed the
baseline, the chaos run and the swapped run; without `--seed` a random one, printed first. `verify`'s `chaos`
step is `--seed 188001`, the short match (the round ends while bot 4 is downed): three runs of 720 frames in
about 4 s, 6 s with Godot's start; 20 runs in a row passed (2026-10-02). On protocol v7 (#227, 2026-10-03),
`--seed 1 --runs 8`, `--long --seed 5` and `--enet --seed 7` passed. With the zone and bot 4's freeze (#649,
2026-10-09) a seed's three runs are 1830 frames (30.5 s simulated, about 11 s); `--seed 1 --runs 10`, `--seed
188001`, `--long --seed 5`, `--enet --seed 7` and `--transport webrtc --seed 188001` passed. The night job `chaos` runs ten seeds of
`--long` from a random one, then one over ENet (§15 of AGENT_WORKFLOW).

##### 4.6.5.2 Proven (2026-10-02, seed 188001, each plant reverted)
`HostSession` taking no budget failed on the
replayed counts (`OVER_BUDGET` 70 expected for the hostile, none counted) and on the oracle's command count
(319 checked, 283 within budget); `Match` answering a refused `MoveClaim` with `Rejected` failed class 5 (the
malformed peer's claim answered `not_accepted`); debug kinds taken from every peer failed on the roles (bot 4
forced crew, now a dissident) and on the `BAD_PAYLOAD` counts; `InReach` always passing (`--long`) failed
class 4 (the hostile picked up a knife resting far away). Tests: `tests/unit/net/transport/
chaos_frames_test.gd` (every shape over a `LoopbackHub` is its reject or fails the codec),
`tests/integration/server/host_session_chaos_test.gd` (what each peer receives for replayed seqs, a hostile
claim and a burst over budget), `tests/scenarios/chaos_test.gd` (the oracle, the replay, the exemption, no
`ForceRole` for a bot 2 without a peer id), `tests/scenarios/chaos_enet_start_test.gd` (the start over the network:
a join lost for good fails at once naming its reason, a join that found no room joins again without starting play,
`MAX_JOINS`).

##### 4.6.5.3 Covered wire rows (M5 extends them with every new intent or row)
The C→H kinds 1 to 13 and 112 (kind 14, `MoveClaimReliable`, has no chaos shape: `host_session_claim_twin_test`
covers its teleport, far-future, stale and wrong-phase twins, #429), the debug kinds 24 and 25 (`ForceRole`,
`ForceClock`), the H→C kind 32 sent the wrong way, and unassigned kinds (0, 15, 19, 23, 26, 31, 66, 80, 95, 97, 111,
113, 127, 128, 200, 255). A new intent gets its refusals in
`ChaosHostile._refused` and `ChaosOracle` (its allowlist row and reasons), a new wire type its malformed shape
in `ChaosFrames`; a change of §3.2's table changes `ChaosOracle.ACCEPTS` with it.

#### 4.6.6 `host` and `join` (3i)
`tools\run.cmd host [--port P] [--clients N]` starts a host with its own client and,
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
own client ends. The default port, 24600, is a placeholder, "not a decision". Usage: `docs/AGENT_WORKFLOW.md` §11.8.
Since M4-6 (#142) its arguments are `LaunchOptions` and its end texts `EndReasons`, both in `client/app/`, which
the game reads alike.
Tests: `tests/unit/tools/headless_session_test.gd` (the roster line, the refusal texts, the exit codes),
`tests/unit/client/app/launch_options_test.gd` (the arguments) and
`tools/runner/tests/test_hostjoin.py` (the supervision, each stopped process's time from the stop to its exit, taken
at its own exit even while a kill of another process blocks, a killed one's last line and when it came, a grace per process, and a real host with two local clients reaching the
lobby roster Player1 to Player3).
Since #149 (M4-6, E20) `host` and `join` run this session with `--headless`, and by default in a shell where
`CLAUDECODE` is set (an agent's); otherwise they open the game in windows (§4.7).

#### 4.6.7 Over WebRTC
(M6-6, #371; [the M6 design](decisions/2026-10-04-m6-playable-over-the-internet.md) §5, §6):
`tools\run.cmd bots <scenario> --instances N --transport webrtc` runs `BotsEnet` with every transport a
`BotWebRtc` (`tests/harness/bots/`): instance 1 serves `LanSignalling` on the port, whose one room is
`BotWebRtc.CODE`, and only IPv4 host candidates on 127.0.0.1 are signalled (no STUN in a container, the design's
§2.7). Each process first sets the WebRTC library up and keeps that warm-up connection until its end (§4,
`WebRtcWarmUp.wait()`, #510), so the setup is in no join's `JOIN_TIMEOUT_MS`; a remote bot prints how long its join
took. A bot
whose join found no room (`no_room`, `service_unreachable`: its process started first) joins again 0.5 s later;
every other end (`host_unreachable`, after 15 s at most: the service answered and the connection never opened;
`joins_closed`, `full` and the other refusals; `host_lost` before the `Welcome`) fails the bot's step at once,
naming the reason (#483), and a remote bot's view file carries that line to the host. The fault
shim (§4 above) is on in every transport, seeded per transport: RELIABLE 50 ms late, LATEST 10 % duplicated, and
on the clients LATEST also 10 % dropped and one in five 120 ms late (a host that loses an epoch's first claim takes
the next as one tick, §7.1, and corrected an honest chaos bot in 1 of 10 runs under load); not for a measurement (`BotScenario.measurement`, which measures the relay).
A remote bot that wrote its view file sends nothing more and only polls until the host closes, since a send that
meets the other side's close prints an engine `ERROR:` line (the state check and the send race libdatachannel's
threads). Every check of the leak test runs unchanged, plus the **order check** (`OrderLog`, the design's §5):
each transport records per peer a fingerprint (the kind, the payload's hash and size) of every RELIABLE and LATEST
message its channel took (`send`) and every one it delivered (`packet_received`, after the inbox's merge); what one
side delivered from a peer must be what that peer sent, in order, with LATEST messages left out at most. It fails on
a message delivered after one sent later, a RELIABLE message skipped, a recording that delivered nothing, and, as
the host's lists are whole, a message never sent to that peer (a swapped id-to-connection map). A remote bot's
lists end with its view file, so the walk of what the host delivered from it stops at the first message missing
from them. The host checks both directions of each remote bot (its view file carries its lists), the lurker and
the refused bot; bot 1 is the host's own loopback client. Over WebRTC the relay counters' upload adds no IP and UDP
bytes per datagram: E56's 108 B per packet already counts them (`RelayReport.window`).
`tools\run.cmd bots --chaos [--seed N] --transport webrtc` (`--enet` is `--transport enet`) runs `ChaosRun` in one
process the same way (the library set up first, before the host's transport: `WebRtcWarmUp.wait()`, #510), paced to
the real clock (a frame waits until the real clock reached the simulated one: the connections and the shim's delays
are real time), with the ENet variant's invariants plus the order check, both ways for the honest bots and the
watchers, host to peer for the two chaos peers (their raw sends bypass `send`). A raw
packet goes on the channel of the lane whose ENet channel and mode `ChaosFrames` chose; a LATEST one still gets
`LaneOrder`'s header, as any sender's would (a 0-byte one is refused, and its send counts as not made). `verify`, and
so CI, runs `bots-webrtc` (`dissident_kills_the_crew --instances 3`, about 50 s) and `chaos-webrtc` (seed 188001,
about 16 s). Tests: `tests/scenarios/order_log_test.gd`,
`tests/scenarios/bots_enet_test.gd` (the joins again over WebRTC, and a join lost for good whose reason reaches the
view file), `tests/unit/net/transport/fault_shim_test.gd`,
`tools/runner/tests/test_bots.py` and `test_verify.py`.

##### 4.6.7.1 Proven (2026-10-05, each plant reverted)
`LaneOrder`'s "behind" rule removed (the design's §5 plant, M6-3's
again): with M6-4's shim alone `bots-webrtc` passed, as 127.0.0.1 never delivered a LATEST packet after a reliable
one sent after it; with the clients' late LATEST above both steps failed on the order check (`bots-webrtc`: `host
to bot 3: message 11 was delivered after message 14, which was sent after it`, and a second; `chaos-webrtc`: three
such lines for bots 2 and 3). #427's plant with real `HostSession`s and `ClientSession`s (its
review's item 3): a swapped id-to-connection map in `WebRtcTransport._backend_send` (the host's message to peer
p went on the connection of p xor 1) failed `bots-webrtc` on all three instances: bot 3 decoded another peer's
`PlayerJoined` where `view_of` holds its own `Welcome`, and other snapshots; the lurker decoded the refused bot's
`Rejected`, and the refused bot nothing; voice relayed under the wrong speaker; and the order check (`host to bot 3:
delivered message 0 was never sent to it`).

### 4.7 The game client (M4 design, #125)
Decided in the [M4 ADR](decisions/2026-10-01-m4-first-person-client.md) (Accepted): the engineer's choices E18 to E33
and the designer's D4 to D10 each took its recommendation, which this section follows (for E32 and D10 the
recommendation was (b)). It is the client
that M4-6 to M4-9 build; the core rework of vision revision 1 (M4-1 to M4-5) rewrites §3 to §9 in the issues that
change their code, and the client reads the events those issues add (the ADR's §4 lists them).

#### 4.7.1 One process, one persistent root (E19)
The main scene `client/app/game.tscn` (`application/run/main_scene`)
lives for the whole process:

| Node | What it is |
|---|---|
| `Game` | `client/app/game.gd`: the menu's choices, the sessions, the level swap, leaving and quitting, the end reasons |
| `HostNode` | on a host only: steps `HostSession` (§4.5) at `process_physics_priority` -100 |
| `SessionNode` | steps the `ClientSession` at priority -90 |
| `World` | a `Node3D`: `Level` (the lobby or the map instance), the views of stations, items and bodies, `Avatars` (a `RemotePlayerBody` per other player) and `Player` (the local `PlayerController` and its cameras) |
| `Ui` | a `CanvasLayer`: the main menu, the lobby HUD, the loading screen, the HUD, the task screen, the end screen, the Esc menu, messages |

Levels are swapped under `World`. Nothing calls `SceneTree.change_scene_to_*`: it removes the current scene at once
and frees it at the end of the frame (Godot 4.7.2), so a `HostNode` inside it would close the session (`_exit_tree`) and
every client would see `host_lost` at the first map load. There is no autoload, which `check` and every test run
would load.

#### 4.7.2 Who owns what (E18)
Hosting (the menu's Host, or `--host` after `--`) does what `tools/run/headless_session.gd`
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

#### 4.7.3 One physics frame

| Priority | Node | What it does |
|---|---|---|
| -100 | `HostNode`, on a host | `HostSession.step` (§4.5); its messages to the own client are read in this frame |
| -90 | `SessionNode` | `ClientSession.step`: poll, decode, fold into `ClientModel`, fire the signals (a `Correction` teleports the player before it moves; at each event `Game` sets the player's physics step and input flags for the screen the model is on, #241), advance a map load, send the `MoveClaim` due |
| -80 | `Avatars` | place every remote body at its interpolated pose, so the local push search sees this frame's capsules (static bodies placed with `force_update_transform()`, below) |
| 0 | `Player` | read input, move, then `set_motion` for the next claim (one physics frame, 1/60 s, old when it is sent) |
| `_process` | the views, the cameras, `Ui` | draw from `ClientModel` and the interpolated poses |

Under load or after a hitch Godot runs several physics frames in one idle frame. Between them `ClientModel` and
`Game.screen()` can already be on the next phase while the screens and their texts, which `Game._process` sets, still
follow the previous one; nothing is drawn in between. A test that reads those waits until `game.ui.screen` shows the
screen it waited for; game_loop_test checks that wait with `Game._process` off (#225). The local player's physics step
and input flags (`Game._apply_player_flags`) follow the model at once: `Game._on_event` applies them at every event the
session folds, in its physics step, and `_process` again every frame (the Esc menu), so after a hitch the player
neither steps nor claims into Loading or End, nor waits for `_process` to walk again (#241). A step turned off there
stops the player in that physics frame; one turned on steps it from the next (observed on 4.7.2, not in the docs).
game_loop_test plays a loop with no `Game._process` from the lobby on and sees no step in Loading, everyone at the
round's and the lobby's `Correction`s and no `Correction` of a refused claim.

A `queue_free`d node stays in the tree, and its body in the physics space, at least until the end of the current physics
frame, where a node at a later priority still finds it. (On 4.7.2 it was then gone: a probe for #242, not kept since it
slept, freed a body in one physics frame and found it gone in the next with no idle frame between. Observed, not in the
docs, and nothing here relies on it.) So a view that drops a physics body takes it out of the tree first: `AvatarViews`
removes a `RemotePlayerBody` whose player the model dropped (a new map, the lobby, a leave, a death) before freeing it.
Only queued, it pushed the local player off a spot the same frame's `Correction` had put it on, by one step at sprint
speed (End → Lobby brings `PhaseChanged`, which forgets the avatars, and the placement in one host step). Since #241
the player steps again only from the physics frame after that `PhaseChanged`, when the body is gone, so the game test
cannot see this one: `avatar_views_test.gd` guards it. The game test did see another: the next lobby snapshot drew
the others again from the round's poses behind the interpolation delay, at their round spots, where the greybox lobby
(its markers share the round's coordinates) may have placed the local player, pushed 0.35 m. So `AvatarViews` forgets
the poses at a `PhaseChanged` to a phase on another level, as at `LoadMatch`. One reordered packet still brought them
back until #251: a round snapshot sent before the change and arriving after it. `SnapshotBuffer.clear(floor_tick)` now
keeps no snapshot at or below the host tick estimated at the change (nor at or below the newest it held), and the
model folds none (§4.6.1); such an arrival still counts for the jitter.

#### 4.7.4 The flow

| State (`ClientModel` and the session) | Screen | Level under `World` | The local player |
|---|---|---|---|
| no session | main menu: address, port, Host, Join, Quit, and why the last session ended | none | none |
| connecting, no `Welcome` yet | "Connecting to <address>", Cancel | none | none |
| Lobby, Countdown | lobby HUD: the keys' hint, the roster with ready flags, the countdown; Ready and the settings in the Esc menu's Lobby tab (#169) | the mode's `lobby_level` | walks and claims |
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
  respawn, a failed check) through `ClientSession.corrected`. A teleport keeps the body's yaw and the head's pitch;
  only the own `Respawned` (#191) and a `PlayersPlaced` naming the own player (`End -> Lobby` and the deal, #240)
  level the look (§4.7.13).
- **The lobby** (#169): the player walks it like the round, with the lobby HUD in a corner (the keys' hint "Esc: menu
  · F: ready", the roster with ready flags, the countdown) and nothing to click. The Esc menu's Lobby tab has the
  roster, the Ready toggle and the settings; the `ready` key (F, a placeholder) toggles Ready without the menu.
  Ready sends `SetReady`; one control per `SettingSpec` of the client's own mode (its
  display name, a whole number within its bounds, or check boxes for the banned task types) sends `ChangeSettings`
  with that setting only; the demands and shortfalls come from `SettingsChanged`. Everyone sees the settings; only
  the host changes them, and only in a phase that accepts its `ChangeSettings` (the lobby, not the countdown).
  The countdown and the match clock show `end_tick` minus the estimated host tick (Movement, below).
- **The end screen** shows the winning side's `SideSpec.display_name` from the client's own mode and nothing else
  (§3.2: no names, no roles).
- **The Esc menu** (#169): one Esc opens it and frees the mouse; Esc again, or Resume, closes it, and where
  `GameFlow.pointer_on` does not free the mouse (the lobby, Loading, the round) captures it again. Its tabs are on the left (Resume; Lobby, in the lobby and the countdown;
  Voice, in every screen, M5-6; Leave; Quit), the selected tab's page on the right; it opens on the Lobby tab where
  there is one, else on Resume. `Game.open_esc` gives it the live `screen()`, not the screen `_process` drew last:
  an Esc in the frame the Welcome arrives comes before the lobby is drawn and opens on the Lobby tab too (#204).
  Under it nothing reads the gameplay keys, the held ones are released, and F readies nobody.
- **The mouse** (#517): `GameFlow.pointer_on` says what each screen asks of it. The lobby and the round capture it
  when they show (no click first; also after Back to lobby), Loading keeps it as it was, and the menu, Connecting
  and the end screen free it for their buttons. A screen never captures it from under the Esc menu, nor while the
  window lacks the focus (`MousePointer.focused`): Windows clips the cursor to a capturing window even when another
  app has the focus (`DisplayServerWindows::_set_mouse_mode_impl`, 4.7.2); a click captures it there. Closing the Esc
  menu in Loading captures it too. Until #517 Loading freed it (`GameFlow.frees_pointer`), and since the countdown
  runs on the lobby's screen, every round started with the cursor showing until a click.
- **The window** (#517): an exported game starts in borderless fullscreen, `display/window/size/mode.template=3` in
  `project.godot`. Only an export template has the `template` feature, so everything the editor's binary runs (the
  runner's `shot`, `playcheck`, `host` and `join` windows, the tests, the editor's runs) starts in a window: in
  Godot 4.7.2 neither `--position` and `--resolution` nor `--windowed` undo a project's fullscreen mode (`main.cpp`
  creates the window in the setting's mode; `--windowed` only skips a later `window_set_mode`). Not exclusive
  fullscreen: the docs say it allows one window per screen and turns alt-tab into a fullscreen transition (on
  Windows driver dependent, with black screens); the borderless window alt-tabs at once and leaves the other
  monitors usable. Godot binds nothing to Alt+Enter: the action `toggle_fullscreen` (Alt+Enter) flips fullscreen
  and a window through `GameWindow` (`client/app/game_window.gd`), handled first in `Game._input` on every screen.
  Resolution options are M6.2's settings screen. Tests: `tests/unit/client/app/game_window_test.gd` (the setting
  with an export's features and without, the toggle), `input_actions_test.gd`,
  `tests/integration/client/app/game_window_input_test.gd` (Alt+Enter through `Input` events) and
  `pointer_flow_test.gd` (a host and a joined client through Ready, the countdown, Loading, the round, the end and
  back, the mouse captured all the way to the end screen; an open Esc menu and an unfocused window stay free). Not
  headless: the real mouse and window; the manual check is in the PR of #517.
- **Leaving:** the Esc menu's Leave and Quit. A client's Leave calls `ClientSession.leave()`; the host's asks for a
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
  runner's `--stop-file` and `--alive-file` (M6-7 adds `--code`, `--signal=`, `--room=` and codes for `--join=`, §4.8); the parser moves from `tools/run/headless_session.gd` to `client/app/`.

#### 4.7.5 Built in M4-6 (#142), the shell
`client/app/` holds `Game` (`game.gd`, `game.tscn`, the main scene),
`GameFlow` (the flow table above as a pure class: the screen and the level per session state and phase, read from
the client's own `PhaseSpec`: a lobby level shows the lobby screen, a phase that accepts `LoadAck` the loading screen,
one that accepts `ReturnToLobby` or a match with a winner the end screen, any other map phase the round),
`SessionNode` (-90), `LaunchOptions` (the command line, which `headless_session.gd` also reads) and `EndReasons`
(the reasons in words; it writes the host's own reasons as ids, since `client/` may not name `HostSession`, and a
test pins them to `server/`'s). `client/ui/` holds the screens, built in code under `GameUi` (the `Ui` layer):
`MainMenu`, `ConnectingScreen`, `LobbyPanel`, `LoadingScreen`, `EndScreen` and `EscMenu`. `client/world/avatar_views.gd`
(`Avatars`, -80) showed a `RemotePlayerBody` per other player at the newest snapshot's position, which M4-7 replaced
with `SnapshotBuffer`'s poses. What the build pinned:
- `HostNode` is the façade: `HostNode.host(transport, mode, port)` (and a clock for tests), `is_running()`,
  `own_client`, `errors`, `end_reason`, `ended`, `counters()` and `relay_counters()` (debug builds only),
  `skip_replay()` and `close()`; the session is private. The source test also fails on a path into `server/` (a preload; `app/` may name
  `host_node.gd`) and on `._session`, HostNode's private field.
- The countdown showed `end_tick` minus the newest snapshot's tick until M4-7's estimate replaced it; the local
  player stands still (no physics step) outside the lobby and the round.
- The mouse is freed whenever a screen other than the round shows (`GameFlow.frees_pointer`); loading and the end
  read no device input, and under the Esc menu the held keys are cleared. Welcome and each `Correction` place the
  player through `PlayerController.teleport()`. Since #169 the lobby keeps the mouse too; since #517 Loading keeps
  it and the lobby and the round capture it (`GameFlow.pointer_on`, "The mouse" in §4.7.4).
- Every end goes through one function: the `HostNode` leaves the tree (closing the session), the client leaves, the
  level, the views and the player are freed, and the menu says "The last session ended: <words>". The host's Leave
  and Quit, and closing the host's window, ask first (`EscMenu`); a client's Leave does not.
- A `Range` emits `value_changed` only inside the tree; the lobby panel's controls send one `ChangeSettings` with
  that setting only and are refreshed from `SettingsChanged` without a signal.
- Tests: `tests/unit/client/app/` (`GameFlow`, `LaunchOptions`, `EndReasons`, and E18's source test, seen failing
  on a planted `_host._session.game` in `game.gd` and a `HostNode` named in `client/ui/`),
  `tests/unit/client/ui/screens_test.gd`, and `tests/integration/client/app/game_loop_test.gd`: three `Game` roots,
  each in a `SubViewport` with its own `World3D` as `net_pair.gd`'s are (in one physics space each player stood
  inside the body another game drew of it and was pushed off its spot, #225 and #238), over a `LoopbackHub` on a
  simulated clock through the lobby, the host's setting, Ready, the countdown, loading, the round (which holds the
  players still for half a second), time up, the end screen and back, a client's Leave and the host's close (about
  5 s), and the same loop with no `Game._process` from the lobby on (#241, above).
  The screens' `shot`s: `client/dev/<screen>_preview.tscn` (`screen_preview.gd`, a fake `ClientModel`).
- The runner's windows for `host` and `join` (E20) came with #149, the rest of M4-6: below.

#### 4.7.6 Movement on the network
- **Claims:** every physics step the controller calls `set_motion` (its position and velocity; as the facing, the
  camera's 3D look vector, at most 89° up or down; whether it sprints, gives movement input and stands on the floor)
  and `count_jump` at a jump, and `set_facing` when it turns outside the step (the level look of a respawn or a
  placement, #191, #240);
  `ClientSession` sends one claim per 20 Hz client tick (§4.6.1). The facing's pitch needs
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
- **Stamina** (E24): `PredictedStamina`, which replaced `LocalStamina` (the client's only copy of
  `StaminaLedger`'s rule), predicts between `SelfStatus` updates; the HUD shows the prediction, and sprint and jump
  are gated by it. On the network it settles claim by claim and follows each `SelfStatus` from the claim it names,
  without giving back the ticks in flight (#155, §7.1.5 Speed).
- **Remote players** (E23): `SnapshotBuffer` (pure, unit-tested) keeps the newest snapshots by host tick, estimates
  the host tick from a sliding window of arrivals (not an all-time maximum, §7's lesson), and gives each remote
  player's position and facing, interpolated linearly, and its newest velocity, used only to pick an animation, so a
  claimed velocity never moves a body on another screen, at the estimate minus a delay: one tick plus the jitter seen
  over the window, from 100 ms to 250 ms (placeholders, "not a decision"). Past the newest snapshot a player holds
  still (no extrapolation); a placement or a respawn snaps. The bodies are capsules on the living layer that are
  teleported, and the push search at priority 0 must see where in the same frame. The design said `AnimatableBody3D`
  with `sync_to_physics` off; M4-7 found that not enough on 4.7.2 with Jolt: a transform set in `_physics_process`
  reaches the physics server only after the whole pass unless the node calls `force_update_transform()`, and a
  kinematic body (`AnimatableBody3D` with `sync_to_physics` on or off, `CharacterBody3D`) shows a teleport to shape
  queries only after the physics step, even set on the server directly. So `RemotePlayerBody` is a `StaticBody3D`
  placed with `force_update_transform()`; nothing collides with it as a wall (the controller's mask is the world).
  M4-7's two-client push tests assert every frame that the server holds the pose set at -80 and that a shape query on
  the living layer, as the push search's, finds the capsule there and not where it was a frame before (an
  `AnimatableBody3D` failed both on most frames a body moved, 30 to 173 per test, even with `force_update_transform()`).
- **The crawl** (M4-9): a downed controller moves at the crawl speed, with no sprint and no jump, up the step height,
  colliding with the level only and pushing nobody; it keeps the standing capsule for collision (the host's floor
  checks use it), and only its mesh lies down. Physics layer 3 is `downed` (`PhysicsLayers.DOWNED`, built in M4-9),
  which no push search looks at: the downed collide with no player.

#### 4.7.7 Built in M4-7 (#143), movement on the network
- `client/player/`: `PlayerController` takes `rules` (the mode's `PlayerRules`) and, `attach()`ed to the
  `ClientSession`, ends every physics step with `set_motion` (the camera's look vector as the facing) and
  `count_jump` at a jump, and has its `PredictedStamina` settle each claim and follow each `SelfStatus` (#155,
  §7.1.5 Speed); `PlayerTuning` holds the push factors and the view's easing only. `RemotePlayerBody` takes its
  capsule and eye height from the rules, turns the body by the yaw and the head (a visor) by the pitch, and is a
  `StaticBody3D` (above).
- `client/world/`: `SnapshotBuffer` (pure) and `AvatarViews`, which draws from it at -80, snaps the players a
  `PlayersPlaced` names (no blend across a tick within one of the event's estimated tick, since events and
  snapshots travel on different lanes), forgets the poses at `LoadMatch` and at a `PhaseChanged` to another level
  (End → Lobby, #241), keeping no late snapshot of a tick at or below `host_tick()` at that change (#251), and gives
  the estimated host tick (`host_tick()`, also handed to the model's `host_tick_now`) and the delay. A teleport too
  far for anyone to walk in the time between two snapshots (30 m/s, a placeholder) also snaps. A body whose player
  the model drops leaves the tree before it is freed (#242, above).
- `client/net/client_session.gd`: `snapshot_received(tick, avatars)` for every decoded snapshot, `corrections`, the
  count of `Correction`s of refused claims, and `placements`, of those that follow a placing event naming the client
  (`PLACING_EVENTS`: `PlayersPlaced`, `KnockedDown` and `Respawned` (M4-4); a death and a revive send no
  `Correction`; a later rule that places a player with a `Correction` adds its event there).
- `client/app/game.gd` wires them: a `SnapshotBuffer` per session, the player's rules and session, the lobby's
  countdown from the estimate, `device_input` (tests drive the controller's wish fields), and in a debug build the
  debug overlay (`client/ui/debug_overlay.gd`, the `debug_overlay` action on F3; `client/dev/debug_overlay_preview.tscn`
  for `shot`), which since #431 also shows the own connection's kind and round trip (§4.8).
- Tests: `tests/unit/client/world/snapshot_buffer_test.gd` (jitter, loss, a freeze and its burst, a lasting rise of
  the latency, degenerate facings, placements), `tests/unit/client/player/predicted_stamina_test.gd` (against
  `StaminaLedger` after every tick), `tests/unit/client/net/client_session_snapshots_test.gd`,
  `tests/unit/client/ui/debug_overlay_test.gd`, `tests/integration/client/world/avatar_views_test.gd` (since #242
  also: a dropped body leaves the physics space in the frame it is dropped, and a real controller placed onto it in
  that frame is not pushed, both seen failing with `queue_free` alone, the push by 7/60 m; `clear()` takes each body
  out of the tree too), and over a
  `LoopbackHub` with a `HostSession` (`net_pair.gd`: a host and a joined `Game`, each in a world of its own, on a
  simulated clock, in `tests/fixtures/client/steps_room.tscn`): `player_network_test.gd` (the real controller walks,
  sprints up steps, jumps and walks down with 0 corrections; a teleport the test forces is corrected once; the round's
  placement is one placement and no correction, and the placed joiner snaps on the host's screen; the overlay shows
  each side its numbers) and
  `player_network_push_test.gd` (the two-client pushes at the interpolation delay, the same-frame pose asserted).
- Not headless: how the others look moving, the overlay's key and the feel; the one-PC playtest (the M4 ADR's §6)
  checks them, and the two-machine one records its movement notes on #76.

#### 4.7.8 The revision in 3D
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
  | Living | walks, sprints, jumps, pushes (§7.1) | first person, the hand item in view | all (the ADR's controls) | health, stamina, hand, belt, a package's destination, task progress, clock, own role |
  | Downed | crawls, keeps its items; holds still and claims no displacement from a `RaiseStarted` naming it until `RaiseStopped` or `Revived` (the host corrects any, answer 8) | third person above the body | crawl, look, give up | the knockdown countdown (paused while raised), who raises them |
  | Dead | off: no avatar, no claims, no look (#191) | the spectate camera | next and previous target | the respawn countdown; "Spectating <name>" and the target's hand and belt items (#168); nothing else of the target's |

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
  target. Nothing about the target is sent, and the client shows no health, stamina, role, teammates or private
  event of it.
  From a living target's eyes the spectator sees what the target's own screen shows (#168): its body and head
  hidden, its hand item in the spectate camera's first-person hand, the views of its hand and belt items at its
  body hidden; the HUD says "Spectating <name>" over those public slots (§4.7, The HUD).
  The dead keep receiving every snapshot (none holds a dead player's avatar): the camera is built from them.
- **What the dead hear** (V11): no voice (the host routes none, and the client plays none while dead); the world's
  sounds around the target (from M5-5 the listener is `Ears`, at the target's eye or its body's head, §6); lift music
  from an `AudioStreamPlayer` on the Music bus that only the dead player's client plays. M4's world sounds are
  placeholders for `Swung`, `ItemPickedUp` and `ItemPlaced` at their positions.
- **A hearing range** (E33 (a), amended by the M5 ADR's E40, confirmed by the engineer): a world sound plays only
  within about 12 m of the ears (until M5-5, of the listener's camera; a placeholder,
  "not a decision"), for the living, the downed and the dead alike: a pure sound chooser (unit-tested) drops an event
  from farther away, and each `AudioStreamPlayer3D` sets `max_distance`. The events reach everyone with a position,
  so an uncut sound would tell every client through the walls where a package was just put down. Behind the level
  a sound plays muffled, not cut (one ray from the ears as it starts, M5-7; §6.5.7 Occlusion).
- **Respawn:** `Respawned` of the own player and its `Correction` put the controller at the marker in first person
  again, looking level (head pitch 0) with the yaw it had, as at the round's start (the engineer's answer on #191:
  the markers carry no facing); the spectate camera and the lift music stop. After `Revived` the controller stands
  up where it lay, in first person; a revive sends no `Correction` (M4-4: the raise held the downed player where
  the host has it).
- **Others:** a `RemotePlayerBody` shows its facing (a head that turns and nods), the hand item at a hand attach
  point, the belt item at a belt attach point, a two-handed package held in front, the downed pose and its layer, and
  invulnerability (the avatar's flag). A body (`Died`) is a view of its own, removed at `Respawned` or `PlayerLeft`.
- **Hands:** the own hand item is drawn in the first-person view and the belt item on the HUD. Every item is drawn
  from `ClientModel`'s fold of the item events: on the ground where it lies, or at its holder's hand or belt. The own
  slots come from events only, since the own avatar never arrives. No screen reads out the own invulnerability
  (the engineer's answer 2 on PR #167: a later buffs UI may show it); others wear the shell (D8).
- **Interactions:** the camera's ray picks the candidate, the first item or downed player along it in the client's
  own level; the hint and the key then apply only if the mode's `InReach` of `PickUp` holds, measured as the host
  measures it (2 m from the feet, not along the ray from the eye 1.6 m higher), so a crate-top item the host would
  refuse gets no hint and a floor item it would accept does. M4-8's target-choice test checks both against a fixture
  world. The pick-up hint stops a margin short of that reach (#319): the host measures from the feet of the last
  `MoveClaim` it accepted, which trail the player's own while walking in, so E at the first hint would otherwise be
  refused `out_of_reach`. The margin is the walk (the mode's `walk_speed_mps`) in one claim interval and one physics
  step (`TargetChoice.HINT_MARGIN_S`, 4/60 s, not a decision): 1.7 m of the base mode's 2 m. The raise hint stops
  the same margin short of the raise's `TargetInReach`, which the host also measures from that claim's feet (#352:
  `LifeView.raise_hint_reach_of`, through `TargetChoice.hint_reach`). The host's `InReach` and `TargetInReach` are
  unchanged. The keys send `PickUp(item)`,
  `Raise(target)` and `StopRaise()`, `PutDown(facing)`, `Use(facing)`, `Swap()` and `GiveUp()`; the host checks each
  again (§7.1), and the client predicts nothing of an action's outcome.
- **The HUD:** health and stamina (`SelfStatus`, the stamina predicted), the hand and belt items by their kinds'
  display names, a package's destination (a swatch of its circle's colour and a marker over that circle, drawn
  through walls too, since circles are fixed, public places: D10 (b)), the shared progress (`TaskProgress`), the match
  clock, the own role by its display name and, for a dissident, its teammates (`Teammates`), and
  what the crosshair would do. While dead (#168) the HUD keeps the clock, the progress, the own role and teammates,
  and shows "Spectating <name>" with the watched player's hand and belt items instead of the own numbers, slots,
  destination and hint; no target's health, stamina, role, teammates or private event (the ADR's §3 item 2).
  **The task screen** (Tab), for the living, the downed and the dead: each task of the
  match (`TaskState`) with its type's display name and description from the client's own mode, and its shared
  progress; no map. **A circle** is a translucent cylinder of its station kind's radius and height in
  `StationPlaced`'s colour, dimmed once `PackageDelivered` names it.

#### 4.7.9 Built in M4-9 (#145), the life states in 3D
- `client/player/`: `PlayerController.life` (`set_life`, replacing the ghost flag and `set_ghost`) follows the own
  life fold (`Game._sync_life`): living on the living layer; downed on the `downed` layer, crawling, with its lying
  mesh (`Lying`); dead on no layer, no mesh, and no physics step (the controller returns at once and `Game` stops
  its step), so a dead player never stands back up and walks before its `Respawned`. `held` (from
  `ClientModel.raiser_of(own) != 0`) makes a downed controller stand still, spend nothing and claim where it lay.
  Any life change clears a pending jump. `RemotePlayerBody` lies down while its player is downed (its head hidden,
  the capsule shape kept standing), wears a pulsing white shell while its avatar has the `invulnerable` flag, hides
  its meshes while watched from its eyes (`set_watched`), and knows its `peer`. `LifeLooks` holds D8's greybox
  looks (the lying capsule, the body's grey capsule and dark cross, the shell).
- `client/world/`: `BodyViews` (`Bodies` under `World`, -70) draws a body per `ClientModel.bodies` entry, the own
  one included. `SnapshotBuffer` keeps a unit facing for a huge but finite relayed one (scaled by its largest
  component before normalising; `unit_or()`), which `look_angles` shares.
- `client/life/`: `LifeView` (`Life` under `World`, 5: after the player, before `SightHider`) picks the camera by
  the own life (the player's, `DownedCamera`, or the spectate camera), runs the life inputs (E pressed on a downed
  player within the mode's `TargetInReach` from the feet, less the walking margin of #352, sends `Raise`, its
  release `StopRaise`, and a raise that
  starts after E was let go is stopped at once; G held for 1 s sends `GiveUp` once; the left and right mouse
  buttons cycle the spectate target while the mouse is captured) and plays `LiftMusic` while dead. `DownedCamera`
  is the `SpringArm3D` above (its probe 0.2 m, its arm pitch 0 to 80° down, a look further down tilting the
  camera alone); the arm casts at priority 7, after `LifeView` placed it in the same step. The raise target is
  cast once per physics step (the physics space is read only there), and the click that captures the mouse does
  not cycle the target. `SightHider` (10) hides every node of its group `hidden_out_of_sight` (the avatars, the bodies;
  M4-8's item views join it) with no line of sight from the pivot, a ray each against the world layer with 0.1 m
  of slack, and shows them again when the camera is out of use. `SpectateTargets` and `LifeCountdowns` are the pure
  parts; a spectated living target is drawn from its body's interpolated pose (position, yaw, head pitch), so the
  camera inherits `SnapshotBuffer`'s guard. `LifeHud` words the panel. (#168 adds the spectator's first-person
  hand and removes the panel's own invulnerability line and its "Watching" line: below.)
- `client/ui/`: `LifePanel` (the round's life panel under `Ui`, its own, not M4-8's HUD) and the shared greybox
  theme `client/ui/theme/game_theme.tres` (`GameUi.THEME`, given to every screen under the `Ui` layer, which as a
  `CanvasLayer` holds none itself), with the type variations `LifePanel`, `LifeTitle` and `LifeText`; M4-8 moved
  the older screens' inline styles into it.
- `project.godot`: `give_up` (G), `spectate_next` and `spectate_previous` (the left and right mouse buttons).
- The lift music is a generated placeholder (`LiftMusic.placeholder_stream()`: a quiet looping arpeggio), until a
  human picks a CC0 track with its `docs/credits/` entry.
- Tests: `tests/unit/client/life/` (`LifeCountdowns`, `SpectateTargets` with a pinned seed, `LifeHud`, `LiftMusic`),
  `tests/unit/client/ui/life_panel_test.gd` (the theme source test, seen failing on a planted override),
  `tests/unit/client/app/session_node_test.gd`, `tests/integration/client/life/downed_camera_test.gd` (every look
  at or below the eye and before a wall behind the body, seen failing without the clamp and the mask; a view seen
  from the arm's end past a short wall but not from the eye is hidden),
  `tests/integration/client/world/body_views_test.gd`, and over the loopback (`NetPair.with_life()`, which adds the
  raise, the give-up and a 2 s respawn on `steps_room`'s new `respawn` markers) `life_network_test.gd`: a raised
  downed joiner trying to crawl holds still and gets 0 `Correction`s (58 without the hold) and stands up
  invulnerable in first person; a joiner who gives up stays off the living however it is driven, watches the host
  from its eyes with the music, follows it to the camera above its body when it goes down, and respawns at a marker
  in first person, invulnerable on the host's screen, with no `Correction`; `life_raise_network_test.gd` (#352: the
  joiner walks at the downed host's body from three sides and presses E at the first raise hint, on an even and an
  uneven clock; the host starts every raise; seen failing `out_of_reach` with no margin) and
  `tests/unit/client/life/life_view_reach_test.gd`. `client/dev/life_preview.tscn` is the
  `shot` of the downed pose, a body, the invulnerable look and the panel.
- Not headless: the keys and the mouse, the feel of the cameras and the music; the one-PC playtest (the M4 ADR's
  §6) checks them.

#### 4.7.10 Built in M4-8 (#144), items, hands, the HUD and the task screen
- `client/world/`: `ItemWorld` (`Items` under `World`, made by `Game`) holds `ItemViews`, `CircleViews`,
  `ItemInteractions` and `WorldSounds` and gives the HUD what the model does not hold (`hud_local()`: the predicted
  stamina and the crosshair's hint; `Game` adds whom a dead player watches, #168). `ItemView` is one item's
  greybox look by its kind's id (D7 (a)), a labelled box for an unknown kind, its origin the resting point;
  `ItemViews` places one per model item: where it lies, at a remote holder's `RemotePlayerBody` attach point
  (`hand_point()`, `belt_point()`, `carry_point()` for a two-handed kind), on the ground at the body while that
  holder is downed (the own player too, whose first-person hand then shows nothing), hidden while it has no body
  drawn and when the own living player holds it. Each view joins `SightHider.GROUP` and gives `sight_point()`; the
  root's `visible` is left to the sight hiding, `ItemViews` toggles the look under it. `ItemViews` places in the
  physics step at priority 1, after the avatars and the player moved and before `SightHider` (10) casts, so a view
  out of the body's eye's sight is never drawn for a frame. `CircleViews` finds a station kind's size in the task types'
  `StationKind` properties (Delivery's `circle`) and draws the D10 (b) marker, the one `no_depth_test` material,
  over the circle of `ItemViews.destination_item()` (the own hand's package, else the belt's). It leaves out a
  zone, which `ZoneViews` (§4.7.24) draws.
- `TargetChoice` (pure) and `ItemInteractions` (physics priority 6, after the player): one ray from the camera against
  the world layer (as the host's line of sight) and the `downed` layer gives where it stops (a downed player in
  front is M4-9's raise target, and E there picks up nothing behind it); the candidate is the ground item (not
  held, not delivered) whose middle the ray passes within 0.3 m of, entered short of that and of 4 m, the one the
  crosshair is closest to first; the hint and E apply only if the item lies within `InReach.reach_m` of `PickUp`
  (the client's own mode) of the feet, less the walking margin of #319 (`TargetChoice.hint_reach_of`), and a second
  ray from the camera to the item's middle meets no world geometry (the host's `InSight`): an item just behind a
  thin wall or a door jamb is never named.
  Q, the left button and X send `PutDown(facing)`, `Use(facing)` and `Swap()` while the own slots hold something
  (the click that captures the mouse is not a use); only while the own player is living, in the round, with no Esc
  menu. The facing is the camera's look vector.
- `SoundChooser` (pure) and `WorldSounds`: `Swung` at the swinger (the local player or its body), `ItemPickedUp`
  where the item lay, `ItemPlaced` at its position, each only within `HEARING_RANGE_M` (12 m, "not a decision") of
  the ears (from M5-5; until then the viewport's current camera), and nothing beyond; every `AudioStreamPlayer3D`
  sets `max_distance` to it, and from M5-7 plays muffled behind the level. The sounds are 0.15 s blips generated in
  code (no asset), until the engineer's CC0 files arrive with their `docs/credits/` entries (#144; M6.2's #525,
  each file passing `sfx-check` first, AGENT_WORKFLOW §11.25).
- `client/player/`: `FirstPersonHand` under the camera shows the own hand item (`PlayerController.hand_view()`);
  `RemotePlayerBody` has the three attach points.
- `client/ui/`: `HudText` (pure: the HUD's words) and `Hud`; `TaskScreen` (its rows pure: each `TaskState` by task
  id with its type's display name, progress and description, then `TaskProgress`; no place, no map), shown while
  `task_screen` (Tab) is held in the round with no Esc menu, which hides the crosshair (only the living have one)
  and hint under it. **The shared theme:**
  `client/ui/theme/game_theme.tres` (`GameUi.THEME`) holds every colour, font size, spacing and style box as a type
  variation; `GameUi` gives it to every `Control` child, one added later too (a `CanvasLayer` holds no theme); the
  screens name variations only. The input actions `swap` (X) and `task_screen` (Tab) are in `project.godot`.
- Tests: `tests/unit/client/ui/hud_test.gd`, `theme_test.gd` (a source test over `client/ui/` against
  `add_theme_*_override`, `Color(...)`, `Color.X` and `font_size` outside `client/ui/theme/`, seen failing on a planted
  override in `hud.gd`), `tests/unit/client/world/target_choice_test.gd`, `sound_chooser_test.gd` (seen failing on a
  chooser without the range), `tests/integration/client/world/item_interactions_test.gd` (the real controller on a
  fixture floor: a crate-top item 2.08 m from the feet and 1.75 m from the eye gets no hint, floor items 1.3 to
  1.7 m away get one and one 1.85 m away none (#319); seen failing with the reach measured from the eye),
  `item_pick_up_network_test.gd` (#319: a joiner walks at each of three knives over `NetPair` and presses E at the
  first hint, on an even and an uneven clock; the host accepts every `PickUp`; seen failing `out_of_reach` with no
  margin) and `item_views_test.gd`. The `shot`s:
  `client/dev/hud_preview.tscn`, `task_screen_preview.tscn`, `items_preview.tscn` and `hand_preview.tscn`.
- Not headless: the keys, the feel of the hint and the sounds; the one-PC playtest after M4-8 checks them (the M4
  ADR's §6), and a human picks the CC0 sounds (by ear on `sfx-check --page`'s listening page, AGENT_WORKFLOW
  §11.25).

#### 4.7.11 Built in #169 (an M4 follow-up of the one-PC playtest), one Esc menu with tabs
- `client/ui/`: `EscMenuState` (pure: open or closed, the tabs per screen, the selected tab, the host's questions
  before Leave and Quit, who may change the settings: the host, while the phase's `PhaseSpec` accepts its
  `ChangeSettings`), `EscMenu` (draws it: the tab buttons, a scrolling page on the right), `LobbyPanel` (now the
  Lobby tab's page; read-only settings for everyone but the host) and `LobbyHud` (the lobby's corner: the hint, the
  roster, the countdown; it ignores the mouse). The theme gains `EscBody`, `EscTabs`, `EscTab` and `EscPage`.
- `client/app/`: `Game` handles Esc in `_input` and the `ready` key in `_unhandled_input` (the lobby screen, no Esc
  menu): `toggle_ready()` sends the Ready toggle's `SetReady` with the own flag flipped. `GameFlow.frees_pointer` no
  longer frees the mouse in the lobby (#517 replaced it with `GameFlow.pointer_on`). `MousePointer` captures and
  frees it through `Input.mouse_mode`; headless
  Godot keeps no mouse mode (it reads visible whatever was set, probed on 4.7.2), so tests give `Game` one that
  remembers. The input action `ready` (F, a placeholder) is in `project.godot`.
- Tests: `tests/unit/client/ui/esc_menu_state_test.gd`, `screens_test.gd` (the menu's pages, the host's question, the
  read-only settings), `game_flow_test.gd`, `input_actions_test.gd`, and
  `tests/integration/client/app/esc_menu_input_test.gd`: a host's `Game` alone over the loopback, with keys sent
  through `Input.parse_input_event` (headless, it reaches `_input`, `_unhandled_input` and the action states): one
  Esc opens the Lobby tab with the mouse free, another closes it and captures the mouse, W held under the menu is
  released, F under the menu readies nobody, F and the Ready toggle both set the own ready flag. Seen failing first
  with the lobby panel's Ready and settings shown over the game, and with the re-capture planted out. The `shot`s:
  `client/dev/lobby_preview.tscn` (the lobby HUD) and `esc_<lobby|lobby_guest|resume|leave|quit>_preview.tscn`.
  #204 adds an Esc pressed from the `welcomed` signal, before any `_process` drew the lobby: the Lobby tab (seen
  failing without the fix, also under a slow `_process`); `screens_test.gd` holds `GameUi.open_esc`'s `screen_now`.
- Not headless: the mouse capture on a real window and the feel; the engineer repeats the lobby part of the one-PC
  playtest. `tools\run.cmd playcheck esc_menu` drives both windows' menus; since #204 its guest presses Esc as soon
  as its screen is the lobby, with no frames between, and readies with the Lobby tab's Ready button, which only that
  tab shows.

#### 4.7.12 Built in #168, the follow-up of the one-PC playtest on `release/m4` (PR #167)
- The spectate camera: the playtest saw it "at another point than the target's eyes". Headless it has no offset:
  `tests/integration/client/life/spectate_network_test.gd` (NetPair; the joiner dies and watches the host's player
  while it walks and turns) finds the camera equal to the target's interpolated eye transform every physics frame,
  and retracing the poses of the target's own camera within a few millimetres, later by the interpolation delay
  (about 0.15 s on the loopback: some 0.7 m behind a walking target); both fail with a planted 5 cm offset. What
  the playtest likely saw instead: from the eyes, the target's items hung at its hidden body (the hand item 0.65 m
  under the eye, seen only when the target looks down, and never where its own screen shows it). `LifeView` now
  shows the watched target's hand item in a `FirstPersonHand` under the spectate camera (`spectate_hand()`) and hides the
  views of its hand and belt items after `ItemViews` (1) placed them in the same physics step (`LifeView.items`,
  given by `Game`); a downed target, another target or the own respawn shows them at the body again.
- `client/ui/`: `HudText.Local.watching` (from `LifeView.target()`, `Game._hud_local()`), `HudText.spectates()`
  and `Shown.spectating`; `Hud.spectating_label` heads the slots' corner. `LifeHud` has no own invulnerability
  line and no "Watching <name>" line (the HUD names the target once); the respawn countdown and the cycling keys
  stay.
- Tests: `tests/unit/client/ui/hud_test.gd` (the spectator's words from a fake `ClientModel`: the target's name
  and slots, none of its private facts, none of the spectator's own slots, numbers or hint),
  `tests/unit/client/life/life_hud_test.gd`, `life_network_test.gd` (the HUD's line on the network),
  `spectate_network_test.gd` (above; the target's meshes and items not drawn from its eyes, drawn again when it
  goes down or the spectator respawns; the retrace measured to the segment between two recorded poses, so the
  render tick's phase cannot fail it) and `spectate_cycle_test.gd` (no network: a dead player cycles between two
  living targets of a hand-folded model, and the one it leaves is drawn with its items again). The `shot`:
  `client/dev/spectate_preview.tscn`.
- Not headless: the feel of spectating; the engineer repeats the spectating part of the one-PC playtest.

#### 4.7.13 Built in #191 and #240, the player looked up after a respawn or a new match (fillers)
- `client/player/player_controller.gd`: the own `Respawned` (the controller's session events) calls
  `look_level()`: the head's pitch 0, the body's yaw kept (the engineer's answer on #191, no protocol change), and
  `ClientSession.set_facing` (new: the next `MoveClaim`'s facing, nothing else of `set_motion`'s report) with that
  look, since the first claim after the respawn can go out in the same session step as its `Correction`, before
  the controller steps again; so other players see a level head from the first claim. A `Correction` alone (a
  refused claim, a knockdown) and a revive keep the look. `look()` does nothing while dead or left:
  before, mouse motion while spectating still turned the hidden body and tilted its head (the controller reads
  the mouse while `Game` only stops its physics step), up to 89°, which the respawn kept, as it kept a downed
  player's look up. `LifeView` is unchanged: the downed camera follows the downed look, the camera above the own
  body keeps the look at death, and spectating reads the target's interpolated pose only.
- Tests: `life_network_test.gd` (the downed joiner turns and looks up, gives up, moves the mouse while dead
  without effect, and respawns level with the downed yaw: its camera's forward horizontal, the facing at the
  respawn's `Correction` and in the first claim after it level, and a level head on the host's screen; seen
  failing first; its raise test now also keeps the look through the knockdown's `Correction` and the revive),
  `player_network_test.gd` (a refused claim's `Correction` keeps the look), `player_controller_downed_test.gd`
  (the dead and the left neither turn nor tilt; `look_level()`), `client_session_claims_test.gd` (`set_facing`).
- Not headless: the mouse itself (headless keeps no mouse mode, so the tests call `look()`, which the mouse's
  `_unhandled_input` calls); the respawn part of the one-PC playtest.
- #240: a player who died looking up and was next placed by a new match, not a respawn, kept that pitch. A
  `PlayersPlaced` that names the own player (`End -> Lobby`'s and the deal's, the only two, both naming everyone
  present) now calls `look_level()` as the own `Respawned` does (`PlayerController._places_level`; the engineer's
  answer on #240, option (b): every placement (the lobby's and a new round's) starts level, the yaw kept). It
  comes right before the placement's `Correction`, so that `Correction`'s facing is level too. A `Correction`
  alone (a refused claim, a knockdown), a revive, and another player's respawn or placement keep the look.
- Tests (#240): `life_network_test.gd` (a joiner who died looking up, the round won before its respawn, is level
  with the yaw it had after `End -> Lobby`'s placement and its `Correction`'s facing; it looks up in the lobby and
  the next deal levels it again; seen failing first), `player_controller_downed_test.gd` (only a `PlayersPlaced`
  naming the own player or the own `Respawned` levels; another's keep the look). `NetPair.win()` ends the round
  (the fixture's crew win) for it.

#### 4.7.14 What the client renders
What the client renders follows the ADR's checklist (its §3), which `netcode-security-reviewer` checks on every
M4 client PR: only the own model, the interpolated poses and the own mode; spectating from the public snapshot only;
the downed camera at or below eye height, never through the level, and showing nothing out of sight of the body's
eye; no screen with an item's or a player's
position, and no name or marker over a player or an item drawn through walls (`no_depth_test` is for the fixed,
public circles only, the destination marker of D10 (b) included; a zone's fill, which tells that a living player
stands there, is depth-tested like the zone and hidden by the downed camera's sight hiding, with no marker, label or
HUD line, §4.7.24); a role named only on its
own player's screen (a dissident's teammates on theirs); no hit confirmation for
the attacker beyond the accepted exceptions; hidden information in debug builds only (the debug overlay, F3).
World sounds play within the hearing range only (E33), measured from the ears (E40). What the client plays of voice
follows the M5 ADR's checklist (its §3; §6 below).

#### 4.7.15 Built in M5-5 (#219), hearing voice
- `client/world/`: `VoiceViews` (`Voices` under `World`, physics priority 8, after `LifeView` placed the ears) plays
  `ClientSession.voice_received(speaker, seq, tick, opus)` frames through one `VoiceSpeaker` per speaker on its
  `RemotePlayerBody.mouth_point()` (eye height − 0.1 m, a placeholder), by the rules of §6.5.4 Playback and the ears.
  `WorldSounds` plays on the Effects bus and measures its range from the viewport's current `AudioListener3D`.
- `client/life/`: `Ears` (an `AudioListener3D`; `Ears.point()` and `lying_head()` are pure), placed by `LifeView`
  after the cameras in each physics step, turned with the current camera, current while a session runs. `LiftMusic`
  plays on the Music bus.
- `client/audio/`: `AudioBuses` (Voice, Effects, Music), made by `Game._ready`. `Game` gives `VoiceViews` a
  `TwoVoipCodec` unless a test sets `voice_codec`; without the addon nothing is played and the game runs.
- `client/ui/`: the debug overlay's voice lines, one per speaker by index of first arrival (`DebugOverlay.voice_text`).
- Tests: `tests/integration/client/world/voice_views_test.gd` (the rules over a hand-folded model, each seen failing on
  a plant: the dead check, the flush at the own `Died` and at a `KnockedDown`, the late frame stamped before a
  knockdown and delivered after it and after a revive, the speaker's life, the ears' distance; a downed listener
  still hearing the living, the own death recording the flush of a peer with no speaker yet),
  `voice_views_audio_test.gd` (the fake codec through real players and the Voice bus under the Dummy driver; seen
  failing without the flush and without `max_distance`), `tests/integration/client/life/life_ears_test.gd` (seen
  failing with the ears left at the camera or unturned, a dead player's ears off its body, and world sounds measured
  from the camera), `tests/integration/voice/voice_speaker_test.gd` (a frame that does not fit the playback dropped
  and counted), `tests/unit/client/life/ears_test.gd`, `tests/unit/client/audio/audio_buses_test.gd`, the overlay's
  voice lines in `debug_overlay_test.gd`, and `Game`'s buses, voices and their reset at a session's end in
  `game_loop_test.gd`.
- Not headless: how a voice sounds (the direction, the fade to 8 m, no pop at the edge, the downed hearing from the
  body); the one-PC listening test of the M5 ADR's §6, after M5-6.

#### 4.7.16 Built in M5-7 (#221), occlusion's muffle
(the CC0 files had not arrived: they, their credits and CI's LFS step are
a follow-up on #144 and #145):
- `client/world/`: `Muffle` (pure) holds how muffled one sound is: 0 clear, 1 behind the level; it eases over
  100 ms, gives the player's offset (−8 dB at 1) and its bus (muffled from 0.75 on the way in to 0.25 on the way
  out, so a ray flickering at an edge does not flip it), and jumps to the ray's answer at a speaker's first audible
  frame after a silence. `Muffle.blocked()` is the one ray, `SightHider.sees` on the world layer (a hit within 0.1 m
  of the ray's end does not count).
  `VoiceViews` casts it each physics frame for each audible speaker (active, not fading, within `max_distance`;
  `rays` counts them) from the ears to the mouth, and sets the speaker's `extra_db` and bus; `WorldSounds` casts it
  once per sound as it starts (`rays()`, `muffled()`), to the sound's `aim`: 1 m above a swinger's feet (about the
  chest) or 0.3 m above an item, placeholders, since a ray to a point on a floor, step or table reaches it only from
  above (a curb in front of the feet, or ears below the swinger's step, would muffle a sound in plain view).
- `client/audio/`: `AudioBuses` adds `VoiceMuffled` and `EffectsMuffled`, each made after and sending to its clear
  bus (its slider still applies) with one `AudioEffectLowPassFilter` at 1 kHz. `voice/`'s `VoiceSpeaker` adds its
  owner's `extra_db` (never above 0) to the fade's volume.
- The mechanism, measured headless under the Dummy driver by a probe not kept in the repo (a looping 400 Hz or
  3 kHz tone on an `ATTENUATION_DISABLED` player with an 8 m `max_distance`, at 0.5, 2 and 6 m): the player's own
  `attenuation_filter_cutoff_hz` (1 kHz) with `volume_db` −8 lowered 400 Hz by 7.7, 8.6 and 12.7 dB and 3 kHz by
  39 to 43 dB, since Godot's attenuation filter is a high shelf whose depth follows the distance fade and
  `volume_db`; a bus low-pass at 1 kHz with −8 dB lowered 400 Hz by 9.3 dB and 3 kHz by 28 dB at every distance. So
  the dullness is the bus's and the 8 dB the player's own `volume_db`, which eases per speaker (a shared bus
  cannot). Through `VoiceViews` behind a fixture wall at 3 m (`voice_views_audio_test.gd` prints it): 400 Hz 9.2 dB
  lower, 3 kHz 36 dB.
- Tests: `tests/unit/client/world/muffle_test.gd`; `tests/integration/client/world/voice_views_muffle_test.gd` (a
  wall between muffles from the first audible frame, one aside does not; boxes on the LIVING and DOWNED layers and a
  remote player's body on the line muffle nothing; one ray per audible speaker per physics frame, none for the
  silent or past the cutoff; eased in and back out; a speaker heard again starts at its ray's answer; a railing below
  the mouth muffles nothing; a body freed without `PlayerLeft` takes its muffle along; seen failing with the ray
  removed, with a ray that also sees the players' layers, and with an ease that never goes back);
  `voice_views_audio_test.gd` (the Voice bus behind a fixture wall: quieter at 400 Hz and much duller at 3 kHz; seen
  failing without the ray and without the muffled bus); `world_sounds_test.gd` (muffled behind a wall, clear in the
  open, one ray per sound, no ray out of range, capsules muffle nothing, nor do the floor under a package and a curb
  in front of it, while a wall just in front of the ears does; seen failing without the ray and with the ray aimed
  at the sound's position); `voice_speaker_test.gd` (`extra_db` adds to the fade, never louder); `audio_buses_test.gd`.
- Not headless: how the muffle sounds (8 dB and 1 kHz are placeholders, the bus switch within the ease, a door
  jamb's edge): the listening test of the M5 ADR's §6.

#### 4.7.17 Built in M5-6 (#220), speaking (§6.5.3 Capture and the gate)
- `voice/`: `VoiceCapture` (the device list, the chosen device opened, every whole 20 ms chunk at the device's rate
  with its age, errors in words, the "opening" mark through `mark_changed`) over a `VoiceMicrophone` (the machine's,
  through 4.7's `AudioServer` input API; `VoiceToneMicrophone`, the debug test tone; the tests' `FakeMicrophone`).
- `client/voice/`: `VoiceSender` (a node under `Game`) drains the capture each frame, encodes every chunk, feeds each
  to `VoiceGate` with that frame's `may_speak` and talk key, and sends what leaves through `ClientSession.send_voice`;
  `may_speak_of(model, mode)` is the own life fold living and `VoiceRule.radius_of` of the current phase > 0 in the
  client's own mode. What waits when `may_speak` turns true, or after `ClientModel.silencings` (each phase change,
  each time the own life leaves living) moved since its last step, goes as unspeakable (§6, #241). `VoiceControl`
  applies `UserSettings` to the sender and the buses and takes the Voice tab's changes; which microphone opens, the
  mark and the modes are §6's.
- `client/app/`: `UserSettings` (`user://settings.cfg`, or `settings_<n>.cfg` for `PRIME_INSTANCE` n > 1: the
  microphone, the mode, the threshold, RNNoise, the four volumes, the mark; written on each change). `Game` reads this
  window's file unless a test sets `settings` (with `read_command_line` off, as in tests and playcheck, the settings
  stay in memory and touch no file), wires the tab, gives the sender each session, counts the talk key
  (`voice_talk`, V) only without the Esc menu, and closes the microphone on exit. `project.godot`: `voice_talk` and
  `audio/driver/enable_input`.
- `client/ui/`: `VoicePanel`, the Esc menu's Voice tab in every screen (`EscMenuState.Tab.VOICE`, last in the enum so
  the previews' saved numbers hold); the lobby HUD's hint until a microphone is picked; the debug overlay's own voice
  line (`DebugOverlay.own_voice_text`: gate, peak, frame age, encode µs). No talking indicator (D14).
- Tests: `tests/unit/voice/voice_capture_test.gd`, `voice_gate_test.gd` (an empty frame while closed empties the
  pre-roll; the threshold clamped above 0; each seen failing first), `tests/unit/client/voice/voice_sender_test.gd`
  (seen failing on a planted widening: no life check, no drain while unspeakable; and, #241, a knockdown and its
  revive, or Round, End and Lobby, folded between two steps, seen sending their backlog before `silencings`), the
  count in `tests/unit/client/net/client_model_test.gd`, `voice_control_test.gd` (the mark
  in the file before the device opens, seen failing with it emitted after),
  `tests/unit/client/app/user_settings_test.gd`, `tests/unit/client/ui/voice_panel_test.gd`, the Voice tab in
  `esc_menu_state_test.gd`, the own voice line in `debug_overlay_test.gd`,
  `tests/integration/client/app/game_voice_test.gd` (the saved settings applied, the tab's changes saved, a word into
  a client's fake microphone delivered at the host), `input_actions_test.gd`, and the runner's `PRIME_INSTANCE` per
  window in `tools/runner/tests/test_hostjoin.py`. `shot`: `client/dev/esc_voice_preview.tscn`,
  `debug_overlay_voice_preview.tscn`.
- Not headless: a real microphone (headless runs open none: the Dummy driver captures nothing), the #22 laptop's
  windowed start with input enabled (the M5 ADR §6), and the one-PC and two-machine listening tests.

#### 4.7.18 What stays headless
`HostSession`, `ClientSession`, `ClientModel`, `DecodedView`, the bots runner and the leak
test, `host` and `join` with `--headless`, and every GdUnit4 suite. A bot loads no scene.

#### 4.7.19 `host` and `join` with windows (E20)
`tools\run.cmd host [--clients N]` and `join <address>` run the game scene
in windows, tiled on one PC with `--position`, with Vulkan as everywhere on Windows; `--headless` runs the M3
session of §4.6. In a shell where `CLAUDECODE` is set (an agent's) the default stays headless, so an unattended run
never opens a window on a human's screen.

#### 4.7.20 Built in #149 (M4-6) in `tools/runner/hostjoin.py`
Each window is `client/app/game.tscn` with the arguments of
`LaunchOptions` after `--` (`--host [--local]` or `--join=<address>`, `--port=`, the runner's stop and alive files),
so it skips the menu, and stops cleanly for the runner as the headless session does. The console exe (`GODOT_BIN`)
opens them, since the runner reads each process's lines (the host's `session: hosting` starts the clients; a host
that prints `session: cannot host` stays at its menu and gets none). A host and its `--clients` are tiled in a grid
over the primary screen's work area (`--position` and `--resolution`, 16:9, below each title bar and inside its
frame; a lone window goes where the system puts it); a windowed host on every interface prints what to type on
another PC. Each process gets `PRIME_INSTANCE` (1 the host, 2 and on the clients in tile order; M5-6), so each window
keeps its own settings file. `--windows` opens windows where `CLAUDECODE` is set; agents never pass it. They run
until Ctrl+C, `--seconds` or every window closed. A window never welcomed into a lobby fails the run with the game's
`cannot host` or `ended:` line, since the game exits 0 from its menu.
Tests: `tools/runner/tests/test_hostjoin.py` builds the command lines without starting Godot (the defaults, the
tiles, `--headless`), and `verify`'s `game` step runs `game.tscn` headless through that command line: a host
(`--local --no-replay`) and one client over ENet on a free port of 127.0.0.1, both welcomed into the lobby, then
both stopped through the stop file with exit 0 and no engine error line (about 5 s).

#### 4.7.21 The import before a launch (#174)
Only an import rebuilds Godot's global class cache, the uid cache and the
imported assets, so a game started after a `git switch` that brought a new `class_name` script failed to parse
(`Identifier "MousePointer" not declared`, the engineer's playtest). `check.ensure_import()` runs before Godot starts
in `host`, `join`, `run` (and through it `perf` and `bots`), `playcheck`, `shot` and `verify`'s `game` step: it
imports when there is no class cache, no record of an import through the runner (`.godot/runner_import.stamp`, which
every `check.run_import` and the post-edit hook's import write through `check.record_import`, never later than
the import's end), or a file Godot sees is newer than that record, and prints one line either way; a file dated in the
future is a warning that names it, and every launch imports until it is touched.
The test walks the project (no hidden folders, none with a `.gdignore`, no Markdown or Python) in 0.03 to 0.04 s
against about 10 s for a quick import that finds nothing to do. A linked worktree's `override.cfg` is written first.
Tests: `tools/runner/tests/test_import_freshness.py` (the test over throwaway folders, the stamp, the override
before the import, each command's order of finding Godot, importing and starting it, and, with the pinned Godot, a
`class_name` script added after the import: the game fails without the import and `run` imports first and passes).

Built in #515 ([LFS ADR](decisions/2026-09-29-git-lfs-for-binary-assets.md), amendment of 2026-10-07): in CI
(`common.IS_CI`, and a Claude Code cloud session, `common.IS_CLOUD`: checkouts that may have no LFS content) every
`check.run_import` keeps the LFS pointer files from Godot's import (`lfs.aside`), whose import of one fails and
rewrites its `.import` file. Each pointer file goes into `tools/out/lfs-aside/` (behind a `.gdignore`); a type with a
stand-in (`lfs.STAND_INS`: PNG, JPEG, WebP, BMP, TGA, WAV, glTF, GLB, OBJ) gets a minimal valid file of its type in
its place under its committed `.import` file, so Godot writes the imported file every use of the asset loads (later
steps too); a type without one has its `.import` moved too. All of it goes back afterwards as it was, even when the
import fails. `check`'s project check then drops the lines that name a hidden pointer file, its imported file or a
script that failed to load because of one (`lfs.drop_lines`), in one `skip` line with the counts; the credits check
still covers pointer files. `check --lfs-content` fails on any pointer file, with no Godot (a build's step before its
export). Locally nothing is detected and nothing changes, but `check` warns when the checkout has pointer files
(`lfs.local_hint`, with `git lfs pull`). Not covered: for a type without a stand-in, a `class_name` that preloads one
breaks its users in CI, and the `test`, `bots` and `game` steps print Godot's errors for it.
Tests: `tools/runner/tests/test_lfs.py` (detection over a throwaway git repository in CI, cloud and local mode and
in a folder that is not a git work tree, the stand-ins and the move and their way back after a failed import, the
dropped lines of a probed run, the credits check on a pointer file, `--lfs-content`, and, with the pinned Godot, a
committed texture checked out as a pointer file: in CI mode the import prints no error and leaves its `.import` file
as it was and `check` passes with nothing dropped, a script that uses a preloading `class_name` included; in local
mode both fail as before; and every stand-in imported under the `.import` file a real import of it wrote).

#### 4.7.22 `playcheck`: scripted windows with screenshots (#186), the AI productivity design's P9
(`docs/decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md`, item 8), for the UI and camera bugs that
only a playtest saw (#168, #169). `tools\run.cmd playcheck [scenario ...]` runs each scenario of
`tools/playcheck/scenarios/` as `host` would with windows: window 1 is `game.tscn` hosting on 127.0.0.1 (`--host
--local --no-replay` on a free port), up to two more windows join it, and the players after them are bots in one
headless process (`tests/harness/playcheck/`: `NetPlay`'s bots playing a `BotScenario`'s scripts over ENet). Each
window runs under `tools/playcheck/playcheck_window.gd`, a `SceneTree` script under `tools/` that adds `game.tscn`
with its `LaunchOptions` arguments and runs that window's steps (`playcheck_steps.gd`). A wait reads only the
window's own `Game.client()` (its `ClientSession` and `ClientModel`), its screen, Esc menu and pointer, never
`HostSession`, the match or `core/`, on the host's window too (invariant 2), so a window that draws before its
filtered event arrived fails its wait instead of being covered by the host's state. `wait text <field>
is|has|lacks <text>` and `wait shown <field> on|off` (#275) read what the window draws: the `Hud`'s labels, the
`LifePanel`, the `LobbyHud`, the `EndScreen`, the visible Esc tabs and the kind in the `FirstPersonHand` under
`get_viewport().get_camera_3d()` (the own hand, or the spectated target's), from its own `GameUi` and camera only;
the field list is `FIELDS` in `tools/runner/playcheck.py`, with the same keys in the window's `GameView` (a test holds
them equal). Whitespace runs count as one space and a hidden field reads as "", and scenarios assert short `has` and
`lacks` parts of the greybox wording (#150). `button <text>` gives the one visible, enabled `Button` of the Ui with
that text the focus and `ui_accept`'s key, so no mouse event captures the mouse. With no mouse look, `aim item
<kind>` (until `aim off`, #276) turns the window's own local player and nothing else: each frame it reads the
nearest item of that kind resting (no holder) in the window's own `ClientModel`, whose positions every client is
sent, and calls `PlayerController.look` on `Game.player()` to face its middle (`ItemView.centre_of`), as mouse motion
would. The pick-up hint stops a walking margin short of the host's reach (#319, §4.7 "Interactions"), so a scenario
presses `interact` the moment the hint shows, with no settle step (`items.txt`, #353). Keys go in through
`Input.parse_input_event`, before the frame's `_process`, so actions polled there (`interact`, `swap`, `put_down`)
see them as just pressed; holds through `Input.action_press`, screenshots through
`Viewport.get_texture().get_image().save_png` after `frame_post_draw`, as `shot` does. The windows sit at `shot`'s
off-screen position (never headless: Godot then draws nothing), with the dummy audio driver and a `MousePointer`
that only remembers, so the real mouse is never captured; what needs a captured mouse (`use`, spectate cycling)
stays with the playtest. Window 1 sends the setup (`ForceRole`, `ForceClock`, `ChangeSettings`) as the host's own
client once every player is in its roster (within the scenario's `timeout`, plus `BOTS_START_SECONDS`, 60 s, when
bots play, #406); peer ids travel as `peer-<n>` files, as over ENet in `bots`. The bots'
process starts beside the windows: the bots play once every player is in each bot's lobby, and a bot whose join
went unanswered (window 1 not listening yet) joins again, `BotsEnet`'s start (#318, §4.6.2 "bots runner"). Nothing in
`client/` changed for it. The stop is `host`'s: the stop file, then a kill once a process's grace has passed, 30 s
for a window (`WINDOW_GRACE_SECONDS`) and `host`'s 10 s for the bots; the report gives each one's time from the stop
to its exit. A window's grace is longer because its exit can wait seconds on the GPU driver (#354): on a PC whose
every core runs normal-priority work (32 busy loops on 16 cores), the main thread waits in the renderer's teardown on
NVIDIA's D3D user-mode driver threads (`nvwgf2umx.dll`), which run at idle priority and stay Ready with no CPU until
Windows lifts a starved thread, about every 4 s; such windows took up to 9.5 s to exit after `session: stopped`
(about 75 runs), a headless bots process about 1 s. **Known load limits** (#354's runs of `playcheck spectate`
before its fix, beside 32 busy loops on 16 cores, PR #394; #406): besides the slow exits, one run each failed with an
honest bot corrected outside a placement, with a Godot process that exited with 0xC0000142 (Windows'
STATUS_DLL_INIT_FAILED: it could not start; AGENT_WORKFLOW §11.16 since #441), and with window 2 not finishing its steps
(`wait life dead`); one more, under the other workflows' load alone, with player 2 never downed though the bot had
finished its script (the next run passed). Five failed because the bots' process, which starts only once window 1
hosts, joined so late that window 1's setup timed out after 30 s with 2 of 3 players: since #406, when bots play,
the setup and, in every other window (window 1 too without a setup), the first wait after its first `press ready`
wait `BOTS_START_SECONDS` (hostjoin's 60 s for a host to start listening) longer, since the round needs the bots in
and ready; the other waits keep their timeout. The rest stay known limits: on a PC at full load a red `playcheck` is run again once the
load ends before it is debugged. Desktop only; CI and `verify` never run it. Usage: `docs/AGENT_WORKFLOW.md` §11.
Tests: `tools/runner/tests/test_playcheck.py` (the scenario parser and its errors, the plan, the command lines, and
runs of stand-in processes that pass, time out, fail a step, print an engine error or miss a PNG, each stopping
every process; windows that exit slowly within their grace beside bots killed after theirs; the setup's and the
first wait after `press ready`'s added wait for the bots' start, #406; the text, shown and button grammar and `FIELDS` against `GameView`'s keys), `tests/scenarios/playcheck_bots_test.gd` (the bots' start,
#318) and
`tests/unit/tools/playcheck_steps_test.gd` (the steps over a fake view and clock: a wait passes at once or fails at its
timeout and not before, with its line and what the window saw; frames; events matched once through player numbers;
the setup; `is`/`has`/`lacks`, collapsed whitespace, a hidden field read as "", shown on and off; the `button` step's
one visible, enabled button or its failure; `aim` as an action step, the nearest resting item it picks and the
turn that makes a real `PlayerController` face a target). The scenarios `esc_menu` (#169), `spectate` (#168),
`items` and `end` (#276) are its own checks, run on a desktop; since #275 they assert the Esc tabs, the lobby
roster and countdown, the life panel, the spectator HUD and the knife in the first-person hand besides their PNGs,
and since #276 the Hand and Belt lines through a pick-up, a swap and a put-down, the end screen's winner and its
host-only Back to lobby, the lobby's cleared ready flags after End and a second round.

#### 4.7.23 Tests
The logic lives outside scenes where it can (the flow, the launch options, the end reasons,
`SnapshotBuffer`, `PredictedStamina`, the countdowns, the spectate targets, the HUD's texts, a zone's fill),
unit-tested headless in `tests/unit/client/`. `tests/integration/client/` drives physics headless: the real `PlayerController` walking,
sprinting, jumping and climbing steps through a `ClientSession` over a `LoopbackHub` to a `HostSession` on a fixture
level is corrected 0 times; the downed camera against a fixture wall never rises above eye height or passes the wall,
and an item visible from the arm's end but not from the pivot is hidden;
the two-client push runs over the loopback with the interpolation delay. Key events can run headless through
`Input.parse_input_event` (#169); the mouse mode and the look of the UI cannot: every
screen and view gets a `shot` of its preview scene in `client/dev/`, `playcheck` (#186) screenshots the real game in
off-screen windows at the named steps of a scripted run and asserts what they draw (#275), and the playtests of the
ADR's §6 check the rest.

#### 4.7.24 Built in M7-Z4 (#650), the zones, their fill and the done look
The client side of the zone task (§9.5.17; the [zone task ADR](decisions/2026-10-09-m7-zone-task.md)'s ZD6 (a),
ZD11 (b) and ZE8, as the engineer answered them on #302).
- **Which stations are zones.** A station whose kind is the `zone` of a `ZoneTask` in the client's own copy of the mode
  (`ZoneViews.zone_task(mode, kind)`); `CircleViews` leaves those out and draws every other station kind as before.
- **The model** (§4.6.1.2): `ClientModel.Station` holds the last `ZoneProgress` (`ticks`, `needed`, `counting`,
  `progress_tick`) and sets `done` from it. The client predicts nothing: the local player stepping in sees the fill
  start about a round trip later (its claim to the host, the event back), and a knockdown or a push the client has
  not heard of never shows a fill that runs and then jumps back.
- **The fill** is pure (`ZoneViews.ticks_at(station, now)` and `fill(station, now)`): the event's `ticks`, plus the
  host ticks since its `tick` while it counts, capped at `needed`; a host tick behind the event or unknown (-1) adds
  nothing; a done zone is full; a zone with no `ZoneProgress` yet is empty. `now` is `AvatarViews.host_tick()`, the
  estimate the match clock reads; between two events the fill errs by at most the host's window (5 ticks), and the
  next event's `tick` sets it right.
- **The look** (ZD11 (b), greybox placeholders until the art pass): `ZoneViews` (`client/world/`, under `ItemWorld`
  beside `CircleViews`) draws each zone at its station's position as a faint flat disc of the zone's radius, a ring
  (`TorusMesh` squashed to a band about 1 cm tall, resting on the fill) at that radius and a fill: a second flat disc
  scaled from the centre, its radius the share of the time counted, hidden while empty. All three are unshaded,
  translucent, in `StationPlaced`'s colour (the palette is the data's: yellow, provisional, #302) and ordered disc,
  fill, ring among themselves by a small `sorting_offset` each (2 cm apart), with `render_priority` left at 0 so they
  sort by camera distance against every other translucent object, the delivery circles' cylinders included. A done
  zone is full and dimmed (darker, fainter fill and ring). It is flat on the floor, so it never reads as a delivery
  circle's cylinder.
- **The render checklist** (the M4 ADR's §3): every material is depth-tested (no `no_depth_test`; items 5 and 10), so
  the fill never shows through walls; there is no through-walls marker, label or HUD line for zones and no zone
  sound (ZD11; sounds come later, within the hearing range). Item 3: the fill tells that a living player stands in the
  zone, as an avatar does, so it sits under a `FillSight` holder in `SightHider.GROUP` (its sight point the zone's
  centre 10 cm up): while the downed camera is in use it shows only where the body's eye could see that point. The
  holder's `visible` is `SightHider`'s; the fill inside keeps its own (empty or not). The disc and the ring are the
  zone's fixed, public place, like the level, and stay drawn. The task screen is unchanged: its rows are `TaskState`s.
- Tests: `tests/unit/client/net/client_model_test.gd` (the fold), `tests/unit/client/world/zone_views_test.gd` (which
  kinds are zones; the fill extrapolated, still, capped, done, never running backwards),
  `tests/integration/client/world/zone_views_test.gd` (the parts' sizes and colour, no circle for a zone, the fill
  following `ZoneProgress` and the host tick, the done look, every part depth-tested: seen failing with a planted
  `no_depth_test` on the fill and with `CircleViews` drawing zones, reverted; the flat ring and the parts' sort order;
  the fill hidden behind a wall by `SightHider` while the disc and the ring stay: seen failing without the group,
  reverted). The `shot`s:
  `client/dev/zones_preview.tscn` (a zone empty, counting, paused, done, beside a circle) and
  `zones_preview_low.tscn` (at eye height: a wall hides a counting zone and its fill); they use the base mode's
  `ZoneTask` once M7-Z3 adds one, a stand-in of their own until then.

### 4.8 Signalling (M6-5a, #366)
How a host and a joiner find each other before WebRTC connects (the
[M6 design](decisions/2026-10-04-m6-playable-over-the-internet.md) §2.3, §2.4; E52, E53, E55). The protocol is
versioned apart from the game's wire (`"v"`, 1 today) and changes no row of §4.3. It carries no game data.

**Pieces** (`net/signal/`): `SignalCodec` (the messages, their fields and checks), `SignalRouter` (the service's
rooms and routing, with no sockets: a socket number in, the messages to send out), `LanSignalling` (the router over
`ws://` from `TCPServer` and `WebSocketPeer`, served by the host itself on a LAN and in every headless test) and
`Signaller` (the client side for a host and a joiner over `WebSocketPeer`; its signals fire from `poll()`; a socket
still connecting after `CONNECT_TIMEOUT_MS`, 5 s, the engineer's choice on #474, is closed and `closed` fires: on
Windows a refused connect stays connecting until the engine's 30 s TCP connect timeout, #431, #461). The Worker
(M6-5b, `tools/signal/`) implements the same router in JavaScript.

**Messages:** JSON text, printable ASCII (tab, CR and LF allowed: no `get_string_from_utf8` engine error a peer could
repeat), at most 16 KB (16384 bytes, counted before parsing), each with `"t"` (the type) and `"v"`. Integers are JSON
numbers without a fraction; the content hash, an s64, travels as 16 lowercase hex digits (its little-endian bytes;
`SignalCodec.content_text`), since JavaScript numbers lose an s64's low bits.

| From → to | Type and fields |
|---|---|
| host → service | `open {protocol: u16, content: hex16, max: 1..255}` (the first message; `max` is how many joiners at once, the mode's maximum minus the host); `offer {to, id, sdp}`; `candidate {to, mid, index, cand}`; `close`; `reopen` |
| service → host | `room {code, ice_servers}`; `join {from}` (joiner `from` wants in); `answer {from, sdp}`; `candidate {from, mid, index, cand}`; `error {why}` |
| joiner → service | `join {code}` (the first message); `answer {sdp}`; `candidate {mid, index, cand}` |
| service → joiner | `found {protocol, content}` (advisory, §2.5 of the M6 ADR); `offer {id, sdp, ice_servers}`; `candidate {mid, index, cand}`; `error {why}` |

`to` and `from` are the service's number for a joiner in its room (1 upward, never reused in that room), not a game
peer id: the game's id comes in `ADMIT` (§2.3 of the M6 ADR). `id` is the host's id for that connection attempt,
which the service checks as an id (1 to 2^31 - 1) and otherwise passes on. `sdp` is 1 to 12288 characters, `cand` 0 to 1024 (empty: end of candidates),
`mid` 0 to 64, `index` 0 to 255; `ice_servers` is a list of at most 8 `{urls: [1 to 4 "stun:", "stuns:", "turn:" or
"turns:" URLs], username?, credential?}`. Codes are 6 characters from the 31 that cannot be misread
(`23456789ABCDEFGHJKMNPQRSTUVWXYZ`: no 0, O, 1, I, L), random per room.

**Rules** (the router's; the Worker keeps them):
- **Decoding:** over 16384 bytes is `too large`, unread. Not printable ASCII, not JSON or not an object is
  `bad message`. Any `"v"` but the integer 1 (missing included) is `update the game`, before the type is looked at.
  An unknown type is `bad message`; a type of the protocol that the sender's side may not send is `not allowed`; a
  field missing or out of its rule is `bad message`. Unknown fields are ignored, and every message sent on is
  rebuilt from the checked fields only, so nothing a sender adds passes through.
- **Roles per socket**, fixed by its first accepted message (the design says "first message"; a refused one fixes
  nothing): `open` makes it a room's host, `join` a joiner; a socket without a role may send only those two, and one
  whose `join` failed keeps no role and may try another code. A host's type (`offer`, `close`, `reopen`), or `open`
  or `join`, from a joiner gets `not allowed` and is never forwarded; so do `open`, `join` and `answer` from a host. A
  joiner's `answer` and `candidate` go to its room's host with its `from`, whatever they name (a `to` is dropped). The
  host's `offer` and `candidate` go only to the joiner of its own room named in `to`, else `no such joiner`. Joiners
  never see each other, and the host never sees another room.
- **Joining:** `join` of a code no room holds is `no such room`; of a closed room (`close`, entering Loading) `the
  match has started`, until `reopen`; of a room with `max` joiners `the room is full` (a joiner leaving frees its
  place). Otherwise the joiner gets `found` and the host `join {from}`.
- **ICE servers:** `room` carries the service's own (STUN from its configuration, E58); the service adds a joiner's
  to the host's `offer` to that joiner, never to `found`, so a code pasted in a public chat hands out no relay.
  `LanSignalling` serves an empty list by default (host candidates connect on a LAN and in tests); the transcripts'
  replay passes theirs. With TURN on (the Worker only, M6-10, below), `room` also carries a TURN credential minted
  for the host, and each host `offer` one minted for that joiner alone. The entries' keys (`urls`, `username`,
  `credential`) are the ones `WebRTCPeerConnection.initialize`'s `"iceServers"` takes (4.7.2's
  `extension_api.json`), so the WebRTC backend (`WebRtcTransport`, not built yet) can pass `room_opened`'s and
  `offer_received`'s lists on as `{"iceServers": list}` unchanged.
- **Caps** (placeholders, "not a decision"): 16 KB a message, received and forwarded: what the service adds (`from`,
  its ICE servers) can push a message at the cap over it, and the receiver would drop it unread, so the sender gets
  `too large` instead; 32 candidates per joiner each way, the 33rd refused with `too many candidates` to its sender;
  `max` joiners at once. Offers and answers are not counted: the service forwards each, and the host takes one answer
  per offer and the joiner one offer per attempt (§2.3 of the M6 ADR).
- **No reclaim:** the host's socket closing closes the room; its joiners get `the host left` and the service closes
  their sockets; the code is free, and hosting again makes a new room.
- **Closing after an error:** the service closes a socket a moment after the message that ends it
  (`LanSignalling.close_grace_ms`, 1 s): Godot's `WebSocketPeer` drops a message read together with the close (#366's
  probe: a text sent just before `close()` never reached the client), so closing at once would lose the reason.

**Shared transcripts** (`tests/fixtures/signal/`, one exchange per file, plain JSON): `config` holds the service's
`ice_servers` and the `codes` it hands out in order (so GDScript and JavaScript produce the same codes); `steps` are
`{"open": s}` (socket s connects), `{"gone": s}` (s closes), or `{"from": s, "send": {...}}` / `{"from": s, "raw":
"text"}` (s sends it; `"pad_to": n` pads the text with spaces to n bytes, `"repeat": n` sends it n times), each with
`expect`: in order, `{"to": s, "msg": {...}}` the service sends after that step, with `"close": true` when it then
closes s. Messages compare as JSON values (numbers by value, keys in any order). The flows: `flow_join`, `flow_closed`,
`flow_no_room`, `flow_wrong_version`, `flow_host_left` (the freed code handed out again), `caps_full`,
`caps_candidates`, `caps_too_large`, `caps_forwarded_too_large`; the forged types (the design's §5): `forged_offer`,
`forged_candidate_to`, `forged_close`, `forged_reopen`, `forged_from` (a joiner's `from`, a host's `ice_servers` and
`from`, all dropped) and `forged_roles` (a host joining or answering, a joiner opening, a host naming another room's
joiner). Both suites check the exact list, so a deleted transcript fails them. A file with `"turn_only"` (its text
says why) needs TURN credentials minted, from the fake API answers in `config.turn` (`key_id`, and `minted` in the
order the offers ask): `SignalRouter`, `LanSignalling` and the Worker's router test skip it, the Worker's service test
replays it, and `signal_codec_test.gd` checks that the joiner's codec decodes each of its messages to itself.
`turn_per_joiner` is the only one: a host and two joiners, `room` and each host offer with its receiver's own
credential, none in `found`, answers or candidates.

**Tests:** `tests/unit/net/signal/` (the codec's rules, the router replaying every transcript, a fuzz test of the
decoder: every truncation, every field of every type replaced by each other JSON type, oversized and deeply nested
input and random bytes give a clean reject or a canonical message and no engine error line) and
`tests/integration/net/lan_signalling_test.gd` (every transcript replayed byte for byte over real WebSockets on
127.0.0.1 through `LanSignalling` on a free port; a host and a joiner `Signaller` through a whole exchange with a
default `LanSignalling`; a `Signaller` dropping and counting in `rejected` what is not for its side, with no signal;
one still connecting to a server that never answers the handshake closed after its timeout).
`Signaller.room_found` gives the content hash as the s64 `ContentFingerprint` makes. The
design's §5 plant, the router forwarding a joiner's `offer` to the joiner it names, failed `forged_offer` in both.

**Decoding cases** (`tests/fixtures/signal/decode/decode_cases.json`, #368): 242 messages from every side with the
result Godot 4.7.2's `SignalCodec` gives, recorded from it; `signal_codec_test.gd` and the Worker's `codec.test.js` both
check every one. Godot's JSON parser is not `JSON.parse`: it takes a trailing comma in an object or list, a leading
zero, `1.`, and a raw tab or line break inside a string, and refuses a lone UTF-16 surrogate escape and a value nested
deeper than 1024 (the top one at depth 0). Its numbers come from `built_in_strtod`, not a correctly rounded parse: 18
mantissa digits (leading zeros count, so `0000000000000000001` is 0), a scale built from powers of ten that overflows
past 1e308 (so `1e-320` is 0), and a wrapping 32-bit exponent taken as at most 511. The Worker reads JSON with its own
port of those rules, so both answer every message alike. Two inputs make Godot print a line that is not an `ERROR:`
line, which a LAN peer can repeat: a `\u0000` escape ("Unicode parsing error") and an exponent past 511 ("WARNING:
Exponent too high"); `LanSignalling` serves the LAN only, so they stay.

**The Worker** (M6-5b, #368; `tools/signal/`, its README is the deploy page): `src/codec.js` and `src/router.js` are
`SignalCodec` and `SignalRouter` in JavaScript, rule for rule; `src/service.js` is the Durable Object's work, which
`src/worker.js` (the only file that needs the Cloudflare runtime) wraps.
- **One Durable Object holds every room**, not one per room: the room is named in the socket's first message, after it
  is open, and a socket whose `join` failed may try another code, so a socket cannot be routed to its room's object
  when it connects. It stays far below the Workers Free plan's limits (SQLite-backed objects only on Free).
- **Hibernation:** sockets are accepted with the WebSocket Hibernation API, so idle rooms cost no duration; the object
  may leave memory, and its constructor runs again on the next event. So the router's whole state is one record per
  socket (role, code, number, candidate counts; a host's record also holds its room), kept in that socket's attachment
  after every change, and the constructor rebuilds the router from the attachments. Socket numbers go on from the
  highest one held. A socket the router is done with says so in its attachment, `gone` (it closed or failed; marked
  before anything is sent) or `closing`, so no rebuild gives it back a role, even while the runtime still lists it.
  Joiners a rebuild finds without their host (its socket left while the object was out of memory) hear `the host
  left` at the next event and are closed after the grace, as the transcripts expect.
- **Closing after an error** as `LanSignalling` does: a socket the service ends (the host left) is marked closing in its
  attachment and closed 1 s later; it gets nothing more, and its messages and close are no events. A close whose timer
  was lost with the object's memory happens when the object wakes.
- **A client's close is answered by the service** (`SignalService.clientClosed`, #513), with the client's code when the
  runtime may send it (1000, 3000-4999) and 1000 otherwise (`closeReplyCode`), even when the service's handling of the
  close throws; an answer that fails is logged. Cloudflare's docs say the runtime answers a close itself from
  compatibility date 2026-04-07, but on the first deploy a close without a status (code 1005: a browser's or Node's
  `close()`; Godot's `WebSocketPeer.close()` sends 1000) was never answered. The likely cause, from workerd's source: the handler
  answered with the code it was handed, which the runtime's `close()` refuses (workerd allows 1000 and 3000-4999 under
  its strict rule). The redeploy smoke on #513 confirms or refutes it.
- **ICE servers** from `ICE_SERVERS` in `wrangler.toml` (`stun:stun.cloudflare.com:3478`, E58), checked by the
  clients' rules at start.
- **TURN** (M6-10, #375; D17 (b), E55; `src/turn.js`), on only when the secrets `TURN_KEY_ID` and
  `TURN_KEY_API_TOKEN` are both set (neither, or one alone, logged: no TURN, and the service is what it was).
  For the host's `room` and each host `offer` the service asks Cloudflare's TURN key API for a credential
  (`rtc.live.cloudflare.com/v1/turn/keys/<key id>/credentials/generate-ice-servers`, `{"ttl": 600}`: D17's 10 minutes,
  a placeholder, `TURN_TTL_SECONDS` in `[vars]` replaces it) and adds it after the configured servers: its `turn:`
  and `turns:` URLs only, none on port 53 (browsers block it, Cloudflare's page says), split into entries of at most
  4 URLs with the same username and credential, since Cloudflare answers 6 and the protocol's cap is 4; no protocol
  change. Minted per message for its receiver (the host's own with `room`, the M6 ADR §2.4), never with `found`, so
  a code pasted in a public chat hands out no relay and no joiner holds another's credential. Anyone with the
  service's address can still open a room, join it from a second socket and offer to get one: the code is no key to
  the relay, the address is. Each socket has its own queue: what follows a waiting message to the same socket waits
  for it (a candidate never overtakes its offer), no other socket waits, and each request starts at once. If the API
  fails, takes over 5 s or answers what clients would drop, or the credential would push the message over 16 KB, it
  goes without TURN and the Worker logs a line. A message still waiting when the object restarts (a deploy) is lost,
  and its client times out. Cloudflare's FAQ: a credential expiring while its relay is in use disconnects it "after
  a short delay".
- **Tests** (`tools/run.sh signal`, a `verify` step; Node pinned in `pins.py`, no npm package): every transcript
  through the router and through the service over fake sockets and state, each also with the router or the object
  rebuilt after every step (as after hibernation) and with the object rebuilt as a close wakes it, the close grace,
  the configuration, and the decoding cases; TURN over a fake `fetch` of Cloudflare's API (the requests and their
  TTL, a slow mint holding back only its own socket, the API failing or timing out, the cap, the configuration), and
  the answer to a client's close against a fake socket that refuses the codes the runtime refuses. Only the calls in
  `worker.js` are left to the deploy, and `tools/signal/smoke.js` checks a running service (it passes against a
  headless `LanSignalling`; against the first deploy it failed at the host's close, #513). The design's §5 plant, the Worker forwarding a joiner's `offer` to another
  joiner, failed `forged_offer` in both suites, then was reverted. M6-10's plants, the credential also on `found` and
  one credential reused for every joiner, each failed `turn_per_joiner`, then were reverted.

**Joining in the game (M6-7, #373;** the M6 ADR §2.3, §2.5, §3; D19, E51):
- **`JoinTarget`** (`net/transport/`) is what the player typed: a code (6 characters of the alphabet above, any case,
  spaces and dashes dropped) or a host's `address[:port]` (IPv4, IPv6 in brackets with a port, or a host name, so a
  playit.gg address works). `transport(kinds)` makes the join's backend (a code: `WebRtcTransport` at the service
  URL; an address: `EnetTransport`) and `join(join_address(), port)` starts it. `JoinTarget.SERVICE_URL` is the
  engineer's Worker (`tools/signal/README.md`), `wss://prime-game-signal.xperiaroco-36a.workers.dev/` since 2026-10-07
  (#513). `--signal=<url>` overrides it; an empty one (`--signal=`) makes a code join end as `service_unreachable`
  (use Direct) and a code host refuse to start.
- **The menu** (`MainMenu`): "Join with a code" (a field and Join), Host (a room with a code, `CodeRoom` over
  `WebRtcTransport`), and "Direct (LAN or VPN)": address, port, Join and Host Direct (ENet, as before M6). A host serves
  one backend, so a code host takes no Direct joiner and a Direct host has no code. A failed join returns to the menu
  with its reason; the fields keep what was typed.
- **The connecting screen** names the target the player typed and the step (`JoinProgress`): finding the game (a
  code, before `found`), connecting, joined (connected, before `Welcome`). **The version check** is the joiner's
  `WebRtcTransport`'s (`expect_protocol`, `expect_content`, which `JoinTarget.transport` sets): a `found` naming
  another protocol or content hash fails the join as `wrong_version` or `wrong_content` before any offer is applied,
  and the menu names the host's and the own ("another build" for the content); advisory only, `Hello` still decides.
- **Failures in words** (`EndReasons`): `no_room`, `joins_closed`, `wrong_version`, `wrong_content` ("another
  build"), `service_unreachable` (use Direct) and `host_unreachable`, which also covers a full host (it answers a
  joiner nothing, so the join times out after 15 s) and names the playit.gg fallback under Direct.
- **The lobby's code** (`LobbyHud` line, the Esc menu's Lobby tab with Copy): the host's from `CodeRoom` (the
  transport's `room_code()`), a code joiner's the code it typed, a Direct game's none. When the host's service goes
  away, `room_code()` turns empty and the line says the code is gone (no reclaim). No wire change.
- **No screen shows another player's address, candidates or relay status:** a source test holds that `client/` calls
  no address or ICE-state API and that `client/ui/` names no concrete transport (`EnetTransport`,
  `WebRtcTransport`, `LoopbackTransport`); the debug overlay takes only the own connection's `NetTransport.Route`.
- **F3's connection line** (§3 item 4 of the design, #431; debug builds only): the own connection's kind ("direct",
  "direct or relayed (WebRTC does not say which)", or "in this process" for the host's own player) and its round
  trip, from the own `ClientSession` (`route()`, `round_trip_ms()`), which has its transport measure only while F3
  shows (`set_measuring_round_trip`; WebRTC pings for it, §4 above). A source test holds that no `client/` file but
  `ClientSession`, and no `server/` file, calls the transport's own-connection API; `game_code_join_test` checks the
  joiner's line over real WebRTC and that the host's overlay shows nothing of the joiner's;
  `client/dev/debug_overlay_joiner_preview.tscn` shows a joiner's view for `shot`.
- **The command line and the runner:** `--host --code [--signal=lan --room=<CODE>]` hosts a room (`lan`: this process
  serves `LanSignalling` on TCP of its port); `--join=<code>` joins one through `JoinTarget.SERVICE_URL`, or through
  `--signal=ws://<host>:<port>`. `tools\run.cmd host --code [--clients N] [--local]` picks a random code and starts the
  clients with it; `tools\run.cmd join <code> --signal ws://<address>:<port>` joins from another machine (without
  `--signal`, through the deployed Worker). The headless session (`--headless`)
  does the same through `CodeRoom` and prints `session: room code <CODE>`.

## 5. Per-peer information filtering

- Each outgoing message is built for one recipient from what that peer is entitled to know.
- The information-leak test (bot harness, M3) asserts that no client ever receives anything it is not entitled to,
  connected peers that are not players included: they receive at most a `Rejected`, none unless they sent a `Hello`
  (§4.6.4's lurker). It is the most important test in the project. Once it exists, prove it: inject a leak, see it
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
  living or downed player's avatar (position, velocity, facing, the flag `downed`, hand and belt items) reaches every player of
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
  all public (`StationPlaced`, `ItemSpawned` with a package's circle and colour, `PackageDelivered`, `TaskState`, `TaskProgress`,
  and the zone task's `ZoneProgress`, which names no player and whose counting reads no role, #647); no
  task has an owner, and a subtask's detail stays in `subtask_done` (internal to the task type, not secret). No event
  names a killer; a player who watches the swings and positions (both public by the rules) may still work it out.
- **Widening** follows from evaluating audiences at emission. A knockdown, a death, a respawn and a revive widen
  nothing: the downed are public, `Respawned` is as public as the body it removes and the avatar that appears again,
  a raise and a revive are as public as the two avatars (M4-4), a dead player
  gets the same public snapshots as everyone (minus the dead), and the dead learn no roles and
  no event that a living peer present then does not get (the leak test checks it, §4.6.4; M4-2 tests the snapshots in
  `tests/unit/life/life_rules_test.gd`). End widens nothing: `MatchEnded` names only the winning
  side, and each player knows from its own role whether it won. A later mode that reveals roles would add an event with
  its own audience. A joiner's `Welcome` holds public facts only.
- **Knowledge never shrinks.** A peer keeps what it was sent. What a dead player saw while spectating, all of it
  public, is fair game after the respawn (vision revision 1, V1): nothing is narrowed then.
- **Projection.** `Match` records the recipients of every event it emits, and per tick each peer's snapshot and the
  voice routing (who hears whom). `Match.view_of(peer)` returns that peer's events in order, its snapshot for every
  tick, and the speakers it may hear per tick: everything an honest client of that peer can know. The per-tick
  snapshots and speakers are recorded only with `Match.keep_history` on (off by default: about 1 GiB for 10 players
  over 10 minutes); the tests and the leak test turn it on, a real host does not. `snapshot_for(peer)`, what `server/`
  sends each tick, is empty for anyone but a present player, and in a phase that sends no snapshots
  (`tests/unit/match/view_of_test.gd`). The M3 leak test
  compares what each bot actually decoded (voice frames included) with `view_of` of its peer; anything received that
  `view_of` does not hold is a leak (§4.6.4: the events exactly, the snapshots' avatars and the voice frames as
  subsets).
- **Invariants that do not trust the declarations.** A wrong audience (say `Teammates` declared *everyone*) would
  pass the comparison above, because both sides read the same declaration. So unit tests and the leak test also
  assert facts written independently of them: for the whole session, a crew member knows one role, its own, and a
  dissident knows the dissidents' roles only; no snapshot holds a dead player's avatar; the voice invariant (§6.3): no
  peer gets a downed or dead speaker's voice frame, a downed peer gets only the living's and a dead peer none;
  the distance invariant (M5-1, #215, E45): no peer gets a frame of a speaker farther away than the phase's hearing
  radius (`VoiceRule.radius_of`, the client's cutoff, E41) at the frame's tick, between the last accepted positions,
  in 3D, compared as `VoiceRule.within` does, and none under a radius of 0 (`ScenarioInvariants` per tick on
  `speakers_for`, `LeakCheck` per decoded frame; seen failing on a `RoundVoice` that ignores its radius, which
  `view_of` agrees with, §4.6.4.1);
  nothing reaches only the dead: every event a dead peer gets is for it alone or also reaches every living peer
  present then (`ScenarioInvariants` and `LeakCheck`, M4-2, each seen failing on a plant in `tests/scenarios/` and
  the first on `bots`, §4.6.4.1); nobody gets another player's health, stamina or damage; every player receives the same
  task events; no message holds a seed.

Rejected ways of expressing it (per field, per content part, filtering in `server/`): the ADR.

## 6. Voice pipeline

capture → gate → encode (Opus) → routing decision per speaker and listener (`core/` rules, applied by the host's
`server/`) → listener → jitter buffer → decode → `AudioStreamPlayer3D` on the speaker's avatar → the listener's ears.
- Routing inputs: distance, life (the voice invariant, §6.3), later items such as radios and role abilities. Walls
  do not enter the routing: they muffle on the listener (the M5 ADR's D13 (a), the engineer's answer). Dead chat and
  meetings, in the brief, are gone (vision revision 1).

### 6.1 Decided by the M1 spike ([voice ADR](decisions/2026-09-29-voice-approach.md): **go**; numbers in #15 and #16)
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
  - Check whether TwoVoIP enables Opus in-band FEC; `decode_fec` may only conceal a lost frame. (v6.5 with our
    settings does not: M5-3's round trip, below.)
  - Measure the host's per-send ENet cost with many listeners. In the spike, relaying one frame to one listener,
    ENet send included, cost 111–167 µs against 10 µs without the send, unexplained. At 81 sends per 20 ms that
    would be ~40 % of one core.
  - Godot 4.7.2 WASAPI reads only mono or stereo microphones; laptop arrays need 4.8 (#22). There is no
    input-latency API in 4.7.

### 6.2 Routing per phase in the base mode (#32; radii in the [MVP rules](decisions/2026-09-29-mvp-rules.md))
The mode's
data names each phase's rule (§3.1), so a new mode's rule is one more rule, not a change to the loop.

| Phase | Who hears whom |
|---|---|
| Lobby, Countdown | every pair within the voice radius |
| Loading | nobody: the old scene's positions are gone, and the phase lasts seconds |
| Round | the living hear the living within the voice radius; a downed player hears the living within it, measured from where it lies; nobody hears the downed or the dead, and the dead hear nobody |
| End | nobody: the game is frozen |

A player who left hears nobody and is heard by nobody.

### 6.3 The voice invariant (vision revision 1; built in M4-1, #137)
Nobody hears a downed or dead player, under
any voice rule, and a dead player hears nobody. `VoiceRule.speakers_of` drops every speaker who is not living
and gives a dead listener nobody before it asks the phase's rule, so no mode's data can route their voice; it
replaces 2i's "the living never hear a ghost". Tests: `tests/unit/content/voice_rule_test.gd`, under
`FixtureEveryoneHears`, a rule that lets everyone hear everyone; the leak test's checks (§5).

### 6.4 Built in 2i (#65, `core/voice/`)
`SilentVoice`, `ProximityVoice` and `RoundVoice` (§9.4); the base mode's
data names one per phase with the numbers of §9.5. A distance is between the two players' last accepted
positions (§7.1.2), in 3D, and a radius includes its edge, as the M1 spike's routing measured them (#15,
`distance_to(...) <= cutoff`, which the engineer listened to and accepted); 3D also matches the listener's fade.
A horizontal radius (a player on the floor above heard like one beside) stays a possible later change. M4-1
removed `RoundVoice`'s ghost radii: it keeps `living_m`. Tests: `tests/unit/voice/`.

### 6.5 Designed for M5
(#177, [M5 ADR](decisions/2026-10-02-m5-voice-integrated-with-the-rules.md), accepted on
2026-10-02: E34 to E47, D11 to D15; each part is rewritten here as built by its issue, M5-1 to M5-7, #215 to #221).
The lessons above, answered.

#### 6.5.1 The codec boundary, the gate and the jitter buffer (E34, E37, E38, E39; built in M5-2, #216)
`voice/`'s
`VoiceCodec` (`available()`, `new_encoder()`, `new_stream()`, `playback_of(player)`), `VoiceEncoder`
(`start(input_rate, denoise)` returns an error text, `encode(chunk)` one 20 ms frame) and `VoicePlayback`
(`push(frame, conceal)`, `queued_frames()`, `free_frames()`, `set_running(on)`, `flush()`) are what `client/`
and the rest of `voice/` use; each base is a codec that is never available. `TwoVoipCodec` (with
`TwoVoipEncoder` and `TwoVoipPlayback`) reaches the addon only through `ClassDB.class_exists`, `instantiate` and
`Object.call` with typed results, with the M1 spike's settings (48 kHz, mono, 960 samples, 24 kbit/s,
complexity 5, RNNoise or none) and the spike's method names; its class names are constructor arguments
defaulting to TwoVoIP's, so a test passes a missing class and sees it unavailable on any machine. Without the
addon every script parses, voice is unavailable and the game runs.
`VoiceGate` is pure: `feed(chunk, frame, may_speak, talk_held)` returns the frames to send, oldest first. Voice
activity (the default) opens while the raw chunk's peak is over `threshold` (0.05) and for a hangover of 300 ms
after; push-to-talk opens while `talk_held`; Off is a closed capture (M5-6). On opening, up to 2 frames of
pre-roll go first; the ring fills only while the gate is closed, so it holds only frames never sent and a gate
closed for one chunk sends no frame twice. `may_speak` false (`client/` decides it) closes the gate and empties
the ring, so no frame captured before it turns true again goes out. An empty frame (a failed encode) is never
sent nor kept for the pre-roll, though its chunk counts for the hangover; while the gate is closed it empties the
ring, so audio from before an outage never goes out as pre-roll (M5-6). `threshold` is clamped to 0.01 (−40 dBFS,
a placeholder) to 1: at or below 0 the gate would open on digital silence and a silent player would stream.
`VoiceJitter` is pure, one per speaker on the listener: `push(seq, tick, frame, arrival_usec)`, then once a frame
`update(queued_usec, now_usec)` returns the `Decode`s and `command()` says start, stop or flush. It orders by
the renumbered u16 seq (unwrapped), drops duplicates and frames older than the next due (`late`), waits for a
missing frame until the queue would run dry before the next update (within `DRY_MARGIN_USEC`, 10 ms), then
decodes the next packet held with `conceal` (FEC or concealment) and skips the rest of a longer run (`lost`);
a frame missing across a stop is skipped. It starts when the queue and the frames held reach the prebuffer and
stops when the queue runs dry with nothing held; a held frame whose host tick is more than 2 past the last
decoded frame's is the next spurt, never decoded into a run still playing, so a spurt after a pause of more than
2 ticks starts under its own prebuffer (a spurt that only the late-arrival rule below sees plays on in the run
still playing). The prebuffer is chosen at each start: the largest spread of
arrival offsets within one talk spurt over the last 2 s of frames, plus 20 ms, within 40 to 120 ms; a spurt
starts when a frame arrives more than 60 ms after its due time or its host tick is more than 2 past the newest
frame's. Under the tests' talk (polls 16.7 ms apart) it settles near 40, 59 and 105 ms at 0, 30 and 80 ms of
jitter, with underruns only before the window has seen the jitter. Frames held 200 ms without starting are
discarded (`stale`), counted from their arrival or the latest stop, whichever is later, so a spurt held while a
burst-filled queue drained still plays its first syllable (M5-5, #219); `fade_out()` lowers `gain()` to 0 over
50 ms, then says flush; `flush()` empties the held frames, and a frame older than the flush arrives late. A stream
that restarts at seq 0 gets a new `VoiceJitter`. No queue cap after a burst (the manager's call, until the
listening test shows a problem); `VoicePlayback.push` does not check for room either, so its caller (`VoiceSpeaker`,
M5-5) checks `free_frames()` first and drops a frame that does not fit. A known limit for the listening test (M5-6,
M5-7): a spurt shorter than the prebuffer never starts and is discarded as stale. A voice-activity spurt lasts at
least 320 ms (the hangover), so it reaches only a push-to-talk tap: a key held for one chunk sends 3 frames with the
pre-roll (60 ms), under the prebuffer once the window has seen more than 40 ms of spread. Every number here is a
placeholder, "not a decision".
Tests (no addon, no microphone): `tests/unit/voice/voice_codec_test.gd`, `voice_gate_test.gd`,
`voice_jitter_test.gd` and `voice_jitter_timing_test.gd` (through `voice_jitter_sim.gd`, a listener polling at
60 fps with a playback model), with the fake codec in `tests/fixtures/voice/` (8 kHz µ-law, 160 B per 20 ms,
played through an `AudioStreamGenerator`); `voice_addon_names_test.gd` fails on any script outside `addons/`
naming a TwoVoIP class; `tests/unit/client/app/client_boundary_test.gd` holds `res://voice` to E18's forbidden
names and to E46 (a). The real codec's round trip and FEC probe: `tests/integration/voice/twovoip_roundtrip.gd`
(`tools\run.cmd run tests/integration/voice/twovoip_roundtrip.gd --headless`; SKIP without the addon; not a
`verify` step). CI runs without the addon (§6.5.2).

#### 6.5.2 The addon in the repo (E35 (a), the ADR §2; **built in M5-3**, #217)
TwoVoIP v6.5 in `addons/twovoip/`,
plain git files outside LFS: the `.gdextension` and its `.uid` as shipped and the two Windows libraries, nothing
else (the helper scripts fail the warnings policy; the release archive ships no license file). Credits:
`docs/credits/twovoip.md`. Windows `verify` (every agent's, the engineer's, `publish`'s) loads it. CI on Linux
deletes `twovoip.gdextension` and its `.uid` before `verify` (`.github/workflows/ci.yml`; each night job of
`nightly.yml` too, which runs main), and a cloud session leaves both out of its clone with a sparse checkout
(`tools/cloud/setup.sh`, #345, AGENT_WORKFLOW §2.1), because Godot prints an
`ERROR:` line for a `.gdextension` it cannot load; with no `.gdextension` Godot loads nothing and voice is
unavailable (E34). The libraries stay as inert files: deleting the whole folder fails `check`'s credits step,
since `docs/credits/twovoip.md`'s glob would match no file. A checkout's `.godot/extension_list.cfg` lists the
extensions its last import found, and the runner's import before a launch (#174) compares modification times:
it sees the addon arrive with a pull (git dates the files now), not a delete, nor a hand copy that keeps the
archive's dates. After a local delete of the `.gdextension`, `run` still loads it and fails on the `ERROR:` line
until `check` imports. The round trip on Windows with v6.5 (M5-3): the encoder, the stream and the
playback work by class name with the M1 spike's method names, which v6.5's `ClassDB` lists as the spike used
them; a 440 Hz sine comes back at 439.5 Hz and its full level (rms 0.354). **No in-band FEC seen:** with
`TwoVoipEncoder`'s settings a frame decoded from the next packet with `conceal` is Opus concealment (the probe's
lost frame keeps the 440 Hz before the gap, with no trace of the 660 Hz after it), and v6.5's `ClassDB` lists no
setter for in-band FEC or the expected packet loss on `TwovoipOpusEncoder` (a listing in M5-3's PR), so
`VoiceJitter`'s `conceal` conceals. The encoder offers
`get_speech_probability()` (and `get_peak()`, `get_rms()`; `DENOISER_SPEEX` besides RNNoise). `flush()` (stop,
then play: v6.5's playback has no call that empties its queue) leaves nothing queued. `AudioStreamOpus` queues
2.0 s by default (one audio frame less than 2 s: the round trip sets 3.0 s, as the spike did).

#### 6.5.3 Capture and the gate (E36 as amended, E37, E38, D11; **built in M5-6**, #220; files and tests in §4.7.17)
- The microphone: `voice/`'s `VoiceCapture` over 4.7's `AudioServer` input API (`audio/driver/enable_input` on in
  `project.godot`); each frame every whole 20 ms chunk at the device's rate, with its age. Which device opens
  (`client/voice/`'s `VoiceControl`): none without the codec (voice unavailable, the Voice tab says so), none in
  Off, none in a headless run (the Dummy driver captures nothing, and headless sessions must write no mark); else
  the picked device, or before any pick the Windows default, so voice activity works without the menu.
- The "opening" mark (#22: Godot 4.7.2 freezes on a microphone of more than two channels and cannot tell the
  count beforehand): `VoiceCapture.mark_changed` names the device before it opens and `VoiceControl` writes it to
  the settings file at once; the first second of samples, a clean close or a refusal clears it. A mark found at
  the start keeps the microphone closed, with a line naming #22 and advising a headset, until the player picks a
  microphone (even the same one), so the #22 laptop freezes at most once. Errors (a device gone, Windows'
  microphone privacy) show in the Voice tab.
- The sender: `client/voice/`'s `VoiceSender` drains the capture every frame, encodes every chunk (continuous codec
  and RNNoise state; RNNoise for a microphone only, never the test tone) and feeds each to `VoiceGate` with that
  frame's `may_speak`, also while it is false, so a backlog recorded while downed never goes out after a revive. In
  the frame `may_speak` turns true, and at any step after the own `ClientModel.silencings` moved (it goes up at each
  phase change and each time the own life leaves living, so a knockdown and its revive, or Round, End and Lobby,
  folded between two steps by a hang are not missed, #241), what Godot has handed over by then is fed as unspeakable
  too, however long that frame was. It was recorded before the change, except the audio between the fold and the
  sender's step in that frame, which is dropped with it (as at a change between two phases that both hear); the
  driver's own buffer, under one chunk, may still hold a little from before the change, which goes out as speakable.
  A frame with no chunk while unspeakable still empties the pre-roll. What leaves goes through
  `ClientSession.send_voice`. `may_speak` is `client/`'s: the own life fold living and `VoiceRule.radius_of` of the
  current phase > 0 in the client's own mode, never `Match` or `MatchState` (the E18 boundary test scans
  `res://client` and `res://voice`). Nothing in silence, nothing while downed or dead, nothing in a phase whose rule
  hears nobody, nothing in Off or with no device open.
- Three modes (D11, the engineer's answer): voice activity by default (the threshold slider, never below 0.01,
  with a live meter of the microphone's peak, and the 300 ms hangover), push-to-talk held on V (`voice_talk`,
  counted only with no Esc menu), or Off, which closes only the own microphone: the others stay audible and the
  Voice slider silences them (the design's reading, still "Needs the engineer"). No echo cancellation: under
  voice activity loudspeakers echo, so the Voice tab says headphones avoid it, with the headset and #22 advice.
  In debug builds the tab also has a test tone in place of the microphone and "mute this window" (E47), neither
  saved. F3 shows the own gate, peak, frame age and encode µs.
- 20 ms frames keep E7's bucket (50 a second) and the relay's newest 5 per poll.

#### 6.5.4 Playback and the ears (E40, E41, D12; **built in M5-5**, #219)
`ClientSession.voice_received(speaker, seq,
tick, opus)` carries each `VoiceDown`'s seq. `voice/`'s `VoiceSpeaker` is one remote speaker's
`AudioStreamPlayer3D`, bus Voice, `ATTENUATION_DISABLED`, so Godot fades it linearly to silence at `max_distance` (a
cutoff of 0 sets 1 mm, since Godot reads 0 as no limit), with its `VoiceJitter` and the codec's `VoicePlayback`:
each frame it decodes what the jitter says (a frame that does not fit the queue is dropped, `overflow`), applies the
command, and sets the fade's volume; a fade (50 ms) ends in a flush. `client/`'s `VoiceViews` hangs one per speaker
at its `RemotePlayerBody`'s mouth (eye height − 0.1 m, a placeholder), made at its first frame, freed with the body,
and gives it `max_distance` = `VoiceRule.radius_of()` of the current phase in the client's own mode, again whenever
the model's phase changes (a `PhaseChanged`, or a `Welcome` into a phase). It plays only `voice_received` frames,
and drops every frame: of a speaker with no body, not living (downed, dead), gone from the roster or left, or the
own peer; while the own life fold is dead; while the phase's radius is 0; of a speaker farther from the ears than
`max_distance`; and stamped at or below the newest host tick (snapshots and frames) recorded at that speaker's
latest flush. It fades and flushes a speaker at its `KnockedDown` or `Died`, flushes and frees it at its
`PlayerLeft`, flushes every speaker at the own `Died` and on entering a phase whose radius is 0, and fades and
flushes a speaker that crosses out of `max_distance` from the ears (checked each physics frame). The ears are
`client/life/`'s `Ears`, an `AudioListener3D` that `LifeView` places after the cameras each physics step and turns
with the current camera: the own eye (living), the own body's head where it lies (downed: the standing eye carried
through `LifeLooks.lying`, near the floor; never the downed camera), a spectated living target's eye, a downed
target's head, the own body without a target. Godot measures a 3D player's distance from the current
`AudioListener3D` but mixes one only while the world has a `Camera3D` (observed on 4.7.2 headless, not in the
docs; the game always has one). `WorldSounds` measures its 12 m from the ears too (E40's amendment of E33). F3
(debug builds) lists each speaker by an index of first arrival with its queue, prebuffer, frames, late, lost,
concealed, stale, underruns, overflow and decode µs; no peer id or name. Tests: §4.7.15 Built in M5-5.

#### 6.5.5 Buses and the mix (E43, D15)
`AudioBuses` makes Voice, Effects (the world sounds) and Music, sending to
Master, in code (**built in M5-5**: `AudioBuses.ensure()` at `Game._ready`, each bus once; the world sounds on
Effects, the lift music on Music, its −14 dB now the bus default); four sliders, Master, Voice, Effects and Music
(0, 0, −6 and −14 dB by default: placeholders; −60 to +6 dB, the bottom mutes the bus), no ducking, saved per
window in `user://settings.cfg` (`settings_<n>.cfg` for `PRIME_INSTANCE` n > 1) with the microphone, the mode,
the threshold, RNNoise and the mark, set in the Esc menu's Voice tab (**built in M5-6**: `UserSettings`,
`VoiceControl`, `VoicePanel`). `host --clients N`'s windows get their `PRIME_INSTANCE` from `hostjoin.start`
(M5-6), as `run --instances` and `bots --instances` do from `launch.launch`.

#### 6.5.6 No talking indicator in M5 (D14, the engineer's answer)
No own transmit icon on the HUD, no icon over a
speaker. No screen lists who is talking, and nothing tells a speaker who hears them: the host's relay counters on
F3 (debug builds) never show live during a Round, only in the Lobby, the Countdown and End. Who talks shows later
through a mouth animation with the masks of #73 (after the MVP).

#### 6.5.7 Occlusion (E42, D13 (a); **built in M5-7**, #221)
On the listener only, one ray from the ears per audible
speaker per physics frame (to its mouth) and one per world sound as it starts (to a point above it), against the
world layer of the client's own level, never a player's capsule; the host keeps routing by distance. Behind the
level a voice or a world sound is 8 dB quieter (the player's own `volume_db`) and duller (the muffled Voice or
Effects bus, a low-pass at 1 kHz), both placeholders; a voice's muffle eases over 100 ms. The muffle only lowers
and dulls what already plays. The bus for the dullness, not the player's own attenuation filter, by a headless
measurement (§4.7.16 Built in M5-7). Beyond one ray (several rays, thickness, portals) is not built.

#### 6.5.8 The wire (E44; **measured in M5-4**, #218, and again after #245)
Unchanged in M5 so far. The leak test gained a
distance invariant written apart from `VoiceRule.hears` (E45, M5-1, §6.5.9). M5-4 measured the host's relay time and
upload with `tools\run.cmd bots voice_load --instances 8` (headless; the host's counters, §4.5): 8 bots within 8 m
in the lobby, all talking continuously (30 to 60 B frames, 50 a second) for 30 s, then 2 talkers for 30 s, on the
engineer's machine on 2026-10-03 with the 8 bot processes and other worktrees' Godot processes sharing its cores, so
every time is an upper bound. With everyone talking: 56 `VoiceDown`s per 20 ms, 49 of them on the wire (49 datagrams
per 20 ms; 7 go to the host's own client over the loopback); the relay took 3.0 to 3.5 ms per 20 ms, 54 to 62 µs per
send, of which 16.5 to 19 µs inside the transport's `send` (ENet's `put_packet`, which flushes one datagram), an
average over all 56 sends with the 7 loopback ones to the host's own client included (ENet's alone about 19 to 22 µs
if those cost nothing); the upload was 1.88 Mbit/s of voice (96 B per `VoiceDown` on the wire for a 45 B frame),
0.40 of snapshots and 0.01 of the rest, 2.29 Mbit/s. With 2 talkers: 14 sends per 20 ms (12 on the wire), 0.8 to 1.0
ms, 0.87 Mbit/s. A second run under a heavier load of other worktrees took 190 to 270 µs per send and dropped
backlogs. Scaled to 10 players (90 sends per 20 ms, 81 on the wire): about 4.9 to 5.6 ms per 20 ms of relay time (25
to 28% of a core), **over E44's 2 ms**; the upload about 3.1 Mbit/s of voice and 0.65 of snapshots (each snapshot
holding 9 avatars, not 7), about 3.8 Mbit/s, under E44's 4.5 and the voice ADR's 5 Mbit/s (about 4.5 with every
frame at speech's 67 B peak). The send is not most of the cost: a throwaway probe in one process (debug build, 10
speakers heard by 9 each) spent about 43 µs encoding each `VoiceDown` through `WireSchema` and 9 µs in
`VoiceRelay.flush`, per message, though only its 2-byte seq differs between a frame's listeners. So the measurement
crosses E44's time threshold and asks for M5-4b; the manager's decision (delegated, #134) was to encode each frame
once first (#245, §4.5 "Voice relay").
#245 measured again with the same command on the same PC on 2026-10-03, three runs before the change and three
after, alternating, with about 10 Godot processes of other worktrees running (upper bounds again; the figures are
the five full windows with everyone talking). Before: 2.9 to 3.3 ms per 20 ms, 52 to 60 µs per send (16 to 18 µs
inside the transport's `send`). After, at a comparable load (the transport's part 14 to 15.5 µs): about 1.3 to 1.4
ms per 20 ms, 23.5 to 26 µs per send; the host's own part of a send (all but the transport's `send`) fell from about
37 µs to about 10 (one encoding per frame, M5-4's probe's 43 µs shared by 7 listeners, about 6 µs of each send; the
copy, the seq and the bookkeeping the rest). One run after the change under a heavier load (the transport's part 21
to 25 µs) took 2.0 to 2.3 ms, 35 to 41 µs per send. With 2 talkers: 0.83 to 1.0 ms before, 0.38 to 0.44 ms after.
The upload is unchanged (the same bytes): 2.29 Mbit/s. Scaled to 81 streams (90 sends per 20 ms): about 4.7 to 5.4
ms before, **about 2.1 to 2.3 ms after**, and 3.2 to 3.6 ms under the heavier load: not shown to be under E44's 2
ms, though the comparable-load range starts only about 0.1 ms over it and every figure is an upper bound, so the
true cost may be under; a rerun of the same command on a quiet machine settles whether M5-4b is needed. About 60% of
what is left is the transport's `send` per datagram, which only fewer datagrams cut: M5-4b's batched row (one
`VoiceDown` per listener per poll holding every frame it hears, a protocol change) would send about 11 datagrams per
20 ms at 10 players instead of 81 (the host polls every physics frame, 60 Hz), saving most of the transport's 1.3
ms, and about 1.1 Mbit/s of the voice upload's per-datagram headers (estimates, not measured). Whether to open it is
the engineer's (§10).
**Over WebRTC (M6-6, #371, for D24):** `tools/run.sh bots voice_load --instances 8 --transport webrtc` (the fault
shim off for a measurement) in a cloud container (4 CPUs, Xeon at 2.8 GHz, the 8 bot processes on the same CPUs),
2026-10-05, so every figure is an upper bound; three quiet runs (load average under 4) and two beside a `load` of 8
busy loops. With everyone talking (the five full windows of each run): 56 `VoiceDown`s per 20 ms, 49 on the wire,
as over ENet; the relay took 2.65 to 2.80 ms per 20 ms in the quiet runs' medians (worst window 2.97 ms), 47 to 50
µs per send (45 to 53 per window), of which 31 to 37 µs inside `WebRtcTransport.send` (webrtc-native's
`put_packet`, against ENet's 14 to 19 µs); 3.8 to 4.0 ms (worst 5.96) beside the load. The upload was 3.25 Mbit/s of voice and 0.49 of snapshots,
3.74 Mbit/s, counted by E56 (each packet plus 108 B: IPv6, so about 21 B per datagram high over IPv4); SCTP's
acknowledgements are not counted. Scaled to 10 players as for M5-4 (90 sends per 20 ms, 81 datagrams on the wire;
snapshots by 81/49): the relay about 4.4 ms per 20 ms (run medians 4.25 to 4.50 ms, worst window 4.77; 6.1 to 6.4
ms, worst 9.6, beside the load), and the upload about 6.2 Mbit/s by E56 (about 5.4 over IPv4), plus about 0.3 of
acknowledgements (the M6 design's §4 estimate): **both over E44's 2 ms and 4.5 Mbit/s**, so by D24 (a) M6-8 (the
batched row) is wanted. With two talkers: 0.73 to 0.78 ms and 1.29 Mbit/s. The engineer may rerun it on a quiet PC.
**With the batched row (M6-8, #374, protocol 8):** the same command and container, 2026-10-05, three quiet runs
(load average under 2) after the header and in-place seq changes. With everyone talking: 56 frames per 20 ms in
about 19 `VoiceBatch`es (8 listeners, about 2.4 polls per 20 ms: the host flushes every poll that held frames),
about 16.5 datagrams on the wire; the relay took **1.69 to 1.74 ms per 20 ms** in the run medians (worst window
1.86), 91 µs per batch of which 38 to 39 µs inside `WebRtcTransport.send`. The voice upload was **1.80 Mbit/s**
(3.25 before), snapshots 0.49. Scaled to 10 players (batches by 10/8, the rest of the relay and the frame bytes by
90/56 and 81/49, datagrams by 9/7): the relay about **2.5 ms** per 20 ms (2.8 if all of it scales by 90/56), 37 to
43% below M6-6's 4.4 but still over E44's 2 ms in this container; the upload about **2.7 Mbit/s of voice + 0.8 of
snapshots, about 3.5 Mbit/s** (by E56, IPv6), plus SCTP's acknowledgements, fewer with fewer datagrams: **under
4.5**. About 0.75 ms of the relay's 1.7 is the sends; most of the rest is the relay's flush and one `WireSchema`
encoding per relayed frame. With two talkers: 0.71 to 0.73 ms and 0.65 Mbit/s. A first run that encoded the header
per frame and listener took 2.4 to 2.7 ms, as much as before batching. Whether the relay's figure on a quiet PC is
under 2 ms is the engineer's rerun.

#### 6.5.9 The cutoff and the distance invariant (E41, E45; **built in M5-1**, #215)
Every voice rule answers
`hearing_radius_m()`, the farthest it routes a voice between the last accepted positions in 3D (its edge
included), 0 when it routes nobody: the base class and `SilentVoice` 0, `ProximityVoice` its `radius_m`,
`RoundVoice` its `living_m` (§9.4). The static `VoiceRule.radius_of(rule)` gives 0 for a phase with no voice rule;
it is the one number the client's fade (`max_distance`, M5-5), its sender's "a phase whose rule hears nobody"
(M5-6) and the leak test read for the current phase from their own mode, so no radius is copied anywhere. In the
base mode: 8 m in the Lobby, the Countdown and the Round, 0 in Loading and End. The leak test checks the
routing against it apart from the rule (§5): `ScenarioInvariants` per tick on `speakers_for`, `LeakCheck` on every
decoded frame from the positions and radius it records per tick, compared as `VoiceRule.within` does, so a rule
whose `hears` reaches past its own radius fails though `view_of` agrees with it; the scenario
`voice_beyond_the_radius` (§9.7) has bots talking beyond the radius, then within it, in the Round. The bots talk
at 50 frames a second in talk spurts (§4.6.2). Tests: the voice rules' suites in `tests/unit/voice/` and
`tests/unit/content/voice_rule_test.gd` (per class, per phase, null), `content_modes_test.gd` (the base mode's
radii), `tests/scenarios/bots_runner_test.gd`, `scenario_runner_test.gd` and `bot_voice_test.gd`.

#### 6.5.10 Not in M5
Radios and role abilities (M7+), echo cancellation (players are advised headphones), a talking
indicator (#73's mouth animation, later), lowering the device latency (the voice ADR's advice to players).

## 7. Movement

Client-side movement for the local player; the host checks speed and teleports; remote players are interpolated.
The core tick rate is set in §3.3; what the host checks, in §7.1. The snapshot's wire format (avatars only) is §4.3.
- **Snapshot rate:** one per host tick (20 Hz) in the phases that send snapshots, kept by M4 (E22): the spectate
  camera is built from them.
- **Interpolation** (M4-7, E23): `SnapshotBuffer` draws remote players behind a host tick estimated from a 2 s
  sliding window of arrivals, by one tick plus the jitter of that window, within 100 to 250 ms (placeholders), with
  no extrapolation (§4.7, Movement on the network). On a simulated network with 0 to 100 ms of jitter it holds on
  about 0.2 % of frames where a fixed 100 ms holds on 16 % (the spike's lesson below; `snapshot_buffer_test.gd`).
- **Correction policy:** the host corrects a claim that fails a check of §7.1 with a `Correction` of a new epoch; the
  client adopts it at once (`ClientSession.corrected` teleports the controller before it moves) and counts it, and
  the debug overlay (F3) shows the count: honest play gets none. A placement's or a knockdown's `Correction` (right
  after a `PlayersPlaced` or a `KnockedDown` naming the client) is counted apart, as a placement. The tolerances stay placeholders until #76 and the
  M4 playtests. Found by M4-7's test: on stairs whose treads are narrower than the capsule (0.3 m against 0.8 m) the
  host corrects an honest climb, walking or sprinting, because the landing floor it finds with five rays under the
  footprint lies below the stair edge the capsule rests on; 0.5 m treads pass. That is #76's slope rise to settle.

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
- `PlayerController` is a `CharacterBody3D` with its origin at the feet. Its movement numbers (speeds, jump height,
  capsule, eye and step height, stamina) are the client's own copy of the mode's `PlayerRules` (§9.5), the same
  numbers `core/` checks with (M4-7); `client/player/player_tuning.tres` (`PlayerTuning`) keeps the client's feel
  only (the push factors, the view's easing), with script defaults of 0 so no number is repeated in code.
- Stamina is behind `StaminaSource`: the controller asks before a sprint or a jump and reports each physics step;
  a step counts as moving only while the player gives movement input, so a push is free (§7.1.3 Stamina).
  `PredictedStamina` (M4-7, E24) predicts with `core/`'s rule (`StaminaLedger`, 2d) in thousandths per 20 Hz tick,
  the only copy of it on the client, and follows each `SelfStatus`: off the network as it arrives, on it claim by
  claim from the claim the status names (#155, §7.1.5 Speed).
- A downed player (`PlayerController.life` DOWNED, set by `set_life`; M4-9) crawls as the host's crawl check
  allows (§7.1.7 The crawl, M4-2): the living's capsule (left standing, as the host's floor checks expect, under a
  lying mesh), gravity, floor, steps and slopes at `PlayerRules.crawl_speed_mps`, with no sprint and no jump;
  `StaminaSource` refuses both to the downed, and their stamina regenerates as usual. There is no flight (the
  engineer's correction of 2026-09-30, #46). While a raise holds it (`held`, from `ClientModel.raiser_of(own) != 0`)
  it stands still and claims where it lay. A dead player has no collision layer, no mesh and no physics step. `Game`
  sets `life` from its own life fold and `held` from the raise fold; any life change drops a pending jump. A downed
  crawl over the loopback, holding sprint and asking to jump, is corrected 0 times, also on a clock that stands still
  and then jumps, and up the fixture's steps (`player_network_test.gd`, `player_controller_downed_test.gd`).
- Physics layers (`PhysicsLayers`, named in `project.godot`): 1 `world` (level geometry, Godot's default layer),
  2 `living_players`, 3 `downed` (`PhysicsLayers.DOWNED`, M4-9). The living and the downed collide with the world
  only; the dead are on no layer; a living player finds the
  other living players with a contact search on layer 2 and pushes them (§7.1.6 "Pushing apart"). Other players are
  `RemotePlayerBody` capsules that only their owner's data moves, on layer 2 while the client's life fold says they
  are living and on layer 3 otherwise (a downed player pushes nobody and nobody pushes it).
- Steps: `move_and_slide` stops a capsule at any ledge, so the controller lifts itself onto a ledge up to the step
  height and glides over the edge until it snaps onto the top. While it glides, `move_and_slide`'s own snap is off
  and a snap that lands below the ledge's top is undone: at a slow walk or the crawl it would catch the edge under
  the rounded bottom, which the body then rested on for good (found at the crawl's 1 m/s on 0.3 m treads). What
  blocks it must be a ledge: a walkable blocker (a ramp, a low edge under the rounded bottom) is left to
  `move_and_slide`, and a ledge whose top is steeper than `floor_max_angle` (a steep slope, a round prop) is no step. Only the body jumps up; the view eases after it and
  lags at most one step height. A jump's take-off speed is solved for the physics step so the ballistic peak is the
  jump height.
- For the host's movement checks (`MovementRule`, 2d, covers both): the controller crosses a ledge's edge `STEP_CLEARANCE` (0.01 m)
  above its top, so a rise without a jump can reach step height + 0.01 m, and a jump from mid-crossing peaks as much
  over the jump height. A capsule's rounded bottom also rolls onto a ledge corner, so a jump can land the feet up to
  `capsule_radius * (1 - cos(floor_max_angle))` (about 0.12 m) above the jump height. The tolerances must cover both.

### 7.1 Authority for the MVP's mechanics (#32)
Each choice names the failure it prevents. Numbers: the [MVP rules](decisions/2026-09-29-mvp-rules.md) (placeholders,
"not a decision"), including the player's capsule, eye height and step height; tolerances: M4.

#### 7.1.1 Geometry through a port
`WorldQuery` is an abstract `RefCounted` in `core/` that answers the geometric
questions of the rules: line of sight between two points, the floor below a point (one ray), the floor a player
stands on (its capsule's footprint), where an item placed from A towards B comes to rest, and how far a sphere swept
from A towards B gets (`sweep`, a thrown item's flight, §7.1.16). `server/` implements it over its own `World3D` holding the level's static colliders, never
the client's scene, so a headless host and bots work the same; tests use a fake. `core/` stays pure, and every rule
is still in one place. The 4.7.2 API limits `World3D.direct_space_state` to `_physics_process` on the main thread
when physics runs on a separate thread, so the host ticks `core/` from its physics step; whether a new space answers
queries before its first step was probed in 3c (#99): it does (§4.5).

#### 7.1.2 Positions
`core/` keeps each player's last accepted `MoveClaim` (position, velocity, facing, on floor). Every
range rule (reach, hit zone, circle, voice) reads those, never a position inside another intent. Prevents: a client
claiming to stand next to what it wants to grab.

#### 7.1.3 Stamina
Belongs to `core/` (only the living sprint; the downed regenerate, see §7.1.7 The crawl). The client
predicts its own from the published numbers to draw the HUD and gate Shift, and follows `SelfStatus` (on the
network claim by claim, #155: below). `core/` keeps a ledger per player: the host tick up to which stamina is
settled. A claim settles the ticks it covers (its client-tick delta, never past the current host tick), each with
the flags its masks give that tick (#155, §7.1.5 Speed): a covered tick in the sprint state in which the player gave
movement input and moved horizontally costs 1/20 of the per-second cost, and every other covered tick regenerates.
Only the player's own movement counts (the engineer's decision of 2026-09-30, #46): a pushed player holding sprint
without movement input pays nothing for the push.
`PlayerController` reports a step as moving only while it gives movement input; `core/`'s stamina
(`StaminaLedger`, 2d) counts the same way: a claim says whether movement input was held (`moving`). Before a
jump or a hit is checked, the ticks not yet settled are settled with the last claim's sprint state and movement-input
flag, so an idle player is not refused on stale stamina; a later claim settles only what is left. A jump claim
first settles its own covered ticks with its own flags, so a sprint that ends in a jump is paid. The sprint state
(Q7) starts when the claim holds the sprint flag and stamina is at least the start threshold, and lasts while the flag
is held and stamina is above 0. An accepted jump or hit costs its amount at once. The allowed horizontal speed is the
sprint speed in the sprint state, else the walk speed, plus the push allowance near another living player (§7.1.6 Pushing apart),
measured over the client's tick delta (lesson above). Faster: `Correction` with a new epoch. Prevents:
a client that never spends stamina, or spaces its claims out to regenerate between them, sprinting forever.

#### 7.1.4 Jumps
Are accepted only when the host has the player on the floor (the floor found by `WorldQuery` within
step height plus `STEP_CLEARANCE` below the last accepted feet; the last claim need not say `on_floor`, because claims go at 20 Hz and
the client's physics at 60 Hz, so a landing and a jump can fall within one claim) and stamina covers the cost; a
downed player's new jump is always corrected (§7.1.7 The crawl). Until the next landing
the height above the floor is bounded by the jump height; a rise without an accepted jump beyond step height is
corrected. Prevents: free or endless jumps, and flying. A claim carries `jumps`, the client's count of jumps since
it adopted the epoch (3e, E2; §4.3): a rise d ≥ 1 over the last accepted claim's count in the epoch is one jump,
which stamina must cover d times; a count that falls within an epoch is corrected, and so is a rise d above the
client ticks the claim covers, since a client lands between two jumps (#76, from #117 item 6), except in a fresh
claim (the first of a client-tick baseline, after a placement or a rebase), which the host counts as one tick
whatever span it carries; the count restarts at 0 with every new epoch. So a jump in a claim that the LATEST lane
merged away or lost still counts in the next one.

#### 7.1.5 The movement checks (`MovementRule` in `core/movement/`, the ledger in `core/stamina/`; 2d, #60)
Every
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
- Speed: per covered tick the state's speed, each tick with its own flags (below; a tick past the host's clock,
  which the ledger cannot settle yet, is run on from the settled ones for the speed alone; a living player's tick
  without its own movement gets the walk speed, since only movement pays for sprint),
  for the living plus `sprint_speed` for at most `PUSH_TICKS` (10) covered ticks while another living player's
  last accepted position is within `MovementRule.push_reach()` of the claim's path (§7.1.6 Pushing apart; #76);
  for the downed the crawl speed alone, with no sprint and no push allowance (M4-2); plus `DISTANCE_SLACK_M`
  (0.05 m) per claim, or
  for the crawl `CRAWL_SLACK_FRACTION` (a tenth) of its own travel plus 1 mm: 0.05 m is a whole tick of the
  crawl, so a fixed slack would let a client claiming every tick crawl at twice the speed.
  No tick of sprint goes uncharged (#155). From #76 to #155 the host granted "the sprint's last tick", one covered
  tick more at sprint speed after a sprinting claim, which a modified client alternating its flags turned into
  about eight times the sprint endurance. #155 replaced it with exact data, so three honest cases pass without it:
  - **The claim that stops a sprint.** A claim covers the 3 physics steps (60 Hz) since the one before, and
    `ClientSession` latches its `sprint` and `moving` flags over them: each says whether any of those steps had
    the sprint state or movement input, not only the last one. So the claim of the tick a sprinter lets go in
    still says it sprinted, pays for that tick and is allowed its travel. A `Correction` drops the steps before
    it.
  - **A claim merged at a sprint's end.** The LATEST lane delivers only the newest claim of a poll (§4), so over
    a jittery link (or after a freeze, #70) the walk's claim after a release reaches the host with the sprint's
    last claims folded into it. `MoveClaim`'s masks `sprint_ticks` and `moved_ticks` repeat the latched flags
    per client tick, bit i for client tick `client_tick - i`, every tick a claim covered taking that claim's
    flags; the host settles each covered tick with its bits (`StaminaLedger.simulate_ticks`) and grants sprint
    speed for exactly the ticks in the sprint state with the player's own movement, which it charges. A covered
    tick older than the 32 bits takes bit 31; bits older than the covered ticks count for nothing. A claim
    without masks, which only `core/`'s own callers send (the in-process scenario runner, unit tests), gives
    every covered tick its `sprint` and `moving` flags. A client that claims sprint for ticks its stamina does
    not cover is still corrected by the ledger.
  - **Stamina running out.** A `SelfStatus` answers a claim some ticks old (a round trip), so a client that set
    each one as it arrived got back the ticks still in flight and sprinted on for a round trip after its stamina
    ran out. On the network `PredictedStamina` settles by the claims instead (`ClientSession.claim_sent`: the
    claim's epoch and client tick, the ticks it covers, its latched sprint flag, and whether it moved itself
    from the last claim's position): the ledger's rule, the same ticks with the same flags, a claim's jumps paid
    after its ticks. Each `SelfStatus` names the client tick of the last claim the host settled (`claim_tick`,
    -1 for none since a placement); `follow_status` takes the host's number and sprint availability (which is
    the host's sprint state wherever that decides the next tick) and settles again exactly the claims after
    that one (with none, the claims of the current epoch), of the last 32 it remembers. A refused claim
    settles nothing on the host (`MovementRule.apply` puts back the ledger a jump claim's check committed), and
    the next claim covers its ticks. A claim after the named one from an older epoch than the client's was
    refused or dropped as stale, so it is settled again without its jumps: events share one ordered reliable
    channel, so a status that arrives after a `Correction` was sent after it. So a cost it does not predict (a
    hit), a refused jump or a tick the host could not settle yet is taken in with the next status, and nothing
    in flight is given back. The jumps since the last claim are forgotten when the session adopts a new epoch,
    whose claims count jumps from 0. The network bots sprint by the same prediction (`NetPlay`).
    Accepted, until a later `SelfStatus` (no guard test met a `Correction` from these):
    - A claim whose ticks reach past the host's clock when it arrives (it overtook the host's ticks, at an
      epoch's start or when the delay shrinks) has those ticks left unsettled, so the client may predict a tick
      of regeneration more than the host has.
    - Before a jump or a `StaminaCost` the host settles the ticks past the last claim with its flags
      (`settle_ahead`), up to the ledger's lag behind the client (about the one-way delay in ticks); the next
      claim settles only the ticks left, while the client settles all of them again on top of a status that
      names the last claim. A second jump or a sprint restart right at its cost may then be corrected. No guard
      test jumps under jitter; the fix, if needed, is a count of those ticks in `SelfStatus`.
    - After a refused first claim of an epoch (none accepted since its placement) or a claim past its credit,
      the host takes the next claim as one tick, while the client counts it from its last claim. A lost first
      claim no longer does this: it travels on `MoveClaimReliable` (§7.1.15 Lost claims, #429).
  Tests: `tests/unit/movement/movement_rule_masks_test.gd` (merged claims at a sprint's end, bits the stamina
  does not cover, flags against masks, old bits, malformed masks), `tests/unit/movement/movement_rule_test.gd`
  (the two tests that pinned the allowance, rewritten with the engineer's approval, and the release that walks
  on), `tests/unit/stamina/stamina_ledger_test.gd` (`simulate_ticks`), `tests/unit/stamina/self_status_feed_test.gd`
  (`claim_tick`), `tests/unit/client/net/client_session_claims_test.gd` (the latch, the masks, `claim_sent`),
  `tests/unit/client/player/predicted_stamina_test.gd` (claim by claim against `StaminaLedger`, `follow_status`),
  `tests/integration/client/player/player_network_sprint_test.gd` (the real controller over the loopback lets go
  of sprint, or of every key, at each step of a claim's tick, sprints until stamina runs out, and holds sprint
  through running out and back, with no delay, with every packet held back four physics frames each way, and
  with 1 to 9 frames of jitter in order, each jitter test checking that the host merged claims; and three claims
  held and merged while it lets go of sprint: 0 Corrections), and the bot scenarios `crew_delivers_every_package`
  and `dissidents_win_by_the_clock`, in one process and over ENet.
- Height, from the last landing's floor (a claim on the floor with a `WorldQuery` floor within step height plus
  `STEP_CLEARANCE` below its feet, which a ledge crossing needs; `FLOOR_PROBE_M` above the feet is where the query
  starts): after an accepted jump, the jump height
  plus `capsule_radius * (1 - cos 45°) + STEP_CLEARANCE` (about 0.127 m, §7) from the take-off, the higher of its
  floor and its feet; without one, the step height plus `STEP_CLEARANCE` (0.01 m) plus the claim's horizontal
  travel times tan 45° (slopes and stairs up to the client's `floor_max_angle`). Positions are 32-bit floats:
  `HEIGHT_SLACK_M` (1 mm) on top. Falling is not bounded.
  The slope allowance counts the travel of at most `SLOPE_TICKS` (10) covered ticks: when a claim covers more, its
  allowed travel times 10 / covered (#76). A claim covering stored credit (up to 200 ticks after 10 s of silence)
  used to rise as far as it travelled, onto a roof tens of metres away; up to nine lost claims in a row change
  nothing, so an honest climb whose unreliable claims were lost passes (a bound of one tick's travel would have
  corrected it, #74). Accepted: a 45° climb through a stall of more than about half a second is corrected once.
  A landing's floor is the higher of the floor `WorldQuery` found and the claim's feet less
  `MovementRule.landing_slack()`, r (1 − cos 45°) ≈ 0.12 m, the most a capsule's rounded bottom hangs below a
  step's corner it rests on (#76; found by M4-7, #143): on stairs whose treads are narrower than the capsule
  (0.3 m against 0.8 m), the five rays may all miss the step the capsule rests on and find the one below, and
  honest climbs were corrected on almost every step. A claim floating above the floor gains at most one step this
  way and is still corrected. Tests: `tests/unit/movement/movement_rule_jump_test.gd` (the stairs test replays
  the claims #143's network test sent on 0.3 m treads).
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
- The claim's age (#647; ZE10 of the [zone task ADR](decisions/2026-10-09-m7-zone-task.md)):
  `MovementRule.claim_age(state, peer, now)` is how many host ticks old the player's last accepted claim is at host
  tick `now` (0 in its own tick), from the record's `claimed_tick`, or -1 when the position is no claim of the
  current epoch: no record, or a placement since (`PlacePlayers`, a knockdown, a respawn), until the epoch's first
  accepted claim (a refused or malformed first claim leaves it -1, though its `Correction` bumps the epoch; the
  record's `accepted_tick`, which the push reach reads, counts the placement too); a refused claim's `Correction`
  keeps the last one's age, and a revive keeps the epoch. The zone task counts a player only while it is at most
  `PUSH_TICKS` (10), the lost-claim tolerance the push allowance already accepts: a client that stops claiming (a
  freeze, or a modified client that goes on polling) stops counting 10 ticks after its last claim. Its companion
  `MovementRule.credit_gain(state, peer, now)` is how many ticks of credit the player stores at `now` above the
  least an accepted claim of its epoch left it (the credit not yet topped up counted in, the cap not; -1 as
  `claim_age`); the record keeps that least as `least_credit`, reset by a placement. An honest client claims one
  tick of its own clock per host tick, so it stays near 0 (lost claims raise it until the next claim covers them; a
  frozen host's backlog is spent in the tick it arrives). A modified client that claims one client tick every 10
  host ticks keeps `claim_age` under 10 but stores 9 ticks a claim (the netcode review of #647): the zone task
  counts a player only while `credit_gain` is at most `PUSH_TICKS` too, so the credit stored while standing in a
  zone, whether silent or claiming slowly, cannot buy more than 10 ticks of zone time and travel at once. Spending
  credit lowers the least, so credit spent and stored again counts as well. A respawn inside a
  zone therefore counts from its first claim after the respawn, about a round trip later, not from the respawn
  tick (a deviation from the ADR's §4 row, which the zone task ADR records). Tests:
  `tests/unit/movement/movement_rule_claim_age_test.gd`.

#### 7.1.6 Pushing apart (the engineer's decision of 2026-09-30, #46; the rule is in the MVP rules, "Collisions")
Living
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
- A downed player runs no search, and its layer is not searched: the downed push nobody and nobody pushes them.
  The dead run no physics step at all.

Speed: a pushed player moves faster than its own walk or sprint without cheating (walking sideways at 4.5 m/s
while a sprinter pushes it at 3.5 m/s is about 5.7 m/s, and two pushers add up). `PlayerController._push_apart`
caps the push-out at `sprint_speed`, so the host's speed bound for a living player is its state's speed plus
`sprint_speed` (proposed for M4, not decided; a test pins the cap). The allowance is granted only while another
living player's last accepted position is within `MovementRule.push_reach()` of the claim's path (#76): measured
horizontally from the segment between the last accepted position and the claim's, with the feet at most the
capsule's height apart. The reach grows by a tick of sprinting for each host tick since the other player's last
accepted claim beyond the usual one, up to `PUSH_TICKS`: a pusher whose unreliable claims are lost while it pushes
is farther ahead than its stored position. The allowance counts at most `PUSH_TICKS` covered ticks, so a claim
spending stored credit buys no more push than that; accepted: an honest player pushed through a stall of more than
about half a second is corrected once. The reach is two capsule radii (touching) plus 0.2 s of sprinting, 2.2 m: the
pushed client moves away from where it draws the pusher, the interpolation delay (§7) plus a round trip behind the
pusher's position on the host, and with two radii alone the honest head-on push of M4-7's network test over the
loopback was corrected (0.86 m apart). Before #76 a modified client claiming a push with nobody near moved at
11.5 m/s with no input and no stamina. The downed get no allowance: they are never pushed, and they push nobody.

Prevents: two clients that see each other late snapping each other back and forth, and a player blocking a doorway.
Accepted: a modified client can walk through players. Latency: the pusher sees the pushed player's capsule a round
trip late (its own motion reaches the other client, which moves, and that motion comes back: about 0.2 s with
100 ms interpolation on each side). Over a network the overlap limit, not the push speed factor, sets how fast a
straight push goes: at most `push_max_overlap` per round trip, 1 m/s at 0.2 s instead of 2.25 m/s. The
two-client tests (`player_controller_push_test.gd`) run with that delay. *Open (M4):* the playtest over a network
decides whether that is enough; the options are a larger limit (deeper visible overlap) or drawing the pushed
capsule moved ahead on the pusher's client (display only).

#### 7.1.7 The crawl (vision revision 1; M4-2, #138, replacing the ghosts' movement)
A downed player's claims get the
movement checks with the crawl's bounds: the allowed travel is `PlayerRules.crawl_speed_mps` times the ticks covered
(plus a tenth of that, and 1 mm for floats), with no sprint ticks and no push allowance; a new jump is corrected; the rise is the step height
(plus `STEP_CLEARANCE` and the slope allowance) above the last landing. The downed are never in the sprint state and
spend no stamina; it regenerates as usual. They collide with the level client-side and with no player. `PickUp`,
`PutDown` and `Use` from the downed are rejected (`not_accepted`: Round accepts them from the living only); the dead
send no intent that is accepted (§3.1). The knockdown places the downed player where it stood, on the floor below
its last accepted position, with a new epoch and a `Correction` (`LifeRules.knock_down`), even on the floor. The
movement rule treats that like a placement: walking claims in flight are dropped as stale instead of failing the
crawl check, and its first claim as downed starts a new client-tick baseline there. A death sends no `Correction`:
the dead claim nothing. Tests: `tests/unit/movement/`, `tests/unit/stamina/stamina_ledger_test.gd`,
`tests/unit/life/life_rules_test.gd`.

#### 7.1.8 The raise (vision revision 1, Revive; M4-4, #140)
The host checks the raise's conditions when `Raise` arrives
and again every tick while it runs (a channel, §9.4): the target is downed, it lies within the pick-up's reach
(2 m) of the raiser's last accepted position, both feet, and the line from the raiser's eye (`Items.eye_of`) to
just above where it lies (`Items.lifted`) is clear; one raiser at a time. So a raiser who walks away or loses
sight stops the raise on the next tick. The raiser may move while it holds E and may hold the package. While a
raise runs, the downed player is **held in place** (the engineer's answer 8 on PR #133): a claim farther than
`MovementRule.HOLD_SLACK_M` (1 mm, a margin for the client's physics, not for the wire) from where the raise
started (`Channel.held_at`), in any direction, is corrected (`MovementRule.held_against`, from
`Channels.holding`), so no run of claims a hair apart adds up to a move, and a teammate who restarts a raise
just short of its time again and again keeps a downed package carrier alive (the pause) but cannot carry it
anywhere; giving up is the way out. A completed raise sends no `Correction`: the player stands where the host has
it, and its next claim is checked at walking speed from there. Tests: `tests/unit/life/raise_test.gd` (also: a
stop restarts only a knockdown the raise paused, of a player still downed).

#### 7.1.9 Walls
The MVP host does not check movement through walls (nobody asked for cheat protection). It does check
walls for hits, pick-ups and placement, because there an honest client would otherwise stab or grab through a thin
wall.

#### 7.1.10 Hits (the knife's `Use`: `Strike`, §9.4)
The host picks the targets: every living player other than the
attacker (strikes skip the downed, the dead and the invulnerable: for `PlayerRules.invulnerable_s` after a
respawn or a revive, `PlayerState.is_invulnerable`, which nothing ends early, not even the player's own attack, the
engineer's answer 3 on PR #133; M4-3, the revive M4-4) whose capsule has a point within
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

#### 7.1.11 Pick up and swap
The client names the item; the host checks reach and line of sight from its own positions.
The picked item goes to the hand (vision revision 1, Two hands; M4-5, #141). A one-handed hand item moves to an
empty belt; otherwise (a full belt, or a two-handed hand item: the package) the hand item rests where the
picked-up one lay, a spot already known to be valid, whichever of the two is two-handed. `Swap()` exchanges the
hand and belt items; it needs an item in one of them (`nothing_to_swap`) and is refused with a two-handed item in
the hand (`two_handed`), so a package carrier cannot draw a belted knife (V13), and only the living send it. Only
the hand item is used or put down: `Match._find_action` reads the hand, and `HoldsItem` too. The downed keep both
slots; a death places both at the body and a leave drops both, the hand item first; a respawn starts empty.
2e (#61) measures the reach from the feet (the last accepted position) and the sight from the eye to just above
the item (`Items.lifted`, 5 cm), so the floor or crate it lies on does not block the line.

#### 7.1.12 Put down
The client sends only its facing. The host places the item at the put-down distance along the
horizontal facing, through `WorldQuery`: stopped before a wall and dropped to the floor. Prevents: a package put
straight onto its circle across the map, or into a wall. 2e (#61) asks `rest_position` from the eye towards the
point at that distance, so an item goes over what the player sees over (a low crate) and is stopped by a wall; a
facing straight up or down puts it at the feet. The eye of the item rules (`Items.eye_of`) is the floor below
the last accepted position plus the eye height, so a jump does not raise it: nobody puts a package, or sees one,
over a partition from the top of a jump.

#### 7.1.13 Drops
An item dropped at a death or a leave, a downed player, and a body, come to rest on the floor below the
player's last position (through `WorldQuery`), never in mid-air. `Items.drop_carried` (2e, #61; both slots, M4-5) drops the items, asking the floor
from 5 cm above the feet so a ray that starts on the floor still finds it; a level with no floor there is a
level bug: the item rests at that position and the match logs an error. Where a knocked-down player lies
(`LifeRules.knock_down`) and its body at the death (`LifeRules.die`; M4-2) are found the same way, with the same
fallback, and at the death the items then drop at the body (`Items.place_carried`). Nothing drops at a knockdown.

#### 7.1.14 Delivery
The rule is "the package rests inside its circle, however it got there". So one check runs whenever
an item comes to rest: a put-down, a swap, a drop at a death or a leave, the spawn, and a throw, whose rest
`core/` finds at the end of its flight (§7.1.16; the flight built in #642, the cause `thrown`; a thrown package
counts, the engineer's TD4 (a): `tests/unit/tasks/delivery_throw_test.gd`). A package resting inside its own circle is delivered: it
stops being interactive (`PickUp` is rejected) and its circle is shown as done. Holding a package over its circle
never counts, because it is not at rest. A circle is an invisible cylinder standing on the floor at its marker
(the engineer's decision of 2026-09-30, #79): radius 1 m (game design, in the data) and height 2 m (a
placeholder). The package counts when its rest position is inside: within the radius horizontally, edge
included, and from the marker's height up to that plus the height, both included (1 mm below the marker
still counts: float noise between a physics floor and a hand-placed marker): `StationState.contains`, the one
cylinder test of a station, which the zone task asks with a player's feet (§9.5.17, #647). The rest position is the one
point `core/` knows of an item: the centre of its base on the surface it rests on, as `WorldQuery` placed it (a
throw's too, §7.1.16), not the centre of its mesh. So a package on a crate inside the circle counts, one on
a floor below the marker does not. The check reads only that position; it asks no geometry of its own.

#### 7.1.15 Lost claims (#429, M6; the engineer's A1 + B3 on PR #434)
Over Wi-Fi a LATEST `MoveClaim` is lost now and then. Two cases hurt an honest player: Alice's claim for the step
that brought her within reach is lost, and her reliable `PickUp` is checked against the claim before
(`out_of_reach`); Bob's first claim after a placement is lost, and the next one, two ticks of walking, is taken as one
and corrected. The host never widens reach or span for a lost claim (a silent client would gain range). Instead the
client makes those two claims reliable, on `MoveClaimReliable` (§4.3): every epoch's first claim, and its last sent
claim again, exactly as sent (the same tick, position and masks; a fresh position under an old tick would correct a
sprinter), right before an intent of `Intents.PLAYER_ACTIONS`, once per claim, never a claim of an older epoch, and
only while it claims. The host hands the twin to `core/` as the plain `MoveClaim` command, so it passes every check
of §7.1.5: a twin of a claim already applied, or behind a newer one, does not rise and is dropped in silence; a
hostile one is corrected. A resend is not a new claim: `claim_sent` does not fire for it, and the stamina prediction
does not count it. Order holds: ENet carries both lanes on channel 0, and over WebRTC `LaneOrder` drops a LATEST
original that arrives behind its twin. Still accepted: a lost landing claim before a second jump (the host may still
have the player in the air), and §7.1.5's notes on the stamina prediction. Tests:
`tests/unit/client/net/client_session_claim_twin_test.gd`, `tests/integration/server/host_session_claim_twin_test.gd`
(a lossy link end to end), `tests/unit/movement/movement_rule_claim_loss_test.gd`,
`tests/unit/net/messages/wire_schema_test.gd`.

#### 7.1.16 Throws (designed in #37; the flight built in #642, the throw itself not yet)
The [throwing ADR](decisions/2026-10-09-throwing-held-items.md)'s TD1 to TD12 and TE1 are answered: the engineer took
every recommendation ([#302](https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-6085059719); TD1's
speed and the provisional gravity, radius and longest flight in the next two comments there), and this section follows
them. Built so far: the flight and the rest (37b, #642, below); the intent, `ThrowItem`, `ItemThrown` and its wire
rows (37c), the client (37d, 37e) and the base mode's rule (37f) are still to come. The flight runs in `core/` (TE1 (a)), not in
`server/`'s physics, which the earlier sketch named (§9.8): the host's level spaces hold no players or items, and Godot
4.7.2 steps them only by physics frames (no `space_step`), while core ticks come from the clock (§4.5.2), so a landing
there would not follow from the commands.
- **The intent.** `Throw(facing)`, from the living in Round, goes to the first `Throw` rule of the hand item, the
  role or the mode (§9.2): `HoldsItem`, then the effect `ThrowItem` (speed, gravity, radius, longest flight: the
  engineer's numbers). The client sends only its facing; a facing that does not normalize to a unit vector (non-finite,
  zero, or one whose squared length underflows or overflows) takes the last accepted claim's, as `Strike` does
  (§7.1.10). The host launches from `Items.eye_of` (the floor below the last accepted position plus
  the eye height, as a put-down, §7.1.12) at the rule's speed, without the thrower's velocity (TD10). Prevents: a throw
  farther than the rule, from somewhere else, or through a wall. `Throw` is one of `Intents.PLAYER_ACTIONS`, so the
  dead never throw and the client sends its claim's twin right before it (§7.1.15).
- **The flight.** The item is `FLYING`. Each later tick, `FlightTicks` sweeps the arc's segment between two ticks'
  points, each computed from the launch (origin, velocity, gravity, the flight's own count of ticks flown, so a phase
  without `FlightTicks` pauses it rather than making it jump), through a new
  `WorldQuery.sweep(from, to, radius)`: the farthest point a sphere reaches, `from` itself when the sphere starts in
  the world. `server/` answers with `intersect_shape`, then `cast_motion`, which ignores a shape the sphere starts
  in. The mode check keeps the throw's sphere inside the player's capsule at the eye, with a margin, so a thrower pressed against a
  wall can still throw away from it. A living player other than the thrower stops it too (their capsule at the last
  accepted position, as hits read it); the downed are flown over (TD12). Prevents: an item through a crack or a ceiling, and
  a landing that differs between two runs of the same commands. **Built in #642:** `ItemState.Where.FLYING` (after
  `BELT`) keeps an `ItemFlight` (`core/items/item_flight.gd`): o, v, g, the ticks flown n, the fallback f, and what the
  throw's rule sets at the launch: the thrower's id, the radius, the longest flight in ticks and the launch tick L
  (`Items.launch` stamps it). The item's `position` is o while it flies. `ItemFlight.point(o, v, g, n)` is the one arc
  function. `FlightTicks` (`core/items/flight_ticks.gd`, §9.4) skips the launch tick, since a command at L runs before
  L's tick systems: after tick L + k of a phase that lists it, n is k, the point a client computes as p(t − L). A
  segment the world's sweep cuts short (any answer other than its end) is a contact. The players are tested on the part
  of the segment the world leaves, so the earlier of a wall and a player ends it (`FlightTicks.contact_fraction`: the
  capsule's side, then the balls at its axis' ends). An invulnerable living player stops an item too: a stop is not
  damage. The thrower is flown through for the whole flight, wherever it stands. Points are never stored: n and the
  three vectors are the whole state.
- **The rest.** At the first contact the item drops to `floor_below` of the stop point and rests through
  `Items.place` with the cause `thrown`: `ItemPlaced`, then `item_rested`, so the delivery check (§7.1.14) runs as
  for any rest. That rest is the base point on the floor (the engineer's answer on PR #82, recorded on #37). A flight
  past the longest flight stops at its last point. With no floor below the stop, the item rests where the thrower stood (TD11):
  on `floor_below` of the thrower's feet, asked once at the throw and logged, and the match logs an error, as for a drop
  (§7.1.13): a level with a hole. A thrower over no floor is refused (`no_floor`), and the item stays in the hand.
  Prevents: a package thrown off the map's edge hanging in the air out of everyone's reach. **Built in #642:**
  `FlightTicks` rests the item through `Items.place` with `Items.THROWN` (`place` clears the flight), at
  `floor_below(Items.lifted(stop))`, else at the flight's fallback with an error logged. `Items.fallback_rest(ctx,
  feet)` is the fallback's question, for 37c's `ThrowItem` to ask at the launch. A fallback that is itself no floor
  (37c refuses such a throw) rests the item at the stop, with its own error. Readers of `where`: `ItemOnGround`
  rejects an item in flight as `unavailable`, `Items.take` and Delivery act only on the ground, the snapshot's items
  in `core/` show `FLYING` at o, and `Items.free_markers` counts no flying item. Tests: `tests/unit/items/item_flight_test.gd`,
  `flight_ticks_test.gd`, `items_test.gd` (the launch and the readers), `tests/unit/tasks/delivery_throw_test.gd`,
  and the cause in both lists of `tests/unit/net/messages/wire_core_test.gd`. A flight is put in flight by a test's
  `Use` (`FixtureThrow`, for `ThrowItem`); the test that the points decoded from `ItemThrown` equal `FlightTicks`'
  is 37c's (#643), with the event.
- **Who sees it.** `ItemThrown` (item, thrower, origin, velocity, gravity as a `vec3` so that it round-trips
  exactly, launch tick) goes to everyone; nothing in it is hidden (§5) while the rule
  belongs to the item kind or the mode (a role-owned one reveals the role, §9.2). The snapshot stays avatars only (§4.3): the
  thrower's client predicts the arc at the key press, and every other client draws it from `ItemThrown` on its
  avatars' timeline (§7), until `ItemPlaced`; its view joins `SightHider`'s group as every item view (§4.7.10), depth-tested with no trail, and its launch
  sound goes through `SoundChooser`, cut beyond the hearing range like every world sound. The
  flight's geometry reaches the command log as `WorldQuery` answers (§3.3); `server/` originates no command for it.
- **The engineer's answers** (all as recommended, #302): strength and range (TD1 (a); 10 m/s, provisional), which
  items (TD2), what a thrown item does to a player (TD3 (b): stops and drops at its feet, no damage), a thrown package
  counts in its circle (TD4 (a)), where an item may come to rest (TD5), a cost (TD6), the key (TD7), no catching
  (TD8 (a)), stop and drop, no bounces (TD9 (a)), no running throw (TD10 (a)), the rest with no floor below the
  thrower's feet (TD11 (a)), the downed flown over (TD12 (a)). The issues 37a to 37f follow the ADR's split.

## 8. Debug tooling

A dev console and debug commands (spawn bots, force role, skip phase, show hidden info locally) in debug builds
only, so the designer can test a mechanic alone. A debug command reaches `core/` as a command that `server/`
originates (`ForceRole`, 2j; `ForceClock`, M4-3, which forces the match clock's length in seconds for the bot
scenarios, §9.7); on the wire (M3 design) it is a kind that only a debug build's table has and only the
host's own client may send (§4.3, E17).

## 9. Content API (the engine–content contract)

A mechanic is data: `Resource`s composed from parts the engine provides. Adding a mechanic should usually mean
adding data plus at most one new part class, never changing the core loop: that is the test of this API (§9.8). Content
work uses **only** the parts listed here. A missing part becomes an `engine-request` issue; the engineer
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
  - **`MatchState`** (§3.1), for what outlives a phase: players (with their hand and belt items, M4-5); items (kind,
    where: on the ground, in a hand, on a belt or locked, position); tasks, each with a **task state** object (`RefCounted`) that its task type creates in its deal
    and alone reads and writes (Delivery: which subtasks are done; the zone task, #647: the ticks counted per zone); stations;
    **bodies** (peer → rest position, written by `LifeRules.die` before `player_died`, from the death until the
    respawn (`LifeRules.respawn`, M4-3) or the leave; M4-2); two tables keyed by names from the data,
    **cooldowns** (the tick at which a player last paid a key, such as `hit`) and **counters** (an integer per player
    and key, such as uses left, #34); and a **per-part state** table, one `RefCounted` per key that a part class
    declares, for state a new part class needs that fits none of the above (the movement rule's records; the running
    channels, `Channels`, M4-4). So a new part adds state without a new field in `MatchState`. `ResetMatch` clears
    all of it.
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
  - *The mode alone:* a phase, outcome, intent, setting, role, side or item kind that a part names but the mode does not
    declare; an outcome a phase can report without a row (§3.1); a phase whose rules can knock a player down but that
    lists no `LifeTicks` (M4-3); a phase that accepts an intent whose rule starts a channel (a `ChannelEffect`) but
    lists no `ChannelTicks`, so the channel would never complete (M4-4); a `ChannelEffect` outside an action (a
    reaction, a row's actions: no player runs it) or in a rule that lacks a condition the effect requires
    (`ChannelEffect.required_conditions`: `RaiseDowned` needs `TargetDowned`); a reaction or a win condition holding a
    condition that reads the actor (`Condition.reads_actor_state`, §9.4's "Where" column), which tests no player there
    (§9.2, #283, #299), or one that reads the rule's target where nothing supplies it (`Condition.needs_target`: a win
    condition, or a reaction whose fact does not carry it, #379); an accepted intent that neither the phase class
    nor any rule handles; two rules on one trigger in one owner; a number outside its part's bounds; an id outside
    the wire's alphabet (3e, #97; §4.3, E5): every `id`, `side`,
    `spawn_tag` and `tag` a part holds, and every condition's rejection reason, is 1 to 32 characters of `a-z`, `0-9`
    and `_` (D1 (a), the designer's answer on #96). A unit test (2a, `tests/unit/content/content_modes_test.gd`) loads
    every mode in `content/modes/` and runs this part (`ModeCheck`).
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
  so a refused intent pays nothing. **Where a condition may appear.** A reaction runs, and a win condition is checked,
  for no player (actor 0), so a condition that reads the actor (its player state, its hand, its channel) tests no
  player there and its answer never changes: a cost that reads the actor's player state (`Cooldown`, `StaminaCost`)
  always refuses, so a reaction with one would never run its effects, record no cooldown and charge nobody (#201;
  `tests/unit/combat/costs_in_reactions_test.gd`) and a win condition with one would never hold; `HoldsItem` never
  passes and `HandNotTwoHanded` always does. The mode check therefore refuses such a condition in a reaction or a win
  condition at load, naming the mode, the fact or the win condition, its index in `reactions` or `win_conditions` and
  the condition's class (#283, #299; `tests/unit/content/mode_check_test.gd`, `mode_check_actor_test.gd`). A negated
  cost in a reaction gets only the "negates a cost" error, since it passes there and is never paid. A condition says
  whether it reads the actor (`Condition.reads_actor_state`, true unless the class says otherwise, so a new condition
  that forgets is refused rather than silently never or always passing); §9.4's "Where" column gives the answer of
  each part of `core/`. One that reads only the match or the fact is allowed everywhere (as the tests' `FixtureCost`,
  a counter of peer 0). One that reads the rule's target (`Condition.needs_target`: the intent's `target` or `item`,
  the channel's target, the fact's item) finds none in a win condition, which has no intent, channel or fact, nor in a
  reaction whose fact does not carry it (`Condition.target_facts`: only `item_rested` carries one, its item), so the
  mode check refuses it there too, with the same names (#379; `mode_check_target_test.gd`). `needs_target` is false
  unless the class says otherwise: a condition reaches that check only once it said it reads no actor, so its author
  has already said what it reads, and a default of true would mislabel the many that read no target; the guard test in
  `mode_check_actor_test.gd` lists the three answers for every condition of `core/`. Between
  the checks and the costs, an **action** (a rule on an intent) that passed stops its actor's running channel
  (`Channels.interrupt`, M4-4): a raiser who picks up, puts down, uses, swaps (M4-5) or lets go of E stops its
  raise, and a refused intent stops nothing. (`outcome_dropped`, §3.1, is sent after an applied intent, not a refusal.)
- **Effects** (*what happens*) run in order. An effect changes `MatchState` only through `core/`'s own rules (life,
  items, stamina), emits events, raises facts, and may report an outcome (`ReportOutcome`, §3.1).
- **A fact is handled at once, depth first.** When an effect raises one, the rules on it run (the mode's reactions,
  then each task type's check, in the mode's order), then the current phase's win conditions are checked, and only
  then does the raising effect go on. A chain deeper than 16 facts is a bug: `Match` stops it with an error in every
  build.

| Fact | Raised when | The rule sees (**hidden** fields in bold) |
|---|---|---|
| `item_rested` | an item comes to rest: put down; swapped (a pickup's hand item that did not go to the belt, M4-5); dropped at a death or a leave, once per slot, the hand item first; spawned; thrown, at the end of its flight (§7.1.16, `FlightTicks`, #642). A `Swap` between hand and belt raises none: nothing comes to rest | the item, the cause (`put_down`, `swap`, `death`, `leave`, `spawn`, `thrown`), the rest position |
| `player_died` | a downed player dies (its knockdown ran out, M4-2, or it gave up, M4-4), before its hand and belt items drop | the player, the body position; no killer, as no event names one (§4.2). A knockdown raises no fact |
| `player_left` | a player leaves while the life state counts (Round, §3.5), before its hand and belt items drop | the player |
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
| Item kind | `actions`: rules on intents | while a player holds an item of that kind in the hand, never on the belt (the knife's `Use`) |
| Role | `actions` (abilities) | to the players with that role (none in the MVP) |
| Game mode | `actions`, and `reactions` (rules on facts) | to every player, and to every fact (no reactions in the MVP) |
| Task type | its own check of facts, in its class | to its tasks (Delivery on `item_rested`) |

- **An intent** that the phase accepts from this sender (§3.1) goes to the phase class if the class handles it
  (`Hello`, `SetReady`, `LoadAck`, …); `MoveClaim` goes to the movement rule (§7.1); any other goes to the first rule
  with that trigger among the hand item's actions (never the belt item's, M4-5), the actor's role's actions and the
  mode's actions. If there is
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
  `ActorRole`-gated rule with an effect whose event goes to everyone. v0 has none. A channel adds one more way
  (M4-4): any applied action stops its actor's running channel (a raiser's public `RaiseStopped`) while a refused
  one stops nothing, so a role-owned or role-gated action reveals the role of a raiser who tries it; in a mode
  with a channel the check warns about every such action.
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
  `id_sets` (§9.1), map, items (`ItemState`: ground, hand, locked or belt, M4-5; flying with its `ItemFlight`, #642), tasks (`MatchTask`: its task type and `TaskState`,
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
- **Items** (`core/items/items.gd`, 2e #61; the belt M4-5 #141) is the one place that moves an item between the
  ground, a hand and a belt (`PlayerState.held_item`, `belt_item`; `ItemState.Where.BELT`): `held_by` and `belted_by`,
  `take` (the pick-up: the hand item to an empty belt when one-handed, else onto the picked item's spot; `ItemPickedUp`
  with `belted`), `swap` (`Swapped`), `place` (an item comes to rest: `ItemPlaced`, then `item_rested`),
  `place_carried` (both slots, the hand's first: the life rule, 2g, places a dead player's items at its body after
  `player_died`), `drop_carried` (a leaving player's items to the floor below its last accepted
  position; the life rule calls it after the life state changed and `player_left` was raised) and `raise_rested` (`item_rested` for an item
  announced by its own event: after `ItemSpawned`, 2c's `SpawnItems` and 2f's Delivery deal call it with
  `Items.SPAWN`), plus, for a throw (#642, §7.1.16), `launch` (the item leaves the hand or belt into its flight) and
  `fallback_rest` (the floor below the thrower's feet); `FlightTicks` rests it through `place` with `Items.THROWN`.
  `free_markers` counts no item in flight. The causes are constants there. Each condition names its own rejection
  reason as a constant.
- **Tasks** (`core/tasks/`, 2f #62; shared since #79): a task type marks a subtask done in its own task state, then
  calls `Tasks.subtask_done(ctx, task, detail)`, which emits that task's `TaskState` event (`TaskStateEvent`, not
  the task type's `TaskState` class; M4-5, E30: `Tasks.state_of`)
  and `TaskProgress` (everyone; `Tasks.progress` counts the subtasks done and in total over every task), then raises
  `subtask_done`. `Tasks.announce` emits every task's `TaskState` in id order; `DealTasks` calls it after the deal. `Tasks.all_done` is "every task done"
  for `AllSubtasksDone`. Delivery (`core/tasks/delivery.gd`, with its task state as the inner class
  `Delivery.State`) and the zone task (`core/tasks/zone_task.gd`, `ZoneTask.State`, #647) are the two task types.
  `StationState.contains` is the one cylinder test of a station, which both ask. `StationKind.radius_m` and `height_m` have a neutral default of 0,
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
  `Items.LEAVE`), `respawn` (M4-3 #139: from dead, at a marker that `Respawn` draws: the body removed, the role kept,
  health and stamina full, hand and belt empty, a new epoch; then `Respawned` (everyone) and `Correction` (that player)) and
  `make_invulnerable` (`PlayerState.invulnerable_until`: strikes skip the player for `PlayerRules.invulnerable_s`, and
  `damage` does nothing to it, so every damage source spares it; the respawn and the revive call it), and `revive`
  (M4-4 #140: from downed, where it lies: living with the raise's health, stamina kept, invulnerable; then `Revived`
  (everyone), no `Correction`). `die` sets `life_deadline` to the respawn time later. A hit stops the victim's own
  channel (`damage`); `knock_down`, `die` and `leave` first stop every channel the player runs or is the target of
  (a raise: `RaiseStopped`), so a raiser downed, a downed player giving up and either leaving all stop a raise.
  `LifeTicks` (`core/life/life_ticks.gd`), a tick system, calls `die` for each downed player whose
  `life_deadline` has come, and runs its `Respawn` (`core/life/respawn.gd`) for each dead one, in peer-id order
  (without a `Respawn` the dead stay dead); a raise pauses a knockdown by clearing `life_deadline` and keeping what
  was left in `PlayerState.knockdown_left` (M4-4), so `LifeTicks` sees no deadline then. A later weapon
  or a trap calls `damage`; the class is `LifeRules`, not `Life`, which would shadow `PlayerState.Life`.
- **Channels** (`core/channel/`, M4-4 #140): an action that takes time, the generic primitive the raise uses and
  any later timed action reuses (the zone task does not: it counts presence in its own tick, standing being no
  action, ZD1 (a) of the [zone task ADR](decisions/2026-10-09-m7-zone-task.md), the engineer's answer on #302; built
  in #647). A `ChannelEffect` (an effect, abstract)
  starts a `Channel` (state: its effect, the rule it came from, actor, target, start tick, ticks done and needed) for
  its actor on the intent's `target`
  (`Channels.target_of`: the channel's target while it runs, else the intent's, when the intent declares one);
  `Channels` keeps the running ones in `MatchState`'s per-part state, one per actor, and is the one place that
  advances, stops and completes them; `ChannelTicks`, a tick system, advances each running channel once per tick in
  actor-id order: its rule's conditions again (not its costs), with the channel on `MatchContext.channel` and no
  intent, the first failing one stopping it, else one more tick, completing it in the tick that reaches its time. A
  stop or a completion removes the channel, then calls its effect's `stopped` or `completed`. No channel outlives
  its phase: every transition stops every running one before the row's actions (`Channels.stop_all`, from
  `Match`), so a raise running when Round ends sends its `RaiseStopped` before `PhaseChanged`. `ChannelFree` and
  `Channeling` are its conditions; `MatchContext.rule` (set by `RuleRunner`) is how the effect keeps its rule.
- Two class names differ from their kind: `GameRole` and `RuleEffect` (a global `Role` or `Effect` would shadow an
  enum of `NetTransport` or GdUnit4).

| Kind | Answers | Class in `core/` | Data | MVP instances |
|---|---|---|---|---|
| Game mode | which phases, rules and settings a match has | `GameMode`, with `PhaseSpec` (its allowlist of `AcceptSpec`s), `Transition`, `SettingSpec` (a whole number or a set of task types), `SideSpec`, `PlayerRules` | `content/modes/` | the base mode |
| Phase class | what a phase does itself: its own intents, timers and outcomes | `Phase` subclasses (`RefCounted`; a fresh object per entry, §9.1) | named by a `PhaseSpec`, with its settings | Lobby, Countdown, Loading, Round, End |
| Rule | trigger → conditions → effects; an **action** is a rule on an intent, a **reaction** a rule on a fact | `Rule` | inside its owner | PickUp, PutDown, the knife's Use, Raise, StopRaise, GiveUp |
| Condition, cost | *only if*; a cost is also paid | `Condition`, `Cost` subclasses | inside a rule or a win condition | §9.4 |
| Effect, transition action | *what happens*; a transition action is an effect that a transition row runs, with no actor | `RuleEffect` subclasses | inside a rule or a row | §9.4 |
| Tick system | what runs every tick of a phase, in the phase's order | `TickSystem` subclasses | listed per phase | LifeTicks, ChannelTicks, FlightTicks, TaskTicks |
| Voice rule | who hears whom in a phase (§6) | `VoiceRule` subclasses | one per phase | Silent, Proximity, RoundVoice |
| Role | a side, what it knows, its abilities; a display name | `GameRole`, `RoleQuota` | `content/roles/` | Crew, Dissident |
| Item kind | a thing a player can hold, and what using it does; a display name (the HUD's hand or belt item), its spawn tag, and `hands` (1 or 2: a two-handed item never goes on the belt and refuses a swap; the slot model later loot builds on; M4-5) | `ItemKind` | `content/items/` | Package, Knife |
| Task type | how its one shared task is dealt and done, with its own subtasks setting; what it demands of the map; a `description` the task screen shows (M4-5; the mode check refuses an empty one) | `TaskType` subclasses, each with its `TaskState` (§9.1) | `content/tasks/` | Delivery |
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

#### 9.4.1 Conditions and costs
(a failed one rejects an intent with its reason, which reveals only what the column says):

In the "Where" column, *actions only* marks a part that reads the actor (`Condition.reads_actor_state`): the mode
check refuses it in a mode reaction or a win condition, which run for no player (§9.2, #299). *Anywhere* marks one
that reads no actor and no target: an action, a reaction or a win condition. A part that reads no actor but needs the
rule's target (`Condition.needs_target`), which only an intent, a channel or a fact gives, is refused by the mode check
in a win condition and in a reaction whose fact does not carry that target (`Condition.target_facts`), #379: its row
names the facts that do.

| Part | Passes when | Settings | Rejects with | Where (§9.2) | Built in |
|---|---|---|---|---|---|
| `ItemOnGround` | the rule's item (the intent's `item`) exists, lies on the ground (not in a hand or on a belt) and is interactive (not locked, as a delivered package is) | none | `unavailable`: whether an item is held or delivered is public | an action, or a reaction on `item_rested`, whose fact carries the item (reads no actor; needs an item): the mode check refuses it in a win condition and in a reaction on any other fact, which have no item (#379) | 2e (#61) |
| `InReach` | the item's rest position is within `reach_m` of the actor's last accepted position, its feet (§7.1) | `reach_m` (0.1 to 10; no default: the data sets it, the base mode 2) | `out_of_reach` | actions only: reads the actor | 2e (#61) |
| `InSight` | the line from the actor's eye (the floor it stands on at its last accepted position, `WorldQuery.stand_floor_below`, raised by `PlayerRules.eye_height_m`, §7.1) to just above the item's rest position is clear (`WorldQuery.line_of_sight`) | none | `blocked` | actions only: reads the actor | 2e (#61) |
| `HoldsItem` | the actor has an item in hand (a belt item does not count) | none | `empty_hand` | actions only: reads the actor | 2e (#61) |
| `CarriesItem` | the actor has an item in the hand or on the belt: the base mode's `Swap` | none | `nothing_to_swap`: its own slots | actions only: reads the actor | M4-5 (#141, `core/items/carries_item.gd`) |
| `HandNotTwoHanded` | the actor's hand item, if any, is not two-handed (`ItemKind.hands` 2): a package carrier cannot draw a belted knife (V13) | none | `two_handed`: what it holds is public | actions only: reads the actor | M4-5 (#141, `core/items/hand_not_two_handed.gd`) |
| `ActorRole` | the actor's role is one of the listed (no MVP use) | `roles` | `not_allowed`: the actor knows its own role | actions only: reads the actor | with the first mechanic that needs it (#34) |
| `AllSubtasksDone` | every task is done (`Tasks.all_done`): a task with no subtasks is done, and with no tasks it holds (the engineer's rule of 2026-09-30, #79) | none | (facts only) | anywhere: reads no actor | 2h (#64, `core/win/all_subtasks_done.gd`) |
| `NoneAlive` | no player of the side is present: each has left (M4-2: the downed and the dead still count; the name stays from "no crew alive"). A player's side is its role's; a player without a role of the mode is on no side, and with no player of the side it holds (the base mode's deal always leaves at least one crew member). It reads every player's role, which is hidden, but only as a win condition, whose `won` reaches no peer (§9.2) | `side` (a side of the mode) | (facts only) | anywhere: reads no actor | 2h (#64, `core/win/none_alive.gd`) |
| `ClockEnded` | the match clock has reached its end (`MatchState.clock_ended`, set when `Match` raises `clock_ended`); before `StartClock` there is no end | none | (facts only) | anywhere: reads no actor | 2h (#64, `core/win/clock_ended.gd`) |
| `Cooldown` (cost) | this player never paid this key, or at least `seconds` (in host ticks, toward zero, §3.3) passed since it last did; paying records the tick in `MatchState`'s cooldown table. Per player, not per item: a second knife does not skip it. | `key` (no default: the data names it), `seconds` (0 to 600; 0) | `too_soon`: its own timing | actions only: reads the actor | 2g (#63, `core/combat/cooldown.gd`) |
| `StaminaCost` (cost) | the actor's stamina, settled first (§7.1), is at least `amount`; paying spends it and emits `SelfStatus` (the actor, at the end of the tick). | `amount` (whole points, 0 to `PlayerRules`' stamina maximum) | `tired`: its own stamina | actions only: reads the actor | 2d (#60) |
| `TargetDowned` | the rule's target player (`Channels.target_of`: the intent's `target`, or the running channel's) is downed | none | `not_downed`: who is downed is public | an action (and its channel) only (reads no actor; needs a target player): the mode check refuses it in a reaction or a win condition, since no fact carries a target player (#379) | M4-4 (#140, `core/life/target_downed.gd`) |
| `TargetInReach` | the target lies within `reach_m` of the actor: both last accepted positions, their feet (§7.1) | `reach_m` (0.1 to 10; no default: the data sets it, the base mode's raise 2) | `out_of_reach` | actions only: reads the actor | M4-4 (#140) |
| `TargetInSight` | the line from the actor's eye (`Items.eye_of`) to just above the target's feet (`Items.lifted`) is clear (§7.1), as `InSight` for an item | none | `blocked` | actions only: reads the actor | M4-4 (#140) |
| `ChannelFree` | the actor runs no channel and no channel targets the rule's target, apart from the channel being checked again: one channel per actor and one per target (one raiser at a time) | none | `busy`: every channel of the MVP (a raise) is public | actions only: reads the actor | M4-4 (#140, `core/channel/`) |
| `Channeling` | the actor runs a channel | none | `not_channeling`: its own state | actions only: reads the actor | M4-4 (#140) |

#### 9.4.2 Effects in rules

| Part | What it does | Settings | Emits (audience); raises | Built in |
|---|---|---|---|---|
| `TakeIntoHand` | the item goes into the actor's hand; a one-handed hand item moves to an empty belt, any other hand item is swapped: it rests where the picked-up one lay (§7.1.11; the belt M4-5). An item not on the ground (a rule without `ItemOnGround`) is a rule error, logged, and nothing moves; the sender gets `Rejected` (`unavailable`) | none | `ItemPickedUp` (everyone, with `belted`: the item moved to the belt, or none); for a swap `ItemPlaced` (swap, everyone), then `item_rested` | 2e (#61); the belt M4-5 (#141) |
| `SwapHands` | the actor's hand and belt items change places, either of which may be empty (`Items.swap`); run after `CarriesItem` and `HandNotTwoHanded`. One that would put a two-handed item on the belt (a rule without `HandNotTwoHanded`) is a rule error, logged, and nothing moves; the sender gets `Rejected` (`two_handed`). As every applied action, it stops the actor's raise first (§9.2) | none | `Swapped` (everyone) | M4-5 (#141, `core/items/swap_hands.gd`) |
| `PutDownInFront` | the hand item rests `distance_m` along the horizontal facing, stopped before a wall and dropped to the floor (`WorldQuery.rest_position` from the actor's eye, taken from the floor it stands on, §7.1.12); a facing with no horizontal direction puts it at the feet | `distance_m` (0.3 to 3; no default: the data sets it, the base mode 1) | `ItemPlaced` (put down, everyone); `item_rested` | 2e (#61) |
| `Strike` | picks the targets as in §7.1.10 (living, never downed, never invulnerable (M4-3), not the attacker, within reach and half the angle, overlapping vertically, in line of sight from the eye) and damages each through the life rule (`LifeRules.damage`), in peer-id order; at 0 health a target is knocked down there (M4-2) | `angle_deg` (1 to 360), `reach_m` (0.1 to 10), `damage` (whole points, 1 to 1000); no defaults: the data sets them (the knife 30, 1.5, 50) | `Swung` (everyone), even with no target, before any damage; per target `Damaged` and `SelfStatus` (the victim). A knockdown: `KnockedDown` (everyone), `Correction` (the downed); nothing drops (M4-2) | 2g (#63, `core/combat/strike.gd`) |
| `RaiseDowned` (a `ChannelEffect`) | the raise (§7.1.8): starts a channel of the actor on the downed target; its rule's conditions are checked again every tick (`ChannelTicks`). Start: the target's knockdown pauses (`PlayerState.knockdown_left`) and the movement rule holds it in place. Stop (a condition failing, any applied action of the raiser, the raiser hit, downed or leaving, the target giving up or leaving): the knockdown runs on from where it paused. Completion after `seconds`: `LifeRules.revive` with `revive_health` | `seconds` (0.05 to 600; the base mode 3), `revive_health` (whole points, 1 to `PlayerRules.health`; the base mode 50, E27); no defaults: the data sets them | `RaiseStarted`, `RaiseStopped` (no cause), `Revived` (everyone); the revived player's `SelfStatus` | M4-4 (#140, `core/life/raise_downed.gd`) |
| `Die` | the actor, downed, dies at once (`LifeRules.die`): a raise of it stops first; the body, `player_died`, the drop of both slots at the body, the hand item first. A living actor is a rule error, logged | none | `RaiseStopped` (when raised), `Died` (everyone), per dropped item `ItemPlaced` (death, everyone); `player_died`, `item_rested` per item | M4-4 (#140, `core/life/die.gd`) |
| `Respawn` (held by `LifeTicks`, not by a rule) | the actor, dead, comes back at a marker of `tag` in the current level, drawn uniformly with its RNG purpose from the free ones (no living or downed player within `PlayerRules.respawn_free_m` of it); from all of them when none is free (the engineer's answer 5 on PR #133); then `LifeRules.respawn` (§9.3). A marker missing is a rule error, logged | `tag` (`respawn`), `rng_purpose` (`respawn`); no defaults: the data sets them. Demands: one `tag` marker on every map, which the layout check and the lobby's fit check sum through `LifeTicks` | `Respawned` (everyone), `Correction` (that player), its `SelfStatus` at the end of the tick | M4-3 (#139, `core/life/respawn.gd`) |
| `ReportOutcome` | reports an outcome of the current phase (a button in the level, say; no MVP use) | `outcome`, `argument` | an outcome (§3.1), which reaches no peer (§9.2) | with the first mechanic that needs it; 2a builds the outcome reporting it calls |

#### 9.4.3 Transition actions
(effects that a transition row runs; the base mode's rows are in §9.5):

| Part | What it does | Settings | Emits (audience) | Built in |
|---|---|---|---|---|
| `DealRoles` | each quota in order draws its players from the present players not drawn yet, taken in peer-id order and shuffled with its RNG purpose; everyone else gets the default role. Roles forced by a debug command or a scenario (debug builds only, §8) come as data, because `core/` cannot tell a debug build: the command `ForceRole` (peer, role id; an empty id clears it), which only `server/`'s debug path (from M3 also built from peer 1's debug-kind message, §4.3 E17) or the scenario runner sends, in any phase and after the peer connected, since ENet names a peer only then; it sets `MatchState.forced_roles`, which `ResetMatch` keeps, for the deals that follow, and is in the command log like every command; a role the mode lacks is a match error and ignored. Each present peer with a forced role gets it before the draws, and a forced role counts toward its quota (the engineer's answer A on #30: `dissidents` 1 with bot 2 forced to dissident makes bot 2 the only dissident), so a quota draws its count minus the players forced to its role, never below 0; a forced role the mode lacks is a match error and ignored (2j) | `quotas` (`RoleQuota`: role, `count_setting`, `leave_at_least` (0 to 10; class default 0, the mode writes its number): the count is max(0, min(setting, N − leave_at_least)), and never more than are left), `default_role`, `rng_purpose` (`roles`) | `RoleAssigned` (that player), in peer-id order; then, per role of the mode that knows its teammates and has players, in the mode's order, `Teammates` (every player of that role); a forced role is told like a drawn one | 2c (#59); forced roles 2j (#66, `tests/unit/deal/deal_roles_test.gd`) |
| `DealTasks` | draws `tasks_setting` different task types at random (`rng_purpose`) from the mode's task types minus those in `banned_setting`, and runs each drawn type's `TaskType.deal` once, in the mode's order (§9.5, Delivery): one shared task each, owned by nobody (#79). Then each task's `TaskState` in id order (M4-5, E30: `Tasks.announce`) and `TaskProgress`. More tasks than types left (a check that did not run) is an error, and it deals the types left. Refuses in `ChangeSettings` (`settings_problem`): `tasks` above the types not banned, or every type banned (`out_of_bounds`). Mode check: `tasks_setting` a whole number whose maximum is at most the mode's task types, `banned_setting` a set of task types, `rng_purpose` not empty | `tasks_setting` (`tasks`), `banned_setting` (`banned_task_types`), `rng_purpose` (`task_types`) | the task types' events (Delivery: `StationPlaced`, `ItemSpawned`), then `TaskState` per task and `TaskProgress` (everyone) | 2c (#59), shared and drawn in #79; tested with fake task types; Delivery's deal in 2f (#62) |
| `SpawnItems` | places `count_setting` items of `kind` on distinct random markers of the kind's spawn tag, skipping the markers where an item already rests (at most one item per marker in a deal, such as a package of Delivery's deal on a shared tag), into `MatchState`'s items; ids follow the markers' level order. Too few free markers (a fit check that did not run) is an error, and it places none | `kind`, `count_setting`, `rng_purpose` (`knives`) | `ItemSpawned` (everyone), in id order; then `item_rested` (spawn) for each, in id order | 2c (#59) |
| `PlacePlayers` | places every player at a distinct random marker of `tag` (§3.2) | `tag`, RNG purpose (`spawns`) | `PlayersPlaced` (everyone); `Correction` with a new epoch (each player) | 2a (#49) |
| `StartClock` | sets the match clock's end to now plus the setting (whole minutes, in ticks toward zero: 10 min is 12000); the last action of the deal's row, so the round's `PhaseChanged` announces the end tick. In a debug build a `ForceClock` (`MatchState.forced_clock_s`, in seconds) replaces the setting (§8, §9.7 `clock_s`). Mode check: a whole-number setting (not a set of ids) whose minimum is at least 1, since a 0-minute clock never ends | `minutes_setting` (`match_duration`) | `RoundStarted` (everyone), with the start tick | 2h (#64, `core/win/start_clock.gd`) |
| `EndMatch` | records the side of the `won` outcome as the winner (`MatchState.winner`). An argument that is no side of the mode is a rule error, logged, and nothing is recorded or emitted | none | `MatchEnded` (everyone): the side only | 2h (#64, `core/win/end_match.gd`) |
| `ResetMatch` | resets the match state from the roster: items, stations, tasks and their task states, bodies, roles, life, health, stamina, cooldowns, counters, per-part state, the clock and the winner; drops the players who left; keeps the session's join count (§3.5); everyone un-ready. Runs before the row's `PlacePlayers` | none | `ReadyChanged` (everyone), per player | 2b (#58, `core/match/reset_match.gd`) |

#### 9.4.4 Demands
Every placing action, and every task type through `DealTasks`, answers one question: given the settings
and the player count, how many markers of which spawn tag does it need (and, for a station kind, how many colours).
2a defines that interface on `Effect` and `TaskType`, with no demand by default; M4-3 adds it to `TickSystem`, so
`LifeTicks` forwards its `Respawn`'s one `respawn` marker, taken per tag at the most that any one phase played on the
level needs (a `Respawn` in two phases asks for one marker). `DealTasks` asks each task type not
banned for the demand of its one task; it reads the mode's task types from `Demands.mode` and the bans from
`Demands.id_sets`, because an effect's `add_demands` is given neither, so a `Demands` is always built for a mode
(`Demands.new(mode)`, 2c) with the set settings (`LayoutCheck.demands_of`). Which types a match draws is random, so
the fit check must hold for any draw (#79): per spawn tag `DealTasks` demands the sum of the *tasks* largest demands
of that tag among the types left, and per station kind the same over colours. Any draw of *tasks* types sums, per
tag, at most that, so a map that fits it fits every draw; with one type in the pool it is exactly that type's demand.
The price is a stricter check than a given draw needs when the types' demands differ. `all_ready` (2b,
`FitCheck`) sums the demands per tag over every row into a phase on the map and the tick systems of the phases
played on it (per tag, the most that any one of those phases needs; `LayoutCheck.demands_of`), compares
each sum with the chosen map's markers of that tag and each colour count with its palette (`Demands.shortfalls`,
§3.2, §9.6), checks the player count against the mode's bounds, and `SettingsChanged` shows them.

#### 9.4.5 Tick systems, phase classes and voice rules

| Part | Kind | What it does | Settings | Emits (audience) | Built in |
|---|---|---|---|---|---|
| `LifeTicks` | tick system | each downed player whose knockdown time has run out (`PlayerState.life_deadline`) dies (`LifeRules.die`), and each dead player whose respawn time has run out respawns through `respawn` (M4-3), in peer-id order; a downed player being raised has no deadline (M4-4: the raise keeps what was left). A phase whose rules can knock a player down (an accepted intent's action or a reaction with an effect that emits `KnockedDown`: a `Strike`) lists it, or the mode check refuses the phase (M4-3) | `respawn` (a `Respawn`, or none: the dead stay dead); the knockdown and respawn times are `PlayerRules.knockdown_s` and `respawn_s` (E27) | a death's `Died` (everyone), then the dropped item's `ItemPlaced` (death, everyone); the facts `player_died`, `item_rested`; a respawn's events. Demands: its `Respawn`'s | M4-2 (#138, `core/life/life_ticks.gd`); the respawn M4-3 (#139) |
| `ChannelTicks` | tick system | each running channel, in actor-id order: its rule's conditions again (not its costs), the first failing one stopping it; else one more tick, and the tick that reaches its time completes it (`Channels.advance`). A phase that accepts an intent whose rule starts a channel lists it, or the mode check refuses the phase | none | what the channels' effects emit when they stop or complete (the raise: `RaiseStopped`, `Revived`, `SelfStatus`) | M4-4 (#140, `core/channel/channel_ticks.gd`) |
| `FlightTicks` | tick system | each item in flight, in id order, except in its launch tick: one more tick flown and the swept segment between the arc's two points; the world's contact or a living player's other than the thrower (its capsule widened by the item's radius) ends the flight, as does its longest flight; the item rests on the floor below the stop through `Items.place` (cause `thrown`), or at the flight's fallback below the thrower's feet, with an error logged (§7.1.16). A phase that does not list it pauses every flight | none | `ItemPlaced`, and what the rules on `item_rested` emit | 37b (#642, `core/items/flight_ticks.gd`) |
| `TaskTicks` | tick system | runs the tick of each task type that has one, in the mode's order: the zone task's (§9.5.17, #647; Delivery has none). `ModeCheck` refuses a mode with a ticking task type where no phase lists it | none | the task types' events | 2f (#62); the first ticking type, #647 |
| `Lobby` | phase class | allows joins; `Hello` (the join, §3.5), `SetReady`, `ChangeSettings`; leaves (§3.5); reports `all_ready` (§3.2) after a `SetReady`, a settings change (numbers and the bans of task types, #79), a leave and on entry. Rejects (§4.1): `wrong_version`, `full`, `bad_args`, `unchanged`, `unknown_setting`, `out_of_bounds` (a bound, an unknown task type id, or a row action's `settings_problem`), `unknown_map` | none | `Welcome` (the joiner); `PlayerJoined`, `PlayerLeft`, `ReadyChanged`, `SettingsChanged` (everyone); `AllowJoins`, `DisconnectPeer` (server); `Rejected` (the sender) | 2b (#58) |
| `Countdown` | phase class | as Lobby for joins, leaves and `SetReady(false)`, each reporting `cancelled`; `countdown_done` on its end tick, `seconds` after entry | `seconds` (0 to 60; the class default 0) | as Lobby, and `CountdownCancelled` (everyone); its end tick goes out in `PhaseChanged` | 2b (#58) |
| `Loading` | phase class | refuses joins; `LoadMatch`; takes `LoadAck`s (another match's dropped, a second `unchanged`); at the deadline drops who did not confirm, never the host; a leave drops too; reports `all_loaded` | `deadline_seconds` (5 to 600; required, since a missing deadline would drop every client at once) | `LoadMatch`, `PlayerLoaded`, `PlayerLeft` (everyone); `Disconnecting` (the dropped player, M4-6); `RefuseJoins`, `DisconnectPeer` (server) | 2b (#58) |
| `Round` | phase class | nothing of its own: its intents go to rules, a leave to the life rule (§3.5, `LifeRules.leave`; a newcomer's leave is forgotten); a connection gets `DisconnectPeer` (2b) | none | `DisconnectPeer` (server); a leave: `PlayerLeft` (everyone), `player_left`, the drop's `ItemPlaced` (leave, everyone) and `item_rested` | 2a (#49); the leave 2g (#63) |
| `End` | phase class | `ReturnToLobby` from the host reports `back`; a leave sets life `left` (§3.5); a connection gets `DisconnectPeer` | none | `PlayerLeft` (everyone); `DisconnectPeer` (server) | 2b (#58) |
| `Silent` | voice rule | nobody hears anybody; its hearing radius is 0 | none | the routing per tick (§5) | 2i (#65, `SilentVoice`); the radius M5-1 (#215) |
| `Proximity` | voice rule | every pair of present players within the radius (3D, §6), under the voice invariant (§6.3, for every rule): nobody hears the downed or the dead; its hearing radius is `radius_m` | `radius_m` (0.5 to 100; the class default 0, which the mode check refuses) | the routing per tick | 2i (#65, `ProximityVoice`); the radius M5-1 (#215) |
| `RoundVoice` | voice rule | a living or downed listener hears a living speaker within `living_m`, measured from the listener's last accepted position (where a downed player lies); under the voice invariant nobody hears the downed or the dead, the dead hear nobody, and a player who left hears and is heard by nobody (§6); its hearing radius is `living_m` | `living_m` (0.5 to 100; the class default 0, which the mode check refuses) | the routing per tick | 2i (#65); the ghost radii removed in M4-1 (#137); the radius M5-1 (#215) |

#### 9.4.6 A voice rule's hearing radius (M5-1, #215; E41)
Every voice rule answers `hearing_radius_m()`, the farthest it
routes a voice (3D, its edge included), 0 when it routes nobody; `VoiceRule.radius_of(rule)` gives 0 for a phase with
no voice rule. The client fades a voice to silence there and the leak test fails any frame from farther away (§5,
§6), so a new voice rule returns the radius its `hears` uses; one that routes past it fails every scenario where
players stand beyond it.

The match clock itself is not a part: `Match` counts it in phases whose clock runs, after their tick systems
(§3.3), and raises `clock_ended`.

### 9.5 The MVP's content (provisional)
The first content, one entry each. It is provisional: built by the engineer's agent under the
[MVP content ADR](decisions/2026-09-29-mvp-content-built-by-the-engineer.md), reviewed by the designer in #38. Every
new part or piece of content gets an entry in this format:

```
#### 9.5.<n> <Name> (<kind>)
What it does: one sentence.
Settings: name: value or type (allowed values, default).
Produces: events (audience), facts, outcomes, state changes.
Visible to: who learns the result, and when.
Status: designed in #33 · built in <PR>. Tests: path.
```

#### 9.5.1 Base mode (game mode)
What it does: the MVP match, Lobby → Countdown → Loading → Round → End → Lobby (§3.2).
Settings:
- Written in `content/modes/base_mode.tres`, over neutral class defaults (0), so the designer sees every number
  there (the engineer's answer on #49): players, the match settings and the phase settings. The Godot saver drops
  a value equal to its class default, so a bound of 0 (`dissidents` and `knives` from 0) is the default itself.
- players 1 to 10. Match settings, default (bounds): `match_duration` 10 min (1 to 60); `tasks` 2 (1 to 2, the
  number of the mode's task types; #79; 2 since #649, ZD8 (a): every match deals Delivery and the zone task);
  `banned_task_types` (a set of task types, empty; a ban that leaves fewer types than `tasks` needs the lower
  `tasks` in the same change); `packages`, Delivery's subtasks, 6 (1 to 10, a placeholder, "not a decision");
  `zones`, the zone task's subtasks, 1 (1 to 1: the engineer's one zone, and the palette's one colour allows no
  more; the bounds a placeholder, "not a decision", #649); `dissidents` 1 (0 to 9, lowered to N − 1 by the deal);
  `knives` 2 (0 or more; the map's `knife` markers bound it at `all_ready`).
- `PlayerRules`, value (bounds): health 100 (1 to 1000); stamina 100 (1 to 1000), regenerating 15 per second (0 to
  1000); walk 4.5 m/s (0.5 to 20); sprint 7 m/s (at least walk, to 30) for 20 per second (0 to 1000), from 20 (0 to the
  maximum); jump 1 m (0 to 5) for 10 (0 to the maximum); the downed crawl at 1 m/s (`crawl_speed_mps`, 0.1 to the
  walk speed) for a knockdown of 10 s (`knockdown_s`, 1 to 120; vision revision 1's numbers, M4-2, the bounds
  placeholders, "not a decision"); the dead respawn after 30 s (`respawn_s`, 1 to 300) at a `respawn` marker with
  no living or downed player within 1 m (`respawn_free_m`, 0 to 5) and are invulnerable for 3 s (`invulnerable_s`,
  0 to 30; M4-3, the bounds placeholders); capsule radius 0.4 m (0.1 to 1) × height 1.8 m (0.5 to 3); eye 1.6 m (below
  the height); step 0.3 m (0 to 1). Health and stamina are whole points here, thousandths inside `core/` (§3.3).
  `PlayerRules`' class defaults are 0,
  so each number is written in `base_mode.tres` (`PlayerRules_base`), and a mode that leaves one out fails the mode
  check (2d, #60; the engineer's answer (1) on #58). Pushing (§7.1.6) is not in `PlayerRules`: `push_speed_factor`,
  `push_side_bias` and `push_max_overlap` are client feel tuning in `client/player/player_tuning.tres` (engineer),
  placeholders, never checked by the host; every client must ship the same values.
- Sides: `crew` ("Engineers"), `dissidents` ("Dissidents"). Roles: `crew` ("Engineer"), Dissident. The ids stay
  `crew` (vision revision 1's names, M4-1). Item kinds: Package, Knife.
- Actions: PickUp, PutDown, Raise, StopRaise, GiveUp, Swap (below). Reactions: none. Task types: Delivery, Hold
  the zone (§9.5.17). Win conditions, in order: every task done, no crew present, time up.
- Phases (accepts; tick systems; win conditions; clock; voice; level): Lobby (§3.2; none; no; stopped; Proximity 8 m;
  lobby), Countdown 5 s (§3.2; none; no; stopped; Proximity 8 m; lobby), Loading 60 s (`LoadAck`; none; no; stopped;
  Silent; map), Round (`MoveClaim` from the living and the downed, `PickUp`, `PutDown`, `Use`, `Raise`,
  `StopRaise` and `Swap` from the living, `GiveUp` from the downed; LifeTicks with a Respawn (`respawn` markers, the RNG purpose
  `respawn`), ChannelTicks, TaskTicks; yes; runs; RoundVoice; map), End
  (`ReturnToLobby` from the host; none; no; stopped; Silent; map). Snapshots in Lobby, Countdown and Round. RoundVoice's
  `living_m`: 8 m.
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
LifeTicks before it, the crawl speed and the knockdown time; M4-4 (#140) the raise and the give-up, and ChannelTicks
between them; M4-5 (#141) the Swap and Round's `Swap` from the living. 2c (#59) added Crew, Dissident,
the Knife and the `Loading, all_loaded → Round` actions, whose `DealTasks` deals Delivery. #79 made the tasks
shared and drawn: the settings `tasks`, `banned_task_types` and `packages`. #649 (M7-Z3) added Hold the zone to
the task types, the `zones` setting and `tasks` 2 (1 to 2). Tests: the mode check of 2a,
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

#### 9.5.2 Crew (role)
What it does: the side that wins only when every task is done (§3.4).
Settings: id `crew`; display name "Engineer" (its side's "Engineers"; vision revision 1, M4-1); side `crew`; knows
its teammates: no; actions: none. The default role of `DealRoles`.
Produces: `RoleAssigned(crew)`.
Visible to: that player only (§5); `MatchEnded` names only the winning side, never a player's role.
Status: designed in #33; built in 2c (#59): `content/roles/crew.tres`; named Engineer in M4-1 (#137). Tests:
`tests/unit/deal/deal_roles_test.gd`, `tests/unit/content/content_modes_test.gd` (which pins both names).

#### 9.5.3 Dissident (role)
What it does: the side that wins when time is up or no crew member is alive; dissidents know each other.
Settings: id `dissident`; display name "Dissident"; side `dissidents`; knows its teammates: yes; actions: none.
Dealt by the quota `dissidents`, leaving at least one other player.
Produces: `RoleAssigned(dissident)`; `Teammates(dissident, peers)`.
Visible to: `RoleAssigned` to that player; `Teammates` to each dissident, and to nobody else.
Status: designed in #33; built in 2c (#59): `content/roles/dissident.tres`. Tests:
`tests/unit/deal/deal_roles_test.gd`, `tests/unit/content/content_modes_test.gd`.

#### 9.5.4 Delivery (task type)
What it does: one shared task of `packages` packages (the engineer's decision of 2026-09-30, #79); a subtask is done
when its package rests inside its own circle, however it got there (§7.1.14). Nobody owns the task: any living player
delivers any package.
Settings: `package`: the Package item kind; `circle`: a station kind (spawn tag `circle`, radius 1 m (0.2 to 10;
game design, in the data, not a lobby setting), height 2 m (0.1 to 10; a placeholder, "not a decision"), a colour
palette: 10 distinct colours, provisional, one per package at the most `packages` allows); `subtasks_setting`:
`packages` (its own subtasks setting: 1 to 10, default 6, a placeholder); RNG purposes `circles_rng`,
`packages_rng`, `tasks_rng` (`circles`, `packages`, `tasks`). One circle per package, fixed, not a setting.
`description` (M4-5, the task screen): "Carry each package to the circle of its colour. Packages take both hands."
(provisional wording, "not a decision").
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
  (`StationState.contains`, §7.1.14, since #647; `Delivery.rests_in` before: its rest position within the radius horizontally, and from the marker's height up to
  that plus the height, edges included) is delivered: locked (no longer interactive), its circle done, its subtask
  done; then `PackageDelivered`, `TaskState` (M4-5), `TaskProgress` and `subtask_done` (detail: the subtask's index
  and its package), in that order. Any other item in a circle, or a package in another package's circle, does nothing.

Produces: `StationPlaced` and `ItemSpawned` (with the circle and colour) in id order, `PackageDelivered`, `TaskState`
(its task's subtasks done and in total), `TaskProgress` (the subtasks done and in total, over every task); `item_rested` (spawn), `subtask_done`. Its task
state (`Delivery.State`): per subtask its package, its circle and whether it is done. It has no tick; the zone task
(§9.5.17, #647) is the task type that ticks.
Visible to: everyone, all of it: the task is shared, so every player learns the same (the downed and the dead too;
a player who left, nothing). `PackageDelivered` names the item and the circle, never the task.
Status: designed in #33; built in 2f (#62): `core/tasks/delivery.gd`, `content/tasks/delivery.tres` (provisional);
shared, with the cylinder, in #79. DealTasks (2c, #59) calls its deal, and its packages take only free markers
(`Items.free_markers`). Tests: `tests/unit/tasks/delivery_deal_test.gd` (the deal, the demands, the mode check, no
private task event), `tests/unit/tasks/delivery_test.gd` (the check; a done subtask is never delivered again; the cylinder's
edges moved with the test to `tests/unit/match/station_state_test.gd` in #647), `tests/unit/content/delivery_content_test.gd` (the base mode's task settings, the circle and its palette),
`tests/unit/content/layout_check_test.gd` (its demands reach the fit check). M4-5 (#141): the description and
`TaskState` (`delivery_test.gd`, `delivery_deal_test.gd`, `tests/unit/deal/deal_tasks_test.gd`; the description's mode
check in `tests/unit/content/mode_check_test.gd` and `item_intents_test.gd`).

#### 9.5.5 Package (item kind)
What it does: the item a Delivery subtask moves; any living player may carry any package.
Settings: id `package`; display name "Package"; spawn tag `package`; `hands` 2 (M4-5, vision revision 1: never on
the belt, and a carrier cannot swap); actions: none, so `Use` with a package in hand is rejected (`nothing_to_do`).
Placed by Delivery.
Produces: `ItemSpawned`, `ItemPickedUp`, `ItemPlaced`; once delivered, `PackageDelivered`, and `PickUp` gets
`unavailable`.
Visible to: everyone.
Status: designed in #33; built in 2e (#61, `content/items/package.tres`) and 2f (#62, Delivery); `hands` in M4-5
(#141, provisional). Tests: the parts' in `tests/unit/items/` (a package built in code, two-handed); its delivery in
`tests/unit/tasks/delivery_test.gd`; the base mode's `hands` in `tests/unit/content/item_intents_test.gd`.

#### 9.5.6 Knife (item kind)
What it does: the MVP's weapon: `Use` strikes in front of the holder.
Settings: id `knife`; display name "Knife"; spawn tag `knife`; `hands` 1 (M4-5: it fits the belt, and one player
may carry both knives, one in hand and one on the belt, V13); actions: one rule on `Use` with costs `Cooldown`
(key `hit`, 0.5 s) and `StaminaCost` (25), and the effect `Strike` (30°, 1.5 m, 50 damage). The cooldown key is per
player, so swapping to a second knife does not skip the interval (§7.1.10). Placed by `SpawnItems` (`knives`).
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
who learns what, the downed and the dead skipped), `tests/unit/combat/cooldown_test.gd`,
`tests/unit/combat/costs_in_reactions_test.gd` (a cost in a mode reaction refuses actor 0, #201),
`tests/unit/stamina/stamina_cost_test.gd`, `tests/unit/life/life_rules_test.gd` (every life transition, the crawl, the
dead, the §3.4 order, a death of a player who is not downed refused; M4-2), `tests/unit/life/respawn_test.gd` (the
respawn at a free marker or any, its events, invulnerability that strikes skip and nothing ends early, the avatar's
flag; M4-3), `tests/unit/match/phases/round_phase_test.gd` (leaving mid-round).

#### 9.5.7 Every task done (win condition)
What it does: the crew's only win.
Settings: side `crew`; conditions: `AllSubtasksDone`.
Produces: `won(crew)`, then `EndMatch`: `MatchEnded(crew)`.
Visible to: everyone, the side only.
Status: designed in #33; built in 2h (#64): `content/win_conditions/every_task_done.tres`. Tests:
`tests/unit/win/all_subtasks_done_test.gd`, `tests/unit/win/clock_ended_test.gd` (a delivery on the end tick),
`tests/unit/content/content_modes_test.gd` (the base mode's data).

#### 9.5.8 No crew present (win condition)
What it does: the dissidents win when every crew member has left (vision revision 1, V10). A downed or dead crew
member is still present: killing takes time from the crew, it does not end the round.
Settings: side `dissidents`; conditions: `NoneAlive` (side `crew`; the class keeps its old name).
Produces: `won(dissidents)`, then `MatchEnded(dissidents)`.
Visible to: everyone, the side only.
Status: designed in #33; built in 2h (#64) as "no crew alive"; replaced in M4-2 (#138):
`content/win_conditions/no_crew_present.tres` (provisional), in `no_crew_alive.tres`'s place in the order. Tests:
`tests/unit/win/none_alive_test.gd` (a knockdown and a death end nothing, the leaves, the §3.4 order),
`tests/unit/content/content_modes_test.gd`.

#### 9.5.9 Time up (win condition)
What it does: the dissidents win when the clock ends with a subtask not done, with 0 dissidents too.
Settings: side `dissidents`; conditions: `ClockEnded`, `AllSubtasksDone` negated.
Produces: `won(dissidents)`, then `MatchEnded(dissidents)`.
Visible to: everyone, the side only.
Status: designed in #33; built in 2h (#64): `content/win_conditions/time_up.tres`. Tests:
`tests/unit/win/clock_ended_test.gd` (0 dissidents too), `tests/unit/win/end_match_test.gd`,
`tests/unit/content/content_modes_test.gd` (0 dissidents set through the base lobby).

#### 9.5.10 PickUp (action)
What it does: takes an item from the ground into the hand; a one-handed hand item goes to an empty belt, any other
rests where the picked one lay (§7.1.11; M4-5).
Settings: a rule on the base mode: trigger `PickUp`; conditions `ItemOnGround`, `InReach` (2 m), `InSight`;
effects `TakeIntoHand`.
Produces: `ItemPickedUp` (with `belted`, the item moved to the belt, or none); with a hand item that does not go to
the belt, `ItemPlaced` (swap) and `item_rested` for it, so a package swapped onto its circle is delivered.
Visible to: everyone; a refusal (`unavailable`, `out_of_reach`, `blocked`) only the sender. A mode rule: its public
events reveal no role.
Status: designed in #33; built in 2e (#61); the belt in M4-5 (#141). Tests: `tests/unit/items/take_into_hand_test.gd`,
`tests/unit/items/in_sight_test.gd` (`InSight` refuses an item that is not there),
`tests/unit/content/item_intents_test.gd` (only the living may send it).

#### 9.5.11 PutDown (action)
What it does: puts the hand item down in front of the player (§7.1.12); a belt item stays (`empty_hand` with only one).
Settings: a rule on the base mode: trigger `PutDown`; conditions `HoldsItem`; effects `PutDownInFront` (1 m).
Produces: `ItemPlaced` (put down); `item_rested`.
Visible to: everyone; a refusal (`empty_hand`) only the sender. A mode rule: its public events reveal no role.
Status: designed in #33; built in 2e (#61). Tests: `tests/unit/items/put_down_in_front_test.gd`; the drops at a
death or a leave: `tests/unit/items/items_test.gd`.

#### 9.5.12 Use (action; the knife's hit)
What it does: uses the hand item, as its kind's rule says, never the belt item; in the MVP only the knife has one (above). It replaces
#32's `Hit` intent, so that a new held item is data, not a new intent.
Settings, Produces, Visible to: the knife's. A downed or dead player's `Use` is `not_accepted` (Round accepts it
from the living only); an empty hand (a knife on the belt too), or a package, is `nothing_to_do`.
Status: designed in #33; built in 2g (#63), as the knife's. Tests: the knife's; a downed or dead player's `Use`:
`tests/unit/life/life_rules_test.gd`, `tests/unit/content/content_modes_test.gd` (the base mode),
`tests/unit/content/item_intents_test.gd` (only the living, in every mode); a package's: `tests/unit/items/items_test.gd`.

#### 9.5.13 Raise, StopRaise and GiveUp (actions; the revive)
What it does (vision revision 1, Revive and Give up; M4-4, #140): a living player raises a downed one by holding E
for the raise time, and the downed player stands up where it lay; a downed player may give up and die at once.
Settings (provisional, "not a decision"; the numbers are the raise rule's own, E27):
- `Raise` (the mode's action): `TargetDowned`, `ChannelFree`, `TargetInReach` 2 m (the pick-up's reach),
  `TargetInSight`, checked at the start and every tick; then `RaiseDowned` of 3 s with a revive health of 50.
- `StopRaise`: `Channeling`; applied, it stops the raise as every applied action of the raiser does (§9.2).
- `GiveUp`: no condition; `Die`.
- Round accepts `Raise` and `StopRaise` from the living, `GiveUp` from the downed (`not_accepted` otherwise).
Produces: `RaiseStarted`, `RaiseStopped` (no cause), `Revived`; a give-up's `Died` and the drop at the body.
Visible to: everyone (§4.2); a raise is as public as the two avatars. A raise stopped by a hit confirms that hit to
the attacker (the engineer's answer 7 on PR #133). Rejections: `not_downed`, `busy`, `out_of_reach`, `blocked`,
`not_channeling`, and `not_accepted` from the phase. The raiser may hold the package (answer 4).
Status: built in M4-4 (#140). Tests: `tests/unit/life/raise_test.gd`, `tests/unit/channel/channels_test.gd`,
`tests/unit/life/absent_target_test.gd` (`TargetInReach` and `TargetInSight` refuse a target that is not there);
the base mode's data in `tests/unit/content/content_modes_test.gd`; the scenarios
`crew_revives_the_downed` and `raise_stopped_then_given_up` (§9.7).

#### 9.5.14 Swap (action)
What it does (vision revision 1, Two hands; M4-5, #141): exchanges the hand and belt items, either of which may be
empty, so a lone one-handed item moves between the hand and the belt (the ADR's controls: X).
Settings: a rule on the base mode: trigger `Swap`; conditions `CarriesItem`, `HandNotTwoHanded`; effects `SwapHands`.
Round accepts it from the living only: the downed and the dead get `not_accepted`.
Produces: `Swapped`; it stops the swapper's raise (`RaiseStopped`), as every applied action does (§9.2).
Visible to: everyone; a refusal (`nothing_to_swap`, `two_handed`) only the sender. A mode rule: its public events
reveal no role.
Status: built in M4-5 (#141). Tests: `tests/unit/items/swap_hands_test.gd` (the swap, its refusals, the downed and
the dead, a swap stopping a raise, only the hand item used); `tests/unit/channel/channels_test.gd` (a swap refused
by `HandNotTwoHanded` stops no channel); `tests/unit/content/item_intents_test.gd` (the base
mode's rule, only the living); the scenarios `refusals` and `two_handed_pickup_with_a_full_belt` (§9.7).

#### 9.5.15 Sprint (not a part in v0)
What it does: the `sprint` flag of `MoveClaim` and its per-tick mask `sprint_ticks` (#155), settled by the movement
rule for every tick a claim covers (§7.1), with the numbers in `PlayerRules`: 7 m/s, 20 per second, from 20. A tick
costs only when the claim's `moving` flag and `moved_ticks` say the player gave movement input and it moved
horizontally. The downed never sprint: they crawl at 1 m/s (§7.1.7
The crawl, M4-2).
Why not a part: a rule fires once per trigger, while sprint cost and speed apply to every covered tick of a
continuous claim. A mechanic that changes movement (a faster role, a slowing item) needs a movement modifier that the
movement rule reads: a new kind, v1 (§10).
Visible to: the player's own stamina in `SelfStatus`; speed is public through positions.
Status: designed in #33; built in 2d (#60): `MovementRule` and `StaminaLedger`; per-tick masks in #155. Tests:
`tests/unit/movement/movement_rule_test.gd`, `tests/unit/movement/movement_rule_masks_test.gd`,
`tests/unit/stamina/stamina_ledger_test.gd`.

#### 9.5.16 Jump (not a part in v0)
What it does: the `jumps` count of `MoveClaim` (3e; `jumped` until then), accepted as in §7.1.4 with the numbers in
`PlayerRules`: 1 m for 10 per jump.
The downed never jump: a new jump of theirs is corrected (§7.1.7 The crawl, M4-2).
Why not a part: as for sprint.
Visible to: as for sprint.
Status: designed in #33; built in 2d (#60): `MovementRule`. Tests: `tests/unit/movement/movement_rule_jump_test.gd`.

#### 9.5.17 Zone task (task type)
What it does: one shared task of `zones` zones (#36); a zone is done once living players have stood in it for
`seconds` in all, and a subtask is a zone. Nobody owns the task: any living player of any role works any zone. The
second task type, beside Delivery (§9.5.4). In the base mode (#649): `content/tasks/hold_the_zone.tres`, id
`hold_the_zone`, "Hold the zone" (the players' word; the Ukrainian UI's «Утримати зону» once the client is
translated), described "Stand in the zone until it fills."
Settings: `zone` (a `StationKind`: spawn tag, radius, height, palette), `subtasks_setting` (a whole-number setting of
the mode), `seconds` (0.05 to 600, `ChannelEffect.seconds`' bounds; the neutral default 0 is refused, so the data
must set it; data, not a lobby setting, ZD7), `zones_rng` (`zones`). The engineer's provisional values (#302
comment 6085251071), in the base mode's data since #649: 10 s (200 ticks), a `zone` station kind of radius 1.5 m and
height 2.5 m (a jump of 1 m plus the host's slack stays inside) with one yellow colour, spawn tag `zone`, one zone
per subtask; the base mode's `zones` setting is 1 (1 to 1, §9.5.1). The greybox's four `zone` markers along z = 7 are
placeholders, "not a decision" (§9.6); House's are #651's.
- Deal: N zones, N the setting, whatever the player count, on distinct random `zone.spawn_tag` markers, each in a
  distinct random palette colour (both from `zones`); station ids follow spawn-point order and zone *i* is subtask *i*.
  `StationPlaced` in id order. A map short of markers or a palette short of colours deals nothing and logs a match
  error, as Delivery's deal; the fit check refuses such a lobby first. N = 0: a task with no subtasks, done.
- Demands: N `zone` markers and N palette colours.
- Tick (`TaskTicks`, Round in the base mode; `ModeCheck` refuses a ticking task type that no phase lists it in): for
  each undone zone in station-id order, it counts when a player, in peer-id order, is living (life ALIVE, any role,
  ZD3), stands in its cylinder (`StationState.contains` with the feet of its last accepted claim) and that claim is at
  most 10 host ticks old with at most 10 ticks of credit stored since (`MovementRule.claim_age` and `credit_gain`
  at most `PUSH_TICKS`, ZE10, §7.1.5). A counting zone gains one
  tick, however many stand in it (ZD4); leaving pauses it and it keeps its ticks (ZD2). At `seconds` converted once
  (`Ticks.from_seconds`, at least 1 tick) it is done: `ZoneProgress` first, then `Tasks.subtask_done` (ZE5).
  Nothing else stops or resets it (ZD9): carrying, using, swapping, a raise, a hit that does not knock down. A
  knockdown stops it in its own tick (the hit and `LifeTicks` run before `TaskTicks`); a respawn inside counts from
  its first claim after the respawn (the placement's epoch).
- Mode checks (ZE3, `ModeCheck`): two station kinds of the mode's task types with one id or one spawn tag, or one kind
  held by two task types, are refused (stations take markers without asking whether one stands there).

Produces: `StationPlaced` (everyone) in the deal; `ZoneProgress` (everyone, §4.2) when a zone's counting changed
since its last one, at most once per zone per `ZoneTask.WINDOW_TICKS` (5, "not a decision"; a change inside the
window goes out at its end with that tick's state, even when counting is back where it was), and on a done zone, in
its own tick, before its task's `TaskState` and `TaskProgress`; `subtask_done` (detail: the subtask's index and its
station). Its task state (`ZoneTask.State`): per subtask its station, its ticks, whether it counts, whether it is
done, and its last `ZoneProgress` tick with whether its counting changed since. The state lives in `MatchState`
(the phase object dies with Round), so Round's end stops the count and `ResetMatch` clears it.
Visible to: everyone, all of it, as Delivery. `ZoneProgress` names no player, and counting reads no role: a public
event that depended on a role would reveal it (§9.2, ZD3).
Status: designed in #36 ([zone task ADR](decisions/2026-10-09-m7-zone-task.md), PR #619); `core/` built in #647
(M7-Z1): `core/tasks/zone_task.gd`, `core/events/zone_progress_event.gd`, `StationState.contains`,
`MovementRule.claim_age` and `credit_gain`; its data, the greybox's zones and three scenarios in #649 (M7-Z3,
provisional for the engineer's approval); the client's zones, their fill and the done look in #650 (M7-Z4, §4.7.24).
Tests: `tests/unit/content/zone_content_test.gd` (the provisional values, the fit at the most zones, ZE9's spacing on
every map of the base mode), the scenarios `crew_works_every_zone`, `zone_paused_by_a_knockdown` and
`dissident_works_a_zone_alone` (§9.7), `tests/unit/tasks/zone_deal_test.gd`
(the deal, the demands, the check), `zone_rules_test.gd` (every row of the ADR's interruption table, the freeze row
and a slow claimer's, the clock's
last tick, `ResetMatch`), `zone_progress_events_test.gd` (the window, 100 edge crossings, ZE5's order, the wire round
trip), `zone_role_swap_test.gd` (two roles swapped emit the same task events; planted "counts the crew only", it
failed, reverted), `tests/unit/match/station_state_test.gd`, `tests/unit/movement/movement_rule_claim_age_test.gd`,
`tests/unit/content/mode_check_stations_test.gd`; fixtures `tests/fixtures/tasks/fixture_zone_modes.gd`.

### 9.6 Where the MVP's data and scenes live (provisional)
```
content/
  modes/base_mode.tres             the base mode: phases, rows, PickUp, PutDown and voice rules inside it
  roles/crew.tres, roles/dissident.tres
  items/package.tres, items/knife.tres        the knife's Use rule inside it
  tasks/delivery.tres              with its circle station inside it
  tasks/hold_the_zone.tres         the zone task, with its zone station inside it (#649)
  win_conditions/every_task_done.tres, no_crew_present.tres, time_up.tres
  scenarios/                       bot scenarios (§9.7), one per file
levels/
  lobby/lobby.tscn                 the lobby: floor, walls, lobby_player markers
  greybox/greybox.tscn             the MVP map: rooms and round_player, package, knife, circle, respawn and zone markers
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
  4 `knife` markers along z = −5: every tag for 10 players at the default settings and at the most packages. M4-3
  (#139) adds 4 `respawn` markers at (±14, 0, ±5), each with 1 m free (placeholders, under the MVP content ADR, for
  the engineer's approval; L-1 keeps or replaces them), which the layout check demands from M4-3 on. #649 adds 4
  `zone` markers at (−9, 0, 7), (−3, 0, 7), (3, 0, 7) and (9, 0, 7) (placeholders, "not a decision", ZD10 (a)),
  which keep ZE9's distances. The content test checks that fit and that both levels are flat, which the scenarios'
  fake world assumes; `zone_content_test.gd` the fit at the most zones and ZE9's spacing.
- A kind that other modes can reuse (a role, an item kind, a task type, a win condition) gets its own file; a rule,
  a phase spec, a row or a station is a sub-resource of its owner.
- **Markers.** A spawn point is a `Marker3D` in the level scene, in the persistent group `spawn_<tag>` of its one tag
  (the editor's Groups dock: `spawn_package`); a marker in two such groups is a load error. Packages and knives share
  spawn points when their item kinds name the same tag (say `item`), which is content data; a deal puts at most one
  item on a marker. A `circle` marker sits exactly on the floor a package rests on: its circle's cylinder starts at
  the marker's height, so a marker even a little above the floor leaves packages below the cylinder (§7.1.14); a
  `package` marker also sits on the floor.
  One tag per marker keeps the `all_ready` fit check exact: the demands per tag are summed and
  compared with that tag's markers, and a deal that passed it always finds its markers. `server/` reads the markers in
  scene-tree order, the level order of §3.3 (`MarkerReader`, 2j): each where the scene puts it, through its
  `Node3D` parents; a marker in two `spawn_` groups, a `spawn_` group on a node that is not a `Marker3D` and a
  group named `spawn_` alone are load errors. The markers of the station kinds' spawn tags (`circle`, `zone`) are snapped
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
    client); the match settings that differ from the defaults, numbers (`settings`) and sets of task type ids (`id_sets`: the host's bans, #79; M7-Z2), which `problems()` checks as the lobby would: a set the mode does not declare, an id that is none of its task types, and bans that leave fewer types than `tasks` are refused, so a ban of one of two types also lowers `tasks` in the same setup (`DealTasks.settings_problem`); roles forced per bot (debug builds only, invariant 8;
    otherwise the deal draws them from the seed); the match clock's length in seconds, forced with the debug command
    `ForceClock` in place of `match_duration`'s whole minutes (`clock_s`, M4-3; 0 keeps the setting). By default every
    bot joins (sends `Hello`) at the start and acknowledges every `LoadMatch` at once; the steps `Join` and `LoadAck`
    change that for one bot;
  - one script per bot, whose steps run in order; the bots run at the same time;
  - the expected ends, one per match the scenario plays, in order: a winning side, or `none`. `none` passes when every
    script has finished within the time limit and no further `MatchEnded` arrived. Steps may follow an end, so a
    scenario can go back to the lobby and play a second match (seed *k*+1, §3.3). A time limit for the whole run;
  - `never`: events that one bot, or every bot, must never receive;
  - `voice` (M5-1, #215): how the bots' synthetic voice talks, in talk spurts (the default, a pattern per bot) or
    continuously (§4.6.2); every bot talks from its join until a `Talk` step silences it;
  - `measurement` (M5-4, #218): a load measurement, which the bots runner plays only when it is named, never in its
    run of every scenario (`verify`'s `bots`), whose time it would multiply; the core runner's suite still plays it.
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
| `Raise(target, hold_s)` | sends `Raise` of the player of a `bot(i)` target and holds E (M4-4) | its `RaiseStarted` arrived and `hold_s` passed since the step started, or the raise ended before (its `RaiseStopped`, or a `Revived` of the target); the bot still holds E after it |
| `StopRaise` | sends `StopRaise`: lets go of E (M4-4) | its `RaiseStopped` arrives (`not_channeling` when no raise runs) |
| `GiveUp` | the downed bot sends `GiveUp` (M4-4) | its own `Died` arrives |
| `Swap` | sends `Swap`: exchanges its hand and belt items (M4-5) | its own `Swapped` arrives (`nothing_to_swap`, `two_handed` when refused) |
| `Talk(talking)` | turns its synthetic voice off, or on again (M5-4); the core runner has no voice and only records it | at once |

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
  last `SelfStatus` says sprint is available in the core runner, and over the network while the bot's own
  `PredictedStamina`, settled by its claims, says so (#155; a downed bot never: it crawls), and stops exactly
  `stop_m` short. A dead bot claims nothing at all, standing or walking (M4-2).
  `Jump` claims a jump where the bot stands, on the floor: the bot's jump count in its epoch plus one (3e; D3 (a),
  the designer's answer on #96: the step names what a player does, not the count the wire carries). The setup's forced roles go in one `ForceRole` per bot
  right after the joins at the start, and its settings and sets in one `ChangeSettings` from bot 1 after them (`BotScenario.setup_change()`, in both runners).
- `fields` match a subset of the event's payload, as the bot received it (name and fields): text as text, numbers
  and vectors approximately, and `peer` (and the raise events' `raiser` and `target`, M4-4) holds a bot's number, mapped through the runner's `ScenarioPeers`; an event
  for one peer whose payload names none (`SelfStatus`) matches `peer` as the bot that received it (3h). `never` names an event, fields and a
  bot (0: every bot).

- **Targets come from the bot's own view**, the events and snapshots its client received: `package(n)` (the n-th
  package in item-id order, from 1; tasks are shared, #79), `circle_of_held` (of its hand item), `nearest(kind)` (on
  the ground: not in a hand or on a belt, which the bot follows from `ItemPickedUp`'s `belted` and `Swapped`, M4-5), `bot(i)` (where it last saw
  that player), `point(x, y, z)`, `station(kind, n)` (the n-th station, from 1, of that `StationKind` id in station-id order, from the bot's own `StationPlaced`s; a `WalkTo` to it takes `stop_m` 0, and the runners' arrival slack of 1 mm ends the walk: M7-Z2, ZE7 (a), for the zone task, whose zone the bot finds only this way). A target the bot cannot know fails the scenario, so a scenario also proves that the
  mechanic is playable with what a player is told.
- **Failures:** a step that sends an intent fails on a `Rejected` it did not expect and names the reason; a step that
  does not finish within the time limit fails; a `Correction` outside a placement (§3.2), the bot's own knockdown
  (M4-2) or its own respawn (M4-3) fails (a revive sends none, M4-4), because an honest bot is never corrected, so
  every scenario also checks the
  host's movement rules against honest movement. A field that
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
    `DisconnectPeer`, after which the bot is gone and its `PeerLeft` follows on the next tick. A bot that stands still
    claims where it stands every tick, as every `ClientSession` does, so the host settles its stamina as it stands
    (M4-3). Until `server/`'s
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
    of the runner's stand-in for `server/` (§4.6). The same files; it joins `verify` with the leak test (§5). Each bot sees only its `ClientSession`'s decoded view (§4.6.1).
    Built in 3h (#102): `tests/harness/bots/`, `tools\run.cmd bots`, tested by `tests/scenarios/bots_runner_test.gd`.
  - *Perf* (#187): `tests/harness/perf/` plays a seeded 10-bot match through `HostSession` and meters it from the
    harness side for `tools\run.cmd perf`, not a `verify` step (`docs/AGENT_WORKFLOW.md` §11.10). Its match
    (`PerfScenario`) keeps the default draw, both task types since #649: with 10 bots each of the greybox's four
    zone markers lies on one of spokes 1 to 4 (within 0.7 m), so whichever zone is dealt, one spoke crosses it and the
    run meters `ZoneProgress` too.
- **Reproducing a failure:** the runner prints the bot, the step, that bot's last events and the seed; the command log
  replays the match (§3.3).
- **The MVP's scenarios** (2j, #66; provisional under the MVP content ADR, for the engineer's approval), in
  `content/scenarios/`: `crew_delivers_every_package` (3 crew deliver the 6 packages; a delivered package's
  `PickUp` is `unavailable`; the crew never get `Teammates`), `dissident_kills_the_crew` (rewritten in M4-2: a
  forced dissident takes a knife and knocks both crew down; `too_soon`; a downed bot is not hit again, its `PickUp` is
  `not_accepted`, and it crawls; both die at the end of their knockdown and a dead bot's `PickUp` is `not_accepted`;
  the match ends by time up, every crew member dead but present, on a 40 s clock (`clock_s`, M4-3); the `bots-enet`
  step, and over WebRTC `bots-webrtc`, §4.6.7), `crew_respawns_invulnerable` (M4-3: a crew bot is knocked down, dies and respawns 30 s later at a
  `respawn` marker; the dissident sprints to it and swings within its 3 s of invulnerability, which brings no
  `Damaged`, then swings again after them, which does; the match ends by time up on a 55 s clock),
  `crew_revives_the_downed` (M4-4: a dissident knocks a crew bot down and another crew bot raises it for 3 s; it
  stands with 50 health; nobody dies and no raise stops; time up on a 30 s clock; also run once over ENet,
  `tools/run.sh bots crew_revives_the_downed --instances 3`, not a `verify` step), `raise_stopped_then_given_up`
  (M4-4: a raise let go after 1 s, a second raise, the downed bot gives up during it (`RaiseStopped`, `Died`), a late
  `StopRaise` gets `not_channeling`, and the bot respawns 30 s later; time up on a 55 s clock),
  `dissidents_win_by_the_clock` (a 1-minute match that runs out; a jump, a sprint that runs out of stamina),
  `late_join_cancels_the_countdown`, `dropped_at_the_loading_deadline` and `refusals` (`nothing_to_swap`,
  `empty_hand`, `nothing_to_do`, `out_of_reach`, `too_soon`, `tired`; since M4-5 its knife goes to the belt when it
  picks up the package, a `Swap` is then `two_handed`, and after the package is put down a `Swap` draws the knife).
  M4-5 (#141): `crew_downed_before_a_delivery` (a dissident knocks a crew bot down, then another crew bot delivers the
  only package: the scenario the leak test needs to see a misdeclared `TaskState`, §4.6.4.1),
  `two_handed_pickup_with_a_full_belt` (a knife to the belt, a second in the hand, then the package: the hand knife
  rests where the package lay, and a `Swap` is `two_handed`), `dissident_hides_a_package` (a dissident carries the
  package to a corner and puts it down; a crew bot finds it with `nearest(package)` and delivers it) and
  `crew_walks_after_a_respawn` (`crew_respawns_invulnerable`'s match, where the respawned bot walks at once: the
  network runner's travel after a respawn). The first
  three, `crew_respawns_invulnerable` and M4-4's two expect the ends `crew`, `dissidents`, `dissidents`, `dissidents`,
  `dissidents` and `dissidents` (2h's win conditions), M4-5's `crew`, `none`, `crew` and `dissidents`; the other three
  `none`. None of M4-5's runs in `bots-enet`.
  M5-1 (#215): `voice_beyond_the_radius` (in the round bot 1 walks about 5 m from the middle towards -z and bot 2
  about 5 m towards +z, both talking for 5 s some 10 m apart, so neither decodes the other; then bot 2 walks to
  about 6 m from bot 1 and both decode for 5 s; the scenario the distance invariant's plant needs, §4.6.4.1), which
  expects `none`; not a `bots-enet` step (`--instances 2` passed once, 2026-10-03).
  M5-4 (#218): `voice_load`, a `measurement` (8 bots walk to a circle of 3 m in the lobby, all within its 8 m, talk
  continuously for 30 s, then all but bots 2 and 3 fall silent with a `Talk` step for 30 s; expects `none`): run
  with `tools\run.cmd bots voice_load --instances 8`, about 70 s, not a `verify` step (§6.5.8 The wire has its
  numbers); in one process it took 84 s.
  M7-Z3 (#649; the zone task ADR's §7): every scenario above bans the zone task with `tasks` 1 in its setup's one
  `ChangeSettings` (ZE7), so it deals Delivery alone. Three play the zone, each expecting `crew`:
  `crew_works_every_zone` (the default draw with one package: a crew bot delivers it, another walks to `station(zone,
  1)` and holds it until its `ZoneProgress` at 200 ticks, and the crew wins on the second subtask),
  `zone_paused_by_a_knockdown` (Delivery banned: the crew bot holds the zone from 1.2 m short of its centre, on its
  approach side; the dissident strikes it from 1 m further out, outside the zone and inside the knife's reach, and
  knocks it down; both crew bots expect `ZoneProgress` with `counting` false within 0.5 s of the `KnockedDown`, and
  the downed one no `counting` true for 3 s, while the dissident still stands outside, so only the knockdown can stop
  it (a plant that let the downed count failed the scenario); a crew bot raises it from 1.8 m, outside the zone and
  inside the raise's 2 m reach; the zone counts again from its `Revived` and fills; nobody dies) and `dissident_works_a_zone_alone` (Delivery banned:
  a dissident alone in the zone fills it, ZD3, and the crew wins). All three run in `bots`, the leak test.

### 9.8 The extensibility test
Each later mechanic, on paper, against v0. The test counts classes in `core/`; the last paragraph says what each
costs outside it.

| Mechanic | Data | New part classes | New event classes | What else changes, and why |
|---|---|---|---|---|
| Zone task (#36): stand in a zone for N seconds (designed in the [zone task ADR](decisions/2026-10-09-m7-zone-task.md); the engineer took every recommendation on #302; `core/` built in #647, M7-Z1, §9.5.17; the client's look in #650, M7-Z4, §4.7.24; its data waits for M7-Z3) | a task type `.tres` (its time, a zone station kind, its own subtasks setting; the numbers and names are the engineer's, ZD7), markers of the zone's spawn tag in the map, the mode's task types (ZD8) | one task type (one script, §9.3), `ZoneTask`: its deal places one zone per subtask, as Delivery places its circles; its tick (through `TaskTicks`) adds one tick, kept in its task state, to each undone zone with a living player inside whose last claim is at most 10 ticks old (any role; several count as one; leaving pauses: the ADR's recommendations) and completes the subtask at its time. The cylinder test moves from Delivery to `StationState` so both share it | one, `ZoneProgress` (everyone): a zone's time, whether it counts and whether it is done, sent only on a change; a client draws the fill between changes. `StationPlaced`, `TaskState` and `TaskProgress` are generic | none in `Match` or the loop: `DealTasks` draws among the mode's task types (#79). Two mode checks (one spawn tag per station kind; a ticking task type needs `TaskTicks`). Outside `core/`: its wire row and a protocol bump, a bot target `STATION` (a station kind's n-th station) and bans in a scenario's setup, so the MVP's scenarios keep dealing Delivery alone |
| Revive (vision revision 1; built in M4-4, #140), as a timed action on a player | the mode's `Raise` rule: `TargetDowned`, `ChannelFree`, `TargetInReach` (2 m), `TargetInSight`; `RaiseDowned` (3 s, 50 health); `StopRaise` (`Channeling`) and `GiveUp` (`Die`); `ChannelTicks` in Round | as built: the channel primitive (`ChannelEffect`, `ChannelTicks`, `ChannelFree`, `Channeling`, with `Channel` and `Channels` as its state), three conditions on a target player and two effects (`RaiseDowned`, `Die`). The primitive is the reusable part: a timed action is one `ChannelEffect` subclass plus the conditions it is held under, which are checked every tick (a #34 medic's resurrection at a body; #36's zone task only if the engineer picks ZD1 (b), a key held in the zone: the [zone task ADR](decisions/2026-10-09-m7-zone-task.md) recommends ZD1 (a), its time counting presence, which is no action) | `RaiseStarted`, `RaiseStopped`, `Revived` (everyone: both avatars are public) | three intents, `Raise(target)`, `StopRaise()` and `GiveUp()` (E28), with their rows in §4.1; the first intent that targets a player rather than an item. Two lines outside the parts: `RuleRunner` stops an actor's channel when another of its actions applies (§9.2), and `MovementRule` holds a raised player in place (§7.1.8). A #34 resurrection of the dead at their body would add a body target (`BodyInFront`: a body within reach and in sight, else `no_body`, which reveals nothing, bodies being public) and a `ChannelEffect` that brings the dead player back at the body (`LifeRules` gains that move, with its `Correction`, as `respawn` has); if only some roles may, `ActorRole`; a use limit, `Uses` (a cost over the counters table). Which `Use` wins when a medic holds a knife is #38's (§9.2) |
| Meetings mode (#35) | a new mode `.tres` that reuses the base mode's roles, items, Delivery and win conditions, with the phases Meeting, Vote and Resolution, rows such as `Round, meeting_called → Meeting`, `Resolution, resume → Round` and `Resolution, won → End`, a clock stopped by the phase spec and a meeting voice rule | several, because a meeting is a system, not one mechanic: `Interact` (below) for a button and a body report, whose rules report `meeting_called` with `ReportOutcome`; `CastVote`'s effect; a tally as a transition action, fed by the Vote phase object's votes through the outcome's argument (§9.1); a meeting-wide voice rule; the phase classes Meeting, Vote and Resolution (fewer if one timed phase class serves several) | the vote events, each with its audience (a cast vote hidden until the reveal; the reveal; the result) | a new intent, `CastVote(target)`, with its row in §4.1. `PlacePlayers` gains a `who` setting (everyone, or only the living) to seat players for a meeting. Nothing in `Match` or the base mode: phases, rows, outcomes, the clock and the voice rule per phase are data (§3.1) |
| Physics throwing (#37; designed in its [ADR](decisions/2026-10-09-throwing-held-items.md), its answers given on #302, §7.1.16; the flying state, the arc and `FlightTicks` built in #642) | a `Throw` rule on the mode, for any held item (or one per item kind: the engineer's TD2); its numbers are the engineer's (TD1) | two: the `ThrowItem` effect, which takes the item out of the hand into a *flying* state, and the `FlightTicks` tick system, which sweeps the arc each tick and lays the item down at its first contact | a public `ItemThrown` | a new intent, `Throw(facing)` (a new verb for every item, unlike `Use`), with its row in §4.1; the flying state in `MatchState`; one `WorldQuery` question, `sweep`; the cause `thrown`, whose `item_rested` lets delivery work unchanged. The design first sketched here had `server/` simulate the flight and report `ItemRested`; #37 proposes the flight in `core/` instead (TE1, the engineer's), so the clients draw the arc from `ItemThrown` until `ItemPlaced` and `server/` adds no command. Damage on impact would need an impact fact, `item_struck`; #37 recommends none for now (TD3) |

**`Interact(target)`** (v1, with the first mechanic that needs it, #34 or #35): one intent that names a thing in the
world by id, and owners for fixed interactables (a marker kind in `levels/`, such as a meeting button) and for
bodies. It changes the intent catalogue (§4.1) and the owners once; after it, a new interactable is data plus at
most one effect.

**Verdict.** Inside `core/`: the zone task passes, with one class and one event class, as #36's design has it (live
progress and a public "zone done" share `ZoneProgress`), and as built in #647; with ZD1 (a), the engineer's answer,
its time runs in its task state, not on the channel primitive (§9.3), since standing is no action. Delivery's
cylinder test moved to `StationState` unchanged, so both types share one. Beyond the paper test it needed two
helpers outside the parts: `MovementRule.claim_age` and `credit_gain` (§7.1.5), so a stale claim, or credit stored
while standing, stops counting (ZE10). The revive, as built in M4-4, did not pass the letter of the test: a player is a new kind of
target, a timed action needed a new
primitive (the channel) and the raise three public events and three intents. With them in place, a resurrection at
a body (#34) is two or three part classes and one event class: a body is again a new kind of target, and a
resurrection a new public fact. The meetings mode is several parts, as a system. Throwing and
`Interact` each change the engine once, for the reasons given. None of them changes `Match` or the phase loop; the
change to an existing part is a new setting (`PlacePlayers`' `who`). The revive changed two existing rules once,
for every later timed action: `RuleRunner` stops the actor's channel when another of its actions applies, and the
movement rule holds a raised player in place.
Outside `core/`, every new event class and intent also costs a wire schema row (M3, §4) and its presentation on the
client (M4). That is the price of any mechanic that shows something new, not a gap in the content API.

## 10. Open questions

| Question | When |
|---|---|
| Content API v1: the designer's review of v0 (§9) | #38, before M7 |
| `Interact(target)`: fixed interactables and bodies as targets (§9.8) | with the first mechanic that needs it |
| The zone task's numbers, names and maps (ZD7, ZD10 of the [zone task ADR](decisions/2026-10-09-m7-zone-task.md), §9.8) | the engineer answered ZD1 to ZD6 and ZD8 to ZD11 on #302 and gave ZD7's provisional numbers there; M7-Z1 is built (#647), the data and the maps are M7-Z3 and M7-Z5 |
| Movement modifiers, which would make sprint and jump parts (§9.5) | when a mechanic changes movement |
| Which `Use` rule wins when the held item and the actor's role both have one; v0: the item (§9.2) | #38, before a role has a `Use` ability (#34) |
| How levels mark spawn points: groups on `Marker3D` or an engine marker scene (§9.6); and give collision the host can read (`StaticBody3D`, not CSG or `GridMap`, with E8 (a): §4.5) | 4e, with the designer |
| How `MarkerReader` finds the floor under a `circle` marker in M3: `read_levels` reads every level of the mode before `Match.new`, from a copy outside any physics space, so the host's `WorldQuery` (§7.1, one space holding the loaded level) cannot answer it; either the reader computes the floor from the scene's own static colliders, or it reads each level once it is in the host's space (§9.6). #89 proposes the second: the host builds every level's world first and `read_levels` points the host's `WorldQuery` at each level (§4.5 Starting) | Settled: the second, built in 3c (#99, §4.5) |
| Lag compensation for hits (§7.1.10) | after the MVP playtest |
| Throwing held items (§7.1.16): the numbers only. The engineer answered TE1 and TD1 to TD12 of the [throwing ADR](decisions/2026-10-09-throwing-held-items.md) on #302 (every recommendation); the throw speed (10 m/s), the item's radius (0.15 m) and the longest flight (3 s) are provisional, for the first playtest | the engineer, at the playtest; 37a and 37b (#641, #642) are built, 37c to 37f follow |
| Hiding positions behind walls (§5; not wanted now) | only if a human asks |
| Returning players (#73): what identifies one, what a return restores, a return while a round runs, joining again from the menu, and where masks and ready-made parts go | Designed in #73 ([ADR](decisions/2026-10-09-returning-players-keep-their-number.md), proposed): a return key per settings file, the old number back in the lobby only, nothing else restored; P1, P3, P4, P9, P11, P12, P13 and the split wait for the engineer. Proposed: 73-A and 73-B in M7 after #550 and #551; a return into a running round only as its own design (73-D) |
| Wire format of the message layer: schemas, encoding, versioning, reliability | designed in #89 (§4.3 to §4.6, E1 to E17 for the engineer); built in M3 (3c to 3i) |
| The host's per-send ENet cost and upload for voice (ENet between two machines: settled by #21, §4) | Measured by M5-4 (#218, §6.5.8 The wire): 16.5 to 19 µs per send inside the transport (averaged over 56 sends, 7 of them the host's own client's loopback; ENet's alone about 19 to 22 µs) and 54 to 62 µs per relayed `VoiceDown` in all on one busy PC (upper bounds), about 5 ms per 20 ms at 81 streams, over E44's 2 ms; the upload about 3.8 Mbit/s at 10 players, under 4.5 and 5. #245 then encoded each frame's `VoiceDown` once with the seq patched per listener (no wire change, the manager's decision under #134): 23.5 to 26 µs per send, about 2.1 to 2.3 ms per 20 ms at 81 streams (upper bounds, not shown to be under 2 ms), about 60% of it the transport's send per datagram. M5-4b (the batched voice row, [M5 ADR](decisions/2026-10-02-m5-voice-integrated-with-the-rules.md) §4) is built in M6-8 (#374, protocol 8) after M6-6 measured WebRTC over E44 (D24 (a)): in the cloud container about 2.5 ms per 20 ms and 3.5 Mbit/s at 10 players (§6.5.8 The wire), the upload under 4.5 Mbit/s and the relay still over 2 ms as an upper bound. Open: the engineer's rerun on a quiet PC |
| Voice integration: capture, the gate (voice activity by default, push-to-talk or Off), the jitter buffer, playback and the ears, occlusion, the buses Voice, Effects and Music ([M5 ADR](decisions/2026-10-02-m5-voice-integrated-with-the-rules.md) E34 to E47 and D11 to D15, §6) | designed in #177, accepted on 2026-10-02 (PR #194); built in M5 (M5-1 to M5-7, #215 to #221) |
| Which of `client/` and `voice/` uses the other (§1; E46 of the M5 ADR) | Settled: (a), the engineer, 2026-10-02: `client/` uses `voice/`, `voice/` nothing outside itself; §1's rows say so |
| LFS in CI before the first audio asset outside `addons/` (the [LFS ADR](decisions/2026-09-29-git-lfs-for-binary-assets.md)'s open item; a stop-and-ask in the M5 ADR) | Settled: (a), the engineer, 2026-10-02: CI fetches LFS content, cached by the list of LFS files; added with the CC0 sounds of #144 and #145 (a follow-up: M5-7, #221, built the muffle before the files arrived) |
| Who is talking, shown in the world (D14 of the M5 ADR: no talking indicator in M5) | a mouth animation with the masks of #73, after the MVP |
| Radios, abilities and items that change voice; echo cancellation; lowering the device latency | M7+; echo cancellation only if playtests ask (players are advised headphones, the voice ADR) |
| Internet play without a VPN (NAT traversal): Steam networking vs WebRTC with a signaling server | M6 ADR |
| The M4 client's choices E18 to E33 and the designer's D4 to D10, the level conventions included ([ADR](decisions/2026-10-01-m4-first-person-client.md), §4.7) | Settled: every recommendation, E32 (b) and D10 (b) included (PR #136) |
