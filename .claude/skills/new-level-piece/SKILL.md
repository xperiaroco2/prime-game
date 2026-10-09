---
name: new-level-piece
description: Build a reusable level piece (a room, prop, interactable or task-station sub-scene in levels/) by the agreed level conventions, normalize it and show a shot screenshot. Use when the engineer, or the optional designer, asks for a room, a prop, an interactable or a task station.
allowed-tools:
  - Bash(tools/run.sh *)
  - PowerShell(tools\run.cmd *)
  - Bash(gh pr list *)
  - PowerShell(gh pr list *)
  - Bash(gh issue create *)
  - PowerShell(gh issue create *)
---

# New level piece (docs/AGENT_WORKFLOW.md §6 and §11; the engineer's content area)

Read `levels/CLAUDE.md` and `.claude/rules/godot-resources.md` first. The engineer owns `levels/` (#518); the
optional designer may ask too, and then his PR goes to the engineer. "The human" below is whoever asked. Talk in
the human's language.

1. **Conventions come first:** `docs/decisions/2026-10-09-level-piece-conventions.md` (#607), summarised in
   `levels/CLAUDE.md`. Put the piece in its folder (`<map>/rooms/`, `stations/`, `props/`, `kit/`); keep the grid
   (whole metres, 3.2 m floor to floor, 1.4 x 2.15 m doors); a room's origin is its north-west floor corner, with
   `metadata/size_m` and a `Doors` node of `Marker3D` openings; a map takes each room's position from its design
   doc (`docs/design/`). A room the design doc does not list, or a size it does not give, is the engineer's to
   decide: stop and ask, never invent one.
2. **A task.** The piece has an issue (`start-task` first). Scenes are single-owner:
   `gh pr list --state open --json number,author,files`; if another human's open PR changes this scene, stop.
3. **Save first.** Before writing, ask the human to Save All Scenes (Ctrl+Shift+Alt+S, «Зберегти всі сцени») and
   not to edit by hand while you work. When Godot then reports files changed on disk: «Джерело отримання», never
   «Ігнорувати зовнішні зміни».
4. **Engine parts.** Interactables and task stations come from the engine (content-API section of
   `docs/ARCHITECTURE.md`). One that does not exist: an `engine-request` issue with the spec from `content/CLAUDE.md`
   (after the human's OK on its text), then continue with a greybox stand-in.
5. **Write the scene by hand:** one piece per `snake_case.tscn`, `PascalCase` nodes, other pieces instanced rather
   than copied, box-mesh greybox with the shared material. No `uid=` anywhere. Property names from the API dump
   (`tools/out/godot-api/4.7.2/extension_api.json`). A `Transform3D(...)` in a `.tscn` lists the basis row by row.
6. **Normalize and check:** `tools\run.cmd normalize <file>`; if it reports a dropped property, fix that line (a typo,
   or a default value to remove) and run it again. Then `tools\run.cmd check`.
7. **Screenshot:** `tools\run.cmd shot <file>`. A piece without its own camera gets one that frames all of it. Read
   the PNG yourself and fix what looks wrong, then send it to the human and ask whether it looks right. `gh`
   cannot upload images: the human drags the PNG into the PR description.
8. **Assets:** third-party models, textures or sounds go through Git LFS and need `docs/credits/<asset>.md` (source,
   author, license) in the same PR.
9. **Finish** with `finish-task`; the engineer judges the piece in a playtest.
