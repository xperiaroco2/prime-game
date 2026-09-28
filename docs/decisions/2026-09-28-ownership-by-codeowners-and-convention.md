# Ownership by CODEOWNERS and convention

- **Status:** Accepted
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase A decision session)

## Context
KICKOFF §5.3: the designer's agent does not modify engine code; the engineer's agent does not change content without
the designer's approval.

## Decision
Enforced by `.github/CODEOWNERS` and by rules in the `CLAUDE.md` files (root, `content/`, `levels/`), plus the
`engine-request` routing. No hook, no `ownership.json`, no `PRIME_GAME_ROLE` variable.

## Alternatives
- Asymmetric guard (designer denied on engine paths, engineer asked on content paths): recommended, not chosen.
- Deny rules in the designer's personal settings: unreviewed, and they drift from the real layout.

## Consequences
- A boundary slip is caught in review, not at edit time. Code-owner review is off, so the author requests the other
  owner with `--reviewer` when the diff crosses areas.
- Onboarding is simpler: no role variable, no bootstrap mode.
