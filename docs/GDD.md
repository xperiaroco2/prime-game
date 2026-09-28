# Game Design Document

| | |
|---|---|
| **Owner** | The designer. The engineer's agent never fills in or changes design content here without the designer's approval. |
| **Status** | Skeleton (M0): sections and open questions only. Nothing below is decided; examples inside a question are prompts for the designer, not proposals. |
| **How it grows** | "нова механіка: …" → skill `new-mechanic` adds a section with its open questions and a `mechanic` issue. When this file gets long, systems move to `docs/design/<system>.md` and this file links to them. |
| **Constraints** | What the engine can express is the content API in `docs/ARCHITECTURE.md` §9. |

## 1. Vision (from the brief)

A multiplayer social deduction game in the spirit of Lockdown Protocol and Among Us: first-person 3D, stylized
low-poly, player-hosted matches for 4 to 10 players. Proximity voice chat is a core mechanic: who hears whom is
governed by game rules. The differentiator is a rich, varied set of mechanics: roles, abilities, items, sabotages,
task types and information tools.

Open questions:
- What is the one-sentence pitch in the designer's own words?
- Which feeling should a match leave: tension, comedy, detective work, chaos? In what proportion?
- What does this game do that Lockdown Protocol and Among Us do not?

## 2. Match setup

- How many players is the sweet spot inside 4–10, and does the setup scale with the count?
- How are teams and roles dealt, and how many of each per player count?
- How long is a match, and a round?
- Which settings can the host change in the lobby?

## 3. Core loop

The engine's phases are Lobby → RoleAssign → Roam → Meeting → Vote → Resolution → (Roam | End).
- What does each player do in Roam, and what pulls them back to a Meeting?
- What starts a Meeting: a found body, a button, an ability, a timer?
- What happens at Resolution: ejection, reveal, nothing?

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

- Who can speak and hear in a meeting, and for how long?
- Is voting open or secret, and when are votes revealed?
- Ties, skips, abstentions: what happens?

## 10. Win conditions

- What wins for each team, and can a neutral role win alone?
- What ends a match early (all tasks, all of one team dead, a sabotage timer)?

## 11. Proximity voice as a mechanic

The brief lists distance, walls, death, meetings, radios and role abilities as inputs.
- How far does a voice carry, and how much do walls muffle it?
- Can the dead hear the living, and can they talk to each other?
- Which abilities or items change who hears whom?

## 12. Information tools

- Which tools give players information (cameras, logs, vitals, trackers)?
- How reliable is each, and can it be faked?

## 13. Maps

- How many maps at first, how big, and for how many players?
- Which rooms and interactables does the first map need?

## 14. Art and audio direction

The brief sets stylized low-poly, readable and cheap to produce; CSG greyboxing and CC0 packs are fine.
- What is the reference look (a few games or images)?
- What must be readable at a glance: roles, items, dead bodies, open doors?
