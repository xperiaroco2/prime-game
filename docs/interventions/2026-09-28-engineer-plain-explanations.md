# 2026-09-28: Explain with a concrete scenario; ask about real habits first

- **Who intervened:** the engineer.
- **Session:** the engineer's Claude session (Desktop, Opus 5.5), Phase A decision session (step 5).

**What happened.**
- The agent presented D9 (the Godot editor next to the agent) in engine-internals terms: "reload from disk",
  "ignore external changes", runner refusals, guards. The engineer answered: "тут я не зрозумів нічого".
- The agent re-explained with a concrete scenario (the designer moves boxes in a scene while her agent adds a door to
  the same file). The engineer then said nobody edits by hand while an agent works, and asked whether the agent meant
  the engineer's own agent changing the designer's files.
- That one fact removed the need for any enforcement. The recommendation changed from runner-enforced close-first to
  a save-first convention.

**Why it happened.**
- The agent explained mechanisms before the problem, in jargon.
- The proposal designed enforcement against a working pattern (hand edits in the editor during an agent run) that
  nobody had confirmed the humans actually follow.
- It did not say whose agent and which machine the risk was about.

**Rule adopted.**
1. Explain a decision by starting from a concrete scenario of what goes wrong, in plain words. Give the options after
   that, and the jargon last.
2. Say which person, which agent and which machine each risk is about.
3. Before designing enforcement against a human behaviour, ask how the humans actually work.

**Where the rule lives now.**
- `docs/AGENT_WORKFLOW.md` §13 ("The agent explains choices plainly").
- `docs/decisions/2026-09-28-godot-editor-save-first-convention.md`.
- Root `CLAUDE.md`, "Talking to the humans" (promoted in M0 stage 3).
