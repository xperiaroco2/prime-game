# 2026-09-28: Phase A research workflow ran unbounded

- **Who intervened:** the engineer.
- **Session:** the engineer's Claude session (Desktop, Opus 5.5), Phase A steps 3–4.

**What happened.**
- The agent ran two multi-agent workflows plus one more verifier:
  - `phase-a-research`: **27 agents, 66 min, 1,602 tool calls**;
  - `draft-review`: **4 agents, 15 min**;
  - one fresh verifier agent.
- Individual agents made 40–144 tool calls each.
- Together this used about **70% of the engineer's 5-hour plan limit**, as observed by the human.

Metrics are in `docs/history/2026-09-28-phase-a/agent-metrics.csv`.

**Why it happened.**
- The ultracode opt-in was on. Its guidance says to optimize for exhaustiveness and treat token cost as no
  constraint. The agent took that as license to scale up.
- The session's workflow size guideline was *medium* (under 10 agents). The agent **knowingly exceeded it** (27
  agents), because it judged ultracode to override it.
- The workflow prompts set **no explicit bounds**: no agent count cap, no per-agent turn or tool-call limit, no time or
  token budget. The per-claim adversarial verification design multiplied the work.
- The agent did not state a cost estimate or ask before launching.

**Rule adopted.**
1. **`workflowSizeGuideline` = `small`** (fewer than 5 agents) for this project. It goes in the shared
   `.claude/settings.json` when M0 creates it, and in the decided `AGENT_WORKFLOW.md` (effort policy, S8).
2. **Every workflow prompt states explicit bounds:**
   - the maximum number of agents;
   - the maximum turns or tool calls per agent;
   - a wall-clock or token budget;
   - what to drop first if the budget runs out.
3. Before launching any workflow, the agent tells the human the planned agent count and a rough cost, and waits for
   a yes. Exceeding the size guideline needs the human's explicit approval in that same message. "Ultracode" alone
   does not count.

**Where the rule lives now.**
- This entry.
- To be promoted into root `CLAUDE.md` (stop-and-ask list) and into `.claude/settings.json` during M0.

**Update (2026-09-28, decision session).** Rule 1 is applied: `workflowSizeGuideline: "small"` is in the shared
`.claude/settings.json`. Rules 1–3 are part of the decided `docs/AGENT_WORKFLOW.md` §7 and ADR
`docs/decisions/2026-09-28-effort-and-workflow-bounds.md`. Promotion into root `CLAUDE.md` remains an M0 task.
