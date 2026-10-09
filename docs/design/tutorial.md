# The tutorial: an offline solo session, the lesson runner and its room

| | |
|---|---|
| **Status** | Proposed (#552), for the engineer. Nothing here is built. The D items (§7) are the engineer's; the E items (§6) are the M6.2 manager's and stand as recommended unless reported otherwise, but E64 (a new kind in §1's `content/` row) and E65 (a wire row) go to the engineer too. The decisions, the batched questions and the rejected alternatives: [ADR](../decisions/2026-10-08-tutorial-offline-solo-session.md) |
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

The nine lessons, with the action this design detects for each and what the world must hold. Keys are deck keys of
`client/i18n/strings.csv` (`tutorial.step.*`, `tutorial.list.*`); the key that fills `{key}` is an InputMap action
of `project.godot`, shown by `KeyLabel` (#211).

| # | List key | Step: title, how, `{key}` | The action the game sees | Seen by | What the world needs |
|---|---|---|---|---|---|
| 1 | `move` | `move.title`, the key row (`move_forward`, `move_left`, `move_back`, `move_right`, `sprint`, `jump`) | the own claims report the player moving itself (`ClientSession.claim_sent`'s `moved_itself`, counted over the ticks each claim covers) for 1 s in all | the client | a floor and a start spot |
| 2 | `pick_up` | (a) `pick_up.title`, `pick_up.how`, `interact`; (b) `put_down.title`, `press`, `put_down` | (a) an `ItemPickedUp` naming the own peer, of a package; (b) an `ItemPlaced` with cause `put_down` of the item the own hand held as the step started (`ItemPlaced` names no player) | the own events, the own model | a package |
| 3 | `hand_belt` | `hand_belt.title`, `press`, `swap` | a `Swapped` naming the own peer | the own events | a one-handed item (D29): the package takes both hands and is refused (`two_handed`, ARCHITECTURE §9.5.14) |
| 4 | `deliver` | `deliver.title`, `deliver.how`, no key | a `PackageDelivered`, or the task already done when the lesson starts | the own events, the own model | the package's circle (D30) |
| 5 | `map` | (a) `map.title`, `press`, the map action (`task_screen` until #253 renames it); (b) `howto.title`, `howto.how`, the «?» keycap | (a) the map screen opens; (b) a how-to card opens from a task's «?» | the client | the room's map data (#306), the map (#490, #253) and the cards (#254) |
| 6 | `downed` | `downed.title`, `downed.how`, `interact` held | a `Revived` of another player (only the own player raises in the tutorial) | the own events | stage `raise`: a stand-in knocked down when the lesson starts (D27) |
| 7 | `death` | `death.title`, `death.how`, `spectate_next` | while the own life is dead, the player switches the spectate target (`spectate_next` or `spectate_previous`; the first target, drawn at the death, does not count); D36 when the respawn comes first | the client, the own events | stage `death`: the own player dead when the lesson starts (D28), and two living players to watch (D26) |
| 8 | `voice` | `voice.title`, `voice.how`, no key | once the own player lives again (`Respawned`): own voice frames sent while another player stands within the phase's voice radius; D31 when no microphone is open | the client | a stand-in near the respawn marker |
| 9 | `menu` | `menu.title`, `press`, `ui_cancel` | the Esc menu opens | the client | nothing; then back to the main menu (D32) |

Five of the nine actions (the map, the «?», the spectate switch, the voice and the Esc menu) never reach the host as
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
| `lessons` | Round | the room | living: `MoveClaim`, `PickUp`, `PutDown`, `Swap`; host: `NextStage` | TaskTicks | RoundVoice, `living_m` 8 m (the base mode's) | stopped | yes |
| `raise_stage` | Round | the room | as `lessons`, plus `Raise` and `StopRaise` from the living; downed: `MoveClaim` | ChannelTicks, TaskTicks; **no LifeTicks** | as `lessons` | stopped | yes |
| `death_stage` | Round | the room | as `raise_stage`, but no `NextStage` (with D28 (b), plus `GiveUp` from the downed) | LifeTicks with a Respawn (`respawn`), ChannelTicks, TaskTicks | as `lessons` | stopped | yes |

| From | Outcome | To | Actions |
|---|---|---|---|
| (start) | the session starts | `gather` | |
| `gather` | `all_ready` | `loading` | |
| `loading` | `all_loaded` | `lessons` | `DealRoles` with no quota (everyone the default role, crew), `DealTasks` (Delivery, `packages` 1), `SpawnItems` (Knife, `knives` 1), `PlacePlayers` (`round_player`, ordered: §2.5); no `StartClock` |
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
  knock someone down (a `Strike`), and a row's action is no rule, so the phase passes as written.
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
| `ReportOutcome` | effect (listed in §9.4.2 since 2a, "with the first mechanic that needs it"; `MatchContext.report_outcome` exists) | reports `outcome` in the current phase | `outcome` | the outcome (no peer sees it, §9.2) |
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
| `starts_when` | conditions that must hold before the step shows; until then the previous lesson stays done and nothing is current | 8: the own life living (after the respawn) |
| `on_start` | actions run once when the step starts | 6 and 7: `RequestStage` |
| `done_when` | conditions that complete the step at once when they already hold as it starts (the "checked on entry" of §3.1) | 4: every task done; so a package put down inside its circle in lesson 2 does not lock lesson 4 |
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
today's task screen (`task_screen`), then from the map screen that replaces it (#490, #253); `howto_opened` from the
map's card (#254); `spectate_switched` from `LifeView` when the player switches the spectate target to another one; `voice_sent` from `VoiceSender.sent` rising; `esc_opened` from
`Game.open_esc`. `Game` connects them to the runner while a tutorial runs, so no screen knows the tutorial exists.

**What the screens read** (#492): the current lesson's number and step, its keys, and which lessons are done; the
runner's `finished` ends the session (§5).

## 4. The room (D34)
Greybox first, as `levels/CLAUDE.md` asks: one scene, `levels/tutorial/tutorial_room.tscn` (the path is a proposal:
the level conventions are the engineer's, `new-level-piece` step 1), with `StaticBody3D` colliders on layer 1 for
the floor and walls and CSG for looks. One room of about 12 × 10 m (a placeholder) with its stations along the
walls, in lesson order; the environment track dresses it later and keeps every marker where it is, since the mode
checks the markers, not the looks.

| Station | Markers (`spawn_<tag>`) | Lesson |
|---|---|---|
| the start | `round_player` 1 (the own player, ordered placement) | 1 |
| a shelf | `package` 1 | 2 |
| a table | `knife` 1 | 3 |
| the drop-off | `circle` 1, across the room from the shelf, so a package put down by the shelf in lesson 2 is not delivered by chance | 4 |
| the raise spot | `round_player` 2 (stand-in 1) | 6 |
| the corner | `round_player` 3 (stand-in 2), and `respawn` 1 farther than `PlayerRules.respawn_free_m` (1 m in the base mode) from it, so the marker is free, and within the voice radius | 7, 8 |

No `lobby_player` marker and no lobby scene: `gather` plays at no level (E72).

The map lesson needs the room's records (#306: id, names, outline), and the room's names are the engineer's (D34).
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
| D36 | Lesson 7 when the respawn comes before the switch (the player respawns after `respawn_s`, and the switch exists only while dead) | (a) the lesson completes on the switch or on the own `Respawned`, whichever comes first; (b) no respawn until the switch: `death_stage` without a `Respawn`, and the switch's `NextStage` moves to a fourth phase whose row respawns the player (a new transition action); (c) only the switch, with a respawn time long enough to read the plate | (a) a slow player may respawn without having switched; (b) one more host part and phase for one lesson; (c) a player who has not switched by the respawn can never finish lesson 7 (Leave is the only way out) | (a) |

## 8. The split
Sizes as in M5 and M6: S up to about 400 changed lines, M up to about 900. Effort as in AGENT_WORKFLOW §7.

| Issue | Goal | Acceptance | Files | Depends on | Protocol | Effort | Size |
|---|---|---|---|---|---|---|---|
| T1 core | §2.5's parts | `NextStage` as wire kind 15 (version bump, codec round trip and fuzz; 15 out of `ChaosFrames.UNASSIGNED` and §4.6.5.3's list, 16 in its place; `NextStage` in `ChaosOracle.ACCEPTS`, in `ChaosHostile._refused` expecting `not_accepted`, and its malformed shapes), `ReportOutcome`, `KnockDown` (`pick`, `then_die`), `PlacePlayers` `ordered`, a join at no level with no error (E72; a lobby level with no `lobby_player` marker still errs, and a lobby whose markers are all taken still puts the joiner on the first one); their mode checks; a `NextStage` step for bot scenarios (§9.7); §3.5, §4.1, §4.3.2, §9.4 updated | `core/`, `net/messages/`, `tests/unit/`, `tests/harness/`, `docs/ARCHITECTURE.md` | #550 merged first (one version bump after the other); the engineer's D25, D27, D28, D36 and E65, which decide what T1 builds | yes | high | M |
| T2 content and level | the room (greybox) and the tutorial mode | §4's scene with its markers; §2.3's mode passing the mode and layout checks; the bot scenario of both stages (E71) green in the core and the bots runners; `shot` of the room | `levels/tutorial/`, `content/modes/`, `content/scenarios/`, `docs/ARCHITECTURE.md` §9.5, §9.6 | T1; D25 to D28, D33, D34 | no | medium | M |
| T3 client | the solo session in the game | `Game.start_tutorial`, the stand-ins (§2.2) with their source test, the per-session mode, `GameFlow`'s no-level rule, the first-launch rule and `--tutorial` (E70), the own Ready, no replay, leaving to the main menu with the stand-ins freed and no reason shown; a headless integration test to both stages; a networked session after a tutorial uses the base mode; `tools/runner/playcheck.py` gains a `tutorial` header (one window with `--tutorial`, no bots) with its runner test | `client/app/`, `client/tutorial/`, `tests/integration/client/`, `tests/unit/client/`, `tools/runner/`, `docs/ARCHITECTURE.md` §4.7 | T1, T2 | no | high | M |
| T4 client and content | the lesson runner and the nine lessons | §3's classes, `content/tutorial/tutorial.tres` (provisional), `LessonRunner` with every trigger and condition unit-tested, the client signals wired in `Game`: `map_opened` from today's task screen (`task_screen`) until #253 and #490 replace it; lesson 5's second step (`howto_opened`) only once #254's card exists, so the data never holds a step nothing can complete; §1's `content/` row gains the lessons (E64) | `core/content/tutorial/`, `content/tutorial/`, `client/tutorial/`, `client/app/`, `tests/`, `docs/ARCHITECTURE.md` §1, §4.7, §9.3 | T3 (the integration; the runner itself in parallel); D29 to D32, D36; E64 (the §1 boundary row) | no | high | M |
| #492 | the screens (exists) | as written, reading the runner's current lesson; plus a `playcheck` scenario through the nine lessons | as written | T4 and its own | no | high | L |
| UI track | texts for D29 (b) and D30 (b) | lesson 3's first instruction and lesson 4's v1 how text in prime-game-ui `copy/strings.csv` and s01's handoff | prime-game-ui | D29, D30 | no | — | S |

No T issue opens before the engineer has answered the ADR's "Needs the engineer" batch (the D items, E64, E65 and
the split itself): the answers decide what T1 to T4 build, and a T issue started on the recommendations alone would
build what he has not chosen.

Order: T1, then T2, then T3, with T4's runner built alongside T3 and wired after it, then #492. The map lesson (5)
also waits for #490, #253 and #254 for its final look and its second step, the Esc lesson's menu for #491, the
map's room for #306; none of them blocks T1 to T4.
