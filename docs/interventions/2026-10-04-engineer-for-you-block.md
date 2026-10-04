# 2026-10-04: Every manager message ends with a "For you:" block

- **Who intervened:** the engineer.
- **Session:** the AI productivity manager session (the engineer's Claude session, Desktop), 2026-10-04 ~23:20 UTC.
  Recorded on #300.

**What happened.**
- The manager's messages mixed what it had done, what was running and what the engineer had to do: merges to make,
  answers to give, and `worktree-done` and pull commands after each PR. The engineer lost track of which steps were
  his and which the agent's.

**Why it happened.**
- The orchestrate-stage skill said what to report (§6) and that commands go into the chat (§4, §8), but not where in
  a message the engineer's own steps go, nor how often housekeeping is asked of him. Each completion produced its
  own housekeeping lines.

**Rule adopted.**
1. Every message from the manager to the engineer ends with one short "For you:" block in the engineer's language,
   numbered, listing only what needs the engineer now (a merge the gate refused, a decision, a command), or "nothing"
   when nothing does. Everything else stays in the wave comment.
2. Housekeeping commands the engineer must run (a pull of the main checkout, a worktree a live session holds) are
   batched into that block once per wave, not after every PR.

**Where the rule lives now.**
- [Trust-based autonomy](../decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md), "Reporting".
- `.claude/skills/orchestrate-stage/SKILL.md` §4, §6 and §8.
- `docs/AGENT_WORKFLOW.md` §7.1, "The human".
