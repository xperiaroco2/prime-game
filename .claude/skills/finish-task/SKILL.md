---
name: finish-task
description: Finish the current prime-game task by the definition of done - verify, fresh-context reviews, docs, then one "Publish now?" before publish, the PR and the handoff comment. Use when a human says "finish", "заверши задачу", "оформлюй PR" or runs /finish-task.
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
1. **Verify.** `tools\run.cmd verify`. Paste its summary (the lines from "verify summary" to the end) for the human.
   Red: stop and report the failures. Never weaken, skip or delete a test to make it pass.
2. **Fresh-context reviews,** chosen from `git diff --name-only origin/<base>...HEAD`, where `<base>` is the open PR's
   base (`gh pr view --json baseRefName`; a stacked PR's parent), else the parent `start --base` recorded
   (`git config --get branch.<branch>.primeBase`), else `main`; launch them in one message:
   - any code (`.gd`, `.py`, scripts, workflows) → agent `code-reviewer`; a docs-only or content-data-only diff →
     the bundled `/code-review` at medium, or none;
   - `core/`, `server/` or `net/` changed → also `netcode-security-reviewer`;
   - `.gd`, `.tscn` or `.tres` changed → also `godot-api-checker`.
   Fix each finding in a new commit and run `verify` again, or list the findings you leave, with the reason, in the
   PR. If a project subagent reviewed, `tools\run.cmd agents-check` confirms it ran on its own model (with no
   project subagent in this session it has nothing to judge and fails; skip it then).
3. **Docs.** Durable knowledge changed → update the owning doc (`docs/ARCHITECTURE.md`, `docs/AGENT_WORKFLOW.md`,
   `docs/GDD.md`, an ADR). A human corrected you during the task → skill `log-intervention`. A third-party asset →
   `docs/credits/<asset>.md`, then `tools\run.cmd credits`. Commit these too.
4. **Ask exactly once:** "Publish now? (push + PR + handoff comment)". Anything but a yes: stop and summarise what is
   done and what is left.
5. **Publish.** `tools\run.cmd publish`. It rebases on the PR's base (else the recorded parent, else `main`), runs
   `verify` again and pushes the task branch with a lease; its line `base origin/<base>` names the PR's base. If it
   stops (a conflict, red verify, or remote commits the branch never had), report what it said and ask the human. Never
   push by hand and never force-push.
6. **Pull request.** If `gh pr view` finds none for the branch, fill `.github/pull_request_template.md` in a scratchpad
   file and run `gh pr create --base <base> --title "<conventional title>" --body-file <file>` (`<base>`: the one
   `publish` just reported, `main` or a stacked PR's parent). Otherwise update it with `gh pr edit --body-file`.
   - `Closes #<n>`; a summary; the verification commands with their output (at least the `verify` tail); docs
     updated yes/no.
   - Screenshots: `tools\run.cmd shot <scene>` PNGs for visual changes, else "none". `gh` cannot upload images:
     send the PNG to the human and ask them to drag it into the PR description.
   - The other owner's paths touched (`.github/CODEOWNERS`) → `--reviewer <their GitHub handle>` and say why under
     "Cross-area".
   - End the body with the attribution line this session requires.
7. **Handoff.** `gh issue comment <n> --body-file <file>` with four headings: Done, Left, Decisions, Gotchas, plus
   the PR link. Then `tools\run.cmd board move <n> in-review`.
8. **Tell the human** the PR link and that CI runs on it. Only humans merge, with "Create a merge commit". For a
   stacked PR: GitHub retargets the child to `main` when the parent's branch is deleted on merge; if the child
   still shows the parent as base, `gh pr edit <child> --base main` before merging it. If the task ran in
   a worktree: after the merge, the human archives this session in the app (Windows cannot delete a folder a live
   session sits in), then `tools\run.cmd worktree-done <n>` from the main checkout (`--pushed` for a spike that is
   never merged).
