# Machine paths and personal settings in user settings

- **Status:** Accepted
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase A decision session)

## Context
KICKOFF §6 put `GODOT_BIN` and similar variables in `.claude/settings.local.json`. On Windows that file is read from
the session's own directory, so worktree sessions do not see it.

## Decision
Each human's `~/.claude/settings.json` holds `env` (`GODOT_BIN`, `GODOT_GUI_BIN`, `PYTHON_BIN`, `GDTOOLKIT_DIR`),
`"language"` and `"permissions": {"defaultMode": "acceptEdits"}`. `.claude/settings.local.json` keeps personal
approvals only and is gitignored.

## Alternatives
- Keep `settings.local.json`: invisible in worktrees.
- The Windows user environment: set by hand, needs an app restart.

## Consequences
- Applied for the engineer on 2026-09-28. `settings.local.json` had been tracked since the initial commit; it is now
  removed from the index and ignored.
- The `language` setting took effect in the running session. Proof that a fresh session sees `env` from user
  settings is pending (`docs/AGENT_WORKFLOW.md` §14).
