# No workflow framework: plain plan mode and our own skills

- **Status:** Accepted
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase A decision session)

## Context
KICKOFF Phase A asked for a choice between Superpowers, GSD and plain plan mode, installing at most one.

## Decision
Plain plan mode plus our own project skills (`start-task`, `finish-task`, `new-mechanic`, `new-level-piece`,
`log-intervention`, `onboard`). No plugin, and no adapted copies of Superpowers skills. Discipline (tests before
"done", run before claiming, fresh review) lives in root `CLAUDE.md` rules and the `finish-task` gates.

## Alternatives
- Adapted copies of Superpowers' TDD, debugging and verification skills (MIT): recommended by the proposal, not
  chosen.
- Superpowers plugin: commits specs and plans to `docs/superpowers/`, a competing source of truth; Windows friction.
- GSD Core: needs Node 24 or later; its `ROADMAP.md` and `STATE.md` would violate KICKOFF §5.

## Consequences
- Nothing to install, the lowest fixed token cost, and GitHub Issues stays the only moving state.
- An engineer-only Superpowers trial on the M1 spike remains an open question.
- Research: `docs/history/2026-09-28-phase-a/research/superpowers.md` and `gsd.md`.
