# Delivery by meaning (#683): items carried to their own places instead of colour-matched circles

- **Status:** Proposed on 2026-10-10. Nothing here is built. The direction is the engineer's: #683's "Decided" list
  (chat with the game-design manager session, 2026-10-10: Delivery no longer goes by colours, and the mechanic changes,
  not only the text) and his answer on #683,
  [comment 6089404833](https://github.com/xperiaroco2/prime-game/issues/683#issuecomment-6089404833), with his own words
  relayed in [comment 6090227509](https://github.com/xperiaroco2/prime-game/issues/683#issuecomment-6090227509): storage
  holds different items, each to be carried to its own location by what it is ("wine to the living room, maybe oil to
  the garage, something to the garden"; "by the location's sense, not by colours"). The DD items are game rules and
  taste he left open: they are his (the [trust ADR](2026-10-04-trust-based-autonomy-gated-merge-into-main.md)'s tier
  (c)), each with options and a recommendation, and the design proceeds with the recommendation where it can be
  reverted. The DE items are technical, the game-design manager session's to decide and report (tier (a)): decided
  here, each revertible in its issue.
- **Date:** 2026-10-10
- **Deciders:** the engineer (the rules, DD1 to DD8); the game-design manager session of #676 (DE1 to DE14). Designed
  by the agent of #683, on the engineer's word (#683; the track's kickoff on #593, comment 6088751685).
- **Amends:** [MVP rules](2026-09-29-mvp-rules.md) (Delivery: a circle per package placed at random, a colour per
  package, the palette of 10). The direction is the engineer's decision of 2026-10-10, so that ADR's Deciders line, its
  Delivery bullet and its two numbers rows already point here; the rest of this ADR is proposed.
- **Builds on:** [MVP rules](2026-09-29-mvp-rules.md) (Tasks: the shared Delivery of #79; the engineer's correction in
  #32, "rests inside, however it got there"), [content API v0](2026-09-29-content-api-v0.md) (task types are classes
  with settings), [vision revision 1](2026-10-01-vision-revision-1.md) (V4's "living", V13's two-handed package, hiding
  packages as the dissidents' sabotage), [the M4 client design](2026-10-01-m4-first-person-client.md) (D10 (b): the
  destination marker through walls; its render checklist, item 5), [the zone task ADR](2026-10-09-m7-zone-task.md) (#36,
  built on `release/m7`: `StationState.contains`, ZE3's station checks, ZE7's `STATION` target, ZE9's spacing, ZD11's
  looks), the Generator ADR (#679, proposed in PR #695: GE10's exact marker counts, GE11's station scenes, G0's subtasks
  setting, G3's flat-fake rule, G6's `CircleViews` filter), the cooking ADR (#682, proposed in PR #701: item kinds, not a
  variant field; CE18's optional spawn tag), [level piece conventions](2026-10-09-level-piece-conventions.md), [MVP
  content built by the engineer](2026-09-29-mvp-content-built-by-the-engineer.md) (content and levels are provisional,
  approved in their PRs), [the House map](../design/house-map.md) (§2 decision 5, §6's Delivery rows, §7's routes),
  [tests on CI](2026-10-09-tests-on-ci-local-lint-and-check.md) (#605: what "green" means in §8)
- **Numbering:** DD and DE are this ADR's own; the issues are D1 to D5 (§8), which the manager opens from the PR's
  handoff.

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
counts when it rests inside its place, however it got there (a put-down, a swap, a drop at a death or a leave, later a
throw); a delivered item is locked; nothing in Delivery is secret (#79); the dissidents sabotage by hiding items.

## Decision

### 1. The mapping (`new-mechanic` step 3)

#### 1.1 Each rule to its engine part

| # | What #683 needs | Engine part | Exists? |
|---|---|---|---|
| 1 | Storage holds different items | one `ItemKind` per kind of item (DE1): its id, display name (the HUD's hand slot), spawn tag and `hands` | `ItemKind` exists (`core/content/item_kind.gd`); the kinds D2 (placeholders) and D4 (his words, DD1) |
| 2 | Each kind goes to its own place, by meaning | `DeliveryRoute` (DE2), a sub-resource of the task type: `item` (an `ItemKind`) and `drop_off` (a `StationKind`); `Delivery.routes` lists them | missing: D2 |
| 3 | A place on the map | one `StationKind` per place (DE3), the house-map's "drop-off": its own id and spawn tag, `radius_m` and `height_m` (DD3), no palette; exactly one marker of its tag per map | the class exists (`core/content/station_kind.gd`); the markers D1; the data D2 |
| 4 | How many items, and of which kinds | the deal: N items, N the `packages` setting, their kinds spread over the routes in a random order (DD2) | the setting exists; the draw D2 |
| 5 | Delivered at its own place, however it got there | the check on `item_rested`, the same shape: an item of an undone subtask resting on the ground inside its drop-off's cylinder (`StationState.contains`) is delivered and locked | `Delivery.on_fact` exists; `StationState.contains` on `release/m7`; D2 adapts it |
| 6 | Not by colours | no palette and no colour demand for drop-offs; `ItemSpawned` drops its colour (DE5); the client draws neutral looks (DE11) | D2, D3 |
| 7 | An item at a wrong place | nothing happens (DD5) | exists: a package in another circle does nothing today |
| 8 | Packages take both hands | `ItemKind.hands` 2 for every Delivery kind (DD6) | exists (M4-5) |
| 9 | A player tells where an item goes | its look and name (DE1), and the through-walls marker over the held item's drop-off, kept without a colour (DD4) | `CircleViews`'s marker exists (`client/world/circle_views.gd`); D3 |
| 10 | The reader, the mode check, the wire budget and the client find the drop-offs | `TaskType.station_kinds()` (DE4) in place of the four finders of a type's station kinds (three reflections over its `StationKind` properties and `WireBudget`'s colour demands), which miss kinds inside a route list | missing: D2 |
| 11 | Bots find an item and its place from what they were told | `ScenarioTarget`: `PACKAGE` reads any Delivery item, `CIRCLE_OF_HELD` its drop-off (unchanged), a new `NEAREST_PACKAGE` (DE8) | D2 |
| 12 | The flat test level and the bots' scenarios keep working | one flat marker per drop-off tag on the greybox (DE9) | D1 |
| 13 | On House | the four plain markers at house-map §6's points join their drop-off's group (DE10) | the markers exist (`DiningTable`, `TerraceTable`, `GardenDropOff`, `Workbench`, level 0); D1 |
| 14 | Tested on House, which bots do not play (ARCHITECTURE §9.7) | integration tests in the host's real world (D5) | missing |

#### 1.2 Today and after

| | Today | After | Why |
|---|---|---|---|
| Item kinds | one, `package` | several (DD1) | "different items" |
| Which place an item goes to | drawn each deal, a random permutation (`tasks`) | fixed in the data by kind (`routes`) | "by the location's sense" |
| Places | N circles on random `circle` markers, anew each round | one station per drop-off in use, on its own marker, the same every round | a place by meaning stands where it is |
| Colours | a 10-colour palette: demanded, sent, painted | none | "not by colours" |
| RNG purposes | `circles`, `packages`, `tasks` | `packages`, `tasks` | no placement or colour draw is left |
| A place done | when its one package is delivered | when every item routed to it this round is delivered (DE7) | several items may share a place |
| Events | `StationPlaced`, `ItemSpawned` (circle, colour), `PackageDelivered`, `TaskState`, `TaskProgress` | the same classes; `ItemSpawned` without its colour | one wire change (DE5) |

### 2. The rules as the engine runs them (with the recommendations)
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
   `subtask_done`, in that order, as today.
3. **Anything else at a place**: an item resting inside another route's drop-off, or any other item in a drop-off, does
   nothing (DD5 (a)).
4. **Nothing else changes**: any living player carries any item; every Delivery item is two-handed (DD6 (a)); a dying or
   leaving carrier drops it at the body; a held item never counts.

### 3. What everyone sees

| What | Who learns it | How |
|---|---|---|
| Which item kinds go to which place | every client: its own copy of the mode holds the routes | data |
| Where this round's drop-offs stand | everyone | `StationPlaced` in the deal |
| Each item, its kind, where it spawned and its drop-off | everyone | `ItemSpawned` (`kind`, `station`) |
| Where an item lies after it moved | every client receives it; an honest one draws it only where it lies, depth-tested (hidden by sight, the M4 render checklist item 5) | `ItemPickedUp`, `ItemPlaced`, `Swapped`, the snapshots' hand and belt items |
| A delivery | everyone, on the HUD and the task screen too | `PackageDelivered`, `TaskState`, `TaskProgress` |
| Who delivered | nobody, through an event: no Delivery event names a player | the snapshots show who stood there, as today |
| The held item's place, through walls | the carrier (DD4 (b)) | `CircleViews`'s marker, from the own `ClientModel` |

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

### 5. DD items (the engineer's: game rules and taste)

| # | Question | Options | Trade-offs, and the failure each prevents | Recommendation |
|---|---|---|---|---|
| DD1 | The item kinds and their places (#683's open item 1; his examples; the question relayed in comment 6090227509) | (a) one kind per house-map §6 drop-off, four: the wine to the dining table (§6's "the wine" row), the oil to the garage's workbench, his garden item to the garden drop-off, his item for the terrace table; (b) his three examples only: the wine to the living room (a new drop-off there), the oil to the garage, his item to the garden; the terrace table leaves Delivery; (c) (a) or (b) and more places: rooms that hold a circle marker today (the kitchen, the study, the bedrooms) | each place is a marker the fit check demands on every map of the base mode, the greybox included (DE9). (a) keeps §6 and its measured routes (§7: the wine 26 m, the garage 60 m, the garden 57 m) and sends items to three sides; the terrace's item and the garden's need names. (b) follows his words to the letter; the living room is "a place where everyone crosses" (house-map §4), so a delivery there is watched by many, and its route is not measured. (c) more places dilute "by meaning" (what belongs in a bedroom?) and add markers to every map. Either way the Package kind (`package`) leaves the base mode unless he names it one of the kinds (house-map §6 has "Boxes (source)") | (a), the wine at the dining table unless "the living room" was meant literally; the other names his, placeholders marked "not a decision" until then |
| DD2 | How many items a round, and whether the host's setting picks it (#683's open item 2; #256) | (a) N items, N the host's `packages` setting as today (1 to 10, default 6), the kinds spread over the routes in a random order: every place gets one before any gets a second; (b) one item per place, N at most the number of routes: the setting picks how many places, drawn at random; (c) every kind once a round, no setting | (b) caps the task at the routes (4 on House with DD1 (a)), so today's default of 6 is out of range, and the hiding sabotage has fewer items to hide. (c) drops a host setting (#256: every task type has its subtask count) and makes the map's routes the difficulty. (a) keeps the setting, its bounds and the MVP scenarios' counts (`crew_delivers_every_package` delivers 6), and sends players to every place before any repeats (house-map §8: tasks spread the players). In (a) and (b) which places get an item when N is below the routes is drawn each round, so nobody plays one memorised route (as the Generator's GD2 (a)) | (a) |
| DD3 | What counts as "at its place", and how big a place is (#683's open item 2) | (a) inside a drop-off's cylinder standing on the floor at the place's marker, as a circle today: on the floor around the table or bench, or on its top, within the height; the radius and the height in the data (a circle's 1 m, game design since #79, and 2 m, a placeholder); (b) anywhere in the room or area ("to the garage", "to the garden"): a box-shaped drop-off sized to the room, a new station shape; (c) only on the furniture's top | (b) forgives where in the room, at the cost of a second shape in every station test (`StationState.contains`, the client's look, the spacing tests), and on House the garden is 32 x 28 m: a garden item counts as it crosses the fence, with no walk to a spot. (c) needs a marker on the top, and an item put down on the floor by the table is ignored without a word. (a) is what house-map §6 places (drop-offs at a table and a bench) and what a circle does, and players see where it is (DE11) | (a), 1 m and 2 m for every drop-off, placeholders "not a decision"; a wide place (the garden) may take a larger radius in the data (0.2 to 10) |
| DD4 | How a player tells where an item goes (#683's open item 3: does the through-walls marker stay) | (a) by meaning alone: the item's look and its name in the hand slot; (b) (a) and the marker over the held item's drop-off, drawn through walls as today (D10 (b)), in one neutral look; (c) (a) and a sign: the place's picture on the item and at the place, which #520's Delivery card art on `release/m6.2` draws ("check the sign on the package", "find the room with that sign"); (d) (a) and a HUD line naming the place | (a) is the "open knowledge" pillar's finding by looking, and meaning is the point of the change; but a new player on a four-level map may not know where the garden drop-off is, or that the oil goes to the workbench. (b) keeps his answer D10 (b) of 2026-10-01: the marker shows only a fixed, public place, so it reveals nothing, and the render checklist's one exception stays one. (c) waits for the art and the room record (#306): a sign per place, on each item's look and at the place. (d) the M6.2 HUD (#489) shows no destination, by the UI handoff, so a HUD line would undo it | (b); (c) when the art brings the signs |
| DD5 | An item resting at a wrong place | (a) nothing: it lies there and anyone may pick it up (today's rule for a package in another circle); (b) a sign to everyone in sight: a sound or a red flash at the place, client only, nothing in the rules; (c) refused: it is moved off the place, or back to storage | (b) is a client effect on public facts (every client knows the item's kind and the place's routes); it adds nothing for a dissident to learn. (c) a new rule and a new placement path, and a dissident can no longer leave an item at a wrong place as a decoy. (a) needs nothing built | (a); (b) a cheap later add if a playtest asks |
| DD6 | Hands (today's description: "Packages take both hands") | (a) every Delivery item two-handed, as the package today; (b) per kind in the data (one-handed wine, a two-handed crate); (c) every Delivery item one-handed | with (b) or (c) a one-handed item rides the belt: one player carries two at once, or carries one with a knife in the hand, which halves the walks and the exposure the task is built on (V13: a carrier cannot draw a knife). The Generator's and cooking's busy-hands rules refuse a two-handed carrier at a station. The scenarios `two_handed_pickup_with_a_full_belt` and `refusals` rely on a two-handed package, and under (b) which kind a scenario meets is the deal's draw | (a) |
| DD7 | The name, the description and the lobby label (#683's open item 4) | the name: (a) "Delivery" stays (M6.2's copy deck already has `task.delivery`, "Delivery" and "Доставка", and its card art); (b) a new name in his words. The description: the mode check refuses an empty one; main's task screen shows it, `release/m6.2` shows it nowhere since #253. The label "Packages (Delivery)" of the `packages` setting | today's description ("Carry each package to the circle of its colour. Packages take both hands.") is wrong once colours go, so D2 cannot keep it | (a) and the label as it is; the description his words, D2 carrying a placeholder marked "not a decision" for him to replace: "Carry each item from storage to the place it belongs. Items take both hands." |
| DD8 | Where each kind starts in storage | (a) any kind on any storage marker: one spawn tag shared by every Delivery kind, as `package` today; (b) each kind at its own source, the wine at the wine rack and the rest at the boxes (house-map §6): a spawn tag per source | (a) a bottle may lie by the boxes. (b) the look follows §6, and House's ten storage markers split between the sources; the demands follow either way (DE6) | (a): only the look differs, and the data alone switches to (b) |

### 6. DE items (technical: the manager decides and reports)

| # | Choice | Options | The failure it prevents | Decision |
|---|---|---|---|---|
| DE1 | The item kinds | (a) one `ItemKind` per kind, each with its id, display name, spawn tag and `hands`, its look by id; (b) one `package` kind with a variant field on the item and the wire | (b) a field on every item, the wire and the HUD's hand slot for one task type: the cooking ADR rejected it for its ingredients. (a) reuses `ItemSpawned`'s `kind`, the HUD's display name and `client/world/item_view.gd`'s look by kind id (a labelled box for a kind it has no look for), as they are | (a) |
| DE2 | The binding | (a) `Delivery.routes: Array[DeliveryRoute]`; `DeliveryRoute` (`core/tasks/delivery_route.gd`, a sub-resource with no behaviour): `item: ItemKind`, `drop_off: StationKind`; one drop-off may serve several routes, one kind may be in one route only; (b) `ItemKind.destination`; (c) two parallel lists of kinds and drop-offs | (b) a generic item kind would name one task type's station, though an item may serve two types later. (c) two lists that must agree by position, the failure the cooking ADR's CE6 (b) names. (a) one row per "this goes there", which the check reads alone | (a) |
| DE3 | The places | (a) one `StationKind` per place, its own id and spawn tag (both provisional, "not a decision"), no palette; exactly one marker of its tag on a map; a station only for a drop-off a dealt item needs; (b) one `drop_off` kind with several markers told apart by a node name or metadata; (c) rooms in `core/` (the room record, #306) | (b) `MarkerReader` reads groups, not names: a renamed or swapped marker would send the wine to the garage without an error. (c) rooms in `LevelLayout` and a box test before #306 exists. "Exactly one" is the Generator's exact count (GE10): a second garden marker would stand unused, and a player delivering there gets nothing; the fit check refuses more as well as fewer. Placing only the drop-offs in use keeps `StationPlaced` the list of this round's places, so the client draws no place nobody delivers to | (a) |
| DE4 | How the engine finds a task type's station kinds | (a) `TaskType.station_kinds() -> Array[StationKind]`: by default every `StationKind` property of the type (today's reflection, moved here once), Delivery's override its routes' drop-offs, each once; `MarkerReader.floor_tags_of` (`server/levels/marker_reader.gd`), ModeCheck's station checks (ZE3's `_check_stations`, on `release/m7`), the client (`CircleViews.station_kind`) and `WireBudget` (`server/wire_budget.gd`'s `_Content`, which today collects the mode's station ids from `demands.colours.keys()`) call it; (b) teach the three reflections to walk arrays of sub-resources | the three reflections read only a type's `StationKind`-typed properties: a drop-off inside a route list would not be snapped to the floor (its cylinder would start at the marker's hand-placed height, §9.6), would escape ZE3's duplicate check, and would get the client's fallback size. `WireBudget` finds only the station kinds that demand colours: once DE6 drops Delivery's colour demand, `StationPlaced`'s worst case is sized from the zones' kinds alone, or not at all, and `SettingsChanged`'s shortfall list shrinks, with no test failing. (b) three copies of a deeper walk, a fourth reader repeats it, and `WireBudget` stays apart. (a) also serves any later type that holds station kinds in a list (the cooking ADR's bed kinds, CE6, if held in one) | (a) |
| DE5 | The wire | (a) `ItemSpawned` keeps `has_station` and `station` (the item's drop-off station) and drops `colour`; `StationPlaced` keeps its colour (zones use it; a drop-off's is white); `PackageDelivered` stays; one protocol bump; (b) no wire change: `ItemSpawned` sends white; (c) `ItemSpawned` drops `station` too: the client finds the place from its own mode (kind, route, drop-off kind, its one station) | (b) a field that is always white, which a client could still paint by, and which the wire and leak tests keep checking. (c) moves the binding into every reader's copy of the mode, the bots' `CIRCLE_OF_HELD` and `ItemViews.destination_item` with it, and breaks the day a map has two places of one kind. (a) keeps the binding explicit on the wire, and every reader of `station` unchanged. `ClientModel` already reads the colour with a white default, so the client keeps working between D2 and D3 | (a); the version and kind numbers are taken when D2 lands, never here |
| DE6 | The deal's draws, order and demands | §2.1; RNG purposes `packages` (the items' markers, then which listed item takes which) and `tasks` (the routes' order); `circles` goes. Demands while N > 0: exactly one marker per drop-off tag, and per item spawn tag the most items a draw can put there: with r the routes whose kind has that tag, min(N, r × floor(N / K) + min(r, N mod K)) under DD2 (a), which is N for one shared tag (r = K); min(N, those routes) under DD2 (b); no colours (`Demands.add_colours` no longer called) | a purpose of its own shifts no other part's draws (§3.3); a demand below what a draw may need lets a lobby start whose deal then fails | as stated |
| DE7 | A place's done | (a) a drop-off's `StationState.done` once every item routed to it this round is delivered; `PackageDelivered(item, station)` per item as today; `ClientModel`'s fold is event-driven: a station becomes done on a `PackageDelivered` naming it when no other undelivered item names it, and never on `StationPlaced` or `ItemSpawned` (the fold the bots share, so it lands with D2, as `client/CLAUDE.md` asks); (b) a new `DropOffDone` event | (b) a wire row and a fold for what `ItemSpawned` and `PackageDelivered` already tell. Without the "every item" rule the dining table dims after the first of two bottles. A fold derived from the items alone ("done when no undelivered item names it") marks every drop-off done from its `StationPlaced` until its items' `ItemSpawned` arrive (the deal sends the stations first, §2.1), and for good if an item never arrives | (a) |
| DE8 | The bots' targets (§9.7) | (a) `PACKAGE`: the n-th item whose `ItemSpawned` named a station, whatever its kind; `CIRCLE_OF_HELD`: unchanged (its code name may become `DROP_OFF_OF_HELD`; the number a scenario stores stays); `NEAREST_PACKAGE`, new at the end of `ScenarioTarget.Kind`: the nearest such item on the ground; `dissident_hides_a_package` and `dissident_kills_the_crew`, which name `nearest(package)`, switch to it; (b) scenarios name the kinds | (b) the deal draws the kinds, so a script cannot know which kind it meets, and each rename of a kind breaks the scripts. (a) keeps every Delivery scenario independent of DD1 | (a) |
| DE9 | The flat level and the bots (ARCHITECTURE §9.7: bots play only the flat levels) | (a) the greybox gets one marker per drop-off tag at y = 0, as far from the `package` markers as its circles are, so the scenarios, the chaos bots and the perf run play the base mode's Delivery as today; (b) the bots play a fixture mode that keeps circles | (b) the scenarios would stop testing the base mode's Delivery, which is what they are for (§9.6). (a) changes the greybox's markers only, and every drop-off marker stands at y = 0, which the flat fake answers | (a) |
| DE10 | The places on House | (a) markers: the plain `DiningTable`, `TerraceTable`, `GardenDropOff` and `Workbench` markers (under `Stations`, at house-map §6's points, level 0) join their drop-off's `spawn_<tag>` group; the furniture a place is named after is the room's dressing (`levels/props/`, collision on layer 1, so an item rests on its top), not a station; (b) a station scene per place in `levels/stations/`, bound as the Generator's GE11; (c) one generic drop-off scene, its group set per instance | a drop-off has nothing the client drives and nothing the host reads besides its marker, and its facing does not matter (its look is drawn by the client from `StationPlaced`); GE11's scene binding exists for devices with driven nodes and a facing. (b) a scene per place that wraps a table and a marker, and a client lookup by position for nothing. (c) a scene that differs per instance only by a group. (a) is the level piece conventions' "its spawn, package, circle, respawn and knife markers: the existing `spawn_<tag>` groups", and a scene can wrap a marker later (DD4 (c)'s sign) with no engine change. Every House drop-off stands on level 0, so the runners' flat-fake read of House still finds a floor (§9.7) | (a); greybox props for the furniture in D4, provisional |
| DE11 | The client's looks (D3; placeholders until the art pass) | the drop-off: a look of its own in one neutral colour, distinct from the zone task's (`ZoneViews`, ZD11), depth-tested, dimmed when done; an item: its kind's look (`item_view.gd`, a labelled box until the art); the marker (DD4 (b)): one neutral colour; `CircleViews` draws only Delivery's drop-offs, found through `station_kinds()` of the client's own Delivery types (the Generator's G6 restricts it to Delivery's station kinds) | a drop-off and a zone that look alike, now that no colour tells them apart, send a player to stand in a drop-off or to put an item in a zone | as stated |
| DE12 | Content tests | on every map of the base mode: one marker per drop-off tag (the fit check at the mode's maxima), no `package` marker within a drop-off's radius; ZE9's spacing test (`release/m7`) measures zones against drop-off markers through `station_kinds()` | an item spawning delivered; a zone over a drop-off | as stated |
| DE13 | The mode checks | `Delivery.check`: `routes` not empty; each route with an item kind the mode declares, a spawn tag on it (the cooking ADR's CE18 moves that requirement to the parts that place on markers, Delivery among them) and a drop-off; no kind in two routes; no drop-off tag equal to an item tag (today's "circle and package share spawn tag", generalised); no palette on a drop-off; the subtasks setting (G0, if landed) and both RNG purposes set; ZE3 across the mode through `station_kinds()` | a shared tag lets an item spawn on a drop-off marker, delivered before anyone moves; a kind in two routes has two places; a palette suggests a colour the game never shows | as stated |
| DE14 | The words in code | (a) keep `Delivery`, `PackageDelivered`, the `packages` setting, and "package" for any Delivery item in code and docs; (b) rename them | the engineer still calls them packages ("Стосовно пакетів", comment 6090227509); (b) touches the wire's event name, every scenario and the copy deck for no rule | (a) |

### 7. Testing
- **Unit tests** (D2; fixtures only, never `content/`, ARCHITECTURE §9.6): the deal (the spread of DD2 (a): every route
  once before a repeat, N below and above K, N = 0; ids and their order, pinned with two item spawn tags
  (DD8 (b)): station ids in `routes` order, item ids by tag then level order, subtask i the i-th item id; only the drop-offs in use placed; the exact
  drop-off markers and the per-tag item demands; a short map logging a match error); the check (its own drop-off
  delivers; another route's drop-off and a knife do nothing; a place with two items done only after both; a held item
  never counts); DE13's checks; `station_kinds()` (the default equals today's reflection on a fixture type,
  Delivery's lists its drop-offs, `MarkerReader` snaps their markers, ZE3 sees them, `WireBudget` sizes
  `StationPlaced` by the longest station id of a kind with no palette); `ItemSpawned`'s round trip without
  a colour; the `ClientModel` fold of DE7 (a station is not done between its `StationPlaced` and its items'
  `ItemSpawned`, nor after the first of its two items is delivered; done on the second's `PackageDelivered`); the targets of DE8 with two kinds. Delivery reads no role, so no role-swap
  check is new.
- **Scenarios and the leak test** (D2): every MVP scenario passes on the switched base mode, the two of DE8 changed;
  `crew_delivers_every_package` then delivers items of several kinds to several places, and runs in `bots`, so the new
  `ItemSpawned` crosses the real wire and the leak test sees it. The task-event lists stay.
- **The chaos bots** (D2): no new intent, so no new row; the chaos scenario's `PACKAGE` and `CIRCLE_OF_HELD` targets
  (`tests/harness/chaos/chaos_scenario.gd`) resolve through DE8, and no malformed-frame case changes (they build
  intents and `Rejected`, never `ItemSpawned`).
- **Integration tests on House** (D5; bots do not play House, ARCHITECTURE §9.7): `Match` over `HostWorldQuery` with
  House's level: items put down from scripted commands at each drop-off are delivered, on the floor within the radius
  and, once D4's props stand, on their tops; one put down in the next room is not; horizontal `WorldQuery` rays from
  each drop-off marker find no wall within its radius (a delivery through a wall is the failure); every drop-off and
  storage marker reads without an error.
- **The client** (D3): the HUD texts and the folds (pure), the drop-off and item looks, the marker drawn through walls
  only over the held item's fixed drop-off, a `shot` preview; the M4 render checklist.
- **Green** (#605): `verify` (lint and check) locally, then CI's full suite on the PR, for each issue of §8.

### 8. The split
Sizes as in M6 and M7: S up to about 400 changed lines, M up to about 900. Base: `main`. Effort: high for `core/`,
`net/` and `tests/harness/`. The engine change and the base mode's data change in one PR (D2): the class's exports
change, so today's `content/tasks/delivery.tres` would fail the mode check on the next commit. The House's and the
greybox's markers come first (D1), so D2's fit check finds them.

| Issue | Labels | Goal | Acceptance | Files | Depends on | Size |
|---|---|---|---|---|---|---|
| D1 | area:level | The drop-off markers on the greybox and House | one marker per drop-off tag (DD1 (a): four; tags provisional, "not a decision") on `levels/greybox/greybox.tscn` at y = 0, as far from the `package` markers as its circles are, and on House the `DiningTable`, `TerraceTable`, `GardenDropOff` and `Workbench` markers in their groups; the circle markers stay until D4, and no new marker shares an (x, z) with one (the flat fake, §9.7); `levels/CLAUDE.md`'s spawn points gain the tags; every test that reads the maps still passes; provisional, named in the PR for the engineer's approval | `levels/greybox/greybox.tscn`, `levels/house/rooms/` (dining room, terrace, garden, garage), `levels/CLAUDE.md` | none; the engineer's DD1 (revertible: D1 may start on the recommendation) | S |
| D2 | needs-engine, area:core, area:net, area:content | Delivery by routes, and the base mode switched to it | §2's rules with DD2, DD5 and DD6's recommendations taken; DE2 to DE8 and DE13: `DeliveryRoute`, `Delivery`'s routes, deal, check, demands and checks (`circles_rng`, `package` and `circle` gone), `TaskType.station_kinds()` used by `MarkerReader`, ModeCheck, `CircleViews.station_kind` (one line) and `WireBudget`'s `_Content` (station ids from `station_kinds()` over the mode's task types, not from colour demands, with a `tests/unit/server/wire_budget_test.gd` case whose longest station id belongs to a kind with no palette), `ItemSpawned` without its colour (wire row, `WireBudget`'s sample, a protocol bump), the `ClientModel` fold of DE7, the targets of DE8 in both runners and the chaos scenario; the data: `content/tasks/delivery.tres` with four routes and drop-offs (DD1 (a), DD3's placeholders), the item kinds (`wine` and `oil`, his words, and two placeholders "not a decision"), DD7's placeholder description, the base mode's `item_kinds`; the two scenarios of DE8; §7's unit tests; every test that loads the base mode still passes, each changed expectation named in the PR; ARCHITECTURE §3.3 (RNG purposes, its Delivery deal sentences and the "ids in spawn-point order" rule, §2.1), §4.2 and §4.3.4 (`ItemSpawned`), §5, §7.1.14, §9.3's station rows, §9.5.4 and §9.5.5 rewritten, §9.6, §9.7 (the targets, "no drop-off below y = 0"); provisional files named for the engineer's approval | `core/tasks/delivery.gd`, `core/tasks/delivery_route.gd`, `core/content/task_type.gd`, `core/content/mode_check.gd`, `core/content/scenario/scenario_target.gd`, `core/events/item_spawned_event.gd`, `server/levels/marker_reader.gd`, `server/wire_budget.gd`, `net/messages/wire_schema.gd`, `core/match/phases/join_rules.gd` (the version), `client/net/client_model.gd`, `client/world/circle_views.gd`, `tests/harness/` (`scenario_bot.gd`, the chaos scenario), `content/tasks/delivery.tres`, `content/items/`, `content/modes/base_mode.tres`, `content/scenarios/` (two), `tests/unit/`, `tests/fixtures/tasks/`, `tests/integration/levels/house_markers_test.gd`, `docs/ARCHITECTURE.md` | D1; `release/m7` in main (`StationState.contains`, ZE3's checks, ZE7's target); the Generator's G2 for the exact count (GE10), or D2 adds it if it starts first; G0 if landed (Delivery's `subtasks_setting` in `TaskType`); `release/m6.2` in main or not (if in, `Delivery.item_spawn_tags()` returns every route's item tag); the engineer's DD2, DD5, DD6 (each revertible) | M |
| D3 | area:client | The client's view without colours | DE11: the drop-off's look (neutral, distinct from `ZoneViews`' zones, dimmed when done), each kind's look by id, the marker (DD4 (b)) in one neutral colour over the held item's drop-off; the HUD: on main before `release/m6.2`'s #489, the destination row names no colour (the swatch goes; a line naming the place only if DD4 (d)); with #489 in main, nothing (its HUD shows no destination); `ClientModel.Item.colour` and `ItemView.make`'s colour removed; the dev previews (`client/dev/items_preview.gd`, `screen_preview.gd`, `spectate_preview.gd`); the M4 render checklist, the PR routed to `netcode-security-reviewer` too; `shot` previews; ARCHITECTURE §4.7 | `client/world/`, `client/ui/hud_text.gd`, `client/ui/hud.gd`, `client/net/client_model.gd`, `client/dev/`, `tests/unit/client/`, `tests/integration/client/`, `docs/ARCHITECTURE.md` | D2; the engineer's DD4 | M |
| D4 | area:content, area:level | The engineer's words, and the circles gone | DD1, DD3 and DD7's answers in the data (the kinds' names and display names, the description, the radii); a drop-off moved or added (DD1 (b): the living room) on House and the greybox; the circle markers removed from House's ten rooms and the greybox, `circle` dropped from `levels/CLAUDE.md`; greybox props at House's drop-offs (a dining table, a terrace table, a workbench) in `levels/props/`, collision on layer 1, with a `shot` of each room; house-map §6's Delivery rows follow DD1; provisional files named for the engineer's approval | `content/tasks/delivery.tres`, `content/items/`, `levels/house/rooms/`, `levels/greybox/greybox.tscn`, `levels/props/`, `levels/CLAUDE.md`, `docs/design/house-map.md`, `tests/unit/content/`, `tests/integration/levels/`, `docs/ARCHITECTURE.md` (§9.5, §9.6) | D2; the engineer's DD1, DD3, DD7 | S |
| D5 | needs-engine, area:core | Integration tests: Delivery on House | §7's House tests in the host's real world | `tests/integration/levels/`, `docs/ARCHITECTURE.md` (§9.7's House line) | D2; D4 for the tests on the props' tops | S |

### 9. What it means for the parallel work (nothing of theirs is edited here)
- **The Generator** (#679, PR #695): the same words (station kinds, `StationPlaced`, exact marker counts, "not a
  decision"). Delivery needs no `Interact`: it keeps "rests inside, however it got there", so a drop-off holds no rule
  and E there is `nothing_to_do`, as its §2 item 2 says of a delivery circle. G6's `CircleViews` filter ("a Delivery circle")
  reads "a Delivery drop-off" through `station_kinds()`; G3's sentence on circles below y = 0 reads "drop-offs"; G0's
  `subtasks_setting` in `TaskType` takes Delivery's `packages` with it; D2 reuses GE10's exact count. The Generator's
  stations have no palette either, so `WireBudget`, which finds station kinds only through colour demands, misses
  them too: whichever lands first moves it onto `station_kinds()` (DE4), and the other inherits it.
- **Cooking** (#682, PR #701): DE1 is cooking's own choice of item kinds over a variant field; Delivery keeps a spawn
  tag on every kind it places (CE18); a package at a cooking place stays `two_handed` under DD6 (a); DE4's
  `station_kinds()` serves its bed kinds too, if they are held in a list.
- **The M7 zone task** (`release/m7`): D2 waits for its merge and uses `StationState.contains`; ZE3's `_check_stations`
  moves onto `station_kinds()` in D2; ZE7's `STATION` target works for a drop-off kind as it is; ZE9's spacing measures
  zones against drop-off markers (DE12); ZD7's "a palette apart from the circles'" no longer applies, ZD11's look
  clash still does (DE11).
- **The M6.2 UI** (`release/m6.2`): #489's HUD shows no destination, so there the world marker of DD4 (b) is the only
  pointer while carrying; #520's Delivery card art (frames 2 and 3: "check the sign on the package", "find the room with
  that sign") and the copy deck's "Find the room with the sign that's on the package" fit DD4 (c), and DD4 (b) if
  "the sign" is read as what the item is; under (a) or (b) the UI track may redraw those frames, its call; #253's map
  screen lights a type's zones from `item_spawn_tags()`, which returns every route's item tag (storage on House, as
  today); #489's `ITEM_KEYS` has no key for the new kinds, so their display names show until the copy deck adds keys;
  `task.delivery` stays under DD7 (a).

### 10. Needs the engineer
One batched question: DD1 to DD8 (§5), each with its options and a recommendation. "Every recommendation" is a full
answer to DD2 to DD6 and DD8; DD1's names (the garden's and the terrace's items), DD3's numbers and DD7's description
are his to give, or to approve as placeholders marked "not a decision" in D2's and D4's PRs. D1 starts on DD1's
recommendation and D2 on DD2, DD5 and DD6's, each revertible in its data or code; D3 needs DD4.

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

## Consequences
- The MVP rules ADR records the engineer's change (its Deciders line, the Delivery bullet, the rows "Delivery circles
  per match" and "Distinct circle colours"), each pointing here. When this ADR is accepted its Status says so, and the
  issue that builds a rule here updates the line of the MVP rules it replaces.
- ARCHITECTURE §9.5.4 points here, §9.8 gains the row "Delivery by meaning" and §10 its questions; GDD §8 gains
  Delivery's section with the questions still open. house-map §6's Delivery rows change in D4, after DD1's answer.
- When D2 lands, ARCHITECTURE's Delivery entries (§7.1.14, §9.5.4, §9.5.5), `ItemSpawned`'s rows (§4.2, §4.3.4), §5's
  list and §9.7's targets are rewritten, with their `Built in` lines.
- The protocol version goes up once, in D2; kind numbers and versions are taken when it lands, never from here.
- Every map of the base mode needs one marker per drop-off tag: House and the greybox get them in D1, and a later map
  gets them with its level pieces (`new-level-piece`).
- Between D2 and D3 the client draws items and drop-offs in white and main's HUD shows a white swatch: playable, but
  no playtest until D3 lands.
