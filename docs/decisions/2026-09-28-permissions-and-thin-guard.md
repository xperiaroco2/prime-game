# Permission rules and a thin guard hook

- **Status:** Accepted; ask/allow lists and guard scope amended by
  `2026-09-28-unattended-work-permissions.md`
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase A decision session)

## Context
Permission rules match command text, so they are best-effort: flag abbreviations, `git -C` and side-effect flags such
as `git log --output=` get past them. The proposal added a large fail-closed guard (about 20 argument-parsing rules in
two shells). After choosing a public repo, GitHub's ruleset blocks pushes to `main`, force pushes and deletions
server-side. Ownership and the Godot editor were then left to convention (see the ownership and editor-convention
ADRs).

## Decision
- Shared permission lists as in `docs/AGENT_WORKFLOW.md` §8.1, each `Bash(...)` rule with a `PowerShell(...)` twin.
  Issue creation, issue comments and PR creation run without a prompt (KICKOFF said read-only `gh`). Godot, Python and
  gdtoolkit run without a prompt only through the runner (KICKOFF named the raw executables).
- A **thin** guard hook in M0: it only asks before shell commands that write to protected paths (`.claude/`, runner
  files, `.github/`). No parsing of every git flag.
- A pre-push hook stays as a cheap local duplicate of the server rules.

## Alternatives
- The full guard from the proposal: most protection, most M0 work and prompts.
- KICKOFF-literal: raw Godot and gdtoolkit allowed, `gh` writes prompt, no guard.

## Consequences
- Exotic local bypasses are not caught locally; the server ruleset covers what matters.
- **Verified 2026-09-28** (the running session picked the rules up without a restart): a force push (Bash), a push
  to `HEAD:main` (PowerShell) and `gh pr merge 999` were all denied before running. The settings generator found no
  `Bash(...)` rule without its `PowerShell(...)` twin (46 allow, 77 ask, 55 deny).
