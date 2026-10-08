---
name: finish-task
description: Finish the current prime-game task by the definition of done - verify, fresh-context reviews, docs, then publish (in the designer's sessions after one "Publish now?"), the PR and the handoff comment. Use when a human says "finish", "заверши задачу", "оформлюй PR" or runs /finish-task.
allowed-tools:
  - Bash(tools/run.sh *)
  - PowerShell(tools\run.cmd *)
  - Bash(git status*)
  - PowerShell(git status*)
  - Bash(git diff *)
  - PowerShell(git diff *)
  - Bash(git log *)
  - PowerShell(git log *)
  - Bash(gh issue view *)
  - PowerShell(gh issue view *)
  - Bash(gh issue comment *)
  - PowerShell(gh issue comment *)
  - Bash(gh pr view *)
  - PowerShell(gh pr view *)
  - Bash(gh pr create *)
  - PowerShell(gh pr create *)
  - Bash(gh pr edit *)
  - PowerShell(gh pr edit *)
---

# Finish a task (docs/AGENT_WORKFLOW.md §4.2, the definition of done)

Commands below use the PowerShell form `tools\run.cmd`; in Git Bash use `tools/run.sh`. Multi-line texts (commit
messages, PR bodies, comments) go in a scratchpad file: `git commit -F`, `--body-file`.

0. **Which task.** `git branch --show-current` must be a task branch `<area>/<n>-<slug>`; `<n>` is the issue. If it
   is not, stop and ask. Everything must be committed (Conventional Commits, one logical change each).
1. **Verify.** `tools\run.cmd verify`, in the background with `wait <log>` (root CLAUDE.md, Shell: a slot wait alone
   can reach 600 s, where a foreground call is killed). Paste its summary (from "verify summary" to the end).
   In your inner loop you may run `verify --fail-fast` (it stops at the first red step); the run you paste here, and
   publish's, is a plain `verify`.
   Red: stop and report the failures. Never weaken, skip or delete a test to make it pass.
2. **Fresh-context reviews,** chosen from `git diff --name-only origin/<base>...HEAD`, where `<base>` is the open PR's
   base (`gh pr view --json baseRefName`; a stacked PR's parent), else the parent `start --base` recorded
   (`git config --get branch.<branch>.primeBase`) while `origin/<parent>` exists, else `main`; launch them in one
   message:
   - any code (`.gd`, `.py`, scripts, workflows) → agent `code-reviewer`; a docs-only or content-data-only diff →
     the bundled `/code-review` at medium, or none;
   - `core/`, `server/`, `net/`, `client/` (what it renders) or `tests/harness/` (the information-leak test)
     changed → also `netcode-security-reviewer`;
   - `.gd`, `.tscn` or `.tres` changed → also `godot-api-checker`.
   Fix each finding in a new commit and run the tests it touches and `check` (no standalone `verify`: step 5's
   `publish` verifies the new tree), or list the findings you leave, with the reason, in the PR. If a project
   subagent reviewed, `tools\run.cmd agents-check` confirms it ran on its own model (with no project subagent in this
   session it has nothing to judge and fails; skip it then).
3. **Docs.** Durable knowledge changed → update the owning doc (`docs/ARCHITECTURE.md`, `docs/AGENT_WORKFLOW.md`,
   `docs/GDD.md`, an ADR). A human corrected you during the task → skill `log-intervention`. A third-party asset →
   `docs/credits/<asset>.md`, then `tools\run.cmd credits`. Commit these too.
4. **Whose session.** `gh api user --jq .login` is the engineer's account (`xperiaroco2`, the `*` owner in
   `.github/CODEOWNERS`): publish without asking once steps 1 to 3 hold (the
   [trust ADR](../../../docs/decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md)). Otherwise, or if
   unsure, **ask exactly once:** "Publish now? (push + PR + handoff comment)". Anything but a yes: stop and summarise
   what is done and what is left.
5. **Publish.** `tools\run.cmd publish`, in the background with `wait <log>` like `verify`. It rebases on the PR's
   base (else the recorded parent, else `main`), runs `verify` again unless an identical tree was just verified green
   (the newest verify passed at the same head, tree and runner under 2 hours ago: it says so, #471) and pushes the
   task branch with a lease; a red verify pushes nothing. Its line `base origin/<base>` names the PR's base. If it
   stops (a conflict, red verify, or remote commits the branch never had), report what it said and ask the human.
   Never push by hand and never force-push. "cannot confirm that the parent … was merged": ask the human to check
   the parent's PR; only after they confirm the merge, `tools\run.cmd publish --base main`. A task of a stage (its PR
   targets `release/m<k>`): `tools\run.cmd publish --base release/m<k>`, also on a checkout without `start`'s record.
6. **Pull request.** If `gh pr view` finds none for the branch, fill `.github/pull_request_template.md` in a scratchpad
   file and run `gh pr create --base <base> --title "<conventional title>" --body-file <file>` (`<base>`: the one
   `publish` just reported: `main`, a stage's `release/m<k>` or a stacked PR's parent). Otherwise update it with `gh pr edit --body-file`.
   - `Closes #<n>`; a summary; the verification commands with their output (at least the `verify` tail); docs
     updated yes/no.
   - Screenshots: `tools\run.cmd shot <scene>` PNGs for visual changes, else "none". `gh` cannot upload images:
     send the PNG to the human and ask them to drag it into the PR description.
   - The other owner's paths touched (`.github/CODEOWNERS`) → `--reviewer <their GitHub handle>` and say why under
     "Cross-area". A change in the content area: say there on whose word it was made (the engineer's, with its
     link) and list `content/` and `levels/` files as provisional for his approval; no relay phrase and no tag: the
     designer is optional and nothing waits for him (`docs/AGENT_WORKFLOW.md` §9).
   - End the body with the attribution line this session requires.
7. **Handoff.** `gh issue comment <n> --body-file <file>` with four headings: Done, Left, Decisions, Gotchas, plus
   the PR link. Then `tools\run.cmd board move <n> in-review`.
8. **Tell the human** the PR link and that CI runs on it. A stage's task PR into `release/m<k>` is merged by its manager
   session ([ADR](../../../docs/decisions/2026-10-01-release-branch-per-milestone.md)). A workflow agent (`issue-task`,
   `pr-rebase`) stops after telling: its manager merges. A PR into `main` from an interactive solo session: in the
   engineer's session ask once, "merge it yourself, or shall I merge it through the gate?", and only on the engineer's
   word for this PR (or this session) run, once CI is green, `cd D:\prime-game; tools\run.cmd merge <pr> --base main
   --dry-run`, then without `--dry-run` (from the main checkout: it refuses a task's checkout); tell the refusals in
   plain words. The gate's exceptions and the designer's PRs are merged by the engineer, with "Create a merge commit".
   For a stacked PR: GitHub retargets the child to the parent's base when the parent's branch is deleted on merge; if the
   child still shows the parent as base, `gh pr edit <child> --base <that base>` before merging it. If the task ran in a
   worktree: after the merge, the human archives this session in the app (Windows cannot delete a folder a live session
   sits in), then runs `worktree-done` from the main checkout. Give that command in the chat as its own fenced
   PowerShell block (root `CLAUDE.md`, "Talking to the humans"), with `cd` to the main checkout's absolute folder (the
   first line of `git worktree list`), and add `--pushed` for a spike that is never merged: ```powershell cd
   D:\prime-game; tools\run.cmd worktree-done <n> ``` Preview it with `git worktree list` instead of running it: running
   it would do the human's step.
