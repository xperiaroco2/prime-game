# The cooking task (#682): its engine parts, an item source, items on stations, and the split

- **Status:** Proposed on 2026-10-10. Nothing here is built. The rules are the engineer's: #682's "Decided" list, his
  answers on #682 (comment 6089351713; chat with the game-design manager session of 2026-10-10, read back) and his
  answers to CD1 to CD17 ([PR #701, comment 6095326743](https://github.com/xperiaroco2/prime-game/pull/701#issuecomment-6095326743),
  chat with the game-design manager session on the morning of 2026-10-10): every recommendation, except his own words
  for CD2 (the rest of CD2 drafted in §5.1 for his approval), CD3 (b), CD5 (b), CD6 (c), CD8 (b) and CD13 (b); CD17
  became technical (CE17). The CD items are game rules and taste (the
  [trust ADR](2026-10-04-trust-based-autonomy-gated-merge-into-main.md)'s tier (c)); what his answers leave open is in
  §9, each with options and a recommendation, and the design proceeds with the recommendation where it can be
  reverted. The CE items are technical, the game-design manager session's to decide and report (tier (a)): decided
  here, each revertible in its issue.
- **Date:** 2026-10-10
- **Deciders:** the engineer (the rules, CD1 to CD16, answered on 2026-10-10); the game-design manager session of #676
  (CE1 to CE20, and CD17's number as CE17's flood guard).
  Designed by the agent of #682, on the engineer's word (#682; the track's kickoff on #593, comment 6088751685).
- **Builds on:** [the Generator ADR](2026-10-10-generator-task.md) (#679, proposed, its PR to merge before this one:
  `Interact(station)` (GE1), a station kind owning its rules (GE2), `AtStation`, `StationInSight`, `StationUsable`,
  `UseStation`, `TaskType.use_problem` and `use_station`, busy hands, the per-task-type subtask count (§6.1), station
  scenes bound by their use spot (GE11), its issues G0 to G8; this ADR extends G1's API with one hook,
  `TaskType.use_reasons()`, CE11), [content API v0](2026-09-29-content-api-v0.md) (task
  types are classes with settings), [MVP rules](2026-09-29-mvp-rules.md) (Tasks: the engineer's decision of
  2026-09-30, #79), [vision revision 1](2026-10-01-vision-revision-1.md) (V4's "living", two hands and the belt),
  [the zone task ADR](2026-10-09-m7-zone-task.md) (#36, on `release/m7`: `StationState.contains`, the pattern of
  `ZoneProgress`), [level piece conventions](2026-10-09-level-piece-conventions.md) (station scenes in
  `levels/stations/`), [MVP content built by the engineer](2026-09-29-mvp-content-built-by-the-engineer.md) (content
  and levels are provisional, approved in their PRs), [the House map](../design/house-map.md) (§2 decision 6, the
  stations of §6, the routes of §7), [tests on CI](2026-10-09-tests-on-ci-local-lint-and-check.md) (#605)
- **Numbering:** CD and CE are this ADR's own; the issues are C1 to C9 (§8), which the manager opens from the PR's
  handoff.

## Context
The engineer's rules (#682, "Decided"), in short: Cooking is a task type; one burger (one order) is one subtask, the
host sets the count (default 1). Every order hangs on the kitchen's order board from the round's start and shows a
bun and a patty as pictures and a herb as an icon, which only the greenhouse's herb board decodes, with a mapping new
each round. There are 3 buns, 3 patties (told apart by look, never named after animals) and 5 herbs. Each ingredient
is a one-handed item; the belt holds one. One box per bun and patty kind starts in storage: a two-handed item that
gives its ingredient wherever it stands, one per press of E, without limit, to anyone; a dissident may hide one. The
herb beds give one herb per press. The grill takes one patty at a time: 10 s to fry, then 5 s to take it off before
it burns, black and unusable; a fried patty stays fried. Each order has its own place in the kitchen with a plate
already on it; E with an ingredient puts it on, in any order; each one is checked at once, a wrong one red and taken
back, a right one green and fixed; the burger is done on the spot once its bun, patty and herb are green. Open (#682):
the burger count's maximum, the looks and names, and busy hands with a box and a herb.

Three things are new to the engine, beyond what the Generator brings:
- **Items made during a round.** Today every item is spawned in the deal (`SpawnItems`, Delivery's packages). A box
  and a bed make a new item on every press.
- **A station that holds an item and a timed station state.** The grill holds one patty and changes it over time,
  with no player channelling; a place holds the ingredients put on it.
- **An item that changes.** A patty goes from raw to fried to burnt and keeps what it became.

What already holds (ARCHITECTURE §9, §5; the Generator ADR's Context): tasks are shared and only living players do
subtasks (#79, V4); hidden by sight is a client rule, every item reaching every player through reliable events (the
snapshot holds avatars only, §4.3.5) and the client drawing it only where it lies; items move only through `Items`
(`core/items/items.gd`: `take`, `swap`, `place`, the belt); an item id is a `u16` on the wire (0xFFFF is none, §4.3.1);
the reliable-intent bucket bounds each peer at 100, refilled at 20 a second (§4.5.6).

## Decision

### 1. The mapping (`new-mechanic` step 3)

#### 1.1 Each rule to its engine part

| # | What #682 needs | Engine part | Exists? |
|---|---|---|---|
| 1 | Cooking is a task type, like Delivery and the Generator | `Cooking extends TaskType` (`core/tasks/cooking.gd`; the class name is technical, the task's id, name and description the engineer's, CD2), `has_tick()` true (the grill) | missing: C3 |
| 2 | One burger is one subtask; the host sets the count; default 1 | the type's own subtasks setting (`burgers`, a provisional id, "not a decision"), a whole-number `SettingSpec` of the mode that the lobby shows (`client/ui/lobby_panel.gd`), as Delivery's `packages`; its minimum at least 0 (G0's shared bound; the engineer gave only the default), its maximum CD1 | exists as a pattern (`Delivery.subtasks_setting`); G0 may move it into `TaskType`; the setting C6 |
| 3 | Every order hangs on the order board from the round's start | the deal (the deal row's actions, before Round's first tick) draws N orders and emits `OrderPosted` per order (CE8, CE9); the order board is a display station (CE6) whose scene the client draws the orders on | missing: C3 (deal, event), C5 (the board's scene), C7 (its view) |
| 4 | The order shows the bun and the patty as pictures, the herb as an icon | `OrderPosted(station, bun, patty, icon)`: the order's place, the bun's item kind id, the fried patty's item kind id, the icon's index; never the herb (CE9) | missing: C3 |
| 5 | 3 buns, 3 patties, 5 herbs | item kinds in the data: 3 buns, 3 raw patties, 3 fried patties (CE4), 1 burnt patty, 5 herbs; the task's lists `buns`, `raw_patties`, `fried_patties` (index-aligned), `burnt` and `herbs` | `ItemKind` exists (`core/content/item_kind.gd`); the lists C3; the data C6 (names and looks: CD2) |
| 6 | The icon-to-herb mapping is new each round; only the herb board decodes it | the deal draws a permutation of the herbs over the icons (RNG purpose `herb_code`) and emits `HerbCode(herbs)`, everyone, drawn only on the herb board (CE9) | missing: C3, C7 |
| 7 | Patties not named after animals | display names and looks only (CD2) | C6 |
| 8 | Each ingredient is a one-handed item; the belt holds one | `ItemKind.hands` 1 | exists (M4-5: `hands`, the belt, `Swap`) |
| 9 | One box per kind, two-handed, starting in storage | six box item kinds (`hands` 2), each with its own spawn tag; the cooking deal spawns one per kind on a marker of its tag (CE7) | `ItemKind`, `ItemSpawned` exist; the deal C3; the markers C5; the data C6 |
| 10 | A box gives its ingredient wherever it stands: one per press of E, to anyone | `Interact` naming an item (CE1): G1's intent with an item target, whose rules the targeted item's kind owns (`ItemKind.target_actions`): `ItemOnGround`, `InReach`, `InSight`, `HandNotTwoHanded`, `HandsHaveRoom`, the cost `Cooldown` (CE17), then `GiveItem(kind)` (CE2) | `Interact` missing (G1); its item target, `target_actions`, `GiveItem` and `HandsHaveRoom` C1; the four conditions before them and `Cooldown` exist (`core/items/`, `core/combat/cooldown.gd`) |
| 11 | "Without limit" | `GiveItem.max_items`, a cap per given kind (CE3); at the cap the oldest loose one comes to the taker (CD6) | missing: C1 |
| 12 | Sabotage: a dissident takes a box and hides it | nothing new: a box is an item (`PickUp`, `PutDown`), any living player carries one, and no condition reads a role | exists |
| 13 | E at a herb bed gives one herb, without limit | one station kind per herb (CE6), its `Interact` rule `HandNotTwoHanded`, `AtStation`, `StationInSight`, `HandsHaveRoom`, `Cooldown` (CE17), then `GiveItem(that herb)` | `AtStation`, `StationInSight` G1; `GiveItem` C1; the data C6; the scene C5 |
| 14 | The grill takes one patty at a time; 10 s to fry, then 5 s, then burnt | a `grill` station kind whose `Interact` rule ends in `UseStation`: `Cooking.use_station` puts a raw patty on (locked on the grill, `GrillLoaded`) or takes the patty off (`ItemPickedUp`); `Cooking.tick` (through `TaskTicks`) changes the patty's kind at its fried and burnt ticks (CE4, CE10); `fry_seconds` 10 and `burn_seconds` 5 in the task data, converted once by the one rounding rule (§3.3: 200 and 100 ticks) | `UseStation`, `use_station` G1; `TaskTicks` exists; the grill C4; `Items.change_kind` and `ItemChanged` C2 |
| 15 | A fried patty stays fried; a burnt one is black and unusable | the patty's kind: fried until it goes on a grill again (CD7), burnt for good; a burnt patty is red on any plate (CD8) | C2, C4 |
| 16 | Each order has its own place with a plate already on it, not carried | a `place` station kind, one marker per place in the kitchen; order i on the i-th place in level order (CE8); the client shows the plate of a placed place only (CE15) | missing: C3 (placing), C5 (the scene), C7 (the plate) |
| 17 | E on the plate with an ingredient puts it on; layers in any order | the place's `Interact` rule ends in `UseStation`: `Cooking.use_station` moves the hand item onto the place and checks it (CE5) | G1; C4 |
| 18 | Checked at once: a wrong one red, taken back; a right one green, fixed | a right one is locked on the place (no `PickUp` takes it) and fills its slot in the task state; a wrong one lies on the place as a ground item, so `PickUp` takes it back; `IngredientPlaced(item, station, right)`, everyone, drawn with a red or green outline (CE5) | C4; the outlines C7 |
| 19 | Done on the spot once its three are green | the third right one: the place done (`StationState.done`), then `Tasks.subtask_done` (CE13) | `Tasks` exists (`core/tasks/tasks.gd`); C4 |
| 20 | Busy hands | `HandNotTwoHanded` in every cooking rule (#679's rule; CD3) | exists (`core/items/hand_not_two_handed.gd`) |
| 21 | A dissident plays by the same rules; only the living do subtasks | no condition reads a role, so no public event can tell one (§9.2); `Interact` accepted from the living only (the phase's allowlist, as G5 sets it) | by design; the role-swap test C4 |
| 22 | Who sees the order board and the herb board | every client receives `OrderPosted` and `HerbCode`; an honest one draws them only on their boards in the world (CE9; CD12) | C3, C7 |
| 23 | Sounds | client sounds on the public events, within 12 m (CD14) | the range exists (`client/world/sound_chooser.gd`, `client/world/world_sounds.gd`); C7 |
| 24 | The stations on House | station scenes in `levels/stations/` in place of the markers `OrderBoard` (kitchen), `Buns` and `Meat` (storage), `Grill` (chill zone), `HerbBoard` and `HerbBeds` (greenhouse) (CE15) | the markers exist (plain `Marker3D`s under `Stations`, no group); the scenes C5 |
| 25 | Tested without bots on House (ARCHITECTURE §9.7) | unit tests from fixtures (C1 to C4); integration tests on House in the host's real world (C8); scenarios on the greybox, one in `bots`, for the leak test and the chaos bots (C9) | missing |

#### 1.2 Beside the Generator and the zone task

| | Zone task (#36) | Generator (#679) | Cooking | Why |
|---|---|---|---|---|
| Using a station | none: standing counts | `Interact(station)`, the station kind's rule, `UseStation` | the same for the grill and the places; beds give with `GiveItem`; boxes with `Interact(item)` | one intent and one owner per target kind (GE1, GE2, CE1) |
| Items | none | none | made on every take (`GiveItem`), changed on the grill (`ItemChanged`), held by stations | the chain is about carrying things |
| Timed state | each zone's ticks | the charge | the patty on the grill | each in its task state, run by `TaskTicks` |
| Progress event | `ZoneProgress` on each change, with its tick | `ZoneProgress` reused for the charge (GE7) | `GrillLoaded` with its fried and burnt ticks, `ItemChanged` at each | the same pattern: one public event per change, its host ticks in it, the client fills between; the grill has two thresholds and a held item, which `ZoneProgress` does not carry (CE10) |
| Event window | at most one per zone per 5 ticks (ZE4) | ZE4's window on the charge's progress event; none for `SwitchChanged` and `ButtonPressed` (GE8 (b)) | none; a cooldown per player on the takes from boxes and beds (CE10, CE17) | each cooking event follows one accepted intent, or is one of the grill's two changes per patty; a take emits two, so its rate is bounded, as GE8 bounds the button's |
| Done | per zone | the whole task at full charge | per place, one subtask each | a burger is an order |
| Stations | one per subtask, random markers, colours | the level's devices, every marker used | the level's devices (boards, grill, beds) and N places, no colours | the kitchen, the chill zone and the greenhouse are fixed places |
| Task screen | unchanged | the charge percentage (GD8) | unchanged: burgers done of N (CD12) | the orders hang on the board |

### 2. The rules as the engine runs them (with the recommendations)
1. **The deal** (when `DealTasks` draws Cooking). Stations, each on the one marker of its kind's spawn tag (an exact
   count, as the Generator's GE10, so nothing is drawn): the order board, the herb board, the grill, then one bed per
   herb in the order of `herbs`; then N places on the first N `place` markers in level order, N the subtasks setting.
   With N = 0 no place and no order is dealt: the task has no subtasks and is done (#79), as the Generator's N = 0. Then one box per box kind on a random marker of its tag (`cooking_boxes`), each with
   `ItemSpawned` and `item_rested` (spawn), as Delivery's packages. Then per place, in station order, its order: a
   bun, a raw patty kind and a herb, each drawn independently (`cooking_orders`, CD11). Then the code: a random
   permutation of the herbs over the icons 0 to 4 (`herb_code`). Station ids follow that order. A map without the
   markers deals nothing and logs a match error, as Delivery's does (the fit check keeps a match from getting there).
2. **Taking from a box** is `Interact` naming the box, from a living player in Round. An unknown item, or one whose
   kind has no `target_actions`, is refused `nothing_to_do` (CE1). A box's take is refused, in this order,
   `unavailable` (the box is carried), `out_of_reach` (farther than 2 m from the feet of the last accepted claim),
   `blocked` (no line of sight), `two_handed` (a two-handed item in the hand), `hands_full` (CD5) or `too_soon` (the
   player took from a box or a bed less than CD17's seconds ago, CE17). Applied: a new
   item of the box's ingredient kind is spawned at the box's position and goes into the hand, a one-handed hand item
   moving to the empty belt (`ItemSpawned`, then `ItemPickedUp`); at the cap, CD6 (a).
3. **Picking from a bed** is `Interact` naming the bed: refused `two_handed`, `out_of_reach` (the feet outside the
   bed's cylinder, `AtStation`), `blocked`, `hands_full` or `too_soon` (CE17); applied, `GiveItem` of the bed's herb, at the bed's
   position.
4. **The grill** is `Interact` naming the grill: refused `two_handed`, `out_of_reach` or `blocked`, then by
   `Cooking.use_problem`: an empty grill and no raw patty in the hand gives `empty_hand` (nothing in it) or
   `wrong_item` (anything else); an occupied grill and no room in the hands gives `hands_full`. Applied: an empty
   grill takes the hand's raw patty, locked on the grill, its fried tick (now plus 200) and burnt tick (now plus 300)
   in the task state, with `GrillLoaded`; an occupied grill gives its patty, whatever its kind, into the hand
   (`ItemPickedUp`), and is empty. Every tick of a phase that lists `TaskTicks` (Round): a patty on the grill whose
   fried tick has come becomes its fried kind, one whose burnt tick has come becomes the burnt kind (`ItemChanged`).
5. **A place** is `Interact` naming a place: refused `two_handed`, `out_of_reach` or `blocked`, then by
   `Cooking.use_problem`: `unavailable` (the burger is done), `empty_hand`, or `wrong_item` (an item that is none of
   the task's ingredient kinds: a knife). Applied: the hand item goes onto the place. It is **right** when its kind is
   the order's bun, fried patty or herb and that slot is still empty: locked there, its slot filled. Otherwise it is
   **wrong**: it lies on the ground at the place, interactive, so `PickUp` takes it back. `IngredientPlaced` either
   way. The third right one: the place is done, then `Tasks.subtask_done` (detail: the order's index).
6. **Nothing else** changes the cooking. A hit, a knockdown, a death or a leave drops what the player carries, as for
   any item (ARCHITECTURE §9.3, Life): a carried box drops at the body and gives there. The grill goes on frying: the
   patty belongs to no player. `TaskTicks` runs only in Round; `ResetMatch` clears the items, stations and task state.

### 3. What everyone sees

| What | Who learns it | How |
|---|---|---|
| Where every cooking station stands | everyone | `StationPlaced` in the deal (and the level's own scenes) |
| Where each box and ingredient lies, who holds what | every client receives it; an honest one draws an item only where it lies (the open-knowledge pillar: "where a moved item lies now is not shown") | `ItemSpawned`, `ItemPickedUp`, `ItemPlaced`, the snapshots' hand and belt items |
| Each order: its place, bun, patty and icon | every client receives it; an honest one draws it only on the order board in the kitchen (CD12) | `OrderPosted` in the deal |
| The icon-to-herb code | every client receives it; an honest one draws it only on the herb board in the greenhouse | `HerbCode` in the deal |
| An ingredient on a place, and whether it is right | everyone, by looking at the plate | `IngredientPlaced`, drawn on the plate with its outline |
| The grill: a patty on, fried, burnt, taken off | everyone, by looking at the grill or within 12 m of its sounds | `GrillLoaded`, `ItemChanged`, `ItemPickedUp` |
| Burgers done | everyone, on the HUD and the task screen | `TaskState`, `TaskProgress` |
| Who did it | the snapshots show who stood there, as for a delivery; `ItemPickedUp` names the taker, as today; no cooking event names a player | |

The code is shown only on the herb board, for every honest client; but a green herb on a plate also tells anyone
looking which herb that order's icon means (the engineer's red and green rule: no leak, and no invariant to keep). A
modified client could draw the code next to every
order from the wire, as it can draw every hidden package from the events today: the Generator's GE6 (a) says why the
host does not filter by place, and CE9 keeps the order event free of the herb so an honest client cannot show it by
mistake.

### 4. Edge cases

| What happens | What the engine does | Why |
|---|---|---|
| Two players take from one box in one tick | each gets one, in command order (§4.5.3) | "to anyone, without limit" |
| Two players press E at an empty grill in one tick, each with a raw patty | the first puts its patty on; the second's press finds it occupied and takes that patty off (onto its own empty belt, or `hands_full`) | determinism; E on an occupied grill always takes off (CD7) |
| A patty is taken off before 10 s | it is still raw; on the grill again it starts from 0 | CD7 (a): a patty is raw, fried or burnt, nothing between |
| A patty is left on the grill | fried at 10 s, burnt at 15 s, and it stays there until someone takes it off | "left longer it burns"; one patty at a time |
| A fried or burnt patty at an empty grill | `wrong_item` | CD7 (a) |
| A raw or burnt patty on a place | wrong: red, taken back with `PickUp` | the order is a fried patty; CD8 (a) |
| A second right bun on a place whose bun is green | wrong: red | the order has one bun (CD8) |
| A knife or a package at a place | `wrong_item`; a package is `two_handed` first | not an ingredient; busy hands |
| An ingredient put down (Q) or dropped near a place | it lies on the floor, unchecked | CD9 (a): only E puts it on |
| A done place | refuses more (`unavailable`); its red ones still go back with `PickUp` | the burger is done; a wrong item is never stuck |
| A box carried out of storage, or hidden | it gives wherever it stands; carried, it gives nothing (`unavailable`) | "wherever it stands"; the carrier's hands are busy anyway |
| A box carrier at a bed, the grill or a place | `two_handed` | busy hands (#679; CD3) |
| A knife holder taps a box | the knife goes to the empty belt and the ingredient into the hand; with the belt full, `hands_full` | as a pick-up (§7.1.11); CD5 |
| A downed player crawls to the grill | `not_accepted` | the allowlist (V4) |
| A raiser takes a bun | the take applies and the raise stops (`RaiseStopped`) | §9.2: an applied action stops its actor's channel |
| A client spams a box | its takes are refused `too_soon` but one per CD17's seconds (0.25 s: 4 a second); each accepted one goes to everyone; at the cap the oldest loose one comes back (CD6) | CE3, CE17 |
| The burger's last ingredient in the clock's last tick | done, and "every task done" holds if it was the last subtask | the command runs before the clock (§3.3) |
| Round ends while a patty fries | nothing more changes; the state stays until `ResetMatch` | the task state is `MatchState`'s (§9.1) |

### 5. CD items (the engineer's: game rules and taste)
Each row keeps the options and trade-offs he chose from; the last column is his answer of 2026-10-10
([PR #701, comment 6095326743](https://github.com/xperiaroco2/prime-game/pull/701#issuecomment-6095326743)): "every
recommendation stands", except where the row says otherwise.

| # | Question | Options | Trade-offs, and the failure each prevents | Decided by the engineer |
|---|---|---|---|---|
| CD1 | The burger count's maximum (#682's open item 1; default 1, the engineer's; the minimum 0, G0's shared bound, not his word) | (a) 3; (b) 4; (c) 6 | each place is a station marker in the kitchen (8 x 14 m) that the fit check demands, and a row on the board; more places crowd the counter and the board. One burger's time is the issue's playtest question | (a) 3, the recommendation: the starting value, tuned in the playtest |
| CD2 | Looks and names (#682's open item 2): the 3 buns, 3 patties (not after animals), 5 herbs, the 5 icons, the boxes, the burnt patty; the item kinds' display names (the HUD's hand item), the setting's label, the name "Cooking" and the accepted description draft | his words and the art track's looks | an item kind needs an id and a display name, and the mode check refuses an empty description, so C6 cannot land without words | **his:** the buns white, sesame and dark (rye-like); the patties light, a bit redder and redder still. **Drafted by the agents** for his approval in this PR ("make them look nice"): the task's name, the setting's label, the icons and the boxes' look, with the item names that follow from his words (§5.1). The herbs, which his answer does not name, are drafted there too (§9) |
| CD3 | Busy hands with a box and a herb (#682's open item 3) | (a) no: a two-handed item in the hand refuses every take and put, a box included; (b) a box carrier may take a herb onto the belt | (a) is #679's busy-hands rule as it stands. (b) a second exception to two-handed carrying, one more condition per rule | **(b):** a herb may go onto the belt while the hands carry a box (the belt rules allow it). Derived from it, to confirm (§9): a take from another box alike; the grill and the plates still refuse a box carrier (`two_handed`) |
| CD4 | Taking from a box and picking it up are both on E | (a) a tap of E takes an ingredient; holding E (0.4 s, a placeholder) picks the box up; (b) E takes an ingredient; another key picks a box up | (a) one key for every use, as the raise already holds E; a tap goes out on release, about 0.1 s later than a press. (b) one more key to learn for one kind of item | (a), for now. A future idea, not a rule: he may later move another action to F |
| CD5 | Taking with full hands (a one-handed item in the hand and one on the belt) | (a) refused, `hands_full`; (b) the hand item is put down in front, then the new one goes into the hand; (c) as a pick-up: the hand item is left at the source (by the box, on the grill) | (b) and (c) leave an item on the floor or the grill with every press, which a spam turns into a pile. (a) is one plain refusal, the hint showing it | **(b):** the hand item is put down on the ground (at the taker's feet, CE19), then the new one goes into the hand; for the boxes, the beds and the grill. The pile a spam leaves vanishes (CD6) |
| CD6 | What happens at an ingredient kind's cap (CE3's technical bound: 32 items per kind, a placeholder) | (a) the oldest loose one of that kind (on the ground, a red one on a plate included) comes into the taker's hand from where it lay; (b) the take is refused; (c) a loose ingredient vanishes after N s on the ground | (a) the box never runs dry, so "without limit" holds for every player; a loose item somewhere vanishes, which only a spam makes happen. (b) a dissident who spams one kind blocks it until someone gathers the pile. (c) a patty left by the door vanishes in normal play | **(c):** an ingredient left lying vanishes after N s (60, a placeholder, "not a decision"). Spamming takes is fine with him ("if it's fun for them to cover the map in buns, why stop them"): no game rule limits the takes. Against hostile clients a technical bound stays, the manager's: CE17's flood guard and CE3's cap per kind, far above play |
| CD7 | The grill's edges | (a) only a raw patty goes on; taken off early, it is still raw and starts from 0 next time; E on an occupied grill takes the patty off; a burnt patty stays until taken off; (b) as (a), but a patty keeps its frying time when taken off; (c) as (a), but a fried patty may go back on and burns 5 s later | (b) a fourth state per patty (half fried), shown nowhere. (c) a fried patty on the grill to keep it from thieves, at the cost of a burn timer more | (a), the recommendation |
| CD8 | The plate's edges | (a) anything wrong goes on red and comes back with `PickUp`: a raw or burnt patty, a second right bun on a green slot, a wrong kind; a done place refuses more; anything not an ingredient is refused (`wrong_item`); (b) as (a), but a raw or burnt patty is refused outright | (a) one rule for every wrong ingredient, which the red outline explains. (b) a refusal with no outline, which tells less | **(b):** a raw or burnt patty is refused outright (`wrong_item`, it stays in the hand); every other wrong ingredient goes on red |
| CD9 | How an ingredient gets onto a plate | (a) only E on the place; an ingredient put down (Q) or dropped near it lies on the floor; (b) any ingredient that comes to rest at the place counts, as a package in its circle | the host knows a place by its use spot on the floor in front of the counter (GE11), not the plate's own spot. With (b) a patty put down at the counter's foot counts as on the plate, drawn where it is not | (a), the recommendation |
| CD10 | How a place shows which order is its | (a) each place carries a number; the board lists the orders by place number; (b) the order's ticket also hangs over its place | (b) the same picture twice, a second view per order. (a) one glance at the board, then the number | (a), the recommendation |
| CD11 | How the orders are drawn | (a) each order's bun, patty and herb independently: two orders may share a kind; (b) no two orders alike | the engineer's own remark: carrying a box to the kitchen is "worth it when several orders need the same kind" | (a), the recommendation |
| CD12 | Where the orders show | (a) only on the order board; the task screen shows burgers done of N; (b) the task screen lists the orders too, the herb as its icon | (b) nobody needs to go to the kitchen to read the board, which the rules put there; the herb icon still needs the greenhouse | (a), the recommendation |
| CD13 | The herb beds | (a) five beds, one herb each, always the same, the plant showing which; (b) the herbs move between the beds each round | (b) two shuffles a round (the code and the beds) for one herb run. (a) the code is the round's puzzle | **(b):** the herbs are shuffled among the beds each round (CE6, CE8) |
| CD14 | Sounds and the grill's timer | sounds: (a) a click on each take and put, a sizzle while a patty fries, a ding when it is fried, a hiss when it burns, a chime for green and a buzz for red, a sound when a burger is done; (b) fewer. The timer: (i) a ring over the grill in the world, filling to fried and then to burnt, as in Overcooked; (ii) only the patty's look and the sounds | a player without sound, or out of earshot, misses the 5 s window with (ii); (i) is drawn at the grill only, depth-tested, seen by whoever looks at it | (a) and (i), the recommendation; placeholder blips built in code, as `WorldSounds` makes today's, until his CC0 files arrive with their `docs/credits/` entries |
| CD15 | Where Cooking plays, and how many task types a match deals | the Generator's GD7: (a) in the base mode with placeholder markers on the greybox; (b) the base mode on House only, banned by hand elsewhere; (c) a per-map draw; and `tasks` every type or drawn | as GD7. Cooking needs 11 tags on a map (5 station kinds, 6 boxes): 17 markers with CD1's 3 places, so (a) costs the greybox that many placeholder markers and one more task every match | **as GD7** ([PR #695, comment 6095326452](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6095326452)): the chains play on the House, the map being built for them, in the base mode with the station scenes (GD7 (a), with (i): every type every match, 4 with Cooking); the flat greybox stays the bots' map. The match clock for four chains stays his, as GD7 leaves it |
| CD16 | How near and how high a player must be to use a station; the boxes' reach | the stations' `radius_m` and `height_m`; the box rule's `InReach` | as the Generator's GD6: too small refuses a player at the counter, too large lets one use the grill from the deckchairs. Today: the pick-up reach is 2 m | the recommendation: 2 m and 2 m for every cooking station, the boxes' reach 2 m as a pick-up's; placeholders, tuned in the playtest |
| CD17 | The shortest time between two takes from a box or a bed by one player (CE17's cooldown) | (a) 0.25 s; (b) 0.5 s; (c) 0.1 s | a player hammering E for herbs may feel much more than about 0.2 s as a stuck key; much less bounds little (0.1 s allows 10 takes a second) | **technical now:** he sets no game limit on takes (CD6), so CE17's cooldown is the manager's flood guard against hostile clients, not a game rule; 0.25 s, a placeholder |

#### 5.1 The drafts (CD2), for the engineer's approval
His words are the buns and the patties; he asked the agents to draft the rest "so it all looks nice". Each row is a
draft for his approval in this PR; C6 and C7 use what he approves, or these drafts marked "not a decision" until he
does. Nothing is named after an animal.

| What | Draft | Why this draft |
|---|---|---|
| The task's name | "Cooking" | one word beside "Delivery", and the lobby label reads "Burgers (Cooking)" as Delivery's reads "Packages (Delivery)" |
| The subtasks setting's label (`SettingSpec.display_name`) | "Burgers (Cooking)" | Delivery's pattern: what the number counts, then the task |
| The buns (his words) | white: pale and soft, a light golden top; sesame: a golden-brown top dotted with seeds; dark: rye-like, dark brown and matte, a dusting of flour | told apart by colour and by the seeds, in a hand and on the board |
| The patties (his words) | raw: light (pale pink-beige), red ("a bit redder"), deep red ("redder still"); fried: each keeps its hue under a brown crust with grill stripes (golden brown, red-brown, dark mahogany); burnt: one patty, black and cracked | the order shows the fried look and the box the raw one; the shared hue ties them, so a player matches a box to an order |
| The item names (the HUD's hand item) | "White bun", "Sesame bun", "Dark bun"; "Raw light patty", "Raw red patty", "Raw deep red patty"; fried: "Light patty", "Red patty", "Deep red patty"; "Burnt patty"; the boxes "Box of white buns" to "Box of deep red patties" | the fried one has the plain name: it is what the order asks for |
| The five icons (the order's herb) | a sun, a moon, a star, a drop and a heart: white silhouettes, each on a disc of its own colour | told apart by shape alone (a colour-blind player, the greenhouse's light), and none looks like a plant, so an icon hints at no herb |
| The boxes | a bun box: an open wooden bakery crate, three of its buns showing on top, its bun painted on the front; a patty box: a white cool box, its lid in its patty's raw colour, its patty pictured on the front | a box says what it gives from across the room, and a hidden one is known at once when found |
| The herbs (not in his answer, §9) | basil (broad, bright green leaves), dill (feathery yellow-green fronds), rosemary (dark green needles on a woody sprig), chives (thin green tubes with a purple flower), mint (round, serrated, light green leaves) | five silhouettes that read apart in a hand, on a bed and on the herb board; kitchen herbs a player knows |

### 6. CE items (technical: the manager decides and reports)

| # | Choice | Options | The failure it prevents | Decision |
|---|---|---|---|---|
| CE1 | Taking from a box | (a) `Interact` names an item: G1's intent gains an optional `item` field (its `station` becomes optional; exactly one of the two, else `bad_args`), and the targeted item's kind owns its rules, `ItemKind.target_actions` (rules on `Interact`, applying while the item lies on the ground and is the target), tried before the role's and the mode's, as GE2 does for a station's kind; (b) a new intent `TakeFrom(item)`; (c) `PickUp` on a box gives an ingredient, with a flag to take the box itself; (d) a box as a station that moves with an item | (b) one intent per mechanic, which GE1 (c) refused. (c) changes what `PickUp` means for one kind and the flag for every client. (d) a station's position is fixed (`StationState`), and a carried box would need a station that follows a hand. `ItemKind.actions` cannot hold it: they apply while the item is in the hand (§9.2) | (a); an intent naming an item is routed only to that item's kind's `target_actions`: the role's and the mode's `Interact` rules are never tried for it (they are written for station targets), and an unknown item, or a kind with no matching `target_actions` (a bun, a package or a knife on the ground), is refused `nothing_to_do`, as #679 does for a station with no rule. If G1 has not landed when C1 starts, the manager may fold the field into G1, so the protocol goes up once |
| CE2 | The item source | (a) `GiveItem(kind, max_items)`, an effect: a new item of `kind` spawned at the rule's target (the box's rest position, the bed's marker) and taken into the actor's hand in the same command: `ItemSpawned` (no station), then `ItemPickedUp` (with `belted`); no `item_rested`, since it never rests; (b) a new `ItemGiven` event; (c) the source spawns the item on the ground and the player picks it up with a second press | (b) a new wire row and client fold for what two existing events already say. (c) two presses for one take, and an item on the floor with every press | (a); the photo task (#687) may reuse it (a station that gives an item) |
| CE3 | Items without limit | (a) a cap per given kind, `GiveItem.max_items` (32, a placeholder, "not a decision"), with CD6's answer at the cap; `Cooking.check` refuses a cap below twice the mode's maximum of players plus the subtasks maximum plus 1, so the hands, the green slots and the grill can never hold every item of a kind; (b) no cap | item ids are `u16`: a take needs room in the hands, so a spammer alternates a take and a put-down, about 10 takes a second under the bucket's 20 intents (4 under CE17's cooldown); one such peer uses up the 65,535 ids in under 2 hours (4.5 under the cooldown) and ten of them in about 11 minutes (27), after which the wire cannot name a new item; long before that every client draws thousands of items | (a); the recycled item is the loose one with the lowest id (deterministic, no new field). "Loose" means on the ground, neither locked nor flying (#37's proposed throw) nor held; with no loose item of the kind at the cap (every one held, locked or in flight, which the bound above makes impossible today but a later state may not), the take is refused `unavailable`, deterministically, and nothing is spawned: `GiveItem` never asserts and never exceeds the cap. A unit test in C1 |
| CE4 | A patty's raw, fried and burnt | (a) its kind changes: `Items.change_kind(item, kind)` and a public `ItemChanged(item, kind)`, the item keeping its id, place and holder; the task's data lists the fried kind of each raw one and the one burnt kind; (b) a stage per item in the task state, with its own event; (c) a new field on `ItemState` | (b) the HUD's hand item, the plate's check and the item's look would read the task state as well as the kind. (c) a field every item carries for one chain. With (a) the order names a fried kind and the plate compares kinds; the display name and the look follow the kind for free | (a); the photo task (#687) may reuse it (a blank sheet becoming a photo) |
| CE5 | Items on stations | (a) a patty on the grill and a right ingredient on a place are locked there (`ItemState` locked, at the station's position, as a delivered package), so no `PickUp` takes them; a wrong ingredient lies on the ground at the place's position, interactive, so `PickUp` takes it back, and raises `item_rested` with a new cause, `on_station`; one event says where each went: `GrillLoaded(station, item, fried, burnt)` and `IngredientPlaced(item, station, right)`, everyone; taking off or back is `ItemPickedUp`; (b) every item on a station on the ground; (c) every item on a station locked, a red one given back by E on the place | (b) `PickUp` would take a green ingredient back, which the rules forbid, and a patty off the grill without the grill knowing. (c) a second take-back path beside `PickUp`, with the place choosing which red one. The host's position of an item on a station is the station's use spot; the client draws it on the scene's plate or grate (CE15) | (a) |
| CE6 | The station kinds | (a) the order board and the herb board as display stations (a kind with no rule: E gives `nothing_to_do`), placed by the deal so the fit check demands them and the client finds their scenes (GE11); one `place` kind; one `grill` kind; one kind per herb bed, each with its own spawn tag and its own `GiveItem`; (b) one bed kind, bed i giving herb i in level order; (c) boards found by the client in the level, not stations | (b) couples the level's art (which plant grows on which bed) to the order of a list in the data, and needs an event to say which herb a bed gives. (c) a map without a board would still deal Cooking, and nothing could decode the icons | (a) |
| CE7 | The boxes | (a) six box item kinds, each with its own spawn tag (one marker each on House, on the shelf and in the freezer), spawned by the cooking deal; (b) `SpawnItems` in the base mode's deal row | (b) boxes in every match, Cooking drawn or not | (a) |
| CE8 | The deal's order and ids | §2.1: stations in the order board, herb board, grill, beds, places order; places on the first N `place` markers in level order, order i on place i; three RNG purposes (`cooking_boxes`, `cooking_orders`, `herb_code`, provisional ids; the stations take none, each kind having exactly one marker); events `StationPlaced` per station in id order, `ItemSpawned` per box in id order, `OrderPosted` per order in place order, `HerbCode`; then `DealTasks`'s `TaskState` and `TaskProgress` | a purpose of its own shifts no other part's draws (§3.3); random places would change nothing a player sees but the numbers on the board | as stated |
| CE9 | The board events and their audience | (a) `OrderPosted(station, bun, patty, icon)` and `HerbCode(herbs)` carry exactly what each board shows, the order an icon index and never the herb; both everyone, as the Generator's GE6 (a); (b) one event with the orders' herbs; (c) the host filters by place | (b) a client fold that draws the order board holds the herb, and one slip shows it. (c) as GE6 (b): a new audience kind and per-peer state by distance, which ARCHITECTURE §10 keeps for when a human asks | (a); `HerbCode`'s list and the ids count in `WireBudget` (§4.3) |
| CE10 | The grill's timing | (a) the patty's fried and burnt ticks in the task state, set when it goes on; `Cooking.tick` (through `TaskTicks`) changes its kind when each comes; `GrillLoaded` carries both ticks, so the client draws the ring (CD14) and expects the changes without rounding seconds itself (ZE4's `needed`); no rate window; (b) reuse `ZoneProgress` for the frying; (c) an event every second while it fries | (b) `ZoneProgress` has one threshold and no item; the burn needs a second. (c) reliable events for a clock the client can draw. No window: the grill, the plates and `ItemChanged` emit one event per accepted intent (a load, a take-off, an ingredient put on) or one of the grill's two changes per patty, like the Generator's `SwitchChanged`, which GE8 (b) leaves without one. GE8 (b) windows what emits two events per intent at the bucket's rate; here that is a take (`ItemSpawned`, then `ItemPickedUp`), which CE17 bounds instead | (a) |
| CE11 | Rejection reasons | (a) two new reasons, `wrong_item` (the station does not take that item) and `hands_full` (CD5); `empty_hand`, `unavailable`, `two_handed`, `out_of_reach`, `blocked` reused; the grill's and the place's come from `Cooking.use_problem`, which G1's `StationUsable` passes on. `StationUsable`'s one `rejection_reason()` cannot list several, so C1 extends G1's API with `TaskType.use_reasons()` (the base returns [`unavailable`]; `Cooking` lists its own), and the mode check tests each listed reason against the wire alphabet; (b) `unavailable` for everything | each reveals only what is public: what the sender holds and what lies on the station. (b) a client hint that cannot say why | (a) |
| CE12 | The task state | (a) `Cooking.State`: per place its station id, the order's bun, raw patty kind and herb, its three slots (the right items, or none) and done; the grill's patty, its fried and burnt ticks; the code; the station ids of the boards and beds; red ingredients are not tracked: they are ground items, and only the green slots decide; (b) the per-part state table | (b) splits one task over two homes, where §9.1 names the task state | (a) |
| CE13 | The order of events | a take: `ItemSpawned`, `ItemPickedUp`. A place: `IngredientPlaced`, then on the third right one `Tasks.subtask_done` (`TaskState`, `TaskProgress`, `subtask_done`), as Delivery sends `PackageDelivered` first. The grill: `GrillLoaded`; in the tick, `ItemChanged` per change | a `TaskState` before the plate shows the burger; a sound before its state | as stated |
| CE14 | The mode checks and the demands | `Cooking.check`: every station kind set, spawn tags distinct (ZE3 across the mode); one bed kind per herb, each bed's rule a `GiveItem` of its herb; `buns`, `raw_patties`, `herbs` non-empty; `fried_patties` as long as `raw_patties`; `burnt` set; every list's kinds one-handed and distinct, the boxes two-handed, each box's `target_actions` a `GiveItem` of one bun or raw patty kind; at most 255 herbs (the icon is a `u8`); `fry_seconds` and `burn_seconds` within 0.05 to 600, their neutral defaults outside; the subtasks setting declared, whole, minimum at least 0 (G0); non-empty RNG purposes; CE3's cap. Demands: exactly one marker each for the boards, the grill and every bed kind (an exact count, as GE10, so the fit check refuses a second grill or board scene that would stand unused), at least N `place` markers (N the setting; an unused place hides its plate, CE15), at least one marker per box kind's tag (the box drawn among them, `cooking_boxes`); no colours | a setting of 4 on a kitchen with 3 places deals an order with no plate; a bed nobody can use; a box that gives a fried patty | as stated |
| CE15 | How the level binds them | the Generator's GE11 (a): each station scene is the device with its use-spot `Marker3D` in its `spawn_<tag>` group on the floor in front, clear of its collision, and named nodes the client drives: the order board's rows, the herb board's pairs, the grill's grate and ring, the place's `Plate` (hidden until the place is placed, so unused places show a bare counter) and its number; `herb_beds.tscn` holds the five beds, each with its use spot in its own group (House has one `HerbBeds` point); the box shelves (`bun_shelf.tscn` at `Buns`, `freezer.tscn` at `Meat`) hold one item marker per box kind, which are item markers, not stations; no script in `levels/` | a plate drawn where the host's use spot is not; five bed scenes for one point | as stated |
| CE16 | The basement and the scenarios' flat world | (a) nothing: every cooking station stands on level 0 (the kitchen, the chill zone, the greenhouse), and the box markers in storage (Y -3.2) are item markers, which `MarkerReader` does not snap; (b) depend on G3 | `FlatWorldQuery` finds no floor below y = 0 only for snapped station markers (GE12) | (a): Cooking does not need G3 |
| CE17 | The rate of takes | (a) a `Cooldown` cost (`core/combat/cooldown.gd`, key `cooking_take`, a provisional id) in every box's and bed's `GiveItem` rule: one take per player per CD17's seconds, else `too_soon`; (b) ZE4's 5-tick window, which cannot hold back an item a player already holds; (c) the bucket alone | (c): a take emits two reliable events to everyone (`ItemSpawned`, then `ItemPickedUp`) and needs room in the hands, so a spammer alternating a take and a put-down sends about 30 events a second to every player, each new item one more for every client to draw: more than today's `PickUp` and `PutDown` spam (20 a second), and the rate GE8 rejects for the Generator's button. (a) at 0.25 s: 4 takes and 4 put-downs a second, 12 events, under today's 20; `too_soon` reveals only the sender's own timing, as the knife's does; the cost exists, so nothing new in `core/` | (a); the seconds are CD17 |
| CE18 | Item kinds that no deal places | 15 of the 21 kinds (the buns, the raw, fried and burnt patties, the herbs) are only given (`GiveItem`) or changed into (`Items.change_kind`), never put on a marker, yet main's `ItemKind.check` (`core/content/item_kind.gd`) refuses an empty `spawn_tag`. (a) `spawn_tag` becomes optional: `ItemKind.check` stops requiring it, and every part that places a kind on markers refuses one without a tag in its own check (`SpawnItems`, `Delivery`'s package, `Cooking`'s boxes), so the refusal moves to where a tag is used; (b) each given-only kind carries a placeholder tag that no demand ever asks for | (b) 15 tags that name no marker, which a later map author would read as markers to place, and a mistyped real tag would pass unnoticed among them. (a) the existing test of the empty tag moves to the placers' checks: a changed expectation, named in C1's PR for the engineer's approval (never a dropped one) | (a); every one of the 21 kinds is listed in the mode's `item_kinds`, which the client resolves `kind` ids through, `WireBudget` sizes them from (`server/wire_budget.gd`) and ModeCheck walks for their rules (so the boxes' `target_actions` are checked); `Cooking.check` refuses a kind it names that the mode does not list |

### 7. Testing
- **Unit tests** (C1 to C4; fixtures only, never `content/`, ARCHITECTURE §9.6): `Interact`'s item routing (the
  target's `target_actions` before the role's and the mode's; a knife in hand changes nothing), each refusal and its
  order (§2), the allowlist (downed, dead); `GiveItem` (the hand, the belt, `hands_full`, the cap and CD6's recycle,
  no `item_rested`); CE17's cooldown (one player's takes on 100 ticks in a row give at most 100 / 5 + 1 items at
  0.25 s, the rest refused `too_soon`); `Items.change_kind`; the deal (markers, ids, the three purposes, orders and code from a seed, N = 0, a
  short map logging a match error); every row of §4; the grill's ticks (fried at 200, burnt at 300, taken off at 199
  still raw); the plate (right, wrong, a third right one completing the subtask once, a done place); the demands and
  the fit check; CE14's checks; the order of events (CE13); `ResetMatch` clearing it all; the wire rows' round trips.
- **The role-swap check** (C4): the same seed and commands with two players' forced roles swapped emit identical
  `OrderPosted`, `HerbCode`, `IngredientPlaced`, `GrillLoaded`, `ItemChanged`, `TaskState` and `TaskProgress` streams.
  Planted once (a place refuses dissidents), it fails; reverted.
- **The leak test's lists** (C3, C4): the five events join the task events every player receives alike (`LeakCheck`,
  `ScenarioInvariants`). The lists alone prove nothing until a run emits the events: the leak plant waits for C9's
  scenario.
- **The chaos bots** (C1, rows that need no deal): the allowlist row, the malformed frames (an item id 0xFFFF,
  truncated, trailing bytes), `Interact` with both fields or with neither (`bad_args`), and with an unknown item
  (`nothing_to_do`, CE1); the hostile peer gets only its `Rejected`s.
- **Scenarios that play Cooking** (C9, after C6; content, provisional, the engineer approves the scripts; the
  Generator's G8 does the same): the scenario target gains an item by kind and index (`ScenarioTarget`, in both
  runners), and greybox scenarios play a take from a box, a frying, a right and a wrong ingredient on a plate, a
  burger done and a cap recycle; one of them runs in `bots`, so `OrderPosted`, `HerbCode`, `GrillLoaded`,
  `IngredientPlaced`, `ItemChanged`, a mid-round `ItemSpawned` and `Interact(item)` cross the real wire. The leak plant
  in that scenario: `HerbCode` or `IngredientPlaced` declared to the host's peer only fails `LeakCheck` and
  `ScenarioInvariants`; planted once, reverted, recorded in the PR. The chaos rows against dealt boxes and stations:
  a take out of reach (`out_of_reach`), a burst of takes (refused `too_soon` but one per CD17's seconds, CE17), and no
  more than the cap of items of a kind ever existing.
- **Integration tests on House** (C8; bots do not play House, ARCHITECTURE §9.7): `Match` over `HostWorldQuery` with
  House's level: a player takes a bun and a patty from the boxes in storage, fries the patty at the grill, picks the
  order's herb at its bed and puts all three on the order's place: the burger is done; a player at every use spot
  passes `AtStation` and `StationInSight`; one behind a wall within a radius is refused `blocked`; every station and
  box marker reads without an error.
- **The client** (C7): the folds (pure), the board and plate views, the ring's fill (pure), the tap and hold, a `shot`
  preview of each station.
- **Green** (#605): `verify` (lint and check) locally, then CI's full suite on the PR, for each issue of §8.

### 8. The split
Sizes as in M6 and M7: S up to about 400 changed lines, M up to about 900. Base: `main`. Effort: high for `core/`,
`net/` and `tests/harness/`. Every issue comes after #679's PR; G1, G4's conventions and G5's allowlist are shared.

| Issue | Labels | Goal | Acceptance | Files | Depends on | Size |
|---|---|---|---|---|---|---|
| C1 | needs-engine, area:core, area:net | `Interact` naming an item, and the item source | CE1 to CE3, CE11: `Interact`'s optional `item` field (exactly one of `station` and `item`, else `bad_args`) with its wire row and a protocol bump; `ItemKind.target_actions` routed first for an intent naming an item, with ModeCheck's handler, trigger and placement checks; `GiveItem` (cap, CD6's recycle) and `HandsHaveRoom` (`hands_full`); the reasons `wrong_item` and `hands_full` in the wire alphabet; CE18's optional `spawn_tag` (`ItemKind.check`, the placers' checks, the moved test named in the PR); `TaskType.use_reasons()` (base: [`unavailable`]), with ModeCheck checking each listed reason against the alphabet (an extension of G1's API, CE11); §7's unit tests and C1's chaos rows; ARCHITECTURE §4.1, §4.3.2, §9.2's owner table, §9.4.1, §9.4.2, and §4.2's `ItemSpawned` row ("or given mid-round by `GiveItem`, then not in spawn-point order") and `ItemPickedUp` row (`GiveItem`, a CD6 recycle from anywhere on the map) with `ItemSpawnedEvent`'s class doc (`core/events/item_spawned_event.gd`, "placed by the deal") | `core/match/intents.gd`, `core/match/match.gd` (`_find_action`), `core/content/item_kind.gd`, `core/content/task_type.gd`, `core/content/mode_check.gd`, `core/items/` (`give_item.gd`, `hands_have_room.gd`, `items.gd`), `net/messages/`, `core/match/phases/join_rules.gd` (the version), `tests/harness/chaos/`, `tests/unit/items/`, `tests/unit/content/`, `docs/ARCHITECTURE.md` | G1; the engineer's CD5, CD6 (each revertible: C1 may start on the recommendations) | M |
| C2 | needs-engine, area:core, area:net | An item that changes kind, and items on stations | CE4, CE5's moves: `Items.change_kind` with the public `ItemChanged(item, kind)` and its wire row; the `Items` moves that lock an item at a station and lay one on the ground at a station (cause `on_station`), and take a locked one into a hand (`ItemPickedUp`); unit tests; ARCHITECTURE §9.3 (Items), §4.2 (`ItemChanged`; `ItemPickedUp` from a locked item on a station), §4.3.4, §4.3.5's list of `Items` causes, §9.2's `item_rested` fact row (the cause `on_station`), §5's item events | `core/items/items.gd`, `core/events/`, `net/messages/`, `core/match/phases/join_rules.gd`, `tests/unit/items/`, `tests/unit/net/messages/`, `docs/ARCHITECTURE.md` | none | S |
| C3 | needs-engine, area:core, area:net | The Cooking task type: its data, deal and board events | CE6 to CE9, CE12's state for the deal, CE14: `Cooking extends TaskType` with its lists, station kinds, seconds, subtasks setting and three RNG purposes; §2.1's deal; `OrderPosted` and `HerbCode` with their wire rows and `WireBudget` cases; the demands and the fit check; the leak lists; unit tests; ARCHITECTURE: Cooking's entry beside Delivery's (§9.5), §4.2, §4.3.4, §5's task events, §3.3's RNG purposes | `core/tasks/cooking.gd`, `core/events/`, `net/messages/`, `server/` (`WireBudget`), `tests/harness/scenario_invariants.gd`, `tests/harness/bots/leak_check.gd`, `tests/unit/tasks/`, `tests/fixtures/tasks/`, `docs/ARCHITECTURE.md` | G1 (station kinds owning rules); C1 (`GiveItem` and `ItemKind.target_actions`, which CE14's checks read); release/m7 in main (ZE3); the engineer's CD11, CD13 | M |
| C4 | needs-engine, area:core, area:net | The grill and the places | §2.4 and §2.5 with CD7, CD8, CD9's recommendations: `Cooking.use_problem` and `use_station` for the grill and the places, `Cooking.tick` (CE10), `GrillLoaded` and `IngredientPlaced` with their wire rows, the place done and `Tasks.subtask_done` (CE13); §4's rows; the role-swap check with its plant; ARCHITECTURE §9.5's entry completed, §9.4.5's `TaskTicks` row, §4.2's `ItemPickedUp` row (a patty taken off the grill) | `core/tasks/cooking.gd`, `core/events/`, `net/messages/`, `tests/unit/tasks/`, `docs/ARCHITECTURE.md` | C1 (the reasons `wrong_item` and `hands_full`, `use_reasons()`), C2, C3; the engineer's CD7, CD8, CD9 (each revertible) | M |
| C5 | area:level | The cooking station scenes, in place of the House markers | CE15: `levels/stations/order_board.tscn`, `place.tscn`, `grill.tscn`, `herb_board.tscn`, `herb_beds.tscn`, `bun_shelf.tscn`, `freezer.tscn`: greybox looks with `levels/kit/` materials, collision on layer 1, use-spot markers in their groups (tags provisional, "not a decision"), the named nodes the client drives; instanced in the kitchen (the board and CD1's number of places), storage, the chill zone and the greenhouse in place of `OrderBoard`, `Buns`, `Meat`, `Grill`, `HerbBoard` and `HerbBeds`, at house-map §6's points; `levels/CLAUDE.md`'s spawn points gain the tags; a `shot` of each room; provisional, named in the PR for the engineer's approval | `levels/stations/`, `levels/house/rooms/` (kitchen, storage, chill zone, greenhouse), `levels/CLAUDE.md` | G4 (the use-spot convention); the engineer's CD1 (the place count) | M |
| C6 | area:content | Cooking in the base mode | `content/tasks/cooking.tres` with its station kinds and their rules (CD16's numbers), 21 item kinds (3 buns, 3 raw and 3 fried patties, 1 burnt, 5 herbs, 6 boxes with their `target_actions`) in `content/items/`, all 21 listed in the base mode's `item_kinds` (CE18), only the boxes with a spawn tag, CD2's words or placeholders; the base mode: the type, its subtasks setting (0 to CD1's maximum, default 1), `Interact` from the living in Round (if G5 has not added it), `tasks` per CD15; the greybox's placeholder markers if CD15 (a); the MVP's scenarios ban Cooking; every test that loads the base mode still passes, each changed expectation named in the PR; provisional files named for the engineer's approval | `content/tasks/`, `content/items/`, `content/modes/base_mode.tres`, `levels/greybox/greybox.tscn`, `content/scenarios/`, `tests/harness/chaos/`, `tests/harness/perf/` (once the base mode deals Cooking, the chaos and perf harnesses deal it with its defaults: their waits scoped to Cooking, or Cooking banned there, in this change, as the Generator's G5), `tests/unit/content/`, `tests/integration/`, `tests/scenarios/`, `docs/ARCHITECTURE.md` (§9.5, §9.6) | C1, C3, C4, C5; G5; the engineer's CD1, CD2, CD15, CD16, CD17 | M |
| C7 | area:client | The client's view | the E hints and intents: over a usable cooking station `Interact(station)`; over a box a tap (`Interact(item)`) or a hold (`PickUp`, CD4); none where the host would refuse what the client knows (a full belt, a done place); the order board's rows (place number, bun and patty pictures, herb icon) and the herb board's pairs drawn on their scenes (`Label3D`, `Sprite3D`), in the world, depth-tested, on no screen (CD12); the plate's items with a red or green outline (an inverted hull: `GeometryInstance3D.material_overlay`, a `StandardMaterial3D` with `grow`, `cull_mode` front, unshaded); the grill's patty and the ring (CD14) extrapolated from `GrillLoaded`; the placeholder looks of the 21 item kinds (`item_view.gd`); the sounds (CD14) through `SoundChooser` and `WorldSounds`, within 12 m (`AudioStreamPlayer3D.max_distance`), muffled behind the level (M5-7); the M4 render checklist, the PR routed to `netcode-security-reviewer` too; `shot` previews; the fold handles a mid-round `ItemSpawned` and an `ItemPickedUp` of a distant item (a CD6 recycle: the item leaves where it lay, its pick-up sound plays at the taker, within 12 m); ARCHITECTURE §4.7 | `client/net/client_model.gd`, `client/world/`, `client/ui/`, `tests/unit/client/`, `tests/integration/client/`, `docs/ARCHITECTURE.md` | C1 to C5; G6 (`TargetChoice` over stations); C6 for a playtest; the engineer's CD4, CD12, CD14 | M |
| C8 | needs-engine, area:core | Integration tests: Cooking on House | §7's House tests in the host's real world | `tests/integration/levels/`, `docs/ARCHITECTURE.md` (§9.7's House line) | C4, C5, C6 | S |
| C9 | area:content, area:tooling | Scenarios that play Cooking, its leak plant | §7's Cooking scenarios on the greybox (provisional, the engineer approves the scripts), one of them in `bots`; an item target in the scenario step (`ScenarioTarget` by kind and index) in both runners, with a `scenario_runner_test` case; the leak plant in that scenario, planted once and reverted, recorded in the PR; §7's chaos rows against dealt boxes and stations; the scenario runner's and `bots`' tests still pass | `content/scenarios/`, `core/content/scenario/`, `tests/harness/` (the runners, the chaos bots), `tests/scenarios/`, `docs/ARCHITECTURE.md` (§9.7, §4.6.5.3) | C1, C4, C6 (Cooking dealt on the greybox: CD15 (a), else a fixture mode); G8's step | S |

### 9. Needs the engineer
His answers of 2026-10-10 settle CD1 and CD3 to CD17 (§5). Left, one batched question for his approval in this PR;
each is revertible, and C6 and C7 proceed with the recommendation, marked "not a decision", until he answers:
1. **The drafts of §5.1** (CD2): the task's name, the setting's label, the item names, the icons and the looks of
   the buns, the patties and the boxes. (a) as drafted; (b) his changes. Recommended: (a).
2. **The herbs** (CD2): his answer names no herb. (a) the five drafted in §5.1 (basil, dill, rosemary, chives,
   mint); (b) his own five. Recommended: (a).
3. **How far CD3 (b) reaches** (derived from his answer and its reason, "the belt rules allow it"): (i) a box carrier
   may also take from another box onto the belt, the same rule for every source; (ii) a box carrier whose belt is
   full and who takes a herb puts the box down at the feet and gets the herb in the hand, CD5 (b) as it reads, rather
   than a refusal; (iii) the grill and the plates still refuse a box carrier (`two_handed`), since their one rule
   also puts an item from the hand. Each: as stated, or the other way. Recommended: as stated.

The numbers he left as placeholders (CD6's 60 s, CD16's 2 m, CD17's 0.25 s, CE3's cap of 128) are tuned in the
playtest; none blocks an issue.

## Alternatives
- **A new intent for boxes** (CE1 (b)) or **`PickUp` with a flag** (CE1 (c)): one intent per mechanic, or one verb
  meaning two things for one item kind.
- **A box as a moving station** (CE1 (d)): stations stand where the deal put them.
- **A new event for a given item** (CE2 (b)): `ItemSpawned` and `ItemPickedUp` already say it.
- **No cap** (CE3 (b)): the item ids run out, and the clients draw every spammed item.
- **A cooking stage per item** (CE4 (b), (c)): state beside the kind, read by the HUD, the check and the look.
- **One ingredient item kind with a variant field**: fewer files, but a new item field on the wire and in the HUD,
  where 21 kinds reuse `ItemSpawned`'s `kind` and the display name as they are.
- **Every item on a station on the ground** (CE5 (b)): `PickUp` would take a green ingredient back.
- **One bed kind bound by order** (CE6 (b)): the level's plants and the data's list must agree by position.
- **Boxes in the base mode's deal** (CE7 (b)): boxes in matches without Cooking.
- **The orders' herbs on the wire** (CE9 (b)): an honest client one slip from showing the code at the kitchen.
- **`ZoneProgress` for the grill** (CE10 (b)): one threshold where the grill has two.
- **The bucket alone for takes** (CE17 (c)): about 30 reliable events a second from one spamming peer to everyone.
- **Placeholder tags for the given-only kinds** (CE18 (b)): 15 tags that name no marker.

## Consequences
- ARCHITECTURE §9.8 gains Cooking's row and §10 its questions; GDD §8 gains its section beside the Generator's and
  the zone task's; house-map §10 records the counts the engineer decided (3 buns, 3 patties, 5 herbs).
- When C1 to C4 land, ARCHITECTURE gains `Interact`'s item target in §4.1 and §4.3, the item kind's `target_actions`
  as an owner in §9.2, `GiveItem` and `HandsHaveRoom` in §9.4, `Items.change_kind` in §9.3, Cooking's entry in §9.5
  and its events in §4.2, §4.3.4 and §5, with their `Built in` lines.
- The protocol version goes up in C1, C2, C3 and C4; kind numbers and versions are taken when each lands, never from
  here.
- `GiveItem`, `ItemChanged` and the items on stations are generic: the photo chain (#687: a printer that gives a
  photo, a board that holds it) and the car repair (a part from a shelf) can reuse them as data.
- With CD15 (a) every map of the base mode needs the 15 cooking tags; House has them once C5 lands, the greybox in C6.
- The meat run stays as long as house-map §7 measures it (135 m, about 30 s walking): nothing here shortens it.
