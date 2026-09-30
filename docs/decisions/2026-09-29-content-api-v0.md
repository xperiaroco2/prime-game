# Content API v0: rules, kinds and bot scenarios

- **Status:** Proposed: the engineer reviews it in #33's PR; the designer reviews it before v1 (#38)
- **Date:** 2026-09-29
- **Deciders:** designed by the agent in #33, unattended overnight, and revised after a fresh adversarial review; the
  choices under "Open for the engineer" are provisional until the engineer's review

## Context
Invariant 4 says that roles, abilities, items and task types are `Resource`s composed from trigger → condition →
effect, and that the available parts are the content API, the contract between the engineer and the designer. #32
fixed the match loop and the kinds a game mode is built from (game mode, phase, action, tick system, transition
action; `docs/ARCHITECTURE.md` §3.1), and left the composition model, the first parts and the bot-scenario format to
this issue. The [MVP rules](2026-09-29-mvp-rules.md) are the first content. Resurrection (#34), the meetings mode
(#35), the zone task (#36) and physics throwing (#37) must fit later without a change to the loop. Stage 2 (#32's
handoff, 2a to 2j) builds on the names chosen here.

## Decision
The details are in `docs/ARCHITECTURE.md` §9.1 to §9.8; §3, §4.1, §4.2, §5 and §7.1 follow. The main choices:

1. **Behaviour is a rule:** a trigger (an intent, or a fact that an effect raised), conditions checked in order, and
   effects run in order. A cost is a condition that is also paid, only once every condition and cost passed. A fact
   is handled at once, depth first, with a depth cap. Task types are classes with settings, because a task type's
   deal and its check depend on each other; the rules around a task are composed.
2. **The owner of a rule scopes it.** An item kind's actions apply while an item of that kind is held, a role's to its
   players, the mode's to everyone. An accepted intent goes to the phase class, else to the first rule for it on the
   held item, the role, then the mode. So #32's `Hit(facing)` becomes **`Use(facing)`**: what `Use` does is the held
   item's data, and a new held item needs no new intent. The item-before-role order is a gameplay rule, provisional
   for #38.
3. **Win conditions are checked after every fact and at the end of every step**, in the mode's order, in phases that
   check them. This implements §3.4: the effects of one command are ordered, so a kill raises `player_died` before
   the victim's package drops into its circle, and "no crew alive" is reported before the delivery.
4. **Definitions hold no state.** Parts are stateless `Resource`s. What outlives a phase is in `MatchState`: players,
   items, tasks with a task state object that their task type owns, stations, bodies, generic cooldown and counter
   tables keyed by names from the data, and a per-part state table for a new part class, so a new mechanic adds
   state without a new `MatchState` field. What lives as long as a phase is in a fresh phase object that `Match`
   creates on each entry. A part reads its own settings, or a match setting that the mode declares, by id; never
   another part's. The knife's numbers are in the knife's own rule.
5. **Who sees what stays per event class** (#32's choice 3). Effects emit events whose class declares the audience;
   data never chooses recipients; each part lists the events it can emit, each condition its rejection reason, and
   each rule whether its public events reveal its owner's role. An outcome and its argument reach no peer by
   themselves.
6. **The kinds** (§9.3): game mode (with phase specs, transitions, match settings, sides and player rules), phase
   class, rule, condition and cost, effect and transition action, tick system, voice rule, role, item kind, task type
   (with its task state), task station, win condition, spawn point (`LevelLayout`) and bot scenario. An interactable
   is an item on the ground until `Interact` (v1). Base classes in `core/content/`, created together by 2a; parts
   beside the rules they implement; the bot-scenario data classes in `core/content/scenario/`; data in `content/`;
   markers in `levels/`; the scenario runners in `tests/harness/`.
7. **The deal is data.** The `all_loaded` row lists `DealRoles`, `DealTasks`, `SpawnItems`, `PlacePlayers` and
   `StartClock`, each naming its RNG purpose, and each placing action and task type declares its demands per spawn
   tag for the lobby's fit check. Because the engine no longer knows a role called dissident or a station called a
   circle, **`DissidentTeam` becomes `Teammates(role, peers)`** and **`CirclePlaced` becomes `StationPlaced`**;
   `TasksAssigned` names each subtask's target (an item or a station) and `SettingsChanged` the demands per tag. The
   match clock is `Match`'s, run by a phase flag; stamina and cooldowns are settled on use, so neither needs a tick
   system.
8. **Sprint and jump are not parts** in v0: they are flags of the continuous `MoveClaim`, settled per covered tick
   with the numbers in `PlayerRules`. A mechanic that changes movement brings a movement modifier (v1).
9. **Bot scenarios are data:** a `BotScenario` `.tres` in `content/scenarios/`, with a setup, one script of steps
   per bot from a closed list, the expected ends (a scenario may play several matches) and events that must never
   arrive. Every intent step can expect a refusal; joins and load acks are steps, so late joins and missed loading
   deadlines can be scripted. Targets come from the bot's own filtered view. One format, two runners: through `Match`
   directly (stage 2j, part of `verify`) and over the network (M3, `tools\run.cmd bots`).
10. **The MVP's data and scenes** have a provisional layout (§9.6); a spawn point is a `Marker3D` in one
    `spawn_<tag>` group. Kinds share spawn points by naming the same tag, never by a marker with two tags, so the
    `all_ready` fit check per tag is exact. The lobby and the map exist from 2j as flat, marker-only scenes at their
    final paths, and 4e dresses them.
11. **Replays pin the content.** The command log records the game mode's path and a hash of its content; a replay
    refuses a different hash.

## Alternatives
- **One engine class per mechanic, with settings only** (a `KnifeHit` class): every variant (a longer blade that
  only dissidents may use) would be a new class, and "mechanics are data" would hold only for numbers. **An
  expression language or node graph in data:** a second language to test, and a designer could not see what a rule
  reveals. **Signals between resources:** the order of handlers and the depth of chains would be implicit, and a
  replay needs both explicit. Rejected for choice 1.
- **Delivery as a composed rule** (`item_rested` → "rests in its station" → "complete the subtask"): one more pair
  of generic parts and events for no setting the designer could change. Revisit when a second task type shares the
  check. Rejected for choice 1.
- **A global list of rules, each with its own filter conditions** ("the actor holds a knife"): every rule would
  repeat what its owner already says, and a forgotten filter would let a package hit. **Keeping `Hit`:** every new
  held-item verb would add an intent, a wire row and an allowlist entry. Rejected for choice 2.
- **Win conditions as the last tick system and after every command** (#32's first wording): after the command both
  "no crew alive" and "every task done" can hold, and the mode's order would pick one, not the order of the effects
  that §3.4 requires. **A list of facts per condition that re-checks only it:** a forgotten fact would silently delay
  a win. Rejected for choice 3.
- **State on the part** (a cooldown field on the knife resource, the countdown's end tick on the phase spec): the
  loader cache shares the resource between matches and tests, and replays would diverge. **A new `MatchState` field
  per mechanic:** every mechanic with state would change `core/`'s central class. **Generic conditions reading "the
  held weapon's" numbers:** a value source per setting, and a second place for the knife's numbers. Rejected for
  choice 4.
- **Audiences chosen in data** (a "notify" effect with a recipient setting): one mistyped audience leaks a role, and
  the leak test compares against the same declaration. Rejected for choice 5, as in #32.
- **Sprint and jump as rules:** a rule fires once; a claim covers several ticks with one flag each. Rejected for
  choice 8.
- **Scenarios as GDScript builder scripts in `tests/scenarios/`:** shorter and typed, but the designer's agent,
  which writes the scenarios from M3 (`docs/AGENT_WORKFLOW.md` §12), never writes code outside her paths. **JSON:**
  Godot's JSON parser returns every number as a float, and `check` would not validate it. **Raw command logs:** tied
  to item ids and ticks, and blind to what the bot knows. **The scenario classes in `tests/harness/`** (the first
  draft): `content/` data would then reference engineer test code, which §1 does not allow. Rejected for choice 9.
- **An engine marker scene with a script for spawn points:** needs a new engine-owned folder for level-facing nodes
  (`server/` may not use `client/`), a boundary change. Groups need no script. **Markers with several tags** (a
  marker that takes a package or a knife): a check per tag counts such a marker twice, so `all_ready` could pass and
  the random deal still run out of markers; an exact check needs a matching over every set of tags. **A flat test
  level in `tests/fixtures/` for the stage-2 scenarios** (the first draft): the base mode would point into `tests/`,
  or at scenes that do not exist until 4e. Rejected for now for choice 10.

## Consequences
- **The extensibility test on paper** (§9.8), counted honestly: the zone task (#36) is one task-type class plus
  data and a mix setting on `DealTasks`, and one event class more for each of live progress and a public "zone done"
  if #36 wants them. Resurrection (#34) as an item needs two part classes (`BodyInFront`, `Revive`; three with a
  `Uses` limit) and one event class (`Revived`), so it misses the letter of "at most one class": a body is a new
  target and a revival a new public fact. Physics throwing (#37) needs a `Throw` intent, a flying item state and
  `server/` physics, because a throw is a new verb and the flight is `server/`'s. The meetings mode (#35) is several
  parts (`Interact`, voting, a tally, a meeting voice rule, phase classes) and a `who` setting on `PlacePlayers`.
  None changes `Match` or the phase loop. Every new event class or intent also costs a wire row (M3) and client
  presentation (M4).
- **Stage 2 keeps #32's split (2a to 2j), and #30's dependency lines stay true, because 2a now builds what the
  parallel tasks share.** The first draft of this ADR assigned `DealTasks` (2c) over `TaskType` (2f) and `SpawnItems`
  (2c) into the item state of 2e, and gave nobody the demand interface that 2b's fit check needs; parallel sessions
  would each have invented them. Now:
  - 2a: `core/content/` with the base class of every kind in §9.3 (`Condition`, `Cost`, `Effect` with the demand
    interface, `TickSystem`, `VoiceRule`, `Role`, `RoleQuota`, `ItemKind`, `TaskType` with its `TaskState`,
    `StationKind`, `WinCondition`, `GameMode` with `PhaseSpec`, `Transition`, `SettingSpec`, `SideSpec`,
    `PlayerRules`, and `LevelLayout`); `MatchState` with the items table (kind, where, position), tasks, stations,
    cooldowns, counters and per-part state; fresh phase objects per entry; the mode check without layouts and a test
    that runs it on every mode in `content/`; the rule runner (owners, facts, the depth cap, the win-check points,
    outcome reporting, `outcome_dropped`); the mode's hash in the command log; `PlacePlayers`; and the base mode's
    skeleton `content/modes/base_mode.tres` under the MVP content exception;
  - 2b: the phase classes Lobby, Countdown, Loading and End with their settings, `ResetMatch`, the mode check with
    layouts, and the fit check over the demands per spawn tag (with fake layouts in its tests);
  - 2c: `DealRoles` with `Teammates`, `DealTasks` (tested with a fake task type), `SpawnItems` into the items table,
    and the Crew, Dissident and Knife data;
  - 2d: `PlayerRules` in the movement rule, `StaminaCost`, sprint and jump;
  - 2e: the hand slot, `ItemOnGround`, `InReach`, `InSight`, `HoldsItem`, `TakeIntoHand`, `PutDownInFront`,
    `item_rested`, the PickUp and PutDown rules, and the Package data;
  - 2f: Delivery and its data (its deal, its check, its task state, the circle station), `TaskTicks`,
    `subtask_done`;
  - 2g: `Use` (was `Hit`), `Cooldown`, `Strike`, bodies in `MatchState`, `player_died`, `player_left`, and the
    knife's `Use` rule;
  - 2h: `AllSubtasksDone`, `NoneAlive`, `ClockEnded`, `StartClock`, `EndMatch`, `clock_ended`, and the three
    win-condition files;
  - 2i: the voice rules `Silent`, `Proximity` and `RoundVoice`;
  - 2j: the scenario data classes in `core/content/scenario/`, the core runner in `tests/harness/`,
    `tests/scenarios/scenarios_test.gd`, the marker reader in `server/` that builds a `LevelLayout`, the flat
    marker-only `levels/lobby/lobby.tscn` and `levels/greybox/greybox.tscn` (MVP content exception, the engineer's
    approval in its PR), and the base mode's scenarios in `content/scenarios/`.
  - M3's 3d runs the same scenarios over the network (`tools\run.cmd bots`); 4e dresses the two levels and settles
    the marker convention with the designer. `ActorRole` and `ReportOutcome` have no MVP use and come with the first
    mechanic that needs them (#34, #35).
  - 2a is larger than in #32's split. If it is too large for one session, the base classes and `MatchState` can be
    their own task before 2b to 2e start; the dependency lines do not change.
- `docs/ARCHITECTURE.md` §4.1 and §4.2 rename `Hit` to `Use`, `DissidentTeam` to `Teammates` and `CirclePlaced` to
  `StationPlaced`, and make `TasksAssigned` and `SettingsChanged` generic; §3.1 to §3.4 name the win-check points,
  the row actions, `outcome_dropped` and the mode's hash in the log. The
  [match loop ADR](2026-09-29-match-loop-intents-events-and-entitlement.md) keeps its record and points here. The
  root `CLAUDE.md` and `core/CLAUDE.md` name the rule model.
- The designer's files teach what v0 no longer matches; see "Open for the engineer" 3.
- Risks: behaviour spread over data is harder to trace than a function, so the rule runner names the rule, owner
  and fact chain in every error and rejection log; a designer can build a rule whose refusal or public event reveals
  hidden state (§9.2 asks each condition and rule to say so, and validation warns on role-gated public events; v0
  has none); scenario steps that walk in straight lines need waypoints on levels with walls until M4 brings
  navigation.

## Open for the engineer
Adopted provisionally, each reversible until the stage-2 task named:
1. **`Hit` → `Use`** (2g). A: rename now (adopted). B: keep `Hit` and add an intent per held-item verb. A, because a
   new item is then data only.
2. **Where bot scenarios live and in what form** (2j). A: `.tres` data in `content/scenarios/`, written by the
   mechanic's owner, with the data classes in `core/content/scenario/` as part of the content API (adopted). A2: the
   same data, with the classes in `tests/harness/`, and §1's "May use" cell for `content/` widened to name them (a
   boundary change). B: GDScript builder scripts in `tests/scenarios/`, shorter, with the folder shared with the
   designer (an ownership change). C: B, but engineer-only, with the designer asking for scenarios in
   `engine-request` issues. A, because the designer writes scenarios from M3, stays in her folder, and `content/`
   keeps depending on the content API only.
3. **The designer's files** are out of date once 2a lands data: `content/CLAUDE.md` (it says there is no content data
   yet, lists the engine-request kinds as trigger, condition, effect, interactable and station, and does not mention
   `content/scenarios/`), `levels/CLAUDE.md` (it does not know the `Marker3D` in `spawn_<tag>` convention of §9.6)
   and the skill `new-mechanic` (step 3 maps ideas to "trigger → conditions → effects, interactables, task stations",
   without owners, costs, facts or task types). A: 2a edits them minimally under the MVP content exception, with the
   engineer's approval in its PR, and the designer reviews them in #38 (recommended). B: leave them to the designer in
   #38.
4. **Spawn-point markers** (4e). A: `Marker3D` in `spawn_<tag>` groups (adopted). B: an engine marker scene and
   script in a new engine-owned folder (a boundary change). A for the MVP; 4e confirms it with the designer.
5. **The levels in stage 2** (2j). A: 2j adds the flat, marker-only lobby and map at their final paths in `levels/`
   under the MVP content exception, and 4e dresses them (adopted). B: the base mode names no levels until 4e; the
   mode check and the scenarios take fixture layouts from `tests/fixtures/`, and a scenario overrides the lobby and
   the map. A, because the mode's paths never change and `content/` never points into `tests/`.
