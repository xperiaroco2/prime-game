# Permission rules and a thin guard hook

- **Status:** Accepted; ask/allow lists and guard scope amended by
  `2026-09-28-unattended-work-permissions.md`; the guard's runtime is in `2026-09-29-claude-code-hooks-in-git-bash.md`;
  guard scope widened to recursive deletes and `git reset`, and the scratch folder `tests/scratch/` added, on
  2026-09-30 (Consequences)
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
- **Built in M0 stage 4 (2026-09-29):** the guard matches `Bash|PowerShell` only. Edit rules already cover the file
  tools (Edit, Write, NotebookEdit), and a shell write is the one path they miss: Claude Code checks a redirect or
  `tee` target against Edit allow and deny rules, not ask rules. The pre-push hook blocks force pushes, deletions
  and pushes to `main` locally, which matters while the `main-2` ruleset lets admins bypass it.
- **Amended 2026-09-30 (issue #47, option A):** the text ask rules for recursive deletes (`rm -r*` and its spellings,
  `Remove-Item -Recurse|-r`) and `git reset *` leave `.claude/settings.json`; the guard judges those commands by
  their target instead. A recursive delete asks when a target is in the project (the main checkout or a worktree,
  regenerated `tools/out/` and `.godot/` and the gitignored scratch folder `tests/scratch/` aside), above it, a drive
  root or the home or temp folder itself, or cannot be resolved and names it; `git reset` asks for `--hard`,
  `--merge`, `--keep` or a move of the branch in a repository anywhere in the project, and passes when it only
  unstages. Temporary files go only to the scratchpad or to `tests/scratch/` (a probe test has to live under
  `res://`); full `check`, `test` and `lint` runs leave that folder out.
  Reason: the overnight run `wf_65292cf4-8b4` stopped four times on these text rules, for two deletes of its own
  scratch folders, one `git reset -q` and one `rm -r tests/integration/tmp`, a probe-test folder inside a worktree;
  the text cannot tell those from `rm -rf .` or `git reset --hard`. The engineer chose the scratch folder; the
  alternative, exempting any target whose files are all untracked or ignored, needs a git call in the hook for each
  delete and lets agents scatter temporary folders across the tree.
  Rejected: B, keep the text rules and tell agents to avoid the commands (an agent that forgets still stops the
  night); C, drop the rules (no stop before a real `rm -rf` of the repo or a `git reset --hard`). The guard stays
  best-effort like every text rule: a target it cannot resolve and that does not name the project passes. No shell
  call keeps variables from an earlier one, so a bash variable the command never assigns is also judged as empty
  (`rm -rf "$X"/*` asks); a variable from the environment is the case left open.
  Details and the replay: `docs/AGENT_WORKFLOW.md` §8.2.
