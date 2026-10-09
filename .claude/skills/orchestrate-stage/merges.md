# Merges and rebases (orchestrate-stage)

Part of the orchestrate-stage skill ([SKILL.md](SKILL.md)); read it before every merge, rebase, conflict or
`--sync-main`, and at the stage's end.

## 5. Merges and rebases
You merge task PRs into `release/m<k>`, and PRs into `main` through the gate of `merge <pr> --base main`
([release-branch ADR](../../../docs/decisions/2026-10-01-release-branch-per-milestone.md),
[trust ADR](../../../docs/decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md)). A typed `gh pr
merge` stays denied: you merge only with `tools\run.cmd merge` (#181, #300; AGENT_WORKFLOW §7.1 Git flow). Run
`merge` and `merge-check` from the main checkout: your `release-m<k>` worktree has them only once `release/m<k>` has
taken in a `main` that has them.
- **The gate.** Merge a PR only when CI is green, the fresh reviews left no open blocker or major (the PR's
  findings table and `not_fixed`; one that waits for the engineer waits for the merge too: write its answer as
  "Answered: <link>" at the end of the item, `gh pr edit --body-file`), and, into `release/m<k>`, `verify` is green
  on the merged tree (`merge` checks CI and runs that `verify`; into `main` it checks the rest of the gate instead).
- **Before every merge: `tools\run.cmd merge-check --base release/m<k>`** (seconds, no Godot): each open PR onto
  its base tip and each pair into it, textually and by symbols (what one side removes or changes and the other's
  added lines use; a signature that only appends parameters with defaults is a note), plus the pairs across bases
  that change a shared file (§2.8); Markdown tables for the wave comment; exit 1 on a conflict, an overlap or a PR
  it could not check. An overlap is a lead, not a proof. When it flags the PR you are about to merge, either merge
  the side that changes the symbol first and send the other to `pr-rebase` (inline for a docs or test-list
  conflict, below), or first run `tools\run.cmd merge-check --trial <pr> <pr>... --base release/m<k>` with
  `run_in_background` (the base plus the PRs merged in that order in a scratch worktree, then `verify`): green,
  merge in that order; red, merge the first and send the later PR to `pr-rebase` with the trial's log in `why`. A
  chain you merge in one go gets a trial too.
- **Flagged across bases** (your PR and an open PR into `main`, §2.8): `--trial` takes one base, so hold that one PR
  and merge the rest of the wave. Name the pair on your plan issue and the other track's; the `main` side merges
  first (its manager's gate notes the pair). Once it is on `main`: `merge --sync-main`, then the held PR to
  `pr-rebase` (inline for a docs conflict), then merge it. If the `main` PR is still open when everything else of
  the stage is merged, it goes into your "For you:" block: the engineer chooses the order.
- **The merge:** `tools\run.cmd merge <pr> --base release/m<k>` with `run_in_background` (12 to 14 minutes on this
  PC: a fresh import plus the whole suite). It refuses any base but `release/*` and `main`, and a task's checkout;
  a PR a human already merged is only fetched (the engineer merged #107 himself); otherwise it checks CI, merges
  `--no-ff` in a scratch detached worktree at `origin/release/m<k>`, runs `verify` on the merged tree, pushes the
  merge commit by hash, confirms the PR merged on GitHub and prints one `wave:` line: paste it into the wave comment.
  A red `verify` or a conflict pushes nothing and leaves nothing to undo (logs and GdUnit reports in
  `tools/out/merge-logs/`): tell the human and relaunch the task with the failure in `notes`. Never type its git
  steps by hand: the guard asks for them, and the deny rule `git push *HEAD*` refuses `HEAD:`.
- **Taking `main` in** (the engineer's answer N2): when the tooling track's manager says on your plan issue that
  `main` has a change the stage should take in, run `tools\run.cmd merge --sync-main --base release/m<k>` at the
  next wave boundary (no merge in flight), with `run_in_background`: `origin/main` merged into the release branch the
  same way, `verify` on the merged tree, the push by hash. Then `merge-check --base release/m<k>` again (the open
  task PRs onto the new tip); both go into the wave comment.
- **Order.** Stacked PRs: the parent first. Never merge a parent while its child's workflow has not reached Publish:
  the merge deletes the parent branch the child's reviewers diff against and its publisher targets. If it happened
  anyway, relaunch the child fresh with `base: "release/m<k>"` (its `wave --args <n>` with the new base) once the
  running one ends.
- After each merge: `gh pr list --state open --json number,headRefName,baseRefName,mergeStateStatus` (`UNKNOWN` just
  after a merge: ask again). A child still based on the merged parent: `gh pr edit <child> --base release/m<k>`.
- Never touch a worktree whose workflow is still running, yours or another session's (§2.2).
- A docs or test-list conflict: resolve inline in that task's worktree, each command in a subshell
  (`(cd <worktree> && git fetch origin && git rebase origin/release/m<k>)`, keep both sides, `verify`, then
  `(cd <worktree> && tools/run.sh publish --base release/m<k>)`, both in the background with `wait <log>`), then a
  PR comment listing the conflicts. The guard lets a rebase through without a prompt when the command enters the
  worktree with `cd` (or `git -C`) and it is on its task branch (AGENT_WORKFLOW §8.2, #51); while another live
  session works in that worktree it asks, so hand such a case to `pr-rebase` when the human is away.
- A semantic conflict (two PRs creating the same classes, a changed interface): the saved workflow `pr-rebase`
  with args `{n, pr, wt, branch, base, why, steps, focus}` (`base: "release/m<k>"`) and its v2 args
  `second_review`, `skeptic`, `bounded_waits`, `efforts`, `models`, `lean` and `lean_reason` (roles rebase, review, netcode, second_review,
  skeptic, fix; the rules of §3): rebase agent → fresh reviewer(s) → a fix agent only for a blocker or major; 2 to 4
  agents, plus 1 for `second_review` and 1 per skeptic. `why` names what merged and the PRs and handoffs to read;
  `steps` says which side's files and payloads to keep. A result with `stopped` (rebase red or unpublished) gets one
  fresh relaunch with its `problems` in `steps`, then goes to the human. A result with `note` (skeptics refuted every
  blocker and major, so no fix agent ran): add its `refuted`, each with its reason, to the PR body (`gh pr view <pr>
  --json body -q .body` into a file under `<scratchpad>/manager/`, append, `gh pr edit <pr> --body-file <file>`). A fix
  agent that changed netcode-relevant code gets a fresh `netcode-security-reviewer` before the merge (§9).
- **Into `main`** (the tooling track, #170, and a milestone's closing PR): `tools\run.cmd merge-check --base main`,
  then `tools\run.cmd merge <pr> --base main --dry-run` (seconds), then without it. The gate (AGENT_WORKFLOW §7.1)
  refuses with every reason: a red, pending or missing CI, a draft, not the engineer's PR or session, a head behind
  `main` (a background `publish` with `wait <log>` in its worktree, or `pr-rebase` when its `gate: note:` lines name an
  overlap, then CI), the exceptions (the content area or an ADR without "Approved by the engineer: <link>", added once
  his approval is on GitHub; `.claude/settings*.json`, `.claude/githooks/`, the guard), an open "Needs the engineer".
  An exception goes into your "For you:" block; the rest you fix and run again. Each merge leaves the other PRs behind
  `main`: two or more go through `tools\run.cmd merge-train <pr>... --base main` (#387; `--dry-run` first, then in the
  background, `wait` on its log): per PR in order, publish in its worktree (a red verify retried once), CI, the gate; a
  PR that fails is skipped with the reason and the train goes on. After each merge: one chat line ("merged #N into main
  as <sha>"), the `wave:` line in the wave comment, a note on a running milestone's plan issue that needs it (`merge
  --sync-main`). `main` broken by your merge: a revert PR (`git revert -m 1 <merge>`) through the same gate; tell the
  engineer. "стоп мерджі": no merges into `main` until the engineer lifts it; record it on your plan issue and #170.
- **The stage's end.** When every task is merged, open the PR from `release/m<k>` into `main` (`gh pr create --base
  main --head release/m<k>`; M3: #117): a table of the task PRs with their merge commits, every open "Needs the
  engineer" item, and the issues to close after the merge (`Closes` does not fire from the
  release branch). Open it only when no task PR still targets `release/m<k>`: merging it deletes the branch
  (auto-delete) and GitHub retargets such a PR to `main`. Run `merge-check --base main` and put its table in the PR.
  Ask the engineer for the milestone's go (a playtest, their human checks done or postponed); record it as a PR
  comment, add "Approved by the engineer: <its link>" to the body and merge it with `merge <pr> --base main`. Then
  close the stage's issues (a comment linking the PRs and merge commits) and remove your release worktree.
