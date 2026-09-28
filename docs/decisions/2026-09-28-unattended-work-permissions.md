# Permissions for unattended work

- **Status:** Accepted (amends `2026-09-28-permissions-and-thin-guard.md`)
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase B kickoff)

## Context
At the start of Phase B the engineer ran the session in bypass permissions mode and was still prompted for routine
read-only calls (`gh api`, `gh project list`). The current Claude Code docs (`code.claude.com/docs/en/permission-modes`,
checked 2026-09-28) say deny rules block and explicit ask rules prompt in **every** mode, including
`bypassPermissions`; allow rules have no effect there. The Phase A ask list (77 rules) therefore stopped the agent for
status reads, branching, pushes of task branches and every edit under `tools/run*`, `.github/` and `.claude/`.
The engineer wants to leave the agent working alone for about an hour.

## Decision
- The ask list keeps only real stop points: the agent's own permissions (`.claude/settings*.json`), dependencies
  (`addons/`), commands that discard work or rewrite history, recursive deletes, `gh api` PUT/PATCH/DELETE, deletions
  on GitHub, reviews, workflow dispatch, releases, secrets, variables and repo settings.
- Status reads, `git switch`/`branch`/`log`/`stash`, pushes of an explicit task branch, `gh api` GET/POST, labels,
  projects and issue/PR edits move to allow (needed in the designer's `acceptEdits` mode; a no-op in bypass).
- New deny rules close the ways a push could reach `main` without naming it: bare `git push`, `git push [-u] origin`
  and any push naming `HEAD`.
- The thin guard (M0) covers shell writes to the remaining ask-protected paths only.

## Alternatives
- Keep the Phase A lists and approve prompts as they come: no unattended work.
- Auto mode: a classifier instead of prompts; explicit ask rules still prompt, so the list would need the same cut.

## Consequences
- Until the M0 pre-push hook exists, the deny rules and the server ruleset are the only barrier for `main`. Ruleset
  `main-2` (require a PR) currently lets repository admins bypass it, and the engineer's account is an admin, so a
  push to `main` that slips past the deny rules would land. Removing that bypass is a pending human action.
- Verified 2026-09-28: `gh api repos/xperiaroco2/prime-game` ran without a prompt; a bare `git push` was denied.
