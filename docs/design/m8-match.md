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
- **The lobby is the aliens' spaceship;** each match the crew flies down to Earth to party, which later allows several
  party maps with different tasks (an idea, #1031). Open: whether the aliens live in the House or visit it; what the
  House's garage tech becomes if the ship is the lobby; how the trip maps onto Lobby, Countdown, Loading and Pregame.
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
- **The host sets the exact number of humans** (e.g. 3 of 10) (#1032). Open: the defaults per player count
  (research round 2 suggests 4→1, 5→1, 6→2, 7→2, 8→2, 9→3, 10→3).

## 3. Death and respawn

- **Death costs time, not the match** (#1032): about 5 or 6 capsules across the map; to farm an outed human the aliens
  would have to split up and guard every capsule, time they do not spend on tasks.
- **A random capsule** by default; **a perk (mutation) to choose one**; **a few seconds of invulnerability** after the
  respawn (today 3 s) to run, so a respawn among everyone becomes a chase, not a loss (#1032).
- **The wait is 30 s** (decided, tuned by playtest); **no wait that grows per death** (rejected as boring) (#1032).
  Today's rules already respawn at a random free marker after 30 s with 3 s of invulnerability (vision revision 1),
  so the capsules start as those markers.

## 4. Points

- **One point per task per player**, either for completing it or for sabotaging it, never both; aliens may sabotage
  too (#1040).
- **Completion:** every player who took part earns the task's point when it completes (#1040). A completed task
  advances the aliens' goal whoever did it, so a human who helps earns a point and brings the aliens closer to
  winning: his trade-off (#1031).
- **Sabotage credit:** open between two variants (#1040): a sabotage pays only once it has really cost the other
  side time, or sabotages are made universal (e.g. a light room: cutting the House's lights once is one sabotage).
- **A completed task is locked:** it cannot be undone or farmed (#1040).
- **The scoring must stop abuse:** if sabotage pays, aliens will try sabotaging just for the points; the balance has
  to prevent it (#1040). The neighbours' anger (§5) is part of the answer: mischief helps the humans whoever does it.
- **What points buy:** a mutation, a global sabotage, or a weapon (§7); calming the neighbours (§5) and stalling the
  cops (§5) also cost points (#1031, #1040).
- **No cap on re-sabotaging one task for now:** the aliens outnumber the humans, so two of them kill a camper; the
  intended human plays on the move (#1040).

## 5. The neighbours' anger and the cops

Designed in the chat from research round 2 and the engineer's idea of calling the cops (#1031, comment of
2026-10-15). Two layers, kept apart so each makes sense in the story:

1. **Task sabotage** (hide a delivery item, switch the generator off) slows the aliens against the timer and earns
   its point. The neighbours do not care about it.
2. **Mischief the neighbours notice** raises the **neighbours' anger** meter. Mischief stations are open knowledge
   and anyone may use them; an alien who does calls the cops on his own party.
   - **Ongoing mischief** (the engineer's examples: music turned up, the barbecue on fire, the bins knocked over, the
     street's lights cut): while it is not dealt with, anger keeps rising a little. The aliens get a marker ("the
     neighbours complain about the rubbish") and go and fix it (an extinguisher, pick the rubbish up). **Fixing stops
     the rise; anger already gained stays.**
   - **One-off big mischief**, harder and in several steps (the engineer's example: fireworks fetched from storage,
     carried to the attic or roof and lit: an instant +10% that stays).
   - **Calming the neighbours:** for points, or by an action about as hard as the fireworks (the engineer's example:
     bake a cake for the neighbours and take it to them, about −10%).
   - **The aliens choose:** if the humans only sabotage tasks, the aliens may ignore the meter and push their tasks.
   - **The threshold is a host setting** (e.g. 50 or 100).
   - **Start small:** one ongoing mischief, one one-off, and the timer; more are added one at a time.
3. **The meter full: the finale.** The neighbours call the cops themselves: "they arrive in a minute". The aliens have
   that minute to finish. **Any player may spend points at a special place to stall the cops** (a minute more): a
   hidden human may offer, be trusted, and not do it.

## 6. Winning

- **The aliens** win by finishing their tasks before the timer and before the cops arrive (#1031).
- **The humans** win **by the timer** (the aliens' goal unfinished when time is up) **or when the cops arrive**: a
  siren, "busted: the party is over" (#1031).
- **An average match lasts about 10 minutes** (GDD §2). Open: a finale beyond the cops' minute (research round 2: a
  shorter respawn in the last minutes, a capped overtime).

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
- **Walls muffle voice:** heard through a wall, but muffled (#1035). Today voice is pure distance (8 m).
- The level work, its openings and traversal are #1035, #1036 and #1037; research round 2's level report has the
  options (two rings and a double-height void, chase-breaker geometry, dead ends with one-way escapes, a measurement
  kit first).

## 9. Open

- Sabotage credit: the cost-in-time rule or universal sabotages (§4); sabotages tied to each task, global ones, or
  both.
- The defaults for the number of humans (§2); the anger threshold, rises, jumps and the cops' minute (§5): the balance
  model #1089.
- A finale beyond the cops' minute (§6).
- Weapons: which, prices, ammunition, the host presets (§7).
- Whether the aliens live in the House or visit it (§1); the title (§1).
- The reference frame (§1).
- Mutations, meta-progression and faces: M8.3 (#1040, #1041, #1038).
