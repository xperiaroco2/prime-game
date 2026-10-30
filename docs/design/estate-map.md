# The forest estate: the MVP's map

| | |
|---|---|
| **Owner** | The engineer (the content area, #518). Agents change this file only on his word. |
| **Status** | Approved by the engineer on 2026-10-20 as the MVP's map ([#1035 comment 6297325577](https://github.com/xperiaroco2/prime-game/issues/1035#issuecomment-6297325577)): the decisions in §1 are his. Every position, size and time below is a **working draft for a box greybox**, to be tuned by walking it. |
| **Source** | The design track's concept art rounds and a first-person walk-through prototype (prime-game-design, `ideas/2026-10-20-*.md`, #1035). The House ([house-map.md](house-map.md)) stays as M7's map and record. |
| **Numbers used** | Walk 4.5 m/s, sprint 7 m/s and voice 8 m from `content/modes/base_mode.tres`, as in `house-map.md`. Paths count 1.3 times their straight line; a change of level counts 6 m. |

## 1. Decisions (the engineer, 2026-10-20)

Recorded on #1035 (comments 6291174376 to 6297325577) and #1033 (6294249388).
1. **A country estate in a pine forest on the edge of a small town.** Two sides forest, two sides a road with the
   neighbours' cabins. No interaction with the neighbours for now.
2. **Separate small buildings in their own clearings,** joined by lantern-lit paths; trees grow in strips between the
   clearings, not as a solid forest. No pool and no DJ stage: no mechanic needs them.
3. **No dead ends:** every clearing has at least two ways out; the paths form a figure eight.
4. **The bonfire is the party's heart,** in the centre (the grill, the loudspeakers); the summer kitchen beside it (the
   burger plates); the house behind it.
5. **The house is small but tall:** the living room (the burger serving board), the library on the second floor, the
   basement (the laboratory, the security room, a cellar), the roof terrace.
6. **The pantry** stands between the greenhouse and the bonfire; **the well** far from the greenhouse, so watering is a
   walk; **the ship** on the lower loop, not in a corner.
7. **Passages:** a creek across the plot with three crossings (a log bridge, stepping stones, a drainage pipe) and a
   hollow fallen trunk to crawl through. No zip line for now.
8. **Scale:** the plot is 135 x 90 m, neighbouring stations at least about 20 m apart (the voice carries 8 m), so one
   station's talk does not spill into the next.
9. **Night:** lit clearings, dark paths; light sets how far you see. **The blackout** (GDD §7) cuts the estate's lights.
10. **Modules:** every location is a separate module (a building, its clearing and the points where paths reach it),
    so modules can be moved and the surroundings changed without rebuilding the rest.

## 2. Coordinates and levels

Metres; the origin is the plot's north-west corner, x runs east, y runs south. The plot (0..135, 0..90) is fenced. The
road runs along the south side (y 90..96) with the gate at x 67.5, and along the east side (x 135..141) with the
garage's driveway at y 11. North and west: forest.

| Level | What |
|---|---|
| -1 | The house's basement: the laboratory, the security room, the cellar |
| 0 | The plot: every clearing, the house's living room, the ship |
| 1 | The house's library and its balcony |
| roof | The house's roof terrace |

## 3. Modules (working draft)

| Module | Centre (x, y) | Footprint (m) | Clearing radius (m) | Levels |
|---|---|---|---:|---|
| House | 68.4, 11 | 12 x 10; the basement 20 x 16, under the yard to the south (§5c) | 12 | -1, 0, 1, roof |
| Bonfire | 65.3, 41 | fire pit r 2, benches r 7 | 13 | 0 |
| Summer kitchen | 82.8, 30 | 8 x 5, open, roofed | 9 | 0 |
| Pantry | 48, 27 | 8 x 6 (§5d) | 8 | 0 |
| Greenhouse | 30, 12 | 10 x 6, glass | 10 | 0 |
| Garage | 101.4, 11 | 10 x 8, the long side east-west (§5d) | 10 | 0 |
| Gazebo (photo) | 114.9, 34 | r 3.5, open | 8 | 0 |
| Well | 24.9, 72 | r 1.2 | 7 | 0 |
| Ship (a manta, §5a) | 116, 72 | 26 wide x 14 deep, its mouth ramp facing north | 16 | 0 and its interior |
| Fallen trunk | 86, 79.5 | 12 x 3, east-west, walkable inside | | 0 |
| Gate | 67.5, 90 | 4 wide | | 0 |

**The creek:** (0, 48) → (22.5, 49.5) → (45, 60) → (67.5, 63) → (90, 55.5) → (112.5, 54) → (135, 57), about 3 m wide,
not crossable except at the crossings: the log bridge (30, 51.8), the stepping stones (57, 62.3), the drainage pipe
(94.5, 54.8), and a plank footbridge (118, 54.9) on the gazebo → ship spoke, which otherwise crosses the creek with no way
over (found by the design track's walk-through, 2026-10-21; a working fix for him to confirm).

## 4. Paths

2.5 m wide, a lantern every 6 m.
- **Upper loop:** bonfire → pantry → greenhouse → house → garage → gazebo → summer kitchen → bonfire.
- **Lower loop:** bonfire → stepping stones → well → fallen trunk → ship → pipe → bonfire.
- **Spokes:** house ↔ bonfire; pantry → log bridge → well; gazebo → plank footbridge → ship (east side); trunk → gate; garage →
  driveway.

## 5a. The ship (the engineer, 2026-10-20)

The aliens' ship is a **wide metal manta** (#1035 comment 6299338851): broad flat wings, two eye-like cockpit bubbles,
a mouth-shaped front ramp; wider than it is long. Its interior is one deck, built for the ship's engine (GDD §8),
approved on #1035 comment 6300127535 and revised on 2026-10-22 with the approved 2D (#1095 comments 6326838901 to
6327093164; prime-game-design `ideas/ship-components/2d/`, which keeps the look) and **mirrored** the same day (#1033
comments 6336844073 and 6336988967; the plan to scale: prime-game-design `ideas/ship-components/layout/`); at the
hull's shape gate the tip rooms moved into the rear corners and lost their windows (prime-game-art#263 comments
6340304651 and 6340589162); the throat's option A (prime-game-art#263 comment 6341553197); then the hull was rebuilt round the inside as the
lens-diamond hull P and the tip rooms became lens rooms with windows; the numbers below are **as built**:
- **One entrance:** the mouth ramp; no side hatch, no other way in or out.
- **The cockpit bubbles are on the outside only:** inside, the hall has a closed ceiling; no ladders, no seats.
- **Mirrored:** the west half and the east half hold the same stations, so a player says "left" or "right" (as you
  come in up the ramp, left is east). Every station hangs flat on a wall, no niches; whoever works at one leaves at
  least 1.6 m of pass behind them.
- **Raised on legs** (the engineer, 2026-10-23, after his walk; prime-game-art#309, its numbers in prime-game-art#263
  comment 6364737530): the deck stands 1.2 m above the ground on upright legs with pistons and 1.2 m footpads; the
  belly is 0.77 m up, the brow over the mouth 4.9 m. Station heights count from the deck, so the spots below stand.
- **The mouth ramp** (north side, 3.3 m wide) runs from the ground up into a short tunnel, 1 m long, that carries the
  mouth straight on from the nose edge; its hinge is at the tunnel's open front, (0, -8.1), its foot at (0, -12.6):
  4.66 m long at 14.9°. It leads into **the throat** (the engineer, 2026-10-22): no straight pass, its walls open as
  a funnel from 3.3 m at the mouth to the hall, 4.05 m deep, so the whole hall is seen from the mouth. Its front is an open notch in the nose, like a mouth with no upper lip; from
  where the nose is high enough it has a roof, 2.3 m clear, to the hall (option A, the nose kept as picked). Its two
  side walls (the clean throat, the engineer, 2026-10-29, #1095 comments 6497225134 and 6497869348) are vertical to
  2.10 m, then a 25 cm cove to the flat 2.30 m ceiling (the hull leaves no room for more), one clean panel each over a
  plinth with its cyan line, a frame at the ramp and a jamb at each hall corner. Each wall carries **the gills**
  (overheat, GDD §8; #1095 comment 6522811252): a gill set of five slits cut into the panel, a light bar over each and
  one round button at the set's hall end, all flush, so the whole pass stays open.
- **The central hall**, round, 8 m across (50 m²), its wall 3.2 m high all round, 3.8 m at the apex: **the start
  console** 1 m aft of its centre (the engineer, 2026-10-23, #1095 comment 6360765037): a low ring pedestal (Ø 1.2 m,
  0.6 m high) with the start button and three stage strips, and above it a hologram of the hull, level, fixed to the
  ship's axes, whose wings carry the eight lamps of both breaker boards (GDD §8; no lever, no battery, no button for
  the order); **four cartridge sockets** on its wall (the engineer, 2026-10-22: more places to burn, the same problem
  count), two on the back wall beside the vault's hatch and two at the front sides, beside the throat and clear of
  its pass. Behind the back wall, **the vault**: closed, 1.8 × 2 m, its hatch at (0, 3.6), not an exit.
- **Two corridors**, straight, 3 m wide, 2.4 m clear, run from the hall 8.66° aft out to the wings; their walls are
  vertical up to 1.45 m, then slant; on each one's front wall hangs **a breaker board** (four coloured breakers, a lamp
  over each), in sight of the console down the corridor.
- **Two lens rooms** at the wing tips, round, r 2.0 m, a window band round the outward side (sill 1.0 m, head 2.2 m),
  a slanted ceiling 2.45 to 2.35 m with three roof windows; each with **one charger** (the cartridge's renewer, GDD §8)
  against its aft wall. A spent cartridge goes to the charger on its own side, about 8.5 m from a back socket and 9 m
  from a front one in a straight line; with both sockets of a side spent, the second runs across the hall to the
  other charger or waits.
- **The silhouette** (the art track's hull P, a lens-diamond, approved 2026-10-23, prime-game-art#263 comment
  6359082930): 26.1 × 22.1 m with the engine pods, 4.82 m high before the raise, now 0.6 m higher; the ridge over the corridors 3.13 m deep, the fin
  edges about 0.4 m, the lens rims about 3.26 m; at least 0.17 m of skin round every room.
- Positions inside, as built (prime-game-art#263 comment 6346859072, `layouts/ship/ship.toml`), from the ship's centre
  (x east, y south, so +y is aft): the hall's centre (0, -0.4); the console (0, 0.6); the mouth (±1.65, -7.1) at the
  nose edge, its tunnel to y -8.1, the throat's walls to the hall's corners at y -3.25, its roof from y -5.561; the gill sets' slit middles (±2.298, -5.130), (±2.411, -4.784), (±2.525, -4.439), (±2.638, -4.094) and
  (±2.751, -3.750), along each wall from the mouth corner at s 2.07, 2.44, 2.80, 3.16 and 3.53 m, their chords 1.08,
  0.99, 0.90, 0.82 and 0.74 m between h 0.82 and 1.90 m, each bar 6 cm over its slit, the buttons (±2.856, -3.433) at
  h 1.15 m;
  the back sockets (±1.800, 3.112), the front sockets (±3.426, -2.358); the boards (±6.664, -0.902); the lens rooms'
  centres (±10.5, 1.2), the chargers (±10.269, 3.237), 0.9 m deep. Each wall spot is flat on a plain wall with a 1.6 m
  band.

## 5. Links between levels

| Link | Levels | Why |
|---|---|---|
| Inner stairs: living room ↔ basement | 0 ↔ -1 | |
| Outdoor cellar door on the house's west side | 0 ↔ -1 | the basement's second exit |
| Inner stairs: living room ↔ library | 0 ↔ 1 | |
| Outdoor stairs: the library's balcony ↔ the yard | 1 ↔ 0 | the second floor's second exit |
| Ladder through a hatch: library ↔ roof terrace | 1 ↔ roof | the fireworks' launch point |
| The library's bookcase: a secret stair inside the wall, library ↔ cellar | 1 ↔ -1 | §5b |
| The chimney: roof terrace → the living room's fireplace, down only | roof → 0 | the roof's second way down (§5b) |

## 5b. Passages (the engineer, 2026-10-21)

The network approved on [#1035 c6316439474](https://github.com/xperiaroco2/prime-game/issues/1035#issuecomment-6316439474) (from his word on the secret passages, the vents and the sewer,
[c6315895910](https://github.com/xperiaroco2/prime-game/issues/1035#issuecomment-6315895910)); the design track's draft:
prime-game-design `ideas/2026-10-21-estate-passages.md`. **Everything underground meets in the house's basement.**
Underground players walk at 4.5 m/s without sprinting; the ducts are gone through crouched (GDD §3, 2.0 m/s). Lengths
and times are placeholders.

| Passage | Joins | Length, time | On the surface |
|---|---|---|---|
| The library's bookcase | The library (1) ⇄ the cellar (-1): a narrow stair inside the wall. Pressing a book swings the bookcase open; from below, pulling a bottle on the wine rack | about 10 m, 4 s | security room ⇄ library 50 m, 11 s |
| The tunnel | The garage's inspection pit under the car ⇄ the laboratory | 22 m, 5 s | about 39 m, 9 s |
| The sewer | The cellar ⇄ a manhole by the bonfire (65.3, 51) ⇄ a fork under the creek (67, 64) ⇄ manholes by the well (30, 68) and by the ship's west wing (99, 73) | bonfire → ship 46 m, 10 s; well → ship 70 m, 16 s; cellar → bonfire 42 m, 9 s | 60 m, 13 s; 93 m, 21 s; about 36 m, 8 s |
| The ducts | The laboratory ⇄ a grate in the pantry (53, 25.5); the security room ⇄ a grate by the summer kitchen's bins (76.4, 30.8) | 16 m, 8 s each | about 58 m, 13 s; about 30 m, 7 s |
| The chimney | The roof terrace → the living room's fireplace, down only | at once | roof → hatch → library → stairs |

- **No dead ends:** every passage has two ends, each opening from inside and outside.
- **A passage is a way where nobody sees you,** not a teleport: mostly only a little faster than the surface; the
  tunnel and the sewer between far clearings are clearly faster.
- **An exit is seen and heard:** the bookcase opens in front of whoever is in the library; a manhole cover clangs.
- **Every passage takes anything, and the movement stays arcade** (the engineer, 2026-10-21,
  [c6316401602](https://github.com/xperiaroco2/prime-game/issues/1035#issuecomment-6316401602)): no refusal for a
  two-handed item; a ladder is climbed with anything in the hands, with no climbing animation.
- **Hiding things in the passages only costs time** (the compass §3).
- **Secret is not a hidden rule:** every passage is in the rules; a newcomer discovers it, a regular uses it.
- **The watering stays a walk:** no passage shortens the greenhouse ⇄ well trip (§1.6).
- Open: the basement's layout (the laboratory, the security room, the cellar) and where each passage starts in it.

## 5c. The house inside (the engineer, 2026-10-21)

Approved on [#1035 c6317165077](https://github.com/xperiaroco2/prime-game/issues/1035#issuecomment-6317165077); the design track's draft: prime-game-design `ideas/2026-10-21-house-inside.md`. Local metres
from the house's centre (68.4, 11): x east, z south; placeholders.

| Level | Rooms and what stands there | Ways out |
|---|---|---|
| roof | The terrace (12 x 10, railing): the fireworks crates; the chimney stack (west) | the hatch and ladder to the library (north-east); the chimney down to the fireplace |
| 1 | The library (12 x 10): bookshelves, the decoder book on a lectern (middle), the house phone (west wall); the balcony (8 x 2, south) | the inner stairs (north, middle); the ladder to the roof; the secret bookcase (north-west, §5b); the balcony's outdoor stairs to the yard |
| 0 | The living room (12 x 10, one room): the long party table, the burger serving board (east wall), the fireplace under the chimney (west wall), the stair well (north, middle) | doors south (the bonfire), east (the garage path) and west (the greenhouse path), so the upper loop runs through the house; the stairs up and down |
| -1 | The basement (20 x 16, x -10..10, z -5..11), wider than the house: **the cellar** (north-west, 8 x 7: barrels, beer crates, the wine rack, the sewer's manhole); **the stair hall** (north, middle, 4 x 7); **the security room** (north-east, 8 x 7: the camera wall, the Wi-Fi computer and the house phone, the light breaker); **the laboratory** (the whole south, 20 x 9: the big parts printer at the west end, the mutation workbench, the healing pod at the east end) | the cellar: the hall, the outdoor cellar door (west), the secret stair, the sewer; the security room: the hall, a door into the laboratory, the duct to the summer kitchen; the laboratory: the hall, the security room, the duct to the pantry (west wall), the tunnel to the garage (east wall) |

- **Every room has at least two ways out** (§1.3).
- **The secret stair runs in the thick chimney wall:** the bookcase and the wine rack stand one above the other.
- **The Wi-Fi spans the house:** the computer in the security room, the decoder book two floors up.
- **The parts printer and the healing pod stand 16 m apart,** so the laboratory's ends do not talk over each other.
- **Walls muffle the voice, openings do not** (GDD §11, "Voice through walls"): the vent grates and the manhole are where you eavesdrop.
- **The camera wall** (GDD §12): six screens for six fixed cameras, one each in a corner of the bonfire, the summer
  kitchen, the pantry, the greenhouse, the garage and the roof terrace, each in sight with a red lamp; no camera on
  the paths, the passages, the house's rooms, the laboratory or the ship.

## 5d. The outbuildings inside (the engineer, 2026-10-21)

Approved on [#1035 c6318742185](https://github.com/xperiaroco2/prime-game/issues/1035#issuecomment-6318742185); the
design track's draft: prime-game-design `ideas/2026-10-21-outbuildings-inside.md`. Local metres from each module's
centre (§3): x east, z south; placeholders. The gazebo and the well stay open, one thing each.

| Building | What stands where | Ways out |
|---|---|---|
| Garage (10 x 8) | The car in the middle, its nose to the roll-up door, over the inspection pit (its ladder at the car's back, the tunnel to the laboratory from the pit's west wall, §5b); the order board on the west wall, facing the car; the tools on cables on two ceiling rails, one on each side of the car; hazard tape on both thresholds marks where a tool drops from the hand; a workbench with a boombox (north-west corner), music always on | the roll-up door (east, always open: the driveway, the road and the neighbours in sight); a side door (south wall, west end); the pit's tunnel |
| Pantry (8 x 6) | Party-stock shelves along the north wall (beer, chips, toilet paper, pizza boxes); the food printer at the west wall; the paint mixer with its spray stand in the middle of the east wall; the fireworks crates along the south wall; the duct's grate low in the east wall's north end (§5b's 53, 25.5 moves in to this wall) | doors in the south ends of the west wall (the greenhouse path) and the east wall (the bonfire and the house); the grate |
| Greenhouse (10 x 6, glass) | Five flower beds in a row along the long axis, one colour each; a rack of watering cans inside the east door, always holding one | the east door (toward the house); a door in the middle of the south side (toward the pantry) |
| Summer kitchen (8 x 5, open, roofed) | Posts and a roof, no walls; a long counter along the north side with the numbered plates and the order board above; the bins at the west end, the duct's grate on the ground behind them (§5b) | open all round |

- **Every passage end has its place:** the pit's tunnel, the pantry's grate, the grate behind the bins.
- **The pantry is one room on purpose:** the cook and the painter meet there and see what the other carries.
- **The voice rule shapes them** (GDD §11): the garage and the pantry are closed rooms, muffled from outside and clean
  at the grate; the greenhouse's glass is seen through and not heard; the summer kitchen is open to all.
- **The grill stays at the bonfire,** 21 m from the summer kitchen: the meat run is intended.

## 6. Task stations

| Station | Where | Task (GDD §8, m8-match) |
|---|---|---|
| The car, its order board, tools on cables | garage | car tuning |
| Big parts printer, mutation workbench, healing pod | laboratory (basement) | car tuning, mutations |
| Food printer, paint mixer, fireworks crates | pantry | cooking, car tuning, mischief |
| Five flower beds | greenhouse | car paint, cooking |
| Well and watering can | well | the flowers |
| Grill, loudspeakers | bonfire | cooking, mischief (loud music) |
| Numbered plates, bins | summer kitchen | cooking, mischief (the bins) |
| Serving board | living room | cooking |
| Decoder book, house phone | library | the Wi-Fi |
| Wi-Fi computer, house phone, camera wall, light breaker | security room (basement) | the Wi-Fi, cameras, the blackout |
| Cellar | basement | decor |
| Fireworks launch point | roof terrace | mischief |
| Camera and pose spot | gazebo | photo |
| Start console (start button, stage strips, the hologram), two gill sets, four cartridge sockets, two breaker boards, two chargers (§5a) | ship | the ship's engine |
| The dead's room | a separate scene | death (m8 §3) |

## 7. Routes and travel times

Lengths follow the paths plus 6 m per change of level; times are travel only, without the actions.

| Route | Chain | Levels | Length | Walk | Sprint |
|---|---|---:|---:|---:|---:|
| Car, one part | greenhouse → laboratory → pantry → garage | 2 | 168 m | 37 s | 24 s |
| Burger | pantry → greenhouse → grill → summer kitchen → living room | 0 | 148 m | 33 s | 21 s |
| Watering | greenhouse → well → greenhouse | 0 | 158 m | 35 s | 23 s |
| Fireworks | pantry → house → roof | 2 | 46 m | 10 s | 7 s |
| Photo | bonfire → gazebo | 0 | 65 m | 15 s | 9 s |
| Wi-Fi solo, one password | security room → library → back | 4 | 50 m | 11 s | 7 s |
| Blackout fix | bonfire → breaker | 1 | 45 m | 10 s | 7 s |
| Upper loop | the whole loop | 0 | 256 m | 57 s | 37 s |
| Lower loop | the whole loop | 0 | 271 m | 60 s | 39 s |

The closest stations (straight): bonfire–summer kitchen 21 m, bonfire–pantry 22 m, pantry–greenhouse 23 m,
house–summer kitchen 24 m.

## 8. Open

- The tree strips' density and the night's sight distance: from walking the greybox.
- The amount of work per match: at this scale a clean expert team finishes in about 5 minutes; the host's counts and
  the engine's stages are the lever (the balance model, #1089).
