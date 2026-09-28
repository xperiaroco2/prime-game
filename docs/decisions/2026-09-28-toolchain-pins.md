# Toolchain pins and how the runner judges results

- **Status:** Accepted
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase B, M0 stage 1; delegated to the agent: "do what is best")

## Context
KICKOFF §2 requires the exact Godot version to be pinned in an ADR, in CI and in the task runner, with a fast, clear
failure on a mismatch. Several tools report success when something is broken: `godot --import` exits 0 on script
errors, `load()` returns a script that does not compile, and the GdUnit4 console can print PASSED for a failing suite
(GdUnit4 #1330). Research: `docs/history/2026-09-28-phase-a/research/godot_toolchain.md`.

## Decision
**Pins.** They live in one place, `tools/runner/pins.py`. CI reads them with `tools/run.sh pins --get <name>`.

| Tool | Pin | Note |
|---|---|---|
| Godot | 4.7.2 official stable, standard build (`4.7.2.stable.official*`) | Every command that runs Godot checks the version first and stops with a download link |
| GdUnit4 | 6.2.1, committed in `addons/gdUnit4` | Its README lists Godot up to 4.7.1; runs on 4.7.2 verified locally |
| gdtoolkit | 4.5.0 | No upstream commits since 2025-10; Godot's parser in `check` stays the authority |
| Python | 3.11 or newer | Runner uses the standard library only |
| gh | 2.97 or newer | Needed for the board commands |
| Claude Code on PATH | 2.1.281 or newer | `doctor` fails on an older `claude` on PATH |

**How results are judged.**
- `check` fails on: a warnings policy below Error for `untyped_declaration`, `unsafe_property_access`,
  `unsafe_method_access` or `unsafe_call_argument`; UID warnings printed by the import; files the import creates or
  changes (typically a `.uid` sidecar that was not committed); the static UID lint (duplicates, a missing sidecar, an
  `ext_resource` uid that belongs to a different file than its `path=`); and any engine error while loading every
  `.gd`, `.tscn` and `.tres` outside `addons/`. Warn-level GDScript warnings are printed but do not fail. The loader
  runs with `-d --ignore-error-breaks`, never a bare `-d`, which hangs.
- `test` trusts only the GdUnit4 exit code and `results.xml`. Exit 101 (**orphan nodes**) fails the build, and so
  does a run with zero tests.
- `verify` runs doctor (quick), lint, check, test and the runner's own tests, and fails if the run left files in the
  working tree.
- Every Godot call has a hard timeout and kills the whole process tree (the Windows console exe starts the engine as
  a child process).

**Changing a pin** is a PR that edits `tools/runner/pins.py` (plus the addon for GdUnit4), updates this ADR, and
shows `verify` green locally and in CI.

## Alternatives
- Orphans as a warning only: leaks in `core/` tests would pile up unseen.
- Binary warnings policy (every warning Error or Ignore): the editor would lose gentle hints for the designer.
- Per-file `--check-only` for `check`: 0.3 s per file, and it cannot resolve autoload names.

## Consequences
- CI checks out without LFS content (engineer's decision). Once the first LFS asset outside `addons/` lands, the CI
  import would see LFS pointer files instead of images or audio. Decide before that PR: enable LFS in CI (uses the LFS
  bandwidth quota) or teach `check` to skip pointer files in CI.
- The editor and a headless runner can share one checkout; see
  `2026-09-28-godot-editor-save-first-convention.md` for what was verified.
