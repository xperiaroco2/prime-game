# No Godot MCP server before M4

- **Status:** Accepted
- **Date:** 2026-09-29 (decided 2026-09-28, Phase A item S12; recorded at the end of M0)
- **Deciders:** the engineer (Phase A decision session: a tier 2 default, no veto recorded)

## Context
KICKOFF §8 asked whether a Godot MCP server adds enough over the CLI. Research in
`docs/history/2026-09-28-phase-a/research/godot_mcp.md`: MCP tools cannot run in CI; the headless servers drive one
Godot process at a time (the bot harness needs a host and several clients) and some use a bare `-d`, which hangs on
the first runtime error; editor-plugin servers add an addon, a localhost port and usually an eval tool, and the best
featured ones are paid and closed.

## Decision
No Godot MCP server in M0–M3. API facts come from `check`, the engine API dump `doctor` generates into
`tools/out/godot-api/4.7.2/`, and `docs.godotengine.org/en/4.7/`; visual checks from `shot`. Revisit at M4 if the bot
harness cannot drive a needed input or observation, or the designer's agent keeps needing live editor state. The
preferred M4 path is a debug-only in-game input and inspection autoload plus the bot harness; the fallback is a
runtime MCP scoped to one subagent.

## Alternatives
- An editor-plugin MCP now: an extra addon and port, and nothing CI can replay.
- A headless MCP now: one process at a time.

## Consequences
The GDScript LSP bridge and Context7 stay off too (AGENT_WORKFLOW §14).
