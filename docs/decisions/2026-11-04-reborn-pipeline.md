# Reborn: releases, one line of work, taste only by the engineer

- **Status:** Accepted (the engineer, 2026-11-04, in the meta session's chat: "звучить супер [...] давай записуй")
- **Date:** 2026-11-04
- **Deciders:** the engineer; written by the meta session (#1578)
- **Overrides:** where `docs/AGENT_WORKFLOW.md` §7 (the orchestrator, the director, the tracks), the
  [weekly budget ADR](2026-10-05-weekly-budget-across-four-tracks.md) and the director skill disagree with this ADR,
  this ADR wins; they are not rewritten (the process is frozen, rule 6)

## Context
The first month (2026-09-28 to 2026-11-04), measured on main: 5,782 commits; 172, 261, 151, 87 and 104 merged PRs in
weeks 40 to 44; of the non-merge commits since 2026-10-05, 1,401 `docs`, 659 `feat`, 607 `test`, 489 `fix`;
`docs/ARCHITECTURE.md` at 10,178 lines and 59 ADRs; none of the 110 PRs merged since 2026-10-25 on a milestone.
`tools\run.cmd metrics --since 2026-10-05 --compact --no-gh --track design meta`: the meta track spent more than the
design track (50.7% against 35.6% of a week). What went well: the foundation (the host-authoritative netcode, voice,
the pure core, the bots and the leak test, CI), the lobby, and the ship built in Blender by Claude from the
engineer's blueprints.

What went wrong, in the engineer's words: too much ran in parallel for one person to follow (game, UI, art, design and
meta tracks, the director, managers, night shifts); he approved what he did not see; agents invented visible things
and took taste for him. Each cost a build and then a rework:
- The engine's finish got flames, a light show and a linger (2026-11-01) and lost them the next day (#1563).
- Car tuning's finishing show, never the engineer's idea (GDD §8).
- Hitting left the M8 slice: the 2026-10-31 standing word "let everything be done by the recommendations"
  ([#507 c6547715071](https://github.com/xperiaroco2/prime-game/issues/507#issuecomment-6547715071)) let the design
  session take "no hitting" from his "you can only take the crystal in your hands"
  ([#1035 c6549452793](https://github.com/xperiaroco2/prime-game/issues/1035#issuecomment-6549452793)); he meant the
  crystal is the only item.

## Decision
1. **Milestones are releases.** Each is a whole, playable match from the lobby to the End, with only finished parts:
   every feature card of the release works, tests and bots are green, nothing inside the release is a greybox (its
   look, sound and UI are final), friends played it, no known blocker, and a tagged build with a short changelog.
   After a release its parts change only by bug fixes. The releases and their order: `docs/ROADMAP.md`.
2. **A feature card before code.** A feature starts as an issue from the `feature-card` template: what the player
   sees and does, a picture, the numbers, and what is **not** in it. The engineer approves the card; agents build only
   what it says. Anything new, visible or not on the card, is a new card for him, never added quietly.
3. **One line of work.** One session runs the current release, with two or three tasks in flight at most. Art and UI
   are tasks inside the release, not tracks of their own. No night shifts by default; the director's shifts and the
   tracks are paused. Parallel sessions only on the engineer's word for that piece of work.
4. **Taste is only the engineer's.** Revoked: the standing word of 2026-10-31 for taste questions. No taste question
   is "taken for him": art, visuals, game and level design wait for his answer, batched once a week with pictures. A
   technical choice still takes the recommendation without a question (the
   [trust ADR](2026-10-04-trust-based-autonomy-gated-merge-into-main.md)'s tiers).
5. **Shown before merge.** A PR that changes what a player sees or hears carries `shot` screenshots or a clip and a
   list "what changed on screen"; it merges on the engineer's yes.
6. **The process is frozen.** No new process rule, ADR, skill or tool unless something actually broke; meta work stays
   at about 5% of a week. Docs shrink when touched; they do not grow.
7. **The budget.** The subscription is Max (5x Pro a week, with a 5-hour limit); Ultra (10x Pro a week, no 5-hour
   limit) only for a push the engineer asks for. The spend is read once a week.
8. **The rhythm.** A 15-minute weekly review with the engineer (done, next, the taste batch) and a short retrospective
   at the end of each release.

## Consequences
- Slower by the calendar, cheaper by the token: less rework, no cross-track coordination, less process.
- The game is aliens-only (the host sets 0 humans) until the humans' block after the planned releases: the
  cooperative race against the clock and one's own mistakes has to be fun on its own (GDD §1, "The party is hard on its
  own"). One trial match with humans in the middle (after the third location) checks the idea lives.
- The open issues are sorted into the releases, "later" or closed (the next step after this ADR); M7, M8.2 and M8.3
  close or move.
- The Steam store page ("Coming soon") opens only when every 1.0 mechanic is in the game; a technical release (Steam
  lobbies, settings, a stable build) comes before it.
