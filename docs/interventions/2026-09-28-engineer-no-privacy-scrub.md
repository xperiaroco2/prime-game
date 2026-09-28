# 2026-09-28: No privacy scrub for a hobby project

- **Who intervened:** the engineer.
- **Session:** the engineer's Claude session (Desktop, Opus 5.5), Phase A decision session (step 5).

**What happened.**
- After the engineer chose a public repo (D1), the agent planned a clean-up of the Phase A archive before the first
  push: the GitHub handle, the organization name and local Windows paths.
- The engineer corrected it: the game is a hobby project for the engineer and friends, and this kind of privacy and
  security work is not needed.

**Why it happened.**
- The proposal and the archive README had flagged these items as a privacy risk, calibrated for a higher-stakes
  project. The agent carried that framing forward without asking whether it mattered here.
- In the same session, the engineer also chose lighter options than the proposal's recommendations for ownership
  enforcement (D8) and the Godot editor (D9). The proposal as a whole leaned towards more enforcement than this
  project needs.

**Rule adopted.**
1. This is a hobby project. Protections exist to prevent accidents and lost work, not attackers.
2. Do not add privacy or security hardening (redaction, scrubbing, extra guards) unless a human asks for it.
3. Secrets (tokens, keys, passwords) are still never committed.

**Where the rule lives now.**
- `docs/AGENT_WORKFLOW.md` §1 ("Proportionate protection").
- `docs/decisions/2026-09-28-public-repo-on-github-free.md` (the archive is published as is).
- Root `CLAUDE.md`, "Hard rules" (promoted in M0 stage 3).
