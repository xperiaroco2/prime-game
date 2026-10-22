# The tutorial: an offline solo session, the lesson runner and its room

| | |
|---|---|
| **Status** | §1 to §8: designed in #552 and built by T1 to T4 and #492 (M6.2); ARCHITECTURE §4.7.44, §4.7.46, §9.5.17 and §9.6 record what was built and on which answers. §9, **the rework without tasks** (#825, [ADR](../decisions/2026-10-12-tutorial-without-tasks.md)): answered by the engineer on [PR #894](https://github.com/xperiaroco2/prime-game/pull/894#issuecomment-6122434286) (LD1 to LD10 as recommended); 825a (#900) built it and rewrote §1 to §5 to its eight lessons; 825b (#901) added the throw lesson as lesson 4, so §1 to §5 count nine lessons again and number them as §6 to §8 were decided (825c (#902) is built too). The D items (§7) are the engineer's; the E items (§6) are the M6.2 manager's and stand as recommended unless reported otherwise, but E64 (a new kind in §1's `content/` row) and E65 (a wire row) go to the engineer too. The decisions, the batched questions and the rejected alternatives: [ADR](../decisions/2026-10-08-tutorial-offline-solo-session.md) |
| **Owner** | The engineer (the content area, #518). He asked for this design on #516 ([scope option A](https://github.com/xperiaroco2/prime-game/issues/516#issuecomment-6055436108), item 2) |
| **His answer it builds on** | The tutorial is **offline, in a room of its own**: a solo session with no network, a small room with its own stations (chat with the M6.2 manager, 2026-10-08, recorded in #552's body) |
| **Screens** | prime-game-ui `docs/handoff/s01-tutorial.md` at `ui-0.4.0` (built by #492), with s2 (the main menu's Tutorial), s5 (the Esc menu's `tutorial-game`), s8 (the map's «?» and its how-to card) and s9 (spectating). This page decides how the feature behind them runs, never how they look |
| **Numbers** | Every number below is a placeholder, "not a decision", unless it names its source |

## 1. What the player meets (fixed by the screens)
- **The first launch** opens in the tutorial room, dimmed, under the invite: two language chips, Start and Skip. Start
  begins lesson 1; Skip or Esc goes to the main menu. Either hides the invite for good (a `user://` flag, #492).
- **Later**, the main menu's Tutorial (s2) starts lesson 1 again.
- **In the room** the round HUD shows without the timer and the role, the current lesson at the top, the nine
  lessons at the right. A lesson advances when the game sees its action; a lesson with two instructions swaps them
  within one step number. After lesson 9 the game returns to the main menu with no end screen. The Esc menu shows
  Game, Guide and Settings; its Leave reads "Leave the tutorial" and returns to the main menu.

The nine lessons (#900 removed the Delivery lesson and the map lesson's «?» step, §9; #901 added the throw lesson in Delivery's place, as lesson 4), with the action this design
detects for each and what the world must hold. Keys are deck keys of
`client/i18n/strings.csv` (`tutorial.step.*`, `tutorial.list.*`); the key that fills `{key}` is an InputMap action
of `project.godot`, shown by `KeyLabel` (#211).

| # | List key | Step: title, how, `{key}` | The action the game sees | Seen by | What the world needs |
|---|---|---|---|---|---|
| 1 | `move` | `move.title`, the key row (`move_forward`, `move_left`, `move_back`, `move_right`, `sprint`, `jump`) | the own claims report the player moving itself (`ClientSession.claim_sent`'s `moved_itself`, counted over the ticks each claim covers) for 1 s in all | the client | a floor and a start spot |
| 2 | `pick_up` | (a) `pick_up.title`, `pick_up.how`, `interact`; (b) `put_down.title`, `press`, `put_down` | (a) an `ItemPickedUp` naming the own peer, of a package; (b) an `ItemPlaced` with cause `put_down` of the item the own hand held as the step started (`ItemPlaced` names no player) | the own events, the own model | a package |
| 3 | `hand_belt` | `hand_belt.title`, `press`, `swap` | a `Swapped` naming the own peer | the own events | a one-handed item (D29): the package takes both hands and is refused (`two_handed`, ARCHITECTURE §9.5.14) |
| 4 | `throw` | `throw.title`, `throw.how`, `throw` (built in #901, 825b; the words are the deck's: list "Throwing", title "Throw an item", how "Take an item in your hand and press {key}") | an `ItemThrown` naming the own peer | the own events | an item in the hand (a belt item is never thrown, so the how asks for one); `Throw` accepted and `FlightTicks` running in the three lesson phases (§2.3); the room kept as it is (the engineer's answer (c) on #901, #911) |
| 5 | `map` | `map.title`, `press`, the map action (`map`, M, since #253) | the map screen opens | the client | the room's map data (#306) and the map (#490, #253) |
| 6 | `downed` | `downed.title`, `downed.how`, `interact` held | a `Revived` of another player (only the own player raises in the tutorial) | the own events | stage `raise`: a stand-in knocked down when the lesson starts (D27) |
| 7 | `death` | `death.title`, `death.how`, `spectate_next` | while the own life is dead, the player switches the spectate target (`spectate_next` or `spectate_previous`; the first target, drawn at the death, does not count); D36 when the respawn comes first | the client, the own events | stage `death`: the own player dead when the lesson starts (D28), and two living players to watch (D26) |
| 8 | `voice` | `voice.title`, `voice.how`, no key | once the own player lives again (`Respawned`): own voice frames sent while another player stands within the phase's voice radius; D31 when no microphone is open | the client | a stand-in near the respawn marker |
| 9 | `menu` | `menu.title`, `press`, `ui_cancel` | the Esc menu opens | the client | nothing; then back to the main menu (D32) |

Four of the nine actions (the map, the spectate switch, the voice and the Esc menu) never reach the host as
anything it can react to: they are screens and the microphone of the own client. That fact shapes §3.

## 2. The solo session

### 2.1 How it runs (E62)
`Game` starts the tutorial the way it hosts today (§4.7.2 of ARCHITECTURE), on another transport and another mode:

1. `mode` becomes the tutorial mode for this session (E69).
2. A private `LoopbackHub`, and a `LoopbackTransport` on it as the host's transport (`net/transport/`, built in #40
   for the host's own client and for headless tests of a host and its clients in one process).
3. `HostNode.host(transport, mode, port)`: the façade as it is. The port is a key in this hub, nothing more.
4. The own `ClientSession` on `HostNode.own_client` (`LoopbackTransport.own_client_of`), exactly as when hosting.
5. The stand-ins (§2.2): each a `ClientSession` on its own `LoopbackTransport` that joins the same hub and port.

The game's own integration tests already run this shape: `game_loop_test.gd` (`tests/integration/client/app/`)
hosts a `Game` and joins two more on one `LoopbackHub` through `Game.make_transport` and plays the loop to the end
and back. Nothing opens a socket: no ENet, no signalling service, no firewall prompt, no port to collide with a
second game window, and it works with the network cable out. Nobody else can join: the hub lives in this process
only. Everything above the transport is the networked game's own code, unchanged: `HostSession`, `Match`, the
per-peer filter, `ClientSession`, `ClientModel` and the views. The host's own player still sees only what its
`ClientSession` decoded (E18), so every screen built for a round (the HUD, the map, the downed and spectating HUD)
works in the tutorial without a tutorial branch, and the tutorial cannot show what a networked round would hide.

**What changes for networked play** (the failure each guard prevents is in §6):

| Area | Change |
|---|---|
| The wire | one new client-to-host row, `NextStage` (E65), so the protocol version goes up by one; the base mode accepts it in no phase, so a networked host answers it `not_accepted` |
| `core/` | the parts of §2.5; the base mode's data unchanged, and every existing part's behaviour too but a join in a phase with no level (E72), which no base-mode phase is |
| `server/`, `HostNode`, `ClientSession`, `net/` transports | none |
| `Game` | `start_tutorial()`, the mode chosen per session, the stand-ins; a networked session after a tutorial uses the base mode again (a test). The tutorial's host writes no replay (`HostNode.skip_replay`): a debug build keeps only the newest 10 command logs (`ReplayFiles.KEEP`), and each tutorial would push out a match's |
| `GameFlow` | a phase with no level shows the loading screen (every base-mode phase has a level, so no base flow changes) |
| The leak test and chaos bots | kind 15 leaves `ChaosFrames.UNASSIGNED` (16 takes its place) and §4.6.5.3's list; the new row in `ChaosOracle.ACCEPTS` (accepted in no base-mode phase), a `NextStage` in `ChaosHostile._refused` that expects `not_accepted`, and its malformed shapes (a missing `seq`, trailing bytes); no new event, so no new audience |

### 2.2 Stand-ins (D25, D26, D35, E67)
Lessons 6 to 8 need another player: someone down to raise, someone to watch while dead, someone near to talk to.
The raise checks that its target is a downed player the host knows (§7.1.8), spectating draws its targets from the
roster (`SpectateTargets`), and voice is routed between players (§6). So the others must be **players of the
session**, not props.

A **stand-in** is an in-process client of the tutorial's hub, run by the game (`client/tutorial/`):
- it sends `Hello` (the tutorial mode's content hash, as every client), `SetReady(true)` once welcomed, and
  acknowledges `LoadMatch` at once (`ClientSession.load_levels` off, as the bots do);
- it claims standing still where it was placed, on the floor, as the bots' `stand` hook does, and sends nothing else:
  no intent, no voice. Lessons stage it from the host (§2.4), never by scripting its client;
- the game steps it every physics frame, after the host and before the own session (a `StandIns` node);
- the game never reads a stand-in's model for anything it shows: what the player sees of a stand-in comes from the
  own session's snapshots and events, like any other player. A source test holds it (only `stand_ins.gd` names a
  stand-in's session).

The host names it as any joiner (Player2, Player3; #550's own names when it lands); its body looks like any player's.
Once #550 puts the player's name in `Hello`, a stand-in's `Hello` carries whatever #550 defines as "no name", so
the host's default for a joiner applies (D35 (a)); the game picks no name for it.
Two stand-ins (D26): one to raise in lesson 6, and a second so that lesson 7's "watch another player" has another
player to switch to (with one living player `spectate_next` keeps the same target).

### 2.3 The tutorial mode (E68)
`content/modes/tutorial_mode.tres`, provisional under the [MVP content
ADR](../decisions/2026-09-29-mvp-content-built-by-the-engineer.md), built from existing parts plus §2.5's. Players:
1 + the stand-ins, minimum and maximum alike (3), so `all_ready` waits for everyone. `PlayerRules`: the base mode's,
but `respawn_s` 10 (a placeholder, "not a decision": lesson 7 is a short wait, not 30 s). No settings the player
changes, no win conditions, no Pregame (#213) and no End: the tutorial has no roles to reveal and no winner, and it
ends when the own client leaves.

| Phase | Class | Level | Accepts (§3.1) | Tick systems | Voice | Clock | Snapshots |
|---|---|---|---|---|---|---|---|
| `gather` | Lobby | none | `Hello` (newcomers), `SetReady` (any player) | none | Silent | stopped | no |
| `loading` | Loading, deadline 60 s (the base mode's) | the room | `LoadAck` | none | Silent | stopped | no |
| `lessons` | Round | the room | living: `MoveClaim`, `PickUp`, `PutDown`, `Swap`, `Throw`; host: `NextStage` | FlightTicks | RoundVoice, `living_m` 8 m (the base mode's) | stopped | yes |
| `raise_stage` | Round | the room | as `lessons`, plus `Raise` and `StopRaise` from the living; downed: `MoveClaim` | ChannelTicks, FlightTicks; **no LifeTicks** | as `lessons` | stopped | yes |
| `death_stage` | Round | the room | as `raise_stage`, but no `NextStage` (with D28 (b), plus `GiveUp` from the downed) | LifeTicks with a Respawn (`respawn`), ChannelTicks, FlightTicks | as `lessons` | stopped | yes |

| From | Outcome | To | Actions |
|---|---|---|---|
| (start) | the session starts | `gather` | |
| `gather` | `all_ready` | `loading` | |
| `loading` | `all_loaded` | `lessons` | `DealRoles` with no quota (everyone the default role, crew), `SpawnItems` (Package, `packages` 1, its own `rng_purpose`), `SpawnItems` (Knife, `knives` 1), `PlacePlayers` (`round_player`, ordered: §2.5); no `StartClock` |
| `lessons` | `next` | `raise_stage` | `KnockDown` of the first other player (stand-in 1) |
| `raise_stage` | `next` | `death_stage` | `KnockDown` of the host's player, dying at once (D28) |

- **`gather` has no level** and the mode no `lobby_level` (E72), so the room loads once, as the map, and nothing
  loads before it. A joiner there has no marker to stand on: `JoinRules` today looks for a `lobby_player` marker in
  the current phase's level and records a match error for each join when there is none (`ctx.layout` is null at no
  level), so T1 makes a join at no level stand at the origin, with no error. The rule keys on the phase spec's level
being `PhaseSpec.Level.NONE`, never on `ctx.layout` being null: `Match._layout_of` also returns null for a lobby
level whose layout failed to load, and that case must still record its match error (a unit test holds it). Nobody sees that spot (`gather` sends
  no snapshots) and the deal's `PlacePlayers` moves everyone. The client shows the loading screen until the room
  is in (E69), which also keeps the own player frozen (`GameFlow.frozen`) while it has no floor.
- **No `Use`** in any phase: the knife of lesson 3 swings at nobody (`not_accepted`), so the player cannot knock a
  stand-in down before its lesson, and no lesson needs a strike.
- **`raise_stage` has no LifeTicks**, so the downed stand-in waits however long the player takes; with them it would
  die after `knockdown_s` and lesson 6 could not finish. The M4-3 mode check asks for LifeTicks only where a *rule* can
  knock someone down (a `Strike`), and a row's action is no rule, so the phase passes as written. Once `KnockDown`
  exists, that gap lets any mode knock a player down for good by a row; T1 closes it with a mode-check **warning**
  (not an error) on a row whose `KnockDown` without `then_die` enters a phase with no LifeTicks, and §9.4.3's
  `KnockDown` row names `raise_stage` as the intended case.
- **`death_stage` has LifeTicks** for the respawn, which lesson 8 waits for.

### 2.4 Stages: how the host learns that a lesson starts (E65)
Only two lessons change the world: lesson 6 (a stand-in down) and lesson 7 (the own player dead). The lesson runner
on the client decides when a lesson starts (§3), so the host must hear it: the own client sends **`NextStage`**, a
new intent with no argument. The tutorial mode's action rule on it has one effect, `ReportOutcome(next)`; the phase
that accepts it has one `next` row, so the host moves `lessons → raise_stage → death_stage` and runs each row's
actions. The client can only say "next": the host validates the sender (the host's own player, `AcceptSpec` HOST),
the phase (only `lessons` and `raise_stage` accept it) and the order (one row each). It is the same kind of session
control as `ReturnToLobby`, the host's shortcut out of End.

### 2.5 New host-side parts (E66)
Each is a content-API part in `core/` with its own unit tests and a §9.4 entry, built in one issue (§8, T1).

| Part | Kind | What it does | Settings | Emits (audience); raises |
|---|---|---|---|---|
| `NextStage` | intent (C→H row, kind 15, the next free one; `seq: u32`, cap 4). 15 is among the unassigned kinds the chaos frames send today (`ChaosFrames.UNASSIGNED`, §4.6.5.3), so T1 moves that shape to another unassigned kind (16) and updates the list | the host's player asks a scripted mode to go on | none | `Rejected` (`not_accepted`) where no phase accepts it |
| `ReportOutcome` | effect (listed in §9.4.2 since 2a, "with the first mechanic that needs it"; `MatchContext.report_outcome` exists) | reports `outcome` in the current phase | `outcome` (and `argument`, as §9.4.2 lists it; unused here) | the outcome (no peer sees it, §9.2) |
| `KnockDown` | transition action | knocks down one present living player through `LifeRules.knock_down`; with `then_die`, `LifeRules.die` at once | `pick`: the host's player, or the n-th other present player in peer-id order (from 1); `then_die` | `KnockedDown` (everyone), `Correction` (the downed); with `then_die`: `Died` (everyone), the drop's `ItemPlaced` (death, everyone); facts `player_died`, `item_rested` |
| `PlacePlayers`, `ordered` | a setting of an existing transition action | the players in peer-id order onto the tag's markers in level order, with no draw (the host's player, peer 1, on the first) | `ordered` (false: today's draw) | as today: `PlayersPlaced`, `Correction` |
| a join at no level (E72) | the `Lobby` phase class's join (`JoinRules`) | in a phase whose spec's level is `PhaseSpec.Level.NONE` (never "the layout is null", which a lobby whose layout failed to load also has), the joiner stands at the origin with no match error; a lobby level with no `lobby_player` marker still errs as today, and a lobby whose markers are all taken still puts the joiner on the first one | none | as today: `Welcome`, `PlayerJoined` |

No new event and no new audience: every event above is one the life and item rules already emit (ARCHITECTURE
§4.2), so the information-leak test's audiences and the client's folds hold as they are. A `pick` that names nobody
present (fewer players than n), or a `then_die` whose `LifeRules.die` errs, is a rule error recorded during the row,
so the session ends (ARCHITECTURE §4.5.11: `HostSession` ends it on a new row error); T1's unit test asserts the
row error count.

## 3. The lesson runner (E63, E64)
The runner is client code that watches what the own client already knows and moves the plates on. It reads only the
own `ClientModel`, the own session's events (`ClientSession.event_received`), the own outgoing claims
(`claim_sent`), the client's own copy of the modes, and a short list of the client's own signals. It sends nothing
but `NextStage`. It is a pure `RefCounted` (`client/tutorial/lesson_runner.gd`), unit-tested by feeding it events
and signals, like `GameFlow` and `SpectateTargets`.

**Lessons are data.** The classes are data only and live in `core/content/tutorial/`, next to the bot scenarios'
(§9.7), so `content/` still uses only the content API; the nine lessons are `content/tutorial/tutorial.tres`
(provisional); the runner that plays them is in `client/`. A lesson is a list of one or two steps; a step has the
content API's shape, trigger → conditions → effects, where the effect of a completed step is always the same (the
next step starts) and a step's own actions run when it starts:

| Field of a step | What it holds | Lesson that needs it |
|---|---|---|
| `title_key`, `how_key`, `keys` | the deck keys and the InputMap actions (or the «?» glyph) the plate shows (#492) | every |
| `starts_when` | conditions that must hold before the step shows; until then the previous lesson stays done and nothing is current | 7: the own life living (after the respawn) |
| `on_start` | actions run once when the step starts | 5 and 6: `RequestStage` |
| `done_when` | conditions that complete the step at once when they already hold as it starts (the "checked on entry" of §3.1) | no lesson since #900 (it held the Delivery lesson's "every task done") |
| `triggers` | the events or signals that complete it, any one of them, matched only from the step's start | every; two in lesson 7 with D36 (a): the switch, or the own `Respawned` |
| `conditions` | what must hold when a trigger fires; the first that fails ignores that firing | 2: the item is a package; 8: another player within the radius. Lesson 7 needs none: `LifeView` switches targets only while the own player is dead |

The parts, a closed list like §9's (a new one is an engine request):

| Part | Kind | Settings | Reads |
|---|---|---|---|
| `EventSeen` | trigger | `event`, `fields`: a subset of the payload matched as §9.7's `WaitFor`; a peer field takes `own` or `other`, an item field `held` (the item the own hand held as the step started) | the own session's events; for `held`, the own model at the step's start |
| `ClientSeen` | trigger | `signal`: `moved`, `map_opened`, `howto_opened`, `spectate_switched`, `voice_sent`, `esc_opened`; `amount` (seconds for `moved`) | the client's signals (below) |
| `OwnLife` | condition | `life` | the own model |
| `OtherWithin` | condition | `metres`, or 0 for the current phase's voice radius (`VoiceRule.radius_of`) | the others' positions in the own model's latest snapshot (`ClientModel.avatars`), the own from the local player, which `Game` passes in |
| `ItemKindIs` | condition | `kind` | the event's `item` in the own model |
| `TasksDone` | condition | none | the own model's `tasks_done` and `tasks_total` |
| `RequestStage` | action | none | sends `NextStage` |

**The client's signals** each come from the code that already knows: `moved` from the own claims; `map_opened` from
`GameUi.map_opened`, when the map screen opens (#253; #490 restyles it); `howto_opened` from the
map's card (#254); `spectate_switched` from `LifeView` when the player switches the spectate target to another one; `voice_sent` from `VoiceSender.sent` rising; `esc_opened` from
`Game.open_esc`. `Game` connects them to the runner while a tutorial runs, so no screen knows the tutorial exists.

**What the screens read** (#492): the current lesson's number and step, its keys, and which lessons are done; the
runner's `finished` ends the session (§5).

## 4. The room (D34)
Greybox first, as `levels/CLAUDE.md` asks: one room, `levels/tutorial/rooms/tutorial_room.tscn`, placed by
`levels/tutorial/tutorial.tscn` (proposed here as `levels/tutorial/tutorial_room.tscn`; built under the
[level piece conventions](../decisions/2026-10-09-level-piece-conventions.md)), with `StaticBody3D` colliders on
layer 1 for the floor and walls and CSG for looks. One room of about 12 × 10 m (a placeholder) with its stations along the
walls, in lesson order; the environment track dresses it later and keeps every marker where it is, since the mode
checks the markers, not the looks.

| Station | Markers (`spawn_<tag>`) | Lesson |
|---|---|---|
| the start | `round_player` 1 (the own player, ordered placement) | 1 |
| a shelf | `package` 1 | 2 |
| a table | `knife` 1 | 3 |
| the raise spot | `round_player` 2 (stand-in 1) | 5 |
| the corner | `round_player` 3 (stand-in 2), and `respawn` 1 farther than `PlayerRules.respawn_free_m` (1 m in the base mode) from it, so the marker is free, and within the voice radius | 6, 7 |

No `lobby_player` marker and no lobby scene: `gather` plays at no level (E72).

The map lesson needs the room's records (#306: id, names, outline), and the room's names are the engineer's (D34).
T2 writes the record if #306 has merged; otherwise T2 opens a follow-up issue for it, linked from #306, so the map
of lesson 5 does not open with no room on it.
The mode check and the layout check run on it in `content_modes_test.gd` like every mode in `content/modes/`.

## 5. The flow in the game (E69, E70)
| Path | What happens |
|---|---|
| **First launch** (no launch option, the settings from a file, the tutorial flag absent) | `start_tutorial(invite = true)`: the session starts; once the room is in, the invite shows over it, the player frozen and the mouse free. Start: lesson 1. Skip or Esc: the session ends and the main menu shows. Either sets the flag |
| **The main menu's Tutorial** | `start_tutorial(invite = false)`: lesson 1 once the room is in |
| `gather`, `loading` | the loading screen (#494); the game sends the own `SetReady(true)` once welcomed (the tutorial has no Ready key) |
| The lesson phases | the round screen: #489's HUD without the timer (no clock runs) and the role, the lesson plates (#492); the Esc menu's tutorial variant (#491) |
| **After lesson 9** (D32), or Leave in the Esc menu | the own client leaves: the `HostNode` is freed as on a host's Leave today (`Game._end_session`), and the stand-ins with it, with no confirmation (s5: "In the tutorial: … back to the main menu"), and the main menu shows no reason for the end |
| `--tutorial` after `--` | starts it without the invite, for `playcheck` (a `tutorial` scenario header that launches one window with `--tutorial` and no bots, T3; today window 1 is always `--host --local`). `shot` renders a scene by path and takes no game options, so the room's shot needs no flag |

Tests, the runner's `host`, `join`, `playcheck` and `shot` windows, and any launch with an option never start the
tutorial by themselves (E70): each starts with an empty `user://` (#210), so a first-launch check alone would drop
every one of them into the tutorial.

## 6. E items (technical; the M6.2 manager decides and reports)
| # | Choice | Options | The failure it prevents | Recommendation |
|---|---|---|---|---|
| E62 | The solo session's transport | (a) a `LoopbackTransport` hosting on a private `LoopbackHub`; (b) ENet bound to 127.0.0.1 (`--host --local`); (c) the client runs a `Match` itself, no host | (b) opens a UDP port: a second game window or another program on that port stops the tutorial, and an offline feature runs a network listener; (c) the client reads `core/` state, against invariant 2 and E18, and every screen needs a second source | (a) |
| E63 | Where lessons are detected | (a) a client-side runner over the own events and signals; (b) lesson rules in `core/` on the host | (b) needs a new intent for each of the five client-only actions and a lesson event on the wire, all for an offline feature | (a) |
| E64 | Where the lesson classes live | (a) data-only classes in `core/content/tutorial/`, data in `content/tutorial/`, the runner in `client/tutorial/`; (b) the classes in `client/tutorial/` | (b) puts a `client/` script into `content/` data, which §1 allows the content API only | (a) |
| E65 | How the host learns a stage | (a) the `NextStage` intent (one wire row) with `ReportOutcome(next)`; (b) a `HostNode` method the game calls, no wire row; (c) host facts only: stage 6 on lesson 4's `subtask_done`, stage 7 on a new `player_revived` fact | (b) gives the own client a path into `Match` that no remote client has and the bots cannot drive, and widens E18's façade; (c) stages lesson 6 while the player is still on the map, and the player who raises early dies before lesson 7 shows | (a) |
| E66 | The host-side parts | (a) §2.5: `KnockDown` with a `pick` by peer order and `then_die`, `PlacePlayers` `ordered`, `ReportOutcome`; (b) role-based targets (a "stand-in" role) with a deal that gives roles in peer order | (b) needs an invented role and a second deal option for the same need, and a role is hidden information the tutorial does not need | (a) |
| E67 | How stand-ins run | (a) in-process `ClientSession`s on the hub that only join, ready, acknowledge and stand (§2.2); (b) the bots' `ScenarioPlay` moved from `tests/harness/` into the game to script them | (b) ships test code and a mover with no walls in the game, and a scripted stand-in can be outrun or blocked by the player | (a) |
| E68 | The mode's phases | (a) §2.3: `gather`, `loading`, then a phase per stage, chained by `next`, LifeTicks only where the respawn is needed; (b) one lesson phase with `next` rows back to itself | (b) lets a repeated `next` stage twice (a second knockdown of a downed stand-in), and one phase cannot leave the downed stand-in without LifeTicks yet respawn the player | (a) |
| E69 | The session's mode in `Game` | (a) `Game.mode` set per session (the tutorial's while it runs) and `GameFlow` showing the loading screen for a phase with no level; (b) a second main scene for the tutorial | (b) breaks the one persistent root (E19) and duplicates the session code | (a) |
| E70 | When the first launch starts it | (a) only with no launch option and settings read from a file (`UserSettings.path` not empty), plus `--tutorial` for tooling; (b) whenever the flag is absent | (b) drops every test and every runner window, each with a fresh `user://` (#210), into the tutorial | (a) |
| E71 | Tests | (a) the runner fed events and signals (unit); each new part in `tests/unit/`; a bot scenario that stages both stages over the hub with three bots (bot 1 sends `NextStage`, raises bot 2, dies and respawns); a headless integration test of `Game.start_tutorial` to the lessons phase and both stages; a `playcheck` scenario of the nine lessons by keys; the chaos rows of `NextStage`; (b) unit tests only | (b) never runs the hub, the stand-ins and the host together, which is where a stage would fail | (a) |
| E72 | Where the joiners stand in `gather` | (a) no level and no `lobby_level`; a join at no level stands at the origin with no error (§2.5); (b) `gather` in the lobby, with the room as both `lobby_level` and the map (`MarkerReader.level_paths_of` reads a path once); (c) a marker-only lobby scene beside the room | (a) unchanged, every join records a match error (`no lobby_player marker for a joiner`); (b) the client loads the room at the Welcome as the lobby, then drops it and loads it again as the map when `loading` starts (`Game._sync_level`), with the lobby screen (walking, the roster, Ready) between; (c) the lobby screen, and the own player walking with no floor until `loading` | (a) |

## 7. D items (the engineer's)
| # | Question | Options | The failure each one leaves | Recommendation |
|---|---|---|---|---|
| D25 | Lessons that need another player (6 to 8) | (a) stand-ins: real players of the session, staged by the host (§2.2, §2.4); (b) puppets drawn by the client, the raise and the spectate faked locally; (c) shortened lessons that need nobody (new texts from the UI track) | (a) two figures stand in the room from the start; (b) the client would show what the host never sent (the client rule), and the raise taught is not the real one; (c) teaches less than the screens drew | (a) |
| D26 | How many stand-ins | (a) 2; (b) 1 | (a) one more figure; (b) lesson 7's "watch another player" has no other player to switch to | (a) |
| D27 | How the stand-in goes down in lesson 6 | (a) the host knocks it down as the lesson starts, with no visible cause; (b) the second stand-in strikes it with a knife in view | (a) it falls for no reason the player sees; (b) a scripted attacker that walks, aims and swings (E67 (b)), and violence between two crew stand-ins teaches a wrong idea of who strikes | (a) |
| D28 | How the player dies in lesson 7 | (a) knocked down and dead at once as the lesson starts; (b) knocked down, then dead when the tutorial's knockdown runs out or the player gives up (F); (c) a stand-in strikes the player | (a) a death with no cause, explained only by the plate; (b) a longer lesson, and the downed state without a plate of its own; (c) a scripted attacker is no faster than the player, who can run from it, so the lesson may never start | (a) |
| D29 | Lesson 3's one-handed item (the package takes both hands) | (a) the knife on a table, the plate as drawn ("Press X"); (b) (a), plus a first instruction to pick up the knife, drawn by the UI track; (c) leave lesson 3 out until another one-handed item exists | (a) a player who presses X with empty hands gets a refusal and no hint; (b) a request to the UI track; (c) eight lessons, not the nine drawn | (b), and (a) until the UI track draws it |
| D30 | Lesson 4's text and Delivery today | (a) wait for Delivery v2 (#255, out of M6.2), which the text describes ("Find the room with the sign that's on the package"); (b) a Delivery v1 how text from the UI track (the circle of the package's colour); (c) the v2 text over v1's coloured circle | (a) no tutorial in M6.2; (b) a request to the UI track and a second text change at v2; (c) a text that misleads | (b) |
| D31 | Lesson 8 when no microphone is open (voice unavailable, Off, or push-to-talk not held) | (a) it completes on the first voice frame sent within the radius, and with no open microphone after 3 s within the radius; (b) only on a voice frame (Leave is the way out); (c) left out when no microphone is open | (a) a player with a microphone who stays silent still waits; (b) a player with no microphone cannot finish; (c) a lesson that silently disappears | (a) |
| D32 | When the game returns to the main menu after lesson 9 | (a) at once, when the Esc menu opens; (b) when the Esc menu closes after it opened (Resume, Esc or Leave); (c) after a short pause with every lesson checked | (a) the menu the lesson taught flashes and is gone; (b) Resume leads to the main menu, not back to the room; (c) a pause with nothing to do | (b) |
| D33 | The tutorial's numbers | the placeholders above: 2 stand-ins, 1 package, 1 knife, `respawn_s` 10, 1 s of walking for lesson 1, 3 s for D31, a room of about 12 × 10 m; everything else the base mode's | none until a playtest: they are placeholders, "not a decision" | the placeholders, tuned in the engineer's playtest |
| D34 | The room's shape and its names on the map | (a) one room, its stations along the walls, one room record (#306) named by the engineer; (b) two rooms with a door (a storage and a hall), closer to Delivery v2; (c) a room of the house (#523) | (a) the map lesson shows one room; (b) more level work and two names to choose; (c) ties the tutorial to the slice level and its art | (a) |
| D35 | The stand-ins' names and looks | (a) whatever the host gives any joiner (Player2, Player3; #550's rule when it lands) and the default body; (b) names and looks of their own | (a) generic names on the spectating HUD; (b) invented content | (a) |
| D36 | Lesson 7 when the respawn comes before the switch (the player respawns after `respawn_s`, and the switch exists only while dead) | (a) the lesson completes on the switch or on the own `Respawned`, whichever comes first; (b) no respawn until the switch: `death_stage` without a `Respawn`, and the switch's `NextStage` moves to a fourth phase whose row respawns the player (a new transition action); (c) only the switch, with a respawn time long enough to read the plate | (a) a slow player may respawn without having switched; (b) one more host part and phase for one lesson, and the host learns when the dead player switched the spectate target (not whom): the first intent triggered by spectating, which §5 keeps on the client; (c) a player who has not switched by the respawn can never finish lesson 7 (Leave is the only way out) | (a) |

## 8. The split
Sizes as in M5 and M6: S up to about 400 changed lines, M up to about 900. Effort as in AGENT_WORKFLOW §7.

| Issue | Goal | Acceptance | Files | Depends on | Protocol | Effort | Size |
|---|---|---|---|---|---|---|---|
| T1 core | §2.5's parts | `NextStage` as wire kind 15 (version bump, codec round trip and fuzz; 15 out of `ChaosFrames.UNASSIGNED` and §4.6.5.3's list, 16 in its place; `NextStage` in `ChaosOracle.ACCEPTS`, in `ChaosHostile._refused` expecting `not_accepted`, and its malformed shapes), `ReportOutcome`, `KnockDown` (`pick`, `then_die`), `PlacePlayers` `ordered`, a join at no level with no error (E72; a lobby level with no `lobby_player` marker still errs, and a lobby whose markers are all taken still puts the joiner on the first one); their mode checks, among them a warning on a row whose `KnockDown` without `then_die` enters a phase with no LifeTicks (§2.3); a `NextStage` step for bot scenarios (§9.7); §3.5, §4.1, §4.3.2, §9.4 updated | `core/`, `net/messages/`, `tests/unit/`, `tests/harness/`, `docs/ARCHITECTURE.md` | #550 merged first (one version bump after the other); the engineer's D25, D27, D28, D36 and E65, which decide what T1 builds | yes | high | M |
| T2 content and level | the room (greybox) and the tutorial mode | §4's scene with its markers; §2.3's mode passing the mode and layout checks; the bot scenario of both stages (E71) green in the core and the bots runners; `shot` of the room; the room's map record per #306 with the name the engineer gives (D34) if #306 has merged, else a follow-up issue linked from #306 | `levels/tutorial/`, `content/modes/`, `content/scenarios/`, `docs/ARCHITECTURE.md` §9.5, §9.6 | T1; D25 to D28, D33, D34 | no | medium | M |
| T3 client | the solo session in the game | `Game.start_tutorial`, the stand-ins (§2.2) with their source test and a `Hello` with #550's "no name", the per-session mode, `GameFlow`'s no-level rule, the first-launch rule and `--tutorial` (E70), the own Ready, no replay, leaving to the main menu with the stand-ins freed and no reason shown; a headless integration test to both stages; a networked session after a tutorial uses the base mode; `tools/runner/playcheck.py` gains a `tutorial` header (one window with `--tutorial`, no bots) with its runner test | `client/app/`, `client/tutorial/`, `tests/integration/client/`, `tests/unit/client/`, `tools/runner/`, `docs/ARCHITECTURE.md` §4.7 | T1, T2, #550; D35 | no | high | M |
| T4 client and content | the lesson runner and the nine lessons | §3's classes, `content/tutorial/tutorial.tres` (provisional), `LessonRunner` with every trigger and condition unit-tested, the client signals wired in `Game`: `map_opened` from `GameUi.map_opened` (#253); lesson 5's second step (`howto_opened`) only once #254's card exists, so the data never holds a step nothing can complete; §1's `content/` row gains the lessons (E64) | `core/content/tutorial/`, `content/tutorial/`, `client/tutorial/`, `client/app/`, `tests/`, `docs/ARCHITECTURE.md` §1, §4.7, §9.3 | T3 (the integration; the runner itself in parallel); D29 to D32, D36; E64 (the §1 boundary row) | no | high | M |
| #492 | the screens (exists) | as written, reading the runner's current lesson; plus a `playcheck` scenario through the nine lessons | as written | T4 and its own | no | high | L |
| UI track | texts for D29 (b) and D30 (b) | lesson 3's first instruction and lesson 4's v1 how text in prime-game-ui `copy/strings.csv` and s01's handoff | prime-game-ui | D29, D30 | no | — | S |

No T issue opens before the engineer has answered the ADR's "Needs the engineer" batch (the D items, E64, E65 and
the split itself): the answers decide what T1 to T4 build, and a T issue started on the recommendations alone would
build what he has not chosen.

Order: T1, then T2, then T3, with T4's runner built alongside T3 and wired after it, then #492. The map lesson (5)
also waits for #490, #253 and #254 for its final look and its second step, the Esc lesson's menu for #491, the
map's room for #306; none of them blocks T1 to T4.

## 9. The rework without tasks (#825)
Accepted (#825; the engineer's answers on PR #894, every LD item as recommended; 825a built in #900); the decisions,
the batched questions and the rejected alternatives:
[ADR](../decisions/2026-10-12-tutorial-without-tasks.md). He decided that the tutorial deals no task at all and
teaches only movement and the basic mechanics (DD10 of the
[Delivery by meaning ADR](../decisions/2026-10-10-delivery-by-meaning.md), answered on
[PR #713](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6108665402), 2026-10-11), the tasks leaving
with this rework, not as a change of their own
([#825](https://github.com/xperiaroco2/prime-game/issues/825#issuecomment-6109457789)). Which mechanics, the order
and the words are his call: the **LD** items (§9.4). The **LE** items (§9.5) are the M7 manager session's and stand
as recommended unless it reports otherwise. His answers came on PR #894; the build issues are #900, #901 and #902.

### 9.1 What today's tutorial teaches
The lessons of `content/tutorial/tutorial.tres` (§1's table), by their list names (`tutorial.list.*`):

| # | Lesson | What it teaches | Needs a task | After the rework (recommended) |
|---|---|---|---|---|
| 1 | Controls (`move`) | walking, `sprint`, `jump` | no | stays |
| 2 | Picking up and putting down (`pick_up`) | `PickUp` and `PutDown`, of the package | its item: the package spawns only through Delivery's deal (`core/tasks/delivery.gd`) | stays; the package spawned by `SpawnItems` (LD1 (a), LE2) |
| 3 | Hand and belt (`hand_belt`) | `Swap`, with the knife (D29) | no | stays |
| 4 | Delivery (`deliver`) | carrying the package to its circle (`PackageDelivered`, `TasksDone`) | yes | goes |
| 5 | Map and tasks (`map`) | (a) opening the map; (b) a task's how-to card from the map's «?» (`howto_opened`) | (b) yes | (a) stays, (b) goes (LD2 (a)) |
| 6 | Downed (`downed`) | raising a downed player (`Raise`, `interact` held) | no | stays (stage `raise_stage`) |
| 7 | Death (`death`) | watching another player while dead; the respawn (D36) | no | stays (stage `death_stage`) |
| 8 | Voice nearby (`voice`) | proximity voice | no | stays |
| 9 | Menu (`menu`) | the Esc menu | no | stays |

The player's mechanics on main that the tutorial does not teach:

| Mechanic | On main | In the tutorial today | Item |
|---|---|---|---|
| Throwing the held item (`throw` key) | built (#643 to #646, [throwing ADR](../decisions/2026-10-09-throwing-held-items.md)) | refused: the mode has no `Throw` rule | LD3 |
| Crouching | designed ([crouch ADR](../decisions/2026-10-10-crouch.md)), not built: #790 and #791 (M7, open) build it; played where `PlayerRules.crouch_maps` says (empty: every map); since #991 everywhere, with no list | no key, no rule yet | LD4 |
| The knife's strike (`Use`) | built | refused in every phase (ARCHITECTURE §9.5.17) | LD5 |
| Giving up while downed (`GiveUp`) | built; the downed plate reads "Hold {key} to give up" (#497) | refused; lesson 7 kills at once (D28 (a)) | LD6 |
| A station's `Interact` (#796) | built | none | none: stations belong to task types |
| The Guide (the Esc menu's how-to cards) | built | lesson 9 opens the Esc menu that holds it | LD2 (c) |

What stays fixed whatever he answers:
- **The stages.** `lessons → raise_stage → death_stage`, staged by the host on `NextStage` (§2.4): lessons 6 and 7
  keep their places, and an item lesson stays in `lessons`, since the death of lesson 7 drops both slots at the body.
- **The deck.** `client/i18n/strings.csv` is copied byte for byte from prime-game-ui (ARCHITECTURE §4.7.26): no
  #825 issue types a key into it; a key added or dropped is a UI track release taken by `ui-copy`. The Guide's basics
  cards (`content/howto/basics/`) reuse the tutorial's step keys, so those stay in the deck whatever the tutorial
  drops.
- **Lesson 3's knife** (D29) and its open UI request (D29 (b), the first instruction to pick it up).

### 9.2 What goes with the tasks
The list the [Delivery by meaning ADR](../decisions/2026-10-10-delivery-by-meaning.md) left to #825; all of it is
825a's (§9.7).

| Where | Today | After |
|---|---|---|
| `content/modes/tutorial_mode.tres` | task types: Delivery; settings `tasks` 1, `banned_task_types`, `packages` 1 ("Packages (Delivery)"), `knives` 1; `loading → lessons`: `DealRoles`, `DealTasks`, `SpawnItems` (the knife), `PlacePlayers`; `TaskTicks` in `lessons`, `raise_stage` and `death_stage` | no task types, no `tasks` and no `banned_task_types`, no `DealTasks`, no `TaskTicks` (LE1); a `SpawnItems` of the package by `packages` (LE2) |
| `content/tutorial/tutorial.tres` | nine lessons | lesson 4 and lesson 5's step (b) gone: eight lessons (LD2, LD7) |
| `levels/tutorial/rooms/tutorial_room.tscn` | markers `Start`, `ShelfPackage`, `TableKnife`, `DropOff` (`spawn_circle`), `RaiseSpot`, `Corner`, `Respawn` | `DropOff` gone (LE4) |
| `client/dev/tutorial_preview.gd` (its `step-howto` state), `client/dev/tutorial_step_howto_preview.tscn`, `client/dev/tutorial_step_howto_uk_preview.tscn` | the «?» step's shots (`step-howto`) | the two scenes and the script's `step-howto` state go with the step; the script stays for the invite and step shots (LE5) |
| `tests/unit/content/tutorial_mode_test.gd` | the `tasks` and `packages` settings (`test_the_deal_s_settings_are_fixed`); `TaskTicks` in the three stages (`test_the_tick_systems_with_life_ticks_only_in_the_death_stage`); `DealTasks` in the loading row's actions (`test_the_rows_and_their_actions`); "one circle" in the match's layout (`test_a_match_from_gather_to_the_respawn_in_the_death_stage`) | no task settings; no `TaskTicks`; the loading row with the package's `SpawnItems` and no `DealTasks`; no circle in the layout (LE5) |
| `tests/integration/levels/tutorial_map_test.gd` | the circle in the marker counts (`test_the_markers_are_the_design_s_stations_on_the_floor`); the drop-off across the room from the shelf, so the package is not delivered by chance (`test_the_drop_off_is_across_the_room_from_the_shelf`) | no circle in the counts (LE5); the drop-off test deleted only on his LD10 (a) |
| `tests/unit/content/tutorial/tutorial_content_test.gd` | lesson 4's row; the «?» step's card check | the eight rows (LE5) |
| `tests/integration/client/app/game_tutorial_lessons_test.gd` | the tasks done; the «?» card of Delivery | the eight lessons, no task (LE5) |
| `tests/unit/client/ui/tutorial_screen_test.gd` (it loads the real `tutorial.tres`) | the nine rows; the deliver and «?» steps (`test_step_howto_is_lesson_5s_round_keycap_and_lesson_4_has_a_title_only`) | the eight rows; the round keycap tested on a step the test builds, since no lesson shows it (LE3, LE5) |
| ARCHITECTURE | §4.7.44 ("the tutorial teaches Delivery anyway"), §4.7.46 (nine lessons), §4.7.49 (the shots), §9.5.17, §9.6 (the room), the content tree | as built by 825a |
| this page and the GDD | §1, §2.3, §4; GDD §15 | as built by 825a |

What stays (LE3, LE6): `TasksDone` (`core/content/tutorial/tasks_done.gd`), `ClientSeen`'s `howto_opened` and its
feed in `client/app/game_tutorial.gd`, the «?» step's client code (`TutorialStep.HOWTO_GLYPH` and `TutorialScreen`'s
round keycap branch, `client/ui/tutorial_screen.gd`), which no lesson uses any more,
and their tests (`tests/unit/content/tutorial/tutorial_parts_test.gd`,
`tests/unit/client/tutorial/lesson_runner_test.gd`); `content/scenarios/tutorial_stages.tres`, which names no task
(825a runs it again); every key of the deck.

What the player sees change: eight lessons ("Step n of 8"); the package carries no circle's colour and is drawn white
(`client/net/client_model.gd`); the loading screen shows no task card (`HowtoCards.deal_of` finds no `DealTasks`);
lesson 5's map opens with its Tasks panel (`map.tasks`) empty. How the map looks with no task is the UI track's
(a request, §9.7).

### 9.3 The order and the words, as recommended
Only keys the deck has (LD8 (a)); a new lesson's words go to the UI track as drafts, never typed into the deck here.

| # | List key | Step: title, how, `{key}` | Done when | Note |
|---|---|---|---|---|
| 1 | `move` | as today | as today | 825c adds the crouch key to the row (LD4 (b)) |
| 2 | `pick_up` | as today | as today | the package, spawned by `SpawnItems` (LD1 (a)) |
| 3 | `hand_belt` | as today | as today | |
| (new) | from the UI track | title and list name: drafts, not decisions, "Throw an item" and "Throwing"; how `press` with `throw` | an `ItemThrown` naming the own peer | built in #901 (825b) as lesson 4, the words from the deck (`tutorial.list.throw`, `tutorial.step.throw.*`) |
| 4 | `map` | (a) only: `map.title`, `press`, `map` | the map screen opens | the list name stays "Map and tasks ({key})", the screen's own name (`control.map`) |
| 5 to 8 | `downed`, `death`, `voice`, `menu` | as today | as today | today's 6 to 9 |

### 9.4 LD items (the engineer's)
| Item | Question | Options | The failure each prevents or brings | Recommended |
|---|---|---|---|---|
| LD1 | Lesson 2's item with no Delivery | (a) the package as a plain item, spawned on the shelf's marker by `SpawnItems`; (b) the knife for lesson 2 as for lesson 3, no package; (c) a House item of Delivery by meaning, once D2 builds it | (a) the words of lesson 2 and the Guide's basics cards, which name a package, stay true, with no wait; but after D2 the package plays only on the greybox test bench, so the tutorial names an item a House player never meets; (b) one item fewer, but lesson 2's words need new keys from the UI track; (c) waits on D2, which comes after #825, and on new words | (a); (c) as a later change once D2 has built its items |
| LD2 | Lesson 5 with no task to open a card for | (a) the map step only; (b) lesson 5 goes; (c) the «?» step becomes "open the Guide" | (a) the map is taught with no new words; its list name says "tasks" in a tutorial with none, as the Controls row does; (b) the player first opens the map in a match; (c) a new client signal (the Guide opened) and new words for what lesson 9's Esc menu already shows | (a) |
| LD3 | Teach the throw | (a) a lesson after Hand and belt (825b); (b) not taught | (a) a player who first throws in a match learns it by accident otherwise; placed after the item lessons, an item thrown out of reach blocks no later lesson; it needs the `Throw` rule in `lessons`, the throw's checks on the tutorial room (as #746 for the base mode's maps: walls of 3 m, no roof), an item in the hand (a belt item is never thrown, so after lesson 3 the step must say to take one) and two keys from the UI track; and `FlightTicks` in `lessons`, `raise_stage` and `death_stage`, since a phase without it pauses every flight (`core/items/flight_ticks.gd`) and a knife thrown just before the map lesson's `NextStage` would hang `FLYING`, hidden by the client until an `ItemPlaced` that never comes, through lessons 6 to 8; (b) a built mechanic left untaught | (a), as its own issue after 825a |
| LD4 | Teach the crouch | (a) a lesson of its own with a low prop to crouch under; (b) the crouch key in lesson 1's key row (825c); (c) not taught | (a) a new trigger, a prop and new words for one key; (b) the row shows the key, but lesson 1 completes on walking alone, so nobody has to press it; (c) the player first meets the crouch under a House table. Whatever he picks, the crouch plays in the room once #790 and #791 land (since #991 everywhere, with no list): the tutorial mode's `crouch_maps` lists the room explicitly (#790, the engineer's answer (c); an empty list is every map under the [crouch ADR](../decisions/2026-10-10-crouch.md)'s KE10), and the mode check refuses a listed path that is not one of the mode's maps, so the tutorial cannot list the House. (c) therefore means "plays, untaught"; keeping the crouch out of the room would reopen KE10 (a no-map value, its rejected (d)), an engine-request issue, not data | (b), after #790 and #791 |
| LD5 | Teach the knife's strike | (a) not taught, `Use` refused as today; (b) a swing at nobody, `Use` accepted in `lessons` | (a) the strike is first met in a match; (b) it teaches a key and not what a strike does, and a strike among the crew teaches a wrong idea of who strikes (D27's reason); "at nobody" needs a rule that hits no one: the base mode's strike rule, reused, accepts a knife `Use` that can down one of the two stand-ins in `lessons`, which lists no `LifeTicks`, so the stand-in stays down, the `lessons, next` transition's `KnockDown` (pick 1) may pick a player already down and the staged raise lesson (D27) breaks | (a) |
| LD6 | Teach giving up | (a) not taught: D28 (a) stands; (b) lesson 7 knocks the own player down first (`KnockDown` without `then_die`), `GiveUp` accepted from the downed in `death_stage`, the step done at the own death | (a) giving up is read from the downed plate in a match ("Hold {key} to give up", #497); (b) a longer lesson 7 and a knocked-down step with new words; D28's other failure (no downed plate) went with #497 | (a) |
| LD7 | The order | (a) today's with the removed left out and a new lesson in place (§9.3); (b) the map just before the menu | (a) keeps the order the UI track drew (s01); (b) puts the two screens together, but changes the drawn order for no gain the player sees | (a) |
| LD8 | The words | (a) 825a uses only the deck's keys; the new lessons' words come from the UI track as drafts at his word; the deck drops the unused keys at a later release; (b) the UI track redraws every step (s01) before any build | (a) the handoff draws nine lessons until the UI track updates it; (b) the build waits on a UI release | (a) |
| LD9 | The split | (a) §9.7; (b) with his changes | (a) one logical change per issue, none waiting on another's blocker | (a) |
| LD10 | The tests and assertions 825a drops: no test is deleted without his explicit yes (CLAUDE.md's hard rule) | (a) yes to this list: `tutorial_map_test.gd`'s `test_the_drop_off_is_across_the_room_from_the_shelf` deleted; the assertions on what goes dropped (the circle in the marker counts and in the match's layout, `TaskTicks`, `DealTasks`, the `tasks` setting, lesson 4's rows and its title-only plate, the tasks done and Delivery's «?» card in the lessons test); every other test of §9.2 rewritten to the eight lessons; (b) the list with his changes | (a) and (b): 825a deletes no test on the manager's word alone (LE5 is the manager's), and each dropped assertion is listed again in its PR | (a) |

### 9.5 LE items (the M7 manager's)
| Item | Question | Options | The failure each prevents | Recommended |
|---|---|---|---|---|
| LE1 | How the mode deals no task | (a) drop `DealTasks`, the task types, the `tasks` and `banned_task_types` settings and every `TaskTicks`; (b) keep `DealTasks` with `tasks` 0 | (b): the loading screen's `HowtoCards.deal_of` still finds Delivery dealable and shows its card, and `DealTasks`' check (`tasks` at most the pool's size) keeps a task type the mode never deals | (a) |
| LE2 | How the package spawns | (a) a `SpawnItems` of the package by the `packages` setting, with its own `rng_purpose`, in `loading → lessons` beside the knife's; the setting's display name drops "(Delivery)", which no screen shows here (no lobby, no `ChangeSettings`); (b) a setting of a new name | (b) renames what the tests and the mode check already read | (a) |
| LE3 | The parts no data uses any more | (a) keep `TasksDone`, `howto_opened`, the «?» step's `HOWTO_GLYPH` and round keycap, and their tests (the keycap's test rewritten on a step it builds); (b) remove them | (b) deletes tests, which needs the engineer's approval, and "for now" may bring a task back | (a) |
| LE4 | The room's markers | (a) remove `DropOff` only; (b) leave it | (b) a `circle` marker no rule reads, taken for a drop-off by the next reader | (a) |
| LE5 | The tests and the shots | (a) rewrite §9.2's tests to the eight lessons, deleting or dropping only what his LD10 answer approves, every changed assertion listed in the PR; the «?» shots go; (b) keep the old assertions where they still pass | (b) tests that check a lesson nobody plays | (a) |
| LE6 | The deck | (a) no #825 issue types into `strings.csv`; new keys come with a UI tag through `ui-copy` in the first PR that needs them (825b; 825c's crouch key is named by #791's `control.crouch`); (b) add the drafts to the deck here | (b) the next `ui-copy` overwrites them and `strings.lock.json` no longer matches | (a) |

### 9.6 Shared files
Scenes are single-owner: a scene has one open PR at a time, and the later PR starts after the earlier merges.

| File | Also edited by | Here | Order |
|---|---|---|---|
| `levels/tutorial/rooms/tutorial_room.tscn` | #715 (the room's map record, which waits on #306) | 825a removes `DropOff`; 825b only if the throw's checks need the room changed | 825a first: it is ready once he answers, #715 is not |
| `content/modes/tutorial_mode.tres` | #790 sets the crouch's four numbers and `crouch_maps` (the House alone) in `base_mode.tres`, and the four numbers with the room in this file; `tutorial_mode_test.gd` holds every number of the tutorial's `PlayerRules` equal to the base mode's. The tutorial's `crouch_maps` listed its own room explicitly (the engineer's answer (c), #790); since #991 neither mode has `crouch_maps` (the crouch plays everywhere) | 825a (the tasks out, the package in), 825b (`Throw`); 825c does not edit it | 825a, then #790 and 825b in either order |
| `client/i18n/strings.csv`, `client/i18n/strings.lock.json` | #715, #718, #306 (their keys); #791 (`control.crouch`, the crouch key's Controls name) | through `ui-copy` only: 825b takes a UI tag with its keys; 825a and 825c take none (825c's row names the crouch by #791's `control.crouch`) | whoever takes a tag first; the next one rebases onto it |

### 9.7 The split
Sizes as in §8. Each issue's content files are provisional under the
[MVP content ADR](../decisions/2026-09-29-mvp-content-built-by-the-engineer.md); its PR names them and ends
"Approved by the engineer: <link>".

| Issue | Goal | Acceptance | Files | Depends on | Size |
|---|---|---|---|---|---|
| 825a content | the tutorial without tasks | §9.2 done: the mode deals no task and spawns the package, both checks pass; the eight lessons of §9.3; no `DropOff`; §9.2's tests rewritten, each changed assertion listed in the PR; `tutorial_stages` green in the core and the bots runners; `shot` of lesson 5's map and of the loading screen; ARCHITECTURE, this page and GDD §15 updated | §9.2's | his answers (LD1, LD2, LD7 to LD10); before D2 and before #715 edits the room | M |
| 825b content | the throw lesson | `Throw` accepted in `lessons` with the base mode's rule; `FlightTicks` in `lessons`, `raise_stage` and `death_stage` (a flight outlives `NextStage`); the lesson after Hand and belt, done on an own `ItemThrown`, its words from a UI tag; a thrown item cannot leave the room; tests in the three tutorial test files; ARCHITECTURE §4.7.46, §9.5.17 | `content/modes/tutorial_mode.tres`, `content/tutorial/tutorial.tres`, the room if needed, `client/i18n/` through `ui-copy`, tests | 825a; LD3 (a); a UI tag with its keys | S |
| 825c content | the crouch key in lesson 1 | lesson 1's row shows the `crouch` action, named by #791's `control.crouch`; the crouch plays in the room (everywhere since #991; before, the tutorial mode's `crouch_maps` listed the room, #790); tests of the row; ARCHITECTURE §4.7.46, §9.5.17 | `content/tutorial/tutorial.tres`, tests | 825a, #790, #791; LD4 (b) | S |
| UI track | the words | a request on #150: the drafts for 825b; D29 (b) still open; D30 (b) withdrawn; the unused keys (`tutorial.step.deliver.*`, `tutorial.list.deliver`, `tutorial.step.howto.*`) dropped at a later release; s01 redrawn with eight lessons (nine with 825b); the map with no task | prime-game-ui | his LD8 answer | — |
