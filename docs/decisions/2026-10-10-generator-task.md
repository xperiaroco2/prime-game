# The Generator task (#679): its engine parts, a station-use intent, and the split

- **Status:** Proposed on 2026-10-10. Nothing here is built. The rules are the engineer's: #679's "Decided" list
  (chat, 2026-10-09). The GD items are game rules and taste that list leaves open: they are his (the
  [trust ADR](2026-10-04-trust-based-autonomy-gated-merge-into-main.md)'s tier (c)), each with options and a
  recommendation, and the design proceeds with the recommendation where it can be reverted. The GE items are
  technical, the game-design manager session's to decide and report (tier (a)): decided here, each revertible in its
  issue.
- **Date:** 2026-10-10
- **Deciders:** the engineer (the rules, GD1 to GD11; GD1's name and description answered on 2026-10-10); the game-design manager session of #676 (GE1 to GE12).
  Designed by the agent of #679, on the engineer's word (#679; the track's kickoff on #593, comment 6088751685).
- **Builds on:** [content API v0](2026-09-29-content-api-v0.md) (task types are classes with settings; `Interact`
  is v1), [MVP rules](2026-09-29-mvp-rules.md) (Tasks: the engineer's decision of 2026-09-30, #79),
  [vision revision 1](2026-10-01-vision-revision-1.md) (V4's "living", no ghosts, two hands),
  [the M4 client design](2026-10-01-m4-first-person-client.md) (its render checklist, items 4, 5 and 10; E33's
  hearing range), [the zone task ADR](2026-10-09-m7-zone-task.md) (#36, built on `release/m7`: `StationState.contains`,
  `ZoneProgress`, the station mode checks, the client's progress fold), [level piece
  conventions](2026-10-09-level-piece-conventions.md) (station scenes in `levels/stations/`),
  [MVP content built by the engineer](2026-09-29-mvp-content-built-by-the-engineer.md) (content and levels are
  provisional, approved in their PRs), [the House map](../design/house-map.md) (§2 decision 8, the stations of §6),
  [tests on CI](2026-10-09-tests-on-ci-local-lint-and-check.md) (#605: what "green" means in §8)
- **Numbering:** GD and GE are this ADR's own; the issues are G0 to G8 (§8), which the manager opens from the PR's
  handoff.

## Context
The engineer's rules (#679, "Decided"), in short: the Generator is a task type whose subtasks are its switches. Four
switches stand in four basement rooms out of each other's earshot; 2 to 4 of them are active (the host's lobby
setting, default 3), the rest always on. Every active switch starts off and toggles on each press, with no cooldown.
Anyone presses the generator's button: with every switch on a press starts the charge and a second press stops it;
with a switch off it plays its animation and nothing happens. A switch going off stops the charge, which only a new
press resumes. The charge is cumulative, 60 s in all, one per match; charged is done for good. A 4-bar battery at the
panel lights a bar per switch on and glows blue when all are lit; it is seen only there. Everyone sees the charge
percentage. Every action has a sound, carrying 12 m. Nobody is told who switched a switch. A dissident plays under the
same rules; the knocked-out and the dead can do nothing; a two-handed item stops a use. The one item #679 left open,
the task screen's description and whether the working name "Charge the generator" stays, he answered on 2026-10-10
(#679's comments [6089213752](https://github.com/xperiaroco2/prime-game/issues/679#issuecomment-6089213752) and
[6089352170](https://github.com/xperiaroco2/prime-game/issues/679#issuecomment-6089352170)): the name stays, and the
description is a draft he accepted, "Switch on every active switch, then press the generator's button to charge it.",
to be approved in the content PR (G5).

It is the first mechanic with a **fixed interactable**: the player presses a thing the level holds, not an item.
ARCHITECTURE §9.3 lists fixed interactables as v1, and §9.8 planned `Interact(target)` "with the first mechanic that
needs it". It is the second task type with a tick, after the zone task, whose parts it reuses where they fit (§1.2).

What already holds (ARCHITECTURE §9, §5):
- **Tasks are shared** (#79): nobody owns one, any living player does any subtask, each type has its own subtasks
  setting, and the `tasks` setting draws the types. **"Living" means ALIVE** (V4): the downed are not living, and the
  dead have no avatar.
- **Hidden by sight is a client rule.** Every living or downed avatar and every item reaches every player in the
  snapshots; a hidden package is hidden because the client draws an item only where it lies, depth-tested, and no
  screen lists items or players (the M4 render checklist, item 5), and a world sound plays only within 12 m of the
  listener (item 10, E33 (a); `SoundChooser.HEARING_RANGE_M`). Hiding positions behind walls on the host is "not
  wanted now, only if a human asks" (ARCHITECTURE §10).
- **The task slots:** a `TaskType` subclass with its `TaskState` as an inner class; `TaskTicks` runs each ticking
  type in Round after `LifeTicks` and `ChannelTicks` and before the match clock; `StationKind` (spawn tag, radius,
  height, palette), whose markers `MarkerReader` snaps to the floor for every station kind a task type holds;
  `StationPlaced`, `TaskState` and `TaskProgress` are generic; `Tasks.subtask_done` is the one way a subtask completes.
- **On `release/m7`** (M7-Z1 to M7-Z4, which reach main when the milestone merges): `StationState.contains` (the
  cylinder test), `ZoneProgress` (a station's ticks, needed, counting, tick; everyone), the mode checks of ZE3 (no
  station kind or spawn tag twice; a ticking type needs `TaskTicks`), scenario bans (M7-Z2) and the client's fold of
  a station's progress (`ClientModel.Station`, ZE8).

## Decision

### 1. The mapping (`new-mechanic` step 3)

#### 1.1 Each rule to its engine part

| # | What #679 needs | Engine part | Exists? |
|---|---|---|---|
| 1 | The Generator is a task type, like Delivery | `Generator extends TaskType` (`core/tasks/generator.gd`), `has_tick()` true | missing: G2 |
| 2 | Each switch on or off, the charge so far, whether it charges, done | `Generator.State extends TaskState` (§9.1's task state, GE5): the generator's station id; per switch its station id, whether it is active, whether it is on; the charge's ticks; running; done | missing: G2 |
| 3 | Two station kinds: a switch, the generator with its button | two `StationKind` sub-resources of the task type: `switch` and `generator` (ids and spawn tags provisional, "not a decision"), each with its spawn tag, radius and height (GE3), an empty palette, and its own `Interact` rule (GE2) | the class exists (`core/content/station_kind.gd`); its `actions` are G1; the data G5 |
| 4 | The subtasks are the active switches, 2 to 4, set by the host in the lobby | the type's own subtasks setting, a whole-number `SettingSpec` of the mode, which the lobby shows (`client/ui/lobby_panel.gd`: one control per `SettingSpec`), as Delivery's `packages`; the type's check refuses a maximum above its switch count | exists as a pattern (`Delivery.subtasks_setting`, the base mode's `packages`); the check G2, the setting G5; #256's shared part: §6 |
| 5 | Always four switches; the battery always has 4 bars | `switches`, a whole number in the type's data (4): the deal places that many switches and the demands ask for that many markers | missing: G2 (the property), G5 (the value) |
| 6 | At the round's start every active switch is off, the others on | the deal draws which switches are active (GD2) and sets the start states | missing: G2 |
| 7 | A player presses a switch or the button | `Interact(station)`, a new intent (GE1), accepted from the living in Round, its rules owned by the station's kind (GE2) | missing: G1 (§9.8's `Interact`, never built) |
| 8 | The knocked-out and the dead can do nothing | the phase's allowlist: `Interact` from the living only, so the downed get `not_accepted` and the dead, with no avatar, send nothing | exists: `AcceptSpec`; the data G5 |
| 9 | Busy hands: a two-handed item stops a use | `HandNotTwoHanded` in each station kind's rule (`two_handed`) | exists: `core/items/hand_not_two_handed.gd` |
| 10 | In range and in sight of the device | `AtStation`: the actor's feet inside the station's cylinder (`StationState.contains`, GE3; `out_of_reach`); `StationInSight`: the actor's eye to just above the station's marker (GE4; `blocked`) | missing: G1; `StationState.contains` exists on `release/m7` |
| 11 | A fixed switch cannot be switched; nothing works once charged | `StationUsable`: the station's task type takes a use now (`TaskType.use_problem`), else its reason, `unavailable` (GD5) | missing: G1 (the condition and the hook), G2 (the Generator's answer) |
| 12 | A press toggles a switch; the button starts, stops or does nothing | `UseStation`, an effect that calls the station's task type (`TaskType.use_station`), which alone writes its task state (§9.1) | missing: G1 (the effect and the hook), G2 (the Generator's use) |
| 13 | A switch going off stops the charge; a second press stops it | `Generator.use_station` | missing: G2 |
| 14 | The charge: cumulative, 60 s, one per match | `Generator.tick` through `TaskTicks`: one tick per host tick while running; `seconds` in the data (GD9), converted once by the one rounding rule (§3.3: 60 s is 1,200 ticks at 20 Hz) | `TaskTicks` exists (`core/tasks/task_ticks.gd`); the tick is G2 |
| 15 | Charged is done for good | every station done; every subtask done through `Tasks.subtask_done` (GD3); every later use refused | `Tasks` exists (`core/tasks/tasks.gd`); the rest G2 |
| 16 | Everyone sees the charge percentage | the progress event (GE7: `ZoneProgress` reused), public, on each start, stop and done; a client fills between events | the event and the fold exist on `release/m7`; the Generator's use G2; its task-screen row G6 |
| 17 | Every action has a sound; sounds carry 12 m | public events, audience everyone, no peer field: `SwitchChanged(station, on, fixed)` (a switch: its station id, whether it is on, whether it is an always-on switch; sent for every switch in the deal and on each toggle, so a client knows the fixed ones and shows no hint over them), `ButtonPressed(station)` (the button: the generator's station id), the progress event `ZoneProgress(station, ticks, needed, counting, tick)` (the charge, GE7); the client plays each only within 12 m (E33 (a)) | the range exists (`client/world/sound_chooser.gd`); the events G2; the sounds G6 |
| 18 | Nobody is told who switched a switch | no event of the Generator names a player | by design: G2 |
| 19 | The battery: a bar per switch on, blue when all are lit, seen only at the panel | no part in `core/`: the client counts the switches that are on from `SwitchChanged` and draws the bars on the panel in the world, depth-tested, on no screen (GE6, GD4) | missing: G6 (the view), G4 (the panel's nodes) |
| 20 | A dissident plays under the same rules | no condition reads a role, so no public event can tell one (§9.2, "a public event can reveal its rule's owner"); a role-swap test proves it (§7) | by design; the test G2 |
| 21 | The host's own player follows the same rules | its client sends `Interact` like any other (peer 1 is exempt from the rate budgets only, §4.5.6) | exists |
| 22 | The stations in the generator hall, storage, the boiler room, the pump room and the switch room | `levels/stations/generator.tscn` and `switch.tscn` (GE11), instanced in the five rooms in place of the markers; `MarkerReader` snaps their use-spot markers to the floor into the `LevelLayout` | the markers exist (`Generator`, `SwitchA` to `SwitchD`: plain `Marker3D`s under `Stations`, no group, in `levels/house/rooms/`); the reader and the layout exist (`server/levels/marker_reader.gd`, `core/content/level_layout.gd`); the scenes G4 |
| 23 | Players at different switches cannot hear each other | a content test per map: every two switch markers farther apart than the world sounds' 12 m, and so than the voice's 8 m (12 m is derived from E33's hearing range, stricter than the engineer's "more than 8 m"; his to confirm in G5's PR, else 8 m) | missing: G5 (House passes: 20 to 39 m, house-map §6) |
| 24 | Tested without bots on House (ARCHITECTURE §9.7) | unit tests from fixtures (G1, G2); integration tests on House in the host's real world (G7) | missing |

#### 1.2 Beside the zone task

| | Zone task (#36) | Generator | Why |
|---|---|---|---|
| Progress | `ZoneProgress` per zone, on a change; the client extrapolates | the same event for the generator's station (GE7) | same shape: ticks, needed, running, tick |
| Event window | at most one per zone per 5 ticks (ZE4) | the same window for the charge's progress event; none for `SwitchChanged` and `ButtonPressed` (GE8) | the bucket alone lets one peer's button spam send two reliable events per press to everyone; a switch or a press is one event per accepted intent, like `Swapped` |
| Stale claims | ZE10's claim age | none | a use is an intent checked in its own tick, not presence over time |
| Inside test | `StationState.contains` with the feet | the same, for "at the station" (GE3) | one cylinder for every station |
| Who counts | any living player, whatever the role | any living player, whatever the role | a role-gated public event tells a role (§9.2) |
| Stations | one per subtask, on random markers, in palette colours | one generator and `switches` switches, on every marker of the map (exact counts, no placement draw), no colours; N of the switches active | the stations are the level's devices, not places dealt anew |
| Done | per zone, one subtask each | the whole task at once, at full charge (GD3) | the subtasks are the switches, and the charge is one |
| Task screen | unchanged (its rows are `TaskState`s) | the generator's row shows the charge percentage (GD8) | #679: everyone sees the percentage |

### 2. The rules as the engine runs them (with the recommendations)
1. **The deal** (when `DealTasks` draws the Generator): a station on every marker, with no draw for placement: the
   generator on the map's one `generator` marker and the `switches` (4) switches on its `switch` markers, in level
   order. Each marker is a device scene (GE11), so a marker the deal skipped would stand in the level as a dead device;
   the type's demands are therefore exact, not minimums: the fit check refuses a map with any other count (GE10). N of
   the switches are active, N the subtasks setting, drawn from the RNG purpose `switches_rng` (GD2). The active ones start off; the others start on and are fixed. Station ids: the generator first, then the
   switches in level order. With N = 0 no switch is active: the task has no subtasks and is done (#79), and nothing
   can be used.
2. **A use** is `Interact(station)` from a living player in Round. In this order it is refused `two_handed` (a
   two-handed item in hand), `out_of_reach` (the feet of its last accepted claim outside the station's cylinder),
   `blocked` (no line of sight from its eye to just above the station's marker) or `unavailable` (a fixed switch, a
   charged generator). A station whose kind holds no `Interact` rule (a delivery circle, a zone) and an unknown
   station find no rule: `nothing_to_do` (§9.2). Applied, it stops the actor's own running channel, a raise, as every
   applied action does (§9.2).
3. **A switch's use** toggles it. One that goes off while the charge runs stops the charge in the same command.
4. **The button's use:** the charge runs: it stops. It does not run and every switch is on: it starts. Otherwise
   nothing changes; the press is still an applied action, with its event, animation and sound.
5. **The charge**, every tick of a phase that lists `TaskTicks` (Round) while it runs: one more tick. At `seconds`
   converted once (1,200 ticks): done. It stops running, every station of the task is done, the progress event goes
   out at its full value, then each active switch's subtask is done in station order (GD3).
6. **Nothing else** stops or resets the charge: no hit, knockdown, death or leave of anyone; the charge belongs to no
   player. `TaskTicks` runs only in Round, and the state stays in `MatchState` until `ResetMatch`.

### 3. What everyone sees

| What | Who learns it | How |
|---|---|---|
| Where the generator and each switch stand | everyone | `StationPlaced` in the deal (and the level's own scenes) |
| Which switches are active, and each switch's state | every client receives it; an honest one shows it only where the eye or the ear reaches: the switch's look in the world, the panel's bars at the generator, the click within 12 m | `SwitchChanged` in the deal and on each use (GE6) |
| A press of the button | every client receives it; shown in sight, heard within 12 m | `ButtonPressed` |
| The charge: so far, running, done | everyone, on the task screen too | the progress event (GE7) |
| Who switched or pressed | nobody, through an event | no event names a player; the snapshots show who stood there, as for a delivery or a zone |
| The battery | whoever stands at the panel and looks at it | drawn on the panel in the world, depth-tested, on no screen or HUD (GD4) |

"Seen only at the panel" and "nobody is told who" hold for every honest client. A modified client could draw every
switch from the wire, as it can draw every hidden package from the snapshots today; GE6 says why the host does not
filter them, and GD11 puts the choice to the engineer.

### 4. Edge cases

| What happens | What the engine does | Why |
|---|---|---|
| Two players press the button in one tick | commands in their order (§4.5.3): the first starts the charge, the second stops it | determinism; "a second press stops it" |
| A switch goes off and the button is pressed in one tick | in command order: a switch off first keeps the charge from starting; the button first starts it, and the switch then stops it | the same |
| A switch goes off in the tick the charge would complete | the command runs before `TaskTicks`: the charge stops one tick short | §4.5.3: a tick's commands, then its tick systems |
| The charge completes in the clock's last tick | done, and "every task done" holds if it was the last task | `TaskTicks` before the clock (§3.3), as a delivery |
| A player is knocked down, killed or leaves after switching | nothing: the switch stays as left; the charge runs on | #679: "it stays as it was left"; the charge belongs to no player |
| A downed player crawls to a switch | `not_accepted` | the allowlist (V4) |
| A raiser presses a switch | the press applies and the raise stops (`RaiseStopped`) | §9.2: an applied action stops its actor's channel |
| A knife holder presses E at a switch | the switch toggles; the knife's `Use` never runs | GE1 |
| A package carrier | `two_handed`: put it down, use, pick it up again | #679: busy hands |
| A player behind a wall within the radius | `blocked` | GE4 |
| A press of a fixed switch | `unavailable`, no event (GD5) | #679: "cannot be switched off" |
| Any use after the charge is done | `unavailable` | #679: "can no longer be used" |
| A client spams a switch or the button | each accepted press's `SwitchChanged` or `ButtonPressed` goes to everyone, bounded by the reliable-intent bucket (100, refilled at 20 a second per peer, §4.5.6); the charge's starts and stops go out at most once per 5-tick window | GE8 |
| Round ends while charging | nothing more counts; the charge stays until `ResetMatch` | the task state is `MatchState`'s (§9.1) |

### 5. GD items (the engineer's: game rules and taste)

| # | Question | Options | Trade-offs, and the failure each prevents | Recommendation |
|---|---|---|---|---|
| GD1 | The task screen's description and the task's name (#679's open item); the lobby setting's label | **Answered on 2026-10-10** (#679's comments 6089213752 and 6089352170): the name "Charge the generator" stays; the description is "Switch on every active switch, then press the generator's button to charge it.", a draft he accepted, to be approved in G5's PR. Still open: the subtasks setting's label (`SettingSpec.display_name`), a name the lobby shows to every host | the mode check refuses an empty description, so G5 needed one; the label is a name too | the label: his words, or a placeholder in G5 marked "not a decision", his to approve in its PR |
| GD2 | Which switches are active | (a) drawn at random each round; (b) fixed by the map, the first N in level order (A, B, C); (c) chosen by the host | (a) players cannot learn one route, as Delivery's circles move each round. (b) the same rooms every match: one memorised route, and with N = 3 switch D never matters. (c) one more lobby control, and a host who always picks the same | (a) |
| GD3 | How the Generator counts in the shared progress (the HUD's `TaskProgress`) | (a) its N subtasks are done together, at full charge; (b) one subtask per switch that is on, going up and down; (c) one subtask, whatever N | (b) the HUD would show every player, everywhere, how many switches are on, against "seen only at the panel", and a done subtask would be undone, which `Tasks` never does. (c) breaks "its subtasks are its switches" | (a); the task screen's row shows the charge percentage (GD8) |
| GD4 | What the panel's bars say | (a) one bar per switch in a fixed order, labelled A to D: the panel says which switch is off; (b) a count, filled from one end like a battery's level: it says how many are on, not which | (a) "B is off" points at whoever claimed B: lies are caught at once, unless nobody stands at the panel. (b) reads "a battery of bars, one per switch that is on" literally; which switch is off is for the players to find out, without hearing each other, which is the intent. The wire is the same either way: only the client's panel differs | (b) |
| GD5 | A fixed switch | (a) a press is refused (`unavailable`): no event, no sound, no hint; (b) a press is accepted and changes nothing, with its click. And its look: (i) like an active switch that is on; (ii) marked as fixed | (a) "cannot be switched off" as a refusal; with no hint over it (the hint follows the host's rules, as the pick-up hint does), a player learns it is fixed by trying. (b) a click that does nothing, as the button's with a switch off. Which switches are fixed is public by sight anyway: they are on at the start | (a); the look is the art track's, (i) until it says otherwise |
| GD6 | How near and how high a player must be to use a station | the switch's and the generator's `radius_m` and `height_m` (GE3) | too small: refused `out_of_reach` while standing at the device; too large: a press from the doorway, or through a thin wall where the sight line passes. Today's numbers: the pick-up and raise reach is 2 m, the circle's height 2 m | 2 m and 2 m for both, placeholders, "not a decision" |
| GD7 | Where the Generator plays, and how many task types a match deals | (a) in the base mode, with G4's generator and switch station scenes instanced on the greybox at placeholder points (not bare markers: the client draws the devices from those scenes, GE11), so every map fits; (b) in the base mode on House only: a greybox host must ban it every time; (c) a per-map draw: `DealTasks` and the fit check leave out a type a map has no markers for (an engine change). And `tasks`: (i) every type every match (3 with the zone task: the default and maximum 3); (ii) drawn | (b) a manual ban in every greybox lobby, as the zone ADR's ZD10 (b). (c) a host who left the type in gets no generator without a word. (i) keeps every chain in every match, as ZD8 (a) did for two types; the match clock (10 minutes, the base mode) may want a retune for three. (ii) half the matches lose the generator | (a) and (i); the clock his |
| GD8 | "The map screen with the tasks" | (a) the Tab task screen: the Generator's row shows the charge percentage; (b) a map screen, its own design later | no map screen exists (live: none in `client/`), and the task screen shows no map (the M4 design's answer 2, render checklist item 4) | (a) |
| GD9 | The 60 s: data or a lobby setting | (a) data in the task type, as the circle's radius and the zone's time (ZD7); (b) a lobby setting | (b) one more control; #679 makes only the switch count the host's | (a) |
| GD10 | The sounds | a switch's click, the button's click, the charge: (a) a hum at the generator while it charges, stopping when it stops or is done; (b) (a) and a sound when it is done | #679: "every action has a sound (a switch, the button, the charge)"; a done sound is not in it | (a); placeholder blips built in code, as `WorldSounds` makes today's, until his CC0 files arrive with their `docs/credits/` entries (the M4 design's D9, #144) |
| GD11 | How hidden "seen only at the panel" and "nobody is told who switched" are | (a) hidden by sight: every client receives every switch's state and every press (GE6 (a)), and an honest client shows them only where the eye or the ear reaches, as packages and world sounds today; (b) hidden on the wire: the host sends a switch's state only to peers near or in sight of it (GE6 (b)) | (a) a modified client could draw all four switches anywhere and, with the public positions and `SwitchChanged`'s arrival tick, tell who switched one off, as it can draw every hidden package today. (b) a new audience kind with its own leak-test invariant and state sent as a peer walks into range, which §10 keeps for "only if a human asks"; the public positions still show who stood at a switch | (a) |

### 6. GE items (technical: the manager decides and reports)

| # | Choice | Options | The failure it prevents | Decision |
|---|---|---|---|---|
| GE1 | The station-use intent | (a) `Interact(station)`: one intent naming a placed station by id (`StationPlaced`'s), sent on E (the `interact` action, as a pick-up and a raise) over a station, the host checking everything again; (b) `Use(facing)` with a rule of the mode that finds the station in front; (c) an intent of the Generator's own (`PressSwitch(station)`) | (b) `Use` goes to the hand item's rule first (§9.2): a knife holder at a switch would stab, and a station rule of the mode fires only for an empty hand or a package, which busy hands refuses. (c) one intent per mechanic: the next station (the lift, the grill) adds another. §9.8 sketched `Interact(target)` for fixed interactables and bodies; this builds the station half, and a body report (#35) adds its own field or intent then | (a) |
| GE2 | Who owns a station's rule | (a) its station kind: `StationKind.actions`, rules on `Interact`, which `Match` tries first for an intent naming a station (the station's kind, then the role's, then the mode's), as an item kind owns its actions (§9.2); (b) one `Interact` rule of the mode for every station, busy hands inside the Generator's class; (c) no composed rule: the task type checks everything | (b) a mode holds one rule per trigger, so the next station that wants other conditions (one that takes a two-handed item) cannot have them. (c) busy hands, reach and sight become code instead of data, against invariant 4. The station's task is found through its kind: ZE3 holds every station kind in one task type, and a type deals one task per match (#79). ModeCheck counts station kinds' rules as handlers of `Interact` and checks them as it checks an item kind's (one rule per trigger, where each condition may appear, `ChannelTicks` for a channel) | (a) |
| GE3 | "At the station" | (a) the actor's feet (its last accepted claim) inside the station's cylinder: `StationState.contains`, with the kind's `radius_m` and `height_m`; (b) a `reach_m` in the rule, as `InReach` | (b) a second number for the same thing, and the kind's radius and height, which its check requires, would mean nothing for a switch. With (a) one cylinder means "at the station" for every station: a package rests in it, a zone counts a player in it, a switch is used from it | (a), `AtStation` (`out_of_reach`) |
| GE4 | Sight | (a) from the eye (`Items.eye_of`) to just above the station's marker (`Items.lifted`), as `InSight` for an item; the marker is the use spot, on the floor in front of the device, clear of its collision (GE11); (b) a second marker at the device's face, not snapped; (c) no sight check | (c) a press through a thin wall from the next room whenever the cylinder reaches through it. (b) one marker kind more and a reader exception. (a) reuses the tested geometry and records its `WorldQuery` answers in the command log as `InSight` does | (a), `StationInSight` (`blocked`) |
| GE5 | Where the state lives | (a) the task state (`Generator.State`), and `StationState.done` on every station at full charge; (b) the per-part state table; (c) fields on `StationState` (on, fixed) | (b) splits one task over two homes where §9.1 names the task state. (c) a field every station kind carries for one type | (a) |
| GE6 | Who receives the switch states and the presses | (a) everyone (`SwitchChanged`, `ButtonPressed`, the progress event: audience everyone), and the client shows each only where the eye or the ear reaches; (b) the host filters by place: a new audience kind (within a radius of a point, or in sight), and a peer coming near a switch is sent its state then | (b) a new audience kind with its own leak-test invariant, and a state sent when a peer walks into range: per-entity visibility by distance, which §5 does not have and §10 keeps for "only if a human asks". It would not hide who used a switch either, which the public positions show. (a) is how items and world sounds already work (the M4 render checklist, items 5 and 10) | (a), the engineer's to confirm as GD11; host filtering only if he asks |
| GE7 | The charge's progress event | (a) reuse `ZoneProgress(station, ticks, needed, counting, tick)` for the generator's station, and the client's fold of it; (b) rename it `StationProgress` for both types first; (c) a new `GeneratorCharge` of the same shape | (c) one event class, wire row and client fold more for the same fields. (b) touches every file of the M7 track's progress for a name | (a): G2 depends on G1, which depends on `release/m7` in main, so (c) does not arise; (b) a cleanup if anyone wants the name. The reuse's knock-ons: G2 rewrites `ZoneProgressEvent`'s class doc and its §4.2 and §5 rows as "a station's progress (a zone, or the Generator's charge)", which also covers the deal's progress at 0 (GE9), which the zone task never sends; G5 adds `tests/harness/chaos/` and `tests/harness/perf/` (both build base-mode setups with the defaults, so they deal the Generator, and `chaos_scenario.gd` waits on `ZoneProgress` by its fields alone): each scopes its `ZoneProgress` waits to the zone's station kind, or bans the Generator with `tasks` lowered in the same change |
| GE8 | A rate limit on the Generator's events | (a) none: each event follows an accepted intent, which the reliable-intent bucket bounds (§4.5.6); (b) ZE4's window for the progress event only: a start or stop inside a 5-tick window goes out at the window's end with that tick's state, done in its own tick; `SwitchChanged` and `ButtonPressed` stay one per accepted intent, like `Swapped` | (a) the bucket's rate (20 a second, 100 in a burst) is the very rate ZE4 rejected as too costly, and each button press emits two events: one peer spamming the button with every switch on sends 40 reliable events a second to every player (200 in a burst tick) and flips the hum 20 times a second; it would also break `ZoneProgress`'s documented "at most once per zone per `ZoneTask.WINDOW_TICKS`". (b) the charge still changes at once on the host, and the event's `tick` keeps the client's extrapolation right; #679's "no cooldown" is about the switch, which (b) leaves alone | (b); a unit test: 100 button presses in 100 ticks cause at most 100 / 5 + 1 progress events; the chaos bots' burst row (§7) |
| GE9 | The order of events | in one command: a switch's `SwitchChanged`, then the progress event if the charge stopped; the button's `ButtonPressed`, then the progress event if it started or stopped (in that tick, or at the end of GE8's window with that tick's state, never before its cause). At full charge (in `TaskTicks`): the progress event, then `Tasks.subtask_done` per active switch in station order (`TaskState`, `TaskProgress`, `subtask_done`), as Delivery sends `PackageDelivered` first. The deal: `StationPlaced` per station in id order, then `SwitchChanged` per switch, then the progress event at 0 | a `TaskState` that arrives before the charge shows full; a sound before its state | as stated |
| GE10 | The mode checks and the demands | `Generator.check`: both station kinds set, with different spawn tags (and ZE3 across the mode); `switches` at least 1; the subtasks setting declared, a whole number, its minimum at least 0 and its maximum at most `switches`; `seconds` within 0.05 to 600 (`ZoneTask`'s bounds), its neutral default outside them; a non-empty RNG purpose; each station kind holding an `Interact` rule whose effect is `UseStation`. Demands: exactly one `generator` marker and exactly `switches` `switch` markers, whatever the setting and the players (an exact count, new beside Delivery's minimums: the fit check refuses more as well as fewer, so no device scene stands unused, §2.1); no colours | a setting of 4 on a type with 3 switches deals a fourth active switch that does not exist; a station kind nobody can use leaves a task no round can finish | as stated |
| GE11 | How the level binds the stations | (a) a station scene is the device: its look and collision (layer 1), a use-spot `Marker3D` in its `spawn_<tag>` group on the floor in front of the device, clear of its collision, and named nodes the client drives (the switch's on/off part; the generator's button and its four bars); the client finds each placed station's scene by the use spot's position, the nearest in 3D within a tolerance (`StationPlaced` carries the snapped floor's y; House stacks four levels, so x and z alone could match a scene on another floor), and drives those nodes; (b) the client builds the dynamic parts itself at the station's position; (c) `StationPlaced` gains a facing | (b) `StationPlaced` has no orientation: a panel drawn the wrong way round, or apart from the device the level placed. (c) a wire change for every station kind, and the client still duplicates the level's look | (a); no script in `levels/` |
| GE12 | Basement stations and the scenarios' flat world | (a) the four runners (`scenario_runner.gd`, `bots_runner.gd`, `bots_enet.gd`, `perf_run.gd`) snap station markers only on the levels the scenarios play (`tests/fixtures/scenario_levels.gd`), and read every other map's markers where the scene puts them; (b) `FlatWorldQuery` answers a point below its floor with a floor at that point; (c) the Generator's markers are not snapped | `FlatWorldQuery` finds no floor below y = 0 (`_floor_at`), and every station kind's markers are snapped, so the five basement stations (Y -3.2) fail every scenario run once the base mode holds the Generator (§9.7 today forbids only a delivery circle below y = 0). A map no scenario plays needs only its counts there (`LayoutCheck`), and G7 reads House in the host's real world, snapped. (b) a lie that also hides a real mistake on a scenario level. (c) a station kind unlike the others, placed by hand to the floor. Not the first such station: `release/m7` (#651) put `Zone01` (`spawn_zone`) in `levels/house/rooms/generator_hall.tscn` at level -1, and main's base mode lists House (#626), so the same failure comes with the `release/m7` merge into main, before any Generator work | (a), in G3, which (or the M7 track's equivalent fix) must land no later than the `release/m7` merge; coordinated with the M7 track on #651 |

### 6.1 The subtask count setting (#256)
Every task type already reads its own subtasks setting: a property ending in `_setting` that names a whole-number
`SettingSpec` of the mode, one lobby control each (Delivery's `packages`, the zone task's; the Generator's in G5). So
the Generator needs nothing new for it. The shared part, proposed as G0 (optional): `subtasks_setting` moves up into
`TaskType`, required non-empty with a `min_value` of at least 0 (ModeCheck already checks every `*_setting` property names a declared whole-number setting: `core/content/mode_check.gd`), so a new type
cannot forget it, and each type adds only its own bound (the Generator's `switches`). #256's other half, a complex
task's recipe, is its own design.

### 7. Testing
- **Unit tests** (G1, G2; fixtures only, never `content/`, ARCHITECTURE §9.6): `Interact`'s routing (a station kind's
  rule before the role's and the mode's; a knife in hand changes nothing), each refusal and its order (§2.2), a raise
  stopped by a use, the allowlist (downed, dead); the deal (markers, active draw, start states, ids, N = 0, a short map
  logging a match error as Delivery's does); every row of §4; the demands and the fit check; GE10's checks; the order
  of events (GE9); `ResetMatch` clearing the state; the wire rows' round trips.
- **The role-swap check** (G2): the same seed and commands with two players' forced roles swapped emit identical
  `SwitchChanged`, `ButtonPressed`, progress, `TaskState` and `TaskProgress` streams (as the zone task's). Planted
  once (the button refuses dissidents), it fails; reverted.
- **The leak test's lists** (G2): the three events join the task events every player receives alike (`LeakCheck`,
  `ScenarioInvariants`). Both check only events a run emits, so the lists alone prove nothing until a scenario plays
  the Generator.
- **Scenarios that play the Generator** (G8; content, provisional, the engineer approves the scripts): a scenario step
  `StepInteract` (G1) names a station by its kind and index (M7-Z2's `ScenarioTarget.Kind.STATION`) and sends
  `Interact`. On the greybox, whose station scenes stand above y = 0 (G5): the crew switches on every active switch
  and presses the button; a dissident switches one off mid-charge, and someone switches it back on and presses again;
  one bot is knocked down while it charges and one stands far away; the run ends with the charge done and its
  `TaskProgress`. One of them runs in `bots`, the leak test over the real wire.
- **The leak plant** (G8, once a scenario plays the Generator, as the zone task's M7-Z3): `SwitchChanged` declared to
  the actor only fails both `LeakCheck` and `ScenarioInvariants` in that scenario; reverted, and recorded in the PR
  (ARCHITECTURE §4.6.4.1).
- **The chaos bots** (ARCHITECTURE §4.6.5.3). G1, where no phase of the base mode accepts `Interact` yet: its row in
  `ChaosOracle.ACCEPTS` (`not_accepted` everywhere until G5), a `ChaosFrames` malformed shape for the new C→H kind
  (station 0xFFFF, truncated, trailing bytes). G2: the two new H→C kinds in the wrong-direction list. G8, once the
  base mode deals the Generator (`ChaosScenario` deals it with the defaults): a hostile `Interact` meets real stations
  and gets only its `Rejected`s, each reason in `ChaosHostile._refused` and `ChaosOracle`: `not_accepted` (downed, and
  in the wrong phase), `two_handed`, `out_of_reach`, `unavailable`, `nothing_to_do` (an unknown station), and a burst
  stopped at the bucket; the role-swap class 8 compares the Generator's events.
- **Integration tests on House** (G7; bots do not play House, ARCHITECTURE §9.7): `Match` over `HostWorldQuery` with
  House's level: a player at each use spot uses its station (`AtStation`, `StationInSight` pass); one in the next
  room, within the radius but behind the wall, is refused `blocked`; a full charge from scripted commands; the five
  stations read without errors.
- **The maps** (G5): the spacing test (§1.1, row 23) on every map of the base mode; the content test's fit.
- **The client** (G6): the fold, the panel's bars (pure), the hint over usable stations only, a `shot` preview.
- **Green** (#605): `verify` (lint and check) locally, then CI's full suite on the PR, for each issue of §8.

### 8. The split
Sizes as in M6 and M7: S up to about 400 changed lines, M up to about 900. Base: `main`. Effort: high for `core/`,
`net/` and `tests/harness/`.

| Issue | Labels | Goal | Acceptance | Files | Depends on | Size |
|---|---|---|---|---|---|---|
| G1 | needs-engine, area:core, area:net | `Interact(station)`: the station-use intent, its owner and its parts | GE1 to GE4; `Intents.INTERACT` (`station`) in `Intents.ALL` and `Intents.PLAYER_ACTIONS` (`core/match/intents.gd`), so the client sends the reliable claim twin right before it (#429, §7.1.15: else an honest player who just walked up is refused `out_of_reach` after a lost claim) and a dead host's `Interact` under HOST reaches no rule (§3.1), with a client test that `MoveClaimReliable` goes out right before `Interact`, a match test for the dead host, and §3.1's sentence updated; its rows in §4.1 and §4.3 and a protocol bump; `StationKind.actions` routed first for an intent naming a station, with ModeCheck's handler, trigger and placement checks (GE2); `AtStation`, `StationInSight`, `StationUsable`, `UseStation`; `TaskType.use_problem` and `use_station` (defaults: `unavailable`, nothing); `StepInteract`, a scenario step naming a station by kind and index (`ScenarioTarget.Kind.STATION`), in both runners, with a `scenario_runner_test` case on a fixture mode; §7's unit tests and G1's chaos rows (the allowlist row, the malformed frames); ARCHITECTURE §4.1, §9.2's owner table, §9.3, §9.4.1, §9.4.2, §9.8 and §10 | `core/match/intents.gd`, `core/match/match.gd` (`_find_action`), `core/content/station_kind.gd`, `core/content/task_type.gd`, `core/content/mode_check.gd`, `core/tasks/` (the four parts), `core/content/scenario/` (`StepInteract`), `net/messages/`, `core/match/phases/join_rules.gd` (the version), `tests/harness/` (the runners, the chaos bots), `tests/unit/`, `tests/scenarios/`, `docs/ARCHITECTURE.md` (and §9.7's steps) | `release/m7` in main (`StationState.contains`, ZE3) | M |
| G2 | needs-engine, area:core, area:net | The Generator task type and its events | §2's rules with the recommendations taken (GD2, GD3, GD5); GE5 to GE10; `SwitchChanged` and `ButtonPressed` with their wire rows; the progress event (GE7); §7's unit tests, the role-swap check, G2's chaos row (the wrong-direction kinds) and the three events in the leak test's lists (the leak plant waits for G8's scenario); ARCHITECTURE: the Generator's entry beside Delivery's (§9.5), §4.2, §4.3.4, §5's task events, §9.4.5's `TaskTicks` row, §3.3's RNG purposes | `core/tasks/generator.gd`, `core/events/`, `net/messages/`, `tests/harness/scenario_invariants.gd`, `tests/harness/bots/leak_check.gd`, `tests/unit/tasks/`, `tests/fixtures/tasks/`, `docs/ARCHITECTURE.md` | G1; the engineer's GD2, GD3, GD5 (each revertible, so G2 may start on the recommendations) | M |
| G3 | needs-engine, area:tooling | The runners snap station markers only on the scenario levels | GE12 (a): the four runners read the maps no scenario plays without the snap; a test that a fixture map with a station marker below y = 0 reads without an error in a runner; §9.7's sentence on circles below y = 0 updated | `tests/harness/scenario_runner.gd`, `tests/harness/bots/`, `tests/harness/perf/`, `server/levels/marker_reader.gd` (a parameter, if needed), `tests/scenarios/`, `tests/unit/content/content_modes_test.gd` (it reads every map through the fake, §9.7), `docs/ARCHITECTURE.md` (§9.7) | none; before G5, and no later than the `release/m7` merge into main (its basement `Zone01` on House needs the same fix); superseded if the M7 track's merge brings an equivalent fix | S |
| G4 | area:level | The station scenes, in place of the House markers | `levels/stations/switch.tscn` and `generator.tscn` by GE11: greybox look with `levels/kit/` materials, collision on layer 1, the use-spot `Marker3D` in `spawn_switch` or `spawn_generator` (the tags provisional, "not a decision") on the floor in front, the named nodes the client drives; instanced in storage, the boiler room, the pump room, the switch room and the generator hall in place of `SwitchA` to `SwitchD` and `Generator`, at house-map §6's points; `levels/CLAUDE.md`'s spawn points gain both tags and the use-spot convention; a `shot` of each room; provisional, named in the PR for the engineer's approval | `levels/stations/`, `levels/house/rooms/` (five rooms), `levels/CLAUDE.md` | none (the markers carry no group until the base mode holds the type, G5) | S |
| G5 | area:content | The Generator in the base mode | `content/tasks/generator.tres` with the engineer's name "Charge the generator" and description "Switch on every active switch, then press the generator's button to charge it." (GD1, answered), `seconds` 60, `switches` 4, both station kinds with their `Interact` rule (`HandNotTwoHanded`, `AtStation`, `StationInSight`, `StationUsable`, then `UseStation`) and GD6's numbers; the base mode: the type, its subtasks setting (2 to 4, default 3, GD1's label), `tasks` per GD7, Round accepting `Interact` from the living; G4's `levels/stations/generator.tscn` and `switch.tscn` instanced on the greybox at placeholder points (GD7 (a); bare markers would leave the client no device to draw, GE11), above y = 0, switches more than 12 m apart (derived, the engineer to confirm, §1.1 row 23); the spacing test; the MVP's scenarios ban the Generator too (M7-Z2's bans) and keep dealing Delivery alone; every test that loads the base mode still passes, each changed expectation named in the PR; provisional files named for the engineer's approval | `content/tasks/`, `content/modes/base_mode.tres`, `levels/greybox/greybox.tscn`, `content/scenarios/`, `tests/unit/content/`, `tests/integration/`, `tests/scenarios/`, `tests/harness/chaos/`, `tests/harness/perf/` (GE7), `docs/ARCHITECTURE.md` (§9.5, §9.6) | G2, G3, G4; M7-Z3 in main; the engineer's GD6, GD7 (GD1's label may be a placeholder) | M |
| G6 | area:client | The client's view | the E hint and `Interact` over a usable station (`TargetChoice` gains stations; the hint a margin short of the cylinder, as the pick-up's, #319; none over a fixed switch or a charged generator; when E could pick up, raise or use a station, the target nearest along the crosshair's ray wins, a station counting only when the ray hits its device or its use spot, so a package lying inside a switch's cylinder is still picked up when aimed at, with a unit test for an item inside a station's cylinder); the switch's on/off part, the button's animation, the panel's bars (GD4) glowing blue when all are lit (an emissive `StandardMaterial3D`: `emission_enabled`, `emission`), all drawn in the world, depth-tested, on no screen; the driven nodes (the switch's on/off part, the button's moving part, the four bars and the glow) in `SightHider`'s group, as `ZoneViews` puts its fill (render checklist item 3: a downed player's arm camera sees past short walls), with a test that a downed own player with no line of sight to a switch does not show its state; the sounds (GD10) through `SoundChooser` and `WorldSounds`, within 12 m (`AudioStreamPlayer3D.max_distance`) and muffled behind the level (M5-7); the task screen's Generator row with the charge percentage (GD8), extrapolated from the progress event of the one station whose kind is a Generator's `generator` kind in the client's own mode (as `ZoneViews.zone_task` filters zones), never a zone's, which would tell every player through walls that someone stands in that zone (ZD11, render checklist items 4 and 5), with a test that a zone's `ZoneProgress` leaves the task screen unchanged; `CircleViews` draws a cylinder only for a station whose kind is a Delivery's circle in the client's own mode (today it draws every kind that is not a zone, the fallback size for an unknown one, so each switch and the generator would get a delivery cylinder), with a unit test that a Generator station gets none; the M4 render checklist, the PR routed to `netcode-security-reviewer` too; `shot` previews; ARCHITECTURE §4.7 | `client/net/client_model.gd`, `client/world/`, `client/ui/task_screen.gd`, `tests/unit/client/`, `tests/integration/client/`, `docs/ARCHITECTURE.md` | G2, G4; G5 for a playtest; the engineer's GD4, GD8, GD10 | M |
| G7 | needs-engine, area:core | Integration tests: the Generator on House | §7's House tests in the host's real world | `tests/integration/levels/`, `docs/ARCHITECTURE.md` (§9.7's House line) | G2, G4, G5 | S |
| G8 | area:content, area:tooling | Scenarios that play the Generator, its leak plant | §7's Generator scenarios on the greybox (provisional, the engineer approves the scripts), one of them in `bots`; the leak plant in that scenario, planted once and reverted, recorded in the PR; the chaos bots against dealt stations (§7); the scenario runner's and `bots`' tests still pass | `content/scenarios/`, `tests/scenarios/`, `tests/harness/chaos/`, `docs/ARCHITECTURE.md` (§9.7, §4.6.5.3) | G1, G2, G5 | S |
| G0 | needs-engine, area:core | Optional: `subtasks_setting` in `TaskType` (#256's shared part, §6.1) | the property in `TaskType`, required non-empty with `min_value` at least 0 (the type check exists already); Delivery, the zone task and the Generator use it; no data change | `core/content/task_type.gd`, `core/tasks/`, `core/content/mode_check.gd`, `tests/unit/` | `release/m7` in main | S |

### 9. Needs the engineer
One batched question: GD1's setting label and GD2 to GD11 (§5), each with its options and a recommendation (GD1's
name and description he answered on 2026-10-10). "Every recommendation" is a full answer to GD2 to GD11; GD1's label
and GD6's numbers are his to give, or to approve as placeholders marked "not a decision" in G5's PR. G1, G3 and G4 need none of them; G2 starts on GD2, GD3 and GD5's recommendations, each
revertible in its code.

## Alternatives
- **`Use(facing)` for stations** (GE1 (b)): the hand item decides what `Use` does, so a knife holder would stab.
- **One `Interact` rule in the mode** (GE2 (b)): one rule per trigger per owner leaves the next station no conditions
  of its own.
- **A reach setting beside the station's cylinder** (GE3 (b)): two numbers for one distance.
- **Host-side filtering of the switch states by place** (GE6 (b)): a new audience kind and per-peer state by distance,
  which §10 keeps for when a human asks; the public positions would still tell who stood at a switch.
- **A new progress event, or a rename** (GE7 (b), (c)): `ZoneProgress` carries exactly the charge's fields.
- **No window on the Generator's progress event** (GE8 (a)): the intent bucket alone lets one peer's button spam send
  two reliable events a press to every player, at the rate ZE4 rejected.
- **The progress following the switches** (GD3 (b)): it shows the battery to everyone through the HUD.
- **A flat-world floor below y = 0** (GE12 (b)): a lie in the fake that would hide a real mistake on a scenario level.

## Consequences
- ARCHITECTURE §9.3's interactable row, §9.8's `Interact` paragraph and §10's `Interact` row point here: the
  Generator is the first mechanic that needs `Interact`. GDD §8 gains the Generator's section with its open
  questions; house-map §10 drops the generator ideas the engineer has now decided.
- When G1 and G2 land, ARCHITECTURE gains `Interact` in §4.1 and §4.3, a station kind as a rule owner in §9.2, the
  four parts in §9.4, the Generator's entry in §9.5 and its events in §4.2, §4.3.4 and §5, with their `Built in`
  lines.
- The protocol version goes up in G1 and in G2; kind numbers and versions are taken when each lands, never from here.
- `Interact` is there for the House's next chains: the grill, the printer and the lift are stations with a use, each a
  station kind with its rule and its task type's `use_station`.
- With GD7 (a) every map of the base mode needs a generator scene and four switch scenes (GE11); House has them once G4
  lands, the greybox in G5. On House the generator stands 12.5 m from switch D (house-map §6's points, a straight
  line): its button and its charge are just out of D's 12 m earshot.
