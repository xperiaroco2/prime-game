# M8: the match

| | |
|---|---|
| **Owner** | The engineer, the project lead and game designer (the content area, #518, #1073). Agents change this file only on his word. |
| **Status** | Decided by the engineer on 2026-10-15 in the design session's chat, each rule with its source issue; everything under "Open" is not decided. Every number is a **placeholder** to tune by a balance model (#1089) and playtests, unless the text says it is decided. |
| **Milestones** | M8 (the story, the roles, the capsules, the tasks and gadgets in the story), M8.2 (the House as a level), M8.3 (points and mutations, meta-progression, faces): plan #1039. |
| **Research** | [`research/`](research/README.md), rounds 1 and 2 (2026-10-15). Research informs; only what is written here as decided is a rule. |

## 1. The story

- **Pitch** (GDD §1): *aliens throw the best party on Earth, but disguised humans who hate their party hide among
  them, and it all turns into chaos.* Working title **My Alien Prime Friends**; "Prime" as in prime time, the
  aliens are at their coolest (#1031). A decision on the title comes before any public store page (research round
  2 found Amazon's PRIME mark covers online games).
- **The sides:** the players are aliens; the humans (the existing dissident role) are disguised as aliens and spoil
  the party out of envy (#1031, plan #1039).
- **The lobby is a space station where the aliens' ship, the skat, stands docked** (2026-10-28, #1095; GDD §3 Base
  mode); each match the crew flies down to Earth to party, which later allows several party maps with different tasks
  (#1031). **The aliens visit** (the engineer, 2026-10-31, [#1031 c6549509266](https://github.com/xperiaroco2/prime-game/issues/1031#issuecomment-6549509266)): every match the crew flies down on
  the skat from the station to party at the alien lord's estate; they do not live there. **The round starts with the
  crew together at the foot of the skat's ramp** (the skat has landed; they walk out in a crowd and spread out; the
  same comment; engine part #1492). Open: how the flight itself is shown between Countdown and Pregame (Loading).
- **Tone:** teens and adults, adult and funny, comic violence, no guts or dismemberment (GDD §1).
- **References:** parody, never another work's names, logos, characters or assets (GDD §1). Research round 2
  proposed a frame (the aliens learned Earth from bad broadcasts, so every Earth reference comes out recognisable but
  wrong); not decided.
- **Far future, an easter egg:** a rare shovel digs up alien skeletons in the garden (the crew the humans replaced);
  never a clue to who is who (#1031). The engineer's own open hole: how the crew were killed if everyone respawns.

## 2. Roles

- **Mechanically identical:** a human can do exactly what an alien does; only the win condition differs, for now
  (#1031).
- **Being outed is a disadvantage, never a loss:** an outed human drops the act, plays the villain openly and keeps
  real levers; nobody has to lie to faces. Hiding pays, it is never forced (#1031).
- **The host sets the exact number of humans** (e.g. 3 of 10) (#1032). **The defaults:** 1 at 4–5 players, 2 at 6–8,
  3 at 9–10 (the engineer, 2026-10-31, [#1031 c6549509266](https://github.com/xperiaroco2/prime-game/issues/1031#issuecomment-6549509266), from research round 2; engine part #1492).

## 3. Death and respawn

- **In the M8 slice** (GDD §3, "The M8 slice"; #1492): everyone spawns and respawns on the ship's clearing, in a
  loose crowd before the open jaw ramp; the wait is 30 s, then 3 s of invulnerability. The points across the map, the
  dead's room, the body and the drone below are the full match's, after the slice (#1489).
- **Death costs time, not the match** (#1032): about 5 or 6 respawn points across the map (the full match, after the
  slice); to farm an outed human the aliens would have to split up and guard every point, time they do not spend on
  tasks.
- **No capsule props** (the engineer, 2026-10-15: they add visual noise): the respawn points are today's random free
  respawn markers, marked in the design only.
- **A random point** by default; **a perk (mutation) to choose one** (later); **a few seconds of invulnerability**
  after the respawn (today 3 s) to run, so a respawn among everyone becomes a chase, not a loss (#1032).
- **The wait is 30 s** (decided, tuned by playtest); **no wait that grows per death** (rejected as boring) (#1032).
- **The dead's room** (the MVP, the engineer, 2026-10-20,
  [#1032 c6289051758](https://github.com/xperiaroco2/prime-game/issues/1032#issuecomment-6289051758)): the dead do not
  spectate the living; they go together to a place they walk and play in until the respawn, and hear and talk only
  with each other. **That place is the lobby station's hall** (GDD §3), without the skat: while the crew parties on
  Earth, the dead wait up on the station with the bar, the pinball and the Earth in the windows (2026-10-31, taken
  for the engineer: [#1032 c6549455501](https://github.com/xperiaroco2/prime-game/issues/1032#issuecomment-6549455501)).
  Kept for later: choosing the spot and the misprint debuff
  ([#1032 c6223852584](https://github.com/xperiaroco2/prime-game/issues/1032#issuecomment-6223852584)).
- **The body stays** where the player died until the return: evidence for whoever finds it (kills are still not
  revealed, §4). It disappears when the player is printed back (2026-10-31, the same comment).
- **The return:** a small drone hovers over the respawn point and "3D-prints" the player back in about 2 s, from the
  feet up, seen by everyone near (the engineer, 2026-10-15; the length 2026-10-31, the same comment); the player
  cannot move or be hit while printed; then the invulnerability. Engine part: #1489. Numbers are placeholders.

## 4. Points

- **Points follow the work** (#1040, the engineer's later answer of 2026-10-15): deliver all 5 delivery items alone
  and you earn 5 points; one point per *task* would make players split the items one each just to farm points. It
  replaces the earlier "one point per task per player" for completion. Aliens may sabotage too (#1040).
- **Points come from work and from mischief only:** task sabotage earns nothing; mischief that provokes the
  neighbours does (#1040, 2026-10-15). An alien who does mischief for points helps the humans; hide-then-deliver earns
  only the delivery; an outed human still earns from mischief, which needs no trust.
- **Completion:** a completed task advances the aliens' goal whoever did it, so a human who does the work earns its
  points and brings the aliens closer to winning: a risk-reward trade that also clears him of suspicion (#1031,
  #1040). **Shared steps:** each player earns a point for his own step (his switch, holding the car, sitting for the
  photo) (#1040).
- **A completed task is locked:** it cannot be undone or farmed (#1040).
- **The scoring must stop abuse:** if sabotage paid, aliens would sabotage just for the points (#1040); that is why
  only work and mischief pay.
- **Kills are not revealed** (the engineer, 2026-10-21,
  [#1095 c6313108955](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6313108955)): no banner of
  who killed whom and no killer line; the game never shows who killed you. It replaces "a killed alien tells everyone
  who killed him" (#1040). How the return from the dead's room is shown: later.
- **What points buy:** a mutation, a global sabotage, or a weapon (§7); calming the neighbours (§5) and stalling the
  cops (§5) also cost points (#1031, #1040).
- **In the MVP points buy three positive mutations** (the engineer, 2026-10-20,
  [#1040 c6289148858](https://github.com/xperiaroco2/prime-game/issues/1040#issuecomment-6289148858)): run faster, jump
  higher, more HP, put on at the mutation workbench in the laboratory. No negative mutations yet. Global sabotages,
  weapons, calming the neighbours and stalling the cops are not in the MVP. What earns points and how many is to be
  validated.
- **No cap on re-sabotaging one task for now:** the aliens outnumber the humans, so two of them kill a camper; the
  intended human plays on the move (#1040).

## 5. The neighbours' anger and the cops

Designed in the chat from research round 2 and the engineer's idea of calling the cops (#1031, comment of
2026-10-15). Two layers, kept apart so each makes sense in the story:

1. **Task sabotage** (in the MVP: paint a car part the wrong shade, let an engine problem run out; GDD §8) slows the aliens against the timer and earns
   nothing (§4). The neighbours do not care about it.
2. **Mischief the neighbours notice** raises the **neighbours' anger** meter. Mischief stations are open knowledge
   and anyone may use them; an alien who does calls the cops on his own party.
   - **Ongoing mischief** (the engineer's examples: music turned up, the barbecue on fire, the bins knocked over, the
     street's lights cut): while it is not dealt with, anger keeps rising a little. The aliens see the meter rise
     and must search for what raises it (#1031, 2026-10-15; the reading "they do not know what raises it" is to be
     confirmed, and whether the type of problem is hinted without its place), then fix it (an extinguisher, pick the
     rubbish up). **Fixing stops the rise; anger already gained stays.**
   - **One-off big mischief**, harder and in several steps (the engineer's example: fireworks fetched from storage,
     carried to the attic or roof and lit: an instant +10% that stays).
   - **Calming the neighbours:** for points, or by an action about as hard as the fireworks (the engineer's example:
     bake a cake for the neighbours and take it to them, about −10%).
   - **The aliens choose:** if the humans only sabotage tasks, the aliens may ignore the meter and push their tasks.
   - **The threshold is a host setting** (e.g. 50 or 100).
   - **Start small:** one ongoing mischief, one one-off, and the timer; more are added one at a time.
   - **The MVP's set** (the engineer, 2026-10-20,
     [#1033 c6289051351](https://github.com/xperiaroco2/prime-game/issues/1033#issuecomment-6289051351)): the meter
     stays; the bins knocked over and loud music (ongoing), the fireworks (one-off, from the pantry). No cake for now.
3. **The meter full: the finale.** The neighbours call the cops themselves: "they arrive in a minute". The aliens have
   that minute to finish. **Any player may spend points at a special place to stall the cops** (a minute more): a
   hidden human may offer, be trusted, and not do it. Not in the MVP (the engineer, 2026-10-20,
   [#1040 c6289148858](https://github.com/xperiaroco2/prime-game/issues/1040#issuecomment-6289148858)).

## 6. Winning

- **The aliens** win by finishing their tasks before the timer and before the cops arrive (#1031).
- **The humans** win **by the timer** (the aliens' goal unfinished when time is up) **or when the cops arrive**: a
  siren, "busted: the party is over" (#1031).
- **An average match lasts about 10 minutes** (GDD §2), **with the humans' spoiling;** a clean team of aliens would
  finish in about 7.5 (the engineer, 2026-10-21, [#1095 c6315676554](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6315676554)). Open: a finale beyond the cops' minute (research round 2: a
  shorter respawn in the last minutes, a capped overtime).

## 6a. The tasks get harder

- **The party is hard on its own** (GDD §1, #1093): aliens who understand nothing and make many mistakes lose even
  without humans; the humans tip the balance and hide in honest mistakes.
- **Harder steps:** find something, look something up, remember something (#1033). Today the House holds only about 3
  to 4 minutes of work for 6 or more aliens (#1089).

## 6a2. The MVP's work per player count (2026-10-21)

- **The counts scale with the players by default, and the host may change them** (the engineer, 2026-10-21,
  [#1095 c6315676554](https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-6315676554); every task type has its own count, #256).
- **The defaults** come from the design track's balance model of the night of 2026-10-21 (prime-game-design
  `ideas/2026-10-21-mvp-balance.md`): placeholders until a playtest. The humans column is the model's assumption (§2
  keeps that open).

| Players | Humans | Car parts | Burgers | Engine stages | Passwords | Photos |
|---:|---:|---:|---:|---:|---:|---:|
| 4 | 1 | 4 | 3 | 3 | 3 | 2 |
| 5 | 1 | 6 | 4 | 3 | 4 | 3 |
| 6 | 2 | 6 | 4 | 3 | 4 | 3 |
| 7 | 2 | 6 | 5 | 4 | 5 | 4 |
| 8 | 2 | 7 | 6 | 5 | 5 | 4 |
| 9 | 3 | 7 | 6 | 5 | 5 | 4 |
| 10 | 3 | 7 | 6 | 5 | 6 | 4 |

- **What the model showed:** the engine is the floor (its stages cannot go faster with more people, about 2.5 to 3.5
  minutes); at 10 players the caps run out, so a tenth player needs another task; parts and burgers need up to 13
  flowers from 5 beds, so watering matters.

## 6b. What the balance model showed (#1089)

A coarse simulation with placeholder numbers, parked until the mechanics mature; structural lessons only:
- the House needs more work, and it must scale with the player count (about 3x at 8 to 10 players);
- a kill is priced by a fair fight (the attacker often loses), not by being outed;
- the side that talks wins, by a wide margin: the humans need tools against the aliens' talk;
- covert spoiling (the wrong herb on a burger) is the humans' best answer to a talking team;
- searching for mischief, rather than a marker that shows where, makes the cops a real path.

## 7. Weapons (direction, deferred)

From #1040, not yet rules:
- **Host settings** like Lockdown Protocol's: no weapons, normal, or lots.
- **Melee spawns on the map** (knives, a club, a baseball bat); maybe a rare pistol spawn.
- **Ranged weapons mostly for points**, with limited ammunition; the engineer's examples: a pistol for 3 points, 10
  rounds at 20 HP each, a headshot crit; a shotgun for 5; a rare, expensive rocket launcher with one round, or
  grenades: blow up three aliens doing something together in the kitchen, once, and a minute later they respawn.
- **The moments he wants:** a human farms points on tasks, then near the end buys a shotgun and goes on a rampage; an
  alien spends all his points on weapons and plays the guard.
- **Why it stays fair** (the engineer, #1040): death is cheap with respawns, so a gun only drags the match out by a
  minute; ammunition runs out; two players who are not into shooters can sprint at a shooter from two sides with
  knives. Macro play (running tasks, managing everything) gives more of an edge than a gun; aim matters for those who
  want it, because the audience includes hardcore players (GDD §1, the amended pillar).

## 8. The House (M8.2)

- **Spaciousness decides it:** even a single room should feel spacious, not a box (#1035).
- **Walls muffle voice:** heard through a wall, but muffled (#1035); the full rule is GDD §11, "Voice through walls".
- The level work, its openings and traversal are #1035, #1036 and #1037; research round 2's level report has the
  options (two rings and a double-height void, chase-breaker geometry, dead ends with one-way escapes, a measurement
  kit first).

## 9. Open

- Sabotages tied to each task, global ones, or both; the humans' tools against the aliens' talk (§6b).
- Points: the unit of work per chain (an item, a switch, a burger, a photo, a car part) (§4).
- How the aliens learn what raises the anger: no hint, or the type of problem without its place (§5).
- Filling 10 minutes: the work scales with the lobby (§6a2); at 10 players another task, or a stream of guests'
  requests (§6a).
- The anger threshold, rises, jumps and the cops' minute (§5): the balance
  model #1089.
- A finale beyond the cops' minute (§6).
- Weapons: which, prices, ammunition, the host presets (§7).
- How the flight is shown (§1); the title (§1).
- The reference frame (§1).
- Mutations, meta-progression and faces: M8.3 (#1040, #1041, #1038).
