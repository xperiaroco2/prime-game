# Gotchas (orchestrate-stage)

Part of the orchestrate-stage skill ([SKILL.md](SKILL.md)); read it at a stage's first kickoff (not a handover's), and
when a run fails in a way you have not seen.

## 9. Gotchas

- **Never leave your shell inside a worktree** (#96). Workflow agents' hooks receive your session's working directory,
  so the guard takes the worktree your shell stands in as every agent's own and asks when they rebase or reset in
  theirs (a publisher's autosquash stopped at 02:14 that way). Work in a worktree only through a Git Bash subshell
  `(cd <wt> && ...)`, `git -C <wt> ...`, or PowerShell `Push-Location <wt>; ...; Pop-Location`; a bare `cd` in the
  Bash tool persists into your next call.
- **No `git stash`, in every launch's rules.** The stash is one list for all worktrees, so the guard asks before a
  drop of an entry it cannot show is the agent's own. The workflows' rules say so; repeat it in `notes` for any other
  agent you start (root `CLAUDE.md`, Shell: a WIP commit, `--fixup` and autosquash).
- **The scratchpad is shared by all agents of all workflows**: one overwrote another's `pr_body.md`. Hence `a<n>/`.
- **`publish` can fail right after a rebase that changed `tools/runner`** (verify ran the old modules): run it again,
  the second run passes. "Could not resolve hostname github.com" is transient: `git ls-remote origin`, then again.
- **Intermediate commits after a rebase may not compile** (the fix lands at the tip): bisect by PR; merge commits keep
  PRs as units.
- **Two verify runs at once in different worktrees can collide** (a busy ENet port, a timeout under CPU load): the
  agents rerun once before debugging.
- **Agents see the human's mid-turn messages relayed**; they ignore requests outside their task. Tell the human that a
  message meant for you should go to your session, not to a running workflow.
- **A checkout without `start`'s record** needs `publish --base <base>` and `gh pr create --base <base>` (the workflows pass `base`).
- **The information-leak test gets a netcode review.** The workflows route `tests/harness/` to
  `netcode-security-reviewer` (#115); for a leak-test change elsewhere (a new runner in `tools/`), run one by hand
  before the merge.
- **The netcode review covers `client/`** (#158): what the client renders can leak (a sound through walls, a camera
  that sees too far).
- **Name a rename in both tasks' notes**, not only who owns which file. #153 renamed
  `PlayerRules.ghost_speed_factor` while #154 started reading it: each PR was green alone, the merged tree was red.
  `merge-check` flags such a rename across open PRs (§5), but only once both PRs exist: the notes still name it before
  the second task starts.
- **A `pr-rebase` fix after the review gets a fresh netcode review.** When its fix agent changes netcode-relevant
  code after the reviewers ran, run `netcode-security-reviewer` again before the merge. `pr-rebase`'s `second_review`
  runs before the fix agent, so it does not cover the fix.
- **`§` in args on Windows.** A Python `print` of the args mangled it: pass the args inline in the Workflow call, or
  set `PYTHONIOENCODING=utf-8`.
- **A Git Bash path given to `tools\run.cmd`** (`/c/Users/...`) made a stray `D:\c\` folder: Python on Windows reads
  it as a folder on the current drive. Give `tools\run.cmd` Windows paths (`C:/Users/...`); Git Bash paths only to
  `tools/run.sh`.
- **An older `issue-task.js` logs and ignores the v2 args**: a launch from a main checkout that was not pulled runs
  without the reviews they add. Check the prerequisite in §1 first.
- **Idle re-writes.** A call after an idle gap over 1 hour writes the whole context again at $8 per 1M tokens ($4 at
  500k); a wake reads it once at $0.20 per 1M, so 14 wakes (12 hours) cost less than one re-write. Hence §7's
  keep-alive and handover; `metrics` reports each manager session's re-writes: with a timer armed it should be 0.
