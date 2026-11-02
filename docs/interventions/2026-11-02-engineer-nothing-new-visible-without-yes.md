# 2026-11-02: Nothing new and visible is built without the engineer's yes

- **Who intervened:** the engineer.
- **Session:** his director session (Claude Code Desktop, `D:\prime-game`), relayed to the #1565 task session.

**What happened.**
- Playing the ship he found the engine finish's flames and light show (#1502, PR #1544), which he never asked for, and
  had them removed (#1563;
  [#507 comment 6573053399](https://github.com/xperiaroco2/prime-game/issues/507#issuecomment-6573053399)). The design
  rule from it: no moments that make players stop and watch; a task done is done
  ([#507 comment 6573108317](https://github.com/xperiaroco2/prime-game/issues/507#issuecomment-6573108317)).
- Asked how to change the standing word of
  [#507 comment 6547715071](https://github.com/xperiaroco2/prime-game/issues/507#issuecomment-6547715071) ("Taken for
  you": taste details taken by the recommendation and listed), he chose the recommendation, "new and visible only with
  my yes" ([#507 comment 6573070345](https://github.com/xperiaroco2/prime-game/issues/507#issuecomment-6573070345),
  the rule's record). It replaces that word from now.

**Why it happened.**
- The old word let a session take a taste choice by the recommendation, and a GDD line that names a thing ("a light
  show") read as a yes for building it. The session chose a look nobody had drawn or approved and listed it only
  afterwards.

**Rule adopted.**
1. Numbers and details inside something he approved, or that the GDD names explicitly (a timer, a size, a placement, a
   count, the wording of a prompt, which of the drafted options of an approved thing), still take the recommendation
   without waiting.
2. Anything new and visible (an effect, a prop, a look, a UI element, an animation) that the GDD and his words do not
   name explicitly is never built without his yes. Build the rest, leave it out or keep the plainest placeholder
   already in the game, and list it in the report with a picture, options and a recommendation.
3. A GDD line that names a thing without its look is not a yes for a look.
4. Looks drawn by an approved track's package (the UI track's tagged pack, an approved art package) are approved; what
   they do not draw waits.

**Where the rule lives now.**
- This entry (the one wording) and [#507 comment 6573070345](https://github.com/xperiaroco2/prime-game/issues/507#issuecomment-6573070345).
- The [trust ADR](../decisions/2026-10-04-trust-based-autonomy-gated-merge-into-main.md) (amendment 2026-11-02);
  root `CLAUDE.md` ("Stop and ask before"); `docs/HUMAN_SESSIONS.md`; `docs/MANAGERS.md` §3;
  `docs/AGENT_WORKFLOW.md` §7.2; the `director` skill (Limits).
- Not edited here: `docs/GDD.md` and `docs/design/` (the design track's PR #1564 records the "no ceremony" design
  rule), `docs/ARCHITECTURE.md` (#1563).
