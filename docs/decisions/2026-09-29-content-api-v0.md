# Content API v0: rules, kinds and bot scenarios

- **Status:** Proposed: the engineer reviews it in #33's PR; the designer reviews it before v1 (#38)
- **Date:** 2026-09-29
- **Deciders:** designed by the agent in #33, unattended overnight; the choices under "Open for the engineer" are
  provisional until the engineer's review

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
   item's data, and a new held item needs no new intent.
3. **Win conditions are checked after every fact and at the end of every step**, in the mode's order, in phases that
   check them. This implements §3.4: the effects of one command are ordered, so a kill raises `player_died` before
   the victim's package drops into its circle, and "no crew alive" is reported before the delivery.
4. **Definitions hold no state; `MatchState` does**, with generic cooldowns and counters keyed by names from the
   data. A part reads its own settings, or a match setting that the mode declares, by id; never another part's. The
   knife's numbers are in the knife's own rule.
5. **Who sees what stays per event class** (#32's choice 3). Effects emit events whose class declares the audience;
   data never chooses recipients; each part lists the events it can emit, and each condition its rejection reason.
6. **The kinds** (§9.3): game mode (with phase specs, transitions, match settings and player rules), phase class,
   rule, condition and cost, effect and transition action, tick system, voice rule, role, item kind, task type, task
   station, win condition, spawn point and bot scenario. An interactable is an item on the ground until `Interact`
   (v1). Base classes in `core/content/`, parts beside the rules they implement, data in `content/`, markers in
   `levels/`, the scenario classes in `tests/harness/`.
7. **The deal is data.** The `all_loaded` row lists `DealRoles`, `DealTasks`, `SpawnItems`, `PlacePlayers` and
   `StartClock`, each naming its RNG purpose. **`DissidentTeam` becomes `Teammates(role, peers)`**, because the
   engine no longer knows a role called dissident. The match clock is `Match`'s, run by a phase flag; stamina and
   cooldowns are settled on use, so neither needs a tick system.
8. **Sprint and jump are not parts** in v0: they are flags of the continuous `MoveClaim`, settled per covered tick
   with the numbers in `PlayerRules`. A mechanic that changes movement brings a movement modifier (v1).
9. **Bot scenarios are data:** a `BotScenario` `.tres` in `content/scenarios/`, with a setup, one script of steps
   per bot from a closed list, the expected end and events that must never arrive. Targets come from the bot's own
   filtered view. One format, two runners: through `Match` directly (stage 2j, part of `verify`) and over the
   network (M3, `tools\run.cmd bots`).
10. **The MVP's data and scenes** have a provisional layout (§9.6); a spawn point is a `Marker3D` in one
    `spawn_<tag>` group. Kinds share spawn points by naming the same tag, never by a marker with two tags, so the
    `all_ready` fit check per tag is exact.

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
- **State on the part** (a cooldown field on the knife resource): the loader cache shares the resource between
  matches and tests, and replays would diverge. **Generic conditions reading "the held weapon's" numbers:** a value
  source per setting, and a second place for the knife's numbers. Rejected for choice 4.
- **Audiences chosen in data** (a "notify" effect with a recipient setting): one mistyped audience leaks a role, and
  the leak test compares against the same declaration. Rejected for choice 5, as in #32.
- **Sprint and jump as rules:** a rule fires once; a claim covers several ticks with one flag each. Rejected for
  choice 8.
- **Scenarios as GDScript builder scripts in `tests/scenarios/`:** shorter and typed, but the designer's agent,
  which writes the scenarios from M3 (`docs/AGENT_WORKFLOW.md` §12), never writes code outside her paths. **JSON:**
  Godot's JSON parser returns every number as a float, and `check` would not validate it. **Raw command logs:** tied
  to item ids and ticks, and blind to what the bot knows. Rejected for choice 9.
- **An engine marker scene with a script for spawn points:** needs a new engine-owned folder for level-facing nodes
  (`server/` may not use `client/`), a boundary change. Groups need no script. **Markers with several tags** (a
  marker that takes a package or a knife): a check per tag counts such a marker twice, so `all_ready` could pass and
  the random deal still run out of markers; an exact check needs a matching over every set of tags. Rejected for
  now for choice 10.

## Consequences
- **The extensibility test on paper** (§9.8): the zone task (#36) is one task-type class plus data, and
  `DealTasks` gains a setting that splits tasks between task types. Resurrection (#34) as an item is data plus a
  `Revive` effect (and a `Uses` cost if the count is limited); as an action at a body it needs `Interact`. Physics
  throwing (#37) needs a `Throw` intent, a flying item state and `server/` physics, because a throw is a new verb
  and the flight is `server/`'s; delivery is unchanged. The meetings mode (#35) is several parts (`Interact`, voting,
  a tally, a meeting voice rule, phase classes) and no change to `Match` or the base mode.
- **Stage 2 keeps #32's split (2a to 2j) and its dependencies**; each part's "Built in" names its task:
  - 2a adds `core/content/` (the base classes and kinds, `GameMode` validation and a test that loads every mode in
    `content/`), the rule runner (owners, facts, the depth cap, the win-check points, outcome reporting),
    `PlacePlayers`, and the base mode's skeleton `content/modes/base_mode.tres` under the MVP content exception;
  - 2b: the phase classes Lobby, Countdown, Loading and End with their settings, `ResetMatch`, and the fit check
    over the placing actions' demands per spawn tag;
  - 2c: `DealRoles` with `RoleQuota` and `Teammates`, `DealTasks`, `SpawnItems`, and the Crew, Dissident and Knife
    data;
  - 2d: `PlayerRules`, `StaminaCost`, sprint and jump in the movement rule;
  - 2e: `ItemOnGround`, `InReach`, `InSight`, `HoldsItem`, `TakeIntoHand`, `PutDownInFront`, `item_rested`, the
    PickUp and PutDown rules, and the Package data;
  - 2f: `TaskType`, `StationKind`, Delivery and its data, `TaskTicks`, `subtask_done`;
  - 2g: `Use` (was `Hit`), `Cooldown`, `Strike`, `player_died`, `player_left`, and the knife's `Use` rule;
  - 2h: `WinCondition`, `AllSubtasksDone`, `NoneAlive`, `ClockEnded`, `StartClock`, `EndMatch`, `clock_ended`, and
    the three win-condition files;
  - 2i: the voice rules `Silent`, `Proximity` and `RoundVoice`;
  - 2j: `tests/harness/` (the scenario classes and the core runner), `tests/scenarios/scenarios_test.gd`, the marker
    reader in `server/` that builds a `LevelLayout`, a flat test level in `tests/fixtures/`, and the base mode's
    scenarios in `content/scenarios/`.
  - M3's 3d runs the same scenarios over the network (`tools\run.cmd bots`); 4e settles the marker convention with
    the designer. `ActorRole` and `ReportOutcome` have no MVP use and come with the first mechanic that needs them
    (#34, #35).
- `docs/ARCHITECTURE.md` §4.1 and §4.2 rename `Hit` to `Use` and `DissidentTeam` to `Teammates`; §3.1 to §3.4 name
  the win-check points and the row actions. The [match loop ADR](2026-09-29-match-loop-intents-events-and-entitlement.md)
  keeps its record and points here.
- `content/CLAUDE.md` belongs to the designer and still says that there is no content data before the content API
  exists and that scenarios come with M3; see "Open for the engineer".
- Risks: behaviour spread over data is harder to trace than a function, so the rule runner names the rule, owner
  and fact chain in every error and rejection log; a designer can build a rule whose refusal reveals hidden state
  (§9.2 asks each condition to say so, v0 has none); scenario steps that walk in straight lines need waypoints on
  levels with walls until M4 brings navigation.

## Open for the engineer
Adopted provisionally, each reversible until the stage-2 task named:
1. **`Hit` → `Use`** (2g). A: rename now (adopted). B: keep `Hit` and add an intent per held-item verb. A, because a
   new item is then data only.
2. **Where bot scenarios live and in what form** (2j). A: `.tres` data in `content/scenarios/`, written by the
   mechanic's owner (adopted). B: GDScript builder scripts in `tests/scenarios/`, shorter, with the folder shared
   with the designer (an ownership change). C: B, but engineer-only, with the designer asking for scenarios in
   `engine-request` issues. A, because the designer writes scenarios from M3 and stays in her folder.
3. **`content/CLAUDE.md`**, the designer's file, is out of date once 2a lands data. A: 2a edits it minimally under
   the MVP content exception, with the engineer's approval in the PR, and the designer reviews it in #38
   (recommended). B: leave it to the designer in #38.
4. **Spawn-point markers** (4e). A: `Marker3D` in `spawn_<tag>` groups (adopted). B: an engine marker scene and
   script in a new engine-owned folder (a boundary change). A for the MVP; 4e confirms it with the designer.
