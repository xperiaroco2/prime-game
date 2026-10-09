# Game Design Document

| | |
|---|---|
| **Owner** | The engineer (#518; the designer is optional and may contribute through PRs to the engineer). Agents never fill in or change design content here without the engineer's word. |
| **Status** | Skeleton (M0): sections and open questions only. Nothing below is decided except §1's pillars, §3's base mode, §13's first map and what [vision revision 1](decisions/2026-10-01-vision-revision-1.md) settled in §9, §10, §11 and §14; examples inside a question are prompts for the designer, not proposals. |
| **How it grows** | "нова механіка: …" → skill `new-mechanic` adds a section with its open questions and a `mechanic` issue. When this file gets long, systems move to `docs/design/<system>.md` and this file links to them. |
| **Constraints** | What the engine can express is the content API in `docs/ARCHITECTURE.md` §9. |

## 1. Vision (from the brief)

A multiplayer social deduction game in the spirit of Lockdown Protocol and Among Us: first-person 3D, stylized
low-poly, player-hosted matches for 4 to 10 players. Proximity voice chat is a core mechanic: who hears whom is
governed by game rules. The differentiator is a rich, varied set of mechanics: roles, abilities, items, sabotages,
task types and information tools.

The brief's "social deduction game in the spirit of Lockdown Protocol and Among Us" predates the pillars below,
where deduction is not central: the designer rewords it with the pitch (open question below).

### Pillars
Decided in [vision revision 1](decisions/2026-10-01-vision-revision-1.md) (#126), from the meeting with the designer
on 2026-09-30, with the engineer's answers V1 to V13 to its review (agreed with the designer):
- **Fun from the first second.** The lobby, customization, gestures and proximity voice are fun before any match.
- **Deduction is not central.** Each side plays to its own goal. Roles are dealt privately, but the game does not
  rely on keeping them secret: knowing who a dissident is helps, it does not win, and a dissident may even say so
  himself. Everyone plays their role through actions, not through manipulation or lying (unlike Lockdown Protocol).
  What a dead player saw while spectating is fair game after the respawn.
- **Death does not take you out of the game, and killing is not a win.**
- **Action over long discussions.** Run, do tasks, outwit.
- **Cringe-fun vibe**, and an audience that is not only guys.
- **Macro skill over micro skill.** Simple mechanics, no aim-heavy mechanics: decisions, teamwork and communication
  win, and a player who never plays shooters has as much fun as anyone. One-shot kills exist only as rare moments that
  are hard to abuse: the dropped car now, maybe later a single-shot weapon that is very hard to get. The player
  respawns as usual (the ADR's amendment of 2026-10-08, #591).
- **Open knowledge.** The rules, how every mechanic works and the fixed places (the map, the task circles, the zones
  where items may appear) are known to everyone, dissidents included. Who the dissidents are is dealt privately, but
  it is not a secret the game protects. Where a moved item lies now is not shown: players find it by looking.

Open questions:
- What is the one-sentence pitch in the designer's own words?
- Which feeling should a match leave: tension, comedy, detective work, chaos? In what proportion? (Proposed as
  answered by the pillars: cringe-fun comedy and chaos, action over detective work; the designer confirms or
  rewrites it.)
- What does this game do that Lockdown Protocol and Among Us do not?

## 2. Match setup

- How many players is the sweet spot inside 4–10, and does the setup scale with the count?
- How are teams and roles dealt, and how many of each per player count?
- How long is a match, and a round?
- Which settings can the host change in the lobby?

## 3. Core loop

The phases come from the game mode, not from the engine: each mode lists its phases and the transitions between
them ([ADR](decisions/2026-09-29-game-modes-define-the-phases.md), `docs/ARCHITECTURE.md` §3). A new mode can add
phases without engine changes to the loop.

### Base mode (the MVP)
Lobby → Countdown → Loading → Pregame → Round → End → Lobby. Adopted by the designer in #38 from the provisional
[MVP rules](decisions/2026-09-29-mvp-rules.md), with their numbers as starting values to tune after the first playtest.
- **Lobby:** players join, walk and talk by proximity; the host changes the match settings; each player presses
  Ready.
- **Countdown:** 5 s once everyone is ready; anyone un-readying, joining or leaving cancels it. The settings are
  locked.
- **Loading:** everyone loads the map, with no voice. Then roles and the shared tasks are dealt, packages and knives
  are scattered and players are placed.
- **Pregame:** 3 s of a dark screen with the player's own role; nobody hears anybody, nobody moves. Then the
  match clock starts (the engineer, #213).
- **Round:** everyone works on the shared tasks (Delivery); the dissidents sabotage by hiding packages and run out
  the clock. A player at 0 health is knocked down, can be raised, and otherwise dies, spectates and respawns
  ([vision revision 1](decisions/2026-10-01-vision-revision-1.md)). The first win condition met ends it: every task
  done (the Engineers, id `crew`), every engineer has left the match (dissidents), time up with a task left
  (dissidents).
- **End:** a black screen that names only the winning side; the game is frozen and nobody hears anybody. The host
  returns everyone to the lobby.

The base mode has no meetings and no votes.

### Later modes
- Meetings mode (#35): dropped by [vision revision 1](decisions/2026-10-01-vision-revision-1.md), since deduction
  is not central.
- Deathmatch: parked.

Open questions:
- Without meetings, what makes the crew suspect someone during a Round, and what can they do about it?

## 4. Roles

- Which roles exist in the first playable version, and which come later?
- What does each role know at the start, and what can it learn?
- How are roles revealed, if ever?

## 5. Abilities

- Which abilities are active (used on purpose) and which passive?
- How are they limited: cooldowns, charges, conditions, phases?
- Who learns that an ability was used, and when?

## 6. Items

- How are items found or given, and can they be traded or stolen?
- Which items affect voice (for example radios, which the brief mentions)?

## 7. Sabotages

- Who can sabotage, how is it fixed, and what does the crew lose if it is not?
- Can sabotages affect voice, vision or movement?

## 8. Tasks

- What kinds of tasks exist (short, long, shared, fake-able)?
- Are tasks a win condition, an information source, or both?
- How does a task look in first-person 3D?

## 9. Meetings and voting

Dropped by [vision revision 1](decisions/2026-10-01-vision-revision-1.md): no game mode has meetings. The questions
below stay only as history.

- Who can speak and hear in a meeting, and for how long?
- Is voting open or secret, and when are votes revealed?
- Ties, skips, abstentions: what happens?

## 10. Win conditions

Answered for the base mode by [vision revision 1](decisions/2026-10-01-vision-revision-1.md): the Engineers win only
by finishing every task before the timer ends; the dissidents win when the timer ends with a task left, or when every
engineer has left the match. Killing never wins, and a downed or dead engineer still counts as present.

- What wins for each team, and can a neutral role win alone? (The neutral role is still open.)
- What ends a match early (all tasks, all of one team dead, a sabotage timer)? (Answered above.)

## 11. Proximity voice as a mechanic

The brief lists distance, walls, death, meetings, radios and role abilities as inputs. Death is answered by
[vision revision 1](decisions/2026-10-01-vision-revision-1.md): nobody hears a downed or dead player, under any rule;
a downed player hears the living from where they lie; the dead hear no voice, only the world sounds around the player
they watch and lift music. There are no meetings.
- How far does a voice carry, and how much do walls muffle it?
- Can the dead hear the living, and can they talk to each other? (Answered above: no and no.)
- Which abilities or items change who hears whom?

## 12. Information tools

- Which tools give players information (cameras, logs, vitals, trackers)?
- How reliable is each, and can it be faked?

## 13. Maps

The first map is [House](design/house-map.md) (decided by the engineer on 2026-10-08, #591): a country house with a
yard on an 80 x 60 m plot, for 4 to 10 players, on four levels (basement, ground floor with the yard, second floor,
attic and roof), laid out for the five task chains. Its sizes and positions are a working draft until a greybox
playtest.

- How many maps in all, and do later maps keep the same scale and player count?

## 14. Art and audio direction

The brief sets stylized low-poly, readable and cheap to produce; CSG greyboxing and CC0 packs are fine.
- What is the reference look (a few games or images)?
- What must be readable at a glance: roles, items, dead bodies, open doors? Under
  [vision revision 1](decisions/2026-10-01-vision-revision-1.md) everyone sees a downed player, a body (it stays until
  its player respawns), the item in a player's hand and the one on their belt, and a player's few seconds of
  invulnerability, so each must read at a glance; how they look is open.

## 15. Tutorial

[`docs/design/tutorial.md`](design/tutorial.md) (#552, proposed): an offline solo session in a room of its own,
the UI track's nine lessons, and its open points (D25 to D36) for the engineer.
