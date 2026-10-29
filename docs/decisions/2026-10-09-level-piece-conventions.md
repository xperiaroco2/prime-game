# Level piece conventions: folders, one grid with the art kit, rooms placed by the design doc

- **Status:** Accepted on 2026-10-09: the engineer merged its PR (#611). (Was: Proposed in #607; accepted when the
  engineer merges its PR (the content area: `levels/` and the skill `new-level-piece`).)
- **Amended 2026-10-09 (#658):** greybox role materials in `levels/kit/` and a `Name` label per room, after the
  first playtest found one grey unreadable ("Looks and collision" below).
- **Amended 2026-10-15 (#799, proposed: the engineer approves it in its PR):** station scenes, the device a player
  uses where it stands ("Station scenes" below), set by the Generator's switch and generator for the stations after it.
- **Date:** 2026-10-09
- **Deciders:** the engineer. He approved the level-design track's recommendations in chat on 2026-10-09 ("з усім
  рекомендаціями згоден") and reviews their written form here.
- **Tracking:** #607; the map #591 ([design doc](../design/house-map.md)); the art kit
  xperiaroco2/prime-game-art#73 and #74

## Context
`levels/CLAUDE.md` leaves the folder layout and the piece conventions to the engineer "when level work starts", and
the skill `new-level-piece` stops until they are written. Level work starts now: the first map, House, is approved and
goes into modelling on the art side, kit first. The engineer wants the map built from independent pieces, so that a
room can be moved, resized or replaced after a playtest without touching the rest of the map.

Two things go wrong without shared conventions:
- the art kit is modelled on one grid and the game's rooms on another, and walls stop meeting at the seams;
- the map scene drifts from the design doc's plan, and nobody notices until a playtest disagrees with the doc.

## Decision

### Folders
| Path | What |
|---|---|
| `levels/<map>/<map>.tscn` | The map. It only instances and places pieces; it holds no geometry of its own. |
| `levels/<map>/rooms/<room>.tscn` | One scene per room of the map's design doc. |
| `levels/stations/<station>.tscn` | Task stations, reusable on any map (a generator switch, the grill, the lift). |
| `levels/props/<prop>.tscn` | Dressing props. |
| `levels/kit/<piece>.tscn` | Thin wrappers of the art kit's GLBs (a wall module, a floor, stairs), each with its own collision; until the kit lands, the greybox role materials. |

The MVP scenes the base mode names (`levels/lobby/lobby.tscn`, `levels/greybox/greybox.tscn`) stay where they are.

### One grid with the art kit
- Whole metres. Walls in 2 m and 1 m modules.
- 3.2 m floor to floor: levels -1, 0 and 1 at Y -3.2, 0 and 3.2. An attic floor at 6.4 with 2.2 m knee walls.
- Doors 1.4 m wide and 2.15 m high; the garage gate 8 m.

These are House's numbers and the art kit's (xperiaroco2/prime-game-art#74). A later map may use other room sizes but
keeps the grid, so the kit carries over.

### Coordinates: the map is placed by its design doc
A design doc's plan maps straight onto Godot: plan x is X, plan y is Z, a level is Y. A room scene's origin is its
north-west floor corner, so the map places each room at the doc's (x, level height, y), with no rotation. Moving a room
in the doc and in the map is the same number.

**Amendment 2026-10-29 (#1375): a lot is placed by its centre.** A map whose design doc gives a lot's centre
(`docs/design/estate-map.md` §3) places that piece by its centre, not its north-west corner: the piece's origin is its
module's centre, at the doc's numbers. Every other room keeps the north-west corner. PR #1370's estate (`levels/estate/`)
is the first such map. This records what `levels/CLAUDE.md` and that PR already do; no other rule here changes.
Approved by the engineer: https://github.com/xperiaroco2/prime-game/issues/1039#issuecomment-6495878671

### A room declares itself
- Its size on its root: `metadata/size_m = Vector2i(<width>, <depth>)` in whole metres.
- Its door openings: `Marker3D` children of a `Doors` node, one per opening, at the opening's centre on the floor.
- Its task stations: instanced station scenes, never copied geometry.
- Its spawn, package, circle, respawn and knife markers: the existing `spawn_<tag>` groups (`levels/CLAUDE.md`).

Replacing a room is replacing one instance in the map.

### Looks and collision
- Collision as `levels/CLAUDE.md` already says: `StaticBody3D` with `CollisionShape3D` on layer 1, in each kit piece
  and each station; meshes (and CSG, if used) for looks only.
- Until the art kit lands, a piece is greyboxed with box meshes (`MeshInstance3D` with a `BoxMesh`, as
  `levels/greybox/` does; CSG where a shape needs it) and the shared greybox materials of `levels/kit/`, one per
  role: walls, a floor per zone, stairs and door frames, with a floating `Label3D` name per room (#658: a single
  grey hid the doors and the structure in the first playtest). The kit's GLBs then replace the greybox inside the
  same piece, and the map does not change.

### Station scenes
A station a player uses where it stands (the [Generator ADR](2026-10-10-generator-task.md)'s GE11: the switch and the
generator, #799; the photo, cooking and car repair stations follow) is a scene that is the device: the client finds
it by its use spot's position and drives its named nodes; no script in `levels/`. Each station scene:
- lives in `levels/stations/<device>.tscn`, its root a plain `Node3D` at the device's **floor point**, its front
  facing local **+Z** (the art props' convention);
- shows the device as `Body`: the art's kit wrapper (`levels/kit/house_props/<stem>.tscn`) with
  `[editable path="Body"]` (an override inside an instance needs it, or `normalize` drops it), its mesh in the
  room's material, the art's own state meshes (`*_off`, `*_on`) hidden and the wrapper's collider bodies at
  `collision_layer = 0`; with no art prop, greybox boxes in `levels/kit/` materials;
- collides through its own `Collision`: one `StaticBody3D` on layer 1 with primitive `CollisionShape3D`s
  (`BoxShape3D` and the like) in the scene, never a GLB's hull, so it stays the same when the art re-imports and
  in CI's stand-ins (no LFS content there);
- holds one `UseSpot` `Marker3D` in its `spawn_<tag>` group on the floor (y = 0) in front of the device (x = 0,
  z > 0), where a standing player clears the device's collision: the host snaps it and places the station there;
- names the parts the client drives, outside `Body`, each with its default `visible` (the client sets only
  `visible`; a moving part is its own `MeshInstance3D`): the switch's `Active/Off` (shown), `Active/On` and
  `Fixed` (hidden), the generator's `Button`, `Bars/Bar1` to `Bar4` and `Glow` (hidden); their looks in
  `levels/kit/greybox_station_*.tres` materials until the art track draws them (placeholders, "not a decision").

A room places the scene under `Stations/<Name>` in place of the old marker, turned so that the use spot lands on
its design doc's point (house-map §6), and drops the art's own copy of the device from `Dressing` (the prop with
`metadata/station = "<Name>"`), or two devices stand there. `tests/integration/levels/stations/station_scenes_test.gd`
checks each scene (a new one joins its `SCENES`), `tests/integration/levels/house_stations_test.gd` the House's
placements.

The photo task's stations (#783, proposed with them) add three cases. A device used from behind (the camera on its
tripod, whose shooter stands behind the lens) turns its `Body` inside the scene so that +Z stays the user's side: the
lens looks along -Z and the use spot still lies at z > 0. A station with no device (the photo spot, a display kind
the camera frames) is only its look on the floor and its marker at the root: no `Body`, no `Collision`. A device on a
stand (the printer) may hold the art's stand pieces beside its `Body` (the desk, the computer), their colliders off
too, and every marker its device needs besides the use spot (the printer's tray).

The car repair's stations (#809, proposed with them; the [car repair ADR](2026-10-10-car-repair-task.md)'s RE16) add
three more. A device with several use spots (the parts shelf, one bin per part kind) gives each its own child
(`Bin<n>`) with a `UseSpot` in its own tag's group. A frame on a room's wall (the part picture) has no `Collision`:
the wall stops a player. And a device that moves (the car): its moving part is an `AnimatableBody3D` (`Lift`) on the
client-only layer 4 (`movers`), carrying the art bodies that move with it, with only the static frame in `Collision`
on layer 1; its use spot lies under the device (RE16's exception), so the frame stays clear of it and the host snaps
it to the room's floor.

The cooking task's stations (#774, proposed with them) add three more. A row of like devices used one by one (the
greenhouse's five herb beds) is one scene: its root at the middle device's floor point, one node per device
(`Bed1` to `Bed5`), each holding its own `Body`, its driven nodes (`Plant`) and its `UseSpot` in front of it, all
those spots in the one group; one `Collision` body holds a shape per device. A station whose items are picked up
(the bun shelf, the freezer: the cooking boxes are items on the ground, the cooking ADR's CE1) has no `UseSpot`: its
markers are the items' spawn points (`Boxes/*`, one group per box kind), on the floor in front of the device. A
device a room uses more than once with a number (the kitchen's places) keeps its number on a hidden `Label3D`
(`Number`) the room sets per instance (`[editable path]` and a `text` override).

### A check
A test reads the map scene and its design doc's room table and fails when a room's position or size differs, so the
doc and the map never disagree silently. It comes with the first map scene, in that task's PR.

## Consequences
- The skill `new-level-piece` stops refusing for lack of conventions; it builds pieces by this ADR.
- The art kit (#74) and the game's pieces meet at the seams by construction.
- A playtest change to the layout is a change of numbers in the design doc and in the map, checked against each other.
- Task stations are separate from rooms, so the five task chains' mechanics can arrive one by one.

## Not decided here
- The House map's own scenes (the next level task).
- The task chains' mechanics (one `mechanic` issue each, through the skill `new-mechanic`).
- The final look and its light (the art track).
