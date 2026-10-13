# Merges and rebases (orchestrate-stage)

Part of the orchestrate-stage skill ([SKILL.md](SKILL.md)); read it before every merge, rebase and conflict, and at the
stage's end.

## 5. Merges and rebases
Every task PR targets `main` and you merge it through the gate of `merge <pr> --base main` ([trust
ADR](../../../docs/decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md); no release branch from M7 on,
[release-branch ADR](../../../docs/decisions/2026-10-01-release-branch-per-milestone.md), amendment). A typed `gh pr
merge` stays denied: you merge only with `tools\run.cmd merge` (#181, #300; AGENT_WORKFLOW §7.1 Git flow). Run `merge`
and `merge-check` from the main checkout.
- **The gate.** Merge a PR only when CI is green on a head up to date with `main`, the fresh reviews left no open
  blocker or major (the PR's findings table and `not_fixed`; one that waits for the engineer waits for the merge too:
  write its answer as "Answered: <link>" at the end of the item, `gh pr edit --body-file`) and `merge`'s gate passes.
  No local `verify` of the merged tree: tests run on CI (#622).
- **Before every merge: `tools\run.cmd merge-check --base main`** (seconds, no Godot): each open PR onto `main` and
  each pair into it, textually and by symbols (what one side removes or changes and the other's added lines use; a
  signature that only appends parameters with defaults is a note); Markdown tables for the wave comment; exit 1 on a
  conflict, an overlap or a PR it could not check. An overlap is a lead, not a proof. When it flags the PR you are
  about to merge, either merge the side that changes the symbol first and send the other to `pr-rebase` (inline for a
  docs or test-list conflict, below), or first run `tools\run.cmd merge-check --trial <pr> <pr>... --base main` with
  `run_in_background` (`main` plus the PRs merged in that order in a scratch worktree, then `verify`): green, merge in
  that order; red, merge the first and send the later PR to `pr-rebase` with the trial's log in `why`. A chain you
  merge in one go gets a trial too.
- **The merge:** `tools\run.cmd merge <pr> --base main --dry-run` (seconds), then without `--dry-run`. The gate
  (AGENT_WORKFLOW §7.1) refuses with every reason: a red, pending or missing CI, a draft, not the engineer's PR or
  session, a head behind `main` (a background `publish` with `wait <log>` in its worktree, or `pr-rebase` when its
  `gate: note:` lines name an overlap, then CI), the exceptions (the content area or an ADR without "Approved by the
  engineer: <link>", added once his approval is on GitHub; `.claude/settings*.json`, `.claude/githooks/`, the guard),
  an open "Needs the engineer". An exception goes into your "For you:" block; the rest you fix and run again. A PR a
  human already merged is only fetched. A behind head whose files do not overlap `main`'s new commits and that GitHub
  reports MERGEABLE merges anyway (#632: "behind by N commits, no overlap" in its `wave:` line); an overlap is refused
  with its paths. Never type its git steps by hand.
- **A train.** Each merge leaves the other PRs behind `main`: two or more go through `tools\run.cmd merge-train <pr>...
  --base main` (#387; `--dry-run` first, then in the background, `wait` on its log): per PR in order, publish in its
  worktree (a red verify retried once), CI, the gate; a PR that fails is skipped with the reason and the train goes on.
- After each merge: one chat line ("merged #N into main as <sha>"), the `wave:` line in the wave comment, and
  `gh pr list --state open --json number,headRefName,baseRefName,mergeStateStatus` (`UNKNOWN` just after a merge: ask
  again). A child still based on the merged parent: `gh pr edit <child> --base main`. `main` broken by your merge: a
  revert PR (`git revert -m 1 <merge>`) through the same gate; tell the engineer. "стоп мерджі": no merges into `main`
  until the engineer lifts it; record it on your plan issue and #170.
- **Order.** Stacked PRs: the parent first. Never merge a parent while its child's workflow has not reached Publish:
  the merge deletes the parent branch the child's reviewers diff against and its publisher targets. If it happened
  anyway, relaunch the child fresh with `base: "main"` (its `wave --args <n>` with the new base) once the running one
  ends.
- Never touch a worktree whose workflow is still running, yours or another session's (§2.2).
- A docs or test-list conflict: resolve inline in that task's worktree, each command in a subshell
  (`(cd <worktree> && git fetch origin && git rebase origin/main)`, keep both sides, `verify`, then
  `(cd <worktree> && tools/run.sh publish)`, both in the background with `wait <log>`), then a PR comment listing the
  conflicts. The guard lets a rebase through without a prompt when the command enters the worktree with `cd` (or
  `git -C`) and it is on its task branch (AGENT_WORKFLOW §8.2, #51); while another live session works in that
  worktree it asks, so hand such a case to `pr-rebase` when the human is away.
- A semantic conflict (two PRs creating the same classes, a changed interface): the saved workflow `pr-rebase`
  with args `{n, pr, wt, branch, base, why, steps, focus}` (`base: "main"`) and its v2 args
  `second_review`, `skeptic`, `efforts` and `models` (roles rebase, review, netcode, second_review,
  skeptic, fix; the rules of §3): rebase agent → fresh reviewer(s) → a fix agent only for a blocker or major; 2 to 4
  agents, plus 1 for `second_review` and 1 per skeptic. `why` names what merged and the PRs and handoffs to read;
  `steps` says which side's files and payloads to keep. A result with `stopped` (rebase red or unpublished) gets one
  fresh relaunch with its `problems` in `steps`, then goes to the human. A result with `note` (skeptics refuted every
  blocker and major, so no fix agent ran): add its `refuted`, each with its reason, to the PR body (`gh pr view <pr>
  --json body -q .body` into a file under `<scratchpad>/manager/`, append, `gh pr edit <pr> --body-file <file>`). A fix
  agent that changed netcode-relevant code gets a fresh `netcode-security-reviewer` before the merge (§9).
- **The stage's end** has no merge: when every task is merged, the engineer's playtest; then close what is still open of the
  stage (task issues close with their PRs' `Closes`, so mostly the plan and milestone issues; a comment linking the
  PRs and merge commits) and report, with every open "Needs the engineer" item.
- **A release branch** exists only when a kickoff names one for a stage (the M3-M6 flow, in the ADR above). Then
  `release/m<k>` is created from `main` after the yes (stage-setup step 5), and everything above reads `--base
  release/m<k>` for its task PRs (`start`, the workflow `base`, `publish`, `merge`, `merge-check`, `gh pr edit`,
  `pr-rebase`); `merge` needs CI green on a head that contains it, and CI runs on pushes to `release/**`. Take `main`
  in at a wave boundary with no merge in flight, when the other track's manager says on your plan issue that `main`
  has a change the stage needs: `tools\run.cmd merge --sync-main --base release/m<k>` (no local `verify`; then
  `merge-check` again). A task PR into it and a PR into `main` that change a shared file: hold the release one, the
  `main` side merges first, then `--sync-main`, then the held PR to `pr-rebase`. The stage ends with a PR from
  `release/m<k>` into `main` (`gh pr create --base main --head release/m<k>`): a table of the task PRs with their merge
  commits, every open "Needs the engineer" item and the issues to close (`Closes` does not fire from the release
  branch); open it only when no task PR still targets the branch (merging it deletes the branch and GitHub retargets
  such a PR to `main`). The engineer's go, then "Approved by the engineer: <link>" in its body and `merge <pr> --base
  main`; then close the issues and remove your release worktree.
