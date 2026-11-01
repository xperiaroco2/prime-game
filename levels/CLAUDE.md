# levels/: maps from reusable pieces (the content area)

This folder belongs to the **engineer** (#518, root `CLAUDE.md` Ownership); the optional designer may contribute,
and his PRs go to the engineer. Maps are assembled from small, reusable sub-scenes: rooms, props, interactables and
task stations. Read `docs/GDD.md` and `docs/ARCHITECTURE.md`'s content API (its interactables, stations) first.

## Pieces, not big scenes
- One reusable piece per scene file. A map instances pieces; it does not copy them.
- Small files mean two people rarely touch the same scene. Scenes are single-owner: never edit one in another's open PR.
- Godot file and folder names are `snake_case` (`storage_room.tscn`); node names are `PascalCase`.
- **Conventions** ([ADR](../docs/decisions/2026-10-09-level-piece-conventions.md), #607):
  - folders: `<map>/<map>.tscn` (only places pieces), `<map>/rooms/`, `stations/` (reusable on any map), `props/`, `kit/` (art GLB wrappers in
    `kit/<pack>/`, greybox role materials; the estate greybox (#1158) uses the `greybox_floor_*` and `greybox_stairs`); `lobby/` and `greybox/` stay;
  - one grid with the art kit: whole metres, 2 m and 1 m wall modules, 3.2 m floor to floor (Y -3.2, 0, 3.2; an
    attic at 6.4 with 2.2 m knee walls), doors 1.4 x 2.15 m;
  - a room's origin is its north-west floor corner (an estate lot's: its module's centre, the doc's numbers, #1158; see the [ADR's 2026-10-29 amendment](../docs/decisions/2026-10-09-level-piece-conventions.md));
    the map places it at its design doc's (x, level height, y), plan x = X, plan y = Z, no rotation;
  - a room declares `metadata/size_m = Vector2i(w, d)`, its record (#306: `room_id`, `name_key`), its door
    openings as `Marker3D` under `Doors`, its stations as sub-scenes; a test checks the map against the design doc.
- House rooms are the art's (P1-P7, #523, #1052): its `Shell` (kit wrappers, see Assets), `Dressing`, `Detail`
  inside the game's piece (origin, `size_m`, record, `Doors`, `Stations`, `Markers`); the plot is `house/outdoor.tscn`.
  No door opens in M7 (E4): a kit door or gate on a walk sets `collision_layer = 0` on its wrapper's collider bodies.
  An override inside an instance needs its `[editable path]`, or a re-save drops it: `colliders` adds them (#1056).
- **Collision** ([D2](../docs/decisions/2026-09-30-wire-format-and-host-session.md)): `StaticBody3D` nodes with
  `CollisionShape3D` children on layer 1; CSG and `GridMap` for looks only. The host refuses a level with CSG or `GridMap`
  collision, a `CollisionPolygon3D`, a `RigidBody3D` or `CharacterBody3D` on layer 1, or no layer-1 body (#112). A look a player
  can hide behind (partition, tarp, shelf) needs a layer-1 collider over it, or name plates show through (`docs/ARCHITECTURE.md`
  §4.7.29, #257). Voice muffling is a client ray on layer 1 (`client/world/muffle.gd`): openings and covers decide it.
- **Spawn points** (`docs/ARCHITECTURE.md` §9.6): a `Marker3D` in exactly one persistent group `spawn_<tag>` (Groups
  dock: `spawn_lobby_player`, `spawn_tap`, `spawn_booth`, `spawn_round_player`, `spawn_package`, `spawn_knife`, `spawn_circle` (greybox, estate),
  `spawn_zone`; House only, provisional (DE10, #826): `spawn_drop_dining_table`, `spawn_drop_terrace_table`,
  `spawn_drop_garden`, `spawn_drop_workbench`, one each at its furniture (#831); House only, "not a decision" (#799,
  #783, #809, #774): use spots `spawn_switch`, `spawn_generator`, `spawn_camera`, `spawn_photo_spot`,
  `spawn_film_box`, `spawn_printer`, `spawn_photo_board`, `spawn_car`, `spawn_car_end`, `spawn_lift_panel`,
  `spawn_part_bin_<n>`, `spawn_part_picture`, `spawn_order_board`, `spawn_herb_board`, `spawn_grill`, `spawn_place`,
  `spawn_herb_bed`; `spawn_film`, `spawn_photo`; the cooking boxes' `spawn_box_bun_white`/`_sesame`/`_dark`,
  `spawn_box_patty_light`/`_red`/`_deep_red`; the estate's ship engine: §9.5.27; its toggles: §9.6). A marker in two is a load error.
  The host reads them in scene-tree order. Bot scenarios snap station markers only on the levels they play (the lobby,
  the first map, any a scenario names: `tests/fixtures/scenario_levels.gd`, ARCHITECTURE §9.7), on a flat fake (floor
  y = 0): there no station marker (`circle` or `zone`, #681) below it and no two of different tags at one (x, z).
  Other maps (House, estate) are read as placed (GE12, #798): a station marker may stand off y = 0 there.
- **Task stations** (every station kind's marker: Delivery's `circle`, the zone task's `zone`, #649; the [zone task
  ADR](../docs/decisions/2026-10-09-m7-zone-task.md) ZD10, ZE2, ZE9): the host snaps the marker down to the floor
  below it when read, and the station's cylinder (the zone: 1.5 m radius, 2.5 m high; the circle: 1 m, 2 m) stands
  on that floor; one with no floor below is a load error. So every station marker:
  - sits on **flat floor**: a player counts only with its feet inside the cylinder, so a zone on a slope or a step
    never counts the player whose feet stand below the snapped marker;
  - keeps its whole cylinder **clear of walls and ceilings**: the host tests positions only, with no line of
    sight, so a cylinder through a thin wall counts a player behind it, and one taller than its storey counts a player
    upstairs. A `shot` of the station's room in the PR checks it; on House, `house_markers_test.gd` also tests each
    zone's cylinder against the host's collision world (no wall, ceiling or furniture in it, a flat floor, #651);
  - keeps **ZE9's distances**, which `tests/unit/content/zone_content_test.gd` checks on every map of the base
    mode, read in the host's collision world (#681): any two `zone` markers at least twice the zone's radius apart (3 m); each `zone` marker at least
    its radius plus 1 m (2.5 m) from every `round_player` and `respawn` marker, and at least its radius plus the
    circle's (2.5 m) from every `circle` marker. Markers more than a zone's height apart in y (another storey)
    are not compared (the check is `tests/fixtures/tasks/fixture_zone_spacing.gd`, which House's marker test runs too).
- `zone` markers (as many as the `zones` setting's maximum) only where the zone task plays: its `maps` list the House
  alone (GD13 (b), #804), the greybox (a test bench, #767) has none; House's three (the yard, the garden, the
  landing) are #651's placeholders until the engineer moves them.
- **Station scenes** (#799, #783, #809, #774; RE16: the car's use spot under its `Lift`, layer 4 `movers`): read the
  [level piece ADR](../docs/decisions/2026-10-09-level-piece-conventions.md)'s "Station scenes" first: root at the
  device's floor point, front +Z; `Body` the art's kit wrapper (editable, its colliders on layer 0); own primitive
  `Collision` on layer 1; one `UseSpot` on the floor in front; driven nodes by `visible`; the room drops the art's copy.
  The car breaks the layer-1 rule: only its layer-4 `Lift` collides: the living hit it on `movers`, plates pass (RE8).
- **World toggles** (ARCHITECTURE §4.5.9's level contract; the `new-level-piece` skill, step 4): a `spawn_<tag>`
  marker per station, read as placed (on its floor, in sight of both poses), parts on layer 1 in `toggle_<key>` with
  the int meta `toggle_index` (its marker's ordinal), a mover with a child `OnPose`, a passage an `_inside` kind.
- **Respawn points** ([vision revision 1](../docs/decisions/2026-10-01-vision-revision-1.md)): markers in
  `spawn_respawn`, at least one per round map: the layout check and the lobby's fit check demand them (M4-3), and
  each needs 1 m free around it (a marker with a player that near is drawn only when none is free).
- **Hiding spots** (the same revision): a dissident may hide a package anywhere a put-down allows, so every floor a
  put-down can reach must also be reachable for a pickup (the pick-up reach and line of sight, from somewhere a
  player can stand). No gap, ledge or thin wall may keep a package for good; a playtest checks it.
- **Thrown items and launched bodies** ([throwing ADR](../docs/decisions/2026-10-09-throwing-held-items.md) TD5 (a),
  #646; [knockdown ADR](../docs/decisions/2026-10-10-knockdown-reworked.md) KD12 (a), #850): each rests where its
  flight ends, so every surface a throw or a launch reaches (shelf, ledge, canopy, table, roof) lies within reach of
  a spot players walk to: the pick-up's 2 m, or the raise's (`TargetInReach`, `TargetInSight` from the crouched eye);
  no rule in `core/`. House's guards (ARCHITECTURE): `house_roof_throw_test.gd` (no throw rests on the roof; a perch
  near it gets columns in `house_throws.gd`) and `house_body_reach_test.gd` (every launch's rest within a raise of a
  spot walked to from the spawn; a new piece goes in its `WALKABLE` or `LOCKED`). Out of reach: the humans' to fix.
- The MVP's lobby and map: `lobby/lobby.tscn` (the art hall, #1451), `greybox/greybox.tscn` (the base mode's paths; M2's, dressed in M4).

## The designer's agent never edits engine code
- Interactables and task stations come from the engine. A level that needs a missing one opens an `engine-request`
  issue with a precise spec (`content/CLAUDE.md` says what it holds) and goes on with the rest of the level.
- The designer's agent edits only the content area and the shared logs, as listed in `content/CLAUDE.md`.

## Assets
- Binary assets (models, textures, audio, fonts) go through Git LFS automatically (`.gitattributes`). They land
  in `assets/<kind>/<id>/` with their committed `.import` file, never under `levels/`; a level instances them from
  there (`docs/ARCHITECTURE.md` §11); an art GLB only through its wrapper `kit/<pack>/<stem>.tscn` (#523, LFS ADR
  amendment 2026-10-14): the GLB is the look, its hint colliders the wrapper's bodies with text `.tres` shapes outside
  LFS (CI, bots). After an art import: `tools\run.cmd colliders` (`check` fails on a stale or bypassed wrapper).
- Every third-party asset gets a credits file in `docs/credits/<asset>.md` (source, author, license) in the same PR.

## Checking the work
- Hand-written `.tscn` files follow `.claude/rules/godot-resources.md`; `verify` must be green.
- Headless runs cannot see a level: a new or changed piece gets a `shot` in the PR; the engineer playtests the feel.
