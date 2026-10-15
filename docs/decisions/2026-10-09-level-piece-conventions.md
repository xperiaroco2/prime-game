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
