# Delivery by meaning (#683): items carried to their own places instead of colour-matched circles

- **Status:** Proposed on 2026-10-10. Nothing here is built, and nothing will be until the engineer says so: for now
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
  more); the garden's and the terrace's items and the description are drafted here for his approval (§5.1). His later
  answers on the House track touch Delivery too (§9): the flat greybox keeps only the basic Delivery
  ([PR #695, comment 6096108206](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096108206)), the
  shared task total goes
  ([comments 6096176652](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096176652)
  and [6096191814](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096191814), #738), and every take
  beside a two-handed item goes onto the belt
  ([PR #701, comments 6096140448](https://github.com/xperiaroco2/prime-game/pull/701#issuecomment-6096140448) and
  [6096157421](https://github.com/xperiaroco2/prime-game/pull/701#issuecomment-6096157421)). One question is left, DD9
  (§10); the design proceeds with its recommendation, which can be reverted. The DE items are technical, the
  game-design manager session's to decide and report (tier (a)): decided here, each revertible in its issue.
- **Date:** 2026-10-10
- **Deciders:** the engineer (the rules: DD1 to DD8, answered on 2026-10-10 in PR #713's comments; DD9 open); the
  game-design manager session of #676 (DE1 to DE14). Designed by the agent of #683, on the engineer's word (#683; the
  track's kickoff on #593, comment 6088751685).
- **Amends:** [MVP rules](2026-09-29-mvp-rules.md) (Delivery: a circle per package placed at random, a colour per
  package, the palette of 10) and [the M4 client design](2026-10-01-m4-first-person-client.md) (D10 (b), the destination
  marker drawn through walls, and its render checklist's one exception in item 5: DD4 (a), the engineer's). Both record
  the change and point here; D3a removes the marker from the client.
- **Builds on:** [MVP rules](2026-09-29-mvp-rules.md) (Tasks: the shared Delivery of #79; the engineer's correction in
  #32, "rests inside, however it got there"), [content API v0](2026-09-29-content-api-v0.md) (task types are classes
  with settings), [vision revision 1](2026-10-01-vision-revision-1.md) (V4's "living", V13's two-handed package, hiding
  packages as the dissidents' sabotage), [the M4 client design](2026-10-01-m4-first-person-client.md) (its render
  checklist, item 5), [the zone task ADR](2026-10-09-m7-zone-task.md) (#36, built on `release/m7`:
  `StationState.contains`, ZE3's station checks, ZE7's `STATION` target, ZE9's spacing, ZD11's looks), [the throwing
  ADR](2026-10-09-throwing-held-items.md) (#37, built on `release/m7`: a thrown package counts, the engineer's TD4 (a)),
  the Generator ADR (#679, proposed in PR #695: GE10's exact marker counts, GE11's station scenes, GE15's
  `TaskType.maps` in its G8, G0's subtasks setting, G3's flat-fake rule, G6's `CircleViews` filter), the cooking ADR
  (#682, proposed in PR #701: item kinds, not a variant field; CE18's optional spawn tag; CE21's belt rule for every
  take), #738 (the shared task total goes), [level piece conventions](2026-10-09-level-piece-conventions.md), [MVP
  content built by the engineer](2026-09-29-mvp-content-built-by-the-engineer.md) (content and levels are provisional,
  approved in their PRs), [the House map](../design/house-map.md) (§2 decision 5, §6's Delivery rows, §7's routes),
  [tests on CI](2026-10-09-tests-on-ci-local-lint-and-check.md) (#605: what "green" means in §8)
- **Numbering:** DD and DE are this ADR's own; the issues are D1, D2a, D2, D3a, D3, D4 and D5 (§8), proposals for the
  M7 backlog, which the manager opens from the PR's handoff after the engineer approves them.

## Context
Today (`core/tasks/delivery.gd`, `content/tasks/delivery.tres`; ARCHITECTURE §7.1.14, §9.5.4): one shared task of N
packages, N the host's `packages` setting (1 to 10, default 6). The deal places N circles on random `circle` markers,
each in a random colour of a 10-colour palette, puts N packages on random free `package` markers, and binds each
package to a random circle, whose colour it takes. A package resting inside its own circle's cylinder (radius 1 m,
height 2 m), however it got there, is delivered and locked. The client paints the package and its circle in that colour,
the HUD shows a swatch with "Deliver to the circle of this colour", and while the own player carries a package a marker
floats over its circle, drawn through walls (D10 (b)). The wire carries the colour in `StationPlaced` and, for a
package, its circle and colour in `ItemSpawned`. On House (#626): 10 `package` markers in storage, 10 `circle` markers in
ten rooms; house-map §6 names Delivery's points: the wine rack and the boxes in storage (sources), the dining table (the
wine's drop-off), the terrace table, the garden and the garage's workbench (drop-offs), as plain markers under each
room's `Stations` node with no group.

The engineer's direction changes the binding: what an item is decides where it goes, as fixed data, where today a
colour drawn each round does. For the engine that means:
- several item kinds take part in one Delivery, where today one (`package`) does;
- each kind has a fixed place in the data, where today the deal draws a circle;
- a place stands where the map puts it, the same every round, where today circles move;
- colour leaves the rules, the wire and the client.

What stays (§9.5.4): the task is shared and only living players deliver (#79, V4); one item is one subtask; an item
counts when it rests inside its place, however it got there (a put-down, a swap, a drop at a death or a leave, a throw:
the engineer's TD4 (a), built on `release/m7`); a delivered item is locked; nothing in Delivery is secret (#79); the
dissidents sabotage by hiding items.

## Decision

### 1. The mapping (`new-mechanic` step 3)

#### 1.1 Each rule to its engine part

| # | What #683 needs | Engine part | Exists? |
|---|---|---|---|
| 1 | Storage holds different items | one `ItemKind` per kind of item (DE1): its id, display name (the HUD's hand slot), spawn tag and `hands` | `ItemKind` exists (`core/content/item_kind.gd`); the kinds D2: `wine` and `oil` (his words) and §5.1's drafts for the garden and the terrace (DD1 (a)) |
| 2 | Each kind goes to its own place, by meaning | `DeliveryRoute` (DE2), a sub-resource of the task type: `item` (an `ItemKind`) and `drop_off` (a `StationKind`); `Delivery.routes` lists them | missing: D2 |
| 3 | A place on the map | one `StationKind` per place (DE3), the house-map's "drop-off": its own id and spawn tag, `radius_m` and `height_m` (DD3), no palette; exactly one marker of its tag per map | the class exists (`core/content/station_kind.gd`); the markers D1; the data D2 |
| 4 | How many items, and of which kinds | the deal: N items, N the `packages` setting, their kinds spread over the routes in a random order (DD2) | the setting exists; the draw D2 |
| 5 | Delivered at its own place, however it got there | the check on `item_rested`, the same shape: an item of an undone subtask resting on the ground inside its drop-off's cylinder (`StationState.contains`) is delivered and locked | `Delivery.on_fact` exists; `StationState.contains` on `release/m7`; D2 adapts it |
| 6 | Not by colours | no palette and no colour demand for drop-offs; `ItemSpawned` drops its colour (DE5); the client draws neutral looks (DE11) | D2, D3 |
| 7 | An item at a wrong place | nothing happens (DD5) | exists: a package in another circle does nothing today |
| 8 | Packages take both hands | `ItemKind.hands` 2 for every Delivery kind (DD6) | exists (M4-5) |
| 9 | A player tells where an item goes | by meaning alone (DD4 (a), the engineer's): the item's look and its name in the hand slot (DE1); nothing points to its place, and the one marker the client draws through walls today, over the held package's circle, goes | `CircleViews`'s marker exists (`client/world/circle_views.gd`); its removal D3a |
| 10 | The reader, the mode check, the wire budget and the client find the drop-offs | `TaskType.station_kinds()` (DE4) in place of the four finders of a type's station kinds (three reflections over its `StationKind` properties and `WireBudget`'s colour demands), which miss kinds inside a route list | missing: D2a (Delivery's override in D2) |
| 11 | Bots find an item and its place from what they were told | `ScenarioTarget`: `PACKAGE` reads any Delivery item, `CIRCLE_OF_HELD` its drop-off (unchanged), a new `NEAREST_PACKAGE` (DE8) | D2 |
| 12 | The flat test level and the bots' scenarios keep working; the greybox keeps only the basic Delivery (his read-back of the Generator ADR's GD7) | the greybox plays this Delivery, the base mode's one (DD9): one flat marker per drop-off tag (DE9), and a greybox prop at each so a player there tells the places apart (DD9 (a), open) | D1; the props D4 |
| 13 | On House | the four plain markers at house-map §6's points join their drop-off's group (DE10) | the markers exist (`DiningTable`, `TerraceTable`, `GardenDropOff`, `Workbench`, level 0); D1 |
| 14 | Tested on House, which bots do not play (ARCHITECTURE §9.7) | integration tests in the host's real world (D5) | missing |

#### 1.2 Today and after

| | Today | After | Why |
|---|---|---|---|
| Item kinds | one, `package` | several (DD1) | "different items" |
| Which place an item goes to | drawn each deal, a random permutation (`tasks`) | fixed in the data by kind (`routes`) | "by the location's sense" |
| Places | N circles on random `circle` markers, anew each round | one station per drop-off in use, on its own marker, the same every round | a place by meaning stands where it is |
| Colours | a 10-colour palette: demanded, sent, painted | none | "not by colours" |
| What points to a place | the HUD's swatch of the circle's colour, and a marker over the circle drawn through walls (D10 (b)) | nothing: the item's look and its name (DD4 (a)) | "by meaning alone", and no marker through walls any more |
| RNG purposes | `circles`, `packages`, `tasks` | `packages`, `tasks` | no placement or colour draw is left |
| A place done | when its one package is delivered | when every item routed to it this round is delivered (DE7) | several items may share a place |
| Events | `StationPlaced`, `ItemSpawned` (circle, colour), `PackageDelivered`, `TaskState`, `TaskProgress` | the same classes; `ItemSpawned` without its colour | one wire change (DE5) |

### 2. The rules as the engine runs them (with the engineer's answers)
1. **The deal** (when `DealTasks` draws Delivery). N is the `packages` setting; with N = 0 the task has no subtasks and
   is done (#79). Otherwise, in these steps (K the number of routes):
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

   Then `StationPlaced` per station in id order, `ItemSpawned` per item in id order (with its drop-off station, DE5),
   then `item_rested` (spawn) per item. A map short of markers deals nothing and logs a match error, as today; the fit
   check keeps a match from getting there. Station ids follow `routes`, not the level, which changes ARCHITECTURE
   §3.3's "item and station ids are assigned in spawn-point order" for Delivery's drop-offs (each is the one marker of
   its tag, so no level order applies across them): D2 rewrites that sentence and §3.3's Delivery deal with it.
2. **The check**, on `item_rested`: an item of an undone subtask resting on the ground inside its own drop-off's
   cylinder is delivered: locked (`PickUp` gets `unavailable`), its subtask done, and its drop-off done once every item
   routed to it this round is delivered (DE7); then `PackageDelivered(item, station)`, `TaskState`, `TaskProgress` and
   `subtask_done`, in that order, as today (`TaskProgress` as long as #738 keeps it).
3. **Anything else at a place**: an item resting inside another route's drop-off, or any other item in a drop-off, does
   nothing (DD5 (a)).
4. **Nothing else changes**: any living player carries any item; every Delivery item is two-handed (DD6 (a)), so none
   ever rides a belt; a dying or leaving carrier drops it at the body; a held item never counts. A carrier who takes a
   one-handed item puts it onto the belt and keeps the Delivery item in the hands: the engineer's belt rule for every
   take, which cooking's C2 builds (§4, §9); Delivery adds nothing for it.

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

Nothing in it is secret, as since #79: the per-peer filter (§5) gains nothing, and the leak test's task-event lists
stay as they are.

### 4. Edge cases

| What happens | What the engine does | Why |
|---|---|---|
| An item rests at another kind's place | nothing; anyone may carry it on | DD5 (a); today's rule for another circle |
| Two items of one kind, one place | each counts when it rests there; the place dims after the second | DE7 |
| N below the number of routes | the routes drawn first get an item; the other places get no station and show nothing this round | DD2 (a), DE3 |
| N above the number of routes | some places take two or more items | DD2 (a) |
| A downed carrier crawls into the item's place and gives up | the item drops at the body: delivered if it rests inside | "however it got there" (#32); vision revision 1 notes it |
| A package marker inside a drop-off's cylinder | an item of that place's kind spawning there is delivered in the deal | as today; the content test of DE12 keeps it off every map of the base mode |
| A drop-off's cylinder reaches through a wall | an item resting behind the wall, inside the radius, counts | as a circle today; a level convention and D5's wall test (§7) |
| E at a drop-off | `nothing_to_do`: a drop-off holds no `Interact` rule | the Generator ADR's §2 item 2 says so for a delivery circle; Delivery needs no use |
| A map with no marker for one route's drop-off | the fit check refuses the lobby while N > 0; with N = 0 it plays | DE6 |
| A delivered item | locked; `PickUp` gets `unavailable` | as today |
| An item thrown into its place | delivered once it comes to rest inside | "however it got there"; the engineer's TD4 (a), built on `release/m7` (`delivery_throw_test.gd`) |
| A carrier picks up a loose one-handed item (a knife, an ingredient) | it goes onto the belt, a full belt's item put down at the carrier's feet first; the Delivery item stays in the hands. Today the carried package rests where the picked item lay | the engineer's belt rule for every take (PR #701, comments 6096140448 and 6096157421; cooking's CE21, built in its C2); the carrier still cannot draw the knife (`Swap` refuses a two-handed hand item, V13) |
| A carrier picks up another Delivery item | today's swap: the carried one rests where the picked one lay, and is delivered if that spot is inside its own place | the belt holds only a one-handed item (cooking's CE21) |
| A taker's full belt empties at its feet inside a place | never a Delivery item: none rides a belt | DD6 (a) |
| The oil carried to the car on the lift, beside the garage's workbench | nothing for Delivery: only the workbench's cylinder counts (on House the workbench, at 70, 37, is 7.2 m from the car, at 64, 41); the car is the car repair's station (#688, PR #709) | DD5 (a); two chains in one room, each with its own place |

### 5. DD items (the engineer's: game rules and taste)
The engineer answered DD1 to DD8 on 2026-10-10
([PR #713, comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718)): every
recommendation stands except DD4, which he answered otherwise. The options stay for the record; the last column is what
holds now. DD1's garden and terrace items and DD7's description he left to the agents to draft for his approval: §5.1.
DD9 comes from his later answer on the greybox (PR #695) and is open (§10).

| # | Question | Options | Trade-offs, and the failure each prevents | Decided |
|---|---|---|---|---|
| DD1 | The item kinds and their places (#683's open item 1; his examples; the question relayed in comment 6090227509) | (a) one kind per house-map §6 drop-off, four: the wine to the dining table (§6's "the wine" row), the oil to the garage's workbench, his garden item to the garden drop-off, his item for the terrace table; (b) his three examples only: the wine to the living room (a new drop-off there), the oil to the garage, his item to the garden; the terrace table leaves Delivery; (c) (a) or (b) and more places: rooms that hold a circle marker today (the kitchen, the study, the bedrooms) | each place is a marker the fit check demands on every map of the base mode, the greybox included (DE9). (a) keeps §6 and its measured routes (§7: the wine 26 m, the garage 60 m, the garden 57 m) and sends items to three sides; the terrace's item and the garden's need names. (b) follows his words to the letter; the living room is "a place where everyone crosses" (house-map §4), so a delivery there is watched by many, and its route is not measured. (c) more places dilute "by meaning" (what belongs in a bedroom?) and add markers to every map. Either way the Package kind (`package`) leaves the base mode unless he names it one of the kinds (house-map §6 has "Boxes (source)") | **(a), the engineer** ([comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718), the recommendation): four kinds, one per house-map §6 drop-off, the wine at the dining table and the oil at the garage's workbench; the garden's and the terrace's items he left to the agents to draft, for his approval in PR #713 (§5.1). The `package` kind leaves the base mode's Delivery |
| DD2 | How many items a round, and whether the host's setting picks it (#683's open item 2; #256) | (a) N items, N the host's `packages` setting as today (1 to 10, default 6), the kinds spread over the routes in a random order: every place gets one before any gets a second; (b) one item per place, N at most the number of routes: the setting picks how many places, drawn at random; (c) every kind once a round, no setting | (b) caps the task at the routes (4 on House with DD1 (a)), so today's default of 6 is out of range, and the hiding sabotage has fewer items to hide. (c) drops a host setting (#256: every task type has its subtask count) and makes the map's routes the difficulty. (a) keeps the setting, its bounds and the MVP scenarios' counts (`crew_delivers_every_package` delivers 6), and sends players to every place before any repeats (house-map §8: tasks spread the players). In (a) and (b) which places get an item when N is below the routes is drawn each round, so nobody plays one memorised route (as the Generator's GD2 (a)) | **(a), the engineer** ([comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718), the recommendation) |
| DD3 | What counts as "at its place", and how big a place is (#683's open item 2) | (a) inside a drop-off's cylinder standing on the floor at the place's marker, as a circle today: on the floor around the table or bench, or on its top, within the height; the radius and the height in the data (a circle's 1 m, game design since #79, and 2 m, a placeholder); (b) anywhere in the room or area ("to the garage", "to the garden"): a box-shaped drop-off sized to the room, a new station shape; (c) only on the furniture's top | (b) forgives where in the room, at the cost of a second shape in every station test (`StationState.contains`, the client's look, the spacing tests), and on House the garden is 32 x 28 m: a garden item counts as it crosses the fence, with no walk to a spot. (c) needs a marker on the top, and an item put down on the floor by the table is ignored without a word. (a) is what house-map §6 places (drop-offs at a table and a bench) and what a circle does, and players see where it is (DE11) | **(a), the engineer** ([comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718), the recommendation): 1 m and 2 m for every drop-off, placeholders "not a decision"; a wide place (the garden) may take a larger radius in the data (0.2 to 10) |
| DD4 | How a player tells where an item goes (#683's open item 3: does the through-walls marker stay) | (a) by meaning alone: the item's look and its name in the hand slot; (b) (a) and the marker over the held item's drop-off, drawn through walls as today (D10 (b)), in one neutral look; (c) (a) and a sign: the place's picture on the item and at the place, which #520's Delivery card art on `release/m6.2` draws ("check the sign on the package", "find the room with that sign"); (d) (a) and a HUD line naming the place | (a) is the "open knowledge" pillar's finding by looking, and meaning is the point of the change; but a new player on a four-level map may not know where the garden drop-off is, or that the oil goes to the workbench. (b) keeps his answer D10 (b) of 2026-10-01: the marker shows only a fixed, public place, so it reveals nothing, and the render checklist's one exception stays one. (c) waits for the art and the room record (#306): a sign per place, on each item's look and at the place. (d) the M6.2 HUD (#489) shows no destination, by the UI handoff, so a HUD line would undo it | **(a), the engineer, not the recommendation** ([comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718)): by meaning alone, and no through-walls markers any more: the one the client draws today, over the own package's circle (`client/world/circle_views.gd`), goes too (D3a), and with it the M4 render checklist's one exception (item 5), so nothing in the client is drawn through walls |
| DD5 | An item resting at a wrong place | (a) nothing: it lies there and anyone may pick it up (today's rule for a package in another circle); (b) a sign to everyone in sight: a sound or a red flash at the place, client only, nothing in the rules; (c) refused: it is moved off the place, or back to storage | (b) is a client effect on public facts (every client knows the item's kind and the place's routes); it adds nothing for a dissident to learn as long as it keeps the M4 render checklist: the sound through `SoundChooser` and `WorldSounds`, within 12 m and muffled behind walls (item 10), the flash depth-tested and in `SightHider.GROUP` (items 3 and 5), or players would learn through walls where someone just put an item down. (c) a new rule and a new placement path, and a dissident can no longer leave an item at a wrong place as a decoy. (a) needs nothing built | **(a), the engineer** ([comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718), the recommendation); (b) stays a cheap later add if a playtest asks |
| DD6 | Hands (today's description: "Packages take both hands") | (a) every Delivery item two-handed, as the package today; (b) per kind in the data (one-handed wine, a two-handed crate); (c) every Delivery item one-handed | with (b) or (c) a one-handed item rides the belt: one player carries two at once, or carries one with a knife in the hand, which halves the walks and the exposure the task is built on (V13: a carrier cannot draw a knife). The Generator's and cooking's busy-hands rules refuse a two-handed carrier a station's use (a take from a station or the floor goes onto the belt, the engineer's later belt rule, §4). The scenarios `two_handed_pickup_with_a_full_belt` and `refusals` rely on a two-handed package, and under (b) which kind a scenario meets is the deal's draw | **(a), the engineer** ([comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718), the recommendation) |
| DD7 | The name, the description and the lobby label (#683's open item 4) | the name: (a) "Delivery" stays (M6.2's copy deck already has `task.delivery`, "Delivery" and "Доставка", and its card art); (b) a new name in his words. The description: the mode check refuses an empty one; main's task screen shows it, `release/m6.2` shows it nowhere since #253. The label "Packages (Delivery)" of the `packages` setting | today's description ("Carry each package to the circle of its colour. Packages take both hands.") is wrong once colours go, so D2 cannot keep it | **(a), the engineer** ([comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718), the recommendation): "Delivery" and the label stay; the description he left to the agents to draft, for his approval in PR #713 (§5.1) |
| DD8 | Where each kind starts in storage | (a) any kind on any storage marker: one spawn tag shared by every Delivery kind, as `package` today; (b) each kind at its own source, the wine at the wine rack and the rest at the boxes (house-map §6): a spawn tag per source | (a) a bottle may lie by the boxes. (b) the look follows §6, and House's ten storage markers split between the sources; the demands follow either way (DE6) | **(a), the engineer** ([comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718), the recommendation): only the look differs, and the data alone switches to (b) |
| DD9 | What the flat greybox's "basic Delivery" is, and how its places show what they are. His read-back of the Generator ADR's GD7 ([PR #695, comment 6096108206](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096108206)): the greybox "keeps only the basic Delivery and nothing else"; all new mechanics come with M7 | (a) this Delivery, the base mode's only one, with a greybox prop beside each of its four drop-off markers that says what the place is: a dining table, a terrace table with a parasol stand, a patch of lawn with a low fence (the garden), a workbench (D4's props, provisional); (b) this Delivery on bare drop-off markers; (c) today's colour Delivery on the greybox and this one on House: two Delivery task types, each listing its map (the Generator's G8, `TaskType.maps`) | The design reads his words as (a) or (b): #683 took colours out of Delivery itself ("we have not gone by colours for a long time"), its open item 5 asks the flat level and the bots' scenarios to keep working with the change, and Delivery by meaning reworks the one task the greybox keeps; it is not one of the House's new chains. (b) is all the bots need, but the greybox is the base mode's first map, where the default lobby lands: by meaning alone (DD4 (a)), a player there sees four drop-offs that look alike and must try each, since a wrong place says nothing (DD5 (a)). (c) reads "basic" as "today's": the engine keeps the palette, `ItemSpawned`'s colour and the circle deal beside the routes, the bots test a Delivery nobody plays on House, and the client draws both looks | **Open** (§10). The design proceeds with (a): D1's markers serve (a) and (b) alike, and the props (D4) are level data, so the level alone reverts it; (c) would add a task type and keep D2 from removing the colours |

#### 5.1 The drafts for his approval (DD1, DD7)
The engineer left the garden's and the terrace's items and the description to the agents (comment 6095445718). Each
draft below is provisional: he approves or replaces it in PR #713, and D2 carries what he approves. Each item passes one
test: a player who sees it for the first time sends it to one place only, and to none of another chain's stations
(the greenhouse's herb beds, the kitchen, the car).

| What | Draft | Why this one | Rejected |
|---|---|---|---|
| The garden's item | **Garden gnome** (id `gnome`): a large one, carried in both arms | belongs only in a garden; on House the greenhouse's beds take herbs (cooking), so nothing else there wants it; the cringe-fun vibe (GDD §1) | a sack of compost or a watering can: either reads as the greenhouse's |
| The terrace's item | **Parasol** (id `parasol`): closed, long, carried in both arms | it stands in an outdoor table, the terrace table's; the dining table indoors takes the wine, and the garden has no table | deck chair cushions (the garden's too); a crate of lemonade (a drink, which reads as the dining table's, like the wine) |
| The oil's name | **Motor oil** (id `oil`, his word): a canister | "Motor" so nobody carries it to the kitchen, where the burgers are made | "Oil" alone |
| The wine's name | **Wine** (id `wine`, his word): a case of bottles | his word | none |
| The description | "Carry each item from storage to the place where it belongs. Every item takes both hands." | by meaning alone (DD4 (a)), it names no place; a task type's description is the same on every map, and the greybox has no dining room | a description listing the four routes: a pointer DD4 (a) left out, and wrong on a map that places them otherwise |

The drop-off station kinds' ids and spawn tags are technical (DE3), provisional until D1 and D2 land:
`drop_dining_table`, `drop_terrace_table`, `drop_garden` and `drop_workbench`; the prefix keeps them apart from any
later station of the same room (a car repair workbench, say), which ZE3 would refuse as a tag used twice.

### 6. DE items (technical: the manager decides and reports)

| # | Choice | Options | The failure it prevents | Decision |
|---|---|---|---|---|
| DE1 | The item kinds | (a) one `ItemKind` per kind, each with its id, display name, spawn tag and `hands`, its look by id; (b) one `package` kind with a variant field on the item and the wire | (b) a field on every item, the wire and the HUD's hand slot for one task type: the cooking ADR rejected it for its ingredients. (a) reuses `ItemSpawned`'s `kind`, the HUD's display name and `client/world/item_view.gd`'s look by kind id (a labelled box for a kind it has no look for), as they are | (a) |
| DE2 | The binding | (a) `Delivery.routes: Array[DeliveryRoute]`; `DeliveryRoute` (`core/tasks/delivery_route.gd`, a sub-resource with no behaviour): `item: ItemKind`, `drop_off: StationKind`; one drop-off may serve several routes, one kind may be in one route only; (b) `ItemKind.destination`; (c) two parallel lists of kinds and drop-offs | (b) a generic item kind would name one task type's station, though an item may serve two types later. (c) two lists that must agree by position, the failure the cooking ADR's CE6 (b) names. (a) one row per "this goes there", which the check reads alone | (a) |
| DE3 | The places | (a) one `StationKind` per place, its own id and spawn tag (both provisional, `drop_<place>`, §5.1), no palette; exactly one marker of its tag on a map; a station only for a drop-off a dealt item needs; (b) one `drop_off` kind with several markers told apart by a node name or metadata; (c) rooms in `core/` (the room record, #306) | (b) `MarkerReader` reads groups, not names: a renamed or swapped marker would send the wine to the garage without an error. (c) rooms in `LevelLayout` and a box test before #306 exists. "Exactly one" is the Generator's exact count (GE10): a second garden marker would stand unused, and a player delivering there gets nothing; the fit check refuses more as well as fewer. Placing only the drop-offs in use keeps `StationPlaced` the list of this round's places, so the client draws no place nobody delivers to | (a) |
| DE4 | How the engine finds a task type's station kinds | (a) `TaskType.station_kinds() -> Array[StationKind]`: by default every `StationKind` property of the type (today's reflection, moved here once), Delivery's override its routes' drop-offs, each once; `MarkerReader.floor_tags_of` (`server/levels/marker_reader.gd`), ModeCheck's station checks (ZE3's `_check_stations`, on `release/m7`), the client (`CircleViews.station_kind`) and `WireBudget` (`server/wire_budget.gd`'s `_Content`, which today collects the mode's station ids from `demands.colours.keys()`) call it; (b) teach the three reflections to walk arrays of sub-resources | the three reflections read only a type's `StationKind`-typed properties: a drop-off inside a route list would not be snapped to the floor (its cylinder would start at the marker's hand-placed height, §9.6), would escape ZE3's duplicate check, and would get the client's fallback size. `WireBudget` finds only the station kinds that demand colours: once DE6 drops Delivery's colour demand, `StationPlaced`'s worst case is sized from the zones' kinds alone, or not at all, and `SettingsChanged`'s shortfall list shrinks, with no test failing. (b) three copies of a deeper walk, a fourth reader repeats it, and `WireBudget` stays apart. (a) also serves any later type that holds station kinds in a list (the cooking ADR's bed kinds, CE6, if held in one) | (a) |
| DE5 | The wire | (a) `ItemSpawned` keeps `has_station` and `station` (the item's drop-off station) and drops `colour`; `StationPlaced` keeps its colour (zones use it; a drop-off's is white); `PackageDelivered` stays; one protocol bump; (b) no wire change: `ItemSpawned` sends white; (c) `ItemSpawned` drops `station` too: the client finds the place from its own mode (kind, route, drop-off kind, its one station) | (b) a field that is always white, which a client could still paint by, and which the wire and leak tests keep checking. (c) moves the binding into every reader's copy of the mode, the bots' `CIRCLE_OF_HELD` and `ItemViews.destination_item` with it, and breaks the day a map has two places of one kind. (a) keeps the binding explicit on the wire, and every reader of `station` unchanged. `ClientModel` already reads the colour with a white default, so the client keeps working between D2 and D3 | (a); the version and kind numbers are taken when D2 lands, never here |
| DE6 | The deal's draws, order and demands | §2.1; RNG purposes `packages` (the items' markers, then which listed item takes which) and `tasks` (the routes' order); `circles` goes. Demands while N > 0: exactly one marker per drop-off tag, and per item spawn tag the most items a draw can put there: with r the routes whose kind has that tag, min(N, r × floor(N / K) + min(r, N mod K)) under DD2 (a), which is N for one shared tag (r = K); min(N, those routes) under DD2 (b); no colours (`Demands.add_colours` no longer called) | a purpose of its own shifts no other part's draws (§3.3); a demand below what a draw may need lets a lobby start whose deal then fails | as stated |
| DE7 | A place's done | (a) a drop-off's `StationState.done` once every item routed to it this round is delivered; `PackageDelivered(item, station)` per item as today; `ClientModel`'s fold is event-driven: a station becomes done on a `PackageDelivered` naming it when no other undelivered item names it, and never on `StationPlaced` or `ItemSpawned` (the fold the bots share, so it lands with D2, as `client/CLAUDE.md` asks); (b) a new `DropOffDone` event | (b) a wire row and a fold for what `ItemSpawned` and `PackageDelivered` already tell. Without the "every item" rule the dining table dims after the first of two bottles. A fold derived from the items alone ("done when no undelivered item names it") marks every drop-off done from its `StationPlaced` until its items' `ItemSpawned` arrive (the deal sends the stations first, §2.1), and for good if an item never arrives | (a) |
| DE8 | The bots' targets (§9.7) | (a) `PACKAGE`: the n-th item whose `ItemSpawned` named a station, whatever its kind; `CIRCLE_OF_HELD`: unchanged (its code name may become `DROP_OFF_OF_HELD`; the number a scenario stores stays); `NEAREST_PACKAGE`, new at the end of `ScenarioTarget.Kind`: the nearest such item on the ground; `dissident_hides_a_package` and `dissident_kills_the_crew`, which name `nearest(package)`, switch to it; (b) scenarios name the kinds | (b) the deal draws the kinds, so a script cannot know which kind it meets, and each rename of a kind breaks the scripts. (a) keeps every Delivery scenario independent of DD1 | (a) |
| DE9 | The flat level and the bots (ARCHITECTURE §9.7: bots play only the flat levels; the greybox keeps only the basic Delivery, DD9) | (a) the greybox gets one marker per drop-off tag at y = 0, as far from the `package` markers as its circles are, so the scenarios, the chaos bots and the perf run play the base mode's Delivery as today; Delivery lists no map in `TaskType.maps` (the Generator's G8: empty is every map), so it deals on the greybox and on House alike; (b) the bots play a fixture mode that keeps circles | (b) the scenarios would stop testing the base mode's Delivery, which is what they are for (§9.6). (a) changes the greybox's markers only, and every drop-off marker stands at y = 0, which the flat fake answers; it serves DD9 (a) and (b) alike, the props being D4's | (a) |
| DE10 | The places on House | (a) markers: the plain `DiningTable`, `TerraceTable`, `GardenDropOff` and `Workbench` markers (under `Stations`, at house-map §6's points, level 0) join their drop-off's `spawn_<tag>` group; the furniture a place is named after is the room's dressing (`levels/props/`, collision on layer 1, so an item rests on its top), not a station; (b) a station scene per place in `levels/stations/`, bound as the Generator's GE11; (c) one generic drop-off scene, its group set per instance | a drop-off has nothing the client drives and nothing the host reads besides its marker, and its facing does not matter (its look is drawn by the client from `StationPlaced`); GE11's scene binding exists for devices with driven nodes and a facing. (b) a scene per place that wraps a table and a marker, and a client lookup by position for nothing. (c) a scene that differs per instance only by a group. (a) is the level piece conventions' "its spawn, package, circle, respawn and knife markers: the existing `spawn_<tag>` groups", and a scene can wrap a marker later (DD4 (c)'s sign) with no engine change. Every House drop-off stands on level 0, so the runners' flat-fake read of House still finds a floor (§9.7) | (a); greybox props for the furniture in D4, provisional |
| DE11 | The client's looks (D3a, D3; placeholders until the art pass) | the drop-off: a look of its own in one neutral colour, distinct from the zone task's (`ZoneViews`, ZD11), depth-tested, dimmed when done; an item: its kind's look (`item_view.gd`, a labelled box until the art); no marker (DD4 (a)): `CircleViews`' marker and its `no_depth_test` material go, with the HUD's destination row and `ItemViews.destination_item`, their only reader left, so no material in the client draws through walls; `CircleViews` draws only Delivery's drop-offs, found through `station_kinds()` of the client's own Delivery types (the Generator's G6 restricts it to Delivery's station kinds) | a drop-off and a zone that look alike, now that no colour tells them apart, send a player to stand in a drop-off or to put an item in a zone; a marker left over the held item's place would point where the engineer chose that nothing points | as stated |
| DE12 | Content tests | on every map of the base mode: one marker per drop-off tag (the fit check at the mode's maxima), no marker of any Delivery item kind's spawn tag inside a drop-off's cylinder (`StationState.contains`, the cylinder at its snapped floor, so a storage marker on the level below does not count); ZE9's spacing test (`release/m7`) measures zones against drop-off markers through `station_kinds()` | an item spawning delivered; a zone over a drop-off | as stated |
| DE13 | The mode checks | `Delivery.check`: `routes` not empty; each route with an item kind the mode declares, a spawn tag on it (the cooking ADR's CE18 moves that requirement to the parts that place on markers, Delivery among them) and a drop-off; no kind in two routes; no drop-off tag equal to an item tag (today's "circle and package share spawn tag", generalised); no palette on a drop-off; the subtasks setting (G0, if landed) and both RNG purposes set; ZE3 across the mode through `station_kinds()` | a shared tag lets an item spawn on a drop-off marker, delivered before anyone moves; a kind in two routes has two places; a palette suggests a colour the game never shows | as stated |
| DE14 | The words in code | (a) keep `Delivery`, `PackageDelivered`, the `packages` setting, and "package" for any Delivery item in code and docs; (b) rename them | the engineer still calls them packages ("Стосовно пакетів", comment 6090227509); (b) touches the wire's event name, every scenario and the copy deck for no rule | (a) |

### 7. Testing
- **Unit tests** (D2, and D2a for `station_kinds()`; fixtures only, never `content/`, ARCHITECTURE §9.6): the deal
  (the spread of DD2 (a): every route once before a repeat, N below and above K, N = 0; ids and their order, pinned
  with two item spawn tags, which the data allows though DD8 (a) uses one: station ids in `routes` order, item ids by
  tag then level order, subtask i the i-th item id; only the drop-offs in use placed; the exact drop-off markers and
  the per-tag item demands; a short map logging a match error); the check (its own drop-off delivers; another route's
  drop-off and a knife do nothing; a place with two items done only after both; a held item never counts; an item
  thrown into its own drop-off is delivered, `release/m7`'s `delivery_throw_test.gd` moved onto the routes); DE13's
  checks; `station_kinds()` (the default equals today's reflection on a fixture type, Delivery's lists its drop-offs,
  `MarkerReader` snaps their markers, ZE3 sees them, `WireBudget` sizes `StationPlaced` by the longest station id of a
  kind with no palette); `ItemSpawned`'s round trip without a colour; the `ClientModel` fold of DE7 (a station is not
  done between its `StationPlaced` and its items' `ItemSpawned`, nor after the first of its two items is delivered;
  done on the second's `PackageDelivered`); the targets of DE8 with two kinds. Delivery reads no role, so no role-swap
  check is new.
- **Scenarios and the leak test** (D2): every MVP scenario passes on the switched base mode, the two of DE8 changed;
  `crew_delivers_every_package` then delivers items of several kinds to several places, and runs in `bots`, so the new
  `ItemSpawned` crosses the real wire and the leak test sees it; `throw_scenarios_test.gd` (`release/m7`) throws an
  item into its drop-off. The task-event lists stay.
- **The chaos bots** (D2): no new intent, so no new row; the chaos scenario's `PACKAGE` and `CIRCLE_OF_HELD` targets
  (`tests/harness/chaos/chaos_scenario.gd`) resolve through DE8, and no malformed-frame case changes (they build
  intents and `Rejected`, never `ItemSpawned`).
- **Integration tests on House** (D5; bots do not play House, ARCHITECTURE §9.7): `Match` over `HostWorldQuery` with
  House's level: items put down from scripted commands at each drop-off are delivered, on the floor within the radius
  and, once D4's props stand, on their tops; one put down in the next room is not; horizontal `WorldQuery` rays from
  each drop-off marker find no wall within its radius (a delivery through a wall is the failure); every drop-off and
  storage marker reads without an error.
- **The client** (D3a, D3): the HUD texts and the folds (pure), the drop-off and item looks, no material drawn
  through walls anywhere (`item_views_test.gd`'s check, its one exception gone with the marker), no destination row
  on the HUD, a `shot` preview; the M4 render checklist. The tests of what DD4 (a) removes (the marker's in D3a, the
  HUD's destination row's in D3) go with it, each named in its PR with the engineer's comment as the reason.
- **Green** (#605): `verify` (lint and check) locally, then CI's full suite on the PR, for each issue of §8.

### 8. The split
Sizes as in M6 and M7: S up to about 400 changed lines, M up to about 900. Base: `release/m7` for every issue, which
holds what they build on (`StationState.contains`, ZE3's `_check_stations`, ZE7's `STATION` target, the throw and its
`delivery_throw_test.gd`). Effort: high for `core/`, `net/` and `tests/harness/`. These are proposals for the M7
backlog: the manager opens them once the engineer approves the texts, and none starts before he says so (for now the
track only designs, [comment 6096108206](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096108206)).
The engine change and the base mode's data change in one PR (D2): the class's exports change, so today's
`content/tasks/delivery.tres` would fail the mode check on the next commit. The House's and the greybox's markers come
first (D1), so D2's fit check finds them. `TaskType.station_kinds()` changes no behaviour and serves the Generator and
cooking too, so it is its own issue (D2a) before D2. The engineer's answers (§5) leave D4 no data of his to wait for:
the names and the description go into D2, and D4 removes the circles and adds the props. The marker through walls
goes in an issue of its own (D3a): its removal needs nothing else, so it may land first.

| Issue | Labels | Goal | Acceptance | Files | Depends on | Size |
|---|---|---|---|---|---|---|
| D1 | area:level | The drop-off markers on the greybox and House | one marker per drop-off tag (DD1 (a): four; §5.1's tags, provisional) on `levels/greybox/greybox.tscn` at y = 0, as far from the `package` markers as its circles are, and on House the `DiningTable`, `TerraceTable`, `GardenDropOff` and `Workbench` markers in their groups; the circle markers stay until D4, and no new marker shares an (x, z) with one (the flat fake, §9.7); `levels/CLAUDE.md`'s spawn points gain the tags; every test that reads the maps still passes; provisional, named in the PR for the engineer's approval | `levels/greybox/greybox.tscn`, `levels/house/rooms/` (dining room, terrace, garden, garage), `levels/CLAUDE.md` | none (DD1 answered; the greybox's markers serve DD9 (a) and (b), and under (c) the greybox gets none); not while the car repair's level issue (#688) has an open PR on `garage.tscn`, scenes having one owner at a time (`levels/CLAUDE.md`) | S |
| D2a | needs-engine, area:core, area:server, area:client | `TaskType.station_kinds()`: one finder of a task type's station kinds | DE4 with no behaviour change: `TaskType.station_kinds()`, by default today's reflection over the type's `StationKind` properties; `MarkerReader.floor_tags_of`, ModeCheck's `_check_stations` (ZE3), `CircleViews.station_kind` and `WireBudget`'s `_Content` (station ids from `station_kinds()` over the mode's task types, not from colour demands) call it; unit tests: the default equals today's reflection on a fixture type, an override's kinds are snapped by `MarkerReader` and seen by ZE3, and a `tests/unit/server/wire_budget_test.gd` case whose longest station id belongs to a kind with no palette; every existing test passes unchanged; ARCHITECTURE §9.3 (the hook) | `core/content/task_type.gd`, `core/content/mode_check.gd`, `server/levels/marker_reader.gd`, `server/wire_budget.gd`, `client/world/circle_views.gd`, `tests/unit/`, `tests/fixtures/tasks/`, `docs/ARCHITECTURE.md` | none (ZE3's `_check_stations` is on `release/m7`, the base); the Generator (#695) and cooking (#701) may use it too, so it may land before either | S |
| D2 | needs-engine, area:core, area:server, area:net, area:client, area:content | Delivery by routes, and the base mode switched to it | §2's rules with the engineer's answers (DD2, DD5, DD6 and DD8, each (a)); DE2, DE3 and DE5 to DE8 and DE13: `DeliveryRoute`, `Delivery`'s routes, deal, check, demands and checks (its `circles_rng`, `package` and `circle` exports gone; the `package` spawn tag stays, DD8 (a)), Delivery's override of D2a's `station_kinds()` (its routes' drop-offs, each once), `ItemSpawned` without its colour (wire row, `WireBudget`'s sample, a protocol bump), the `ClientModel` fold of DE7, the targets of DE8 in both runners and the chaos scenario; the data: `content/tasks/delivery.tres` with four routes and drop-offs (DD1 (a), DD3's placeholders, §5.1's ids and tags), the item kinds `wine` and `oil` (his words) and `gnome` and `parasol` (§5.1's drafts, as he approves them in PR #713), each two-handed with the shared `package` spawn tag (DD6 (a), DD8 (a)) and §5.1's display names, §5.1's description, the base mode's `item_kinds` (the `package` kind leaves Delivery); the two scenarios of DE8; `delivery_throw_test.gd` and `throw_scenarios_test.gd` (`release/m7`) moved onto the routes; §7's unit tests; every test that loads the base mode still passes, each changed expectation named in the PR; ARCHITECTURE §3.3 (RNG purposes, its Delivery deal sentences and the "ids in spawn-point order" rule, by this ADR's deal in section 2 item 1), §4.2 and §4.3.4 (`ItemSpawned`), §5, §7.1.14, §9.3's station rows, §9.5.4 and §9.5.5 rewritten, §9.6, §9.7 (the targets, "no drop-off below y = 0"); provisional files named for the engineer's approval | `core/tasks/delivery.gd`, `core/tasks/delivery_route.gd`, `core/content/scenario/scenario_target.gd`, `core/events/item_spawned_event.gd`, `server/wire_budget.gd` (the sample), `net/messages/wire_schema.gd`, `core/match/phases/join_rules.gd` (the version), `client/net/client_model.gd`, `tests/harness/` (`scenario_bot.gd`, the chaos scenario), `content/tasks/delivery.tres`, `content/items/`, `content/modes/base_mode.tres`, `content/scenarios/` (two), `tests/unit/`, `tests/fixtures/tasks/`, `tests/scenarios/throw_scenarios_test.gd`, `tests/integration/levels/house_markers_test.gd`, `docs/ARCHITECTURE.md` | D1; D2a; the Generator's G2 for the exact count (GE10), or D2 adds it if it starts first; G0 if landed (Delivery's `subtasks_setting` in `TaskType`); `release/m6.2` in main or not (if in, `Delivery.item_spawn_tags()` returns every route's item tag) | M |
| D3a | area:client | No marker through walls | DD4 (a), the engineer's: `CircleViews`' destination marker goes (`_marker`, `_mark`, `MARKER_ABOVE`, `MARKER_SIZE` and its `no_depth_test` material, `client/world/circle_views.gd`), so no material in the client draws through walls; the HUD's swatch stays until D3 (the package is painted in its colour until then, so the circles still read); `item_views_test.gd`'s marker cases go, each named in the PR with the engineer's [comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718) as the reason, and its check that nothing draws through walls stays, with no exception left; the doc comments that name the marker (`circle_views.gd`, `hud_text.gd`); the M4 render checklist, the PR routed to `netcode-security-reviewer` too; a `shot` preview; ARCHITECTURE §4.7 (the HUD's line on the world marker, `CircleViews`' entry, the render checklist's summary of `no_depth_test`'s one use) | `client/world/circle_views.gd`, `client/ui/hud_text.gd`, `tests/integration/client/world/item_views_test.gd`, `docs/ARCHITECTURE.md` | none: it needs no other change, so it may land first | S |
| D3 | area:client | The client's view without colours | DE11: the drop-off's look (neutral, distinct from `ZoneViews`' zones, dimmed when done), each kind's look by id (a labelled box until the art: a case of wine, a canister of motor oil, a gnome, a closed parasol); the HUD: on a base without `release/m6.2`'s #489, the destination row and its swatch go (`HudText.destination`, `destination_colour`, `hud.gd`'s swatch) with no line naming the place (DD4 (a)), and `ItemViews.destination_item` with them, their last reader; with #489 in, nothing (its HUD shows no destination); `ClientModel.Item.colour` and `ItemView.make`'s colour removed; `hud_test.gd`'s destination cases go with the row, each named in the PR with the engineer's comment as the reason; the dev previews (`client/dev/items_preview.gd`, `screen_preview.gd`, `spectate_preview.gd`); the M4 render checklist, the PR routed to `netcode-security-reviewer` too; `shot` previews; ARCHITECTURE §4.7 | `client/world/`, `client/ui/hud_text.gd`, `client/ui/hud.gd`, `client/net/client_model.gd`, `client/dev/`, `tests/unit/client/`, `tests/integration/client/`, `docs/ARCHITECTURE.md` | D2; D3a | M |
| D4 | area:level | The circles gone, and the drop-offs' props | the circle markers removed from House's ten rooms and the greybox, `circle` dropped from `levels/CLAUDE.md`; greybox props in `levels/props/`, collision on layer 1 so an item rests on a top: a dining table, a terrace table with a parasol stand and a workbench at House's drop-offs, and on the greybox the same three and a patch of lawn with a low fence beside its four drop-off markers (DD9 (a)), each place told apart at a glance (the two tables unlike: a long indoor one with chairs, a round outdoor one with the stand); a `shot` of each room and of the greybox's drop-offs; house-map §6's Delivery rows as built; every test that reads the maps still passes; provisional files named for the engineer's approval | `levels/house/rooms/`, `levels/greybox/greybox.tscn`, `levels/props/`, `levels/CLAUDE.md`, `docs/design/house-map.md`, `tests/unit/content/`, `tests/integration/levels/`, `docs/ARCHITECTURE.md` (§9.6) | D2; DD9 for the greybox's props (none under (b); under (c) the greybox keeps its circles); not while cooking's C5 (`kitchen.tscn`) or the car repair's level issue (#688, `garage.tscn`) has an open PR on a room D4 edits: it waits, or leaves that room's circle marker to the station PR that owns the room | S |
| D5 | needs-engine, area:core | Integration tests: Delivery on House | §7's House tests in the host's real world | `tests/integration/levels/`, `docs/ARCHITECTURE.md` (§9.7's House line) | D2; D4 for the tests on the props' tops | S |

### 9. What it means for the parallel work (nothing of theirs is edited here)
- **The Generator** (#679, PR #695): the same words (station kinds, `StationPlaced`, exact marker counts, "not a
  decision"). Delivery needs no `Interact`: it keeps "rests inside, however it got there", so a drop-off holds no rule
  and E there is `nothing_to_do`, as its §2 item 2 says of a delivery circle. G6's `CircleViews` filter ("a Delivery circle")
  reads "a Delivery drop-off" through `station_kinds()`; G3's sentence on circles below y = 0 reads "drop-offs"; G0's
  `subtasks_setting` in `TaskType` takes Delivery's `packages` with it; D2 reuses GE10's exact count. Room scenes have
  one owner at a time: D1 and D4 edit `garage.tscn` (the car repair's `CarLift`, #688) and D4 `kitchen.tscn` (cooking's
  C5), so each waits for an open PR on that room or leaves its circle marker to the station PR that owns it. The Generator's
  stations have no palette either, so `WireBudget`, which finds station kinds only through colour demands, misses
  them too: D2a moves it onto `station_kinds()` (DE4), and may land before the Generator. Its G8 (`TaskType.maps`,
  GE15) keeps the House's chains off the greybox; Delivery lists no map, so it plays on both (DE9, DD9). Whether the
  zone task leaves the greybox too is its GD13, not this ADR's.
- **Cooking** (#682, PR #701): DE1 is cooking's own choice of item kinds over a variant field; Delivery keeps a spawn
  tag on every kind it places (CE18); a package at a cooking place stays `two_handed` under DD6 (a); DE4's
  `station_kinds()` serves its bed kinds too, if they are held in a list. The engineer's belt rule for every take (CD3
  (b) and CE21, built in its C2) reaches every Delivery item: a carrier's take of a one-handed item, from a box, a bed,
  the grill or the floor, goes onto the belt and the Delivery item stays in the hands, where today a pick-up from the
  floor leaves the package where the picked item lay; a pick-up of another Delivery item keeps today's swap (§4).
  Delivery's code changes nothing for it, and C2 owns its tests.
- **The M7 zone task** (`release/m7`): D2 is based on it (§8) and uses `StationState.contains`; ZE3's `_check_stations`
  moves onto `station_kinds()` in D2; ZE7's `STATION` target works for a drop-off kind as it is; ZE9's spacing measures
  zones against drop-off markers (DE12); ZD7's "a palette apart from the circles'" no longer applies, ZD11's look
  clash still does (DE11).
- **The M6.2 UI** (`release/m6.2`): #489's HUD shows no destination, as DD4 (a) wants, and its hand slot shows a
  two-handed item's name (`client/ui/hud_slot.gd`), which is how a player tells where the item goes. #520's Delivery
  card art (frames 2 and 3: "check the sign on the package", "find the room with that sign") and the tutorial's
  `tutorial.step.deliver.how` ("Find the room with the sign that's on the package", `client/i18n/strings.csv`) name a
  sign that DD4 (a) leaves out: the UI track's to redraw and reword, routed by the manager (no issue of §8). #253's map
  screen lights a type's zones from `item_spawn_tags()`, which returns every route's item tag (storage on House, as
  today); #489's `ITEM_KEYS` has no key for the new kinds, so their display names show until the copy deck adds keys;
  `task.delivery` stays under DD7 (a).
- **The shared total** (#738, the engineer's answers on PR #695): the HUD's "Tasks x / y" and the task screen's
  "Shared progress" go; Delivery's row keeps its own count ("2 / 6") and is struck through once every item is
  delivered. Delivery emits `TaskState` as today, which is all the row needs; whether `TaskProgress` stays on the wire
  is #738's.
- **The M4 client design**: DD4 (a) removes its D10 (b) marker and the one exception in its render checklist's item 5;
  that ADR records the change and points here, and D3a builds it.

### 10. Needs the engineer
DD1 to DD8 (§5) are answered. Left for him:
- **DD9: which Delivery the flat greybox plays, and how its places show what they are** (§5): (a) this Delivery, with
  a greybox prop beside each drop-off; (b) this Delivery on bare drop-off markers; (c) today's colour Delivery on the
  greybox, this one on House. **Recommendation: (a)**: the greybox is where the default lobby lands, and by meaning
  alone a player needs something there to read the meaning from. The design proceeds with (a); only D4's greybox
  props depend on the answer.
- **His approval of the drafts** (§5.1): the garden gnome, the parasol, "Motor oil" and the description, in PR #713.
  DD3's numbers stay placeholders, "not a decision", for him to approve in D2's PR.
- **His approval of the texts** in PR #713: GDD §8's Delivery section, house-map §6's Delivery rows, and the issue
  texts D1, D2a, D2, D3a, D3, D4 and D5 (§8), which the manager opens after it as proposals for the M7 backlog; none
  starts before he says so.

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
- **Keep the colour on the wire** (DE5 (b)) or **drop the station too** (DE5 (c)): a dead field, or the binding moved
  into every reader's copy of the mode.
- **A `DropOffDone` event** (DE7 (b)): `ItemSpawned` and `PackageDelivered` already tell it.
- **Station scenes for the places** (DE10 (b), (c)): scenes with nothing to drive and no facing that matters.
- **The bots on a fixture mode** (DE9 (b)): the scenarios would stop testing the base mode's Delivery.
- **A marker without colour over the held item's place** (DD4 (b), the recommendation he did not take), **a sign**
  (DD4 (c)) or **a HUD line** (DD4 (d)): the engineer chose by meaning alone, and no marker through walls anywhere.
- **Today's colour Delivery kept on the greybox** (DD9 (c)): two Deliveries, the palette and a colour on the wire for
  a test level, and bots that test a Delivery nobody plays on House; #683 took colours out of Delivery itself.
- **A description that lists the routes** (§5.1): a pointer DD4 (a) left out, wrong on a map that places them
  otherwise.

## Consequences
- The MVP rules ADR records the engineer's change (its Deciders line, the Delivery bullet, the rows "Delivery circles
  per match" and "Distinct circle colours"), each pointing here. When this ADR is accepted its Status says so, and the
  issue that builds a rule here updates the line of the MVP rules it replaces.
- The M4 client design records DD4 (a) at its D10 (b) and its render checklist's item 5: once D3a lands, nothing in
  the client is drawn through walls, and a new marker through walls is a design change, not an exception to cite.
- ARCHITECTURE §9.5.4 points here, §9.8 gains the row "Delivery by meaning" and §10 its last question (DD9); GDD §8
  gains Delivery's section with the engineer's answers. house-map §6's Delivery rows name each place's item now (DD1
  (a), §5.1's drafts), and D4 updates them as built.
- When D2 lands, ARCHITECTURE's Delivery entries (§7.1.14, §9.5.4, §9.5.5), `ItemSpawned`'s rows (§4.2, §4.3.4), §5's
  list and §9.7's targets are rewritten, with their `Built in` lines.
- The protocol version goes up once, in D2; kind numbers and versions are taken when it lands, never from here.
- Every map of the base mode needs one marker per drop-off tag: House and the greybox get them in D1, and a later map
  gets them with its level pieces (`new-level-piece`).
- Between D2 and D3 the client draws items and drop-offs in white and the HUD on `release/m7` shows a white swatch,
  and until D3a the marker still points through walls: playable, but no playtest until D3a and D3 land.
