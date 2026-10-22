# Delivery by meaning (#683): items carried to their own places instead of colour-matched circles

- **Status:** Accepted; built in part, see the issues (amended 2026-10-22, #1243). First written as: Proposed on 2026-10-10; the engineer answered DD1 to DD9 the same day and approved the design
  ([PR #713, comment 6100696677](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6100696677)); DD10,
  raised by the review after, he answered on 2026-10-11
  ([PR #713, comment 6108665402](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6108665402)): the
  tutorial deals no task (§5, #825). Nothing here is built, and nothing will be until the engineer says so: for now
  the track only designs
  ([PR #695, comment 6096108206](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096108206); §8).
  The direction is the engineer's: #683's "Decided" list (chat with the game-design manager session, 2026-10-10:
  Delivery no longer goes by colours, and the mechanic changes, not only the text) and his answer on #683,
  [comment 6089404833](https://github.com/xperiaroco2/prime-game/issues/683#issuecomment-6089404833), with his own words
  relayed in [comment 6090227509](https://github.com/xperiaroco2/prime-game/issues/683#issuecomment-6090227509): storage
  holds different items, each to be carried to its own location by what it is ("wine to the living room, maybe oil to
  the garage, something to the garden"; "by the location's sense, not by colours"). The DD items are game rules and
  taste he left open: they are his (the [trust ADR](2026-10-04-trust-based-autonomy-gated-merge-into-main.md)'s tier
  (c)), each with options and a recommendation. He answered DD1 to DD8 on 2026-10-10 in
  [PR #713, comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718): every
  recommendation stands except DD4, which he answered otherwise (by meaning alone, and no marker through walls any
  more); the garden's and the terrace's items and the description were drafted here (§5.1). His later answers on the
  House track touch Delivery too (§9): the shared task total goes
  ([PR #695, comments 6096176652](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096176652)
  and [6096191814](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096191814), #738), and every take
  beside a two-handed item goes onto the belt
  ([PR #701, comments 6096140448](https://github.com/xperiaroco2/prime-game/pull/701#issuecomment-6096140448) and
  [6096157421](https://github.com/xperiaroco2/prime-game/pull/701#issuecomment-6096157421)). His last answers
  ([comment 6100696677](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6100696677)): DD9 (c), through
  #767 (the flat greybox becomes a test bench only, and players always play the House): this Delivery plays on the
  House only, and the greybox keeps today's colour-matched Delivery as far as its bot scenarios and the leak test
  need it (§5, DE9, DE15); §5.1's drafts approved as drafted. DD10, which Delivery the tutorial teaches, he answered
  with none of its options ([comment 6108665402](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6108665402)):
  the tutorial deals no task at all and teaches only movement and the basic mechanics, its rework the M7 backlog issue
  #825, and this Delivery does not reach it (§5). The DE items are technical, the game-design manager
  session's to decide and report (tier (a)): decided here, each revertible in its issue.
- **Amended 2026-10-13 (#925):** the engineer lifted "backlog for now" on 2026-10-11, "Implementation starts now"
  ([#676, comment 6109559003](https://github.com/xperiaroco2/prime-game/issues/676#issuecomment-6109559003)), so
  "nothing here is built" above is history. What is built is read from the issues, not from a list here: the plan issue #676 and the issues named in §8.
- **Date:** 2026-10-10
- **Deciders:** the engineer (the rules: DD1 to DD8, answered on 2026-10-10 in PR #713's comment 6095445718; DD9 and
  §5.1's drafts in its comment 6100696677, which approved the design; DD10 on 2026-10-11 in its comment 6108665402,
  so D2 comes after #825); the game-design manager session of #676 (DE1 to DE16). Designed by the agent of #683, on the engineer's word (#683; the track's kickoff on #593, comment
  6088751685).
- **Amends:** [MVP rules](2026-09-29-mvp-rules.md) (Delivery: a circle per package placed at random, a colour per
  package, the palette of 10; on the House, while the greybox keeps them, DD9 (c)) and [the M4 client
  design](2026-10-01-m4-first-person-client.md) (D10 (b), the destination marker drawn through walls, and its render
  checklist's one exception in item 5: DD4 (a), the engineer's). Both record the change and point here; D3a removes
  the marker from the client.
- **Builds on:** [MVP rules](2026-09-29-mvp-rules.md) (Tasks: the shared Delivery of #79; the engineer's correction in
  #32, "rests inside, however it got there"), [content API v0](2026-09-29-content-api-v0.md) (task types are classes
  with settings), [vision revision 1](2026-10-01-vision-revision-1.md) (V4's "living", V13's two-handed package, hiding
  packages as the dissidents' sabotage), [the M4 client design](2026-10-01-m4-first-person-client.md) (its render
  checklist, item 5), [the zone task ADR](2026-10-09-m7-zone-task.md) (#36, built on `release/m7`:
  `StationState.contains`, ZE3's station checks, ZE7's `STATION` target, ZE9's spacing, ZD11's looks), [the throwing
  ADR](2026-10-09-throwing-held-items.md) (#37, built on `release/m7`: a thrown package counts, the engineer's TD4 (a)),
  [the Generator ADR](2026-10-10-generator-task.md) (#679: GE10's exact marker counts, GE11's station scenes, GE15's
  `TaskType.maps` in its G8, G0's subtasks setting, G3's flat-fake rule, G6's `CircleViews` filter), [the cooking
  ADR](2026-10-10-cooking-task.md) (#682: item kinds, not a variant field; CE18's optional spawn tag; CE21's belt rule
  for every take), #738 (the shared task total goes), #767 (the greybox a test bench only), [level piece
  conventions](2026-10-09-level-piece-conventions.md), [MVP content built by the
  engineer](2026-09-29-mvp-content-built-by-the-engineer.md) (content and levels are provisional, approved in their
  PRs), [the House map](../design/house-map.md) (§2 decision 5, §6's Delivery rows, §7's routes), [tests on
  CI](2026-10-09-tests-on-ci-local-lint-and-check.md) (#605: what "green" means in §8)
- **Numbering:** DD and DE are this ADR's own; the issues are D1, D2a, D2, D3a, D3, D4 and D5 (§8), proposals for the
  M7 backlog, which the manager opens from the PR's handoff.

## Context
Today (`core/tasks/delivery.gd`, `content/tasks/delivery.tres`; ARCHITECTURE §7.1.14, §9.5.4): one shared task of N
packages, N the host's `packages` setting (1 to 10, default 6). The deal places N circles on random `circle` markers,
each in a random colour of a 10-colour palette, puts N packages on random free `package` markers, and binds each
package to a random circle, whose colour it takes. A package resting inside its own circle's cylinder (radius 1 m,
height 2 m), however it got there, is delivered and locked. The client paints the package and its circle in that colour,
the HUD shows a swatch with "Deliver to the circle of this colour" (on main, the M6.2 HUD of #489 shows no destination
since #758), and while the own player carries a package a marker floats over its circle, drawn through walls (D10
(b)). The wire carries the colour in `StationPlaced` and, for a package, its circle and colour in `ItemSpawned`. On
House (#626): 10 `package` markers in storage, 10 `circle` markers in ten rooms; house-map §6 names Delivery's points:
the wine rack and the boxes in storage (sources), the dining table (the wine's drop-off), the terrace table, the
garden and the garage's workbench (drop-offs), as plain markers under each room's `Stations` node with no group. The
same Delivery plays on the flat greybox, where the bots' scenarios and the information-leak test run (ARCHITECTURE
§9.7).

The engineer's direction changes the binding on the House: what an item is decides where it goes, as fixed data, where
today a colour drawn each round does. For the engine that means:
- several item kinds take part in one Delivery, where today one (`package`) does;
- each kind has a fixed place in the data, where today the deal draws a circle;
- a place stands where the map puts it, the same every round, where today circles move;
- colour leaves the House's rules and its client view.

His DD9 (c) keeps today's Delivery on the greybox, a test bench only (#767): so the new rules come as a second
Delivery task type that plays on the House alone, and today's stays, unchanged, on the greybox alone (DE9, DE15).

What stays (§9.5.4): the task is shared and only living players deliver (#79, V4); one item is one subtask; an item
counts when it rests inside its place, however it got there (a put-down, a swap, a drop at a death or a leave, a throw:
the engineer's TD4 (a), built on `release/m7`); a delivered item is locked; nothing in Delivery is secret (#79); the
dissidents sabotage by hiding items.

## Decision

### 1. The mapping (`new-mechanic` step 3)

#### 1.1 Each rule to its engine part

| # | What #683 needs | Engine part | Exists? |
|---|---|---|---|
| 1 | Storage holds different items | one `ItemKind` per kind of item (DE1): its id, display name (the HUD's hand slot), spawn tag and `hands` | `ItemKind` exists (`core/content/item_kind.gd`); the kinds D2: `wine`, `oil`, `gnome` and `parasol` (DD1 (a), §5.1, the engineer's) |
| 2 | Each kind goes to its own place, by meaning | a second Delivery task type, `DeliveryByMeaning` (DE15); `DeliveryRoute` (DE2), a sub-resource of it: `item` (an `ItemKind`) and `drop_off` (a `StationKind`); `DeliveryByMeaning.routes` lists them | missing: D2 |
| 3 | A place on the map | one `StationKind` per place (DE3), the house-map's "drop-off": its own id and spawn tag, `radius_m` and `height_m` (DD3), no palette; exactly one marker of its tag on each map the type lists | the class exists (`core/content/station_kind.gd`); the markers D1; the data D2 |
| 4 | How many items, and of which kinds | the deal: N items, N the `packages` setting, their kinds spread over the routes in a random order (DD2) | the setting exists; the draw D2 |
| 5 | Delivered at its own place, however it got there | the check on `item_rested`, the shape of today's `Delivery.on_fact`: an item of an undone subtask resting on the ground inside its drop-off's cylinder (`StationState.contains`) is delivered and locked | `Delivery.on_fact` exists; `StationState.contains` on `release/m7`; D2 builds the new type's |
| 6 | Not by colours | no palette and no colour demand for drop-offs; the drop-offs' and the items' colour on the wire is white, which the client never paints by (DE5 (b)); the client draws neutral looks (DE11) | D2, D3 |
| 7 | An item at a wrong place | nothing happens (DD5) | exists: a package in another circle does nothing today |
| 8 | Packages take both hands | `ItemKind.hands` 2 for every kind of this Delivery (DD6) | exists (M4-5) |
| 9 | A player tells where an item goes | by meaning alone (DD4 (a), the engineer's): the item's look and its name in the hand slot (DE1); nothing points to its place, and the one marker the client draws through walls today, over the held package's circle, goes, on every map | `CircleViews`'s marker exists (`client/world/circle_views.gd`); its removal D3a |
| 10 | The reader, the mode check, the wire budget and the client find the drop-offs | `TaskType.station_kinds()` (DE4) in place of the four finders of a type's station kinds (three reflections over its `StationKind` properties and `WireBudget`'s colour demands), which miss kinds inside a route list | missing: D2a (the new type's override in D2) |
| 11 | Bots find an item and its place from what they were told | nothing: the bots never meet this Delivery (they play only the greybox, which keeps today's, DD9 (c)); `ScenarioTarget`'s `PACKAGE` and `CIRCLE_OF_HELD` stay as they are (DE8) | exists |
| 12 | The flat test level, the bots' scenarios and the leak test keep working | the engineer's DD9 (c), through #767: the greybox, a test bench only, keeps today's colour Delivery as far as its bot scenarios and the leak test need it; `TaskType.maps` (the Generator's G8, GE15) lists the greybox alone for today's Delivery and the House alone for this one (DE9) | G8 for the part; the two lists D2 |
| 13 | On House | the four plain markers at house-map §6's points join their drop-off's group (DE10) | the markers exist (`DiningTable`, `TerraceTable`, `GardenDropOff`, `Workbench`, level 0); D1 |
| 14 | Tested on House, which bots do not play (ARCHITECTURE §9.7) | integration tests in the host's real world (D5) | missing |

#### 1.2 Today and after

| | Today | After | Why |
|---|---|---|---|
| Task types | one, `Delivery`, on every map of the base mode | two: this one, `DeliveryByMeaning`, on the House; today's `Delivery`, unchanged, on the greybox (DE15) | DD9 (c): the greybox keeps today's for its bots and the leak test |
| Item kinds (on House) | one, `package` | several (DD1) | "different items" |
| Which place an item goes to | drawn each deal, a random permutation (`tasks`) | fixed in the data by kind (`routes`) | "by the location's sense" |
| Places | N circles on random `circle` markers, anew each round | one station per drop-off in use, on its own marker, the same every round | a place by meaning stands where it is |
| Colours | a 10-colour palette: demanded, sent, painted | none on House; the greybox keeps its palette | "not by colours" |
| What points to a place | the HUD's swatch of the circle's colour (gone on main with #489), and a marker over the circle drawn through walls (D10 (b)) | nothing: the item's look and its name (DD4 (a)); the marker goes on every map (D3a) | "by meaning alone", and no marker through walls any more |
| RNG purposes | `circles`, `packages`, `tasks` | this type: `packages`, `tasks`; today's keeps its three | no placement or colour draw is left on House |
| A place done | when its one package is delivered | when every item routed to it this round is delivered (DE7) | several items may share a place |
| Events | `StationPlaced`, `ItemSpawned` (circle, colour), `PackageDelivered`, `TaskState`, `TaskProgress` | the same classes and wire rows; this type's colour is always white | no wire change (DE5 (b)) |

### 2. The rules as the engine runs them (with the engineer's answers)
1. **The deal** (when `DealTasks` draws this Delivery, on the House, the one map its data lists, DE9). N is the
   `packages` setting; with N = 0 the task has no subtasks and is done (#79). Otherwise, in these steps (K the number of
   routes):
   1. The routes are shuffled (`tasks`).
   2. Each route's item count: the route at shuffled position p (from 0) gets floor(N / K) items, plus one if
      p < N mod K, so every route has an item before any has a second (DD2 (a)).
   3. The stations: one per drop-off whose routes got an item, on its tag's one marker (no marker is drawn), each
      drop-off once, in `routes` data order of its first appearance. Station ids follow that order.
   4. The items, per item spawn tag, the tags taken in `routes` data order of their first appearance: the tag's items
      are listed route by route in shuffled order, each route's count of its kind; they get as many distinct random
      free markers of the tag (`packages`; `Items.free_markers`, picked as today in level order), and a random
      permutation (`packages`, drawn next) gives each listed item its marker. Item ids follow the markers' level order
      within a tag, tag after tag, so with one shared tag (DD8 (a)) item ids follow level order as today.
   5. Subtask i is the i-th item in id order, bound to its kind's route and so to that route's drop-off station.

   Then `StationPlaced` per station in id order, `ItemSpawned` per item in id order (with its drop-off station and that
   station's colour, white, DE5), then `item_rested` (spawn) per item. A map short of markers deals nothing and logs a
   match error, as today; the fit check keeps a match from getting there. Station ids follow `routes`, not the level,
   which changes ARCHITECTURE §3.3's "item and station ids are assigned in spawn-point order" for this type's drop-offs
   (each is the one marker of its tag, so no level order applies across them): D2 adds that exception and this type's
   deal to §3.3, beside today's Delivery deal.
2. **The check**, on `item_rested`: an item of an undone subtask resting on the ground inside its own drop-off's
   cylinder is delivered: locked (`PickUp` gets `unavailable`), its subtask done, and its drop-off done once every item
   routed to it this round is delivered (DE7); then `PackageDelivered(item, station)`, `TaskState`, `TaskProgress` and
   `subtask_done`, in that order, as today's Delivery does (`TaskProgress` as long as #738 keeps it).
3. **Anything else at a place**: an item resting inside another route's drop-off, or any other item in a drop-off, does
   nothing (DD5 (a)).
4. **Nothing else changes**: any living player carries any item; every item of this Delivery is two-handed (DD6 (a)),
   so none ever rides a belt; a dying or leaving carrier drops it at the body; a held item never counts. A carrier who
   takes a one-handed item puts it onto the belt and keeps the Delivery item in the hands: the engineer's belt rule for
   every take, which cooking's C2 builds (§4, §9); Delivery adds nothing for it.
5. **The greybox** keeps today's Delivery as it is (DD9 (c)): the same class, data, circles and colours; only the
   marker through walls goes, on every map (DD4 (a), D3a).

### 3. What everyone sees

| What | Who learns it | How |
|---|---|---|
| Which item kinds go to which place | every client: its own copy of the mode holds the routes | data |
| Where this round's drop-offs stand | everyone | `StationPlaced` in the deal |
| Each item, its kind, where it spawned and its drop-off | everyone | `ItemSpawned` (`kind`, `station`) |
| Where an item lies after it moved | every client receives it; an honest one draws it only where it lies, depth-tested (hidden by sight, the M4 render checklist item 5) | `ItemPickedUp`, `ItemPlaced`, `Swapped`, the snapshots' hand and belt items |
| A delivery | everyone, on the task screen too: Delivery's row keeps its own count of delivered items and is struck through once every item is delivered; no shared total on the HUD or the task screen (the engineer's, #738) | `PackageDelivered`, `TaskState`; `TaskProgress` as long as #738 keeps it on the wire |
| Who delivered | nobody, through an event: no Delivery event names a player | the snapshots show who stood there, as today |
| Where an item goes | everyone, by what it is: its look, and its name in the hand slot (DD4 (a)); nothing points to the place, on the HUD or through walls | the item kind's display name and look; the routes in each client's copy of the mode |

Nothing in it is secret, as since #79: the per-peer filter (§5) gains nothing. The leak test keeps playing today's
Delivery on the greybox (DD9 (c)); this type emits the same event classes (`StationPlaced`, `ItemSpawned`,
`PackageDelivered`, `TaskState`, `TaskProgress`) to everyone, so its task-event lists stay as they are.

### 4. Edge cases

| What happens | What the engine does | Why |
|---|---|---|
| An item rests at another kind's place | nothing; anyone may carry it on | DD5 (a); today's rule for another circle |
| Two items of one kind, one place | each counts when it rests there; the place dims after the second | DE7 |
| N below the number of routes | the routes drawn first get an item; the other places get no station and show nothing this round | DD2 (a), DE3 |
| N above the number of routes | some places take two or more items | DD2 (a) |
| A carrier is knocked down holding the item, inside or near its place | it keeps the item: nothing drops at a knockdown (ARCHITECTURE §7.1.13), and a held item never counts, so nothing is delivered while it is down, even with its body inside its place. Today it crawls with the item. Once #728 lands it cannot move on its own (#728's answer A, [comment 6095620279](https://github.com/xperiaroco2/prime-game/issues/728#issuecomment-6095620279)), but on the House a launch, or the host's physics rolling the body, may carry it and the item into or out of its place (#728's KD10 (A), PR #754). A raise leaves the item in its hands, wherever the body lies. At its death, or when it leaves the match, the item drops at the body and is delivered if it rests inside (with #728, the body and the item rest where the motion stopped, its KD8 (a)) | "however it got there" (#32); vision revision 1 ("nothing at a knockdown", both slots drop at death); #728's design (PR #754, its row for this Delivery) |
| A package marker inside a drop-off's cylinder | an item of that place's kind spawning there is delivered in the deal | as today; the content test of DE12 keeps it off every map this Delivery lists |
| A drop-off's cylinder reaches through a wall | an item resting behind the wall, inside the radius, counts | as a circle today; a level convention and D5's wall test (§7) |
| E at a drop-off | `nothing_to_do`: a drop-off holds no `Interact` rule | the Generator ADR's §2 item 2 says so for a delivery circle; Delivery needs no use |
| A map with no marker for one route's drop-off | the fit check refuses the lobby while N > 0; with N = 0 it plays | DE6 |
| A delivered item | locked; `PickUp` gets `unavailable` | as today |
| An item thrown into its place | delivered once it comes to rest inside | "however it got there"; the engineer's TD4 (a), built on `release/m7` (`delivery_throw_test.gd`, on today's Delivery) |
| A carrier picks up a loose one-handed item (a knife, an ingredient) | it goes onto the belt, a full belt's item put down at the carrier's feet first; the Delivery item stays in the hands. Today the carried package rests where the picked item lay | the engineer's belt rule for every take (PR #701, comments 6096140448 and 6096157421; cooking's CE21, built in its C2); the carrier still cannot draw the knife (`Swap` refuses a two-handed hand item, V13) |
| A carrier picks up another Delivery item | today's swap: the carried one rests where the picked one lay, and is delivered if that spot is inside its own place | the belt holds only a one-handed item (cooking's CE21) |
| A taker's full belt empties at its feet inside a place | never a Delivery item: none rides a belt | DD6 (a) |
| The oil carried to the car on the lift, beside the garage's workbench | nothing for Delivery: only the workbench's cylinder counts (on House the workbench, at 70, 37, is 7.2 m from the car, at 64, 41); the car is the car repair's station (#688, PR #709) | DD5 (a); two chains in one room, each with its own place |
| A match on the greybox | today's Delivery deals there, with its circles and colours; this one does not | DD9 (c); `TaskType.maps` (DE9) |

### 5. DD items (the engineer's: game rules and taste)
The engineer answered DD1 to DD8 on 2026-10-10
([PR #713, comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718)): every
recommendation stands except DD4, which he answered otherwise. The options stay for the record; the last column is what
holds now. DD1's garden and terrace items and DD7's description he left to the agents to draft: §5.1, which he
approved as drafted. DD9, from his later answer on the greybox (PR #695), he answered (c), not the recommendation,
through #767 ([comment 6100696677](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6100696677)).
DD10, which Delivery the tutorial teaches, came from the review of PR #713 after those answers; he answered it on
2026-10-11 with none of its options
([comment 6108665402](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6108665402)).

| # | Question | Options | Trade-offs, and the failure each prevents | Decided |
|---|---|---|---|---|
| DD1 | The item kinds and their places (#683's open item 1; his examples; the question relayed in comment 6090227509) | (a) one kind per house-map §6 drop-off, four: the wine to the dining table (§6's "the wine" row), the oil to the garage's workbench, his garden item to the garden drop-off, his item for the terrace table; (b) his three examples only: the wine to the living room (a new drop-off there), the oil to the garage, his item to the garden; the terrace table leaves Delivery; (c) (a) or (b) and more places: rooms that hold a circle marker today (the kitchen, the study, the bedrooms) | each place is a marker the fit check demands on every map of the base mode, the greybox included (DE9; written before DD9 (c), which leaves the greybox out). (a) keeps §6 and its measured routes (§7: the wine 26 m, the garage 60 m, the garden 57 m) and sends items to three sides; the terrace's item and the garden's need names. (b) follows his words to the letter; the living room is "a place where everyone crosses" (house-map §4), so a delivery there is watched by many, and its route is not measured. (c) more places dilute "by meaning" (what belongs in a bedroom?) and add markers to every map. Either way the Package kind (`package`) leaves the base mode unless he names it one of the kinds (house-map §6 has "Boxes (source)") | **(a), the engineer** ([comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718), the recommendation): four kinds, one per house-map §6 drop-off, the wine at the dining table and the oil at the garage's workbench; the garden's and the terrace's items drafted by the agents and approved by him as drafted ([comment 6100696677](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6100696677), §5.1). The `package` kind leaves the House's Delivery and stays the greybox's (DD9 (c)) |
| DD2 | How many items a round, and whether the host's setting picks it (#683's open item 2; #256) | (a) N items, N the host's `packages` setting as today (1 to 10, default 6), the kinds spread over the routes in a random order: every place gets one before any gets a second; (b) one item per place, N at most the number of routes: the setting picks how many places, drawn at random; (c) every kind once a round, no setting | (b) caps the task at the routes (4 on House with DD1 (a)), so today's default of 6 is out of range, and the hiding sabotage has fewer items to hide. (c) drops a host setting (#256: every task type has its subtask count) and makes the map's routes the difficulty. (a) keeps the setting, its bounds and the MVP scenarios' counts (`crew_delivers_every_package` delivers 6), and sends players to every place before any repeats (house-map §8: tasks spread the players). In (a) and (b) which places get an item when N is below the routes is drawn each round, so nobody plays one memorised route (as the Generator's GD2 (a)) | **(a), the engineer** ([comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718), the recommendation) |
| DD3 | What counts as "at its place", and how big a place is (#683's open item 2) | (a) inside a drop-off's cylinder standing on the floor at the place's marker, as a circle today: on the floor around the table or bench, or on its top, within the height; the radius and the height in the data (a circle's 1 m, game design since #79, and 2 m, a placeholder); (b) anywhere in the room or area ("to the garage", "to the garden"): a box-shaped drop-off sized to the room, a new station shape; (c) only on the furniture's top | (b) forgives where in the room, at the cost of a second shape in every station test (`StationState.contains`, the client's look, the spacing tests), and on House the garden is 32 x 28 m: a garden item counts as it crosses the fence, with no walk to a spot. (c) needs a marker on the top, and an item put down on the floor by the table is ignored without a word. (a) is what house-map §6 places (drop-offs at a table and a bench) and what a circle does, and players see where it is (DE11) | **(a), the engineer** ([comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718), the recommendation): a 1 m radius (a circle's, the engineer's since #79) and a 2 m height (a placeholder, "not a decision") for every drop-off; a wide place (the garden) may take a larger radius in the data (0.2 to 10) |
| DD4 | How a player tells where an item goes (#683's open item 3: does the through-walls marker stay) | (a) by meaning alone: the item's look and its name in the hand slot; (b) (a) and the marker over the held item's drop-off, drawn through walls as today (D10 (b)), in one neutral look; (c) (a) and a sign: the place's picture on the item and at the place, which #520's Delivery card art draws ("check the sign on the package", "find the room with that sign"); (d) (a) and a HUD line naming the place | (a) is the "open knowledge" pillar's finding by looking, and meaning is the point of the change; but a new player on a four-level map may not know where the garden drop-off is, or that the oil goes to the workbench. (b) keeps his answer D10 (b) of 2026-10-01: the marker shows only a fixed, public place, so it reveals nothing, and the render checklist's one exception stays one. (c) waits for the art and the room record (#306): a sign per place, on each item's look and at the place. (d) the M6.2 HUD (#489) shows no destination, by the UI handoff, so a HUD line would undo it | **(a), the engineer, not the recommendation** ([comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718)): by meaning alone, and no through-walls markers any more: the one the client draws today, over the own package's circle (`client/world/circle_views.gd`), goes too (D3a), on the greybox as well, and with it the M4 render checklist's one exception (item 5), so nothing in the client is drawn through walls |
| DD5 | An item resting at a wrong place | (a) nothing: it lies there and anyone may pick it up (today's rule for a package in another circle); (b) a sign to everyone in sight: a sound or a red flash at the place, client only, nothing in the rules; (c) refused: it is moved off the place, or back to storage | (b) is a client effect on public facts (every client knows the item's kind and the place's routes); it adds nothing for a dissident to learn as long as it keeps the M4 render checklist: the sound through `SoundChooser` and `WorldSounds`, within 12 m and muffled behind walls (item 10), the flash depth-tested and in `SightHider.GROUP` (items 3 and 5), or players would learn through walls where someone just put an item down. (c) a new rule and a new placement path, and a dissident can no longer leave an item at a wrong place as a decoy. (a) needs nothing built | **(a), the engineer** ([comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718), the recommendation); (b) stays a cheap later add if a playtest asks |
| DD6 | Hands (today's description: "Packages take both hands") | (a) every Delivery item two-handed, as the package today; (b) per kind in the data (one-handed wine, a two-handed crate); (c) every Delivery item one-handed | with (b) or (c) a one-handed item rides the belt: one player carries two at once, or carries one with a knife in the hand, which halves the walks and the exposure the task is built on (V13: a carrier cannot draw a knife). The Generator's and cooking's busy-hands rules refuse a two-handed carrier a station's use (a take from a station or the floor goes onto the belt, the engineer's later belt rule, §4). The scenarios `two_handed_pickup_with_a_full_belt` and `refusals` rely on a two-handed package, and under (b) which kind a scenario meets is the deal's draw | **(a), the engineer** ([comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718), the recommendation) |
| DD7 | The name, the description and the lobby label (#683's open item 4) | the name: (a) "Delivery" stays (M6.2's copy deck already has `task.delivery`, "Delivery" and "Доставка", and its card art); (b) a new name in his words. The description: the mode check refuses an empty one; the task screen shows it, the M6.2 UI (#253, on main since #758) nowhere. The label "Packages (Delivery)" of the `packages` setting | today's description ("Carry each package to the circle of its colour. Packages take both hands.") is wrong once colours go, so the House's Delivery cannot keep it | **(a), the engineer** ([comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718), the recommendation): "Delivery" and the label stay; the description drafted by the agents and approved by him as drafted ([comment 6100696677](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6100696677), §5.1). The greybox's Delivery keeps today's description, which is true there (DD9 (c)) |
| DD8 | Where each kind starts in storage | (a) any kind on any storage marker: one spawn tag shared by every Delivery kind, as `package` today; (b) each kind at its own source, the wine at the wine rack and the rest at the boxes (house-map §6): a spawn tag per source | (a) a bottle may lie by the boxes. (b) the look follows §6, and House's ten storage markers split between the sources; the demands follow either way (DE6) | **(a), the engineer** ([comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718), the recommendation): only the look differs, and the data alone switches to (b) |
| DD9 | What the flat greybox's "basic Delivery" is, and how its places show what they are. His read-back of the Generator ADR's GD7 ([PR #695, comment 6096108206](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096108206)): the greybox "keeps only the basic Delivery and nothing else"; all new mechanics come with M7 | (a) this Delivery, the base mode's only one, with a greybox prop beside each of its four drop-off markers that says what the place is: a dining table, a terrace table with a parasol stand, a patch of lawn with a low fence (the garden), a workbench (D4's props, provisional); (b) this Delivery on bare drop-off markers; (c) today's colour Delivery on the greybox and this one on House: two Delivery task types, each listing its map (the Generator's G8, `TaskType.maps`) | The design read his words as (a) or (b): #683 took colours out of Delivery itself ("we have not gone by colours for a long time"), its open item 5 asks the flat level and the bots' scenarios to keep working with the change, and Delivery by meaning reworks the one task the greybox keeps; it is not one of the House's new chains. (b) is all the bots need, but the greybox was then the base mode's first map, where the default lobby lands: by meaning alone (DD4 (a)), a player there sees four drop-offs that look alike and must try each, since a wrong place says nothing (DD5 (a)). (c) reads "basic" as "today's": the engine keeps the palette, `ItemSpawned`'s colour and the circle deal beside the routes, the bots test a Delivery nobody plays on House, and the client draws both looks. Under (a) the greybox's props carry no collision: the greybox is the scenarios' level, pinned flat (`content_modes_test.gd`'s `test_the_scenarios_levels_are_flat`: one floor box, its top at y = 0), and the core runner answers it with `FlatWorldQuery` while the bots runners host it over `HostWorldQuery`; a table with collision would stop an item put down by a bot short of its drop-off in one runner and not the other, or block a pickup's line of sight, so the two runners would stop playing one world | **(c), the engineer, not the recommendation** ([comment 6100696677](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6100696677)), through #767: the greybox becomes a test bench only and players always play the House, so no player needs to read a meaning there. Delivery by meaning plays on the House only; the greybox keeps today's colour-matched Delivery as far as its bot scenarios and the leak test need it. So: two Delivery task types, each listing its one map in `TaskType.maps` (DE9, DE15); D1 puts no drop-off marker on the greybox; D2 adds the second type and leaves today's as it is, with no wire change (DE5 (b)) and no new bot target (DE8); D3 draws both looks; D4 leaves the greybox's circles and gives it no props |
| DD10 | Which Delivery the tutorial teaches (raised by the review of PR #713: `content/modes/tutorial_mode.tres` deals `content/tasks/delivery.tres`, its one task type, on `levels/tutorial/tutorial.tscn`, whose room holds a `spawn_package` marker and a `spawn_circle` marker and no drop-off; under DE15 (i) that file becomes Delivery by meaning, which D2 keeps to the House, so the tutorial would deal no Delivery, or fail to start) | (a) the tutorial keeps the colour Delivery: `tutorial_mode.tres` deals `colour_delivery.tres`, whose `maps` lists the greybox and `tutorial.tscn`; no level change; (b) the tutorial teaches Delivery by meaning: the House's type lists `tutorial.tscn` too, and the tutorial room gets one marker per drop-off tag, four (the fit check demands every route's drop-off on each map the type lists, DE6), while `packages` stays 1, so each run carries one random item to its place; (c) by meaning with one route: a tutorial-only Delivery by meaning with its own id and a single route, one item and one drop-off marker in the tutorial room; which item and which place are his | (a) costs nothing, but teaches a Delivery that players never play (#767: players always play the House), and the step's words ("Find the room with the sign that's on the package", `tutorial.step.deliver.how`) fit neither Delivery. (b) teaches what the House asks: find where the item belongs among real places; it reuses the House's type, its copy-deck key and its card; the cost is four places in the tutorial room (markers now, props later, content the engineer approves) and the step reworded. (c) is the shortest lesson, but a third Delivery type needs its own copy-deck key, card and tutorial lookups, and the lesson shows one place, so nothing is chosen by meaning | **none of (a), (b), (c), the engineer, not the recommendation** ([comment 6108665402](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6108665402)): the tutorial deals no task at all (no Delivery, colour or by meaning) and teaches only movement and the basic mechanics ("the tutorial must be reworked completely; for now its tasks can be removed altogether"); Delivery by meaning (D2) does not reach it. The rework is its own M7 backlog issue, #825, not started before he says so; which mechanics, steps and words is his call there. D2 therefore comes after #825 (technical, the manager's, revertible): by then `tutorial_mode.tres` deals no task, so D2's change of `delivery.tres` touches no tutorial file, and the tutorial neither waits for a Delivery it no longer deals nor fails to start (the failures the question names). Rejected: D2 pointing `tutorial_mode.tres` at `colour_delivery.tres` until #825 is (a) in all but name, the colour Delivery he declined; D2 taking the tutorial's task out itself leaves lesson 4 (`deliver`, `docs/design/tutorial.md`) waiting for a `PackageDelivered` that never comes, so D2 would rework the lessons, #825's design. Should he want D2 before the rework, the part of #825 that takes the tutorial's task out may land first, his call in #825 |

#### 5.1 The drafts he approved (DD1, DD7)
The engineer left the garden's and the terrace's items and the description to the agents (comment 6095445718), and
approved each draft below as drafted on 2026-10-10
([comment 6100696677](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6100696677)); D2 carries them.
Each item passes one test: a player who sees it for the first time sends it to one place only, and to none of another
chain's stations (the greenhouse's herb beds, the kitchen, the car).

| What | His (as drafted) | Why this one | Rejected |
|---|---|---|---|
| The garden's item | **Garden gnome** (id `gnome`): a large one, carried in both arms | belongs only in a garden; on House the greenhouse's beds take herbs (cooking), so nothing else there wants it; the cringe-fun vibe (GDD §1) | a sack of compost or a watering can: either reads as the greenhouse's |
| The terrace's item | **Parasol** (id `parasol`): closed, long, carried in both arms | it stands in an outdoor table, the terrace table's; the dining table indoors takes the wine, and the garden has no table | deck chair cushions (the garden's too); a crate of lemonade (a drink, which reads as the dining table's, like the wine) |
| The oil's name | **Motor oil** (id `oil`, his word): a canister | "Motor" so nobody carries it to the kitchen, where the burgers are made | "Oil" alone |
| The wine's name | **Wine** (id `wine`, his word): a case of bottles | his word | none |
| The description | "Carry each item from storage to the place where it belongs. Every item takes both hands." | by meaning alone (DD4 (a)), it names no place; a task type's description is the same on every map it plays | a description listing the four routes: a pointer DD4 (a) left out, and wrong on a map that places them otherwise |

The drop-off station kinds' ids and spawn tags are technical (DE3), provisional until D1 and D2 land:
`drop_dining_table`, `drop_terrace_table`, `drop_garden` and `drop_workbench`; the prefix keeps them apart from any
later station of the same room (a car repair workbench, say), which ZE3 would refuse as a tag used twice.

### 6. DE items (technical: the manager decides and reports)

| # | Choice | Options | The failure it prevents | Decision |
|---|---|---|---|---|
| DE1 | The item kinds | (a) one `ItemKind` per kind, each with its id, display name, spawn tag and `hands`, its look by id; (b) one `package` kind with a variant field on the item and the wire | (b) a field on every item, the wire and the HUD's hand slot for one task type: the cooking ADR rejected it for its ingredients. (a) reuses `ItemSpawned`'s `kind`, the HUD's display name and `client/world/item_view.gd`'s look by kind id (a labelled box for a kind it has no look for), as they are | (a) |
| DE2 | The binding | (a) `DeliveryByMeaning.routes: Array[DeliveryRoute]`; `DeliveryRoute` (`core/tasks/delivery_route.gd`, a sub-resource with no behaviour): `item: ItemKind`, `drop_off: StationKind`; one drop-off may serve several routes, one kind may be in one route only; (b) `ItemKind.destination`; (c) two parallel lists of kinds and drop-offs | (b) a generic item kind would name one task type's station, though an item may serve two types later. (c) two lists that must agree by position, the failure the cooking ADR's CE6 (b) names. (a) one row per "this goes there", which the check reads alone | (a) |
| DE3 | The places | (a) one `StationKind` per place, its own id and spawn tag (both provisional, `drop_<place>`, §5.1), no palette; exactly one marker of its tag on each map the type lists; a station only for a drop-off a dealt item needs; (b) one `drop_off` kind with several markers told apart by a node name or metadata; (c) rooms in `core/` (the room record, #306) | (b) `MarkerReader` reads groups, not names: a renamed or swapped marker would send the wine to the garage without an error. (c) rooms in `LevelLayout` and a box test before #306 exists. "Exactly one" is the Generator's exact count (GE10): a second garden marker would stand unused, and a player delivering there gets nothing; the fit check refuses more as well as fewer. Placing only the drop-offs in use keeps `StationPlaced` the list of this round's places, so the client draws no place nobody delivers to | (a) |
| DE4 | How the engine finds a task type's station kinds | (a) `TaskType.station_kinds() -> Array[StationKind]`: by default every `StationKind` property of the type (today's reflection, moved here once), `DeliveryByMeaning`'s override its routes' drop-offs, each once; `MarkerReader.floor_tags_of` (`server/levels/marker_reader.gd`), ModeCheck's station checks (ZE3's `_check_stations`, on `release/m7`), the client (`CircleViews.station_kind`) and `WireBudget` (`server/wire_budget.gd`'s `_Content`, which today collects the mode's station ids from `demands.colours.keys()`) call it; (b) teach the three reflections to walk arrays of sub-resources | the three reflections read only a type's `StationKind`-typed properties: a drop-off inside a route list would not be snapped to the floor (its cylinder would start at the marker's hand-placed height, §9.6), would escape ZE3's duplicate check, and would get the client's fallback size. `WireBudget` finds only the station kinds that demand colours: the drop-offs demand none (DE6), so `StationPlaced`'s worst case would be sized without their ids and `SettingsChanged`'s shortfall list would miss them, with no test failing. (b) three copies of a deeper walk, a fourth reader repeats it, and `WireBudget` stays apart. (a) also serves any later type that holds station kinds in a list (the cooking ADR's bed kinds, CE6, if held in one) | (a) |
| DE5 | The wire | (a) `ItemSpawned` keeps `has_station` and `station` (the item's drop-off station) and drops `colour`; `StationPlaced` keeps its colour (zones use it; a drop-off's is white); `PackageDelivered` stays; one protocol bump; (b) no wire change: this type's `ItemSpawned` names its drop-off station and that station's colour, white (a kind with no palette), as its `StationPlaced` does; (c) `ItemSpawned` drops `station` too: the client finds the place from its own mode (kind, route, drop-off kind, its one station) | (a) cannot stand beside DD9 (c): the greybox's Delivery still sends a package's colour, which the client paints. (b) a field that is always white for this type, which a client could still paint by: D3 draws this type's items by kind and its drop-offs by their own look, never by that colour (DE11); the wire and leak tests keep checking the field for the greybox's packages. (c) moves the binding into every reader's copy of the mode and the bots' `CIRCLE_OF_HELD` with it (`ItemViews.destination_item` was removed as dead in #1247), and breaks the day a map has two places of one kind | (b), since DD9 (c): no wire row, `WireBudget` sample or protocol version changes. (a) was the choice while the greybox was to play this Delivery |
| DE6 | The deal's draws, order and demands | §2.1; RNG purposes `packages` (the items' markers, then which listed item takes which) and `tasks` (the routes' order); this type has no `circles` purpose (today's Delivery keeps its three on the greybox). Demands while N > 0, on a map the type lists: exactly one marker per drop-off tag, and per item spawn tag the most items a draw can put there: with r the routes whose kind has that tag, min(N, r × floor(N / K) + min(r, N mod K)) under DD2 (a), which is N for one shared tag (r = K); min(N, those routes) under DD2 (b); no colours (this type never calls `Demands.add_colours`) | a purpose of its own shifts no other part's draws (§3.3); a demand below what a draw may need lets a lobby start whose deal then fails | as stated |
| DE7 | A place's done | (a) a drop-off's `StationState.done` once every item routed to it this round is delivered; `PackageDelivered(item, station)` per item as today; `ClientModel`'s fold is event-driven: a station becomes done on a `PackageDelivered` naming it when no other undelivered item names it, and never on `StationPlaced` or `ItemSpawned` (the fold the bots share, so it lands with D2, as `client/CLAUDE.md` asks; for today's circles, one package each, it changes nothing); (b) a new `DropOffDone` event | (b) a wire row and a fold for what `ItemSpawned` and `PackageDelivered` already tell. Without the "every item" rule the dining table dims after the first of two bottles. A fold derived from the items alone ("done when no undelivered item names it") marks every drop-off done from its `StationPlaced` until its items' `ItemSpawned` arrive (the deal sends the stations first, §2.1), and for good if an item never arrives | (a) |
| DE8 | The bots' targets (§9.7) | (a) `PACKAGE`: the n-th item whose `ItemSpawned` named a station, whatever its kind; `CIRCLE_OF_HELD`: unchanged; `NEAREST_PACKAGE`, new: the nearest such item on the ground, for `dissident_hides_a_package` and `dissident_kills_the_crew`; (b) scenarios name the kinds; (c) no change: the bots never meet this Delivery | (b) the deal draws the kinds, so a script cannot know which kind it meets. (a) was needed while the greybox was to play this Delivery; under DD9 (c) the bots play only the greybox, which keeps today's Delivery and its one `package` kind, so (a) would be code no bot runs | (c), since DD9 (c): `ScenarioTarget`, the scenarios, both runners and the chaos scenario stay as they are |
| DE9 | The flat level and the bots (ARCHITECTURE §9.7: bots play only the flat levels) | (a) the greybox gets one marker per drop-off tag at y = 0 and plays this Delivery; Delivery lists no map in `TaskType.maps`, so it deals on the greybox and on House alike; (b) the bots play a fixture mode that keeps circles; (c) the engineer's DD9 (c): today's Delivery stays the greybox's, its `TaskType.maps` the greybox alone, and this Delivery's the House alone (the Generator's G8, GE15: `DealTasks` draws only the types that play on the match's map, and the demands and the fit check ask a map only for those) | (b) the scenarios would stop testing the base mode, which is what they are for (§9.6). (a) puts markers and props for players on a level no player gets (#767). (c) keeps the scenarios, the chaos bots, the perf run and the leak test playing what they play now, with no change to their code or data, at the cost of a second type (DE15); the House's Delivery is tested without bots (§7) | (c), the engineer's |
| DE10 | The places on House | (a) markers: the plain `DiningTable`, `TerraceTable`, `GardenDropOff` and `Workbench` markers (under `Stations`, at house-map §6's points, level 0) join their drop-off's `spawn_<tag>` group; the furniture a place is named after is the room's dressing (`levels/props/`, collision on layer 1, so an item rests on its top), not a station; (b) a station scene per place in `levels/stations/`, bound as the Generator's GE11; (c) one generic drop-off scene, its group set per instance | a drop-off has nothing the client drives and nothing the host reads besides its marker, and its facing does not matter (its look is drawn by the client from `StationPlaced`); GE11's scene binding exists for devices with driven nodes and a facing. (b) a scene per place that wraps a table and a marker, and a client lookup by position for nothing. (c) a scene that differs per instance only by a group. (a) is the level piece conventions' "its spawn, package, circle, respawn and knife markers: the existing `spawn_<tag>` groups", and a scene can wrap a marker later (DD4 (c)'s sign) with no engine change. Every House drop-off stands on level 0, so the runners' flat-fake read of House still finds a floor (§9.7) | (a); the House's furniture props in D4, provisional |
| DE11 | The client's looks (D3a, D3; placeholders until the art pass) | the drop-off: a look of its own in one neutral colour, distinct from the zone task's (`ZoneViews`, ZD11) and from today's circles, depth-tested, dimmed when done; an item of this Delivery: its kind's look (`item_view.gd`, a labelled box until the art), never tinted by `ItemSpawned`'s colour (white, DE5 (b)); no marker (DD4 (a)), on any map: `CircleViews`' marker and its `no_depth_test` material go (D3a), so no material in the client draws through walls; `CircleViews` draws both Delivery types' stations, found through `station_kinds()` of the client's own Delivery types (the Generator's G6 restricts it to Delivery's station kinds), and tells a drop-off from a circle by which type lists its kind; on the greybox today's circles and packages keep their colours, by which a player there finds a circle | a drop-off and a zone or a circle that look alike, now that no colour tells them apart, send a player to stand in a drop-off or to put an item in a zone; a marker left over the held item's place would point where the engineer chose that nothing points | as stated |
| DE12 | Content tests | on every map this Delivery lists (House): one marker per drop-off tag (the fit check at the mode's maxima), no marker of any of its item kinds' spawn tags inside a drop-off's cylinder (`StationState.contains`, the cylinder at its snapped floor, so a storage marker on the level below does not count); today's Delivery's content tests keep the greybox; ZE9's spacing test (`release/m7`) measures zones against circle and drop-off markers alike through `station_kinds()` | an item spawning delivered; a zone over a drop-off | as stated |
| DE13 | The mode checks | `DeliveryByMeaning.check`: `routes` not empty; each route with an item kind the mode declares, a spawn tag on it (the cooking ADR's CE18 moves that requirement to the parts that place on markers, Delivery among them) and a drop-off; no kind in two routes; no drop-off tag equal to an item tag (today's "circle and package share spawn tag", generalised); no palette on a drop-off; the subtasks setting (G0, if landed) and both RNG purposes set; ZE3 across the mode through `station_kinds()`; today's `Delivery.check` unchanged | a shared tag lets an item spawn on a drop-off marker, delivered before anyone moves; a kind in two routes has two places; a palette suggests a colour the game never shows | as stated |
| DE14 | The words in code | (a) keep `Delivery`, `PackageDelivered`, the `packages` setting, and "package" for any Delivery item in code and docs; (b) rename them | the engineer still calls them packages ("Стосовно пакетів", comment 6090227509); (b) touches the wire's event name, every scenario and the copy deck for no rule | (a) |
| DE15 | The two Deliveries in the engine (DD9 (c)) | the class: (a) a new class `DeliveryByMeaning` (`core/tasks/delivery_by_meaning.gd`, `extends TaskType`) beside today's `Delivery`, which stays as it is; (b) one `Delivery` class with both deals, chosen by whether `routes` is set; (c) `DeliveryByMeaning extends Delivery`. The content ids: (i) the House's type takes today's id `delivery` and file `content/tasks/delivery.tres`, and today's data moves, unchanged but for its id and `maps`, to `content/tasks/colour_delivery.tres` (id `colour_delivery`, display name "Delivery", today's description), with a copy of today's how-to card under that id; (ii) today's keeps `delivery`, and the House's takes a new id | (b) every method branches on its data, a `.tres` holding both a circle and routes must be refused, and a change for the House can break the greybox's scenarios and the leak test, which must keep testing what they test now. (c) inherits the `package`, `circle` and `circles_rng` exports it must leave empty, which its check then polices. (ii) the copy deck's `task.delivery` ("Доставка"), the how-to card (`content/howto/tasks/delivery.tres`) and the map screen's lookups all key on the id, so the House's players would see an untranslated name and no card fitting their Delivery until the UI track adds keys for a new id, while those keys follow a type nobody plays (#767); and `howto_content_test.gd` demands a card for every task type, so the new id needs one anyway. (i) keeps what players see keyed to the Delivery they play; the class name `Delivery` stays on today's code, so no test of it changes, and the `.tres` header names its class. Both types name the one `packages` setting as their subtasks setting: one lobby row, its label as DD7 (a) keeps it; each map deals only one of them (DE9) | (a) and (i); the id `colour_delivery` is technical and provisional; a player sees that type only as "Delivery" (its display name) on the greybox, whose lobby, guide and loading card list it alone (DE16) |
| DE16 | The lobby, the guide and the loading card on a map (DE15 (i) puts two types named "Delivery" in the base mode) | (a) the lobby's ban chips (`client/ui/lobby_panel.gd`), the guide's cards (`client/ui/guide_panel.gd` over `HowtoCards.of_tasks`) and the loading card (`HowtoCards.dealable`, `client/app/game_howto.gd`) list only the types whose `TaskType.maps` holds the lobby's picked map or the match's map (an empty `maps`: every map), so the House shows one Delivery, by meaning, and the greybox one, by colours; (b) mode-wide lists, as the Generator ADR's GE15 accepts, with a `task.colour_delivery` copy-deck key to tell the two apart | (b) shows two "Delivery" chips and cards on each map, one of which deals nothing there: banning it changes nothing, and the House's guide teaches the colour circles that DD4 (a) and DD9 (c) rule out there; GE15 accepted mode-wide lists only while no two types shared a name. (a) a chip and a card follow the map picker; a ban on a type the picked map hides stays in the setting and changes nothing there, as it deals nowhere on that map | (a), in D2 |

### 7. Testing
- **Unit tests** (D2, and D2a for `station_kinds()`; fixtures only, never `content/`, ARCHITECTURE §9.6): the deal
  (the spread of DD2 (a): every route once before a repeat, N below and above K, N = 0; ids and their order, pinned
  with two item spawn tags, which the data allows though DD8 (a) uses one: station ids in `routes` order, item ids by
  tag then level order, subtask i the i-th item id; only the drop-offs in use placed; each item's `ItemSpawned` naming
  its drop-off with white; the exact drop-off markers and the per-tag item demands; a short map logging a match
  error); the check (its own drop-off delivers; another route's drop-off and a knife do nothing; a place with two items
  done only after both; a held item never counts, nor one held by a carrier knocked down inside its drop-off, which is
  delivered at that carrier's death there and stays held after a raise (§4); an item thrown into its own drop-off is
  delivered, a case beside `release/m7`'s `delivery_throw_test.gd`, which stays on today's Delivery); DE13's checks;
  `TaskType.maps` keeping each Delivery to its map (the deal and the demands, on a fixture mode with two maps);
  `station_kinds()` (the default
  equals today's reflection on a fixture type, `DeliveryByMeaning`'s lists its drop-offs, `MarkerReader` snaps their
  markers, ZE3 sees them, `WireBudget` sizes `StationPlaced` by the longest station id of a kind with no palette); the
  `ClientModel` fold of DE7 (a station is not done between its `StationPlaced` and its items' `ItemSpawned`, nor after
  the first of its two items is delivered; done on the second's `PackageDelivered`); a round trip of the deal's events
  through the wire codec into `ClientModel` (two items on one drop-off), since no bot carries this type's events over
  the real wire; and, for the same reason, the host's per-peer filter over a dealt and delivered round of this type
  with a crew player and a dissident: every peer receives the same task events (§3: nothing in it is secret), which the leak test
  checks only for the greybox's Delivery. Delivery reads no role, so no role-swap check is new.
- **Content tests** (D2, DE12; on `content/` and the real maps): on every map this Delivery lists (House), one marker
  per drop-off tag and no marker of its item spawn tags inside a drop-off's cylinder (an item that would spawn
  delivered); each Delivery's `maps` naming one map of the base mode, the two apart, and neither the tutorial's (DD10:
  #825 has dealt it no task); ZE9's spacing (`tests/fixtures/tasks/fixture_zone_spacing.gd`, used by
  `house_markers_test.gd`) measured against the drop-offs too, through `station_kinds()`.
- **Scenarios and the leak test**: unchanged. They play today's Delivery on the greybox (DD9 (c)): every MVP scenario,
  `throw_scenarios_test.gd` (`release/m7`), the chaos bots and `bots` pass with no change to their code or data, which
  D2 shows by running them on its PR; the task-event lists stay. The tutorial's are not D2's (DD10):
  `content/scenarios/tutorial_stages.tres` (bots, on `levels/tutorial/`), `tests/unit/content/tutorial_mode_test.gd`
  and `tests/integration/levels/tutorial_map_test.gd` play or check `tutorial_mode.tres`, which deals `delivery.tres`
  today, and the lesson tests lean on its delivery (among them
  `tests/integration/client/app/game_tutorial_lessons_test.gd`, `tests/unit/client/tutorial/lesson_runner_test.gd` and
  `tests/unit/content/tutorial/tutorial_content_test.gd`; a sample, not the full list, which is #825's to draw up);
  #825, which deals the tutorial no task, changes them in its own PR, before D2.
- **Integration tests on House** (D5; bots do not play House, ARCHITECTURE §9.7): `Match` over `HostWorldQuery` with
  House's level: items put down from scripted commands at each drop-off are delivered, on the floor within the radius
  and, once D4's props stand, on their tops; one put down in the next room is not; horizontal `WorldQuery` rays from
  each drop-off marker find no wall within its radius (a delivery through a wall is the failure); every drop-off and
  storage marker reads without an error.
- **The client** (D3a, D3): the folds (pure), the drop-off and item looks, no material drawn through walls anywhere
  (`item_views_test.gd`'s check, its one exception gone with the marker), no destination for this Delivery's items, a
  `shot` preview of House's drop-offs and items; the M4 render checklist. The tests of what DD4 (a) removes (the
  marker's, in D3a) go with it, each named in its PR with the engineer's comment as the reason. In D2 (DE16), on a
  fixture mode of two maps and two types that each play on one: the lobby's ban chips, the guide's cards and the
  loading card's pool hold only the type of the picked map, and follow the picker when it changes.
- **Green** (#605): `verify` (lint and check) locally, then CI's full suite on the PR, for each issue of §8.

### 8. The split
Sizes as in M6 and M7: S up to about 400 changed lines, M up to about 900. Base: `release/m7` for every issue, which
holds what they build on (`StationState.contains`, ZE3's `_check_stations`, ZE7's `STATION` target, the throw and its
`delivery_throw_test.gd`). Effort: high for `core/`, `net/` and `tests/harness/`. These are proposals for the M7
backlog: the manager opens them from the PR's handoff, and none starts before the engineer says so (for now the track
only designs, [comment 6096108206](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096108206)).
The new type and the base mode's data come in one PR (D2): the House switches to it and the greybox keeps today's in
the same commit, so no commit has both Deliveries dealing on one map, or neither. D2 comes after #825, whose
tutorial deals no task, so it changes no tutorial file (DD10). The House's markers come first (D1),
so D2's fit check finds them. `TaskType.station_kinds()` changes no behaviour and serves the Generator and cooking too,
so it is its own issue (D2a) before D2. The engineer's answers (§5) leave no data of his to wait for: the names and the
description go into D2, and D4 removes the House's circles and adds its props. The marker through walls goes in an
issue of its own (D3a): its removal needs nothing else, so it may land first.

| Issue | Labels | Goal | Acceptance | Files | Depends on | Size |
|---|---|---|---|---|---|---|
| D1 | area:level | The drop-off markers on House | on House the `DiningTable`, `TerraceTable`, `GardenDropOff` and `Workbench` markers join their drop-off's group (DD1 (a): four; §5.1's tags, provisional); the greybox gets none (DD9 (c)); the circle markers stay until D4, and no new marker shares an (x, z) with one (the flat fake, §9.7); `levels/CLAUDE.md`'s spawn points gain the tags; every test that reads the maps still passes; provisional, named in the PR for the engineer's approval | `levels/house/rooms/` (dining room, terrace, garden, garage), `levels/CLAUDE.md` | none (DD1 answered); not while the car repair's level issue (#688) has an open PR on `garage.tscn`, scenes having one owner at a time (`levels/CLAUDE.md`) | S |
| D2a | needs-engine, area:core, area:server, area:client | `TaskType.station_kinds()`: one finder of a task type's station kinds | DE4 with no behaviour change: `TaskType.station_kinds()`, by default today's reflection over the type's `StationKind` properties; `MarkerReader.floor_tags_of`, ModeCheck's `_check_stations` (ZE3), `CircleViews.station_kind` and `WireBudget`'s `_Content` (station ids from `station_kinds()` over the mode's task types, not from colour demands) call it; unit tests: the default equals today's reflection on a fixture type, an override's kinds are snapped by `MarkerReader` and seen by ZE3, and a `tests/unit/server/wire_budget_test.gd` case whose longest station id belongs to a kind with no palette; every existing test passes unchanged; ARCHITECTURE §9.3 (the hook) | `core/content/task_type.gd`, `core/content/mode_check.gd`, `server/levels/marker_reader.gd`, `server/wire_budget.gd`, `client/world/circle_views.gd`, `tests/unit/`, `tests/fixtures/tasks/`, `docs/ARCHITECTURE.md` | none (ZE3's `_check_stations` is on `release/m7`, the base); the Generator (#695) and cooking (#701) may use it too, so it may land before either | S |
| D2 | needs-engine, area:core, area:client, area:content | Delivery by meaning, a second Delivery type, on House | §2's rules with the engineer's answers (DD2, DD5, DD6 and DD8, each (a)); DE2, DE3, DE5 (b), DE6, DE7, DE9 (c), DE12, DE13, DE15 and DE16: `DeliveryRoute` and `DeliveryByMeaning` (routes, deal, check, demands and checks; its override of D2a's `station_kinds()`, its routes' drop-offs, each once), today's `Delivery` class unchanged; `TaskType.maps` on both (the Generator's G8; D2 adds the part if it starts first): the House's type lists House alone, today's the greybox alone; the `ClientModel` fold of DE7; no wire change; the data: `content/tasks/delivery.tres` becomes Delivery by meaning (id `delivery`, DE15 (i)) with four routes and drop-offs (DD1 (a), DD3's 1 m radius and 2 m placeholder height, §5.1's ids and tags), the item kinds `wine`, `oil`, `gnome` and `parasol` (§5.1, the engineer's), each two-handed with the shared `package` spawn tag (DD6 (a), DD8 (a)) and §5.1's display names, §5.1's description; today's data in `content/tasks/colour_delivery.tres` (id `colour_delivery`, its `package` kind, circle, palette and description unchanged) with a copy of today's how-to card (`content/howto/tasks/`); both in the base mode's task types, the new kinds in its `item_kinds`; no tutorial file (DD10: #825 has dealt the tutorial no task); §7's unit tests; DE12's content tests in `tests/unit/content/`; ZE9's spacing (`tests/fixtures/tasks/fixture_zone_spacing.gd`'s `Spacing.circle`, which `house_markers_test.gd` calls) measuring the drop-offs too, through `station_kinds()`; every scenario, the chaos bots and `bots` pass with no change; the lobby's ban chips, the guide's cards and the loading card list only the types that play on the picked or the match's map (DE16), with client tests on a fixture mode of two maps; every test that loads the base mode still passes, each changed expectation (a test that names the id `delivery` or loads `content/tasks/delivery.tres` and meant today's Delivery) named in the PR; the players' body colours, the circle palette by the engineer's choice (#551), follow the palette to `colour_delivery.tres`: `client/player/body_colours.gd`'s doc comment, `tests/unit/client/player/body_colours_test.gd`'s path and its `as Delivery` cast, and ARCHITECTURE §4.7.50; ARCHITECTURE §3.3 (this type's RNG purposes and deal, its station ids by `routes`), §7.1.14, §9.3's station rows, §9.5.1 (the base mode's item kinds, its two Delivery types and what a host may ban), §9.5.4 (today's, the greybox's) and a new entry beside it for this type, §9.5.5, §9.6, §9.7 (the greybox keeps today's Delivery; the House's tested without bots), provisional files named for the engineer's approval | `core/tasks/delivery_by_meaning.gd`, `core/tasks/delivery_route.gd`, `core/content/task_type.gd` (if G8 has not landed), `client/net/client_model.gd`, `content/tasks/delivery.tres`, `content/tasks/colour_delivery.tres`, `content/items/`, `content/howto/tasks/`, `content/modes/base_mode.tres`, `client/ui/lobby_panel.gd`, `client/ui/guide_panel.gd`, `client/ui/howto_cards.gd`, `client/app/game_howto.gd`, `client/player/body_colours.gd`, `tests/unit/`, `tests/fixtures/tasks/`, `tests/integration/levels/house_markers_test.gd`, `docs/ARCHITECTURE.md` | D1; D2a; #825, the tutorial with no task (DD10); the Generator's G8 for `TaskType.maps` and G2 for the exact count (GE10), or D2 adds them if it starts first; G0 if landed (Delivery's `subtasks_setting` in `TaskType`) | M |
| D3a | area:client | No marker through walls | DD4 (a), the engineer's: `CircleViews`' destination marker goes, on every map (`_marker`, `_marked`, `_mark`, the accessors `marker()` and `marked()` that `item_views_test.gd` reads, `clear()`'s hiding of it, `MARKER_ABOVE`, `MARKER_SIZE` and its `no_depth_test` material, `client/world/circle_views.gd`), so no material in the client draws through walls; the greybox's packages and circles keep their colours, by which a player there still finds a circle; `item_views_test.gd`'s marker cases go, each named in the PR with the engineer's [comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718) as the reason, and its check that nothing draws through walls stays, with no exception left; the doc comments that name the marker (`circle_views.gd`, `hud_text.gd`); the M4 render checklist, the PR routed to `netcode-security-reviewer` too; a `shot` preview; ARCHITECTURE §4.7 (the HUD's line on the world marker, `CircleViews`' entry, the render checklist's summary of `no_depth_test`'s one use) | `client/world/circle_views.gd`, `client/ui/hud_text.gd`, `tests/integration/client/world/item_views_test.gd`, `docs/ARCHITECTURE.md` | none: it needs no other change, so it may land first | S |
| D3 | area:client | The client's view of Delivery by meaning | DE11: the drop-off's look (neutral, distinct from `ZoneViews`' zones and today's circles, dimmed when done), told from a circle by which of the client's own Delivery types lists its kind; each kind's look by id (a labelled box until the art: a case of wine, a canister of motor oil, a gnome, a closed parasol), never tinted by `ItemSpawned`'s white; today's circles and packages unchanged; the HUD: nothing on a base with the M6.2 UI (#489, in main since #758: its HUD shows no destination); on a base without it, the destination row and its swatch show nothing for this Delivery's items (DD4 (a)) and stay for the greybox's packages; the dev previews (`client/dev/items_preview.gd`, `screen_preview.gd`, `spectate_preview.gd`); the M4 render checklist, the PR routed to `netcode-security-reviewer` too; `shot` previews; ARCHITECTURE §4.7 | `client/world/`, `client/ui/hud_text.gd`, `client/ui/hud.gd`, `client/dev/`, `tests/unit/client/`, `tests/integration/client/`, `docs/ARCHITECTURE.md` | D2; D3a | S |
| D4 | area:level | The House's circles gone, and its drop-offs' props | the circle markers removed from House's ten rooms (today's Delivery no longer deals there, DE9); the greybox keeps its circles and gets no props (DD9 (c)), and `circle` stays in `levels/CLAUDE.md` for it; props in `levels/props/` at House's drop-offs: a dining table, a terrace table with a parasol stand and a workbench, with collision on layer 1 so an item rests on a top; each place told apart at a glance (the two tables unlike: a long indoor one with chairs, a round outdoor one with the stand); a `shot` of each room; house-map §6's Delivery rows as built; every test that reads the maps still passes; provisional files named for the engineer's approval | `levels/house/rooms/`, `levels/props/`, `docs/design/house-map.md`, `tests/unit/content/`, `tests/integration/levels/`, `docs/ARCHITECTURE.md` (§9.6) | D2; not while cooking's C5 (`kitchen.tscn`) or the car repair's level issue (#688, `garage.tscn`) has an open PR on a room D4 edits: it waits, or leaves that room's circle marker to the station PR that owns the room | S |
| D5 | needs-engine, area:core | Integration tests: Delivery on House | §7's House tests in the host's real world | `tests/integration/levels/`, `docs/ARCHITECTURE.md` (§9.7's House line) | D2; D4 for the tests on the props' tops | S |

### 9. What it means for the parallel work (nothing of theirs is edited here)
- **The Generator** (#679, PR #695): the same words (station kinds, `StationPlaced`, exact marker counts, "not a
  decision"). Delivery needs no `Interact`: it keeps "rests inside, however it got there", so a drop-off holds no rule
  and E there is `nothing_to_do`, as its §2 item 2 says of a delivery circle. G6's `CircleViews` filter ("a Delivery
  circle") reads both Delivery types' station kinds through `station_kinds()`; G3's sentence on circles below y = 0
  covers drop-offs too; G0's `subtasks_setting` in `TaskType` takes both Deliveries' `packages` with it; D2 reuses
  GE10's exact count. Room scenes have one owner at a time: D1 and D4 edit `garage.tscn` (the car repair's `CarLift`,
  #688) and D4 `kitchen.tscn` (cooking's C5), so each waits for an open PR on that room or leaves its circle marker to
  the station PR that owns it. The Generator's stations have no palette either, so `WireBudget`, which finds station
  kinds only through colour demands, misses them too: D2a moves it onto `station_kinds()` (DE4), and may land before
  the Generator. Its G8 (`TaskType.maps`, GE15) keeps the House's chains off the greybox, and splits Delivery by map:
  this one lists the House, today's the greybox (DD9 (c), DE9). Whether the zone task leaves the greybox too is its
  GD13, not this ADR's.
- **Cooking** (#682, PR #701): DE1 is cooking's own choice of item kinds over a variant field; Delivery keeps a spawn
  tag on every kind it places (CE18); a package at a cooking place stays `two_handed` under DD6 (a); DE4's
  `station_kinds()` serves its bed kinds too, if they are held in a list. The engineer's belt rule for every take (CD3
  (b) and CE21, built in its C2) reaches every Delivery item: a carrier's take of a one-handed item, from a box, a bed,
  the grill or the floor, goes onto the belt and the Delivery item stays in the hands, where today a pick-up from the
  floor leaves the package where the picked item lay; a pick-up of another Delivery item keeps today's swap (§4).
  Delivery's code changes nothing for it, and C2 owns its tests.
- **The M7 zone task** (`release/m7`): D2 is based on it (§8) and uses `StationState.contains`; ZE3's `_check_stations`
  moves onto `station_kinds()` in D2a; ZE7's `STATION` target works for a drop-off kind as it is; ZE9's spacing
  measures zones against drop-off markers too (DE12); ZD7's "a palette apart from the circles'" no longer matters on
  the House, whose circles go (D4); ZD11's look clash still does (DE11).
- **The M6.2 UI** (in main since #758; `release/m7` gets it at its next sync with main): #489's HUD shows no
  destination, as DD4 (a) wants, and its hand slot shows a two-handed item's name (`client/ui/hud_slot.gd`), which is
  how a player tells where the item goes. #520's Delivery card art (frames 2 and 3: "check the sign on the package",
  "find the room with that sign") names a sign that DD4 (a) leaves out: the UI track's to redraw, routed by the manager
  (no issue of §8); under DE15 (i) it stays keyed to the House's Delivery, and the greybox's `colour_delivery` gets a
  copy of today's card. The tutorial's `tutorial.step.deliver.how` ("Find the room with the sign that's on the
  package", `client/i18n/strings.csv`) names one too; it is #825's, whose tutorial deals no task (DD10). #253's map
  screen lights a type's zones from `item_spawn_tags()`, which returns every route's item tag (storage on House, as
  today); the copy deck has no `item.<id>` key for the new kinds (`ContentNames`, `client/ui/content_names.gd`, falls
  back to the display name), so their display names show until it adds keys; `task.delivery` stays under DD7 (a).
- **The shared total** (#738, the engineer's answers on PR #695): the HUD's "Tasks x / y" and the task screen's
  "Shared progress" go; Delivery's row keeps its own count ("2 / 6") and is struck through once every item is
  delivered. Delivery emits `TaskState` as today, which is all the row needs; whether `TaskProgress` stays on the wire
  is #738's.
- **The greybox as a test bench** (#767, the engineer's, M7 backlog): this design adds nothing to the greybox, and
  today's Delivery stays there for the scenarios and the leak test. D2 does not wait for #767, nor #767 for D2: until
  #767 lands a host may still pick the greybox and play colours there.
- **The M4 client design**: DD4 (a) removes its D10 (b) marker and the one exception in its render checklist's item 5;
  that ADR records the change and points here, and D3a builds it.

### 10. Needs the engineer
Nothing is open. He answered DD1 to DD8 in
[comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718); DD9 (c), the
drafts of §5.1 and his approval of the design in
[comment 6100696677](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6100696677); and DD10 in
[comment 6108665402](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6108665402): none of its options,
the tutorial deals no task at all and teaches only movement and the basic mechanics, its rework the M7 backlog issue
#825 (his call there: which mechanics, the steps and their words), which D2 comes after (§5). Approved in the PRs
that build them, as provisional content under the MVP content ADR: DD3's 2 m height (a placeholder, "not a decision",
in D2), §5.1's drop-off ids and tags and DE15's `colour_delivery` (D2), and the House's furniture props (D4). The issue
texts D1, D2a, D2, D3a, D3, D4 and D5 (§8): the manager opens them as M7 backlog proposals; none starts before he says
so.

## Alternatives
- **Keep the colours beside the meaning** (each kind with a fixed colour, its place in that colour): the engineer said
  not by colours.
- **Deliver with E at the place** (the cooking ADR's CD9 (a) for plates): the engineer's #32 rule, "however it got
  there", stays: a drop at a death or a later throw counts; this change is about which place, not how an item arrives.
- **One kind with a variant field** (DE1 (b)): a field on every item, the wire and the HUD for one task type.
- **The destination on the item kind** (DE2 (b)): a generic item kind would name a task's station.
- **One drop-off kind told apart by marker names** (DE3 (b)): a swapped marker would silently swap places.
- **Rooms or box-shaped zones as places** (DD3 (b), DE3 (c)): a second shape in every station test and rooms in
  `core/` before the room record (#306); his to ask for under DD3.
- **Drop the colour from the wire** (DE5 (a)): the greybox's Delivery still needs it (DD9 (c)). **Drop the station
  too** (DE5 (c)): the binding moved into every reader's copy of the mode.
- **A `DropOffDone` event** (DE7 (b)): `ItemSpawned` and `PackageDelivered` already tell it.
- **New bot targets for several kinds** (DE8 (a)): no bot plays this Delivery (DD9 (c)).
- **Station scenes for the places** (DE10 (b), (c)): scenes with nothing to drive and no facing that matters.
- **The bots on a fixture mode** (DE9 (b)): the scenarios would stop testing the base mode.
- **A marker without colour over the held item's place** (DD4 (b), the recommendation he did not take), **a sign**
  (DD4 (c)) or **a HUD line** (DD4 (d)): the engineer chose by meaning alone, and no marker through walls anywhere.
- **This Delivery on the greybox too, with props or on bare markers** (DD9 (a), the recommendation he did not take, and
  (b)): the greybox becomes a test bench only (#767), so no player there needs to read a meaning, and the bots keep
  testing what they test now.
- **One class for both Deliveries, or a subclass** (DE15 (b), (c)): a change for the House would reach the greybox's
  scenarios, or unused inherited exports to police. **Today's id kept for the greybox** (DE15 (ii)): what players see
  would key on a type nobody plays.
- **A description that lists the routes** (§5.1): a pointer DD4 (a) left out, wrong on a map that places them
  otherwise.

## Consequences
- The MVP rules ADR records the engineer's change (its Deciders line, the Delivery bullet, the settings' demand, the
  HUD's destination, the rows "Delivery circles per match" and "Distinct circle colours"), each pointing here and
  saying that the greybox keeps today's rules (DD9 (c)). When this ADR is accepted its Status says so, and the issue
  that builds a rule here updates the line of the MVP rules it replaces.
- The M4 client design records DD4 (a) at its D10 (b) and its render checklist's item 5: once D3a lands, nothing in
  the client is drawn through walls, and a new marker through walls is a design change, not an exception to cite.
- ARCHITECTURE §9.5.4 points here, §9.8 gains the row "Delivery by meaning" and §10 its settled row; GDD §8 gains
  Delivery's section with the engineer's answers. house-map §6's Delivery rows name each place's item (DD1 (a), §5.1)
  and where it plays (DD9 (c)), and D4 updates them as built.
- When D2 lands, ARCHITECTURE gains an entry for `DeliveryByMeaning` beside §9.5.4's, and its Delivery entries
  (§3.3, §7.1.14, §9.5.4, §9.5.5) and §9.7 say which map each Delivery plays, with their `Built in` lines.
- No protocol change (DE5 (b)): `ItemSpawned` and `StationPlaced` keep their rows; this type sends white.
- Every map this Delivery lists needs one marker per drop-off tag: House gets them in D1, and a later map that lists it
  gets them with its level pieces (`new-level-piece`). The greybox keeps its circles.
- Between D2 and D3 the client draws the House's items as labelled boxes and its drop-offs in today's circle look, in
  white, and until D3a the marker still points through walls: playable, but no playtest until D3a and D3 land.
- 2026-10-22 (#1307): ARCHITECTURE §9.5.25 names its code, no longer its builds: D2 (#828), the House's drop-off
  furniture in D4 (#831), the client's view in D3 (#830), the study's last circle removed in #1059.
