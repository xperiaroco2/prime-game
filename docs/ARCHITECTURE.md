# Architecture

| | |
|---|---|
| **Owner** | The engineer. The **content API** section is the contract between engine and content; since #518 the engineer owns both sides, and the optional designer reviews a change to it only when he wants to. |
| **Status** | The code as built. The boundaries below are locked ([KICKOFF §3](history/KICKOFF.md); stack: [ADR](decisions/2026-09-29-technical-stack-from-the-brief.md)). Everything marked *open* is designed before M2 (core and content API) or in the milestone named. The match loop, intents, events and entitlement (§3, §4.1, §4.2, §5, §7.1): M2 design, #32. The content API v0 and bot scenarios (§9): M2 design, #33. The wire schemas, the codec, the host session and the M3 client and bots (§4.3 to §4.6): M3 design, #89, accepted ([ADR](decisions/2026-09-30-wire-format-and-host-session.md)). Vision revision 1 ([ADR](decisions/2026-10-01-vision-revision-1.md), #126) replaces ghosts, the one hand slot, `no_crew_alive` and the meetings mode: the M4 rework updated the sections that describe them (the ADR's Consequences list each section). The windowed client (§4.7) and the split of that rework into M4 issues: M4 design, #125, accepted ([ADR](decisions/2026-10-01-m4-first-person-client.md)). |
| **Rules for agents** | The invariants are repeated in the root `CLAUDE.md`, so they survive compaction. Area rules: `core/`, `server/`, `net/`, `client/`, `voice/` `CLAUDE.md`. |
| **A contract, not a changelog** | A finished task updates the text that its change makes stale, so each section says what is true now, and adds no "Built in #n" section. Its history (which PR built it, what changed when) goes in its ADR's Consequences, the PR and git log (#1244); a section's Tests paragraph is the test map and stays, kept current. §10 holds only the questions still open: a settled one leaves it. |

## 1. Layers and boundaries

| Folder | Contains | May use | Owner |
|---|---|---|---|
| `core/` | Pure rules: match state machine, intent validation rules (movement checks included), win conditions, who is entitled to each event and entity (§5), voice routing rules, content-API primitives. `RefCounted` only; no Nodes, scenes, networking or audio | nothing outside `core/` | engineer |
| `server/` | Host logic: wraps `core/`, checks the sender, format and rate of intents, builds one message per recipient from `core/`'s entitlement, answers `core/`'s geometric questions (`WorldQuery`, §7.1), simulates the knocked-down bodies on the maps `PlayerRules.motion_maps` lists (`HostBodies`, §7.1.18) | `core/`, the `net/` abstraction | engineer |
| `net/` | Transport abstraction (ENet first), message schemas, serialization, sync | nothing game-specific | engineer |
| `client/` | Scenes, player controller, UI, camera, audio playback, dev console | the filtered view it receives; `net/` to send intents; `core/`'s content definitions and constants (its own copy of the mode: which maps exist, which phase accepts which intent), never `core/` state (`Match`, `MatchState`, `view_of`; [ADR](decisions/2026-09-30-wire-format-and-host-session.md), review answers); `voice/`'s plumbing (E46 (a), [M5 ADR](decisions/2026-10-02-m5-voice-integrated-with-the-rules.md)); `assets/`'s scenes, textures and sounds by path (§11) | engineer |
| `voice/` | Capture, Opus encode and decode, jitter buffer, playback plumbing | nothing outside `voice/` but the engine and the TwoVoIP addon by class name (E46 (a)): no `client/`, `net/` or `core/` state, no `ClientSession` or `ClientModel`; `client/` decides what is played | engineer |
| `content/` | Game modes, roles, abilities, items, sabotages, task types and win conditions as `Resource`s built from content-API parts (§9); bot scenarios (§9.7), how-to cards (§4.7.36) and the tutorial's lessons (`content/tutorial/`, §4.7.46; E64), whose data classes are part of the content API | the content API only | engineer (#518) |
| `levels/` | Maps from reusable room, prop, interactable and task-station sub-scenes | the content API; `assets/`'s scenes, textures and sounds by path (§11) | engineer (#518) |
| `assets/` | Art from the art repo or a third-party pack: GLBs, images, sounds and fonts through Git LFS, with their `.import` files; no scripts (§11) | nothing: scenes in `client/` and `levels/` instance them | engineer |
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
- **Base mode:** Lobby → Countdown → Loading → Pregame → Round → End → Lobby. Roles are dealt and packages
  scattered on the way into Pregame, the silent seconds that show each player its role (§3.6); the clock starts on
  the way into Round.
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
  (§9.2), the rule's costs were paid and its effects ran. The kills a step queues (`LifeRules.kill_later`, #806)
  land before its win check, once the command's dispatch, the phase's own timers, each tick system, the clock ending
  or a phase's entry has finished,
  and never once the step has an outcome (§9.3 "Life").
- A mode with more phases (the parked deathmatch, say) is then data plus its phase classes, with rows out of Round
  and back. The deal runs only on `Loading, all_loaded → Pregame`, so returning to Round deals nothing, and a phase
  whose clock does not run pauses the match clock by its phase flag. `Match` does not change.
- **Life states** (vision revision 1): `PlayerState.Life` is ALIVE, DOWNED,
  DEAD and LEFT, and `is_alive()` means ALIVE only. 0 health knocks a living player down for the knockdown time
  (`LifeRules.knock_down`); when it runs out the player dies (`LifeTicks`, §9.4), and the respawn time later it
  respawns at a `respawn` marker, invulnerable for a while (M4-3, #139); a player who leaves mid-round is left (§3.5).
  `PlayerState.life_deadline` is the host tick at which the current life state runs out (the knockdown's end; the
  respawn's). `AcceptSpec.From` names a newcomer (1), any player (2), the living (4), the host (16) and the
  downed (32). Bit 8 was the ghosts' and is never reused; a mode still written for ghosts would silently refuse the
  downed's claims, so the mode check refuses a sender bit that names nobody. The dead send no intents as players:
  `Match` accepts none from them under PLAYER, LIVING or DOWNED (M4-2), so an intent in flight at a death reaches no
  rule. HOST still accepts the host's own player dead for the session's controls (`ReturnToLobby`, the shortcut out of End,
  where whoever died in the round is dead until `ResetMatch`), never for a player's action (`MoveClaim`, `PickUp`,
  `PutDown`, `Use`, `Throw`, `Interact` and the rest of `Intents.PLAYER_ACTIONS`). A flag for the dead is added only when a mode needs one.

### 3.2 Base mode: phases and transitions
A **player** is a peer whose `Hello` was accepted; *everyone* in an audience means every player (§5). A connected
peer without an accepted `Hello` is in no rule, receives nothing but a `Rejected`, and `server/` drops it after the
hello deadline.

| Phase | On enter | Accepts (§4.1) | Voice (§6) | Clock |
|---|---|---|---|---|
| Lobby | joins allowed | `Hello`, `MoveClaim`, `SetReady`, `ChangeSettings` (host), `SetProfile` (#551); leave | proximity | stopped |
| Countdown | its end tick: now + 5 s | `Hello`, `MoveClaim`, `SetReady(false)`; leave | proximity | stopped |
| Loading | the roster is frozen; joins refused; `LoadMatch`; the loading deadline | `LoadAck`; leave | nobody | stopped |
| Pregame (§3.6) | the deal has run; its end tick: now + 3 s; frozen: no movement, no snapshots, no win check | nothing (a `MoveClaim` is dropped); leave | nobody | stopped |
| Round | the deal has run (below); `LifeTicks` lets the downed die at the end of their knockdown and the dead respawn; `ChannelTicks` runs the raises (M4-4); `FlightTicks` flies the thrown items (#646) | living: `MoveClaim`, `PickUp`, `PutDown`, `Use`, `Raise`, `StopRaise`, `Swap` (M4-5), `Throw` (#646); downed: `MoveClaim` (its look only, §7.1.7), `GiveUp`; dead: nothing; leave | round rule | runs |
| End | frozen: no movement, no snapshots; its end tick: now + 3 s (#212) | `ReturnToLobby` (host; a shortcut no screen offers); leave | nobody | stopped |

| From | Outcome: its trigger | To | Actions |
|---|---|---|---|
| (start) | the host creates the session | Lobby | |
| Lobby | `all_ready`: every player is ready, and the settings fit the map for the current player count (packages, circles, knives and players within the map's spawn points, the demands per spawn tag of §9.4, for any draw of the task types; circles within the palette's colours; 1 to 10 players) | Countdown | |
| Countdown | `cancelled`: a `SetReady(false)`, a join or a leave | Lobby | none: ready flags and positions stay, so after a leave `all_ready` fires on entry and restarts the 5 s |
| Countdown | `countdown_done`: the end tick is reached | Loading | |
| Loading | `all_loaded`: every player of the frozen roster confirmed. A leave, or a client's missing `LoadAck` at the loading deadline, drops that player from the roster. The host (peer 1) is never dropped, so the roster is never empty: if its own load fails, `server/` ends the session, which clients see as the host lost (#40) | Pregame | the deal (§3.3): `DealRoles`, `DealTasks`, `SpawnItems` (knives), `PlacePlayers` |
| Pregame | `pregame_done`: the end tick is reached (#213) | Round | `StartClock`: the clock and `RoundStarted` begin with the round |
| Round | `won(winner)`: a win condition (§3.4) | End | `EndMatch`: `MatchEnded`. The clock stops because End's clock does not run |
| End | `back`: the end tick is reached, with no intent (#212: everyone returns after 3 s; no button), or the host's `ReturnToLobby` before it | Lobby | `ResetMatch`: the match state reset from the roster (the players who left dropped), everyone un-ready, and `SettingsChanged` to everyone (#737: with fewer players the lobby may be short again); then `PlacePlayers` in the lobby. In this order: placed first, a downed or dead player would be placed in the lobby still downed or dead, a dead one with no avatar in anyone's snapshot |

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
  (`roles`, `task_types`, `circles`, `tasks`, `packages`, `zones`, `switches`, `knives`, `spawns`; Cooking's
  `cooking_boxes`, `cooking_orders`, `herb_code` and `herb_beds`, #772; the car repair's `car_parts`, #807, provisional ids), named in the data of the part that
  draws (§9.4), gets its own `RandomNumberGenerator`, seeded by a fixed mixing function of the match seed and the
  purpose's name (for example SplitMix64 over the seed and an FNV-1a hash of the name; not `String.hash()`, whose
  algorithm is no documented contract). In GDScript `>>` on `int` is arithmetic, so
  the implementation masks after each shift, and its unit test pins known outputs. A new purpose never shifts the
  draws of the existing ones. Shuffles are our own Fisher–Yates over the injected RNG (`Array.shuffle()` uses the
  global one), and inputs are iterated in a stable order: players by peer id, spawn points in their level order.
- **The deal** (the actions of the `all_loaded` row, §9.4), in this order: roles (`DealRoles`: dissidents = max(0,
  min(setting, N−1)), drawn from the roster in peer-id order with the `roles` stream; each player learns its own role,
  and each dissident the dissidents); then `DealTasks` (the engineer's decision of 2026-09-30, #79): it draws *tasks*
  different task types from the mode's task types that play on the match's map (`TaskType.maps`, #803) minus the host's
  bans (`task_types`), the map's whole pool when *tasks* asks for more, and runs each drawn type's deal
  once, in the mode's order. Tasks are shared: nobody owns one. The greybox's Delivery by colours (`colour_delivery`,
  §9.5.4): circle positions and colours (one
  circle per package, over the map's circle spawn points), package positions, and one task of *packages* packages, each
  bound to a random circle of its own, whose colour it takes (`tasks`). The House's Delivery by meaning (`delivery`,
  #828, §9.5.25): the routes shuffled (`tasks`), *packages* items split over them so every route has one before any has
  a second; a white drop-off station on the one marker of each drop-off that got an item, its station ids in `routes`
  order (not the level's); the items on distinct random free markers of their spawn tag and which item takes which
  marker (`packages`), item ids in the markers' level order; subtask *i* is item *i*. The zone task's deal (#647, §9.5.18): one task
  of *zones* zones on distinct random zone spawn points, each in a distinct random palette colour (both `zones`); zone
  *i* is subtask *i* in station-id order. The Generator's deal (#797, §9.5.19): its generator on the one
  `generator` marker, then a switch on as many of the `switch` markers as its subtasks setting asks, drawn with `switches`, in level
  order; switch *i* is subtask *i*. Cooking's deal (#772, §9.5.20): its fixed stations in level order (the boards,
  the grill, a bed on every `herb_bed` marker, N places), then a box per box kind on a random free marker of its tag
  (`cooking_boxes`), then per place its order's bun, raw patty and herb (`cooking_orders`), then the code
  (`herb_code`) and the herbs over the beds (`herb_beds`), each a Fisher–Yates permutation; place *i* is subtask *i*.
  The car repair's deal (#807, §9.5.21): the car, the lift panel, one bin per part
  kind and the part's picture, each on its one marker, then the N needed parts drawn with `car_parts`; part *i* is
  subtask *i*. The photo task's deal (#781, §9.5.22): a station on the one marker of each of its
  five kinds (camera, photo spot, film box, printer, board, in that id order), then one fresh film on the `film`
  marker; nothing drawn; at 0 photos nothing placed. Then each task's `TaskState` (its id, type and
  subtasks done and in total: the task screen's data, M4-5) and `TaskProgress` (the subtasks done and in total over
  every task, 0 done unless a package spawned in its circle or an item in its drop-off) to everyone; knife positions (`SpawnItems`); player spawn points
  (`PlacePlayers`). Item and station ids are assigned in spawn-point order (Delivery by meaning's drop-offs in `routes`
  order) and `ItemSpawned` and `StationPlaced` are emitted in id order, so an id follows the level, not the draw. Packages and knives share spawn points when their item
  kinds name the same spawn tag; a marker carries one tag, and a deal puts at most one item on a marker (§9.6):
  `SpawnItems` and Delivery's packages skip the markers where an item already rests (`Items.free_markers`, which every
  placing part uses). Each placing part emits all its `ItemSpawned` first, then raises `item_rested` (spawn) for each
  item in id order. A package that spawns inside its own circle (an item inside its own drop-off) is delivered at once,
  by the rule; the `package` and `circle` tags (and the `drop_*` tags) keep the two kinds of spawn points apart.
- **Exact numbers.** Health and stamina are integers in thousandths, so a replay on another machine matches exactly.
  Positions are the claims as received.
- **Replay.** The command log holds everything `core/` is given: the session seed, the game mode's path and a hash
  of its content (every resource it loads, sub-resources included), every command with its tick and order (the ones
  `server/` originates too: `PeerConnected`, `PeerLeft` with their peer ids, `BodyMoved` with a body's report (§7.1.18), and in debug builds `ForceRole`, §9.4
  `DealRoles`), the levels' `LevelLayout`s (§9.1), and every `WorldQuery` answer (a throw's flight adds only answers,
  no command of `server/`'s: §7.1.16). A replay reads the answers from the log instead of asking the
  level, and refuses to run when the mode's hash differs (after an edit in `content/`, say the knife's damage, it
  would silently diverge); unit tests use a fake `WorldQuery`. Seeds and RNG state never leave the host (§5).
  The log grows with the session (a `MoveClaim` per player at 20 Hz, idle or not, and the answers it asks), so `Match`
  keeps it only with `recording` on (the default: the tests, `Match.replay`, the bots, the leak check): off, it keeps
  the log's header but no command, no answer and no event once `take_outbox` handed it out (unless `keep_history`).
  `HostSession` leaves it on only in a debug build, the one that writes a replay (§4.5.10), and
  `HostNode.skip_replay` turns it off; once off it stays off, since a log with a gap does not replay (#1191). The
  log is one per session, never trimmed at `End -> Lobby`: every later match's seed derives from the session seed.

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
everyone the side and why (#548: the winning condition's id and the round's play time), no name and no role (§5). The checks are in `core/win/`, tested through seeded matches in
`tests/unit/win/` (the crew wins on the last delivery only, a delivery on the end tick counts, time up with 0
dissidents, no crew present only once every crew member left, End widens nothing).

### 3.5 Joining, leaving and the host
| Phase | A client joins (its `Hello` is accepted) | A client leaves |
|---|---|---|
| Lobby | `Welcome` to it, then `PlayerJoined` and `SettingsChanged` to everyone (it included) | dropped from the roster; `PlayerLeft`, `SettingsChanged` |
| Countdown | as in Lobby, and `cancelled` | as in Lobby, and `cancelled` |
| Loading | refused: `core/` emits `RefuseJoins` on entering Loading and `AllowJoins` on entering Lobby, and `server/` sets `refuse_new_connections`. A peer whose connection completed anyway gets `DisconnectPeer`. Entering Loading also disconnects every newcomer still waiting (`DisconnectPeer`, no `Rejected`), and a `Hello` that arrives now gets `Rejected` (`joins_closed`) (E14, 3e) | dropped from the roster; `PlayerLeft` |
| Round | refused, as in Loading | life state `left`, which "no crew present" counts (§3.4); the avatar is removed and no body stays: a downed player who leaves leaves none, and a dead player's body is removed (the engineer's answer 1 on PR #133); in this order `PlayerLeft` (everyone else), the fact `player_left`, then the hand item and then the belt item come to rest on the floor below where the player stood (§7.1, M4-5). 2g (#63): `RoundPhase` hands it to `LifeRules.leave`, after forgetting a newcomer that never joined (`JoinRules.forget_newcomer`) |
| Pregame | refused, as in Loading | as in Round (`PregamePhase` hands it to `LifeRules.leave`): the players were dealt, so the round's win checks count the one who left on its entry (#213) |
| End | refused, as in Loading | life state `left`; `PlayerLeft`. `ResetMatch` drops the player from the roster, as it drops one who left in Pregame or Round, and sends `SettingsChanged` (#737) |

- **The join** (2b, `JoinRules`): `server/`'s `PeerConnected` makes a peer a *newcomer*, and only a newcomer's
  `Hello` is taken, once. Checked in order: the version equals the host's (`JoinRules.PROTOCOL_VERSION`), else
  `Rejected` (`wrong_version`) and `DisconnectPeer`; the content hash equals the host's (`Match.content_hash`, which
  `server/` passes to `Match.new` with the seed; §4.3, E1, 3e), else `Rejected` (`wrong_content`) and
  `DisconnectPeer`; the roster has fewer than the mode's maximum of players, else
  `Rejected` (`full`) and `DisconnectPeer`. A newcomer's leave is forgotten silently, and so is the late `PeerLeft`
  of a peer that a directive disconnected. The joiner stands on the first `lobby_player` marker of the phase's level
  with no player within 1 m, or on the first marker when all are taken (placeholders); no marker, or a lobby layout
  that failed to load, is a match error and the origin. In a phase whose spec's level is `PhaseSpec.Level.NONE` (the
  tutorial's `gather`, E72) the joiner stands at the origin with no error (#599): the rule keys on the spec's
  level, never on the layout being null, which the failed load has too (`join_rules_spot_test`).
- **Names** (#550, the engineer's answers on #73; built on #58's `Player<n>`): a player sets their own name
  (`UserSettings.player_name` in `user://`, "" until chosen, never empty once chosen) and `Hello` asks for it.
  The host decides (`JoinRules.joiner_name`, the rules in `core/match/player_names.gd`): `PlayerNames.clean`
  drops the C0 and C1 controls, DEL, U+FEFF, surrogates and the invisible format characters (zero-width
  marks, line separators, bidi controls: a name that looks like another), trims blank edges (the space and the Unicode spaces
  that show nothing) and keeps the first 16 characters (code points); when nothing is left (no name, the wrong
  type, blanks or controls only) the joiner gets the fallback `Player<n>`, n being its number
  (`PlayerState.number`, never sent): every accepted join that is no return ("A return" below) takes the next one,
  a named join too (`MatchState.joins`, the highest number given; a return does not step it): Player1, Player2,
  and so on. A number is never given to a second player: Player1 to Player3 join, Player2 leaves, and the next
  nameless newcomer becomes Player4. `ResetMatch` keeps the count, so it runs on through End → Lobby. An own
  name of the form `Player` and digits (`PlayerNames.is_reserved`: after `clean`, "player" in any case and one
  or more ASCII digits, nothing else; "Player 2" stays a name) is reserved for the fallbacks (P13 (b), the
  engineer's answer on #302): it reads as nothing usable, so a newcomer naming itself "Player2" while Player2 is
  away keeps its own fallback. Then `PlayerNames.unique`: a name that a present player has, ignoring case, gets
  the first free suffix " 2", " 3" and so on ("Dima", then "Dima 2"), its base cut so the whole stays within 16
  characters; a leaver's name is free again. A name is never a reason to refuse a `Hello`. Every client learns
  the final names from `Welcome`'s roster and `PlayerJoined` (§4.2). In the lobby a player changes its name with
  `SetProfile` (#551, the next item); a returning player gets its old number (#638, "A return" below).
  Tests: `player_names_test.gd`, `join_rules_test.gd`, the wire's `wire_codec_test.gd` (UTF-8, malformed bytes),
  `host_session_names_test.gd` (what each client's roster holds, over loopback) and `user_settings_test.gd`.
- **Body colours and `SetProfile`** (#551, the engineer's answers on #73 of 2026-10-08): a player's body is one of
  10 preset colours (no picker), held in `core/` as an index 0..9 (`PlayerColours`, `PlayerState.colour`;
  `core/` never holds a `Color`, the client draws the index, §4.7.50). The colour is **public**: `PlayerJoined`,
  `Welcome`'s roster and `ProfileChanged` carry it to everyone. A joiner takes the first colour no present
  player has (`PlayerColours.first_free`; `Hello` asks for none). `SetProfile(name, colour)` (§4.1) changes both,
  in the Lobby only, from a player (the base mode's accept row; Countdown, Loading, Pregame, Round and End answer
  `not_accepted`, so a profile never changes under a countdown or in a match; the tutorial accepts it nowhere).
  The host's rule (`JoinRules.set_profile`): a `name` that is not text or a `colour` that is not an int is
  `bad_args`; a colour outside 0..9 `out_of_bounds`; the name goes through `PlayerNames.clean` and
  `PlayerNames.unique` against the **other** present players (re-sending one's own "Dima 2" keeps it), and a name
  with nothing usable left, or a reserved one (`Player` and digits, P13 (b); never `Rejected` for it, so a
  player with its fallback name changes its colour by re-sending that name), keeps the current one (it never
  counts a join: `MatchState.joins` numbers joins only); the colour is the one asked when no other present player
  has it, else the **first free** one (the engineer's answer, literally: its own colour counts as free, so a
  clash can leave the sender where it was);
  both as they are: `unchanged`. Else both change and `ProfileChanged` goes to everyone; the ready flag stays.
  `ResetMatch` keeps colours and names. `GameMode.check` refuses a mode whose `max_players` exceeds the 10
  colours, so a free colour always exists (`first_free` of ten taken would give 0, unreachable). A returning
  player (M7) gets name and colour by these rules as any joiner. Tests: `player_colours_test.gd`,
  `join_rules_profile_test.gd`, `mode_check_test.gd`, `content_modes_test.gd` (the accept row),
  `host_session_profile_test.gd` (every client's roster over loopback) and the chaos run (§4.6.5).
- **The lobby's name** (#214, the engineer's answers on #214 of 2026-10-08): the host names the lobby, at most
  20 characters, with the same cleaning as a player's name (`LobbyName.clean`, `core/match/lobby_name.gd`, which
  is `PlayerNames.clean_to` with `LobbyName.MAX_CHARS`): controls and invisible characters dropped, blank edges
  trimmed, cut at 20 code points; never refused for its content. "" is the default, which is not a stored string:
  each client shows the deck key `lobby.default_name` with the host's name (`ClientModel.host_name()`, peer 1's
  roster name), so it follows the host's name and the client's language. Decisions (the implementer's, #214):
  (1) a **session property**, `MatchState.lobby_name`, next to `joins`, not a `SettingSpec` of the mode: it is
  text, not a number or an id set, and no mode (content) should own it; `ResetMatch` keeps it, so End → Lobby
  keeps the name. (2) It rides **ChangeSettings** as an optional `lobby_name` (§4.1), not a new intent: the
  mode's existing ChangeSettings row already makes it host-only and Lobby-only (`Accept_lobby_settings`, from =
  HOST; the Countdown has none), so no file under `content/` changes, and `LobbyPhase._change_settings`
  applies it all or nothing with the rest of the change. (3) It reaches clients in **`Welcome`** (the host's
  answer, so a client knows it the moment it is welcomed, before the `SettingsChanged` that follows) and in
  every **`SettingsChanged`** (a change reaches everyone; a join, a leave and the return to the lobby repeat
  it). Public: no filtering (§5). (4) The wire's `name` type carries it (§4.3.1), widened to 80 bytes for 20
  four-byte characters.
  Before `Welcome` a joiner knows no name: the connecting screen shows `connect.connecting_unnamed` (#494).
  Tests: `lobby_name_test.gd`, `lobby_phase_lobby_name_test.gd`, `host_session_lobby_name_test.gd` (over
  loopback: every client, a joiner's `Welcome`, a non-host refused, the limits), `client_model_test.gd`,
  `lobby_panel_name_test.gd` and `game_loop_test.gd`.
- A client's missed loading deadline: `core/` emits `Disconnecting(load_deadline)` to p, then `DisconnectPeer(p)`
  for `server/`, and treats p as leaving; p's client ends with that reason, not `host_lost` (#119, M4-6).
- **A return** (#638, 73-A of #73, [ADR](decisions/2026-10-09-returning-players-keep-their-number.md); the
  engineer's answers P1 (c), P3 (a), P4 (a), P13 (b) on
  [#302](https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-6085059719)): every `Hello` carries a
  return key (`ReturnKey`: the first 16 bytes of SHA-256 of "secret|target", 32 lowercase hex characters). The
  secret is random, made once per settings file (`UserSettings.secret`, written on the first launch but never over
  a file that could not be read; a malformed one is replaced); the target is the join's code or its address:port
  in lower case (`JoinTarget.return_target`), so a key one host learns works nowhere else. The host's own client,
  and any client given no usable key, sends a random key of its session alone. The host (`MatchState.give_number`)
  binds a usable key not bound yet to the joiner's new number (`MatchState.numbers`, key → number, session state
  that `ResetMatch` keeps); a later `Hello` with that key, while no present player holds the number, gets the
  number back and does not step `joins`. A key whose number a present player holds (a second window, or a return
  faster than the host's timeout noticed the leave) joins as a new number, and the key keeps its first binding; an
  unusable key (not a String of 32 of 0-9a-f) joins with no binding, never `Rejected`. Only where joins are
  allowed (Lobby, Countdown; a return in Countdown cancels it as any join): every other phase still refuses joins,
  so a player who left a round returns in the next lobby; a full lobby refuses a returner with `full` (no seat is
  held). A return restores the number only (P3 (a)): the name and the colour follow #550's and #551's rules as for
  any joiner, a nameless returner's fallback being its old `Player<n>`. No `PlayerState` holds a key, so no event
  carries one (§5); the number is not on the wire either. The command log keeps each `Hello` as sent, its key too
  (P10). Tests: `return_key_test.gd`, `join_rules_return_test.gd`, `match_state_test.gd`, `wire_schema_test.gd`,
  `user_settings_test.gd`, `join_target_test.gd`, `client_session_test.gd`, `host_session_return_test.gd`
  (loopback). Bots and the leak test with a return: #639 (73-B); the menu's last code: #640 (73-C).
- **The host is lost:** there is no `core/` event: `core/` runs on the host. How a client notices is a transport
  signal (#40); the client returns to the main menu with a message.

### 3.6 Pregame, the silent intro (#213, M6.2)
The engineer's answers on #213 (2026-10-02 and 2026-10-08): pre game is its own phase, `pregame`, between Loading and
Round, like a film's titles: a dark screen (`EndBackdrop`, the pack's ToyBackdropNight like the end screen's `Night`, not pure black) shows each player its own role for
about 3 s, nobody hears anybody, there is no input and no movement, and the round's clock does not run yet. Neither
screen says anything about the microphone: it is obvious nobody hears anybody. Post game is End (§3.2), already
silent; a test keeps it so.
- **The data** (`content/modes/base_mode.tres`): `Phase_pregame`, class `PregamePhase`, `seconds` 3.0 (the
  engineer's "about 3 s"), no accepts (a `MoveClaim` in flight is dropped as in any phase that refuses it, E15;
  every other intent gets `not_accepted`), no tick systems, no win check, the clock stopped, `SilentVoice`, the map
  level, no snapshots (nothing moves). `PregamePhase` itself only reports `pregame_done` on its end tick, refuses
  joins, and hands a leave to the life rule as Round does (§3.5).
- **The rows.** The deal stays on `Loading, all_loaded → Pregame`: `RoleAssigned` and `Teammates` reach each client
  before the pregame's `PhaseChanged`, so its screen has the role at once, and everyone is placed on the map. Only
  `StartClock` waits, alone on `Pregame, pregame_done → Round`, so `RoundStarted` names the round's first tick and
  the round's `PhaseChanged` its clock end. No win condition is checked in the pregame: a leave that empties the
  crew there is seen by the round's entry, in the same step (`Match._finish_step`), before any of its ticks.
- **The client** (`GameFlow.Screen.PREGAME`, `client/ui/pregame_screen.gd`): chosen by the own copy's `PhaseSpec`,
  its class `PregamePhase`, never by the phase's name. The Toy role reveal (#496, §4.7.39): on the opaque Night, "Your
  role", the own role on the title plate, its generic goal and, for a dissident, its teammates' names (the engineer
  on #175); nothing of any other player's role. At the round's start Night fades out over the HUD. Frozen as Loading
  and End, and the mouse kept as in Loading (#517).
- **Role sounds.** The refinement of 2026-10-02 asks one sound per role in the pregame (#175): the pregame screen,
  where nobody hears anybody, plays the own side's once as it reveals the own role (its `role_revealed` hook,
  #716, §4.7.39), and stops it when the pregame ends, so none plays in the round; local to the own client, so no peer
  hears another's.
Tests: `tests/unit/match/phases/pregame_phase_test.gd` (the last `LoadAck` enters it with roles dealt and no clock;
the round, `RoundStarted` and the clock on its end tick; each peer's own `RoleAssigned` only; a dropped `MoveClaim`
and `not_accepted` for the rest; no win check before the round's entry; a leave as Round's; a connection refused;
its `seconds` bounds; a mode with no `pregame_done` row refused), `tests/unit/voice/voice_by_phase_test.gd` (nobody
heard on any pregame tick with everyone within 2 m; its radius 0), `tests/unit/content/content_modes_test.gd` (the
data, the rows, and the real mode's pregame ticks silent with the clock still), `game_flow_test.gd` and
`screens_test.gd` (the screen, frozen, the mouse kept, no word on the microphone), `pregame_screen_test.gd`
(§4.7.39), the chaos bots (the oracle's `pregame` row; quiet phases from the mode's voice rules; the hostile speaks
in the pregame, and no honest bot may decode it). How it looks: the `shot`s of §4.7.39.

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
  ids, as precise as the backend can tell (M6-4, #370): the loopback cannot tell a refusal from no answer and gives
  `connect_failed`, ENet gives `joins_closed` for a host refusing new connections (§4 "Joining") and `connect_failed`
  otherwise; WebRTC adds `no_room`, `joins_closed`, `full` (the service's answers),
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
    (`UNKNOWN_KIND`), the exact `BYE` frame on RELIABLE below excepted. After every channel
    was read (the backlog drained first, so a thawed side drops nobody), a peer heard nothing from for `SILENCE_MS`
    (20 s), keepalives included, leaves: `peer_left` on the host, `host_lost` on a client. So does a connection in
    `FAILED` or `CLOSED` (judged after its channels were read, so what came with the end comes first, as on ENet;
    the fault shim's late RELIABLE packets too), and a channel not open under a live connection: on a client at once (it is how
    `disconnect_peer` ends it); on the host after `CHANNEL_GRACE_MS` (1 s) with the connection still up, counted as
    `CHANNEL_CLOSED` (a client's own close resets its channels just before its connection ends, and under load the
    host read the first a poll before the second: 1 run in 10). Inside that grace a send on a channel the client
    closed returns `ERR_DOES_NOT_EXIST`, as for a peer gone, so the host logs no error for it (#639: a leave in
    `bots-webrtc` did in 3 runs of 4). `DISCONNECTED` is transient. A join not admitted
    `JOIN_TIMEOUT_MS` (15 s) after `join()` gives up with `host_unreachable` (no offer came, or the channels never
    opened); the host closes a half-made connection after as long. A join whose socket to the service has not opened
    by `Signaller.CONNECT_TIMEOUT_MS` (5 s, §4.8) gives up before that with `service_unreachable` (#431, #461): on
    Windows the engine reports a refused connect only at its TCP connect timeout
    (`network/limits/tcp/connect_timeout_seconds`, 30 s; `WebSocketPeer` and `StreamPeerTCP` alike), though the OS
    refuses a closed 127.0.0.1 port in about 2 s, and a service that takes the connection but never answers the
    handshake reports nothing. On Linux the refused socket closes at once (`service_unreachable` too).
  - **Never a send on a closed channel:** each write checks the channel's `get_ready_state()` first (a closed one
    prints an engine `ERROR:` line, M6-1). A leaving peer's channels are drained and discarded until it is gone.
  - **Nor into a connection the other side shuts down** (#950): one closed over there can still read open here for a
    moment (libdatachannel's threads change its state), and a send into it prints `SCTP sending failed, errno=32`
    (`bots-webrtc` failed on it three times, a client's leave while the host sent snapshots). So `close()` (either
    role) sends each live peer `BYE` on RELIABLE (the kind-0 frame with the 1-byte payload 3, consumed before the
    inbox) and leaves the connection to it, kept by a SceneTree timer for `CLOSE_WAIT_MS` (5 s) and then closed
    (with no SceneTree, or a peer not live, at once; a peer no longer connected or silent for over `SILENCE_MS`
    less one keepalive gets no `BYE` and is closed at once too: it has dropped the connection or is about to, #1231; a process that quits in the frame it closes frees the timer and
    drops the connection at once, so it keeps running for a moment first). A side that reads `BYE` has read all sent before it, sends
    nothing more, ends that peer (a leave on the host, `host_lost` on a client) and closes the connection itself.
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
  left a refused client "connected" until a timeout. A refusing host sends the new peer `REFUSED_JOINS_CLOSED` on
  RELIABLE instead (kind 0 with a 1-byte payload, the reason: 1, joins closed) and disconnects it later, and the
  client gets `connect_failed` with `joins_closed` at once, as over WebRTC (#1233); an id in use is disconnected
  with no frame (`connect_failed`); with no answer at all (no host, or a full one) the join gives up after 5 s.
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
  connection; `BYE` both ways, and ten client closes with the host sending meanwhile and no engine error line, #950;
  the round trip's pings only while measuring, one answer per poll, probes the wrong way rejected;
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
| `Hello(version, content, name, key)` | a connected peer that is not yet a player, once; Lobby or Countdown. In another phase a newcomer's `Hello` gets `joins_closed` and `DisconnectPeer`, another non-player's `joins_closed` (E14, 3e) | the version (an int) equals the host's, or `wrong_version` and `DisconnectPeer`; `content` (an int, the content hash, §4.3) equals the host's (`Match.content_hash`), or `wrong_content` and `DisconnectPeer` (E1, 3e); room in the roster, or `full` and `DisconnectPeer`. `name` (a String, the player's own, #550) is never refused: the host cleans it, falls back to `Player<n>` and suffixes a duplicate (§3.5). `key` (the return key, #638) is never refused either: a usable one may give an old number back, anything else joins with a new number and no binding (§3.5, "A return"). Accepted, it is the join (§3.5) |
| `SetReady(ready)` | any player; Lobby (true or false), Countdown (false only: true is `not_accepted`) | `ready` is a bool, or `bad_args`; that it changes the player's state, or `unchanged` |
| `ChangeSettings(settings, map, lobby_name)` | the host (peer 1) only; Lobby only | `settings` names only the settings that change; each is a declared setting (`unknown_setting`) with a value of its kind (§9.1; else `unknown_setting`): an int within its bounds (`out_of_bounds`), or for `banned_task_types` an array of the mode's task type ids (another id: `out_of_bounds`), which replaces the set. Then the settings as they would be must suit the deal: `tasks` at most the task types not banned, and at least one type not banned (`out_of_bounds`; #79, placeholder rules). The optional `map` is one of the mode's maps (`unknown_map`). The optional `lobby_name` (#214, §3.5) is text (else `bad_args`, which only a `core/` caller can reach: the wire's type is `name`), never refused for its content: `LobbyName.clean` keeps 20 characters, "" is the default again. All or nothing. Whether they fit the map is checked at `all_ready` |
| `LoadAck(match_id)` | each player of the frozen roster, once; Loading | the current match id (the match's index in the session): an ack of another match is dropped silently; a second ack is `unchanged` |
| `MoveClaim(epoch, client_tick, position, velocity, facing, sprint, moving, jumps, on_floor, crouched, sneaking, sprint_ticks, moved_ticks)` | living players in Lobby, Countdown and Round; the downed in Round (its facing only, the rest ignored and never corrected, §7.1.7); never the dead; in another phase, or from another sender, dropped without `Rejected` (E15, 3e) | the current epoch and a rising client tick (else dropped as stale); finite values; the client tick rising at a bounded rate; speed for the life state and stamina; jumps; height (§7, §7.1). `client_tick` counts 20 Hz core ticks of the client's own clock (`Ticks.RATE`), not physics frames. `sprint` and `moving`: the sprint state and movement input in any physics step since the client's last claim (#155). `sprint_ticks` and `moved_ticks` (#155): the same per client tick, bit i for client tick `client_tick - i`, so a claim the LATEST merge superseded still has each of its ticks settled as sent; the host reads only the bits of the ticks the claim covers (older ones take bit 31), and a mask outside the u32 is malformed in core itself (`MovementRule.MAX_MASK`, a `Correction`). A claim that fails a check gets `Correction`, not `Rejected`. `jumps` (3e, E2): the client's count of jumps since it adopted the epoch, which survives the LATEST merge (§4.3, §7.1) |
| `PickUp(item)` | a living player; Round | the item lies on the ground (not carried, not delivered); pick-up reach from the host's position of the player; line of sight. It goes to the hand; a one-handed hand item moves to an empty belt, any other hand item rests where the picked one lay (§7.1.11, M4-5); beside a two-handed hand item a one-handed picked item goes onto the belt instead, a full belt's item put down at the feet first (the cooking ADR's CE21, #771) |
| `PutDown(facing)` | a living player with an item in hand; Round | nothing from the client but the facing: the host computes the placement (§7.1.12). Only the hand item: a belt item alone is `empty_hand` |
| `Use(facing)` | a living player; Round | the first `Use` rule of the hand item's kind (never the belt item's), the actor's role or the mode (§9.2); none: `nothing_to_do` (an empty hand, or a package in the MVP). The knife's rule: its minimum interval since this player's last hit, whatever weapon that was; stamina of at least the hit's cost; the host picks the targets (§7.1.10) |
| `ReturnToLobby()` | the host only; End | none: End reports `back` at once, before its end tick; since #212 no screen sends it (the tests and the bots' `ReturnToLobby` step do) |
| `Raise(target)` | a living player; Round (M4-4, E28: sent on pressing E over a downed player) | the base mode's raise rule (§9.5), its conditions at the start and again every tick: the target is downed (`not_downed`) and its body is at rest (`moving` while the host's physics moves it, KE15, #847); neither the sender nor the target is in a running channel (`busy`: one raiser at a time, the engineer's answer 4 on PR #133); the target lies within the pick-up's 2 m of the sender's last accepted position (`out_of_reach`) and in its line of sight (`blocked`). A raiser may hold the package. Accepted, the raise runs until it completes or stops (§9.4 `RaiseDowned`) |
| `StopRaise()` | a living player; Round (M4-4: sent on releasing E) | the sender runs a channel (`not_channeling`: a late one after it completed or stopped): a raise, or a hold at a station (`HoldStation`, #805); applied, that channel stops (releasing E ends a hold too, the car repair ADR's RE5) |
| `NextStage()` | the host (peer 1) only, `AcceptSpec` HOST; only a scripted mode's phase that lists it (the tutorial's `lessons` and `raise_stage`, `docs/design/tutorial.md` §2.4, E65). The base mode lists it in no phase: `not_accepted` (#599) | nothing more: the phase's rule reports `next` (§9.4 `ReportOutcome`) and its one `next` row runs. A session control like `ReturnToLobby` (not in `Intents.PLAYER_ACTIONS`), so the client does not resend it; as every applied intent it stops the sender's own channel first |
| `SetProfile(name, colour)` | a player; Lobby only (#551; the base mode's accept row, the tutorial lists it nowhere): elsewhere `not_accepted` | `name` text and `colour` an int (`bad_args`); `colour` one of the 10 (`out_of_bounds`); the name cleaned and made unique against the other players (§3.5; nothing usable left keeps the current name), a colour another player has replaced by the first free one; both as they are: `unchanged`. Applied: `ProfileChanged` to everyone; the ready flag stays. A session control, not in `Intents.PLAYER_ACTIONS` |
| `GiveUp()` | a downed player; Round (M4-4) | nothing more: the player dies at once, and a raise of it stops first (§9.4 `Die`) |
| `Swap()` | a living player; Round (M4-5, the ADR's controls: X); the downed and the dead get `not_accepted` | an item in the hand or on the belt (`nothing_to_swap`); no two-handed item in the hand (`two_handed`: a package carrier cannot draw a belted knife, V13). Applied, the hand and belt items change places, either of which may be empty, and a raise the sender runs stops (§9.2) |
| `Throw(facing)` | a living player (`PLAYER_ACTIONS`: the dead get `not_accepted`, even the host); a phase whose mode accepts it (the base mode's Round, #646) | the first `Throw` rule of the hand item's kind, the actor's role or the mode (§9.2; none: `nothing_to_do`). The base mode's rule: `HoldsItem` (`empty_hand`: a belt item is never thrown), `OverFloor` (`no_floor`: a floor below the host's position of the sender), then `ThrowItem` (§7.1.16, #643). Nothing from the client but the facing, and a facing that does not normalize to a unit vector takes the last accepted claim's. Applied, the item flies and a raise the sender runs stops; refused, nothing stops (§9.2) |
| `Interact(station or item)` | a living player (`PLAYER_ACTIONS`: the dead get `not_accepted`, even the host under `HOST`); a phase whose mode accepts it (the base mode's Round, from the living, since #800, the Generator's G5) | `station` and `item` ints, each optional (-1, none), and exactly one of them names something: both or neither is `bad_args` (the cooking ADR's CE1, #770). A `station` that names no placed station, which is all a fixed switch is, or a station of a display kind (`StationKind.display`, CE6: the order and herb boards): `nothing_to_do` before any owner is tried (a package carrier hears `nothing_to_do`, not `two_handed`). An `item` that names no item: `nothing_to_do` too; else only the first `Interact` rule of the item's kind's `target_actions` (none: `nothing_to_do`), never the role's, the mode's or the hand item's: a box's take, whose rule is `ItemOnGround` (`unavailable` for a carried box), `InReach`, `InSight`, then `GiveItem` (CE2, CE3; §9.4.2). Then the first `Interact` rule of the station's kind (`StationKind.actions`), the actor's role or the mode, never the hand item (§9.2; none: `nothing_to_do`). A station's rule, as the Generator's switch has it: `HandNotTwoHanded` (`two_handed`), `AtStation` (`out_of_reach`), `StationInSight` (`blocked`), `StationUsable` (its type's `use_problem`: `unavailable`, or another reason the type lists in `use_reasons()` among `StationUsable.REASONS`, `wrong_item`, `empty_hand`, `two_handed`, the cooking ADR's CE11, #780; `no_film`, `no_frames_left`, `film_exposed`, the photo ADR's PE16, #781; `nothing_to_print`, `no_photo`, #782), then `UseStation` (the Generator ADR's GE1 to GE4, #796). A kind's rule may instead hold the station (`HoldStation`, #805: `AtStation` and `ChannelFree`, `busy` while another channel runs on it), a channel its rule's conditions check again every tick, ended by `StopRaise` (§9.4.2). Applied, a channel the sender runs (a raise, a hold) stops; refused, nothing stops (§9.2) |

A connection and a leave are not intents: the transport reports them, and `server/` passes `PeerConnected(peer)` and
`PeerLeft(peer)` to `core/`. The join is the accepted `Hello`; `server/` disconnects a peer that sent none within
the hello deadline. Nor are the host's body reports: `server/` originates `BodyMoved(peer, epoch, position,
velocity)` from `HostBodies` (§7.1.18, KE14), never decodable from the network, and `core/` takes it in every phase.
Debug commands (§8) are outside this table and exist in debug builds only: `ForceRole` (§9.4
`DealRoles`, 2j) is a command that `server/` originates, and on the wire (M3) it is a debug-only kind that only the
host's own client may send (§4.3, E17).

### 4.2 Events (MVP, #32)
Who receives each event is its audience (§5). A snapshot is not an event: §5 says what it holds for each peer. The
wire schemas of the events and the snapshot are §4.3.

| Event | Payload | Audience | When |
|---|---|---|---|
| `Welcome` | your peer id, spawn point and epoch; the roster with names (the host's final names, §3.5), ready flags and body colours (#551); the whole-number settings (the bans of task types follow in the `SettingsChanged` after it) and the map; the phase; the other players' positions; the lobby's name ("" while it is the default, #214) | the joiner | its `Hello` is accepted |
| `PlayerJoined` | peer, name (the host's final name, §3.5), spawn point, body colour (an index 0..9, #551) | everyone | its `Hello` is accepted, after its `Welcome` |
| `PlayerLeft` | peer | everyone | a player leaves in any phase, or misses the loading deadline |
| `ReadyChanged` | peer, ready | everyone | `SetReady`; everyone un-ready on `End → Lobby` |
| `ProfileChanged` | peer, name and body colour as the host settled them (§3.5) | everyone | an accepted `SetProfile` in the lobby (#551) |
| `SettingsChanged` | settings (the whole numbers, and the banned task types) and map; the player count; the derived demands per spawn tag (§9.4: in the MVP packages, circles, knives, player spawns, for any draw of the task types) against the map's markers, the package count among them; colours per station kind against its palette; every shortfall that holds `all_ready` back, as host text (an id, its subject ids and whole-number arguments, which each client words in its own language, #548); the lobby's name ("" while it is the default, #214) | everyone | `ChangeSettings`, a join or leave in Lobby or Countdown (the demands change), and `End → Lobby` (`ResetMatch`, #737: the players who left mid-match are dropped, so the shortfalls of before the countdown are stale) |
| `PhaseChanged` | phase; the countdown's or the match clock's end as a host tick, if it runs | everyone | every transition |
| `CountdownCancelled` | reason: un-ready, join or leave | everyone | `cancelled` |
| `PlayersPlaced` | per player: spawn point | everyone | `End → Lobby`; the deal (§3.2) |
| `LoadMatch` | match id, map, the whole-number settings | everyone | entering Loading |
| `PlayerLoaded` | peer | everyone | a valid `LoadAck` |
| `RoundStarted` | start tick | everyone | entering Round (`StartClock` on `Pregame, pregame_done → Round`, #213) |
| `RoleAssigned` | your role | that player | the deal |
| `Teammates` | a role and the peer ids of its players | each player of that role, for a role that knows its teammates (the dissidents) | the deal |
| `StationPlaced` | station, station kind (in the MVP the delivery circle), colour, position | everyone | the deal, in station-id order |
| `ItemSpawned` | item, kind, position; a package's circle and colour | everyone | the deal, in item-id order, or given mid-round by `GiveItem`, then not in spawn-point order (#770) |
| `ItemPickedUp` | peer, item; `belted`: the one-handed hand item this pickup moved to the belt, or none (M4-5, E29), or the item itself when it went straight onto the belt beside a two-handed hand item (the cooking ADR, CE20, CE21, #771) | everyone | `PickUp`; or `Items.give` (#771): a new item from a source, or an item locked on a station taken back (a box's, a bed's or the grill's take, the cooking ADR §2), the taker making room by §2's table (a hand item it puts down at its feet comes first as `ItemPlaced` `put_down`) |
| `Swapped` | peer | everyone | a `Swap` (M4-5): the peer's hand and belt items changed places. With `ItemPickedUp`'s `belted` and `ItemPlaced` it tells every client every player's two slots, its own included (its avatar is sent to it only while it is knocked down, KE5) |
| `ItemThrown` | item, peer (the thrower), origin, velocity, gravity, launch tick: exactly the flight's vectors, so a client computes the host's arc bit for bit (`ItemFlight.point`, §7.1.16) | everyone: the item was in a hand everyone sees, and the velocity shows only the facing the snapshot already shows (a role-owned `Throw` rule would put the role into it: ModeCheck warns, §9.2) | a `Throw` (#643), before the flight's first tick |
| `ItemPlaced` | item, rest position, cause: put down, swap (a pickup's hand item that did not go to the belt), death or leave (at a death or a leave the hand item's comes first, then the belt item's), thrown (a flight's rest, §7.1.16) | everyone | an item comes to rest |
| `PackageDelivered` | item, its circle (now shown as done) | everyone | the delivery check (§7.1.14) |
| `ItemVanished` | item | everyone: items on the ground are public, and it names no player | an item of a kind with `vanish_seconds` lay on the ground that long (`VanishTicks`, §9.4.5; the cooking ADR, CD6 (c), #779); its id may later name a new item (§9.3) |
| `ItemChanged` | item, kind | everyone: items are public, and it names no player | `Items.change_kind` (the cooking ADR, CE4, #771): an item became another kind where it is (a patty on the grill turning fried, then burnt), keeping its id, place and holder; nothing is sent when it already is that kind |
| `OrderPosted` | a place's station, the bun's kind, the fried patty's kind and the index of the herb's icon (#772; the cooking ADR, CE8, CE9) | everyone: tasks are shared, and it names no player; it carries the icon, never the herb (CE9 (a)) | Cooking's deal (§9.5.20), one per place in station order, after its `StationPlaced`s and the boxes' `ItemSpawned`s |
| `HerbsDealt` | the herb's kind per icon (the code) and per herb bed in station order (#772; CE8, CE9, CD13 (b)) | everyone, as `OrderPosted`; an honest client draws the code only on the herb board and a bed's herb only on its bed | Cooking's deal, once, after its `OrderPosted`s; none when its subtasks setting is 0 |
| `GrillLoaded` | the grill's station, the patty's item, and the host ticks it turns fried and burnt at (#773; the cooking ADR's §2.4, CE5, CE10) | everyone: it names no player | Cooking's grill took a raw patty (§9.5.20); taking it off is `Items.give`'s `ItemPickedUp`, and no event marks the grill empty |
| `IngredientPlaced` | the ingredient's item, the place's station (#773; since #1101 never whether it is right: the cooking ADR's amendment of 2026-10-15) | everyone: it names no player | an ingredient went onto a place's free slot (§9.5.20), first: before it is locked there |
| `TaskState` | task, its task type's id, its subtasks done and in total (M4-5, E30) | everyone: the task screen is every player's, living, downed or dead | the deal, for each task in id order, after the task types dealt; a subtask of that task is done, before `TaskProgress` |
| `TaskProgress` | subtasks done, subtasks in total, over every task of the match | everyone | the deal, after the task types dealt and their `TaskState`s (so the HUD shows the total from the start); a subtask is done |
| `ZoneProgress` | a zone's station, its ticks so far (after this tick's gain), the ticks it needs, whether it counts now, and the host tick (#647, ZE4) | everyone: it names no player, and counting is role-blind (ZD3) | the zone task's tick (§9.5.18): a zone whose counting changed since its last one, at most once per zone per 5 ticks (a change inside the window goes out at its end with that tick's state), and a zone done, in its own tick, before its task's `TaskState` and `TaskProgress`. The Generator's charge shares it (#797, the Generator ADR's GE7 and GE8; §9.5.19): its station is the generator's; at 0 in the deal, after the `StationPlaced`s; a start or stop by a use, after its `SwitchChanged` or `ButtonPressed`, with `tick` the tick before (the charge counted through it), or held to its window's end; the full charge in its own tick, before the `TaskState`s and `TaskProgress` |
| `SwitchChanged` | the switch's station, whether it is on now (#797, the Generator ADR's GE9) | everyone: it names no player (the ADR's row 18), and any living player of any role may use a switch | an accepted `Interact` on an active switch of the Generator (it toggles); before the charge's `ZoneProgress` when the toggle stopped it |
| `ButtonPressed` | the generator's station (#797, GE9) | everyone, as `SwitchChanged` | an accepted `Interact` on the generator, whether or not it changed the charge (a press with a switch off changes nothing else); before the charge's `ZoneProgress` on a start or stop |
| `LiftChanged` | the lift panel's station, whether the car goes up (a hold began) or down (it stopped), the host tick (#807, the car repair ADR's §3) | everyone: it names neither the holder nor who let go, and any living player of any role may hold the lift | `CarRepair.hold_started` and `hold_stopped` (`HoldStation`'s `hold_emits`); a drop's `LiftChanged` comes before its victims' `Died`, which wait for the end of the command, tick system or channel step (RE17) |
| `PartNeeded` | the picture's station, the part kind needed now, or none when every part is fitted (#807, RD3) | everyone, as `LiftChanged` | the car repair's deal, after its `StationPlaced` events; then after each `PartFitted`, with no kind once the last part is fitted (#808) |
| `FitChanged` | the car's station, the fitting player's peer, or 0 when the fit stopped, the host tick (#808, the car repair ADR's §2.4, RE10) | everyone: the engineer accepted that every client learns who fits (RD15 (a)), drawn only on the fitter's avatar; nothing at the lift panel reads it | `CarRepair.hold_started` and `hold_stopped` for the car's timed hold: a fit's start, and a stop before it completed (its progress is lost, RD10 (d); a stop by a hit confirms the hit to everyone, the exception `RaiseStopped` has); a completed fit sends `PartFitted` instead |
| `PartFitted` | the car's station, the fitted part's item (#808, RE10, RE12) | everyone, as `LiftChanged`: it names no player | `CarRepair.hold_completed`: the part leaves the fitter's hand, locked at the car's use spot (`Items.lock_at`, no `ItemPlaced`); then the task's `TaskState` and `TaskProgress`, then `PartNeeded` |
| `FilmLoaded` | the camera's station, the film's item (#781, the photo ADR §2.2, §3.1) | everyone: it names no player (PD13), and items and stations are public | an accepted `Interact` at an empty camera: the actor's fresh film lies on the camera (`item_rested` on_station, no `ItemPlaced`) |
| `ShotTaken` | the camera's station, the film's item, the shot's id (u16, wrapping), the record: up to 15 rows of `peer`, `position`, `facing`, `downed`, `crouched` (#790), `held_item`, `belt_item` (#781, §3.3) | everyone: the rows hold what every player's snapshots show anyway, the recipient's own pose included (§5); it names no shooter and never says whether a person counted (PE5) | an accepted `Interact` at a loaded camera with frames left (§9.5.22) |
| `PhotoPrinted` | the photo's item, the shot it shows (#782, the photo ADR §2.6, PE8) | everyone: it names no player and never says whether a person is in the shot (PE5); every shot was public already | an accepted `Interact` at the printer: per shot of the actor's exposed film, in shot order, after the photo's `ItemSpawned` on the tray; the film's `ItemVanished` follows the last (§9.5.22) |
| `BurgerPlated` | the burger's item, the place's station, the kinds of its bun, patty and herb (#1101, the cooking ADR's amendment) | everyone: it names no player and only what everyone saw on the plate, never whether it is right | a full plate was taken as a burger (§9.5.20), last: after the plated items' `ItemVanished` and the burger's `ItemSpawned` and `ItemPickedUp` |
| `BurgerServed` | the burger's place's station, and whether the burger was right (#1101) | everyone: it names no player and no part | a burger was served at the order board (§9.5.20), first: before the burger's `ItemVanished` and, right, before the leftovers' `ItemVanished` and the subtask's `TaskState` (CE13) |
| `PhotoHung` | the photo's item, the board's station, whether it counted (#782, the photo ADR §2.7, PE9) | everyone: it names no player; the board shows what hangs on it and the count is the public task state | an accepted `Interact` at the board: counted, the photo is locked there for good and `TaskState`, `TaskProgress` follow; not, it lies there (`item_rested` on_station, no `ItemPlaced`) for `PickUp` |
| `Swung` | peer, facing (the zone's horizontal direction, a unit vector or zero when it has none: of the `Use`'s facing, or the last accepted claim's when the `Use` had no finite, non-zero one) | everyone | a valid `Use` of a knife (`Strike`), whether or not it touched anyone; before any `Damaged` |
| `Damaged` | amount, your health (thousandths, §3.3); no attacker | the victim | a hit on them |
| `SelfStatus` | health and stamina (thousandths, §3.3), whether sprint is available, and the client tick of the last `MoveClaim` the host settled for that player in its epoch (-1: none since its placement; #155) | that player | on change of the numbers, at most once per tick: at the end of the tick, with its final numbers (`SelfStatusFeed`); a new claim tick alone sends none |
| `KnockedDown` | peer, where it lies (the floor below its last accepted position; on a map `PlayerRules.motion_maps` lists, the last accepted position itself, where its body starts to move, §7.1.18) | everyone, the downed player included | health reaches 0 (`LifeRules.knock_down`, M4-2); no attacker or cause. From then on its own snapshot holds its own avatar until it stands or dies (KE5, §5). It tells the attacker its hit knocked down: an accepted exception to "no hit confirmation" (vision revision 1) |
| `Died` | peer, body position | everyone, the dead player included | a downed player's knockdown time runs out (`LifeTicks`, M4-2) or it gives up (`GiveUp`, M4-4), or a living or downed player is killed at once (`LifeRules.kill`, #806: no `KnockedDown` before it); no event names a killer or a cause. The body stays until its player respawns or leaves |
| `RaiseStarted` | raiser, target | everyone | a `Raise` is accepted (M4-4): the target's knockdown pauses (it holds still as every knocked-down player does, §7.1.7) |
| `RaiseStopped` | raiser, target; no cause | everyone | a raise stops before completing (M4-4): `StopRaise`, any other applied action of the raiser, the raiser out of reach or sight, hit, downed or leaving, the target giving up or leaving. The knockdown runs on from where it paused. A raise stopped by a hit tells the attacker the hit landed: an accepted exception to "no hit confirmation" (the engineer's answer 7 on PR #133) |
| `Revived` | peer | everyone, the revived player included | a raise completes (M4-4): the player stands where it lay with the raise's revive health, its stamina kept, invulnerable for `PlayerRules.invulnerable_s`. It ends the raise (no `RaiseStopped`); a `Correction` follows (a placement where it lay, with a new epoch: its client claimed no place while knocked down, #728 KE6) |
| `Respawned` | peer, the respawn marker it stands on | everyone, the respawned player included | a dead player's respawn time runs out (`LifeTicks`' `Respawn`, M4-3): it is living again with full health and stamina and empty hands, and invulnerable for `PlayerRules.invulnerable_s`. It removes the player's body (E26: no event of its own); before the respawned player's `Correction`. Names no cause of the death |
| `Correction` | epoch, position, velocity | that player | a `MoveClaim` that fails a check (§7.1); a placement (§3.2); a knockdown: the downed player where it lies, with a new epoch (§7.1.7); a respawn: at the marker, with a new epoch, after `Respawned` (M4-3); a revive: where it lay, with a new epoch, after `Revived` (#728 KE6). None at a death (the dead send no claims), and none to a knocked-down player for any claim (its claims carry only its look, KE4) |
| `Rejected` | the intent's sequence number, reason | the sender (*sender*: a present player, or a peer that is not a player: a newcomer whose `Hello` was not accepted yet, or a peer being disconnected whose intent was in flight) | any rejected intent but a `MoveClaim` (dropped, E15); an applied intent whose outcome was dropped (`outcome_dropped`, §3.1) |
| `MatchEnded` | the winning side (crew or dissidents) and, when a win condition reported the `won`, its id as the reason with `numbers` {`time`: the round's play time in whole seconds, when the clock ran} (#548); no names, no roles | everyone | `won` |
| `Disconnecting` | reason: `load_deadline` (the only one today) | that player (`peer` is its subject, as `Correction`'s, although the payload names none) | right before the `DisconnectPeer` it explains: a missed loading deadline (#119, the M4 ADR's E21) |

Directives to `server/` have the audience *server* and reach no peer: `RefuseJoins`, `AllowJoins`,
`LaunchBody(peer, epoch, origin, velocity)` and `StopBody(peer)` (the host's body of a knocked-down player on a map
`PlayerRules.motion_maps` lists starts and is freed, §7.1.18; a replay ignores both; #847),
`DisconnectPeer(peer)`. `DisconnectPeer` follows the `Rejected` it explains, and `server/` sends what came before
it (§4, `disconnect_peer`); Loading's waiting newcomers get it too. `StartClock` emits `RoundStarted` on the
row into the round. `LeakCheck.FOR_ONE` lists `Disconnecting` by hand (§4.6.4).

### 4.3 Wire schemas (M3 design, #89)
[ADR](decisions/2026-09-30-wire-format-and-host-session.md): every row below is a row of
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
| `text` | 1 + n | `u8` n, then n bytes of printable ASCII (0x20 to 0x7E), n up to 64 (no row uses it since #550) | another byte |
| `name` | 1 + n | `u8` n, then n bytes of UTF-8, n up to 80 (`WireField.NAME_MAX_BYTES`: the lobby's 20 characters of at most 4 bytes, #214; a player's name keeps 16, #550); empty allowed (the host's fallback, the lobby's default) | a malformed sequence (checked by hand before any decode: a lone or missing continuation byte, an overlong form, a surrogate, above U+10FFFF), a C0 or C1 control, DEL, an invisible format character (U+200B to U+200F, U+2028 to U+202E, U+2060 to U+2064, U+2066 to U+2069), U+FEFF (a decoder drops it silently), bytes that do not encode back the same; the encoder refuses the same and over 80 bytes. `PlayerNames.is_dropped` (`core/`) refuses exactly these characters, so every host-made name encodes; a test pins the two, and `lobby_name_test.gd` pins both limits at 4 bytes a character within the bound. Since 80 bytes, a `Hello` name of 17 to 20 characters decodes and the host cuts it to 16 |
| `note` | 2 + n | `u16` n, then n bytes of printable ASCII, n up to 320 (no row uses it since #548: the shortfalls became host text) | as `text` |
| `list<T>` | 1 + Σ | `u8` count, then the items | a count over the field's maximum |
| `map<K, V>` | 1 + Σ | `u8` count, then key and value pairs, keys strictly ascending (by bytes for `id`, by number for `peer`) | a count over the maximum; a key out of order or repeated |
| `opus` | the rest | the rest of the payload, opaque: the host never decodes it | empty, or over the cap |
| `sized_opus` | 2 + n | a u16 length, then that many opaque bytes (a `VoiceBatch` frame's, M5-4b) | 0, or over the field's maximum (500) |

Maxima: 16 players on the wire (the base mode allows 10), so a list or map of players holds at most 16 entries (a
snapshot's avatars at most 16: the viewer's own only while it is knocked down, KE5); a map of settings or station kinds at most 32, of spawn tags (`SettingsChanged`'s `needed_markers` and `map_markers`) at most 64 (32 until #810: the House demands 36 with car repair); a
set of task types at most 16 ids; shortfalls at most 64 (32 until #775), and a host text's subject ids at most 2 and its arguments at
most 4 (#548). The sizes below are the MVP's with 10 players, then the cap.
These maxima bound the decoder, not the payload: at the maxima some kinds exceed their caps (`SettingsChanged`'s
`id_sets` alone could reach about 18 KB). How big they get depends on the content, so the content is checked
(E16): `WireBudget` (`server/`, 3d) computes, from a game mode, the worst case of every kind whose size its content
sets (`Welcome`, `SettingsChanged`, `LoadMatch`, `ChangeSettings`, `StationPlaced`, `ItemSpawned`, `Teammates`,
`PlayersPlaced`, and since #772 `HerbsDealt`, both lists as long as the mode's longest Cooking herbs, every case with
empty lists when it has none), with the mode's own ids, settings, map paths, `max_players` and shortfalls (at most one per demanded
spawn tag and demanded palette (a station kind no action demands a palette of has none, #784), each sized as the one subject and two arguments `Demands.shortfalls` makes (#775: 29 tags in the base mode, so the longest host text, 257 bytes each, would have gone over the 8192 bytes of `SettingsChanged`; since #810 the subject is the mode's longest demanded tag or palette kind, the text id the longest of the three a shortfall uses and the arguments `need` and `have`, not ids as long as the wire takes: the House's 36 tags), plus the player count and the layout, each the longest host text the wire takes). A mode over a cap is refused
when the host starts, with the kind named; a test runs it over every mode in `content/`, so `verify` catches a
content edit before a playtest instead of the encoder refusing a reliable event in one.

**Host text** (#548). No row carries a sentence: what the host words for players travels as host text, `record{id:
id, ids: list<id>, numbers: map<id, s32>}` (`core/`'s `HostText`: an id, its subjects such as a spawn tag or a station
kind, and its whole-number arguments by name), and each client words it in its own language through the copy deck
(§4.7.45), so two players of one lobby read it each in theirs. `SettingsChanged`'s shortfalls are host text;
`MatchEnded`'s reason is the winning `WinCondition`'s id with its `numbers`. The other ids a client shows (`Rejected`'s,
`CountdownCancelled`'s and `Disconnecting`'s `reason`) were ids already. A test (`wire_schema_test.gd`,
`test_no_row_carries_free_text`) fails on any row with a `text` or `note` field.

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
| 1 | `Hello` | RELIABLE | `version: u16`, `content: s64` (the content hash, E1), `name: name` (the player's own, "" for none; #550), `key: id` (the return key, decoded as a String; any id is taken and only `ReturnKey.is_valid` tells a usable one, §3.5; #638) | 12 + n + k; 8192 |
| 2 | `SetReady` | RELIABLE | `seq: u32`, `ready: bool` | 5; 5 |
| 3 | `ChangeSettings` | RELIABLE | `seq: u32`; `settings: map<id, setting>`, where a setting is `u8` 0 then `s32` (a whole number), or `u8` 1 then `list<id>` (a set of task types, which replaces the set); `has_map: bool`, then `map: path` when true (the args hold `map` only then); `has_lobby_name: bool`, then `lobby_name: name` when true (the same, #214) | 21 for one number; 2048 |
| 4 | `LoadAck` | RELIABLE | `seq: u32`, `match_id: u32` | 8; 8 |
| 5 | `MoveClaim` | LATEST | `epoch: u32`, `client_tick: u32`, `position: vec3`, `velocity: vec3`, `facing: vec3`, flags `u8` (1 `sprint`, 2 `moving`, 4 `on_floor`, 8 `crouched`, #790: the pose at the claim's last physics step, kept for a living claim in any phase, §7.1.17; 16 `sneaking`, #990: kept only for a living claim that is not also crouched, §9.5.24; other bits 0), `jumps: u16` (below), `sprint_ticks: u32`, `moved_ticks: u32` (bit i: client tick `client_tick - i`, #155) | 55; 55 |
| 6 | `PickUp` | RELIABLE | `seq: u32`, `item: item` | 6; 6 |
| 7 | `PutDown` | RELIABLE | `seq: u32`, `facing: vec3` | 16; 16 |
| 8 | `Use` | RELIABLE | `seq: u32`, `facing: vec3` | 16; 16 |
| 9 | `ReturnToLobby` | RELIABLE | `seq: u32` | 4; 4 |
| 10 | `Raise` | RELIABLE | `seq: u32`, `target: peer` (M4-4, #140, E28) | 8; 8 |
| 11 | `StopRaise` | RELIABLE | `seq: u32` (M4-4) | 4; 4 |
| 12 | `GiveUp` | RELIABLE | `seq: u32` (M4-4) | 4; 4 |
| 13 | `Swap` | RELIABLE | `seq: u32` (M4-5, #141) | 4; 4 |
| 14 | `MoveClaimReliable` | RELIABLE | the fields of `MoveClaim` (5), in its order; no `seq`. `MoveClaim`'s RELIABLE twin (#429): the client sends every epoch's first claim on it, and its last sent claim again, exactly as sent, right before a player action (§7.1.15 Lost claims). The host hands it to `core/` as the `MoveClaim` command (`WireRow.command`), so it passes the same checks and gets no `Rejected` (E15's silent drop kept) | 55; 55 |
| 15 | `NextStage` | RELIABLE | `seq: u32` (#599, the tutorial's stages, E65) | 4; 4 |
| 16 | `SetProfile` | RELIABLE | `seq: u32`, `name: name`, `colour: u8` (#551; core refuses a colour past 9, `out_of_bounds`) | 6 to 86; 86 |
| 17 | `Throw` | RELIABLE | `seq: u32`, `facing: vec3` (#643; kind 15 on `release/m7`, 17 since it reached `main`, #837) | 16; 16 |
| 18 | `Interact` | RELIABLE | `seq: u32`, `station: station` (optional), `item: item` (optional) (#796, the Generator ADR's GE1: a placed station's id from its `StationPlaced`; #770, the cooking ADR's CE1: an item's id from its `ItemSpawned`; 0xFFFF is none, and core refuses both or neither `bad_args`). A player action: the client sends its reliable claim twin first (§4.5.6) | 8; 8 |

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
| 33 | `Welcome` | `peer: peer`, `spot: vec3`, `epoch: u32`, `roster: list<peer: peer, name: name, ready: bool, colour: u8>`, `settings: map<id, s32>`, `map: path`, `phase: id`, `positions: map<peer, vec3>`, `lobby_name: name` | 171; 2048 |
| 34 | `PlayerJoined` | `peer: peer`, `name: name`, `spot: vec3`, `colour: u8` (#551) | 26; 98 |
| 35 | `PlayerLeft` | `peer: peer` | 4; 4 |
| 36 | `ReadyChanged` | `peer: peer`, `ready: bool` | 5; 5 |
| 37 | `SettingsChanged` | `settings: map<id, s32>`, `id_sets: map<id, list<id>>`, `map: path`, `players: u8`, `needed_markers: map<id, s32>`, `map_markers: map<id, s32>`, `needed_colours: map<id, s32>`, `palettes: map<id, s32>`, `shortfalls: list<record{id: id, ids: list<id>, numbers: map<id, s32>}>` (host text, #548), `lobby_name: name` | 251 with no shortfall and the default name; 8192 |
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
| 57 | `MatchEnded` | `side: id` (the winning `SideSpec`'s id; audience *everyone*, 2h), `has_reason: bool`, then `reason: id` (the winning `WinCondition`'s id) and `numbers: map<id, s32>` (at most 4; `time`, the round's play time in seconds, when the clock ran), #548 | 12 without a reason, 30 with `time_up` and its time; 216 |
| 58 | `Disconnecting` | `reason: id` (`load_deadline`; audience *only* that player, M4-6, #119) | 14; 33 |
| 59 | `KnockedDown` | `peer: peer`, `position: vec3` (audience *everyone*, M4-2, #138) | 16; 16 |
| 60 | `Respawned` | `peer: peer`, `position: vec3` (audience *everyone*, M4-3, #139) | 16; 16 |
| 61 | `RaiseStarted` | `raiser: peer`, `target: peer` (audience *everyone*, M4-4, #140) | 8; 8 |
| 62 | `RaiseStopped` | `raiser: peer`, `target: peer`: no cause (audience *everyone*, M4-4) | 8; 8 |
| 63 | `Revived` | `peer: peer` (audience *everyone*, M4-4) | 4; 4 |
| 64 | `Swapped` | `peer: peer` (audience *everyone*, M4-5, #141) | 4; 4 |
| 65 | `TaskState` | `task: u8`, `type: id`, `done: u16`, `total: u16` (audience *everyone*, M4-5, E30) | 14 for `delivery`; 38 |
| 66 | `ProfileChanged` | `peer: peer`, `name: name`, `colour: u8` (audience *everyone*, #551) | 6 to 86; 86 |
| 67 | `ZoneProgress` | `station: station`, `ticks: u16`, `needed: u16`, `counting: bool`, `tick: tick` (audience *everyone*, #647; ZE4 and ZE6 of the [zone task ADR](decisions/2026-10-09-m7-zone-task.md); `needed` is at most 12,000, 600 s; kind 66 on `release/m7`, 67 since #837) | 11; 11 |
| 68 | `ItemThrown` | `item: item`, `peer: peer`, `origin: vec3`, `velocity: vec3`, `gravity: vec3`, `tick: tick` (audience *everyone*, #643; the vec3s are exactly the flight's, so a decoded event rebuilds the host's points bit for bit, `wire_throw_test`; kind 67 on `release/m7`, 68 since #837) | 46; 46 |
| 69 | `ItemVanished` | `item: item` (audience *everyone*, #779; the cooking ADR, CD6 (c)) | 2; 2 |
| 70 | `SwitchChanged` | `station: station`, `on: bool` (audience *everyone*, #797; GE9 of the [Generator ADR](decisions/2026-10-10-generator-task.md)) | 3; 3 |
| 71 | `ButtonPressed` | `station: station` (audience *everyone*, #797, GE9) | 2; 2 |
| 72 | `ItemChanged` | `item: item`, `kind: id` (audience *everyone*, #771; the cooking ADR, CE4) | 4 to 35; 35 |
| 73 | `OrderPosted` | `station: station`, `bun: id`, `patty: id`, `icon: u8` (audience *everyone*, #772; the cooking ADR, CE9) | 7 to 69; 69 |
| 74 | `HerbsDealt` | `code: list<id>`, `beds: list<id>`, each a u8 count up to `WireSchema.MAX_HERBS` (255; audience *everyone*, #772; CE9, CD13 (b)) | content-sized (`WireBudget`); 2048 |
| 75 | `LiftChanged` | `station: station`, `up: bool`, `tick: tick` (audience *everyone*, #807; the car repair ADR's §3) | 7; 7 |
| 76 | `PartNeeded` | `station: station`, `kind: id` (optional, behind a `has_kind` flag; absent, the kind is empty: every part fitted) (audience *everyone*, #807, RD3) | 3 to 36; 36 |
| 77 | `FilmLoaded` | `station: station`, `item: item` (audience *everyone*, #781; the [photo ADR](decisions/2026-10-10-photo-task.md) §3.1) | 4; 4 |
| 78 | `ShotTaken` | `station: station`, `film: item`, `shot: u16`, `record: list<peer: peer, position: vec3, facing: vec3, flags: bits(downed, crouched (#790)), held_item: maybe<item>, belt_item: maybe<item>>` (at most 15 rows; audience *everyone*, #781, §3.3; content-sized: `WireBudget` holds its 15-row worst case) | 7 plus 29 to 33 a row; 502 |
| 79 | `GrillLoaded` | `station: station`, `item: item`, `fried: tick`, `burnt: tick` (audience *everyone*, #773; the cooking ADR, CE10) | 12; 12 |
| 80 | `IngredientPlaced` | `item: item`, `station: station` (audience *everyone*, #773; `right` dropped by #1101) | 4; 4 |
| 81 | `FitChanged` | `station: station`, `fitter: peer` (optional, behind a `has_fitter` flag; absent, the fitter is 0: the fit stopped), `tick: tick` (audience *everyone*, #808; the car repair ADR's RE10, RD15 (a)) | 7 to 11; 11 |
| 82 | `PartFitted` | `station: station`, `item: item` (audience *everyone*, #808; RE10, RE12) | 4; 4 |
| 83 | `PhotoPrinted` | `item: item`, `shot: u16` (audience *everyone*, #782; the photo ADR §2.6) | 4; 4 |
| 84 | `PhotoHung` | `item: item`, `station: station`, `counted: bool` (audience *everyone*, #782; the photo ADR §2.7) | 5; 5 |
| 85 | `BurgerPlated` | `item: item`, `station: station`, `bun: id`, `patty: id`, `herb: id` (audience *everyone*, #1101; the cooking ADR's amendment) | 10 to 103; 103 |
| 86 | `BurgerServed` | `station: station`, `right: bool` (audience *everyone*, #1101) | 3; 3 |

#### 4.3.5 State and voice

| Kind | Message | Dir | Lane | Fields | Bytes; cap |
|---|---|---|---|---|---|
| 96 | `Snapshot` | H→C | LATEST | `tick: tick` (the host tick whose state it shows); `avatars: map<peer, avatar>`, an avatar being `position: vec3`, `velocity: vec3`, `facing: vec3`, flags `u8` (1 `downed`, M4-2; 2 `invulnerable`, M4-3: strikes skip the player at that tick; 4 `crouched`, #790: only a living player, in any phase since #991, §7.1.17; 8 `sneaking`, #990: only a living player that is not crouched, §9.5.24; other bits 0), `held_item: item` (optional), `belt_item: item` (optional, M4-5). Every living or downed player's avatar, never a dead one's, and the viewer's own only while it is knocked down (§5) | 410 (9 avatars); 1024 (16 avatars: 725; a knocked-down viewer's holds its own, KE5) |
| 112 | `VoiceUp` | C→H | VOICE | `seq: u16` (the speaker's frame counter), `opus` (one 20 ms frame, 1 to 500 bytes) | 47; 502 |
| 114 | `VoiceBatch` | H→C | VOICE | `tick: tick` (the host tick whose routing let its frames through, E11); `frames: list<frame>` (1 to 113 in practice, the cap bounds it first), a frame being `speaker: peer`, `seq: u16` (renumbered per speaker and listener, §4.5) and `opus: sized_opus` (a u16 length, then 1 to 500 bytes). One poll's frames for one listener (M5-4b, #374); each frame decodes to the `VoiceDown` (speaker, seq, tick, opus) it stands for. Kind 113, protocol 7's single-frame `VoiceDown`, is retired | 58 (one 45 B frame), 9 frames: 482; 1024 |

The rules of the table:
- **Kinds.** 0 is the transport's (`ADMIT`, and ENet's refusal, §4 "Joining"); 1 to 23 are intents, 24 to 31 debug
  commands (a debug build's table only, E17), 32 to 95 events, 96 to 111 state, 112 to 127 voice.
- **Frozen:** two whole rows never change. Kind 1 (`Hello`): C→H, RELIABLE, `version: u16` as its first two bytes,
  and its cap at `NetKindTable.MAX_PAYLOAD` (8192), which never shrinks. Kind 32 (`Rejected`): H→C, RELIABLE,
  `seq: u32` then `reason: id`, cap 37. A client of any version can then send its version and read
  `Rejected(wrong_version)` (§3.5), instead of timing out at the hello deadline on a host that drops its packets as
  malformed or over the cap. The host decodes `Hello` in two steps: the version, and the rest only when the version is
  its own; another version reaches `core/` as `{version}` alone and the rest of its payload is ignored, whatever its
  length (since protocol 10 `Hello` carries the player's name, #550, and since 25 ends with the return key, #638).
  3d's version test pins both rows byte for
  byte and decodes a synthetic longer `Hello` of another version to `{version}`.
- **The version.** `JoinRules.PROTOCOL_VERSION` (`core/`) and the codec's version are one number, which a unit test
  pins. Every change to a row (a kind, lane, direction, cap, field, its type or its order) bumps it in the same PR.
  It was 2 when M4-6 (#142) added `Disconnecting` (58), 3 when M4-2 (#138) added `KnockedDown` (59) and
  renamed the avatar's flag `downed`, 4 when M4-3 (#139) added `Respawned` (60), the avatar's flag
  `invulnerable` and the debug row `ForceClock` (25), 5 when M4-4 (#140) added `Raise`, `StopRaise` and
  `GiveUp` (10 to 12) and `RaiseStarted`, `RaiseStopped` and `Revived` (61 to 63), 6 when M4-5 (#141)
  added `Swap` (13), `Swapped` (64) and `TaskState` (65), `ItemPickedUp`'s `belted` and the avatar's
  `belt_item`, 7 when #155 added `MoveClaim`'s `sprint_ticks` and `moved_ticks` and `SelfStatus`'s
  `claim_tick`, 8 when M6-8 (#374) added `VoiceBatch` (114), 9 when #429 added `MoveClaimReliable` (14), 10
  when #550 added `Hello`'s `name` and the `name` type (UTF-8) for it, `PlayerJoined` and the `Welcome` roster,
  11 when #214 added the lobby's name (`ChangeSettings`'s `has_lobby_name` and `lobby_name`, `Welcome`'s
  and `SettingsChanged`'s `lobby_name`), widened the `name` type to 80 bytes and raised `PlayerJoined`'s cap to
  97, 12 since T1 (#599, E65) added the tutorial's `NextStage` (15), 13 since #548 turned
  `SettingsChanged`'s shortfalls into host text and gave `MatchEnded` its reason, 14 since #551 added
  `SetProfile` (16), `ProfileChanged` (66) and the body colour of `PlayerJoined` (cap 98) and the `Welcome`
  roster, and is 15 since `release/m7` reached `main` (#837) with #647's `ZoneProgress` (67) and #643's `Throw`
  (17) and `ItemThrown` (68): on `release/m7` they were its own 11 and 12 (kinds 66, 15 and 67), renumbered above
  `main`'s highest in one bump; 16 since #796 added `Interact` (18), 17 since #779 added `ItemVanished` (69), 18 since #797 added
  `SwitchChanged` (70) and `ButtonPressed` (71), 19 since #771 added `ItemChanged` (72), 20 since #770 made `Interact`'s `station` optional and added its optional `item` (18), 21 since #780 let a station refuse a use `wrong_item` (a new `Rejected` reason, no row changed), 22 since #772 added `OrderPosted` (73) and `HerbsDealt` (74), 23 since #807 added `LiftChanged` (75) and `PartNeeded` (76), 24 since #781 added `FilmLoaded` (77) and `ShotTaken` (78) and the reasons `no_film`, `no_frames_left` and `film_exposed`, 25 since #638 ended `Hello` with the return key (`key`, no new row), 26 since #773 added `GrillLoaded` (79) and `IngredientPlaced` (80), 27 since #808 added `FitChanged` (81) and `PartFitted` (82), 28 since #782 added `PhotoPrinted` (83) and `PhotoHung` (84) and the reasons `nothing_to_print` and `no_photo`, 29 since #790 added the `crouched` flag to `MoveClaim`'s and `MoveClaimReliable`'s flags (8), the avatar's (4) and `ShotTaken`'s record row's (2), no new row, 30 since #847 let a knocked-down viewer's snapshot carry its own avatar and added the `Rejected` reason `moving`, 31 since #990 added the `sneaking` flag to `MoveClaim`'s and `MoveClaimReliable`'s flags (16) and the avatar's (8), no new row, 32 since #775 raised `SettingsChanged`'s shortfalls from 32 to 64 entries, no new row, 34 since #810 raised `SettingsChanged`'s `needed_markers` and `map_markers` from 32 to 64 entries, no new row (33 was held by #1101's open PR #1109, which took its base's plus one at its rebase; a skipped number is harmless, the versions only have to match), 35 since #1101 dropped `IngredientPlaced`'s `right` (80) and added `BurgerPlated` (85) and `BurgerServed` (86). M4's protocol PRs each set it to their
  base's plus one at the rebase before the merge (the M4 ADR §4).
- **The content** (E1). `Hello.content` is the content hash: the game mode's (`ContentHash.of`, §3.3) combined with
  `FileAccess.get_sha256` of every level file the mode names (the lobby and the maps). `ContentHash` covers scripts
  and levels only by path, so without the files a designer's branch that moved a wall or a crate would join `main`
  and meet the same unexplained corrections and refused pick-ups (the host's `WorldQuery` answers from its level, the
  client walks its own). Any byte of a level counts, a light included: a false alarm costs a rebuild, a miss costs a
  playtest. An exported build, which may convert scenes, is M6's to check. The host's `server/` and each client compute
  it when they load the mode, and `Match` gets the host's with the seed. `JoinRules` compares it with the host's: another one gets `Rejected(wrong_content)` and `DisconnectPeer`. Prevents: the designer
  hosts a playtest from a branch with edited `PlayerRules`, the engineer joins from `main`, and the engineer's client
  predicts other speeds and stamina and is corrected over and over with nothing saying why. `Hello`'s `name` (#550)
  is not part of the check: the host cleans it (§3.5).
  The level files are walked (#118): every scene and resource a level reaches through
  `ResourceLoader.get_dependencies`, recursively and each once (a cycle, a piece two levels share), is hashed too,
  sorted by `res://` path, so a wall moved inside a room the map instances counts. A dependency with a known uid is
  the file the uid names, as Godot loads it, else its fallback path; a missing file is hashed as `missing`, and
  `ContentFingerprint.of` logs a warning naming it, on each walk (once per process and mode, below).
  Left out: scripts (`ContentHash` covers them by path) and Godot's generated
  files under `res://.godot/`; an imported asset counts by its source bytes and its `.import` settings. Levels that
  instance nothing hash as they did before the walk.
  The walk is computed once per process and mode (#1172): `ContentFingerprintCache` (`net/messages/`) keeps the
  value per mode hash and level list, and computes it again when a level file's modified time or size changed. The
  House's 2016 reached files took about 5.5 s per walk on the engineer's PC, and a join asked twice (`Game.join_target`,
  then its `ClientSession`), a host start twice (`HostSession.start_with`, then its own client): an 11 s freeze. Only
  the level files are stamped (the engineer asked for a recompute when a level file's modified time changes, #1169):
  stamping every reached file cost about 0.3 s, and a running
  game reads its scenes once (the editor's Run starts a new process), so a room or asset edited while a process runs
  keeps its old hash there until a level changes or the process restarts. `ContentFingerprint.of` never caches (its
  tests rewrite files and expect another value at once); the check itself is unchanged. Tests:
  `tests/unit/net/messages/content_fingerprint_cache_test.gd`, and the session tests that a host start and its own
  client, and `content_of` and a session, hash once.
- **Ids** on the wire are the content's own names (`crew`, `knife`, `match_duration`) (E5), so a content difference
  shows up as an unknown id, never as the wrong thing. The mode check (§9.1) refuses an id outside the wire's alphabet
  (3e): a change to the content API that the designer took (D1 (a) in the ADR): ids lowercase snake_case of at most 32
  characters, which every MVP id already is. The ids that reach an `id` field, and who checks each: from the content,
  checked by the mode check (3e): role ids, side ids, item and station kinds, setting ids, spawn tags, phase ids, the reject
  reasons that conditions and costs name (§9.4) and the use reasons task types list (#780); from `core/`'s constants, checked by 3d's table-against-core test:
  `RejectReasons`, `CountdownCancelledEvent`'s reasons, `StationUsable.REASONS` (#780), the `Items` causes (`put_down`, `swap`, `death`, `leave`,
  `spawn`, `thrown`, `on_station`). An id that neither covers is a bug that the encoder refuses and logs.
- **Lossless** (E6). Every float is an `f32`, as the standard build's `Vector3` and `Color` hold it, so
  decode(encode(x)) == x and the leak test compares exactly.
- **The snapshot holds avatars only** (E3). Items and bodies change only through reliable events (`ItemSpawned`,
  `ItemPickedUp`, `Swapped`, `ItemPlaced`, `PackageDelivered`, `Died`), which the client folds into its view (§4.6.1);
  a carried item follows its holder's avatar, in the hand or on the belt (the avatar's `held_item` and `belt_item`). `core/`'s snapshot keeps items and bodies for `view_of` and the unit tests (recorded with `keep_history` only; `snapshot_for`, what the host sends, builds the avatars alone, #1198); the leak
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
  longest shortfall of each kind, as host text, encodes within its cap or is refused by `WireBudget` first (#548); and a synthetic mode at
  the declared maxima is refused with the kind named.
- **Voice batching** (M5-4b, #374; protocol 8). One `VoiceBatch` per listener per poll holds every
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
    bytes) does not, and the snapshot's 16 avatars take 725 bytes of its 1024 (45 bytes each with its key, the belt
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
`circle` markers snap to the floor the host plays on: the reader reads each level in the host's space, as #66 recommended. A
level with load errors stops the host with the errors shown. Each level's scene file is read from disk once per start
(#1068): `for_mode` holds the scenes it loads (`LevelScenes`), `read_levels` reads the markers from them, and the host
releases them before `Match.new`, so they are not held for the match. (2) The session seed: 8 bytes of
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
| 4 | **Apply**, when tick t has not run yet: every queued command in queue order, stamped with t (`Match.apply`), then `Match.tick(t)`. The host's body reports head the batch: one `BodyMoved` per body in motion, in peer-id order (`HostBodies.reports`, KE14), stamped t like the rest; step 1's catch-up ticks get none (the bodies moved through the freeze, and their next report tells where). Otherwise the queue waits for the next due tick | `Match.apply` takes only the next tick to run (§3.3); a command is stamped when it is applied, so none is stamped with a tick that ran already |
| 5 | **Deliver** `take_outbox()` in order. An event is encoded once and sent to each recipient in peer-id order, skipping a peer this session disconnected (its `send` would fail with `ERR_DOES_NOT_EXIST`, expected, not an error) and a peer whose leave is pending (a reused id, "One outbox slice per call" below); a directive is carried out in its place: `RefuseJoins` and `AllowJoins` set `set_refuse_new_connections`; `LaunchBody` and `StopBody` start and free a host body (`HostBodies.launch`, `stop`, §7.1.18); `DisconnectPeer(p)` calls `disconnect_peer(p)` after everything before it was sent, the `Rejected` that explains it included, and is dropped while p's leave is pending (it answers the connection that left, not one that took its id) | The recipients are `core/`'s, never the transport's broadcast target, which also reaches peers that are not players (§5). ENet's `peer_disconnect_later` keeps what was queued (§4). A `DisconnectPeer` of the host (peer 1) would be a `core/` bug (§3.2): the host ends the session |
| 6 | **Snapshots**, when a tick ran in this step: for each present player p, `snapshot_for(p)`; empty means the phase sends none; else `{tick: t, avatars}` (§4.3) to p on LATEST, after the tick's events. Each avatar's record is encoded once per tick (#1234) and p's payload is built from the entries of the avatars its own snapshot holds, an entry reused only for a record equal by `var_to_bytes`; byte for byte `WireSchema.encode`'s (`SnapshotEncoder`; tests: `tests/unit/server/snapshot_encoder_test.gd`, `tests/integration/server/host_session_snapshot_test.gd`). The voice routing table is refreshed after every `Match.tick` call, in step 1 as here (below) | A client sees a tick's events before its snapshot (both on channel 0). Catch-up ticks send none: only the newest state counts |
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
only orders one poll's frames, so a frame lost or reordered before the host is not concealed (the speaker-to-host
limit in §6.5.1). After a freeze of the host or of the speaker, at most the newest 5 frames (100 ms; a
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
a client bug sends an intent every frame; on a host that records (a debug build, §3.3) every command, and every
`WorldQuery` answer it causes, stays in the command log for the whole session, and on any host each costs work, so one
looping client grows the host's memory and work without end.
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
(debug builds only; the M5 ADR's E47 as amended, its §3 item 11 and §4). `HostNode.counters()` gives the budgets' and the codec's counts (`over_budget`, `bad_payloads`,
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
  `WorldQuery.use_level(path)` on start and in each transition (the path of the lobby or the map,
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
  eye_height_m, crouch_height_m - crouch_eye_height_m)` (the crouched pair since #790) less it leaves the sphere at
  a pressed capsule's eye clear of the wall or ceiling (a technical
  constant, not a game number). `core/` records every answer in the command log while it records (§3.3).
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
- **The builder.** `LevelWorld` (`server/level_world.gd`: `build(path)`, `from_packed(scene, path)`,
  `from_scene(root, path)`, `errors`) builds one level's world as above, and also reports a `CollisionPolygon3D` of a
  layer-1 body, which it does not read, any other physics body on layer 1 (a `RigidBody3D`, a `CharacterBody3D`), a
  scene that cannot be instantiated and a level that gives the world no layer-1 body; a disabled shape and a body on
  other layers are left out. Only a root CSG node with `use_collision` and a `GridMap` whose used items have shapes
  count as collision. An `AnimatableBody3D` is a `StaticBody3D`: built where the scene puts it, it never moves on the
  host. `HostWorldQuery` (`server/host_world_query.gd`: `for_mode(mode)` builds every level of the mode with its capsule
  radius, `errors`; `add_level`, `use_level`; `scenes` and `release_scenes()`, below) answers as above; with no level (an empty or unknown path) it answers like
  an empty world. A floor answer keeps the point's x and z. A ray that starts inside a shape does not hit it
  (`hit_from_inside` is off: sight from inside a wall is clear, within §7.1.9's limit that the host does not check walls),
  and one that starts exactly on a surface may miss it, so callers ask from a little above the point, as `core/` does.
  `MarkerReader.read_levels` calls `use_level(path)` before reading each level.
- **One read of each scene (#1068).** `LevelScenes.load_packed(path)` (`server/levels/level_scenes.gd`) is the one
  load of a level scene on the host, counted per path in its process-wide `reads`. A `LevelScenes` holds what it loaded
  until `release()`: `for_mode` makes one (`HostWorldQuery.scenes`) and passes it to `LevelWorld.build(path, scenes)`,
  and `MarkerReader.read_levels` hands a `HostWorldQuery`'s `scenes` to `read_scene`, so the markers come from the same
  `PackedScene` (without a held reference `ResourceLoader` frees it and the second reader reads the file again: about
  1.6 s of a House start). `HostSession.start` calls `release_scenes()` once the markers are read; after it (and with
  no `scenes`) each read loads directly and holds nothing. Each reader still instantiates and frees its own copy (about
  0.1 s for the House). Tests: `tests/integration/server/` (fixture levels with a wall, a ledge and a low crate in
  `tests/fixtures/levels/`, a package put down beside the ledge through a `Match`, and 2j's flat levels;
  `level_scenes_test`, the read counts and the release in `host_world_query_test`, one read per level of `base_mode` in
  `host_session_test`).
- **The bodies (KE13, #847).** The level's world also holds the host's knocked-down bodies: `HostWorldQuery.bodies`
  (`server/host_bodies.gd`, a capsule of `capsule_radius_m` by `crouch_height_m` per body, `BODY_MODE_RIGID_LINEAR`,
  on the `downed` layer with the world mask, CCD) is handed the current level's `World3D` by `use_level`; a change to
  another level (or to none) frees every body, as the host's end does. A `World3D.new()` space steps its rigid bodies
  as the physics frames run (the probe in `tests/integration/server/host_bodies_test.gd`), so the bodies need no
  scene tree. With no world to move it (no level, or a host on a fake world with no physics: the bots' and the core
  runner's `FlatWorldQuery`), a launched body is held still where it starts and reported at rest, so it rests after
  the rest time. Tests: that suite, on `tests/fixtures/levels/body_rest_course.tscn` (§7.1.18).

#### 4.5.10 The command log and replays (E13)
The host keeps the log in memory (§3.3), only where it can write it: a release-build host, and one that skips its
replay (`HostNode.skip_replay`), keeps no command, no `WorldQuery` answer and no delivered event (`Match.recording`
off, #1191; `tests/unit/match/match_recording_test.gd`, `tests/integration/server/host_session_recording_test.gd`).
A debug-build host writes the session's
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
the exit, `Match.row_error_count()`), and `HostSession` reads the count after every `Match.apply` and `Match.tick` call.
A new one ends the session with that error shown to the host's human, before that call's slice is delivered (above).
So any row whose actions fail is fatal, a deal or not; an error outside a row, such as a `ForceRole` naming a role the
mode lacks in the same host tick, is logged and the session goes on. The bots runner already fails a scenario on any
match error (§9.7). 3f tests it with a fixture mode whose deal logs an error.

#### 4.5.12 Ending
The host quits, its own client's load fails, or the deal fails (above): `close()`, and every client sees
`host_lost` (#40).

#### 4.5.13 The host session's API (3f, #100)
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
`client/net/` holds `ClientSession`, `DecodedView` (the record, in `PeerView`'s shape) and
`ClientModel` (the fold):
- The owner calls `step(now_usec)` every frame, like `HostSession`: it polls the transport, advances a threaded load
  and sends the claim that is due. The game's `SessionNode` gives it the physics steps run as its clock (the
  physics step divided by 3), not the real clock: catch-up steps after a hitch would put 4 or more physics steps
  of travel in a claim of one client tick, past the movement check's allowance. So the client tick follows physics steps
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
  `ClientSession.content_of` and `HostSession` take it through `ContentFingerprintCache`, once per process and mode
  (§4.3, #1172).
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
snapshot's avatar flag (the own player's arrives only while it is knocked down, KE5);
`is_alive(peer)` is `life_of(peer)` living. `ClientModel.Life` is the client's own enum, so no `client/` file
names a `core/` state class. Tests: `tests/unit/client/net/client_model_test.gd` and
`client_session_claims_test.gd` (a dead client stops claiming even where every player may).

##### 4.6.1.2 The slots and the tasks (E25 for M4-5, #141)
Each `ClientModel.Item` holds its holder and whether it is
`belted`, from `ItemPickedUp` (the picked item to the picker's hand, its `belted` item to its belt), `Swapped`
(the swapper's two items change places), `ItemThrown` (in flight: no holder, not belted, `position` at its origin and
the flight's fields `thrower`, `flight_origin`, `flight_velocity`, `flight_gravity` and `flight_tick`, #644) and
`ItemPlaced` or `PackageDelivered` (resting, which ends a flight); `Item.rests()` (no holder, not flying, not fitted: #811) is what
`ItemViews`, `TargetChoice` and `PlaycheckSteps` draw and aim at, so a flying item is neither drawn nor picked where
it lay; a phase change does not end a flight (the host only pauses it). `hand_item(peer)` and
`belt_item(peer)` read them for every player, the own one included, whose avatar arrives only while it is knocked down (KE5). `TaskState`
fills `tasks` (task id to its type's id, done and total: the task screen's rows, E30); a new match clears them.
`ZoneProgress` (#650, the zone task ADR's ZE8) sets its station's `ticks`, `needed`, `counting` and `progress_tick`
(the event's host tick), and `done` once `ticks` reaches `needed`, as `PackageDelivered` sets a circle's; nothing
else changes them (no prediction). `PackageDelivered` marks its item delivered and sets its station `done` only when no
undelivered item names that station (`Item.station`, from `ItemSpawned`): a drop-off of Delivery by meaning that takes
two items stays open after the first (DE7, #828); a colour circle takes one package, so it is done at once as before. `ItemVanished` (#779) removes its item from `items`, so its id may name a new item's `ItemSpawned` later. `ItemChanged` (#771) gives a known item its new `kind` where it is (`ItemViews` rebuilds a view whose kind differs), and an `ItemPickedUp` whose `belted` names the item itself puts it straight on the belt, the hand item still held (CE20, CE21). `SwitchChanged` (#797) sets its station's `on` (a switch is off until its first
one) and `ButtonPressed` counts its station's `presses`; neither keeps a peer (they name none). Tests:
`client_model_test.gd`.

#### 4.6.2 Bots (`tests/harness/`, 3h)
A bot is a `ClientSession`, a scenario script and an honest mover. The script is the
core runner's (2j): on `main` `ScenarioRunner` holds both the §9.7 steps (`_run_step` and a method per step) and its
stand-in for `server/` (`_queue`, `_deliver`, `_carry_out`), and `ScenarioBot.receive` takes `MatchEvent` objects. 3h
splits the steps from the stand-in and has `ScenarioBot` learn from (name, fields), which the core runner takes from
`to_dict()` and a network bot from its decoded view, so both runners play the same steps the same way, and
`ScenarioInvariants` checks §5 in both (in the bots runner per `Match` call, through `HostSession`'s observer,
§4.5). The mover moves its position toward the target at the walk or sprint speed of the mode's `PlayerRules` on
the flat levels (2j), claims every client tick, counts its jumps
and adopts every `Correction`; a dead bot claims nothing, and a `WalkTo` of a dead bot fails (M4-2), as one of a knocked-down bot does (it holds still, #728 KE4). Its fold of a snapshot (`ScenarioBot.see`) skips its own avatar, which a knocked-down bot's snapshot carries (KE5, #847): it knows where it is. It acknowledges `LoadMatch` as §9.7 says, without loading the scene: a bot needs no geometry of its own.
A scenario's forced roles go as the core runner sends them, one `ForceRole` per bot right after the joins, but on the
wire: bot 1, the host's own client (peer 1), sends the debug kind (§4.3, E17) naming each bot's peer id, so the bots
run in debug builds only. **Bot numbers to peer ids:** a scenario names players by bot number (§9.7), and nothing on
the wire tells bot 1 which peer is bot i: a name is no id (a wire bot's `Hello` asks for none, so the host names it
`Player<n>`, §3.5; the core runner's bots ask for no name either, so every bot is `Player<n>`), and over ENet the
clients choose their ids (§4.5). So each runner owns a map from bot number to peer id, which `peer_of`, `matches` and
`ScenarioInvariants` (its `never` check) take in place of today's static `ScenarioRunner.peer_of` (3h). The core
runner keeps 1 and 1000 + i; the one-process bots runner fills the map as it connects each bot's loopback client
(`LoopbackHub` hands out the ids). Over ENet each instance writes its peer ids to `tools/out/bots/<scenario>/peer-<i>`
on `connected`, one id per line, one line per connection (a bot that left and returned has a line for each); bot 1
waits for all of them (up to the scenario's time limit), writes the whole map to `peers` there, and only then sends
the `ForceRole`s; every other bot reads `peers` before its first step. Since #950 a remote bot's clock (its
scenario's times and time limit) and its first join start once bot 1 wrote `host-up` there (it serves: its session
started, over WebRTC its room is up), or `HOST_UP_WAIT_S` (30 s) after its own start at the latest (bot 1's own clock starts at its first step, after its start, and each join's retry clock when its client is made): the host's start
takes seconds, and clocks started with the processes ran the scenario's spacing out meanwhile
(`leave_and_return_keep_the_number`'s bot 3 joined before bot 2 in 4 runs of 4 on the engineer's PC). Learning ids
out of band is harmless: peer ids are public in the roster. A bot that joins later gets its `ForceRole` once its id
is known, after it connected (§9.4). Its voice is synthetic: frames of varying length holding its peer id and a counter, so a
listener also checks that the relay changed no frame and named the right speaker. **Since M5-1 (#215)** it sends
like a player's gate (the M5 ADR §5): one frame per 20 ms of the runner's clock (50 a second, E38), each 30 to 60 B
with the peer id and the counter first (`LeakCheck.voice_frame`), in talk spurts by default (`BotVoice`: a spurt of
0.8 to 1.7 s, then a silence of 0.3 to 0.9 s, both lengths and the start shifted per bot; placeholders, "not a
decision"), so every scenario starts and stops streams; continuously when the scenario's `voice` says so (§9.7),
the load M5-4's `voice_load` measures. After a hitch of the clock at most the newest 5 frames go out at once (the
relay's newest 5 per poll). It talks in every phase and life state, as a modified client may: the host must route
none of it where nobody hears it (§6), which the leak test checks. The perf harness (§9.7) talks the same way, so
its voice numbers from before M5-1 (20 frames a second of 8 to 14 B) do not compare with later ones.
In `tests/harness/`: `ScenarioPlay` holds the steps and the runner's hooks (send, connect,
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
  allowed, or 0.15 m crawled (the crawl went with #728) against 0.056 m (one tick) and 0.111 m (two), and the host rightly corrected an
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
  `joins_closed` (refusing new connections) or `connect_failed` (an id in use) within a poll or two (§4
  "Joining") and after it with `host_lost` (a rejected `Hello`), and all stay failures. A join `_join_again` does
  not join again is lost for good (`NetPlay._lost_join`, #483): its
  bot's step fails at once, naming the reason it ended and those of its earlier joins; a remote bot then writes its
  view file with that line at once, and the host reports it as that bot's failure when its own time limit ends
  the run (it reads the view files only then). A runner that
  never calls `_join_again` (`PerfRun`) joins nobody again, so every lost join of it fails at once. Since #318 both
  live in `NetPlay` (`_lobby_full`, `_join_again`; since #509 the rule of when a join is tried again, and how
  often, is `JoinRetry`'s, one per joiner, which the watchers of §4.6.4 share) and the chaos run's ENet
  variant and the playcheck bots use them too (below and §4.7's `playcheck`): `_lobby_full` asks of one bot that
  every other player that joins at the start has a known peer id and is in that bot's decoded lobby (its
  `Welcome`'s positions or a `PlayerJoined`); peer ids alone, which `connected` gives before the `Hello` is
  admitted, were the weaker gate those two runners had. `_join_again` judges a join on `_join_clock_usec()`,
  the runner's clock, the real one in a runner on a simulated clock (the chaos run): `JOIN_TIMEOUT_MS` is real
  time. A `BotsEnet` remote bot's join starts once its client is made (#950): a process's first `ClientSession` of a
  mode computes its `ContentFingerprint` as it is made (5.5 s on the engineer's PC since the House assets; later
  ones take it from `ContentFingerprintCache`, #1172), and a join started before that ran out the signalling's 5 s cap meanwhile, every time (`bots_enet_test.gd`). Tests: `tests/scenarios/chaos_enet_start_test.gd` and `tests/scenarios/playcheck_bots_test.gd`, each the
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
  (2026-10-03). #1197's two House scenarios add about 10 s to the one-process run (19 scenarios: 130 s on a busy
  machine, 2026-10-21), and #1209's `bots_carry_items_between_the_house_storeys` about 20 s (64 s simulated; the
  20 scenarios: 133.5 s on a busy machine, 2026-10-21), which ends, after a run of every scenario, with the task events' coverage
  (`BOTS coverage: passed`, §4.6.4.1).
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
  `Correction` after each placement of a player, after its knockdown (M4-2) and after its revive (KE6), and the bot
  expects exactly that one; a death sends none.

#### 4.6.4 The information-leak test (§5)
Compares what each bot b decoded with `view_of(b)`:
- events: b's decoded events are `view_of(b)`'s, in order, as (name, `to_dict()`); for a bot that left, a prefix;
  a bot that left and joined again (a `Join` after its `Leave`, §9.7; #639) has one view per connection, each
  checked against `view_of` of that connection's peer id: every earlier one as a prefix, labelled
  "bot N (connection i)" (`NetPlay.earlier_views`; over ENet `ViewFile`'s `earlier` lives), the last one as "bot N";
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
  Before that, a watcher whose join was lost the way a bot's is joined again (§4.6.2's `JoinRetry`: unanswered over
  ENet, or `no_room` / `service_unreachable`, the signalling's 5 s connect cap, over WebRTC) joins again on a new
  transport, `BotWatcher.MAX_JOINS` (3) joins at most (`NetPlay._watcher_join_again`, run by `BotsRunner` and so the
  chaos run, and by `BotsEnet`'s host; #509): under load a lost watcher join failed a run whose leak test never
  ran on it. No bot (nor the chaos run's hostile peers) acts until each watcher connected or its join is lost for
  good (`NetPlay._watchers_settled`, checked in `play_frame`): the match's Loading refuses new joins (over WebRTC
  the room closes), so with bots that ready at once the countdown's 5 s closed joins before a watcher lost to the
  cap joined again. The hold is what bounds the watchers' joins, not the run's time limit: 3 joins of up to 5.5 s
  each. A run out of time names the watchers it still waited for (`_lobby_wait`). The host's room
  (`BotsRunner.EXTRA_CLIENTS`) holds every join the watchers may make plus one: an unanswered ENet join can hold a
  slot until ENet's own timeout. Its checks are the same on the join that connected; one that never connected
  names the reasons its earlier joins ended too ("...; earlier joins ended service_unreachable,
  service_unreachable"). Tests: `tests/scenarios/watcher_join_test.gd` (bots that ready at once; a lurker lost to
  the cap and a refused bot unanswered, each after 5 s, join again and pass; `MAX_JOINS` joins and then every
  reason; a refusal or `host_unreachable` not joined again).
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
  that match's dissidents only; no bot decodes a dead player's avatar; a bot decodes its own avatar exactly when the host's state had it knocked down at that tick (the own-avatar check, KE5, #847, from the life state `record_tick` saw, never from `Snapshots.for_peer`); no bot decodes a downed or dead speaker's voice frame, a
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
  present for a whole round decode the same task events; no decoded message has a field that names a seed, nor one
  that holds a return key (each bot's `ScenarioBot.key_of` and every key of the host's `numbers`; and the key of the bot that does not exist, which a hostile Hello may carry; `LeakCheck.set_keys`
  and `ScenarioInvariants.keys`, #639: a key planted in `PlayerJoined`'s name failed both, then reverted); a peer
  that is not a player decodes at most the `Rejected`s of its own intents (a returning bot's refused try too: a snapshot, voice or another event it decodes fails the run, #639); one that sends nothing (the lurker)
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
`ZoneTask` counted in the zone) on the greybox's three zone scenarios, which failed on `ScenarioInvariants` alone
(and, with `ZoneProgress` out of its `TASK_EVENTS`, on `LeakCheck`); reverted. **#804 (Generator G9)** took the
greybox's zones and those scenarios away (GD13 (b) of the [Generator ADR](decisions/2026-10-10-generator-task.md):
the House is not played by bots, §9.7) and planted the same leak once on their successor with no bot,
`tests/integration/levels/house_zone_test.gd` (the House in the host's real world, `ScenarioInvariants` per call and
per tick, §9.7): its three tests failed on `ScenarioInvariants` (`ZoneProgress reached [1003], not every present
player [1, 1002, 1003]`); reverted.
**#779 (cooking C10)** added `ItemVanished` to both lists; no scenario plays a vanishing item kind yet (the base mode has none), so its plant waits for the first that does.
**#771 (cooking C2)** added `ItemChanged` to both lists; its plant waits for the scenarios that play Cooking (CE22). `ScenarioBot._learn` folds a pick-up straight onto the belt (`belted` the item itself: the two-handed item stays `held`), pinned by `scenario_runner_test.gd`'s `test_a_take_straight_onto_the_belt_keeps_the_hand_item_held`, seen failing without the fold.
**#797 (Generator G2)** added `SwitchChanged` and `ButtonPressed` to both `TASK_EVENTS` lists; no bot plays the
Generator (the House is not played by bots, §9.7), so no leak plant was made for it then. Beside it stand
`generator_check_test` (both lists name every event the Generator emits), `generator_rules_test` (every present
player, downed and dead included, receives the same `SwitchChanged`, `ButtonPressed` and `ZoneProgress`, so an
audience-narrowing change fails there) and the wire test `host_session_generator_test` (each client's decoded events
equal `view_of`). **#802 (Generator G7)** planted it on the House with no bot,
`tests/integration/levels/house_generator_test.gd` (the House in the host's real world, `ScenarioInvariants` per call
and per tick, §9.7): `SwitchChangedEvent.audience()` as `Audience.only` of the player who switched; the two tests that
switch failed on `ScenarioInvariants` (`SwitchChanged reached [1003], not every present player [1, 1002, 1003]`);
reverted. `LeakCheck` checks the same events once bots play a map with the Generator.
**#772 (cooking C3)** added `OrderPosted` and `HerbsDealt` to both `TASK_EVENTS` lists; no bot plays Cooking (CE22,
§9.7), so their plant waits for the House's scenarios. `cooking_check_test` holds both lists to every event
`Cooking.emits()` names, and `cooking_events_name_no_player_test` keeps both events free of a player field.
**#807 (car repair R3)** added `LiftChanged` and `PartNeeded` to both `TASK_EVENTS` lists; no bot plays car repair
(§9.7), so its leak plant is R8's (on the House). What stands in: `car_repair_lift_test` (every present player
receives the same `LiftChanged`), `car_repair_events_name_no_player_test` and `car_repair_role_swap_test` (planted "the
panel refuses dissidents", both failed, reverted).
**#781 (photo P2)** added `FilmLoaded` and `ShotTaken` to both `TASK_EVENTS` lists (`photo_check_test` holds that
both name every event `PhotoTask.emits()` returns) and the record invariant (the photo ADR §8): `ShotTaken` is the
first event to carry other players' avatar rows, and `view_of` reads the same record, so the leak test alone would pass
a record-building bug. `ScenarioInvariants.record_problems`, written apart from `PhotoTask`'s builder, checks every
row: a present peer alive or downed at the shot, named once, near its accepted position, and within `range_m` + 2 m
of the lens (the camera's position raised by the eye height), each checker with its own slack (below).
`LeakCheck.check_bot` runs it on each decoded `ShotTaken` (the camera from the decoded `StationPlaced`, the life states and positions `record_tick`
saw); it sees positions only at the ends of ticks, so its slack is one movement claim's longest step (`record_step`:
`MAX_TICK_CREDIT` plus `PUSH_TICKS` ticks of sprinting, plus the slack) horizontally of the position at the end of
the tick before or of the shot's tick. `ScenarioInvariants.check_event` runs it on each emitted `ShotTaken` in the
shot's own `Match` call, so it takes the positions now with no step (#788: with the base mode's sprint the step was
some 73 m, more than the House, and the record plant passed). No bot plays the photo task (PE18): its unit cases
(`tests/scenarios/record_invariant_test.gd`: a dead player's row, a row beyond the bound, a row a step from every
accepted position, a peer named twice, each caught; `record_wiring_test.gd`: a row a metre off its player now, a
metre beyond the range, each seen failing on the stepped check) stand in. **#788 (photo P9)** planted both on the
House with no bot, `tests/integration/levels/house_photo_test.gd` (§9.7): `ShotTakenEvent.audience()` as
`Audience.only` of the shooter failed the two tests that shoot on `ScenarioInvariants` (`ShotTaken reached [1002],
not every present player [1, 1002, 1003]`); the record builder without its distance test (a row for every living
present player outside the camera's cylinder, however far) failed both on the record invariant (`a ShotTaken row puts
peer 1003 at (24.0, 0.0, 55.0), 45.311 m from the lens ..., beyond 12.001 m`), after the step was taken out of
`ScenarioInvariants` (with it, only the test's own record assertion failed); each reverted.
**#773 (cooking C4)** added `GrillLoaded` and `IngredientPlaced` to both `TASK_EVENTS` lists; no bot plays Cooking
(CE22, §9.7), so their plant waits for the House's (C8). What stands in: `cooking_events_name_no_player_test` (neither
names a player) and `cooking_role_swap_test` (planted "a place refuses dissidents", both failed, reverted).
**#777 (cooking C8)** planted it on the House with no bot, `tests/integration/levels/house_cooking_test.gd` (§9.7):
`IngredientPlacedEvent.audience()` as `Audience.only(1)` failed the burger's test on `ScenarioInvariants`
(`IngredientPlaced reached [1], not every present player [1, 1002, 1003]`); reverted. The other cooking events' plants
wait for the bots that play Cooking (CE22): the House tests run `ScenarioInvariants` over every one they emit.
**#1101 (cooking, checked when served)** added `BurgerPlated` and `BurgerServed` to both `TASK_EVENTS` lists; what
stands in for a bot: `cooking_serve_test`'s "no event tells right or wrong before the serve" (planted: a `right` field
back in `IngredientPlaced`'s dict, failed, reverted) and `cooking_events_name_no_player_test`.
**#808 (car repair R4)** added `FitChanged` and `PartFitted` to both `TASK_EVENTS` lists; no bot plays the House
(§9.7), so their plant waits for its bots. What stands in: `car_repair_events_name_no_player_test` (`PartFitted` names
no player; `FitChanged` names only the fitter, RD15 (a)).
**#812 (car repair R8)** planted it on the House with no bot, `tests/integration/levels/house_car_repair_match_test.gd`
(§9.7): `FitChangedEvent.audience()` as `Audience.only(fitter)` failed the full repair's and the drop's tests on
`ScenarioInvariants` (`FitChanged reached [1003], not every present player [1, 1002, 1003, 1004]`), and the drop's own
check of every player's `FitChanged` stream; reverted. The other car repair events' plants wait for the bots that play
the House: its tests run `ScenarioInvariants` over every one they emit.
**#782 (photo P3)** added `PhotoPrinted` and `PhotoHung` to both `TASK_EVENTS` lists (`photo_check_test` holds that
both name every event `PhotoTask.emits()` returns); no bot plays the photo task (PE18), so their plant waited for the
House's: #788 (P9) declared `FilmLoaded`, `PhotoPrinted` and `PhotoHung` to peer 1 alone, and `house_photo_test`
failed on `ScenarioInvariants` (`PhotoPrinted reached [1], not every present player [1, 1002, 1003]`, and the same
for the other two); reverted. Beside it: `photo_role_swap_test` over the whole chain (planted "a dissident's hang counts
nothing", both failed, reverted) and `photo_check_test` (neither `ShotTaken` nor `PhotoPrinted` says whether a person counted).
**#1197 (foundation audit #877, e4)** made the bots play the House's station tasks (§9.7: one storey per scenario), so
`check_tasks` and `ScenarioInvariants` see the Generator's, Cooking's, the car repair's and the photo task's events
over the wire, and added a coverage check so that cannot silently drop: after a run of every scenario (`bots` with no
names; `BotsRunner.task_events_seen`, `bots_main` prints `BOTS coverage: passed` or `FAILED` with a line each)
`LeakCheck.check_coverage` fails a task event no bot decoded, unless `LeakCheck.UNREACHED` lists it with why, and
fails an UNREACHED event some bot decoded (take it off the list) or that is no task event. #1197 listed nine (the
chains across storeys, and `ItemVanished`); **#1209** reached them all (the bots change storey over the House's
stairs, §9.7), so the list is empty; `bots_runner_test` checks the list's two failures with a list of its own. Seen failing: `check_coverage` planted to skip the missing branch failed
`bots_runner_test`'s coverage case; with the basement scenario taken out, `bots` printed `BOTS 18 of 18 scenarios
passed`, then `BOTS coverage: FAILED` (`no bot decoded the task event SwitchChanged in any scenario`, the same for
`ButtonPressed`) and exited 1; both reverted.
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

**#639** planted the joiner's return key as `PlayerJoined`'s name in `JoinRules.hello`: `bots
late_join_cancels_the_countdown` failed on `ScenarioInvariants` (`invariant at tick 1: PlayerJoined holds a return
key`), and with that check switched off on `LeakCheck` for each bot (`decoded PlayerJoined holding a return key`);
then passed with the plant reverted. `leave_and_return_test.gd` keeps a decoded key as a unit case, and a plant in
the earlier connection's view of a bot that returned fails naming "bot 2 (connection 1)".

The own-avatar check (KE5, 728b, #847), in `LeakCheck` and `ScenarioInvariants` (`own_avatar_problem`, from the life
state): seen failing on a planted own avatar of a living bot and on a missing own avatar of a knocked-down one
(`bots_runner_test.gd`'s `test_an_own_avatar_of_a_living_bot_or_none_of_a_knocked_down_one_is_a_leak`, and
`tests/scenarios/body_motion_invariants_test.gd`); and run through a body in motion on every
tick (that suite: no scenario moves a body, KE12).

#### 4.6.5 Chaos bots
(#188; item 6 of the [AI productivity ADR](decisions/2026-10-02-ai-productivity-baseline-and-pipeline-v2.md),
P11): invariant 1 (the host validates every intent) against what a modified client can send, in
`tests/harness/chaos/`. `ChaosRun` is a `BotsRunner` whose match (`ChaosScenario`, built in code: four bots, the
shipped base mode's default draw, one package, since #804 (from #649 to #804 also one zone on the greybox); bot 4
walks to `ChaosScenario.STAND_AT`, where that zone stood, and freezes, bot 1 then knocks it down, bot 2 delivers and
bot 3 waits for the end) carries two chaos peers that are never peer 1: a
**hostile but valid** player, bot 4's own connection (`ChaosHostile`), which plays the whole round as living,
downed and (`--long`) dead, and stays under the malformed limit; and a **malformed** peer (`ChaosMalformed`)
that never sends `Hello`, so it is in no rule and invisible to the players (§3.2), until the host disconnects
it. Each peer's inputs come from a seeded `RandomNumberGenerator`; one rule per input class, each from the
sections named:
1. malformed frames (too short, too large, an unknown kind, random bytes behind one, the wrong direction or lane,
   a payload over its kind's cap, truncated, trailing bytes) and payloads the codec rejects (a bool not 0 or 1,
   item 0xFFFF, peer 0, a NaN or infinite float, unknown flag bits, a capital in an id, bytes after the last
   field, an empty Opus frame), and `ForceRole` (kind 24) and `ForceClock` (kind 25) from a peer other than 1: counted under the reason
   `ChaosFrames` names (§4 Transport, §4.3, §4.4, E17), with no reply; no role changes (the forced roles hold, read after the last call in the round or End: End's
   return to the lobby 3 s later, which a slow network run outlasts, resets every role, #212);
2. a burst past the reliable-intents bucket (130 refused intents in one frame) and past the voice bucket
   (530 frames): `OVER_BUDGET`, no reply, no disconnect (§4.5);
3. the malformed peer: disconnected at the 50th malformed message within 10 s, with exactly one log line naming
   it (`ChaosLog`, a `Logger`), what it sent after it in that poll counted `UNKNOWN_PEER` (§4, §4.5);
4. well-formed intents the phase or the rules refuse (§3.1, §3.2, §4.1; never one a race could turn into an
   action): exactly `Rejected(seq, reason)` to the sender, nothing else emitted, no reject counted, the reason
   `ChaosOracle`'s, written from §3.2's table, not from the code: `not_accepted` for the wrong phase or life
   state, `unchanged`, `unavailable`, `empty_hand`, `nothing_to_do`, `nothing_to_swap`, `not_channeling`,
   `not_downed`, `moving` (a downed target still in motion, #847), `out_of_reach` (a `PickUp` of an item resting more than 8 m away, half of them right after a
   claim that teleports the hostile next to it: reach is measured from the host's last accepted position, §7.1,
   §9.4), and no reply to a `LoadAck` of another match;
5. hostile `MoveClaim`s (a teleport, a speed over the cap, a client tick past the credit, jumps 65535 where it
   stands, another epoch, a client tick that does not rise; NaN and infinity are class 1 on the wire), each with
   the per-tick masks (protocol v7, #155) of a client that walked every tick (`sprint_ticks` 0, `moved_ticks` all
   ones: `ChaosFrames.HONEST_MOVED_TICKS`), so the shape alone calls for the answer (a mask outside the u32 the
   encoder refuses, and core corrects; bits older than the covered ticks count for nothing: both
   `movement_rule_masks_test.gd`, not chaos shapes): a `Correction` (its epoch plus one, the old position) to
   the sender alone when the phase takes its claims, the epoch is its own and the sender is not knocked down, else
   nothing (§7.1, E15); to a knocked-down sender none for any claim, its walking ones included (#728 KE4: the host
   takes only its look); the position never changes; never `Rejected`. A repeated client tick right after a placement is the first claim of
   a new baseline, checked as one tick and corrected: either answer passes. **The freeze** (#649, the zone task
   ADR's freeze row, ZE10): bot 4 stands at `STAND_AT` a second (in the zone until #804), then its client sends no claim for 190 ticks while
   it polls on (`ChaosRun.claim_clients` holds them while `ChaosScenario.FREEZE` is its step, in every run), and
   then one claim spends the stored credit to walk about 39 m away. The freeze is `ChaosScenario.FREEZE_TICKS`,
   `MovementRule.MAX_TICK_CREDIT` less `PUSH_TICKS`: that claim also covers a tick when the freeze starts between
   two client ticks and the claims a network lost before it. At 200 it covered 201 over WebRTC (#674, seed 7, 4 of
   6 runs), was corrected, and bot 4 stood in the zone on the host all round while its script, which adopts no
   `Correction` outside a placement (each is taken for a chaos claim's), claimed from 39 m off and was corrected
   every tick; `chaos_test.gd` pins the margin. Since #693 the host's answer to each of bot 4's own claims (no
   chaos tag: `ChaosFrames.claim_shape` is -1) is checked on the host over every transport
   (`ChaosHonestClaims`): a `Correction` of one fails the run, naming the seed (`chaos seed 7: the host corrected
   an honest claim of bot 4 ... (and N more)`: one line, the first correction and the count of the rest), and so
   does a run in which the movement rule accepted none (the summary line counts those); a placement's `Correction`
   comes with another call. Until #804 `ChaosRun` also checked on the host's state that the zone gained at most
   `ZoneTask.STALE_TICKS` (10) after bot 4's last accepted claim (planted "stale claims count", it failed); the
   greybox's zones gone, that check lives in `tests/integration/server/host_session_zone_test.gd` (§4.6.5.3), and
   the chaos run's zone code (`ChaosZones`, its quiet rule near a zone, the freeze check) went with them.
   The hostile sends no claim in the round until that walk away, nor while its host position or a nonzero
   velocity has not caught up with its bot's: a `Correction` or a `LATEST` claim superseding its
   walk would move it, and change what every honest bot sees, from the baseline's (seed 3 caught the last).
   Since #1194 it sends none in the pregame either (`ChaosRun.QUIET_PHASES`): the pregame takes no claim
   (E15), but one sent in its last frames reached the host in the round, before bot 4's first claim of its
   epoch (WebRTC seed 188001). Its `Correction` left the new epoch without a client-tick baseline, bot 4's
   claims in flight in the old one were stale, and its first claim of the new one, a round trip into the
   walk to `STAND_AT` it began on the round's start, counted one tick (the first of a client-tick baseline,
   §7.1): corrected, 1.05 m off its spawn, and 74 times after (its script adopts no `Correction`). The host
   was right (an honest client adopts it); `chaos_test.gd` pins both the race on a `Match` and the quiet
   pregame. Item 5's "else nothing" for the pregame is thus no longer checked over the wire by the chaos
   runs (the loading phase and the End still are); `host_session_end_to_end_test.gd`, the `ChaosOracle`
   `pregame` row and the `Match`-level assertion in `chaos_test.gd` cover it.
   Over every transport (#674), `ChaosRun` fails a run in which no hostile claim went out while its client knew it
   alive in the round (`ChaosHostile.round_alive_claims`, in each passed run's summary line; 12 to 24 over seeds
   188001 to 188010; a plant that kept the hostile quiet all round failed), so a quiet rule gone wrong cannot
   silence class 5 unseen; the failure names the claims each quiet rule held back (`ChaosRun.quiet_held`: the
   200-tick freeze's WebRTC seed 7 read "before its walk away" 44, its host position behind its bot's 17).
   The run does not play the freeze with refused claims (a far claim, a past-credit tick or another epoch sent
   during the freeze, hoping each `Correction` keeps the claim young): `MovementRule.claim_age` reads only an
   accepted claim, covered by `movement_rule_claim_age_test.gd` (a refused claim does not renew it), not end to
   end;
6. repeated, replayed and out-of-order seqs (and `Hello`'s seq 0 from a player): every copy gets its own rule
   answer echoing the seq it carried (4 checks each copy);
7. no honest bot decodes the malformed peer's voice, nor the hostile's while it is downed or dead or in Loading,
   Pregame or End (the mode's phases that hear within 0 m, checked against a hand-written list; §6; the leak
   test's voice checks run too);
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
step is `--seed 188001`, the short match (the round ends while bot 4 is downed): three runs of 900 frames (the 3 s pregame, #213) in
about 4 s, 6 s with Godot's start; 20 runs in a row passed (2026-10-02). On protocol v7 (#227, 2026-10-03),
`--seed 1 --runs 8`, `--long --seed 5` and `--enet --seed 7` passed. With the zone and bot 4's freeze (#649,
2026-10-09) a seed's three runs are 1830 frames (30.5 s simulated, about 11 s); `--seed 1 --runs 10`, `--seed
188001`, `--long --seed 5`, `--enet --seed 7` and `--transport webrtc --seed 188001` passed. With the 190-tick
freeze and the claim coverage check over every transport (#674, 2026-10-10) a seed's runs are 1800 frames (30.0 s
simulated); `--seed 188001 --runs 10`, `--seed 1 --runs 10` and `--long --seed 5 --runs 2` passed (12 to 24 hostile
claims alive in the round), `--enet` seeds 7, 188001 and 3 (12 to 19) and `--transport webrtc` seed 7 three times
(18, 19, 18; with the 200-tick freeze it sent none in 4 of 6 runs) and seeds 188001, 1, 2 and 3 (12 to 19). With
the honest-claim check (#693, 2026-10-10) `--seed 188001 --runs 10`, `--seed 1 --runs 10`, `--long --seed 5 --runs
2`, `--enet --seed 7` and `--transport webrtc` seeds 188001, 7, 1, 2 and 3 passed (222 to 478 honest claims of bot 4
each accepted without a `Correction`); a plant holding bot 4's claims 2 s past its freeze (its walk away past the
credit) failed on that check alone (`chaos seed 188001: the host corrected an honest claim of bot 4`; reverted). With
no zone (#804, 2026-10-13: the shipped base mode, bot 4 frozen at `STAND_AT`, bot 1 waiting a fixed
`AWAY_WAIT_S` from the round's start) `--seed 188001` and `--seed 188002 --long --transport webrtc` passed. The
night job `chaos` runs ten seeds of `--long` from a random one, then one over ENet (§15 of AGENT_WORKFLOW).

##### 4.6.5.2 Proven (2026-10-02, seed 188001, each plant reverted)
`HostSession` taking no budget failed on the
replayed counts (`OVER_BUDGET` 70 expected for the hostile, none counted) and on the oracle's command count
(319 checked, 283 within budget); `Match` answering a refused `MoveClaim` with `Rejected` failed class 5 (the
malformed peer's claim answered `not_accepted`); debug kinds taken from every peer failed on the roles (bot 4
forced crew, now a dissident) and on the `BAD_PAYLOAD` counts; `InReach` always passing (`--long`) failed
class 4 (the hostile picked up a knife resting far away); `Throw` taken in Round from the living by
`ChaosOracle.ACCEPTS` failed class 4 naming Throw (seed 188001, #644). Tests: `tests/unit/net/transport/
chaos_frames_test.gd` (every shape over a `LoopbackHub` is its reject or fails the codec),
`tests/integration/server/host_session_chaos_test.gd` (what each peer receives for replayed seqs, a hostile
claim and a burst over budget), `tests/scenarios/chaos_test.gd` (the oracle, the replay, the exemption, a
corrected honest claim of bot 4 (#693), no
`ForceRole` for a bot 2 without a peer id), `tests/scenarios/chaos_enet_start_test.gd` (the start over the network:
a join lost for good fails at once naming its reason, a join that found no room joins again without starting play,
`MAX_JOINS`).

##### 4.6.5.3 Covered wire rows (M5 extends them with every new intent or row)
The C→H kinds 1 to 13, 15 to 18 and 112 (kind 14, `MoveClaimReliable`, has no chaos shape:
`host_session_claim_twin_test` covers its teleport, far-future, stale and wrong-phase twins, #429), the debug kinds 24
and 25 (`ForceRole`, `ForceClock`), the H→C kinds 32 (`Rejected`), 70 and 71 (#797: `SwitchChanged`,
`ButtonPressed`), 75 and 76 (#807: `LiftChanged`, `PartNeeded`), 77 and 78 (#781: `FilmLoaded`, `ShotTaken`), 79 and 80 (#773: `GrillLoaded`, `IngredientPlaced`), 81 and 82 (#808: `FitChanged`, `PartFitted`), 83 and 84 (#782: `PhotoPrinted`, `PhotoHung`), 85 and 86 (#1101: `BurgerPlated`, `BurgerServed`) sent the wrong way, one drawn
per packet, and unassigned kinds (0, 19, 20, 23, 26, 31, 87, 88,
95, 97, 111,
113, 127, 128, 200, 255; `chaos_frames_test` fails while a row has one; 73 became 75 when #772 took 73 and 74, 75 became 77 when #807 took 75 and 76, 77 became 79 when #781 took 77 and 78, 79 became 81 when #773 took 79 and 80, 81 became 83 when #808 took 81 and 82, 83 became 85 when #782 took 83 and 84, 85 became 87 when #1101 took 85 and 86). Kind 15, `NextStage` (#599): the hostile
sends it in every phase and the oracle answers `not_accepted` because no phase of `ACCEPTS` lists it (the base mode
lists it in no phase, peer 1 included); `ChaosOracle.NEVER_ACCEPTED` records that decision, and `chaos_test` pins
that every intent is in a phase of `ACCEPTS` or in that list;
its malformed shapes are `NEXT_STAGE_NO_SEQ` (0 to 3 bytes: NetFrame takes it, the codec does not, `BAD_PAYLOAD`)
and `NEXT_STAGE_TRAILING` (its seq and 1 to 4 bytes more: over the cap of 4, so NetFrame's `PAYLOAD_TOO_LARGE`
before the codec could see a trailing byte). Kind 17, `Throw`: its facing from `ChaosFrames.THROW_FACINGS` (a unit
vector, zero, a 1e-30 vector and a 1e38 vector); since the base mode's rule (#646) Round takes it from the living, so
the hostile's `Throw` there, with the empty hand its bot always has, is refused `empty_hand` (`HoldsItem` comes before
`OverFloor`), and `not_accepted` in every other phase and from the downed and the dead; non-finite facings are the
codec's, class 1, #644. Kind 1, `MoveClaim`: knocked down, half the hostile's claims are `ChaosFrames.Claim.WALK`
(a step of `WALK_M`, 0.1 m, less than a walk covers in one client tick, #728), and its claims carry a zero facing so
the look the host takes of a knocked-down claim (KE4) changes nothing the honest bots decode; class 5 expects no
`Correction` for any of them. A new intent gets its refusals in
`ChaosHostile._refused` and `ChaosOracle` (its allowlist row and reasons), a new wire type its malformed shape
in `ChaosFrames`; a change of §3.2's table changes `ChaosOracle.ACCEPTS` with it. Since #214 the hostile's
`ChangeSettings` also carries a `lobby_name`: a non-host rename is caught by the oracle's `not_accepted` check of
`ChangeSettings` (`From.HOST`), and `ChaosRun` also fails a run that ends with the lobby named (only the host may
name it, and the host's bot never does), a backstop not yet seen failing.
Kind 16, `SetProfile` (#551): the oracle's lobby row (`From.PLAYER`); the hostile sends its own name and colour in any
phase (`unchanged` in the lobby, `not_accepted` elsewhere: no race can make it a change, since nobody else renames
it), and "Hacked" with the next colour only while its client is in loading or pregame, where the host cannot be
in the lobby (not in the round: its last frames could meet the lobby after End); its malformed shapes `SET_PROFILE_NO_COLOUR`, `SET_PROFILE_TRAILING` and
`SET_PROFILE_BAD_NAME` (not UTF-8) are each under the cap, so the codec refuses them (`BAD_PAYLOAD`). `ChaosRun`
fails a run that ends with a player named "Hacked" or two players sharing a colour. Seen failing: with
`Match._accepts` taking `SetProfile` everywhere, seeds 5510 and 5511 failed on the countdown's `SetProfile`.
Kind 18, `Interact` (#796): since #800 (the Generator's G5) Round of `ACCEPTS` lists it from the living, as the base mode
does, so outside Round, or downed or dead, the hostile's `Interact` is refused `not_accepted`; in Round, alive, a target that
names nothing, or a station or item with no `Interact` rule where the host looks for one (a station: its kind's actions, the sender's role's and the mode's; an item: its kind's `target_actions`; every one on the greybox, which deals no
Generator), is `nothing_to_do` (`ChaosOracle._interact`), and only a target with the rule answers `?`. Since
#770 its `station` and `item` are both optional (0xFFFF, none), so the hostile sends four shapes
(`ChaosHostile._interact_args`): a station id from 0 to 9, an item it knows or none, both, and neither; and no field
value is malformed any more: its malformed shapes are `INTERACT_TRUNCATED` (the seq and 0 to 3 of the 4 field bytes:
the codec's `BAD_PAYLOAD`) and `INTERACT_TRAILING` (over the cap of 8: NetFrame's `PAYLOAD_TOO_LARGE`).
`ChaosOracle._interact` keeps the rule for a mode that accepts it: both or neither `bad_args`, an unknown id or a
display station `nothing_to_do`, else unknown ("?").
The chaos run plays the greybox, which holds no Cooking, and a take it applied would break its idle-baseline comparison
(class 4), so Cooking's flood guard and cap are held outside it (#778, the cooking ADR's §7): in
`tests/integration/server/host_session_cooking_test.gd` one peer's burst of `Interact(item)` naming a box gets at most
one applied take per 5 ticks and `too_soon` for the rest (CE17), and never more than the kind's `max_items` exist
(CE3); seen failing with the boxes' `Cooldown` planted out and with the cap raised to 1000.
The car repair's bursts are held outside the chaos run too (#813, the car repair ADR's §7, RD13: the greybox never deals it): in
`tests/integration/server/host_session_car_repair_test.gd` one peer's burst of `Interact` naming a bin gets at most one
applied take per 5 ticks and `too_soon` for the rest, and never more than the part's `max_items` exist; a burst of
`Interact` at the lift panel (one hold, `busy` for the rest) and one of `StopRaise` (one stop, `not_channeling` for the
rest) each stop at the reliable-intents bucket (§4.5.6: at most `PeerBudget.INTENTS` reach the match, the rest counted
`over_budget`, nobody disconnected); seen failing with the bins' cooldown at 0.01 s, the cap raised to 1000 and
`PeerBudget.take_intent` never refusing.
The photo task's film box is held outside it too (#789, photo P10, the photo ADR's §8: the greybox never deals the
photo task, PD14): in `tests/integration/server/host_session_photo_test.gd` one peer's burst of `Interact(film_box)`
gets at most one applied take per 5 ticks and `too_soon` for the rest (PE14), and never more than the film kind's
`max_items` exist (PE10); seen failing with the box's cooldown at 0.01 s and the film cap raised to 1000.
The chaos run's freeze in a zone left with the greybox's zones (#804, GD13 (b)): in
`tests/integration/server/host_session_zone_test.gd` (`FixtureZoneModes.zone_task` on the harness's layouts plus one
`zone` marker) a client walks into the zone and fills it, every client decoding `ZoneProgress`, `TaskState` and
`TaskProgress` as its `Match.view_of`; a client frozen in the zone 2 s gains at most `ZoneTask.STALE_TICKS` after its
last accepted claim and stops counting, and counts again once thawed. Seen failing with "stale claims count" planted
(both `_anyone_inside` guards, the claim's age and `credit_gain`, out: 40 ticks gained); with the age guard alone out
it passes, as `credit_gain` also stops a frozen client. The gain is counted from the end of the host tick of that claim, and both tests replay the match from its command log (`Match.replay`) to the same events, recipients and ticks.
Kind 1's `key` (`Hello`, the return key of the [returning-players ADR](decisions/2026-10-09-returning-players-keep-their-number.md); #639):
the hostile's joining `Hello` carries an honest bot's key (`ChaosScenario.KEY_BOT`, bot 2's `ScenarioBot.key_of`),
sent once the host holds that bot's `PlayerJoined` (`ChaosJoining` makes each chaos transport without joining; the
hostile's client exists from the start and `ChaosRun._after_host_step` joins it then). The key is a present
player's, so the hostile joins as a new number and binds none, and bot 2 plays on with its own:
`ChaosOracle.key_problems` checks that at the end of every run (a hostile that is no player by then is named too). The hostile's extra `Hello`s carry, in turn by a
counter (no draw from its rng, so a seed's stream is unchanged), a malformed key, bot 2's, bot 1's and one no player
holds: each is `not_accepted`, whatever it carries. A malformed key is 73-A's core unit test and wire-fuzz case.

#### 4.6.6 `host` and `join` (3i)
`tools\run.cmd host [--port P] [--clients N]` starts a host with its own client and,
with `--clients`, N local clients joined to it; `tools\run.cmd join <address> [--port P]` joins one. In M3 they ran
headless sessions that print the roster, the phase and the counters: a connectivity check between two machines, as
#21 ran; with `--headless` they still do. Since #149 (M4-6) they open the game in windows (§4.7). The default port
is a placeholder. Several windows on one PC
met the D3D12 freeze of §4; Windows now renders with Vulkan (#124), which did not meet it in 10 runs on one PC.
The headless session is `tools/run/headless_session.gd` (a `SceneTree` script under `tools/`, which may use
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
naming the reason (#483), and a remote bot's view file carries that line to the host. The lurker and the refused
bot, in the host's process, join again the same way, 3 joins at most (§4.6.4, #509). The fault
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
the refused bot; bot 1 is the host's own loopback client. A bot that left and joined again (§9.7, #639) has one
pair of lists per connection, each life of its view file its own, checked against the host's lists of that
connection's peer id; its `Hello` carries the same return key over every transport (`ScenarioBot.key_of`, fixed from
its number). Over WebRTC the relay counters' upload adds no IP and UDP
bytes per datagram: E56's 108 B per packet already counts them (`RelayReport.window`).
`tools\run.cmd bots --chaos [--seed N] --transport webrtc` (`--enet` is `--transport enet`) runs `ChaosRun` in one
process the same way (the library set up first, before the host's transport: `WebRtcWarmUp.wait()`, #510), paced to
the real clock (a frame waits until the real clock reached the simulated one: the connections and the shim's delays
are real time), with the ENet variant's invariants plus the order check, both ways for the honest bots and the
watchers, host to peer for the two chaos peers (their raw sends bypass `send`). A raw
packet goes on the channel of the lane whose ENet channel and mode `ChaosFrames` chose; a LATEST one still gets
`LaneOrder`'s header, as any sender's would (a 0-byte one is refused, and its send counts as not made). `verify`, and
so CI, runs `bots-webrtc` (`dissident_kills_the_crew --instances 3`, about 50 s, then since #639
`leave_and_return_keep_the_number --instances 4`, about 40 s; `bots-enet` plays the same two) and `chaos-webrtc`
(seed 188001, about 16 s). Tests: `tests/scenarios/order_log_test.gd`,
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
| `Game` | `client/app/game.gd`: the menu's choices, the sessions, the level swap, leaving and quitting, the end reasons; its helpers sit beside it: `GameHowto`, `GameSettings`, `GameTutorial`, `GameTalk` (the per-frame talk key and Voice panel, #964, out of `game.gd` for lint's 1000 lines), and since #1249 `GamePlayer` (the local player's flags, mouse, life and HUD facts), `GameJoin` (the join under way) and `GameLevel` (the level swap); `GameSettings` also sets up the settings, the own voice and the controls at `_ready` |
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
`ClientSession` and `join(address, port)`. The mode is `content/modes/base_mode.tres`, but in the solo tutorial,
which hosts `tutorial_mode.tres` through the same façade on a private `LoopbackHub` (§4.7.44). `client/app/` is the
only part of `client/` that names `server/`, and only through `HostNode` as a narrow façade:
`HostNode.host(transport, mode, port)` builds and starts the `HostSession` and keeps it private; the game reads only `own_client`, `errors`,
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
and input flags (`GamePlayer.apply_flags`) follow the model at once: `Game._on_event` applies them at every event the
session folds, in its physics step, and `_process` again every frame (the Esc menu), so after a hitch the player
neither steps nor claims into Loading, Pregame or End, nor waits for `_process` to walk again (#241). A step turned off there
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
| no session | main menu (s2, #493, §4.7.38): the name row; Host, Join (the code panel), Join by address (the Direct panel), Tutorial, Settings (the Settings panel), Quit | none | none |
| connecting, no `Welcome` yet | connecting screen (s3, #494, §4.7.32): the spinner, the title, the step, a code join's code and the time since Join, Cancel (Esc too) | none | none |
| Lobby, Countdown | lobby HUD (s4, #495, §4.7.47): the status (ready count, the host's shortfalls, countdown), the lobby's name, the code, the players with ready checks, the own ready chip, the mic; Ready and the settings in the Esc menu's Lobby tab (#169) | the mode's `lobby_level` | walks and claims |
| Loading | the connecting screen's loading (#494): this machine's load, who has loaded (`PlayerLoaded`), one tip | the map, once `map_loaded` | frozen (Loading accepts no claim) |
| a phase with no level (the tutorial's `gather`, #601, §4.7.44) | the same loading screen (`GameFlow.screen`: `PhaseSpec.level` `NONE`) | none | frozen, the mouse kept |
| Pregame | pregame screen (#496, §4.7.39): black, "Your role", the own role on the title plate, its goal, a dissident's teammates; at the round's start the black fades out over the HUD (#213, §3.6) | the map, not drawn | frozen |
| Round | HUD; the map and tasks screen on M (§4.7.33); in the tutorial its invite and lesson plates (#492, §4.7.49) | the map | by its life (below); none under the tutorial's invite |
| End | post game screen (#498, §4.7.31): black, "End of the round", the winning side (the title plate for its players), why the round ended; "Back to the lobby in 3…" from End's `end_tick`, for everyone, no button (#212) | the map, not drawn | frozen |
| ended | the connecting screen's failure in plain words until Back (#494), then the main menu, its panel and what was typed kept; the player's own leaving (`left`, `closed`) goes straight to the menu | none | none |

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
- **The lobby** (#169): the player walks it like the round, with the lobby HUD (since #495 the Toy one, §4.7.47: the
  status, the players with ready checks, the own ready chip; no key prompt) and nothing to click. The Esc menu's Lobby tab has the
  lobby's name (the host's to edit, #214, §4.7.11) with the map's picker right under it (#694), the roster, the
  Ready toggle and the settings; the `ready` key (F, a placeholder) toggles Ready without the menu.
  Ready sends `SetReady`; one control per `SettingSpec` of the client's own mode (its
  display name, a whole number within its bounds, or check boxes for the banned task types) sends `ChangeSettings`
  with that setting only; a Map picker of the maps players play (`GameMode.player_maps()`: the mode's `maps` but its
  test benches, #767), named by file name (#627), shows `ClientModel.map` and
  sends `ChangeSettings` with no settings and that map (disabled unless the settings are editable and there are
  two or more such maps); the demands and shortfalls come from `SettingsChanged` (the
  shortfalls worded by `HostTextView`, §4.7.45). Everyone sees the settings; only
  the host changes them, and only in a phase that accepts its `ChangeSettings` (the lobby, not the countdown).
  The countdown and the match clock show `end_tick` minus the estimated host tick (Movement, below).
- **The end screen** (the post game screen, §4.7.31) shows the winning side's deck line, on the title plate when the
  own role's side won and as plain text otherwise, why the round ended, and the seconds left until End's `end_tick`
  (`EndScreen.count_shown`, hidden when End has none), and nothing else (§3.2: no names, no roles, no button since
  #212: End returns everyone by itself).
- **The Esc menu** (#169): one Esc opens it and frees the mouse; Esc again, or the Game tab's Resume, closes it (one Esc closes one overlay, the topmost first: a card (a how-to card, §4.7.36), the map, the host's Leave or Quit question before the menu, §4.7.35), and where
  `GameFlow.pointer_on` does not free the mouse (the lobby, Loading, Pregame, the round) captures it again. Its tabs are on the left (Game: Resume, Leave, Quit; Role, in the round only; Guide, #254, §4.7.36; Lobby, on the lobby
  screen, the lobby and the countdown, read-only in the round; Settings; the tutorial shows only Game, Guide and Settings;
  #491, §4.7.42), the selected tab's page on the right; it opens on the tab chosen last on this kind of screen, else on
  Lobby in the lobby and Game everywhere else. `Game.open_esc` gives it the live `screen()`, not the screen `_process` drew last:
  an Esc in the frame the Welcome arrives comes before the lobby is drawn and opens on the Lobby tab too (#204).
  A new screen closes it, its question too, when it opened over another (`EscMenuState.over_screen`, #726): the
  match leaving the lobby, the end screen, the lobby again (the countdown is still the lobby's screen and keeps it;
  the menu opened over the live screen in #204's frame stays). `EscMenu.close` hides a dropdown's open list, a window of its own, too.
  Under it nothing reads the gameplay keys, the held ones are released, and F readies nobody.
- **The mouse** (#517): `GameFlow.pointer_on` says what each screen asks of it. The lobby and the round capture it
  when they show (no click first; also after End's return), Loading and Pregame keep it as it was, and the menu, a failure (#494),
  Connecting and the end screen free it (the first three for their buttons; the end screen only counts down since #212). A screen never captures it from under the Esc menu, nor while the
  window lacks the focus (`MousePointer.focused`): Windows clips the cursor to a capturing window even when another
  app has the focus (`DisplayServerWindows::_set_mouse_mode_impl`, 4.7.2); a click captures it there (never while the map is open: the map frees the mouse in the round, and closing it captures it again, §4.7.33). Closing the Esc
  menu in Loading captures it too, and so does a screen change that closes the menu in Loading or Pregame (#726).
  Until #517 Loading freed it (`GameFlow.frees_pointer`), and since the countdown runs on the lobby's screen, every
  round started with the cursor showing until a click.
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
  back, the mouse captured all the way to the end screen; the match closes an open Esc menu, #726, and an unfocused
  window stays free). Not headless: the real mouse and window; the manual check is in the PR of #517.
- **Leaving:** the Esc menu's Leave and Quit. A client's Leave calls `ClientSession.leave()`; the host's asks for a
  confirmation, then frees the `HostNode`, which closes the session (every client sees `host_lost`). Closing the
  window does the same (`SceneTree.auto_accept_quit` off, `NOTIFICATION_WM_CLOSE_REQUEST` handled). In the solo
  tutorial (§4.7.44) `Game.hosting()` is false: Leave, Quit and closing the window end it at once, as a host's own
  leaving (`closed`, no failure shown), and its stand-ins go with the `HostNode`.
- **Every end shows why.** On `ClientSession.ended` or `HostSession.ended`, `Game` frees the sessions, the level and
  the views, shows the end's failure (`EndReasons.failure_state`, #494, §4.7.32) and returns to the main menu; the reason in words (printed, and kept in `Game.last_words` since #493) comes from one table, `client/app/end_reasons.gd`, which
  `tools/run/headless_session.gd` then uses instead of its own: the refusals (`wrong_version`, `wrong_content`,
  `joins_closed`, `full`, `connect_failed`), `host_lost`, `unknown_map`, `load_failed`, `left`, the host's own ends
  (`closed`, `row_error`, `own_client_malformed`, `own_client_disconnected`) and `load_deadline`.
- **A drop at the loading deadline** (#119, E21): the Loading phase emits `Disconnecting(reason)`, `load_deadline`,
  to the dropped player right before its `DisconnectPeer`, and `ClientSession` ends with that reason. ENet's
  `peer_disconnect_later` delivers it first (§4 Transport).
- **The command line:** `--host [--local]`, `--join=<address>` and `--port=<p>` after `--` skip the menu, with the
  runner's `--stop-file` and `--alive-file` (M6-7 adds `--code`, `--signal=`, `--room=` and codes for `--join=`, §4.8); the parser moves from `tools/run/headless_session.gd` to `client/app/`.
  `--tutorial` (#601, §4.7.44) starts the solo tutorial without its invite, for `playcheck`; any option at all keeps
  the first launch from starting it.

#### 4.7.5 The shell (M4-6, #142)
`client/app/` holds `Game` (`game.gd`, `game.tscn`, the main scene),
`GameFlow` (the flow table above as a pure class: the screen and the level per session state and phase, read from
the client's own `PhaseSpec`: a lobby level shows the lobby screen, a phase that accepts `LoadAck` the loading screen,
one that accepts `ReturnToLobby` or a match with a winner the end screen, any other map phase the round),
`SessionNode` (-90), `LaunchOptions` (the command line, which `headless_session.gd` also reads) and `EndReasons`
(the reasons in words; it writes the host's own reasons as ids, since `client/` may not name `HostSession`, and a
test pins them to `server/`'s). `client/ui/` holds the screens, built in code under `GameUi` (the `Ui` layer):
`MainMenu`, `ConnectingScreen`, `LobbyPanel`, `LoadingScreen` (folded into `ConnectingScreen` by #494), `EndScreen` and `EscMenu`. `client/world/avatar_views.gd`
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
  players still for half a second), time up, the end screen and back with no intent after 3 s (#212), a client's Leave and the host's close (about
  5 s), and the same loop with no `Game._process` from the lobby on (#241, above).
  The screens' `shot`s: `client/dev/<screen>_preview.tscn` (`screen_preview.gd`, a fake `ClientModel`).
- The runner's windows for `host` and `join` (E20) came with #149, the rest of M4-6: below.

#### 4.7.6 Movement on the network
- **Claims:** every physics step the controller calls `set_motion` (its position and velocity; as the facing, the
  camera's 3D look vector, at most 89° up or down; whether it sprints, gives movement input, stands on the floor and,
  since #791, has the crouched capsule, §7.1.17) and `count_jump` at a jump, and `set_facing` when it turns outside the step (the level look of a respawn or a
  placement, #191, #240);
  `ClientSession` sends one claim per 20 Hz client tick (§4.6.1). The facing's pitch needs
  no wire or `core/` change (E22): `Strike.horizontal`, `Swung` and `PutDownInFront` flatten it, and `MovementRule`
  only requires it finite; the snapshot's avatar then carries it, for remote heads and the spectate camera. Snapshots
  stay at 20 Hz, since the spectate camera is built from them. A relayed facing can be degenerate even in honest play
  (a bot falling straight down claims (0, -1, 0)): `MovementRule` stores a unit facing, keeps the last one when a
  claim's has no direction and clamps the pitch to ±89° (§7.1), and every camera, head or basis the client builds from a
  remote facing still guards against a zero or vertical vector (the M4 ADR's §3, Host trust).
- **Numbers:** the controller's speeds, jump height, capsule, eye and step height, stamina and the crouch's two
  heights and two speeds (#791; the crouch plays everywhere, #991) come from
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
- **The knocked-down hold still** (M4-9; the crawl went with #728, KE4): a downed controller moves nothing, with no
  gravity, no sprint and no jump (`PlayerController._hold` every physics step), and claims where it lay with its
  look; it keeps the standing capsule for collision, and only its mesh lies down. Physics layer 3 is `downed` (`PhysicsLayers.DOWNED`),
  which no push search looks at: the downed collide with no player.
- **The crouch** (#791, §7, §7.1.17): the controller claims its crouch as the pose of the step it sends (the claim's
  `crouched` flag), wherever the player moves (the lobby included, #991), as the host's `MovementRule` keeps the
  flag of a living claim in every phase that takes one, so an honest crouched walk or crouched sprint is never corrected: 0 `Correction`s over the
  loopback, also with packets held back and with jitter (`player_network_crouch_test.gd`). Its remote pose: the next
  bullet (727c).
- **Remote players crouched** (#792, the crouch ADR's KE7; §7.1.17): the pose's `crouched` is the flag of the
  snapshot at or before the drawn tick, never blended. `AvatarViews` calls `RemotePlayerBody.set_crouched` before
  `set_pose`, so the capsule (a new `CapsuleShape3D` of `crouch_height_m`, the feet staying, placed with
  `force_update_transform()`) is what the push search finds in that same frame; the greybox look and the sight point
  switch with it, and the head, with the mouth, hand, belt and carry points hung on it, eases down by the eye
  heights' difference at `PlayerTuning.view_catch_up_seconds`' rate (a body drawn for the first time: at once). A
  downed body lies at standing size. The spectate camera stands at the target body's head, crouched or not.

#### 4.7.7 Movement on the network: the code (M4-7, #143)
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
  (`PLACING_EVENTS`: `PlayersPlaced`, `KnockedDown`, `Respawned` (M4-4) and `Revived` (#728 KE6); a death sends no
  `Correction`; a later rule that places a player with a `Correction` adds its event there).
- `client/app/game.gd` wires them: a `SnapshotBuffer` per session, the player's rules and session, the lobby's
  countdown from the estimate, `device_input` (tests drive the controller's wish fields), and in a debug build the
  debug overlay (`client/ui/debug_overlay.gd`, the `debug_overlay` action on F3; `client/dev/debug_overlay_preview.tscn`
  for `shot`), which since #431 also shows the own connection's kind and round trip (§4.8); `client/app/OverlayFeed`
  feeds it each frame (out of `game.gd` since #254).
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
  body; everyone living at `RoundStarted` and in the lobby). `life_of(peer)` (the knockdown, the death and the
  leave; `is_alive()` reads it, not "has no body", which would keep a respawned player dead). `ClientSession` claims while its own copy of the phase accepts
  `MoveClaim` from its life, and never while dead. Each fold lands in the core issue that adds its event, because the
  bots are `ClientSession`s.
- **The own player**, by life:

  | Life | Controller | Camera | Inputs | HUD |
  |---|---|---|---|---|
  | Living | walks, sprints, jumps, pushes (§7.1) | first person, the hand item in view | all (the ADR's controls) | clock, own role, health, stamina, mic, hand and belt (#489, §4.7.37; the destination and task progress moved to the world marker and the map) |
  | Downed | holds still where it lay and keeps its items; its claims carry its look only, which the host takes and never corrects (#728 KE4) | third person above the body | look, give up | the knockdown countdown (paused while raised), who raises them |
  | Dead | off: no avatar, no claims, no look (#191) | the spectate camera | next and previous target | the respawn countdown; "Watching: <name>" (§4.7.37) and the target's hand and belt items (#168); nothing else of the target's |

- **The downed camera** (answer 9 (a)): a `SpringArm3D` whose pivot is on the body at the mode's standing eye height
  (`PlayerRules.eye_height_m`; at the crouched eye, `crouch_eye_height_m`, where the crouch's stand-up test (KE6)
  finds no room over the body, so a player downed or killed crouched under a low ceiling never looks past it,
  `LifeView.downed_eye_of`, #958), pointing back along the look, never above its pivot (the arm's pitch is clamped to
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
  body hidden; the HUD says "Watching: <name>" over those public slots (§4.7.37).
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
  the markers carry no facing); the spectate camera and the lift music stop. After `Revived` and its `Correction` (a
  placement where it lay, #728 KE6) the controller stands up there, in first person, keeping its look (only the own
  respawn levels it, #191). Placed with its capsule inside `movers` (`PhysicsLayers.MOVERS`: the lowered car,
  which the host's world never holds, so a revive may place a player inside it), its first living step finds the
  nearest clear floor within `MOVER_EXIT_REACH_M` (3 m, a placeholder) and walks its capsule there at walk speed
  over its first claims, whatever the keys say, ignoring those movers (collision exceptions) until clear: KD15 (b2)
  ([#976, comment 6162445237](https://github.com/xperiaroco2/prime-game/issues/976#issuecomment-6162445237)), a client rule; the host checks the claims as any claims. A placement
  anywhere else finds no mover and plays step for step as before.
- **Others:** a `RemotePlayerBody` shows its facing (a head that turns and nods), the hand item at a hand attach
  point, the belt item at a belt attach point, a two-handed package held in front, the downed pose and its layer, and
  invulnerability (the avatar's flag). A body (`Died`) is a view of its own, removed at `Respawned` or `PlayerLeft`.
- **Hands:** the own hand item is drawn in the first-person view and the belt item on the HUD. Every item is drawn
  from `ClientModel`'s fold of the item events: on the ground where it lies, or at its holder's hand or belt. The own
  slots come from events only (the own avatar arrives only while it is knocked down, KE5). No screen reads out the own invulnerability
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
  `Raise(target)` and `StopRaise()`, `PutDown(facing)`, `Use(facing)`, `Swap()` and `GiveUp()` (and, since #645,
  `Throw(facing)` on G; and, since #801, `Interact(station, item -1)` on E at a Generator's station,
  §4.7.54); the host checks each again (§7.1), and the client predicts nothing of an action's outcome
  but a throw's drawn arc and the hand item it hides, from the key press until `ItemThrown`, `Rejected`,
  `PhaseChanged` or `LoadMatch` (§4.7.52), which change no slot.
- **The HUD** (the Toy HUD, §4.7.37): health and stamina (`SelfStatus`, the stamina predicted), the hand and belt
  items (a kind's deck key and pack icon, else its display name), the match clock, the own role (its deck key),
  the mic and what the crosshair would do; no teammates, task progress, destination swatch or hint. While dead the HUD shows nothing (§4.7.12,
  §4.7.41): no target's health, stamina, role, teammates or private event (the ADR's §3 item 2).
  **The tasks** of the match (`TaskState`) are on the map and tasks screen (`MapScreen`, on M, §4.7.33). **A
  circle** is a translucent cylinder of its station kind's radius and height in `StationPlaced`'s colour, dimmed
  once `PackageDelivered` names it.

#### 4.7.9 The life states in 3D (M4-9, #145)
- `client/player/`: `PlayerController.life` (`set_life`, replacing the ghost flag and `set_ghost`) follows the own
  life fold (`GamePlayer.sync_life`): living on the living layer; downed on the `downed` layer, holding still (#728), showing nothing
  (its body is the own avatar's ragdoll); dead on no layer, no mesh, and no physics step (the controller returns at once and `Game` stops
  its step), so a dead player never stands back up and walks before its `Respawned`. `held` (the
  raise's hold, from `ClientModel.raiser_of(own) != 0`) went with #728: every downed controller holds still.
  Any life change clears a pending jump. `RemotePlayerBody` hides its meshes and turns its shape off while its player
  is downed (its ragdoll stands in), wears a pulsing white shell while its avatar has the `invulnerable` flag, hides
  its meshes while watched from its eyes (`set_watched`), and knows its `peer`. `LifeLooks` holds D8's greybox
  looks (the capsule, a body's dark cross, the shell).
- `client/world/`: `BodyViews` (`Bodies` under `World`, -70) draws a body per `ClientModel.bodies` entry, the own
  one included. `SnapshotBuffer` keeps a unit facing for a huge but finite relayed one (scaled by its largest
  component before normalising; `unit_or()`), which `look_angles` shares.
- `client/life/`: `LifeView` (`Life` under `World`, 5: after the player, before `SightHider`) picks the camera by
  the own life (the player's, `DownedCamera`, or the spectate camera), runs the life inputs (E pressed on a downed
  player within the mode's `TargetInReach` from the feet, less the walking margin of #352, sends `Raise`, its
  release `StopRaise`, and a raise that
  starts after E was let go is stopped at once; the `give_up` key (G until #211, F since) held for 1 s sends
  `GiveUp` once; the left and right mouse
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
- `client/ui/`: `LifePanel` (the round's life panel under `Ui`, its own, not M4-8's HUD; #497 replaced it with the Toy
  `LifeScreen`, §4.7.41) and the shared greybox
  theme `client/ui/theme/game_theme.tres` (`GameUi.THEME`, given to every screen under the `Ui` layer, which as a
  `CanvasLayer` holds none itself), with the type variations `LifePanel`, `LifeTitle` and `LifeText`; M4-8 moved
  the older screens' inline styles into it.
- `project.godot`: `give_up` (G; F since #211, §4.7.28), `spectate_next` and `spectate_previous` (the left and right
  mouse buttons). G is `throw` since #645 (§4.7.52), and the give-up hold counts only from a press made while downed
  (`LifeView.hold_give_up`): a key held for a throw through the own knockdown, should a rebind share it, gives nothing
  up until it is let go.
- The lift music is a generated placeholder (`LiftMusic.placeholder_stream()`: a quiet looping arpeggio), until a
  human picks a CC0 track with its `docs/credits/` entry.
- Tests: `tests/unit/client/life/` (`LifeCountdowns`, `SpectateTargets` with a pinned seed, `LifeHud`, `LiftMusic`),
  `tests/unit/client/ui/life_screen_test.gd` (the Toy `LifeScreen` that #497 put in place of `LifePanel`),
  `tests/unit/client/ui/theme_test.gd` (the theme source test, seen failing on the planted overrides),
  `tests/unit/client/app/session_node_test.gd`, `tests/integration/client/life/downed_camera_test.gd` (every look
  at or below the eye and before a wall behind the body, seen failing without the clamp and the mask; a view seen
  from the arm's end past a short wall but not from the eye is hidden),
  `tests/integration/client/world/body_views_test.gd`, and over the loopback (`NetPair.with_life()`, which adds the
  raise, the give-up and a 2 s respawn on `steps_room`'s new `respawn` markers) `life_network_test.gd`: a raised
  downed joiner holds still, is never corrected (its revive's `Correction` is a placement, #728 KE6) and stands up
  invulnerable in first person; a joiner who gives up stays off the living however it is driven, watches the host
  from its eyes with the music, follows it to the camera above its body when it goes down, and respawns at a marker
  in first person, invulnerable on the host's screen, with no `Correction`; `life_raise_network_test.gd` (#352: the
  joiner walks at the downed host's body from three sides and presses E at the first raise hint, on an even and an
  uneven clock; the host starts every raise; seen failing `out_of_reach` with no margin) and
  `tests/unit/client/life/life_view_reach_test.gd`. `client/dev/life_preview.tscn` is the
  `shot` of a ragdoll at rest, a body, the invulnerable look and the panel.
- **Ragdolls (728d, #848; the knockdown ADR's KE7, KE8, KD7).** `client/player/RagdollView`: on today's capsule
  avatar one `RigidBody3D` capsule of the client's `PlayerRules` on the `downed` layer with the world mask only,
  top-level, never asleep; `start()` stands it on the snapshot's point with its velocity and tips it (towards the
  velocity, else backwards: an upright capsule pulled through its centre stays standing). That velocity is the host
  body's, from a snapshot that shows the player downed only, else none: the reliable `KnockedDown` can overtake the
  knockdown tick's snapshot, and the one before it carries the living player's claimed velocity, which never moves a
  body on another screen; `hold()` cuts any to `SnapshotBuffer.SNAP_SPEED_MPS`. Each step a spring and a
  damper pull its centre to the lying centre over the host's interpolated point (the point plus the radius, never
  into the floor), across the floor only as much as it lies, and a centre farther than `SNAP_M` moves there at once.
  Its constants (`SNAP_M`, `SPRING_K`, `SPRING_D`, `TIP_RAD_PER_S`, `FRICTION`, `STILL_MPS`) and `DownedCamera`'s
  `FLOOR_RAY_M` are placeholders, "not a decision"; `CEILING_MARGIN_M` is the knockdown ADR's own placeholder.
  `AvatarViews` draws every knocked-down avatar, the own one included (KE5), as a ragdoll beside the bodies, in
  SightHider's group with the host's point as its sight point; `point_of(peer, fallback)` is that point, which the
  own camera, ears, held items, world sounds and the map's own place read (`LifeView.own_point()`, the controller
  until the first snapshot with the own avatar). Nothing reads a ragdoll's pose (the render checklist's item 1).
  `DownedCamera.place_over` takes `LifeView.downed_eye_of`'s eye height (#958: the crouched eye where the standing
  capsule finds no room), casts down and up from the point plus the radius and `clamp_eye` keeps the pivot no
  higher than that eye height above the floor below (none found: no clamp) nor than `CEILING_MARGIN_M` under the
  ceiling, for the own camera and a spectator's over a knocked-down target. The raise hint's ray maps a hit ragdoll to
  its peer and measures the reach to `held_point()`. At a death `BodyViews` takes the ragdoll (`release_ragdoll`, the
  same step), greys it, puts it on no layer (no ray stops at a body) and draws `LifeLooks.cross` over the body's
  point; a body this client never saw knocked down gets a fresh ragdoll lying at rest along -Z. A revive drops the
  ragdoll and the controller stands at the host's point. With the character (#522, §4.7.53) the same view holds the
  skeleton's `PhysicalBone3D`s instead of the capsule.
  Tests: `tests/integration/client/player/ragdoll_view_test.gd`, `tests/integration/client/world/avatar_views_test.gd`,
  `body_views_test.gd`, `tests/unit/client/life/downed_camera_clamp_test.gd`, `life_raise_ragdoll_network_test.gd`
  and `life_ragdoll_network_test.gd` (over the loopback on `NetPair.MOTION_LEVEL`, whose low slab the host and the
  client share: a launched joiner's camera and ears follow its avatar with both clamps in mid-flight, the root within
  the snap distance every frame, a spectator's floor clamp, the ragdoll kept at a death, a revive at the point).
- Not headless: the keys and the mouse, the feel of the cameras and the music; the one-PC playtest (the M4 ADR's
  §6) checks them.

#### 4.7.10 Items, hands, the HUD and the task screen (M4-8, #144)
- `client/world/`: `ItemWorld` (`Items` under `World`, made by `Game`) holds `ItemViews`, `CircleViews`,
  `ItemInteractions` and `WorldSounds` (since #801 also `StationViews` and `StationHums`, §4.7.54) and gives the HUD what the model does not hold (`hud_local()`: the predicted
  stamina and the crosshair's hint; `Game` adds whom a dead player watches, #168). `ItemView` is one item's
  greybox look by its kind's id (D7 (a)), a labelled box for an unknown kind, its origin the resting point;
  `ItemViews` places one per model item: where it lies, at a remote holder's `RemotePlayerBody` attach point
  (`hand_point()`, `belt_point()`, `carry_point()` for a two-handed kind), on the ground at the body while that
  holder is downed (the own player too, whose first-person hand then shows nothing), hidden while it has no body
  drawn and when the own living player holds it; in flight, on its arc (§4.7.52). Each view joins
  `SightHider.GROUP` and gives `sight_point()`; the root's `visible` is left to the sight hiding, `ItemViews`
  toggles the look under it. `ItemViews` places in the physics step at priority 1, after the avatars and the
  player moved and before `SightHider` (10) casts, so a view out of the body's eye's sight is never drawn for a
  frame. `CircleViews` finds a station kind's size in the task types' `station_kinds()` (Delivery's `circle`, Delivery
  by meaning's drop-offs) and draws the circles in their colours; nothing of the client draws through walls since the
  destination marker (D10 (b)) went with D3a (#829, Delivery by meaning DD4 (a)): a carried item says where it goes by
  what it is. Since #801 it draws only Delivery's circles and the fallback cylinder of a kind no type holds
  (`CircleViews.draws`, §4.7.54): a zone is `ZoneViews`' (§4.7.51), the Generator's stations are their level
  scenes, and each task type's view is its `TaskClient`'s (§4.7.59).
  Delivery by meaning's looks (DE11 of its ADR, #830; greybox placeholders until the art): `CircleViews.is_drop_off`
  tells a drop-off from a circle by which of the client's own Delivery types lists its kind (a `DeliveryByMeaning`'s
  `station_kinds()`), never by a colour or a name; a drop-off is an open tube (no caps) of its kind's radius and
  height in one neutral colour (`DROP_OFF_COLOUR`), never `StationPlaced`'s (white for a drop-off, DE5 (b)), both
  faces drawn, depth-tested, dimmed as a circle once done (DE7's fold), so it looks like neither a circle's coloured
  cylinder nor a zone's disc and ring. Its kinds (wine, oil, gnome, parasol) have no look of their own yet: each is
  `ItemView`'s labelled box, never tinted by `ItemSpawned`'s colour (only the `package` look takes it), labelled with
  the kind's name through `ContentNames` (the deck key's text, else the mode's display name; `ItemViews` passes its
  mode, the first-person hand none, so there the deck key or the id). Today's circles and packages are unchanged. The
  HUD needs nothing: the M6.2 HUD (#489) shows no destination for any item.
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
  the ears, and nothing beyond; every `AudioStreamPlayer3D` sets `max_distance` to it and plays muffled behind the
  level. The sounds, footsteps included, are Kenney's CC0 files (§4.7.43), each passing `sfx-check` first
  (AGENT_WORKFLOW §11.25).
- `client/player/`: `FirstPersonHand` under the camera shows the own hand item (`PlayerController.hand_view()`);
  `RemotePlayerBody` has the three attach points.
- `client/ui/`: `HudText` (pure: the HUD's words) and `Hud` (the Toy HUD, §4.7.37); the tasks are on `MapScreen`,
  opened and closed on M (the action `map`, §4.7.33), and Tab has no action. **The shared theme:**
  `client/ui/theme/game_theme.tres` (`GameUi.THEME`) holds every colour, font size, spacing and style box as a type
  variation, the base controls a screen builds bare included, under their class's name (§4.7.30); `GameUi`
  gives it to every `Control` child, one added later too (a `CanvasLayer` holds no theme); the screens name
  variations only. The file is generated from the UI pack (§4.7.25); the Toy components and the large-text swap are
  §4.7.27. The input actions `swap` (X) and `map` (M) are in `project.godot`.
- Tests: `tests/unit/client/ui/hud_test.gd`, `theme_test.gd` (a source test over `client/ui/` against
  `add_theme_*_override`, `Color(...)`, `Color.X` and `font_size` outside `client/ui/theme/`, seen failing on a planted
  override in `hud.gd`), `tests/unit/client/world/target_choice_test.gd`, `sound_chooser_test.gd` (seen failing on a
  chooser without the range), `tests/integration/client/world/item_interactions_test.gd` (the real controller on a
  fixture floor: a crate-top item 2.08 m from the feet and 1.75 m from the eye gets no hint, floor items 1.3 to
  1.7 m away get one and one 1.85 m away none (#319); seen failing with the reach measured from the eye),
  `item_pick_up_network_test.gd` (#319: a joiner walks at each of three knives over `NetPair` and presses E at the
  first hint, on an even and an uneven clock; the host accepts every `PickUp`; seen failing `out_of_reach` with no
  margin) and `item_views_test.gd`. The `shot`s:
  `client/dev/hud_preview.tscn`, `map_preview.tscn`, `items_preview.tscn`
  and `hand_preview.tscn`.
- Not headless: the keys, the feel of the hint and the sounds; the one-PC playtest after M4-8 checks them (the M4
  ADR's §6), and a human picks the CC0 sounds (by ear on `sfx-check --page`'s listening page, AGENT_WORKFLOW
  §11.25).

#### 4.7.11 One Esc menu with tabs (#169)
- `client/ui/`: `EscMenuState` (pure: open or closed, the tabs per screen, the selected tab, the host's questions
  before Leave and Quit, who may change the settings: the host, while the phase's `PhaseSpec` accepts its
  `ChangeSettings`), `EscMenu` (draws it: the tab buttons, a scrolling page on the right), `LobbyPanel` (now the
  Lobby tab's page; read-only settings for everyone but the host) and `LobbyHud` (the lobby's corner: the hint, the
  roster, the countdown; it ignores the mouse; the Toy HUD since #495, §4.7.47). The theme gains `EscBody`, `EscTabs`, `EscTab` and `EscPage`.
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
  `client/dev/lobby_preview.tscn` (the lobby HUD) and `esc_<lobby|lobby_guest|game_host|game_confirm>_preview.tscn` (since #491, §4.7.42).
  #204 adds an Esc pressed from the `welcomed` signal, before any `_process` drew the lobby: the Lobby tab (seen
  failing without the fix, also under a slow `_process`); `screens_test.gd` holds `GameUi.open_esc`'s `screen_now`.
- #214 adds the lobby's name (§3.5) at the top of the Lobby tab: a `LineEdit` (`LobbyPanel.name_edit`, at most
  `LobbyName.MAX_CHARS` characters) that the host edits and everyone else reads (not editable), its placeholder
  the default (`LobbyPanel.default_name`: `lobby.default_name` with `ClientModel.host_name()`). The page is
  refreshed every frame, so the host's field takes the model's name only while it has no focus (the host's typing
  stays; a player's read-only field follows every rename, focused or not), and it sends only on submit or when it
  loses focus, cleaned (`LobbyName.clean`: a pasted invisible character would make the wire refuse the whole
  intent) and only when it differs from the model's or from a name already sent: no `ChangeSettings` per
  keystroke, each of which the host would answer with a `SettingsChanged` to everyone. A sent name stays in the
  field until the model's name moves (its echo is a round trip away), so it never flicks back to the old one; with
  no host in the roster the default is "" (never "'s lobby"). `Game.change_lobby_name`
  sends it (cleaned again). `LobbyPanel.default_name(model)` is the default name (#1247 removed the unused `lobby_title`); the
  lobby HUD (#495) builds the same from `LobbyText.title_text`, in the language of the moment. Tests: `lobby_panel_name_test.gd` (seen failing with the focus guard planted out) and
  `game_loop_test.gd` (the host's tab reaches every `Game`'s model; seen failing without the clean).
- #694 (main's #627 taken into the slice) puts the map's picker (`LobbyPanel.map_picker`, built once, its items
  rebuilt by `set_mode`) in the row right under the name, out of the settings box: the two things that name the
  match side by side. Its label is plain "Map" until the UI deck has a key for it. `Game.change_map` sends it.
  Tests: `screens_test.gd` (#627's two map tests, and the row's place and a rebuilt list) and
  `game_map_choice_test.gd` (every `Game` loads the host's map). The `shot`s: `esc_lobby_preview.tscn` and
  `esc_lobby_uk_preview.tscn` (the host's tab in Ukrainian).
- #767 (the engineer's option (a)): players always play the House. `GameMode.bench_maps` marks the maps of
  `maps` that are test benches only (the base mode's: the flat greybox, for the bot scenarios and the leak test,
  §9.7); `player_maps()` is the rest and `default_map()` its first, where every match starts (`Match`), so the
  picker lists the House alone. The host still accepts a bench in `ChangeSettings` (the bots ask for it, and the
  host cannot tell a bot from a person); the mode check refuses a bench not in `maps` and a mode whose every map
  is a bench. Tests: `game_mode_maps_test.gd`, `screens_test.gd` (the shipped lobby offers the House alone),
  `content_modes_test.gd` and `game_map_choice_test.gd` (a human match loads the House on both machines).
- Not headless: the mouse capture on a real window and the feel; the engineer repeats the lobby part of the one-PC
  playtest. `tools\run.cmd playcheck esc_menu` drives both windows' menus; since #204 its guest presses Esc as soon
  as its screen is the lobby, with no frames between, and readies with the Lobby tab's Ready button, which only that
  tab shows.
- Since #491 the menu is the Toy one of §4.7.42: the tabs Game, Role, Guide, Lobby and Settings; the host's
  question is a dialog.

#### 4.7.12 Spectating from the target's eyes (#168, PR #167)
- The spectate camera has no offset: it is the target's interpolated eye transform every physics frame, so it
  retraces the poses of the target's own camera, later by the interpolation delay (about 0.15 s on the loopback:
  some 0.7 m behind a walking target). `LifeView` shows the watched target's hand item in a `FirstPersonHand` under
  the spectate camera (`spectate_hand()`) and hides the views of its hand and belt items after `ItemViews` (1)
  placed them in the same physics step (`LifeView.items`, given by `Game`); a downed target, another target or the
  own respawn shows them at the body again.
- `client/ui/`: while `HudText.spectates()` the HUD shows nothing, not even the target's hand and belt (§4.7.37,
  §4.7.41). The target's name is `LifeHud.Local.watching` (from `LifeView.target()`) and `Shown.watching`, shown by
  `LifeScreen`'s `Spectate` plate (#497) in `watching_label`. `LifeHud` has no own invulnerability line; the respawn
  countdown and the cycling keys stay.
- Tests: `tests/unit/client/ui/hud_test.gd` (from a fake `ClientModel`: a dead spectator sees nothing of the HUD,
  `test_a_dead_spectator_sees_nothing_of_the_hud`), `tests/unit/client/life/life_hud_test.gd`,
  `life_network_test.gd` (the target's name on `LifeScreen.watching_label`, on the network),
  `tests/integration/client/life/spectate_network_test.gd` (NetPair; the joiner dies and watches the host's player
  while it walks and turns: the camera equals the target's interpolated eye transform every physics frame and
  retraces the poses of the target's own camera within a few millimetres, both failing with a planted 5 cm offset,
  the retrace measured to the segment between two recorded poses, so the render tick's phase cannot fail it; the
  target's meshes and items not drawn from its eyes, drawn again when it goes down or the spectator respawns) and
  `spectate_cycle_test.gd` (no network: a dead player cycles between two living targets of a hand-folded model, and
  the one it leaves is drawn with its items again). The `shot`: `client/dev/spectate_preview.tscn`.
- Not headless: the feel of spectating; the engineer repeats the spectating part of the one-PC playtest.

#### 4.7.13 The view after a respawn or a new match (#191, #240)
- `client/player/player_controller.gd`: every placement starts level, the yaw kept (the engineer's answers on #191,
  no protocol change, and on #240, option (b)). The own `Respawned` (the controller's session events) and a
  `PlayersPlaced` that names the own player (`End -> Lobby`'s and the deal's, the only two, both naming everyone
  present; `PlayerController._places_level`) call `look_level()`: the head's pitch 0, the body's yaw kept, and
  `ClientSession.set_facing` (the next `MoveClaim`'s facing, nothing else of `set_motion`'s report) with that look,
  since the first claim after it can go out in the same session step as its `Correction`, before the controller
  steps again; the placement's call comes right before its `Correction`, so that `Correction`'s facing is level
  too, and other players see a level head from the first claim. A `Correction` alone (a refused claim, a
  knockdown), a revive, and another player's respawn or placement keep the look. `look()` does nothing while dead
  or left (the controller reads the mouse while `Game` only stops its physics step, so mouse motion while
  spectating would turn the hidden body and tilt its head). `LifeView` is unchanged: the downed camera follows the
  downed look, the camera above the own body keeps the look at death, and spectating reads the target's
  interpolated pose only.
- Tests: `life_network_test.gd` (the downed joiner turns and looks up, gives up, moves the mouse while dead without
  effect, and respawns level with the downed yaw: its camera's forward horizontal, the facing at the respawn's
  `Correction` and in the first claim after it level, and a level head on the host's screen; its raise test also
  keeps the look through the knockdown's `Correction` and the revive; a joiner who died looking up, the round won
  before its respawn, is level with the yaw it had after `End -> Lobby`'s placement and its `Correction`'s facing,
  and after looking up in the lobby the next deal levels it again; `NetPair.win()` ends the round, the fixture's
  crew win), `player_network_test.gd` (a refused claim's `Correction` keeps the look),
  `player_controller_downed_test.gd` (the dead and the left neither turn nor tilt; `look_level()`; only a
  `PlayersPlaced` naming the own player or the own `Respawned` levels, another's keep the look),
  `client_session_claims_test.gd` (`set_facing`).
- Not headless: the mouse itself (headless keeps no mouse mode, so the tests call `look()`, which the mouse's
  `_unhandled_input` calls); the respawn part of the one-PC playtest.

#### 4.7.14 What the client renders
What the client renders follows the ADR's checklist (its §3), which `netcode-security-reviewer` checks on every
M4 client PR: only the own model, the interpolated poses and the own mode; spectating from the public snapshot only;
the downed camera at or below eye height, never through the level, and showing nothing out of sight of the body's
eye; no screen with an item's or a player's
position, and no name or marker over a player or an item drawn through walls (no `no_depth_test` at all, since the destination marker of D10 (b) went in #829; the teammate marks of #257 and #756 show only past no level
geometry, within 10 m, §4.7.29; a zone's fill, which tells that a living player stands there, is depth-tested like
the zone and hidden by the downed camera's sight hiding, with no marker, label or HUD line, §4.7.51); a role named
only on its own player's screen
(a dissident's teammates on theirs, the plates' teammate mark too); no hit confirmation for
the attacker beyond the accepted exceptions; hidden information in debug builds only (the debug overlay, F3).
World sounds play within the hearing range only (E33), measured from the ears (E40). What the client plays of voice
follows the M5 ADR's checklist (its §3; §6 below).

#### 4.7.15 Hearing voice (M5-5, #219)
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

#### 4.7.16 Occlusion's muffle (M5-7, #221)
(the CC0 files had not arrived then: they, their credits and CI's Ogg stand-in came with #525, §4.7.43;
CI's LFS step with #515):
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

#### 4.7.17 Speaking (M5-6, #220; §6.5.3 Capture and the gate)
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
  microphone, the mode, the threshold, RNNoise, the four volumes, the mark, and since #208 the interface language,
  §4.7.26; written on each change). `Game` reads this
  window's file unless a test sets `settings` (with `read_command_line` off, as in tests and playcheck, the settings
  stay in memory and touch no file), wires the tab, gives the sender each session, counts the talk key
  (`voice_talk`, V), under the Esc menu too since #488 but never while a text field has the focus or a key capture
  runs (`GameTalk.typing`), and closes the microphone on exit. `project.godot`: `voice_talk` and
  `audio/driver/enable_input`.
- `client/ui/`: `VoicePanel`, the Esc menu's Voice tab in every screen (`EscMenuState.Tab.VOICE`, last in the enum so
  the previews' saved numbers hold); the lobby HUD's hint until a microphone is picked (a chip over
  the ready chip since #495); the debug overlay's own voice
  line (`DebugOverlay.own_voice_text`: gate, peak, frame age, encode µs). No talking indicator (D14).
- **The main menu's Voice page** (#301, the follow-up of #220's Esc-only tab; since #493 the Settings panel, §4.7.38):
  `MainMenu`'s Settings item opens a second `VoicePanel` (the same class, in its light look); Esc closes it and
  opens no Esc menu. `Game` wires both panels to its one `VoiceControl` and feeds the one on screen
  (`Game.shown_voice_panel`), so a pick there is saved in this window's `UserSettings` and opens under the mark as in
  the tab. With no `ClientSession` the sender still captures and gates for the meter (its `may_speak` is false
  without a model, and it has no `send`), so nothing leaves; the Settings panel closes when a session ends.
  Tests: `tests/unit/client/ui/main_menu_test.gd`, `game_voice_test.gd` (a pick on the page saved and opened under
  the mark; the meter with no session, nothing sent even to a send of the test's own; both seen failing with the
  page unwired or `may_speak` true without a model), `esc_menu_input_test.gd` (Esc leaves the page, seen failing
  without it). `shot`: `client/dev/menu_voice_preview.tscn`.
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
  window in `tools/runner/tests/test_hostjoin.py`. `shot`: `client/dev/esc_settings_sound_preview.tscn`,
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

#### 4.7.20 `tools/runner/hostjoin.py` (#149, M4-6)
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

A failed import (#949): `check.run_import` runs an import that exits non-zero once more (a timeout, `IMPORT_TIMEOUT`
300 s, is not run again). Each failed attempt's log is kept as `tools/out/logs/<label>-attempt-<n>.log` (the next
attempt overwrites `<label>.log`; a first failure clears older ones), a signal exit is named (`-11 (SIGSEGV)`),
and the Failure names those logs and quotes the last 25 lines of the last attempt's output, so a CI log alone tells
a hang from a crash; CI keeps `tools/out/logs` as each part's artifact. `RealPointerTest`, whose logs live in its
temporary folder, copies them to `tools/out/logs/<test method>/` when it fails. Its import of every stand-in crashed
now and then in CI (exit -11, twice in a row) and on Windows (0xC0000005: 2 of 50 runs of the test, both attempts
ending at `reimport | a.otf`). Measured for #949 on Windows, fresh imports of a throwaway project: the TTF and OTF
stand-ins together crashed 6 of 140, the other stand-ins 0 of 80, the TTF stand-in alone and the real Comfortaa
alone 0 of 100 each; the cause is open in #949.
Tests: `tools/runner/tests/test_lfs.py` (`CheckTest`: over a faked Godot, a crash twice, a crash and then an import,
a timeout, an import that printed nothing, and the attempt logs each leaves).

The [LFS ADR](decisions/2026-09-29-git-lfs-for-binary-assets.md)'s amendment of 2026-10-07 (#515): in CI
(`common.IS_CI`, and a Claude Code cloud session, `common.IS_CLOUD`: checkouts that may have no LFS content) every
`check.run_import` keeps the LFS pointer files from Godot's import (`lfs.aside`), whose import of one fails and
rewrites its `.import` file. Each pointer file goes into `tools/out/lfs-aside/` (behind a `.gdignore`); a type with a
stand-in (`lfs.STAND_INS`: PNG, JPEG, WebP, BMP, TGA, WAV, glTF, GLB, OBJ, and since #520 TTF and OTF) gets a
minimal valid file of its type in its place under its committed `.import` file, so Godot writes the imported file every use of the asset loads (later
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
--local --no-replay` on a free port; a scenario with the `tutorial` header has that one window only, started with
`--tutorial`, #601, §4.7.44), up to two more windows join it, and the players after them are bots in one
headless process (`tests/harness/playcheck/`: `NetPlay`'s bots playing a `BotScenario`'s scripts over ENet). Each
window runs under `tools/playcheck/playcheck_window.gd`, a `SceneTree` script under `tools/` that adds `game.tscn`
with its `LaunchOptions` arguments and runs that window's steps (`playcheck_steps.gd`). A wait reads only the
window's own `Game.client()` (its `ClientSession` and `ClientModel`), its screen, Esc menu and pointer, never
`HostSession`, the match or `core/`, on the host's window too (invariant 2), so a window that draws before its
filtered event arrived fails its wait instead of being covered by the host's state. `wait text <field>
is|has|lacks <text>` and `wait shown <field> on|off` (#275) read what the window draws: the `Hud`'s labels, the
`LifeScreen` (#497), the `LobbyHud` (#495: `lobby.status`, `lobby.ready`, and `lobby.roster`, a line per row "<name
as drawn> ready" or "not ready"), the `EndScreen`, the `TutorialScreen` (#492: `tutorial.step`, its "Step n of N", and
`tutorial.how`, its how line as drawn), the visible Esc tabs and the kind in the `FirstPersonHand` under
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
`Viewport.get_texture().get_image().save_png` after `frame_post_draw`, as `shot` does. The windows stay off every
screen as `shot`'s does (never headless: Godot then draws nothing; `playcheck_window.gd` calls
`tools/offscreen/offscreen.gd` `place()` first, since Godot clamps `--position` onto the screen, #1141, AGENT_WORKFLOW
§11.4), with the dummy audio driver and a `MousePointer`
that only remembers, so the real mouse is never captured. The item keys read the game's pointer
(`ItemInteractions.mouse_captured`, which `Game` gives `pointer.captured`, #1114), so `hold use` (the left button has
no key to press) uses the hand item and takes the viewfinder's shot (`house_photo`). Spectate cycling reads the
game's pointer too (`LifeView.mouse_captured`, `pointer.captured`, #1117), but `spectate_next` and
`spectate_previous` are the mouse buttons alone and no playcheck step drives them (`spectate.txt` watches its one
target), so cycling stays with the playtest.
Window 1 sends the setup (`ForceRole`, `ForceClock`, `ChangeSettings`, and the header `map`'s ChangeSettings: a match plays the House unless a script that walks on flat ground names the greybox test bench, #767) as the host's own
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
roster and countdown, the downed and spectating plates (#497) and the knife in the first-person hand besides their PNGs,
and since #276 the Hand and Belt lines through a pick-up, a swap and a put-down, the end screen's winner, its
countdown (`end.countdown`) and the return with no button press, the lobby's
cleared ready flags after End and a second round. A text wait reads a Label as drawn, `atr(text)` (a deck key's
translation; #498), and `end.winner` the winner line shown (`EndScreen.winner_shown()`).

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
ADR's §6 check the rest. A thrown item's arc, stop and fall are pure (`ItemArc`, `ItemFlights`, unit-tested against
core's `ItemFlight.point()` and a fixture match's real throw); the arcs in a physics world, the own arc's sweep
against a fixture wall and the throw's sounds through `ItemWorld` run in `tests/integration/client/world/` (§4.7.52).

#### 4.7.24 The UI's base resolution (#287)
- `project.godot`: the UI is laid out on a 1920x1080 canvas (`display/window/size/viewport_width` and `_height`),
  the size the UI pack's mock-ups and Toy tokens are drawn at, so one mock-up px is one Godot px and no int token
  (border, radius, shadow, font size) is scaled and rounded. It still stretches to the window (`canvas_items`,
  `expand`; the 3D view renders at the window's size), and `window_width_override` and `_height_override` keep the
  start window at 1152x648 (`host` and `join` size theirs with `--resolution`; `shot`, `playcheck` and
  `run --offscreen` start at 1x1 and `Offscreen.place()` sizes theirs, #1141). Mouse look reads
  `screen_relative`, which the stretch does not scale.
- Until the screen issues (#489-#498) move each screen to Toy variations, its sizes are those of the old 1152x648
  base times 5/3, rounded (the generated theme, §4.7.25, keeps them for the names it does not map to a Toy look), so
  the screens keep their apparent size: the theme's font sizes, container margins and separations and its style
  boxes' content margins (not the corner radii); the layout widths in `client/ui/` code (the menu's fields,
  `UiParts.BUTTON_SIZE` and its labels, `EscMenu.PAGE_SIZE`, `Hud.SWATCH_SIZE`, the debug
  overlay's inset, the dev test room's overlay box). Godot's default theme, which drew the controls no variation
  styled (fields, spin boxes, sliders, scroll bars, bare labels and buttons), was scaled by
  `gui/theme/default_theme_scale` = 1.6667 until the generated theme covered them: the fields, dropdowns, sliders
  and scroll bars since #576, CheckBox, SpinBox's arrows and the bare Buttons since #1020 (§4.7.30), so the setting
  is unset again (Godot's 1).
- Tests: `tests/unit/client/ui/base_resolution_test.gd` (the base, read back from the running root; the stretch; the
  start window; the default theme's scale, 1 since #1020, read back from `ThemeDB`), seen failing on the old
  `project.godot`. The `shot`s of every preview in `client/dev/` at 1152x648 before and after match in apparent size
  (PR of #287).

#### 4.7.25 The generated theme (#288)
- The flow: a tag `ui-<semver>` of xperiaroco2/prime-game-ui → `tools\run.cmd ui-sync <tag>` (AGENT_WORKFLOW
  §11.26: the pack's JSON and SVG in `client/ui/theme/pack/` under a `.gdignore`, `client/ui/theme/pack.lock.json`)
  → `tools\run.cmd run tools/theme/build_theme.gd --headless` → `client/ui/theme/game_theme.tres` (its uid
  `uid://c8behqt7jtcn8` kept with `ResourceSaver.set_uid`, a headless save writes none) and `game_theme_large.tres`.
  Both are generated, never edited by hand. Pinned at `ui-0.8.0` (since #1020; `ui-0.4.0` before).
- `tools/theme/mapping.json` is the engine knowledge, data: pack states to Godot StyleBox names
  (`hover-pressed` → `hover_pressed`), the 19 fields to `StyleBoxFlat` properties, per-state `font-color` to the
  `font_*_color` items, `items` (kebab-case to the Godot item), `label` to `font_size`, `press.*`, `size.*` and
  ToyButton's `motion` to custom constants (`press_depth`, `press_hover`, `press_held`, `press_disabled`, `width`,
  `height`, `min_width`, `wide_min_width`, `wide_width`, `press_duration_ms`, `press_duration_reduced_ms` from the
  reduced-motion mode, `press_trans`, `press_ease`), the health ramp to the colours `ramp_stop_00` … `ramp_stop_20`
  (ToyBarHealth), ToyMic's `icon_on` and `icon_off`, and the `empty` list to one `StyleBoxEmpty`. ToySlider's
  `focus` StyleBox is written though Slider draws none: `ToySlider` draws that ring (§4.7.27). Custom items are what
  the Toy components' code reads; the mapping names which items are custom and which bound items Godot's default
  theme leaves out (Button's `hover_pressed`, ScrollContainer's `scrollbar_h_separation`).
- `tools/theme/theme_builder.gd` (preloaded, no `class_name`) checks a pack against the mapping (an unmapped class,
  state, token or texture, a name that is not letters only or is an engine class, a broken ramp or motion, a bad
  base type, §4.7.30, stop the build) and builds the `Theme` in memory; each StyleBox has the sub-resource id
  `<Variation>_<item>`, so a regenerated file differs only where a value did. `build_theme.gd` also stops when the
  pack differs from its lock or the project's UI base is not the pack's `reference` (1920x1080, #287), which the
  tests also hold.
- What it writes: the pack's live type variations (118 at `ui-0.4.0`, 122 at `ui-0.8.0`; ToyChipNew, ToyChipNewText and
  ToyHowtoCaption are deprecated and skipped); since #576 also the base types under their engine class's name, the
  engine's SpinBoxInnerLineEdit and a default font size (§4.7.30); the pack's textures as icons and, once its file is
  in the project (since #684), the font (§4.7.34). Each theme also carries
  the pack's `base` and `toggle` hints as its metadata `toy_hints` (mapping `hints`; §4.7.27). The large-text theme
  is a whole theme that differs only in font sizes and the keycaps' `min_width` (42, from `modes.textSize.large`):
  `GameUi.set_large_text` swaps to it.
- Today's names are thin variations of Toy ones, so the screens restyle with no code change (the issue's list):
  HudPanel, LifePanel, TaskPanel → ToyPlate; HudText, TaskRow, LifeText → ToyTextOnDark; HudHint → ToyHudCaption (not
  in the issue's list: a hint reads below HudText); HudTitle, Title, EndTitle, LifeTitle → ToyTitleOnDark;
  TaskDescription → ToyTextMutedOnDark; EscShade → ToyBackdrop; EndBackdrop, LoadingBackdrop → ToyBackdropNight;
  LifeBar → ToyBarProgress with its own `background` (left and right content margins 267, the bar's width;
  `Theme.get_stylebox` does not follow variations); EscTab → ToyMenuItem, not the issue's ToyTab, whose ink text is
  unreadable on the Esc menu's dark panel. The names the issue does not map (the containers' margins and separations,
  DebugText, HudCrosshair, Shortfalls) keep their greybox values at #287's sizes in the mapping's `keep`.
- The pack also gives (#520, the font file #684; §4.7.34) the theme icons from its `textures` (an imported copy of
  the pack's assets under the same lock), the Delivery card art, and the font hook (`font.file`: a FontVariation per
  label weight).
- Tests: `tools/runner/tests/test_ui_sync.py` (the sync from a fixture repository, byte for byte with a CRLF blob, a
  binary outside the assets list deferred, stale files removed, a bad pack leaving the pinned copy untouched, the tag already pinned not
  fetched, each problem the offline verify names on a mutated copy, a pack SVG missing from the lock, and the
  committed copy against its lock); `tests/unit/tools/theme_builder_test.gd` (every variation mapped and each planted
  gap named, a StyleBox state missing a field too; every mapped engine item and icon name in the class reference, with
  a planted typo and a custom item that shadows an engine one; names letters only and no engine class but the base
  types (#576); the committed themes equal a fresh
  build, which is deterministic, seen failing on a planted stale value; the uids; spot values, the press motion and
  the ramp; the large-text theme; the legacy and kept names; the project's base against the pack's `reference`, seen
  failing on a probe at 1152). `theme_test.gd` runs unchanged on the generated theme.

#### 4.7.26 English and Ukrainian (#208 (a))
The game speaks English and Ukrainian (the engineer, 2026-10-02). Part (a) builds the base the Toy screens use;
host-made text as ids with arguments on the wire is #548 (§4.7.45), and the source test against literal strings, the content
names and the font's glyphs are #549 (§4.7.48).
- **The copy deck.** The texts are the UI track's copy deck, `copy/strings.csv` of xperiaroco2/prime-game-ui, in
  Godot's CSV format (`keys,en,uk,?plural,?context`; its rules in that repo's `copy/README.md`). `tools\run.cmd
  ui-copy <tag>` (AGENT_WORKFLOW §11.27) copies it at a release tag into `client/i18n/strings.csv`, byte for byte,
  with `client/i18n/strings.lock.json` (repo, tag, commit, sha256); now `ui-0.8.0`, 270 keys in 274 rows (since #1025;
  `ui-0.6.0` before, 265 keys in 269 rows). Never edit the deck here: a change goes to the UI repo, a new tag, then
  `ui-copy`.
- **The translations.** Godot's import writes `strings.en.translation` and `strings.uk.translation` beside the deck
  (gitignored: every import rebuilds them); `project.godot`'s `[internationalization]` lists both, so every run loads
  them. A screen sets a Control's text to a key (Godot translates it and retranslates it on a switch) or calls
  `tr(key)` and fills the placeholders with `String.format({...})` after it, rebuilding on
  `NOTIFICATION_TRANSLATION_CHANGED`. A number before a word that changes takes `tr_n(key, key, n)`: Ukrainian has
  three forms (one when the number ends in 1 except 11: 1, 21, 31; few when it ends in 2 to 4 except 12 to 14: 2, 22; many otherwise: 0, 5 to 20, 25), which the deck writes as the
  key's row and two rows without a key.
- **The language.** `UserSettings.language` (`[interface] language`, "" before any choice, an unknown one reads as
  "") holds the player's choice; key bindings get their own file (#211). `Languages` (`client/app/`) names the two
  (`lang.en`, `lang.uk`, each in its own language in both columns), picks the first launch's language (Ukrainian
  when `OS.get_locale_language()` is `uk`, English otherwise; not written to the file, so until a choice the game
  follows the system), applies it with `TranslationServer.set_locale`, and `choose()` applies and saves a pick at
  once, for the settings screen. `GameSettings.ready_settings` applies it before the voice settings and the first screen. A Game with no command line (a test, a playcheck window) ignores the machine's language and speaks English unless its settings say otherwise.
Tests: `tests/unit/client/i18n/translations_test.gd` (both translations listed and loaded, every key in both
languages, Ukrainian plurals for 1, 2, 5, 11 and 21 directly and through `tr_n`, the deck against its lock),
`tests/unit/client/app/languages_test.gd` (the first launch, the choice over the system, a switch at once that
outlives a restart, an unknown language), `user_settings_test.gd` (the language's round trip and fallback),
`tests/integration/client/app/game_language_test.gd` (a saved choice is the locale at the start; seen failing
without `Languages.apply`), and `tools/runner/tests/test_ui_copy.py`.

#### 4.7.27 The Toy components (#289)
The Toy look's behaviour that a theme cannot hold (prime-game-ui `ui-0.4.0`: its spec's sections 5, 6 and 19 and
the issue's comment of ui-0.2.0), all in `client/ui/` and built on the generated theme only (no override, no
`Color(...)`, no font size: `theme_test.gd`).
- **Hints.** The pack's `base` (the toy base under a raised face, per screen context `dark`, `light` or `any`) and
  `toggle` (the selected partner) are not theme items: the generator writes them into each theme's metadata
  `toy_hints`, which `ToyHints.base_for(variation, context)` and `selected_for(variation)` read. `check_pack` stops
  on a base that is not a live Panel variation, a context outside the three, or a partner that is not a live
  variation of the same class. A legacy name (EscTab) has no hints, as its ToyMenuItem has none.
- **`ToyRaised`** (a `MarginContainer`): the base `Panel` first (its variation from the hints, `mouse_filter`
  IGNORE, hidden while there is none or while a button face is disabled), then the face. The base StyleBox draws
  the face's shape moved down by its depth through expand margins, so layout and the hit area are the face's. The
  wrapper takes placement, size flags, minimum size and visibility; the face keeps its variation, text and signals;
  the base follows the face's variation on its theme change. The wrapper reserves no room for what the base's and
  the face's StyleBoxes draw outside its rect (expand margins: ToyTitlePlate's base reaches 36 px out): the caller
  leaves that gap, read from the theme (the showcase's `_room_for_base`).
- **`ToyPress`** (an internal child of every Toy button): `offset_transform_enabled`, and the face's visual-only
  `offset_transform_position:y` moves to `press_disabled` if disabled, else `press_held` while held (`button_down`
  to `button_up`: mouse, touch and `ui_accept`) or while a toggle is on, else `press_hover` while the pointer is
  over it, else 0. It re-evaluates on `draw`, `button_down`, `button_up`, `mouse_entered`, `mouse_exited` and
  `toggled`, and tweens only when the target changes (`TRANS_SINE`, `EASE_OUT`, `press_duration_ms` 70, or
  `press_duration_reduced_ms` 0 under `UiPrefs.reduced_motion`). A container's sort sets position and size, never
  the offset transform, so a press survives a re-layout or a theme swap. A face disabled while held drops the hold
  (Godot sends no `button_up` then and drops the release on a disabled button), so it is not sunk once enabled. A
  raised toggle that stays on (the Esc
  menu's Ready, a selected preset card) rests at `press_held`: #289's choice, to judge in the interactive showcase.
- **`ToyToggle`** (an internal child): on `toggled(true)` the variation becomes the partner (ToyTab, both
  ToyChipToggle, ToyRadio, ToyPresetCard), and back on `toggled(false)`; companions (a card's note) swap with it;
  `sync()` after `set_pressed_no_signal`. ToyMenuItem and ToyKeyButton have no partner and draw their own pressed
  look.
- **`ToyBar`**: a ToyBarTrack holding a fill-only `ProgressBar` (ToyBarHealth or ToyBarStamina, no percentage). The
  health fill's `self_modulate` is `ramp_stop_NN` of `step = clampi(floori(hp * 20 + 0.5), 0, 20)` (the downed
  bleed-out bar too); the stamina fill keeps its colour. **`ToySlider`** draws the theme's ToySlider `focus` box over
  itself while it has visible (keyboard or gamepad) focus, `has_focus(true)`.
- **`UiParts`**, the one way to build them: `button()` returns the `ToyRaised` (its `face` is the Button; by default
  ToyButtonSecondary on a dark screen; `BUTTON_SIZE`, the M4 width, on the wrapper), `raised()` (ToyPanelMenu,
  ToyPanelDialog, ToyPanelHowto, ToyMapBoard, the ToyTitlePlate Label), `toggle()` (a flat toggle with ToyPress and
  ToyToggle: tabs, chips, radios, menu items, keycaps), `sized()` (`width`, `height`, `min_width`, `wide_width`,
  `wide_min_width` into `custom_minimum_size`, keeping a dimension the variation lacks, again after each theme
  change; deferred, as during `theme_changed` `get_theme_constant` still answers from the old theme's cache,
  observed on 4.7.2) and `scroll()` (a ToyScroll with the ToyScrollBar). Today's screens changed only where
  `button()` now wraps: the menu, connecting and Esc buttons are Toy buttons, and the Esc menu's tabs are `toggle()`s
  of EscTab (`tab_buttons` still maps the Buttons). The screens' own Toy layouts are #489-#498.
- **Large text and reduced motion.** `GameUi.set_large_text(on)` gives every screen that holds the shared theme
  `THEME_LARGE` (or back) live; a screen with its own theme keeps it, a later one gets `shared_theme()`.
  `UiPrefs.reduced_motion` (a bool) defaults from `DisplayServer.accessibility_should_reduce_animation() == 1`:
  it answers -1 for unknown (Linux, the Steam Deck, headless), which GDScript reads as true; the screen issues
  read it for the connecting spinner and the fades. Settings > Accessibility sets both and `UserSettings` saves
  them (`large_text`, `reduced_motion`; #491, §4.7.42).
- **The showcase** (`tools/theme/showcase.gd`, a dev tool): every live variation on its night or cream stage at
  1920x1080 in four pages, shot with `tools\run.cmd shot tools/theme/showcase.tscn --size 1920x1080` and the same for
  `showcase_1.tscn` to `showcase_3.tscn`. A Button row has each state Godot can force: hover through a per-cell theme
  that draws the hover StyleBox (Godot cannot force a hover) plus the hover offset, held, disabled, focus drawn over
  the face, selected and selected + hover; then a live cell. `showcase_interactive.tscn` (page chips, large text,
  reduced motion, a live health slider) is for a human, in a window:
  `tools\run.cmd run tools/theme/showcase_interactive.tscn --seconds 3600`. Feedback goes to the UI track as token
  changes, never as edits in the game.
- Tests: `tests/unit/client/ui/toy_press_test.gd` (the targets per variation from the theme; the base unplugged,
  seen failing without its line; one tween per changed target; reduced motion; the raised toggle on; the offset
  after a sort and a theme swap; a face disabled while held, seen failing), `ui_prefs_test.gd` (only 1 is on; a
  bool after `reset()`), `toy_raised_test.gd`, `toy_toggle_test.gd` (every pair, a ButtonGroup, no
  partner, a companion, `sync()`), `toy_bar_test.gd` (step(0.22) = 4, (0.8) = 16, (1.0) = 20, (0.23) = 5 against a
  floor, the clamps; all 21 stops in both themes; the fill's colour), `toy_slider_test.gd`, `ui_parts_test.gd`
  (the large keycap's 42 after a theme swap), `large_text_test.gd`; `theme_test.gd` also reads the builders'
  variation names (seen failing on a planted `EscTabb`); `tests/unit/tools/theme_builder_test.gd` (the hints, three
  planted hint problems, a changed hint seen by the stale test); `theme_showcase_test.gd` (the pages show every live
  variation, seen failing with ToyMic left out; the interactive switches: the health slider, reduced motion,
  large text, the page). The look: the four shots in the PR.

#### 4.7.28 Give-up on F and the controls the player rebinds (#211)
- `project.godot`: `give_up` moves from G to F, Ready's key in the lobby. The two never act in one phase: `Game`
  reads `ready` on the lobby screen only, `LifeView` reads `give_up` only in the round while downed.
- `client/app/Controls`: the 19 rebindable actions of Settings › Controls (#488's 16, `crouch` and `sneak` after `jump`, #951, #1009, and `throw` after `swap`, #851) in order with their `control.*` deck
  keys; their defaults from `project.godot` (ProjectSettings `input/<action>`, never the InputMap, which `apply()`
  rewrites); each action's phases (`Controls.PHASES`: the lobby, living, downed or dead, from what reads it today:
  movement in the lobby, living and downed, sprint and jump in the lobby and living, the item keys and `interact`
  living, the map on any life, talk in the lobby and living, `give_up` downed, `ready` the lobby, the spectate
  buttons dead; no action acts in the pregame, which is frozen and silent, #213); `clashes_of()`, the "same key"
  check per phase (#488's rule 6), under which `give_up` and `ready`
  share F legally. A binding is a bare physical key or mouse button (not the wheel, which only clicks), no modifiers,
  for every device (-1, as `project.godot`); Esc is never bound (#488's rule 2), nor the keys of the fixed actions
  `debug_overlay` (F3) and `toggle_fullscreen` (Enter), on which both would act. `Controls.UNLISTED` holds the actions that
  act on their `project.godot` key but have no Settings row yet, with their phases: none now (`throw`, G, #645, alive, left it
  for a row in #851; `crouch`, Ctrl, #791, in #951; `sneak`, the left Alt, #990, in #1009). `bind()` refuses a binding that would put an action of such a phase on
  that key (`unlisted_on()`; one press must never do both), and a saved one reads as the default.
  The player's file is `user://controls.cfg`, one per PC (not per window, unlike `UserSettings`), holding only the
  actions bound away from their default as `key:<physical keycode>` or `mouse:<button index>`, so a changed default
  reaches every player who never rebound it; a missing, damaged or foreign entry keeps the default. Each window keeps
  its copy in memory, so with two windows open the last to save wins. `Game` reads and
  applies it at the start; a `Game` without a command line (tests, playcheck windows) keeps the defaults and never
  touches the InputMap.
- `client/ui/KeyLabel`: the label of an action's binding now (`of_action`, `of_event`), for every key prompt and the
  Toy screens' keycaps (#488's rule 7, #491, #495, #497): the physical key's label on the current layout
  (`DisplayServer.keyboard_get_label_from_physical`: AZERTY's physical Q reads A) when it is Latin, else its US name
  (`KeyLabel.shown()`: a Ukrainian layout labels the physical F "А", probed in a window on 4.7.2, and the prompt
  reads F; headless Godot has no layout and prints an error, so it reads the physical key's name there), the deck's
  `key.space`, `key.mouse_left` and `key.mouse_right` only through #208's translations (§4.7.26: Space, Пробіл;
  no table of its own), as are `Controls`' action names and `ControlsPanel`'s words. `LifeHud` (the give-up key,
  through `LifeHud.Local.read_keys()`; since #497 the Toy downed screen's keycap inside the deck's
  `downed.give_up_hold`, §4.7.41, and no spectate key), `LifeView.raise_cue()` (the HUD's raise cue, the deck's
  `tutorial.step.downed.how`, §4.7.41), `ItemInteractions.hint()`'s pick-up and the Voice tab's push-to-talk name
  use it, so each follows a rebind (`LobbyHud`'s hint did until the Toy lobby HUD dropped it, #495). Known gap
  until the Toy screens (#491's Settings page keeps the Voice rows' greybox lines) move these sentences to the deck:
  they are greybox English in every language, so under Ukrainian a mouse button or Space reads in Ukrainian inside
  one (the pick-up hint's "ЛКМ: pick up <item>" after a rebind).
- `client/ui/ControlsPanel`: the Esc menu's new Controls tab (`EscMenuState.Tab.CONTROLS`, in every screen, after
  Voice): a row per action with its name, a key button with the label and a "Same key" mark (`Shortfalls`). A click
  or `ui_accept` starts a capture; the capture runs in `_input`, before `Game._input` and the GUI, and consumes every
  event but the wheel (it scrolls the page): the next key or mouse button press binds (applied and saved at once), a
  release or an echo does nothing, a click on another key or on Reset cancels and reaches that button, Esc cancels
  with the menu left open, and hiding the panel cancels it. Reset to defaults empties the file; it is a Toy button
  (`UiParts.button()`, §4.7.27), the key buttons plain ones. `GameUi` builds the panel before `Game` applies the
  player's language, so it writes its words again on `NOTIFICATION_TRANSLATION_CHANGED` (`retext()`, §4.7.26), and
  `screen_preview` sets English first, so its shots read the same on every machine. The Toy Esc menu (#491) hosts
  the panel in its Settings page and restyles it.
- Tests: `tests/unit/client/app/controls_test.gd` (the defaults, the phases, the clash per phase, saving only the
  rebound actions, loading, reset, the fallback for a missing, damaged or foreign file, `apply()` matching real
  keyboard and mouse device ids, F3, Enter and the wheel refused),
  `tests/unit/client/ui/key_label_test.gd` (the deck's words in English and Ukrainian; these suites set the locale,
  as the machine's language is the test run's), `controls_panel_test.gd` (the capture binds, ignores releases and
  echoes, cancels on Esc and on a click on another button, lets the wheel through, marks a clash, resets, follows a
  language switch after it was built), `life_hud_test.gd` (the give-up key is the one bound now; since #497 the
  screen's keycap follows a rebind through the life view, `life_screen_test.gd`),
  `input_actions_test.gd` (`give_up` is F); `tests/integration/client/app/esc_menu_input_test.gd` (through real key
  events in the Controls tab: Esc cancels a capture and leaves the menu open, K rebinds Ready, a click on another
  row's key cancels the capture and starts that row's, K then toggles Ready
  and F no longer does; seen failing with the capture not consuming its events) and
  `tests/integration/client/life/life_network_test.gd` (a downed joiner gives up on F held, not on G, and no F in the
  round readies; seen failing with G bound). The `shot`s: `client/dev/esc_settings_controls_preview.tscn` (the page
  with a same-key clash) and `life_give_up_preview.tscn` (the downed screen's "Hold F to give up", from a real
  window's layout; the Toy plates since #497).
- Since #491 the Controls page is a sub-page of Settings, the same scene in both menus (§4.7.42).

#### 4.7.29 Name plates (#257; the names removed by #756)
Plates over the other players' heads, in line of sight within about 10 m for now (the engineer as the designer,
2026-10-03, on #257: to revisit after the playtests). Since #756 no player has a name over the head, in the lobby or the
round, standing or crouching (the engineer's KD2 answer; names stay in the lobby's player list, the end screen and the
vote screen), and the plate is the **teammate mark alone**, drawn only on a dissident's own client over a fellow
dissident (his answer 5 on #516). The classes keep their #257 names. The tree and the numbers were the UI handoff's
(prime-game-ui `docs/handoff/s07-hud.md` `Plates`); the look is provisional: the Toy round HUD (#489) restyles it. If
the UI design still draws a name on `Plates`, that is for the UI track (#150).
- `client/ui/NamePlates` (`Plates`, the first child of `GameUi`, so under every screen, with the shared theme and
  the large-text swap; shown on the lobby and round screens only) keeps one `NamePlate` per marked fellow dissident whose
  body `AvatarViews` draws. A plate shows only while the body is drawn (`SightHider` hid none of it) and not watched
  from its eyes (`RemotePlayerBody.is_watched()`), its eye (the head standing, the lying capsule's middle downed) is
  within `NamePlates.RANGE_M` (10 m, the engineer's value, the one place to change it) of the viewport's camera, the
  plate's point is in front of the camera, and one ray from the camera to the eye meets no level geometry
  (`SightHider.sees`, the world layer only, so no mark is ever drawn through a wall: §4.7.14). While the downed
  camera's `SightHider` is active (`NamePlates.hider`, `LifeView.hider()`), the body's eye must see the player's eye
  too, so the arm's camera shows no more than standing at the body would (the M4 ADR's §3 item 3). The rays run in the
  physics frame at priority 11, after the bodies moved (-80) and `SightHider` hid (10); each drawn frame centres the
  shown plates on `Camera3D.unproject_position` of the point `ABOVE_HEAD_M` (0.35 m) over the head (over the lying
  capsule downed). A plate of a player who has no body any more is freed.
- `NamePlate` is `Plate` ToyNamePlate > `Mark`, a `TeammateMark`, and nothing else: no name, no role, no health, no
  life state. `NamePlates` makes a plate only for a peer with `NamePlates.marked(model, peer)` (and runs the sight rays
  only for those): the peer is in the own model's `teammates[role]` (its own Teammates, which the host sends only to a
  role whose players know each other, so only to dissidents) and is not the own player; an engineer's client, the
  lobby and a dissident's view of a non-teammate have no plate at all, so the per-peer filtering is unchanged: the
  mark is drawn from what the dissident's own filtered view carries. `TeammateMark` is the handoff's 20 px
  `TextureRect` of the pack's `teammate-mark.svg` (imported by #520, §4.7.34), tinted with ToyNamePlateText's
  `font_color` through `self_modulate`.
- The ray meets only the world layer (1), while a body is hidden by what the level draws: a look a player can hide
  behind (a partition, a tarp, a shelf) needs a layer-1 collider that covers it, or the plate shows through it
  (`levels/CLAUDE.md` keeps looks and colliders apart on purpose). Today's levels have only floors.
Tests: `tests/integration/client/ui/name_plates_test.gd` (a real `AvatarViews` drawing five players from snapshots in
a `SubViewport` world, the own player a dissident: a teammate's mark in sight within 10 m centred over the head; none
behind a wall, beyond 10 m, behind the camera, for a body hidden or watched, on a hidden layer or for a player who left;
the mark for a dissident's teammate only, none over a non-teammate, on an engineer's client or in the lobby; no text on
any plate, a downed player's included; a downed player's mark over the lying body; a downed camera's mark needing the
body's eye to see the player; seen failing without the ray, without the hider's ray and with a mark for everyone),
`tests/unit/client/ui/name_plate_test.gd` (the tree `Plate` > `Mark` with no label, the plate shrinking when the theme
swaps back, the mark's tint, `marked` for a dissident, an engineer and the lobby, the layer under every screen on the
lobby and round screens only). The `shot`: `client/dev/name_plates_preview.tscn` (a teammate with the mark and no name,
a head over a wall and a player beyond 10 m without one).

#### 4.7.30 The generated theme over the base controls, with ui-0.7.0's looks (#576, #1020)
- The screens build bare `LineEdit` (the menu's code and address), `OptionButton` (the Voice tab's microphone and
  mode), `HSlider` (its threshold and volumes), `ScrollContainer` (the Esc menu's pages) and `Button` (the lobby's
  copy button, the Controls tab's reset button), with no type variation, so Godot's default theme drew them. No
  screen builds a `SpinBox` or a `CheckBox` today; their looks are there for the ones that will. `tools/theme/mapping.json`
  `base_types` now styles those classes under their own name: `from` copies every item of a live, parentless pack
  variation of that very class, the same objects (a StyleBox stays one sub-resource `<Variation>_<item>`): LineEdit
  ← ToyField, OptionButton ← ToyDropdown, PopupMenu (its list) ← ToyDropdownList, HSlider ← ToySlider, VScrollBar
  ← ToyScrollBar, ScrollContainer ← ToyScroll; since #1020 (the UI track's base-type sources of `ui-0.7.0`, the
  engineer's option a on prime-game-ui#52, its steps in prime-game-ui#59) also Button ← ToyButtonPlain (the white
  secondary face, flat), CheckBox ← ToyCheckBox (its boxes the pack's 28 px icons) and SpinBox ← ToySpinBox (yellow
  arrows, the pack's 18 px chevrons). A row's literal items are #287's greybox values for what the pack has no look
  for (Godot's default × 5/3; not a design decision): Label `line_spacing` 5, VBoxContainer, HBoxContainer and
  VSeparator `separation` 7. The theme's `default_font_size`, which a control takes when no type of its chain has a
  `font_size` (bare Label, ProgressBar), is the pack's `font.size.theme-default` at the theme's text size since
  #1020: 27, 34 in large text (mapping `default_font_size.token`; before, a literal 27 in both). The dev test room's
  overlay, the one Control outside `GameUi`, takes `GameUi.THEME`.
- How Godot 4.7.2 looks a theme item up (seen in probes, the plan review of #576): for each theme owner up the tree,
  every type of the control's chain (its variation's chain, then its class and parents), and only then Godot's
  default theme; so a row on a class also restyles its subclasses (a Button row would beat Godot's own CheckBox
  look). `check_pack` refuses a row on no engine Control or Window class, an unknown member, a `from` that is not a
  live parentless variation of that class, and any item that would replace one the default theme sets on an
  engine subclass (read from its item lists: `Theme.has_font_size` is true for every type of a theme with a default
  font size) unless a row of that subclass gives it too (CheckBox's and OptionButton's under the Button row) or the
  subclass is in the mapping's `unbuilt` (#1020: CheckButton, ColorPickerButton and MenuButton, which no screen
  builds and which take the ToyButtonPlain look; `base_controls_test.gd` holds that `client/ui/` builds none, so a
  screen that starts to needs a row first). The chain comes from the theme that names the control's variation:
  SpinBox's field is a SpinBoxLineEdit with the engine's variation SpinBoxInnerLineEdit, which the default theme does
  not name, so it found the theme's default font size before the LineEdit row; the mapping's `engine_variations`
  names it a thin variation of ToySpinField since #1020 (ToyField with 12 px above and below instead of 10, so each
  arrow, half the field's height less the 2 px between them, is at least 24 px high), itself a variation of
  LineEdit, whose row backs it; `check_pack` refuses an engine variation of anything but a base type or a live pack
  variation of a base type's class.
- Left on Godot's default theme (listed in `base_controls_test.gd`; the screen issues #489-#498 and the UI track
  decide): the voice meter's ProgressBar boxes, the bare PanelContainers' panel (no margins), the Esc menu's
  VSeparator line, the hidden HScrollBar. ToySlider and ToyScrollBar are light-context looks (ink fill on a lavender
  track): on the Esc menu's dark panel their filled part and grabber barely show until the screen moves to a light
  panel. Not bound (prime-game-ui#59): CheckBox's radio icons (no screen puts one in a ButtonGroup), its
  `check_v_offset` and `checkbox_*_color`, SpinBox's separators (the default theme's are empty).
- `gui/theme/default_theme_scale` (§4.7.24) stayed 1.6667 after #576: at 1 (its first build, shots in its PR) the
  gaps of then shrank to about 60% in a 1152x648 window (the host's unchecked "Delivery" ban box on the dark Esc
  Lobby tab could no longer be seen, SpinBox's arrows became 6 px chevrons, the check icons 8 px, the key buttons'
  padding 7 → 4). With CheckBox, SpinBox and Button styled (#1020) it is back to 1 (unset); the gaps above draw at
  Godot's own size, and a Toy Button variation with an icon takes Godot's `h_separation` 4 between icon and text
  (7 before; only ToyMenuItem's pack look gives one): the Lobby tab's Ready check sits 3 px nearer its word. The
  `shot`s of 22 previews at 1152x648 before and after #1020 differ in nothing else a person sees (a few pixels of
  the debug overlay's panel corners; the spinner's and the end screen's animation).
- Tests: `tests/unit/client/ui/base_controls_test.gd` (live controls under both themes: a bare LineEdit takes
  ToyField's StyleBoxes, size and colour and a SpinBox's field ToySpinField's, a SpinBox ToySpinBox's arrow boxes,
  icons and items with each arrow at least 24 px high (the line from the committed Comfortaa metrics, as CI imports
  a stand-in font), an OptionButton and its list ToyDropdown's and ToyDropdownList's, an HSlider and a
  ScrollContainer's bar ToySlider's and ToyScrollBar's, a Button, a CheckBox and an OptionButton each their own Toy
  look and a Toy variation still winning; bare text takes the default size and spacing the greybox one; large text
  grows the fields and the default size (34); every engine control class `client/ui/` builds is a base type or
  named with its gap, a planted TextEdit named, and none of `unbuilt`; seen failing on the old theme and, for the
  field's size, without `engine_variations`); `tests/unit/tools/theme_builder_test.gd` (each planted bad row named,
  a Button row shadowing CheckBox too, and a subclass row covering it; the `unbuilt` list skipping exactly the three
  subclasses the check names without it, a bad entry named; the default size a pack token at each text size, a
  missing token and a large 0 named; the base types share the variations' objects in both themes; a base type's
  literal item in the class reference, a planted typo named; the CheckBox and SpinBox icons at their sizes);
  `base_resolution_test.gd` (the scale, 1); `theme_showcase_test.gd` (the showcase shows ToyButtonPlain, ToySpinBox
  with ToySpinField and ToyCheckBox). The `shot`s of every preview in `client/dev/` before and after: only the Esc
  menu's tabs and the main menu's fields change (PR of #576); of the Settings and Lobby tabs at 1152x648, default
  and large text, before and after #1020 (its PR).

#### 4.7.31 The post game screen (#498)
`EndScreen` (`client/ui/end_screen.gd`) is the UI track's post game screen, node for node as prime-game-ui
`docs/handoff/s10-post-game.md` draws it at `ui-0.4.0` (the issue named `ui-0.2.0`; ui-0.4.0 wins): `Night`
(ToyBackdropNight) under `V`, a centred 1440 px ToyColumnThirtyTwo of `Title` (`end.title`), the winner line,
`Result` (ToyColumnEight) holding `Reason`, the 8 px `Gap` and `Back`. Pack variations only, no override.
- **The winner line.** `end.won_engineers` or `end.won_dissidents` by the winning side's id (`SIDE_KEYS`: the base
  mode's `crew` and `dissidents`; a side not there, or no winner, hides both lines). When the own role's side won
  (`own_team_won`, from the own `ClientModel` and the client's own mode) it is `Winner` on the raised ToyTitlePlate
  (`WinnerRaised`, a `ToyRaised` on ToyBaseTitle, SHRINK_CENTER); otherwise `WinnerLoss`, plain ToyTextOnDark. No
  other line says who won, and no role is shown.
- **The reason.** `end.reason.all_tasks` (the round's time as m:ss) or `end.reason.time_up`, by `MatchEnded`'s
  reason, the id of the win condition that ended the round (`REASON_KEYS`: `every_task_done`, `time_up`, #548); any
  other id, `no_crew_present` too (the deck at ui-0.4.0 has no key for it), and a `MatchEnded` without one hide the
  line (and its `Result` box with it, so no empty gap is left). `refresh` takes the reason and the time from the
  model (`ClientModel.ended_by`, `round_seconds`) through `show_reason(id, seconds)`. Hiding the screen clears the reason, the round's time and the
  countdown, so the next End starts without the last round's.
- **The countdown.** `end.back_to_lobby` with End's seconds left, 3, 2, 1 (never 0: at the end tick the lobby takes
  over, #212); hidden when End has none. It and the reason are set with `tr()` and `format()`
  (`auto_translate_mode` DISABLED) and rebuilt on `NOTIFICATION_TRANSLATION_CHANGED`; the other lines are keys
  Godot translates.
- **Behaviour.** Each time the screen shows (End starts; a parent hidden and shown again is not a new End), Night fades in over 0.4 s (`FADE_SECONDS`, a `Tween` on
  its alpha), a cut under `UiPrefs.reduced_motion`, and `outro_began` is emitted: the hook for the one sound of both
  outcomes: the screen plays `UiSounds.outro` on it (#657, §4.7.43). Every Control ignores the mouse and takes no focus. Voice is
  silent in End by #213's rule, not by the screen.
- **Layer.** The handoff's black-screen CanvasLayer 6: `GameUi.black`, shared with #494's connecting, failure and
  loading screen and the pregame (#656), the last on it; the Esc menu opens over it on `GameUi.above` (§4.7.32).
Tests: `tests/unit/client/ui/end_screen_test.gd` (the tree: names, classes, variations, anchors, size flags and
minimum sizes; the pack's variations only; the plate for a win and plain text for a loss from each team's view and
without a role; a side with no key; each reason, the m:ss time and an unknown id; the countdown 3, 2, 1 for host and
client; a language switch; no focus or input; the fade, its cut and the outro hook once per End; the outro sound on the UI bus once per End, #657, started as a new playback each End: not `playing`, which the 0.12 s file loses on the headless driver's mixing thread under load, #948),
`tests/integration/client/app/game_loop_test.gd` (each Game's shown winner line in a real match). The `shot`s, at
`--size 1920x1080 --frames 60`: `client/dev/end_preview.tscn` (win, en), `end_lose_preview.tscn`,
`end_uk_preview.tscn`, `end_lose_uk_preview.tscn` and `end_large_preview.tscn` (win, uk, large text); the game's
own: `tools\run.cmd playcheck end`.

#### 4.7.32 The connecting, failure and loading screen (#494)
prime-game-ui's s3 at `ui-0.4.0` (its handoff `docs/handoff/s03-connecting.md`; the issue linked `ui-0.2.0`, and
where they differ `ui-0.4.0` is built), node for node, in `client/ui/connecting_screen.gd`.
- **One screen, three parts.** `ConnectingScreen` (GameUi's `connecting`) draws GameFlow's `CONNECTING`, `FAILURE` and
  `LOADING`: under `Night` (ToyBackdropNight, `mouse_filter` STOP) one of `Connecting`, `Failure`, or `Loading` and
  `Tip` (or `Head` and the how-to card) shows. `LoadingScreen` is gone. It is on the handoff's black-screen
  CanvasLayer 6, `GameUi.black` (`BLACK_LAYER`), with the pregame and the post game (#656). The Esc menu, layer 4 in
  that table, is on `GameUi.above` (`ABOVE_LAYER` 7) with the debug overlay: Esc in Loading, the pregame or the post
  game opens it over the black, a way out of a hung loading (the engineer's answer (b) on #656). Esc on Connecting
  and Failure stays their Cancel and Back (no Esc menu); #726's rule stands (a new screen closes a menu opened over
  another). Test: `tests/unit/client/ui/game_ui_layers_test.gd`; shots `client/dev/loading_esc_preview.tscn`,
  `pregame_esc_preview.tscn`, `end_esc_preview.tscn` (`ScreenPreview.esc_over`).
- **Connecting.** `show_join(code, step)`: the title `connect.connecting_unnamed` until the host's `Welcome` brings
  the lobby's name (#214, §3.5: `GameJoin.refresh` then calls `set_lobby(model.lobby_name, model.host_name())`,
  `connect.connecting` with the typed name, or `lobby.default_name` with the host's name). That title is wired but
  not drawn today: the frame that folds a Welcome in the Lobby already picks the lobby screen (`GameFlow.screen`),
  so the name shows in the Esc menu's Lobby tab and (#495) the lobby HUD instead; showing it on this screen (a
  short beat after Welcome, or the name in the signalling `found`) is the engineer's call on #214. Then the step
  from `JoinProgress.step()`, a code join's code in a keycap (`ToyKeyOnDark`'s `min_width` through
  `UiParts.sized`, 42 under large text) and the time since Join (m:ss, `GameJoin.refresh`); a Direct join and a
  host show no code row and no address. The spinner turns once a second about its centre, half as fast under
  `UiPrefs.reduced_motion`; it sits in a plain `Control` (`SpinnerBox`, the column's child, the one node beyond the
  handoff's tree), because a container resets a child's rotation at every sort. Cancel is focused; Esc on this screen is Cancel (`Game._input`): it leaves, and the menu's
  fields keep what was typed (a command-line join fills them first, `GameJoin.fill_menu`).
- **Failures.** `EndReasons.FAILURE_STATES` maps every end reason to the handoff's state but `left` and `closed`
  (`NO_FAILURE`); `ConnectingScreen.FAILURES` gives each state its title, body and action. `Game._show_end` keeps the
  end as `Game.failure` (GameFlow's `FAILED` session, `FAILURE` screen, the pointer free) until Back
  (`back_to_menu`, also Esc), Try again (`retry`: `Game._retry`, the last `join_target`, `host` or `host_with_code`
  with the same arguments) or Join directly (`open_direct`: the menu's Direct panel open, its address focused, the
  code kept, #493). Primary is focused with a flat BackGhost beside it, or the raised BackSolo stands alone and
  focused. A code join that the service's `found` ended on another version shows both versions
  (`JoinProgress.found_versions`: "<protocol> (<first six hex digits of the content hash>)"); a Rejected Hello names
  none. The menu draws no reason line since #493 (§4.7.38): the failure says why.
- **Loading.** `GameUi.show_screen` starts it on entering `LOADING` (`show_loading`: one random `TIPS` key, a test
  holds the list to the deck's `tip.*`); `refresh_loading(model)` lists the host (`NetTransport.HOST_ID`) first, then
  the roster's order, the own row `player.you`, each `loading.player_loading` muted until its `PlayerLoaded`; the bar
  is `ClientSession.load_progress()` (the threaded load's progress, 1 once its `LoadAck` went out). `load-card` is a
  hook: `show_card(card)` places #490's card (a `ToyRaised` of ToyPanelHowto) as drawn with `Head`; #254 picks it (§4.7.36).
- Every text is a deck key; the title, the version lines, the code, the names and the time are set from code with
  `auto_translate_mode` DISABLED and rebuilt on `NOTIFICATION_TRANSLATION_CHANGED`.
- Tests: `tests/unit/client/ui/connecting_screen_test.gd` (the tree node for node: names, classes, variations,
  anchors, offsets, grow, size flags and minimum sizes; every end reason's state, texts and buttons; the join states;
  the title's lobby name in both languages; the version lines; the focus as drawn; the loading rows; the tips against
  the deck; the card hook; the spinner's speed; the keycap under large text; every key in the deck),
  `end_reasons_test.gd` (every end but leaving has a state the screen draws), `game_flow_test.gd`,
  `join_progress_test.gd` (the version lines), `client_session_load_test.gd` (the progress),
  `tests/integration/client/app/esc_menu_input_test.gd` (Esc cancels a join and leaves a failure, the address kept,
  Try again focused), `game_loop_test.gd` (`lost` after the host left, `fail-no-answer` then Try again then Back with
  the address kept, `host-failed` then Try again hosting the same way) and `game_code_join_test.gd` (the code on the
  connecting screen, `fail-no-room` and Back with the code kept, `fail-service` and Join directly). The look: a `shot`
  of each state in en and uk, default and large text, from `client/dev/screen_preview.gd` (`s3_state`, `language`,
  `large_text`) in the PR.

#### 4.7.33 The map and tasks screen on M (#253)
The hold-Tab task screen of M4-8 (§4.7.10) became a map and tasks screen that M opens and M closes (the engineer as
the designer, 2026-10-03, on #253). Its Toy look and its keyboard focus are #490's (§4.7.40), the how-to card
#254's (§4.7.36).
- **The key.** The action `task_screen` is renamed `map` and bound to M (physical); Tab is bound to no action (kept
  for an inventory later). Settings › Controls' row "Map and tasks" (`control.map`, #211) rebinds it; its phases stay
  any life. A saved binding under the old name reads as an unknown action and keeps the default. `Game` reads it in
  `_unhandled_input` on the round's screen only, never under the Esc menu (whose Controls tab captures keys);
  `GameUi.press_map_key` closes a how-to card over the map first (§4.7.35).
- **One open state.** `GameUi` holds whether the map is open (`open_map`, `close_map`, `toggle_map`, `map_is_open`;
  the signals `map_opened`, the tutorial's hook, and `map_closed`). It opens only in the round with no Esc menu;
  any other screen closes it, so a new round starts with it closed; `open_esc` closes it after the menu opened, so
  the two never show together (a close request while hosting too). Esc with the map open closes only the map
  (#488's rule 2, `GameUi.overlays`, §4.7.35). While it shows the crosshair hides.
- **The mouse.** Opening frees the mouse (`Game._on_map_opened`); closing captures it again only in the round, with
  no Esc menu and the window focused, as closing the Esc menu does. `PlayerController.mouse_free` (set every frame
  from `map_is_open()`) stops look and the click that would capture the mouse again; move, sprint, jump, interact,
  put down, swap and talk keep working (the designer's answer on #253: the game does not pause; #488's rule 4).
  `use` and the spectate buttons already act only while the mouse is captured. The «?» buttons take the focus of
  the arrows and the d-pad since #490 (§4.7.40); Space, which jumps, is out of `ui_accept` since #488, so a focused
  one never presses with a jump.
- **What it shows** (`client/ui/MapScreen`): the tasks, one row per task type (since #490; DealTasks deals a type once) with its name (`ContentNames.task`, §4.7.48: `task.<id>`, else the
  mode's display name, else the id), its counter (`map.progress`) and a «?» that emits `howto_requested(type)`, on which the
  screen opens that type's how-to card (§4.7.36); no description, no NEW mark (the engineer's #254 comment and the `ui-0.4.0` handoff), no shared
  progress line (nor has the HUD since #489, §4.7.37); the clock (`map.time`). The board (`MapData`): the rooms by name (`room.<id>`, else
  the id), the own pin at the own body's place, turned to its heading, with `map.you_are_here`; no pin for the dead
  (no body). Hovering a row (its «?» included; `gui_get_hovered_control`, since a child takes the parent's hover)
  lights that type's zones, drawn under the room's pictogram and name, and their tag (`map.zone_hint.<type>`, else
  `map.zone_hint`; under the first lit room since #490, §4.7.40). Words built in code are
  set again on `NOTIFICATION_TRANSLATION_CHANGED`. A level with no room hides the board.
- **Rooms and zones from data** (`client/ui/MapData`, pure, read once when a map level loads): a room is a `Node3D`
  of the level with `metadata/size_m` (whole metres), its origin the north-west floor corner, unrotated, plan x = X
  and plan y = Z: the level piece conventions proposed in PR #611. **The room record** (#306) is that node: its id
  `metadata/room_id` (a StringName) and its name `metadata/name_key` (a copy deck key with English and Ukrainian
  text, never the words) beside the outline's `size_m`; no sign and no door-plate position (the engineer, on #306:
  no wall signs). A room without them still draws, its id its node name in snake_case and its key `room.<id>`; a
  room repeating an id is left out. Every House room carries its record on its own scene's root (`levels/house/rooms/`,
  the id its file name, the key the deck's `room.<id>`, ui-0.6.0); the tutorial room's is #715's. Only
  `MapData.rooms_of()` reads that shape (`MapData.Room`: `id`, `rect`, `name_key`), and the screen names a room by
  its `name_key`, else its id. A marker is placed as the host's `MarkerReader` places it
  (`LevelWorld.transform_in_scene`: the level root counts, a `top_level` node ends the walk) and one in two spawn groups lights nothing (the reader
  refuses it); `MapData.SPAWN_GROUP_PREFIX` copies the reader's prefix and a test ties the two. A task
  type's zones are the rooms holding a level marker (`spawn_<tag>`) of one of its `TaskType.item_spawn_tags()`
  (Delivery: its package kind's): every such marker, never the ones a deal chose. The greybox, a test bench only
  (#767), declares no rooms, so on it the map shows the tasks only; the previews use a fake house in
  `client/dev/screen_preview.gd`.
- **Privacy** (the M4 ADR's §3 item 4 as amended): the screen reads the model's tasks and clock and the own place
  only; never another player's place, an item's or a circle's.
- Tests: `tests/unit/client/ui/map_screen_test.gd` (rows, counters and names in English and Ukrainian and a switch,
  no description or NEW, the «?» signal and no focus, the lit zones and chip, the rooms and the pin's place and
  turn; the privacy test: models that differ in other players, items and circles draw the same screen, node by
  node, seen failing with a planted item pin; it replaces `hud_test`'s "the task screen names no place"; a room
  named by its record's key, else its id, #306), `map_data_test.gd` (rooms by the metadata through parents, the
  record's id and name key and their fallbacks, zones from markers only, placement as the reader's, no
  rooms, the greybox's rooms have an area,
  the board's fit), `tests/unit/levels/house_room_records_test.gd` (#306: every House room has a record, its id
  unique and its scene's file name, its name key with English and Ukrainian text, read by `MapData` as it stands;
  seen failing with a pasted id, a missing key and an unknown key), `hud_test.gd` (open only in the round, the
  signals, the downed crosshair, the Esc menu closes it), `tests/unit/tasks/item_spawn_tags_test.gd`, `tests/unit/client/input_actions_test.gd` (`map` is M, no action
  on Tab; seen failing on the old input map), `controls_test.gd`, `key_label_test.gd`, `controls_panel_test.gd`,
  and `tests/integration/client/app/map_input_test.gd` (real key events in a host's round: M toggles and frees and
  captures the mouse, Tab does nothing, W still walks, the pin's place and heading, a click stays unhandled, Esc closes only the map, M under the
  Esc menu does nothing, a close request, the end of the round; seen failing without `mouse_free` and without the
  Esc rule). The `shot`s and the playcheck scenario `map`: §4.7.40.

#### 4.7.34 The pack's icons, the Delivery cards and the font hook (#520)
- **The imported copy.** `ui-sync` (AGENT_WORKFLOW §11.26) also lands every asset of the pack's `assets` list (17
  icons, 8 room pictograms, `cards/delivery-1..4.png` at `ui-0.4.0`; at `ui-0.8.0` (#1020) 23 icons with the CheckBox
  and SpinBox ones, the 8 pictograms, `cards/delivery-meaning-1..4.png` and the Comfortaa TTF, the font hook's
  file since #1045: the theme loads it, `assets/ui/comfortaa/` is gone) in `assets/ui/toy_pack/`, a folder Godot
  imports (§11.1), byte for byte under the lock's `imported` (`.gitattributes`: its SVGs `-text`, its PNGs through
  LFS, a pointer file counted by its oid). Each SVG's `.import` gets the pack's `svg_scale` (the s07 and s08
  handoffs' import scales: `item` 2, `mic` 1.17, `teammate-mark` and `lock` 0.84, `swatch-disc` 1.54, the rest 1);
  `ui-sync` writes it into Godot's own file, so a re-sync keeps the uid. Credits: `docs/credits/prime_game_ui_pack.md`
  from the pack's `LICENCES.json` (own work).
- **Theme icons.** `theme_builder.gd` sets each live variation's `textures` as icons (`grabber-highlight` →
  `grabber_highlight`) loaded from `mapping.textures.folder`, and refuses a texture that is not imported: ToySlider's
  grabbers, ToyDropdown's arrow, ToyDropdownList's radio icons, ToyCheckBox's boxes and ToySpinBox's chevrons
  (#1020), and through the base types (§4.7.30) the bare HSlider, CheckBox, SpinBox,
  OptionButton and PopupMenu. `name_external` gives each external file the id of its name in the saved file, since
  Godot would make it from the path saved to and the stale test saves elsewhere.
- **The teammate mark** (§4.7.29) is the pack's SVG in a TextureRect. The room pictograms draw on the map (#490,
  §4.7.40); the Delivery cards for the how-to card (#254, the s08 handoff's wordless `Art` frames); the hand
  slot, mic and lock icons for the Toy screens (#489 and on).
- **The font hook.** `mapping.font.file` is `res://assets/ui/toy_pack/fonts/Comfortaa-VariableFont_wght.ttf` (the pack's copy since #1045;
  `assets/ui/comfortaa/comfortaa.ttf` before), added in #684 (google/fonts'
  variable `Comfortaa[wght].ttf`, `wght` 300 to 700, with Cyrillic; a Git LFS file; proposed on prime-game-ui#44).
  `build_theme.gd` makes one `FontVariation` of it per weight the pack's labels use (each label token's `fontWeight`
  on the `wght` axis: 600 and 700 at `ui-0.4.0`, the sub-resources `Comfortaa_wght_600` and `_700`), sets it as the
  `font` of each variation with a label, and type.body's weight (`Comfortaa_wght_600`) as the theme's default font;
  the base types copy it. The committed themes carry both. A checkout without the file builds themes with no font, so
  Godot's default draws. With the font, each Label variation also gets the `line_spacing` that makes its line its
  label token's `lineHeight` tall (#685): `fontSizePx` × `lineHeight`, half rounded up, less Godot's line height
  of the font at that size (its ascent plus descent, each rounded up to a pixel; 22 px: a 28 px line over 26, so
  2). The ascent and descent are `mapping.font.metrics` (881 and 234 at size 1000), measured once from the real
  TTF and committed, never read from the loaded file: CI imports a stand-in font (§4.7.21, `lfs`'s TTF and OTF
  stand-in) whose metrics differ, so a build there writes the same theme. The test checks the metrics and every
  Label variation's line against the real font only where it is present (its `font_name` is Comfortaa). The bare
  Label keeps #287's greybox 5. The credits entry `docs/credits/comfortaa.md` is complete; the OFL text ships as
  `licenses/comfortaa/OFL.txt` (`docs/credits/licenses/README.md`).
- Tests: `tools/runner/tests/test_ui_sync.py` (the imported copy, its scales and a re-sync that keeps Godot's
  `.import`, an asset the pack lists but does not ship, each problem verify names: a missing, changed or extra file,
  an LFS pointer by its oid, a wrong or missing scale, an asset not imported; the committed copy);
  `tests/unit/tools/theme_builder_test.gd` (the icons and their size, exactly the six types with icons, a texture
  that is not imported named; no font in a checkout without the file, and with Godot's fallback font as a stand-in a
  FontVariation per label weight shared by every label and base type; each Label variation's line spacing, #685);
  `base_controls_test.gd` (a bare slider,
  dropdown and list draw the pack's icons); `name_plate_test.gd` (the mark's texture and tint);
  `test_credits.py` (a Pending entry, seen failing without the change); `test_lfs.py` (the TTF and OTF stand-ins
  import with the pinned Godot, seen failing on a broken one). `client/dev/pack_preview.tscn`: a `shot` of the
  assets in English and Ukrainian.

#### 4.7.35 The UI's input rules across the game (#488)
The «Layers and input (every screen)» section of the UI handoffs at `ui-0.4.0` (the engineer's standing decision for
the UI work), set once so every screen issue relies on it. #211 (§4.7.28) built the 16 actions, their phases and
`KeyLabel`; #253 (§4.7.33) the map key and its mouse.
- **Space leaves `ui_accept`** (rule 1). `project.godot` overrides `ui_accept` with Godot 4.7.2's own list (probed:
  Enter, keypad Enter, Space; deadzone 0.5) without Space, plus the gamepad's A (button 0), which the builtin lacks
  and the rule names; Enter stays first (playcheck's `button` step presses the first key). `ui_select` keeps Space:
  no Button reads it. `ui_up/down/left/right` are the arrows and the d-pad only, never WASD.
- **Esc closes the topmost overlay, one per press** (rule 2). `client/ui/UiOverlays` (pure) holds the overlays by
  layer, each registered with what tells whether it is open and what closes it, asked on every press (a freed one
  counts as closed): `MENU_PANEL` (the main menu's open panel, code, Direct or Settings since #493, §4.7.38, only
  while the main menu shows), `INVITE` (the tutorial's invite, its Skip; #492, §4.7.49), `MAP`, `CARD`,
  `ESC_MENU` (closed as its Resume, so `Game.close_esc` captures the mouse again), `ESC_DIALOG` (the host's Leave or
  Quit question, `EscMenuState.asking()`: back to the default tab). `GameUi` registers all but the card. `Game._input`
  asks, in order: Alt+Enter, F3, the black screens' Esc (Cancel on Connecting, Back on a failure, §4.7.32), then
  `ui.overlays.close_top()`, then, with a session only, opens the Esc menu. A key capture in Settings › Controls
  takes its Esc in its own `_input`, which runs before the game's, so it is no overlay here.
- **The how-to card's seam** (#254, built there, §4.7.36): `GameUi` registers the map's card,
  `overlays.add(&"howto_card", UiOverlays.CARD, map.howto_open, map.close_howto, true)`; the last argument makes the
  map key close it too. It closes with the map (`map_closed`), which `open_esc` closes. #488's tests use a stub card.
- **The map key** (rule 3): `GameUi.press_map_key()` closes a card over the map if one is open (the top overlay
  the map key closes), else toggles the map; under the Esc menu or the tutorial's invite (`GameUi.blocks_keys`, #492) it does nothing and returns false.
- **Gameplay input per screen** (rule 4). Under the Esc menu the own character takes no key and no look (§4.7.4) and
  the voice keeps working as set, the Talk key too (an amendment of the M5 ADR's push-to-talk line): `GameTalk.typing()`
  alone stops it, while a `LineEdit` or `TextEdit` has the focus (the Lobby tab's name, #214) or a key capture
  runs, since a handled key still reads as pressed in `Input`; and `GameTalk.talk_blocked` keeps it shut after the
  typing stops until the talk key has been let go once (a V that ended the capture is still held). With the map open the keys work and the look stops
  (`mouse_free`). The lobby HUD, the round HUD and the life screen (#497) take no mouse (the destination row, the life
  panel's column and bar were PASS or STOP); the pregame takes no input, as the post game screen (its backdrop,
  centre and column were STOP or PASS); the connecting screen's backdrop stops the mouse (§4.7.32).
- **Keys on screen** (rule 7): `KeyLabel.is_wide(physical)` and `is_wide_action(action)`: a keycap is wide for
  exactly the physical keys Space, Shift, Tab and Esc, wherever a rebind puts them; Ctrl, Enter, F5 and the mouse
  words stay normal until a screen shows one (a placeholder, not a decision).
  The keycap builders (#492, #497) take the theme's wide size from it. Esc has no deck key (`key.esc`): it shows as
  the literal "Esc" where it is fixed.
- **Look in tests.** Headless Godot keeps no mouse mode (CAPTURED reads back VISIBLE, probed on 4.7.2), so
  `PlayerController.mouse_captured` (a Callable, Input's mouse mode by default) is the seam the tests replace.
- Tests: `tests/unit/client/input_actions_test.gd` (the `ui_accept` list, Space jumps, a focused Button pressed by
  Enter, keypad Enter and the gamepad's A and not by Space through `Input.parse_input_event`, no WASD in the focus
  actions; seen failing on the builtin list), `tests/unit/client/ui/ui_overlays_test.gd` (the order, one per press,
  a closed or freed overlay skipped, the map key closes only a card), `game_ui_overlays_test.gd` (the main menu's
  page only on the main menu, the question before the menu, the map key), `input_rules_test.gd` (the HUDs and the
  pregame take no mouse and no focus; seen failing on four parts), `key_label_test.gd` (the four wide keycaps follow a
  rebind), `tests/unit/client/app/controls_test.gd` (the 16 actions with the issue's deck keys and defaults),
  `tests/integration/client/app/esc_menu_input_test.gd` (the host's question closes first, a capture before the
  menu, no look, jump or sprint under the menu and the look back after it; seen failing on the old `Game._input`
  and without the controller's guard; #726: a ready guest's menu, the host apart, closed by Loading and the round,
  a dropdown and the host's question by the end screen, the menu by the lobby; seen failing on the old `Game`),
  `map_input_test.gd` (a stub card closes first on Esc and on M, M under the
  menu does nothing, the keys work and the look stops with the map open), `game_voice_test.gd` (Talk sends under
  the menu, a focused text field or a capture stops it; seen failing without `GameTalk.typing`). The playcheck scenarios
  `esc_menu` (the host's Leave question, one Esc back; the guest's menu left open closed by the pregame, #726) and
  `map`.

#### 4.7.36 How-to cards per task type (#254)
Every task type has a **how-to card**: 3 to 4 wordless frames, one action each, like an airline safety card (the
designer's answers on #254: cards for task types first, a calm tone; the engineer's ui-0.4.0 note: no captions, only
the title and `howto.label`; the 2026-10-05 text decision: no NEW mark, no "new task" line). It shows in three places:
the map's «?», the loading screen, and the Esc menu's Guide. Nothing on the HUD.
- **Content data** (`HowtoCard`, `HowtoFrame`: content-API data classes in `core/content/howto/`, §9.3, as the bot scenarios', so `content/` names only the content API, §1): an id, a title deck key and its frames; a frame is a
  picture (a `res://` PNG path of the UI pack) or, until its art is drawn, the words of a deck key (`{key}` filled
  with an action's bound key through `KeyLabel`), and the finish frame is the last (`done`, ToyHowtoFrameDone). A
  task type's card is `content/howto/tasks/<id>.tres`, the Guide's basics `content/howto/basics/<id>.tres` (the
  spec's: moving and hands, voice, downed and back, from the tutorial's keys). The cards are not rules: the host never
  reads them, and they are not part of the mode or its content hash. A path, not a Texture2D, so a card loads while
  its PNG is missing: Delivery's pictures are #520's (`assets/ui/toy_pack/cards/delivery-1.png` to `-4.png`); until
  they are in the game each frame shows a placeholder naming the file. `HowtoCards` finds a card and checks every
  task type of a mode has a valid one (`problems_of`).
- **The card** (`client/ui/HowtoCardView`, a ToyRaised of ToyPanelHowto through `raised()`): prime-game-ui's P8 tree
  at ui-0.4.0, `V` with `Head` (`Title`, `Note`) and `Frames` (`Frame1`..`Frame4`, each a ToyHowtoFrame holding its
  `Art`, a TextureRect that keeps its aspect); the art is 320x240 on the map, 352x264 on the loading screen and
  160x120 in the Guide; the map's card adds `Bar` with Close. Words set in code follow the language live.
- **On the map** (`MapScreen.open_howto`, s8's `guide`): a «?» opens its type's card centred over the map on `Dim2`
  (ToyBackdrop, it stops the mouse), 1536 px wide. Close, Esc or the map key closes only the card: `GameUi`
  registers it in its `overlays` as `howto_card` on `UiOverlays.CARD`, above the map, closed by the map key too
  (#488's rules 2 and 3, §4.7.35; until the rebase on #488 the map screen read both keys in its own `_input`). While it is open the task list and the board take no focus
  (`focus_behavior_recursive`); the map closing (its key, the Esc menu, the end of the round) closes the card.
- **On the loading screen** (s3's `load-card`): entering Loading, `GameUi` emits `loading_started` and `Game` (`client/app/GameHowto`) shows
  the card of the first task type the round may deal (`HowtoCards.dealable`: the pool of the mode's DealTasks, its task types minus the host's
  bans in the set its `banned_setting` names, that play on the lobby's map (`TaskType.maps`, #803; the mode's default map while none is known, `HowtoCards.shown_map`, DE16, #828); DealTasks draws them at the end of Loading, so no more is known) that
  has a card (`HowtoCards.with_card`), the player has not completed and has seen there fewer than twice (`HowtoProgress.LOADING_SHOWS`, the issue's "at most twice"); else the tip.
- **Seen and completed** (`client/app/HowtoProgress`, `user://howto.cfg`, one file per player as the controls): the
  loading screen's shows per task type, and whether the player completed the type: a task of it reached its total
  (its `TaskState`, done = total > 0) while the player was in the round or at its end (`Game._process`, `GameHowto.follow`). Tasks are
  shared (#79) and no event names who did a subtask, so this is what the client can see. A `Game` with no command
  line keeps it in memory. Each write merges the file as it is (another window of the PC, `host` and `join`, may have
  written): a showing counts on top of the file's count, a completion stays.
- **The Guide** (`client/ui/GuidePanel`, s5's `guide`): a Guide tab after Resume in every screen, the lobby
  included (`EscMenuState.Tab.GUIDE`, its label the deck's `esc.tab.guide`); the basics' chips and one chip per task
  type of the mode with a card that plays on the match's map (`HowtoCards.of_tasks(mode, map)`; `GuidePanel.set_map`, called by `EscMenu.refresh`, keeps the selection; DE16, #828: the House's guide shows one Delivery, the greybox's the other), one ButtonGroup, the selected chip's card beside them (Delivery first). Its own
  control, so #491's restyle hosts it; it draws for a light page (the handoff's, the Toy Esc menu's since #491) or a
  dark one (`...OnDark` captions and chips, an option no menu uses now).
- **In `Game`** (`client/app/GameHowto`): its `howto` progress, the Guide tab's mode, the loading card and the follow, as
  static calls on the `Game`, read at each call (a test's `howto` set after `_ready` is the one used). They left
  `game.gd` when #488's lines and these took it past lint's 1000 (with the debug overlay's feed, `client/app/OverlayFeed`,
  §4.7.7), so #493's and #489's lines fit.
- Tests: `tests/unit/content/howto_content_test.gd` (every task type of every mode has a valid card, a task type
  without one fails the check; Delivery's four pictures with the finish last; the basics' words; every key in the
  deck, and every picture in the game once the pack's folder is), `tests/unit/client/ui/howto_card_test.gd` (a card's
  checks, the dealable types, the tree node for node, the placeholder, the words with the bound key in both
  languages), `guide_panel_test.gd` (the list, the selection, both languages, the dark page, the Esc menu's tab),
  `map_screen_test.gd` (the card over the map, Dim2, focus, Close, the map hiding closes it),
  `game_ui_overlays_test.gd` (Esc and the map key close only the card, then Esc closes the map),
  `esc_menu_state_test.gd` (the Guide tab in every screen), `tests/unit/client/app/howto_progress_test.gd` (twice
  then never, a completion, the file), `tests/integration/client/app/howto_loading_test.gd` (a host's first loading
  shows the card and counts it, seen failing without the wiring; twice seen or completed shows the tip; a task
  finished in the round completes its type for the next loading, seen failing without `GameHowto.follow`; a banned
  type no card) and `map_input_test.gd` (real Esc and M close the card before the map, seen failing without the
  card's `howto_card` overlay). The `shot`s: `client/dev/map_card_preview.tscn`, `loading_card_preview.tscn`,
  `esc_guide_preview.tscn`, each with a `_uk` twin, and `esc_guide_basics_uk_preview.tscn`.

#### 4.7.37 The round HUD in the Toy style (#489)
The round's HUD (§4.7.10's M4-8 HUD) redrawn as the UI track drew it: prime-game-ui `ui-0.4.0`
`docs/handoff/s07-hud.md` (not `ui-0.2.0`; since then the hand-slot icon is tinted by ToySlotText and the teammate mark
by ToyNamePlateText, and the SVG scales come from the pack's `assets` list, prime-game-ui#44), node for node, px at
the 1920x1080 base (§4.7.24), styled by the pack's variations only (no override, `theme_test.gd`). The slice's cut is
#521: Delivery v2 (#255) is out, so the hand slot shows today's Delivery package.
- **The tree** (`client/ui/Hud`, built in code under `GameUi`; `Plates`, §4.7.29, stays the first child of `Ui`,
  under it): `Timer` ToyPlate (top centre, 40 px down) > `Time` ToyTimer, 140 px wide; `Role` ToyChipPlate (top left)
  > `Text`; `Cross` ToyCrosshair (centre); `Aim` ToyChipPlate (38 px under the centre) > `Text`; `Vitals`
  ToyColumnTwelve (bottom left) > `Health` and `Stamina` (ToyColumnFour, 320 px: `Cap` ToyBarLabel > `Text`
  ToyHudCaption, `Track` a `ToyBar` with its `Fill`) and `Mic` ToyMic > `Icon`; `Slots` ToyRowTwelve (bottom right)
  > `Hand` ToySlotActive and `Belt` ToySlot (`HudSlot`: `Center` > `Row` ToyRowEight > `Icon`, `Name`
  ToySlotTextEmpty, `ItemName` ToySlotText); `Raising` ToyPlate > `Bar` ToyBarProgress (240 x 10). Every root sits at
  a point (the four offsets equal) and takes its minimum size along its grow directions, so a slot that narrows
  pulls the row back into its corner. The size constants (`width`, `height`, `wide_width`) are read into
  `custom_minimum_size` (`UiParts.sized`, `HudSlot` for the wide hand), again after the large-text swap. Every
  Control ignores the mouse and takes no focus.
- **What it shows** (`HudText`, pure, from the own `ClientModel`, the own mode and `HudText.Local`): the time left
  as mm:ss (data); the own role as its deck key (`ContentNames.role`, §4.7.48: `crew` is `role.engineer`); health as the
  fraction of the mode's (`ToyBar`: the fill's ramp stop, §4.7.27) and the predicted stamina's, full before the
  first status; the mic (`VoiceSender.live()`: a microphone open, the own player heard in this phase and life, in
  push-to-talk the key held; `mic` tinted `icon_on`, else `mic-off` tinted `icon_off`); the hand and belt (a kind's
  deck key, `ContentNames.ITEMS`, else its display name; its pack icon, `HudText.ITEM_ICONS`; empty shows the slot's
  name, a one-handed item only its 48 px icon, a two-handed one widens the hand to `wide_width` and shows its icon
  and its name, cut at 106 px with an ellipsis; a kind with no icon shows its name); `Aim`, the name of the item
  `ItemInteractions.target()` is on (the hint's reach and sight, §4.7.10), or the rescuer's raise cue over a downed
  player E would raise (#497, §4.7.41); `Raising`, the own raise's progress
  (`LifeView.raise_shown()`: the countdowns' `raise_progress`, the same value as the downed player's bar), in
  place of Aim while the living player raises (the engineer, 2026-10-06). The map (#253) or a life other than living
  hides Cross, Aim and Raising. The HUD shows no key but the raise cue's, walking or running, player list, who
  knocked the player down, destination or task progress (the handoff): the old lines "Teammates", "Tasks n / m", the destination's
  swatch and the crosshair's "E: pick up" hint are gone (the destination is no longer shown: the world's marker went in #829, §4.7.10;
  the map the tasks' counters, §4.7.33; a dissident's teammates the plates' mark with no name, §4.7.29).
- **Downed and dead** (#497 settled s09 against this HUD, §4.7.41): downed, only `Vitals` > `Mic` (off) shows
  (`HudText.Shown.bars` hides Health and Stamina); dead, nothing of the HUD shows, neither the spectator's own
  nor, since #497, the watched player's hand and belt (#168 showed them until s9 was settled: the engineer's
  answer 3 on PR #675). The `Spectate` plate moved to `LifeScreen`; the raiser sees the `Raising` bar alone, as
  drawn (the greybox "Raising <name>" is gone).
- **Icons** (`client/ui/ToyIcons`): the pack's white SVGs, tinted through `self_modulate` as each node line says.
  An icon is #520's imported copy (`res://assets/ui/toy_pack/icons/<name>.svg`, imported at the `svg_scale` the
  pack's `assets` list gives: `item` 2, `knife` 1, `mic` and `mic-off` 1.17), which an export packs. Only an icon
  with no imported copy (one a newer pin lists before `ui-sync` imports it) falls back to the pinned, `.gdignore`d
  copy under `client/ui/theme/pack/icons/`, rasterised at run time (`Image.load_svg_from_string`) at the same
  scale; that copy is not exported. `TeammateMark` (§4.7.29) is #520's: the pack's SVG in a TextureRect.
- **Not built here:** separate CanvasLayers per the handoff's layer table for these (the screens stay children of
  one `Ui` layer, in the same order; only the black screens and the Esc menu have their own, §4.7.32); the font (#520: Godot's default until the TTF lands); the tutorial, which reuses these
  nodes. The role reveal (§4.7.39) fades out over them; the downed, dead and respawn plates are §4.7.41's.
- Tests: `tests/unit/client/ui/hud_test.gd` (the time, the role keys, the fractions, the slots' keys and icons, Aim
  and the raise in its place, a dissident's and an engineer's HUD equal but the role; since #497 the downed see the
  mic alone and the dead nothing, none of the target's; the map's tests of §4.7.33), `hud_layout_test.gd` (the
  handoff's tree, anchors, offsets, grow directions and minimum sizes; no mouse or focus; the health stop for 0.22,
  0.8 and 1.0; the states empty, pack, tired, hurt, mate, raising; the mic off; the downed and the dead; large text
  and the row shrinking back into its corner), `tests/unit/client/voice/voice_sender_test.gd` (`live()`),
  `tests/integration/client/life/life_network_test.gd` (the raiser's bar is the raised player's value and shows on
  the raiser's HUD), `base_controls_test.gd` (TextureRect named). The teammate mark never on an engineer's client:
  §4.7.29's tests. The `shot`s: `client/dev/hud_preview.tscn` (empty) and `hud_<state>_preview.tscn` for pack,
  tired, hurt, mate and raising, each with a `_uk` twin, and `hud_large_uk_preview.tscn`, at `--size 1920x1080`
  (s09's states: §4.7.41); the playcheck fields `hud.*` (`tools/runner/playcheck.py`) read the new nodes.

#### 4.7.38 The main menu (#493)
prime-game-ui's s2 at `ui-0.4.0` (its handoff `docs/handoff/s02-main-menu.md`; the issue linked `ui-0.2.0`, and
where they differ `ui-0.4.0` is built), node for node, in `client/ui/main_menu.gd`.
- **The tree.** `MainMenu` (GameUi's `menu`) holds `Backdrop` (ToyBackdrop, full rect, the mouse ignored), `Column`
  (the logo `prime-game`, a data text; `NameRow`; `Body`: the 592 px `Items`, then `Gap` and the raised 784 px
  `CodePanel` and `DirectPanel`), the raised 960x888 `SettingsPanel` at (856, 96), a root of its own, and `Version`
  bottom right. A raised panel or button is its `ToyRaised` wrapper `<name>Raised` (placement, size, visibility) with
  the face inside. It stays a `Control` of the `Ui` layer, built in code like the other screens (the handoff's "its
  own scene, under none of the in-game CanvasLayers" holds: the `Ui` layer is none of the handoff's layers 1 to 6).
  The live lobby behind it with an idle camera is not built: no level loads before a session (`GameFlow`), so the
  backdrop dims the empty viewport.
- **Items.** ToyMenuItem Buttons, left-aligned, each with the pointer icon at 24 px that ToyMenuItem's
  `icon_*_color` shows only focused, hovered or pressed: the pack's `pointer.svg` as #520 imported it
  (`ToyIcons.texture(&"pointer")`, §4.7.34, its `svg_scale` 1). Join, Join by address and Settings are `UiParts.toggle`s in one ButtonGroup with
  `allow_unpress`: pressing one opens its panel (`open_panel`), pressing it again, Back or Esc closes it
  (`close_panel`) and focuses its item. Esc reaches the open panel as #488's overlay `menu_panel` (§4.7.35:
  `GameUi` registers `panel_open()` and `close_panel`, only while the menu shows), so `Game._input` closes it like
  any other overlay; with no panel open and no session it does nothing.
  Focus starts on Host whenever the menu shows with no panel; up and down follow the items. Host emits
  `code_host_requested` (`Game.host_with_code` on the launch options' port); Quit quits; Tutorial is drawn and
  unplugged until the tutorial exists (#492).
- **The code panel.** `code_text()` keeps the field upper case, only `SignalCodec.CODE_ALPHABET` (no spaces, dashes,
  0, O, 1, I or L), at most 6 (`max_length` 6); a paste longer than the room left comes back through
  `text_change_rejected` and is filtered whole, so "k7m-2qx" pasted reads K7M2QX. Join (ToyButtonPrimary, unplugged
  until `SignalCodec.is_code`) and Enter join by the code. Opening it from its item empties the field; a failure's
  Back shows the menu as it was, the code kept.
- **The Direct panel.** Address takes host or host:port (`JoinTarget.of_direct`); Join and Enter are unplugged while
  it does not parse (an empty field included), so no typed problem reaches `Game`; the port line names the default
  (`join.port`, the launch options' `--port`). Host hosts over ENet on the port typed after the address, else the
  default (`typed_port`); Host is off while the typed port is not one (`JoinTarget.port_problem`), never quietly on
  the default. A command-line join fills its panel (`GameJoin.fill_menu`) so Back finds it there; a `--join=` that does
  not parse waits in the Direct field with Join off, the menu's only sign of it.
- **The name row** binds to `UserSettings.player_name` (`bind_name`, #550): each change is cleaned by `PlayerNames`
  and saved; a field left empty keeps the name there was and shows it again on leaving the field. Empty until the
  player chooses one (the host then names them `Player<n>`): the engineer's answer on PR #621, which the handoff's
  "never empty, else the system user name" predates.
- **The Settings panel.** `settings_page` is #491's `SettingsPage` (§4.7.42), the same scene as the Esc menu's
  Settings tab, opened on Sound and voice; its `VoicePanel` keeps #301's logic. `Game` feeds it as before
  (`shown_voice_panel`, `settings_open()`). It opens at its top: `follow_focus` scrolls to the focused first row
  before the panel's first sort, with the old sizes (290 px down under large text), so the menu scrolls it back once
  the focus has landed.
- **No reason line.** The handoff draws none: a failure shows on the connecting screen (§4.7.32); the words of the
  last end, or of a problem with a command-line target, are printed and kept in `Game.last_words`.
- **Version.** `menu.version` with `application/config/version`; hidden while `project.godot` names no version.
- Every text is a deck key; the version and port lines are set from code with `auto_translate_mode` DISABLED and
  rebuilt on `NOTIFICATION_TRANSLATION_CHANGED`; the logo, the name, the code and the address are data texts. Every
  LineEdit has `context_menu_enabled` false (Godot's menu words are English).
- Tests: `tests/unit/client/ui/main_menu_test.gd` (the tree node for node: names, classes, variations, anchors,
  offsets, grow, size flags and minimum sizes; the items, the group, the pointer (the imported file) and its colours; every state by its
  item, Back and another item, seen failing on the group's release order; the focus as drawn; the alphabet, the case, six at most and a long paste, seen
  failing without the filter; Join and Enter only with a whole code; the code kept on a return; Direct's Join and
  Host's port; the Settings panel at its top under large text, seen failing without the scroll back; the name row and its file; the port and version lines in uk; every key in the deck),
  `tests/unit/client/ui/game_ui_overlays_test.gd` (the `menu_panel` overlay closes each panel and returns the focus to
  its item; none open, no overlay), `tests/integration/client/app/esc_menu_input_test.gd` (Esc on the real game's
  menu closes Settings, the code and the Direct panel, no Esc menu), `game_voice_test.gd` (the Settings panel's pick and meter), `game_code_join_test.gd` (Join
  directly opens the Direct panel; a mistyped code never leaves the field) and `game_loop_test.gd` (Back to the
  Direct panel with the command line's address). The look: a `shot` of each state in en and uk, default and large
  text, from `client/dev/screen_preview.gd` (`menu_state`, `language`, `large_text`) in the PR; the playcheck
  scenario `main_menu` (a guest leaves to the real menu, then its Direct, Settings and code panels by keys).

#### 4.7.39 The pregame role reveal in the Toy style (#496)
`PregameScreen` (`client/ui/pregame_screen.gd`, §3.6's screen) is the UI track's pre game, node for node as
prime-game-ui `docs/handoff/s06-pre-game.md` draws it at `ui-0.4.0` (the issue named `ui-0.2.0`; ui-0.4.0 wins, as
for #498 and #489): `Night` (ToyBackdropNight, opaque) under `V`, a centred 1152 px ToyColumnThirtyTwo of `YourRole`
(`pregame.your_role`, ToyTextMutedOnDark), `RoleRaised` (a `ToyRaised` on ToyBaseTitle, SHRINK_CENTER) > `Role`
ToyTitlePlate, and `Text` (ToyColumnSixteen) > `Goal` (ToyTextOnDark) and `Team` (ToyTextMutedOnDark), both 1152 px
wide, wrapped. Pack variations only, no override.
- **What it shows** (from the own `ClientModel` and the own mode only): the own role as its deck key
  (`HudText.role_key`: `crew` is `role.engineer`, `dissident` `role.dissident`; a role the deck lacks, its display
  name); its goal, `role.goal.engineer` or `role.goal.dissident` by `GOAL_KEYS` (the engineer's provisional generic
  lines on #175; a role not there shows no goal, no text is invented); and `pregame.teammate` with `{names}`, the
  roster names of the own role's `Teammates` but the own player, in the host's order, joined with ", "
  (`team_of`), set with `tr()` and `format()` (`auto_translate_mode` DISABLED, rebuilt on
  `NOTIFICATION_TRANSLATION_CHANGED`). The host sends `Teammates` only to a role that knows them (§5), so an
  Engineer, and a dissident with no teammates, get no team line. It reads `model.role`, `model.teammates[model.role]`,
  `model.own_peer` and `model.roster` only (a source test holds it): never another role's entry. Before
  `RoleAssigned` only Night shows. No word about the microphone or hearing.
- **Behaviour.** `GameUi` calls `reveal()` on every Pregame frame. When the screen turns from Pregame to Round,
  `lift()`: `V` hides, Night fades from alpha 1 to 0 over 0.4 s (`FADE_SECONDS`, a `Tween` on `modulate:a`) over
  the round's HUD, then the screen hides (the handoff's "freed": the one instance stays under `GameUi` for the next
  match, reset); a cut under `UiPrefs.reduced_motion`, and outside the tree. Any other screen after Pregame hides
  it at once. It draws over the HUD, the life screen (§4.7.41), the tutorial's plates and the map from the black layer
  `GameUi.black` (§4.7.32), under the post game screen; the Esc menu opens over it from `GameUi.above` (#656).
  Every Control ignores the mouse and takes no focus; the pregame is frozen
  and silent by its phase (§3.6), so no mic shows (the HUD is hidden).
- **Role sounds** (#716, #213 criterion 3, #175). `role_revealed(role, side)` is emitted once per pregame when the
  own role shows, with that role's side in the client's own mode (empty for a role it does not know), and never
  while Night fades out over the round (a role that arrives that late plays nothing in the round). The screen plays
  `SIDE_SOUNDS[side]` on it through `UiSounds.role` (§4.7.43): `crew` the engineers' sound, `dissidents` the
  dissidents'; any other side nothing. Only the own `ClientModel.role` chooses it and nothing is sent, so no peer
  hears another's role sound (the bots test checks the wire).
- **Not built here.** The Esc menu's Role tab (#491).
Tests: `tests/unit/client/ui/pregame_screen_test.gd` (the tree: names, classes, variations, anchors, size flags and
minimum sizes; the pack's variations only; engineer, dissident with teammates, dissident alone, before the role, a
role with no key; it reads only the own role and Teammates (the source's model fields; another role's Teammates
name nobody); the language switch; no focus or input; the fade, its cut under reduced motion; the hook once per
pregame with the side; the own side's sound once per reveal on the UI bus, none before the role, hidden, during the
lift or for an unknown side (seen failing without the lift guard), its sources name no session, send or voice;
`GameUi`'s lift into the round, its layer order and the cut on another screen), `screens_test.gd` and
`input_rules_test.gd`. The `shot`s, at `--size 1920x1080 --frames 60`: `client/dev/pregame_preview.tscn` (engineer),
`pregame_dissident_preview.tscn` (with a teammate), `pregame_alone_preview.tscn`, `pregame_after_preview.tscn` (Night
frozen halfway through its fade over the round's HUD), their `_uk` twins (`pregame_uk`, `pregame_dissident_uk`, `pregame_after_uk`) and
`pregame_large_uk_preview.tscn` (dissident, large text); the game's own: `tools\run.cmd playcheck pregame`.

#### 4.7.40 The map and tasks screen in the Toy style (#490)
The look and the focus of §4.7.33's screen, node for node from prime-game-ui's s08 handoff at `ui-0.4.0` (the
engineer's standing decision for the UI work, prime-game-ui#44), and its how-to card (§4.7.36).
- **The tree** (`client/ui/MapScreen`): `Dim` (ToyBackdropDeep, no mouse); `Tasks` (ToyPanelMenu raised on
  ToyBasePanel; its wrapper `TasksRaised` at 80, 88, 608 wide, growing down to its content): `V` (ToyColumnTwentyFour)
  with `Title`, `Rows` (ToyColumnEight) and `Time`; a row `<Type>` (ToySettingRow, 64 tall) holds `H` (ToyRowTwelve):
  `Name` (ToySettingRowValue), `Count` (ToySettingRowText) and `Help` (ToyKeyRoundButton, the handoff's fixed 42x42,
  not the variation's `min_width`, so it needs no theme-change hook). `Board` (ToyMapBoard raised, its wrapper at
  744, 88, 1096x904) holds `Rooms`, 1088x896 inside the 4 px border (`MapScreen.ROOMS_SIZE`, the size MapData fits
  the rooms to): a room `<Room>` (ToyMapRoom) holds `V` (ToyColumnFour, centred) with `Icon` (the pack's
  `room/<id>` pictogram through `ToyIcons`, 48x48, its `self_modulate` the ink of ToyMapRoomText's `font_color`,
  #2a1f33, set again on a theme change; hidden for a room id the pack draws none for) and `Name` (ToyMapRoomText, 120
  wide at least, wrapped); then `Zone<Type>Tag` (ToyChipLight, `Text` ToyChipLightText), `Pin` (ToyMapPin) and
  `Here` (ToyChipPlate, `Text` ToyHudCaption). `Dim2`, `Guide` and the card are §4.7.36's.
- **Rows** are one per task type, in the order of its first task's id, the counters of its tasks summed (DealTasks
  deals each drawn type once, so a round has one task per type). A refresh with the same types sets the words in
  place, so a live counter never takes a «?»'s focus.
- **Zones.** Lighting a type adds `Zone<Type>` (ToyMapZone, no mouse) as the first child of each lit room, so it
  fills the room under its pictogram and name; the tag sits 12 px under the first lit room, its left edge on the
  room's, on one line, wrapped only where it would pass the board's right edge, and above the room where it would pass
  the rooms' bottom (a lit room in the lowest row, large text). The hovered row lights its type, else
  the «?» with the keyboard's focus (`has_focus(true)`: a focus a mouse press gave is hidden and lights nothing).
- **Focus.** `Help` is `FOCUS_ALL`. Nothing has the focus on open; with none, the first `ui_down` or `ui_up` (the
  arrows and the d-pad only, §4.7.35) focuses the first «?» in `MapScreen._unhandled_input`, and Godot moves it from
  there. A «?» pressed while it shows its focus (keyboard or gamepad) opens its card with Close focused
  (`open_howto(type, true)`), and closing it (Close, Esc or M, the overlays of §4.7.35) gives that «?» the focus
  back; pressed with the mouse, closing drops a focus on the map. `focus_help(type)` focuses a «?» (the previews).
- **Not as drawn** (each in the PR): the screens are children of `GameUi`, not CanvasLayers; the hover is read with
  `gui_get_hovered_control` each frame, not `mouse_entered`/`mouse_exited` (a child takes the parent's hover,
  §4.7.33); the Delivery PNGs keep #520's import without mipmaps (the canvas's default filter samples none); the
  rooms are what MapData reads today, and the greybox has none until #306 (the engineer chose to wait for its
  room records, PR #652), so in the game the board hides (since #306 the House's rooms carry their records, §4.7.33;
  the greybox, a test bench, #767, stays roomless); the base mode has no Switches task type, so neither its
  row nor `map.zone_hint.switches` shows; Delivery lights every room with a package marker (the storage-only zone
  is Delivery v2, #255, out of the slice, #521).
- Tests: `tests/unit/client/ui/map_screen_test.gd` (the tree node for node with its sizes, the ink, one row per type,
  a counter set in place keeping the focus, the first arrow and the keyboard's lit zones, Close focused and the focus
  back, each seen failing without its code, the mouse's card dropping the focus, the zone first in its room and its
  tag under it, the tag's wrap at the board's edge, the privacy signature), `hud_test.gd` (one row),
  `tests/integration/client/app/map_input_test.gd` (real Down, W, Enter, Esc and M in a host's round; the open
  map's click moved to the corner, which the task list does not cover). The `shot`s, at `--size 1920x1080`:
  `client/dev/map_list_preview.tscn` (`list`), `map_preview.tscn` (`zone`, the «?» focused),
  `map_card_preview.tscn` (`guide`), each with a Ukrainian twin (`map_list_uk_preview`, `map_preview_uk`,
  `map_card_uk_preview`), and `map_large_uk_preview.tscn` (`zone` at large text); `screen_preview.gd`'s fake house
  follows the handoff's sample rooms. The playcheck scenario `map` focuses a «?» with Down, opens its card with
  Enter and closes only the card with Esc.

#### 4.7.41 The downed, dead and respawn screen in the Toy style (#497)
The handoff s09 (prime-game-ui `ui-0.4.0` `docs/handoff/s09-downed.md`; since `ui-0.2.0` the give-up pieces are
stripped and the keycap's `min_width` follows the text size, #497's comment), node for node on §4.7.37's HUD, px
at the 1920x1080 base, the pack's variations only (no override, `theme_test.gd`). It replaces M4-9's greybox
`LifePanel` (its words "Knocked down", "Dying in n s", "Respawn in n s", the raise hint and the spectate keys).
The living rescuer's greybox "Hold <interact> to raise" went with it; the engineer's answer 6B on PR #721 brought
it back in §4.7.37's `Aim`: the deck (`ui-0.4.0`, nor `ui-0.5.0`) has no raise sentence, so it is the nearest key
with `{key}`, `tutorial.step.downed.how` ("Hold {key} next to them", "Утримуй {key} поруч"; a stopgap the engineer
confirms or swaps for a deck key), with the bound
`interact` key's label (`KeyLabel`), set in code and written again on a language switch (`Hud._show_aim_text`).
`LifeView.raise_cue()` gives the key while the living own player's crosshair is on a downed player E would raise
(`raise_target()`, within `raise_hint_reach_of()`) and nobody raises them yet (`raiser_of()`: the host lets one raiser
at a time, so a second Raise would be `busy`), so it offers what E does: the base mode's raise has no team condition,
so a dissident sees it over a downed engineer too. `HudText` puts it in place of the item's name
(both are on E); the own raise's `Raising` bar replaces it; the downed and the dead see none. It names nobody.
- **The tree** (`client/ui/LifeScreen`, built in code, `GameUi.life` after `Hud` under `Ui`): `Downed` ToyPlate
  (top centre, 152 px down, 688 px) > `V` ToyColumnEight > `Title` ToyTitleOnDark (600 px, word-wrapped), `Bleed`
  a health `ToyBar` (600 x 16, its fill 10 px high and tinted by the ramp's stop, §4.7.27), `Left`
  ToyTextMutedOnDark, `Raise` ToyBarProgress (600 x 16) and `Pad` (0 x 4); `GiveUp` ToyPlate (bottom centre, 128 px
  up) > `V` ToyColumnEight > `Line` ToyRowFour (centred) > `Before`, `Key` ToyKeyOnDark > `Text` ToyKeyText,
  `After`, then `Hold` ToyBarProgress (360 x 10) and `Pad`; `Spectate` ToyPlate (top centre, 40 px down) > `V`
  ToyColumnFour > `Respawn` ToyTextMutedOnDark and `Watching` ToyTitleOnDark; `Protect` ToyChipLight (top centre,
  144 px down: 24 px under the timer plate) > `Text` ToyChipLightText. Every root sits at a point and takes its
  minimum size; the keycap's `min_width` (36, 42 at large text) is read by `UiParts.sized` again after the
  large-text swap. Every Control ignores the mouse and takes no focus. The four roots sit under one full-rect
  `LifeScreen` Control beside `Hud`, not beside its nodes (one class owns s09; the places are the handoff's).
- **What it shows** (`client/life/LifeHud`, pure, from the own `ClientModel`, the own `LifeCountdowns` at the
  estimated host tick and `LifeView`'s own state; `LifeView.hud()` reads the give-up binding each frame):
  `down`: `downed.title`, the bleed-out bar (`LifeCountdowns.knockdown_fraction()`: the time left over the mode's
  knockdown) and `downed.time_left` (m:ss, rounded up), and the give-up line: `tr("downed.give_up_hold")` split at
  `{key}`, each piece through `strip_edges()`, an empty piece hidden (uk: "Щоб здатися, утримуй" [F]), around the
  keycap of `KeyLabel.of_action(&"give_up")` (§4.7.28), so it follows a rebind, wide (`wide_min_width`) when
  `KeyLabel.is_wide_action(&"give_up")` says so (§4.7.30 rule 7, carried as `LifeHud.Shown.give_up_wide`, read
  again on every theme change); the hold bar fills over
  `LifeView.GIVE_UP_HOLD_S` and stays shown, empty, at rest (`down-holding`). `raise` (a raiser in the model):
  `downed.raised_by` with the raiser's name, the raise's progress (the raiser's HUD bar's value, §4.7.37) in place
  of the bar and the time, no GiveUp; when the raise stops the bleed-out returns. `dead` (or gone): `dead.respawn_in`
  (m:ss) and `dead.watching` with `LifeView.target()`'s roster name (hidden with no target); the HUD shows nothing
  (§4.7.37), no key (the tutorial teaches the spectate keys) and nothing of the target's. `back`: the HUD returns;
  `respawn.protected` counts the respawn's invulnerability (`LifeCountdowns.protection_left_s()`, the mode's 3 s:
  3, 2, 1 rounded up), and only a respawn's: a raise's invulnerability shows no chip. Never who knocked the player
  down: nothing here reads it. Texts with data are set in code (`auto_translate_mode` DISABLED) and written again on
  `NOTIFICATION_TRANSLATION_CHANGED`; `downed.title` too, which the handoff sets as a plain key.
- **Playcheck:** the fields `life.title`, `life.left`, `life.bleed`, `life.raise`, `life.give_up` (the line as
  drawn), `life.hold`, `life.respawn`, `life.watching` and `life.protected` replace `life.lines`, `life.bar` and
  `hud.spectating`; the `spectate` scenario waits on them.
- Tests: `tests/unit/client/ui/life_screen_test.gd` (the tree, anchors, offsets, grow directions and minimum sizes;
  no mouse or focus; every state in English and Ukrainian and a language switch; the bleed fill's ramp stop; the
  hold leaving the plate's size alone; the keycap following a rebind through `LifeView.hud()`; Space's 96 px wide keycap on both themes and K's
  36 and 42 px after it; 36 and 42 px at large
  text with every plate on the screen; the `Ui` shows it in the round only), `tests/unit/client/life/life_hud_test.gd`
  (each state's data, the m:ss rounding, the raise stopping, the protection after a respawn and not a raise, the
  sentence's pieces), `life_countdowns_test.gd` (`knockdown_fraction`, `protection_left_s`), `hud_test.gd` and
  `hud_layout_test.gd` (the HUD's part; the raise cue in place of the item's name for the living only, the same for
  a dissident and an engineer, naming nobody, in en and uk and after a switch),
  `tests/integration/client/life/life_network_test.gd` (the host's player, as a dissident, aiming at the downed
  joiner sees the cue in its Aim, seen failing with `Game` not passing it on; the raised joiner's title and bar, the
  spectator's plate with the HUD empty, the chip after the respawn). The `shot`s:
  `client/dev/hud_<state>_preview.tscn` for cue, downed, holding, raised, dead and back, each with a `_uk` twin, and
  `hud_downed_large_uk_preview.tscn`, at `--size 1920x1080`; `spectate_preview.tscn` and `life_preview.tscn` draw it
  too.

#### 4.7.42 The Esc menu in the Toy style (#491)
- Built node for node from prime-game-ui's handoff s05 at `ui-0.4.0` (the PR lists every difference). `EscMenu`:
  `Dim`, the raised 1600x880 `Menu` with the `Tabs` column (ToyTab toggles in one ButtonGroup) and the `Page`, whose
  title row reads the selected tab's name, the host's `HostNote` on the Lobby tab or a player's `HostOnly` lock line.
  `EscMenuState` (pure): the tabs Game, Role (the round only), Guide, Lobby (the lobby screen, and read-only in the
  round: the issue's "everyone in a round"), Settings; the tutorial's Game, Guide and Settings
  (`GameUi.set_tutorial(on)`, which `GameTutorial.start` and `end` call, §4.7.44); the default tab Lobby in the lobby
  and Game elsewhere; the last tab pressed is kept for the next opening on the same kind of screen (lobby or other).
  Character waits for #73 (M7): no tab, no placeholder.
- Game: Resume (also Esc on the menu), Leave (the host's coral ToyButtonDanger, a player's and the tutorial's
  ToyButtonSecondary, "Leave the tutorial" there) and Quit. The host's Leave and Quit open `ConfirmDim` and `Confirm`
  (P1): the menu behind takes no focus (`Menu.focus_behavior_recursive` FOCUS_BEHAVIOR_DISABLED, INHERITED again on
  close), Cancel has the focus, and Esc closes only the dialog through `GameUi`'s `esc_dialog` overlay (§4.7.35), not
  an `_input` of its own; Cancel gives the focus back to the button that asked. Closing the window asks the same, but
  in the tutorial (a solo session its player hosts), which quits at once.
- Role (`RolePage`, the pure `RoleFacts`): the own role (HudText's key), its goal (`role.goal.*`) and, for a role
  whose `Teammates` the own client holds, the team in join order without the own player or a player who left, in a
  two-column ToyGridList scrolling in a 250 px view. It reads only `model.role`, `model.teammates[model.role]`,
  `own_peer` and the roster's names (per-peer filtering decides what the model holds). The HUD's role chip hides
  while the map is open (`Hud.role_hidden`, the engineer on #652).
- Lobby (`LobbyPanel`, its signals, name logic and statics kept): the preset cards (`LobbyPresets`: Standard, Quick,
  No knives, the own preset and Save your own; the values are placeholders, "not a decision"), a 784 px
  `SettingList` (the lobby's name, the map, then a row per `SettingSpec`: a `SettingStepper` for a number, whose
  arrows hand the focus over before one is disabled, and toggle chips for the banned task types, selected =
  allowed, only those of the types that play on the picked map, the mode's default map while none is known (DE16, #828: a ban on a hidden type stays in the set the chips send); a number with one allowed value hides) and `Side` (the code keycap with Copy, or `esc.lobby.code_gone`;
  the players' rows, scrolling; the shortfalls; Ready). The pressed card is derived from the model, so any other
  change deselects it and a player reads "Preset: Custom"; a card sends every value it changes in one
  ChangeSettings (`settings_changed`, `Game.change_settings`): the host checks them together. The own preset is
  `UserSettings.own_preset` (`[lobby]`). In the round the page is everyone's read-only view: the host-only line with the host's
  name (the issue: "everyone in a round"), no Ready, no ready marks, no shortfalls (`refresh(..., in_round)`).
- Settings (`SettingsPage`, one scene in the Esc menu and in the main menu's Settings panel, §4.7.38): the `Sub`
  chips (Sound and voice, Controls, Display, Accessibility, Language) over a `follow_focus` scroll of 64 px
  ToySettingRows (`SettingRows`: the row, the ToyDropdown with its ToyDropdownList, the ToySlider, the chip groups).
  `VoicePanel` and `ControlsPanel` keep their logic and signals in the new rows (the sliders keep the engine's units,
  no number is drawn; the echo, headset and notice lines and the debug rows stay, in greybox English).
  `client/app/GameSettings` (out of `game.gd`) binds both pages to the player's `UserSettings` (new: `large_text`,
  `reduced_motion` -1/0/1, `window_mode`), `Controls` and `GameWindow`, applies and saves each pick (large text
  through `GameUi.set_large_text`, reduced motion through `UiPrefs`, the language through `Languages.choose`), keeps
  Alt+Enter and the window chips in step, and keeps the talk key shut while either page captures a key. A page reads
  its values again whenever it shows; the saved window mode applies only with the command line read.
- Tests: `esc_menu_states_test.gd` (the 15 states the menu builds against the handoff's own lists: the lobby-host
  tree, each state's Hidden list, Shown roots, pressed tab, title and Settings chip, its paths mapped onto the
  built tree; no deck key shown as itself in en or uk; seen failing with a planted fault in each), `esc_menu_state_test.gd`,
  `screens_test.gd` (the tree by name and variation, the host's question, its focus and the menu shut behind it,
  the tutorial, the Lobby tab in the round), `game_ui_overlays_test.gd` and `esc_menu_input_test.gd` (real keys: Esc
  closes only the dialog), `role_page_test.gd`, `settings_page_test.gd`, `setting_stepper_test.gd` (seen failing
  with the focus hand-over planted out), `lobby_presets_test.gd`, `game_settings_test.gd`, `user_settings_test.gd`,
  `hud_test.gd`, and the Voice and Controls suites. The `shot`s: `client/dev/esc_<state>_preview.tscn` for every
  state of the handoff but Character (`lobby`, `lobby_guest`, `lobby_no_code`, `game_host`, `game_guest`,
  `game_confirm`, `role_engineer`, `role_dissident`, `guide`, `guide_basics`, `settings_sound`, `settings_controls`,
  `settings_display`, `settings_access`, `settings_language`, `tutorial_game`; `lobby_round`, a guest's Lobby tab in
  the round), each with a `_uk` twin, and `esc_lobby_large_preview.tscn`, `esc_settings_sound_large_preview.tscn`.
  The playcheck scenarios `esc_menu` (the round's tabs too) and `main_menu` press the deck keys' buttons.
#### 4.7.43 Basic sound from Kenney's CC0 packs (#525)
No new event, row or rule: a client plays a sound only for the events and the snapshots it already receives, and
nothing for a door (M6.2 has none; the engineer, #525, 2026-10-07).
- **The files** (§11.1): `assets/audio/kenney_impact_sounds/` (footsteps on concrete, wood, carpet and grass, five
  each), `kenney_rpg_audio/` (`swing_1..2`, `pick_up_1..3`, `put_down_1..3`, renamed), `kenney_interface_sounds/`
  (`click_1..3`; `ui_outro`, #657; `ui_role_engineers`, `ui_role_dissidents`, #716), Ogg Vorbis through LFS,
  one `docs/credits/` entry per pack; and the project's own `prime_task_feedback/` (`task_success.wav`,
  `task_error.wav`, mono WAV through LFS, §4.7.60), whose CI stand-in is a silent WAV. The packs ship only Ogg, most of it
  stereo: `sfx-check` passes a mono or stereo Ogg (a WAV stays mono, AGENT_WORKFLOW §11.25), header-checked only;
  the engineer's verdicts from its listening page go to `assets/audio/sfx-verdicts.json`. In CI an Ogg pointer
  file imports a real 10 ms Ogg stand-in (the LFS ADR's amendment of 2026-10-10), so every load works there.
- `client/audio/`: `SfxSet` gives each sound id one `AudioStreamRandomizer` of its files (no repeats, pitch ×1/1.06
  to ×1.06, ±1.5 dB: placeholders), loaded at its first play; a file that does not load is left out and an id with
  none plays nothing. `AudioBuses.UI` sends to Master at −6 dB (no slider of its own, Master's applies; §6.5.5).
- `client/world/`: `WorldSounds` plays `Swung`, `ItemPickedUp` and `ItemPlaced` with their `SfxSet` streams, as
  before (the 12 m range, the one muffle ray), and footsteps each physics frame:
  - **Who:** the local player while living and on the floor, from its own movement; every other player the client
    draws while the model knows it living (not downed, dead or gone) and its snapshot not downed, from how far its
    interpolated pose (`AvatarViews`' body) moved. Never a claimed velocity (client/CLAUDE.md): a peer that claims
    to stand while it runs still steps, one that claims to run while it stands is silent.
  - **When:** `FootstepCadence` (pure): the step interval from the horizontal speed, 0.45 s at the mode's walk
    speed and 0.32 s at its sprint speed, the stride interpolated between them and held outside (placeholders);
    none below 0.5 m/s, and a still frame keeps the place in the step; a move faster than
    `SnapshotBuffer.SNAP_SPEED_MPS` in a frame (a respawn, a round start, a correction) plays none and starts the
    cadence again.
  - **Heard:** `SoundChooser.step` cuts a step beyond `HEARING_RANGE_M` of the ears before any ray. Another
    player's step casts the one muffle ray to `STEP_AIM_M` (= `ITEM_AIM_M`) above its feet; the own steps cast
    none (never muffled).
  - **Quiet** (#792, the crouch ADR's KD1 (b) as #991 changed it): anywhere (the crouch plays everywhere), a step,
    the own or another player's, at or below the mode's `crouch_speed_mps` plays
    `FootstepCadence.QUIET_STEP_DB` (−6 dB, added to the muffle's) and is heard within `QUIET_STEP_RANGE_M` (6 m:
    `SoundChooser.step`'s cut and `max_distance` alike); both ease linearly to a walk's step at the fast crouch's
    `crouch_fast_speed_mps` (`quiet_of`; the ease is a placeholder), so Shift while crouched sounds like a walk.
    Both numbers are placeholders, "not a decision". It is read from the step's speed, averaged over the step
    (`step_speed_mps`, so one jittery frame of a pose never sets it), never the crouch flag.
  - **Silent** (#990, §9.5.24): a step of a player whose relayed `sneaking` flag is set (the own `sneak_held`) AND
    whose step speed is at most `crouch_speed_mps` plus `FootstepCadence.SNEAK_SPEED_MARGIN_MPS` plays nothing for
    every listener (`FootstepCadence.silent_of`); a flag with a faster step is heard as the speed says.
  - **Surface:** `FootstepSurface`: one ray down from 0.3 m above to 0.5 m below the feet on the world layer; the
    hit collider's or its nearest ancestor's metadata `surface` (concrete, wood, carpet, grass) picks the set,
    untagged or unknown is concrete (the greybox tags nothing). No floor under the feet (a jump) plays no step.
    The House's floors carry their tags (#523, the content area: the art's Shell pieces and the plot's Ground);
    `tests/integration/levels/house_footstep_surface_test.gd` casts this ray on a 1 m grid over every piece's
    floor in the client's world of the House and asks for a tag on every floor hit (the garage too since the
    art's P6, #1052; #1042).
- `client/ui/`: `UiSounds.click`, from `ToyPress.on_button_down` (every Toy button and toggle: `UiParts.button`,
  `UiParts.toggle`, the connecting screen's back ghost, the map's help, the theme showcase): a mouse or touch
  press or `ui_accept`, never hover, release or a toggle's change alone; a disabled button sends no
  `button_down`. One `AudioStreamPlayer` (polyphony 4) under the window's root on the UI bus, made at the first
  click and kept, so a press that frees its screen does not cut its click; a button outside the tree clicks
  nothing. `UiSounds.outro` (#657), from `EndScreen.outro_began` (once each time End starts): `ui_outro`, the one
  sound of both outcomes, from its own player (`UiOutro`, polyphony 1) under the root on the UI bus, made at the
  first End and kept; no voice is routed through it (#213). `UiSounds.role` (#716), from
  `PregameScreen.role_revealed` (once per pregame, the own side's, §4.7.39): `ui_role_engineers` or
  `ui_role_dissidents`, each from its own player (`UiRoleEngineers`, `UiRoleDissidents`, polyphony 1) under the
  root on the UI bus, made at its first reveal and kept, and stopped (`UiSounds.stop_roles`) when the pregame
  ends (`lift`, `stop`), so none reaches the round; local to the own client, no voice routed through it.
- Tests: `tests/unit/client/world/footstep_cadence_test.gd` (the interval at walk and sprint speed, between and
  below; one step per interval; none standing; a still frame; a placement; only horizontal movement),
  `footstep_surface_test.gd` (the tag, the nearest ancestor's, the default), `sound_chooser_test.gd` (the step's
  12 m cut-off and aim; each former stub event plays its own files, replacing the blips' length test),
  `tests/unit/client/audio/sfx_set_test.gd` (every file exists and loads, one randomizer per id, five footsteps a
  surface, none for an id with no file), `audio_buses_test.gd` (the UI bus), `tests/unit/client/ui/toy_press_test.gd`
  (a press clicks on the UI bus, hover, release and toggle do not, the click outlives its button, none outside the
  tree), `pregame_screen_test.gd` (the role sounds, §4.7.39),
  `tests/integration/client/world/world_sounds_steps_test.gd` (a walker steps from its poses with a zero
  claimed velocity, a claimed run standing still is silent, none and no ray beyond 12 m, muffled behind a wall,
  none downed, dead or off the floor, the floor's tag picks the set; the own steps cast no ray and stop while
  downed; seen failing with the life checks and the own steps' ray planted). The listening checklist is the
  engineer's, in a two-client `host`/`join` session (the PR). The quiet step (#792):
  `footstep_cadence_test.gd` (`quiet_of` at, below, between and above the speeds; a mode without them; equal
  crouch speeds a hard edge; the step's speed over the step) and `world_sounds_steps_test.gd` (−6 dB and 6 m at
  crouch speed, a walk's at the fast crouch's (#991) and at the walk speed whatever the flag, eased between, cut
  beyond 6 m, the own slow steps too).
#### 4.7.44 The solo tutorial session in the game (#601)
T3 of the tutorial (`docs/design/tutorial.md` §2.1, §2.2, §5; E62, E67, E69, E70; D25, D26, D35 (a)). The lessons
(T4, #602), the invite and the plates (#492) and the Esc menu's tutorial variant (#491) build on it.
- **`Game.start_tutorial(invite := false)`** (`client/app/game_tutorial.gd`, `GameTutorial`, held in `Game.tutorial`
  to keep `game.gd` under lint's 1000 lines): false while a session runs. It sets `Game.mode` to
  `content/modes/tutorial_mode.tres` (§9.5.17) and hosts it through `Game.host_on` (the path `host()` and
  `host_with_code()` take) on a `LoopbackTransport` of a private `LoopbackHub`: `HostNode.host(transport, mode, port)`
  unchanged, the own `ClientSession` on `HostNode.own_client`. No socket opens and nobody else can join; the port
  (`GameTutorial.PORT`, `LaunchOptions.DEFAULT_PORT`) only keys the hub, and `Game.make_transport` is never called.
  The host writes no replay (`HostNode.skip_replay`: each would push a match's out of `ReplayFiles.KEEP`). The game
  sends the own `SetReady(true)` once welcomed (the tutorial has no Ready key). A failed start shows host-failed
  (the invite never counts as seen then), and Try again starts the tutorial again, without the invite.
- **The stand-ins** (`client/tutorial/stand_ins.gd`, `StandIns`, a child of `Game` named `StandIns`): two
  `ClientSession`s, each on its own `LoopbackTransport` that joins the hub (peers 2 and 3) once the own player is
  welcomed (`StandIns.join_host`), each stepped by a `SessionNode` of its own at physics priority -95 (after the
  `HostNode`'s -100, before the own session's -90; it runs while the tree is paused). Each sends `Hello` with no name
  (#550's ""), so the host's join count names them after the own player: `Player2` and `Player3` (stepped before the
  own session, they would otherwise say Hello first and take `Player1` and `Player2`). Then `SetReady(true)` once
  welcomed, `LoadAck` at once (`load_levels` off, as the bots), and `ClientSession`'s own claims from its last
  `Welcome` or `Correction` (at rest, on the floor), so it stands where the host placed it; nothing else, no intent,
  no voice. Its public members are `join_host()`, `count()`, `welcomed()` and `corrections()` (a test hook): no
  session, model or transport leaves the class.
- **The mode per session:** `GameTutorial.end` (called by `Game._end_session` before `_show_end`) frees the
  stand-ins and gives `Game.mode` back the mode it had (the base mode, or a test's), so a networked session after a
  tutorial uses the base mode again. `GameFlow` shows the loading screen for a phase with no level (`gather`, §4.7.4's
  table), which no base-mode phase is. The loading screen's how-to card reads the mode like any other: the tutorial
  mode has no `DealTasks` (#900), so `HowtoCards.dealable` finds no task type and its loading shows a tip; no
  tutorial branch in `GameHowto`.
- **Leaving:** `Game.hosting()` is `_host != null and not tutorial.running`, so the Esc menu's Leave and Quit and the
  window's close act at once, with no question. From `start` to `end` `GameTutorial` sets `GameUi.set_tutorial`: the
  Esc menu shows its tutorial variant (#491, §4.7.42): Game (Resume, Leave, Quit), Guide and Settings, no Lobby tab.
  Leave ends it as a host's own leaving (`EndReasons.CLOSED`: no failure, the main menu). D32 (b)'s end after
  lesson 9 is the lesson runner's `finished` calling `Game.leave()` (§4.7.46).
- **When it starts (E70):** `GameTutorial.setup` (the last line of `Game._ready`) wires the main menu's
  `tutorial_requested` to `start_tutorial(false)` (the item was disabled until #492, #672's answer 2A), starts it
  without the invite on `--tutorial`, and with the invite on a first launch: `GameTutorial.first_launch(options,
  settings)` holds only with no launch option at all (`LaunchOptions.given`, a wrong one too), the settings read from
  a file (`UserSettings.path` set) and `UserSettings.tutorial_seen` (`[player] tutorial_seen`) false. A Game with no
  command line (every test and `playcheck` window) keeps its settings in memory, and the runner's `host` and `join`
  windows pass options: none of them starts it (a test whose settings come from a file sets `tutorial_seen`, as
  `game_voice_test` does). `--tutorial` with `--host`, `--join=`, `--local` or `--code`, or in the headless session,
  is a problem. `invite_open` says the invite is due; since #492 (§4.7.49) only its Start and Skip (or Esc) set the
  flag (`GameTutorial.mark_seen`, written): a session ended under the invite (the window closed) offers it again on
  the next launch. Until #492 the end of an invited tutorial set it.
- **`playcheck`:** the scenario header `tutorial` (§4.7.22) starts one window with `--tutorial` and no `--host
  --local` or `--no-replay` (`hostjoin.tutorial_parts`); `players` and `windows` are 1, and `bots`, `role`, `setting`, `map`
  and `clock` are refused naming their line. The window still prints the `session: hosting` line, which nothing
  waits for with one window. Scenario `tutorial`: the room in the lessons phase with three players and lesson 1's
  plates, lesson 2's after a walk (#492), and its Esc menu.
- Tests: `tests/unit/client/app/game_flow_test.gd` (the tutorial mode's flow), `launch_options_test.gd` (`--tutorial`,
  `given` and the problems), `user_settings_test.gd` (the flag), `game_tutorial_test.gd` (the first-launch rule's
  table), `tests/unit/client/tutorial/stand_ins_source_test.gd` (only `stand_ins.gd` and `game_tutorial.gd` name
  `StandIns` or its node path, nothing else reads its private lists or builds a `ClientSession` but `game.gd`, the
  wiring makes no node lookups, no public member hands out a session; planted failures rejected),
  `tests/integration/client/tutorial/stand_ins_test.gd` (on a `HostNode` of the tutorial mode, what the host receives
  from each stand-in: one `Hello` with no name, one `SetReady`, one `LoadAck`, claims at one spot at rest, nothing
  else, seen failing with a planted voice frame; leaving the tree leaves), and
  `tests/integration/client/app/game_tutorial_test.gd` (E71: `start_tutorial` to the lessons and through both stages,
  the loading screen in `gather`, seen failing without `GameFlow`'s rule; the Esc menu's tutorial tabs (none after
  it) and its Game page's Leave with no question, the base mode again and a networked host after it, seen failing
  without the restore; no replay, seen failing without the skip; the first launch, `--tutorial`, a wrong launch and
  the menu's Tutorial); `tools/runner/tests/test_playcheck.py` (the header, its refusals and its one window's
  command line).

#### 4.7.45 Host text as ids plus arguments (#548)
Part (b) of #208 (§4.7.26): text the host makes for players reaches each client as an id plus arguments, and the
client words it in its own language, so two players of one lobby read the same shortfall or end reason each in theirs.
Protocol 13 (§4.3.4).
- **On the host.** `core/`'s `HostText` (`core/events/host_text.gd`): an id, its subject ids and its whole-number
  arguments by name, never a sentence. `FitCheck.shortfalls` makes `players_few` and `players_many` (`count`: how many
  players short or over, `min`, `max`), `no_layout` (no arguments: a map path is no wire id, and `SettingsChanged`
  names the map) and, since #803, `no_task_types` (no arguments: no task type plays on the map after the bans,
  §9.4.4); `Demands.shortfalls` makes `markers` (the spawn tag; `need`, `have`), `markers_exact` (#797: the spawn tag of an
  exact demand, §9.4.4, whose markers differ in number from the demand; `need`, `have`) and `colours` (the station kind;
  `need`, `have`); a task type's own `TaskType.layout_problems` (#807) adds `short_axis` (the car repair's `car_end`
  and `car` tags; `need`, the car kind's radius, and `have`, the axis's horizontal length, in whole centimetres). `MatchEnded`'s reason is the id of the win condition that reported the `won` (`Match` keeps it with
  the step's outcome and hands it to the row as `MatchContext.outcome_reason`), with `time`, the seconds the round's
  clock ran (`StartClock` records `MatchState.clock_ticks_total`; no time when it never started); a `won` that no win
  condition reported has neither. The reason ids are the content's (`WinCondition.id`), with no content change.
- **On the client.** `ClientModel` keeps the shortfalls as decoded (`{id, ids, numbers}`) and `MatchEnded`'s reason
  and time (`ended_by`, `round_seconds`, cleared with the match). `HostTextView` (`client/ui/host_text_view.gd`,
  pure) owns the table from a shortfall id to its deck key and words it with `TranslationServer`, the plural by the
  argument the key counts (`players_few` is `lobby.need_more`, by `count`); `LobbyPanel` (the Esc menu's Toy Lobby page, §4.7.42) and the lobby HUD's status (§4.7.47) show
  its lines, refreshed each frame, so a language switch rewords them. `EndScreen.REASON_KEYS` maps the reason ids (§4.7.31).
- **The deck's gaps (ui-0.6.0).** The deck has keys for `players_few`, `players_many` (`lobby.too_many`, by `max`), `markers` (`lobby.need_markers`, by `have` and `need`), `no_layout`, `no_task_types` (#718; no plural form, so no `PLURAL_BY` entry) and the reasons `every_task_done` and `time_up`. `markers_exact` (#797), `colours`, `short_axis` (#807) and `photo_spot_near` have none, so `HostTextView.plain` shows the id, its
  subjects and `name=value` arguments, no words of any language, rather than hide why the start is held back (in the
  base mode `players_few` occurs: the join limit stops `players_many`, `LayoutCheck` refuses a mode whose map
  lacks markers, colours or a layout); `no_crew_present` hides the reason line. No key is invented: the UI track's
  deck adds them, then one table entry each.
- **Tests.** `tests/unit/net/messages/wire_schema_test.gd` (no row carries `text` or `note`, seen failing on row 37
  before the change), `wire_codec_test.gd` (the longest host text round-trips; a sentence as an id, a third subject,
  a fifth argument refused; 32 longest texts beside 32 long settings over the cap), `wire_samples.gd` (all five
  shortfall ids, `MatchEnded` with and without a reason, round-tripped and fuzzed),
  `tests/unit/events/host_text_test.gd` (the decoder's types), `tests/unit/match/phases/lobby_phase_test.gd` and
  `lobby_phase_bans_test.gd` (each shortfall's id and arguments, `players_many`, `no_layout`),
  `tests/unit/win/end_match_test.gd` (the reason and the time, a rule's `won` without them, no clock no time; seen
  failing on the old `EndMatch`), `clock_ended_test.gd` and `content_modes_test.gd` (the base mode's reasons),
  `tests/unit/server/wire_budget_test.gd` (FitCheck's and Demands' longest texts encode),
  `tests/unit/client/ui/host_text_view_test.gd`, `end_screen_test.gd` (the reason from the model),
  `tests/unit/client/net/host_text_locale_test.gd` (one payload over the loopback in English, then Ukrainian, with
  the plural forms) and `tests/integration/server/host_session_host_text_test.gd` (every client of a host session
  decodes the same shortfall, and the same reason at the end, equal to `view_of`).

#### 4.7.46 The lesson runner and the lessons (#602; nine since #901)
T4 of the tutorial (`docs/design/tutorial.md` §1, §3; E63, E64 (a); the engineer's D29 to D33, D36 answers on PR
#596). The plates, the lesson list and the invite (#492) read it.
- **Data** (`core/content/tutorial/`, data only, §9.3): `TutorialLessons` (the root, `lessons`), `TutorialLesson`
  (`list_key`, `list_action` filling the row's `{key}`, one or two `steps`), `TutorialStep` (`title_key`, `how_key`,
  `keys`: InputMap actions or `TutorialStep.HOWTO_GLYPH` for the map's «?»; `starts_when`, `on_start`, `done_when`,
  `triggers`, `conditions`) and the closed list of parts of the design's §3: the triggers `EventSeen` (`event`,
  `fields` matched as `WaitFor`; the markers `own`, `other` on a peer field, `held` on an item field) and
  `ClientSeen` (`signal_name`, one of `moved`, `map_opened`, `howto_opened`, `spectate_switched`, `voice_sent`,
  `esc_opened`; `amount` in seconds), the conditions `OwnLife` (`life` by name: `alive`, `downed`, `dead`, `left`, so
  `core/` data names no state class), `OtherWithin` (`metres`, 0: the phase's `VoiceRule.radius_of`), `ItemKindIs`
  (only in `conditions`: it reads the fired event's `item`) and `TasksDone` (at least one task, all done), the action
  `RequestStage`. Each has `problems()`. The lessons are `content/tutorial/tutorial.tres` (provisional, approved on
  PR #722, §9.6).
- **`LessonRunner`** (`client/tutorial/lesson_runner.gd`, a pure `RefCounted`; a source test keeps nodes, input,
  sessions and sends out of it): `setup(lessons, model)`, `start()` (once), then `on_event(name, fields)` (after the
  model folded it), `on_claim(covered, moved_itself)`, `see(signal_name)`, `advance(delta_s, own_position,
  mic_live)` every frame and `esc_closed()`. A step starts once its `starts_when` holds (until then the previous
  lesson stays done and `lesson()` is 0), records the own hand item (`held`) and zeroes its counters, emits
  `next_stage_requested` for each `RequestStage`, and completes at once when its `done_when` holds; else the first
  trigger firing from its start with its `conditions` holding completes it. `moved` adds the `covered` ticks of the
  claims that moved the player itself (`Ticks.RATE`) until `amount`. `voice_sent` fires on a frame sent and, with an
  `amount`, after that many seconds in a row in which the step's conditions hold and no microphone is open (D31 (a):
  a voice frame within the radius, or 3 s within it with none open). After the last lesson, a completion by
  `esc_opened` makes the next `esc_closed()` emit `finished` (D32 (b)); a menu opened before lesson 9 started does
  not count. Signals `changed`, `next_stage_requested`, `finished`; queries for #492: `lesson()` (1-based, 0 for
  none), `step()`, `current_step()`, `keys()`, `is_done(n)`, `lesson_count()`, `is_running()`, `is_finished()`.
- **The wiring** (`GameTutorial`, so no screen knows the tutorial exists): `start()` builds `Game.tutorial.runner`
  over the own session's model (`end()` drops it) and binds the session's `event_received` and `claim_sent` to that
  runner (a handler of an older session's runner does nothing); `setup()` connects, once, `GameUi.map_opened` and
  `LifeView.target_switched` (fired by `cycle_target` only, when the dead player picks another target: never the
  first target drawn at the death or a lost one replaced). `GameTutorial.process(game, delta)` (the last line of
  `Game._process`) feeds `advance` with the local player's position and `VoiceSender.live()`, and a `delta` of 0
  while the Esc menu is open (`GameUi.esc_open()`): D31 (a)'s quiet time stands still there, an open microphone
  still resets it (the engineer's answer on PR #722); `howto_opened` on a
  rise of `MapScreen.howto_open()` (polled, so it holds whichever order the «?» emits `howto_requested` and opens the
  card in), and `voice_sent` when `VoiceSender.sent` rose; `Game.open_esc` and `close_esc` (its last line) call
  `esc_opened()` and `esc_closed()`. `next_stage_requested` sends `NextStage` through the own session; `finished`
  calls `Game.leave()`. Without the invite, lesson 1 begins as `PhaseChanged` brings the `lessons` phase; with it,
  `GameTutorial.begin(game)` is #492's Start.
- **The nine lessons** follow the design's §1 table and §9.3 on the deck keys of `client/i18n/strings.csv`
  (ui-0.4.0; LD8 (a)): lesson 3 as drawn (D29 (a)) until the UI track's first instruction exists (#150); #900 (the
  tutorial without tasks, its ADR `docs/decisions/2026-10-12-tutorial-without-tasks.md`) dropped the Delivery
  lesson and the map lesson's «?» step (LD2 (a), LD7 (a)): lesson 5 only opens the map; lesson 7 completes on the
  switch or the own `Respawned` (D36 (a)); lesson 1's key row also lists `crouch` after `jump` (825c, #902, LD4 (b); the row only shows the key, lesson 1 completes on walking alone), its label the deck key of `Controls.ACTIONS`' row (#951); `sneak` follows `crouch` (#1009). #901 (825b, LD3 (a)) added lesson 4, the throw, after Hand and belt: its one step (`tutorial.step.throw.*`, the `throw` key) completes on the own `ItemThrown`, and its how asks for an item in the hand (a belt item is never thrown). Lesson 8 waits for the own life living. The parts `TasksDone`,
  `howto_opened` and `TutorialStep.HOWTO_GLYPH` stay, used by no lesson (LE3 (a)). The numbers (1 s, 3 s) are
  D33's placeholders. If the host refuses a `NextStage`, nothing sends it again: the lesson stays.
- Tests: `tests/unit/content/tutorial/tutorial_parts_test.gd` (the closed list, each `problems()`, `OwnLife.LIVES`
  against `ClientModel.Life`), `tutorial_content_test.gd` (the nine lessons as §1's rows, lesson 1's row with `crouch`, deck keys and actions,
  `RequestStage` only in 6 and 7, no step waiting on what nothing can complete: a `howto_opened` with no card, a
  `TasksDone` with no task type), `tests/unit/client/tutorial/lesson_runner_test.gd`
  (every trigger and condition, the markers, `held`, D31's timer, `starts_when`, `done_when`, `RequestStage` once,
  the end after the menu closes), `lesson_runner_source_test.gd`, the switch in
  `tests/integration/client/life/spectate_cycle_test.gd`, and
  `tests/integration/client/app/game_tutorial_lessons_test.gd` (the nine lessons on the real session, no task dealt
  and the package put down where the player stands, the stages from the runner's own `NextStage`, lesson 8's quiet
  time paused under the Esc menu, the end at the main menu; the invite's `begin()`, a second tutorial's fresh
  runner); the `tutorial` playcheck scenario plays through lesson 4's throw to lesson 5's map.

#### 4.7.47 The lobby HUD in the Toy style (#495)
The lobby's HUD (§4.7.11's `LobbyHud`) redrawn as the UI track drew it: prime-game-ui `ui-0.4.0`
`docs/handoff/s04-lobby.md` (not `ui-0.2.0`: since then the keycap's `min_width` follows the text size and the
`check` icon's `svg_scale` is the pack's `assets` list's, 1, not the 5 #495's `ui-0.3.0` note gave), node for node, px
at the 1920x1080 base (§4.7.24), styled by the pack's variations only (no override, `theme_test.gd`).
- **The tree** (`client/ui/LobbyHud`, built in code under `GameUi`; `Plates`, §4.7.29, stays the first child of
  `Ui`, under it, the same layer as the round's): `Cross` ToyCrosshair (centre); `Status` ToyPlate (top centre, 40 px
  down) > `Text` ToyPlateText, ToyTitleOnDark during the countdown; `Players` ToyPlate (top right, 400 px) > `V`
  ToyColumnSixteen > `Info` ToyColumnEight (`LobbyName` ToyTextMutedOnDark; `CodeRow` ToyRowEight > `Label`
  `common.code`, `Code` ToyKeyOnDark > `Text` ToyKeyText) and `List` ToyColumnEight (`Head` ToyTextOnDark, `Rows`
  ToyColumnEight > one ToyRowTwelve per player: `HostRow`, the own `OwnRow`, the others `Row<n>`, each `Name`
  ToyTextOnDark expanding and `Ready`, the pack's `check` at 24 px tinted ToyTextOnDark's `font_color`, shown while
  that player is ready); `Bottom` ToyColumnTwelve (bottom left) > `ReadyChip` (ToyChipPlate `lobby.ready_no`, or
  ToyChipLight `lobby.ready_yes`) and `Mic` ToyMic > `Icon` (`mic` tinted `icon_on`, else `mic-off` `icon_off`, as
  the round's). The keycap's `min_width` (36, 42 at large text) is read again after each theme change
  (`UiParts.sized`). Every Control ignores the mouse and takes no focus, also the rows built later. Names and the
  lobby's name are cut with an ellipsis inside the plate.
- **What it shows** (`LobbyText`, pure, from the own `ClientModel` and the own mode): the status, the countdown while
  one runs (`lobby.countdown`, 5 to 1, from `end_tick`), else the host's shortfalls while it sends any (§4.7.45's
  `HostTextView`, one line each: `players_few` reads `lobby.need_more` with the host's `count`, an id the deck has
  no key for its neutral line; never a count of the client's own), else `lobby.waiting` (ready of all);
  `lobby.player_count` against the mode's
  `max_players`; the lobby's name (`LobbyName`'s, else `lobby.default_name` with the host's name); the rows, the host
  first, then the order the model got them (the Welcome's roster, then each `PlayerJoined`: the order they joined),
  reading `player.you` for the own row, `lobby.host_mark` for the host's, else the name. All of it is the whole
  lobby's (the roster, the ready flags, the host, the lobby's name, the countdown, the host's shortfalls, which every
  peer gets alike): no role, team or match fact. The
  rows are built again only when a join, leave, rename or ready changes them; the texts with data are set with
  `auto_translate_mode` DISABLED and written again on `NOTIFICATION_TRANSLATION_CHANGED`.
- **The code** (`LobbyHud.show_code(code, gone, waiting)`, from `GameJoin.refresh`): the code to the host and every
  code joiner, "…" while the host's code service has not made the room, "—" once it is gone (the Esc Lobby tab
  explains it and has Copy), no row for a Direct game. **The mic**: `VoiceSender.live()` (`GameTalk.refresh`).
- **No key prompt:** Ready is the bound `ready` key (#211) and the Esc Lobby tab's button.
- **Beyond the handoff:** M5-6's voice hint until a microphone is picked stays, a `VoiceHint` ToyChipPlate over the
  ready chip (plain English, as before). Besides `players_few` the status shows the host's other shortfalls, one line each by its deck key (`players_many` is `lobby.too_many`, `markers` is `lobby.need_markers`, `no_layout` and `no_task_types` their own, #718); `colours` (and `markers_exact`) have no key and stay #548's neutral line. The Esc Lobby page's Shortfalls label words them the same way.
- **After a match** the host sends its shortfalls again as the match returns to the lobby (`ResetMatch`, #737), so
  the status and the Esc Lobby page read `players_few` there too, never a count of the client's own.
- Tests: `tests/unit/client/ui/lobby_text_test.gd` (the rows' order, the status's three states and their texts in
  English and Ukrainian, `lobby.need_more` from the host's `players_few` for 1, 2, 5, 11 and 21, an id without a
  key in the neutral line, no shortfall from the host not short, the countdown from 5 to 1 before short, the
  lobby's name, the rows' names, a role or teammates known changing nothing), `lobby_hud_layout_test.gd` (the
  handoff's tree, anchors, offsets, grow directions, size flags and minimum sizes; no mouse or focus; the ellipsis
  inside 400 px; the tints; count, short, code-waiting, direct and a gone code; the rows rebuilt only on a change; a
  language change, seen failing without the notification; large text's keycap), `esc_menu_input_test.gd` (no
  prompt; the ready key's rebind reaches the chip and the check), `game_code_join_test.gd` (the code row; "—" when
  the service is gone), `game_voice_test.gd` (the voice hint; the mic follows the sender). The `shot`s, at
  `--size 1920x1080`: `client/dev/lobby_hud_preview.tscn` (`wait`, a code joiner), `lobby_hud_host_preview`,
  `lobby_hud_count_preview`, `lobby_hud_count_host_preview`, `lobby_hud_short_preview`,
  `lobby_hud_code_waiting_preview` and `lobby_hud_direct_preview`, each with a `_uk` twin, and
  `lobby_hud_large_uk_preview` (`short` and `code-waiting` fold the host's `players_few` against four players, the
  handoff's sample). The playcheck fields `lobby.status`, `lobby.roster` and `lobby.ready` read the new nodes
  (`esc_menu`, `end`).

#### 4.7.48 No literal text, content names and the font's glyphs (#549)
Part (c) of #208 (§4.7.26), after the Toy screens.
- **No literal text.** `tests/unit/client/i18n/literal_strings_test.gd` reads every script and scene under `client/`
  (`client/dev/`'s previews left out) and fails on a string literal that reads as words but is no deck key and not
  in its allow-list `tests/unit/client/i18n/literals_allowed.txt`. Words: any Cyrillic, Latin words with a space
  between (a placeholder counts as a word: "Mouse %d"), and one capitalised word only where it is text (a Control's
  `text`, a value named for text such as `MAP_LABEL`, a `tr()` argument): elsewhere one word is a node's name, of
  which the screens have hundreds. Not words: keys, ids, paths, formats; `&"..."` and `^"..."`; comments; strings in a
  log or assert call (`push_error`, `print`, `assert`...) or in a call naming an engine thing (`get_node`, `connect`,
  `load`, `set_meta`...); a node's `name`. An allow-list line is `<path> | <literal as written> | <why>`, `*` for a
  whole file (the debug overlay, the command line's problems, the end reasons' log words); its why names the issue or
  comment tracking the missing key (#150's requests, comment 6095875901: the lobby's "Map"; comment 6096420162: the
  rest, items 5 to 11) or why the text is never shown (the greybox lobby texts the Toy lobby HUD #495 left unused).
  A line that matches nothing fails, so a screen moving to keys deletes its lines (#497's downed screen did, on the
  rebase, and #495's lobby HUD its old hint). Not seen by the
  scan: words built at run time and text a variable not named for text carries; #548's neutral shortfall line is
  ids and numbers, and the raise cue's stopgap a deck key (`tutorial.step.downed.how`), no literal. Nor does it
  read outside `client/`: `voice/voice_capture.gd`'s "the microphone ... did not open" and "froze" notices reach the
  voice panel through `VoiceControl.notice` and are English literals with no deck key yet (listed with
  `voice_sender.gd`'s in the PR).
- **Content names** (`client/ui/ContentNames`, pure): a role, item kind or task type shows by its deck key
  (by the convention `role.<id>`, `item.<id>`, `task.<id>` where the deck has the key, so content adding a type the
  deck names needs no edit; `ROLE_EXCEPTIONS` holds the one id that differs: the base mode's crew are
  `role.engineer`), else the content's display name, else its id; a room by `room.<id>` where the deck has it, else
  its id; a map by its scene's file name ("House"). A Control given one translates it and retranslates on a switch;
  `text()` gives it in the language now. `HudText` (the HUD's role and slots), `RoleFacts`, `PregameScreen`,
  `MapScreen` (task rows, rooms) and `LobbyPanel` (the task chips, the map picker) ask it (the unshown
  `ItemInteractions.hint()` keeps the display name). The deck (`ui-0.4.0`) has no key for a map, the House's rooms or
  the `tasks` count setting: they show as before (no key invented, the PR lists them). `TASK_EXCEPTIONS` names a
  type the deck has no `task.<id>` for by the nearest key it has: `colour_delivery` as `task.delivery`, the Generator as
  `task.switches` (§9.5.19) and the photo task as `room.photo_zone` (§9.5.22, #784); the photo task's Film and Photo
  show their display names until the deck has `item.film` and `item.photo`.
- **The font's glyphs.** `tests/unit/client/i18n/deck_glyphs_test.gd` loads the real
  `assets/ui/toy_pack/fonts/Comfortaa-VariableFont_wght.ttf` from its own bytes (`FontFile.load_dynamic_font`, FreeType's character map
  through `has_char`), not Godot's import, and fails on any character of the deck's `en` and `uk` columns
  (placeholders and line breaks left out) it lacks. In a checkout without LFS content (CI, §4.7.21) the file is a
  pointer and the import a stand-in font: the test prints a `skip:` line naming it and checks only that it is a
  pointer, so the glyphs are checked on every machine with the font (the local `test` and `verify --full`).
- Tests: the two above (each with planted cases: the literals it must find and pass, the allow-list's format, the
  deck's characters without placeholders, a private-use character the real font lacks) and
  `tests/unit/client/ui/content_names_test.gd` (every role, item kind and task type of every shipped mode has a deck
  key with English and Ukrainian text; both languages and a switch; what the deck does not name);
  `client/dev/menu_uk_preview.tscn`: a
  `shot` of the main menu in Ukrainian, beside the Esc menu's `*_uk_preview.tscn`.

#### 4.7.49 The tutorial's invite and lesson plates in the Toy style (#492)
The UI handoff's s1 (prime-game-ui `ui-0.4.0` `docs/handoff/s01-tutorial.md`, with ui-0.3.0's keycap and `check`
notes) over the tutorial session (§4.7.44) and its lesson runner (§4.7.46); `docs/design/tutorial.md` §1, §5.
- **`TutorialScreen`** (`client/ui/tutorial_screen.gd`, `GameUi.tutorial`, a child of `GameUi` after `LifeScreen`
  and before the map: the `Ui` layer, the handoff's HUD layer 2 (its table names the lesson plates there and not
  the invite, which shows with them only in the round, where no black screen is up; #656), under the map and under
  the Esc menu on `GameUi.above`, §4.7.32), node for node: the invite (`Dim` ToyBackdrop
  taking the mouse; `Lang`, the chips `Uk` and `En` of `ToyChipToggleOnDark` in one ButtonGroup, each `lang.*` key
  naming its language in itself, the one spoken pressed; `Box`, a raised ToyPanelDialog 688 px wide with the title,
  the body, Start (`UiParts.button`, ToyButtonPrimary) and Skip (ToyButtonGhostOnLight)), `Step` (912 px, 40 px
  down: Progress `tutorial.step.progress`, Title, and How) and `List` (440 px, top right 256 px down: Head and the
  eight `Rows` since #900). Only pack variations, no override. `show_lessons(lessons, lesson, step, done)` draws the
  plates and redraws only when its arguments or a bound key's label changed, so the game calls it every frame and a
  rebind in Settings > Controls (or the layout, through `KeyLabel`) redraws the keycaps.
- **How:** a step with a `how_key` is `tr()` of it split at `{key}` (`LifeHud.give_up_pieces`: `strip_edges()`, an
  empty piece hidden), `Before`, the `Key` keycap and `After`; the keycap is a ToyKeyOnDark holding a ToyKeyText
  label of `KeyLabel.of_action` of the step's first key (`key.space`, `key.mouse_left` from the deck), its width
  `min_width`, or `wide_min_width` for Space, Shift, Tab and Esc (`KeyLabel.is_wide_action`), read again after each
  theme change (the large-text 42 px); `TutorialStep.HOWTO_GLYPH` is a ToyKeyRound «?», the map's. A step with keys
  and no `how_key` (lesson 1) is `HowKeys`: `Walk` (the four walking keys, `control.walk`), then a group per other
  key named by its `Controls.ACTIONS` row (`Sprint`, `Jump`). A step with neither (title only; no lesson since
  #900) hides How. Lesson 8's Esc keycap reads Godot's key name ("Escape"): the deck has no `key.esc`.
- **List:** a done lesson is `<Name>Done` (its name, then the `check` icon tinted with ToyTextOnDark's
  `font_color`), the current one `<Name>Now` (a one-line ToyChipLight; the plate grows to the left for a long one),
  the rest the muted, wrapping names; `<Name>` is the list key's last part in PascalCase (the handoff names lesson 2
  `PickUpNext` in one state and `HandBelt` in another: one rule here). `tutorial.list.map`'s `{key}` is the bound
  `list_action`. Every plate node ignores the mouse and takes no focus. Texts with data or in pieces are set from
  code (`auto_translate_mode` DISABLED) and rebuilt on NOTIFICATION_TRANSLATION_CHANGED.
- **Placement:** `GameUi.show_screen` shows the screen in the round while the tutorial runs (`set_tutorial`, which
  also clears it at the end) and hides the HUD and the life plates under the invite (s1's `invite`). While the dead
  player's Spectate plate shows (lesson 6) the Step plate sits 24 px under it (`set_step_under`; s9's Protect gap,
  not a decision: s1 draws no dead player).
- **The game** (`GameTutorial`): once the room is in with `invite_open`, `open_invite()` (Start focused) and the
  mouse freed; `GameUi.blocks_keys()` (the Esc menu or the invite) and `frees_mouse()` (the map or the invite) feed
  `GamePlayer.apply_flags`, so no key counts under the invite and a click does not recapture; the map key is
  ignored there. Esc is the invite's Skip through a `UiOverlays` entry (`INVITE`, layer 2). Start writes
  `tutorial_seen`, closes the invite, `begin()`s lesson 1 and captures the mouse (focused windows only); Skip writes
  it and leaves (`EndReasons.CLOSED`: the main menu, no failure). A chip calls `GameSettings.choose_language`
  (applied and saved; the invite's texts follow). The main menu's Tutorial is enabled and starts it with no invite.
- Shots: `client/dev/tutorial_preview.gd` (the tutorial room from its start spot, the HUD without timer and role):
  `tutorial_invite_preview`, `tutorial_step_preview`, `tutorial_step_keys_preview`, each with a `_uk` twin, and
  `tutorial_invite_large_uk_preview`, `tutorial_step_large_uk_preview` (the «?» step's `tutorial_step_howto_preview`
  went with the step, #900); `playcheck tutorial` shoots the loading screen (a tip: no task, no how-to card),
  lessons 1, 2 and 4's map (no task listed) in the game, waiting on the new fields `tutorial.step` and
  `tutorial.how`.
- Tests: `tests/unit/client/ui/tutorial_screen_test.gd` (the tree of each state, a title-only step it builds, the
  list, no mouse, a rebind, Ukrainian, large text on screen for every step, the step under the Spectate plate),
  `tests/integration/client/app/game_tutorial_invite_test.gd` (the invite over the room with no key, no map and a
  free mouse; Start, Esc, Skip and a chip; the menu's Tutorial with plates and no invite, seen failing without
  `blocks_keys`' invite), `game_tutorial_test.gd` (the flag only from Start and Skip), `main_menu_test.gd`.
#### 4.7.50 The bodies in their players' colours (#551)
The client half of §3.5's body colours. `ClientModel.Member.colour` follows `Welcome`'s roster, `PlayerJoined` and
`ProfileChanged` (which also renames), and `ClientModel.colour_of(peer)` gives 0 for a peer not on the roster.
`BodyColours` (`client/player/`) maps an index to what is drawn: the delivery circles' ten colours (the
circle `StationKind`'s palette in `content/tasks/colour_delivery.tres` since #828, in its order, which `body_colours_test.gd` pins),
the engineer's choice on PR #745 until the UI track's player-colour list (asked on #150) replaces them; one const
array, `BodyColours.HEXES`. `AvatarViews` paints each remote body every physics frame through
`RemotePlayerBody.set_colour`, which only recolours the capsule's own material on a change (no mesh per frame; a
colour set before the body is ready waits for its rules). Each ragdoll, the own one included, wears its player's colour (`RagdollView.set_colour`, 728d); a dead
body's is `LifeLooks.BODY_COLOUR`, grey. No picker
yet: the Esc menu's Character page (#491, M7) and the main menu's remembered colour will send `SetProfile`
(`ClientSession.send_intent`); `client/app/` and `client/ui/` are untouched. The Toy lobby HUD (§4.7.47) shows no
colour: its handoff (s04) draws none, the swatches are only on s05's Character page. Dev preview:
`tools\run.cmd shot client/dev/colours_preview.tscn` (ten bodies, the last two downed). Tests:
`body_colours_test.gd`, `client_model_test.gd`, `avatar_views_test.gd` (the colour, a profile change on the same
material, the ragdolls' colours).

#### 4.7.51 The zones, their fill and the done look (M7-Z4, #650)
The client side of the zone task (§9.5.18; the [zone task ADR](decisions/2026-10-09-m7-zone-task.md)'s ZD6 (a),
ZD11 (b) and ZE8, as the engineer answered them on #302).
- **Which stations are zones.** A station whose kind is the `zone` of a `ZoneTask` in the client's own copy of the mode
  (`ZoneViews.zone_task(mode, kind)`); `CircleViews` leaves those out (since #801 it draws only Delivery's circles, §4.7.54).
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
  `ZoneTask` (added in #649, M7-Z3), a stand-in of their own if a mode has none.

#### 4.7.52 The throw key, the predicted arc and the remote arcs (#645, 37e)
The client side of throwing (§7.1.16; the [throwing ADR](decisions/2026-10-09-throwing-held-items.md)'s TD7 (a) and
TE5 (a)). The wire is unchanged.
- **The key.** The input action `throw` on G: a provisional pick on the engineer's delegation (#302 comment
  6085904317), "not a decision"; Q stays an exact put-down. G was also `give_up` (F since #211, §4.7.28),
  which acts only while downed and
  counts its hold only from a press made while downed (§4.7.9). `ItemInteractions.throw()` sends `Throw(facing)`
  (the camera's look vector) only while the own player is living, its hand (never the belt) holds an item, the
  client's own copy of the mode has a `Throw` rule for it (`ItemArc.rule_of`: the hand item kind's actions, then
  the role's, then the mode's, the first rule triggered by `Throw`, its first `ThrowItem`, as core finds it), the
  phase takes `Throw` from the living, and no earlier throw waits for its answer. With no such rule G sends
  nothing (the base mode until 37f). `ClientSession` sends the last claim's reliable twin right before it (#644).
- **The prediction** (`ItemFlights`, `ItemArc`, pure, in `client/world/`). `throw_sent` hands the seq, the camera
  and the look to `ItemViews.predict_throw`: the arc starts at the camera with the velocity and gravity built as
  `ThrowItem` builds them from the rule's numbers (bit for bit the host's for the same facing), drawn on the
  thrower's own clock from the press, and the first-person hand shows nothing. Until the arc's `ItemPlaced`, each
  physics frame sweeps the drawn item's step through the own scene (a sphere of the rule's radius against the world
  layer: `intersect_shape` at the start, then `cast_motion`'s safe fraction, as `HostWorldQuery.sweep`) and holds
  it where the sweep stops it: presentation only. The own `ItemThrown` swaps in the host's vectors and launch tick,
  and an offset that keeps the drawn item where it was fades out over `ItemArc.EASE_S` (0.2 s, not a decision); the
  drawn time stays on the thrower's clock. The Throw's `Rejected` (by seq), or no answer within
  `ItemFlights.PREDICTION_TIMEOUT_S` (2 s, not a decision; the reliable lane always answers), drops the arc and the
  hand shows the item again.
- **The remote arcs.** Every other `ItemThrown` gets an arc drawn at `AvatarViews.drawn_at()` less the launch tick,
  the host-tick timeline the avatars are drawn on (behind by the interpolation delay). Between two whole ticks the
  item is on the straight segment from point(k) to point(k + 1), the segment `FlightTicks` sweeps; at a whole tick it
  is `ItemFlight.point()` exactly, no second copy of the formula. Before the drawn tick reaches the launch the item
  stays at the thrower body's hand point (`carry_point()` for a two-handed kind), so it leaves the hand as the body
  is seen throwing it; with no body drawn it is hidden; no point before the launch is ever computed. A spectator
  watching the thrower from its eyes sees no such item there: `LifeView` hides the views that
  `ItemFlights.awaiting_launch_of(peer)` names, with the watched peer's hand and belt items (#168).
- **The stop and the fall.** `ItemPlaced` with the cause `thrown` ends an arc: the host drops a stopped item straight
  down, so the stop is the arc's point whose x and z are the rest's (`ItemArc.stop_of`; within
  `REST_TOLERANCE_M`, 5 cm, not a decision), and a throw with no horizontal speed falls back to the rest's height;
  the stop can lie no later than the estimated host tick at the event's arrival (`AvatarViews.host_tick()`; the
  thrower's own clock for its own arc) plus `STOP_SLACK_TICKS` (3, not a decision). The drawn item flies on to the
  stop, then falls straight down with the arc's gravity (sqrt(2h/g)); the own arc held at a wall falls from there.
  A rest not below the arc (off its line, behind the launch, the no-floor fallback at the thrower's feet, TD11 (a)),
  or a stop the drawn item has already flown more than a tick past, ends the arc at once at the rest. The exception
  is the own arc past a stop: its clock runs ahead of the host's flight by the round trip, and its sweep sees the
  level only, not a living player the host stopped the item on, so it glides back to the rest over
  `ItemArc.GLIDE_S` (0.15 s, not a decision) instead of jumping.
- **A phase change.** `PhaseChanged` and `LoadMatch` drop every arc and the prediction; the model keeps `flying`, so
  `ItemViews` hides the item until its `ItemPlaced`, if one comes, and no later phase draws it again (after a phase
  without `FlightTicks` the host's flown ticks are no longer the host tick less the launch tick). An item picked up,
  or gone from the model, loses its arc.
- **The view** (the M4 ADR's §3 items 3, 5 and 10): the item in flight is its ordinary depth-tested `ItemView`, with
  no trail, outline, label or `no_depth_test` overlay, already in `SightHider.GROUP` (its `sight_point()` follows
  the arc), placed in `ItemViews`' physics step (priority 1, after the avatars and before `SightHider`).
- **The sounds.** `SoundChooser` plays `ItemThrown` at its origin, the thrower's eye (`THROW`, aim at the origin),
  cut beyond `HEARING_RANGE_M` of the ears and muffled behind the level by `WorldSounds`' ray: uncut, it would tell
  every client where a package was just thrown to hide it. `ItemWorld` forwards every event to `ItemViews` and
  plays neither `ItemThrown` nor a thrown item's `ItemPlaced` on arrival: `ItemViews.sound_due` hands them to
  `WorldSounds.on_event` when the drawn item launches (the own throw at the press, from the predicted origin; the
  host's own `ItemThrown` repeats nothing) and when it reaches its rest; an `ItemPlaced` with no arc lands at once.
  The launch sound is a generated placeholder blip like the others (`WorldSounds.blip`); the asset is the
  engineer's to pick.
- Tests: `tests/unit/client/world/item_arc_test.gd` (the points against `ItemFlight.point()`, the fraction on the
  segment; the prediction against a fixture match's real `ItemThrown`, bit for bit; `rule_of` in core's order
  against a match's launch speed; the stop against a fixture match's wall stop, the longest flight, a vertical
  throw, a rest off the arc and the no-floor fallback: seen failing without the past-the-stop rule, reverted; the
  fall; the easing), `tests/unit/client/world/item_flights_test.gd` (the hidden hand, `Rejected` by seq, the
  timeout, the own adoption with no second launch sound, the remote timeline and its launch sound, the stop, fall
  and landing sound, no arc for a landing, the own sweep held at the wall: seen failing without the hold, reverted;
  no sweep of a remote arc; a phase change, a new match, a pick-up),
  `tests/integration/client/world/item_views_flight_test.gd` (a remote throw in the body's hand, then on the arc at
  the drawn tick, to its stop and rest; the view in `SightHider`'s group with nothing drawn through walls; hidden at
  a phase change until its rest; the own throw's empty hand and `Rejected`; the own drawn item held before a
  fixture wall: seen failing without the sweep, reverted), `item_interactions_test.gd` (G after the claim's twin,
  one at a time, Q still `PutDown`; nothing without a rule, in a phase that takes none, for a belt item, downed),
  `item_world_throw_test.gd` (the launch sound at the press, none for the host's own `ItemThrown`, the landing sound
  only once the drawn item lands, a put-down's at once), `sound_chooser_test.gd` (a launch beyond the hearing range
  plays nothing), `world_sounds_test.gd` (a launch behind a wall muffled, none beyond the range),
  `tests/unit/client/life/life_view_give_up_test.gd` (the give_up key held through the knockdown: seen failing without the guard,
  reverted) and `input_actions_test.gd`. The `shot`: `client/dev/throw_preview.tscn`, on a `Throw` rule of its own
  built in code (the base mode gets its rule in 37f): five packages on one remote arc, one falling from its stop at
  a wall, and the own predicted knife held at a wall a step ahead.

#### 4.7.53 The animated character (#522)
The art character (`assets/characters/slice_m1/`, §11.3) on the avatars, its clips from a pure mapping, and the
knocked-down body as its skeleton's ragdoll. Not built: the cast (heads, hair, faces, art#42) and which parts take the
body colour (a follow-up of #522), and a mirror or shadow of the own living player.
- `client/player/AvatarClips` (pure, `RefCounted`): the drawn state in, the clip out. The state is what the client may
  draw (invariants 2 and 7): a remote avatar's drawn move (its interpolated position's change over the drawn frame,
  never `Pose.velocity`, a claimed or host velocity; a source test holds it), its pose's yaw and public `crouched` bit
  (#790), whether its hand item (`ClientModel.hand_item`, from events it already received) is two-handed, and its
  life (knocked down, or a dead player's body). The rates are the drawn speed over the clip's ground speed at rate 1
  (the art's table: `Jog_*` and `Strafe_*` 4.5 m/s, `Sprint_Fwd` 7.0, `Crouch_Fwd` 0.75), clamped to 0.25..4.0 (a
  placeholder, "not a decision"). Checked in this order:

  | State | Base clip | Rate |
  |---|---|---|
  | knocked down, or a dead body | none: the ragdoll (`RAGDOLL`, KE7), no clip; a revive stands up at once (KD7 (a)) | - |
  | drawn speed under 0.5 m/s (`FootstepCadence.MIN_SPEED_MPS`), crouched | `Crouch_Idle` | 1 |
  | drawn speed under 0.5 m/s, standing (sneaking too) | `Idle` | 1 |
  | moving, crouched (any heading) | `Crouch_Fwd` | speed / 0.75 |
  | moving within 45° of the body's back | `Jog_Bwd` | speed / 4.5 |
  | moving more to a side than ahead | `Strafe_Left`, `Strafe_Right` | speed / 4.5 |
  | moving ahead, at most halfway from the walk to the sprint speed (`PlayerRules`) | `Jog_Fwd` | speed / 4.5 |
  | moving ahead, faster | `Sprint_Fwd` | speed / 7.0 |

  Holding a two-handed item adds the `Carry_Upper` layer over any base (carry idle = `Idle` + `Carry_Upper`, carry
  walk = `Jog_Fwd` + `Carry_Upper`). Picking up and putting down are one-shots (`one_shot()`): `Pickup_Package` and
  `Putdown_Package` for a two-handed item, `Pickup_One` and `Putdown_One` for another. Not mapped (they stay in the
  GLB): jump, turn, raise, talk, push and knife clips, and the head's pitch.
- `client/player/character/CharacterSet`: the injected character (the GLB's scene and its ragdoll data), null for the
  placeholder capsule. It is a set only when the instantiated scene is the character (one `Skeleton3D` with the bones
  the rig names, one `AnimationPlayer` with every mapped clip), never judged from the GLB's bytes: CI's empty LFS
  stand-in and a missing file give null silently, so no test needs LFS content.
- `client/player/character/CharacterRig`: one avatar's instance of the set, turned to face -Z, on an `AnimationTree`
  in the physics step (base clips cross-faded, a time scale, the carry layer filtered to `Torso` and every bone below
  it, a one-shot), with no root motion (the clips are in place; the body's code moves the body, the collision capsule
  is unchanged) and no physical bones while living. Sockets (`BoneAttachment3D`s on `Wrist.R`, `Hips`, `Chest`) hold
  the hand, belt and carry points, each a point in its bone's own frame measured on the art from close-up shots (#1050):
  the hand's at the right palm (a one-handed item's bottom in the fist), the belt's on the outside of the left hip at
  the waist, the carry's the bottom of a two-handed item held between both palms in front of the chest. Each socket
  stands upright in the rig at the pose its item shows in, never the rest pose (the art's arms-out bind pose, which
  the clips lower): the hand and belt at the idle clip's first frame, the carry with `Carry_Upper`'s first frame on
  the carry layer's bones (the art's carry leans the chest forward, so a socket fitted at idle tipped the package).
  A `shot` close-up: `client/dev/sockets_preview.tscn` (needs the LFS art). A tint multiplies each surface's own
  albedo: the body colour of #551 (§4.7.50) stays on the character.
- The living avatars: `RemotePlayerBody.set_character` puts the rig in the capsule's place; the collision capsule,
  the head (its pitch, the spectate camera's eye), the mouth and the sight point stay the capsule's; the capsule mesh
  and the visor hide, the rig hides by the capsule's rule (knocked down, or watched from its eyes) and takes the body
  colour; `hand_point()`, `belt_point()` and `carry_point()` return its sockets, so the item views follow the bones
  (the tree runs in the physics callback; the skeleton applies its pose in its deferred update, so a socket, and an item on
  it, may show the previous step's bone pose: a one-step lag, accepted). `AvatarViews` (its
  `character` and `mode` set by `Game`) plays each frame `AvatarClips.plan` of the drawn move since its last frame (a
  move faster than `SnapshotBuffer.SNAP_SPEED_MPS` is a placement and counts as none), the pose's yaw and crouch bit
  and the model's hand item. One-shots: `ItemPickedUp` (its `peer`) plays the pick-up, and `ItemPlaced` with the cause
  `put_down` the put-down on the peer the last physics frame drew holding the item (the event names no holder and
  the model has already folded it); each plays once the interpolation delay has passed since the event arrived, when
  the drawn body reaches its tick, on a body still drawn standing; other causes (thrown, swap, death, leave) and the
  own player play none. The own living player has no character on its own screen (no mirror or shadow yet).
- The ragdoll on the skeleton (KE7, §4.7.9): `RagdollView.setup` with the set (and its ragdoll data) gives the
  knocked-down player, the own one too, a fresh rig of its own, `top_level`, whose skeleton gets the art's bodies and
  joints (`client/player/character/ragdoll_builder.gd`, the art's reference builder from prime-game-art 45f73ac,
  typed for the project's warnings; the game builds them at spawn from `slice_m1.ragdoll.json`: 16 bodies, 15 joints,
  70 kg). The view stays as the anchor: frozen, with no mesh, no shape and no layer (never hidden through `visible`,
  which `SightHider` owns; hiding the view hides its rig), following the pelvis. The bones are on the `downed` layer
  with the world mask, never sleep, and are the only ray target: `RagdollView.of_collider` names a hit bone's view,
  which the raise hint uses. The fall starts from the idle pose one physics frame after the view enters the tree, tipped
  over as the capsule is (each body turned about the feet, so the legs do not fold under a body left sitting), with
  the host's velocity. The spring is the capsule's on the pelvis (the data's parentless body): to the point plus the
  pelvis' smallest half extent, the vertical term whole, across the floor faded by how much the pelvis lies (its axis
  up the body, measured at the idle pose), the same velocity change on every bone so it moves the body, not its
  joints; past `SNAP_M` from where the pelvis belongs (the lying centre raised by the standing pelvis height as much
  as it stands, so a standing pose is never snapped into the floor) every bone moves by one offset. The bones take
  the capsule's low `FRICTION`, not the data's, so the floor does not hold a body off the point. `lie_at_rest` lays the rig on its back along the yaw's
  axis with its pelvis on the lying centre; `make_dead` greys the tint and puts every bone on no layer; the handover
  to `BodyViews` keeps it simulating, and `BodyViews.character` (set by `Game` with `AvatarViews.character`) dresses
  a fresh body. The living rig has no physical bones. The export ships the data (`include_filter="*.ragdoll.json"`
  in both presets: a `.json` is no resource).
- `Game` loads the shipped set once, at the first session (`load_character`, on unless a test turns it off: every
  `Game` test does, so a checkout with the LFS art and CI without it run the same capsules).
- Tests: `tests/unit/client/player/avatar_clips_test.gd` (the table, every clip in the import contract with its loop:
  seen failing on the old contract; the velocity guards on AvatarClips and on AvatarViews' clip code: seen failing on
  planted reads), `tests/integration/client/player/character_set_test.gd` and `character_rig_test.gd` on an
  in-memory character (`character_fixture.gd`; the carry filter seen failing with the filter off; the sockets on
  their bones, upright at their fitting poses: the carry socket seen failing fitted at idle; the measured points'
  signs in the art's bone frames, #1050), `character_rig_art_test.gd` on the art (where each socket lands: the hand
  at the right middle knuckle, the belt beyond the left hip joint, the carry in front of the chest between the
  palms: seen failing on a flipped hand point and a mirrored belt point; without the LFS art, as in CI, it checks
  only that the GLB is a pointer),
  `tests/integration/client/world/avatar_views_character_test.gd` (the rig in the capsule's place, hidden, tinted, its
  sockets; the clip per drawn move, a claimed sprint standing still is `Idle`: seen failing on a planted
  `pose.velocity`; a placement's jump; the carry layer; the one-shots per cause after the delay; a knocked-down
  player's ragdoll is the skeleton), `tests/integration/client/player/ragdoll_view_character_test.gd` (the anchor, the
  bones' layers, the fall to rest over the point, the snap, lying at rest, off a ledge, a lifted point: the vertical
  term seen failing with a horizontal-only pull; dead on no layer; `of_collider`; the handover),
  `tests/integration/client/world/body_views_test.gd` (a fresh body's grey skeleton) and
  `tests/integration/client/life/life_raise_ragdoll_network_test.gd` (a hit bone names its peer: seen failing on the
  old collider cast).

#### 4.7.54 The Generator's stations, switches and panel (#801, G6)
The client side of the Generator (the [Generator ADR](decisions/2026-10-10-generator-task.md)'s GD4, GE11, GE14),
from the own `ClientModel`'s StationPlaced, SwitchChanged, ButtonPressed and ZoneProgress folds only; the wire is
unchanged.
- **What E offers.** `StationUse` (pure) offers a placed station whose kind has an Interact rule, whose hand rule
  (HandNotTwoHanded) holds, and whose task type's `TaskClient` owns the kind and offers it (§4.7.59): a Generator's
  generator and switch, neither once the charge is done (the host's StationUsable); a fixed switch is no station (GE14). Cooking's are
  `CookingUse`'s (§4.7.55), the photo task's `PhotoUse`'s (§4.7.56), car repair's `CarRepairUse`'s (§4.7.57); every
  kind with an Interact rule is offered.
- **The target.** `TargetChoice.choose_target` weighs the item against the offered stations: a station counts where
  the camera's ray hits its device (`StationViews.station_of_body` names the scene's `Collision`) or enters its use
  spot's sphere (`STATION_AIM_RADIUS_M` 0.4 m, its middle 0.4 m above the floor point; looks, "not a decision"),
  while the feet stand in its cylinder less the hint's margin (the host's AtStation); the nearest along the ray
  wins, an item on a tie. `ItemInteractions` then casts the host's StationInSight (camera to the lifted floor point,
  world layer) and E sends `Interact(station, item -1)`. The HUD names the station by `ContentNames.station`
  (`station.<id>` once the UI deck has it, else the kind id), never a switch's state.
- **The scenes.** `CircleViews` draws only Delivery's circles (and the fallback cylinder of a kind no type holds).
  `StationViews` (in `ItemWorld`; `Game` hands it the level) binds each placed generator or switch to the level's
  scene of its kind whose `UseSpot` is nearest (within 0.5 m) and drives the level-piece ADR's named parts: a
  switch's `Active/On` or `Active/Off`; a scene no station binds while the Generator is dealt shows `Fixed`; the
  generator's `Bars/Bar1..` lit from the fixed switches' count plus the switches on, `Glow` once all are lit, and
  `Button` moved in 0.02 m for 0.15 s at each press (a press before the bind replays nothing). The driven parts move
  once per scene under a `StationSight` wrapper in `SightHider.GROUP` (sight point 1 m above the use spot), so a
  downed eye behind a wall sees none; `Fixed` stays outside it. All are the level's depth-tested meshes. It searches a
  level for its scenes once (as `CookingViews`, `PhotoViews` and `CarRepairViews`, #1198): a level that holds none is
  not rescanned every frame; a new level is searched again.
- **The sounds.** `SoundChooser` plays SwitchChanged's click at the switch's station and ButtonPressed's at the
  generator's (aimed `PANEL_AIM_M` above), cut at the hearing range and muffled like every world sound, on
  `WorldSounds.station_blip()` placeholders. `StationHums` (in `ItemWorld`) keeps one looping hum
  (`WorldSounds.hum_blip()`) at each generator station that counts and is not full, while `GameFlow.in_round`; a zone
  held never hums (`StationUse.is_generator`); a muffle ray every 0.1 s. The hum stops with the charge or the round.
- **The map bar.** `MapScreen`'s Generator row shows a `ProgressBar` `Charge` (theme variation `MapBar`, a thin
  `ToyBarProgress` in the mapping's legacy section, as `LifeBar`) in place of the counter: `max_value` the
  ZoneProgress's `needed`, `value` `ZoneViews.ticks_at` at the host tick while `GameFlow.in_round`, else the last
  event's ticks (the model's `end_tick` is the clock's, not the round's end); full, and struck, once the station or
  the task is done. It reads only its generator station's events.
- **Tests.** `tests/unit/client/world/station_use_test.gd`, `target_choice_station_test.gd`,
  `generator_sounds_test.gd`, `tests/integration/client/world/item_interactions_station_test.gd`,
  `circle_views_generator_test.gd`, `station_views_test.gd` (the real `levels/stations/` scenes),
  `station_scene_search_test.gd` (the four views' one search),
  `station_hums_test.gd`, `tests/unit/client/ui/content_names_test.gd`, `map_screen_generator_test.gd`,
  `tests/unit/client/app/game_flow_test.gd` (`in_round`).

#### 4.7.55 Cooking's client view (#776, C7)
The client side of Cooking (the [cooking ADR](decisions/2026-10-10-cooking-task.md)'s §8 C7, CD4, CD12, CD14,
CE6, CE15), from the own `ClientModel` and the client's own copy of the mode only; the wire is unchanged. #1101 (the
ADR's amendment of 2026-10-15: a burger is checked when it is served) moved it to the new rule, as this section
reads now.
- **The fold.** `ClientModel` folds `OrderPosted` (a place's `bun`, `patty`, `icon`), `HerbsDealt` (`herb_code`,
  `herb_beds`), `IngredientPlaced` and `GrillLoaded`: the host sends no `ItemPlaced` for a put on a plate or the
  grill, so the fold takes the item out of the hand and lays it at the station (`Item.on_station`, a plated one
  always `locked`, `ClientModel.plated_on(station)` lists them; the grill's `grill_item`, `fried_tick`,
  `burnt_tick`). `BurgerPlated` gives the burger item its `parts` (bun, patty, herb kinds) and its `place`;
  `BurgerServed` right marks that place `done` (nothing else: wrong changes no state). A pick-up, a put-down, a
  throw or a vanish clears them, the patty's `ItemPickedUp` empties the grill. Nothing records who put what (the
  ADR's §3), and nothing on the client knows whether a plate is right before the serve.
- **What E offers.** `CookingUse` (pure, behind `StationUse.usable`): never the herb board (a `display` kind); the
  order board only while the hand holds a burger whose `place` is not done; a place not done when its plate is full
  (the take), or while the hand holds one of its type's buns, fried patties or herbs whose slot is free; the grill
  empty with a raw patty in
  the hand, occupied always (the take-off); a bed always. `TargetChoice` skips a locked item, aims at an
  on-station item only where it is drawn (`aim_of`, never its floor point) and lets an offered station win over an
  unlocked item lying on it (none lies on a plate since #1101; the clause stays generic). A box (an item kind with an Interact rule among its `target_actions`): `ItemInteractions`
  sends `Interact(-1, box)` when E is released within `HOLD_SECONDS` 0.4 s and `PickUp(box)` once when held that
  long; the box is captured at the press, and leaving it, the Esc menu or the own life leaving ALIVE drops the press.
  The device ray names a bed by its shape: `ItemWorld.station_of_hit(body, shape)` asks `StationViews`, then
  `CookingViews` (`HerbBeds/Collision`'s `ShapeN` is `BedN`).
- **The scenes.** `CookingViews` (in `ItemWorld`) binds each placed station to the scene whose use spot (the
  `spawn_<tag>` marker) is nearest within 0.5 m, its scene the marker's parent (so five beds under one
  `herb_beds.tscn` bind to five `Plant`s), and drives, under `StationViews.StationSight` wrappers in
  `SightHider.GROUP`: the order board's `Rows/RowN` (the place's number, bun and patty looks, herb icon), the herb
  board's `Pairs/PairN` (icon and herb), each bed's `Plant` (its herb's look), a place's `Plate` and `Number`
  (its row on the board; an unused place stays a bare counter) and the grill's ring: 24 segments under its `Ring`,
  filling yellow to fried and red to burnt from `GrillLoaded`'s ticks at the estimated host tick (CD14 (i)).
  `ItemViews` draws an on-station item at `CookingViews.point_of` (every plated one stacked on the plate by its
  slot, the patty on the grate), with an inverted-hull outline on a plate (`CookingLooks.outline`: `grow`,
  `CULL_FRONT`, unshaded; one neutral filled-slot colour, never right or wrong, #1101); its view stays in
  `SightHider.GROUP`. Every part is
  depth-tested, none drawn over the level (`client/dev/cooking_wall_preview.tscn`).
- **The looks.** `CookingLooks` builds the 22 item kinds' placeholder looks (the burger since #1101: its three
  parts stacked as on the plate, each on the one below so the bun never hides the patty, from `Item.parts`; `ItemViews` rebuilds a view when its parts arrive, the own hand
  too) and the five icons (sun, moon, star, drop, heart, the ADR's §5.1) in code, keyed on C6's kind ids; `ItemView`
  asks it first, so the hand, the loose view and the pick sphere share one size. A kind with no look keeps the labelled box (`ContentNames`).
- **The sounds.** `SoundChooser` (given the mode): `IngredientPlaced`'s put click at the place (no chime or buzz,
  which would tell right or wrong, #1101); `BurgerPlated`'s chime at the place; `BurgerServed`'s task success
  (right) or error (wrong) at the order board (§4.7.60); `GrillLoaded`'s put click at the grill; `ItemChanged`'s
  ding to a fried patty, the task's error to the burnt one; each aimed `COUNTER_AIM_M` above, cut and muffled like
  every world sound; the chime and the ding on `WorldSounds.cooking_blip()` placeholders. `StationHums` sizzles the grill (`sizzle_blip()`) while its ring
  fries (CD14 (a); it stops at fried, where the ding plays), in the round.
- **Tests.** `tests/unit/client/net/client_model_cooking_test.gd`, `tests/unit/client/world/cooking_use_test.gd`,
  `target_choice_cooking_test.gd`, `cooking_looks_test.gd`, `cooking_sounds_test.gd`,
  `tests/integration/client/world/item_interactions_cooking_test.gd`, `cooking_views_test.gd` (the real
  `levels/stations/` scenes), `grill_sizzle_test.gd`; previews `client/dev/cooking_preview.tscn` and
  `cooking_wall_preview.tscn`.

#### 4.7.56 The viewfinder and the camera's state (#786, P7)
The client side of the photo camera (the [photo ADR](decisions/2026-10-10-photo-task.md)'s §2, §3.1, §9 P7, PD17
(a)), from the own `ClientModel` and the client's own copy of the mode only; the wire is unchanged.
- **The fold.** `ClientModel` folds `FilmLoaded` (the host sends no `ItemPlaced` for the load: the film leaves the
  loader's hand or belt and lies at the camera, `on_station`, unlocked) and `ShotTaken` (its film and count only):
  `Station.film` and `Station.shots` on the camera, and `film_shots` (film id to shots, kept wherever the film goes,
  dropped at its `ItemVanished`). The film's `ItemPickedUp`, `ItemPlaced` or `ItemVanished` empties the camera.
  Nothing records who loaded or shot (PD13); P8 draws its pictures and counter from this state (§4.7.58).
- **What E offers.** `PhotoUse` (pure, behind `StationUse.usable`): never the photo spot (a `display` kind, CE6);
  the camera holding a film always, a two-handed item in the hand too (the take-out is a take, which neither a done
  task nor a two-handed item refuses, the photo ADR's §2.4), an empty one while the
  task is not done and the own hand or belt carries a fresh film; the box always; the printer while a film with a
  shot is carried; the board while a photo is carried; the hand rule stays `StationUse`'s, and for the loaded camera
  only the viewfinder asks it (`StationUse.hand_allows_at`: the shot is refused `two_handed`). The loaded film is
  never an item target (it lies on the camera, where `TargetChoice.aim_at` names no point). E at an empty camera sends
  `Interact(camera, item -1)`, the load; at a loaded camera cooking's gesture (§4.7.55, `HOLD_SECONDS`): a tap
  opens the viewfinder (nothing sent), a hold sends `PickUp` of the film once, within PickUp's hint reach of it.
- **The viewfinder.** `PhotoViewfinder` (in `ItemWorld`) opens only while the own player is alive with no
  two-handed item in the hand, the camera holds a film and frames a placed photo spot, the feet stand in its cylinder less the hint's margin
  (`TargetChoice.stands_at`, the host's AtStation) and, cast in each physics step (priority 7, after
  `ItemInteractions`), the line from the own eye to the camera's lifted floor point is clear (StationInSight): no
  view from afar or through a window shows more than standing there (the M4 render checklist, items 3 and 5). It
  closes when any of those stops holding, on `Damaged`, on E, on Esc (`Game`, after the overlays and before the
  Esc menu) and when the keys stop listening. While up, its `Lens` (a `Camera3D` at `PhotoUse.frame_of`'s pose,
  `PhotoFrame.between` as the host builds it; `keep_aspect` `KEEP_HEIGHT`, `near` `PhotoFrame.NEAR_M`) is current
  (`LifeView.view_camera`), its fov `fov_for(fov_deg, aspect, screen)`: the frame's own on a screen at least as
  wide as the photo, on a narrower one widened until the frame's width fits; four black bars (a `CanvasLayer` at
  layer 0, under `GameUi`'s) mask the screen outside `photo_rect`, and a digits-only label shows the frames left in
  the photo's corner (its size and inset are looks, "not a decision"). `PlayerController.held` holds the movement
  keys and the look (a click still captures the mouse), the first-person hand is hidden, the HUD's crosshair too
  (`HudText.Local.viewing`). The primary button sends the shot, `Interact(camera, item -1)`, while frames are left and
  the mouse is captured (the click that captures it takes none; `ItemInteractions.mouse_captured`, the game's
  `MousePointer`, #1114); no other item key acts.
- **Tests.** `tests/unit/client/net/client_model_photo_test.gd` (fixture `tests/fixtures/client/
  fixture_photo_client.gd`), `tests/unit/client/world/photo_use_test.gd`, `photo_viewfinder_test.gd` (the frame's
  corners project onto the mask's corners on wide, square and narrow screens), `target_choice_photo_test.gd`,
  `tests/unit/client/ui/game_ui_viewfinder_test.gd`, `tests/integration/client/world/item_interactions_photo_test.gd`
  (the load, the tap, the hold, the shot and every exit; none from outside the cylinder or through a wall),
  `item_interactions_shot_network_test.gd` (#1114: the left button through `Input.parse_input_event` in the view,
  against a `HostSession` on `FixtureWirePhoto`: the host's `ShotTaken` and the counter one down; the capturing click
  takes none), `tests/integration/client/app/pointer_flow_test.gd` (the item keys read `Game`'s pointer),
  `tests/integration/client/player/player_controller_held_test.gd`,
  `tests/integration/client/life/life_view_camera_test.gd`.

#### 4.7.57 Car repair's view (#811, R7)
The client side of the car repair (the [car repair ADR](decisions/2026-10-10-car-repair-task.md)'s §8 R7, RE8,
RE16, RD1, RD3, RD14), from the own `ClientModel` and the client's own copy of the mode only; the wire is unchanged.
- **The fold.** `ClientModel.Station.rise_tick` keeps the last hold's start through its stop (how high the car got
  before it dropped); a fitted part (`Item.fitted`, PartFitted) rests nowhere (`rests()` false), so `ItemViews` draws
  it nowhere and no crosshair names it (RE12).
- **The car's body.** The living player's `collision_mask` holds layer 4, `movers` (`PhysicsLayers.MOVERS`, §7),
  the downed's does not. `CarRepairViews` (in `ItemWorld`) moves the car scene's `Lift` (an `AnimatableBody3D`,
  `sync_to_physics`) in its `_physics_process`: its rest height plus `CarRepairUse.lift_fraction` of the rise that puts
  its lowest box `clearance_m` above the use spot's floor (read from the scene once, so the data sets the height the
  crouch must pass, RE8). Up over the client's copy of `rise_seconds` from `LiftChanged`'s tick at the estimated host
  tick; down over `DROP_SECONDS` 0.25 s from the stop (a look: the host's world has no car). The car is not hidden by
  `SightHider` (its height is public).
- **What E offers.** `CarRepairUse` (pure, behind `StationUse.usable`): the panel while the task is not done and the
  car not up (`up`); the car fully up at the estimated host tick (none: never), nobody fitting, the hand holding the
  part `PartNeeded` names; a bin always; never the picture (a display kind). E sends `Interact`; on a kind whose
  Interact rule holds the station (`StationUse.holds`: a `HoldStation` effect, the panel and the car) `ItemInteractions`
  keeps the hold and sends `StopRaise` once on E released or the Esc menu, wherever the crosshair is; the own life
  leaving ALIVE drops it silently (the host stops the hold itself). The device ray's mask holds `movers`: the `Lift`
  and the scenes' `Collision` name their stations, a shelf hit names the bound bin nearest across the floor
  (`station_near_hit`, turned shelves included).
- **The scenes.** Each placed station binds to the scene whose use spot (`spawn_<tag>`) is nearest within 0.5 m (the
  shelf's `BinN`s, the car, the panel, the picture). Under `StationViews.StationSight` wrappers in `SightHider.GROUP`:
  the panel's `Light`, shown from `up` alone, and the wall's `Picture` quad, wearing the bound bin plate's own material
  for the part `PartNeeded` names (RD3: the same picture; a placeholder colour for an unbound bin) and hidden when none
  is needed. Nothing at the panel (its lamp, its hint, the HUD of a player there) reads `FitChanged` or `PartFitted`
  (RE16).
- **The fitter.** Drawn crouched by its own crouch (RD1 (b): snapshots' `pose.crouched`, no override). The own fitter's
  progress from `FitChanged`'s tick fills the raise bar (`ItemWorld.fit_shown`, `HudText.Local.raising`); a player
  that fits nothing sees none.
- **The sounds.** `SoundChooser`: `LIFT_CRASH` at the car on `LiftChanged(up = false)` in the round only (the phase's
  end lowers it without a kill; the host sends that stop's `LiftChanged` before its `PhaseChanged`, so `WorldSounds`
  holds a crash to its next physics frame and plays it only if the round still runs), `PartFitted`'s task success
  at the car (§4.7.60), each `CAR_AIM_M` above, cut at 12 m and muffled; `FitChanged` is silent (RD14 (a)). `StationHums` runs the lift's motor
  at the car while it rises (a hum placeholder at a lower pitch). Placeholders, not decisions.
- **Tests.** `tests/unit/client/world/car_repair_use_test.gd`, `tests/unit/client/physics_layers_test.gd`,
  `tests/unit/client/net/client_model_test.gd`, `tests/integration/client/world/car_repair_views_test.gd` (the real
  `levels/stations/` scenes), `item_interactions_car_repair_test.gd`, `car_repair_sounds_test.gd`,
  `car_repair_panel_blind_test.gd` (planted: the lamp reading the fitter, failed, reverted), `car_lift_walk_test.gd`
  (RE8 on NetPair with the real car: a jump at the lowered car and a standing walk at the raised one stay out, a
  crouched walk goes under and out, no Correction; the drop on a crouched player at the end prints its push on an
  `RE8 edge:` line; planted: `movers` off the living mask, failed, reverted),
  `tests/integration/client/world/item_world_car_repair_test.gd` (the own fit in the raise bar, and a raise),
  `tests/integration/client/player/player_controller_downed_test.gd`; fixture
  `tests/fixtures/client/fixture_car_repair_client.gd`. `shot` previews: `client/dev/car_repair_preview.tscn` (fully
  up, the lamp lit, a picture per part beside the shelf), `car_repair_half_preview.tscn`,
  `car_repair_lowered_preview.tscn` and `car_repair_crouch_preview.tscn` (the crouched eye under the raised car), on a
  CarRepair built in `car_repair_preview.gd` (it does not read the shipped `content/tasks/car_repair.tres`, R6, #810).

#### 4.7.58 The pictures, the camera's counter and the photo's look (#787, P8)
The client side of the photo's pictures (the [photo ADR](decisions/2026-10-10-photo-task.md)'s §3.3, PE15, §9 P8),
from the own `ClientModel`, the snapshot-free `ShotTaken` record and the client's own copy of the mode; the wire is
unchanged and nothing hidden is drawn (each picture is rendered locally from what this client was sent).
- **The fold.** `ClientModel` keeps each `ShotTaken`'s record as a `Shot` (`shots`, a shot id seen again is a new
  `Shot`), the shots each film lists (`film_pictures`), `PhotoPrinted`'s `Item.shot` and `PhotoHung`'s
  `Station.hung` slots (the host sends no `ItemPlaced` for a hang: the photo lies on the board, locked when
  counted). `hang_slot()` alone picks a slot: the lowest free one (a taken-down uncounted photo's), else a new one
  after the last. Shots no film lists and no photo shows are pruned as the host's `PhotoTask._prune`.
- **The layers.** `PhotoLayers`: `LIVE_AVATAR` (visual layer 19) for what moves live (the remote bodies, a downed
  player's live ragdoll, the first-person hands, a carried item's view), `PHOTO` (layer 20) for the pictures'
  puppets; every live camera's `cull_mask` is `LIVE_VIEW` (all but `PHOTO`), a picture's camera `PHOTO_VIEW` (all
  but `LIVE_AVATAR`). Ground items and dead bodies (`BodyViews` puts the handed-over ragdoll back on `GROUND`) stay
  in both, as they move only by events.
- **The looks and the views.** `PhotoLooks` builds the film's and the photo's look (a card whose +Y face holds the
  picture slot); `PhotoViews` binds the camera, printer and board scenes of `levels/stations/` by their kinds'
  spawn tags (`StationViews`' pattern) and gives `ItemWorld.drawn_point` / `aim_point` (after `CookingViews`): the
  loaded film at the camera's `FilmSlot` (drawn, still never an item target: `aim_point` names no point, #1104
  option (a)), a hung photo upright on its board `SlotN` (past the last slot stacked 1 cm out), the photos lying
  on the tray (a photo kind within 5 cm of the `Tray` marker, where the print puts it; any other item is drawn
  where it lies) spread three to a row by item id (each rank 1 mm higher, so overlapping cards never z-fight); the camera's
  `FramesLeft` label shows the digits of the frames left while it holds a film, hidden otherwise. Spacings are
  looks, "not a decision".
- **The pictures.** `PhotoPictures` (in `ItemWorld`, after `PhotoFlashes`) queues each folded `ShotTaken` and starts
  one render a frame: a `SubViewport` (`UPDATE_ONCE`, 384 px high and as wide as the type's aspect makes it,
  sharing the live `World3D`), its `Camera3D` at `PhotoUse.frame_of` (fov, `KEEP_HEIGHT`, `PhotoFrame.NEAR_M`)
  seeing `PHOTO_VIEW`, and a puppet per record row: a `RemotePlayerBody` with collision 0 and no shadow on `PHOTO`,
  the live avatars' rules and character, crouched as recorded, turned through `SnapshotBuffer.look_angles` (a zero
  or vertical facing is honest play), a downed row laid flat, its hand, carried and belt items with it. A puppet
  with the character is posed at once (`CharacterRig.pose_now`: the tree evaluated, the skeleton and sockets
  updated), since it is drawn before any physics step would run its tree (else the art's arms-out rest). After
  `drawn` (`RenderingServer.frame_post_draw`) the image is read back (`reader`), kept as JPEG bytes (quality 0.8),
  the viewport and puppets freed, then the flash released (`PhotoFlashes.release`: the picture is lit by it). A
  queued or in-hand render whose shot the model no longer holds is dropped and its flash released. A picture lives
  while the model holds the same `Shot`; its texture decodes on `texture_of` and goes after 30 frames nobody asked.
  Headless (`enabled` false by `DisplayServer`) nothing renders and the flash ends at its 1 s fallback.
- **Showing them.** `ItemViews` sets a photo view's picture while its look is shown within `PICTURE_RANGE_M` 12 m of
  the drawing camera, else none (so the material holds no texture and `PhotoPictures` frees it); the own hand and
  the spectate hand (`LifeView`) show the held photo's, keyed on the item id. The primary button with a photo in the
  own hand holds it up close (`FirstPersonHand.set_close`: in front of the eye, facing it, 2.2 times larger) or
  back, sending nothing (a photo has no Use rule); a hand change, a knockdown or death, the viewfinder and the keys
  no longer listening end it. Sizes, range and frames are placeholders, "not a decision".
- **Memory** (`tools\run.cmd shot client/dev/photo_memory_preview.tscn --frames 450`, the greybox puppets, two
  to a shot, measured 2026-10-15 on the engineer's PC, Vulkan Forward+, 1280x720): 20 pictures kept are 172 KB
  of JPEG; PE15's worst case of 224 (32 films x 5 frames plus 64 photos) 1.9 MB, about 8.6 KB each, well under
  PE15's 10 MB. Static memory grows about 16 MB with the first renders and stays there (124.5 to 140.8 MB from 20
  to 224 pictures, not growing with the count). Texture memory: 20.4 MB before any render, 61.5 MB once 224 are
  kept and no render is in hand (the renderer keeps about 41 MB from the first renders, the same at 20 and 224),
  109.5 MB with 64 photos of distinct shots drawn in view (48 MB, 0.75 MB a decoded 512x384 texture): the 12 m
  range and the 30 frames bound how many are decoded at once. 224 renders took 6.9 s at one a frame.
- **Previews.** `client/dev/photo_preview.tscn` (the room: the board with two hung photos, the camera, the
  printer), `photo_counter_preview.tscn`, `photo_tray_preview.tscn` (close on the counter, on the tray),
  `photo_picture_preview.tscn` and `photo_character_preview.tscn` (a picture itself, greybox and with the art).
- **Tests.** `tests/unit/client/net/client_model_photo_pictures_test.gd`,
  `tests/unit/client/world/photo_layers_test.gd`, `photo_looks_test.gd`,
  `tests/integration/client/world/photo_isolation_test.gd` (every live camera drops `PHOTO`, the live parts on
  `LIVE_AVATAR`, a dead body back on `GROUND`), `photo_views_test.gd` (the real scenes),
  `photo_pictures_test.gd` (with a test `drawn` signal and `reader`: the frame, the puppets, read then release, one
  render a frame, lazy textures, dropped and recycled shots, zero and vertical facings, a posed character, no live
  view's `visible` touched, headless), `character_rig_test.gd` (`pose_now`),
  `photo_close_up_test.gd`, `tests/integration/client/player/first_person_hand_test.gd`,
  `tests/integration/client/life/spectate_cycle_test.gd` (the spectate hand's picture).

#### 4.7.59 The task types' clients (#1260)
What the client does for each core task type class sits behind one table, client-only: `core/` and the content
`.tres` name no client, and nothing here travels on the wire.
- **The client.** `TaskClient` (`client/world/tasks/`, pure, a `RefCounted`) answers for one core `TaskType` class:
  `owns(type, kind)` (E is this client's to answer for that station kind), `usable(model, type, id)` (E offers the
  placed station now), `draws_circle(kind)` (`CircleViews` draws it as a circle) and `make_view()` (the class's view
  under `ItemWorld`, named as its child, or none). The base answers no, draws no circle and makes no view. One
  subclass per class: `DeliveryClient` (the circles, `CircleViews`), `DeliveryByMeaningClient` (its drop-offs as
  circles), `ZoneTaskClient` (`ZoneViews`), `GeneratorClient` (`StationViews`; the generator and the switches until
  the charge is done), `CookingClient` (`CookingViews`, `CookingUse`), `CarRepairClient` (`CarRepairViews`,
  `CarRepairUse`), `PhotoTaskClient` (`PhotoViews`, `PhotoUse`). Each but `DeliveryClient` also has the static
  `types_of(mode)`, the mode's types of its class in the mode's order: the one place outside `core/` an `is` or `as`
  of a task type class stands; the `*Use` helpers (`CookingUse.types_of`, `StationUse.generators_of`, `PhotoUse.type_of`, ...) and the
  views call it.
- **The table.** `TaskClients` (`task_clients.gd`) holds the one dictionary from the core script to its
  `TaskClient` script; `of(type)` takes the type's class row, else its nearest base's along `get_base_script()`
  (a subclass falls back to its base), else null. A client holds no state: one is made per script, on first use.
- **The views.** `ItemWorld` adds `TaskClients.make_views()`: a view of every row's client that makes one, not
  only the mode's types', as before; its children keep their names and tree order (`ItemWorld._ORDER`). It gives
  each the model and the mode and, where the view has them, the host tick and the level, and at a reset calls its
  `clear()` if it has one and forgets the model and the host tick. The lookups by a hit or an item
  (`station_of_hit`, `drawn_point`, `aim_point`, the car's near hit) stay per type, through the views it takes from
  the table by class.
- **What E offers.** `StationUse.usable` checks the kind's Interact rule, the loaded camera's take-out (a take,
  §4.7.56) and the hand rule, then asks the first of the mode's types whose client owns the station's kind; a kind
  no client owns is never offered (a Delivery circle, a zone). Content today shares no station kind between two
  types of one mode, so the mode's order gives the same answer as the per-type order before.
- **A missing row.** `ItemWorld.setup` calls `TaskClients.report_missing(mode)`: a `push_error` per mode type with
  no client, once per class for the process, so a type is never skipped silently. The hums, the sound choice, the
  camera and box keys and the item looks (`station_hums.gd`, `sound_chooser.gd`, `item_interactions.gd`,
  `item_view.gd`, `item_views.gd`) stay per-type code outside the table, through the `*Use` helpers.
- **Tests.** `tests/unit/client/world/tasks/task_clients_test.gd` (every global class outside the tests whose base
  chain reaches `TaskType`, from `ProjectSettings.get_global_class_list()`, has a client; so does every task type of
  `content/modes/`; the base fallback; a class with no row reported once), `task_clients_source_test.gd` (no
  `is`/`as` of such a class in `client/` outside `client/world/tasks/`, comments and strings stripped, the five
  files above named exceptions), `tests/integration/client/world/item_world_children_test.gd` (`ItemWorld`'s
  children: names, classes, order); each `*_use_test.gd` unchanged.

#### 4.7.60 Every task's success and error (#1341)
One success and one error sound for every task, the engineer's picks on #1333: U2 (a kalimba's three rising notes)
and P1 (the same kalimba falling a minor third), the project's own synthesis in `assets/audio/prime_task_feedback/`
(`docs/credits/prime_task_feedback.md`).
- **The ids.** `SfxSet.TASK_SUCCESS` (`task_success.wav`) and `SfxSet.TASK_ERROR` (`task_error.wav`), one file each,
  through the same randomizer as every id (§4.7.43's pitch and volume placeholders). A ship station that lands later
  plays them through the same two ids.
- **When.** `SoundChooser` picks success whenever a task or one of its subtasks is done, error on a miss by the
  task's own rules, each at the station of the event that tells it, the burnt patty's where it lies (every one
  reaches everyone):

  | Task type | Success (done) | Error (a miss) |
  |---|---|---|
  | Delivery | `PackageDelivered`, at the package's circle (each package a subtask) | none |
  | DeliveryByMeaning | `PackageDelivered`, at the item's drop-off (each item a subtask) | none |
  | ZoneTask | a done `ZoneProgress` (`ticks` at `needed` > 0), at the zone | none |
  | Generator | a done `ZoneProgress` of the generator: the charge full (every subtask at once), at the generator | none |
  | Cooking | `BurgerServed` right, at the order board | `BurgerServed` wrong (a wrong ingredient shows only at the serve, #1101), at the order board; a patty turned burnt (`ItemChanged` to the burnt kind), where it lies |
  | CarRepair | `PartFitted`, at the car | none |
  | PhotoTask | `PhotoHung` counted, at the board | `PhotoHung` not counted (a photo without a person, PD6), at the board (the engineer's word on #1344) |

  A delivery and a charge can be done at the deal (a package that spawned inside its circle, a generator dealt with
  no switch, GE9): those two play only in the play phase (`SoundChooser.in_play`), so nobody's success sounds then.
  Step sounds that mean neither stay: `BurgerPlated`'s chime, the fried patty's ding, the put clicks, the
  Generator's clicks, the sizzle and hums, the shutter and the print, the lift's crash. The placeholders that meant
  done or a miss gave way: Cooking's served burger and buzz, its burnt hiss, the car repair's part fitted, the
  photo's hang.
- **How.** `WorldSounds` plays them as every event's sound: a one-shot `AudioStreamPlayer3D` at the station on the
  Effects bus, cut at `HEARING_RANGE_M` (and its `max_distance`), muffled behind the level. So a player near the
  station hears another's success or miss, the same whoever caused it; no event names a player.
- **Tests.** `tests/unit/client/world/task_feedback_sounds_test.gd` (a done subtask and a miss each pick their id;
  the delivery, the zone and the charge, a filling zone silent, the deal silent; `WorldSounds` on SfxSet's files on
  Effects), `cooking_sounds_test.gd`, `photo_sounds_test.gd`, `tests/integration/client/world/car_repair_sounds_test.gd`,
  `tests/unit/client/audio/sfx_set_test.gd` (the two files, every pack credited).

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
- **The menu** (`MainMenu`, the Toy menu of #493, §4.7.38): Host (a room with a code, `CodeRoom` over
  `WebRtcTransport`), Join (the code panel) and Join by address (the Direct panel: the address with an optional port,
  Join and Host, ENet as before M6). A host serves one backend, so a code host takes no Direct joiner and a Direct
  host has no code. A failed join shows its failure (#494), then the menu with the panel and what was typed kept.
- **The connecting screen** names the target the player typed and the step (`JoinProgress`): finding the game (a
  code, before `found`), connecting, joined (connected, before `Welcome`). **The version check** is the joiner's
  `WebRtcTransport`'s (`expect_protocol`, `expect_content`, which `JoinTarget.transport` sets): a `found` naming
  another protocol or content hash fails the join as `wrong_version` or `wrong_content` before any offer is applied,
  and the menu names the host's and the own ("another build" for the content); advisory only, `Hello` still decides.
- **Failures in words** (`EndReasons`): `no_room`, `joins_closed`, `wrong_version`, `wrong_content` ("another
  build"), `service_unreachable` (use Direct) and `host_unreachable`, which also covers a full host (it answers a
  joiner nothing, so the join times out after 15 s) and names the playit.gg fallback under Direct.
- **The lobby's code** (`LobbyHud`'s code row, the Esc menu's Lobby tab with Copy): the host's from `CodeRoom` (the
  transport's `room_code()`), a code joiner's the code it typed, a Direct game's none. When the host's service goes
  away, `room_code()` turns empty and the tab's line says the code is gone (no reclaim); the HUD's keycap reads "…"
  while the host waits for its room and "—" once it is gone (#495, §4.7.47). No wire change.
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
  living or downed player's avatar (position, velocity, facing, the flags `downed`, `invulnerable`, `crouched` and `sneaking`,
  the last two only for a living player and never together (#990, §9.5.24), `crouched` in any phase since #991, §7.1.17, #790; hand and belt items) reaches every player of
  the match, the dead included, whose spectate camera is built from it (§4.7); a dead player has no avatar, so no
  snapshot holds one (M4-2, #138); bodies and items reach everyone. Nobody gets their own avatar while it lives: it moves client-side, and `Correction` settles disagreement. Private numbers are never avatar
  fields; they travel in `SelfStatus`. #728's design (§7.1.18) adds one exception: the own avatar while
  knocked down, on every map (the greybox included, where the body stays at rest), decided from the life state alone,
  not from whether the host moves the body (KE5). The photo task's `ShotTaken` (#781, §9.5.22) is another: its record
  holds a row for each living or downed player near the camera at the shot, the recipient's own pose included; it
  tells the recipient nothing new (its own pose is what its client sent, and every other row is what its snapshots
  show anyway, the dead having none), so it goes to everyone alike (the photo ADR §3.3).
- **`core/` says who is entitled; `server/` delivers.** The rule is game logic, like voice routing (§6). `server/`
  asks `core/` for each event's recipients and builds one message per recipient, *everyone* events included: it sends
  them to each player in turn, never to the transport's broadcast target, which would also reach a peer that is not
  a player (no accepted `Hello` yet, or a straggler about to be disconnected). It never adds a recipient or a field
  (`core/CLAUDE.md` and `server/CLAUDE.md` say so since 2a).
- **Never leaves the host:** seeds and RNG state; another player's role (the end screen shows none either), health,
  stamina and damage; a player's return key (#638: it reaches the host alone, in `Hello`, and lives only in
  `MatchState.numbers`, never in a `PlayerState` or an event; the command log on the host's disk keeps it as sent,
  P10) and its secret, which never leaves the client (§3.5, "A return"); whom a dead player watches (it never leaves the dead player's client, §4.7). Tasks are shared (#79): what a client learns of them is
  all public (`StationPlaced`, `ItemSpawned` with a package's circle and colour, `PackageDelivered`, `TaskState`, `TaskProgress`,
  and the zone task's `ZoneProgress`, which names no player and whose counting reads no role, #647; `ItemVanished`, an item left lying too long, #779; `ItemChanged`, an item that became another kind, #771; the Generator's
  `SwitchChanged`, `ButtonPressed` and charge `ZoneProgress`, which name no player, and whose uses read no role, #797;
  Cooking's `OrderPosted` and `HerbsDealt`, which name no player, #772; an order carries its herb's icon, the code
  says which herb an icon means); the car repair's `LiftChanged` and `PartNeeded`, which name no player, and whose hold reads no role, #807;
  the photo task's `FilmLoaded` and `ShotTaken`, which name no shooter and never say whether a person counted, #781;
  Cooking's `GrillLoaded` and `IngredientPlaced`, which name no player, and whose uses read no role, #773;
  the car repair's `FitChanged`, which names the fitter (RD15 (a): what every client sees on the crouched avatar anyway), and
  `PartFitted`, which names no player, #808; the photo task's `PhotoPrinted` and `PhotoHung`, which name no player, and whose print and hang read no role, #782); no
  task has an owner, and a subtask's detail stays in `subtask_done` (internal to the task type, not secret). No event
  names a killer; a player who watches the swings and positions (both public by the rules) may still work it out.
- **Widening** follows from evaluating audiences at emission. A death, a respawn and a revive widen
  nothing, and a knockdown widens only its own player's snapshot, by its avatar (KE5, #847): the downed are public, `Respawned` is as public as the body it removes and the avatar that appears again,
  a raise and a revive are as public as the two avatars (M4-4), a dead player
  gets the same public snapshots as everyone (minus the dead), and the dead learn no roles and
  no event that a living peer present then does not get (the leak test checks it, §4.6.4; M4-2 tests the snapshots in
  `tests/unit/life/life_rules_test.gd`). End widens nothing: `MatchEnded` names the winning
  side and why (#548): the id of the win condition that ended the round and the round's play time. Both are public:
  every player sees what ends a round (the tasks done, the clock, who is left), and the time follows from the public
  `RoundStarted` and the end, so a condition whose holding were a secret must not be a win condition. Each player
  knows from its own role whether it won. A later mode that reveals roles would add an event with
  its own audience. A joiner's `Welcome` holds public facts only.
- **Knowledge never shrinks.** A peer keeps what it was sent. What a dead player saw while spectating, all of it
  public, is fair game after the respawn (vision revision 1, V1): nothing is narrowed then.
- **Projection.** `Match` records the recipients of every event it emits (with `Match.recording` or `keep_history`
  on; with both off, `emitted()` and `view_of(peer).events` hold only the events `take_outbox` has not handed out
  yet, so never read `view_of` on a host's match), and per tick each peer's snapshot and the
  voice routing (who hears whom). `Match.view_of(peer)` returns that peer's events in order, its snapshot for every
  tick, and the speakers it may hear per tick: everything an honest client of that peer can know. The per-tick
  snapshots and speakers are recorded only with `Match.keep_history` on (off by default: about 1 GiB for 10 players
  over 10 minutes); the tests and the leak test turn it on, a real host does not. `snapshot_for(peer)`, what `server/`
  sends each tick (its avatars alone; the recorded snapshots add the items and the bodies, #1198), is empty for anyone but a present player, and in a phase that sends no snapshots
  (`tests/unit/match/view_of_test.gd`). The M3 leak test
  compares what each bot actually decoded (voice frames included) with `view_of` of its peer; anything received that
  `view_of` does not hold is a leak (§4.6.4: the events exactly, the snapshots' avatars and the voice frames as
  subsets).
- **Invariants that do not trust the declarations.** A wrong audience (say `Teammates` declared *everyone*) would
  pass the comparison above, because both sides read the same declaration. So unit tests and the leak test also
  assert facts written independently of them: for the whole session, a crew member knows one role, its own, and a
  dissident knows the dissidents' roles only; no snapshot holds a dead player's avatar; a snapshot holds its viewer's own avatar exactly when the host's state has the viewer knocked down, read from the life state, never from `Snapshots.for_peer` (KE5, #847: `ScenarioInvariants` per tick, `LeakCheck` per decoded snapshot); the voice invariant (§6.3): no
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
| Pregame | nobody: each player is reading its own role (#213, §3.6) |
| Round | the living hear the living within the voice radius; a downed player hears the living within it, measured from where it lies; nobody hears the downed or the dead, and the dead hear nobody |
| End | nobody: the game is frozen |

A player who left hears nobody and is heard by nobody.

### 6.3 The voice invariant (vision revision 1; M4-1, #137)
Nobody hears a downed or dead player, under
any voice rule, and a dead player hears nobody. `VoiceRule.speakers_of` drops every speaker who is not living
and gives a dead listener nobody before it asks the phase's rule, so no mode's data can route their voice; it
replaces 2i's "the living never hear a ghost". Tests: `tests/unit/content/voice_rule_test.gd`, under
`FixtureEveryoneHears`, a rule that lets everyone hear everyone; the leak test's checks (§5). The knockdown reworked
(#728, §7.1.18) needs nothing here: "cannot talk" is this invariant.

### 6.4 `core/voice/` (2i, #65)
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

#### 6.5.1 The codec boundary, the gate and the jitter buffer (E34, E37, E38, E39; M5-2, #216)
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
A known limit, accepted by the engineer (#1239): loss concealment covers only the host-to-listener leg. The seq that
`VoiceJitter` orders by is the relay's renumbering (§4.5.5), which has no gaps in what the relay forwarded, so a
`VoiceUp` lost on the speaker-to-host leg (unsequenced, about one in a hundred over Wi-Fi or the internet), or one
of the older frames above 5 per poll that the relay drops after a speaker's hitch, leaves no gap for it to see:
`lost` and `concealed` stay 0, the missing 20 ms is spliced out with no concealment and the listener hears a click;
two frames reordered across two polls are renumbered in relay order and play swapped. The relay does not carry the
speaker's gaps into a stream, since doing so without showing a listener what the speaker sent while it was out of
range needs a rule of its own; revisit if players report clicks. The jitter tests' loss and reordering model only
the host-to-listener leg.
Tests (no addon, no microphone): `tests/unit/voice/voice_codec_test.gd`, `voice_gate_test.gd`,
`voice_jitter_test.gd` and `voice_jitter_timing_test.gd` (through `voice_jitter_sim.gd`, a listener polling at
60 fps with a playback model), with the fake codec in `tests/fixtures/voice/` (8 kHz µ-law, 160 B per 20 ms,
played through an `AudioStreamGenerator`); `voice_addon_names_test.gd` fails on any script outside `addons/`
naming a TwoVoIP class; `tests/unit/client/app/client_boundary_test.gd` holds `res://voice` to E18's forbidden
names and to E46 (a). The real codec's round trip and FEC probe: `tests/integration/voice/twovoip_roundtrip.gd`
(`tools\run.cmd run tests/integration/voice/twovoip_roundtrip.gd --headless`; SKIP without the addon; not a
`verify` step). CI runs without the addon (§6.5.2).

#### 6.5.2 The addon in the repo (E35 (a), the ADR §2; M5-3, #217)
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

#### 6.5.3 Capture and the gate (E36 as amended, E37, E38, D11; M5-6, #220; files and tests in §4.7.17)
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
  microphone privacy) show in the Voice tab. The same panel is in the main menu's Settings panel (#301, §4.7.17, §4.7.38), so the
  microphone is picked and the meter checked before hosting or joining; with no session the capture and the gate
  run for the meter and nothing is sent.
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
  counted under the Esc menu too since #488, never while typing in a text field or a key capture), or Off, which closes only the own microphone: the others stay audible and the
  Voice slider silences them (the design's reading, still "Needs the engineer"). No echo cancellation: under
  voice activity loudspeakers echo, so the Voice tab says headphones avoid it, with the headset and #22 advice.
  In debug builds the tab also has a test tone in place of the microphone and "mute this window" (E47), neither
  saved. F3 shows the own gate, peak, frame age and encode µs.
- 20 ms frames keep E7's bucket (50 a second) and the relay's newest 5 per poll.

#### 6.5.4 Playback and the ears (E40, E41, D12; M5-5, #219)
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
with the current camera: the own eye (living), the own body's head where it lies (downed: the lying head over the own
avatar's point, near the floor, KE8; never the downed camera), a spectated living target's eye, a downed
target's head, the own body without a target. Godot measures a 3D player's distance from the current
`AudioListener3D` but mixes one only while the world has a `Camera3D` (observed on 4.7.2 headless, not in the
docs; the game always has one). `WorldSounds` measures its 12 m from the ears too (E40's amendment of E33). F3
(debug builds) lists each speaker by an index of first arrival with its queue, prebuffer, frames, late, lost,
concealed, stale, underruns, overflow and decode µs; no peer id or name. Tests: §4.7.15 Hearing voice.
A crouched speaker or target (#792, the crouch ADR's KE7): the mouth hangs on the body's head, lowered with its
crouched eye, and a spectator's ears and spectate camera sit at the target body's head (`Ears.point`'s `target_eye_m`),
crouched or not, never the mode's standing eye; tests `ears_test.gd` and `life_ears_test.gd` (§7.1.17).

#### 6.5.5 Buses and the mix (E43, D15)
`AudioBuses` makes Voice, Effects (the world sounds) and Music, sending to Master (and UI for the Toy buttons' click
at −6 dB with no slider of its own, §4.7.43), in code (`AudioBuses.ensure()` at `Game._ready`, each bus once; the
world sounds on Effects, the lift music on Music, its −14 dB the bus default); four sliders, Master, Voice, Effects and Music
(0, 0, −6 and −14 dB by default: placeholders; −60 to +6 dB, the bottom mutes the bus), no ducking, saved per
window in `user://settings.cfg` (`settings_<n>.cfg` for `PRIME_INSTANCE` n > 1) with the microphone, the mode,
the threshold, RNNoise and the mark, set in the Esc menu's Voice tab (`UserSettings`, `VoiceControl`, `VoicePanel`) or, before any session, the main menu's Settings panel (#301, #493).
`host --clients N`'s windows get their `PRIME_INSTANCE` from `hostjoin.start`, as `run --instances` and
`bots --instances` do from `launch.launch`.

#### 6.5.6 No talking indicator in M5 (D14, the engineer's answer)
No own transmit icon on the HUD, no icon over a
speaker. No screen lists who is talking, and nothing tells a speaker who hears them: the host's relay counters on
F3 (debug builds) never show live during a Round, only in the Lobby, the Countdown and End. Who talks shows later
through a mouth animation with the masks of #73 (after the MVP).

#### 6.5.7 Occlusion (E42, D13 (a); M5-7, #221)
On the listener only, one ray from the ears per audible
speaker per physics frame (to its mouth) and one per world sound as it starts (to a point above it), against the
world layer of the client's own level, never a player's capsule; the host keeps routing by distance. Behind the
level a voice or a world sound is 8 dB quieter (the player's own `volume_db`) and duller (the muffled Voice or
Effects bus, a low-pass at 1 kHz), both placeholders; a voice's muffle eases over 100 ms. The muffle only lowers
and dulls what already plays. The bus for the dullness, not the player's own attenuation filter, by a headless
measurement (§4.7.16 Occlusion's muffle). Beyond one ray (several rays, thickness, portals) is not built.

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
ms, and about 1.1 Mbit/s of the voice upload's per-datagram headers (estimates, not measured). M6-8 built it (#374,
protocol 8).
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

#### 6.5.9 The cutoff and the distance invariant (E41, E45; M5-1, #215)
Every voice rule answers
`hearing_radius_m()`, the farthest it routes a voice between the last accepted positions in 3D (its edge
included), 0 when it routes nobody: the base class and `SilentVoice` 0, `ProximityVoice` its `radius_m`,
`RoundVoice` its `living_m` (§9.4). The static `VoiceRule.radius_of(rule)` gives 0 for a phase with no voice rule;
it is the one number the client's fade (`max_distance`, M5-5), its sender's "a phase whose rule hears nobody"
(M5-6) and the leak test read for the current phase from their own mode, so no radius is copied anywhere. In the
base mode: 8 m in the Lobby, the Countdown and the Round, 0 in Loading, Pregame (§3.6) and End. The leak test checks the
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
- A downed player (`PlayerController.life` DOWNED, set by `set_life`; M4-9) holds still where the host has it and
  only looks (§7.1.7, #728 KE4): every physics step moves nothing, with no gravity, no sprint and no jump
  (`PlayerController._hold`), the living's capsule left standing and no mesh drawn (its body is the own avatar's
  ragdoll, §4.7.9), and its claims carry where it lay and its look; `StaminaSource` refuses sprint and jump to the downed, and their stamina regenerates as usual.
  There is no flight (the engineer's correction of 2026-09-30, #46). The crawl (M4-2) and the raise's hold (`held`)
  went with #728. A dead player has no collision layer, no mesh and no physics step. `Game` sets `life` from its own
  life fold; any life change drops a pending jump. A knocked-down joiner holding the move keys over the loopback
  stays where the host has it with 0 `Correction`s, also on a clock that stands still and then jumps
  (`player_network_test.gd`, `player_controller_downed_test.gd`).
- The crouch (#791, §7.1.17, the crouch ADR's KE5, KE6, KD4 (a), KD5 (b), KD6 (b)): while `crouch_held` (the held
  `crouch` action on physical Ctrl, read inexactly so Ctrl+W still walks), living, anywhere (#991), the body
  takes `crouch_height_m` at once: its own `CapsuleShape3D`'s height switches and the shape moves to half of it, so
  the feet stay, and the contact search's capsule follows; the head eases to `eye_height_of(crouched)` at the step
  view's rate. Without Ctrl it stands only where `test_move` from the feet straight up by the height difference
  hits nothing (`_room_to_stand`), checked each crouched step, so letting go under a low ceiling keeps the crouch
  until the body is out. Crouched, Shift's sprint state (`PredictedStamina.can_sprint`, paid as a sprint) moves at
  `crouch_fast_speed_mps`, else `crouch_speed_mps`. Space while crouched stands up and jumps in the same step where
  the standing capsule fits, does not crouch again before it lands and crouches again on landing while Ctrl is held;
  where it does not fit, nothing happens. Every teleport and life change into the living takes the crouched capsule
  first and stands only where the test from the new place finds room (the ADR's step 7); a
  life out of the living stands the body at once. Each step's pose goes to `set_motion`'s `crouched`. The key
  works in the lobby and on every map (the crouch ADR's amendment, #991: no per-map gate since `crouch_plays` and
  `crouch_maps` went), and `release_keys()` lets go of Ctrl with the other keys under the Esc menu.
- Physics layers (`PhysicsLayers`, named in `project.godot`): 1 `world` (level geometry, Godot's default layer),
  2 `living_players`, 3 `downed` (`PhysicsLayers.DOWNED`, M4-9), 4 `movers` (`PhysicsLayers.MOVERS`: client-only
  moving bodies, today the car repair's car, §4.7.57). The living collide with the world and the movers (#811), the
  downed with the world only (a raise ray passes through the movers); the dead are on no layer; a living player
  finds the other living players with a contact search on layer 2 and pushes them (§7.1.6 "Pushing apart"). Other
  players are
  `RemotePlayerBody` capsules that only their owner's data moves, on layer 2 while the client's life fold says they
  are living and on layer 3 otherwise (a downed player pushes nobody and nobody pushes it).
- Steps: `move_and_slide` stops a capsule at any ledge, so the controller lifts itself onto a ledge up to the step
  height and glides over the edge until it snaps onto the top. While it glides, `move_and_slide`'s own snap is off
  and a snap that lands below the ledge's top is undone: at a slow walk it would catch the edge under
  the rounded bottom, which the body then rested on for good (found at the crawl's 1 m/s on 0.3 m treads, before #728). What
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
Belongs to `core/` (only the living sprint; the downed regenerate, see §7.1.7). The client
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
downed player's jumps are ignored, never corrected (§7.1.7, #728 KE4). Until the next landing
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
  (the downed are not checked: §7.1.7); plus `DISTANCE_SLACK_M`
  (0.05 m) per claim.
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
  current epoch: no record, or a placement since (`PlacePlayers`, a knockdown, a respawn, a revive), until the epoch's first
  accepted claim (a refused or malformed first claim leaves it -1, though its `Correction` bumps the epoch; the
  record's `accepted_tick`, which the push reach reads, counts the placement too); a refused claim's `Correction`
  keeps the last one's age. The zone task counts a player only while it is at most
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

#### 7.1.7 The knocked-down hold still (#728's KE4, 728a #846; the crawl of vision revision 1, M4-2 #138, went)
A knocked-down player cannot move: of its claim the host takes the facing only (a unit vector, as for every claim)
and ignores its position, velocity, jumps and sprint, with no movement check and no `Correction`; its covered ticks
are settled as standing still, so its stamina regenerates as usual and it never sprints (`MovementRule._take_look`).
A taken claim still advances the claim bookkeeping (`player.claim_tick`, and the credit it covers spent), so a claim
whose tick does not rise is dropped, an older twin (§7.1.15) sets no older facing, a run of claims ahead of the
host's ticks meets the past-credit drop, and `SelfStatus`'s `claim_tick` names the last claim taken. A malformed
claim, a negative client tick and a claim past its credit, each corrected from the living, are dropped from a
knocked-down sender with no `Correction` and its facing not taken (`MovementRule._refuse`): the host takes no place
from it to correct. A claim of an old epoch is dropped as stale, as from anyone. The look matters: a dead player
watching a knocked-down target looks through its look. Prevents: a client that still crawls (an old build, a
hostile peer) moving its body, and a `Correction` storm while #728's later parts move the body. `PickUp`, `PutDown`
and `Use` from the downed are rejected (`not_accepted`: Round accepts them from the living only); the dead send no
intent that is accepted (§3.1). The knockdown places the downed player where it stood, on the floor below its last
accepted position, with a new epoch and a `Correction` (`LifeRules.knock_down`), even on the floor: claims in flight
are dropped as stale, and its first claim as downed starts a new client-tick baseline there. A revive is a
placement too (KE6, §7.1.8). A death sends no `Correction`: the dead claim nothing. Tests:
`tests/unit/movement/movement_rule_downed_test.gd` (a far claim moves nothing and is not corrected, the facing, the
regeneration, the malformed, negative-tick, stale and older-twin claims, the past-credit drop),
`tests/unit/movement/`, `tests/unit/stamina/stamina_ledger_test.gd`, `tests/unit/life/life_rules_test.gd`.

#### 7.1.8 The raise (vision revision 1, Revive; M4-4, #140)
The host checks the raise's conditions when `Raise` arrives
and again every tick while it runs (a channel, §9.4): the target is downed, it lies within the pick-up's reach
(2 m) of the raiser's last accepted position, both feet, and the line from the raiser's eye (`Items.eye_of`) to
just above where it lies (`Items.lifted`) is clear; one raiser at a time. So a raiser who walks away or loses
sight stops the raise on the next tick. The raiser may move while it holds E and may hold the package. The raised
player holds still as every knocked-down player does (§7.1.7); until #728 a raise held it in place on its own (the
engineer's answer 8 on PR #133, `Channel.held_at` and `MovementRule.held_against`), which went with the crawl. A
teammate who restarts a raise just short of its time again and again keeps a downed package carrier alive (the
pause) but cannot carry it anywhere; giving up is the way out. A completed raise is a placement (#728 KE6):
`Revived`, then a `Correction` where the player lay with a new epoch (its client claimed no place while knocked
down), then its `SelfStatus`; its next claim starts a new baseline there and is checked at walking speed. Tests:
`tests/unit/life/raise_test.gd` (also: claims move it neither while a raise runs nor after; a stop restarts only a
knockdown the raise paused, of a player still downed).
A hit of the raiser stops the raise because the raise's effect stops on a hit (`ChannelEffect.stops_on_hit`, true
by default; #805). The raise is no longer the only channel: a hold at a station (`HoldStation`, the
[car repair ADR](decisions/2026-10-10-car-repair-task.md)'s RE1 to RE5, #805) is one too. It targets no player:
its rule's `AtStation` checks the holder's feet
against the station's cylinder every tick. A timed hold (the fit) also fails that re-check when the holder's last
accepted claim is more than `MovementRule.PUSH_TICKS` old, when there is no claim since a placement, or when the
holder stored more than `PUSH_TICKS` of credit since (`MovementRule.claim_age`, `credit_gain`). This is the zone
task's ZE10, so a client that stops claiming cannot finish a fit by standing still on the host. The endless hold (the
lift) is exempt: a stale holder only keeps the car up. An honest holder losing half a second of claims would
otherwise drop it on the fitter. Tests: `tests/unit/channel/station_channels_test.gd`.

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
vertically when the target's feet lie at most its own height below the attacker's and at most the attacker's
height above them (each `capsule_height_m`, or `crouch_height_m` while crouched, #790, §7.1.17); the line of sight
runs from the attacker's eye (`Items.eye_of`, the floor below plus the eye height, crouched or not) to the middle
of the target's capsule, crouched or not. A facing with no
horizontal part leaves only the apex; a `Use` without a finite facing takes the last accepted claim's. The
cooldown is a `Cooldown` cost with the key `hit` in the knife's rule, recorded per player in `MatchState`.

#### 7.1.11 Pick up and swap
The client names the item; the host checks reach and line of sight from its own positions.
The picked item goes to the hand, except a one-handed pick beside a two-handed hand item, which goes onto the belt (below, CE21) (vision revision 1, Two hands; M4-5, #141). A one-handed hand item moves to an
empty belt; otherwise (a full belt, or a two-handed hand item, the package, with a two-handed picked item; a
one-handed one goes onto the belt, below) the hand item rests where the picked-up one lay, a spot already known to
be valid. `Swap()` exchanges the
hand and belt items; it needs an item in one of them (`nothing_to_swap`) and is refused with a two-handed item in
the hand (`two_handed`), so a package carrier cannot draw a belted knife (V13), and only the living send it. Only
the hand item is used or put down: `Match._find_action` reads the hand, and `HoldsItem` too. The downed keep both
slots; a death places both at the body and a leave drops both, the hand item first; a respawn starts empty.
2e (#61) measures the reach from the feet (the last accepted position) and the sight from the eye to just above
the item (`Items.lifted`, 5 cm), so the floor or crate it lies on does not block the line.
Since #771 (the [cooking ADR](decisions/2026-10-10-cooking-task.md)'s CE21, the engineer's rule that every take
works beside a two-handed item, CD3 (b)): a one-handed item picked up beside a two-handed hand item goes onto the
belt instead (`Items.take` shares `Items.give`'s belt move), a full belt's item put down at the taker's feet first
(`ItemPlaced` `put_down`), and the two-handed item stays in the hand; `ItemPickedUp`'s `belted` names the picked
item itself. A two-handed picked item keeps the swap above. Three tests changed their expectations for this rule
(two in `take_into_hand_test.gd`, `delivery_test.gd`'s swap into a circle, which keeps its claim with a two-handed
picked item and gains the belted case); `items_test.gd`'s Use with a package in hand keeps its claim, its setup
putting the package down before it picks up the tool.

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
`core/` finds at the end of its flight (§7.1.16; the cause `thrown`; a thrown package
counts, the engineer's TD4 (a): `tests/unit/tasks/delivery_throw_test.gd`). A package resting inside its own circle is delivered: it
stops being interactive (`PickUp` is rejected) and its circle is shown as done. Holding a package over its circle
never counts, because it is not at rest. A circle is an invisible cylinder standing on the floor at its marker
(the engineer's decision of 2026-09-30, #79): radius 1 m (game design, in the data) and height 2 m (a
placeholder). The package counts when its rest position is inside: within the radius horizontally, edge
included, and from the marker's height up to that plus the height, both included (1 mm below the marker
still counts: float noise between a physics floor and a hand-placed marker): `StationState.contains`, the one
cylinder test of a station, which the zone task asks with a player's feet (§9.5.18, #647). The rest position is the one
point `core/` knows of an item: the centre of its base on the surface it rests on, as `WorldQuery` placed it (a
throw's too, §7.1.16), not the centre of its mesh. So a package on a crate inside the circle counts, one on
a floor below the marker does not. The check reads only that position; it asks no geometry of its own.

Delivery by meaning (the House's, #828, §9.5.25) runs the same check with a drop-off for the circle: an item of an
undone subtask resting on the ground inside its own route's drop-off (the same `StationState.contains`, radius 1 m,
height 2 m placeholder) is delivered and locked. An item resting in another route's drop-off, or any other item there,
does nothing (the engineer's DD5 (a)). One drop-off may take several items: it is shown as done only once every item
routed to it this round is delivered (DE7), on the host and in the `ClientModel` fold alike (§4.6.1.2).

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

#### 7.1.16 Throws (#37; #642, #643)
The [throwing ADR](decisions/2026-10-09-throwing-held-items.md)'s TD1 to TD12 and TE1 are answered: the engineer took
every recommendation ([#302](https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-6085059719); TD1's
speed and the gravity, radius and longest flight in the next two comments there; the numbers were approved as built on
2026-10-16, below), and this section follows them. Built so far: the flight and the rest (37b, #642, below); the intent, `ThrowItem`, `OverFloor`, `ItemThrown`
and their wire rows (37c, #643, below).
The client's model, the chaos shapes and the bots' step (37d, #644, below);
the base mode's rule and House's roof check (37f, #646, below); the client's view and prediction (37e, #645) are in §4.7.52.
The flight runs in `core/` (TE1 (a)), not in
`server/`'s physics, which the earlier sketch named (§9.8): the host's level spaces hold no players or items, and Godot
4.7.2 steps them only by physics frames (no `space_step`), while core ticks come from the clock (§4.5.2), so a landing
there would not follow from the commands.
- **The intent.** `Throw(facing)`, from the living in Round, goes to the first `Throw` rule of the hand item, the
  role or the mode (§9.2): `HoldsItem`, `OverFloor`, then the effect `ThrowItem` (speed, gravity, radius, longest
  flight: the engineer's numbers). The client sends only its facing; a facing that does not normalize to a unit vector (non-finite,
  zero, or one whose squared length underflows or overflows) takes the last accepted claim's, as `Strike` does
  (§7.1.10). The host launches from `Items.eye_of` (the floor below the last accepted position plus
  the eye height, as a put-down, §7.1.12) at the rule's speed, without the thrower's velocity (TD10). Prevents: a throw
  farther than the rule, from somewhere else, or through a wall. `Throw` is one of `Intents.PLAYER_ACTIONS`, so the
  dead never throw and the client sends its claim's twin right before it (§7.1.15). **The intent and the effect:**
  `Intents.THROW` (wire kind 17); `ThrowItem` (`core/items/throw_item.gd`, §9.4): `speed_mps`, `gravity_mps2`,
  `radius_m` and `longest_flight_s` (seconds, converted once with `Ticks.from_seconds` at the throw), each defaulting
  to 0 so a rule that forgot one fails the mode check; the bounds are placeholders, "not a decision" (the base mode's values: #646,
  below). `ThrowItem.unit_facing` normalizes without pre-scaling; it asks `Items.fallback_rest`, builds the
  `ItemFlight`, `Items.launch`es it and emits `ItemThrown` from the flight's own vectors. `OverFloor`
  (`core/items/over_floor.gd`) is the `no_floor` refusal, a condition rather than a check inside the effect, so a
  refused throw stops no raise (`RuleRunner` interrupts a channel before the effects run). ModeCheck (§9.1) refuses a
  `ThrowItem` outside an intent (a reaction or a row's actions), a rule with a `ThrowItem` that lacks a non-negated
  `HoldsItem` or `OverFloor`, a `radius_m` above `ThrowItem.largest_radius` (min(capsule radius, capsule height less
  eye height) less `WorldQuery.THROW_RADIUS_MARGIN_M`), and a phase that accepts an intent whose rule (of the mode, a
  role or an item kind) throws but lists no `FlightTicks`. Tests: `tests/unit/items/throw_item_test.gd`,
  `tests/unit/content/mode_check_throw_test.gd`, `tests/unit/net/messages/wire_throw_test.gd`.
- **The flight.** The item is `FLYING`. Each later tick, `FlightTicks` sweeps the arc's segment between two ticks'
  points, each computed from the launch (origin, velocity, gravity, the flight's own count of ticks flown, so a phase
  without `FlightTicks` pauses it rather than making it jump), through a new
  `WorldQuery.sweep(from, to, radius)`: the farthest point a sphere reaches, `from` itself when the sphere starts in
  the world. `server/` answers with `intersect_shape`, then `cast_motion`, which ignores a shape the sphere starts
  in. The mode check keeps the throw's sphere inside the player's capsule at the eye, with a margin, so a thrower pressed against a
  wall can still throw away from it. A living player other than the thrower stops it too (their capsule at the last
  accepted position, as hits read it); the downed are flown over (TD12). Prevents: an item through a crack or a ceiling, and
  a landing that differs between two runs of the same commands. **The flight:** `ItemState.Where.FLYING` (after
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
  Prevents: a package thrown off the map's edge hanging in the air out of everyone's reach. **The rest:**
  `FlightTicks` rests the item through `Items.place` with `Items.THROWN` (`place` clears the flight), at
  `floor_below(Items.lifted(stop))`, else at the flight's fallback with an error logged. `Items.fallback_rest(ctx,
  feet)` is the fallback's question, which `ThrowItem` asks at the launch. A fallback that is itself no floor rests
  the item at the stop, with its own error; since #643 no throw reaches it (`OverFloor` refuses one, ModeCheck
  requires it, and `ThrowItem` itself logs an error and throws nothing over no floor). Readers of `where`: `ItemOnGround`
  rejects an item in flight as `unavailable`, `Items.take` and Delivery act only on the ground, the snapshot's items
  in `core/` show `FLYING` at o, and `Items.free_markers` counts no flying item. Tests: `tests/unit/items/item_flight_test.gd`,
  `flight_ticks_test.gd`, `items_test.gd` (the launch and the readers), `tests/unit/tasks/delivery_throw_test.gd`,
  and the cause in both lists of `tests/unit/net/messages/wire_core_test.gd`. #642's flight tests put an item in
  flight with a test's `Use` (`FixtureThrow`), kept on purpose: their numbers and rule lie outside `ThrowItem`'s
  bounds and required conditions. The test that the points decoded from `ItemThrown` equal `FlightTicks`' sweeps, exactly,
  is `tests/unit/net/messages/wire_throw_test.gd` (#643).
- **Who sees it.** `ItemThrown` (item, thrower, origin, velocity, gravity as a `vec3` so that it round-trips
  exactly, launch tick) goes to everyone; nothing in it is hidden (§5) while the rule
  belongs to the item kind or the mode (a role-owned one reveals the role, §9.2). The snapshot stays avatars only (§4.3): the
  thrower's client predicts the arc at the key press, and every other client draws it from `ItemThrown` on its
  avatars' timeline (§7), until `ItemPlaced`; its view joins `SightHider`'s group as every item view (§4.7.10), depth-tested with no trail, and its launch
  sound goes through `SoundChooser`, cut beyond the hearing range like every world sound. The
  flight's geometry reaches the command log as `WorldQuery` answers (§3.3); `server/` originates no command for it.
  **The client:** `ClientModel` folds `ItemThrown` (§4.6.1.2; `client_model_test.gd`), and `ItemViews`,
  `TargetChoice` and `PlaycheckSteps` skip a flying item (`item_views_test.gd`, `target_choice_test.gd`,
  `playcheck_steps_test.gd`); `ScenarioBot` folds it into `Where.FLYING`, whose place it cannot know, and the
  `Throw` step (§9.7) sends it (`scenario_runner_test.gd`); `throw_scenarios_test.gd` throws a package end to end
  (with the base mode's own rule since #646), through the core runner and the network, where the leak
  check compares each `ItemThrown` exactly; chaos sends its facing extremes (§4.6.5.3; `chaos_frames_test.gd`,
  `chaos_test.gd`).
- **The base mode throws (37f, #646).** Its one `Throw` rule (`HoldsItem`, `OverFloor`, `ThrowItem`) takes every
  item, and Round accepts `Throw` from the living and lists `FlightTicks` after `ChannelTicks`, before `TaskTicks`
  (§3.2). The numbers (#302 comments 6085904317, 6096074314), approved as built by the engineer on 2026-10-16 with
  the M7 playtests skipped ([#879, comment 6202590193](https://github.com/xperiaroco2/prime-game/issues/879#issuecomment-6202590193)):
  5 m/s, the project's physics gravity (9.8 m/s²), a 0.15 m radius, a 3 s longest flight. **House's roof:** walkable,
  but its door may be locked, so instead of TD5 (b)'s "no rest" volume the speed is kept below what reaches it: the highest speed, in 0.5 m/s steps, at which
  no throw from a standable spot near the roof rests on it, less one step: 5.5 m/s on the greybox House's flat roof
  at 6.4 m, where the tops of the balcony's 1 m railings decided it (a 1 m jump may reach them and the eye then
  stands 1 m higher; at 5 m/s the highest arc from there topped out at 7.08 m, below the 7.35 m a 0.15 m item needed
  to clear the roof's parapet). The art's House (#523) has a pitched roof over the attic, its eaves at about 8.3 m:
  from the balcony's floor 9 m/s rests 140 of house_roof_throw_test's 38 880 throws on it and 7.5 m/s none, so the
  rule's 5 m/s keeps a wider margin there.
  **Tests:** `tests/integration/levels/house_roof_throw_test.gd` flies 648 throws from each spot of
  `house_throws.gd` at the rule's own numbers against House's host collision world and fails on any rest on the
  roof (a later speed, gravity, radius, eye height or level change that reaches it turns it red; seen red at 6 m/s);
  `tests/unit/content/base_mode_throw_test.gd` (the rule and its numbers), `delivery_content_test.gd` (Round's tick
  order), `tests/unit/items/throw_replay_test.gd` (a throw replayed from its command log), `chaos_test.gd`
  (§4.6.5.3), and the scenario `crew_throws_a_package_into_its_circle` (§9.7). The level convention: `levels/CLAUDE.md`.
- **The engineer's answers** (all as recommended, #302): strength and range (TD1 (a); 5 m/s since #646,
  approved as built, above), which
  items (TD2), what a thrown item does to a player (TD3 (b): stops and drops at its feet, no damage), a thrown package
  counts in its circle (TD4 (a)), where an item may come to rest (TD5 (a); House's roof by the speed, #302 comment
  6096074314), a cost (TD6), the key (TD7), no catching
  (TD8 (a)), stop and drop, no bounces (TD9 (a)), no running throw (TD10 (a)), the rest with no floor below the
  thrower's feet (TD11 (a)), the downed flown over (TD12 (a)). The issues 37a to 37f follow the ADR's split.

#### 7.1.17 The crouch (#727; #790 to #792)
The crouch has the host's part and the wire, the local player's crouch and others' crouch with the quiet steps; the
character's crouch clips (`Crouch_Idle`, `Crouch_Fwd`, #522) play on its remote avatars (§4.7.53).
The engineer decided a crouch for every player (#727: hold Ctrl; Shift while crouched moves a bit faster); the
[crouch ADR](decisions/2026-10-10-crouch.md) designs it, and he answered its KD1 to KD8 on 2026-10-10 (PR #752,
comments 6097878317 and 6098097098). A crouch shrinks the capsule from the top: the feet, which every movement check
reads, do not move.
- **Where.** Everywhere: the lobby, the tutorial, the House and the greybox (the engineer, 2026-10-14, #989, #991:
  movement basics are never blocked anywhere, and no per-map option; the crouch ADR's amendment reverses KE10 (a)).
  `MovementRule` keeps a living claim's bit in every
  phase that accepts a `MoveClaim` (`PhaseSpec.accepts`), the lobby included, and a crouch lasts across a phase
  change like any pose (a placement, a knockdown and a respawn stand the player up). Bots never crouch, so the
  scenarios, the chaos run and the perf run on the greybox are unchanged.
- **The claim.** `MoveClaim`'s and `MoveClaimReliable`'s flags gain `crouched` (8), the pose at the claim's last
  physics step, and the avatar's flags gain `crouched` (4), relayed in the snapshot: one protocol bump, no byte more
  (KE1); the photo task's `ShotTaken` record, once built, carries the same bit, and its subject's head takes the
  crouched eye (KE2). Prevents: a separate crouch intent on another lane, whose pose disagrees with the position for
  a round trip. `crouched` joins the public avatar fields (§5, both leak-test allowlists), and a scenario invariant
  reads the player's state, not the rule, to fail a crouch relayed for a player not living (the ADR's "Who sees
  what"; its phase and map clauses went with #991).
- **The host** keeps `PlayerState.crouched` from the last accepted claim, false at every placement and knockdown, and
  ignores a downed claim's bit (KE2). It reads it for the eye (`Items.eye_of` takes `crouch_eye_height_m`, so every
  sight line of a crouched player starts there: a crouched player does all a standing one does, from that eye, KD8)
  and for the capsule (`Strike`'s vertical overlap and the end of its sight line, a thrown item's contact:
  `crouch_height_m`, KD7). Prevents: an honest crouched player under a ceiling lower than the standing eye refused a
  pick-up as `blocked`. No new speed or height check (KE3, KE4): an honest crouch is slower than the walk, whose bound
  holds it, and the host's world has no car to check headroom against (the car repair ADR's RE8). Shift while
  crouched is the sprint state at `crouch_fast_speed_mps`, paid as a sprint (KD5): the claim's `sprint` flag and mask
  carry it, so the stamina ledger and the sprint bound hold with nothing new. Accepted, as for walls (§7.1.9): a
  modified client can claim a crouch at any speed, sprint included, and be hit as a crouched player; or claim
  standing where an honest one crouches, so its eye and sight lines start above a low ceiling (a pick-up or a stab
  through a thin floor over a crawlspace). No level has such a place; one that adds it brings back the ADR's KE3 (b)
  and KE4 (b).
- **The client** switches its own `CapsuleShape3D` between `capsule_height_m` and `crouch_height_m`, the feet staying,
  and stands up only when `PhysicsBody3D.test_move` straight up by the difference finds room (KD4, KE5, KE6). Space
  while crouched stands up, then jumps, and does nothing where the standing capsule does not fit (KD6). Remote bodies
  take the pose from the snapshot, their capsule, head, mouth and sight point lowered with it (KE7); no name plate is
  drawn over any player (KD2, removed by #756). The steps of a slow walk are quieter and slower (KD1), read from the
  speed as every step is, never the flag: at or below `crouch_speed_mps` 6 dB quieter and heard within 6 m
  (placeholders), eased to a walk's at `crouch_fast_speed_mps` (#991: the fast crouch sounds like a walk; the ease a
  placeholder), anywhere; the cadence's held stride makes
  them slower. The input is a held, rebindable `crouch` action on Ctrl (KE8) with its Settings row
  (`control.crouch`, #951).
- **Under the car** (#688): the raised car's underside lies between the crouched and the standing heights, so its
  height alone asks for the crouch (KD3 (a), the engineer's, which also answers the car repair ADR's RD1). A crouched
  player may hold the lift (KD8), so the car repair ADR's "no view of who is under the car" test (its RE15, in R8)
  runs from the panel's use spot at every eye height from `crouch_eye_height_m` to `eye_height_m` (every 0.1 m, both
  ends), and the level's walls block that whole band; R8 (#812) runs that band from every point
  of the panel's cylinder where a player fits and sees the panel (`house_car_repair_match_test`, §9.7). Prevents: a
  dissident crouching at the panel and seeing the fitter's legs under the car.
- **The host's part and the wire.** The crouch plays everywhere (the crouch ADR's amendment of 2026-10-14):
  `PlayerRules`' four crouch numbers, `height_of` and `eye_height_of`, with no per-map option (§7.1.18's
  `motion_maps` is a separate list); `PlayerState.crouched`, kept by `MovementRule` from an accepted living claim in
  every phase that takes a claim, never from a downed one, false at each placement, knockdown and respawn; the
  snapshot avatar's `crouched`; `Items.eye_of`, `Strike`, `FlightTicks` and `ThrowItem`'s largest radius reading the
  crouched eye and capsule; the photo task's subject head and `ShotTaken`'s record row (§9.5.22); the avatar's
  flag bit on the wire (§4.3.5); `ClientSession.set_motion`'s `crouched` (the controller's) and `ClientModel.is_crouched`; the base
  mode's numbers (§9.5.1). The scenario invariant is `ScenarioInvariants.crouch_problem` (a crouched player who is
  not alive), run on every tick's snapshots by `check_tick`. Bots play the House only on a flat fake floor (§9.7),
  and the greybox carries no new mechanic (the engineer's answer (a) on #790): the wire is tested through the host
  session harness on a fixture mode instead, as cooking C9 did. The car repair's RE15 eye band runs in R8's House
  test (#812).
- **Tests:** `tests/unit/movement/movement_rule_crouch_test.gd` (kept and shown, in the lobby too, kept across a
  phase change, ignored from the downed, cleared by placement, the walk bound and the sprint charge),
  `tests/unit/content/player_rules_test.gd` (bounds, no per-map option, the helpers), `strike_test.gd`,
  `flight_ticks_test.gd`, `mode_check_throw_test.gd`, `photo_shot_test.gd`, `respawn_test.gd`, `view_of_test.gd`,
  the client's `client_session_claims_test.gd` and `client_model_test.gd`, `chaos_frames_test.gd` (each flag bit
  past `crouched`), `tests/scenarios/crouch_invariant_test.gd` (the invariant; a lobby crouch passes),
  `content_modes_test.gd` and `tests/integration/server/host_session_crouch_test.gd` (over the real wire: a
  crouched avatar shown, a downed claim's bit ignored, the crouch kept on the second map, in the lobby and from a raw
  client there; each client's decode equals its `view_of`).
- **The local player's crouch** (§7's controller, §4.7.6): the `crouch` action on physical Ctrl in `project.godot`,
  a row of Settings › Controls (#951), and no living action on Ctrl; `PlayerController`'s `crouch_held`,
  `is_crouched()` and `release_keys()`, the capsule switched with the feet kept, the eased eye, the `test_move`
  stand-up test, the crouched speeds, the jump from the crouch, the crouched capsule first after every teleport and
  life change, and `set_motion`'s `crouched`. The test level is `tests/fixtures/client/crouch_room.tscn` (a slab
  under 1.4 m), never the greybox (#767, the engineer's answer (a) on #790).
- **Tests:** `tests/integration/client/player/player_controller_crouch_test.gd` (blocked standing and passing
  crouched, letting go underneath, a teleport and a life change underneath, Shift's speed and stamina and the slow
  walk without it, the crouched jump and none under the slab, landing crouched again, never downed or dead, each body
  its own capsule), `player_network_crouch_test.gd` (over the loopback, `NetPair.with_crouch_room`: 0 `Correction`s,
  also with packets held back and with jitter, the host relaying the pose; Ctrl with W and Shift through
  `Input.parse_input_event`; the Esc menu releasing Ctrl; Ctrl crouches in the lobby) and `controls_test.gd` (the
  crouch on Ctrl, no living action on it).
- **Others' crouch and the quiet steps** (KE7, KD1 (b)): `SnapshotBuffer.Pose.crouched`, the flag of the snapshot
  at or before the drawn tick (never blended); `AvatarViews` calls `RemotePlayerBody.set_crouched` before `set_pose`
  (at once for a body drawn for the first time), which switches the capsule, the greybox look (`LifeLooks.capsule`,
  `shell`) and the sight point at once and eases the head with the mouth, hand, belt and carry points down by the eye
  heights' difference at the own view's catch-up rate (§4.7.6); a downed body lies at standing size. The spectate
  camera and the spectator's `Ears` sit at the target body's head (§6.5.4). The quiet step:
  `FootstepCadence.quiet_of(speed, quiet_mps, loud_mps)` of a step's speed (averaged over the step), from
  `crouch_speed_mps` (quiet) to `crouch_fast_speed_mps` (a walk's), a hard edge when the two are equal, used by
  `WorldSounds` (§4.7.43); the sneak's silent step: `FootstepCadence.silent_of` (§9.5.24, #990); #522's crouch clips
  play on the character's remote avatars (§4.7.53); without the character the bodies stay capsules. A `shot`
  preview: `client/dev/crouch_preview.tscn`.
- **Tests:** `tests/unit/client/world/snapshot_buffer_test.gd` (the pose's flag),
  `tests/integration/client/world/avatar_views_test.gd` (the push search finds the crouched capsule in the frame it
  crouches; the head, mouth, points and look lowered and eased; a body first drawn crouched at once),
  `tests/unit/client/life/ears_test.gd` and `tests/integration/client/life/life_ears_test.gd` (the dead see and hear
  from a crouched target's crouched eye), `tests/unit/client/world/footstep_cadence_test.gd` (`quiet_of` at, below,
  between and above the speeds, a mode without them; the step's speed over the step) and
  `tests/integration/client/world/world_sounds_steps_test.gd` (the quiet step at crouch speed, the fast crouch a
  walk's, the slow steps below `crouch_speed_mps`, eased between, cut beyond 6 m, the own slow steps quiet too, on a
  fixture world).

#### 7.1.18 The knockdown reworked (#728; #846 to #848)
The engineer decided (#728, his answer A in its comment 6095620279) that the knockdown stays as it is (§7.1.7's
knockdown, §7.1.8's raise, `LifeTicks`, the give-up), except that a knocked-down player cannot move and cannot talk,
and its body falls as a ragdoll that a hit can send flying. He answered every question of the
[knockdown ADR](decisions/2026-10-10-knockdown-reworked.md) on 2026-10-10: each recommendation (PR #754, comment
6097876326: KD1 to KD8 (a), KD9 (b), KE5 (a), and the launch on the House only), and KD10 (A) (comment 6100602989):
the body is a real rigid body in the host's physics, which rolls or slides it off any slope, roof or stairs by
itself, with no slide rule, so KE1 is (b). Its issues 728a, 728b, 728d, 728e and 728f (the ADR's §10) are
proposals for the M7 backlog; nothing is built until he says so. KD11 (comment 6108669765, 2026-10-11): the body's
collider in the host's physics is a crouching player's, so a body rests only where a crouching player fits, and a
raised player gets up crouched there and stands by the crouch's rules (§7.1.17) once there is room. KD12 and KD13
(comment 6109457234, the same day), both (a): a launch never carries a body where no player can reach it, since the
levels keep every surface a launch can reach within a raise's reach of a spot a player can walk to, tables and the
roof included (#646's reach convention applied to bodies, checked on the House by 728f's tests, no rule in `core/`);
and the host's capsule never turns. KD14 and KD15 (comment 6110171062, the same day), both (a): tables keep the
space under them, so a body may rest under a table a crouching player fits under as long as a raise can reach it,
with no level rule that closes tables; and a player raised from a body launched into the lowered car (client-only,
so the host's body rests inside it) is pushed out by its own client, the car's accepted quirk (its ADR's RE8 and
RD6 (a)), with nothing new in code. That push starts with the feet inside the footprint box, deeper than the 0.4 m
from its edge RD6 (a) accepts, so 728e's test records it and stops if the host corrects it more than once. It
measured 3 `Correction`s (with a stand-in car until the car repair's R5 and R7), the stop the ADR's §2 names; the
engineer then chose **KD15 (b2)** ([#976, comment 6162445237](https://github.com/xperiaroco2/prime-game/issues/976#issuecomment-6162445237)): the raised player's own client walks
its capsule out of the car at walk speed over its first claims, ignoring the car until clear (§4.7's revive), with
no `core/` change; the stand-in test now measures no sink and no `Correction`.
- **Still** (§7.1.7, §7.1.8). A knocked-down player's `MoveClaim` moves nothing: the host
  takes its facing only (a spectator watching a knocked-down target looks through it) and ignores the rest, with no
  movement check and no `Correction` (KE4). §7.1.7's crawl, its slack, `PlayerRules.crawl_speed_mps` and §7.1.8's
  hold went; `revive` sends a `Correction` (KE6). Prevents: an old or hostile client crawling, and a correction
  storm while the host moves the body.
- **Mute.** Nothing changes: §6.3 already routes no voice from a speaker who is not living, its client sends none,
  and the HUD's mic (#489, open) is to show off while knocked down (KE10).
- **The body's motion** (KE1 (b), KD10 (A)). Only the strike that knocks down launches the body (KD1; the strike's
  `launch_mps` away from the attacker and `launch_up_mps` upwards, the knife's included; KD2, KE9). On a map
  `motion_maps` lists, `knock_down` emits the directive `LaunchBody` (audience *server*, §4.2), and `server/`'s
  `HostBodies` starts a rigid capsule, the crouching player's collider (KD11), upright at the player's feet, in the
  level's world that answers `WorldQuery` (§4.5.9), colliding with the world only, under the engine's gravity and
  materials (KE13): it flies, slides and falls off whatever the level's colliders give it, and never turns
  (`BODY_MODE_RIGID_LINEAR`), so it rests only where a crouching player fits. That it never turns is the agent's
  reading of KD11, which the engineer confirmed (KD13 (a)): the host's body never rolls (only each screen's ragdoll
  does) and slides off only a slope steeper than its friction angle. `core/` holds no physics (invariant
  3) and keeps where the body is: each core tick `server/` queues `BodyMoved` (the capsule's lowest point and its
  velocity), a command it originates
  as it does `PeerConnected`, logged for the replay (§3.3) and never sent by a peer; `core/` sets the knocked-down
  player's position and velocity from it, which every rule and the filtered snapshots read as today (KE14). `core/`
  decides the rest: reports slower than the rest speed for the rest time (counted only in ticks that brought a
  report, so a hitch's catch-up ticks never end a motion in mid-air), or the longest motion, then the standing
  floor under the capsule at the last point (`stand_floor_below`, so a body on a stair's nosing or a railing rests on
  it, not on the floor below) (or the knockdown's own floor, with an error, over no floor), and `StopBody` frees the host's body
  (KE15). The state is `PlayerState.motion` (KE3). A body still moving cannot be raised (`TargetDowned` rejects
  `moving`, KD4), and a death ends the motion where it is (KD8). Prevents: a body rolling off a roof on one screen
  and staying on it for the host, where a teammate standing over it could not raise it. The cost the engineer took:
  the same commands can rest a body in two places on two runs (Godot 4.7.2 steps the host's spaces by physics frames,
  with no call that steps one, §7.1.16), so the replay holds through the logged reports, and the motion is checked
  by host-side integration tests that assert where a body may rest, not by `core/`'s determinism.
- **The House only** (the engineer's answer; KE12). Bodies move only on the maps `PlayerRules.motion_maps` lists, the
  shape of `TaskType.maps` (the Generator ADR's GE15): the base mode lists the House alone, and the mode check
  refuses a path that is not one of the mode's maps (its KD11 crouch clause went with `crouch_maps` in #991:
  the crouch plays everywhere, §7.1.17). On the flat greybox a
  knockdown takes no launch and starts no host body, whatever the knife's numbers, so it is today's knockdown, still,
  mute and drawn as a ragdoll; the scenarios, the chaos run and the perf run, which play the greybox, see no motion,
  and the House's motion is checked by integration tests (bots play the House only on a flat fake floor, §9.7). Prevents: the knife's
  launch, which travels with the knife to every map, bringing a new mechanic to the greybox.
- **Who gets what.** The knocked-down avatar reaches everyone as today, its position moving with the body; its own
  player gets it too while knocked down (KE5: the one exception to §5's "nobody gets their own avatar", with a
  protocol bump and the wire's `MAX_AVATARS` raised from 15 to 16, so a full match's snapshot still decodes), so its
  camera and ears follow the body. `LaunchBody` and `StopBody` reach no peer.
- **The ragdoll** is the client's looks only (KE7): held by a spring to the interpolated point, colliding with the
  world layer only, and never read by the raise hint's reach, the camera, the ears or `SightHider`. `DownedCamera`'s
  pivot, for the own player and for a spectator of a knocked-down target, stays above the body as today and follows
  it (KD6), rises no higher than the standing eye height above the floor below the body and stops below a ceiling
  right above it (KE8). A dead body keeps the ragdoll's pose, greyed, with the cross, and a raised player gets up at
  once (KD7), crouched until the standing capsule fits (KD11; the crouch's controller, §7.1.17, KE6).
- **Numbers.** The launch speeds, the rest speed and time and the longest motion are placeholders the agents set,
  marked "not a decision" (KD9 (b)), each with bounds in its data; the gravity, mass, friction and bounce are the
  physics engine's. The base mode's: 0.1 m/s for 0.5 s, 8 s at the longest; the knife's launch 4 m/s away and
  2 m/s up (728e), which moves a body on the House alone (`motion_maps`).
- **The motion.** `core/`: `BodyMotion` (`core/life/body_motion.gd`), `LifeRules.knock_down`, `body_moved`,
  `count_motion`, `rest`, `stop_motion`; `LaunchBody`, `StopBody`; `Intents.BODY_MOVED`; `Strike`'s launch; `TargetDowned`'s
  `moving`; `PlayerRules.motion_maps` and the rest's numbers; `Snapshots.for_peer`'s own avatar (protocol 30).
  `server/`: `HostBodies` in `HostWorldQuery`, `HostSession`'s reports and directives. Every launch ships at 0 (the
  House's numbers are 728e's); the bots' fold skips the own avatar (the client's `AvatarViews` did until 728d). Tests:
  `tests/unit/life/body_motion_test.gd` (scripted reports), `tests/unit/combat/strike_launch_test.gd`,
  `tests/unit/content/player_rules_test.gd`, `tests/unit/net/messages/snapshot_own_avatar_test.gd`,
  `tests/scenarios/body_motion_invariants_test.gd` (the invariants through a motion, the own-avatar check's plants) and
  `tests/integration/server/host_bodies_test.gd` (the probe; the ledge, ramp, stairs, wall, hole, low table, low
  ceiling, nosing and railing of `tests/fixtures/levels/body_rest_course.tscn`).
- **The client.** The ragdolls, the own camera and ears from the own avatar, KE8's clamps and the dead body
  (KD7): §4.7.9's "Ragdolls". The client's `AvatarViews` draws the own avatar since.
- **The knife's launch:** `content/items/knife.tres`'s `Strike` 4 m/s away and 2 m/s up
  (placeholders, "not a decision", provisional for the engineer's approval, §9.5.6); `motion_maps` stays the House
  alone (KE12). Tests: `tests/integration/levels/house_knife_launch_test.gd` (the base mode on the House in the
  host's world: launches in 8 directions from the yard, the terrace, the balcony and the top of the outside stairs,
  each read from the level's floors, rest on a floor within the longest motion where a crouched capsule is clear,
  KD11, never at an exact point, KE1 (b); on the greybox a knife knockdown starts no host body and is today's, step
  for step) and `tests/integration/client/life/life_raise_in_lowered_car_test.gd` (KD15 with a stand-in
  for the lowered car on layer 4: under (a) it measured the capsule pushed down into the floor on its own screen,
  not out, and 3 `Correction`s on the way out; under (b2), #976, it asserts no sink, the capsule out of the
  footprint and at most one `Correction`, measured 0).
- **Thrown items and the levels.** KD12 (a) kept by the levels, no rule in `core/`: `levels/CLAUDE.md`'s "Thrown items"
  convention names launched bodies too. `tests/integration/levels/house_body_reach_test.gd` checks the House: its
  `WALKABLE` list names the pieces of `house.tscn` whose floors players walk (every piece, a node declaring
  `size_m`, is listed there or in `LOCKED`, which is empty: the art's walkable attic stair under a 3.125 x 1.14 m
  hatch replaced the hatch ladder, prime-game-art#183 and #188, #1080, which also moved the attic's knife marker
  back from the pump room, where #523 had put it); a flood fill of the crouched capsule from the `round_player`
  spawn markers over those pieces' walked colliders (the art rooms' `Shell` floor, slab and stair pieces, the
  garage's among them since the art's P6, #1052, and the plot's ground; each spot named after the smallest piece
  whose footprint holds it; 0.5 m apart in two halves, each rise at most `step_height_m`, any drop; a flight
  narrower than the lattice, the attic stair between its stringer walls, is walked 0.1 m at a time along
  `NARROW_FLIGHTS` from a spot at its foot, its top joining the fill) gives the spots a player walks to, every
  piece reached; from one open spot near each piece's middle, every launching
  `Strike` of the base mode's item kinds (read from the data) knocks a body down in 8 directions, and each rest must
  lie off the locked roof and within the raise's reach of a spot (`TargetInReach`'s distance from its feet, read from
  the `Raise` rule, and `TargetInSight` from its crouched eye). On the House as it stands every knife launch passes;
  seen red with the reach cut to a tenth. A rest out of reach is reported, the scene being the humans'.

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

**v0** (#33, [ADR](decisions/2026-09-29-content-api-v0.md), accepted by the engineer); the
designer reviews it before v1 (#38). Every part's row (§9.4) or entry (§9.5) names its code; a part whose row names
none is not built and is not usable in data. Which task or PR built a part is in its ADR's Consequences (stage 2's,
2a to 2j: the content API v0 ADR). Every number is a placeholder from the
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
    where: on the ground, in a hand, on a belt or locked, position; ids 1 to `MAX_ITEM_ID`, 0xFFFE, the wire's `item`, kept in the order added: id order until a freed id is reused past the last, #779, so a part needing §3.3's order sorts them); tasks, each with a **task state** object (`RefCounted`) that its task type creates in its deal
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
    (`ChannelEffect.required_conditions`: `RaiseDowned` needs `TargetDowned`, `HoldStation` `AtStation` and
    `ChannelFree`, #805); a `HoldStation` in a rule on an intent that names no station, or without `StationInSight`, or with `ChannelFree` before `AtStation` or `StationInSight` (its `busy` tells of another holder: only a player with the station in reach and in sight may hear it; #805); a phase that accepts an intent whose
    rule throws (a `ThrowItem`) but lists no `FlightTicks` (#643); an item kind with `vanish_seconds` in a mode where no phase lists `VanishTicks` (#779), or a Delivery whose package kind vanishes (the task knows a package by its item id alone, which a vanish frees for reuse); a `ThrowItem` outside an action or in a rule that
    lacks `HoldsItem` or `OverFloor` (`ThrowItem.required_conditions`); a required condition counts only when it is
    not negated (#643); a reaction or a win condition holding a
    condition that reads the actor (`Condition.reads_actor_state`, §9.4's "Where" column), which tests no player there
    (§9.2, #283, #299), or one that reads the rule's target where nothing supplies it (`Condition.needs_target`: a win
    condition, or a reaction whose fact does not carry it, #379); an accepted intent that neither the phase class
    nor any rule handles; two actions on one intent in one owner (reactions are exempt: conditions are ANDed, so two
    mechanics reacting to one fact need a rule each, and all of them run, #1253); an action that is never reached, on `MoveClaim` (the
    movement rule takes it) or on an intent the class of every phase that accepts it handles (`RuleReachCheck`,
    #1236; a reaction with no effects is a warning); a number outside its part's bounds; an id outside
    the wire's alphabet (3e, #97; §4.3, E5): every `id`, `side`,
    `spawn_tag` and `tag` a part holds, every condition's rejection reason and every reason a task type lists in
    `use_reasons()` (#780), is 1 to 32 characters of `a-z`, `0-9`
    and `_` (D1 (a), the designer's answer on #96). A unit test (2a, `tests/unit/content/content_modes_test.gd`) loads
    every mode in `content/modes/` and runs this part (`ModeCheck`; its station checks are `StationRuleCheck`'s and
    its checks of the conditions that read the actor or the target `ActorConditionCheck`'s, #1249). Each error starts
    with the mode's file, and a part's index path (`mode.item_kinds[17]`) carries the part's own file or its
    sub-resource id in the mode's file (`mode.phases[1] (::Phase_round)`; Godot 4.7.2 gives a sub-resource loaded from
    a `.tres` the path `<file>::<id>`); a host that cannot start prints them one per line (#1253,
    `tests/unit/content/mode_check_sources_test.gd`).
  - *With the layouts* that `server/` or a test hands in: a spawn tag that a part places on and a map lacks (a task
    type only on the maps it plays on, `TaskType.maps`, #803); a marker with two tags; a lobby with fewer
    `lobby_player` markers than the mode's maximum of players; a level without a layout. `Match` runs this part (`LayoutCheck`, 2b) on creation, with the tags each row's actions
    demand at the default settings and the maximum of players (§9.4). The content test runs it with the layouts of
    the mode's levels, read by the marker reader (2j, `server/levels/marker_reader.gd`), and checks that the
    greybox fits 10 players at the default settings and at the most packages
    (`tests/unit/content/content_modes_test.gd`).
- **Checked as text** (#1238). Godot loads a `.tres` key that no property has (`negate_ = true`) without an error and
  keeps the default, which neither part above can tell from a deliberate one. `check` (`tools/check/content_keys.gd`,
  run by `check_project.gd`) reads every `.tres` under `content/` and fails on each `[resource]` or `[sub_resource]`
  key that is not a stored property of its section's class (type and script), naming file and line; `script` and
  `metadata/` keys pass. Tests: `tests/unit/tools/content_keys_test.gd`.
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
  `Rejected` with that condition's reason (`Condition.rejection_reason_in(ctx)`: its fixed `rejection_reason()`,
  unless the reason depends on the run, as `StationUsable`'s, which passes on its task type's own, #780); for a fact,
  nothing happens. Every condition has `negate: bool` (false); a
  negated condition rejects with `not_allowed`. A **cost** is a condition that is also paid (stamina, a cooldown,
  later a use): all conditions and costs are checked first, then every cost is paid in order, then the effects run,
  so a refused intent pays nothing. An effect may refuse too (`RuleEffect.refusal`, asked of every effect in order
  after the conditions, before a channel is interrupted or anything is paid: `GiveItem` at its cap with none loose,
  `unavailable`, #770), so a refused intent still pays nothing. **Where a condition may appear.** A reaction runs, and a win condition is checked,
  for no player (actor 0), so a condition that reads the actor (its player state, its hand, its channel) tests no
  player there and its answer never changes: a cost that reads the actor's player state (`Cooldown`, `StaminaCost`)
  always refuses, so a reaction with one would never run its effects, record no cooldown and charge nobody (#201;
  `tests/unit/combat/costs_in_reactions_test.gd`) and a win condition with one would never hold; `HoldsItem` never
  passes and `HandNotTwoHanded` always does. The mode check therefore refuses such a condition in a reaction or a win
  condition at load, naming the mode's file, the fact or the win condition, its index in `reactions` or `win_conditions` and
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
- **A fact is handled at once, depth first.** When an effect raises one, the rules on it run (every reaction of the
  mode on that fact, in data order, then each task type's check, in the mode's order), then the current phase's win conditions are checked, and only
  then does the raising effect go on. A chain deeper than 16 facts is a bug: `Match` stops it with an error in every
  build.

| Fact | Raised when | The rule sees (**hidden** fields in bold) |
|---|---|---|
| `item_rested` | an item comes to rest: put down; swapped (a pickup's hand item that did not go to the belt, M4-5); dropped at a death or a leave, once per slot, the hand item first; spawned; thrown, at the end of its flight (§7.1.16, `FlightTicks`, #642); laid on the ground at a station (`Items.lay_on_station`, the cooking ADR's CE5, #771: a wrong ingredient at a place). A `Swap` between hand and belt raises none: nothing comes to rest | the item, the cause (`put_down`, `swap`, `death`, `leave`, `spawn`, `thrown`, `on_station`), the rest position |
| `player_died` | a downed player dies (its knockdown ran out, M4-2, or it gave up, M4-4), or a living or downed one is killed at once (`LifeRules.kill`, #806), before its hand and belt items drop | the player, the body position; no killer, as no event names one (§4.2). A knockdown raises no fact |
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
| Item kind | `target_actions`: rules on intents that name an item (`Interact`'s `item`) | to an intent naming an item of that kind, alone: never the role's or the mode's rules (a box's take; the cooking ADR's CE1, #770) |
| Station kind | `actions`: rules on intents that name a station (`Interact`) | to an intent naming a placed station of that kind (the Generator's switch; #796, the Generator ADR's GE2); none for a `display` kind, whose stations no rule receives (CE6, #770) |
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
  An intent that names a station (`Interact`, any intent with a `station` field: `Stations.names_station`) goes
  instead to the first rule among the station's kind's actions, the role's and the mode's, never the hand item's
  (ModeCheck refuses an item kind's rule on it); a `station` that names no placed station is refused
  `nothing_to_do` before any owner is tried, so a role's or the mode's rule only ever sees a placed station
  (the Generator ADR's GE2, #796). Since #770 (the cooking ADR's CE1, CE6) such an intent names a station or an
  item, exactly one (else `bad_args`); a station of a display kind is refused `nothing_to_do` as an unknown one, so
  no owner's rule receives it; an intent naming an item goes only to the first rule of its kind's `target_actions`
  (an unknown item, or none there: `nothing_to_do`), never to the role's or the mode's, which are written for
  station targets.
- **Win conditions** (`WinCondition`: a side and its conditions) are checked in the mode's order, in phases whose
  spec says so (Round in the base mode): after every fact, and at the end of every step (a command, a tick, a phase
  entry). The first that holds reports `won(side)`, and once a step has an outcome no win condition is checked again
  in it. Its `id` reaches every player as `MatchEnded`'s reason (#548): which condition held must be a fact every player
  may learn. The check after every fact orders the effects of one command (§3.4): the last crew member leaving raises
  `player_left` before its package drops into its circle, so "no crew present" is reported first, while a death's
  `player_died` meets no win condition and the dropped package then delivers. The check at the step's end catches a
  change that raised no fact.
- **Outcomes** come from phase classes, win conditions and `ReportOutcome`; the first in a step wins (§3.1). An
  outcome and its argument reach no peer: `PhaseChanged` names only the new phase, and only an event that a
  transition action emits can carry the argument (`EndMatch`: the side of `won`, and the id of the win condition
  that reported it as the reason, #548), with that event's audience.
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
  with a channel the check warns about every such action. A `UseStation` emits what its task type's `use_emits()`
  lists, which the check counts: in a role's or the mode's rule, every task type's (any station may be named). A
  `HoldStation` emits what its task type's `hold_emits()` lists, counted the same way (#805).
- **Determinism.** Rules, conditions and effects run in data order, and players in peer-id order. A part that draws
  randomness names its RNG purpose in its data (§3.3), so a new part never shifts the draws of the others.

### 9.3 Kinds and where they live
The base classes and the kinds are in `core/content/` (the bot-scenario data classes in `core/content/scenario/`,
the tutorial's in `core/content/tutorial/`);
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
  (§3.5; own names since #550, `PlayerNames`); `MovementRule` (`core/movement/`) takes `MoveClaim`s, with the
  checks of §7.1 since 2d.
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
  with `belted`; beside a two-handed hand item a one-handed picked item goes onto the belt through `give`'s belt move,
  CE21, #771), `swap` (`Swapped`), `place` (an item comes to rest: `ItemPlaced`, then `item_rested`),
  `place_carried` (both slots, the hand's first: the life rule, 2g, places a dead player's items at its body after
  `player_died`), `drop_carried` (a leaving player's items to the floor below its last accepted
  position; the life rule calls it after the life state changed and `player_left` was raised) and `raise_rested` (`item_rested` for an item
  announced by its own event: after `ItemSpawned`, 2c's `SpawnItems` and 2f's Delivery deal call it with
  `Items.SPAWN`), plus, for a throw (#642, §7.1.16), `launch` (the item leaves the hand or belt into its flight) and
  `fallback_rest` (the floor below the thrower's feet); `FlightTicks` rests it through `place` with `Items.THROWN`.
  `free_markers` counts no item in flight. **The ground state and vanishing (#779; the cooking ADR, CD6 (c), CE3):** `lay` is the one writer of an item's ground state (its `ItemState.rest_tick` the tick it came to lie, and its `ItemState.moves`, a host-only move serial never sent, bumped there and by every lift, `lock`, `launch` and the take into a hand or onto a belt, so a part can tell an item still lying where it laid it from one lifted and laid again in the same tick: the photo camera's film, PE17, #781; `place` lays through it, and every later part that leaves an item lying calls `lay` or `place`, as `give`'s put-down at the feet and `lay_on_station` do, #771); `spawn` adds a new lying item (`MatchState.add_item`, then `lay`; `SpawnItems` and Delivery's deal use it), `lock` locks a delivered package (not lying, so it never vanishes), and `vanish` removes an item for good (`ItemVanished`, everyone; `MatchState.remove_item` frees its id, reused oldest first only once the counter has passed `MAX_ITEM_ID`, so a normal match never reuses one). `VanishTicks` (§9.4.5) vanishes what lay its kind's `ItemKind.vanish_seconds`; C1's cap (#770) calls `vanish` too. **Stations and sources (#771; the cooking ADR §2, CE4, CE5, CE19 to CE21):** `give` hands a new item from a source, or one locked on a station, to a player who makes room by §2's table (empty hands: into the hand; a one-handed hand item: to an empty belt, else put down at the feet, `put_down`; a two-handed hand item: the given item onto the belt, a full belt's item put down at the feet first, `ItemPickedUp`'s `belted` naming the given item; the feet are `WorldQuery.rest_position` from the eye straight down); a two-handed given item, or one carried or flying, is a rule error and nothing moves. `change_kind` turns an item into another kind where it is (`ItemChanged`, everyone; nothing when it already is that kind). `lock_at` locks an item at a station's spot (out of any hand or belt, not interactive, never vanishing; it emits nothing, the station's event announces it), and `lay_on_station` lays one on the ground at a station's spot through `lay`, interactive, raising `item_rested` with the cause `on_station` and no `ItemPlaced` (the station's event says where it went). The causes are constants there. Each condition names its own rejection
  reason as a constant.
- **Tasks** (`core/tasks/`, 2f #62; shared since #79): a task type marks a subtask done in its own task state, then
  calls `Tasks.subtask_done(ctx, task, detail)`, which emits that task's `TaskState` event (`TaskStateEvent`, not
  the task type's `TaskState` class; M4-5, E30: `Tasks.state_of`)
  and `TaskProgress` (everyone; `Tasks.progress` counts the subtasks done and in total over every task), then raises
  `subtask_done`. `Tasks.announce` emits every task's `TaskState` in id order; `DealTasks` calls it after the deal. `Tasks.all_done` is "every task done"
  for `AllSubtasksDone`. Delivery (`core/tasks/delivery.gd`, the greybox's by colours, with its task state as the inner class
  `Delivery.State`; the House's Delivery by meaning in `core/tasks/delivery_by_meaning.gd`, `DeliveryByMeaning.State`, #828) and the zone task (`core/tasks/zone_task.gd`, `ZoneTask.State`, #647) were the first task types.
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
  channel when its effect stops on a hit (`damage`, `Channels.interrupt_hit`, `ChannelEffect.stops_on_hit`: the
  raise does; a hold with `HoldStation.hit_stops` false, the lift's, goes on; #805); `knock_down`, `die` and `leave` first stop every channel the player runs or is the target of
  (a raise: `RaiseStopped`), so a raiser downed, a downed player giving up and either leaving all stop a raise.
  `LifeTicks` (`core/life/life_ticks.gd`), a tick system, calls `die` for each downed player whose
  `life_deadline` has come, and runs its `Respawn` (`core/life/respawn.gd`) for each dead one, in peer-id order
  (without a `Respawn` the dead stay dead); a raise pauses a knockdown by clearing `life_deadline` and keeping what
  was left in `PlayerState.knockdown_left` (M4-4), so `LifeTicks` sees no deadline then. A later weapon
  or a trap calls `damage`; the class is `LifeRules`, not `Life`, which would shadow `PlayerState.Life`.
  The instant kill (#806, the car repair ADR's RE6 and RD7) is `kill`: a living or downed player, invulnerable or
  not, goes straight to dead, everything else as `die` (its channels stop first, the body, `Died`, `player_died`, the
  drop at the body, the respawn time); a living player's health falls to 0 (its `SelfStatus` touched), with no
  `KnockedDown` and no `Correction`; a player neither living nor downed is a rule error. A part that kills from inside
  someone's command (the car's drop, from inside `Channels.interrupt`) never calls it there: it queues the victim
  (`kill_later`, RE17, in `MatchState`'s per-part state, which `ResetMatch` clears), and `settle_kills` kills the
  queued players in peer-id order, skipping one no longer living or downed (dead already, or left) with no rule
  error, and clearing the queue with no kill once the step has an outcome (`MatchContext.step_has_outcome`: a win
  recorded earlier in the same advance; RD16 (c), nothing dies after the outcome); kills a kill queues settle in the
  same call. `Match` settles after a command's dispatch, after the phase's own timers, after each tick system, after
  the clock ending and at the end of a phase's entry (each before the step's win check), `Channels.advance` after each
  channel's step, so a kill lands in the command or tick of its cause, after that command's or channel step's own
  events; a transition drops the queue (`drop_kills`, once the old phase has exited). `kill` itself is public but a
  part's hook never calls it in the middle of someone's command (RE17): it queues. `Strike` skips a target no longer
  alive at its turn (a defensive check behind the queue).
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
  **Channels on stations** (#805, the [car repair ADR](decisions/2026-10-10-car-repair-task.md)'s RE1 to RE5):
  - **The station:** `Channel.station` is the placed station a channel runs on, or -1. A station channel targets
    no player (target 0), so a knockdown of the peer whose number equals the station id never stops it.
    `Channels.station_of(ctx)` gives the channel's station while the channel's conditions are checked again or it
    ends. Otherwise it gives the `station` of the intent being handled, when the intent declares one (`Interact`),
    else -1. The station conditions read their station through it (`Stations.target_of`), so a hold passes its own
    re-check. `Channels.on_station` finds the channel on a station (at most one, `ChannelFree`).
  - **Endless channels:** a channel whose effect is endless (`ChannelEffect.is_endless`, false by default; RE3)
    counts its ticks but never completes. Only its stops end it, and its effect's `check` skips the `seconds`
    bound.
  - **The phase's end:** `Channels.stop_all` sets `Channel.phase_ended` on each channel before stopping it, so the
    effect can tell the phase's end from a let-go (RE4: the car comes down without a kill).
  - **Hits:** a hit stops the actor's channel only when its effect stops on a hit (`ChannelEffect.stops_on_hit`,
    true by default; `Channels.interrupt_hit`, from `LifeRules.damage`).
  - **The effect:** `HoldStation` (`core/tasks/hold_station.gd`, §9.4.2) is the one effect that starts a station
    channel. It hands each start, stop and completion to the task type owning the station's kind, through the
    hold hooks below.
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
| Item kind | a thing a player can hold, and what using it does; a display name (the HUD's hand or belt item), its spawn tag (empty for a kind no deal places, one only given or changed into: each part that places a kind on markers, `SpawnItems` and `Delivery's package, refuses one without a tag in its own check; the cooking ADR's CE18 (a), #780), and `hands` (1 or 2: a two-handed item never goes on the belt and refuses a swap; the slot model later loot builds on; M4-5), and `vanish_seconds` (0, never, or 1 to 3600: how long it may lie before it vanishes, `VanishTicks`, #779), `max_items` (0, no cap, or 1 to `MatchState.MAX_ITEM_ID`, a technical bound: the most of the kind at once, which `GiveItem` keeps by vanishing the loose one that lay longest, the cooking ADR's CE3, #770) and `target_actions` (its rules on an intent naming one of its items on the ground, `Interact`'s `item`, §9.2: a box's take, CE1, #770) | `ItemKind` | `content/items/` | Package, Knife; Wine, Oil, Gnome, Parasol (the House's Delivery, #828) |
| Task type | how its one shared task is dealt and done, with its own subtasks setting, `subtasks_setting` (in `TaskType` itself since #795, the Generator ADR's G0, #256's shared part: every type names a whole-number setting of the mode; `TaskType.check` refuses it empty or going below 0, a type adding only its own bound, the Generator's `switches`; tests: `tests/unit/content/task_type_subtasks_test.gd`); what it demands of the map; a `description` (M4-5; the mode check refuses an empty one; the task screen showed it until #253; nothing shows it since, the how-to card of #254 being wordless, §4.7.36); the spawn tags of the markers its items may lie at, `item_spawn_tags()` (none by default), whose rooms the map screen lights (#253, §4.7.33); the station kinds it places, `station_kinds()` (by default the reflection over its `StationKind` properties, in property order; a type that holds its kinds another way overrides it: `Stations`, `MarkerReader.floor_tags_of` (the floor-snapped tags), the mode check's ZE3 (§9.6), `CircleViews.station_kind` and `WireBudget` all ask it, so they see the same kinds; DE4 of the delivery-by-meaning ADR, #827); whether it can kill, `kills()` (false by default; true makes the mode check require `LifeTicks` with a `Respawn` wherever `Interact` is accepted, #806); the maps it plays on, `maps` (the paths of the mode's maps; empty, the default, every map; the mode check refuses a path the mode does not list; `DealTasks` and the demands leave a type out on a map it does not list, §9.4.4; the Generator ADR's GE15, #803) | `TaskType` subclasses, each with its `TaskState` (§9.1) | `content/tasks/` | Delivery (by meaning, the House's, §9.5.25), Delivery by colours (`colour_delivery`, the greybox's, §9.5.4) |
| Task station | a place where a task is done, placed by its task type | `StationKind` (spawn tag, radius, height, colour palette; `actions`, its rules on `Interact`, §9.2, #796; `display`, a station that is placed but never used, such as the cooking task's order and herb boards: `Match` refuses an `Interact` naming one `nothing_to_do` before any rule, and its check refuses `actions` on it, the cooking ADR's CE6, #770) | inside its task type (Delivery by meaning: in its `routes`, each route's `drop_off`, #828) | the delivery circle; a drop-off of Delivery by meaning (white, no palette; its station ids in `routes` order) |
| Win condition | which side wins, and when | `WinCondition` | `content/win_conditions/` | three (§9.5) |
| Interactable | a thing in the world that a player targets with an intent | v0: an item on the ground (`PickUp`). Fixed ones (a button) and bodies come with `Interact`, v1 (§9.8; stations first, for the Generator: its [ADR](decisions/2026-10-10-generator-task.md)); since #770 `Interact` may name an item on the ground too, routed to its kind's `target_actions` (a cooking box) | | packages and knives on the ground |
| Spawn point | where the deal may place something | `LevelLayout` in `core/content/` (2a): the markers by tag, in level order; `server/`'s marker reader (`MarkerReader`, 2j) fills it | markers in `levels/` (§9.6) | tags `lobby_player`, `round_player`, `package`, `knife`, `circle`, the House's `drop_*` (one marker each), the House's `switch` and `generator` (station scenes' use spots, #799), the House's photo tags `camera`, `photo_spot`, `film_box`, `printer`, `photo_board` (use spots) and `photo` (the printer's tray), `film` (the first film; #783), the House's cooking tags `order_board`, `herb_board`, `grill`, `place`, `herb_bed` (use spots) and the six `box_bun_*` and `box_patty_*` (the boxes; #774) |
| Bot scenario | a scripted match that exercises a mechanic | `BotScenario`, its steps and targets: data only, in `core/content/scenario/`; the runners in `tests/harness/` | `content/scenarios/` | §9.7 |
| How-to card | a task type's (or a Guide basic's) wordless card of 3 to 4 frames, which the client draws; not a rule: the host never reads it, and it is not in the mode or its content hash | `HowtoCard`, `HowtoFrame`: data only, in `core/content/howto/`; the client's `HowtoCards` finds them, `HowtoCardView` draws them | `content/howto/tasks/`, `content/howto/basics/` | §4.7.36 |
| Tutorial lesson | one of the tutorial's lessons: its plate's deck keys and keys, and what completes each of its one or two steps (trigger → conditions → the next step; `starts_when`, `on_start`, `done_when`); not a rule: the host never reads it, and it is not in the mode or its content hash | `TutorialLessons`, `TutorialLesson`, `TutorialStep` and the closed list of parts: the triggers `EventSeen`, `ClientSeen`, the conditions `OwnLife`, `OtherWithin`, `ItemKindIs`, `TasksDone`, the action `RequestStage` (a new one is an engine request); data only, in `core/content/tutorial/` (E64 (a)); the client's `LessonRunner` plays them | `content/tutorial/` | the nine lessons, §4.7.46 |

- **`PhaseSpec`**: the phase id; the phase class with its settings; the intents it accepts and from whom (a newcomer,
  any player, the living, the downed, the host; §3.1); its tick systems in order; whether it checks win conditions;
  whether the match clock runs; its voice rule; its level (the lobby or the map); whether snapshots are sent.
- **`Transition`**: from phase, outcome, to phase, and its actions (effects) in order, which see the outcome and its
  argument (`EndMatch` reads the side of `won`).
- **`GameMode`**: players (minimum, maximum); its match settings; `PlayerRules` (health, stamina, speeds, capsule);
  its sides (`SideSpec`: id and display name; `MatchEnded` names the winner's id, which the end screen shows as a deck line, §4.7.31); its roles; its item kinds; the
  lobby level and the maps (paths that `server/` loads); its actions and reactions; its task types and win
  conditions, in order; its phases, the first phase and the transitions. Validation (§9.1) refuses a role, side or
  item kind that a part names and these lists lack.
- **Task types are classes** with settings, not composed rules: Delivery's deal and its check depend on each other
  (which package belongs to which circle). The rules around a task (pick up, put down) are composed. A new task type
  is one new script: the class, with its `TaskState` as an inner class (§9.8). Its interface (#79):
  `deal(ctx)` deals one shared task of the type (nobody owns it) and reads the type's own subtasks setting
  (`subtasks_setting`);
  `add_demands(settings, players, into)` says what that one task needs of the map (per spawn tag and colours) for
  the fit check of §9.4; `on_fact`, `tick` and `emits` as before. A use of one of its stations (`Interact`, #796):
  `use_problem(ctx, task, station)` says why the type refuses it now (`unavailable` by default: a type whose
  stations nobody uses takes none), a query that changes nothing, only with a reason the type lists in
  `use_reasons()` (the cooking ADR's CE11, #780; [`unavailable`] by default; the mode check refuses a listed reason
  outside the wire's alphabet or `StationUsable.REASONS`); `use_station(ctx, task, station)` applies
  it (`UseStation`), writing the type's own task state; `use_emits()` lists the event classes it can emit (none by
  default), which ModeCheck counts for its role-reveal warning (§9.2). A hold at one of its stations
  (`HoldStation`, #805) calls `hold_started(ctx, task, station, channel)` once the channel runs, and
  `hold_stopped(...)` when it stops before completing for any reason (`channel.phase_ended` when its phase ended).
  It calls `hold_completed(...)` when a timed hold ran its seconds. All three do nothing by default. The type writes
  its own task state there and emits only what `hold_emits()` lists (none by default), which ModeCheck counts as it
  counts `use_emits()`. On a hold's re-check, `use_problem` says whether the hold may go on (`StationUsable`).
  `cap_tier(state, item)` ranks an item of a capped kind for `GiveItem`'s cap (#782, the photo ADR's PE10): the cap
  vanishes the loose item with the lowest tier first (the highest any task of the match gives it), 0 by default; a
  pure query, from public state only, since `ItemVanished` tells everyone which item went.

### 9.4 Parts (v0)

#### 9.4.1 Conditions and costs
(a failed one rejects an intent with its reason, which reveals only what the column says):

In the "Where" column, *actions only* marks a part that reads the actor (`Condition.reads_actor_state`): the mode
check refuses it in a mode reaction or a win condition, which run for no player (§9.2, #299). *Anywhere* marks one
that reads no actor and no target: an action, a reaction or a win condition. A part that reads no actor but needs the
rule's target (`Condition.needs_target`), which only an intent, a channel or a fact gives, is refused by the mode check
in a win condition and in a reaction whose fact does not carry that target (`Condition.target_facts`), #379: its row
names the facts that do.

| Part | Passes when | Settings | Rejects with | Where (§9.2) | Code |
|---|---|---|---|---|---|
| `ItemOnGround` | the rule's item (the intent's `item`: `PickUp`'s, or since #770 `Interact`'s, in an item kind's `target_actions`, where it, `InReach` and `InSight` check the targeted box) exists, lies on the ground (not in a hand or on a belt) and is interactive (not locked, as a delivered package is) | none | `unavailable`: whether an item is held or delivered is public | an action, or a reaction on `item_rested`, whose fact carries the item (reads no actor; needs an item): the mode check refuses it in a win condition and in a reaction on any other fact, which have no item (#379) | `core/items/item_on_ground.gd` |
| `InReach` | the item's rest position is within `reach_m` of the actor's last accepted position, its feet (§7.1) | `reach_m` (0.1 to 10; no default: the data sets it, the base mode 2) | `out_of_reach` | actions only: reads the actor | `core/items/in_reach.gd` |
| `InSight` | the line from the actor's eye (the floor it stands on at its last accepted position, `WorldQuery.stand_floor_below`, raised by `PlayerRules.eye_height_m`, or `crouch_eye_height_m` while crouched, #790; §7.1) to just above the item's rest position is clear (`WorldQuery.line_of_sight`) | none | `blocked` | actions only: reads the actor | `core/items/in_sight.gd` |
| `HoldsItem` | the actor has an item in hand (a belt item does not count) | none | `empty_hand` | actions only: reads the actor | `core/items/holds_item.gd` |
| `OverFloor` | there is a floor below the actor's last accepted position (`WorldQuery.floor_below` of it lifted, the point `Items.fallback_rest` asks): the base mode's `Throw`; ModeCheck requires it, not negated, in every rule with a `ThrowItem` (§7.1.16) | none | `no_floor`: only the sender's own position | actions only: reads the actor | `core/items/over_floor.gd` |
| `CarriesItem` | the actor has an item in the hand or on the belt: the base mode's `Swap` | none | `nothing_to_swap`: its own slots | actions only: reads the actor | `core/items/carries_item.gd` |
| `HandNotTwoHanded` | the actor's hand item, if any, is not two-handed (`ItemKind.hands` 2): a package carrier cannot draw a belted knife (V13) | none | `two_handed`: what it holds is public | actions only: reads the actor | `core/items/hand_not_two_handed.gd` |
| `ActorRole` | the actor's role is one of the listed (no MVP use) | `roles` | `not_allowed`: the actor knows its own role | actions only: reads the actor | not built: with the first mechanic that needs it (#34) |
| `AllSubtasksDone` | every task is done (`Tasks.all_done`): a task with no subtasks is done, and with no tasks it holds (the engineer's rule of 2026-09-30, #79) | none | (facts only) | anywhere: reads no actor | `core/win/all_subtasks_done.gd` |
| `NoneAlive` | no player of the side is present: each has left (M4-2: the downed and the dead still count; the name stays from "no crew alive"). A player's side is its role's; a player without a role of the mode is on no side, and with no player of the side it holds (the base mode's deal always leaves at least one crew member). It reads every player's role, which is hidden, but only as a win condition, whose `won` reaches no peer (§9.2) | `side` (a side of the mode) | (facts only) | anywhere: reads no actor | `core/win/none_alive.gd` |
| `ClockEnded` | the match clock has reached its end (`MatchState.clock_ended`, set when `Match` raises `clock_ended`); before `StartClock` there is no end | none | (facts only) | anywhere: reads no actor | `core/win/clock_ended.gd` |
| `Cooldown` (cost) | this player never paid this key, or at least `seconds` (in host ticks, toward zero, §3.3) passed since it last did; paying records the tick in `MatchState`'s cooldown table. Per player, not per item: a second knife does not skip it. | `key` (no default: the data names it), `seconds` (0 to 600; 0) | `too_soon`: its own timing | actions only: reads the actor | `core/combat/cooldown.gd` |
| `StaminaCost` (cost) | the actor's stamina, settled first (§7.1), is at least `amount`; paying spends it and emits `SelfStatus` (the actor, at the end of the tick). | `amount` (whole points, 0 to `PlayerRules`' stamina maximum) | `tired`: its own stamina | actions only: reads the actor | `core/stamina/stamina_cost.gd` |
| `TargetDowned` | the rule's target player (`Channels.target_of`: the intent's `target`, or the running channel's) is downed | none | `not_downed`: who is downed is public; `moving` for a downed target whose body is in motion (`PlayerState.motion`, KD4 (a), #847), as public as the snapshot's velocity | an action (and its channel) only (reads no actor; needs a target player): the mode check refuses it in a reaction or a win condition, since no fact carries a target player (#379) | `core/life/target_downed.gd` |
| `TargetInReach` | the target lies within `reach_m` of the actor: both last accepted positions, their feet (§7.1) | `reach_m` (0.1 to 10; no default: the data sets it, the base mode's raise 2) | `out_of_reach` | actions only: reads the actor | `core/life/target_in_reach.gd` |
| `TargetInSight` | the line from the actor's eye (`Items.eye_of`) to just above the target's feet (`Items.lifted`) is clear (§7.1), as `InSight` for an item | none | `blocked` | actions only: reads the actor | `core/life/target_in_sight.gd` |
| `ChannelFree` | the actor runs no channel, no channel targets the rule's target (`Channels.target_of`) and no channel runs on the rule's station (`Channels.station_of`), apart from the channel being checked again: one channel per actor, one per target (one raiser at a time) and one per station (one holder of the lift, one fitter at the car: the car repair ADR's RE2, RE9) | none | `busy`: every channel of the MVP is public (a raise: `RaiseStarted`; a hold: its task type's public events) | actions only: reads the actor | `core/channel/channel_free.gd`, per station too |
| `Channeling` | the actor runs a channel | none | `not_channeling`: its own state | actions only: reads the actor | `core/channel/channeling.gd` |
| `AtStation` | the actor's feet (its last accepted position, §7.1) stand inside the cylinder of the station the intent names, or on a channel's re-check the channel's (`Stations.target_of` through `Channels.station_of`, #805) (`StationState.contains`: the kind's `radius_m` and `height_m`); one cylinder means "at the station" for every station (the Generator ADR's GE3). On the re-check of a timed station channel (a fit) it also fails when the actor's last accepted claim is more than `MovementRule.PUSH_TICKS` old, there is none since a placement, or the actor stored more than `PUSH_TICKS` of credit since (ZE10 as the zone task's, §7.1.8); an endless hold is exempt (#805) | none | `out_of_reach`: its own position and the station's (`StationPlaced` is public) | actions on an intent that names a station (reads the actor; needs a station, which no fact carries): the mode check refuses it in a reaction and a win condition, and requires it in every rule with a `UseStation` or a `HoldStation` | `core/tasks/at_station.gd`, with the channel's station and the claim age |
| `StationInSight` | the line from the actor's eye (`Items.eye_of`) to just above the named station's marker (on a channel's re-check the channel's station, #805) (`Items.lifted`) is clear, as `InSight` for an item: a press through a thin wall is refused where the cylinder reaches through it (GE4) | none | `blocked`: the sender sees the wall too | as `AtStation` | `core/tasks/station_in_sight.gd` |
| `StationUsable` | the task type owning the named station's kind takes a use of it now (`TaskType.use_problem` empty); on a channel's re-check the channel's station, and `use_problem` says whether a running hold may go on (#805) | none | the type's own reason (`Condition.rejection_reason_in`, which asks `use_problem` again), one it lists in `TaskType.use_reasons()` and one of `StationUsable.REASONS` (#780, the cooking ADR's CE11): `unavailable` (only that the type takes no use of that station now), `wrong_item` (the station does not take what the actor holds), `empty_hand` (the use needs an item in the hand), `two_handed` (the use would put an item beside a two-handed one), and the photo task's (#781, PE16): `no_film` (the actor carries no film: its own carried items), `film_exposed` (every film it carries has a shot: its own carried items), `no_frames_left` (the loaded camera's film has every frame drawn: the camera's shots, which every `ShotTaken` told everyone), `nothing_to_print` (no film the actor carries has a shot: its own carried items, #782) and `no_photo` (the actor carries no photo: its own carried items, #782), and its `unavailable` the public task state (done, or the photo spot, which takes no use); each is public state of a station the actor has in reach and in sight and of what the actor holds, never a role (a reason outside either list is a match error and refused `unavailable`, as is an empty answer to the second ask, from a `use_problem` that is not a pure query; a negated one answers `not_allowed`) | as `AtStation`; the mode check requires it after `AtStation` and `StationInSight`, negated too (`not StationUsable` answers by the same `use_problem`), and refuses it, `AtStation` and `StationInSight` in a rule on an intent that names no station (a dead rule, #379) | `core/tasks/station_usable.gd`; its own reasons (`use_reasons`, `rejection_reason_in`; the photo task's five); `tests/unit/tasks/station_usable_test.gd`, `tests/unit/content/mode_check_interact_test.gd` |

#### 9.4.2 Effects in rules

| Part | What it does | Settings | Emits (audience); raises | Code |
|---|---|---|---|---|
| `TakeIntoHand` | the item goes into the actor's hand; a one-handed hand item moves to an empty belt, any other hand item is swapped: it rests where the picked-up one lay (§7.1.11; the belt M4-5). Beside a two-handed hand item a one-handed picked item goes onto the belt instead, a full belt's item put down at the actor's feet first, the two-handed item staying in the hand (the cooking ADR's CE21, #771). An item not on the ground (a rule without `ItemOnGround`) is a rule error, logged, and nothing moves; the sender gets `Rejected` (`unavailable`) | none | `ItemPickedUp` (everyone, with `belted`: the item moved to the belt, the picked item itself when it went onto the belt, or none); for a swap `ItemPlaced` (swap, everyone), then `item_rested`; for a full belt's put-down beside a two-handed item `ItemPlaced` (`put_down`) and `item_rested` first | `core/items/take_into_hand.gd` |
| `SwapHands` | the actor's hand and belt items change places, either of which may be empty (`Items.swap`); run after `CarriesItem` and `HandNotTwoHanded`. One that would put a two-handed item on the belt (a rule without `HandNotTwoHanded`) is a rule error, logged, and nothing moves; the sender gets `Rejected` (`two_handed`). As every applied action, it stops the actor's raise first (§9.2) | none | `Swapped` (everyone) | `core/items/swap_hands.gd` |
| `PutDownInFront` | the hand item rests `distance_m` along the horizontal facing, stopped before a wall and dropped to the floor (`WorldQuery.rest_position` from the actor's eye, taken from the floor it stands on, §7.1.12); a facing with no horizontal direction puts it at the feet | `distance_m` (0.3 to 3; no default: the data sets it, the base mode 1) | `ItemPlaced` (put down, everyone); `item_rested` | `core/items/put_down_in_front.gd` |
| `ThrowItem` | the hand item leaves the actor's eye (`Items.eye_of`) into a flight (§7.1.16): the claimed facing normalized, else the last accepted claim's, times `speed_mps`, without the actor's velocity; the fallback rest below its feet is asked once (`Items.fallback_rest`). Only in an intent's rule, after `HoldsItem` and `OverFloor` (ModeCheck requires both); over no floor anyway it logs an error and throws nothing. A phase that accepts such an intent lists `FlightTicks` | `speed_mps` (1 to 40), `gravity_mps2` (1 to 40), `radius_m` (0.02 to 0.5 and at most `ThrowItem.largest_radius` of the mode's `PlayerRules`), `longest_flight_s` (0.5 to 30); each defaults to 0, so the data sets it; the bounds are placeholders, "not a decision" | `ItemThrown` (everyone); the flight's rest: `ItemPlaced` (thrown) through `FlightTicks` | `core/items/throw_item.gd` |
| `Strike` | picks the targets as in §7.1.10 (living, never downed, never invulnerable (M4-3), not the attacker, within reach and half the angle, overlapping vertically, in line of sight from the eye) and damages each through the life rule (`LifeRules.damage`), in peer-id order, skipping one no longer alive at its turn (#806, a defensive check behind the kill queue: what an earlier target's damage set off downed or killed it); at 0 health a target is knocked down there (M4-2), and on a map `PlayerRules.motion_maps` lists launched (KE9): `launch_mps` away from the attacker horizontally, foot to foot (along the zone's direction where they coincide), plus `launch_up_mps` up; a knockdown on another map drops the launch | `angle_deg` (1 to 360), `reach_m` (0.1 to 10), `damage` (whole points, 1 to 1000); no defaults: the data sets them (the knife 30, 1.5, 50); `launch_mps` (0 to 20) and `launch_up_mps` (0 to 10), 0 launching nothing, the default (bounds placeholders, "not a decision", KD9 (b); the knife 4 and 2, placeholders, 728e) | `Swung` (everyone), even with no target, before any damage; per target `Damaged` and `SelfStatus` (the victim). A knockdown: `KnockedDown` (everyone), `Correction` (the downed), and on a listed map `LaunchBody` (server, #847); nothing drops (M4-2) | `core/combat/strike.gd` |
| `RaiseDowned` (a `ChannelEffect`) | the raise (§7.1.8): starts a channel of the actor on the downed target; its rule's conditions are checked again every tick (`ChannelTicks`). Start: the target's knockdown pauses (`PlayerState.knockdown_left`) (it holds still, as every knocked-down player does, §7.1.7). Stop (a condition failing, any applied action of the raiser, the raiser hit, downed or leaving, the target giving up or leaving): the knockdown runs on from where it paused. Completion after `seconds`: `LifeRules.revive` with `revive_health`, a placement (#728 KE6) | `seconds` (0.05 to 600; the base mode 3), `revive_health` (whole points, 1 to `PlayerRules.health`; the base mode 50, E27); no defaults: the data sets them | `RaiseStarted`, `RaiseStopped` (no cause), `Revived` (everyone); the revived player's `Correction` and `SelfStatus` | `core/life/raise_downed.gd` |
| `Die` | the actor, downed, dies at once (`LifeRules.die`): a raise of it stops first; the body, `player_died`, the drop of both slots at the body, the hand item first. A living actor is a rule error, logged | none | `RaiseStopped` (when raised), `Died` (everyone), per dropped item `ItemPlaced` (death, everyone); `player_died`, `item_rested` per item | `core/life/die.gd` |
| `Respawn` (held by `LifeTicks`, not by a rule) | the actor, dead, comes back at a marker of `tag` in the current level, drawn uniformly with its RNG purpose from the free ones (no living or downed player within `PlayerRules.respawn_free_m` of it); from all of them when none is free (the engineer's answer 5 on PR #133); then `LifeRules.respawn` (§9.3). A marker missing is a rule error, logged | `tag` (`respawn`), `rng_purpose` (`respawn`); no defaults: the data sets them. Demands: one `tag` marker on every map, which the layout check and the lobby's fit check sum through `LifeTicks` | `Respawned` (everyone), `Correction` (that player), its `SelfStatus` at the end of the tick | `core/life/respawn.gd` |
| `ReportOutcome` | reports `outcome` in the current phase with `argument` (a button in the level, say; the tutorial's `NextStage` rule reports `next`, `docs/design/tutorial.md` §2.4); the row's actions read the argument as `MatchContext.outcome_argument` (null when empty). The first outcome of a step wins (§3.1). Mode check: an outcome named (the existing check wants a row for it in every phase that accepts the rule's intent). As a row's action it is a row error (`Match.report_outcome`) | `outcome`, `argument` (an id, empty for none; unused by the tutorial) | an outcome (§3.1), which reaches no peer (§9.2); no event of its own | `core/match/report_outcome.gd` (`tests/unit/match/report_outcome_test.gd`), over the rule runner's outcome reporting |
| `UseStation` | hands the named station to the task type owning its kind (`TaskType.use_station`), which alone writes its task state (§9.1) | none | what the type's `use_emits()` lists (none by default; the Generator's `SwitchChanged`, `ButtonPressed` and its progress, G4); the mode check requires `AtStation`, `StationInSight` and `StationUsable` in its rule, allows it only on an intent that names a station, and counts `use_emits()` for the role-reveal warning (§9.2) | `core/tasks/use_station.gd` |
| `HoldStation` (a `ChannelEffect`) | a channel of the actor on the station the intent names (`Channel.station`, §9.3; the car repair ADR's RE1 to RE5): the actor holds E there for `seconds` (a fit at the car) or with no end (`endless`: the lift's hold, which only its stops end). Its rule's conditions run again every tick with the channel's station, so walking out of the cylinder or out of sight, or a `use_problem` the type now returns, stops it; `StopRaise` and every other stop of `Channels` stop it too. It hands its start, stop (`Channel.phase_ended` at the phase's end) and completion to the task type owning the station's kind (`TaskType.hold_started`, `hold_stopped`, `hold_completed`), which alone writes its task state | `seconds` (0.05 to 600 when timed; 0 when endless, else a check error), `endless` (false), `hit_stops` (true: a hit of the actor stops it; the lift's hold sets false, RD10 (c); a knockdown stops it either way) | what the type's `hold_emits()` lists (none by default); none itself. The mode check requires `AtStation` and `ChannelFree` in its rule (one holder per station, RE9), `StationInSight` too, and `ChannelFree` only after `AtStation` and `StationInSight` (as `StationUsable`: its `busy` must not tell a player anywhere that another holds a station), allows it only on an intent that names a station, counts `hold_emits()` for the role-reveal warning (§9.2), and refuses a phase that accepts its intent without `ChannelTicks` | `core/tasks/hold_station.gd` |
| `GiveItem` | a new item of `kind` comes to the actor from the rule's target (the cooking ADR's CE2, CE3: a box's take): spawned at the position of the item the intent names, else of the station it names, then given (`Items.give`, which makes room: the hand item to the belt, or a full belt's item down at the feet; beside a two-handed hand item onto the belt, CE21). The cap: with `kind.max_items` items of the kind in the match, the loose one (on the ground) the cap ranks first vanishes first: the lowest `TaskType.cap_tier` (the highest any task of the match gives it; 0 by default; the photo task's PE10 tiers, #782), then the one that has lain longest (the earliest rest tick, then the lowest id) (`Items.vanish`), so a take is never refused for spam; with none loose (every one held, locked or flying) it refuses `unavailable` through `RuleEffect.refusal`, before anything is paid (§9.2). The given item never rests (no `item_rested`). Its body is the static `give_new(ctx, kind, position)`, which a task type calls for a source that is a station (Cooking's herb bed, C4); its cap step is the static `make_room(ctx, kind)`, which a task type calls before a spawn of its own (the photo task's print, #782) | `kind` (one-handed, capped and listed in the mode's `item_kinds`: its check refuses a two-handed kind, one without `max_items` or an unlisted one) | `ItemVanished` (the cap), `ItemSpawned` (no station), then what `Items.give` emits (`ItemPlaced` and `item_rested` for an item put down at the feet, `ItemPickedUp`), all to everyone; the mode check allows it only in an action on an intent that names a target (`Interact`), never in a reaction or a row, which have no actor, and only after the conditions that make the host check the actor's reach and sight (`GiveItem.required_conditions`, in the refusal order of §2: in an item kind's `target_actions` `ItemOnGround`, `InReach`, `InSight`; in any other rule `AtStation`, `StationInSight`), else it is an error naming the missing class (`ItemTargetCheck`) | `core/items/give_item.gd` (`tests/unit/items/give_item_test.gd` on `FixtureGiveModes`) |

#### 9.4.3 Transition actions
(effects that a transition row runs; the base mode's rows are in §9.5):

| Part | What it does | Settings | Emits (audience) | Code |
|---|---|---|---|---|
| `DealRoles` | each quota in order draws its players from the present players not drawn yet, taken in peer-id order and shuffled with its RNG purpose; everyone else gets the default role. Roles forced by a debug command or a scenario (debug builds only, §8) come as data, because `core/` cannot tell a debug build: the command `ForceRole` (peer, role id; an empty id clears it), which only `server/`'s debug path (from M3 also built from peer 1's debug-kind message, §4.3 E17) or the scenario runner sends, in any phase and after the peer connected, since ENet names a peer only then; it sets `MatchState.forced_roles`, which `ResetMatch` keeps, for the deals that follow, and is in the command log like every command; a role the mode lacks is a match error and ignored. Each present peer with a forced role gets it before the draws, and a forced role counts toward its quota (the engineer's answer A on #30: `dissidents` 1 with bot 2 forced to dissident makes bot 2 the only dissident), so a quota draws its count minus the players forced to its role, never below 0; a forced role the mode lacks is a match error and ignored (2j) | `quotas` (`RoleQuota`: role, `count_setting`, `leave_at_least` (0 to 10; class default 0, the mode writes its number): the count is max(0, min(setting, N − leave_at_least)), and never more than are left), `default_role`, `rng_purpose` (`roles`) | `RoleAssigned` (that player), in peer-id order; then, per role of the mode that knows its teammates and has players, in the mode's order, `Teammates` (every player of that role); a forced role is told like a drawn one | `core/deal/deal_roles.gd`; forced roles in `tests/unit/deal/deal_roles_test.gd` |
| `DealTasks` | draws `tasks_setting` different task types at random (`rng_purpose`) from the mode's task types that play on the match's map (`TaskType.maps`, #803: `pool_of` takes the map) minus those in `banned_setting`, and runs each drawn type's `TaskType.deal` once, in the mode's order (§9.5, Delivery): one shared task each, owned by nobody (#79). Then each task's `TaskState` in id order (M4-5, E30: `Tasks.announce`) and `TaskProgress`. More tasks than the map's types left deals that map's whole pool, with no error (a map may play fewer types than another, GE15); more than the types left after the bans on every map (a check that did not run) is an error, and it deals the map's pool. Its demand is for its `Demands`' map (§9.4.4), and with `tasks` above 0 and no type left on that map it sets `Demands.no_task_types`, which the fit check refuses (`no_task_types`). Refuses in `ChangeSettings` (`settings_problem`, whatever the map, #79): `tasks` above the types not banned, or every type banned (`out_of_bounds`). Mode check: `tasks_setting` a whole number whose maximum is at most the mode's task types, `banned_setting` a set of task types, `rng_purpose` not empty | `tasks_setting` (`tasks`), `banned_setting` (`banned_task_types`), `rng_purpose` (`task_types`) | the task types' events (Delivery: `StationPlaced`, `ItemSpawned`), then `TaskState` per task and `TaskProgress` (everyone) | `core/deal/deal_tasks.gd`, shared, drawn and per map; tested with fake task types, per map in `tests/unit/deal/deal_tasks_maps_test.gd` on `FixtureMapTaskModes`, the fit check in `lobby_phase_bans_test.gd`, the path check in `mode_check_test.gd` |
| `SpawnItems` | places `count_setting` items of `kind` on distinct random markers of the kind's spawn tag, skipping the markers where an item already rests (at most one item per marker in a deal, such as a package of Delivery's deal on a shared tag), into `MatchState`'s items; ids follow the markers' level order. Too few free markers (a fit check that did not run) is an error, and it places none. The mode check refuses a `kind` without a spawn tag (an item kind may have none, the cooking ADR's CE18 (a), #780) | `kind`, `count_setting`, `rng_purpose` (`knives`) | `ItemSpawned` (everyone), in id order; then `item_rested` (spawn) for each, in id order | `core/deal/spawn_items.gd` |
| `PlacePlayers` | places every player at a distinct random marker of `tag` (§3.2); with `ordered` the players in peer-id order onto the markers in level order, with no draw (the host's player, peer 1, on the first: the tutorial's deal, `docs/design/tutorial.md` §2.5). Too few markers, or no layout, is a rule error and places nobody | `tag`, RNG purpose (`spawns`; not required when `ordered`), `ordered` (false: the draw) | `PlayersPlaced` (everyone); `Correction` with a new epoch (each player) | `core/placement/place_players.gd`. Its `ordered` setting is in `ContentHash.of` of every mode that places players, so a command log recorded before #599 refuses to replay |
| `KnockDown` | knocks down one present living player where it stands (`LifeRules.knock_down`); with `then_die`, `LifeRules.die` at once (the body, the drop of both slots at it). `pick` 0 is the host's player (peer 1), n the n-th present player other than peer 1 in peer-id order. A pick that names nobody present, or a player who is not alive, is a rule error during the row (`Match.row_error_count`, so `HostSession` ends the session, §4.5.11), exactly one, and nothing happens: `then_die` only kills a player this action downed (so `die`'s own error cannot follow a successful knockdown). Without `then_die` only a `LifeTicks` of the phase entered runs the knockdown out; mode check: a **warning** on a row whose `KnockDown` without `then_die` enters a phase with no `LifeTicks`, where the downed stays downed for good. The tutorial's `raise_stage` is the intended case (`docs/design/tutorial.md` §2.3: lesson 6 waits however long the player takes to raise the stand-in). Mode check: `pick` 0 to the mode's maximum players minus 1; an **error** on a row whose `KnockDown` changes the level (`Match` switches the world to the entered phase's level before a row's actions run, so the floor asked would be a level the player is not in): only on a row that stays on one level | `pick` (whole, class default 0), `then_die` (class default false) | `RaiseStopped` (everyone, for a channel involving the player: none in a row, which stops every channel first), `KnockedDown` (everyone), `Correction` (the downed); with `then_die` `Died` (everyone) and per dropped item `ItemPlaced` (death, everyone); facts `player_died`, then `item_rested` per item. No new event or audience | `core/life/knock_down.gd` (`tests/unit/life/knock_down_test.gd`, `tests/unit/content/mode_check_stage_test.gd`) |
| `StartClock` | sets the match clock's end to now plus the setting (whole minutes, in ticks toward zero: 10 min is 12000); alone on the row into the round (`Pregame, pregame_done → Round`, #213), so the round's `PhaseChanged` announces the end tick. In a debug build a `ForceClock` (`MatchState.forced_clock_s`, in seconds) replaces the setting (§8, §9.7 `clock_s`). It records the clock's length (`MatchState.clock_ticks_total`, for `EndMatch`'s time, #548). Mode check: a whole-number setting (not a set of ids) whose minimum is at least 1, since a 0-minute clock never ends | `minutes_setting` (`match_duration`) | `RoundStarted` (everyone), with the start tick | `core/win/start_clock.gd` |
| `EndMatch` | records the side of the `won` outcome as the winner (`MatchState.winner`). An argument that is no side of the mode is a rule error, logged, and nothing is recorded or emitted | none | `MatchEnded` (everyone): the side and, when a win condition reported the `won`, its id as `reason` with the round's play time (`numbers.time`, whole seconds the clock ran; none when it never started), #548 | `core/win/end_match.gd` |
| `ResetMatch` | resets the match state from the roster: items, stations, tasks and their task states, bodies, roles, life, health, stamina, cooldowns, counters, per-part state, the clock and the winner; drops the players who left; keeps the session's join count (§3.5); everyone un-ready; the settings and shortfalls for the players still present (`FitCheck`), as a leave in the lobby sends them (#737). Runs before the row's `PlacePlayers` | none | `ReadyChanged` (everyone), per player; then `SettingsChanged` (everyone) | `core/match/reset_match.gd`, with the resent shortfalls (`tests/unit/match/reset_match_test.gd`) |

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
The price is a stricter check than a given draw needs when the types' demands differ. A map is asked only for the
types that play on it (`TaskType.maps`, the Generator ADR's GE15, #803): a `Demands` carries the map it is for
(`Demands.new(mode, map)`; `LayoutCheck.demands_of`'s `map`), and `DealTasks` draws its pool from the types that play
there; an empty map (`WireBudget`'s worst case) asks every type. So the fit check asks the lobby's chosen map, and
`LayoutCheck`'s load check each map at the defaults, only for its own types' markers; when *tasks* asks for tasks
and no type is left on the map after the bans, `DealTasks` sets `Demands.no_task_types` and the fit check refuses
the map with `no_task_types` (no arguments: `SettingsChanged` names the map, as `no_layout`). Since #800
`LayoutCheck`'s load check refuses it too at the defaults (no bans): a map of the mode no task type plays on is a data
mistake that fails `check` (`deal_tasks_maps_test.gd`). `all_ready` (2b,
`FitCheck`) sums the demands per tag over every row into a phase on the map and the tick systems of the phases
played on it (per tag, the most that any one of those phases needs; `LayoutCheck.demands_of`), compares
each sum with the chosen map's markers of that tag and each colour count with its palette (`Demands.shortfalls`,
§3.2, §9.6), checks the player count against the mode's bounds, and `SettingsChanged` shows them.

An exact demand (#797, the Generator ADR's GE10): a demand of a spawn tag may be exact (`Demands.add_markers(tag,
count, true)`, kept in `Demands.exact`), which asks for that many markers of the tag, no more and no fewer, whatever
the settings and the players: the Generator asks for exactly one `generator` and exactly `switches` `switch` markers,
because every switch device of the map is either an active switch's station or a fixed switch. The exact set survives
`DealTasks`' sum over its pool and `LayoutCheck.demands_of`'s merge of the tick systems' demands; `Demands.shortfalls`
gives `markers_exact` (`need`, `have`; §4.7.45) for any other count of an exact tag, and `LayoutCheck`'s load check
refuses such a map at the defaults (`_check_exact`), so a mode with one never starts on it. A task type's own
problems with a layout come after the marker shortfalls (#807, RE14): `Demands.task_types` records the pool
`DealTasks` sums, and `FitCheck.shortfalls` appends each type's `TaskType.layout_problems(layout)` (none by default;
the car repair's `short_axis`, a `car_end` marker nearer the `car` marker than the car kind's radius; the photo
task's `photo_spot_near`, a photo spot within reach of the camera, #781, §9.5.22); `WireBudget`
sizes `SettingsChanged`'s shortfalls by each type's `most_layout_problems()`.

#### 9.4.5 Tick systems, phase classes and voice rules

| Part | Kind | What it does | Settings | Emits (audience) | Code |
|---|---|---|---|---|---|
| `LifeTicks` | tick system | each downed player whose knockdown time has run out (`PlayerState.life_deadline`) dies (`LifeRules.die`), and each dead player whose respawn time has run out respawns through `respawn` (M4-3), in peer-id order; a downed player being raised has no deadline (M4-4: the raise keeps what was left). Before the deadline it counts each body in motion (`LifeRules.count_motion`, every tick, reports or not): once a motion has lasted `PlayerRules.longest_motion_s` it ends as at rest, on the standing floor under its capsule, or with no floor at the fallback (the floor below where it was knocked down) with an error; either way `StopBody` (#847, KE15). A phase whose rules can knock a player down (an accepted intent's action or a reaction with an effect that emits `KnockedDown`: a `Strike`) lists it, or the mode check refuses the phase (M4-3). A mode with a task type that can kill (`TaskType.kills()`, the car's drop) lists it with a `respawn` in every phase that accepts `Interact`, or the mode check refuses the phase (`KillCheck`, #806, the car repair ADR's RE6): a dead player always comes back | `respawn` (a `Respawn`, or none: the dead stay dead); the knockdown and respawn times are `PlayerRules.knockdown_s` and `respawn_s` (E27) | a motion's end: `StopBody` (server); a death's `StopBody` if it moved, `Died` (everyone), then the dropped item's `ItemPlaced` (death, everyone); the facts `player_died`, `item_rested`; a respawn's events. Demands: its `Respawn`'s | `core/life/life_ticks.gd`, with the respawn |
| `ChannelTicks` | tick system | each running channel, in actor-id order: its rule's conditions again (not its costs), the first failing one stopping it; else one more tick, and the tick that reaches its time completes it (`Channels.advance`), unless its effect is endless (`ChannelEffect.is_endless`, #805: it never completes). A phase that accepts an intent whose rule starts a channel lists it, or the mode check refuses the phase | none | what the channels' effects emit when they stop or complete (the raise: `RaiseStopped`, `Revived`, `SelfStatus`) | `core/channel/channel_ticks.gd` |
| `FlightTicks` | tick system | each item in flight, in id order, except in its launch tick: one more tick flown and the swept segment between the arc's two points; the world's contact or a living player's other than the thrower (its capsule widened by the item's radius) ends the flight, as does its longest flight; the item rests on the floor below the stop through `Items.place` (cause `thrown`), or at the flight's fallback below the thrower's feet, with an error logged (§7.1.16). A phase that does not list it pauses every flight; a phase that accepts an intent whose rule throws (a `ThrowItem`) lists it, or the mode check refuses the phase (#643) | none | `ItemPlaced`, and what the rules on `item_rested` emit | `core/items/flight_ticks.gd` |
| `VanishTicks` | tick system | each item of a kind with `vanish_seconds` that lies on the ground and has lain that long since `Items.lay` set its `rest_tick` vanishes through `Items.vanish`, in ascending item id (never the item table's order, which a reused id breaks): an item lying since tick r of a kind of s seconds goes in the first tick t of a listing phase with t - r at least `Ticks.from_seconds(s)`. A pick-up and a put-down start it over; an item in a hand, on a belt, in flight or locked never vanishes. A phase that does not list it removes nothing, and a later one that does removes at once what lay long enough meanwhile; a vanishing item on the ground with no rest tick is a rule error, logged once, and its clock starts at that tick. A mode with a vanishing item kind lists it in some phase, or the mode check refuses it | none | `ItemVanished` (everyone) | `core/items/vanish_ticks.gd` (`tests/unit/items/vanish_ticks_test.gd`, `vanish_replay_test.gd`, id reuse in `tests/unit/match/match_state_item_ids_test.gd`; no player in `ItemVanished`'s keys or wire row: `tests/unit/events/cooking_events_name_no_player_test.gd`, the list the cooking events extend) |
| `TaskTicks` | tick system | runs the tick of each task type that has one, in the mode's order: the zone task's (§9.5.18, #647), the Generator's (§9.5.19, #797: a held progress event, then the charge; Delivery has none) and Cooking's (§9.5.20, #773: the grill's patty turning fried, then burnt). `ModeCheck` refuses a mode with a ticking task type where no phase lists it | none | the task types' events | `core/tasks/task_ticks.gd`; the ticking types: the zone task, the Generator, Cooking |
| `Lobby` | phase class | allows joins; `Hello` (the join, §3.5), `SetReady`, `ChangeSettings`, `SetProfile` (#551: name and body colour, §3.5; `out_of_bounds` also for a colour past the ten); leaves (§3.5); reports `all_ready` (§3.2) after a `SetReady`, a settings change (numbers and the bans of task types, #79), a leave and on entry. Rejects (§4.1): `wrong_version`, `full`, `bad_args`, `unchanged`, `unknown_setting`, `out_of_bounds` (a bound, an unknown task type id, or a row action's `settings_problem`), `unknown_map` | none | `Welcome` (the joiner); `PlayerJoined`, `PlayerLeft`, `ReadyChanged`, `SettingsChanged`, `ProfileChanged` (everyone); `AllowJoins`, `DisconnectPeer` (server); `Rejected` (the sender) | `core/match/phases/lobby_phase.gd`, with `SetProfile` |
| `Countdown` | phase class | as Lobby for joins, leaves and `SetReady(false)`, each reporting `cancelled`; `countdown_done` on its end tick, `seconds` after entry | `seconds` (0 to 60; the class default 0) | as Lobby, and `CountdownCancelled` (everyone); its end tick goes out in `PhaseChanged` | `core/match/phases/countdown_phase.gd` |
| `Loading` | phase class | refuses joins; `LoadMatch`; takes `LoadAck`s (another match's dropped, a second `unchanged`); at the deadline drops who did not confirm, never the host; a leave drops too; reports `all_loaded` | `deadline_seconds` (5 to 600; required, since a missing deadline would drop every client at once) | `LoadMatch`, `PlayerLoaded`, `PlayerLeft` (everyone); `Disconnecting` (the dropped player, M4-6); `RefuseJoins`, `DisconnectPeer` (server) | `core/match/phases/loading_phase.gd` |
| `Round` | phase class | nothing of its own: its intents go to rules, a leave to the life rule (§3.5, `LifeRules.leave`; a newcomer's leave is forgotten); a connection gets `DisconnectPeer` (2b) | none | `DisconnectPeer` (server); a leave: `PlayerLeft` (everyone), `player_left`, the drop's `ItemPlaced` (leave, everyone) and `item_rested` | `core/match/phases/round_phase.gd`, with the leave |
| `Pregame` | phase class | `pregame_done` on its end tick, `seconds` after entry (#213); nothing else of its own: the data makes it silent and frozen (§3.6); joins refused (a connection gets `DisconnectPeer`); a leave as Round's (`LifeRules.leave`, §3.5) | `seconds` (0 to 60; the class default 0) | `PlayerLeft` (everyone), as the life rule's leave; `DisconnectPeer` (server); its end tick goes out in `PhaseChanged` | `core/match/phases/pregame_phase.gd` |
| `End` | phase class | `back` on its end tick, `seconds` after entry, or earlier on `ReturnToLobby` from the host; with no `seconds` it has no end tick and waits for `ReturnToLobby`, which no screen offers (a dead end for the host: a mode sets `seconds`); a leave sets life `left` (§3.5); a connection gets `DisconnectPeer` | `seconds` (0 to 60; absent: no end tick) | `PlayerLeft` (everyone); `DisconnectPeer` (server); its end tick goes out in `PhaseChanged` | `core/match/phases/end_phase.gd`, with the end tick |
| `Silent` | voice rule | nobody hears anybody; its hearing radius is 0 | none | the routing per tick (§5) | `core/voice/silent_voice.gd` (`SilentVoice`), with its radius (§9.4.6) |
| `Proximity` | voice rule | every pair of present players within the radius (3D, §6), under the voice invariant (§6.3, for every rule): nobody hears the downed or the dead; its hearing radius is `radius_m` | `radius_m` (0.5 to 100; the class default 0, which the mode check refuses) | the routing per tick | `core/voice/proximity_voice.gd` (`ProximityVoice`), with its radius (§9.4.6) |
| `RoundVoice` | voice rule | a living or downed listener hears a living speaker within `living_m`, measured from the listener's last accepted position (where a downed player lies); under the voice invariant nobody hears the downed or the dead, the dead hear nobody, and a player who left hears and is heard by nobody (§6); its hearing radius is `living_m` | `living_m` (0.5 to 100; the class default 0, which the mode check refuses) | the routing per tick | `core/voice/round_voice.gd`, with its radius (§9.4.6) |

#### 9.4.6 A voice rule's hearing radius (M5-1, #215; E41)
Every voice rule answers `hearing_radius_m()`, the farthest it
routes a voice (3D, its edge included), 0 when it routes nobody; `VoiceRule.radius_of(rule)` gives 0 for a phase with
no voice rule. The client fades a voice to silence there and the leak test fails any frame from farther away (§5,
§6), so a new voice rule returns the radius its `hears` uses; one that routes past it fails every scenario where
players stand beyond it. `VoiceRule.speakers_of` reads each player's last accepted position once per call and asks
`hears_at(state, listener, speaker, listener_at, speaker_at)`, which defaults to `hears` (#1282): a rule that measures
distance (`ProximityVoice`, `RoundVoice`) overrides `hears_at` and compares the positions handed in with
`VoiceRule.within_at`, the comparison `within` makes, its `hears` reading the positions and calling `hears_at`.

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
Code: the files that hold it. Tests: path.
```

The task or PR that built an entry is in its ADR's Consequences (stage 2's: the content API v0 ADR), never here.

#### 9.5.1 Base mode (game mode)
What it does: the MVP match, Lobby → Countdown → Loading → Pregame → Round → End → Lobby (§3.2).
Settings:
- Written in `content/modes/base_mode.tres`, over neutral class defaults (0), so the designer sees every number
  there (the engineer's answer on #49): players, the match settings and the phase settings. The Godot saver drops
  a value equal to its class default, so a bound of 0 (`dissidents` and `knives` from 0) is the default itself.
- players 1 to 10. One player may start a match alone to try the mechanics and is then always Crew: the deal
  lowers `dissidents` to N − 1, which is 0 (the engineer's answer on #719: there is no minimum; a recommended size
  of 4 and up is only a hint, never enforced). Match settings, default (bounds): `match_duration` 10 min (1 to 60);
  `tasks` 5 (1 to 5: every type a map plays, in every match, the Generator ADR's GD7 (i), the photo ADR's PD14 and the car repair ADR's RD13 (d): the House's Delivery, Generator, photo task, Cooking and car repair; the greybox deals its one Delivery, as `DealTasks` deals a smaller pool whole; #810, #775, #784, #800, #828, #79); `banned_task_types` (a set of task types, empty;
  a host may ban any type: `ChangeSettings` refuses a ban that leaves fewer types than `tasks`, or none (`out_of_bounds`); on a map whose pool a ban empties, the fit check at `all_ready` refuses the start, `no_task_types`. The House plays five types since #810 (four since #775, three since #784, two since #800): banning any but all of them leaves the rest, and banning all five (allowed once `tasks` is 1, as the greybox Delivery is left) empties its pool; the greybox plays one Delivery, so banning it empties the pool, #828); `packages`, both Deliveries' subtasks (items or packages), 6 (1 to 10, a placeholder, "not a
  decision"); `switches`, the Generator's subtasks (its active switches), 3 (2 to 4; its label "Active switches (Generator)" a placeholder, "not a decision", GD1; #800); `photos`, the photo task's subtasks (the photos to hang), 3 (1 to 5; its label "Photos (Photography)" a placeholder, "not a decision"; #784); `burgers`, Cooking's subtasks (its orders), 1 (0 to 3, the cooking ADR's CD1; its label "Burgers (Cooking)", the cooking ADR §5.1; #775); `car_parts`, car repair's subtasks (the parts to fit), 2 (1 to 3, the car repair ADR's RD2, a placeholder, "not a decision"; its label "Parts to fit", RD12; #810); `dissidents` 1 (0 to 9, lowered to N − 1 by the deal); `knives` 2 (0 or more; the map's `knife` markers bound it at `all_ready`).
- `PlayerRules`, value (bounds): health 100 (1 to 1000); stamina 100 (1 to 1000), regenerating 15 per second (0 to
  1000); walk 4.5 m/s (0.5 to 20); sprint 7 m/s (at least walk, to 30) for 20 per second (0 to 1000), from 20 (0 to the
  maximum); jump 1 m (0 to 5) for 10 (0 to the maximum); the downed hold still (§7.1.7) for
  a knockdown of 10 s (`knockdown_s`, 1 to 120; vision revision 1's numbers, M4-2, the bounds
  placeholders, "not a decision"); the dead respawn after 30 s (`respawn_s`, 1 to 300) at a `respawn` marker with
  no living or downed player within 1 m (`respawn_free_m`, 0 to 5) and are invulnerable for 3 s (`invulnerable_s`,
  0 to 30; M4-3, the bounds placeholders); capsule radius 0.4 m (0.1 to 1) × height 1.8 m (0.5 to 3); eye 1.6 m (below
  the height); step 0.3 m (0 to 1); the crouch (§7.1.17, the crouch ADR's KE2, #790): crouched height 1.2 m
  (`crouch_height_m`, twice the radius to the height), crouched eye 1.0 m (`crouch_eye_height_m`, below the crouched
  height), crouch walk 2.0 m/s (`crouch_speed_mps`, 0.1 to the walk) and with Shift 2.8 m/s (`crouch_fast_speed_mps`,
  the crouch walk to the walk), playing everywhere (no per-map list since #991, the engineer's change on #989).
  A knockdown moves the body on the House alone (`motion_maps`, KE12 (a), #847: each one of the mode's
  maps, empty is every map),
  and the motion rests once the host's reports stay under 0.1 m/s (`rest_speed_mps`, 0.01 to 2) for 0.5 s (`rest_s`,
  0.05 to 5, counted in reports), or after 8 s at the longest (`longest_motion_s`, the rest time to 60): placeholders,
  "not a decision" (KD9 (b)), as are their bounds. Health and stamina are whole points here, thousandths inside `core/` (§3.3).
  `PlayerRules`' class defaults are 0,
  so each number is written in `base_mode.tres` (`PlayerRules_base`), and a mode that leaves one out fails the mode
  check (2d, #60; the engineer's answer (1) on #58). Pushing (§7.1.6) is not in `PlayerRules`: `push_speed_factor`,
  `push_side_bias` and `push_max_overlap` are client feel tuning in `client/player/player_tuning.tres` (engineer),
  placeholders, never checked by the host; every client must ship the same values.
- Sides: `crew` ("Engineers"), `dissidents` ("Dissidents"). Roles: `crew` ("Engineer"), Dissident. The ids stay
  `crew` (vision revision 1's names, M4-1). Item kinds: Package, Knife, and the House's Wine, Oil, Gnome and Parasol (#828, §9.5.25), Film and Photo (the photo task's, #784, §9.5.22), Cooking's 21 (#775, §9.5.20) and car repair's three parts (#810, §9.5.21).
- Actions: PickUp, PutDown, Throw (§7.1.16), Raise, StopRaise, GiveUp, Swap (below). Reactions: none. Task types: Delivery (by meaning, the House's alone, §9.5.25), Delivery by colours (`colour_delivery`, the greybox's alone, §9.5.4) (#828); the Generator (`generator`, the House's alone, §9.5.19, #800); the photo task (`photo`, the House's alone, §9.5.22, #784); Cooking (`cooking`, the House's alone, §9.5.20, #775); car repair (`car_repair`, the House's alone, §9.5.21, #810); Hold
  the zone (§9.5.18) until #842. Win conditions, in order: every task done, no crew present, time up.
- Phases (accepts; tick systems; win conditions; clock; voice; level): Lobby (§3.2; none; no; stopped; Proximity 8 m;
  lobby), Countdown 5 s (§3.2; none; no; stopped; Proximity 8 m; lobby), Loading 60 s (`LoadAck`; none; no; stopped;
  Silent; map), Pregame 3 s (nothing; none; no; stopped; Silent; map; #213), Round (`MoveClaim` from the living
  and the downed, `PickUp`, `PutDown`, `Use`, `Raise`, `StopRaise`, `Swap` and `Interact` (#800) from the living, `GiveUp` from the
  downed; LifeTicks with a Respawn (`respawn` markers, the RNG purpose `respawn`), ChannelTicks, FlightTicks, VanishTicks (#775), TaskTicks; yes;
  runs; RoundVoice; map), End 3 s
  (`ReturnToLobby` from the host; none; no; stopped; Silent; map). Snapshots in Lobby, Countdown and Round. RoundVoice's
  `living_m`: 8 m.
- Transitions: §3.2. Their actions: `Loading, all_loaded → Pregame`: `DealRoles` (Dissident by `dissidents`,
  leaving at least 1; default Crew), `DealTasks` (`tasks`, `banned_task_types`, `task_types`), `SpawnItems` (Knife
  by `knives`), `PlacePlayers` (`round_player`). `Pregame, pregame_done → Round`: `StartClock`. `Round, won →
  End`: `EndMatch`. `End, back → Lobby`: `ResetMatch`, `PlacePlayers` (`lobby_player`).

Produces: the events of its phases and parts. Visible to: as each of them says.
Code: `content/modes/base_mode.tres`. The mode check refuses an accepted intent
that no rule handles, so every intent a phase accepts comes with its rule (Round's `Use` with the knife's, §9.5.6).
Each map's lobby, guide and loading card list its own task type alone (DE16, §4.7.36, §4.7.42). The zone task's code,
its tests and the House's zones stay while the mode plays no zone task (the engineer's
[answer on #842](https://github.com/xperiaroco2/prime-game/pull/842#issuecomment-6110558513): "only from the mode,
now").
`FixtureBaseModeWithZones` (`tests/fixtures/tasks/base_mode_with_zones.tres`) is the base mode with Hold the zone
among its task types, its `zones` setting (1 to 1) and `tasks` 2 (1 to 2), read from the shipped one when it loads, for the
zone task's tests (not its scenarios, chaos or perf runs, which play without zones since #804). It leaves out the
Generator, its `switches` setting and Round's `Interact`, so the zone tests keep Delivery beside the zone; the photo
task and its `photos` setting (its Film and Photo kinds stay, unused); Cooking, its `burgers` setting and its item
kinds; and car repair and its `car_parts` setting (its part kinds stay, unused: no rule names them).
Tests: the mode check, the base mode's numbers and `End → Lobby` order, and the whole deal run by a match entering
the round (`tests/unit/content/content_modes_test.gd`, §9.1), which also plays a whole match from this data to the
end and back to the lobby, twice (the second time with no intent: End's 3 s, nobody heard on any of its ticks), and
a round with 0 dissidents set in its lobby; the phases with a mode built in code (`tests/unit/match/phases/`,
`tests/unit/match/reset_match_test.gd`, `tests/unit/content/layout_check_test.gd`); the scenarios in
`content/scenarios/` (`tests/scenarios/scenarios_test.gd`, §9.7), on the flat lobby and greybox of §9.6. The
Generator's content: `tests/unit/content/generator_content_test.gd` (§9.5.19); the photo task's:
`tests/unit/content/photo_content_test.gd` (§9.5.22). A lone player (#719): `tests/unit/content/lone_player_test.gd`
(Crew for 32 seeds at 1 and 9 `dissidents`, and a round alone in which no win condition fires in its first minute
and delivering every package wins it for the crew, `every_task_done`). Voice rules through the phases:
`tests/unit/voice/voice_by_phase_test.gd` (End silent on every tick until its return). End's end tick:
`tests/unit/match/phases/end_phase_test.gd`. The pregame (#213): §3.6.

#### 9.5.2 Crew (role)
What it does: the side that wins only when every task is done (§3.4).
Settings: id `crew`; display name "Engineer" (its side's "Engineers"; vision revision 1, M4-1); side `crew`; knows
its teammates: no; actions: none. The default role of `DealRoles`.
Produces: `RoleAssigned(crew)`.
Visible to: that player only (§5); `MatchEnded` names the winning side and the win condition, never a player's role.
Code: `content/roles/crew.tres`. Tests:
`tests/unit/deal/deal_roles_test.gd`, `tests/unit/content/content_modes_test.gd` (which pins both names).

#### 9.5.3 Dissident (role)
What it does: the side that wins when time is up or no crew member is alive; dissidents know each other.
Settings: id `dissident`; display name "Dissident"; side `dissidents`; knows its teammates: yes; actions: none.
Dealt by the quota `dissidents`, leaving at least one other player.
Produces: `RoleAssigned(dissident)`; `Teammates(dissident, peers)`.
Visible to: `RoleAssigned` to that player; `Teammates` to each dissident, and to nobody else.
Code: `content/roles/dissident.tres`. Tests:
`tests/unit/deal/deal_roles_test.gd`, `tests/unit/content/content_modes_test.gd`.

#### 9.5.4 Delivery by colours (task type)
**The greybox's Delivery** (#683, the [Delivery by meaning ADR](decisions/2026-10-10-delivery-by-meaning.md),
answered and approved by the engineer on PR #713): the House plays a second task type,
`DeliveryByMeaning` (§9.5.25): items of several kinds, each carried to its own drop-off by what it is, with no
colours and no marker through walls. It took the id `delivery` and the file `content/tasks/delivery.tres` (DE15 (i)),
so the copy deck's `task.delivery` and the how-to card follow the Delivery players play. This entry, today's Delivery,
moved unchanged but for its id and `maps` to `content/tasks/colour_delivery.tres` (id `colour_delivery`, display
name "Delivery"; `ContentNames` names it by the deck's `task.delivery`, its `TASK_EXCEPTIONS`; a copy of the how-to
card in `content/howto/tasks/colour_delivery.tres`). It stays the flat greybox's, a test bench only (#767), for the bot
scenarios and the leak test (the ADR's DD9 (c)); the class `Delivery` keeps its name and code.
What it does: one shared task of `packages` packages (the engineer's decision of 2026-09-30, #79); a subtask is done
when its package rests inside its own circle, however it got there (§7.1.14). Nobody owns the task: any living player
delivers any package.
Maps (`TaskType.maps`, #803, every task type's): the greybox alone (#828; before it none listed, so every map).
Settings: `package`: the Package item kind; `circle`: a station kind (spawn tag `circle`, radius 1 m (0.2 to 10;
game design, in the data, not a lobby setting), height 2 m (0.1 to 10; a placeholder, "not a decision"), a colour
palette: 10 distinct colours, provisional, one per package at the most `packages` allows); `subtasks_setting`:
`packages` (its own subtasks setting: 1 to 10, default 6, a placeholder); RNG purposes `circles_rng`,
`packages_rng`, `tasks_rng` (`circles`, `packages`, `tasks`). One circle per package, fixed, not a setting.
`description` (M4-5, the task screen): "Carry each package to the circle of its colour. Packages take both hands."
(provisional wording, "not a decision"). `item_spawn_tags()` (#253): its package kind's spawn tag (`package`), so the
map screen lights the rooms that hold a `package` marker, never a circle's.
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
  spawn tag, and a package item kind without one (an item kind may have none, the cooking ADR's CE18 (a), #780).
- Check, on `item_rested`: a package of an undone subtask that rests on the ground inside its circle's cylinder
  (`StationState.contains`, §7.1.14, since #647; `Delivery.rests_in` before: its rest position within the radius horizontally, and from the marker's height up to
  that plus the height, edges included) is delivered: locked (no longer interactive), its circle done, its subtask
  done; then `PackageDelivered`, `TaskState` (M4-5), `TaskProgress` and `subtask_done` (detail: the subtask's index
  and its package), in that order. Any other item in a circle, or a package in another package's circle, does nothing.

Produces: `StationPlaced` and `ItemSpawned` (with the circle and colour) in id order, `PackageDelivered`, `TaskState`
(its task's subtasks done and in total), `TaskProgress` (the subtasks done and in total, over every task); `item_rested` (spawn), `subtask_done`. Its task
state (`Delivery.State`): per subtask its package, its circle and whether it is done. It has no tick; the zone task
(§9.5.18, #647) is the task type that ticks.
Visible to: everyone, all of it: the task is shared, so every player learns the same (the downed and the dead too;
a player who left, nothing). `PackageDelivered` names the item and the circle, never the task.
Code: `core/tasks/delivery.gd`, `content/tasks/colour_delivery.tres` (provisional); its subtasks shared, with the
cylinder (#79). DealTasks calls its deal, and its packages take only free markers
(`Items.free_markers`). Tests: `tests/unit/tasks/delivery_deal_test.gd` (the deal, the demands, the mode check, no
private task event), `tests/unit/tasks/delivery_test.gd` (the check; a done subtask is never delivered again), the
cylinder's edges in `tests/unit/match/station_state_test.gd`, `tests/unit/content/delivery_content_test.gd` (the base mode's task settings, the circle and its palette),
`tests/unit/content/layout_check_test.gd` (its demands reach the fit check); the description and
`TaskState` (`delivery_test.gd`, `delivery_deal_test.gd`, `tests/unit/deal/deal_tasks_test.gd`; the description's mode
check in `tests/unit/content/mode_check_test.gd` and `item_intents_test.gd`).

#### 9.5.5 Package (item kind)
What it does: the item a subtask of the greybox's Delivery by colours moves; any living player may carry any
package. The House's Delivery by meaning carries four other kinds built the same way (spawn tag `package`, `hands`
2, no actions): Wine, Oil, Gnome and Parasol (§9.5.25, #828).
Settings: id `package`; display name "Package"; spawn tag `package`; `hands` 2 (M4-5, vision revision 1: never on
the belt, and a carrier cannot swap); actions: none, so `Use` with a package in hand is rejected (`nothing_to_do`).
Placed by Delivery.
Produces: `ItemSpawned`, `ItemPickedUp`, `ItemPlaced`; once delivered, `PackageDelivered`, and `PickUp` gets
`unavailable`.
Visible to: everyone.
Code: `content/items/package.tres` (its `hands` provisional). Tests: the parts' in `tests/unit/items/` (a package built in code, two-handed); its delivery in
`tests/unit/tasks/delivery_test.gd`; the base mode's `hands` in `tests/unit/content/item_intents_test.gd`.

#### 9.5.6 Knife (item kind)
What it does: the MVP's weapon: `Use` strikes in front of the holder.
Settings: id `knife`; display name "Knife"; spawn tag `knife`; `hands` 1 (M4-5: it fits the belt, and one player
may carry both knives, one in hand and one on the belt, V13); actions: one rule on `Use` with costs `Cooldown`
(key `hit`, 0.5 s) and `StaminaCost` (25), and the effect `Strike` (30°, 1.5 m, 50 damage; a knockdown launches the
body 4 m/s away from the attacker and 2 m/s up, `launch_mps` and `launch_up_mps`, placeholders marked "not a
decision", KD9 (b), §7.1.18; a body moves only on the mode's `motion_maps`, the House alone, KE12). The cooldown key is per
player, so swapping to a second knife does not skip the interval (§7.1.10). Placed by `SpawnItems` (`knives`).
Produces: `ItemSpawned`, `ItemPickedUp`, `ItemPlaced`; on `Use`: `Swung`, `Damaged`, `SelfStatus` (the attacker's
stamina, the victim's health), and on a knockdown `KnockedDown` and the downed player's `Correction` (M4-2).
Visible to: `Swung` and `KnockedDown` everyone; `Damaged` only the victim; the attacker gets no confirmation of a hit
but the public knockdown (an accepted exception, vision revision 1); a
refusal (`too_soon`, `tired`) only the attacker. The public `Swung` reveals no role: the rule belongs to the item
kind, which any living player may hold (§9.2).
Code: the item kind (id, name, spawn tag) in `content/items/knife.tres`, spawned by `SpawnItems`, tested by
`tests/unit/deal/spawn_items_test.gd` and `tests/unit/content/content_modes_test.gd`; the parts `Cooldown`, `Strike`
(`core/combat/`) and the life rule (`core/life/`), and the rule in `knife.tres` with `Use` from the living in Round's
allowlist (provisional under the MVP content ADR, for the engineer's approval); the launch (§7.1.18), provisional the
same way.
Tests: `tests/integration/levels/house_knife_launch_test.gd` (the launch on the House rests a body where a crouching
player fits; none on the greybox, §7.1.18), `tests/integration/levels/house_body_reach_test.gd` (every rest within a
raise's reach of a spot walked to from the spawn, §7.1.18), `tests/unit/content/content_modes_test.gd` (the rule's numbers, and a base-mode round where the living
strike and a downed player's `Use` is `not_accepted`), `tests/unit/combat/strike_test.gd` (the zone, sight, order,
who learns what, the downed and the dead skipped, a target dead at its turn skipped, #806), `tests/unit/combat/cooldown_test.gd`,
`tests/unit/combat/costs_in_reactions_test.gd` (a cost in a mode reaction refuses actor 0, #201),
`tests/unit/stamina/stamina_cost_test.gd`, `tests/unit/life/life_rules_test.gd` (every life transition, the downed holding still, the
dead, the §3.4 order, a death of a player who is not downed refused; M4-2), `tests/unit/life/respawn_test.gd` (the
respawn at a free marker or any, its events, invulnerability that strikes skip and nothing ends early, the avatar's
flag; M4-3), `tests/unit/life/kill_test.gd` (the instant kill from living and downed, invulnerable or not, and the kill queue: its order, its skips, no kill after the step's outcome or in a transition; #806), `tests/unit/content/mode_check_kills_test.gd` (`TaskType.kills()` needs `LifeTicks` with a `Respawn`), `tests/unit/match/phases/round_phase_test.gd` (leaving mid-round).

#### 9.5.7 Every task done (win condition)
What it does: the crew's only win.
Settings: side `crew`; conditions: `AllSubtasksDone`.
Produces: `won(crew)`, then `EndMatch`: `MatchEnded(crew)` with the reason `every_task_done` and the round's time.
Visible to: everyone: the side, this condition's id and the time (#548).
Code: `content/win_conditions/every_task_done.tres`. Tests:
`tests/unit/win/all_subtasks_done_test.gd`, `tests/unit/win/clock_ended_test.gd` (a delivery on the end tick),
`tests/unit/content/content_modes_test.gd` (the base mode's data).

#### 9.5.8 No crew present (win condition)
What it does: the dissidents win when every crew member has left (vision revision 1, V10). A downed or dead crew
member is still present: killing takes time from the crew, it does not end the round.
Settings: side `dissidents`; conditions: `NoneAlive` (side `crew`; the class keeps its old name).
Produces: `won(dissidents)`, then `MatchEnded(dissidents)` with the reason `no_crew_present` and the round's time.
Visible to: everyone: the side, this condition's id and the time (#548).
Code: `content/win_conditions/no_crew_present.tres` (provisional). Tests:
`tests/unit/win/none_alive_test.gd` (a knockdown and a death end nothing, the leaves, the §3.4 order),
`tests/unit/content/content_modes_test.gd`.

#### 9.5.9 Time up (win condition)
What it does: the dissidents win when the clock ends with a subtask not done, with 0 dissidents too.
Settings: side `dissidents`; conditions: `ClockEnded`, `AllSubtasksDone` negated.
Produces: `won(dissidents)`, then `MatchEnded(dissidents)` with the reason `time_up` and the round's time.
Visible to: everyone: the side, this condition's id and the time (#548).
Code: `content/win_conditions/time_up.tres`. Tests:
`tests/unit/win/clock_ended_test.gd` (0 dissidents too), `tests/unit/win/end_match_test.gd`,
`tests/unit/content/content_modes_test.gd` (0 dissidents set through the base lobby).

#### 9.5.10 PickUp (action)
What it does: takes an item from the ground into the hand; a one-handed hand item goes to an empty belt, any other
rests where the picked one lay (§7.1.11; M4-5). Beside a two-handed hand item a one-handed picked item goes onto the
belt instead, a full belt's item put down at the taker's feet first (the cooking ADR's CE21, #771).
Settings: a rule on the base mode: trigger `PickUp`; conditions `ItemOnGround`, `InReach` (2 m), `InSight`;
effects `TakeIntoHand`.
Produces: `ItemPickedUp` (with `belted`, the item moved to the belt, the picked item itself when it went onto the belt,
or none); with a hand item that does not go to the belt, `ItemPlaced` (swap) and `item_rested` for it, so a package
swapped onto its circle is delivered; beside a two-handed item a full belt's item first gets `ItemPlaced` (`put_down`)
and `item_rested`.
Visible to: everyone; a refusal (`unavailable`, `out_of_reach`, `blocked`) only the sender. A mode rule: its public
events reveal no role.
Code: the rule in `content/modes/base_mode.tres`; `core/items/take_into_hand.gd`, `core/items/item_on_ground.gd`.
Tests: `tests/unit/items/take_into_hand_test.gd`,
`tests/unit/items/in_sight_test.gd` (`InSight` refuses an item that is not there),
`tests/unit/content/item_intents_test.gd` (only the living may send it).

#### 9.5.11 PutDown (action)
What it does: puts the hand item down in front of the player (§7.1.12); a belt item stays (`empty_hand` with only one).
Settings: a rule on the base mode: trigger `PutDown`; conditions `HoldsItem`; effects `PutDownInFront` (1 m).
Produces: `ItemPlaced` (put down); `item_rested`.
Visible to: everyone; a refusal (`empty_hand`) only the sender. A mode rule: its public events reveal no role.
Code: the rule in `content/modes/base_mode.tres`; `core/items/put_down_in_front.gd`, `core/items/holds_item.gd`.
Tests: `tests/unit/items/put_down_in_front_test.gd`; the drops at a
death or a leave: `tests/unit/items/items_test.gd`.

#### 9.5.12 Use (action; the knife's hit)
What it does: uses the hand item, as its kind's rule says, never the belt item; in the MVP only the knife has one (above). It replaces
#32's `Hit` intent, so that a new held item is data, not a new intent.
Settings, Produces, Visible to: the knife's. A downed or dead player's `Use` is `not_accepted` (Round accepts it
from the living only); an empty hand (a knife on the belt too), or a package, is `nothing_to_do`.
Code: the knife's (above); the rule is the item kind's, `Use` is in Round's allowlist in `content/modes/base_mode.tres`.
Tests: the knife's; a downed or dead player's `Use`:
`tests/unit/life/life_rules_test.gd`, `tests/unit/content/content_modes_test.gd` (the base mode),
`tests/unit/content/item_intents_test.gd` (only the living, in every mode); a package's: `tests/unit/items/items_test.gd`.

#### 9.5.13 Raise, StopRaise and GiveUp (actions; the revive)
What it does (vision revision 1, Revive and Give up; M4-4, #140): a living player raises a downed one by holding E
for the raise time, and the downed player stands up where it lay; a downed player may give up and die at once.
Settings (provisional, "not a decision"; the numbers are the raise rule's own, E27):
- `Raise` (the mode's action): `TargetDowned`, `ChannelFree`, `TargetInReach` 2 m (the pick-up's reach),
  `TargetInSight`, checked at the start and every tick; then `RaiseDowned` of 3 s with a revive health of 50.
- `StopRaise`: `Channeling`; applied, it stops the actor's channel as every applied action of the actor does
  (§9.2): the raise, or since #805 a hold at a station (`HoldStation`; releasing E ends it, the car repair ADR's
  RE5), so one intent serves every channel (`tests/unit/channel/station_channels_test.gd`).
- `GiveUp`: no condition; `Die`.
- Round accepts `Raise` and `StopRaise` from the living, `GiveUp` from the downed (`not_accepted` otherwise).
Produces: `RaiseStarted`, `RaiseStopped` (no cause), `Revived`; a give-up's `Died` and the drop at the body.
Visible to: everyone (§4.2); a raise is as public as the two avatars. A raise stopped by a hit confirms that hit to
the attacker (the engineer's answer 7 on PR #133). Rejections: `not_downed`, `moving` (the body still in motion, #847), `busy`, `out_of_reach`, `blocked`,
`not_channeling`, and `not_accepted` from the phase. The raiser may hold the package (answer 4).
Code: the rules in `content/modes/base_mode.tres`; `core/life/raise_downed.gd`, `core/life/die.gd`, the conditions
`core/life/target_downed.gd`, `core/life/target_in_reach.gd`, `core/life/target_in_sight.gd`, `core/channel/channel_free.gd`
and `core/channel/channeling.gd`, the channel primitive in `core/channel/`.
Tests: `tests/unit/life/raise_test.gd`, `tests/unit/channel/channels_test.gd`,
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
Code: the rule in `content/modes/base_mode.tres`; `core/items/swap_hands.gd`, `core/items/carries_item.gd`,
`core/items/hand_not_two_handed.gd`.
Tests: `tests/unit/items/swap_hands_test.gd` (the swap, its refusals, the downed and
the dead, a swap stopping a raise, only the hand item used); `tests/unit/channel/channels_test.gd` (a swap refused
by `HandNotTwoHanded` stops no channel); `tests/unit/content/item_intents_test.gd` (the base
mode's rule, only the living); the scenarios `refusals` and `two_handed_pickup_with_a_full_belt` (§9.7).

#### 9.5.15 Sprint (not a part in v0)
What it does: the `sprint` flag of `MoveClaim` and its per-tick mask `sprint_ticks` (#155), settled by the movement
rule for every tick a claim covers (§7.1), with the numbers in `PlayerRules`: 7 m/s, 20 per second, from 20. A tick
costs only when the claim's `moving` flag and `moved_ticks` say the player gave movement input and it moved
horizontally. The downed never sprint: they hold still (§7.1.7,
#728 KE4).
Why not a part: a rule fires once per trigger, while sprint cost and speed apply to every covered tick of a
continuous claim. A mechanic that changes movement (a faster role, a slowing item) needs a movement modifier that the
movement rule reads: a new kind, v1 (§10).
Visible to: the player's own stamina in `SelfStatus`; speed is public through positions.
Code: `MovementRule` (with its per-tick masks) and `StaminaLedger`. Tests:
`tests/unit/movement/movement_rule_test.gd`, `tests/unit/movement/movement_rule_masks_test.gd`,
`tests/unit/stamina/stamina_ledger_test.gd`.

#### 9.5.16 Jump (not a part in v0)
What it does: the `jumps` count of `MoveClaim` (3e; `jumped` until then), accepted as in §7.1.4 with the numbers in
`PlayerRules`: 1 m for 10 per jump.
The downed never jump: their jumps are ignored, never corrected (§7.1.7, #728 KE4).
Why not a part: as for sprint.
Visible to: as for sprint.
Code: `MovementRule`. Tests: `tests/unit/movement/movement_rule_jump_test.gd`.

#### 9.5.17 Tutorial mode (game mode)
What it does: the tutorial's solo session (`docs/design/tutorial.md` §2.3, E68): `gather` → `loading` →
`lessons` → `raise_stage` → `death_stage`, the last two staged by the host's player with `NextStage` (§2.4, E65).
Settings:
- Written in `content/modes/tutorial_mode.tres`, built from the base mode's parts plus T1's (#599). Players 3 to 3
  (the own player and the two stand-ins, D26, so `all_ready` waits for everyone). `PlayerRules`: the base mode's
  numbers, but `respawn_s` 10 (a placeholder, "not a decision": lesson 7 is a short wait); its `crouch_maps`, which listed its own map
  (the engineer's answer (c) on #790), went with #991: the crouch plays everywhere, and lesson 1's key row names it (825c, #902; the mode file is unchanged). No `lobby_level` (E72), no
  win conditions, no Pregame and no End, no `ChangeSettings` in any phase. The settings the deal reads are fixed (each
  bound equal to its value): `packages` 1, `knives` 1 (no `tasks` or `banned_task_types` since #900).
- Sides: `crew` ("Engineers"). Roles: `crew`. Item kinds: Package, Knife. No task type (#900). Actions: PickUp,
  PutDown, Raise, StopRaise, Swap and Throw (`Holds`, `OverFloor`, `ThrowItem`, #901) as in the base mode, and `NextStage` with one effect, `ReportOutcome(next)`. No
  `Use` and no `GiveUp` is accepted in any phase (the knife swings at nobody; D28 (a) kills the own player at once).
- Phases (accepts; tick systems; voice; level; snapshots), none checking wins or running a clock: `gather` (Lobby;
  `Hello` from newcomers, `SetReady` from players; none; Silent; none; no), `loading` (Loading 60 s; `LoadAck`;
  none; Silent; the map; no), `lessons` (Round; `MoveClaim`, `PickUp`, `PutDown`, `Swap`, `Throw` from the living,
  `NextStage` from the host; FlightTicks; RoundVoice 8 m; the map; yes), `raise_stage` (as `lessons`, plus `Raise` and
  `StopRaise` from the living and `MoveClaim` from the downed, no `Throw`; ChannelTicks and FlightTicks, no LifeTicks), `death_stage` (as
  `raise_stage` but no `NextStage`; LifeTicks with a Respawn (`respawn`), ChannelTicks, FlightTicks).
- Transitions: `gather, all_ready → loading`; `loading, all_loaded → lessons`: `DealRoles` (no quota, default Crew),
  `SpawnItems` (Package by `packages`, its own `rng_purpose` `packages`, LE2 (a)), `SpawnItems` (Knife by `knives`),
  `PlacePlayers` (`round_player`, `ordered`), no `StartClock`; `lessons, next → raise_stage`: `KnockDown` (`pick`
  1, stand-in 1; the mode check's warning about a downed player with no LifeTicks is the intended case);
  `raise_stage, next → death_stage`: `KnockDown` (`pick` 0, the host's player, `then_die`).
- Map: `levels/tutorial/tutorial.tscn`, the room of §9.6.

Produces: the events of its phases and parts. Visible to: as each of them says.
Provisional under the MVP content ADR, for the engineer's approval (his answers D25 to D28, D33 and D34 (a) on
PR #596; LD1 (a), LD2 (a), LD3 (a) and LD7 to LD10 (a) on PR #894). The solo session that hosts it: §4.7.44. It
deals no tasks (DD10, the [tutorial without tasks ADR](decisions/2026-10-12-tutorial-without-tasks.md),
`docs/design/tutorial.md` §9): no `DealTasks`, task types or `TaskTicks`; `SpawnItems` spawns the package; the
throw lesson plays `Throw` with FlightTicks.
Tests: the mode check and the layout check (`tests/unit/content/content_modes_test.gd`, every mode); the tables of
`docs/design/tutorial.md` §2.3, no task dealt, and a match from `gather` to the respawn in `death_stage`
(`tests/unit/content/tutorial_mode_test.gd`); the room against `docs/design/tutorial.md` §4
and no throw at the mode's numbers leaving it, a flight over a wall resting at its fallback below the thrower; the rests on the north wall's top from the table are known, not a failure, until the map's rework (the engineer's (c) on #901, #911) (`tests/integration/levels/tutorial_map_test.gd`); the scenario `tutorial_stages` (E71: three bots; bot 1 sends
`NextStage`, waits past the 10 s knockdown while bot 2 stays down, raises it, sends `NextStage` again, dies at once
and respawns; nobody else dies; expects `none`) in the core runner and in `tools\run.cmd bots`.

#### 9.5.18 Zone task (task type)
What it does: one shared task of `zones` zones (#36); a zone is done once living players have stood in it for
`seconds` in all, and a subtask is a zone. Nobody owns the task: any living player of any role works any zone. The
second task type, beside Delivery (§9.5.4). Dealt by the base mode from #649 until the engineer took it out on #842
(only from the mode; it may come back with a name and a how-to card), and by `FixtureBaseModeWithZones` (§9.5.1): `content/tasks/hold_the_zone.tres`, id
`hold_the_zone`, "Hold the zone" (the players' word; the Ukrainian UI's «Утримати зону» once the client is
translated), described "Stand in the zone until it fills."
Maps (`TaskType.maps`, #803, every task type's): the House alone since #804 (GD13 (b) of the Generator ADR), so a mode deals it on no other map.
Settings: `zone` (a `StationKind`: spawn tag, radius, height, palette), `subtasks_setting` (a whole-number setting of
the mode), `seconds` (0.05 to 600, `ChannelEffect.seconds`' bounds; the neutral default 0 is refused, so the data
must set it; data, not a lobby setting, ZD7), `zones_rng` (`zones`). The engineer's provisional values (#302
comment 6085251071), in its data since #649: 10 s (200 ticks), a `zone` station kind of radius 1.5 m and
height 2.5 m (a jump of 1 m plus the host's slack stays inside) with one yellow colour, spawn tag `zone`, one zone
per subtask; the fixture mode's `zones` setting is 1 (1 to 1, §9.5.1). The greybox's four `zone` markers along z = 7 were
placeholders, "not a decision" (§9.6), until #804 removed them. House has three (#651, M7-Z5, placeholders on the engineer's delegation until
he moves them, #302 comment 6085904317): the yard (48, 0, 37), the garden (52, 0, 20) and the landing (30, 3.2, 41).
None in the attic, whose sloped roof leaves no clear spot, and none in the basement, where the scenarios' flat fake
finds no floor (§9.7; #681 moved the generator hall's (44, −3.2, 37) up to the yard).
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
Designed in the [zone task ADR](decisions/2026-10-09-m7-zone-task.md) (#36, PR #619). Code: `core/tasks/zone_task.gd`,
`core/events/zone_progress_event.gd`, `StationState.contains`, `MovementRule.claim_age` and `credit_gain`; its data
(provisional for the engineer's approval) with the House alone in its `maps` (the greybox has no zones, and no
scenario plays the zone task); the client's zones, their fill and the done look: §4.7.51.
Tests: `tests/unit/content/zone_content_test.gd` (the provisional values, the House's fit at the most zones, the
greybox asking none, ZE9's spacing on every map the zone task plays, each read in the host's collision world since
#681, and the flat fake shown hiding a spawn point beside an upstairs zone), `tests/unit/content/zone_base_mode_test.gd`
(on the House in the host's world since #804), `tests/integration/levels/house_zone_test.gd` (with no bot, the
House in the host's world, `ScenarioInvariants` per call and per tick: the crew works every zone, a dissident works
one alone, a knockdown pauses one; §9.7), `tests/integration/server/host_session_zone_test.gd` (`ZoneProgress` on the
real wire, a freeze in a zone; §4.6.5.3), `tests/unit/tasks/zone_deal_test.gd`
(the deal, the demands, the check), `zone_rules_test.gd` (every row of the ADR's interruption table, the freeze row
and a slow claimer's, the clock's
last tick, `ResetMatch`), `zone_progress_events_test.gd` (the window, 100 edge crossings, ZE5's order, the wire round
trip), `zone_role_swap_test.gd` (two roles swapped emit the same task events; planted "counts the crew only", it
failed, reverted), `tests/unit/match/station_state_test.gd`, `tests/unit/movement/movement_rule_claim_age_test.gd`,
`tests/unit/content/mode_check_stations_test.gd`; fixtures `tests/fixtures/tasks/fixture_zone_modes.gd`. House's zones
(#651): `tests/integration/levels/house_markers_test.gd` (ZE9's spacing through the shared
`tests/fixtures/tasks/fixture_zone_spacing.gd`, the fit at the most zones, each cylinder on flat floor clear of walls and
ceilings in the host's collision world, and a zone by a wall or over the stairs refused).

#### 9.5.19 Generator (task type)
What it does: one shared task (#679) whose subtasks are its N active switches, N the subtasks setting (0 to
`switches`): the players turn every active switch on, then press the generator's button, and its charge runs for
`seconds`; at full charge every subtask is done at once (GE13 (a)). Nobody owns it: any living player of any role
uses a switch or the button (`Interact(station)`, through each station kind's rule, §9.4.2 `UseStation`; GE1, GE2).
Designed in the [Generator ADR](decisions/2026-10-10-generator-task.md); its station scenes stand in the House, its
client (the E key, the scenes driven, the clicks and hum, the map's charge bar) is §4.7.54, and the base mode deals
it on the House alone.
Settings: `generator` and `switch` (two `StationKind`s with different spawn tags, each with an `Interact` rule whose
effect is `UseStation`), `subtasks_setting` (a whole-number setting of the mode from at least 0 to at most
`switches`), `switches` (the switch devices on a map it plays, at least 1), `seconds` (`ZoneTask`'s bounds, 0.05 to
600), `switches_rng` (`switches`); `TaskType.maps` as every type's (GE15).
- Deal: the generator's station on the map's one `generator` marker, then a switch station on N of the `switch`
  markers, drawn with `switches`, in level order; station ids the generator first, then the switches; every switch
  starts off. The other markers get no station: their devices are fixed switches, on for good (GE14), so an
  `Interact` naming one names an unknown station (`nothing_to_do`, `Match._target_problem`). `StationPlaced` in id
  order, then the charge's `ZoneProgress` at 0. N = 0: the generator is placed and the task done at the deal, its
  progress full. A map short of markers deals nothing and logs a match error, as Delivery's.
- Demands: exactly one `generator` and exactly `switches` `switch` markers, whatever the settings (§9.4.4's exact
  demands): the fit check gives `markers_exact` and `LayoutCheck` refuses any other count.
- A use (`use_problem`, `use_station`; reads no role): a done task refuses every use `unavailable`; a switch toggles
  (`SwitchChanged`), and one turned off stops a running charge; the button (`ButtonPressed`) stops a running charge,
  starts one when every active switch is on, and otherwise changes nothing. Nothing else stops or resets the charge
  (the ADR's rule 2.6): not a knockdown, a leave or a role.
- Tick (`TaskTicks`): first a held progress event whose window has passed goes out, even when the charge stopped
  since (GE8); then a running charge gains one tick, and at `seconds` (`Ticks.from_seconds`) it is done: every station
  of the task done, `ZoneProgress` at its full value, then `Tasks.subtask_done` per active switch in station order
  (detail: the subtask's index and its station), so each `TaskState` reads N of N.
- Mode checks (GE10, `Generator.check`): both kinds present with different spawn tags and the use rule, `switches`
  at least 1, the subtasks setting at most `switches` (from 0: `TaskType.check`, G0), `seconds` in bounds, a
  non-empty RNG purpose.

Produces: `StationPlaced` and `ZoneProgress` (everyone) in the deal; `SwitchChanged`, `ButtonPressed` and
`ZoneProgress` (everyone) on a use (`use_emits`); `ZoneProgress`, `TaskState` and `TaskProgress` (everyone) on a held
event and at full charge. A start or stop in a command sends its `ZoneProgress` with `tick` the tick before (the
command runs before that tick's gain); one inside `WINDOW_TICKS` (`ZoneTask`'s 5) of the last waits for the window's
end. Its task state (`Generator.State`): the generator's station, per active switch its station and whether it is
on, the charge's ticks, whether it runs, done, and the window's bookkeeping, in `MatchState` (`ResetMatch` clears it).
Visible to: everyone, all of it. No event names a player (the ADR's row 18), and nothing reads a role (§9.2).
Code (`core/`): `core/tasks/generator.gd`, `core/events/switch_changed_event.gd`,
`core/events/button_pressed_event.gd`, the exact demands (`Demands.exact`, `markers_exact`), wire kinds 70 and 71
(protocol 18), `ClientModel.Station`'s `on` and `presses`. The station scenes (GE11; provisional
until the engineer approves them): `levels/stations/switch.tscn` (the active look, off and on, and GD5's fixed look)
and `generator.tscn` (the button, four bars, the glow), each the art prop as its body, its own primitive collision
and a use spot in `spawn_switch` or `spawn_generator`, instanced in the House's storage, boiler room, pump room,
switch room and generator hall in place of the plain markers, their use spots at house-map §6's points (the
convention: the [level piece ADR](decisions/2026-10-09-level-piece-conventions.md)'s "Station scenes");
read as plain points until the Generator's task type snaps their tags. The data (provisional until the engineer
approves it): `content/tasks/generator.tres` (GD1's name "Charge the generator" and description, `seconds` 60,
`switches` 4, `maps` the House alone, both kinds' `Interact` rule and GD6's 2 m radii and heights, placeholders) in the
base mode with its `switches` setting (3, 2 to 4; §9.5.1); until the copy deck has `task.generator` the client names
it by the deck's `task.switches` ("Switches", `ContentNames.TASK_EXCEPTIONS`) and its how-to card
(`content/howto/tasks/generator.tres`) shows three word frames of existing keys, placeholders the engineer approves.
`LayoutCheck` also refuses a map on which no task type plays while a row deals tasks at the defaults.
Tests: `tests/unit/content/generator_content_test.gd` (the data, the fit of House with it and of the greybox
without it, GD12's switch spacing in the host's world, fixture cases 13 m refused and 16 m accepted at 2 m, and the
panel's bars matching `switches`); and `tests/unit/tasks/generator_deal_test.gd`, `generator_rules_test.gd` (every row of the ADR's edge-case
table), `generator_progress_events_test.gd` (the window, the order, the ticks), `generator_check_test.gd` (GE10,
`use_emits`, the leak lists, no event naming a player), `generator_role_swap_test.gd` (planted "the button refuses
dissidents", both failed, reverted), `generator_demands_test.gd` (the exact demands through `LayoutCheck` and the
fit check), `tests/unit/content/demands_test.gd`, `tests/unit/client/net/client_model_test.gd`,
`tests/unit/client/ui/host_text_view_test.gd`, and over the wire `tests/integration/server/host_session_generator_test.gd`
(each client's decoded events equal `view_of`); fixtures `tests/fixtures/tasks/fixture_generator_modes.gd`. The
scenes: `tests/integration/levels/stations/station_scenes_test.gd` (one use spot on the floor in front, layer-1
collision only from the scene's primitive shapes, a player on the use spot clear of the device, the default looks)
and `tests/integration/levels/house_stations_test.gd` (the use spots read and snapped in the host's world at §6's
points, a player on each clear of walls, no other marker at a use spot's (x, z), no art copy of a device left; a
switch moved 0.5 m failed it). A match on the House (#802, Generator G7; no bot plays it, §9.7):
`tests/integration/levels/house_generator_test.gd` (the shipped base mode in the host's world, `ScenarioInvariants`
per call and tick: a use from each use spot, a full charge then `unavailable`, `blocked` and `out_of_reach` in the
House's geometry, the markers the deal left with no station, and the leak plant of §4.6.4.1).

#### 9.5.20 Cooking (task type)
What it does: one shared task (#682) whose subtasks are its N burgers, N the subtasks setting: each place shows an
order (a bun, a patty and a herb shown as an icon); the players take buns and raw patties from boxes, fry the patty on
the grill, pick the herb the herb board's code names from its bed and fill the place, take the plated burger and
serve it at the order board, where alone it is checked (#1101, the ADR's amendment of 2026-10-15). Nobody owns it:
any living player of any role takes, fries, fills and serves. Designed in the [cooking ADR](decisions/2026-10-10-cooking-task.md) (the ADR's §8,
the split); C3 (#772) built its data, deal, board events, demands and checks, C4 (#773) the uses of the grill, the
beds and the places and the grill's tick, C5 (#774) its station scenes in the House; the client's boards are
C7's. C6 (#775) put it in the shipped base mode on the House alone (provisional data the engineer approves):
`content/tasks/cooking.tres` (the cooking ADR §5.1's name "Cooking" and the GDD's description, `fry_seconds` 10, `burn_seconds` 5, `maps` the
House alone, CD16's 2 m radii and heights, the herb board `display` (the order board too until #1101 gave it the
serve rule), CE17's `Cooldown` key `cooking_take` at 0.25 s on
the beds and the boxes, `HandNotTwoHanded` on the place alone), its 21 item kinds in `content/items/` (the cooking ADR §5.1's names;
since #1101 22 with `burger.tres`, one-handed, `vanish_seconds` 60, no cap; the 15 ingredients `vanish_seconds` 60, the 11 a take gives `max_items` 128, placeholders; the six boxes two-handed,
each tagged with its id and holding its take rule, CE7), all listed in the mode's `item_kinds` (CE18), the `burgers`
setting (1, 0 to 3, "Burgers (Cooking)") and VanishTicks in Round (§9.5.1). Until the copy deck has `task.cooking`
and the 21 `item.<id>` keys the client names the task by the deck's `room.kitchen` ("Kitchen",
`ContentNames.TASK_EXCEPTIONS`) and the items by their display names, and its how-to card
(`content/howto/tasks/cooking.tres`) shows three word frames of existing keys, placeholders the engineer approves.
Tests (C6): `tests/unit/content/cooking_content_test.gd` (the data, the rules, the 21 kinds, the setting, Round, and
the fit of House with it and of the greybox without it).
Settings (CE14): five `StationKind`s, `herb_board` (a `display` kind), `order_board`, `grill`, `herb_bed` and
`place` (each with an `Interact` rule ending in `UseStation`; the order board's since #1101); the `burger` item
kind (#1101); the lists `buns`, `raw_patties`, `fried_patties` (in
the raw ones' order), `burnt`, `herbs` (at most 255) and `boxes` (two-handed item kinds on tags of their own, each
giving one bun or raw patty kind by its `target_actions`' `GiveItem`); `subtasks_setting`; `fry_seconds` and
`burn_seconds` (`ZoneTask`'s bounds; the first counted from the patty going on, the second from its turning fried,
as the ADR's 200 and 100 ticks); the RNG purposes
`boxes_rng`, `orders_rng`, `code_rng` and `beds_rng` (§3.3); `TaskType.maps` as every type's.
- Deal (the ADR's §2.1, CE8): N = 0 places nothing, and the task, with no subtasks, is done. Otherwise the order board, the
  herb board and the grill on the one marker of their tags, a bed on every `herb_bed` marker and N places on the
  first N `place` markers, all in level order (station ids in that order); one box per box kind on a random free
  marker of its tag; per place an order of a bun, a raw patty and a herb, each drawn on its own (CD11 (a): two
  orders may share a kind); the code (which herb each icon means) and the beds' herbs, two permutations of the
  herbs (CD13 (b)). A map short of markers deals nothing and logs a match error, as Delivery's.
- Demands: exactly one marker each for the boards and the grill and exactly as many `herb_bed` markers as herbs
  (§9.4.4's exact demands), at least N `place` markers and at least one per box kind's tag, whatever the players.
- Mode checks (`Cooking.check`, CE14): every station kind set and of the right sort, every listed item kind
  distinct and in the mode, the ingredients one-handed with `vanish_seconds` (CD6 (c)), a cap (`max_items`) on every
  given kind (CE3), the boxes as above and never vanishing, each bun and raw patty kind given by some box, the seconds
  in bounds, the setting from at least 0, non-empty RNG purposes.
- Uses (`Interact` naming a station; `use_problem`, `use_station`, the ADR's §2.3 to §2.5, CE11, #773): the grill,
  empty, takes a raw patty (locked on it, `GrillLoaded` with its fried and burnt ticks; refused `two_handed`,
  `empty_hand` or `wrong_item` for anything else, CD7 (a)); occupied, it gives its patty, whatever its kind
  (`Items.give`, which makes room: the belt, or the feet; a box carrier's onto the belt, CD3 (b), CD5 (b)). A bed
  gives a new item of its herb of the round at the bed (`GiveItem.give_new`; at the cap with none loose `unavailable`
  before anything is paid, CE3). A place (#1101) takes a bun, a fried patty or a herb on its free slot, locked
  there whatever the order asks, `IngredientPlaced` (else `wrong_item`: a knife, a raw or burnt patty, CD8 (b);
  `unavailable` for a filled slot or a done place; its rule's `HandNotTwoHanded` refuses `two_handed` first). E on a
  full place takes the burger: the three items vanish (`ItemVanished`, ascending id), a `burger` item is spawned and
  given to the actor (`GiveItem.give_new`), then `BurgerPlated` with its kinds; `State.burgers` keeps its order, bound to the burger's own item (never another item given that id after it vanished).
  The order board serves the held burger (`empty_hand`, `wrong_item` for no burger, `unavailable` for a done order):
  `BurgerServed(station, right)` against its place's order, the burger vanishes; right, what was put on that place
  since vanishes, the order and the place are done and the subtask done (CE13); wrong, nothing more. The grill's and
  the beds' rules have no `HandNotTwoHanded` (a take beside a box, CD3 (b)); a bed's rule holds a `Cooldown`
  (CE17's flood guard, `too_soon`), which `Cooking.check` demands. No use reads a role.
- Tick (`TaskTicks`, Round): the grill's patty turns fried at its fried tick and burnt at its burnt tick
  (`Items.change_kind`, `ItemChanged`, CE4, CE10); a burnt one stays until taken off; nothing changes after the round.

Produces: `StationPlaced` per station in id order, `ItemSpawned` per box, `OrderPosted` per place in station order,
then `HerbsDealt` (all everyone) in the deal, then the task's `TaskState` and `TaskProgress`; then `item_rested`
(spawn) per box. On a use: `GrillLoaded`, `IngredientPlaced`, `BurgerPlated`, `BurgerServed`, `ItemSpawned`,
`ItemVanished` (the cap, a take, a serve), `ItemPlaced`
(room made), `ItemPickedUp`, `TaskState` and `TaskProgress`; in the tick `ItemChanged` (all everyone). Its task state
(`Cooking.State`, CE12 (a)): the boards', grill's and beds' stations, each bed's herb,
the code, the orders (`Cooking.Order`: its place, bun, raw patty, herb, the items locked on its slots, done) and the
grill's patty with its fried and burnt ticks, the plated burgers by item id (`Cooking.Burger`: its order and
kinds, #1101), in `MatchState`. Visible to: everyone; an order carries its fried patty and its herb's icon, never
the herb (CE9 (a)); no event names a player, nothing tells right or wrong before a serve (#1101), and nothing reads
a role (§9.2).
Code (`core/`): `core/tasks/cooking.gd`, `core/events/order_posted_event.gd`,
`core/events/herbs_dealt_event.gd`, wire kinds 73 and 74 (protocol 22), `WireBudget`'s `HerbsDealt`; the uses and the
tick: `core/events/grill_loaded_event.gd`, `core/events/ingredient_placed_event.gd`, wire kinds 79 and
80 (protocol 26); the burger checked when served: `core/events/burger_plated_event.gd`,
`core/events/burger_served_event.gd`, wire kinds 85 and 86, kind 80 without `right` (protocol 35).
Tests: `tests/unit/tasks/cooking_deal_test.gd`, `cooking_check_test.gd` (CE14, `emits`, the leak lists),
`cooking_demands_test.gd` (the exact demands through `LayoutCheck` and the fit check),
`tests/unit/events/cooking_events_name_no_player_test.gd`, `tests/unit/server/wire_budget_test.gd` and the wire
schema tests; `cooking_grill_test.gd`, `cooking_beds_test.gd`, `cooking_places_test.gd`, `cooking_edges_test.gd` (the
§4 rows beside other parts: a downed player, a raise, the clock's last tick, the round's end), `cooking_serve_test.gd`
(#1101: the take, the serve right and wrong, the board's refusals, a refilled plate cleared, nothing tells right or
wrong before the serve) and
`cooking_role_swap_test.gd` (§7); fixtures `tests/fixtures/tasks/fixture_cooking_modes.gd`. Over the wire (#778, cooking
C9, the ADR's §7 and CE22): `tests/integration/server/host_session_cooking_test.gd` on
`tests/fixtures/tasks/fixture_wire_cooking.gd` (a fixture mode dealing a fixture Cooking on its one map, whose path is
the mode's `maps`, a key of the harness's `game_layouts` and the type's `TaskType.maps`): two clients take from the
boxes (onto the belt beside a package, a full belt's bun down at the feet), fry a patty, put a right and a wrong
ingredient on a place, finish the burger and leave what lay to vanish, and what each decoded equals its
`Match.view_of` (planted: `IngredientPlaced`'s wire row without `right`, failed, reverted; since #1101 they plate
and serve a wrong burger, then a right one); and the flood guard and
the cap against one peer's burst of takes (§4.6.5.3).
The station scenes (provisional until the engineer approves them; the convention: the
[level piece ADR](decisions/2026-10-09-level-piece-conventions.md)'s "Station scenes"):
`levels/stations/order_board.tscn`
(`spawn_order_board`; `Rows/Row1` to `Row3`, each a hidden `Number` `Label3D` and the `Bun`, `Patty` and `Herb`
anchors where C7 draws an order), `herb_board.tscn` (`spawn_herb_board`; `Pairs/Pair1` to `Pair5`, an `Icon` and a
`Herb` anchor each), `grill.tscn` (`spawn_grill`; the art's lid hidden, a `Grate` and the hidden `Ring` above it,
CD14), `place.tscn` (a counter, `spawn_place`; the `Plate` and the `Number` hidden: an unused place is a bare counter,
CE15), `herb_beds.tscn` (`Bed1` to `Bed5`, each holding its `Plant` and its use spot in `spawn_herb_bed`),
`bun_shelf.tscn` and `freezer.tscn` (no use spot: the markers of the boxes, `spawn_box_bun_white`, `_sesame`,
`_dark` and `spawn_box_patty_light`, `_red`, `_deep_red`, on the floor in front). The House's kitchen holds the board
and the three places (numbered 1 to 3 in level order, CD1), storage the shelf and the freezer, the chill zone the
grill, the greenhouse the herb board and the beds, each at house-map §6's point in place of a plain marker and of the
art's copy of its device; no other map holds one (CD15). Since C6 (#775) the base mode's Cooking data reads them as its stations and boxes.
Tests: `tests/integration/levels/stations/station_scenes_test.gd` (the convention, for the four one-spot devices),
`cooking_stations_test.gd` (the rows, pairs, grate, ring, plate and number, the five beds with a clear use spot
each, the shelves' box markers on the floor) and `tests/integration/levels/house_cooking_stations_test.gd` (the
markers read once each at §6's points, one box per kind, the places numbered in level order, a player clear on each
used device's spot on a whole floor, a player walking up to the order board within its reach and seeing it
(#1101: its marker, between the board and the counters, is too tight to stand on), the boxes on storage's floor, no
shared (x, z), no art copy left, none on another map).

#### 9.5.21 Car repair (task type)
What it does: one shared task (#688) whose subtasks are the N parts the car needs, N the subtasks setting: one player
holds the lift at its panel while another takes the needed part from its bin and fits it under the raised car; letting
go drops the car on whoever lies under it. Nobody owns it: any living player of any role holds the lift, takes a part
or fits it (`Interact(station)`, through each station kind's rule), and no condition reads a role. Designed in the
[car repair ADR](decisions/2026-10-10-car-repair-task.md) (approved for the MVP only); built so far: R3 (#807), the
deal, the lift and the drop, R4 (#808), the fit, its refusals and the bins' belt rule, R5 (#809), the station scenes
on the House, R7 (#811), the client's view, and R6 (#810), its data: the shipped base mode deals it on the House alone.
Data (R6, #810; provisional, the engineer approves it in #810's PR): `content/tasks/car_repair.tres` with RD12's
words ("Repair the car", its description) and RD2's placeholders ("not a decision"): the car's rule
(`HandNotTwoHanded`, `AtStation`, `StationInSight`, `ChannelFree`, `StationUsable`; a 5 s `HoldStation`) on a 0.9 m by
1.4 m cylinder, the panel's (the same conditions; an endless `HoldStation` a hit does not stop) on 1.5 m by 2 m, three
bins (`part_bin_1` to `_3`, 2 m by 2 m; `AtStation`, `StationInSight`, the 0.25 s `car_part_take` `Cooldown`, no
busy-hands condition, RD17; `GiveItem` of its part), the display `part_picture`, a 2 s rise, the box's half-width
1.0 m and clearance 1.4 m, `maps` the House; the parts `content/items/car_part_green.tres`, `_blue` and `_yellow`
("Green part", "Blue part", "Yellow part": the bins' plate colours; one-handed, no spawn tag, `max_items` 32, no
`vanish_seconds`), in the base mode's `item_kinds`; the setting `car_parts` ("Parts to fit", 1 to 3, default 2);
the how-to card `content/howto/tasks/car_repair.tres` (deck keys only, a placeholder).
Settings: `car`, `lift_panel` (station kinds; the car's `Interact` rule ends in a timed `HoldStation`, the panel's in
an endless one), `bins` (one station kind per part, each with its own spawn tag and an `Interact` rule holding a
`Cooldown` and ending in `GiveItem` of its part), `picture` (a display kind, never used), `parts` (the part item kinds,
each given by exactly one bin, each among the mode's `item_kinds` and capped at least at twice the mode's maximum of
players plus the subtasks maximum plus 1, CE3), `subtasks_setting` (a whole-number setting from at least 0),
`car_end_tag` (the marker at the middle of the car's front: the car's long axis, no station), `rise_seconds` (0 to
60), `half_width_m` (0.2 to 10) and `clearance_m` (0.5 to 10) of the footprint box, the car kind's cylinder inside it,
`parts_rng` (`car_parts`); `TaskType.maps` as every type's. The numbers' defaults are out of bounds: the data sets them.
- Deal: a station on the one marker of each kind's tag: the car, the lift panel, the bins in `parts` order, then the
  picture (`station_kinds()`); the N needed parts drawn in order with `car_parts`, the first uniformly from every part
  kind, each later one from the kinds other than the one before it (RD3 (g)). `StationPlaced` in id order, then
  `PartNeeded(picture, first part)`. N = 0: no subtasks, done at the deal, `PartNeeded` with no kind.
- Demands: exactly one marker of each kind's tag and one `car_end` marker (§9.4.4's exact demands); its own layout
  problem `short_axis` (`layout_problems`, RE14): a `car_end` nearer the `car` marker than the car kind's radius.
- The hold (`hold_started`, `hold_stopped`, called by `HoldStation`): a hold at the panel starts `LiftChanged(panel,
  true, tick)` and records the tick; the car is fully up `rise_seconds` later (`is_up`, computed where it is read, so
  the type never ticks). The panel refuses a new hold `unavailable` once the task is done; a running hold passes its
  re-check whatever the task's state (RD11 (a)). A hit does not stop the hold (`hit_stops` false); a knockdown, a leave,
  `StopRaise`, another action of the holder, or its feet leaving the panel's cylinder or sight do.
- The drop: every stop emits `LiftChanged(panel, false, tick)`; unless the phase's end stopped it (RE4: the car comes
  down without a kill), every living or knocked-down player (invulnerable or not, RD7) whose feet (the last accepted
  position) lie in the footprint box (`in_box`, RE7: a horizontal box from the car's use spot to `car_end`, as long
  again behind it, `half_width_m` to each side, from 0.25 m below its floor to `clearance_m` above, edges inclusive) is
  queued through `LifeRules.kill_later` in peer-id order, so nobody dies halfway through a command, a tick system or a
  channel's step (RE17).
- A use (`use_problem`, `use_reasons`; reads no role): after the rule's own refusals, the car refuses `unavailable`
  (not fully up, or the task done), then `empty_hand` (nothing in the hand), then `wrong_item` (anything but the part
  needed now, another part included: RD8 (a)); a bin never refuses for the task's state.
- The fit (the ADR's §2.4, RD10 (d)): the car's timed hold. Its start emits `FitChanged(car, fitter, tick)`; the same
  refusals run on every re-check, so the car going down or the part leaving the hand stops it, a hit stops it
  (`hit_stops` true), and `AtStation` stops a fitter whose last accepted claim is too old (RE2); a stop emits
  `FitChanged(car, 0, tick)` and loses the progress. Completed (`hold_completed`): the part leaves the hand, locked
  at the car's use spot (`Items.lock_at`, RE12, C2's lock), then `PartFitted(car, item)`, the subtask
  (`Tasks.subtask_done`: `TaskState`, `TaskProgress`, `subtask_done` with the subtask's index and the car), then
  `PartNeeded(picture, next part)`, with no kind once the last is fitted and the task done. The lift's hold goes on.
  A fit and a drop in one tick: channels step in peer-id order, so a fitter stepping before the holder's drop
  fits its part, then dies; a drop first (a lower holder, or `StopRaise` in the command step) stops the fit
  unfitted (`FitChanged` with 0), and the fitter dies at the step's end (RE17).
  A hit that stops the fit sends `FitChanged(car, 0)` to everyone in the tick of the attacker's public `Swung`, so
  it confirms the hit landed (the fitter was not invulnerable). This follows from RD10 (c) (a hit stops the fit) and
  RD15 (a) (`FitChanged` is public); the engineer's answer 7 on PR #133 covered `RaiseStopped` only, so the exception
  to "no hit confirmation" was accepted by the engineer on 2026-10-13
  ([PR #917, comment 6146566084](https://github.com/xperiaroco2/prime-game/pull/917#issuecomment-6146566084)), as his
  answer 7 on PR #133 did for `RaiseStopped`.
- The bins (the ADR's §2.5, RE13): cooking's item source (#770: a `Cooldown`, then `GiveItem` of its part;
  `Items.give` makes room, the kind's `max_items` caps it, vanishing the part that lay longest) with no busy-hands
  condition: RD17's belt rule gives a package carrier its part onto the belt.
- Mode checks (RE14, `CarRepair.check`): the bullets above, each with its own message. A bin's `Cooldown` sits on the
  same Interact rule that ends in its `GiveItem`; the car's and the panel's rules each hold `StationUsable` (a use's
  task state is read only through it) and end in the right hold: the car's timed with `hit_stops` true, the panel's
  endless with `hit_stops` false (RD10 (c)). A bin's take holding a `HandNotTwoHanded` (not negated) is refused (RD17).

Produces: `StationPlaced` and `PartNeeded` (everyone) in the deal; `LiftChanged` (everyone) on a hold's start and stop
(`hold_emits`); `FitChanged` (everyone) on a fit's start and stop, and `PartFitted`, `TaskState`, `TaskProgress` and
`PartNeeded` (everyone) on its completion; a drop's deaths are `Died`, as every death. Its task state (`CarRepair.State`): the stations' ids, the
`car_end` position, the needed parts, the parts fitted, the tick the running hold began, in `MatchState` (`ResetMatch`
clears it). Visible to: everyone, all of it. Only `FitChanged` names a player, the fitter (RD15 (a)); none names the
lift's holder (the ADR's §3), and nothing reads a role (§9.2).
Code (`core/`): `core/tasks/car_repair.gd`, `core/events/lift_changed_event.gd`,
`core/events/part_needed_event.gd`, `TaskType.layout_problems` and `HostText.SHORT_AXIS`, wire kinds 75 and 76
(protocol 23), `ClientModel.Station`'s `up`, `lift_tick` and `part`; the fitting: `core/events/fit_changed_event.gd`,
`core/events/part_fitted_event.gd`, wire kinds 81 and 82 (protocol 27), `ClientModel.Station`'s `fitter`, `fit_tick`
and `fitted`, and `ClientModel.Item`'s `fitted`. The level: `levels/stations/car.tscn` (the car and
the lift arms on `Lift`, an `AnimatableBody3D` on layer 4, `movers`, with one box hull: no top within a jump's reach,
its lowest point 0.16 m, under the 1.4 m `clearance_m`; the posts' frame on layer 1, clear of the use spot under the
car), `lift_panel.tscn` (a hidden lamp), `parts_shelf.tscn` (three bins, each a use spot and a colour plate, RD2's
placeholders) and `part_picture.tscn` (a hidden plate on the garage's east wall), instanced in the garage and in
storage in place of the markers and the art's copies; a kit partition 1 m east of the panel's use spot hides the space
under the car (RE15); house-map §6 holds the use spots. Tags, plates and the partition are provisional. The client: §4.7.57
(`ClientModel.Station`'s `rise_tick`, `Item.rests()` false when fitted, the `movers` mask, `CarRepairUse`,
`CarRepairViews`, the hold's `StopRaise`). The data: above.
Tests: `tests/unit/content/car_repair_content_test.gd` (the words and numbers, the rules, the parts and their
cap, `car_parts`, `tasks` at the House's five, Round's `Interact` and `StopRaise`, the House's fit with one marker of
each tag and the greybox asked for none); `tests/integration/levels/stations/car_repair_stations_test.gd` and `station_scenes_test.gd` (the scenes),
`tests/integration/levels/house_car_repair_test.gd` (#809: the use spots at §6's points, the car's on the garage
floor, RE15 from the use spot and the rim of its cylinder at every eye of the crouch band, planted without the
partition: failed, reverted; the voice distance, no marker in the footprint, players clear),
`house_car_repair_match_test.gd` (#812, car repair R8: the House's match in the host's real world, §9.7; planted
`FitChanged` to its fitter alone: failed, reverted, §4.6.4.1);
`tests/unit/tasks/car_repair_deal_test.gd` (the stations, the draw with no repeat, N = 0, an exact-count map,
the fit check's `short_axis`), `car_repair_lift_test.gd` (every stop, the box, the downed and the invulnerable, a busy
second press, RD11, the rise, the phase's end), `car_repair_fit_test.gd` (#808: the fit's start and completion, the
refusals in order, a stop, a hit, a stale fitter, the last part, the same-tick fit and drop, the belt; planted out
`wrong_item`: failed, reverted), `car_repair_drop_order_test.gd` (RE17's mid-command drops, planted
`kill` for `kill_later`: three failed, reverted), `car_repair_check_test.gd` (RE14; RD17's bin with `HandNotTwoHanded`, its check planted out: failed, reverted), `car_repair_role_swap_test.gd`
(planted "the panel refuses dissidents", both failed, reverted), `tests/unit/events/car_repair_events_name_no_player_test.gd`,
`tests/unit/client/net/client_model_test.gd`; fixtures `tests/fixtures/tasks/fixture_car_repair_modes.gd`. Over the
wire (#813, car repair R9, the ADR's §7): `tests/integration/server/host_session_car_repair_test.gd` on
`tests/fixtures/tasks/fixture_wire_car_repair.gd` (a fixture mode dealing a fixture `CarRepair` on its one map, whose
path is the mode's `maps`, a key of the harness's `game_layouts` and the type's `TaskType.maps`; its `PlacePlayers` is
`ordered`, so each test puts each client on its spot): the host's client holds the lift, a second client takes each
part from its bin and fits it (refused `unavailable` once while the car is down), a third stands in the footprint box,
and the holder lets go: the fitter and the third die, the holder does not; what each decoded equals its
`Match.view_of` (planted: `FitChanged`'s wire row without `tick`, failed, reverted). As in cooking's C9, a server path
that broadcasts what the filter should route stays unseen there (every one of its events goes to every player) until
bots play car repair. And the flood guard, the cap and the reliable-intents bucket against one peer's bursts at a bin,
at the panel and of `StopRaise` (§4.6.5.3).

#### 9.5.22 Photo task (task type)
What it does: one shared task (#687) whose subtasks are the photos with a person hung on the board, N the subtasks
setting: the players load the camera with a film, take shots with a player standing in its frame, take the film to
the printer, and hang a printed photo on the board. Nobody owns it: any living player of any role loads, shoots,
takes a film from the box, prints and hangs (`Interact(station)`, through each station kind's rule, §9.4.2
`UseStation`; PD1). Designed in the [photo ADR](decisions/2026-10-10-photo-task.md) (§9 holds its split into P1 to
P10); P2 (#781) builds the deal, the load and the shot, P3 (#782) the box, the printer, the board and the count; the
client's picture is a later part. The base mode deals it on the House alone since P5 (#784; provisional until the
engineer approves it): `content/tasks/photo.tres` (§6.1's name "Photography" and description, `frames_per_film` 5,
`fov_deg` 50, `aspect` 4:3, `range_m` 10, `maps` the House alone, `subtasks_setting` `photos`, the five kinds with
PD9's 2 m radii and heights and their `Interact` rules, the box's `Cooldown` 0.25 s, placeholders) with
`content/items/film.tres` and `content/items/photo.tres`, in the base mode with its `photos` setting (3, 1 to 5;
§9.5.1). Until the copy deck has `task.photo`, `item.film` and `item.photo`, the client names the task by the deck's
`room.photo_zone` ("Photo zone", `ContentNames.TASK_EXCEPTIONS`) and the two items by their display names, and its
how-to card (`content/howto/tasks/photo.tres`) shows three frames of existing keys, placeholders the engineer
approves. Tests: `tests/unit/content/photo_content_test.gd` (the data, the rules and the box's cooldown, the items,
the setting and every House type in every match, Round's `Interact` from the living, the House's fit with the exact
demands and the greybox asked for none, a clean layout check).
Settings: `camera`, `photo_spot`, `film_box`, `printer`, `board` (`StationKind`s with different spawn tags; the photo
spot a display kind with no rule, the aim; the four others each an `Interact` rule ending in `UseStation`, the box's
paying a `Cooldown`), `film` and `photo` (one-handed item kinds the mode declares, their spawn tags none of a station
kind's), `subtasks_setting` (a whole-number setting from at least 0), `frames_per_film` (at least 1), the frame's
`fov_deg` (vertical, 1 to 179), `aspect` (0.25 to 4) and `range_m` (0.5 to 100); `TaskType.maps` as every type's.
- Deal: N = `max(setting, 0)`; the task is added always; N = 0 places nothing and the task is done (#79). Else a
  station on the one marker of each kind, ids in the order camera, photo spot, film box, printer, board,
  `StationPlaced` in id order, then one fresh film on the `film` marker: `ItemSpawned`, then `item_rested` (spawn)
  (PE11). The `photo` marker's position is kept as the printer's tray (#782). No RNG.
- Demands: exactly one marker of each station kind's tag, of `photo` (the printer's tray) and of `film`, whatever the
  settings (§9.4.4's exact demands). `TaskType.layout_problems` (the fit check, `FitCheck`, which holds the lobby back on
  the chosen map; `most_layout_problems` is 1) gives `photo_spot_near` for a photo spot marker no farther than the two kinds' radii from the camera marker horizontally (when the map holds one marker of each), so
  the spot never lies in the camera's reach and the frame never looks straight up or down (PD18).
- The camera (PE17): it holds a film while the film it was loaded with still lies where the load laid it: the same
  `ItemState` (so a vanished film's recycled id never matches) with the move serial (`ItemState.moves`, bumped by
  `Items` on every lay and lift, §9.3) the load left. Any lift (a pick-up, a take onto a package carrier's belt,
  `PickUp`'s exchange) or a vanish empties it, in the load's own tick too.
  Entries of vanished items (PE6 (a), #782): after the box's take and after a print, the command that vanished an
  item drops its `films` or `prints` entry, the shots no remaining film or photo shows, and the camera's film; the
  identity match keeps a stale entry from being read before that (a film that vanished another way, `VanishTicks`,
  stays in `films` until the next take or print, unread).
- A use (`use_problem`, `use_station`; reads no role): at an empty camera the actor's fresh film (a film with no shot),
  the hand's, else the belt's, is laid on the camera (`Items.lay_on_station`: `item_rested` on_station, no
  `ItemPlaced`) and `FilmLoaded` goes to everyone. At a loaded camera a shot (§3.2 of the ADR): the lens is the camera
  marker raised by the eye height, aimed at the photo spot's marker raised alike (`PhotoFrame`: a frustum from 0.3 m
  to `range_m`); a candidate is an ALIVE player whose feet lie outside the camera's cylinder (`StationState.contains`,
  so the shooter, who uses it from inside, never is), and it counts when its head (feet plus the eye height, the
  crouched eye while crouched, #790) lies in the frame with a clear `WorldQuery.line_of_sight` from the lens; whether
  any counted is kept on the host (PE5). The record (§3.3): one row per ALIVE or knocked-down player with its feet
  outside the cylinder within `range_m` + `RECORD_MARGIN_M` (2 m) of the lens, in peer order, at most 15: `peer`,
  `position`, `facing`, `downed`, `crouched` (#790), `held_item`, `belt_item` (the snapshot's avatar row without
  velocity and invulnerability). Then the film's next shot
  (`ShotTaken` to everyone: the camera, the film, the shot id, wrapping at 0x10000, and the record). A film keeps its
  shots whoever carries it until it is printed or vanishes.
- The box (the photo ADR §2.5, PE7, PE14, PD12, #782): a take gives the actor a fresh film through `GiveItem.give_new` (§9.4.2: the
  cap, `ItemSpawned` at the box, `Items.give`: into the hand, the hand item to the belt; beside a two-handed item onto
  the belt), nothing in the hands refusing it; its rule's `Cooldown` paces one player's takes; it gives after the
  task is done too. The film cap's order (PE10, `cap_tier`): a fresh film (0) first, then one with shots (1), the
  camera's film (2) last; within a tier the one that has lain longest. Every photo is tier 0: a tier by its shot's
  person would tell everyone through `ItemVanished` which photos hold one (PE5).
- The printer (the photo ADR §2.6, PD3, PD16 (a), PE8, PE11, #782): the actor's exposed film (the hand's, else the belt's) prints
  every shot once, in shot order: per shot the photo kind's cap (`GiveItem.make_room`), a photo on the tray
  (`ItemSpawned`), `PhotoPrinted` (the photo, the shot) and `item_rested` (spawn); then the film vanishes
  (`ItemVanished`). Unshot frames print nothing. Should the cap find no loose photo (the check's floor keeps it from
  happening) the film keeps the shots not printed and the match logs an error.
- The board (the photo ADR §2.7, PD6, PE9, PE11, #782): the actor's photo (the hand's, else the belt's) is hung. Its shot has a
  person: `PhotoHung` counted, the photo locked on the board for good (`Items.lock_at`; `PickUp` refuses it), then
  `Tasks.subtask_done` (`TaskState`, `TaskProgress`) with the photo and its shot as the detail. Else `PhotoHung` not
  counted and the photo lies on the board (`Items.lay_on_station`: `item_rested` on_station) for `PickUp`.
- Refusals (after `HandNotTwoHanded` (not at the box), `AtStation`, `StationInSight`; §9.4.1's `StationUsable`):
  `unavailable` at the photo spot, and once the task is done at every station but the box; at the box only the
  cap's `unavailable` (every film held, locked or flying); at a loaded camera `no_frames_left` when its film has
  `frames_per_film` shots; at an empty one `no_film` when the actor carries no film, `film_exposed` when every film it
  carries has a shot (PD16 (a)); at the printer `nothing_to_print` when no film the actor carries has a shot; at the
  board `no_photo` when it carries no photo. `use_reasons()` lists the six.
- Mode checks (PE12, `PhotoTask.check`): the parts above, the frame's numbers in bounds, and the caps (CE3's floor):
  the film's `max_items` at least twice the most players plus 1, the photo's at least twice the most players plus the
  setting's maximum plus `frames_per_film` plus 1.

Produces: `StationPlaced` and `ItemSpawned` (everyone) in the deal; `FilmLoaded`, `ShotTaken`, `PhotoPrinted`,
`PhotoHung`, `ItemSpawned`, `ItemVanished`, `ItemPlaced`, `ItemPickedUp`, `TaskState` and `TaskProgress` (everyone) on a
use (`use_emits`). Its task state (`PhotoTask.State`): the station ids, the tray, the photos to hang, the camera's
film and its move serial, the shots (film, tick, whether a person counted, who), the films that have them, the
printed photos and their shots, the counted shots, in `MatchState` (`ResetMatch` clears it).
Visible to: everyone, all of what is sent. No event names a player as the shooter (PD13); the record holds what every
player's snapshots show anyway, its own pose included (§5); nothing reads a role (§9.2).
Code (`core/`): `core/tasks/photo_task.gd`, `core/tasks/photo_frame.gd`,
`core/events/film_loaded_event.gd`, `core/events/shot_taken_event.gd`, `ItemState.moves`, `TaskType.layout_problems`,
the three reasons in `StationUsable.REASONS`, wire kinds 77 and 78 (protocol 24) with `WireBudget`'s 15-row
`ShotTaken` case; the box, the print and the hang in `core/tasks/photo_task.gd`,
`core/events/photo_printed_event.gd`, `core/events/photo_hung_event.gd`, `TaskType.cap_tier` and
`GiveItem.make_room` (§9.4.2), the reasons `nothing_to_print` and `no_photo`, wire kinds 83 and 84 (protocol 28).
Tests: `tests/unit/tasks/photo_deal_test.gd` (the deal, the exact demands, the layout problem), `photo_load_test.gd` (the
load, the camera's film through every lift and a recycled id, the refusals; planted "the camera ignores the move
serial" and "ignores the item's identity", each failed, reverted), `photo_shot_test.gd` (the frame's edge, the sight
line, the cylinder, the range, the record), `photo_check_test.gd` (PE12, the caps at and below the floor, the leak
lists, `use_emits`, no shot or print saying whether a person counted), `photo_role_swap_test.gd` (the whole chain; planted
"the frame skips dissidents" and "a dissident's hang counts nothing", each failed both, reverted), `photo_box_test.gd`
(the take, the belt, the cooldown, after done), `photo_print_test.gd` (shot order, the hand before the belt, the
refusals), `photo_hang_test.gd` (counted and locked, uncounted and taken down, the belt's photo, done, a wrapped shot id skipping the ids of live shots because the hang reads its shot by id),
`photo_cap_test.gd` (the tiers, the photo cap at a print, a recycled id; planted the tier-blind order and each
`_prune` call left out, each failed, reverted), `tests/unit/items/give_item_test.gd` (the tiered cap),
`photo_frame_test.gd`, `tests/unit/items/items_station_test.gd` (the move
serial), `tests/scenarios/record_invariant_test.gd` (§4.6.4's record invariant); fixtures
`tests/fixtures/tasks/fixture_photo_modes.gd`. Over the wire (#789, photo P10, the ADR's §8 and PE18):
`tests/integration/server/host_session_photo_test.gd` on `tests/fixtures/tasks/fixture_wire_photo.gd` (a fixture mode
dealing a fixture `PhotoTask` on its one map, whose path is the mode's `maps`, a key of the harness's `game_layouts`
and the type's `TaskType.maps`; its `PlacePlayers` is `ordered`): the host's client takes a film from the box and
stands on the photo spot, a second client is refused `no_film` at the empty camera, loads the dealt film, shoots the
first, takes the film out, prints it and hangs the photo, and a third stands beyond the record's reach; what each
decoded equals its `Match.view_of`, and `LeakCheck.check_bot` (its `record_tick` fed by the session's observer) runs
§4.6.4's record invariant over each decoded `ShotTaken`. Planted, each failed, reverted: `ShotTaken`'s wire row without
the rows' `facing` (the host refuses to start: "record: an undeclared field facing"), the decoded rows losing `facing`,
and the record builder's distance bound raised to 1000 m (a row 100 m off, caught by the decoded-side record
invariant). As in
cooking's C9, a server path that broadcasts what the filter should route stays unseen there (every photo event goes to
every player, and Round refuses joins) until bots play the photo task. And the box's flood guard and the film cap
against one peer's burst of takes (§4.6.5.3).
The client's flash and sounds: `client/world/photo_flashes.gd` (`PhotoFlashes`, under `ItemWorld`):
each `ShotTaken` at a camera the model knows lights one `OmniLight3D` at its lens (the station's marker plus the
client's own copy of the mode's eye height, as `PhotoTask`'s lens), `shadow_enabled` and `omni_range` 4 m (a light
without shadows passes through walls and would light a room where no eye sees the camera), no mesh, sprite or marker;
held on until `release(shot)` (the call P8's render makes once it has drawn; this light is that render's flash), at
least `PULSE_S` 0.1 s, and ended by the fallback at `HOLD_LIMIT_S` 1 s when no render calls (a headless client;
P8, §4.7.58, renders nothing there); the session's end ends every flash. `SoundChooser` places `ShotTaken`'s shutter at the lens,
`PhotoPrinted`'s print where the photo lies on the tray and `PhotoHung`'s at the board's marker (its ray aims
1 m up: a counted photo the task's success, one without a person its error, §4.7.60), each cut at the 12 m hearing
range; `WorldSounds` plays them muffled behind the level (M5-7), the shutter and the print with blips
built in code (`photo_blip()`, PD15) until the engineer's files arrive. Every number placeholders, "not a decision".
Tests: `tests/unit/client/world/photo_flashes_test.gd` (the light, its shadows and range, the hold with a test caller,
the shortest pulse, the fallback by `advance` and over the tree's frames, a recycled shot id; planted shadows off,
no hold and no fallback, each failed, reverted), `photo_sounds_test.gd` (the places, the cut-off, the blips, a
counted hang the success and an uncounted one the error; planted the photo sounds uncut, failed, reverted), `tests/integration/client/world/item_world_photo_test.gd` (off the
loopback wire through `ItemWorld`: the flash and the shutter at the lens, the print, the hang, the shutter muffled
behind a wall (planted unmuffled, failed, reverted), none beyond 12 m, the session's end).
The station scenes (provisional until the engineer approves them; the convention: the
[level piece ADR](decisions/2026-10-09-level-piece-conventions.md)'s "Station scenes"): `levels/stations/camera.tscn`
(the art's tripod turned so its lens looks along -Z, the shooter's use spot in `spawn_camera` behind it at +Z, its
collision below the shooter's eye line; `FilmSlot`, where P8 draws the loaded film (§4.7.58), and the hidden, depth-tested
`FramesLeft` `Label3D`), `photo_spot.tscn` (a floor ring of PD9's 2 m placeholder radius, no device, its marker in
`spawn_photo_spot` at the centre), `film_box.tscn` (greybox, `spawn_film_box`), `printer.tscn` (the art's desk,
computer and printer, `spawn_printer`, the `Tray` marker in `spawn_photo` on the printer) and `photo_board.tscn`
(`spawn_photo_board`, `Slots/Slot1` to `Slot10` on its face); the House's photo zone holds the spot (the gazebo's
centre, house-map §6), the camera 4.3 m east of it (beyond both reaches, PE12) and the first film's `spawn_film`
marker, storage the box, the study the printer, the darkroom the board, each in place of a plain marker; since P5's
data (#784) the base mode snaps their tags to the floor as station kinds. Tests: `tests/integration/levels/stations/station_scenes_test.gd`
(the convention, for the four devices), `photo_stations_test.gd` (the camera's eye line clear, its slot and counter,
the spot's mark, the printer's tray on its top, the board's slots on its face) and
`tests/integration/levels/house_photo_stations_test.gd` (the markers read once each at §6's points, a player clear
on each device's use spot on a whole floor, the spot beyond the camera's reach, the shooter seeing a subject on
the mark and not one behind the backdrop, the film beside the camera, no shared (x, z), no art copy left; the
camera moved 0.9 m nearer and a floor tile moved beside the board each failed it). The ADR's §8 House tests (P9,
#788) in `tests/integration/levels/house_photo_test.gd` (§9.7): the shipped base mode on the House in the host's
real world, `ScenarioInvariants` on every call and tick, the match replayed from its command log, with the leak plant
and the record plant (§4.6.4.1).

#### 9.5.23 Crouch (not a part in v0)
What it does: the `crouched` flag of `MoveClaim` (§7.1.17, the [crouch ADR](decisions/2026-10-10-crouch.md)): the
pose at the claim's last physics step. The host keeps it on a living player in any phase (#991) and judges the
claim with the crouched numbers in `PlayerRules` (`crouch_height_m` 1.2, `crouch_eye_height_m` 1.0,
`crouch_speed_mps` 2.0, `crouch_fast_speed_mps` 2.8; provisional, "not a decision").
Settings: none of its own since #991 (the engineer's change on #989: no per-map option, the crouch plays everywhere;
`PlayerRules.crouch_maps`, KE10, is gone).
Why not a part: as for sprint.
Visible to: the avatar's `crouched` flag is public in the snapshot, only for a living player.
Code: `core/movement/movement_rule.gd`; the numbers are `PlayerRules` in `core/content/player_rules.gd`.
Tests:
`tests/unit/movement/movement_rule_crouch_test.gd`, `tests/integration/server/host_session_crouch_test.gd`,
`tests/unit/content/content_modes_test.gd`.

#### 9.5.24 Sneak (not a part in v0)
What it does: the `sneaking` flag of `MoveClaim` (#989, #990, the [crouch ADR](decisions/2026-10-10-crouch.md)'s
second amendment of 2026-10-14): the pose at the claim's last physics step, standing, at `crouch_speed_mps`. The host
keeps it on a living player in any phase only when the claim does not also crouch (the crouch wins), ignores it on a
downed claim, and clears it at every placement, knockdown and respawn. Each listener's `WorldSounds` plays no step
of a sneaking pose whose measured step speed is at or below `crouch_speed_mps` plus
`FootstepCadence.SNEAK_SPEED_MARGIN_MPS` (0.2, kept as built: the engineer's answer 1a on PR #1007), so a claimed
sneak at a walk is heard.
Settings: the action `sneak` is a row of Settings › Controls (#1009, the deck key `control.sneak`), on the left Alt only: `apply()`
puts `project.godot`'s located event in the InputMap for a default binding, a rebind is the bare physical key.
Why not a part: as for sprint.
Visible to: the avatar's `sneaking` flag is public in the snapshot, only for a living, uncrouched player; never the
own avatar's (a living viewer never gets its own).
Code: `core/movement/movement_rule.gd`; the listener's side, `FootstepCadence` and `WorldSounds` in `client/world/`.
Tests: `tests/unit/movement/movement_rule_sneak_test.gd`,
`tests/integration/server/host_session_sneak_test.gd`, `tests/integration/client/player/player_controller_sneak_test.gd`,
`tests/unit/client/world/footstep_cadence_test.gd`, `tests/integration/client/world/world_sounds_steps_test.gd`.

#### 9.5.25 Delivery by meaning (task type)
What it does (the [Delivery by meaning ADR](decisions/2026-10-10-delivery-by-meaning.md) §2, the engineer's DD2, DD5,
DD6 and DD8, each (a)): the House's Delivery. One shared task of `packages` items; each item is carried to the one
place where its kind belongs, its route's drop-off, found by what the item is: no colours, no marker through walls.
A subtask is done when its item rests on the ground inside its own drop-off, however it got there (§7.1.14); an item
in another route's place does nothing. Nobody owns the task: any living player delivers any item.
The deal (§3.3; ADR §2.1): the routes shuffled (`tasks`); route at shuffled position *p* gets floor(N / K) items plus
one if *p* < N mod K (N the setting, K the routes), so every route has an item before any has a second. One station
per drop-off that got an item, on its tag's one marker, station ids in `routes` order of first appearance; the items
on distinct random free markers of their spawn tag (`packages`), item ids in the markers' level order; subtask *i* is
item *i*. A drop-off is done once every item routed to it is delivered (DE7). With N = 0 the task has no subtasks.
Maps (`TaskType.maps`): the House alone; the greybox plays Delivery by colours (§9.5.4).
Settings (`content/tasks/delivery.tres`, id `delivery`, display name "Delivery", DE15 (i)): `routes`, an array of
`DeliveryRoute` (`core/tasks/delivery_route.gd`: `item`, an `ItemKind`; `drop_off`, a `StationKind` with no palette):
Wine (`wine`) to the dining table (`drop_dining_table`), Motor oil (`oil`) to the workbench (`drop_workbench`), Garden
gnome (`gnome`) to the garden (`drop_garden`), Parasol (`parasol`) to the terrace table (`drop_terrace_table`); each
drop-off a cylinder of radius 1 m and height 2 m (DD3; the height a placeholder, "not a decision") on its one marker
(D1, #826), each marker at the furniture the drop-off is named after, whose layer-1 top an item may rest on (D4,
#831: the art's dining table, terrace table with a parasol stand beside it, workbench and garden drop-off; §9.6);
each item kind two-handed with the shared `package` spawn tag (DD6 (a), DD8 (a)), placed among the
packages' storage markers. `subtasks_setting`: `packages` (the same lobby row as Delivery by colours); RNG purposes
`packages_rng`, `tasks_rng` (`packages`, `tasks`). `station_kinds()` is its routes' drop-offs, each once, in `routes`
order (D2a's override, #827); `item_spawn_tags()` its kinds' tags, each once.
`description`: "Carry each item from storage to the place where it belongs. Every item takes both hands."
Demands (§9.6, DE6): while N > 0, exactly one marker of each drop-off's tag, and per item spawn tag the most items a
draw can put there, min(N, r × floor(N / K) + min(r, N mod K)) with r the routes whose kind has that tag. No colours.
Checks (DE13, `DeliveryByMeaning.check`): `routes` not empty; each route with an item kind the mode declares, with a
spawn tag, that does not vanish (the task knows an item by its id, and a vanished item's id is reused), and a
drop-off; no kind in two routes; no palette on a drop-off; no drop-off tag equal to an item tag (an item would spawn
delivered); both RNG purposes set; ZE3 across the mode through `station_kinds()`.
Produces: `StationPlaced` (white, no palette, DE5 (b)), `ItemSpawned` (its drop-off station, white) in the deal;
`PackageDelivered`, `TaskState`, `TaskProgress` on a delivery; no new event, no wire change.
Visible to: everyone; it deals no private event (the leak test's per-peer filter holds by construction).
Client: `ClientModel` sets a drop-off done only when no undelivered item names it (§4.6.1.2); the lobby's ban chips,
the guide's cards and the loading card list only the types that play on the picked or the match's map, the mode's
default map before one is known (DE16, `HowtoCards.shown_map`, §4.7.36, §4.7.42). Until D3 gives a drop-off its own
look (DE11), `CircleViews` draws it as a circle in the white it is placed with.
Code: `core/tasks/delivery_by_meaning.gd`, `core/tasks/delivery_route.gd`; `content/tasks/delivery.tres`,
`content/items/wine.tres`, `oil.tres`, `gnome.tres`, `parasol.tres` (provisional, the engineer approves them in the
PR); the House has no circles, and its drop-offs have their furniture (D4). Tests (fixtures, never the House's data, §9.6):
`tests/unit/tasks/delivery_by_meaning_deal_test.gd`, `delivery_by_meaning_check_test.gd` (the on-rest check, DE7),
`delivery_by_meaning_demands_test.gd`, `delivery_by_meaning_mode_check_test.gd`, `delivery_by_meaning_filter_test.gd`
(every peer gets the same task events), on `tests/fixtures/tasks/fixture_meaning_modes.gd`;
`tests/unit/client/net/client_model_test.gd` (DE7's fold), `client_model_wire_roundtrip_test.gd` (the deal's
StationPlaced, ItemSpawned and PackageDelivered through WireSchema into ClientModel, two items on one drop-off: no bot
carries them over the wire), `tests/unit/client/ui/lobby_panel_maps_test.gd` and `guide_panel_test.gd` (DE16);
`tests/unit/content/delivery_content_test.gd` (each Delivery's `maps`: one map of the base mode each, the two apart,
neither the tutorial's); the House's markers (DE12: one marker per drop-off, no item marker inside one; ZE9's
spacing against the drop-offs) in `tests/integration/levels/house_markers_test.gd`; an item put on each drop-off's
furniture rests inside its cylinder (#831) in `tests/integration/levels/house_drop_offs_test.gd`; items delivered
through a Match in the host's world on each drop-off's floor and furniture top, not past a wall (D5, #832) in
`tests/integration/levels/house_delivery_test.gd` (§9.7); both tasks
dealt and the round won on the House in `tests/integration/levels/house_zone_test.gd` and `tests/unit/content/zone_base_mode_test.gd`. No bot
plays it: the scenarios and the leak test play the greybox's Delivery by colours (§9.7).

### 9.6 Where the MVP's data and scenes live (provisional)
```
content/
  modes/base_mode.tres             the base mode: phases, rows, PickUp, PutDown and voice rules inside it
  modes/tutorial_mode.tres         the tutorial's solo session (§9.5.17, #600), on levels/tutorial/
  roles/crew.tres, roles/dissident.tres
  items/package.tres, items/knife.tres        the knife's Use rule inside it
  items/wine.tres, oil.tres, gnome.tres, parasol.tres   the House's Delivery items (#828, §9.5.25)
  items/film.tres, photo.tres      the photo task's items (#784, §9.5.22)
  items/bun_*.tres, patty_*.tres, basil.tres ... box_*.tres   Cooking's 21 items (#775, §9.5.20)
  items/car_part_green.tres, car_part_blue.tres, car_part_yellow.tres   car repair's parts (#810, §9.5.21)
  tasks/delivery.tres              the House's Delivery by meaning, its routes and drop-offs inside it (#828)
  tasks/colour_delivery.tres       the greybox's Delivery by colours, with its circle station inside it
  tasks/hold_the_zone.tres         the zone task, with its zone station inside it (#649)
  tasks/generator.tres             the Generator, with its generator and switch station kinds inside it (#800)
  tasks/photo.tres                 the photo task, with its five station kinds inside it (#784)
  tasks/cooking.tres               Cooking, with its five station kinds inside it (#775)
  tasks/car_repair.tres            car repair, with its car, lift panel, three bins and picture inside it (#810)
  win_conditions/every_task_done.tres, no_crew_present.tres, time_up.tres
  scenarios/                       bot scenarios (§9.7), one per file
  howto/tasks/delivery.tres, colour_delivery.tres, generator.tres, photo.tres, cooking.tres, car_repair.tres   a task type's how-to card, one per task type (#254, §4.7.36; client data, not the mode's)
  howto/basics/moving.tres, voice.tres, downed.tres   the Esc menu Guide's basics
  tutorial/tutorial.tres           the tutorial's nine lessons (#602, §4.7.46; client data on core/content/tutorial/)
levels/
  lobby/lobby.tscn                 the lobby: floor, walls, lobby_player markers
  greybox/greybox.tscn             the test bench (#767; the MVP map until then), never offered to players: rooms and
                                   round_player, package, knife, circle, respawn and zone markers
  tutorial/tutorial.tscn           the tutorial's map: it only places its one room (#600)
  tutorial/rooms/tutorial_room.tscn   the tutorial room: a greybox with its players' and items' markers
  stations/switch.tscn, generator.tscn   the Generator's devices with their use spots (#799), in House's basement
  stations/camera.tscn, photo_spot.tscn, film_box.tscn, printer.tscn, photo_board.tscn   the photo task's stations
                                   (#783), in House's photo zone, storage, study and darkroom
  stations/order_board.tscn, herb_board.tscn, grill.tscn, place.tscn, herb_beds.tscn, bun_shelf.tscn, freezer.tscn
                                   the cooking task's stations (#774), in House's kitchen, storage, chill zone and
                                   greenhouse
  props/parasol_stand.tscn         the terrace table's empty parasol stand, the parasol's sign (#831): primitive
                                   meshes, primitive layer-1 colliders (no GLB); the House's other drop-offs stand
                                   at the art's furniture (§9.5.25)
```
- **Provisional.** The engineer's agent builds them under the MVP content ADR, each PR with the engineer's approval;
  the designer adopts or replaces them in #38, and the level conventions of M4 (`new-level-piece`) may move the
  scenes.
- **The tutorial room** (T2, #600; `docs/design/tutorial.md` §4, D33, D34 (a): one room, named "Tutorial" /
  "Навчання"). Built by the level piece conventions (#607): the map places the room at the origin with no rotation;
  the room's origin is its north-west floor corner and it declares `metadata/size_m = Vector2i(12, 10)` (about 12 ×
  10 m, a placeholder, D33), an empty `Doors` (no opening) and an empty `Stations` (no task, no station since #900,
  LE4 (a)), a `Name` label "Tutorial", and box-mesh looks over one layer-1 `StaticBody3D`: the floor (top at y = 0),
  four 3 m walls and the two props, a shelf (2 × 1.8 × 0.5 m) and a table (1.6 × 0.8 × 0.8 m) against the north
  wall. Its looks use `levels/kit/`'s role materials (#658): `greybox_floor_house` on the floor, `greybox_material`
  on the walls and props. The markers, all on the floor in scene-tree (level) order, positions (x, z) in metres
  (placeholders, "not a decision"): `round_player` Start (2, 5) by the west wall, `package` ShelfPackage (4, 1.3)
  in front of the shelf, `knife` TableKnife (8.5, 1.6) in front of the table (#900 removed the `circle` DropOff,
  LE4 (a)), `round_player` RaiseSpot (10.5, 3) by the east wall, `round_player`
  Corner (10.5, 8.5) and `respawn` Respawn (8.5, 8.5), 2 m from the corner (more than `respawn_free_m`, within
  RoundVoice's 8 m). The ordered `PlacePlayers` puts the own player on Start, stand-in 1 on RaiseSpot and
  stand-in 2 in the Corner. No `lobby_player` marker and no lobby scene (`gather` plays at no level, E72). The
  environment track dresses it and keeps every marker where it is.
  The room's map record (#306's shape, §4.7.33) is #715's (the follow-up named in #600's PR).
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
  group named `spawn_` alone are load errors. The markers of the station kinds' spawn tags (`circle`, `zone`, the House's `drop_*`) are snapped
  down to the floor that the host's `WorldQuery` finds below them (asked from 0.1 m above, so a marker a hair under
  the floor still finds it), and one with no floor below is a load error (the engineer's answer on #82, item 3).
  The players' markers (`round_player`, `respawn`) are read as placed: on the House,
  `tests/integration/levels/house_markers_test.gd` checks each `round_player` and `respawn` marker stands within
  2 cm of the floor under it with a standing capsule clear of the level (#1042).
  This convention is provisional until 4e settles it with the designer (§10).
- **Tests and content.** A part's unit tests build their data in code or in `tests/fixtures/` and never load
  `content/` or `levels/`. Only the mode check (§9.1) with the content tests beside it (`tests/unit/content/`, and
  `tests/unit/levels/` or `tests/integration/levels/` for a map against its design) and the scenarios load them,
  so a change to `content/` can break a scenario or a content test, which is what they are for, and never a
  part's unit test.

### 9.7 Bot scenarios
A bot scenario is a scripted match that shows a mechanic working end to end, played only with what each player is
told. One format runs in two runners.
- **Format:** a `BotScenario` resource, `content/scenarios/<name>.tres`, written by whoever owns the mechanic: the
  designer from M3 (`docs/AGENT_WORKFLOW.md` §12), the engineer's agent for the MVP. Its classes (the scenario, its
  steps and targets) are data only and live in `core/content/scenario/` (§9.3), so `content/` still uses only the
  content API; the runners live in `tests/harness/`. It holds:
  - the setup: the mode; the map, one of the mode's maps (none named: the mode's first test bench, `bench_maps`, else
    its default map; `BotScenario.played_map()`, #767, which the setup's `ChangeSettings` sends when it is not the
    default); the seed; the number of bots (bot 1 is the host's own
    client); the match settings that differ from the defaults, numbers (`settings`) and sets of task type ids (`id_sets`: the host's bans, #79; M7-Z2), which `problems()` checks as the lobby would: a set the mode does not declare, an id that is none of its task types, and bans that leave fewer types than `tasks` are refused, so a ban of one of two types also lowers `tasks` in the same setup (`DealTasks.settings_problem`); roles forced per bot (debug builds only, invariant 8;
    otherwise the deal draws them from the seed); the match clock's length in seconds, forced with the debug command
    `ForceClock` in place of `match_duration`'s whole minutes (`clock_s`, M4-3; 0 keeps the setting). By default every
    bot joins (sends `Hello`) at the start and acknowledges every `LoadMatch` at once; the steps `Join` and `LoadAck`
    change that for one bot;
  - one script per bot, whose steps run in order; the bots run at the same time;
  - the expected ends, one per match the scenario plays, in order: a winning side, or `none`. `none` passes when every
    script has finished within the time limit and no further `MatchEnded` arrived. Steps may follow an end, so a
    scenario can go back to the lobby and play a second match (seed *k*+1, §3.3). A time limit for the whole run;
  - `never`: events that one bot, or every bot, must never receive. Every runner hands `problems()` the events a bot
    can receive (`ScenarioBot.receivable_events()`: the wire schema's event rows, their fields, and `peer` on the
    events for one peer), so a `never`, `Expect`, `ExpectNone` or `WaitFor` that names another event or a field its
    event lacks is refused before the run (#1235: a misspelled one never matches and would pass forever);
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
| `Join(at_s, deadline_s)` | sends `Hello` `at_s` seconds after the start instead of at once (a late join that cancels the countdown, or one refused in Loading); directly after the bot's own `Leave` it joins again on a peer id new to the session, and a `joins_closed` or a refused connection tries again every 0.5 s until `deadline_s` (P12 (a), (t2) of the returning-players ADR; #639) | its `Welcome` arrives |
| `LoadAck(skip)` | answers the next `LoadMatch`: with `skip`, never, so the loading deadline drops it | the ack is sent, or skipped |
| `Ready(ready)` | sends `SetReady` | its `ReadyChanged` arrives |
| `Setting(id, value)` | (the host's bot) sends `ChangeSettings` | `SettingsChanged` arrives |
| `ReturnToLobby` | (the host's bot) sends `ReturnToLobby`, the shortcut: End returns everyone by itself after 3 s (#212), which `WaitFor(PhaseChanged, lobby)` waits for | `PhaseChanged` to the lobby arrives |
| `WaitFor(event, fields)` | waits | it receives a matching event |
| `Wait(seconds)` | waits | the time has passed |
| `WalkTo(target, sprint, stop_m)` | sends honest `MoveClaim`s at walk or sprint speed (a dead bot cannot walk and fails the step, M4-2, nor a knocked-down one, which holds still, #728), straight towards the target; a level with walls needs waypoints | it is within `stop_m` (0.5) of the target: 1 m before a circle, the put-down distance, to deliver |
| `PickUp(target)` | faces the item and sends `PickUp` | its `ItemPickedUp` arrives |
| `PutDown(towards)` | faces the target and sends `PutDown` | its `ItemPlaced` arrives |
| `Throw(towards, pitch_deg)` | faces the target flat, tilts that facing up by `pitch_deg` (-90 to 90) and sends `Throw`; standing on the target with a pitch other than ±90 fails the step (a zero facing would throw along the last one) | its `ItemThrown` of the item it held arrives (a `WaitFor` of `ItemPlaced` with cause `thrown` waits for the rest) |
| `Use(towards, until)` | faces the target and sends `Use` | the event `until` names arrives for this bot (default `Swung`, the knife's; an item whose `Use` emits something else names that) |
| `Interact(station, until)` | sends `Interact` naming the station a `station(kind, n)` target finds (`ScenarioBot.station_of`), or with `item` in its place (#1209) the item a `nearest(kind)` target finds (`ScenarioBot.item_of`: the nearest of that kind lying on the ground, such as Cooking's boxes); no facing: the host checks reach and sight from the bot's position, so a `WalkTo` to it comes first; a station or item the bot was told of none of fails the step (#796) | the event `until` names arrives for this bot, or names no peer (no default: a use emits its task type's events); with `expect_rejected` and no `until`, that `Rejected` |
| `Jump` | claims a jump | the claim is sent |
| `Expect(event, fields, within)` | checks | it received a matching event since its previous step, or within `within` seconds |
| `ExpectNone(event, fields, for_s)` | checks | no matching event arrived for `for_s` seconds; the first one fails the step |
| `Leave` | disconnects | at once |
| `Raise(target, hold_s)` | sends `Raise` of the player of a `bot(i)` target and holds E (M4-4) | its `RaiseStarted` arrived and `hold_s` passed since the step started, or the raise ended before (its `RaiseStopped`, or a `Revived` of the target); the bot still holds E after it |
| `StopRaise` | sends `StopRaise`: lets go of E (M4-4) | its `RaiseStopped` arrives (`not_channeling` when no raise runs) |
| `GiveUp` | the downed bot sends `GiveUp` (M4-4) | its own `Died` arrives |
| `Swap` | sends `Swap`: exchanges its hand and belt items (M4-5) | its own `Swapped` arrives (`nothing_to_swap`, `two_handed` when refused) |
| `NextStage` | (the host's bot) sends `NextStage`: a scripted mode (the tutorial's stages) moves on (#599) | a `PhaseChanged` arrives, whichever phase (an `Expect` after it names one); the base mode refuses it (`not_accepted`). `tests/scenarios/next_stage_step_test.gd` |
| `Talk(talking)` | turns its synthetic voice off, or on again (M5-4); the core runner has no voice and only records it | at once |

The classes (`core/content/scenario/`: `BotScenario`, `BotScript`, `NeverEvent`, `ScenarioTarget`, and one class
per step, `StepJoin` to `StepLeave`, whose `problems()` report an unplayable setup before a run):
- `Join` also takes `expect_rejected` (it sends `Hello`). `Ready`, `Setting`, `ReturnToLobby`, `PickUp`, `PutDown`,
  `Throw` and `Use` are done by their own answer: the bot's `ReadyChanged`, a `SettingsChanged` holding the value, the
  `PhaseChanged` to `lobby`, its `ItemPickedUp` of that item, `ItemPlaced` (put down) and `ItemThrown` of the item it
  held, and
  `until` naming this bot when the event has a `peer`.
- `WaitFor` and `ExpectNone` look at the events from their own start; `Expect` also at those since the previous
  step started, so it sees what arrived with the previous step's answer (a `PackageDelivered` after a
  `PutDown`). `Expect` with `within` 0 checks only what already arrived. A bot runs its steps in one tick until
  one waits or sends; before its `Welcome` only `Join` runs, so a `Join` is a script's first step, or directly follows
  the bot's own `Leave` (not bot 1's: the host's own client does not join again), with `deadline_s` above `at_s`
  there and 0 on a first `Join` (`BotScenario.problems()`). The step after a `Leave` waits for the next tick. A refused
  or failed try is dropped and the next one starts on a new connection; past `deadline_s` the step fails naming the
  last refusal (#639).
- `LoadAck` answers the `LoadMatch` that arrives while it is the bot's current step; one that arrived during an
  earlier step was acknowledged at once, and the `LoadAck` step then fails, saying so. A `Join` refused in Loading
  cannot be scripted in the core runner: `server/` refuses it at the transport, so the step fails.
- `WalkTo` claims one host tick of travel per tick (client ticks rising by one), at sprint speed only while the
  last `SelfStatus` says sprint is available in the core runner, and over the network while the bot's own
  `PredictedStamina`, settled by its claims, says so (#155), and stops exactly
  `stop_m` short. A dead bot claims nothing at all, standing or walking (M4-2), and a knocked-down bot's `WalkTo` fails the step (#728).
  `Jump` claims a jump where the bot stands, on the floor: the bot's jump count in its epoch plus one (3e; D3 (a),
  the designer's answer on #96: the step names what a player does, not the count the wire carries). The setup's forced roles go in one `ForceRole` per bot
  right after the joins at the start, and its settings and sets in one `ChangeSettings` from bot 1 after them (`BotScenario.setup_change()`, in both runners).
- `fields` match a subset of the event's payload, as the bot received it (name and fields): text as text, numbers
  and vectors approximately, and `peer` (and the raise events' `raiser` and `target`, M4-4) holds a bot's number, mapped through the runner's `ScenarioPeers`, which keeps a returning bot's earlier peer ids (`peers_of`, `bot_of` maps
  each back to the bot; a `Never` names every one; #639); an event
  for one peer whose payload names none (`SelfStatus`) matches `peer` as the bot that received it (3h). `never` names an event, fields and a
  bot (0: every bot).

- **Targets come from the bot's own view**, the events and snapshots its client received: `package(n)` (the n-th
  package in item-id order, from 1; tasks are shared, #79), `circle_of_held` (of its hand item), `nearest(kind)` (on
  the ground: not in a hand or on a belt, which the bot follows from `ItemPickedUp`'s `belted` and `Swapped`, M4-5), `bot(i)` (where it last saw
  that player), `point(x, y, z)`, `station(kind, n)` (the n-th station, from 1, of that `StationKind` id in station-id order, from the bot's own `StationPlaced`s; a `WalkTo` to it takes `stop_m` 0, and the runners' arrival slack of 1 mm ends the walk: M7-Z2, ZE7 (a), for the zone task, whose zone the bot finds only this way; an `Interact` step names its station only this way, #796). A target the bot cannot know fails the scenario, so a scenario also proves that the
  mechanic is playable with what a player is told.
- **Failures:** a step that sends an intent fails on a `Rejected` it did not expect and names the reason; a step that
  does not finish within the time limit fails; a `Correction` outside a placement (§3.2), the bot's own knockdown
  (M4-2), its own respawn (M4-3) or its own revive (#728 KE6) fails, because an honest bot is never corrected, so
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
    `DisconnectPeer`, after which the bot is gone and its `PeerLeft` follows on the next tick. Its `Hello` asks for no
    name (the host names each player `Player<n>`, as for the network bots) and carries the bot's return key,
    `ScenarioBot.key_of(n)`, fixed from its number, as every runner's does (#639); a returning bot's earlier
    connections keep their events, each checked against `view_of` of its own peer id. A bot that stands still
    claims where it stands every tick, as every `ClientSession` does, so the host settles its stamina as it stands
    (M4-3). Until `server/`'s
    `WorldQuery` exists (M3) a flat fake answers the geometry (`FlatWorldQuery`, one floor at y = 0): the levels
    give their markers only, read into `LevelLayout`s by `server/`'s `MarkerReader`. The §5 invariants are
    checked from the match state's truth after every step and tick, never from an event's `audience()`: proven by
    declaring `Teammates` to everyone, which fails the suite. No `error:` line in `Match.diagnostics` (every match
    error of `core/`) stands in for the log's `ERROR:` lines. The MVP's scenarios play on the flat, marker-only
    lobby and map (§9.6). Only the levels the scenarios play on must be flat: the mode's lobby, the map
    a scenario plays when it names none (the base mode's test bench, the greybox, #767) and any map a scenario names
    (`tests/fixtures/scenario_levels.gd`), but the storeyed maps (`ScenarioLevels.STOREYED_MAPS`: the House). The
    four-level House (#626), the one map players play (#767), is played by people in the host's real world, and since
    #1197 by bot scenarios (below); the runners
    read its markers, and those of every map no scenario plays, where the scene puts them, none snapped to a floor (`MarkerReader.read_levels`'s `unsnapped`,
    `ScenarioLevels.unsnapped`; GE12, #798): a station marker (a delivery
    circle, a zone, a basement device) may stand on any storey, and markers of different tags may share an
    (x, z). Since #1209 a scenario on the House plays in a fake world with its storeys and stairs
    (`ScenarioLevels.world_of`, `tests/fixtures/storeyed_world.gd`; every other scenario keeps `FlatWorldQuery`):
    `FlatWorldQuery`'s arithmetic with three floors (the basement -3.2, the ground floor 0, the second floor 3.2;
    the attic, which no task uses, is left out) joined by flights of stairs, each a straight ramp between two ends
    and 1.2 m wide (`ScenarioLevels.HOUSE_FLIGHTS`: the pantry stairs, two flights and their landing, and the
    external stairs, one flight; the ends follow the walks over the real stairs in `house_cooking_test`'s
    `PANTRY_UP` and `house_photo_test`'s `UPSTAIRS`), a storey's floor cut out over a flight (the stairwell). On
    any other level (the lobby, which `Match` names with `use_level`) it is one floor at y 0. A remote bot instance
    (`bots --instances`) has no `Match` to name the level, so its world stays on the storeys: a House scenario run
    over ENet keeps its lobby walks off the stairs. Each position a walk
    claims stands on the floor found from a step and the claim's travel (the steepest floor, 45°) above the
    bot's feet (`scenario_play.gd`), so a bot climbs a step or a flight, even after a stall that makes one claim span
    several ticks, and walks down one; a drop past that reach is a fall, which the host does not bound (§7.1): the step fails (`route it over the stairs`), so a bot changes
    storey only over the stairs, through waypoints, and a ground walk keeps off the pantry's stairwell. The fake has none of the House's walls,
    so the bots walk straight and see everything, which the wire checks do not depend on. A flat level a scenario plays is still snapped. `content_modes_test.gd` reads every map so (each House station, drop-off and storage marker stands on a storey of the fake; a flat map's on its one floor); ZE9's zone spacing, which the fake would misjudge across storeys, is read in the host's world
    (`zone_content_test.gd`). One GdUnit4 suite, `tests/scenarios/scenarios_test.gd`, runs every scenario in
    `content/scenarios/` and replays each match from its command log (the same events to the same peers), so
    `test` and `verify` run them from stage 2 on; `tests/scenarios/scenario_runner_test.gd` sees each kind of
    failure fail once. `tests/scenarios/leave_and_return_test.gd` (#639) plays a leave and a return in the core
    runner and over the loopback (new peer ids, the kept number, the retries until the lobby, a deadline that fails,
    the fixed keys, a decoded key as a leak, the invariants failing a planted key, a refused try that decoded more than its Rejected), and `scenario_peers_test.gd` the peers map.
  - *Bots* (M3, 3h): `tools\run.cmd bots [scenario]` starts a headless host, whose own client is bot 1, and the other
    bots as headless clients: over `LoopbackHub` in one process by default, stepped by a simulated clock, or over ENet
    on 127.0.0.1 with `--instances`, on the real clock. It plays the core runner's steps and checks its
    `ScenarioInvariants` (per `Match` call, through `HostSession`'s observer, §4.5), with `HostSession` in the place
    of the runner's stand-in for `server/` (§4.6). The same files; it joins `verify` with the leak test (§5). Each bot sees only its `ClientSession`'s decoded view (§4.6.1).
    Code: `tests/harness/bots/`, `tools\run.cmd bots`, tested by `tests/scenarios/bots_runner_test.gd`.
  - *Perf* (#187): `tests/harness/perf/` plays a seeded 10-bot match through `HostSession` and meters it from the
    harness side for `tools\run.cmd perf`, not a `verify` step (`docs/AGENT_WORKFLOW.md` §11.10). Its match
    (`PerfScenario`) keeps the default draw of the shipped base mode, Delivery alone, since #804 (from #649 it also
    dealt a zone on the greybox, on `FixtureBaseModeWithZones` from #842, and metered `ZoneProgress`; the greybox's
    zones went with GD13 (b)).
- **Reproducing a failure:** the runner prints the bot, the step, that bot's last events and the seed; the command log
  replays the match (§3.3).
- **The MVP's scenarios** (2j, #66; provisional under the MVP content ADR, for the engineer's approval), in
  `content/scenarios/`: `crew_delivers_every_package` (3 crew deliver the 6 packages; a delivered package's
  `PickUp` is `unavailable`; the crew never get `Teammates`), `dissident_kills_the_crew` (rewritten in M4-2: a
  forced dissident takes a knife and knocks both crew down; `too_soon`; a downed bot is not hit again, its `PickUp` is
  `not_accepted`; both die at the end of their knockdown and a dead bot's `PickUp` is `not_accepted`;
  the match ends by time up, every crew member dead but present, on a 40 s clock (`clock_s`, M4-3); the `bots-enet`
  step, and over WebRTC `bots-webrtc`, §4.6.7), `crew_respawns_invulnerable` (M4-3: a crew bot is knocked down, dies and respawns 30 s later at a
  `respawn` marker; the dissident sprints to it and swings within its 3 s of invulnerability, which brings no
  `Damaged`, then swings again after them, which does; the match ends by time up on a 55 s clock),
  `crew_revives_the_downed` (M4-4: a dissident knocks a crew bot down and another crew bot raises it for 3 s; it
  stands with 50 health; nobody dies and no raise stops; time up on a 30 s clock; also run once over ENet,
  `tools/run.sh bots crew_revives_the_downed --instances 3`, not a `verify` step), `raise_stopped_then_given_up`
  (M4-4: a raise let go after 1 s, a second raise, the downed bot gives up during it (`RaiseStopped`, `Died`), a late
  `StopRaise` gets `not_channeling`, and the bot respawns 30 s later; time up on a 55 s clock),
  `dissidents_win_by_the_clock` (a 1-minute match that runs out; a jump, a sprint that runs out of stamina; End's
  return to the lobby with no intent, #212),
  `leave_and_return_keep_the_number` (#639, provisional: three bots join, bot 3 a `Join` 3 s in so that the numbers
  follow bot order over a network too; bot 2 leaves the lobby once it saw that join, bot 4 joins as Player4, bot 2
  returns as Player2; in the round bot 3 leaves and, after `ReturnToLobby`, returns as Player3; the `bots-enet` and
  `bots-webrtc` steps play it with 4 instances after `dissident_kills_the_crew`),
  `late_join_cancels_the_countdown`, `dropped_at_the_loading_deadline` and `refusals` (`nothing_to_swap`,
  `empty_hand`, `nothing_to_do`, `out_of_reach`, `too_soon`, `tired`; since M4-5 its knife goes to the belt when it
  picks up the package, a `Swap` is then `two_handed`, and after the package is put down a `Swap` draws the knife).
  M4-5 (#141): `crew_downed_before_a_delivery` (a dissident knocks a crew bot down, then another crew bot delivers the
  only package: the scenario the leak test needs to see a misdeclared `TaskState`, §4.6.4.1),
  `two_handed_pickup_with_a_full_belt` (a knife to the belt, a second in the hand, then the package: the hand knife
  rests where the package lay, and a `Swap` is `two_handed`), `dissident_hides_a_package` (a dissident carries the
  package to a corner and puts it down; a crew bot finds it with `nearest(package)` and delivers it) and
  `crew_walks_after_a_respawn` (`crew_respawns_invulnerable`'s match, where the respawned bot walks at once: the
  network runner's travel after a respawn). #646: `crew_throws_a_package_into_its_circle` (a crew bot picks up the
  only package, walks to 3.6 m short of its circle and throws it 45 degrees up with the base mode's `Throw` rule; it
  rests in the circle and is delivered, TD4 (a), and the crew wins). The first
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
  Delivery by meaning (#828, §9.5.25) has no bot scenario either: it plays on the House alone (DD9 (c)). The greybox,
  where every scenario, the chaos bots and `bots` play, keeps today's Delivery by colours (`colour_delivery`, §9.5.4),
  so no scenario changed; the House's Delivery is tested without bots: its unit tests on fixture modes, its markers in
  `house_markers_test.gd`, both tasks dealt and the crew's win on the House in `house_zone_test.gd` (below), and the
  ADR's §7 House tests (D5, #832) in `tests/integration/levels/house_delivery_test.gd`: the shipped base mode on the
  House (one task, the Generator banned: the mode deals both) in the host's real world (`HostWorldQuery.for_mode`,
  `MarkerReader.read_levels`), `ScenarioInvariants`
  checking every call and tick, the carrier placed at each spot. Two items put down on the floor inside each
  drop-off near its rim are delivered (the drop-off done with the second), one put on its furniture's top too (the
  highest top a player can put it on: the table or the bench, D4's), and one put down in the room past the wall
  nearest the drop-off at eye height is not, then is once carried back. Horizontal rays from each marker, above its
  furniture (1 to 1.9 m), reach no point of its cylinder past a wall: hidden both ways, so a cylinder may end inside
  a wall, never past it. Every drop-off and storage
  marker reads without an error, each on a floor. Every spot is found in the host's world, none written down.
  The zone task has no bot scenario since #804 (GD13 (b) of the [Generator
  ADR](decisions/2026-10-10-generator-task.md): the zone task plays on the House alone, which bots then did not play; #1197 plays only the station tasks). The
  three that played the greybox's zones from #649 (M7-Z3; `crew_works_every_zone`, `zone_paused_by_a_knockdown`,
  `dissident_works_a_zone_alone`; in `tests/fixtures/scenarios/` from #842) are deleted, and their checks live in
  `tests/integration/levels/house_zone_test.gd`, with no bot: the House in the host's real world
  (`HostWorldQuery.for_mode`, `MarkerReader.read_levels`), `ScenarioInvariants` checking every event of every call and
  every tick, players placed at their spots and claiming from there. The crew works every zone (the zone and the
  package; the crew wins), a dissident alone fills the zone (ZD3; the crew wins), and a dissident's knife knocks down
  the crew player holding the zone from outside it: everyone hears `ZoneProgress` stop, it does not count while the
  player is down though the dissident stands by, and after the raise from outside the zone it counts again and fills.
  Seen failing with `ZoneProgress` declared to the crew alone, to the zone's first player alone (the leak plant,
  §4.6.4.1), and with a downed player counted (`_anyone_inside` reading `DEAD` for not alive); each reverted.
  `ZoneProgress` over the wire and a freeze in a zone: `host_session_zone_test.gd` (§4.6.5.3).
  The Generator (§9.5.19) had no bot scenario (GD7, GD13: it plays on the House alone) until #1197's basement
  scenario (below), which plays it in the fake world (since #1209 down its pantry stairs). What stands in for its scenarios in the House's own
  geometry is `tests/integration/levels/house_generator_test.gd` (#802, G7), built as `house_zone_test.gd`: the shipped
  base mode on the House in the host's real world, three players with forced roles, the `switches` setting sent in the
  setup's `ChangeSettings`, `ScenarioInvariants` on every call and tick. The five markers read without errors and each
  holds a station; with four active switches a player on each use spot (a dissident among them) uses its station and
  the button starts the charge; a full charge from scripted commands (60 s of host ticks, everyone claiming), after
  which a press and a switch are refused `unavailable` and the round goes on (Delivery is not done); with two active
  switches the two markers the deal left hold no station (GE14). The refusals in the House's own geometry: behind the
  generator's body, inside its cylinder, `blocked`; in plain sight 2.5 m from it `out_of_reach`. At GD6's 2 m no
  standing spot of another room lies inside a switch's cylinder (a one-off probe of #802, not kept in the repo, found
  the nearest 3 m from switch A, in the darkroom; 3.35 m from B, in the darkroom; 3.45 m from D, in the hall; none
  within 4 m of C; the generator's cylinder was not probed for one), so a player in the
  darkroom behind the storage's wall is refused `out_of_reach`; with the switch cylinder widened to 3.5 m in a copy
  of the mode (a test value, not a decision), the same player is refused `blocked` by the wall. Seen failing with the
  leak plant (§4.6.4.1) and with `StationInSight` always passing (both `blocked` tests); each reverted.
  The photo task (§9.5.22) had no bot scenario either (PD14, PE18 of the [photo ADR](decisions/2026-10-10-photo-task.md))
  until #1197's ground-floor scenario (below) took a shot, and #1209's scenario across the storeys (below) carried the film to the printer upstairs and the
  photo to the board in the basement. What stands in for its scenarios is `tests/integration/levels/house_photo_test.gd` (#788, P9), built as
  `house_generator_test.gd`: the shipped base mode on the House in the host's real world, three players with forced
  roles, the photo task isolated in the setup's `ChangeSettings` (`tasks` 1 and every other task type of the base mode
  banned, read from the mode; `photos` 2, a test value, so one hang leaves the round going), `ScenarioInvariants` on
  every call and tick (the record invariant included). Players move only by movement claims the host accepts (each
  with its own client clock, long walks in pieces of at most 30 m, the climb to the study by the external stairs), so
  `Match.replay` reproduces every position: the two matches that shoot are replayed from their command logs (the same
  events to the same recipients on the same ticks, no `diagnostics`). The station, tray and film markers read without
  errors and the deal fills them; a player on each device's use spot is refused `no_film` at the camera,
  `nothing_to_print` at the printer, `no_photo` at the board, and takes a film from the box; the photo spot's whole
  mark lies outside the camera's cylinder, its lens clear of the camera scene and the line to the aim clear. Who
  counts: a subject on the spot's centre and one on the mark's near edge do; one behind the gazebo's backdrop (in the
  frame, out of sight) and one outside the frame (in sight) do not, each precondition asserted with `PhotoFrame` and
  `line_of_sight`. A scripted chain (a film from the box in storage, the dealt film loaded, a shot with a subject, the
  film out, the print in the study, the hang in the darkroom) completes a subtask, the shot's record naming the
  subject alone, every present player's view holding each photo event once. Seen failing with the leak plant on
  `ShotTaken` and on the other three photo events and with the record plant (§4.6.4.1); each reverted.
  Cooking (the [cooking ADR](decisions/2026-10-10-cooking-task.md), CD15, CE22) had no bot scenario either until
  #1197's ground-floor scenario (below) picked a herb and placed it, and #1209's scenario across the storeys (below) the grill and the burger, whose patty and bun
  come from the basement's boxes. What stands in for its scenarios is `tests/integration/levels/house_cooking_test.gd` (#777, C8), built as
  `house_photo_test.gd`: the shipped base mode on the House in the host's real world, three players with forced roles,
  Cooking isolated in the setup's `ChangeSettings` (`tasks` 1, every other task type banned, `burgers` 3 so every
  place is a station), `ScenarioInvariants` on every call and tick, players moving only by accepted claims (the climb
  from storage by the pantry stairs). Every station and box marker reads without errors and the deal fills them; a
  player on each used device's spot passes `AtStation` and `StationInSight` (the grill and each place refuse
  `empty_hand`, each bed gives its herb of the round, the order board refuses `empty_hand` and, with a herb,
  `wrong_item`), the herb board, a display kind, refuses `nothing_to_do` (CE6); a burger from
  players' commands (a bun and a raw patty from the boxes in storage, the patty fried on the grill, the order's herb
  from its bed, all three on the order's place) is plated with nothing said of right or wrong, taken, and served at the
  order board (#1101: checked there), where it is done and the round goes on, while another bun than the order's is
  thrown away and the order stays undone; a box carrier takes a herb and the grill's patty onto the belt (the herb
  put down at the feet first) and is refused `two_handed` at a place, so the
  base mode's own rules keep CD3 (b); behind the grill's body and each place's counter, inside the cylinder, a use is
  refused `blocked`. The burger's and the carrier's matches replay from their command logs (the same events to the
  same recipients on the same ticks, no `diagnostics`). Seen failing with the leak plant on `IngredientPlaced`
  (§4.6.4.1); reverted.
  The car repair (the [car repair ADR](decisions/2026-10-10-car-repair-task.md), RD13, §7) had no bot scenario either
  until #1197's scenarios (below) raised the car (the ground floor) and took a part (the basement), and #1209's scenario across the storeys (below) a fit, which
  carries a part between the storeys. What stands in for its scenarios is `tests/integration/levels/house_car_repair_match_test.gd` (#812, R8), built as
  `house_cooking_test.gd`: the shipped base mode on the House in the host's real world, four players with forced
  roles, the car repair isolated in the setup's `ChangeSettings` (`tasks` 1, every other task type banned, `car_parts`
  3; Delivery beside it for the package carrier, whose packages are the House's two-handed items), `ScenarioInvariants`
  on every call and tick, players moving only by accepted claims, each client's clock one client tick per host tick
  (an idle player stores no credit, which the fit's `AtStation` refuses, RE2). The deal puts each station on its marker
  and the car's use spot on the garage floor (RE16); no spawn or respawn marker lies in the car's box by
  `CarRepair.in_box` (RE7); the data's `clearance_m` lies between the crouched and the standing capsule (RD1) and
  `car.tscn`'s lowered layer-4 body between the floor and it; RE15 from every floor point of the panel's cylinder
  where a player fits and sees the panel, at every eye of the crouch band (0.1 m, both ends: R8 landed after 727a), to
  the box's grid from the data's `half_width_m` and `clearance_m`, all blocked; the voice distance (RD2) from the
  dealt kinds' radii. A part from each bin, each take making room as `Items.give` does (the first part on the belt,
  the second at the feet, the third in the hand); a package carrier's two takes onto the belt (the first put down at
  the feet), then `two_handed` at the panel and under the raised car (RD17). A full repair from players' commands (the
  holder at the panel, the fitter fetching each needed part from storage); the holder letting go mid-fit kills only
  the fitter under the car, not a bystander beside it or one past its far end; the chaos run's class-5 case (the
  holder's claim from the panel into the box, then a `Swap` in the same tick, applied: on that tick the holder gets
  `LiftChanged(false)`, `Swapped`, then its `Died`, RE17; dead once, no `KnockedDown` after its `Died`, its part at
  the body with one `ItemPlaced(death)`; seen failing with `Items.swap` planted to skip its move, reverted). The
  carrier's, the repair's, the drop's and the class-5 matches replay from their command logs. Seen failing with the
  leak plant on `FitChanged` (§4.6.4.1); reverted.
  The House's station tasks over the wire (#1197; foundation audit #877, e4): two scenarios play them through
  `Interact` with the shipped base mode and settings, a 20 s clock, crew bots doing the
  work and a forced dissident, ending by time up. `bots_use_the_house_ground_floor_stations` (3 bots): a film into
  the camera and a shot (`FilmLoaded`, `ShotTaken`), a herb from a bed onto its place (`IngredientPlaced`), the lift
  panel (`LiftChanged`, `PartNeeded`); `bots_use_the_house_basement_stations` (2 bots, down the pantry stairs since
  #1209): the Generator's three switches, then its button (`SwitchChanged`, `ButtonPressed`), and a part from a bin.
  #1209 added the chains that carry an item between storeys over the fake's stairs (above),
  `bots_carry_items_between_the_house_storeys` (4 bots, a 56 s clock, its own 90 s time limit, raised for that
  clock alone): a burger from the basement's bun and patty boxes over the grill, the herb bed and the plate to the
  order board (`ItemChanged`, `GrillLoaded`, `BurgerPlated`, `BurgerServed`); the part `PartNeeded` names carried
  up to the raised car (`PartFitted`); a shot's film up the external stairs to the printer and the photo down to the
  basement's board (`PhotoPrinted`, `PhotoHung`); the dissident holding the lift panel. Its plated burger's items and
  the printer's film vanish on the spot (`ItemVanished`), so no scenario waits out a loose item's `vanish_seconds`
  and no shipped task setting changed. The burger takes at least 48 s of the clock (46 s failed at the herb), so
  56 s leaves about 8 s. Every bot decodes them alike (`LeakCheck.check_tasks`, `ScenarioInvariants`), and
  `LeakCheck.UNREACHED` is empty (§4.6.4.1).

### 9.8 The extensibility test
Each later mechanic, on paper, against v0. The test counts classes in `core/`; the last paragraph says what each
costs outside it.

| Mechanic | Data | New part classes | New event classes | What else changes, and why |
|---|---|---|---|---|
| Zone task (#36): stand in a zone for N seconds (designed in the [zone task ADR](decisions/2026-10-09-m7-zone-task.md); the engineer took every recommendation on #302; §9.5.18; the client's look, §4.7.51) | a task type `.tres` (its time, a zone station kind, its own subtasks setting; the numbers and names are the engineer's, ZD7), markers of the zone's spawn tag in the map, the mode's task types (ZD8) | one task type (one script, §9.3), `ZoneTask`: its deal places one zone per subtask, as Delivery places its circles; its tick (through `TaskTicks`) adds one tick, kept in its task state, to each undone zone with a living player inside whose last claim is at most 10 ticks old (any role; several count as one; leaving pauses: the ADR's recommendations) and completes the subtask at its time. The cylinder test moves from Delivery to `StationState` so both share it | one, `ZoneProgress` (everyone): a zone's time, whether it counts and whether it is done, sent only on a change; a client draws the fill between changes. `StationPlaced`, `TaskState` and `TaskProgress` are generic | none in `Match` or the loop: `DealTasks` draws among the mode's task types (#79). Two mode checks (one spawn tag per station kind; a ticking task type needs `TaskTicks`). Outside `core/`: its wire row and a protocol bump, a bot target `STATION` (a station kind's n-th station) and bans in a scenario's setup, so the MVP's scenarios keep dealing Delivery alone |
| Delivery by meaning (#683): items of several kinds, each to its own place, no colours, on the House only (designed in its [ADR](decisions/2026-10-10-delivery-by-meaning.md), accepted; §9.5.25; the engineer answered every question and approved the design on PR #713, DD9 (c) included: the greybox, a test bench only (#767), keeps today's colour Delivery for its bot scenarios and the leak test) | a second Delivery `.tres`, listing the House alone in `TaskType.maps` (the Generator's G8; today's lists the greybox alone): routes, each an item kind and its drop-off station kind; one item kind per kind of item; one drop-off station kind per place, with its own spawn tag and no palette; one marker per drop-off tag on the House | a second task type, `DeliveryByMeaning`, and one data class, `DeliveryRoute` (a sub-resource, no behaviour); today's `Delivery` unchanged; `TaskType.station_kinds()` replaces the four finders of a type's station kinds (`MarkerReader`, ModeCheck, `WireBudget`, the client) | none: `StationPlaced`, `ItemSpawned` (its colour white for these items), `PackageDelivered`, `TaskState` and `TaskProgress` stay | none in `Match` or the loop, and no wire change. Outside `core/`: the House gains drop-off markers and loses its circles; the client draws drop-offs and items by kind, and no marker through walls on any map (the engineer's DD4 (a)); the bots and the leak test keep today's Delivery on the greybox, and the House's is tested without bots (unit, House and wire-codec tests) |
| Photo task (#687): load a film, shoot, print and hang on the House map (designed in the [photo task ADR](decisions/2026-10-10-photo-task.md); the engineer answered all its questions on 2026-10-10, the drafted words included; its parts: the task type, `PhotoFrame`, the load, the shot, the box, the print and the hang, §9.5.22; the wire test without bots; the viewfinder and the camera's state on the client, §4.7.56; the pictures, the camera's counter and the photo's look, §4.7.58) | a task type `.tres` (five station kinds, the camera, the photo spot, the box of films, the printer and the board, all but the photo spot with an `Interact` rule, the spot a display kind; `frames_per_film`; the frame's numbers; its own subtasks setting), two item kinds (the film, the photo, each with a cap), the station scenes on House, the one map its data lists (the Generator's `TaskType.maps`: the flat greybox gets none of the House's chains, so no bot plays the photo task; unit, House and wire tests stand in, the ADR's PE18), the mode's task types | on top of the Generator's `Interact` parts (#679, G1): one task type, `PhotoTask`, whose deal places a station on every marker of its five kinds and whose `use_station` loads a film or takes a shot by the camera's state, gives a film, prints and hangs; `PhotoFrame`, pure frustum math the host and the client share; the cooking design's parts by name (#682: `GiveItem.give_new` with its cap, tiered by a `TaskType.cap_tier` the photo task adds so a spammed box never vanishes the film in a camera, and the existing `Cooldown` cost for the box, as its herb beds; `Items.give`, a take beside a two-handed item going onto the belt, the engineer's rule for every take; the moves that lay or lock an item at a station for the camera's film and the board; `Items.vanish` for a printed film; a move serial per item, bumped by the cooking design's one move helper, from which the camera's film is derived; `TaskType.use_reasons()`) | four, all everyone: `FilmLoaded`, `ShotTaken` (with the record of the avatars near the lens at that tick, from which each client renders the picture), `PhotoPrinted`, `PhotoHung`; `ItemSpawned`, `ItemPickedUp`, `ItemVanished`, `TaskState` and `TaskProgress` are generic | none in `Match` or the loop: the film is taken out by the existing `PickUp`. The host decides who is in the shot from its own world (the frame and `WorldQuery.line_of_sight`, invariant 1), never from a client's image; the picture is each client's render from public data, so no image crosses the wire and every player receives the same task events (§5). Outside `core/`: four wire rows and protocol bumps, the viewfinder, the camera's frames counter and the render on the client; no scenario on the greybox |
| Revive (vision revision 1, §9.5.13), as a timed action on a player | the mode's `Raise` rule: `TargetDowned`, `ChannelFree`, `TargetInReach` (2 m), `TargetInSight`; `RaiseDowned` (3 s, 50 health); `StopRaise` (`Channeling`) and `GiveUp` (`Die`); `ChannelTicks` in Round | as built: the channel primitive (`ChannelEffect`, `ChannelTicks`, `ChannelFree`, `Channeling`, with `Channel` and `Channels` as its state), three conditions on a target player and two effects (`RaiseDowned`, `Die`). The primitive is the reusable part: a timed action is one `ChannelEffect` subclass plus the conditions it is held under, which are checked every tick (a #34 medic's resurrection at a body; #36's zone task only if the engineer picks ZD1 (b), a key held in the zone: the [zone task ADR](decisions/2026-10-09-m7-zone-task.md) recommends ZD1 (a), its time counting presence, which is no action) | `RaiseStarted`, `RaiseStopped`, `Revived` (everyone: both avatars are public) | three intents, `Raise(target)`, `StopRaise()` and `GiveUp()` (E28), with their rows in §4.1; the first intent that targets a player rather than an item. Two lines outside the parts: `RuleRunner` stops an actor's channel when another of its actions applies (§9.2), and `MovementRule` holds a raised player in place (§7.1.8). A #34 resurrection of the dead at their body would add a body target (`BodyInFront`: a body within reach and in sight, else `no_body`, which reveals nothing, bodies being public) and a `ChannelEffect` that brings the dead player back at the body (`LifeRules` gains that move, with its `Correction`, as `respawn` has); if only some roles may, `ActorRole`; a use limit, `Uses` (a cost over the counters table). Which `Use` wins when a medic holds a knife is #38's (§9.2) |
| Car repair (#688): hold the lift, fit the part, on the House map (designed in the [car repair ADR](decisions/2026-10-10-car-repair-task.md), accepted; the engineer answered all its questions on 2026-10-10, the drafted words included, and approved it for the MVP only: a more interesting mechanic will replace it later; its parts: the channels on stations and `HoldStation`, `LifeRules.kill` and the kill queue, the task type's deal, lift, drop, fit and parts (§9.5.21), and the wire test without bots (§9.5.21, §4.6.5.3)) | a task type `.tres` (four station kinds, the car, the lift panel and one bin per part kind, each with its `Interact` rule, and the needed part's picture on a garage wall, a display kind; the list of part item kinds; the fit's and the rise's seconds; the car footprint's half-width and clearance; its own subtasks setting), one item kind per part kind, the station scenes on House, the one map its data lists (the Generator's `TaskType.maps`: the flat greybox gets none of the House's chains, so no bot plays car repair; unit, House and wire tests stand in, the ADR's §7), the mode's task types | on top of the Generator's `Interact` parts (#679, G1) and the cooking design's `GiveItem` and `Items.give` (#682, C1, C2; a take beside a two-handed item goes onto the belt, the engineer's rule for every take): one task type, `CarRepair`, whose deal draws the needed parts and whose hold hooks raise and drop the car and fit a part; one effect, `HoldStation`, a channel on a station (timed for the fit, with no end for the lift). The channel primitive gains a station as its subject, a channel with no end and a mark for a stop at the phase's end; `LifeRules` gains `kill`, a death with no knockdown, for the drop, with a queue of kills (`kill_later`, `settle_kills`) that `Match` drains after each command's dispatch and each tick system and `Channels.advance` after each channel's step (a change to `Match`'s step, ADR RE17); `FitCheck.shortfalls` appends a new `TaskType.layout_problems` (RE14); the mode check gains the `kills()` and `LifeTicks` rule (RE6); `LifeRules.damage` stops a channel only when its effect's `hit_stops` is set | four, all to everyone: `LiftChanged`, `PartNeeded`, `FitChanged`, `PartFitted`; a drop's deaths are `Died`, as every death | no new intent: `Interact` starts a hold, `StopRaise` (already "stop my channel") ends it. Outside `core/`: the wire rows and two protocol bumps; a client-only collision layer for the moving car, since the host's world reads layer 1 only (§4.5.9) and the host does not check movement through walls (§7.1.9); a House integration test of a drop that kills only the players under the car (bots do not play House, §9.7). It depends on two mechanics designed elsewhere: a crouch for every player (#727, the [crouch ADR](decisions/2026-10-10-crouch.md); the fitter works crouched, the raised car too low to stand under) and the reworked knockdown (#728) |
| Meetings mode (#35) | a new mode `.tres` that reuses the base mode's roles, items, Delivery and win conditions, with the phases Meeting, Vote and Resolution, rows such as `Round, meeting_called → Meeting`, `Resolution, resume → Round` and `Resolution, won → End`, a clock stopped by the phase spec and a meeting voice rule | several, because a meeting is a system, not one mechanic: `Interact` (below) for a button and a body report, whose rules report `meeting_called` with `ReportOutcome`; `CastVote`'s effect; a tally as a transition action, fed by the Vote phase object's votes through the outcome's argument (§9.1); a meeting-wide voice rule; the phase classes Meeting, Vote and Resolution (fewer if one timed phase class serves several) | the vote events, each with its audience (a cast vote hidden until the reveal; the reveal; the result) | a new intent, `CastVote(target)`, with its row in §4.1. `PlacePlayers` gains a `who` setting (everyone, or only the living) to seat players for a meeting. Nothing in `Match` or the base mode: phases, rows, outcomes, the clock and the voice rule per phase are data (§3.1) |
| Physics throwing (#37; designed in its [ADR](decisions/2026-10-09-throwing-held-items.md), its answers given on #302, §7.1.16: the flying state, the arc, `FlightTicks`, the intent, `ThrowItem`, `OverFloor`, `ItemThrown` and the base mode's rule) | a `Throw` rule on the mode, for any held item (or one per item kind: the engineer's TD2): `HoldsItem`, `OverFloor`, `ThrowItem`; its numbers are the engineer's (TD1) | three: the `ThrowItem` effect, which takes the item out of the hand into a *flying* state, the `FlightTicks` tick system, which sweeps the arc each tick and lays the item down at its first contact, and the `OverFloor` condition (`no_floor`), so no throw leaves its item in the air | a public `ItemThrown` | a new intent, `Throw(facing)` (a new verb for every item, unlike `Use`), with its row in §4.1; the flying state in `MatchState`; one `WorldQuery` question, `sweep`; the cause `thrown`, whose `item_rested` lets delivery work unchanged. The design first sketched here had `server/` simulate the flight and report `ItemRested`; #37 proposes the flight in `core/` instead (TE1, the engineer's), so the clients draw the arc from `ItemThrown` until `ItemPlaced` and `server/` adds no command. Damage on impact would need an impact fact, `item_struck`; #37 recommends none for now (TD3) |
| Cooking (#682): the House's burgers (designed in its [ADR](decisions/2026-10-10-cooking-task.md), accepted; the engineer answered all its questions on 2026-10-10, the drafted words and looks included; its parts: `VanishTicks`, `ItemVanished`, `ItemKind.vanish_seconds` and the id reuse, §9.3; `Items.give`, `change_kind`, `lock_at`, `lay_on_station`, `ItemChanged` and CE21's take beside a two-handed item, §9.3, §7.1.11; `Interact`'s `item`, `ItemKind.target_actions` and `max_items`, `GiveItem` and `StationKind.display`, §9.2, §9.4.2; the optional `ItemKind.spawn_tag`, `TaskType.use_reasons()` and `wrong_item`, §9.4.1; `Cooking`'s data, deal, demands and checks, `OrderPosted` and `HerbsDealt`, §9.5.20; the grill, the beds and the places, the grill's tick, `GrillLoaded` and `IngredientPlaced`, §9.5.20; the wire test, §9.5.20, §4.6.5.3; the client's view, §4.7.55; the data in the base mode on House, §9.5.20, §9.5.1; a burger checked when it is served at the order board, `BurgerPlated` and `BurgerServed`, the ADR's amendment of 2026-10-15, §9.5.20, §4.7.55) | a task type `.tres` with five station kinds (the order board, a place, the grill, the herb board, a herb bed), its seconds (10 and 5) and its subtasks setting; 22 item kinds (3 buns, 3 raw and 3 fried patties, a burnt one, 5 herbs, 6 boxes, each box with its `Interact` rule, and the plated burger, #1101), the 15 ingredients and the burger vanishing after lying 60 s; markers on House, the one map its data lists (the Generator's `TaskType.maps`: the flat greybox gets none of the House's chains, so no bot plays Cooking; unit, House and wire tests stand in, the ADR's CE22) | four: `Cooking` (one task type: its deal hangs the orders, draws the round's herb code and shuffles the herbs over the beds; its station uses and its tick run the grill, the beds and the plates), `GiveItem` (an effect: a new item to the actor, capped per kind), `Items.give` (an item comes to a player, the hand item going to the belt or down at the taker's feet; beside a two-handed hand item the new item goes onto the belt, a full belt's item at the feet, the engineer's rule for every take) and `VanishTicks` (a tick system: an item of a vanishing kind left lying goes); every take from a box or a bed pays the existing `Cooldown`, a flood guard (not the grill's take-off nor `PickUp`, CE17); it uses the Generator's four station parts (G1 of its [ADR](decisions/2026-10-10-generator-task.md)) | eight, everyone: `OrderPosted`, `HerbsDealt`, `IngredientPlaced`, `GrillLoaded`, `BurgerPlated`, `BurgerServed` (#1101) and the generic `ItemChanged` and `ItemVanished`; a given item reuses `ItemSpawned` and `ItemPickedUp` | `Interact` gains an item target and the item kind a second set of rules (`target_actions`, for a targeted item on the ground); `Items` gains a kind change, the give, the vanish and the moves onto a station, and the pick-up belts a one-handed item beside a two-handed hand item (§7.1.11); `ItemKind` gains `vanish_seconds` and `max_items`, and its `spawn_tag` becomes optional for kinds only given; `MatchState` reuses a vanished item's id once the `u16` ids run out; one rejection reason and `TaskType.use_reasons()`; `StationKind` gains `display` (the boards, refused before any rule); nothing in `Match` beyond `Interact`'s routing, nothing in the loop. Outside `core/`: eight wire rows (two since #1101) and protocol bumps, `WireBudget`'s new kinds, the client's boards, beds, plates and grill. It does not pass the letter of the test (a target kind and an owner slot), as `Interact` itself does not |

**`Interact(target)`** (v1, with the first mechanic that needs it, #34 or #35): one intent that names a thing in the
world by id, and owners for fixed interactables (a marker kind in `levels/`, such as a meeting button) and for
bodies. It changes the intent catalogue (§4.1) and the owners once; after it, a new interactable is data plus at
most one effect. The first mechanic that needs it is the House's Generator (#679): its
[ADR](decisions/2026-10-10-generator-task.md) (accepted) designs the station half as `Interact(station)`, a station
kind owning its rules, with four parts (`AtStation`, `StationInSight`, `StationUsable`, `UseStation`)
(the intent, wire kind 18, `StationKind.actions`, `TaskType.use_problem`, `use_station` and `use_emits`, the
four parts in `core/tasks/`, ModeCheck's station rules and the `Interact` scenario step; tests: `tests/unit/tasks/
interact_test.gd`, `station_usable_test.gd`, `tests/unit/content/mode_check_interact_test.gd`); bodies wait for
their own mechanic. The Generator task type: §9.5.19. The item half
(the cooking ADR's CE1 to CE3, CE6: `Interact`'s optional `item`, `ItemKind.target_actions` and `max_items`,
`GiveItem`, `RuleEffect.refusal`, `StationKind.display` and ModeCheck's target rules; tests:
`tests/unit/items/give_item_test.gd`, `interact_item_test.gd`, `tests/unit/content/mode_check_give_test.gd`).

**Verdict.** Inside `core/`: the zone task passes, with one class and one event class, as #36's design has it (live
progress and a public "zone done" share `ZoneProgress`), as its code does; with ZD1 (a), the engineer's answer,
its time runs in its task state, not on the channel primitive (§9.3), since standing is no action. Delivery's
cylinder test moved to `StationState` unchanged, so both types share one. Beyond the paper test it needed two
helpers outside the parts: `MovementRule.claim_age` and `credit_gain` (§7.1.5), so a stale claim, or credit stored
while standing, stops counting (ZE10). The revive did not pass the letter of the test: a player is a new kind of
target, a timed action needed a new
primitive (the channel) and the raise three public events and three intents. With them in place, a resurrection at
a body (#34) is two or three part classes and one event class: a body is again a new kind of target, and a
resurrection a new public fact. The meetings mode is several parts, as a system. Throwing and
`Interact` each change the engine once, for the reasons given. None of them changes the phase loop, and only
`Interact`'s station half changes `Match`, once: its owner lookup tries the named station's kind before the role and
the mode, after refusing an id that names no placed station (#796, §9.2), for every later station intent; the
change to an existing part is a new setting (`PlacePlayers`' `who`). The revive changed two existing rules once,
for every later timed action: `RuleRunner` stops the actor's channel when another of its actions applies, and the
movement rule holds a raised player in place.
Outside `core/`, every new event class and intent also costs a wire schema row (M3, §4) and its presentation on the
client (M4). That is the price of any mechanic that shows something new, not a gap in the content API. A new
task type's client is one `TaskClient` subclass in `client/world/tasks/` plus its row in `TaskClients` (§4.7.59);
`task_clients_test.gd` is red while it is missing.

## 10. Open questions

Only the questions still open. A settled one leaves this table: its answer lives in its ADR and in the contract text
above (#1244).

| Question | When |
|---|---|
| `Interact(target)` with a body as its target (§9.8; the fixed interactables are built: stations in #796, items on the ground in #770) | with a body's own mechanic |
| Which `Use` rule wins when the held item and the actor's role both have one; v0: the item (§9.2; deferred to #34 on #38) | before a role has a `Use` ability |
| The zone task's numbers (ZD7 of the [zone task ADR](decisions/2026-10-09-m7-zone-task.md), §9.8): the data (M7-Z3, #649) and House's three points (M7-Z5, #651) are provisional placeholders | until the engineer moves them |
| Movement modifiers, which would make sprint and jump parts (§9.5) | when a mechanic changes movement |
| How levels mark spawn points: groups on `Marker3D` or an engine marker scene (§9.6); and give collision the host can read (`StaticBody3D`, not CSG or `GridMap`, with E8 (a): §4.5) | 4e, with the designer |
| The crouch's landing (KD6 of the [crouch ADR](decisions/2026-10-10-crouch.md), §7.1.17): crouched again on landing while Ctrl is held (recommended), or only at a fresh press | the engineer |
| Lag compensation for hits (§7.1.10) | after the MVP playtest |
| Hiding positions behind walls (§5; not wanted now) | only if a human asks |
| A return into a running round (#73, 73-D of the [returning players ADR](decisions/2026-10-09-returning-players-keep-their-number.md)) | only as its own design |
| The host's relay cost per `VoiceDown` on a quiet PC (§6.5.8 The wire: measured as upper bounds on a busy PC and in the cloud, over E44's 2 ms per 20 ms) | the engineer's rerun on a quiet PC |
| Who is talking, shown in the world (D14 of the M5 ADR: no talking indicator in M5) | a mouth animation with the masks of #73, after the MVP |
| Radios, abilities and items that change voice; echo cancellation; lowering the device latency | M7+; echo cancellation only if playtests ask (players are advised headphones, the voice ADR) |

## 11. Art assets: the handoff from the art repo (#519)

Art is made in the private art repo (`xperiaroco2/prime-game-art`: its `docs/pipeline.md`, `docs/contract.md`,
`docs/godot.md`, `docs/manifest.md`) and enters this repo only through a game-repo PR, one asset or one set per PR.
This handoff (#519) serves the character (#522) and the house (#523); its dry run is a CC0 Kenney chair
(`assets/environment/kenney_chair/`), which no scene uses.

### 11.1 Where an asset lands
```
assets/
  characters/<id>/<id>.glb     a character: body, rig and clips in one GLB (art `export`)
  environment/<id>/<id>.glb    a house, a room or a prop, its textures beside it
  audio/<id>/<id>.wav|.ogg     a sound effect or a music track
  ui/<id>/<id>.png|.ttf|.otf   a UI image or a font
```
- `<id>` is the art manifest's `id` (lowercase letters, digits and underscores), or for a third-party file a slug
  of its pack and name (`kenney_chair`). A set (several sounds, a font family) keeps its files in its one folder.
- Data only: binaries and the `.import` files Godot writes beside them, no scripts. The engineer owns `assets/`
  (§1). Scenes in `client/` and `levels/` instance them (the avatar a character, the level its environment); an
  asset never refers back to them.
  One kind of text file is data too: an art set's own materials, its shader and the `.tres` that use it, at the
  paths its scenes reference, copied as the art ships them (the House's `house_kit/kit_set.gdshader` and
  `kit_set.tres`, `house_props/prop_fine.gdshader` with `prop_fine_high.tres` and `prop_fine_low.tres`, #523);
  never GDScript.
- The UI pack's imported copy is here too, as `ui/toy_pack/` (its own paths, `icons/room/hall.svg`,
  `cards/delivery-1.png`): `ui-sync` writes it under the pack's lock (§4.7.34), never by hand. The Comfortaa font goes
  to `ui/toy_pack/fonts/` (#520, #1045).
- The sounds are three sets, one per Kenney pack (#525, §4.7.43): `audio/kenney_impact_sounds/` (the footsteps),
  `audio/kenney_rpg_audio/` (swing, pick-up and put-down) and `audio/kenney_interface_sounds/` (the UI click), each
  file named after its sound so `sfx-check` finds its category; the engineer's verdicts on the three, from one
  listening page, in `audio/sfx-verdicts.json`.
- Not here: the pinned UI pack (`client/ui/theme/pack/`, `ui-sync`, #288, text Godot does not import), addons with
  their own files (`addons/`), and test fixtures (`tests/fixtures/`).

### 11.2 The PR an art handoff opens
- **The files:** the asset under §11.1's path, through Git LFS (`.gitattributes` routes glb, png, jpg, wav, ogg,
  ttf and otf, among others, as the [LFS ADR](decisions/2026-09-29-git-lfs-for-binary-assets.md) lists them; the
  pre-push hook uploads the objects). `git lfs ls-files` lists each.
- **The credits:** `docs/credits/<id>.md` with `Files`, `Author`, `Source` (the art manifest's source, or the
  download page with the file's SHA-256), `License` (with its URL), `AI generated` and `Public repo OK`, the
  manifest's `ai_generated` and `public_repo_ok` (AGENT_WORKFLOW §10). From the art repo, only an asset whose
  manifest has `approved_by`, `approved_at` and `approval_pr` set and `public_repo_ok = true`; `check` refuses
  `Public repo OK: false`. Then `tools\run.cmd credits` and the regenerated `CREDITS.md` in the same commit.
- **The import settings:** the `.import` file of every asset, committed (`check` imports first and fails on an
  import that changes or creates one, so run `check`, review the `.import` and commit it). A GLB keeps
  `nodes/root_type=""` (a `Node3D` root: the game's scene owns the body), `nodes/root_scale=1.0` and
  `nodes/apply_root_scale=true` (1 unit = 1 m, the contract's axes) and `animation/import=true`. A character adds
  the art repo's two options (its `docs/godot.md`): `animation/fps=30`, the rate an animation set (the MVP set,
  `mvp.toml` fps = 30) is baked at, which the GLB's `.export.json` records (at another rate Godot resamples every
  track; a GLB of the pack's own 24 fps clips would need 24, and the contract changed first) and
  `optimizer/enabled=false` on the AnimationPlayer node (`_subresources={"nodes": {"PATH:AnimationPlayer":
  {"optimizer/enabled": false}}}`; the optimizer moved joints up to 16.7 mm). Loop modes come from the clip names: Godot 4.7.2 imports a clip named `<Name>_Loop` as `<Name>`
  with `LOOP_LINEAR`, so no per-clip setting is needed. An image keeps its folder's compression: `compress/mode=2`
  (VRAM Compressed, for 3D) under `characters/` and `environment/`, `0` (Lossless) under `ui/`.
- **The colliders** (#523, the LFS ADR's amendment of 2026-10-14): an environment GLB's import-hint colliders
  (`-colonly`, `-convcolonly`, `-col`, `-convcol`) leave the GLB as text, so a checkout without LFS content (CI,
  bots) still has the level's floors, walls and stairs. `tools\run.cmd colliders` (`tools/runner/colliders.py`)
  writes, per GLB under `assets/environment/`, a wrapper `levels/kit/<pack>/<stem>.tscn` (the GLB instance, the
  look, plus one `StaticBody3D` per hint collider at its root, named and placed as the importer names and places it)
  and each body's shape `levels/kit/<pack>/<stem>.<body>.tres` (convex points snapped as Godot's hull snaps them, or
  the trimesh's triangles), sets the GLB's `.import` to skip the importer's own bodies (`_subresources`
  `import/skip_import`) and points each scene under `levels/` at the wrapper. `check` runs `colliders.problems()`: a
  scene under `levels/` that instances a wrapped GLB directly, or a GLB whose files differ from what `colliders`
  writes, fails it. Run `colliders` after every art import and commit its output. An override that reaches a
  collider names the wrapper's body (`Shell/<instance>/<body>`). Without LFS content the GLB's stand-in holds the
  nodes that the scenes under `levels/` override (`lfs.glb_outline`), so those overrides do not print Godot's "has
  vanished" warnings (11 million log lines on the first CI run).
  Tests: `tools/runner/tests/test_colliders.py` (in `selftest`); the House's level tests and `game_loop_test` pass
  in a `GIT_LFS_SKIP_SMUDGE=1` clone with `CI=true` (#1043).
  An override of a node inside an instance (a Shell, Dressing or Detail material, `plan_at`, a collider's layer)
  survives a re-save (the editor's, `normalize`'s) only with its instance's `[editable path]` entry, and a line at
  its default value is dropped (#1056; `levels/CLAUDE.md`). `tools/runner/editables.py` finds an overridden instance
  without its entry in a scene under `levels/` (the wrappers aside): `check` fails on it, and `colliders` ends by
  adding the missing entries, so an art re-import follows the rule. Every House room and the plot are normalized
  (a second `normalize` leaves them byte-identical); the art's per-instance `plan_at` keeps the overrides in the
  rooms, not in the generated wrappers.
  Tests: `tools/runner/tests/test_editables.py` (in `selftest`); `tests/integration/levels/house_overrides_test.gd`
  (each room and the plot packed as a re-save packs it keep every property they set; text cannot see an instance
  nested in an instanced scene).
  Since #1080 (art main 7df542b, the attic stair of art #188) the art draws each room through `merged_*` meshes in
  `Shell` and `batch_*` ones in `Dressing` (art #184; shadow-only twins, art #189), the per-piece meshes `visible =
  false` beside them and their colliders still on the pieces' wrappers. A station prop the game replaces with its
  station scene must stay out of the art's batch (the art's `[merge] keep_props`), else the batch draws the art's copy
  where the station draws its own: the garage's `part_picture` does (an art note on #1042). The re-import was a
  three-way node merge (base: the art export each room was taken from), so every game change to a room stayed.
  The garage (the art's P6, #1052) holds the art's car, lift posts and lift arms inside the car's station scene
  (car repair's R5, #809, §9.5.21), the lift panel behind its partition; its 8 m gate's leaf is an opening (layer 0,
  E4) under its lintel.
  The art has no garage roof, so the room is open above (the greybox's ceiling collider is gone; adding one is
  the engineer's call).
  Tests: `tests/integration/levels/house_garage_test.gd` (the lift pieces in the car's station scene at the art
  handoff's points, no art copy left, the station points, the gate, and every override with its editable path).
- **The checks:** `tools\run.cmd check`, `credits`, and the import check (§11.3) green, the import check run
  locally (CI has no LFS content, so only a local run loads the GLB); for a visible asset `shot` images in the PR
  (the art pipeline's step 15).

### 11.3 The import check
`tools/assets/asset_check.gd` over `tools/assets/asset_contract.json`, run by
`tests/unit/tools/asset_import_test.gd` (so `test`, `verify --full` and CI run it; a plain `verify` runs no tests,
#605; alone: `tools\run.cmd test tests/unit/tools/asset_import_test.gd`):
- every GLB under `res://` (not `addons/`, `.godot/`, `tools/out/`, `tests/scratch/`) has a committed `.import`
  with §11.2's options and loads headless as a `PackedScene` that instantiates;
- a GLB under `assets/characters/` also has exactly one `Skeleton3D` holding every bone of the contract and one
  `AnimationPlayer` holding every clip, each looping exactly as listed;
- every image under `assets/` (png, jpg, jpeg, webp, tga, bmp, exr, hdr: the texture formats `.gitattributes`
  routes through LFS) keeps its folder's `compress/mode`.

Each problem is one line that starts with the asset's path and names what is missing, for instance
`res://assets/characters/fixture/fixture.glb: lacks 1 contract clips: Crouch_Fwd (it has: Carry_Upper, ...)`. Broken
fixtures built in memory (a missing clip, a missing bone, a loop that plays once, wrong import options and
compression) must each be named. Without LFS content (CI) a GLB is a pointer file: the test still checks its
committed `.import` (text, so present), names the file and skips loading its scene and checking its skeleton and
clips, which a local run does; `check` imports a stand-in in its place (the LFS ADR's amendment).

**The contract's data.** The bones are the art export's rig as measured (art `docs/animations.md`:
`CharacterArmature`, the 62 Ultimate Modular bones plus `Toe.L` and `Toe.R`, 64 in all, kept until the art contract
v2, the engineer's "as recommended" of 2026-10-14 on #522); the art contract v2 may move them to Godot's
`SkeletonProfileHumanoid` names, and the file changes with it. The clips are those the avatar maps (#522,
`AvatarClips`, §4.7.53) under the art MVP set's names as Godot imports them: `Idle`, `Jog_Fwd`, `Jog_Bwd`,
`Strafe_Left`, `Strafe_Right`, `Sprint_Fwd`, `Crouch_Idle`, `Crouch_Fwd` and `Carry_Upper` looping, `Pickup_One`,
`Putdown_One`, `Pickup_Package` and `Putdown_Package` once. The knockdown is a ragdoll (art #115), so `Knockdown`,
`Crawl` and `Getup_Fours` left the list; the GLB's other clips (jump, turn, raise, talk, push, knife) are not checked
until a mapping plays them. The first character is `assets/characters/slice_m1/` (prime-game-art `45f73ac`, PR
art#182): the GLB, its 11 textures as the importer extracts them (`compress/mode=2`) and `slice_m1.ragdoll.json`
(text, not LFS), which the game builds the ragdoll's bones from (§4.7.53).
