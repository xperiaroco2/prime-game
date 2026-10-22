# The tutorial without tasks: movement and the basic mechanics, the package as a plain item

- **Status:** Accepted: the engineer's answers on
  [PR #894](https://github.com/xperiaroco2/prime-game/pull/894#issuecomment-6122434286), every LD item as
  recommended (LD1 (a) with (c) later, LD4 (b) after #790 and #791); the LE items (LE1 to LE6) as recommended, the M7
  manager session's. The LD items were his, tier (c) of the
  [trust ADR](2026-10-04-trust-based-autonomy-gated-merge-into-main.md) (game rules, taste and the words). 825a is
  built in #900 (the mode, the eight lessons, the room); 825b (#901) and 825c (#902) follow
- **Date:** 2026-10-12
- **Deciders:** the engineer (the LD items); the M7 manager session (the LE items); designed by the agent in #825
  under the M7 manager session
- **Design:** [`docs/design/tutorial.md`](../design/tutorial.md) §9 holds what today's tutorial teaches, what goes
  with the tasks, every LD and LE item with its options, the failure each prevents and its recommendation, the shared
  files and the split
- **Builds on:** the engineer's decision, asked as DD10 of the
  [Delivery by meaning ADR](2026-10-10-delivery-by-meaning.md) and answered on
  [PR #713](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6108665402) (2026-10-11): "the tutorial
  must be reworked completely; for now its tasks can be removed altogether", "only movement and the basic mechanics";
  his answer that the tasks leave with the rework, not as a separate change
  ([#825](https://github.com/xperiaroco2/prime-game/issues/825#issuecomment-6109457789)); the
  [tutorial ADR](2026-10-08-tutorial-offline-solo-session.md) (D25 to D36 and E62 to E72 stand where this one does not
  reopen them); [throwing held items](2026-10-09-throwing-held-items.md); [the crouch](2026-10-10-crouch.md);
  [the MVP content built by the engineer](2026-09-29-mvp-content-built-by-the-engineer.md)
- **Numbering:** new prefixes for this rework: **LD** (the engineer's) and **LE** (technical); the tutorial ADR's D
  and E items keep their numbers and meaning

## Context
Today's tutorial (built by T1 to T4 and #492; ARCHITECTURE §4.7.44, §4.7.46, §9.5.17) runs nine lessons in a room of
its own. Two of them need a task: lesson 4 ("Delivery") is done when the own Delivery task is (`TasksDone`, a
`PackageDelivered`), and lesson 5's second step opens a task's how-to card from the map's «?». The package of
lesson 2 exists only because Delivery's deal spawns it. The engineer decided that the tutorial deals no task
at all and teaches only movement and the basic mechanics; which mechanics, the steps' order and their words are his
call (#825). His answer of 2026-10-03 on #150 ("the tutorial teaches the basics and how to find out about a task:
open the map and press «?»") is older and gives way where it names a task.

What constrains the rework:
- **The stages are fixed by the mode.** `lessons → raise_stage → death_stage`, staged by the host on `NextStage`:
  lessons 6 (downed) and 7 (death) stay where they are, and every item lesson stays in `lessons`, since the death
  drops both slots where the body lies.
- **The copy deck is not edited here.** `client/i18n/strings.csv` is copied byte for byte from prime-game-ui at a
  tag (ARCHITECTURE §4.7.26): a key added, changed or dropped is a UI track release and a `ui-copy`. The Guide's
  basics cards reuse the tutorial's step keys, so those keys stay whatever the tutorial drops.
- **Lesson 3 needs a one-handed item** (D29): the knife; the package takes both hands.
- **Mechanics outside today's tutorial:** the throw (built, #643 to #646, the `throw` key); the crouch (designed,
  #790 and #791; the base mode's `PlayerRules.crouch_maps` lists the House alone, while the tutorial mode's lists its own
  room explicitly (the engineer's answer (c), #790), so the crouch plays in the room whether taught or not; since #991 there is no list,
  the crouch plays everywhere); the knife's strike
  (`Use`) and giving up (`GiveUp`), both refused in the tutorial by D27 and D28 (a); a station's `Interact` (#796),
  which belongs to a task type.
- **Shared files:** `levels/tutorial/rooms/tutorial_room.tscn` is also #715's (the room's map record);
  `client/i18n/strings.csv` also #715's, #718's and #306's.

## Decision
Recommended, each item in the design's §9 tables:
1. **No task** (LE1): the tutorial mode drops `DealTasks`, its task types, the `tasks` and `banned_task_types`
   settings and every `TaskTicks`. With no `DealTasks` the loading screen shows no task card.
2. **The package stays as a plain item** (LD1 (a), LE2): `SpawnItems` places it on the shelf's marker by the
   `packages` setting; lessons 2 and 3 keep their words.
3. **Lesson 4 goes** with the room's drop-off marker (LE4), and **lesson 5 keeps only its map step** (LD2 (a)).
4. **No new lesson in the first build** (LD3 to LD6): the throw (LD3 (a)) and the crouch (LD4 (b)) come as later
   issues of their own once he picks them and their words exist; the knife's strike and giving up stay untaught.
5. **The order** (LD7 (a)): Controls, Picking up and putting down, Hand and belt, Map, Downed, Death, Voice, Menu
   (eight lessons); a throw lesson, if he takes it, after Hand and belt.
6. **The words** (LD8 (a)): the first build uses only keys the deck has; a new step's words go to the UI track as
   drafts, marked so, at his word.
7. **The parts stay** (LE3): `TasksDone`, `ClientSeen`'s `howto_opened`, the «?» step's `HOWTO_GLYPH` and round
   keycap and their tests remain, used by no data.
8. **The tests** (LE5, LD10 (a)): no test is deleted before his LD10 answer; every rewritten or dropped assertion is
   listed in the build PR.
9. **The split** (LD9 (a)): 825a removes the tasks; 825b adds the throw lesson; 825c adds the crouch to lesson 1.

## Needs the engineer
One batch; the design's §9.4 gives each option's failure. The build proceeds on the recommendations only after he
answers.

| Item | Question | Options | Recommended |
|---|---|---|---|
| LD1 | Which item lesson 2 uses with no Delivery | (a) the package as a plain item, spawned by `SpawnItems`; (b) the knife for lesson 2 as for lesson 3; (c) a House item of Delivery by meaning, once D2 builds it | (a) |
| LD2 | Lesson 5 with no task to open a card for | (a) the map step only; (b) lesson 5 goes; (c) the «?» step becomes the Esc menu's Guide | (a) |
| LD3 | Teach the throw | (a) a lesson after Hand and belt, as issue 825b; (b) not taught | (a), as its own later issue |
| LD4 | Teach the crouch | (a) a lesson of its own with a low prop; (b) the crouch key in lesson 1's key row, as issue 825c; (c) not taught (it still plays in the room: keeping it out would reopen KE10) | (b), after #790 and #791 |
| LD5 | Teach the knife's strike | (a) not taught, `Use` refused as today; (b) a swing at nobody | (a) |
| LD6 | Teach giving up | (a) not taught, D28 (a) stands; (b) lesson 7 downs the own player first and it gives up | (a) |
| LD7 | The order | (a) today's, the removed left out, new lessons in place; (b) the map just before the menu | (a) |
| LD8 | The words | (a) the deck's keys only in 825a, drafts for new steps through the UI track; (b) a new pass over every step's words by the UI track first | (a) |
| LD9 | The split | (a) 825a, 825b, 825c as the design's §9.7; (b) with his changes | (a) |
| LD10 | The tests 825a drops | (a) yes to the design's list (§9.4): one test deleted, the assertions on what goes dropped; (b) the list with his changes | (a) |

## Alternatives
- **Keep a task and teach Delivery by meaning** (DD10's other options): the engineer chose no task (DD10).
- **Remove the tasks now as a small change and rework later**: he chose one rework (#825's comment of 2026-10-11).
- **`DealTasks` with `tasks` at 0**: the loading screen reads the mode's `DealTasks` and would still show
  Delivery's how-to card, and the mode would carry a task type it never deals.
- **The knife for lesson 2** (LD1 (b)): lesson 2's words name a package, so it waits on a UI release for nothing
  the player gains.
- **A House item for lesson 2** (LD1 (c)): it waits on D2, which comes after #825 (the Delivery ADR), and
  needs new words; it stays open as a later change.
- **The Guide in place of the «?»** (LD2 (c)): a new client signal and new words for a step the menu lesson nearly
  covers (its Esc menu holds the Guide).
- **Teaching the strike** (LD5 (b)): with nobody to strike, it teaches a key and not what the strike does; a strike
  among the crew teaches a wrong idea of who strikes (D27's reason); and the base mode's strike rule, reused, could
  down a stand-in in `lessons`, which has no `LifeTicks`, so the stand-in stays down and the staged raise lesson
  (D27) breaks.
- **Teaching giving up** (LD6 (b)): lesson 7 grows by a knockdown and a hold; D28's other failure, a downed state
  with no plate of its own, went with #497's plate ("Hold {key} to give up", `client/ui/life_screen.gd`), which a
  downed player in a match already reads.
- **Removing `TasksDone` and `howto_opened` with their tests**: deleting a part's tests needs his approval, and
  "for now" may bring a task back.
- **Editing `strings.csv` here**: the next `ui-copy` overwrites it and the lock check fails.
- **One build issue with the throw and the crouch**: it would wait on the deck's keys and on #790 and #791; 825a is
  ready once he answers.

## Consequences
- The tutorial deals no task, so Delivery by meaning (D2) never touches it; the tutorial tests the Delivery ADR left
  to #825 are 825a's (the design's §9.2).
- Eight lessons ("Step n of 8"); the package carries no circle's colour and is drawn white; the loading screen shows
  no task card; lesson 5's map opens with its Tasks panel empty, and how the map looks with no task is the UI
  track's (a request with the words, the design's §9.7).
- The keys `tutorial.step.deliver.*`, `tutorial.list.deliver` and `tutorial.step.howto.*` are used by no data;
  they stay in the deck until the UI track drops them. `tutorial.list.map` keeps "Map and tasks ({key})", the map
  screen's own name (`control.map`). The UI request for lesson 4's v1 text (D30 (b)) is moot.
- `TasksDone` and `howto_opened` stay as parts no data uses; a task lesson that comes back reuses them.
- 825a edits the tutorial room before #715 does; scenes are single-owner, so the later PR waits for the earlier's
  merge (the design's §9.6).
