# House: the first map

| | |
|---|---|
| **Owner** | The engineer (the content area, #518). Agents change this file only on his word. |
| **Status** | Decided by the engineer on 2026-10-08 in chat with his agent (#591): exactly the decisions in §2. Every size, position, door and task point below is a **working draft, to be tested in a greybox**: the agent's proposals from the map sketch v0.3, which the engineer accepted as the draft, not as final numbers. |
| **Source** | The engineer's map sketch v0.3, an interactive HTML page in his chat session (not in the repo). This file and the floor plans next to it carry its data for everyone else. |
| **Numbers used** | Walk 4.5 m/s, sprint 7 m/s and voice 8 m from `content/modes/base_mode.tres`; world sounds 12 m from `client/world/sound_chooser.gd` (a placeholder there). |

Floor plans (generated from the sketch's data; grid 5 m):
[level -1, basement](house-map/level-minus-1.svg) ·
[level 0, ground floor and yard](house-map/level-0.svg) ·
[level 1, second floor](house-map/level-1.svg) ·
[level 2, attic and roof](house-map/level-2.svg)

## 1. Purpose

The first map of the game (the engineer's working title: "Prime Friends"; the sides stay Engineers and Dissidents):
a country house with a yard, laid out for the five task chains: delivery, the generator, burgers, photo and the car
repair. This file is the input for a greybox of the map and its first test of distances and travel times.

## 2. Decisions (the engineer, 2026-10-08)

1. **The first map is a country house with a yard.** The plot is 80 x 60 m, kept as the starting scale until a
   greybox playtest. 4 to 10 players.
2. **Four levels:** the basement (-1), the ground floor with the yard (0), the second floor (1), the attic and the
   roof (2).
3. **Two basement entrances only:** from the pantry in the house, and outdoor stairs behind the garage. No hatch in
   the middle of the yard.
4. **The external stairs from the balcony down to the terrace stay:** a second exit from the second floor and a loop
   around the house.
5. **Storage in the basement is the hub:** deliveries, burgers and the car repair start there.
6. **Burgers:** an order board in the kitchen (bun, meat, herb, shown by a code or an icon). Raw meat is fried on a
   grill in a "chill zone" with music in the south-west corner of the yard and carried back to the kitchen. The
   greenhouse has a board mapping icons to herbs, new each round. The long meat run is intended.
7. **Photo:** a fun photo zone (a gazebo, north-west) -> the printer in the study on the second floor -> the darkroom
   in the basement. Kept as is.
8. **Generator:** in a large basement hall. Always four switches, in four different rooms, more than 8 m apart, so
   players at them cannot hear each other. The quest sets how many of them (2 to 4) can be switched off; the rest
   stay statically on.
9. **Garage:** a car on a lift. One player holds the lift, another goes under the car to fit a part brought from
   storage. The dropped car kills at once.
10. **One-shot kills** exist in the game, but only as rare moments that are hard to abuse: the dropped car now, maybe
    later a single-shot weapon that is very hard to get. The player respawns as usual. (GDD §1's pillar "Macro skill
    over micro skill" follows this; see the amendment of 2026-10-08 in
    [vision revision 1](../decisions/2026-10-01-vision-revision-1.md).)
11. **Attic and roof:** the attic is a room full of old things and decor where items can be hidden. The roof is a
    lookout over the yard instead of a camera room; loot may lie there. The door to the roof is always locked (a key
    or a lockpick opens it).
12. **Later, not MVP:** locked doors on routes with keys and lockpicks, a zipline from the roof, an injury from falling
    off the roof.

## 3. Coordinates and levels

Metres; the origin is the north-west corner of the plot, x runs east, y runs south. The plot (0..80, 0..60) is fenced;
the street runs along its south side (y 60..66), with a wicket to the house path and the gates to the garage. The
house is 24 x 20 m (x 18..42, y 24..44) on two floors, with the attic and the roof above. The plot's diagonal is
100 m: 22.2 s walking, 14.3 s sprinting.

| Level | What | Plan |
|---|---|---|
| -1 | Basement: storage, the generator hall and its side rooms, the darkroom | [level-minus-1.svg](house-map/level-minus-1.svg) |
| 0 | Ground floor of the house, the yard, the garage, the greenhouse, the photo zone, the chill zone | [level-0.svg](house-map/level-0.svg) |
| 1 | Second floor of the house and the balcony | [level-1.svg](house-map/level-1.svg) |
| 2 | Attic and roof | [level-2.svg](house-map/level-2.svg) |

## 4. Rooms (working draft)

Position is the room's north-west corner (x, y). Names are English working names; the game names each room by its
room record (#306): its id, its scene's file name, and the copy deck's `room.<id>` with English and Ukrainian text.

### Level -1: basement

| Room | x, y | Size | What is there |
|---|---|---|---|
| Storage | 14, 18 | 16 x 16 m | The hub (decision 5): shelves with buns, a freezer with raw meat, wine, boxes and car parts; switch A. Stairs up to the pantry. |
| Darkroom | 14, 34 | 16 x 10 m | The board where the printed photos are hung. Opens only to storage. |
| Corridor | 30, 26 | 10 x 4 m | From storage to the generator hall. |
| Boiler room | 30, 34 | 10 x 12 m | Switch B. Opens only to the generator hall. |
| Generator hall | 40, 22 | 18 x 20 m | The large hall with the generator, under the yard (decision 8). |
| Pump room | 44, 42 | 10 x 8 m | Switch C. Opens only to the generator hall. |
| Switch room | 42, 16 | 8 x 6 m | An electrical switch room in a dead end off the generator hall; switch D. |
| Passage | 58, 28 | 8 x 6 m | From the generator hall to the outdoor stairs behind the garage. |

### Level 0: ground floor and yard

| Room | x, y | Size | What is there |
|---|---|---|---|
| Yard | 0, 0 | 80 x 60 m | The fenced plot. |
| Street | 0, 60 | 80 x 6 m | Outside the fence; players enter the yard from here. |
| Path | 29, 44 | 2 x 16 m | From the wicket to the main entrance. |
| Driveway | 59, 48 | 10 x 12 m | From the gates to the garage. |
| Garden | 46, 2 | 32 x 28 m | Open garden around the greenhouse; a delivery drop-off. |
| Greenhouse | 58, 6 | 16 x 12 m | Herb beds and the board mapping icons to herbs (decision 6). |
| Photo zone | 4, 6 | 10 x 10 m | The fun gazebo photo zone (decision 7). |
| Terrace | 22, 16 | 20 x 8 m | Off the dining room; a table as a delivery drop-off; the external stairs up to the balcony. |
| Chill zone | 2, 44 | 14 x 14 m | The south-west corner: the grill, deckchairs, music (decision 6). |
| Outdoor stairs | 62, 29 | 4 x 4 m | Stairs down to the basement behind the garage, into the passage to the generator hall (decision 3). |
| Garage | 54, 34 | 18 x 14 m | The car on the lift (decision 9) and a workbench (a delivery drop-off). A back door to the outdoor stairs, a side door to the yard, the gates to the driveway. |
| WC | 18, 24 | 6 x 6 m | Opens to the living room. |
| Pantry | 24, 24 | 6 x 6 m | Stairs down to storage (decision 3). |
| Dining room | 30, 24 | 12 x 6 m | A big table (the wine drop-off); a door to the terrace. |
| Living room | 18, 30 | 8 x 14 m | No task: a place where everyone crosses. |
| Stairs | 26, 30 | 8 x 6 m | The main stairs to the second floor. |
| Kitchen | 34, 30 | 8 x 14 m | The burger order board; burgers are assembled here. A side door to the yard towards the garden and the garage. |
| Hallway | 26, 36 | 8 x 8 m | The main entrance from the path. |

### Level 1: second floor

| Room | x, y | Size | What is there |
|---|---|---|---|
| Bedroom | 18, 24 | 8 x 10 m | No task yet. |
| Kids' room | 18, 34 | 8 x 10 m | No task yet. |
| Landing | 26, 24 | 8 x 20 m | The stairs down and the hatch with a ladder up to the attic. |
| Study | 34, 24 | 8 x 8 m | The computer and the printer for the photos (decision 7). |
| Bathroom | 34, 32 | 8 x 4 m | |
| Guest room | 34, 36 | 8 x 8 m | No task yet. |
| Balcony | 30, 21 | 10 x 3 m | Above the terrace, with a view of the garden and the photo zone; the external stairs down to the terrace (decision 4). |

### Level 2: attic and roof

| Room | x, y | Size | What is there |
|---|---|---|---|
| Attic | 18, 24 | 24 x 20 m | Old things and decor to hide items among, under the pitched roof; the roof outside with the lookout over the yard and the loot (decision 11): one piece since the art import (#523, G1). |

## 5. Entrances and links between levels

| Link | Where (x, y) | Levels |
|---|---|---|
| Pantry stairs: the house to storage | 27, 28 | 0 <-> -1 |
| Outdoor stairs behind the garage: the yard to the passage and the generator hall | 64, 31 | 0 <-> -1 |
| Main stairs: the ground floor to the landing | 28, 33 | 0 <-> 1 |
| External stairs: the terrace to the balcony | 39, 22.5 | 0 <-> 1 |
| Hatch and ladder: the landing to the attic | 28, 28.5 | 1 <-> 2 |
| Climb-out: the attic's dormer window to the roof (the art's `stair_dormer`, #523) | 35, 42.85 | 2 (locked, decision 11) |

Ways into the house on the ground floor: the main entrance from the path (hallway, south), the kitchen's side door
(east) and the dining room's door to the terrace (north). The yard has two openings to the street: the wicket (x 30)
and the garage gates (x 64). Every door's position is on the floor plans.

## 6. Task stations

Each chain's points, with level and position (x, y). "Proposal" marks a point the sketch itself called a proposal.

| Chain | Point | Level | x, y | Room |
|---|---|---|---|---|
| Delivery | Wine rack (a source: any Delivery item starts on any storage spot, decided in #683) | -1 | 16, 26 | Storage |
| Delivery | Boxes (a source, as the wine rack) | -1 | 21, 29 | Storage |
| Delivery | Dining table (drop-off, the wine): the art's long table (3 x 1.2 m) with eight chairs, its marker at the table's centre (#831) | 0 | 36, 27 | Dining room |
| Delivery | Terrace table (drop-off, the parasol, approved by the engineer in #683): the art's table (1.6 x 0.9 m) with four chairs, its marker at the table's centre, and an empty parasol stand at its east end (`levels/props/parasol_stand.tscn`, 29.98, 20, #831) | 0 | 29, 20 | Terrace |
| Delivery | Garden drop-off (the garden gnome, approved by the engineer in #683): the art's garden drop-off (`levels/house/outdoor.tscn`) under its marker | 0 | 62, 24 | Garden |
| Delivery | Workbench (drop-off, the motor oil): the art's workbench against the east wall (centre 71.5, 37); the marker 1 m east of the first point (70, 37), whose 1 m cylinder missed the bench's top (#831) | 0 | 71, 37 | Garage |
| Generator | Generator | -1 | 49, 32 | Generator hall |
| Generator | Switch A | -1 | 16, 32 | Storage |
| Generator | Switch B | -1 | 32, 44 | Boiler room |
| Generator | Switch C | -1 | 52, 48 | Pump room |
| Generator | Switch D | -1 | 48.5, 19.5 | Switch room |
| Burgers | Order board; assembly | 0 | 39, 37 | Kitchen |
| Burgers | Buns | -1 | 17, 22 | Storage |
| Burgers | Raw meat (freezer) | -1 | 23, 21 | Storage |
| Burgers | Grill | 0 | 8, 50 | Chill zone |
| Burgers | Herb board (icon -> herb, new each round) | 0 | 62, 15.5 | Greenhouse |
| Burgers | Herb beds | 0 | 67, 11 | Greenhouse |
| Photo | Photo spot | 0 | 9, 11 | Photo zone |
| Photo | Camera on its tripod, facing the photo spot; it takes a film, the frames left shown on it (#687) | 0 | 13.3, 11 | Photo zone |
| Photo | A film at the round's start, beside the camera (#687) | 0 | 12.5, 11.8 | Photo zone |
| Photo | Computer and printer (the desk at 40, 29; the point is its use spot, #783) | 1 | 39.1, 29 | Study |
| Photo | Board for the printed photos | -1 | 22, 40 | Darkroom |
| Photo | Box of new films (#687) | -1 | 19.5, 30.4 | Storage |
| Car repair | Car parts shelf: its middle bin's use spot, the bins 0.6 m apart along the shelf (bin 1 at 27.6, 32, bin 3 at 26.4, 32; three, RD2's placeholder; #809) | -1 | 27, 32 | Storage |
| Car repair | Car on the lift: its use spot under the car, on the garage floor (`car_end` at 64, 38.7; #809) | 0 | 64, 41 | Garage |
| Car repair | Lift control: its use spot, 5 m west of the car's (RD2's placeholder), behind a partition that hides the space under the car (no view of who is under the car, decided in #688; 57, 46 was the first proposal, 8.6 m from the car; #809) | 0 | 59, 41 | Garage |
| Car repair | Picture of the needed part: its use spot, the frame on the garage's east wall at 71.9, 40.5 (on a garage wall, decided in #688; the point R5's, #809) | 0 | 70.7, 40.5 | Garage |
| Zone task | A zone (placeholder until the engineer moves it, #651; up from the generator hall, #681) | 0 | 48, 37 | Yard, between the kitchen and the garage |
| Zone task | A zone (placeholder, #651; 5 m south of its first point, 52, 20, which the art's garden dressing fills, #523) | 0 | 52, 25 | Garden |
| Zone task | A zone (placeholder, #651) | 1 | 30, 41 | Landing |
| Other | Music speaker | 0 | 12, 55 | Chill zone |
| Other | Hiding spots among old things | 2 | 22, 39 | Attic |
| Other | Lookout over the yard | 2 | 39, 41.9 | Attic, on its roof |
| Other | Loot | 2 | 41, 26 | Attic, on its roof |

No zone stands in the basement: the bot scenarios read every map of the base mode through a flat fake whose one floor
is at y = 0, where a station marker below it finds no floor (`levels/CLAUDE.md`, #681). The yard's zone stands above the
generator hall, 4 m east of its old point (44, 37): 6 m from the house and from the garage, 15.6 m from the nearest
drop-off on its floor (the dining table's; the kitchen's delivery circle, 12 m away, went with #831).

The photo stations (#783, proposed for the engineer's approval; each point is the use spot of its station scene in
`levels/stations/`, where the user stands): the photo spot is the gazebo's centre, on its deck (y 0.15), its 2 m floor
mark inside the deck; the camera stands outside the gazebo's open east side, its use spot 4.3 m from the spot, so the
whole mark lies beyond the camera's reach (2 m + 2 m, the photo task ADR's PD18 and PE12), and the shooter looks west
through the opening between the gazebo's posts; the first film lies on the grass 0.8 m south of the tripod; the box
of new films stands free on storage's floor, west of the darkroom's door (kept clear: a box there shut the darkroom
off); the printer's desk stays where the art put it, its use spot 0.9 m west of it (the art's chair there is gone);
the board's use spot is 1.2 m in front of it.

The generator's switches, straight-line distances: A-B 20.0 m, B-C 20.4 m, C-D 28.7 m, B-D 29.5 m, A-D 34.8 m,
A-C 39.4 m. Every pair is farther apart than the voice range (8 m), and than the world sounds' 12 m: the bound of the
switches' spacing test is 12 m (the engineer, 2026-10-10, the
[Generator ADR](../decisions/2026-10-10-generator-task.md)'s GD12), stricter than decision 8's 8 m, so a switch's click
is out of earshot too. The test measures between the use cylinders, since a player uses a switch from anywhere in its
cylinder: at least 12 m between the cylinders, so the switch markers stand at least 16 m apart at the 2 m placeholder
(the engineer,
[PR #695, comment 6100556117](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6100556117)); the
nearest pair here is 20 m.

The car repair (the engineer, 2026-10-10, #688; the rules in [GDD](../GDD.md) §8): the lift panel has no view of who
is under the car; a dissident plays by the same rules (#679's shared rule), so anyone holding the lift may let it go.
The panel's proposed point stands 8.6 m from the car (a straight line), beyond a station's reach, so one player cannot
hold the lift and fit a part; but that is beyond the voice range (8 m) from parts of the panel's reach, and the holder
relies on voice. So the panel moves nearer: every point of its reach within the voice range less a margin of the car's
use spot, and still out of reach of the car (the [car repair ADR](../decisions/2026-10-10-car-repair-task.md)'s RD2:
5 m, a placeholder; its issue R5 places it and R8 checks it). The garage's level gives the panel its blind side:
a full-height partition 1 m east of the panel's use spot, between it and the car (#809, provisional). His answers of 2026-10-10 (PR #709): a picture on a garage wall shows the part the car needs, for now
(later, ideally, a player crawls under the car to see it); the fitter works crouched under the raised car, every
player having a crouch (#727). He approved the car repair for the MVP only (PR #709, comment 6100556321): a much
more interesting mechanic will replace it later. It plays on the House only, never on the greybox (#767).

Delivery (the engineer, 2026-10-10, #683; the rules in [GDD](../GDD.md) §8): each item goes to its own drop-off by
what it is, with no colours and nothing pointing to the place; the garden gnome, the parasol and the name "Motor oil"
are his, approved as drafted
([PR #713, comment 6100696677](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6100696677)). This
Delivery plays on the House only: the greybox, a test bench only (#767), keeps today's colour-matched Delivery as far
as its bot scenarios and the information-leak test need it, and gets no drop-offs (DD9 (c) of the
[Delivery by meaning ADR](../decisions/2026-10-10-delivery-by-meaning.md), the same comment). The House's circle
markers went with the ADR's D4 (#831, the study's last in #1059). Each
drop-off's furniture is the art's dressing where the art gives it (the rows above), with layer-1 colliders: an item
put on a top rests inside the drop-off's cylinder (`tests/integration/levels/house_drop_offs_test.gd`). The two
tables differ at a glance: the long indoor one with eight chairs, the small outdoor one with four and the empty
parasol stand beside it.

## 7. Routes and travel times

Lengths follow the route's waypoints through doors and stairs in straight segments; each change of level counts as
6 m. Times are travel only, without the actions, at 4.5 m/s walking and 7 m/s sprinting (sprint stamina ignored).

| Route | Chain | Levels | Length | Walk | Sprint |
|---|---|---|---:|---:|---:|
| Burger: bun and meat | Kitchen (order) -> storage (bun, meat) -> grill in the chill zone -> kitchen | 0 -> -1 -> 0 | 135 m | 30.1 s | 19.3 s |
| Burger: herb | Kitchen (icon) -> greenhouse (herb board, bed) -> kitchen | 0 | 94 m | 20.9 s | 13.5 s |
| Delivery: wine | Storage (wine) -> pantry -> dining table | -1 -> 0 | 26 m | 5.9 s | 3.8 s |
| Delivery: garage | Storage (box) -> generator hall -> outdoor stairs behind the garage -> workbench | -1 -> 0 | 60 m | 13.4 s | 8.6 s |
| Delivery: garden | Storage (box) -> generator hall -> outdoor stairs behind the garage -> garden | -1 -> 0 | 57 m | 12.6 s | 8.1 s |
| Car repair | Storage (part) -> generator hall -> outdoor stairs behind the garage -> lift | -1 -> 0 | 54 m | 12.0 s | 7.7 s |
| Photo | Photo zone -> terrace -> study (print) -> down to the basement -> darkroom | 0 -> 1 -> 0 -> -1 | 118 m | 26.2 s | 16.9 s |
| Loop: house, basement, yard | Kitchen -> pantry -> storage -> generator hall -> outdoor stairs -> yard -> kitchen | 0 -> -1 -> 0 | 97 m | 21.5 s | 13.8 s |
| Loop: house, second floor, terrace | Dining room -> stairs -> landing -> balcony -> external stairs -> terrace -> dining room | 0 -> 1 -> 0 | 46 m | 10.2 s | 6.5 s |
| Generator: all four switches | D -> B -> C -> A, the run to reach every switch | -1 | 105 m | 23.4 s | 15.0 s |

## 8. Level-design logic

Why the map is laid out this way (the sketch's reasoning, accepted with the draft):
- **Storage is the heart.** Deliveries, burgers and the car repair start there, switch A stands there and the
  darkroom opens off it. Two ways lead in from opposite sides (the pantry in the house, the outdoor stairs behind the
  garage), so one player standing in a doorway cannot cut it off.
- **Loops instead of corridors.** Two loops let a player escape or go around: house -> basement -> yard -> house, and
  house -> second floor -> balcony -> terrace. No floor of the house has a single exit; the external stairs (decision
  4) are what gives the second floor, with the printer in the study, its second one.
- **Stations spread to every side.** Photo in the north-west, the grill in the south-west, the greenhouse in the
  north-east, the garage in the south-east, the generator underground. Tasks spread the players over the map; storage
  and the kitchen bring them back together.
- **Intended dead ends.** The boiler room, the pump room, the switch room, the darkroom, the attic and the spot under
  the car are dead ends where a task leads a player alone. That is the tension: who comes in after you?
- **Voice does not carry between stations.** The switches stand more than 8 m apart, and the grill, the greenhouse
  and the photo zone are far from the other stations: to know what happens there, someone has to go and look.
- **The roof sees the yard, not inside.** From the roof you see who runs across the yard, but not what happens in the
  house or the basement: the information is incomplete.

## 9. Later, not MVP

From decision 12: locked doors on routes, with keys and lockpicks; a zipline from the roof; an injury from falling off
the roof. Decision 10 adds a possible single-shot weapon that is very hard to get.

## 10. Open questions

- **Scale.** Is 80 x 60 m right for 4 and for 10 players? The greybox playtest answers it (decision 1).
- **Walls and floors.** Every distance here is a straight line that ignores walls and floors (the voice and sound
  ranges included). The greybox shows whether stations that are far apart on the plan are also apart to the ear.
- **#523** (answered). How does this map relate to the environment team's house in #523 (the M6.2 slice's level)? Is
  House that level, or a later map? Players always play the House (the engineer's option (a) on #767, GDD §13);
  #523 imports the art track's expanded House into `levels/house`.
- **Rooms in the level data** (answered). The room record (#306) gives each room its id and its name as a deck key
  (English and Ukrainian), on the room scene's root; no sign (the engineer on #306: no wall signs).
- **Ideas from the sketch, not decided.** The sketch described these, but the engineer has not decided them; they stay
  out of the rules until he does (the generator's two he decided on 2026-10-09, in #679 and [GDD](../GDD.md) §8: it
  charges only while every switch is on, and anyone may switch any active switch on or off):
  - photo: a screen in the photo zone shows a pose silhouette, one player poses with gestures and another takes the
    shot;
  - how dissidents interfere with each chain (a wrong herb, a wrong pose or a spoiled shot; a wrong part is no longer
    one: the car refuses it, decided in #688; for the burgers he decided it in #682: a dissident may hide a box, and
    the rules let anyone burn a patty or put a wrong ingredient on a plate, [GDD](../GDD.md) §8);
  - the street as a spawn point at the start of a round;
  - whether the loot on the roof is a weapon (the burgers' counts he decided on 2026-10-10, in #682 and
    [GDD](../GDD.md) §8: 3 buns, 3 patties and 5 herbs).
