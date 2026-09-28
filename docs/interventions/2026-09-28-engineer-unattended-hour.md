# 2026-09-28: The agent must be able to work unattended for an hour

- **Who intervened:** the engineer.
- **Session:** the engineer's Claude session (Desktop, Opus 5.5), Phase B (M0) kickoff.

**What happened.**
- The engineer ran the session in bypass permissions mode. The agent's first read-only checks (`gh api …/rulesets`,
  `gh project list`) still asked for approval, and one (`git config --get core.hooksPath`) was denied.
- The engineer asked why, and asked for the setup to be reworked so the agent can read status, create branches and
  commit on its own, and be left alone for an hour.

**Why it happened.**
- Phase A built a long ask list (77 rules) for safety. Explicit ask rules prompt in every mode, including bypass, so
  they cancelled the mode the engineer had chosen.
- Phase A never checked the list against the working pattern the engineer actually wants: long unattended runs.

**Rule adopted.**
1. Routine work (status reads, branches, commits, pushes of a task branch, issues and PRs, tooling edits) runs
   without prompts. Ask rules are kept only for real stop points: the agent's own permissions, dependencies,
   commands that discard work or rewrite history, deletions and settings on GitHub.
2. Before adding an ask or deny rule, check it against "can the agent still work alone for an hour?".

**Where the rule lives now.**
- `.claude/settings.json` and `docs/AGENT_WORKFLOW.md` §8.1.
- `docs/decisions/2026-09-28-unattended-work-permissions.md`.
- Root `CLAUDE.md`, "Stop and ask before" (rules 1 and 2, promoted in M0 stage 3).
