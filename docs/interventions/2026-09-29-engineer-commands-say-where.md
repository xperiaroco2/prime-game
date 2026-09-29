# 2026-09-29: A command for a human says where to run it

- **Who intervened:** the engineer.
- **Session:** the engineer's Claude session (Desktop, Opus 5.5), task #14 (M1 walk spike), in the worktree
  `D:\prime-game\.claude\worktrees\14`.

**What happened.**
- The agent asked the engineer to play the spike with
  `powershell -ExecutionPolicy Bypass -File spike\walk\launch.ps1`, a path relative to the project root.
- The engineer ran it in `D:\prime-game`, the main checkout, which was on another branch (`docs/7-wrapup`).
  PowerShell answered that `spike\walk\launch.ps1` does not exist.
- The engineer said the agent keeps giving commands that do not work, and asked to remember this.
- With the right folder, the same command then stopped with "Set GODOT_BIN". Those variables come from the `env`
  block of `~/.claude/settings.json`, which only Claude sessions get; the engineer's own PowerShell has none.
  The launcher now reads them from that file when they are missing.

**Why it happened.**
- The agent had run every command itself from its own worktree, so the relative path worked for it. It never said
  that the task's files existed only in that worktree, and not in the checkout the engineer's terminal was in.
- "Works for me" was taken as "works for the human": the agent did not check the command from the human's side,
  neither the folder nor the environment its own session inherits.

**Rule adopted.**
1. A command for a human to run starts with `cd` to the absolute folder it must run in. When you work in a worktree,
   that is the worktree (`D:\prime-game\.claude\worktrees\<n>`): the human's terminal is usually in the main checkout,
   often on another branch.
2. Write it for the human's shell (PowerShell on Windows) and run it yourself from that folder before handing it over,
   in a shell without the variables `~/.claude/settings.json` gives only Claude sessions (`GODOT_BIN`,
   `GODOT_GUI_BIN`): a script the human runs must find its tools without them.

**Where the rule lives now.**
- This entry.
- Root `CLAUDE.md`, "Talking to the humans".
- Committed on the #14 spike branch (`client/14-m1-spike-first-person-capsules-walking`) at the engineer's request;
  that branch is not merged as a whole, so this commit goes to `main` on its own.
