# Ownership by CODEOWNERS and convention

- **Status:** Accepted
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase A decision session)
- **Amended 2026-10-01 (issue #128, option (a), permanent):** the engineer's agent works in the designer's area
  when the engineer says the change was agreed with the designer. The PR says "agreed with the designer, relayed by
  the engineer" and tags @SwiftySinister; an objection is reverted by a follow-up PR; a scene with the designer's
  open PR is never edited ([intervention](../interventions/2026-10-01-engineer-relayed-design-agreement.md),
  `docs/AGENT_WORKFLOW.md` §9).
- **Amended 2026-10-08 (#518):** the designer becomes optional; the engineer owns the content area (below).

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

## Amendment 2026-10-08: the designer becomes optional (#518)

Approved by the engineer: https://github.com/xperiaroco2/prime-game/issues/170#issuecomment-6037210189

- **Why:** the designer will be little involved, and the vertical slice puts its house into `levels/` (#523). Under
  the rule above an agent would stop and wait in `levels/` for a designer who is mostly away.
- **Ownership:** the engineer owns `content/ levels/ docs/GDD.md docs/design/` and the skills `new-mechanic` and
  `new-level-piece`, besides his earlier paths. `.github/CODEOWNERS` drops the designer's section, so those paths fall
  to the engineer's `*` line; the designer stays on the shared paths.
- **Agents** edit the content area on the engineer's word (the issue, his comment or his chat); without it they stop
  and ask, and they never invent content nobody decided. This replaces the relayed agreement of 2026-10-01: no "agreed
  with the designer, relayed by the engineer" line and no tag are needed.
- **The designer** may still contribute: his PRs go to the engineer, who reviews and merges them; no step waits for
  him. His agent still never edits engine code (a missing primitive is an `engine-request` issue), and a scene with
  someone else's open PR is still never edited.
- Where it lives: root `CLAUDE.md` (Ownership), `docs/AGENT_WORKFLOW.md` §9, `content/CLAUDE.md`, `levels/CLAUDE.md`
  and the skills. The body above is kept as written.
