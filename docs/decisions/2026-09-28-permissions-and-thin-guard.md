# Permission rules and a thin guard hook

- **Status:** Accepted; ask/allow lists and guard scope amended by
  `2026-09-28-unattended-work-permissions.md`; the guard's runtime is in `2026-09-29-claude-code-hooks-in-git-bash.md`;
  guard scope widened to recursive deletes and `git reset`, and the scratch folder `tests/scratch/` added, on
  2026-09-30 (Consequences); all git that discards work or rewrites history judged by the session's own worktree
  and task branch, same day (issue #51, Consequences); `gh` reads of other repositories freed and `gh` writes there
  judged by the guard, same day (issue #68, Consequences); every git command in the own worktree on its task branch
  freed, an interactive rebase whatever its editor included, on 2026-10-06 (issue #457, Consequences); `gh` writes
  to the repositories of gh's own account and filtered deletes in the temp folder freed, same day (issue #464,
  Consequences)
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
- **Amended 2026-09-30 (issue #51, the engineer's design approved in chat):** agents have full freedom in their own
  worktree and task branch. The ask rules for `git checkout`, `switch -f|--force|--discard-changes`, `restore`,
  `clean`, `stash drop|clear`, `branch -d`, `worktree`, `rebase` and `git -c` (26 rules) and the deny pair on
  `git branch -D` leave `.claude/settings.json`; the guard judges those commands, `git reset` and recursive deletes by
  where they act. They pass in the session's own worktree (the one its working directory is in, or, for a session in
  the main checkout, the first worktree its command enters with `cd`, `Set-Location` or `git -C`, unless another
  live session works there) on its task branch (known by the worktree's identity: `<area>/<n>-<slug>` checked out
  in `.claude/worktrees/<n>`, so a parent or spike checked out there is another branch), and in
  repositories outside the project; they ask in the main checkout, in another worktree, on another branch (by name,
  since branches and the stash are shared: only the task branch and its helpers `<task branch>-x` or
  `<task branch>/x` pass), for stash entries made on another branch, for an interactive rebase, `--update-refs`,
  `rebase --exec`, `update-ref --stdin`, `worktree remove|move` of anything but the own worktree's folder, and
  `git -c core.hooksPath`. Branch and stash names come from the files in `.git`, read by the hook without a git call.
  Reason: the only work at risk in the own worktree is the agent's own, committed or reproducible; the risk is in
  the main checkout (the Godot editor and the humans' files), in other sessions' worktrees and on other branches,
  which text rules cannot tell apart. `start` gives every engineer task a worktree (see the worktrees ADR), so the
  freedom always applies.
  Rejected: keep the text rules and allow them in bypass (they prompt in every mode, so a rebase or a
  `git checkout -- file` in the own worktree stops a night run); own worktree only by the session's working
  directory (a manager's task session starts each call in the main checkout, so it would never be free); a
  session-to-worktree map kept by the hook (state across calls, harder to test). Kept: every deny rule on pushes to
  `main`, remote deletes, `--mirror`/`--all`/`--prune`, `gh pr merge` and `hooksPath`, and the asks on
  `.claude/settings*.json` and `addons/`. Left open: a delete by absolute path into a worktree from a session in the
  main checkout, without a `cd`, asks (it owns no worktree). Replay: `docs/AGENT_WORKFLOW.md` §8.2.
- **Amended 2026-09-30 (issue #68):** reading another repository with `gh` never prompts. The ask rules
  `gh * -R *` and `gh * --repo*` (and their PowerShell twins) leave `.claude/settings.json`; `gh release` asks only
  for `create|edit|delete|upload|download`, and `gh release view|list` and `gh search` join the allow list. The guard
  asks instead for a `gh` command that names a repository other than this project's `origin` (`-R|--repo`,
  `GH_REPO`, a github.com URL, `gh repo <sub> x/y`, `gh issue transfer`, a `gh api repos/x/y/...` endpoint) and does
  not only read (views, lists, `pr diff|checks`, `gh search`, `gh api` GET). Writes to this repository are unchanged
  (allowed). Reason: ask beats allow, so a text rule on `-R` could not let reads through; after #51 about 63 of the
  67 remaining prompts in this project's transcripts were such reads (upstream research: Godot, GdUnit4, TwoVoIP,
  Claude Code), and the replay in `docs/AGENT_WORKFLOW.md` §8.2 shows 95 prompts before and 18 after, with both
  real writes to other repositories (upstream `gh issue create`) still asking. Rejected: one text ask rule per write
  subcommand and spelling (`gh issue comment * -R *`, `--repo=`, `-Rx/y`, URLs...): dozens of rules that still miss
  `GH_REPO`, URLs and `gh api` fields, and would also ask for this repository's writes named with `-R`; an allow
  rule per read (ask would still win). Left open: GraphQL mutations and a `gh` command run inside a clone of another
  repository. `runner.permissions` models Claude Code's matcher, so selftests check the lists with the guard, and
  replays local transcripts through the rules and the guard of two revisions.
- **Amended 2026-10-06 (issue #457):** in the own worktree on its task branch an interactive rebase passes whatever
  editor it names (the editor ask above, and #104's no-op-editor exception, are gone), a rebase that names `HEAD` or
  `@` is judged by where it runs (git rebases a detached HEAD), a pathspec the guard cannot resolve is judged by the
  folder before its unknown part (git refuses one outside its repository; not in a cloud session's main checkout),
  and `worktree remove|move` of an absolute path inside the worktree passes. Reason: the engineer, 2026-10-06, "git is
  protected on GitHub"; over the week to 2026-10-06 six such asks protected nothing and one kept #445's fix agent
  waiting a night (`docs/AGENT_WORKFLOW.md` §8.2, intervention `2026-10-06-engineer-git-free-in-own-worktree.md`).
  Kept: the main checkout, other worktrees and branches, the stash, the protected paths, `--update-refs`, `--exec`,
  `update-ref --stdin`, `git -c core.hooksPath`, and every push rule and the pre-push hook. `--exec` is a deliberate
  exception to #457's "every form" (its command can be a push the deny rules cannot see), left to the engineer.
- **Amended 2026-10-06 (issue #464):** a `gh` write to a repository owned by gh's active account (the login
  `gh api user` returns, read from gh's `hosts.yml`) passes like the same write to this repository, so the rules
  judge it; the guard keeps its ask there for every `gh` command a deny or ask rule names (merges, deletion, auth,
  secrets, ...), `gh issue transfer`, and `gh api` writes that are not a POST or reach a merge, secret, variable,
  key, dispatch, release or transfer endpoint, because a spelling like `gh pr -R x merge` slips past the rules' text.
  A filtered recursive delete in the temp folder (`rm -rf "$TEMP"/x*`, a non-recursive `Get-ChildItem $env:TEMP
  -Filter x*` piped to `Remove-Item -Recurse`) is judged by what it matches: it asks only when the pattern reaches
  outside the folder or cannot be read, may match a Claude scratchpad root or a folder holding one, or a match is or
  holds a worktree (or a link or junction there); a kept `gh` command that names this repository asks too. Reason:
  the engineer wanted both (PR #463's answers) and approved the issue on 2026-10-06;
  over the week to 2026-10-06 the 30 asks for `gh` writes to `prime-game-art` and `prime-game-ui` waited about 12.6
  hours and the one `rmtree-*` cleanup 8.8 hours, protecting nothing (`docs/AGENT_WORKFLOW.md` §8.2: the replay
  shows 35 prompts gone and none new). The deny and ask rules, other owners and the other kept asks are unchanged.
  Wanted by the engineer: https://github.com/xperiaroco2/prime-game/pull/463#issuecomment-6014583090 (answer 5);
  approved for building, relayed by the manager:
  https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-6014999058.
