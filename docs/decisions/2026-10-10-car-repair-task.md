# The car repair task (#688): its engine parts, a hold on a station, the drop, and the split

- **Status:** Proposed on 2026-10-10. Nothing here is built. The rules are the engineer's: #688's "Decided" list
  (chat, 2026-10-10) and his answers to RD1 to RD16
  ([PR #709, comment 6095445261](https://github.com/xperiaroco2/prime-game/pull/709#issuecomment-6095445261), chat
  with the game-design manager session on the morning of 2026-10-10): every recommendation stands except RD1: a
  crouch for every player, #727; RD2: placeholders the agents pick; RD3: a picture on the garage wall; RD7: the
  knockdown reworked, #728; and RD12: words the agents draft. RD4 he confirmed as (a). The RD items are game rules
  and taste (the [trust ADR](2026-10-04-trust-based-autonomy-gated-merge-into-main.md)'s tier (c)); what his answers
  leave open is in §9, each with options and a recommendation, and the design proceeds with the recommendation where
  it can be reverted. The RE items are technical, the game-design manager session's to decide and report (tier (a)):
  decided here, each revertible in its issue.
- **Date:** 2026-10-10
- **Deciders:** the engineer (the rules; RD1 to RD16, answered on 2026-10-10 in PR #709's comment 6095445261; what
  is still open, §9); the game-design manager session of #676 (RE1 to RE16). Designed by the agent of #688,
  on the engineer's word (#688; the track's kickoff on #593, comment 6088751685).
- **Prerequisites, designed elsewhere:** the crouch, #727 (needs-design: hold Ctrl to crouch, Shift while crouched
  moves a bit faster; under the car the player works crouched, RD1); the knockdown reworked, #728 (needs-design, his
  answer A in comment 6095620279: today's knockdown, but the knocked-down player cannot move or talk and falls as a
  ragdoll; RD7). This ADR depends on both and designs neither.
- **Builds on:** [the Generator ADR](2026-10-10-generator-task.md) (#679, PR #695, proposed: `Interact(station)`, a
  station kind owning its rules, `AtStation`, `StationInSight`, `StationUsable`, `UseStation`,
  `TaskType.use_problem`, busy hands, the per-task-type subtask count, station scenes as devices, GE11; its issues
  G0 to G8), [the cooking ADR](2026-10-10-cooking-task.md) (#682, proposed: `GiveItem`, `HandsHaveRoom`, display
  station kinds, the reason `wrong_item`, the move that locks an item at a station; its issues C1 and C2),
  [the photo ADR](2026-10-10-photo-task.md) (#687, proposed: the same item source as its PE7, two station markers for
  a pose as its PE3 (a)),
  [content API v0](2026-09-29-content-api-v0.md), [MVP rules](2026-09-29-mvp-rules.md) (Tasks, #79),
  [vision revision 1](2026-10-01-vision-revision-1.md) (V4's "living", knockdown, death and respawn, two hands; the
  amendment of 2026-10-08: rare one-shot kills), [the M4 client design](2026-10-01-m4-first-person-client.md) (its
  render checklist, items 3, 4, 5 and 10; E33's hearing range), [the zone task ADR](2026-10-09-m7-zone-task.md)
  (`StationState.contains`, ZE3's mode checks, ZE10's claim age, M7-Z2's scenario bans),
  [level piece conventions](2026-10-09-level-piece-conventions.md), [MVP content built by the
  engineer](2026-09-29-mvp-content-built-by-the-engineer.md), [the House map](../design/house-map.md) (§2 decisions 5,
  9 and 10; the stations of §6), [tests on CI](2026-10-09-tests-on-ci-local-lint-and-check.md) (#605), the engineer's
  DD4 on Delivery by meaning (#683;
  [PR #713, comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718): no
  marker is drawn through walls any more), and his answer A on where the House chains' engine code goes
  ([#676, comment 6095620770](https://github.com/xperiaroco2/prime-game/issues/676#issuecomment-6095620770): on
  `release/m7`, §8)
- **Numbering:** RD and RE are this ADR's own; the issues are R1 to R9 (§8), which the manager opens from the PR's
  handoff. G-numbers are the Generator ADR's issues, C-numbers the cooking ADR's.

## Context
The engineer's rules (#688, "Decided"), in short: the car repair is a task type like the others, and the host's
per-task-type subtask count applies. The car stays up only while someone holds E at the lift panel; let go, or be
knocked down, and the car drops and kills at once whoever is under it (House decision 9), who respawns as usual
(decision 10). The car shows which part it needs, one of several kinds; the part is taken from the parts shelf in
storage and carried to the garage. Under the car, with the part in hand, the player holds E for some seconds to fit
it, crouched (RD1: every player gets a crouch, #727). The lift panel has no view of who is under the car: the one
holding the lift relies on trust and voice. The Generator's shared rules hold here too (the standing decisions of
#676): a dissident plays by the same rules, busy hands, the host's per-task subtask count; tasks are shared and only
living players do subtasks (#79, V4).

It is the first mechanic with a **hold on a fixed station** (the lift: E held for as long as the car must stay up), the
first **timed use of a station** (the fit: E held for some seconds), and the game's first **instant kill** of a
living player (a death today always comes from a knockdown). The Generator brings the station half of `Interact`;
cooking brings the item source; the raise (M4-4) brings the channel, the primitive for "hold E".

What already holds (ARCHITECTURE §9, §5, §7.1), checked live on main:
- **Channels** (`core/channel/`): a `ChannelEffect` starts a `Channel` for its actor on the intent's `target`, a
  **player** (`Channels.target_of` reads the intent's `target` field; `Channel.target` is an `int`).
  `ChannelTicks` checks its rule's conditions again every tick; any applied action of the actor stops it
  (`RuleRunner`), and so do a hit (`LifeRules.damage` calls `Channels.interrupt`), a knockdown, a death and a leave
  (`Channels.interrupt_involving`, which stops every channel whose actor **or target** is that peer) and every phase
  transition (`Channels.stop_all`). A channel completes after `seconds` (0.05 to 600, `ChannelEffect.check`).
  `ChannelFree` allows one channel per actor and one per target. `StopRaise` has no fields; its base-mode rule is
  `Channeling` alone, so applied it stops whatever channel its sender runs.
- **Life** (`core/life/life_rules.gd`): `die` refuses a player who is not downed (`die: player %d is not downed`);
  the only way to die is through a knockdown. `damage` does nothing to an invulnerable player. A death: channels
  stopped, the body on the floor below the feet, `Died` (everyone, no killer), `player_died`, then both slots drop at
  the body; `LifeTicks`' `Respawn` brings the dead back after `respawn_s`. "Downed" is the code's name for a
  knocked-down player; #728 reworks the knockdown (the engineer's answer A: the same state, raised by another player
  or dying after a while, but the knocked-down player cannot move or talk and falls as a ragdoll, no animation): the
  "downed" of this ADR is that knocked-down state, by its name in the code.
- **No crouch yet.** Nothing in `core/`, `client/`, `server/`, `levels/` or `content/` mentions a crouch (searched on
  2026-10-10). `PlayerRules` holds one capsule (the base mode: 1.8 m high, radius 0.4 m) and one eye height (1.6 m),
  which `InSight`, `TargetInSight` and `Strike` read for every living player. The engineer decided a crouch for every
  player (RD1); its design is #727's, a prerequisite of R5 and R7 (§8).
- **The host's world** (§4.5.9) holds the level's layer-1 static bodies only; an `AnimatableBody3D` there "never
  moves on the host", bodies on other layers are left out, and the host does not check movement through walls
  (§7.1.9). The client's player collides with layer 1 only (`client/player/player_controller.gd`).
- **Markers** carry a position only (`core/content/level_layout.gd`); `CarLift`, `LiftPanel` (in
  `levels/house/rooms/garage.tscn`) and `PartsShelf` (in `levels/house/rooms/storage.tscn`) are plain `Marker3D`s
  under `Stations`, with no group.
- **Hidden by sight is a client rule** (the M4 render checklist): every living or downed avatar reaches every player
  in the snapshots (§5), so who stands under the car is on every client's wire, and an honest client shows it only
  by sight. Hiding positions on the host is "only if a human asks" (§10).

## Decision

### 1. The mapping (`new-mechanic` step 3)

#### 1.1 Each rule to its engine part

| # | What #688 needs | Engine part | Exists? |
|---|---|---|---|
| 1 | Car repair is a task type, like the others | `CarRepair extends TaskType` (`core/tasks/car_repair.gd`); `has_tick()` false (RE11) | missing: R3 |
| 2 | The host's per-task-type subtask count | the type's own subtasks setting, a whole-number `SettingSpec` the lobby shows; one subtask is one part fitted (RD4 (a)) | exists as a pattern (Delivery's `packages`); the setting R6; the shared property G0 (optional) |
| 3 | Where the lift, the parts and the fits stand | `CarRepair.State extends TaskState` (RE11): the station ids, the needed parts drawn at the deal, how many are fitted, the tick the hold started | missing: R3 |
| 4 | The car, the lift panel, the parts shelf, the picture of the needed part | station kinds of the type: `car`, `lift_panel`, and one bin kind per part kind (`part_bin_<n>`), each with its spawn tag, radius, height and `Interact` rule (the Generator's GE2); and `part_picture`, a display kind on the garage wall (cooking's CE6 display flag: no rule, nothing to aim at; RD3); ids and tags provisional, "not a decision" (RE13) | the class exists (`core/content/station_kind.gd`); its `actions` G1; the display flag C1; the data R6 |
| 5 | The car stays up only while someone holds E at the lift panel | `Interact(lift_panel)` starts an **endless** `HoldStation` channel on the panel (RE1, RE3); its rule: `HandNotTwoHanded`, `AtStation`, `StationInSight`, `ChannelFree`, `StationUsable`, then `HoldStation` (endless); `CarRepair.hold_started` emits `LiftChanged(station, up, tick)` | `Interact` and the station conditions G1; `HoldStation`, endless channels and channels on stations R1; the type's hooks R3 |
| 6 | Let go: the car drops | E released sends `StopRaise` (RE5), whose rule (`Channeling`) stops the hold; `HoldStation.stopped` calls `CarRepair.hold_stopped`: the drop | `StopRaise` exists (`core/match/intents.gd`, its rule in `content/modes/base_mode.tres`); the drop R3 |
| 7 | Be knocked down: the car drops | `LifeRules.knock_down` stops every channel its player runs (`Channels.interrupt_involving`) before it downs it | exists (`core/life/life_rules.gd`) |
| 8 | What else stops the hold | another applied action of the holder (`RuleRunner`, §9.2), a death or a leave (`LifeRules`), walking out of the panel's cylinder or out of its sight (the conditions every tick, `ChannelTicks`); a hit only if RD10 says so (`HoldStation.hit_stops`); the phase's end drops the car without a kill (RE4) | the stops exist (`core/channel/channels.gd`); `hit_stops` and the phase end R1 |
| 9 | The dropped car kills at once whoever is under it | `CarRepair.hold_stopped`: every player whose feet (last accepted position) lie inside the car's footprint box (RE7, RD6), living (and downed, RD7), in peer-id order, `LifeRules.kill` (RE6), decided by the host from its own state | missing: R2 (`kill`), R3 (the box and the drop) |
| 10 | The player respawns as usual | `kill` sets the respawn deadline as `die` does; `LifeTicks`' `Respawn` brings the player back | exists (`core/life/life_ticks.gd`, `core/life/respawn.gd`) |
| 11 | Nobody is told who let go, unless they saw it (the brief of #676's manager; no event names a killer, §4.2) | `LiftChanged` names no player; `Died` names no killer and no cause (§4.2) | `Died` exists; `LiftChanged` R3 |
| 12 | The lift panel has no view of who is under the car | the level: static walls (layer 1) between the panel's use spot and the space under the car, tested on the host's world (R8); no screen names who is under the car (R7); hidden by sight (RD15) | missing: R5 (the walls), R8 (the test), R7 (the view) |
| 13 | The car shows which part it needs: a picture, for now on the garage wall (RD3, the engineer's) | `PartNeeded(station, kind)` (everyone), naming the picture's station: sent at the deal and after each fit; the client draws the part's picture there, in the world and depth-tested, never through walls (DD4) | missing: R3 (the event), R5 (the picture's scene), R7 (the drawing) |
| 14 | One of several kinds | `parts`, a list of item kinds in the type's data, one `ItemKind` per part kind (RE13) | `ItemKind` exists (`core/content/item_kind.gd`); the list R3; the kinds R6 |
| 15 | Dealt by the seeded RNG | the deal draws the N needed parts from the RNG purpose `car_parts` (§3.3), never the same kind twice in a row (RD3) | `RngStreams` exists; the draw R3 |
| 16 | Taken from the parts shelf in storage | one bin station per part kind on the shelf; `Interact(bin)`: `HandNotTwoHanded`, `AtStation`, `StationInSight`, `HandsHaveRoom`, the cost `Cooldown` (key `car_part_take`, provisional, "not a decision"; cooking's CE17), then `GiveItem(that part)` (RE13, RD9) | `GiveItem`, `HandsHaveRoom` cooking's C1; `Cooldown` exists (`core/combat/cooldown.gd`); the scene R5; the data R6 |
| 17 | Carried to the garage | the part in a hand (`ItemKind.hands`, RD9) | exists (M4-5) |
| 18 | Fitting: under the car, the part in hand, E held for some seconds | `Interact(car)` starts a timed `HoldStation` (the fit's seconds); its rule: `HandNotTwoHanded`, `AtStation`, `StationInSight`, `ChannelFree`, `StationUsable` (the car fully up, the needed part in hand), then `HoldStation`; completed: the part locked at the car (cooking's C2 move), `PartFitted(station, item)`, `Tasks.subtask_done`, the next `PartNeeded` (RE12) | `Interact` G1; `HoldStation` R1; the fit R4; the lock move C2 |
| 19 | Under the car the player works crouched (RD1, the engineer's) | a crouch for every player (#727, designed there: hold Ctrl, Shift while crouched a bit faster); the raised car's underside lower than a standing player and higher than a crouched one, so only a crouched player gets under it and out (RD1's read-back, (a) recommended, §9); the host checks no crouch for the fit (it has no car, RE8) | missing: #727 (the crouch); R5 (the car's height), R7 (the fitter at work) |
| 20 | Players crouch under the raised car, never walk into the lowered one | the car's body: an `AnimatableBody3D` on a client-only collision layer, driven by each client from `LiftChanged` (RE8) | missing: R5 (the scene, on layer 4), R7 (the drive, the layer's name, the player's mask) |
| 21 | Busy hands | `HandNotTwoHanded` in every rule of the type (#679's shared rule) | exists (`core/items/hand_not_two_handed.gd`) |
| 22 | A dissident plays by the same rules | no condition reads a role, so no public event tells one (§9.2); a role-swap test | by design; the tests R3, R4 |
| 23 | The knocked-out and the dead do nothing | Round accepts `Interact` and `StopRaise` from the living only (the phase's allowlist) | exists (`AcceptSpec`); the data G5, R6 |
| 24 | The stations in the garage and in storage | `levels/stations/car.tscn`, `lift_panel.tscn`, `parts_shelf.tscn` and `part_picture.tscn` (GE11 (a)), instanced in place of the markers, the picture on a garage wall | the markers exist (none yet for the picture); the scenes R5 |
| 25 | Tested without bots on House (ARCHITECTURE §9.7) | unit tests from fixtures (R1 to R4); integration tests on House in the host's real world (R8), a drop that kills only the player under the car among them; scenarios on the greybox (R9) | missing |

#### 1.2 Beside the raise and the Generator

| | Raise (M4-4) | Generator (#679) | Car repair |
|---|---|---|---|
| E | held over a downed player | pressed at a station | held at the lift panel (no end) and at the car (the fit's seconds); pressed at a bin |
| The channel's subject | a player (`Channel.target`) | no channel: a use is instant | a station (`Channel.station`, RE2) |
| What stops it | E released, another action, a hit, the raiser downed or leaving, the target giving up or leaving, out of reach or sight, the phase's end | nothing to stop | the same for the fit; for the hold the same without a hit (RD10 (c)), and the phase's end drops the car without a kill (RE4) |
| Completion | `Revived` | the use itself | the fit: `PartFitted`; the hold never completes (RE3) |
| Who counts | any living player | any living player | any living player; the drop kills every player under the car (RD7) |
| Progress on screen | none | the charge's percentage | the task screen's parts fitted out of needed (`TaskState`, as Delivery's) |
| State | `Channels` | the task state | the task state for the lift, the parts and the fits (RE11); `Channels` for who holds |

### 2. The rules as the engine runs them (with the engineer's answers)
1. **The deal** (when `DealTasks` draws car repair): a station on every marker, as the Generator's §2.1 (each marker
   is a device scene, GE11, so the demands are exact counts, RE14): the car on the `car` marker, the lift panel on the
   `lift_panel` marker, one bin per part kind on its own tag's marker, the picture on the `part_picture` marker (a
   garage wall, RD3). The `car_end` marker (RE7) gives the car's long axis; it is no station. N is the subtasks
   setting: the deal draws the N needed parts in order from `parts` with the purpose `car_parts`, each drawn uniformly
   from the kinds other than the one before it (RD3 (y); with one kind, that kind every time). Then `StationPlaced`
   per station in id order (the car, the panel, the bins in `parts` order, the picture), then
   `PartNeeded(picture, first part)`. With N = 0 the task has no subtasks and is done (#79), and `PartNeeded` carries
   no kind.
2. **The hold** is `Interact(lift_panel)` from a living player in Round. In this order it is refused `two_handed`, `out_of_reach`
   (the feet outside the panel's cylinder), `blocked` (no line of sight from the eye to just above the panel's use
   spot), `busy` (someone holds already) or `unavailable` (the task is done, RD11 (a): a new hold only; a running one
   is never refused on its re-check, where `MatchContext.channel` is set). Applied: an endless channel of the holder on the panel; the car starts rising
   (`LiftChanged(panel, true, tick)`), fully up `rise_seconds` later (RD5 (b)). Every tick the conditions run again;
   the first that fails stops the hold.
3. **The drop** is the hold stopping for any reason but the phase's end: E released (`StopRaise`), another applied
   action of the holder, the holder knocked down, dying or leaving, the holder walking out of the cylinder or out of
   sight; never a hit alone (RD10 (c)). In that command or tick: `LiftChanged(panel, false, tick)`; then every player
   whose feet lie inside the footprint box (RE7) and who is living or knocked down (RD7) is killed at once
   (`LifeRules.kill`), in peer-id order. Players beside the car, on it, or under it while it was not raised are
   judged only by where their feet are, the same for all.
4. **The fit** is `Interact(car)`: refused `two_handed`, `out_of_reach` (the feet outside the car's cylinder, which lies
   inside the footprint box, RE14), `blocked`, `busy` (someone fits already), then by the type: `unavailable` (the
   car not fully up, or the task done), `empty_hand` (no part in the hand), `wrong_item` (another part, or any other
   item: RD8 (a)). Applied: a channel of the fit's seconds (`FitChanged(car, fitter, tick)`). Every tick its
   conditions run again: the car must stay up, the part in hand, and the fitter's last accepted claim at most
   `MovementRule.PUSH_TICKS` old (RE2, ZE10). A stop (`FitChanged(car, 0, tick)`) loses the
   fit's progress (RD10 (i)). Completed: the part leaves the hand, locked at the car (cooking's C2 move, its
   `ItemState` locked as a delivered package); `PartFitted(car, item)`; that subtask done (`Tasks.subtask_done`:
   `TaskState`, `TaskProgress`, `subtask_done`); then `PartNeeded(picture, next)`, or no kind when the last is fitted
   and the task is done. The car stays up while the hold runs: the fitter must get out before the holder lets go. The
   fitter works crouched (RD1): the raised car is too low to stand under, so an honest player crouches to get under
   it (#727's crouch) and leaves crouched, slower than walking; the host checks no crouch (RD1's read-back, §9).
5. **A bin** is `Interact(part_bin_<n>)`: refused `two_handed`, `out_of_reach`, `blocked`, `hands_full` or `too_soon`
   (the same player took from a bin less than RD2's take seconds ago, cooking's CE17); applied,
   `GiveItem` puts a new part of that bin's kind into the hand (cooking's CE2: `ItemSpawned`, then `ItemPickedUp`),
   without limit apart from `GiveItem`'s technical cap (cooking's CE3 and CD6). A bin never refuses for the task's
   state: parts may be taken before, between and after fits.
6. **Nothing else** moves the car or resets the parts: the task state stays in `MatchState` until `ResetMatch`. A
   transition stops the hold (`Channels.stop_all`) with the phase's end marked, so the car goes down without a kill
   (RE4).

### 3. What everyone sees

| What | Who learns it | How |
|---|---|---|
| Where the car, the panel, the bins and the picture stand | everyone | `StationPlaced` in the deal (and the level's own scenes) |
| The needed part | every client receives it; an honest one shows it only as a picture on the garage wall, in the world, depth-tested, never through walls (RD3, RD15, DD4) | `PartNeeded` |
| The car going up or down | every client receives it; seen in the world, heard within 12 m | `LiftChanged(station, up, tick)`; the client derives the height from the tick and its own copy of `rise_seconds` |
| Who holds the lift | nobody, through an event | no event names the holder; the snapshots show who stands at the panel, as for a switch or a circle |
| Who let go | nobody, through an event | `LiftChanged` names nobody; a knockdown's own `KnockedDown` names the downed player as it always does, never that it held the lift |
| Who is under the car | nobody, through a screen; by sight, where the level allows it | the snapshots (every avatar, §5); the panel's use spot has no line of sight into the space under the car (R5, R8) |
| Who fits | every client receives it (to draw the crouched fitter at work); shown on the avatar in the world only, and no sound plays while a fit runs (RD14 (a)), so the holder does not hear it through the wall | `FitChanged(station, fitter, tick)`; the crouch itself from #727's movement state |
| Who died under the car | everyone | `Died(peer, position)` per victim, as every death; no cause, no killer |
| Parts fitted out of needed | everyone, on the task screen too | `TaskState` and `TaskProgress` (generic) |

"No view of who is under the car" and "nobody is told who let go" hold for every honest client. A modified client
could show every avatar's position and so who is under the car, as it can show a hidden package today, and
`FitChanged` tells it outright that a fit runs, by whom; the engineer accepted that limit (RD15 (a)).

### 4. Edge cases

| What happens | What the engine does | Why |
|---|---|---|
| The holder is knocked down | `knock_down` stops its channels first: `LiftChanged(false)`, the victims' `Died`, then the holder's `KnockedDown` | `LifeRules.knock_down` calls `Channels.interrupt_involving` before it downs the player |
| One swing hits the holder (the lower peer id) and a player in the footprint box, and knocks the holder down | the knockdown stops the hold, the drop kills the second target; when `Strike` reaches it, it is no longer alive and is skipped: one `Died`, no `Damaged`, no rule error | `Strike` damages its targets in peer-id order after picking them all; without the skip, `LifeRules.damage` on a dead player logs a rule error, which fails the tests and bots that require none (R2) |
| The holder leaves (or loses its connection) | the drop, its kills, then `PlayerLeft` (RD16 (a)) | `LifeRules.leave` stops the player's channels first |
| The holder walks out of the panel's cylinder | the next tick's re-check fails `AtStation`: the drop | "only while someone holds E at the lift panel" |
| The holder swings, swaps, picks up or uses another station | the action applies, which stops the hold first: the drop | §9.2: an applied action stops its actor's channel |
| The holder presses E at the panel again | `busy` (its own hold is running); nothing stops | a refused intent stops nothing (§9.2) |
| The holder is hit and not knocked down | RD10 (c): the hold goes on (`hit_stops` false); the fit of a hit fitter stops | the engineer's "let go, or be knocked down" |
| Round ends (time, every task done, no crew present) while the car is up | the transition stops the hold with the phase's end marked: `LiftChanged(false)`, no kill | RD16 (x), RE4: nobody dies after the round's outcome |
| The last part is fitted | `PartFitted`, the subtask, the task done; the hold goes on, and its drop kills as always; no new hold (RD11 (a)) | the car stays a car until it is lowered |
| The fit completes and the hold stops in the same tick | a stop in that tick's command step (a `StopRaise`, another applied action of the holder, a knockdown, a leave) drops the car before `ChannelTicks` runs, so the fitter always dies first, whatever the ids; a stop found by `ChannelTicks` itself (the holder out of the cylinder or sight) follows actor-id order: the lower id's channel first, so the fitter fits and then dies, or dies first | determinism (§4.5.3: commands before tick systems); every case is a legal outcome |
| A bystander beside the car | lives: its feet are outside the box | RE7, RD6 |
| A player on the car's roof | cannot happen for an honest client: the car's collision has no top to stand on (RE8); a modified client's claim there floats above the host's floor and is corrected; were its feet above `clearance_m`, it would live | RE7, RE8 |
| A knocked-down player under the car (a fitter knocked down there, who cannot move away, #728) | killed with the others (RD7: "the living and the knocked-down"); its items drop at its body under the car; where its ragdoll lies on a client changes nothing: the host judges the position it holds | "whoever is under it" |
| A player invulnerable (3 s after a revive or a respawn) under the car | killed (RD7; the recommendation's "invulnerable or not" stands): invulnerability spares from strikes and damage, and the drop is neither | `LifeRules.damage` checks it; `kill` does not |
| A standing player walks at the raised car | an honest client's capsule meets the car's body: only a crouched player gets under it (RD1, #727); a modified client standing under it is judged by its feet, as everyone | RE8: the host has no car to check the crouch against |
| A player under the car while nobody holds (a modified client walking through the lowered car) | nothing until a hold and its drop; then killed with the others | the host does not check movement through walls (§7.1.9) |
| Items under the lowered car (a victim's, or one put down towards the car) | they rest on the floor below on the host (it has no car body, RE8); an honest client draws them inside the car's body and offers no pick-up until the car is up; a modified client's `PickUp` of one is accepted (the host's sight passes through the car, RE8) | not "kept for good": anyone can raise the car (`levels/CLAUDE.md`); RD15 |
| A knife swing at a player behind the lowered car | hits, as if the car were not there | the host picks targets over its own sight (`Strike`), which has no car (RE8); RD15 |
| Two players press E at the panel, or at the car, in one tick | commands in their order: the first holds or fits, the second gets `busy` | `ChannelFree` per station (RE2) |
| A player carries a package (two-handed) to the panel or the car | `two_handed` | busy hands |
| A knife holder takes a part | the knife goes to the empty belt, the part into the hand; with the belt full, `hands_full` | cooking's CD5 (a), `HandsHaveRoom` |
| A client spams press and release at the panel | one `LiftChanged` per accepted `Interact` and per stop, bounded by the reliable-intent bucket (§4.5.6), like `Swapped`; each drop runs the box test | RE10 |
| A client spams a bin (a take and a put-down in turn) | its takes are refused `too_soon` but one per RD2's take seconds; at the cap the oldest loose part of that kind comes back (cooking's CD6) | cooking's CE3 and CE17: a take emits two events, which the bucket alone does not bound |
| N = 0 parts | the task is done at the deal; no hold is accepted (RD11 (a)) | #79: a task with no subtasks is done |

### 5. RD items (the engineer's: game rules and taste)
The engineer answered RD1 to RD16 on 2026-10-10
([PR #709, comment 6095445261](https://github.com/xperiaroco2/prime-game/pull/709#issuecomment-6095445261)): every
recommendation stands except RD1, RD2, RD3, RD7 and RD12, which he answered otherwise, and RD4, which he confirmed. The
options stay for the record; the last column is what holds now. Two read-backs of his answers are in §9.

| # | Question | Options | Trade-offs, and the failure each prevents | Decided |
|---|---|---|---|---|
| RD1 | Lying down or crouched (#688 open 1) | (a) a pose only: the raised car's underside stands above a standing player (the capsule is 1.8 m), and while a fit runs every client draws the fitter crouched, from `FitChanged`; no movement change; (b) a crouch for every player (a key: a lower capsule and eye, slower), and a car raised lower than a standing player, so one must crouch to get under; (c) lying: the fit holds the fitter in place under the car (as a raise holds its target), drawn lying | (b) is an engine design of its own: a crouch flag in `MoveClaim`, the movement rule's speed bound, the eye height in every sight check (`InSight`, `TargetInSight`, `Strike`), the snapshots for remote avatars, the controller's headroom check before standing up; none of it exists (Context). (c) a fitter who cannot crawl out while the holder lets go, which turns a trust moment into a trap with no answer. (a) costs one animation and keeps the movement code as it is | **The engineer, close to (b):** a crouch for every player (the art has a crouch animation): hold Ctrl to crouch, Shift while crouched moves a bit faster, its numbers worked out sensibly; under the car the player works crouched. The crouch is a movement mechanic of its own, #727 (needs-design), a prerequisite this ADR names and does not design. How the car asks for the crouch is a read-back (§9): recommended, the raised car too low to stand under |
| RD2 | The numbers (#688 open 2 and 4) | the fit's seconds; the rise's seconds (RD5); the number of part kinds; the subtask count's default and range; the stations' `radius_m` and `height_m`; the footprint's half-width and clearance (RE7); the panel's distance from the car (its point in house-map §6 is a proposal, 8.6 m, beyond the 8 m voice radius from parts of the panel's cylinder); the shortest time between two takes from a bin by one player (the `car_part_take` cooldown, as cooking's CD17) | a long fit keeps the fitter under the car longer, which is the risk; a small car cylinder makes a fit refused `out_of_reach` while lying beside the use spot; with no take cooldown one peer alternating a take and a put-down sends about 30 reliable events a second to every player (cooking's CE17) | **The engineer: the agents pick placeholders to taste**, each "not a decision", his to tune after a playtest: a 5 s fit; a 2 s rise; 3 part kinds; 1 to 3 parts, default 2; the bins' `radius_m` and `height_m` 2 m and 2 m (the Generator's GD6), the panel's 1.5 m and 2 m; the footprint's half-width 1.0 m, its half-length (the use spot to `car_end`) 2.3 m, its `clearance_m` 1.4 m, the raised underside's height, which must lie between #727's crouched height and the standing 1.8 m (#727's placeholder decides the first; R5 keeps the two apart); the car's cylinder 0.9 m and 1.4 m (within the footprint, RE14); a take cooldown of 0.25 s (cooking's CE17, a flood guard); the panel's use spot 5 m from the car's: every point of its 1.5 m cylinder then lies within 6.5 m of the car's use spot, under the voice radius less 1 m (7 m), since the holder "relies on trust and voice", and at least 3.5 m from it, outside the car's cylinder |
| RD3 | How the car shows the needed part, and how it is drawn (#688 open 2) | Where: (a) a sign on the car (its windscreen or bonnet), drawn in the world; (b) a screen on the lift panel; (c) both. What: (i) a picture of the part, the same picture on its bin; (ii) a code (A, B, C) on the car and on the bins. The draw: (x) uniform each time; (y) never the same kind twice in a row | (b) the holder learns the part and the fitter must ask: a second trust link the rules do not name; #688 says "the car shows". (ii) one more thing to decode on top of the walk. (x) a repeat after a fit looks like a fit that failed | **The engineer's own:** (i), a picture, for now on the garage wall, neither on the car nor on the panel: a display station of its own (`part_picture`, §2.1), the same picture on the part's bin. The draw: (y), which his answer did not touch (a read-back, §9). Ideally later something nicer, a player crawling under the car to see what it needs: a future idea, out of this design's scope |
| RD4 | What one subtask is (#688 open 3) | (a) one part fitted: the car needs N parts one after another, N the host's setting; (b) one car repaired, its part count fixed in the data; (c) N parts shown at once, fitted in any order | (b) the host's setting would count cars, and the map has one, so the decided "the host's subtask count applies" would mean nothing. (c) "the car shows which part it needs" is one part | **(a), the engineer's:** one subtask is one part; a repair may need several parts |
| RD5 | Raising and lowering (#688 open 4) | (a) up the tick the hold starts, down the tick it stops; (b) it rises over `rise_seconds` (a fit is refused until it is fully up) and drops at once; (c) it rises and lowers over some seconds, killing only at the bottom, a moment to roll out | (c) is against decision 9's "the dropped car kills at once". (a) a fitter could start a fit in the tick the holder pressed E, before the car could be seen to rise | **(b), the engineer** (the recommendation) |
| RD6 | Who counts as under the car (#688 open 5) | (a) the feet (the capsule's centre on the floor) inside the car's footprint box, from the floor up to the raised underside; (b) any part of the capsule over the footprint (the box grown by the capsule's 0.4 m); (c) only the fit's cylinder | (c) a player lying under the car's front or back end lives while the car lands on them. (b) a bystander leaning on the car's side dies. (a) the body mostly under the car dies, a shoulder under it does not, and the lowered car then pushes that player out on its client (a push the host's world does not see, RE8's accepted quirk) | **(a), the engineer** (the recommendation) |
| RD7 | Whom the drop kills | (a) every living or downed player under it, invulnerable or not; (b) the living only, and not the invulnerable, as a strike | (b) a downed player under the car survives being crushed, and a revived one under it is safe for 3 s. (a) is "whoever is under it"; invulnerability is written against strikes and damage, and the car is neither | **The engineer:** the drop kills the living and the knocked-down, (a), with its "invulnerable or not" standing. There is no "downed/wounded" state any more, only a knockdown: the knocked-down player cannot talk (hears, but cannot speak) and cannot move, and falls as a ragdoll, no animation. That rework is #728 (needs-design; his answer A there, comment 6095620279, keeps today's knockdown otherwise: raised by another player, else dying after a while), a prerequisite this ADR names and does not design |
| RD8 | A wrong part (#688 open 6) | (a) refused at the car (`wrong_item`): the part stays in the hand; (b) fitted and wasted: the fit runs, the part is used up, nothing counts | (b) a fitter who read the display wrong learns it only after a whole fit under the car, and a dissident has a quiet way to waste the team's time. (a) one refusal that tells only what the fitter holds and what the car shows, both public | **(a), the engineer** (the recommendation) |
| RD9 | The parts on the shelf (#688 open 7) | Supply: (a) without limit: each press of E at a bin gives a new part (cooking's `GiveItem`, with its technical cap); (b) one of each kind on the shelf from the round's start; (c) N per kind. Choice: (i) one bin per part kind, the player picks; (ii) the shelf gives the needed part. Hands: (x) one-handed, like cooking's ingredients and the photo's cards; (y) two-handed, like a package | (b) and (c) run out: a dissident who hides the needed kind ends the task for good. (ii) makes the car's display pointless. (y) the carrier cannot draw a knife on the long walk from storage to the garage (V13), as a package carrier; the fit's rule then leaves `HandNotTwoHanded` out, since the part itself takes both hands | **(a), (i) and (x), the engineer** (the recommendation) |
| RD10 | What a hit does to the hold and the fit, and a stopped fit's progress | (a) a hit stops both, as a raise (the channel's default): one stab at the holder drops the car; (b) a hit stops neither; (c) a hit stops the fit, not the hold. And a stopped fit: (i) starts again from zero, as a raise; (ii) keeps its progress | (a) makes the one-shot kill one stab away, against decision 10's "hard to abuse"; #688 names "let go, or be knocked down", not a hit. (b) a fitter stabbed under the car fits on. (ii) one more number in the task state for a few seconds of work | **(c) and (i), the engineer** (the recommendation) |
| RD11 | After the repair | (a) no new hold (`unavailable`); a hold that runs goes on, and its drop kills as always; (b) the lift works as before; (c) the car comes down safely once the task is done | (b) the car stays a trap for the rest of the match, a kill with no task behind it. (c) a dissident at the panel could not punish a fitter who stays under after the last part, and a crewmate holding could lower it at once | **(a), the engineer** (the recommendation) |
| RD12 | The name, the description and the setting's label (#688 open 8) | the task's `display_name`; the task screen's `description`; the lobby label of the part-count setting (`SettingSpec.display_name`). For comparison: "Carry each package to the circle of its colour. Packages take both hands." (Delivery) | the mode check refuses an empty description, so R6 cannot land without one | **The engineer: the agents draft them**, for his approval in the PR; drafts, R6 uses them until he changes them: the name "Repair the car"; the description "Take the part shown on the garage wall from the shelf in storage, then fit it under the car while someone holds the lift."; the setting's label "Parts to fit" |
| RD13 | Where car repair plays, and how many task types a match deals | as the Generator's GD7: (a) in the base mode, with the car, the panel and the shelf instanced on the greybox at placeholder points; (b) on House only, banned on the greybox by hand; and `tasks`: every type every match, or drawn | as there; the car needs a garage-sized space and a wall between the panel and the car on every map | **His GD7 answer, the recommendation:** car repair plays on the House, in the base mode with R5's station scenes; the flat greybox stays the bots' map (§9.7: bots do not play House), with the station scenes above y = 0, so the base mode fits it and R9's scenarios play car repair there; every type every match (GD7 (i)) |
| RD14 | The sounds | Which: the lift's motor while it rises, the drop's crash, a part taken, a part fitted; each within 12 m (E33). And a sound while a fit runs: (a) none, only the part-fitted sound, a fact the task screen already makes public; (b) one whose range is shorter than the gap between the panel's cylinder and the car's cylinder, a level rule R5 keeps and R8 tests beside RE15's sight grid; (c) one within 12 m, the leak accepted | #688 names none; the drop's crash is the one cue a player out of sight gets that someone let go. (c) tells an honest holder at the panel, through the blind wall (world sounds are muffled, not cut, M5-7), exactly when someone is under the car: a dissident waits for it and lets go only when sure of a kill, against "the lift panel has no view of who is under the car". (b) holds only while every map keeps that gap, which RD2's voice constraint makes small (2 m or less) | **The engineer** (the recommendation): the motor, the crash, the taken and fitted sounds, and (a): no running fit sound; placeholder blips built in code, as `WorldSounds` makes today's, until his CC0 files arrive with their `docs/credits/` entries |
| RD15 | How hidden "no view of who is under the car" is | (a) by sight: the panel's use spot has no line of sight into the space under the car (static walls, tested on the host's world), no screen names the fitter, no sound plays while a fit runs (RD14 (a)), and every client still receives every avatar and `FitChanged` (that a fit runs, by whom, from which tick), so a modified client could show who is under the car without any geometry; (b) the host stops sending the avatars under the car to the holder, and narrows `FitChanged` to the fitter alone (the others draw the pose from the snapshot or not at all), with the `busy` refusal at the car re-examined, since it is harmless today only because every running channel is public (`channel_free.gd`) | (b) per-entity visibility by place, which §5 does not have and §10 keeps for "only if a human asks"; with either, the holder hears the fitter's voice, which RD2's panel distance keeps within the 8 m voice radius (R5 places it, R8 checks it). (a) is how hidden packages and the Generator's switches work (GD11). Either way the host's world has no car (RE8): a knife swing hits a player behind the lowered car, and a modified client picks up an item lying inside it; accepting that is part of the answer | **(a), the engineer** (the recommendation), with RE8's host blind spot accepted |
| RD16 | What else drops the car with a kill | The holder leaves or loses its connection: (a) the car drops and kills, as a let-go; (b) the car comes down without a kill. The round ends (time, every task done, no crew present) while the car is up: (x) the car comes down without a kill; (y) it drops and kills, as a let-go | #688 names "let go, or be knocked down". (a) a network drop kills teammates under the car, and a dissident can quit to kill; (b) a car that comes down on a player without killing has no meaning under RD6, and a dissident whose connection is poor is still the one holding. (y) kills after the round's outcome is decided, on the way to the end screen | **(a) and (x), the engineer** (the recommendation): "the car stays up only while someone holds" holds for every stop, and nothing dies after the outcome (RE4's mechanism) |

### 6. RE items (technical: the manager decides and reports)

| # | Choice | Options | The failure it prevents | Decision |
|---|---|---|---|---|
| RE1 | The lift's hold | (a) a channel: `Interact(lift_panel)` starts an endless `HoldStation`, the channel's stops are the drops; (b) a toggle: one `Interact` raises the car, a second lowers it; (c) the client reports "holding" in its claims | (b) a lost or late press inverts the car, and a knockdown, a death, a leave and walking away each need their own code to lower it. (c) client state, against invariant 1. (a) gets every stop the raise already has, tested, and the conditions every tick | (a) |
| RE2 | Channels on stations | (a) `Channel.station` (a station id, or -1), set by `ChannelEffect.run` from the intent's `station` field (`Channels.station_of(ctx)`: the channel's station, else the intent's); `ChannelFree` refuses a second channel on the same station; a station channel has no player target (0); G1's station conditions (`AtStation`, `StationInSight`, `StationUsable`) find their station through `Channels.station_of`, as `TargetInReach` finds its player through `Channels.target_of`, since a re-check handles no intent; (b) the station id in `Channel.target` | (b) `interrupt_involving(peer)` and `on_target(peer)` compare `Channel.target` with peer ids: a knockdown of peer 3 would stop the hold on station 3, and `ChannelFree` would see two stations with one id as one. Station conditions that read only the intent's `station` would fail every re-check (no intent then), stopping every hold in its first tick, as `ChannelEffect`'s class doc warns for `InReach`. The fit is presence over time that earns a subtask, so on the re-check of a timed station channel (`MatchContext.channel` set, the channel not endless) `AtStation` also fails when the actor's last accepted claim is older than `MovementRule.PUSH_TICKS` (the zone task's ZE10, `MovementRule.claim_age` from `release/m7`, with the stored-credit bound #647 added): without it a modified client starts a fit, stops claiming but keeps polling, fits on the host while it walks to the shelf at home, and one later claim spends its stored credit, so it earns the fit and the travel at once. The endless lift hold is exempt: a stale holder only keeps the car up (its own trust moment), while an honest holder losing half a second of claims would drop the car on the fitter | (a), with the claim age on timed station channels |
| RE3 | A hold with no end | (a) `ChannelEffect.endless()` (false by default): `Channels.advance` checks an endless channel's conditions and counts its ticks but never completes it, and the base class skips its `seconds` check (the subclass checks its own); (b) a channel of 600 s, the bound; (c) a new channel started at each completion | (b) the car drops by itself after 10 minutes, the match clock's length. (c) a tick with no channel between two: a drop, or code to skip it | (a) |
| RE4 | The phase's end is no let-go | (a) `Channels.stop_all` sets `Channel.phase_ended` before `stopped()` runs; `CarRepair.hold_stopped` then lowers the car with no box test; (b) a cause argument on every `stopped()` | the mechanism for RD16 (x), the engineer's: without it, a round won while someone works under the car kills that player after the outcome, on the way to the end screen. (b) changes `RaiseDowned` and every later channel for one flag | (a) |
| RE5 | Letting go | (a) `StopRaise`, as it is: no fields, its rule `Channeling`, applied it stops whatever channel its sender runs; the client sends it on E released when its player may run a channel (it sent `Raise`, or `Interact` on a station whose rule ends in `HoldStation`); (b) rename it `StopChannel` (a protocol bump); (c) a new `StopInteract` | (b) every client and the wire change for a name; a later cleanup if anyone wants it. (c) two intents that do the same. A `StopRaise` with nothing running is refused `not_channeling`, to its sender only | (a) |
| RE6 | The instant kill | (a) `LifeRules.kill(ctx, peer)`: from living or downed (RD7) straight to dead, everything else as `die` (channels stopped first, the body, `Died`, `player_died`, the drop at the body, the respawn deadline); (b) `knock_down` then `die` in one command; (c) `damage` with a large amount | (b) a `KnockedDown` and a `Correction` for a player who is dead in the same tick, and a knockdown the client shows for one frame. (c) knocks down, never kills, and spares the invulnerable. (a) keeps `LifeRules` the one place that changes the life state | (a); the mode check requires `LifeTicks` with a `Respawn` in every phase that accepts `Interact` when a task type of the mode can kill (`TaskType.kills()`, false by default), so a dead player always comes back |
| RE7 | The volume under the car | (a) an oriented box from two markers on the floor, both in the car's scene: the car's use spot (its middle) and `car_end` (the middle of its front), so the box turns with the scene; its half-length the distance between them, its half-width and its clearance (the raised underside's height) in the type's data; the test pure geometry over each player's last accepted position, its feet, with no claim-age filter, as `Strike` picks its targets; (b) the car station's cylinder; (c) a rotation per marker in `LevelLayout`; (d) a `WorldQuery` overlap query | (b) a cylinder that covers the car's ends reaches past its sides and kills bystanders; one that spares them spares the ends. (c) changes `LevelLayout`, `MarkerReader` and the command log's layouts (the photo ADR's PE3 (b)). (d) the host's world holds no players; `core/` would ask `server/` for state it has. ZE10's claim age is for presence that earns progress (the fit's re-check, RE2); a kill uses the host's position as a hit does | (a); the host never needs the car's body for it |
| RE8 | The car's collision | (a) the car's body an `AnimatableBody3D` (`sync_to_physics` on) on a client-only collision layer (layer 4, named `movers` in `project.godot`), which the own player's `collision_mask` includes beside layer 1; each client moves it from `LiftChanged`; the host's world (layer 1 only, §4.5.9) never holds it; (b) the car's body on layer 1; (c) a body the host's world moves with the lift | (b) the host builds the body static in whatever pose the scene was saved in: lowered, every fit's sight line from the eye to the use spot under the car hits the car, `blocked`; raised, the host's sight lines meet a car in the air that the clients show on the floor; and a scene saved in the other pose silently changes the rules. (c) `core/` would drive a body in `server/`'s world through `WorldQuery`, a boundary change. (a) costs quirks, because the host's world has no car. First, the host's sight lines pass through the car (an honest client's hint follows its own ray, so it offers nothing through the car). Second, the host's movement checks (§7.1.5) know no car: a landing needs a host floor within step height, so an honest client that jumped onto the lowered car's bonnet or roof (`jump_height_m` 1.0), or rode the rising car up on its roof (`sync_to_physics`), would have its claims corrected, again and again. Third, the host picks a swing's targets and judges a `PickUp`'s sight itself: a knife swing hits a player behind the lowered car, and a modified client picks up an item lying inside it (a victim's knife after a drop), so raising the car to get an item back is a rule only honest clients keep; an accepted limit put to the engineer in RD15 (closing it would teach `PickUp` and `Strike` about one task's car) | (a), with R5 shaping the car's layer-4 collision so nobody can stand on it: its top, lowered, above jump reach (`jump_height_m` plus `step_height_m` plus a margin) or made of faces steeper than the controller's `floor_max_angle`, so nobody stands on the car and nothing rides it up; R7's integration test: a jump at the lowered car, and a crouched walk under and out of the raised one, bring no `Correction`. The one push left, the dropped car's body moving out a player whose capsule overlaps the box's edge (at most the capsule's 0.4 m, sideways on the floor), is an accepted quirk: R7's test records whether the host's horizontal bound (§7.1.5) accepts it or one `Correction` follows |
| RE9 | One holder, one fitter | `ChannelFree` (per actor and per station, RE2) in the panel's and the car's rules, `busy` | two holders would make "let go" mean nothing; two fitters fit one part twice | as stated; `HoldStation.required_conditions()` is `AtStation` and `ChannelFree`, so the mode check refuses a hold rule without them |
| RE10 | The events and their order | public, audience everyone: `LiftChanged(station, up, tick)` (no peer field), `PartNeeded(station, kind)` (`station` the picture's, `kind` an item kind id, empty for none), `FitChanged(station, fitter, tick)` (fitter 0 when it stops), `PartFitted(station, item)`. Order: a drop's `LiftChanged`, then per victim in peer-id order its kill's events; a fit's `PartFitted`, then `subtask_done`'s, then `PartNeeded`; the deal's `StationPlaced`s, then `PartNeeded`. No rate window: each event follows an accepted intent or a stop, bounded by the reliable-intent bucket (§4.5.6), as `Swapped` | a `Died` before its cause, or a `TaskState` before the part leaves the hand. A ZE4-style window would delay a drop past its deaths. The fit's start and stop share one event, `FitChanged` (fitter 0 for a stop), one wire row fewer than the raise's pair | as stated |
| RE11 | Where the state lives | (a) the task state (`CarRepair.State`): the station ids, the drawn parts, how many are fitted, the tick the current hold began (-1 for none); "fully up" is `tick - held_since >= rise ticks`, computed where it is read (the car's `use_problem`, the client from `LiftChanged`'s tick), so `has_tick()` is false; (b) the per-part state table; (c) a tick system that moves the car | (b) splits one task over two homes where §9.1 names the task state. (c) a tick for a number the start tick already gives | (a); who holds stays in `Channels`, the one place for running channels |
| RE12 | The fit's end | (a) the part locked at the car by cooking's C2 move (`ItemState` locked, at the car's use spot, no `item_rested`), then `PartFitted`; the client draws no item locked at a car; (b) the item removed from the match, with a new `ItemRemoved` event | (b) a new event and a new move in `Items` for one use; locked items already exist (a delivered package) | (a); if C2 has not landed when R4 starts, R4 builds that move as C2 names it |
| RE13 | The parts' source | (a) one bin station kind per part kind on the shelf, each with its own spawn tag and its own rule ending in `GiveItem(that part)`: cooking's C1 parts unchanged (its CE2, CE3, CE6 (a)) with its CE17 cost `Cooldown` (`too_soon`) before `GiveItem`, the photo's PE7 by the same names; (b) one bin kind, bin i giving part i in level order; (c) parts lying on the shelf as items, picked up | (b) ties the shelf's art to a list's order and needs an event to say which bin gives which (cooking's CE6). (c) runs out (RD9) | (a) |
| RE14 | The mode checks and the demands | `CarRepair.check`: the car, panel and bin kinds set, and the picture's a display kind (C1's flag) with no rule, spawn tags distinct (ZE3 across the mode); `parts` non-empty and distinct, each given by exactly one bin and listed in the mode's `item_kinds` (cooking's CE18); the car's rule ending in a timed `HoldStation` and the panel's in an endless one; the fit's seconds 0.05 to 600, `rise_seconds` 0 to 60, `half_width_m` 0.2 to 10, `clearance_m` 0.5 to 10, their neutral defaults outside; the car kind's `radius_m` at most `half_width_m` and its `height_m` at most `clearance_m`; a non-empty RNG purpose; the subtasks setting declared, whole, its minimum at least 0; every bin rule holding a `Cooldown` before its `GiveItem`; each part's `GiveItem.max_items` at least twice the mode's maximum of players plus the subtasks maximum plus 1 (cooking's CE3 bound, the subtasks maximum counting the fitted parts locked at the car), so the hands and the car can never hold every part of a kind. Demands: exactly one `car`, `car_end`, `lift_panel` and `part_picture` marker, and one marker per bin kind; no colours. The layout: a new `TaskType.layout_problems(layout)` (empty by default), which `FitCheck.shortfalls` appends for every task type the map's rows can deal, so `all_ready` holds back on a bad map before `Match` starts; `CarRepair`'s refuses a `car_end` marker nearer the `car` marker than the car kind's `radius_m` (a short axis); R8 also asserts it for House and the greybox | a car cylinder wider than the box lets a player fit from beside the car, safe from the drop: the trust moment gone. A short axis makes the box smaller than the cylinder | as stated |
| RE15 | "No view" tested | R8, on House in the host's real world: from the panel's use spot at eye height, `WorldQuery.line_of_sight` to a grid of points in the box, every 0.5 m from the floor up to `clearance_m`, is blocked for every point | a wall moved in a later level edit would give the holder a view nobody notices | as stated |
| RE16 | How the level binds the stations | the Generator's GE11 (a): `car.tscn` (the car's body, RE8; the use spot and `car_end` markers on the floor; the lift's static frame on layer 1), `lift_panel.tscn` (its use spot; a light the client drives), `parts_shelf.tscn` (one bin per part kind, each a use spot in its own tag's group, with the part's picture), `part_picture.tscn` (a frame on a wall, its use spot on the floor in front of it, where the client draws the needed part's picture, RD3); the client finds each placed station's scene by its use spot (the nearest in 3D within a tolerance) | as GE11 | as stated; no script in `levels/`. One deviation from GE11 and GE4's use spot "on the floor in front of the device, clear of its collision": the car's use spot lies under the car (allowed because the car body is on layer 4, RE8), and it must snap to the garage floor, not the lift's layer-1 frame (R5 keeps the frame clear of it, R8 asserts the snapped height, `levels/CLAUDE.md` names the exception) |

### 7. Testing
- **Unit tests** (R1 to R4; fixtures only, never `content/`, ARCHITECTURE §9.6). R1: a channel on a station (its
  `station`, `ChannelFree` per station, a station channel that a knockdown of the peer with the station's number does
  not stop), an endless channel that never completes, `phase_ended` from `stop_all`, `hit_stops`, `HoldStation`'s
  hooks and its required conditions in the mode check. R2: `kill` from living and from downed, an invulnerable
  player, the events' order (channels, `Died`, `player_died`, the drop), the respawn after it, the mode check's
  `LifeTicks` rule. R3: the deal (stations, the drawn parts with no repeat, N = 0, an exact-count map), the hold and
  every stop of §2.3 each dropping the car, the box test (inside, beside, at the ends, on the roof, downed,
  invulnerable), the phase's end with no kill, RD11's refusal of a new hold only, the role-swap check (two players'
  forced roles swapped: identical `LiftChanged`, `PartNeeded`, `FitChanged`, `PartFitted`, `TaskState`,
  `TaskProgress` and `Died` streams; planted once, the panel refusing dissidents, it fails; reverted). R4: the fit's
  refusals in order, a stop losing progress, a fitter who stops claiming (its fit stops 10 ticks after its last
  accepted claim with `FitChanged(car, 0, tick)`, its progress lost, RE2), a holder who stops claiming (the car stays
  up), completion locking the part, the next `PartNeeded`, the last part
  completing the task, the fit and the drop in one tick in both actor orders and with the drop in the command step (the fitter dies first).
- **The leak test's lists** (R3, R4): the four events join the task events every player receives alike
  (`LeakCheck`, `ScenarioInvariants`); they prove nothing until a scenario plays car repair (R9).
- **Integration tests on House** (R8; bots do not play House, ARCHITECTURE §9.7): `Match` over `HostWorldQuery` with
  House's level and its markers read by `MarkerReader`: a holder at the panel, a fitter under the car with the right
  part, a bystander beside the car and one at the car's far end; the holder lets go: only the players inside the box
  die (`Died` for each, none for the bystander); a full repair from scripted commands, ending with `TaskProgress`;
  RE15's "no view" check; the voice distance (the panel's use spot plus its radius within the base mode's voice
  radius less 1 m of the car's use spot, and farther than the two radii apart, RD2); a part from each bin; the
  raised car's underside (`clearance_m`) below the standing capsule's height, so only a crouched player gets under it
  (RD1); the stations read without errors.
- **Scenarios** (R9; content, provisional, the engineer approves the scripts): on the greybox (RD13, his GD7
  answer), a bot holds the lift (`StepInteract`, G1), another fits (`StepWalkTo` under the car, `StepInteract`; the
  host checks no crouch, RD1, so a bot needs none), the holder lets go too early (`StepStopRaise`) and the fitter dies
  and respawns, then a full repair. One of them runs in `bots`, over the real wire. The leak plant (as M7-Z3):
  `FitChanged` declared to the actor only fails `LeakCheck` and `ScenarioInvariants` in that scenario; reverted,
  recorded in the PR.
- **The chaos bots** (ARCHITECTURE §4.6.5.3; R9 once the base mode deals car repair): a hostile `Interact` at the
  panel, the car and every bin gets only its `Rejected`s (`not_accepted` when downed or in the wrong phase,
  `two_handed`, `out_of_reach`, `blocked`, `busy`, `unavailable`, `empty_hand`, `wrong_item`, `hands_full`, `too_soon`), a
  `StopRaise` burst stops at the bucket; the four new H→C kinds join the wrong-direction list (R3, R4).
- **The client** (R7): the lift's height from `LiftChanged` (pure), the picture on the wall from `PartNeeded`, the
  hints only where the host would accept, no item drawn locked at a car, the fitter at work only on its avatar, a
  `shot` preview.
- **Green** (#605): `verify` (lint and check) locally, then CI's full suite on the PR, for each issue of §8.

### 8. The split
Sizes as in M6 and M7: S up to about 400 changed lines, M up to about 900. Effort: high for `core/`, `net/` and
`tests/harness/`. Base (the engineer's answer A on
[#676, comment 6095620770](https://github.com/xperiaroco2/prime-game/issues/676#issuecomment-6095620770)): the engine
issues R1 to R4 and R7 start on `release/m7` (`start <n> --base release/m7`) and their PRs go into it, merged by the M7
manager, their protocol numbers kept in step with it; R7 starts once R5's scenes have reached `release/m7` (the M7
manager takes main into it). The level and content issues go into `main`: R5 at once; R6 and R9 once `release/m7`,
with R1 to R4, has merged into main, since they load its parts; R8, which tests R5's and R6's House, follows them
into main.

| Issue | Labels | Goal | Acceptance | Files | Depends on | Size |
|---|---|---|---|---|---|---|
| R1 | needs-engine, area:core | Channels on stations: `HoldStation`, endless holds | RE2 to RE5, RE9: `Channel.station` and `Channels.station_of`; G1's `AtStation`, `StationInSight` and `StationUsable` reading their station through it, with a test that a hold passes its own re-check; `AtStation`'s claim age on the re-check of a timed station channel (RE2, ZE10; an endless one exempt); `ChannelFree` per station; `ChannelEffect.endless()`; `Channel.phase_ended` from `stop_all`; `HoldStation` (`seconds`, `endless`, `hit_stops`; `required_conditions` `AtStation` and `ChannelFree`) calling `TaskType.hold_started`, `hold_stopped` and `hold_completed` (defaults: nothing); `LifeRules.damage` stops a channel only when its effect's hits stop it; §7's R1 tests; ARCHITECTURE §9.3 (Channels), §9.4.1 (`ChannelFree`), §9.4.2 (`HoldStation`), §9.5.13 (`StopRaise` stops any channel), §4.1's `StopRaise` row and §7.1.8 (no longer raise-only) | `core/channel/`, `core/tasks/` (G1's station conditions), `core/content/task_type.gd`, `core/life/life_rules.gd`, `core/content/mode_check.gd`, `tests/unit/channel/`, `docs/ARCHITECTURE.md` | G1 (`Interact`, `AtStation`, the station rules' mode checks); `MovementRule.claim_age` (on `release/m7`, its base) | M |
| R2 | needs-engine, area:core | The instant kill: `LifeRules.kill` | RE6: `kill` from living or downed; `TaskType.kills()` and the mode check's `LifeTicks` rule; `Strike` skips a target that is no longer alive when its turn comes (a death earlier in the same swing, §4), with a unit test (one swing knocks down a holder whose channel's stop kills the second target: one `Died`, no rule error); §7's R2 tests; ARCHITECTURE §9.3 (Life), §9.4.5's `LifeTicks` row | `core/life/life_rules.gd`, `core/combat/strike.gd`, `tests/unit/combat/`, `core/content/task_type.gd`, `core/content/mode_check.gd`, `tests/unit/life/`, `docs/ARCHITECTURE.md` | none (RD7 answered; #728 reworks the knocked-down state, `downed` in the code, without changing what `kill` does) | S |
| R3 | needs-engine, area:core, area:net | The car repair task type: the deal, the lift and the drop | §2.1 to §2.3 and §2.6 with the engineer's answers (RD3, RD4, RD5, RD6, RD7, RD10 (c), RD11); the `part_picture` display kind (C1's flag) that `PartNeeded` names; RE7, RE10, RE11, RE14 (with `TaskType.layout_problems` in `FitCheck`); `LiftChanged` and `PartNeeded` with their wire rows, `WireBudget` cases and a protocol bump, and their folds in `ClientModel` with unit tests (client/CLAUDE.md: a new event's fold lands in the core PR that adds it, so bots can read it); the leak lists; §7's R3 tests and the chaos wrong-direction kinds; ARCHITECTURE: car repair's entry beside Delivery's (§9.5), §4.2, §4.3.4, §5's task events, §3.3's RNG purposes | `core/tasks/car_repair.gd`, `core/content/task_type.gd`, `core/match/phases/fit_check.gd`, `core/events/`, `net/messages/`, `server/` (`WireBudget`), `core/match/phases/join_rules.gd` (the version), `client/net/client_model.gd`, `tests/unit/client/`, `tests/harness/scenario_invariants.gd`, `tests/harness/bots/leak_check.gd`, `tests/unit/tasks/`, `tests/fixtures/tasks/`, `docs/ARCHITECTURE.md` | R1, R2, G1; C1 (the display flag); ZE3 (on `release/m7`, its base); RD3's draw, read back (§9; revertible) | M |
| R4 | needs-engine, area:core, area:net | The fit and the parts | §2.4 with RD8 (a) and RD10 (i); RE12, RE13; the car's `use_problem` (`unavailable`, `empty_hand`, `wrong_item`; `use_reasons()` for the alphabet test, as cooking's CE11); `FitChanged` and `PartFitted` with their wire rows and a protocol bump, and their folds in `ClientModel` with unit tests; §7's R4 tests | `core/tasks/car_repair.gd`, `core/events/`, `net/messages/`, `core/match/phases/join_rules.gd`, `client/net/client_model.gd`, `tests/unit/client/`, `tests/unit/tasks/`, `tests/harness/`, `docs/ARCHITECTURE.md` | R3; C1 (`GiveItem`, `HandsHaveRoom`, `wrong_item`, CE18's item kinds with no spawn tag), C2 (the lock move; else R4 builds it, RE12) | M |
| R5 | area:level | The car, lift panel, parts shelf and part picture station scenes, in place of the House markers | RE8, RE16: `levels/stations/car.tscn` (the car's `AnimatableBody3D` on layer 4, bit value 8, its collision with no top a player can stand on (RE8), its raised underside at `clearance_m` (RD2's 1.4 m placeholder): below the standing capsule and above #727's crouched one, so only a crouched player gets under it (RD1); the lift's frame on layer 1; the use spot in `spawn_car` and `car_end` in `spawn_car_end` on the floor; tags provisional, "not a decision"), `lift_panel.tscn`, `parts_shelf.tscn` with one bin per part kind (RD2's 3, a placeholder), each bin showing its part's picture, and `part_picture.tscn` (a frame on a wall, RD3); instanced in the garage and storage in place of `CarLift`, `LiftPanel` and `PartsShelf` at house-map §6's points, and the picture on a garage wall at a point R5 proposes (house-map §6); static walls so that the panel's use spot sees nothing of the space under the car; the panel nearer the car than house-map §6's proposed point, every point of its cylinder within the voice radius less 1 m of the car's use spot and outside the car's cylinder (RD2's 5 m and 1.5 m, placeholders); no respawn marker inside the car's footprint; `levels/CLAUDE.md`'s spawn points gain the tags, layer 4 (named `movers` by R7) and the car's use-spot exception (RE16); a `shot` of the garage and of storage; provisional, named in the PR for the engineer's approval | `levels/stations/`, `levels/house/rooms/garage.tscn`, `levels/house/rooms/storage.tscn`, `levels/CLAUDE.md` | no issue (the markers carry no group until the base mode holds the type, R6); #727's crouched height: R5 starts on the 1.4 m placeholder and matches it once #727 gives its number | S |
| R6 | area:content | Car repair in the base mode | `content/tasks/car_repair.tres` with RD12's drafted words (§5, drafts until the engineer approves them) and RD2's placeholders ("not a decision"), the station kinds and their rules (§2; each bin's with the `car_part_take` cooldown, RD2's 0.25 s; the picture's a display kind), the part item kinds in `content/items/` (RD9's hands), with no spawn tag and listed in the base mode's `item_kinds` (cooking's CE18); the base mode: the type, its subtasks setting, `tasks` per RD13, Round accepting `Interact` and `StopRaise` from the living; the greybox's station scenes above y = 0 (RD13, his GD7 answer); the MVP's scenarios ban car repair (M7-Z2's bans); every test that loads the base mode still passes, each changed expectation named in the PR; provisional files named for the engineer's approval | `content/tasks/`, `content/items/`, `content/modes/base_mode.tres`, `levels/greybox/greybox.tscn`, `content/scenarios/`, `tests/unit/content/`, `tests/integration/`, `tests/scenarios/`, `tests/harness/chaos/`, `tests/harness/perf/`, `docs/ARCHITECTURE.md` (§9.5, §9.6) | R3, R4, R5; G5 (`Interact` in Round; GD7's greybox pattern); C6's item-source data pattern; C1's CE18 (given kinds with no spawn tag); `release/m7` with R1 to R4 merged into main | M |
| R7 | area:client | The client's view | RE8's drive: the car's body moved from `LiftChanged` and the client's copy of `rise_seconds`; layer 4 named `movers` in `project.godot`, with `PhysicsLayers.MOVERS` and its row in `physics_layers_test.gd`, which matches the bits to `project.godot`'s names; the own player's `collision_mask` gaining layer 4 (whether #728's ragdoll collides with the car, R7 and #728 agree); RE8's integration test (a jump at the lowered car, a crouched walk under and out of the raised one: no `Correction`; the edge push recorded); the needed part's picture from `PartNeeded` on the `part_picture` station's scene on the garage wall (a `Sprite3D`, the same picture as its bin's, in the world, depth-tested, never through walls (DD4), in `SightHider`'s group: render checklist item 3); the E hints and intents: `Interact` on E pressed over the panel, the car or a bin, `StopRaise` on E released after a hold (RE5), no hint where the host would refuse what the client knows (the car down, a wrong part, someone holding); the fitter's own progress from `FitChanged`'s tick; the fitter at work on its avatar, crouched by #727's crouch (RD1); no item drawn locked at a car; the sounds (RD14) through `SoundChooser` and `WorldSounds`, within 12 m (`AudioStreamPlayer3D.max_distance`) and muffled behind the level (M5-7); no sound tells the panel that a fit is running (RD14); the M4 render checklist, the PR routed to `netcode-security-reviewer` too; `shot` previews; ARCHITECTURE §4.7 | `client/world/`, `client/player/player_controller.gd`, `client/life/life_view.gd`, `project.godot`, `client/physics_layers.gd` (`MOVERS := 1 << 3`), `tests/unit/client/physics_layers_test.gd`, `tests/unit/client/`, `tests/integration/client/`, `docs/ARCHITECTURE.md` | R3, R4, R5 (in `release/m7`); G6 (`TargetChoice` over stations); #727's crouch, built (the crouched walk under the car; the controller's headroom under its layer-4 body); R6 for a playtest | M |
| R8 | needs-engine, area:core | Integration tests: car repair on House | §7's House tests in the host's real world, the drop that kills only the players under the car, RE15's "no view", the voice distance (RD2), the raised car too low to stand under (RD1) and the car's use spot snapped to the garage floor (RE16) among them | `tests/integration/levels/`, `docs/ARCHITECTURE.md` (§9.7's House line) | R3, R4, R5, R6 | S |
| R9 | area:content, area:tooling | Scenarios that play car repair, its leak plant and chaos rows | §7's scenarios on the greybox (provisional, the engineer approves the scripts), one of them in `bots`; the leak plant, planted once and reverted, recorded in the PR; the chaos rows against dealt stations | `content/scenarios/`, `tests/scenarios/`, `tests/harness/chaos/`, `docs/ARCHITECTURE.md` (§9.7, §4.6.5.3) | R3, R4, R6; G1 (`StepInteract`) | S |

The crouch (#727) and the knockdown rework (#728) are not in the split: each is a mechanic the engineer decided, with
its own design first. R5 starts on a placeholder height and R7 waits for #727's crouch; nothing here waits for #728,
whose knocked-down state is today's `downed` (its ragdoll and its mute change no rule of the drop).

### 9. Needs the engineer
RD1 to RD16 are answered (§5). Left, one batched question; the design follows each recommendation until he answers,
each revertible:
- **RD1's read-back, how the car asks for the crouch.** His answer: "under the car the player works crouched". (a) By
  the car's height: the raised car's underside lies below a standing player and above a crouched one, so an honest
  player crouches to get under it and leaves crouched, slower than walking (Shift a bit faster), which is when a
  let-go kills; the host checks no crouch, having no car (RE8), so a modified client could stand under it, judged by
  its feet as everyone. (b) A pose only: the car raised above a standing player, the fitter drawn crouched while it
  fits, and walking out upright at full speed. (c) A rule of the fit: as (a), and the host refuses a fit from a player
  whose claims are not crouched (#727's crouch flag), a new condition and reason in R4. **Recommended: (a):** the
  crouch shapes the risk and the host needs nothing new; (c) guards only against modified clients, which the project
  does not harden against; (b) makes the crouch a look, and the way out fast. It is #727's open question 1 too ("does
  it fit under things only a crouch passes"). R5 and R8 need it.
- **RD3's read-back, the draw.** His answer named the place (the garage wall) and the picture; the draw stays (y),
  never the same kind twice in a row, unless he says otherwise. R3 needs it.
- **His approval in this PR:** RD12's drafted name, description and label (§5); RD2's placeholders, his to tune after
  a playtest; the content-area edits (GDD §8, house-map §6 and §10).

## Alternatives
- **A toggle for the lift** (RE1 (b)): a lost press inverts the car, and every stop needs its own code.
- **A station id in the channel's player target** (RE2 (b)): a knockdown of the peer with that number stops the hold.
- **A 600 s channel for the hold** (RE3 (b)): the car drops by itself at the bound.
- **A cause on every channel's stop** (RE4 (b)): one flag set by `stop_all` says the only cause that matters.
- **A new release intent, or a rename of `StopRaise`** (RE5 (b), (c)): the existing intent already stops any channel.
- **A knockdown then a death for the drop** (RE6 (b)): a knockdown nobody lives through, with its `Correction`.
- **The car's cylinder as the drop's volume** (RE7 (b)): it cannot cover the car's ends without its sides.
- **A rotation in `LevelLayout`** (RE7 (c)): a layout, reader and command-log change for one box.
- **The car's body in the host's world** (RE8 (b), (c)): static, it blocks every fit or hangs a car in the air that
  the clients show on the floor; moving, it is a boundary change.
- **A pose only, under a car a standing player passes** (RD1 (a), the first recommendation): the engineer chose a
  crouch for every player (#727); and RD1's read-back (b), a pose under a high car, would leave the way out fast.
- **The needed part shown on the car or on the panel** (RD3 (a), (b)): the engineer put the picture on the garage wall
  for now; on the panel, the holder would learn the part and the fitter would have to ask.
- **A slow lowering with a moment to roll out** (RD5 (c)): against "the dropped car kills at once".
- **Removing a fitted part from the match** (RE12 (b)): a new event and move where locking exists.

## Consequences
- ARCHITECTURE §9.8 gains car repair's row and §10 its open row, both pointing here; GDD §8 gains its section with
  the engineer's answers and what is still open; house-map §6 and §10 record his decision that the lift panel has no
  view of who is under the car, that anyone holding may let go, and the picture of the needed part on a garage wall.
- The car depends on two mechanics designed elsewhere: from #727's crouch it needs a crouched height below the raised
  car's underside (R5, R7); from #728's knockdown nothing new, since the drop reads the host's position of a
  knocked-down player, wherever a client's ragdoll lies, and a knocked-down player under the car cannot crawl out or
  call for help (it cannot move or talk), which only sharpens the trust moment.
- When R1 lands, the channel is a primitive for stations as well as players: a later timed use of a station (a long
  repair, a printer that takes time) is a `HoldStation` in its kind's rule and its task type's hooks.
- When R2 lands, `LifeRules` has a second way to die. The later single-shot weapon of decision 10 is a `kill` in an
  item's rule (with its own engine request then), not a new life path.
- The protocol goes up in R3 and in R4; kind numbers and versions are taken when each lands, never from here.
- Layer 4 (`movers`) is the first client-only collision layer: the host's world reads only layer 1 (§4.5.9), and the
  host does not check movement through walls (§7.1.9), so a mover there never blocks the host's sight. A later moving
  door or gate may use the same layer; one that must block the host's sight (a pick-up through a closed door) needs
  its own design.
- Merge order: this PR after the Generator's (#695), whose parts it names; the cooking (#682) and photo (#687)
  designs touch the same lines of GDD §8, ARCHITECTURE §9.8 and §10 and house-map §10: whichever merges second
  resolves them on purpose. Implementation: R1 after G1; R4 after C1 (and C2, or it builds the move); R6 after G5;
  the engine issues on `release/m7`, the level and content issues into `main` (§8's base).
