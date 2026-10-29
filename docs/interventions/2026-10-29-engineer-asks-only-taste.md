# 2026-10-29: The engineer is asked only taste questions; technical choices take the recommendation

- **Who intervened:** the engineer.
- **Session:** his director session «Директор: ніч 29.10» (Claude Code Desktop, Opus 5.5, effort high, bypass
  permissions mode) in `D:\prime-game`, over every track's linked sub-sessions; relayed to the #1380 task session.

**What happened.**
- His sessions kept bringing him technical questions: meta, code, documentation and process choices, as "For you:"
  items, "Needs the engineer" items and approvals. At ~00:30 local he had already said small questions go by the
  recommendation for the night
  ([#507 comment 6482248863](https://github.com/xperiaroco2/prime-game/issues/507#issuecomment-6482248863)).
- On 2026-10-29 in the director's chat he made it standing and wider
  ([#507 comment 6495904155](https://github.com/xperiaroco2/prime-game/issues/507#issuecomment-6495904155)): merge
  all the meta, code and documentation questions; he is no expert there and fully trusts the AI with everything
  technical. Only the human, designer's questions of taste go to him: art, visuals, game design, level design.

**Why it happened.**
- The trust ADR's tier (c) "ask and wait" still held a technical item (model policy) and "the design's D items" as a
  whole, technical ones included, and no file said a technical choice is never asked. Sessions read any choice with
  options and a recommendation as his decision and put it in a "For you:" block or a "Needs the engineer" item,
  though the recommendation was the answer he would give.
- A "Needs the engineer" item blocks the gate until "Answered:", so a technical one could only wait for him.

**Rule adopted.**
1. Ask the engineer only the human, taste questions: art, visuals, game design (rules and content), level design,
   and a milestone's goal and go/no-go.
2. Every technical choice (code, engine, netcode, tooling, meta, docs, the agents' process, model policy) takes the
   recommended option, and its PR merges through the gate without asking him; a technical "Needs the engineer" item
   gets the standing word's "Answered:" line (the trust ADR's amendment).
3. Each such choice is listed in the report (a manager's plan-issue comment, a handoff, the director's shift report)
   with the option taken, so he can reverse it.
4. Unchanged, still his: how the humans work, a new dependency (its ADR), anything destructive, anything costing
   money beyond a track's weekly budget, and the gate's exceptions (an ADR added or changed, the permission and
   safety files, the content area's approval line).

**Where the rule lives now.**
- This entry.
- The [trust ADR](../decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md)'s decision tiers (its
  amendment of 2026-10-29).
- Root `CLAUDE.md` ("Stop and ask before", DoD item 5); `docs/HUMAN_SESSIONS.md` ("Talking to the humans");
  `docs/MANAGERS.md` §3; `docs/AGENT_WORKFLOW.md` §7.1, §7.2, §13 and the skills table; the `director` skill
  (Limits, the night report, merges, `digest.md`); `orchestrate-stage` (`SKILL.md`, reporting); `finish-task`
  (step 8, the solo session's merge).
