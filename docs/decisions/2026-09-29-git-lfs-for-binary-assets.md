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
- **Detected the way the runner detects CI** (`common.IS_CI`, the `CI` variable): a file `.gitattributes` routes
  through LFS (outside `addons/`) whose first line is the spec's `version https://git-lfs.github.com/spec/v1` and
  which is under 1024 bytes is a pointer file (`tools/runner/lfs.py`). Locally, with LFS content, nothing is detected
  and nothing changes.
- **The import never sees a pointer file.** Probed with Godot 4.7.2: `--import` of a pointer `.png`, `.wav` or
  `.glb` still exits 0, but prints `ERROR: Error importing 'res://….png'` (`Not a PNG file`, `Not a WAV file`, a
  glTF parse error) and rewrites the committed `.import` file (`valid=false`, no `path=`), so `check`'s "the import
  left the working tree unchanged" would fail. Godot has no per-file ignore (a `.gdignore` hides a whole folder), and
  the Import dock's "Skip File (not exported)" (`importer="skip"`,
  [the import process](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/import_process.html)) is a
  committed setting that would also skip the file where the content exists. So the runner moves each pointer file
  and its `.import` file into `tools/out/lfs-aside/` (a `.gdignore` in it) for every import it runs
  (`check.run_import`) and puts them back afterwards, even when the import fails; CI's checkout is the only one it
  touches. No Godot setting changes.
- **The project check drops what a pointer file causes**, in one summary line (`skip  N LFS pointer files skipped
  …`): a `CHECK` error or warning line that names a pointer file or the imported file its committed `.import` names
  (`Failed loading resource`, `referenced non-existent resource`, `invalid UID … using text path instead`,
  `Unable to open file: res://.godot/imported/….ctex`), and the lines that name a file such a line was about (a
  script that preloads one and then fails to load). Godot 4.7.2 still loads a scene whose texture is missing, with
  the property left null.
- **Limits, left to the local `check`, which has the content:** in CI a problem in a file that uses an LFS asset is
  not reported, and a script that reads a preloaded asset through another script's `class_name` fails there with an
  error that names neither file (`Could not resolve external class member`), which stays red. The `test`, `bots`
  and `game` steps load scenes with the resource missing and print Godot's errors for it; a scene of theirs that
  uses an LFS asset is a follow-up when the first one lands.
- **Credits** (`docs/credits/<asset>.md` per LFS asset outside `addons/`) need only the path: the check covers
  pointer files in CI as before.
- **A build ships the real assets.** `tools/run.sh check --lfs-content` fails, naming each one, on any pointer
  file, with no Godot. `release.yml` keeps `lfs: true` and runs that step before its export. It exists only on
  `release/m6` so far, and #515 changed `main`, so the step is M6's to add: a `Check LFS content` step
  (`tools/run.sh check --lfs-content`) right after its checkout, in the first M6 change to `release.yml` after
  `main` reaches `release/m6`. Until then `release/m6`'s `export` already fails loudly on a pointer file in the tree
  it exports (`export.lfs_pointers`); the earlier step names every pointer file before Godot starts.
