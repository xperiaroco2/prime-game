# 2026-10-03: Commands for the humans go straight into the chat

- **Who intervened:** the engineer.
- **Session:** the AI productivity manager session (the engineer's Claude session, Desktop, Opus 5.5), day 2 of the
  AI productivity track (#170). Recorded by issue #261.

**What happened.**
- The manager listed the engineer's steps after a wave: a one-time cleanup of the leftover `user://` folders that
  runner tests had left in the real app-data folder (PR #235), and the `worktree-done` housekeeping for merged tasks.
  It did not give the commands. It wrote "the command is in PR #235's body" and "see the comment on #170".
- The engineer asked to get the commands he has to run directly in the chat, each ready to run with one click: the
  desktop app runs a fenced shell block in his terminal. He does not want them hidden in PRs. The agent may still
  note them on PRs and issues for its own tracking. He chose "for the project".

**Why it happened.**
- The manager relayed a workflow's `human_steps` as a pointer to where the commands were written, instead of copying
  the commands into the chat. It treated "recorded on GitHub" as "handed to the human". For the engineer that meant
  opening a PR, finding the block, copying it by hand and checking which folder it runs in.
- The orchestrate-stage skill pointed the same way: §6 and §8 put the `worktree-done` lines in the wave comment on the
  plan issue, and §4 said nothing about how `human_steps` reach the human. The manager followed the skill where it
  should have followed the human.

**Rule adopted.**
1. Every command a human must run goes into the chat itself, never only into a PR, an issue or a comment. A PR or an
   issue may carry it too, for the record.
2. One command per fenced block, written for the human's shell (PowerShell on Windows), starting with `cd` to the
   absolute folder it runs in (rule 1 of `2026-09-29-engineer-commands-say-where.md`), so one click runs it.
3. Run the command yourself from that folder first, or preview it (`--dry-run` where the command has one, a read-only
   listing such as `git worktree list`) when running it would do the human's step for them or prompt.
4. The manager copies every command of a workflow's `human_steps` and every housekeeping command (`worktree-done`, a
   worktree or branch removal) into the chat this way. When a step only names where its command is ("the command in
   PR #235's body"), the manager fetches the command from there and copies it.

**Where the rule lives now.**
- This entry.
- Root `CLAUDE.md`, "Talking to the humans": the bullet "A command for a human …" was reworded in place, within the
  150-line launch budget.
- `.claude/skills/orchestrate-stage/SKILL.md` §4 "On each completion" and §8 "Notifications and housekeeping" (with
  an example block), and §6's wave-comment list ("also in the chat").
- `docs/AGENT_WORKFLOW.md` §7.1, "The human".
- `.claude/skills/finish-task/SKILL.md` step 8, "Tell the human": the `worktree-done` command as its own block.
- `.claude/workflows/issue-task.js` and `pr-rebase.js` (#266): every agent that publishes returns `human_steps` as
  `{why, command}` pairs, each command one PowerShell line starting with `cd <absolute folder>;`, run or previewed
  first; the orchestrate-stage skill §4 copies each command as is.
