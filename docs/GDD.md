# Game Design Document

| | |
|---|---|
| **Owner** | The engineer, the project lead and the game designer (#518, #1073; the designer is optional and may contribute through PRs to the engineer). Agents never fill in or change design content here without the engineer's word. |
| **Status** | Decided rules beside open questions (2026-10-13, #925). Decided: §1's pillars, §3's base mode, what [vision revision 1](decisions/2026-10-01-vision-revision-1.md) settled in §9, §10, §11 and §14, and each rule whose section cites the engineer's word (§3's knockdown and crouch, §8's task types, §13's House, §15's tutorial). The rest are open questions; examples inside a question are prompts for the engineer, not proposals. (Was, at M0: "Skeleton (M0): sections and open questions only.") |
| **How it grows** | "нова механіка: …" → skill `new-mechanic` adds a section with its open questions and a `mechanic` issue. When this file gets long, systems move to `docs/design/<system>.md` and this file links to them. |
| **Constraints** | What the engine can express is the content API in `docs/ARCHITECTURE.md` §9. |

## 1. Vision (from the brief)

A multiplayer social deduction game in the spirit of Lockdown Protocol and Among Us: first-person 3D, stylized
low-poly, player-hosted matches for 4 to 10 players. Proximity voice chat is a core mechanic: who hears whom is
governed by game rules. The differentiator is a rich, varied set of mechanics: roles, abilities, items, sabotages,
task types and information tools.

The brief's "social deduction game in the spirit of Lockdown Protocol and Among Us" predates the pillars below,
where deduction is not central: the engineer reworded it with the pitch.

**Pitch** (the engineer, 2026-10-15, #1076): *aliens throw the best party on Earth, but disguised humans who hate
their party hide among them, and it all turns into chaos.* Working title: **My Alien Prime Friends**.

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
- **Never boring** (the engineer, 2026-10-15, #1076). A player never waits long and never loses interest: a mistake
  costs a short time out of play, then he is back in it. Fast and arcade, full of crazy moments; never the hour-long
  sit of Mafia.
- **Randomness is part of the fun** (#1076). Lucky breaks and funny fails make the stories, and randomness always
  leaves a chance to react: a random respawn may land you next to everyone, then a few seconds of invulnerability let
  you run, a chase starts and you may find a weapon on the way and fight back, so it is fun even if they get you.
- **The party is hard on its own** (the engineer, 2026-10-15, #1093). The aliens' tasks are a real challenge: aliens
  who understand nothing and make many mistakes lose even without any humans. The humans only help the chaos along and
  hide in the noise of honest mistakes, so a spoiled burger can always be just a mistake.
- **Full of references, as parody** (#1076). Nods and easter eggs that players recognise from the games and shows
  they love, done as parody and allusion; never another work's names, logos, characters or assets. How games do it
  and where the legal line runs is open research.
- **Cringe-fun vibe**, and an audience that is not only guys. Teens and adults (15 and 16 year olds included): an
  adult, funny tone in which violence stays comic, with no guts and no dismemberment (the engineer, 2026-10-15,
  #1076). How to think in this tone, with a test for every idea: [the design compass](design/COMPASS.md) (#1120).
- **Macro skill first, and skill may matter a little.** Decisions, teamwork and communication win more often than aim:
  two players who are not into shooters can run the tasks and manage everything, or rush a shooter with knives from
  two sides, and a death costs only time because the player respawns. Aim is allowed to matter for those who want it:
  guns come mostly for points and have limited ammunition, and the host's settings set how many weapons a match has. One-shot kills exist only as rare moments that are hard to abuse: the dropped car now, maybe later
  a single-shot weapon that is very hard to get (the ADR's amendment of 2026-10-08, #591; amended by the engineer,
  2026-10-15, #1090).
- **Open knowledge.** The rules, how every mechanic works and the fixed places (the map, the task circles, the zones
  where items may appear) are known to everyone, dissidents included. Who the dissidents are is dealt privately, but
  it is not a secret the game protects. Where a moved item lies now is not shown: players find it by looking.

Open questions:
- What is the one-sentence pitch in the engineer's own words? (Answered above, 2026-10-15.)
- Which feeling should a match leave: tension, comedy, detective work, chaos? In what proportion? (Proposed as
  answered by the pillars: cringe-fun comedy and chaos, action over detective work; the engineer confirms or
  rewrites it.)
- What does this game do that Lockdown Protocol and Among Us do not?

## 2. Match setup

The M8 match (the aliens' party, the humans, points, the neighbours' anger and the cops, capsules, the wins):
[`design/m8-match.md`](design/m8-match.md).

- How many players is the sweet spot inside 4–10, and does the setup scale with the count?
- How are teams and roles dealt, and how many of each per player count?
- How long is a match, and a round? An average match lasts **about 10 minutes**; the respawn wait stays **30 s**
  ([vision revision 1](decisions/2026-10-01-vision-revision-1.md)), both tuned by playtest (the engineer, 2026-10-15,
  #1076: in 30 s the others can finish about one task).
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
- **Round:** everyone works on the shared tasks (the House's task types: §8); the dissidents spoil them deniably and
  run out the clock (in the MVP nothing that matters can be hidden: §8, the rule of 2026-10-20). A player at 0 health is knocked down, can be raised, and otherwise dies, spectates and respawns
  ([vision revision 1](decisions/2026-10-01-vision-revision-1.md)). The first win condition met ends it: every task
  done (the Engineers, id `crew`), every engineer has left the match (dissidents), time up with a task left
  (dissidents).
- **End:** a black screen that names only the winning side; the game is frozen and nobody hears anybody. The host
  returns everyone to the lobby.

The base mode has no meetings and no votes.

### The knockdown (#728)
Decided by the engineer on 2026-10-10 (#728, his answer A): the knockdown of
[vision revision 1](decisions/2026-10-01-vision-revision-1.md) stays (0 health knocks a player down; another player
raises it by holding E; otherwise it dies when its time runs out or when it gives up, then spectates and respawns),
with three changes:
- **Still:** a knocked-down player cannot move; there is no crawl and no separate "wounded" state.
- **Mute:** it hears, but cannot speak: nobody hears it, under any rule (as before).
- **A ragdoll:** the body falls as a rigid body, with no animation. On the House only (below), a hit can send it
  flying, and it rolls or slides off whatever slope, roof or stairs it lands on. Everyone sees it in the same place:
  the host's physics moves the body, and each screen draws its own ragdoll there.

His answers to the [knockdown ADR](decisions/2026-10-10-knockdown-reworked.md) (PR #754, comments 6097876326 and
6100602989, the same day, and 6108669765, 6109457234 and 6110171062 on 2026-10-11):
- Only the blow that knocks a player down sends its body flying, away from the attacker; every weapon's blow has a
  launch, the knife's too.
- The body is a real rigid body with normal physics, run by the host: a blow launches it, and it rolls or slides off
  any slope, roof or stairs by itself. There is no separate slide rule (the ADR's KD10).
- A body still flying or rolling cannot be raised.
- A knocked-down player hears the living near its body, as before, and its camera stays above its body, following it.
- A dead body stays a ragdoll, greyed, with the cross; a raised player gets up at once (crouched where only a
  crouching player fits, below).
- A death in mid-flight ends the motion: the body and its items rest where it stopped.
- **The launch plays on the House only.** On the flat greybox a knocked-down body lies still where it fell, as a
  ragdoll, with no launch.
- The numbers (how hard a blow launches, when a moving body counts as resting) are placeholders, "not a decision",
  until a playtest.
- The body has a crouching player's collider, so it comes to rest only where a crouching player fits (it does not
  roll under a low table); a raised player gets up crouched there and stands up by the crouch's rules once there is
  room (the ADR's KD11).
- A blow never launches a body where no player can reach it to raise it: the levels keep every surface a launch can
  reach, tables and the roof included, within a raise's reach of a spot a player can walk to, the same convention as
  for a thrown item, checked on the House by tests (the ADR's KD12).
- Tables keep the space under them: a body may rest under a table a crouching player fits under, as long as a raise
  can reach it, and no level rule closes tables (the ADR's KD14).
- A player raised from a body launched into the lowered car gets up inside the car on its own screen, and its own
  game pushes it out, the car's accepted quirk; nothing new is built for it but a test of that push, which brings
  the question back to him if the host keeps correcting the player into the car (the ADR's KD15).
- The body keeps the crouching collider upright and never turns: the body the host moves slides and falls but does
  not roll, and slides off only a steep slope; the ragdoll on each screen rolls (the ADR's KD13). "Rolls" above is
  the ragdoll on screen.

### Later modes
- Meetings mode (#35): dropped by [vision revision 1](decisions/2026-10-01-vision-revision-1.md), since deduction
  is not central.
- Deathmatch: parked.

Open questions:
- Without meetings, what makes the crew suspect someone during a Round, and what can they do about it?

### Movement: the crouch (#727)
Decided by the engineer (#727, 2026-10-10): every player can crouch by holding Ctrl, and Shift while crouched moves
a bit faster. A crouched player is lower, so it passes under things a standing one does not: the raised car in the
garage, under which the fitter works crouched (car repair, #688). The art has or will have a crouch animation. A
knocked-down player cannot crouch: since 728a (#846) it cannot move at all, it only looks around.

His answers to the crouch design (PR #752, comments 6097878317 and 6098097098; the options and the reasons are in the
[crouch ADR](decisions/2026-10-10-crouch.md)):
- ~~The crouch plays on the House only. The flat greybox has no crouch. (The lobby, a level of its own, has none
  either: the design's reading of "the House only" (KE10), not a separate answer.)~~ Changed by the engineer on
  2026-10-14 (#989, #991): the crouch plays everywhere, the lobby, the tutorial, the House and the greybox:
  movement basics are never blocked anywhere.
- A crouching player's steps are quieter and slower (KD1). Since 2026-10-14 (#989, #991) only the crouch walk's
  steps are quiet; the fast crouch (Shift while crouched) sounds like a walk.
- No name plates over any player, standing or crouching (KD2); their removal is #756.
- The raised car's height alone asks for the crouch, and no rule checks it (KD3; car repair's RD1 too).
- Letting go of Ctrl under a low ceiling keeps the player crouched; it stands by itself once there is room (KD4).
- Shift while crouched spends stamina as the sprint does (KD5).
- A jump while crouched stands the player up, then jumps (KD6).
- A crouched player is a smaller target for the knife and for a thrown item (KD7).
- A crouched player can do everything a standing one can (KD8).

The numbers are placeholders, "not a decision": crouched 1.2 m tall with the eyes at 1.0 m (standing: 1.8 m and
1.6 m), 2.0 m/s, and 2.8 m/s with Shift (the walk: 4.5 m/s); a crouch walk's step 6 dB quieter and heard within 6 m
(a walk's: 12 m).

Open question:
- After a jump from the crouch with Ctrl still held, does the player crouch again on landing (recommended), or only
  at a fresh press of Ctrl?

### Movement: the sneak (#989)
The engineer's mechanic (#989, 2026-10-14). Engine parts: the sneak state
[#990](https://github.com/xperiaroco2/prime-game/issues/990); the crouch and its quiet step everywhere, the quiet step
only at the crouch walk's speed [#991](https://github.com/xperiaroco2/prime-game/issues/991). Record: the crouch
ADR's amendments of 2026-10-14 (`docs/decisions/2026-10-10-crouch.md`).

Intent: a player can sneak up on others: hold a key and walk slower, and nobody hears the steps. Movement basics
(walk, run, crouch, sneak) work everywhere, the lobby included.

Rules:
- Hold left Alt to sneak (hold, like the crouch's Ctrl). Release: a normal walk.
- Speed: the same as the crouch walk's (one value for both).
- Sound: a sneaking player's steps are silent for everyone. The crouch walk stays a little audible (its quiet step);
  the fast crouch (Shift while crouched) sounds like a walk.
- A state of its own, standing height: sneaking and crouching never combine. Ctrl + Alt: the crouch wins (crouched,
  a little audible). Shift + Alt: Shift wins (a normal sprint, audible, with its stamina).
- Everywhere: the sneak and the crouch play in the lobby, the tutorial, the House and the greybox; no per-map option.

Hidden information: nothing hidden beyond sound. Others see a sneaking player where they would see any player; a
silent step is decided on each listener's client, as every step is.

Edge cases:
- A modified client that claims the sneak while it walks at full speed is heard as a walker: a step is silent only
  when the relayed sneak state is set and the step's speed is at or below the crouch walk's (plus the footstep jitter
  margin).
- Downed, dead and ghosts: as today (no sneak while downed; a ghost's steps as today).

Numbers (placeholders, "not a decision"): the sneak's speed is the crouch walk's (2.0 m/s); the quiet step's top
speed is the crouch walk's; the silent step's jitter margin is 0.2 m/s (an engine tolerance).

Keys: `sneak` on left Alt. It becomes a Controls row once the deck has `control.sneak` (the UI track, #150); lesson
1's key row lists it then.

Open questions, for the engineer (built as today until he answers):
- Does a sneaking player look different to others (only the slower walk, or a pose)?
- A jump while sneaking: does the landing make a sound?
- Carrying an item while sneaking: any change?

## 4. Roles

- Which roles exist in the first playable version, and which come later?
- What does each role know at the start, and what can it learn?
- How are roles revealed, if ever?

## 5. Abilities

- Which abilities are active (used on purpose) and which passive?
- How are they limited: cooldowns, charges, conditions, phases?
- Who learns that an ability was used, and when?

## 6. Items

### The hand and the belt (2026-10-21)
- A player has one hand and **two belt slots** (the engineer, 2026-10-21,
  [#1040 c6315467567](https://github.com/xperiaroco2/prime-game/issues/1040#issuecomment-6315467567); the rule:
  [c6315451657](https://github.com/xperiaroco2/prime-game/issues/1040#issuecomment-6315451657)). It replaces the belt
  of one: a player carries up to three one-handed items, task items and others alike.
- A two-handed item fills the hands and never goes onto the belt, so a bulky thing (a story item, a weapon) is always
  seen in the hands and nothing serious can be stashed.
- A take with an item in the hand puts the hand item into a free belt slot; with both slots full (full hands: an item
  in the hand and two on the belt), the hand item drops at the player's feet. Every "the belt" below means a free
  belt slot, and "the belt is full" both slots taken.
- **Drawing from the belt** (decided by the engineer on 2026-10-21,
  [#1040 c6320249563](https://github.com/xperiaroco2/prime-game/issues/1040#issuecomment-6320249563)): the hand and
  the two belt slots are three places, 1, 2 and 3; an item keeps its place, and the key picks which one is in the
  hand, the rest hang on the belt.
  - Keys 1, 2 and 3 draw that place's item; the mouse wheel steps through the three; X goes back to the item held
    last. An empty place is an empty hand.
  - A take goes into the place in the hand when it is empty, else into a free place, and comes into the hand (the
    rule above, unchanged).
  - With a two-handed item, 1, 2, 3 or the wheel put it down at the feet and draw the belt item: no refusal, a
    visible action.
  - The draw is instant and seen by everyone: the item changes in the hand and leaves the belt. On screen, three
    numbered icons, the one in the hand lit.
- Consumables (a medkit, an energy drink) and rare two-handed gadgets come after the MVP (#1040).

### Open
- How are items found or given, and can they be traded or stolen?
- Which items affect voice (for example radios, which the brief mentions)?
- Throwing a held item (#37): how strong and how far; which items; does a thrown item hurt or stop a player it meets;
  does a thrown package count when it lands in its circle; may an item land where nobody can reach it; does a throw
  cost anything; which key; can a flying item be caught; does it bounce or stop where it hits; does a running throw
  go farther; where does an item thrown off the map end up; does a downed player stop it? The options and a
  recommendation for each are in the [throwing ADR](decisions/2026-10-09-throwing-held-items.md) (TD1 to TD12), for
  the engineer.

## 7. Sabotages

- Who can sabotage, how is it fixed, and what does the crew lose if it is not?
- Can sabotages affect voice, vision or movement?

**The blackout (the MVP; the engineer, 2026-10-20, [#1033 comment 6294249388](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6294249388)).**
A light breaker in the security room (the house's basement, [estate-map](design/estate-map.md) §6) cuts the estate's
lights: the lanterns and the buildings go dark, the camera wall goes dark, and sight in the night drops sharply (the
prototype used 40% of the normal distance). The bonfire burns on and the ship keeps its own power. Anyone may throw
the breaker either way; fixing it means getting back to it. It is the humans' tool against the aliens' talk and sight
(m8-match §9). Numbers are placeholders for the greybox.

## 8. Tasks

- What kinds of tasks exist (short, long, shared, fake-able)?
- Are tasks a win condition, an information source, or both?
- How does a task look in first-person 3D?

**The base mode's task list** (`content/modes/base_mode.tres` and the task types' `maps`; #1088, after the M7 task
chains #676): the mode lists six task types. On the House, the map players always play, it deals Delivery (#683),
the Generator (#800), Photography (#784), Cooking (#775) and Repairing the car (#810). On the greybox, a test bench
only, it deals the colour-matched Delivery alone. The lobby's `tasks` is 5 (1 to 5), the number of different task
types a match deals, drawn at random from the map's types; the host may ban types with `banned_task_types`. The zone
task is not in the mode's list (see below).

**The MVP's task set** (decided by the engineer on 2026-10-20, #1144; his words on #1033, comments
[6286836993](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6286836993) to
[6289345766](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6289345766)): five task types, the
car tuning, the ship's engine, Cooking (reworked below), Photo (as a pose silhouette, #1102) and the Wi-Fi. Delivery,
the Generator and Car repair leave the MVP; their M7 rules stay below for the record. The base mode's data and code
follow in engineering issues. Every number in the new sections is a placeholder for the playtest.

**The rule: nothing can be hidden that cannot be made again** ([#1033 c6287031697](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6287031697),
in his words [#1095 c6289528171](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6289528171); the
compass §3). Every core part is printed, grown or taken from a pool; none exists once on the map, and nothing hidden is
found by highlighting. Parts come from 3D printers (a print takes about 5 s, and it is a sight: the part visibly
grows), grow in the greenhouse, or come from an endless pool. Hiding something costs only time. The reason: the map has many floors, passages and undergrounds
([#1035 c6238063024](https://github.com/xperiaroco2/prime-game/issues/1035#issuecomment-6238063024)), so a hidden key
item would be found too late.

### The flowers (the greenhouse, 2026-10-20)
- Five flowers in five colours grow in the greenhouse. A flower's colour is fixed: it makes the car's paint. Every
  match gives each flower a random icon, shown on it: the burger's order names the icon
  ([#1033 c6287630697](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6287630697)).
- Picking a flower starts its regrowth (about 1 to 2 min); watering it with a can filled at the well speeds it up and
  keeps flowers from being spammed ([#1033 c6198904911](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6198904911),
  [c6238062666](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6238062666)). Anyone, a human too,
  may pick a grown flower and throw it away: it regrows.
- They feed two mechanics: the car's paint and the burgers. The engine takes none (removed 2026-10-20, maybe later).

### The battery (out of the MVP, 2026-10-23)
The engineer dropped it from the MVP ([#1033 c6360412989](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6360412989)):
it was one more step at the end of two long tasks with no point of its own. The ship's engine starts from the
console's start button; the car comes alive on its last green card. A battery may come back later as a scarce
resource with competing uses (prime-game-design `ideas/NOTEBOOK.md`). Its rules of 2026-10-20, for the record:
- Printed empty on its own small printer in the laboratory (about 5 s).
- Charged somewhere else, in a microwave turned charger (the kitchen or another room: the level design decides):
  about 10 to 15 s, a ding, then 3 s to take it out; left longer, it bursts with a bang and flies out across the room
  empty, knocking down whoever is near ([#1033 c6212542349](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6212542349)).
- One level: charged or not. No slow, careful carrying
  ([#1033 c6210643508](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6210643508)).
- The same battery serves both machines: it starts the ship's engine and goes into the car last
  ([#1033 c6288900379](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6288900379)).

### Car tuning (2026-10-20)
A makeover show by aliens (the engineer's concept,
[#1033 c6287031697](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6287031697) and
[c6288572652](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6288572652)): a relaxed task of
handwork, little hassle. It replaces Car repair (#688).
- A board in the garage holds the order: cards, each a part and a colour ("a blue spoiler", "red rims"). The deal
  decides how many cards.
- For each card: pick a flower of that colour in the greenhouse; print the part on the big, wide parts printer in the
  laboratory; carry both to the paint mixer in the pantry, which scans the flower and gives paint of its colour, and
  paint the part; carry it to the garage and screw it on. Partners split it: "you make the paint, I print the part".
- The garage's tools hang on cables: they work anywhere inside the garage and drop from the hand when its holder
  steps out, so nothing to hide. A tool is dangerous: a soldering iron in hand can kill.
- The right colour lights its card green. A wrong one is unscrewed, thrown away and done again.
- Every card green: the car comes alive in a show (neon, bass, the crowd); no battery since 2026-10-23 (above). The
  task is done. A match without this task shows the car already tuned, as decoration.
- **The humans' spoils:** the wrong shade ("I thought that was blue"); being slow; painting someone's fresh print the
  wrong colour; screwing on a wrong part so it must come off again.

### The ship's engine (2026-10-20)
The engineer's spin-up ([#1033 c6235144451](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6235144451),
for the MVP [c6288572652](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6288572652) to
[c6288973914](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6288973914)): a demanding task where
the expert knows every fix by heart.
- **The start:** the start button on the console in the hall (no battery since 2026-10-23, above). Everything
  happens inside the ship, a wide manta with two mirrored halves: two vents in the throat behind the mouth, the hall with the console and four cartridge sockets, a
  breaker board in each corridor, a charger in each lens room ([estate-map](design/estate-map.md) §5a).
- **Solo or together** (the engineer, 2026-10-22, [#1033 c6336844073](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6336844073)):
  one player can start the ship alone, slowly, running back and forth (a running mutation helps); two take a half
  each and fix both sides at once. The ship gives a lot of points (#1040; the number later).
- **No difficulty scaling** (same comment): the engine is the same in every match, whatever the number of players;
  a host only puts the ship on the map or leaves it off.
- **The spin-up, made readable** (the engineer, 2026-10-25,
  [#1095 c6392050112](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6392050112), on the lead's
  proposal [c6391965295](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6391965295): a player who
  walks in must see what to do):
  - **The ship calls:** while the engine is off, the turbines on the console's hologram pulse orange with a soft beep
    every few seconds, and the start button glows.
  - **The charge:** pressed, the hologram's turbines spin and the console's three stage strips fill one after another
    as one charging bar, each a stage (placeholder: about 30 s each, 90 s with no problems); the same bar runs as a
    ring round the hologram's central disc, seen from the throat and both corridors.
  - **The wiring:** on the hologram each station is a point in its place (the four sockets, the two boards with their
    eight lamps, the two vents), with a line of light to the turbines. A station with a problem blinks red, its line
    goes dark and the turbines slow; fixed, the line flashes back. The point shows where, not what: no icon per kind,
    the players go and find out.
  - **The countdown:** over the hologram, a big countdown to the nearest problem's own timer; with several open, the
    one that blows first, its point blinking fastest. There is no timer for the whole start.
- **Stages:** 3. Each stage spawns problems, their kinds random, their count fixed: 2, then 4, then 6, each at a
  random moment spread across the stage (2026-10-25, above), not all at its start. Any open problem stops the
  charging bar until it is fixed; a stage passes when its third of the bar is full.
- **A problem** is seen and heard (a red lamp, a rising wail, its point on the hologram) and has its own timer
  (placeholders: an overheat 10 s, the breakers 30 s, a cartridge 30 s).
- **Overheat** (reaction; the vent as agreed 2026-10-23,
  [#1095 c6361136868](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6361136868); built as the
  ray's gills in the throat's wall, four ribs that rock ±4° and never open, so light, colour and mist carry the states:
  the engineer, 2026-10-27, prime-game-art#263 comment 6453520596 and
  [#1095 c6453612034](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6453612034)): calm, the ribs
  rock slowly like breathing and the slots pulse soft cyan; a problem makes them shudder fast, the slots go red, steam
  rises and the lamp lights. Hold a palm on its scanner (a four-fingered hand): the ribs go still, the red in the slots
  turns cyan in six clicked steps and a marker climbs a light bar; let go inside the green band and all four ribs swing
  out together, the slots at their brightest cyan, mist from every slot: the exhale, fixed. Too early: a sound, try
  again. Past the green, a release coughs steam (a miss); held to the very top, a hard red shudder, the vent coughs and
  throws the player back across the throat, up again by themselves in about 2 s (no raising).
- **A spent cartridge** (multitasking): the cartridge is an energy crystal (the engineer, 2026-10-23,
  [#1033 c6361383461](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6361383461)); spent, it goes
  plain grey. Pull it out of one of the hall's four sockets (two a side, the engineer, 2026-10-22: more places to burn;
  the problem count per stage stays), carry it to the charger in the lens room on its side (8 to 9 m) and put it in
  its one slot; press, and the charger's two inner prongs orbit it in lightning for 10 s (placeholder), then it
  shines and waits until someone takes it,
  so the player can fix something else meanwhile; then take it back and fit it. With both sockets of a side spent,
  the second crystal waits for that charger or runs across the hall to the other one. There are no spare crystals to
  spam.
  - **The crystal never leaves the ship**, so it cannot be hidden (the engineer, 2026-10-27,
    [#1095 c6440586671](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6440586671), the how
    [c6441939778](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6441939778)): carried past the
    mouth onto the ramp, it slips from the hand and rolls back into the throat, as the garage's tools drop when their
    holder steps out of the garage. Charging it in the laboratory was raised and dropped the same day: a much longer
    path, and the crystal could be hidden on the way.
- **Tripped breakers** (memory; the engineer, 2026-10-21, [#1095 c6325852316](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6325852316)
  to [c6326100307](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6326100307); two boards,
  2026-10-22, [#1033 c6336844073](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6336844073); a
  concept until the playtest): a breaker board in each corridor, both with the same four big breakers, red, yellow,
  green and blue, a lamp of its colour over each, eight in all. A problem trips some of them, easy first and harder
  later (placeholders: 2 on one board, then 4 with one change of side, then 6 alternating sides); they pop out and
  smoke.
  - **The order** shows in the hall, on the start console's hologram of the ship (fixed to the ship's axes, so its left
    wing is the left corridor): four lamps on each wing, one per breaker, which glow faintly when theirs trip
    ([#1095 c6360765037](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6360765037)). While breakers
    are tripped it plays the order by itself,
    with a sound: it lights them up brightly one by one in the order to switch them back on, each with its side (green left, blue
    right, red left, red right), each with a beep, then a pause, then again (no button, no lever: the engineer,
    2026-10-23, [#1095 c6359703396](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6359703396)).
    Remember it, or a friend at the console reads it out by voice.
  - **The chain:** a breaker switched on ramps up, its lamp from yellow to green; the next one goes on while that lamp
    is green. Too late, and the previous breaker trips again. The green lasts long enough for one player to run
    across the hall to the other board; two players, one at each board, call the order to each other.
  - **A short circuit** (a wrong breaker, or one switched too early) zaps the player at the board into a knockdown,
    raised by someone; the tripped breakers stay tripped.
- **A fail:** a problem whose timer runs out fails the stage. A blast through the whole ship knocks down everyone
  aboard: raised by someone (a team may leave one player outside for that), or dead and respawned in 30 s. The engine
  drops one stage (the bar loses that third); a fail on stage 1 restarts stage 1.
- **The end:** the last stage passed, the ship roars, flame bursts from its nozzles, a light show over the party. The
  task is done.
- **The humans' spoils:** being slow, letting go outside the band, claiming a problem and not going, reading out a
  wrong order at the console (the friend at the board is knocked down: raise them, "I mixed it up", or run away
  laughing), switching a wrong breaker on purpose, letting a timer run out on purpose (the blast names nobody, and the whole crew then knows whom to suspect: the engineer's "fun
  outing moment"), claiming a station while its line stays dark, calling the wrong point on the hologram ("the back left
  one's out!" when it is the front right).

### The Wi-Fi (2026-10-20)
The engineer's library cipher of 2026-10-15 (`design/ideas/2026-10-15-brainstorm-2.md`), made the party's Wi-Fi
([#1033 c6289149236](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6289149236) to
[c6289345766](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6289345766)).
- The guests demand Wi-Fi. The lord's router is paranoid: it writes passwords only in alien glyphs and changes the
  password after every connection.
- A computer in the security room shows a password of 4 glyphs and a keypad of the digits 0 to 9.
- A static decoder book in the library (it cannot be carried off): ten pages, one per digit, each with its three
  glyphs. Every match deals the 30 glyphs to the digits anew.
- The house phone: one in each of the two rooms, on one line. While both receivers are held, the two players hear
  each other at any distance; the line distorts the voices, and at times its quality drops ("I didn't hear, repeat").
  One describes a glyph ("a snail with horns"), the other finds it in the book and calls the digit.
- A right password switches the Wi-Fi on with a show (the guests' phones light up, a cheer) and the router shows the
  next one. The task is done after N passwords, a lobby setting.
- A wrong password: the router shrieks "HACKER" and locks the keypad for about 5 s; the password stays.
- Solo is possible by memory, or by a screenshot: the player's own business. The task is made for a group.
- **The humans' spoils:** calling a wrong digit, "the line crackled", hanging up mid-password, locking the router
  with a wrong code on purpose.
- **Engine part:** voice through a station (two receivers bridge two players' voices); today voice is proximity only.

### Delivery (#683)
**Out of the MVP** (the engineer, 2026-10-20, [#1033 c6287322692](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6287322692)):
"removed for now, until something cool comes to mind"; its items exist once and hiding them is its sabotage, against
the rule above. The M7 rules below stay for the record.


The base mode's first task type ([MVP rules](decisions/2026-09-29-mvp-rules.md), Tasks; `docs/ARCHITECTURE.md`
§9.5.4), reworked by the engineer on 2026-10-10 (#683 and its comments; his answers on PR #713, comments
[6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718) and
[6100696677](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6100696677), where he approved the
design): on the House it no longer goes by colours. The engine parts are in
[the Delivery by meaning ADR](decisions/2026-10-10-delivery-by-meaning.md). On main: D2a and D3a (#827, #829); D1 to
D5 are open.

**Intent.** Carrying things around the house to where they belong. Storage holds different items, and each kind has
its own place that fits what it is. Players tell the items and their places apart by meaning, not by colour.

**Rules** (the engineer's; DD1 to DD8 of the ADR):
- Storage holds different items; each kind is carried to its own place, chosen by what it is; nothing goes by colour.
- Four kinds, one per drop-off of the [House map](design/house-map.md)'s §6: the wine to the dining table, the motor
  oil to the garage's workbench, the garden gnome to the garden, the parasol to the terrace table. The gnome, the
  parasol and the name "Motor oil" were drafted by the agents and approved by the engineer as drafted (comment
  6100696677; the ADR's §5.1).
- How many: the host's `packages` setting. The round's items are spread over the places, so every place gets one
  before any gets a second; with fewer items than places, which places get one is drawn each round.
- An item counts when it rests inside its place: a cylinder standing on the floor at the table, the bench or the
  garden spot, so on the floor around it or on its top.
- A player tells where an item goes by meaning alone: its look, and its name in the hand slot. Nothing points to the
  place: no marker through walls (the one over a package's circle goes too), no line on the HUD, no sign.
- An item at a wrong place: nothing happens, and anyone may pick it up again.
- Every item takes both hands. A carrier who takes a one-handed item (a knife from the floor, say) puts it onto the
  belt and keeps the carried item in the hands (the engineer's rule for every take, PR #701); picking up a second
  Delivery item swaps the two, as today.
- Any kind starts on any storage spot.
- The task screen shows Delivery's row with its own count of delivered items, struck through once every item is
  delivered; no shared total of all tasks, on the HUD or the task screen (#738).
- Unchanged ([MVP rules](decisions/2026-09-29-mvp-rules.md), #79): one shared task that nobody owns; one item is one
  subtask; any living player carries and delivers any item; an item counts when it rests at its place, however it got
  there (put down, swapped, dropped at a death or a leave, thrown); a delivered item is locked; the dissidents
  sabotage by hiding items.
- On House, storage is the hub ([House map](design/house-map.md) §2, decision 5).

**Hidden information.** None: everyone may know which kind goes where, where each item started and every delivery.
Where a moved item lies now is not shown: players find it by looking.

**Edge cases.** A knocked-out player and a dead player deliver nothing; an item dropped at a body counts if it rests at
its place. The host's own player follows the same rules as everyone.

**Numbers:** the host's `packages` setting, 1 to 10, default 6; a place's radius 1 m (a circle's, the engineer's in
#79) and height 2 m (a placeholder, "not a decision").

**Name and description.** The name "Delivery" and the lobby label "Packages (Delivery)" stay. The description,
drafted by the agents and approved by the engineer as drafted (comment 6100696677): "Carry each item from storage to
the place where it belongs. Every item takes both hands."

**Where it plays.** On the House only (the engineer's DD9 (c), comment 6100696677, through
[#767](https://github.com/xperiaroco2/prime-game/issues/767): the flat greybox becomes a test bench only, and players
always play the House). The greybox keeps today's colour-matched Delivery (a package to the circle of its colour) as
far as its bot scenarios and the information-leak test need it, and gets no drop-offs. Bots do not play the House
([ARCHITECTURE](ARCHITECTURE.md) §9.7), so Delivery by meaning is tested without bots: unit tests, integration tests
on the House and a test over the wire codec.

**Engine parts** ([the Delivery by meaning ADR](decisions/2026-10-10-delivery-by-meaning.md) §1, §8): a second
Delivery task type beside today's, each listing the one map it plays on; one item kind per kind of item; one station
kind per place, on its own marker on the House; a list in its data saying which kind goes to which place; no colours
in its rules or on the screen; House gets one marker per place and loses its circles. The issues follow from the ADR's
split, for M7.

Open questions: none. The engineer answered every one on 2026-10-10 and 2026-10-11 (the ADR's §5 and §10).

### Photo (#687)
**In the MVP: poses from a wheel on a big lawn** (the engineer, 2026-10-15 and 2026-10-25, #1102: the base
[c6193792541](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6193792541), the direction
[c6392026180](https://github.com/xperiaroco2/prime-game/issues/1102#issuecomment-6392026180), the design accepted
[c6392116478](https://github.com/xperiaroco2/prime-game/issues/1102#issuecomment-6392116478); the full design in the
design repo's `ideas/2026-10-25-photo-design.md`). It replaces the M7 film chain below: no films, no printer, no
board. Designed as the release version (emotes and a reveal screen are built for it). Where the M7 rules say
otherwise, this part wins; every number is a placeholder.

- **The photo lawn.** The camera stands on its tripod and never turns; in front of it a wide open lawn, about 2 to
  14 m deep in the frame, where guests and players pass through. Where it stands and what the frame holds is the
  level design's (his word: the creek and a footbridge in the frame, the ship at most far in the background, and the
  lawn out of earshot of the ship's tasks, §11).
- **The pose wheel, everywhere in the game.** Holding a key opens a wheel of two rings, legs and arms; a pick of one of
  each puts the character in that whole pose, made by an animator so every pair looks good. Legs (6): stand, on one
  leg, squat, on one knee, lunge, sit on the ground. Arms (8): hands on hips, arms out like a plane, flex, a heart, a
  finger to the sky, hands behind the head, palms to the camera, a salute. The pose holds while the player stands,
  turning on the spot keeps it, a step drops it. Arms alone were rejected as not photogenic. The engineer kept all
  14 as drawn on the chameleon (2026-10-26, [#1102 c6412817038](https://github.com/xperiaroco2/prime-game/issues/1102#issuecomment-6412817038);
  the sheets in the design repo's `ideas/pose-sheet/`).
- **The silhouettes' starting list of pairs** (kept the same day): one leg + plane; side lunge + finger to the sky; on
  one knee + heart; squat + flex; sitting on the ground + hands behind the head; standing + hands on hips. More pairs
  may join the list after the playtest.
- **The silhouette.** Only the photographer sees it, in the viewfinder: an outline of a random photogenic pose (from a
  list of good pairs), a facing (to the camera, the left side, the right side, the back), a random place in the frame
  and a random size (small means far from the camera, big means near). Each photo draws a new one.
- **Two players.** The photographer uses the camera and enters the viewfinder; the model runs out onto the lawn; the
  photographer guides by voice to the place, the distance, the facing and the pose. The viewfinder shows the model
  over the outline and tints the part that is off (legs, arms or facing) without saying which way to fix it. When all
  match, the outline turns green and a lamp on the camera lights green for everyone around; a shot then counts, with a
  flash, and the next silhouette appears.
- **The shutter works at any time:** only a green shot counts; the others are fail frames, kept for the reveal.
- **Alone, slower.** The photographer starts a self-timer (about 10 s), runs out and poses from memory, without the
  viewfinder; a match when the timer fires counts, a miss is a fail frame. This replaces the M7 rule that nobody can
  photograph himself.
- **The match's last photo is a group:** two silhouettes at once, in different places and poses, for two models or
  one model and the photographer on the timer; each part locks green once matched, so nobody waits frozen.
- **Who is in the shot.** Everyone behind the model is in the photo (copying the pose is welcome); only a body between
  the camera and the model turns the outline red, and anyone can push it away. Anyone can step to the camera and take
  the viewfinder: the camera has no owner.
- **The reveal.** A big photo-frame screen at the bonfire: each counted photo flies onto it for a few seconds with the
  pair's fail frames beside it; between photos it plays the match's slideshow.
- **Hidden information.** The host decides a match from the players' poses, facings and places, never from a picture;
  the outline is the photographer's alone; the lamp and the reveal are public. The task row on the map screen (M)
  shows the photos counted of N.
- **The humans' spoils**, all looking like honest fumbles: the photographer says "back" for "forward", left from his
  own side, the wrong half of a pose; the model picks the wrong half or steps out of the pose just before green;
  anyone walks in front of the lens or takes the camera "to help".
- **Points:** a counted photo is a shared step, a point to the photographer and to each model in it (m8-match §4).
- **Numbers** (placeholders): photos a match from m8-match §6a2; a match within about 1 m and 30°; the timer 10 s.
- **Kept ideas, not rules yet:** the people in each photo growing over the match (1, 2, then 3), and a results screen
  at the match's end with the group photo ([#1102 c6392134933](https://github.com/xperiaroco2/prime-game/issues/1102#issuecomment-6392134933),
  [#1040 c6392135150](https://github.com/xperiaroco2/prime-game/issues/1040#issuecomment-6392135150)).

**The M7 film chain** (for the record; it leaves the MVP). The House map's photo chain ([House map](design/house-map.md) §2, decision 7; its stations in §6). The rules below
are the engineer's (#687, chat of 2026-10-10, and his answers of 2026-10-10 to the design's questions,
[PR #704, comments 6095444907](https://github.com/xperiaroco2/prime-game/pull/704#issuecomment-6095444907) and
[6096344994](https://github.com/xperiaroco2/prime-game/pull/704#issuecomment-6096344994)); the engine parts are in
[the photo task ADR](decisions/2026-10-10-photo-task.md).

**Intent.** "For now the simplest possible thing": one player stands at the photo spot, another takes the shot with a
flash; the photo travels to be printed and is hung in the darkroom, and it counts only if a person is really in it.
Closer to a real photography process where it helps. Later, not now: special poses or gestures the photo must show.

**Rules.**
- The photo is a task type, like the others. One hung photo with a person in it is one subtask; the host sets how
  many in the lobby settings (every task type has such a setting, #256).
- The camera stands on a tripod in the photo zone (the gazebo, north-west), facing the photo spot; it never turns. It
  takes two: one player stands on the spot, another uses the camera. Using the camera enters a viewfinder view: the
  player looks through it and sees the frame; a press takes the shot, with a flash.
- The camera takes a film loaded into it; the film is not carried by the shooter while shooting. A film has 5 frames,
  and the frames left are shown on the camera. The players shoot the frames, then take the film out by holding E over
  the camera (for now); it may be taken out before every frame is used, and then only the frames shot are printed. A
  film is one-way: once a frame on it is shot, it never goes back into the camera, and the printer uses it up.
- New films come from a box in storage, without limit. At the round's start one film lies at the photo zone.
- The path: the film is carried to the computer and printer in the study (the second floor), where one use prints
  every frame shot on it, at once; a printed photo is carried to the darkroom (the basement) and hung on its board.
- A printed photo is an item held in the hand that shows exactly what the camera saw at the moment of the shot. A
  film and a photo each take one hand: a player can hold one in the hand and two on the belt (§6).
- Who counts as a person in the photo: any living player whose head is in the frame and in the camera's sight,
  anywhere in the frame, whatever the role. Nobody standing within the camera's reach (where it can be used) is in
  the photo, neither counted nor drawn, so another player is always needed (the engineer: "you cannot photograph
  yourself: you look through the frame, and the frame must hold a player"). A knocked-down player does not count. One
  player may be in several photos, and several players in one.
- A hung photo counts only if a person is really in it, and then it stays on the board for good. One without a person
  counts nothing and can be taken down and carried away.
- Once the task is done, the camera, the printer and the board no longer work; the box still gives films.
- Tasks are shared, and only living players do subtasks (#79); a dissident plays the same character under the same
  rules (#679).
- Busy hands, as for the Generator, but every take still works, as in the burger chain (#682). A player holding a
  two-handed item (a package) can take a film from the box, the film out of the camera, a photo off the printer's tray
  or the board, or a film or a photo from the floor: the new item goes onto the belt; if the belt is full, its item
  drops at the player's feet; the two-handed item stays in the hands. What is not a take is refused while the hands
  are busy: loading the camera, a shot, a print, a hang. Taking a film from the box with full hands (an item in the
  hand and two on the belt) puts the hand item down at the player's feet, and the film goes into the hand.

**Where it plays.** On the House only, the map being built for the chains, in the base mode, in every match, as the
Generator. The flat greybox, the bots' test map, gets no photo task and none of the House's chains: it keeps what it
deals today (the engineer's read-back answer on the Generator,
[PR #695, comment 6096108206](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096108206)). All the
new mechanics come with M7 on the House, and bots playing them comes later, with the map.

**Hidden information.** Whether a person is in a photo is decided by the host from where everyone stood at the moment
of the shot, never from a player's picture. A photo shows its picture to whoever sees it; whether it counted
everyone learns once it is hung, from the photo task's row on the map screen (M): the photos counted of N, struck
through once every photo is counted. There is no shared total of every task's subtasks, in the HUD or on the map
screen ([#738](https://github.com/xperiaroco2/prime-game/issues/738)). Nobody is told who took a shot: players see it
only by looking at the gazebo. Nothing shows through a wall.

**Numbers** (the engineer's starting values, to tune): 5 frames a film. Placeholders until he sets them: 1 to 5 photos,
3 by default; the camera's view 50° high, 4:3, counting people up to 10 m; a player uses a station from within 2 m;
one take from the box per player every 0.25 s, as the burger chain's sources.

**Name and description** (drafts the engineer took as written, PR #704's comment 6096344994; the ADR's §6.1; the
content files stay provisional until he approves their PR): the task "Photography"; the lobby setting "Photos
(Photography)"; on the task screen, "Load a film into the camera, photograph a player on the spot, print the film,
and hang the photos on the board: each one with a person in it counts."; the items "Film" and "Photo".

**Engine parts** ([the photo task ADR](decisions/2026-10-10-photo-task.md) §1, §9): a photo task type with five
station kinds (the camera, the photo spot, the box of films, the printer, the board), all but the photo spot used
through the Generator's `Interact(station)` (the spot is only where the subject stands), listing House as the one map
it plays on; the film taken out of the camera by an ordinary pick-up; the host's check of who is in the frame (the
camera's view and a sight line from its lens); each client draws a shot's picture from where the host says everyone
stood; film and photo items, the box giving films as the burger chain's sources give their items; station scenes in
`levels/stations/` in place of the House's markers; the client's viewfinder, the frames counter on the camera, the
flash and the photos. Tested without bots: unit tests, integration tests on the House and a test over the real wire.
The issues follow from the ADR's split.

Open questions: none. The engineer answered every one on 2026-10-10 (the ADR's §6).

### Zone task (#36)
**Out of the base mode** (2026-10-11, #837; the engineer's answer on
[#842](https://github.com/xperiaroco2/prime-game/pull/842#issuecomment-6110558513)): the base mode lists no zone task
(its House task types are in "The base mode's task list" above; its `tasks` was 1 (1 to 1) then, and is 5 (1 to 5)
now), so the ZD8 line below is history. The code, its tests (on fixture modes) and the House's
zones stay; the task may come back with a name and a how-to card, by his word.

A second task type from #36: stand in a zone for N seconds. Tasks are shared and only living players do subtasks
(#79; [vision revision 1](decisions/2026-10-01-vision-revision-1.md), V4), so the downed never count, and the dead
have no avatar (there are no ghosts). The engineer took every recommendation of [the zone task
ADR](decisions/2026-10-09-m7-zone-task.md) (#302, comment 6085059719) and gave its starting numbers (comment
6085251071); all are provisional, for the first playtest, and live in data:
- The time is earned by standing in the zone, with no key (ZD1 (a)).
- Leaving pauses the zone: it keeps its time (ZD2 (a)).
- Several players share a zone, and it fills no faster with more of them (ZD4 (a)).
- Any living player counts, a dissident too (ZD3 (a)).
- Each subtask is one zone, every zone open from the start (ZD5 (a)).
- Everyone sees each zone fill as it fills (ZD6 (a)), on a look of its own, not the delivery circle's, with no
  marker through walls (ZD11 (b)).
- Only where living players stand matters: a hit that does not knock down, carrying or using stops nothing; a
  knockdown does (ZD9 (a)).
- History (ZD8 (a)): every match was to deal both Delivery and the zone task, the lobby's `tasks` 2 (1 to 2); the
  host could ban one type and lower `tasks` to 1. Since 2026-10-11 the base mode deals no zone task, "only from the mode, now"
  ([the engineer's answer on #842](https://github.com/xperiaroco2/prime-game/pull/842#issuecomment-6110558513)):
  its code, its tests on fixture modes and the House's zones stay, and it may come back by his word.
- The numbers (ZD7): 10 s in a zone (data, not a lobby setting), radius 1.5 m, height 2.5 m, one zone per subtask
  (the base mode deals 1 zone: a placeholder, "not a decision", #649), yellow; the task's name and the players'
  word "Hold the zone" (Ukrainian UI: «Утримати зону»), described "Stand in the zone until it fills."
- Where zones stand (ZD10 (a)): on the House map alone, three provisional points (#651) until the engineer moves
  them; the task's data lists the House alone in its maps. The greybox's placeholder zones (#649) are gone, with
  their three bot scenarios (GD13 (b) of the Generator ADR, the engineer's, #804).

### Cooking (#682)
The House map's burger chain ([House map](design/house-map.md) §2, decision 6; its stations in §6). The rules below
are the engineer's (#682, chat of 2026-10-10, his answers on #682, and his answers to the design's questions on
[PR #701](https://github.com/xperiaroco2/prime-game/pull/701#issuecomment-6095326743), the last four in
[comments 6096108400](https://github.com/xperiaroco2/prime-game/pull/701#issuecomment-6096108400),
[6096140448](https://github.com/xperiaroco2/prime-game/pull/701#issuecomment-6096140448) and
[6096157421](https://github.com/xperiaroco2/prime-game/pull/701#issuecomment-6096157421)); the engine parts are in
[the cooking ADR](decisions/2026-10-10-cooking-task.md). Its core is on main (C1 to C4, C9 to C11); C5 to C8 are open.

**Changed for the MVP** (the engineer, 2026-10-20, [#1033 c6287322692](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6287322692)
and [c6287630697](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6287630697)), under the rule
"nothing can be hidden that cannot be made again" (§8): the boxes give way to **a food printer in the pantry** (the old storage):
choose the bun or the patty and its kind, about 5 s, take it. **The herbs are the greenhouse's five flowers:** the
order shows a flower's icon, and every match gives each flower a random icon, shown on the flower itself, so the herb
board and the herb beds go. A box can no longer be hidden. Where the rules below say otherwise, this paragraph wins.

**Intent.** More in the spirit of Overcooked than of LOCKDOWN Protocol's containers. Orders hang on a board in the
kitchen; buns and patties come from storage in the basement; the patties are fried on the grill in the chill zone at
the far south-west corner of the yard and carried back (the long meat run is intended); the herb is picked in the
greenhouse, where a board decodes the order's herb icon.

**Rules.**
- Cooking is a task type, like Delivery and the Generator. One burger (one order) is one subtask; the host sets the
  count in the lobby settings (every task type has its own subtask count, #256). Default: 1; at most 3, tuned in the
  playtest.
- Every order hangs on the kitchen's order board from the round's start. It shows the bun and the patty as pictures,
  and the herb as an icon that only the greenhouse's herb board decodes; the icon-to-herb mapping is new each round.
  Each place in the kitchen carries a number, and the board lists the orders by place number. Two orders may ask for
  the same kind. The orders show only on the board; the task screen's Cooking row shows the burgers done of N, struck
  through once every burger is done (there is no shared total of all tasks, #738).
- Kinds: 3 buns (white, sesame, and dark, rye-like), 3 patties (light, a bit redder, and redder still) and 5 herbs.
  The patties are not named after animals: they are told apart by look, so a player may read them as vegetarian.
- Each ingredient is a separate item in the hand: a bun, a patty or a herb takes one hand, and the belt holds two,
  like any one-handed item (§6).
- Boxes: one per kind, 3 bun boxes and 3 patty boxes, starting in storage. A box is a two-handed item that gives its
  ingredient wherever it stands, storage included: one per tap of E, without limit, to anyone; holding E picks the box
  up. A player may take a patty straight from storage, or carry the box to the kitchen so nobody steals it (worth it
  when several orders need the same kind). (A future idea, not a rule: the engineer may later move another action to
  F.)
- The herb beds: a player presses E at a bed and gets one herb in the hand, without limit, and may then do anything
  with it. The herbs are shuffled among the beds each round.
- Busy hands, as for the Generator, but every take still works. A player holding a two-handed item (a box, a
  package) can take: an ingredient from a box, a herb from a bed, the patty off the grill, an item from the floor. The
  new item goes onto the belt; if the belt is full, its item drops at the player's feet; the two-handed item stays in
  the hands. What is not a take is refused while the hands are busy: putting something onto a plate or the grill,
  using a station that gives no item, a hit. (The engineer's reason: the rule does for the player the routine of
  putting the box down, swapping and picking it up again.) Picking up a second two-handed item still swaps it with
  the one in the hands, since the belt holds only a one-handed item.
- Taking with full hands (an item in the hand and two on the belt) puts the hand item down at the player's feet, and
  the new one goes into the hand. This holds at the boxes, the beds and the grill.
- An ingredient left lying vanishes after a while. Spamming takes is fine: nothing in the rules stops players covering
  the map in buns. (A short technical wait between one player's takes only guards the host against a flooding client;
  it is not a game rule.)
- The grill takes one patty at a time. A patty put on it fries for 10 s; then there are 5 s to take it off; left
  longer it burns: black and unusable. A fried patty stays fried. Only a raw patty goes on; one taken off early is
  still raw and starts again from 0; E at a busy grill takes the patty off; a burnt patty stays until someone takes it
  off.
- Assembly on a plate: each order has its own place in the kitchen with a plate already standing on it, not carried.
  A player with an ingredient in the hand presses E on the plate and the ingredient goes on it (a patty on a bun goes
  into the bun). The order of the layers does not matter. Only E puts an ingredient on: one put down or dropped near
  the plate lies on the floor.
- Nothing is checked on the plate (the engineer's answers on #1101, 2026-10-15). A plate has a slot for a bun, one
  for a patty and one for a herb: any bun, fried patty or herb goes on its free slot and stays there; a second one
  for a filled slot is refused, and so are a raw or burnt patty and anything that is no ingredient. The plate shows
  only which slots are filled, never right or wrong.
- E on a full plate takes the burger: one item in one hand, drawn with its bun, patty and herb. The cook carries it
  to the kitchen's order board and serves it with E there; only then is it checked against its place's order. A
  right burger is done; a wrong one is thrown away and made again whole, and the cook learns only "wrong", not
  which part: he works it out from the burger and the order, and the herb, shown on the order only as its icon, is
  the part to look up on the greenhouse's board. A burger left lying vanishes like an ingredient.
- Sabotage: a dissident may take a box and hide it; the others must search for it (the same play as hiding a
  package). Beyond that, the rules above already let anyone take items, burn a patty, put a wrong ingredient on a
  plate or take a burger and serve it wrong.
- A dissident plays the same character as an engineer (role `crew`), under the same rules, and only living players
  do subtasks (#79; vision revision 1, V4).
- Sounds: a click on each take and put, a sizzle while a patty fries, a ding when it is fried, a hiss when it burns, a
  chime when a burger is taken off its plate, a sound when a served burger is right and a buzz when it is wrong. A ring over the grill fills to fried and then to
  burnt.

**Where it plays.** On the House only, the map being built for the chains, in the base mode, in every match, as the
Generator. The flat greybox, the bots' test map, gets no cooking and none of the House's chains: it keeps what it
deals today (the engineer's read-back answer on the Generator,
[PR #695, comment 6096108206](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096108206)). All the
new mechanics come with M7 on the House, and bots playing them comes later, with the map.

**Description** (a draft the engineer accepted, to be approved in the content PR): "Make every order on the kitchen
board: put its bun, a fried patty and the herb from the greenhouse board on its plate." Since #1101 (proposed, to be
approved in its PR): "..., then carry the burger to the board and serve it."

**Words and looks** (he gave the buns and the patties, asked for the rest "so it all looks nice", and took the drafts
as drafted on 2026-10-10; the whole table is the ADR's §5.1): the name "Cooking" and the lobby label "Burgers
(Cooking)"; the five icons a sun, a moon, a star, a drop and a heart, told apart by shape alone; the bun boxes open
wooden bakery crates and the patty boxes white cool boxes with a lid in their patty's colour, each showing what it
gives; the fried patties keeping their hue under a brown crust, so an order's picture matches its box; the herbs
basil, dill, rosemary, chives and mint.

**Hidden information.** The orders hang on the kitchen's board and the herb code on the greenhouse's, for anyone who
goes and looks (the open-knowledge pillar, §1); which herb grows on which bed is seen at the beds. The code is shown
only on the herb board, but a right burger served also tells anyone who saw its herb which herb that order's icon
means. What lies on a plate is seen at the plate, never whether it is right; a serve's right or wrong is heard at
the order board; the burgers done show on the task screen's Cooking row.

**Numbers** (to tune): 1 burger by default, at most 3; 3 buns, 3 patties, 5 herbs; fry 10 s, then 5 s before it
burns. Placeholders: an ingredient or a burger vanishes after lying 60 s; a player uses a station from within 2 m.

**Engine parts** ([the cooking ADR](decisions/2026-10-10-cooking-task.md) §1, §8): a Cooking task type whose deal
hangs the orders, draws the round's herb code and shuffles the herbs over the beds, with its places, grill, beds and
boards as stations; the Generator's station-use intent (`Interact`) also naming an item, for the boxes; an item source
that makes a new ingredient on every take, making room in the hands as the rules say; ingredients that vanish when
left lying; a patty whose kind changes on the grill; items held by the grill and the plates; a task type
that plays only on the maps its data lists (the Generator's part; Cooking: the House); station scenes in `levels/stations/` in place
of the House's markers; the client's boards, beds, plates with their filled-slot outlines, burgers, grill and sounds. The issues follow
from the ADR's split.

Open questions: none; the engineer answered the last ones on 2026-10-10 (the ADR's §9). The numbers above are tuned
in the playtest.

### Generator (#679)
**Out of the MVP** (the engineer, 2026-10-20, [#1033 c6288973914](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6288973914)
and [c6289051351](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6289051351)): he likes its
"king of the hill" (switch everything on and hold), but without a human it is too easy, and random trips would make
it the ship's engine again. The mechanic is kept for later. The M7 rules below stay for the record.

The House map's generator chain ([House map](design/house-map.md) §2, decision 8; its stations in §6). The rules below
are the engineer's (#679, chat of 2026-10-09, and his answers of 2026-10-10 to the design's questions, in PR #695's
comments, from [6095326452](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6095326452) on, each
linked from the ADR's §5); the engine parts are in [the Generator ADR](decisions/2026-10-10-generator-task.md).

**Intent.** A team-coordination task. Up to four switches stand in four basement rooms out of each other's earshot, and
the generator charges only while all of them are on and someone has pressed its button. The players split up and
coordinate without hearing each other. Someone may say they switched theirs on and not have done it, say they were
attacked on the way, or switch theirs on and leave, and someone switches it off behind them; then someone has to go
back, switch it on, and return to press the button again.

**Rules.**
- The Generator is a task type, like Delivery. Its subtasks are its switches: the subtask count is how many switches
  are active, 2 to 4, the task's difficulty, set by the host in the lobby settings. Every task type will have such a
  setting (Delivery: its packages; #256). Its subtasks are all done together, at full charge: the task is done then,
  and the win condition "every task done" waits for it as for any task.
- The generator and its button stand in the generator hall; switches A to D in storage, the boiler room, the pump room
  and the switch room. Where players stand to use any two switches is at least 12 m apart, the range of the sounds,
  and so beyond voice: the switches stand at least 16 m apart with the 2 m reach (20 to 39 m on the House).
- The active switches can be switched on and off; the others are on and cannot be switched off. At the round's start
  every active switch is off. Which switches are active is drawn at random each round.
- An always-on switch is not interactive at all: there is nothing to aim at and nothing to press. It looks different
  from an active switch.
- A switch is a plain press: each press toggles it, as often as anyone likes, with no cooldown. It stays as it was left.
- Anyone presses the button. While every switch is on, a press starts the charge, and a second press stops it. While a
  switch is off, the press plays its animation and nothing happens.
- A switch going off stops the charge. To resume, someone switches it back on and then presses the button again.
- The charge is cumulative: a stop pauses it, and the charge gained never drops. One charge per match; fully charged is
  done for good, and the switches and the button can no longer be used.
- The panel at the generator shows a battery of 4 bars, one lit per switch that is on (the always-on switches' bars
  from the start), filled from one end like a battery's level: it says how many switches are on, not which. When every
  bar is lit it glows blue: the button can start the charge.
- Every action has a sound: a switch's click, the button's click, and a hum at the generator while it charges. There
  is no sound when the charge is done.
- Busy hands: a player holding a two-handed item (a package) cannot use a switch or the button: they put it down, use
  it, and pick it up again.
- A dissident plays the same character as an engineer (role `crew`), under the same rules; only the win condition
  differs. Either side may switch any active switch on or off and press the button, and play the other's
  part.

**Where it plays.** On the House only, the map being built for the chains, in the base mode, in every match. The flat
greybox is a test bench only, for the bot scenarios and the information-leak test, and players always play the House
([#767](https://github.com/xperiaroco2/prime-game/issues/767)), so no new mechanic goes on the greybox: it gets no
generator and none of the House's chains, and the zone task leaves it too, its zones and their three bot scenarios
gone (the engineer, 2026-10-10, the ADR's GD13 (b):
[PR #695, comment 6100556117](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6100556117) and
[6100663476](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6100663476)). All the new mechanics
come with M7 on the House, and bots playing them comes later, with the map.

**Hidden information.** Everyone sees the charge percentage. On the map screen (M) the Generator's row is a bar of its
charge, a percentage that grows while someone charges it, where every other task's row shows its own count of done
subtasks ("2 / 5"); a task whose subtasks are all done is struck through. So a player sees the Generator at 20 % and
growing (someone is on it), at 0 (nobody is), or stuck at 30 % (something happened there). There is no shared total of
every task's subtasks, in the HUD or on the map screen ([#738](https://github.com/xperiaroco2/prime-game/issues/738)).
The battery is seen only at the generator's panel, not on any screen. Nobody is told who switched a switch: players
learn it only by seeing it or guessing (hearing a click nearby follows from "every action has a sound"). The switches
are hidden by sight: a player's game shows a switch only where that player can see or hear it.

**Edge cases.** A knocked-out player and a dead player can do nothing. The host's own player follows the same rules as
everyone.

**Numbers** (the engineer's starting values, to tune): 3 active switches by default (2 to 4, a host setting); the charge
takes 60 s in all, fixed in the game data (not a lobby setting); sounds carry 12 m; every two switches at least 12 m
apart, measured between where players stand to use them (at least 16 m between the switches with the 2 m reach).
Placeholders until he sets them: a player uses a switch or the button from within 2 m of it, and the lobby label of the
switch count.

**Name and description** (the engineer, 2026-10-10, #679's comments): "Charge the generator"; on the map screen,
"Switch on every active switch, then press the generator's button to charge it." (a draft he accepted, to be approved in
the content PR).

**Engine parts** ([the Generator ADR](decisions/2026-10-10-generator-task.md) §1, §8): a Generator task type with two
station kinds (a switch, the generator's button) and its charge on the host's clock; `Interact(station)`, the first
use of a fixed station, with busy hands, reach and sight as each station kind's rule; an always-on switch is no
station at all; two public events (a switch, the button) and the zone task's progress event for the charge; a task
type that plays only on the maps its data lists (the Generator: the House); station scenes in `levels/stations/` in
place of the House's markers; the client's panel, sounds, the always-on switches' look and the charge's bar on the task
screen. The issues follow from the ADR's split: G1 to G3 and G8 are on main, the rest open.

Open questions: none; the engineer answered the ADR's GD1 to GD13 on 2026-10-10 and approved this design with the
last two (ADR §9). The numbers above are tuned in the playtest.

### Car repair (#688)
**Replaced by Car tuning** (above; the engineer, 2026-10-20). The M7 rules below stay for the record.

The House map's garage chain ([House map](design/house-map.md) §2, decisions 5, 9 and 10; its stations in §6). The
rules below are the engineer's: #688 (chat of 2026-10-10) and his answers to the design's questions (PR #709,
[comment 6095445261](https://github.com/xperiaroco2/prime-game/pull/709#issuecomment-6095445261),
[comment 6097878738](https://github.com/xperiaroco2/prime-game/pull/709#issuecomment-6097878738) and
[comment 6100556321](https://github.com/xperiaroco2/prime-game/pull/709#issuecomment-6100556321)); the engine parts
are in [the car repair ADR](decisions/2026-10-10-car-repair-task.md).

**For the MVP only.** The engineer approved this design for the MVP: a much more interesting mechanic will replace
it later (comment 6100556321).

**Intent.** A two-player chain with the game's one rare one-shot kill. One player holds the lift, another goes under
the car to fit a part brought from storage, and a dropped car kills at once. It runs on trust: the one at the lift
cannot see who is under the car.

**Rules.**
- Car repair is a task type, like the others, and the host's per-task-type subtask count applies (#256, #679). One
  subtask is one part fitted; a repair may need several parts, one after another.
- The car stands on a lift in the garage, the lift panel in the garage too, the parts shelf in storage. The panel
  stands near enough to the car for the holder and the fitter to talk (within the voice range), out of reach of the
  car.
- The car stays up only while someone holds E at the lift panel. It rises over a few seconds once the hold starts, and
  a part can be fitted only when it is fully up. Let go, or be knocked down, and the car drops at once and kills
  whoever is under it (decision 9): every player whose feet are under the car, living or knocked down, invulnerable
  or not. The player respawns as usual (decision 10). A hit that does not knock the holder down does not drop the
  car. The holder leaving the match or losing the connection drops it too, with the kill; the round's end lowers it
  without one.
- A picture on the garage wall shows which part the car needs, one of several kinds, never the same kind twice in a
  row. (Later, ideally, something nicer: a player crawls under the car to see what it needs; not now.)
- The part is taken from the parts shelf in storage, one place per part kind with the same picture, as many as the
  players like, and carried to the garage in one hand.
- Taking a part works as at the kitchen's boxes (the belt rule): with an item in the hand and a belt slot free, the
  hand item goes onto the belt; with full hands (an item in the hand and two on the belt), the hand item drops at the
  player's feet; then the part goes into the hand. A player holding a two-handed item, such as a package, can still
  take a part: it goes onto the belt (a full belt's item drops at the player's feet), and the two-handed item stays
  in the hands.
- A part put down lies until someone takes it; it does not vanish.
- Fitting a part: under the car, crouched, with the right part in hand, the player holds E for some seconds. Every
  player can crouch: hold Ctrl; Shift while crouched moves a bit faster (its own mechanic, #727). The raised car is
  too low to stand under, so a player crouches to get under it and comes out crouched; nothing else checks the crouch
  (height alone). A wrong part is
  refused and stays in the hand. A hit on the fitter stops the fit, which then starts again from zero.
- After the last part the lift cannot be raised again; a hold that still runs drops and kills as always.
- The lift panel has no view of who is under the car: the one holding the lift relies on trust and voice.
- As for the Generator (#679): a dissident plays the same character under the same rules, so either side may hold the
  lift, let it go or fit a part; busy hands: a player holding a two-handed item, such as a package, cannot use the
  lift panel or the car (a take at the shelf still works, above).
- The drop kills a knocked-down player under the car too. The knockdown is reworked in #728 (its design in PR #754):
  since 728a (#846) a knocked-down player cannot move, it only looks around; the rest of the rework adds that it cannot
  talk (hears, but cannot speak) and falls as a ragdoll.

**Hidden information.** Nobody at the lift panel sees who is under the car, and nothing tells anyone who let go, unless
they saw it. It is hidden by sight, as packages are: every client still receives every player's position, and the
garage's walls hide the space under the car from the panel; no sound plays while a fit runs. The end of a fit is
not hidden: the part-fitted sound and the task screen tell everyone, the holder too, the moment a part is fitted,
while the fitter is still under the car. Tasks are shared and
every player sees the same task progress (#79): the task screen's Car repair row shows the parts fitted of N, struck
through once every part is fitted (there is no shared total of all tasks, #738).

**Edge cases.** Only living players do subtasks (#79; [vision revision 1](decisions/2026-10-01-vision-revision-1.md),
V4): a knocked-out player and a dead player can do nothing. The host's own player follows the same rules as everyone.

**Sounds.** The lift's motor, the drop's crash, a part taken and a part fitted; none while a fit runs.

**Where it plays.** On the House only, in the base mode: the one map its data lists. Never on the flat greybox, which
is a test bench only (#767: players always play the House). Bots do not play the House, so car repair is tested by
integration tests on the House and over the real wire, not by bot scenarios. Every House match deals it.

**Name and description** (drafted by the agents, approved by the engineer as drafted): "Repair the car"; "Take the
part shown on the garage wall from the shelf in storage, then fit it under the car while someone holds the lift.";
the lobby label of its part count: "Parts to fit".

**Numbers** (placeholders, approved as proposed and still "not a decision": the engineer tunes them after a
playtest): a 5 s fit; a 2 s rise; 3 part kinds; 1 to 3 parts per repair, 2 by default; the raised car's underside at
1.4 m, above a crouched player (1.2 m, the crouch's placeholder) and below a standing one (1.8 m); the panel 5 m from
the car; at most one take from the shelf per 0.25 s, a flood guard.

**Engine parts** ([the car repair ADR](decisions/2026-10-10-car-repair-task.md) §1, §8): a car repair task type with
four station kinds (the car, the lift panel, one bin per part kind on the shelf, the picture on the wall); the lift's
hold and the fit as holds of E on a station (the raise's channel, extended to stations and to a hold with no end);
the drop as an instant kill of every player under the car, decided by the host; the parts as items from the shelf (the
cooking design's item source, #682); the Generator's `Interact(station)` (#679); station scenes in
`levels/stations/` in place of the House's markers; the client's car, picture, fitter and sounds. The crouch (#727, its
own ADR) and the knockdown rework (#728) are designs of their own. The issues follow from the ADR's split: R1 to R4
and R9 are on main, the rest open.

Open questions: none; the engineer answered the last ones on 2026-10-10 (the ADR's §9). The numbers above are tuned
in the playtest.

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

**Voice through walls** (decided by the engineer on 2026-10-21,
[#1035 comment 6318368598](https://github.com/xperiaroco2/prime-game/issues/1035#issuecomment-6318368598), completing
his answer of 2026-10-15, [comment 6191454275](https://github.com/xperiaroco2/prime-game/issues/1035#issuecomment-6191454275)):
1. A voice carries 8 m, through walls and floors too (a placeholder until a playtest).
2. A wall or a floor between the listener and the speaker muffles it: quieter and dull, like a party in the next
   room; you hear that someone talks, the words are hard to catch.
3. An opening lets it through clean: a doorway, a window, a stairwell, a hatch, a vent grate, a manhole. So an ear to
   a grate is how you eavesdrop.
4. One wall or three, the same muffle: no materials, no counting.
5. Stations stay about 20 m apart ([estate-map](design/estate-map.md) rule 8), so one station's voice never reaches
   the next.

The client already plays this (the M5 ADR's muffle, D13 (a): about 8 dB quieter and a low-pass near 1 kHz, both
placeholders); who hears whom stays distance only.
- How far does a voice carry, and how much do walls muffle it? (Answered above.)
- Can the dead hear the living, and can they talk to each other? (Answered above: no and no.)
- Which abilities or items change who hears whom?

## 12. Information tools

**The camera wall** (decided by the engineer on 2026-10-21,
[#1035 comment 6319598316](https://github.com/xperiaroco2/prime-game/issues/1035#issuecomment-6319598316), from his
direction of 2026-10-20, [comment 6290259889](https://github.com/xperiaroco2/prime-game/issues/1035#issuecomment-6290259889)),
in the security room ([estate-map](design/estate-map.md) §5c):
1. Six screens, six fixed cameras: the bonfire, the summer kitchen, the pantry, the greenhouse, the garage and the roof
   terrace, the places where the aliens search for mischief and spoils.
2. A live picture only: no sound, no recording, no rewind, no names over the players (§3). A player is known by their
   look, at night, on a small grainy screen, so a picture proves nothing on its own.
3. No cameras on the paths, the passages, the house's rooms, the laboratory or the ship.
4. The screens are in the world: E sits you in the chair and the wall fills the view; any move gets you up. The
   watcher sits with their back to the door.
5. Every camera is a thing on the map with a red lamp, in sight. E turns it to face the wall (its screen shows planks);
   E turns it back. Anyone may do either.
6. The blackout darkens the whole wall (§7); the house phone beside it reaches the library (§8, the Wi-Fi).

- Which tools give players information (cameras, logs, vitals, trackers)? (The camera wall above; others open.)
- How reliable is each, and can it be faked?

## 13. Maps

**The MVP's map is [the forest estate](design/estate-map.md)** (approved by the engineer on 2026-10-20,
[#1035 comment 6297325577](https://github.com/xperiaroco2/prime-game/issues/1035#issuecomment-6297325577)): a country
estate in a pine forest on the edge of a small town, 135 x 90 m, separate buildings in clearings joined by two loops of
paths, no dead ends, at night. It is built for the MVP's task set (§8); its sizes are a working draft for a box
greybox. Until that greybox exists, the House below is what the game plays.

The first map is [House](design/house-map.md) (decided by the engineer on 2026-10-08, #591): a country house with a
yard on an 80 x 60 m plot, for 4 to 10 players, on four levels (basement, ground floor with the yard, second floor,
attic and roof), laid out for the five task chains. Its sizes and positions are a working draft until a greybox
playtest.

Players always play the House: the lobby offers no other map and every match starts on it. The flat greybox stays a
test bench only, for the bot scenarios and the information-leak test (the engineer's option (a) on
[#767](https://github.com/xperiaroco2/prime-game/issues/767)).

- How many maps in all, and do later maps keep the same scale and player count?

## 14. Art and audio direction

The brief sets stylized low-poly, readable and cheap to produce; CSG greyboxing and CC0 packs are fine.
- What is the reference look (a few games or images)?
- What must be readable at a glance: roles, items, dead bodies, open doors? Under
  [vision revision 1](decisions/2026-10-01-vision-revision-1.md) everyone sees a downed player, a body (it stays until
  its player respawns), the item in a player's hand and the ones on their belt, and a player's few seconds of
  invulnerability, so each must read at a glance; how they look is open.

## 15. Tutorial

[`docs/design/tutorial.md`](design/tutorial.md) (#552, built by T1 to T4 and #492): an offline solo session in a
room of its own, the UI track's lessons, and its points D25 to D36 (his answers: ARCHITECTURE §9.5.17).

The engineer's decision of 2026-10-11 (DD10, [PR #713](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6108665402)):
the tutorial deals no task at all and teaches only movement and the basic mechanics (#825). Its design,
[`docs/design/tutorial.md`](design/tutorial.md) §9, and its [ADR](decisions/2026-10-12-tutorial-without-tasks.md):
his answers on [PR #894](https://github.com/xperiaroco2/prime-game/pull/894#issuecomment-6122434286) (LD1 (a), LD2
(a), LD7 to LD10 (a)). Built in #900 (825a): the package is a plain item, no task is dealt, no drop-off stands in
the room, and eight lessons remained (Controls, Picking up and putting down, Hand and belt, Map and tasks, Downed,
Death, Voice nearby, Menu). Built in #901 (825b, LD3 (a)): the throw lesson, lesson 4 after Hand and belt, so the
tutorial has nine lessons (Controls, Picking up and putting down, Hand and belt, Throwing, Map and tasks, Downed,
Death, Voice nearby, Menu). It completes on the player's own throw; its words are the deck's (`tutorial.list.throw`
"Throwing", `tutorial.step.throw.title` "Throw an item", `tutorial.step.throw.how` "Take an item in your hand and
press {key}"), and the room is kept as it is (the engineer's answer (c) on #901, #911). The crouch key (#902) is
lesson 1's key row.
