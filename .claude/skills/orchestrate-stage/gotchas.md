# Gotchas (orchestrate-stage)

Part of the orchestrate-stage skill ([SKILL.md](SKILL.md)); read it at a stage's first kickoff (not a handover's), and
when a run fails in a way you have not seen.

## 9. Gotchas

### 2026-09-30 (M2)
- The scratchpad is shared by all agents of all workflows: one overwrote another's `pr_body.md`. Hence `a<n>/`.
- `publish` can fail right after a rebase that changed `tools/runner` (verify ran the old modules): run it again.
  "Could not resolve hostname github.com" is transient: `git ls-remote origin`, then again.
- Intermediate commits after a rebase may not compile (the fix lands at the tip): bisect by PR; merge commits keep
  PRs as units.
- Two verify runs at once in different worktrees can collide (a busy ENet port, a timeout under CPU load; GdUnit4's
  `user://` files too, until #182 gave each worktree and shard its own): the agents rerun once before debugging.
- Agents see the human's mid-turn messages relayed; they ignore requests outside their task. Tell the human that a
  message meant for you should go to your session, not to a running workflow.
- Numbers: about 20 workflows in one day; 25 to 60 minutes and 450k to 900k subagent tokens per task workflow.

### 2026-10-01 (the M3 night run, #96)
- **Never leave your shell inside a worktree.** Workflow agents' hooks receive your session's working directory, so
  the guard takes the worktree your shell stands in as every agent's own and asks when they rebase or reset in
  theirs: a publisher's autosquash stopped at 02:14 that way (proved by a `tools\run.cmd permissions` replay). Work
  in a worktree only through a Git Bash subshell `(cd <wt> && ...)`, `git -C <wt> ...`, or PowerShell
  `Push-Location <wt>; ...; Pop-Location`; a bare `cd` in the Bash tool persists into your next call.
- **No `git stash`, in every launch's rules.** The stash is one list for all worktrees, so the guard asks before a
  drop of an entry it cannot show is the agent's own (`git stash drop "$ref"` at 02:10). The workflows' rules say
  so; repeat it in `notes` for any other agent you start: a WIP commit and later `git reset --soft HEAD~1`, or
  `git commit --fixup=<sha>` then `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/<base>`.
- **`publish` with a release base (#113, fixed).** On the M3 night `publish` took `release/m<k>` equal to `main` for
  a merged parent, and after a hand rebase replayed upstream commits from a stale `branch.<branch>.primeBaseTip`.
  It now keeps a base outside `<area>/<n>-<slug>` and replays only the commits after the merge-base. Still pass
  `publish --base release/m<k>` and `gh pr create --base release/m<k>` (the workflows pass `base`): a checkout
  without `start`'s record needs it. The workflows' `primeBaseTip` reset after a hand rebase is now redundant.
- **The information-leak test gets a netcode review.** A PR that touches only `tests/` and `tools/` once had no
  `netcode-security-reviewer` (#115); a pass run by hand found a major blind spot. The workflows now route it for
  `tests/harness/`; for a leak-test change elsewhere (a new runner in `tools/`), run one by hand before the merge.
- **No `staging`.** A second integration branch was tried and dropped the same night: one `release/m<k>` per milestone.

### 2026-10-01 (M4)
- **The netcode review covers `client/`** (#158). What the client renders can leak (a sound through walls, a camera
  that sees too far). Before this, the review ran by hand on PR #154 twice, and both runs found real problems.
- **Name a rename in both tasks' notes**, not only who owns which file. #153 renamed
  `PlayerRules.ghost_speed_factor` while #154 started reading it: each PR was green alone, the merged tree was red,
  and `pr-rebase` fixed it. `merge-check` now flags such a rename across open PRs (§5), but only once both PRs
  exist: the notes still name it before the second task starts.
- **A `pr-rebase` fix after the review gets a fresh netcode review.** When its fix agent changes netcode-relevant
  code after the reviewers ran, run `netcode-security-reviewer` again before the merge (done by hand for #154).
  `pr-rebase`'s `second_review` runs before the fix agent, so it does not cover the fix.
- **Never `cd <wt> && ...` in your Bash shell**: it stayed inside a worktree twice in M4. Only a subshell
  `(cd <wt> && ...)` or `git -C <wt>`.
- **`§` in args on Windows.** A Python `print` of the args mangled it: pass the args inline in the Workflow call,
  or set `PYTHONIOENCODING=utf-8`.

### 2026-10-02 (the AI productivity track, #170)
- **`publish` after a rebase that changed `tools/runner`** needed a second run twice more (#176, #199): the M2
  gotcha holds; the second run passes.
- **A bare `cd` into a worktree** happened once more in a manager's shell: the M3 rule holds for every manager.
- **A Git Bash path given to `tools\run.cmd`** (`/c/Users/...`) made a stray `D:\c\` folder: Python on Windows reads
  it as a folder on the current drive. Give `tools\run.cmd` Windows paths (`C:/Users/...`); Git Bash paths only to
  `tools/run.sh`.
- **An older `issue-task.js` logs and ignores the v2 args**: a launch from a main checkout that was not pulled runs
  without the reviews they add. Check the prerequisite in §1 first.
- **Numbers** (M4, the pipeline v2 ADR's baseline): about 82 minutes, $24 API list and 0.94% of a Max 20x week per
  task ($25.5 per 1%, #304); a stage's budget in % starts from them.

### 2026-10-03 (round 2's scouting, #170)
- **A manager's context only grows** (round 2's wave 0 on #170, `wf_e55a9be5-eac`): neither manager compacted
  (round 1's 147k to 933k tokens, M5's 184k to 928k); a call on day 2 cost 2.7 and 3.3 times one of the first hours;
  the re-writes after idle hours cost $8.12 (14% of round 1's manager) and $14.06 (19% of M5's). Hence §7's handover.

### 2026-10-04 (the Token efficiency track, #302)
- **Idle re-writes** (#302's report of 2026-10-04, the managers since the plan change): 24 calls after a gap over 1
  hour wrote 0.15 to 0.93M tokens each again, $89.8 list: 11 while their own workflow ran ($38.8), 13 at human
  breaks of 1.0 to 13.5 hours ($51.0). A wake reads the context once ($0.20 per 1M on Opus 5.5: $0.10 at 500k) and
  writes a few hundred tokens; a re-write costs $8 per 1M ($4 at 500k), so 14 wakes (12 hours) cost less than one.
  The keep-alive of §7 saves a net 5.7 limit points at cache-read weight 0 (2.9 at full weight). `metrics` reports
  each manager session's re-writes by what held when the gap began: with a timer armed it should be 0.
