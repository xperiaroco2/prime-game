# 2026-09-28: Check live state before stating facts about it

- **Who intervened:** the engineer.
- **Session:** the engineer's Claude session (Desktop, Opus 5.5), Phase A decision session (step 5).

**What happened.**
- In "next steps", the agent told the engineer to create the GitHub repo and planned an "initial push to an empty
  repo".
- The engineer pointed out that the session was already on that repo, with a branch and commits. `git remote -v`
  showed `origin = xperiaroco2/prime-game`, with `main` pushed, and the repo was already public.

**Why it happened.**
- The agent took "the repo does not exist yet" from the Phase A proposal, written hours earlier, and never ran
  `git remote -v` or checked GitHub in this session.

**Rule adopted.**
1. Before stating a fact about the environment (repo, remote, branches, installed tools, versions, settings), check it
   live with a read-only command. Archived docs describe the past.
2. When a doc and the live state disagree, trust the live state and fix the doc.

**Where the rule lives now.**
- This entry. To be promoted into root `CLAUDE.md` (hard rules, next to "never claim without running") in M0.
