---
name: design-manager
description: 'A pointer: the design track''s manager session runs in the private design repo D:\prime-game-design (xperiaroco2/prime-game-design), on that repo''s own design-manager skill. Use when a kickoff says "Track: design", names this skill, or a human says "дизайн-менеджер" or "design manager" in D:\prime-game: say where the session belongs and stop. Not for a mechanic''s issue filing alone (new-mechanic) or a stage of tasks (orchestrate-stage).'
---

# Design manager: a pointer (docs/MANAGERS.md; docs/AGENT_WORKFLOW.md §7.3)

The design track's manager works in the private repo **xperiaroco2/prime-game-design**, checkout
`D:\prime-game-design`, on that repo's skill `.claude/skills/design-manager/SKILL.md` and its root `CLAUDE.md`: its
research, references, idea batches and brainstorms are committed there, straight to its `main`, with no checks (the
engineer's decisions, [#1095 comment 6200062331](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6200062331)
and [comment 6200108169](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6200108169); #1124).

If this session started here, in `D:\prime-game`, on a design kickoff: do nothing else. Your first message says, in
the engineer's language, that the design manager runs in the design repo, and its "For you:" item is: close this
session, open a new one in `D:\prime-game-design`, bypass permissions, effort high, and paste the same kickoff. Then
stop.

What stays in this repo:
- **The decided rules:** `docs/GDD.md` and `docs/design/` (with `docs/design/COMPASS.md`, the design track's lens,
  which the design repo reads by path). A decision lands through a short docs PR here, the design-only fast path of
  `.github/design-only-paths.txt` (#1123), merged on the engineer's word with "Approved by the engineer: <link>" in
  its body.
- **The manager rules** every track follows: `docs/MANAGERS.md` (its §8 pointer, design variant).
- **The budget:** the `design` line of `.claude/skills/orchestrate-stage/budget.md`; `tools\run.cmd metrics --track
  design` reads the design repo's sessions too.
- **The archive of 2026-10-15:** `docs/design/research/` and `docs/design/ideas/`.
