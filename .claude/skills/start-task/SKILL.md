---
name: start-task
description: Start work on a prime-game GitHub issue - doctor, read the issue, ownership check, task branch, board In progress, then restate the plan. Use when a human says "start task 42", "почни задачу 42", "візьми задачу 42" or runs /start-task 42.
argument-hint: "[issue-number]"
allowed-tools:
  - Bash(tools/run.sh *)
  - PowerShell(tools\run.cmd *)
  - Bash(gh issue view *)
  - PowerShell(gh issue view *)
  - Bash(gh pr list *)
  - PowerShell(gh pr list *)
---

# Start a task (docs/AGENT_WORKFLOW.md §4.1)

Issue: $ARGUMENTS. If no number was given, ask for it: one short question, nothing else.

Commands below use the PowerShell form `tools\run.cmd`; in Git Bash use `tools/run.sh`.

1. **Environment.** Run `tools\run.cmd doctor --quick`. Red blocks the task: explain the fix in plain words and stop.
2. **One issue per session.** If this session already worked on another issue, suggest `/clear` or a new session
   first (§4.3).
3. **Read.** `gh issue view <n> --comments`. Read the latest handoff comment, the docs and ADRs it links, and the
   `CLAUDE.md` of every area the task touches. The issue's acceptance criteria are the definition of the task.
4. **Ownership.** List the paths the task will change and compare them with the ownership map in root `CLAUDE.md`.
   - Paths of the other owner: stop and ask the human before anything else.
   - Scenes (`.tscn`) the task edits: `gh pr list --state open --json number,author,files`. If another human's open
     PR changes one of them, stop: scenes are single-owner.
   - If the task touches `.tscn` or `.tres` files, remind the human now: Save All Scenes in Godot (Ctrl+Shift+Alt+S,
     «Зберегти всі сцени») and no hand edits while you work.
5. **Branch and board.** Run `tools\run.cmd start <n>`. It creates or resumes `<area>/<n>-<slug>` from `origin/main`,
   assigns the issue if nobody has it, and moves it to In progress.
   - Stacked on an open PR (the issue or the human names a parent task whose PR is not merged yet): run
     `start <n> --base <parent branch>`. It branches from `origin/<parent>` and records it, so `publish` and the PR
     use the parent as base. "origin has no branch": the parent is not pushed yet; ask the human. On a branch that
     already exists `--base` is ignored (it says so).
   - "uncommitted changes": show the human the list and ask one question: do these changes belong to this task
     (`--include`) or should they be put away (`--stash`)? Never discard them. Run `start` again with the answer.
     After `--stash`, tell the human the changes wait in the stash of the old branch (`git stash list`; switch back
     and `git stash pop` to get them).
   - "no area label": ask which area it is and run `start` again with `--area <x>`; add the label to the issue only
     if the human wants it.
   - Output line `WORKTREE <path>`: another Claude session is working on this checkout. Enter it with the
     EnterWorktree tool (`path`). If that tool is not available, tell the human to open a new session in that
     folder, and stop here.
   - "another Claude session is working on this checkout" (the designer, or `--here` not given): tell the human which
     session, and ask them to finish or close it. Only if they say it is idle, run `start` again with `--here`.
   - "checked out in the worktree <path>": enter that worktree (EnterWorktree) instead.
   - Unsure what `start` would do? `tools\run.cmd start <n> --dry-run` only fetches and says what it would do.
6. **Restate** in the human's chat language, briefly: the goal, the acceptance criteria, your plan, the verification
   commands you will run, and the risks. Non-trivial work: use plan mode and wait for "go" before editing. Small,
   obvious work ("just do it"): go ahead.

Finish with the `finish-task` skill ("finish", "заверши задачу").
