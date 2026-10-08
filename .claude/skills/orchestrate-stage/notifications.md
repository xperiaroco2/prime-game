# Notifications and housekeeping (orchestrate-stage)

Part of the orchestrate-stage skill ([SKILL.md](SKILL.md)); read it when the human is needed and when a merged task's
worktree is due for cleanup.

## 8. Notifications and housekeeping
- When the human is needed (a refused merge, questions, a stop), end your turn with a short summary, the "For you:"
  block, and send a PushNotification. It is suppressed while the human is active in the session, and the desktop app
  only flashes its icon while its window is in use; a PowerShell toast tests whether Windows notifications work at all.
- The secretary reads your "For you:" block (AGENT_WORKFLOW §7.2): label alone, numbered, an English copy in wave notes.
- Merged tasks' worktrees: once the task's work is on `main` (`release/m<k>` merged into `main`, or the task's PR
  on the tooling track), run `tools\run.cmd worktree-done <n>` (from `D:\prime-game`) yourself when no live session
  sits in that worktree (no workflow of yours running there; a solo session's worktree is its owner's); a worktree
  whose branch never reached main but whose work did (merged into a parent) takes `--pushed` or says so. After the
  closing PR has merged, remove your `release-m<k>` worktree too (`git worktree remove .claude/worktrees/release-m<k>`
  and `git branch -D release/m<k>` from `D:\prime-game`). What you cannot run (it prompts, or a live session holds
  the folder, or the human must pull `D:\prime-game` with the editor saved) goes into the wave's "For you:" block.
- Every housekeeping command the human runs, like every command of `human_steps` (§4), goes into the chat when it is
  due, one fenced PowerShell block per command, starting with `cd D:\prime-game` (or the folder it runs in), for example:
  ```powershell
  cd D:\prime-game; tools\run.cmd worktree-done 42
  ```
  Where running it yourself would do the human's step or prompt, preview it instead (`git worktree list` shows the
  worktree is there; `--dry-run` where the command has one). The wave comment may list it too, never instead.
<!-- see docs/interventions/2026-10-03-engineer-commands-in-the-chat.md -->
