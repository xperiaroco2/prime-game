# 2026-10-01: The engineer's agent may act in the designer's area on an agreed change

- **Who intervened:** the engineer.
- **Session:** the M3 manager session (the engineer's Claude session, Desktop, Opus 5.5), during the vision revision
  (PR #127) and the M3 plan (#96). Recorded by issue #128.

**What happened.**
- The engineer and the designer now agree on the game's direction together (vision revision 1, PR #127), and the
  engineer also acts as a game designer and has more time for the project. The designer cannot always run an agent
  on his computer to commit what they agreed.
- The strict ownership rule (root `CLAUDE.md` "Ownership", `docs/AGENT_WORKFLOW.md` §9) said the designer's agent
  owns `docs/GDD.md`, `docs/design/`, `content/` and `levels/`, and the engineer's agent never redesigns content
  without the designer's approval in the PR. Agreed changes then waited for the designer's own session; the M3
  decisions D1 to D3 on #96 were already relayed by the engineer instead.
- On 2026-10-01 the engineer decided, in chat with the M3 manager session, read back and confirmed as option (a),
  permanent: "In the designer's area the engineer's agent works when the engineer says the change was agreed with
  the designer."

**Why it happened.**
- The split was written for two humans who each run their own agent on their own area. It had no path for a change
  both humans agreed on when only the engineer's agent is at hand, so the agreed work stalled on a missing session,
  not on a missing decision.

**Rule adopted.**
1. In the designer's area (`docs/GDD.md`, `docs/design/`, `content/`, `levels/`) the engineer's agent works when the
   engineer says the change was agreed with the designer.
2. The PR says "agreed with the designer, relayed by the engineer" and tags @SwiftySinister for a later look. The
   engineer merges it; the designer's approval before the merge is not required.
3. If the designer objects, a follow-up PR reverts the change.
4. A scene the designer has an open PR on is still never edited.
5. The designer keeps his area and his skills (`new-mechanic`, `new-level-piece`); without the engineer's word that
   a change was agreed, the engineer's agent still stops and asks before touching the area.

**Where the rule lives now.**
- This entry.
- Root `CLAUDE.md`, "Ownership" (the editor-reminder bullet was shortened to keep the budget).
- `docs/AGENT_WORKFLOW.md` §9, in full.
- `docs/decisions/2026-09-28-ownership-by-codeowners-and-convention.md` and
  `docs/decisions/2026-09-28-humans-merge-prs.md`, "Amended 2026-10-01".
- `.github/pull_request_template.md`, "Cross-area".
- `.claude/skills/finish-task/SKILL.md` step 6, `.claude/skills/start-task/SKILL.md` step 4 and
  `.claude/skills/onboard/SKILL.md` step 9.
