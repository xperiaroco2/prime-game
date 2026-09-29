# Instruction files: root invariants, nested area files, line budgets enforced by `lint`

- **Status:** Accepted
- **Date:** 2026-09-29 (decided 2026-09-28, Phase A items S1 and T5; built in M0 stages 3 and 6)
- **Deciders:** the engineer (Phase A decision session: a tier 2 default, no veto recorded)

## Context
Everything Claude Code loads at launch costs context in every session of both humans. Nested `CLAUDE.md` files load
only when a file in their folder is read, and they drop out after compaction. Claude Code ignores an unknown skill
field and loads a rule whose `paths:` YAML does not parse at every launch, without a warning.

## Decision
- Root `CLAUDE.md` holds the hard rules and the **architecture invariants** (they must survive compaction): at most
  150 loaded lines, counting every rule file without `paths:`. Nested `CLAUDE.md` per area: at most 100 lines.
  `.claude/rules/*.md` scoped by `paths:`: at most 60 lines. `docs/` are linked, never `@imported`.
- `tools\run.cmd lint` (in `verify` and CI) counts the lines Claude Code loads (frontmatter and block-level HTML
  comments are free) and checks rule, agent and skill frontmatter strictly, in Python, so CI needs no Claude Code.
- Over budget, the same PR scopes a rule to paths, moves it into a skill, or retires it; the intervention entry says
  which.

## Alternatives
- Everything in root `CLAUDE.md`: every session pays for every area's rules.
- Nothing in root, all in `docs/`: invariants vanish after compaction.
- `claude plugin validate` for skills: it passed a description that YAML cannot parse.

## Consequences
New rules come from interventions (`/log-intervention`) and compete for the same budget. Details: AGENT_WORKFLOW §3
and §6.
