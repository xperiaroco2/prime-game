# 2026-10-15: A design session thinks in the game's tone, read from the design compass

- **Who intervened:** the engineer.
- **Session:** the engineer's design session (Claude Code Desktop, Opus 5.5, effort high, bypass permissions mode),
  the "Game design" track, plan #1095, working on the ship's engine mechanic (#1033).

**What happened.**
- Asked for fun, organic ideas for the ship's engine, the session offered four detailed variants: starting the engine
  by hand-swinging a propeller as in old pilot films, a dacha moonshine still, pests in the engine and a sick living
  engine.
- The engineer: these are "grandpa" mechanics; his own car tuning task is a makeover show, which is fun; the game's
  references are adult animated sci-fi comedies and a comic shooter with talking weapons (named in the chat; private,
  see below), and none of the variants fits them. He asked the session to look at its own behaviour first: it does not
  catch the project's context the way he wants.
- Before that, the session had twice built the engine as a hidden number found by tests (a pump, then plants as fuel),
  which he found unclear and brute force.

**Why it happened.**
- The references were nowhere in the repo: GDD §1 says only "parody" and "cringe-fun"; the car tuning's reference was
  recorded as "a makeover-show reference, internal". A fresh session had no tone to work from.
- The session did not ask for the tone or check its ideas against the vision; it optimised for what the comments
  stressed (fair, not Lockdown Protocol, no guessing) and filled the missing tone with its own associations.
- It answered with long, finished variants and tables instead of short ideas for him to pick from.

**Rule adopted.**
1. A design session reads `docs/design/COMPASS.md` whole at its start and passes every idea through its tone test
   ("could this be a scene in one of the engineer's references?") before he sees it.
2. Ideas start as 5 to 8 one-liners, with no numbers or tables; he picks; only then is one expanded and its maths
   checked.
3. The references' names live only in the engineer's personal Claude memory, never in the repo, an issue, a PR or a
   workflow prompt (his word on #1095, comment 6199371817): the repo is public, and the M8 plan's carried-over rule
   keeps other works' names, designs and plots out of any brief, prompt or public text (#1039).
4. Game design is a track (`design`) with a manager session on the skill `design-manager`, which hands its context
   over to the next session.

**Where the rule lives now.**
- This entry.
- `docs/design/COMPASS.md` (§2 the tone and its test, §4 what went wrong before, §5 how an idea moves).
- `.claude/skills/design-manager/SKILL.md`; `docs/AGENT_WORKFLOW.md` §6 and §7.3; `docs/MANAGERS.md`;
  `.claude/skills/orchestrate-stage/budget.md`; root `CLAUDE.md` (Routing).
