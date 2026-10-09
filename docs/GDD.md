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

### Movement: the crouch (#727)
Decided by the engineer (#727, 2026-10-10): every player can crouch by holding Ctrl, and Shift while crouched moves
a bit faster. A crouched player is lower, so it passes under things a standing one does not: the raised car in the
garage, under which the fitter works crouched (car repair, #688). The art has or will have a crouch animation. A
knocked-down player cannot crouch (today it crawls lying down; once #728's rework is built it cannot move at all).

His answers to the crouch design (PR #752, comments 6097878317 and 6098097098; the options and the reasons are in the
[crouch ADR](decisions/2026-10-10-crouch.md)):
- The crouch plays on the House only. The flat greybox has no crouch. (The lobby, a level of its own, has none
  either: the design's reading of "the House only" (KE10), not a separate answer.)
- A crouching player's steps are quieter and slower (KD1).
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
- Throwing a held item (#37): how strong and how far; which items; does a thrown item hurt or stop a player it meets;
  does a thrown package count when it lands in its circle; may an item land where nobody can reach it; does a throw
  cost anything; which key; can a flying item be caught; does it bounce or stop where it hits; does a running throw
  go farther; where does an item thrown off the map end up; does a downed player stop it? The options and a
  recommendation for each are in the [throwing ADR](decisions/2026-10-09-throwing-held-items.md) (TD1 to TD12), for
  the engineer.

## 7. Sabotages

- Who can sabotage, how is it fixed, and what does the crew lose if it is not?
- Can sabotages affect voice, vision or movement?

## 8. Tasks

- What kinds of tasks exist (short, long, shared, fake-able)?
- Are tasks a win condition, an information source, or both?
- How does a task look in first-person 3D?

### Photo (#687)
The House map's photo chain ([House map](design/house-map.md) §2, decision 7; its stations in §6). The rules below
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
  film and a photo each take one hand: a player can hold one in the hand and one on the belt.
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
  hand and one on the belt) puts the hand item down at the player's feet, and the film goes into the hand.

**Where it plays.** On the House only, the map being built for the chains, in the base mode, in every match, as the
Generator. The flat greybox, the bots' test map, gets no photo task and none of the House's chains: it keeps what it
deals today (the engineer's read-back answer on the Generator,
[PR #695, comment 6096108206](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096108206)). All the
new mechanics come with M7 on the House, and bots playing them comes later, with the map.

**Hidden information.** Whether a person is in a photo is decided by the host from where everyone stood at the moment
of the shot, never from a player's picture. A photo shows its picture to whoever sees it; whether it counted
everyone learns once it is hung, from the photo task's row on the Tab task screen: the photos counted of N, struck
through once every photo is counted. There is no shared total of every task's subtasks, in the HUD or on the task
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
A second task type from #36: stand in a zone for N seconds. Nothing is decided beyond what already holds: tasks are
shared and only living players do subtasks (#79; [vision revision 1](decisions/2026-10-01-vision-revision-1.md), V4),
so the downed never count, and the dead have no avatar (there are no ghosts). The options, with a recommendation for
each question: [the zone task ADR](decisions/2026-10-09-m7-zone-task.md) (ZD1 to ZD11).

Open questions (the engineer's):
- Is the time earned by standing in the zone, or by holding a key there?
- Does leaving the zone pause its time or reset it?
- Can several players share a zone, and does it fill faster with more of them?
- Does a living dissident standing in a zone count, as any living player does a subtask today?
- Is each subtask one zone, with every zone open from the start?
- Does everyone see each zone's progress as it fills, or only when it is done?
- Does anything but leaving stop a zone: a hit, carrying something?
- How long, how big and how many zones, in which colours; the task's name and description; and does "zone" clash
  with "the zones where items may appear" (§1) and with the House map's photo zone and chill zone ([House map](design/house-map.md) §2, §4)?
- Does every match deal both Delivery and the zone task, or one of them at random?
- Where do zones stand on the maps (the [House map](design/house-map.md)'s task stations, its §6, include none), and how do they look?

### Cooking (#682)
The House map's burger chain ([House map](design/house-map.md) §2, decision 6; its stations in §6). The rules below
are the engineer's (#682, chat of 2026-10-10, his answers on #682, and his answers to the design's questions on
[PR #701](https://github.com/xperiaroco2/prime-game/pull/701#issuecomment-6095326743), the last four in
[comments 6096108400](https://github.com/xperiaroco2/prime-game/pull/701#issuecomment-6096108400),
[6096140448](https://github.com/xperiaroco2/prime-game/pull/701#issuecomment-6096140448) and
[6096157421](https://github.com/xperiaroco2/prime-game/pull/701#issuecomment-6096157421)); the engine parts are in
[the cooking ADR](decisions/2026-10-10-cooking-task.md). Nothing is built yet.

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
- Each ingredient is a separate item in the hand: a bun, a patty or a herb takes one hand, and the belt holds one,
  like any one-handed item.
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
- Taking with full hands (an item in the hand and one on the belt) puts the hand item down at the player's feet, and
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
- Each ingredient is checked against that place's order at once. A raw or burnt patty is refused outright and stays
  in the hand; any other wrong one shows a red outline and can be taken back; a right one shows a green outline and
  can no longer be taken.
- A burger is done on the spot, once its bun, patty and herb are all green on its place.
- Sabotage: a dissident may take a box and hide it; the others must search for it (the same play as hiding a
  package). Beyond that, the rules above already let anyone take items, burn a patty or put a wrong ingredient on a
  plate.
- A dissident plays the same character as an engineer (role `crew`), under the same rules, and only living players
  do subtasks (#79; vision revision 1, V4).
- Sounds: a click on each take and put, a sizzle while a patty fries, a ding when it is fried, a hiss when it burns, a
  chime for green and a buzz for red, a sound when a burger is done. A ring over the grill fills to fried and then to
  burnt.

**Where it plays.** On the House only, the map being built for the chains, in the base mode, in every match, as the
Generator. The flat greybox, the bots' test map, gets no cooking and none of the House's chains: it keeps what it
deals today (the engineer's read-back answer on the Generator,
[PR #695, comment 6096108206](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096108206)). All the
new mechanics come with M7 on the House, and bots playing them comes later, with the map.

**Description** (a draft the engineer accepted, to be approved in the content PR): "Make every order on the kitchen
board: put its bun, a fried patty and the herb from the greenhouse board on its plate."

**Words and looks** (he gave the buns and the patties, asked for the rest "so it all looks nice", and took the drafts
as drafted on 2026-10-10; the whole table is the ADR's §5.1): the name "Cooking" and the lobby label "Burgers
(Cooking)"; the five icons a sun, a moon, a star, a drop and a heart, told apart by shape alone; the bun boxes open
wooden bakery crates and the patty boxes white cool boxes with a lid in their patty's colour, each showing what it
gives; the fried patties keeping their hue under a brown crust, so an order's picture matches its box; the herbs
basil, dill, rosemary, chives and mint.

**Hidden information.** The orders hang on the kitchen's board and the herb code on the greenhouse's, for anyone who
goes and looks (the open-knowledge pillar, §1); which herb grows on which bed is seen at the beds. The code is shown
only on the herb board, but a green herb on a plate also tells anyone looking which herb that order's icon means.
What lies on a plate, red or green, is seen at the plate; the burgers done show on the task screen's Cooking row.

**Numbers** (to tune): 1 burger by default, at most 3; 3 buns, 3 patties, 5 herbs; fry 10 s, then 5 s before it
burns. Placeholders: an ingredient vanishes after lying 60 s; a player uses a station from within 2 m.

**Engine parts** ([the cooking ADR](decisions/2026-10-10-cooking-task.md) §1, §8): a Cooking task type whose deal
hangs the orders, draws the round's herb code and shuffles the herbs over the beds, with its places, grill, beds and
boards as stations; the Generator's station-use intent (`Interact`) also naming an item, for the boxes; an item source
that makes a new ingredient on every take, making room in the hands as the rules say; ingredients that vanish when
left lying; a patty whose kind changes on the grill; items held by the grill and the plates; a task type
that plays only on the maps its data lists (the Generator's part; Cooking: the House); station scenes in `levels/stations/` in place
of the House's markers; the client's boards, beds, plates with their outlines, grill and sounds. The issues follow
from the ADR's split, for the M7 backlog: for now the track only designs.

Open questions: none; the engineer answered the last ones on 2026-10-10 (the ADR's §9). The numbers above are tuned
in the playtest.

### Generator (#679)
The House map's generator chain ([House map](design/house-map.md) §2, decision 8; its stations in §6). The rules below
are the engineer's (#679, chat of 2026-10-09); the engine parts and the questions still open are in
[the Generator ADR](decisions/2026-10-10-generator-task.md).

**Intent.** A team-coordination task. Up to four switches stand in four basement rooms out of each other's earshot, and
the generator charges only while all of them are on and someone has pressed its button. The players split up and
coordinate without hearing each other. Someone may say they switched theirs on and not have done it, say they were
attacked on the way, or switch theirs on and leave, and someone switches it off behind them; then someone has to go
back, switch it on, and return to press the button again.

**Rules.**
- The Generator is a task type, like Delivery. Its subtasks are its switches: the subtask count is how many switches
  are active, 2 to 4, the task's difficulty, set by the host in the lobby settings. Every task type will have such a
  setting (Delivery: its packages; #256).
- The generator and its button stand in the generator hall; switches A to D in storage, the boiler room, the pump room
  and the switch room. Every pair of switches is more than 8 m apart (20 to 39 m).
- The active switches can be switched on and off; the others are on and cannot be switched off. At the round's start
  every active switch is off.
- A switch is a plain press: each press toggles it, as often as anyone likes, with no cooldown. It stays as it was left.
- Anyone presses the button. While every switch is on, a press starts the charge, and a second press stops it. While a
  switch is off, the press plays its animation and nothing happens.
- A switch going off stops the charge. To resume, someone switches it back on and then presses the button again.
- The charge is cumulative: a stop pauses it, and the charge gained never drops. One charge per match; fully charged is
  done for good, and the switches and the button can no longer be used.
- The panel at the generator shows a battery of 4 bars, one lit per switch that is on (the always-on switches' bars
  from the start). When every bar is lit it glows blue: the button can start the charge.
- Every action has a sound: a switch, the button, the charge.
- Busy hands: a player holding a two-handed item (a package) cannot use a switch or the button: they put it down, use
  it, and pick it up again.
- A dissident is the same character as an engineer (the crew role, id `crew`), under the same rules; only the win
  condition differs. Either side may switch any active switch on or off and press the button, and play the other's
  part.

**Hidden information.** Everyone sees the charge percentage, on the task screen too. The battery is seen only at the
generator's panel, not on any screen. Nobody is told who switched a switch: players learn it only by seeing it or
guessing.

**Edge cases.** A knocked-out player and a dead player can do nothing. The host's own player follows the same rules as
everyone.

**Numbers** (the engineer's starting values, to tune): 3 active switches by default (2 to 4, a host setting); the charge
takes 60 s in all; sounds carry 12 m.

**Engine parts** ([the Generator ADR](decisions/2026-10-10-generator-task.md) §1, §8): a Generator task type with two
station kinds (a switch, the generator's button) and its charge on the host's clock; `Interact(station)`, the first
use of a fixed station, with busy hands, reach and sight as each station kind's rule; two public events (a switch, the
button) and the zone task's progress event for the charge; station scenes in `levels/stations/` in place of the House's
markers; the client's panel, sounds and the charge on the task screen. The issues follow from the ADR's split.

Open questions (the engineer's; the ADR's GD items, each with options and a recommendation):
- The task screen's description, and whether the working name "Charge the generator" stays (#679's open item).
- Which switches are active: drawn each round, or fixed by the map?
- Does the shared progress count the switches' subtasks only at full charge?
- Do the panel's bars say which switch is off, or only how many are on?
- What does a press of an always-on switch do, and does such a switch look different?
- How near must a player stand to a switch or the button?
- Does the Generator play on the greybox too, and does every match deal it?
- "Also on the map screen": no map screen exists; is the task screen meant?
- Is the 60 s fixed in the data, or a lobby setting?
- Is there a sound when the charge is done, beside the charge's own?

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
