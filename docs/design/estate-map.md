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
   burger plates, the battery charger); the house behind it.
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
| House | 68.4, 11 | 12 x 10 | 12 | -1, 0, 1, roof |
| Bonfire | 65.3, 41 | fire pit r 2, benches r 7 | 13 | 0 |
| Summer kitchen | 82.8, 30 | 8 x 5, open, roofed | 9 | 0 |
| Pantry | 48, 27 | 6 x 5 | 8 | 0 |
| Greenhouse | 30, 12 | 10 x 6, glass | 10 | 0 |
| Garage | 101.4, 11 | 8 x 8 | 10 | 0 |
| Gazebo (photo) | 114.9, 34 | r 3.5, open | 8 | 0 |
| Well | 24.9, 72 | r 1.2 | 7 | 0 |
| Ship (a manta, §5a) | 116, 72 | 26 wide x 14 deep, its mouth ramp facing north | 16 | 0 and its interior |
| Fallen trunk | 86, 79.5 | 12 x 3, east-west, walkable inside | | 0 |
| Gate | 67.5, 90 | 4 wide | | 0 |

**The creek:** (0, 48) → (22.5, 49.5) → (45, 60) → (67.5, 63) → (90, 55.5) → (112.5, 54) → (135, 57), about 3 m wide,
not crossable except at the crossings: the log bridge (30, 51.8), the stepping stones (57, 62.3), the drainage pipe
(94.5, 54.8).

## 4. Paths

2.5 m wide, a lantern every 6 m.
- **Upper loop:** bonfire → pantry → greenhouse → house → garage → gazebo → summer kitchen → bonfire.
- **Lower loop:** bonfire → stepping stones → well → fallen trunk → ship → pipe → bonfire.
- **Spokes:** house ↔ bonfire; pantry → log bridge → well; gazebo → ship (east side); trunk → gate; garage →
  driveway.

## 5a. The ship (the engineer, 2026-10-20)

The aliens' ship is a **wide metal manta** (#1035 comment 6299338851): broad flat wings, two eye-like cockpit bubbles,
a mouth-shaped front ramp, a side hatch; wider than it is long. Its interior is one deck, built for the ship's engine
(GDD §8), approved on #1035 comment 6300127535:
- **The mouth ramp** (north side, the ship's centre) leads into **the central hall** under the two cockpit bubbles:
  the start console with the start lever, the battery slot and the stage display (one lamp per stage).
- **Two corridors** run from the hall along the wings, across the whole width of the ship (about 2.5 m wide, curving
  with the wing).
- **Five problem stations** stand along the corridors: in the west wing a vent (overheat), a cartridge socket and the
  switch panel (four coloured switches, a lamp over each); in the east wing a vent and a cartridge socket.
- **The cartridge renewer** stands at the east wing's tip; **the side hatch** at the west wing's tip is the ship's
  second way out. A burnt cartridge from the west wing runs the whole width of the ship to be renewed (about 22 m,
  5 s each way at a walk), well inside the cartridge's 30 s.
- Positions inside, from the ship's centre (x east, y south): the console (0, 1); the west vent (-5, -1), the west
  socket (-8, -1), the panel (-10.5, 0); the east vent (5, -1), the east socket (8, -1); the renewer (12, 0); the side
  hatch (-12.5, 1). Working draft.

## 5. Links between levels

| Link | Levels | Why |
|---|---|---|
| Inner stairs: living room ↔ basement | 0 ↔ -1 | |
| Outdoor cellar door on the house's west side | 0 ↔ -1 | the basement's second exit |
| Inner stairs: living room ↔ library | 0 ↔ 1 | |
| Outdoor stairs: the library's balcony ↔ the yard | 1 ↔ 0 | the second floor's second exit |
| Ladder through a hatch: library ↔ roof terrace | 1 ↔ roof | the fireworks' launch point |

## 6. Task stations

| Station | Where | Task (GDD §8, m8-match) |
|---|---|---|
| The car, its order board, tools on cables | garage | car tuning |
| Big parts printer, small battery printer, mutation workbench, healing pod | laboratory (basement) | car tuning, the battery, mutations |
| Food printer, paint mixer, fireworks crates | pantry | cooking, car tuning, mischief |
| Five flower beds | greenhouse | car paint, cooking |
| Well and watering can | well | the flowers |
| Grill, loudspeakers | bonfire | cooking, mischief (loud music) |
| Numbered plates, microwave charger, bins | summer kitchen | cooking, the battery, mischief (the bins) |
| Serving board | living room | cooking |
| Decoder book, house phone | library | the Wi-Fi |
| Wi-Fi computer, house phone, camera wall, light breaker | security room (basement) | the Wi-Fi, cameras, the blackout |
| Cellar | basement | decor |
| Fireworks launch point | roof terrace | mischief |
| Camera and pose spot | gazebo | photo |
| Start console (lever, battery slot, stage lamps), five problem stations, cartridge renewer (§5a) | ship | the ship's engine |
| The dead's room | a separate scene | death (m8 §3) |

## 7. Routes and travel times

Lengths follow the paths plus 6 m per change of level; times are travel only, without the actions.

| Route | Chain | Levels | Length | Walk | Sprint |
|---|---|---:|---:|---:|---:|
| Car, one part | greenhouse → laboratory → pantry → garage | 2 | 168 m | 37 s | 24 s |
| Burger | pantry → greenhouse → grill → summer kitchen → living room | 0 | 148 m | 33 s | 21 s |
| Watering | greenhouse → well → greenhouse | 0 | 158 m | 35 s | 23 s |
| Battery for the ship | laboratory → summer kitchen → ship | 1 | 107 m | 24 s | 15 s |
| Battery for the car | laboratory → summer kitchen → garage | 1 | 72 m | 16 s | 10 s |
| Fireworks | pantry → house → roof | 2 | 46 m | 10 s | 7 s |
| Photo | bonfire → gazebo | 0 | 65 m | 15 s | 9 s |
| Wi-Fi solo, one password | security room → library → back | 4 | 50 m | 11 s | 7 s |
| Blackout fix | bonfire → breaker | 1 | 45 m | 10 s | 7 s |
| Upper loop | the whole loop | 0 | 256 m | 57 s | 37 s |
| Lower loop | the whole loop | 0 | 271 m | 60 s | 39 s |

The closest stations (straight): bonfire–summer kitchen 21 m, bonfire–pantry 22 m, pantry–greenhouse 23 m,
house–summer kitchen 24 m.

## 8. Open

- A tunnel from the garage to the basement (not drawn).
- The roof's second way down.
- The tree strips' density and the night's sight distance: from walking the greybox.
- The amount of work per match: at this scale a clean expert team finishes in about 5 minutes; the host's counts and
  the engine's stages are the lever (the balance model, #1089).
