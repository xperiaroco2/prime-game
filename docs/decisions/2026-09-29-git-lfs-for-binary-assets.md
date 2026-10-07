# Binary assets through Git LFS, addons outside it, CI without LFS content

- **Status:** Accepted
- **Date:** 2026-09-29 (decided during M0 stages 1–2; recorded at the end of M0)
- **Deciders:** the engineer

## Context
KICKOFF §2 routes binary assets (`*.glb`, `*.png`, `*.wav`, `*.ogg` and similar) through Git LFS and forces LF for
text files. GdUnit4 in `addons/` ships its own PNG icons. Fetching LFS content in CI counts against the account's LFS
bandwidth quota, and a checkout without it leaves pointer files where images and sounds should be.

## Decision
- `.gitattributes` forces LF for text formats (CRLF only for `.cmd`/`.bat`) and routes the binary formats through LFS.
- `addons/**` is excluded from LFS (`!filter`), so CI can load third-party addons without LFS content.
- CI checks out with `lfs: false`.
- Every LFS asset outside `addons/` has a `docs/credits/<asset>.md` entry; `check` enforces it, and
  `tools\run.cmd credits` generates `CREDITS.md` (AGENT_WORKFLOW §10).
- The git hooks path set by `doctor` (`.claude/githooks`) runs `git lfs pre-push` itself (AGENT_WORKFLOW §8.3).

## Alternatives
- LFS in CI from the start: spends quota while there are no LFS assets.
- Addons inside LFS: CI would load pointer files instead of the addon's icons.

## Consequences
**Open, for the humans, before the first LFS asset outside `addons/` lands (closed by the amendment of
2026-10-07):** either enable LFS in CI (uses the LFS bandwidth quota) or teach `check` to skip LFS pointer files in
CI. Until then CI's import would see pointer files.

## Amendment 2026-10-07: `check` skips LFS pointer files in CI (option 2)
Approved by the engineer: https://github.com/xperiaroco2/prime-game/issues/170#issuecomment-6035817375

The open question above is closed with its second option, built in #515: CI keeps `lfs: false` and spends no LFS
bandwidth on `verify`.
- **Detected the way the runner detects CI** (`common.IS_CI`, the `CI` variable; a Claude Code cloud session,
  `common.IS_CLOUD`, too, another checkout that may lack LFS content): a file `.gitattributes` routes through LFS
  (outside `addons/`) whose first line is the spec's `version https://git-lfs.github.com/spec/v1` and which is under
  1024 bytes is a pointer file (`tools/runner/lfs.py`). Locally, with LFS content, nothing is detected and nothing
  changes; a PC whose checkout has pointer files gets a `check` warning that names them and `git lfs pull`.
- **The import never sees a pointer file.** Probed with Godot 4.7.2: `--import` of a pointer `.png`, `.wav` or
  `.glb` still exits 0, but prints `ERROR: Error importing 'res://….png'` (`Not a PNG file`, `Not a WAV file`, a
  glTF parse error) and rewrites the committed `.import` file (`valid=false`, no `path=`), so `check`'s "the import
  left the working tree unchanged" would fail. Godot has no per-file ignore (a `.gdignore` hides a whole folder), and
  the Import dock's "Skip File (not exported)" (`importer="skip"`,
  [the import process](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/import_process.html)) is a
  committed setting that would also skip the file where the content exists. So for every import it runs
  (`check.run_import`) the runner moves each pointer file into `tools/out/lfs-aside/` (a `.gdignore` in it) and puts
  it back afterwards, even when the import fails; CI's checkout is the only one it touches. No Godot setting changes.
- **A stand-in takes its place where the type has one** (the review of #515): a 4x4 grey PNG, JPEG, WebP, BMP or
  TGA, a silent WAV, an empty glTF or GLB scene, a one-triangle OBJ (`lfs.STAND_INS`), under its committed `.import`
  file. Godot writes the imported file that `.import` names, with its uid and params, so every scene, preload and
  `class_name` that uses the asset loads, in `check` and in the later `test`, `bots` and `game` steps (they find it
  in `.godot/imported/`). The pointer and the committed `.import` go back as they were (bytes and times, so the
  import stays current), and the `.import` a new asset's import wrote is removed again. A type without a stand-in
  (a font, Ogg or MP3 audio, a video, FBX, `.blend`) goes aside with its `.import` file. Hiding every pointer was
  the first build: a class that preloads a texture then broke every script that uses the class, with an error that
  names neither file.
- **The project check drops what a pointer file causes**, in one summary line (`skip  N LFS pointer files skipped
  …`): a `CHECK` error or warning line that names a pointer file or the imported file its committed `.import` names
  (`Failed loading resource`, `referenced non-existent resource`, `invalid UID … using text path instead`,
  `Unable to open file: res://.godot/imported/….ctex`), and the lines that name a script that failed to load
  because of one (a `Could not preload` or `Parse Error` line at a `.gd` location, then `Failed to load script`).
  Godot 4.7.2 still loads a scene whose texture is missing, with the property left null, so a scene's other lines
  are kept. A pointer file with a stand-in causes no such lines.
- **Limits, for a type without a stand-in only, left to the local `check`, which has the content:** in CI a script
  that preloads one is not reported; a script that reads it through another script's `class_name` fails there with
  an error that names neither file (`Could not resolve external class member`), which stays red; the `test`, `bots`
  and `game` steps load a scene that uses one with the resource missing and print Godot's errors for it. A stand-in
  for that type is the fix when the first such asset lands. A glTF stand-in is an empty scene: an inherited scene
  that edits its nodes is not covered either.
- **Credits** (`docs/credits/<asset>.md` per LFS asset outside `addons/`) need only the path: the check covers
  pointer files in CI as before.
- **A build ships the real assets.** `tools/run.sh check --lfs-content` fails, naming each one, on any pointer
  file, with no Godot. `release.yml` keeps `lfs: true` and runs that step before its export. It exists only on
  `release/m6` so far, and #515 changed `main`, so the step is M6's to add: a `Check LFS content` step
  (`tools/run.sh check --lfs-content`) right after its checkout, in the first M6 change to `release.yml` after
  `main` reaches `release/m6`. Until then `release/m6`'s `export` already fails loudly on a pointer file in the tree
  it exports (`export.lfs_pointers`); the earlier step names every pointer file before Godot starts.
