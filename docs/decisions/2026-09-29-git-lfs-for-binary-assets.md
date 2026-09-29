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
**Open, for the humans, before the first LFS asset outside `addons/` lands:** either enable LFS in CI (uses the LFS
bandwidth quota) or teach `check` to skip LFS pointer files in CI. Until then CI's import would see pointer files.
