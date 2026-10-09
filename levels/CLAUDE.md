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
- The folder layout inside `levels/` and the piece conventions are decided by the engineer when level work starts
  (M4); skill `new-level-piece` then encodes them.
- Greybox with CSG and CC0 low-poly packs. Stylized low-poly, no texture-heavy art.
- **Collision** ([D2](../docs/decisions/2026-09-30-wire-format-and-host-session.md)): `StaticBody3D` nodes with
  `CollisionShape3D` children on layer 1; CSG and `GridMap` for looks only. The host refuses a level with CSG or
  `GridMap` collision, a `CollisionPolygon3D`, a `RigidBody3D` or `CharacterBody3D` on layer 1, or no layer-1
  body at all (#112).
- **Spawn points** (`docs/ARCHITECTURE.md` §9.6, provisional until M4): a `Marker3D` in exactly one persistent
  group `spawn_<tag>` (Groups dock: `spawn_lobby_player`, `spawn_round_player`, `spawn_package`, `spawn_knife`,
  `spawn_circle`). A marker in two such groups is a load error. The host reads them in scene-tree order. A
  `circle` marker is snapped down to the floor below it when read (its cylinder starts there); one with no floor
  below is a load error.
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
- Binary assets (models, textures, audio, fonts) go through Git LFS automatically (`.gitattributes`). They land
  in `assets/<kind>/<id>/` with their committed `.import` file, never under `levels/`; a level instances them from
  there (`docs/ARCHITECTURE.md` §11).
- Every third-party asset gets a credits file in `docs/credits/<asset>.md` (source, author, license) in the same PR.

## Checking the work
- Hand-written `.tscn` files follow `.claude/rules/godot-resources.md`; `verify` must be green.
- Headless runs cannot see a level. Each new or changed piece gets a `shot` screenshot (once `shot` exists) in the
  PR, and the engineer checks the look and feel in a playtest.
