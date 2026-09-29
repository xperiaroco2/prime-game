---
paths:
  - "**/*.tscn"
  - "**/*.tres"
  - "**/*.uid"
  - "**/*.import"
  - "project.godot"
---

# Scenes, resources and Godot metadata

## Writing `.tscn` and `.tres` by hand
- Write readable text in format 3: `[gd_scene format=3]` or `[gd_resource type="..." format=3]`, then
  `[ext_resource]`, `[sub_resource]`, `[node]` or `[resource]` sections. Look at an existing file of the same kind
  first.
- **Never invent or copy a uid.** Leave `uid=` out of the header and of `[ext_resource]`; the path is enough.
  A copied uid makes two files claim one identity. Verified on 4.7.2: files without `uid=` load, pass `check`, and
  the headless import leaves them untouched.
- `[ext_resource]` needs `type`, `path="res://..."` and an `id` that is unique in the file. If you do write a uid,
  it must be the one in the target's own `.uid` sidecar or header: `check` fails when a uid resolves to a different
  file than `path=`.
- Property names and enum values come from the API dump (`tools/out/godot-api/4.7.2/extension_api.json`), not memory.
- `Transform3D(...)` lists the basis **row by row** (x.x, y.x, z.x, x.y, …), then the origin: a rotation written as
  columns turns the other way.
- Run `tools\run.cmd normalize <files>` on new or hand-edited files: it re-saves them in editor context, so the
  editor will not rewrite them later. If it reports a dropped property, that line is a typo or a default value.

## Sidecars
- Commit every `.uid` and `.import` file with the file it belongs to. Never copy one to a new file.
- `check` fails if the import creates or changes any file: that means a sidecar is missing from the commit, or
  something was committed that the editor would rewrite.

## Ownership and the editor
- Scenes are single-owner. Never edit a scene that someone else has an open PR on. Levels are built from small
  sub-scenes so that this rarely matters.
- A human may have the editor open. Remind them to Save All Scenes before you edit, and to choose «Джерело
  отримання» (Reload from disk) when Godot reports files changed outside it.
- `project.godot` is engineer-owned: change it only for a reason stated in the PR, and never lower the warnings
  policy under `[debug]`.

## Files
- UTF-8 with LF line endings (`.gitattributes`); binary assets go through Git LFS automatically.
- Third-party assets need `docs/credits/<asset>.md` in the same PR, then `tools\run.cmd credits` (`check` fails on
  an LFS asset without an entry and on a stale `CREDITS.md`).
