# levels/: maps from reusable pieces (the content area)

Loaded when a file in `levels/` is read. This folder belongs to the **engineer** (#518, root `CLAUDE.md`
Ownership); the optional designer may contribute, and his PRs go to the engineer. Maps are assembled from small,
reusable sub-scenes: rooms, props, interactables and task stations. Read the root `CLAUDE.md`, `docs/GDD.md` and
the content-API section of `docs/ARCHITECTURE.md` (which interactables and stations exist) first.

## Pieces, not big scenes
- One reusable piece per scene file. A map instances pieces; it does not copy them.
- Small files mean two people rarely touch the same scene. Scenes are single-owner: never edit a scene that someone
  else has an open PR on.
- Godot file and folder names are `snake_case` (`storage_room.tscn`); node names are `PascalCase`.
- **Conventions** ([ADR](../docs/decisions/2026-10-09-level-piece-conventions.md), #607):
  - folders: `<map>/<map>.tscn` (only places pieces), `<map>/rooms/`, `stations/` (reusable on any map),
    `props/`, `kit/` (wrappers of the art kit's GLBs); `lobby/` and `greybox/` stay;
  - one grid with the art kit: whole metres, 2 m and 1 m wall modules, 3.2 m floor to floor (Y -3.2, 0, 3.2; an
    attic at 6.4 with 2.2 m knee walls), doors 1.4 x 2.15 m;
  - a room's origin is its north-west floor corner; the map places it at its design doc's (x, level height, y),
    plan x = X, plan y = Z, no rotation;
  - a room declares `metadata/size_m = Vector2i(w, d)`, its door openings as `Marker3D` children of `Doors`, its
    stations as instanced station scenes; a test checks the map against the design doc's room table.
- Greybox with box meshes (CSG where a shape needs it) and one shared neutral material until the art kit lands;
  the kit's GLBs then replace the greybox inside the same piece. The look comes from the art track (xperiaroco2/prime-game-art).
- **Collision** ([D2](../docs/decisions/2026-09-30-wire-format-and-host-session.md)): `StaticBody3D` nodes with
  `CollisionShape3D` children on layer 1; CSG and `GridMap` for looks only. The host refuses a level with CSG or
  `GridMap` collision, a `CollisionPolygon3D`, a `RigidBody3D` or `CharacterBody3D` on layer 1, or no layer-1
  body at all (#112).
- **Spawn points** (`docs/ARCHITECTURE.md` §9.6, provisional until M4): a `Marker3D` in exactly one persistent
  group `spawn_<tag>` (Groups dock: `spawn_lobby_player`, `spawn_round_player`, `spawn_package`, `spawn_knife`,
  `spawn_circle`, `spawn_zone`). A marker in two such groups is a load error. The host reads them in scene-tree
  order.
- **Task stations** (every station kind's marker: Delivery's `circle`, the zone task's `zone`, #649; the [zone task
  ADR](../docs/decisions/2026-10-09-m7-zone-task.md) ZD10, ZE2, ZE9): the host snaps the marker down to the floor
  below it when read, and the station's cylinder (the zone: 1.5 m radius, 2.5 m high; the circle: 1 m, 2 m) stands
  on that floor; one with no floor below is a load error. So every station marker:
  - sits on **flat floor**: a player counts only with its feet inside the cylinder, so a zone on a slope or a step
    never counts the player whose feet stand below the snapped marker;
  - keeps its whole cylinder **clear of walls and ceilings**: the host tests positions only, with no line of
    sight, so a cylinder through a thin wall counts a player behind it, and one taller than its storey counts a
    player upstairs. A `shot` of the station's room in the PR checks it; on House, `house_markers_test.gd` also
    tests each zone's cylinder against the host's collision world (no wall, ceiling or furniture inside, flat floor
    under it, #651);
  - keeps **ZE9's distances**, which `tests/unit/content/zone_content_test.gd` checks on every map of the base
    mode: any two `zone` markers at least twice the zone's radius apart (3 m); each `zone` marker at least its
    radius plus 1 m (2.5 m) from every `round_player` and `respawn` marker, and at least its radius plus the
    circle's (2.5 m) from every `circle` marker. Markers more than a zone's height apart in y (another storey)
    are not compared (the check is `tests/fixtures/tasks/fixture_zone_spacing.gd`, which House's marker test runs too).
- Every map of the base mode needs `zone` markers (as many as the `zones` setting's maximum), or its lobby cannot
  start until the host bans the zone type and sets `tasks` to 1. The greybox's four along z = 7 are placeholders,
  "not a decision" (#649); House's three (the generator hall, the garden, the landing) are #651's placeholders until
  the engineer moves them.
- **Respawn points** ([vision revision 1](../docs/decisions/2026-10-01-vision-revision-1.md)): markers in
  `spawn_respawn`, at least one per round map: the layout check and the lobby's fit check demand them (M4-3), and
  each needs 1 m free around it (a marker with a player that near is drawn only when none is free).
- **Hiding spots** (the same revision): a dissident may hide a package anywhere a put-down allows, so every floor a
  put-down can reach must also be reachable for a pickup (the pick-up reach and line of sight, from somewhere a
  player can stand). No gap, ledge or thin wall may keep a package for good; a playtest checks it.
- The MVP's lobby and map live at `lobby/lobby.tscn` and `greybox/greybox.tscn`, the paths the base mode names:
  flat, marker-only scenes from M2 (built by the engineer's agent in #66), dressed in M4.

## The designer's agent never edits engine code
- Interactables and task stations come from the engine. If a level needs one that does not exist, open an
  `engine-request` issue with a precise spec (see `content/CLAUDE.md` for what the spec says) and continue with the
  rest of the level.
- The designer's agent edits only the content area and the shared logs, as listed in `content/CLAUDE.md`.

## Working next to the Godot editor
A human may have this project open in the Godot editor while the agent works. The editor does not merge
changes: whichever copy is saved last wins. Remind the human of the convention:
1. Before asking the agent for anything: Scene → **Save All Scenes** («Зберегти всі сцени», Ctrl+Shift+Alt+S).
2. When Godot says files changed on disk («Файли були змінені за межами Godot»), choose **Reload from disk**, which
   the Ukrainian editor labels **«Джерело отримання»**. Never click **«Ігнорувати зовнішні зміни»**: the editor would
   later save its old copy over the agent's work.
3. Nobody edits a scene by hand while the agent is working on it.

## Assets
- Binary assets (models, textures, audio, fonts) go through Git LFS automatically (`.gitattributes`).
- Every third-party asset gets a credits file in `docs/credits/<asset>.md` (source, author, license) in the same PR.

## Checking the work
- Hand-written `.tscn` files follow `.claude/rules/godot-resources.md`; `verify` must be green.
- Headless runs cannot see a level. Each new or changed piece gets a `shot` screenshot (once `shot` exists) in the
  PR, and the engineer checks the look and feel in a playtest.
