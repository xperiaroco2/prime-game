# Vision revision 1: no ghosts, knockdown and respawn, two hands, hiding as sabotage

- **Status:** Accepted: the engineer with the designer. Dmytro (the engineer) confirmed every item of #126 on
  2026-10-01 and the same day answered the review of the first draft (V1 to V13), agreed with the designer and
  relayed by the engineer; the designer (@SwiftySinister) confirms on the PR
- **Date:** 2026-10-01
- **Deciders:** Dmytro (xperiaroco2), from the meeting with the designer on 2026-09-30 and the idea inbox (IDEA-1 to
  IDEA-20), item by item on 2026-10-01 in the project chat (recorded on #126); the answers V1 to V13 in chat with the
  M3 manager session on 2026-10-01 (recorded on PR #127, which this ADR's PR supersedes)
- **Amends:** [MVP rules](2026-09-29-mvp-rules.md),
  [game modes define the phases](2026-09-29-game-modes-define-the-phases.md),
  [match loop, intents and events](2026-09-29-match-loop-intents-events-and-entitlement.md),
  [content API v0](2026-09-29-content-api-v0.md)

## Context
The [MVP rules](2026-09-29-mvp-rules.md) were decided before the game had a vision of its own. Since then a vision
formed: fun from the first second, deduction not central, no permanent death, active sabotage, a "cringe-fun" vibe,
an audience that is not only guys, and macro skill over micro skill. Several MVP rules contradict it, and code is
already built on them (ghosts in `core/life/`, `core/voice/round_voice.gd`, `client/player/player_controller.gd`; one
hand slot in `core/items/items.gd`; the `no_crew_alive` win condition in `content/`). M4's design (#125) would build
ghosts, the one hand slot and the HUD in 3D. This revision changes the rules before M4 builds more on the old ones.

A three-angle review of the first draft (PR #127: the code impact, the network and M4 impact, open questions) found
what it left to the programmer: what a dead spectator receives, what the map shows, how a revive works, what a downed
player may do, how a pickup fills two slots, and what ends a round when no crew member is left. The engineer answered
it as V1 to V13: the numbers, each question and its answer are the table in
[the comment on PR #127](https://github.com/xperiaroco2/prime-game/pull/127#issuecomment-5930164701), and the tags here
are that table's (the chat's own numbering differed; V8 and V9 were read back and confirmed). Each answer is
written into the Decision below and cited as (Vn); what they still leave open is under "Needs the engineer".

## Decision

### Vision pillars (GDD §1)
- **Fun from the first second.** The lobby, customization, gestures and proximity voice are fun before any match.
- **Deduction is not central.** Each side plays to its own goal. Roles are dealt privately, but the game does not rely
  on keeping them secret: knowing who a dissident is helps, it does not win, and a dissident may even say so himself.
  Everyone plays their role through actions, not through manipulation or lying (unlike Lockdown Protocol). What a
  dead player saw while spectating is fair game after the respawn (V1).
- **Death does not take you out of the game, and killing is not a win.**
- **Action over long discussions.** Run, do tasks, outwit.
- **Cringe-fun vibe**, and an audience that is not only guys.
- **Macro skill over micro skill.** Mechanics are simple; no aim-heavy or one-shot mechanics. Decisions, teamwork
  and communication win, and a player who never plays shooters has as much fun as anyone.
- **Open knowledge.** The rules, how every mechanic works and the fixed places (the map, the task circles, the item
  spawn points) are known to everyone, dissidents included. Who the dissidents are is dealt privately, but it is not
  a secret the game protects. Where a moved item lies now is not shown: players find it by looking (V1, V2).

The engine's filtering does not change: roles still reach only the peers entitled to them (architecture invariant 2),
and the leak test still checks it. The pillar is about game design, not about what the host sends.

### Words
| Word | Meaning |
|---|---|
| **Living** | Upright: the life state ALIVE. Wherever a rule says "living" (who does subtasks, carries packages, is hit, raises a downed player, is watched first by a spectator), it means ALIVE, never downed (V4) |
| **Downed** | Knocked down (DOWNED), until a revive, giving up or the knockdown time running out |
| **Dead** | DEAD, until the respawn |
| **Left** | LEFT: the player left the match. Every other player is **present** |

### Roles
- Players read the good side as **Engineers**: the role's display name is "Engineer", the side's "Engineers", and the
  end screen says "The Engineers won". The ids in the data stay `crew`. The names are provisional until the game's
  setting is known (V12). The docs say `crew` for the id and Engineers for anything a player reads.
- **Dissidents sabotage actively.** In the MVP the sabotage is **hiding packages**: a dissident carries a package
  away and puts it down where the engineers will not find it soon. It needs no new mechanic: anyone may already carry
  any package.
- A package may be hidden anywhere a put-down allows (V13). The level rule that keeps it findable: every spot a
  put-down can reach must be reachable for a pickup (pick-up reach and line of sight from where a player can stand);
  the designer checks it per level (`levels/CLAUDE.md`). If playtests still find dead spots, the fallback is that a
  package nobody touches for N s returns to its spawn point; it is not built now.
- "A dissident cannot win by waiting" is a **playtest target**, not a rule: with no sabotage, the default settings
  finish within about 60% of the match time (V13).

### Win conditions
- **Removed:** "the dissidents win when every crew member is dead" (`no_crew_alive`). Killing takes time from the
  engineers; it never wins.
- **Added: no crew present.** When every crew member has left the match, the dissidents win (V10). A downed or dead
  crew member is still present: they come back. It is `NoneAlive` limited to players who left, in the place
  `no_crew_alive` held in the mode's order.
- Otherwise the dissidents' only win is the timer ending with tasks left (unchanged, also with 0 dissidents).
- The engineers' only win: every task done before the timer ends (unchanged).

### Items: two hands (V5, V13)
- A player has **two one-handed slots**: the **hand** and the **belt**. The belt holds at most one item and is
  **visible** on the body to everyone, as the hand item is. A key swaps hand and belt.
- Every item kind has **`hands`: 1 or 2**. The knife is one-handed. The Delivery package is two-handed: it is on the
  ground or in the hand, never on the belt.
- **Picking up:** the picked item always goes to the hand. If the hand holds a one-handed item and the belt is
  empty, the hand item moves to the belt. Otherwise the hand item is swapped: it rests where the picked item lay, a
  spot already known to be valid. That holds whether the package is the picked item or the hand item, and it
  replaces the first draft's "drops in front of the player".
- A player with two items always has one in hand, never both on the belt. A player with one item may carry it on the
  belt with an empty hand.
- **Swap** is refused while a two-handed item is in the hand, so a package carrier cannot draw a belted knife (V13);
  with both slots empty there is nothing to swap.
- **Only the hand item is used:** `Use` and the put-down key act on it alone.
- One player may carry both knives, one in hand and one visible on the belt (V13).
- **What drops:** nothing at a knockdown (a downed player keeps both slots). At death both slots drop at the body. A
  player who leaves drops both where they stood.
- `hands` is also the slot model that later loot builds on. Nothing else is built for loot now.

### Life: knockdown, death, respawn
Replaces "Death and ghosts". There are no ghosts.

| State | Moves | May do | Struck | Heard by | Hears | Sees |
|---|---|---|---|---|---|---|
| Living | walks, sprints, jumps | everything Round accepts | yes, unless invulnerable | the living and the downed, by proximity | the living, by proximity | first person |
| Downed | crawls | crawl and give up, nothing else | never | nobody | the living, by proximity from where they lie | third person above the body |
| Dead | not at all: no avatar | nothing | never | nobody | no voice; the world sounds around their target, and lift music | the target's camera |

**Knockdown** (V4, V13)
- At 0 health a living player is **knocked down** where they stand, for the knockdown time (10 s). Everyone learns it
  from a public event that names no attacker, as a death's names none.
- A downed player can only **crawl** and **give up**. Crawling: the crawl speed (1 m/s), climbing the step height, no
  jump, no sprint and no stamina cost; they collide with the level, not with the living, and push nobody.
- They keep their items in their hands and cannot use, put down, pick up or swap them.
- Strikes skip a downed player: they **cannot be hit**.
- Crawling into a circle with the package and giving up, so that the package drops at the body inside its circle and
  counts, is legal (V4).
- The camera goes third person above the body, no higher than a standing player's eye height (1.6 m) above it,
  and it collides with the level. A package is hidden by sight only, so being downed (or watching a downed player)
  must not show over cover or around corners more than standing at the body would ("Needs the engineer" 9).

**Revive** (V3)
- Any living player, dissidents included, may **raise** a downed player by holding E for 3 s, within reach and in
  sight of them (the pick-up's reach of 2 m and its line of sight), checked by the host.
- The knockdown timer **pauses** while someone raises; a raise that is cancelled lets it run on from where it paused.
- A downed player **does not crawl while being raised**: the host accepts no displacement from them while a raise runs
  (any is corrected), so they stand up where they lay. Otherwise a teammate could
  restart the raise just short of 3 s while walking beside a crawling package carrier whom nobody can hit, and the
  10 s bound on a downed carrier would be gone ("Needs the engineer" 8).
- A raise is **cancelled** by: releasing E, the raiser moving out of reach, the raiser being hit or downed, the raiser
  starting another action (pick up, put down, use, swap), or the downed player giving up. One raiser at a time
  ("Needs the engineer" 4).
- The public event that a raise stopped names the raiser and the downed player only, never a cause. A raise that
  stops in the tick of a swing still tells the attacker, and everyone else, that the swing hit the raiser: an accepted
  exception to "the attacker gets no hit confirmation" (#32), as a knockdown already is ("Needs the engineer" 7).
- A revived player stands up where they lay with **50 health** (a placeholder in data). Stamina is not reset: it
  regenerates as usual, since a downed player spends none. They are **invulnerable** for 3 s.

**Give up**
- A downed player may give up at any time, even while someone is raising them: they die at once, and the raise is
  cancelled. Giving up is the way out of being raised again and again, and of a raiser who stops just short of 3 s
  to keep the timer paused.

**Death** (V1, V7, V9, V11)
- A downed player **dies** when the knockdown time runs out (it cannot while a raise pauses it) or when they give up.
  Both slots drop at the body, which lies where the downed player was.
- The **body stays until its player respawns**; then it is removed, with a public event (V7).
- The dead have no avatar, send no intents and are heard by nobody.
- **Spectating:** a dead player watches a living or downed player through that player's camera (first person, or a
  downed player's third person), dissidents included. The view is built on the dead player's own client from the
  public snapshot every player receives: no target HUD, health, stamina, role or private event, and no new host feed.
  Whom a dead player watches never leaves their client, and the target is never told (V1, V9).
- **The target** (V9): first a random living player, chosen by the dead player's client with its own seeded
  generator (the purpose `spectate`, so a test can pin it; core's RNG streams are not used, because their seeds never
  leave the host, ARCHITECTURE §5). It is never the attacker by default: the client does not know who that is. A key
  cycles through the living and downed players. The camera switches by itself when the target goes down, dies or
  leaves. With nobody to watch, see "Needs the engineer" 6.
- **Hearing** (V11): the dead hear no voice at all. They hear the world sounds around their target (steps, swings,
  items), rendered by their client from public data, and lift music that only their client plays.

**Respawn** (V6)
- A dead player **respawns** after the respawn time (30 s from the death) at a random free respawn point: a marker
  with the new tag `respawn`, which the layout check demands. The marker is drawn uniformly from the free ones with
  core's RNG purpose `respawn` (from all of them when none is free: "Needs the engineer" 5).
- They keep their role, get full health and stamina and empty hands, and are **invulnerable** for 3 s. Everyone learns
  the respawn from a public event, and the body is removed.

**Invulnerability** (V8)
- For 3 s after a revive or a respawn, strikes skip the player: no damage and no damage event. Pushing works as usual.
- The player's own attack ends it at once (any attack, hit or miss: "Needs the engineer" 3).
- It is visible to everyone.
- Nobody has it at the start of a round.

**Leaving** (V7)
- A player who leaves mid-round disappears, everyone sees "X left", and both slots drop where they stood. A raise of
  them, or by them, is cancelled. A downed player who leaves leaves no body; a dead player's body is removed when
  they leave ("Needs the engineer" 1).

**Countdowns** (V13): the knockdown and respawn countdowns are shown only to their own player. Each follows from
public events and the mode's numbers, so this is a rule of the interface, not of what the host sends.

### Voice (V11)
- **An engine invariant:** nobody hears a downed or dead player, under any voice rule, and a dead player hears no
  voice. No mode's data can route their voice, as no mode's data can route a ghost's to the living today.
- The living hear the living by proximity (unchanged). A downed player hears the living by proximity, measured from
  where they lie.
- The ghost hearing radii and the dead's own voice group (dead chat) are gone.

### HUD and the task screen (V2)
- The HUD shows health, stamina, the hand item and the belt item; a package also shows its destination; the shared
  task progress.
- A **task screen** on Tab, for every player, living, downed or dead: the match's tasks, each with a short description
  and its shared progress, and a **map** of the task circles (where tasks are done), the items' spawn points and the
  viewer's own position. The map never shows an item's current position and never other players. Which spawn
  points: "Needs the engineer" 2.
- A dead viewer has no avatar, so their map shows no own position: not their body (a body is no position of theirs)
  and never their spectate target (another player). A downed viewer's own position is where they lie.

### Hidden information
| What | Who learns it |
|---|---|
| Roles | Each player their own; dissidents each other (unchanged). Not otherwise protected by the game's design (V1) |
| Health, stamina, damage | Only that player (unchanged). A spectator never gets the target's |
| Living and downed avatars: position, velocity, facing, downed and invulnerable, the hand and belt items | Everyone, in the snapshot |
| A dead player's avatar | Nobody: the dead have none |
| Knockdowns, raises starting and stopping, revives, deaths with the body, respawns, a body removed | Everyone. None names an attacker, and a raise stopping names no cause. A knockdown, and a raise stopping in the tick of a swing, confirm that swing's hit: the accepted exceptions to #32's "no hit confirmation" |
| Items on the ground, wherever they lie | Everyone on the wire, as today (#32: positions are not hidden behind walls, which would protect against cheating clients, which nobody asked for). No screen shows an item's position beyond what is in view, the map included, so a hidden package is hidden by sight |
| Whom a dead player watches | Nobody: it never leaves their client |
| Voice | The invariant under Voice |

### Placeholder numbers: not a decision
| Number | Placeholder |
|---|---|
| Knockdown time (crawl, can be raised) | 10 s |
| Time to raise a downed player (hold E) | 3 s |
| Health after a revive | 50 (V3) |
| Reach and sight for a raise | the pick-up's: 2 m and its line of sight |
| Respawn time after death | 30 s |
| A respawn marker is free when no living or downed player stands within | 1 m |
| Respawn markers the layout check demands | at least 1 |
| Invulnerability after a revive or a respawn | 3 s |
| Crawl speed | 1 m/s |
| Highest point of the downed camera above the body | 1.6 m, the standing eye height |
| Playtest target: with no sabotage, the default settings finish within | about 60% of the match time (V13) |

### Closed and parked
- **Meetings mode (#35):** closed; it does not fit "deduction is not central".
- **Resurrection (#34):** replaced by this revision's knockdown and respawn; closed or rewritten.
- **Classes:** not planned.
- **Parked:** deathmatch mode, fixed task locations, maps and settings, other sabotages (light panel, generator,
  molotov), a package that returns to its spawn point (above).
- **Later:** loot (consumables, gear, cases with mega-items). The content API leaves room for it through the item
  kinds' `hands` field, the slot model; nothing else is built for it now.
- **Later, after the MVP:** customization from ready-made parts and masks with an animated mouth (#73), gestures and
  a hand ping seen only in view.

## Needs the engineer
V1 to V13 leave these open. Each has options and a recommendation; the docs and the rework follow the recommendation,
which can be reverted.
1. **A dead player who leaves:** (a) their body is removed at the leave; (b) it stays for the rest of the round, as
   V7's letter ("until its player respawns") reads. Recommended (a): a body then always means a player who is coming
   back, and a body of someone who left would lie there as a false promise for up to an hour.
2. **The map's item spawn points:** (a) the points where this match's items spawned (the public `ItemSpawned`), each
   marked with its kind, a package with its colour; (b) every item spawn marker of the level, drawn into the map
   asset. Recommended (a): it tells the engineers where each package started, which is where to begin looking, and
   it never follows the package once it moved.
3. **What ends invulnerability:** (a) any accepted attack, hit or miss; (b) only a hit. Recommended (a): the attacker
   gets no hit confirmation (ARCHITECTURE §4.2), and a visible protection that ended only on a hit would give them one.
4. **Raising, in detail:** (a) one raiser at a time (a second player's raise is refused while one runs); a raiser may
   hold the package (a raise needs no hand); losing sight cancels like moving out of reach (the start conditions
   are checked every tick); (b) raisers stack and finish sooner. Recommended (a): one progress per downed player and
   one set of checks.
5. **No free respawn marker:** (a) draw uniformly from every respawn marker (players push apart, ARCHITECTURE §7.1);
   (b) wait until one is free. Recommended (a): a respawn is never delayed by where others stand.
6. **A spectator with no target:** (a) with no living player the first target is a random downed one; with nobody
   living or downed, the camera stays above the player's own body; (b) a fixed overview camera. Recommended (a): no
   new camera for a rare case.
7. **A raise cancelled by a hit confirms the hit** (found by the review of this ADR's PR): V3 cancels a raise when
   the raiser is hit, and a raise stopping is public, so a dissident who jabs a raiser sees the raise stop in the
   same tick and knows the jab landed, which #32 otherwise denies the attacker. (a) Keep V3 as answered and accept
   the confirmation as an exception, like the knockdown's; the stop event carries no cause; (b) drop "being hit" from
   the cancels, so only the raiser going down stops it. Recommended (a): it is the engineer's answer, the attacker is
   within a knife's 1.5 m and usually sees the raiser stop anyway, and under (b) a raise could be finished under
   fire.
8. **A raise restarted again and again** (found by the review): the pause lets a teammate keep a downed package
   carrier, whom nobody can hit, alive without limit by restarting the raise before it completes. (a) The downed
   player does not move while a raise runs, so the stall can only hold them in place, where the raiser can be hit
   and downed; (b) as (a), and a raise that ends without completing also uses up the time it paused, so the 10 s
   bound holds exactly; (c) a cooldown for a raiser after a cancelled raise. Recommended (a): it keeps V3's pause
   as answered and removes the unhittable courier; (b) is the step up if playtests find stalls in place.
9. **How far the downed camera sees** (found by the review): "third person above the body" sets no bound, and a
   high camera would make a knockdown a way to scout hidden packages. (a) No higher than the standing eye height
   above the body, colliding with the level; (b) a fixed low camera behind the body. Recommended (a): it keeps the
   third person the engineer chose and sees no more than standing there would.

## Alternatives
- **Many small mechanic issues, one per change:** each would be decided alone, and M4 would keep building on the rest
  of the old rules in the meantime.
- **Rewriting the MVP rules file in place with no record:** the history of why ghosts were dropped would be lost.
- **Restricting spectating** (crew watch only crew; only players near the body; a delay): a list that leaves out
  dissidents reveals who they are by itself, and the others protect a secret the game no longer relies on (V1). The
  first draft's reason for muting the dead ("so they cannot overhear the dissidents' plans") is withdrawn with it; the
  rule that the dead hear no voice stays (V11).
- **A host-routed spectator feed** (a `Spectate` intent, an audience "spectators of p", the target's HUD): a new path
  for private data such as `SelfStatus` or `Teammates` to reach the wrong peer, and more for the leak test to guard;
  the public snapshot already holds what the camera needs.
- **The map showing where items are now:** a dissident's only sabotage would undo itself, since the map would point
  at every hidden package.
- **A two-handed pickup that drops the hand item in front** (the first draft): `PickUp` carries no facing, the drop
  needs a new geometry query, and "in front" can be inside a wall; the picked item's spot is already known to be
  valid. **A one-handed pickup to the belt first:** the player would not hold what they reached for.
- **A revive by one tap that then runs alone:** a raiser could tap and leave, and a hit could not stop it.
  **Progress that survives an interruption:** a raise could be built up in pieces under fire. **The knockdown timer
  running during a raise:** a raise started at 8 s would fail at 10 s with the raiser doing everything right.
- **Full health after a revive:** a 3 s raise would undo the two knife hits it took to down the player, so downing
  would hardly matter. The number stays a placeholder (50, one hit).
- **Invulnerability that the player's own attack does not end:** a revived or respawned player could stab for 3 s at
  no risk. **Hidden invulnerability:** an attacker would swing at a protected player with no way to know why nothing
  happened, against Open knowledge.
- **Respawning at the round's start markers or at the body:** the round's markers are placed for the start of a match,
  not for one player mid-round; at the body the attacker who downed them is likely still there.
- **The body staying for the whole round:** the same player would appear twice, as a body and as a respawned avatar.
  **No body at all:** nothing would show where a player died and their items dropped.
- **Every crew member left, and the round runs to the timer** (no new condition): a round with only dissidents left
  would run for up to an hour. **No winner:** the dissidents' sabotage would count for nothing.
- **Voice for downed and dead players as mode data only:** a mode's data could route their voice, and the leak test
  would depend on that data.
- **"Living" including the downed, or a downed player who may put down and swap:** a downed carrier could hand the
  package on or hide it while nobody can hit them.

## Consequences

### Documents changed with this ADR
- The [MVP rules](2026-09-29-mvp-rules.md): Roles, Win conditions, Tasks, Items, Health and stamina, Collisions,
  "Death and ghosts" replaced by "Knockdown, death and respawn", Voice, Meetings, the match loop's end screen, HUD,
  the placeholder table, the #32 answers it overrides, "Not in the MVP" and Alternatives.
- `docs/GDD.md` (the designer's file, agreed with the designer and relayed by the engineer, #128): §1's pillars, §3's
  Round and later modes, §9 dropped, §10 and §11 answered, §14's bodies.
- "Amended by vision revision 1" lines in [game modes define the phases](2026-09-29-game-modes-define-the-phases.md),
  [match loop, intents and events](2026-09-29-match-loop-intents-events-and-entitlement.md) and
  [content API v0](2026-09-29-content-api-v0.md). "A mode can add phases" stays a requirement, with the parked
  deathmatch and the zone task (#36) as its examples instead of the meetings mode.
- `docs/ROADMAP.md`: the MVP sentence, M2 and M5. `client/CLAUDE.md` (the Tab task screen replaces meetings and
  voting), `content/CLAUDE.md` (the edge cases of an engine request) and `levels/CLAUDE.md` (the put-down rule and
  respawn markers). `docs/ARCHITECTURE.md`'s status row points here.

### ARCHITECTURE sections the rework updates
ARCHITECTURE describes the code as built, so each section changes in the rework issue that changes its code:

| Section | What changes |
|---|---|
| §3 intro, §3.1 | life states ALIVE, DOWNED, DEAD, LEFT; `AcceptSpec` senders (the downed and the dead instead of ghosts); the meetings mode as the example of more phases (the parked deathmatch and #36 instead) |
| §3.2 | Round's accepts: `MoveClaim` from the living and the downed, give up from the downed, raise and swap from the living; `ResetMatch`'s ordering note about ghosts |
| §3.3 | the clock paused for a meeting as the example |
| §3.4 | `no_crew_alive` out, no crew present in; the "last crew member killed over its circle" ordering example |
| §3.5 | leaving while downed or dead; the body's lifetime |
| §4.1 | intents: crawling, give up, raise and its stop, swap; `PickUp`'s two-slot rule |
| §4.2 | events: knocked down, raise started and stopped, revived, respawned, body removed, the belt, per-task progress; `Correction` no longer at a death; `ItemPlaced`'s causes |
| §4.3 | the Snapshot avatar's flags (downed and invulnerable instead of ghost) and belt item; the new rows; the protocol version; the 1024 B snapshot budget rechecked |
| §4.6 | the client's life state, claims while downed and none while dead; the bots' and the leak test's invariants |
| §5 | Open knowledge as reworded above; widening at a knockdown, death and respawn; "knowledge never shrinks" with spectating instead of #34; the invariants |
| §6 | the voice invariant and `RoundVoice`'s radii; dead chat and meetings out of the open items |
| §7, §7.1 | ghost movement (`ghost_speed_factor`, the ghosts' layer, the stamina exemption) replaced by the crawl; pick-up and swap with two slots; the raise's reach and sight; invulnerability in `Strike` |
| §9.1 | "later #35's votes" as the example of phase-lived state (the zone task #36 instead) |
| §9.2 | the `item_rested` causes; the ordering example of §3.4 |
| §9.3 | `MatchState` (life, the belt, timers, bodies), `LifeRules`, `Items` |
| §9.4 | the parts `NoneAlive`, `TakeIntoHand`, `Strike`, `StaminaCost`, `Proximity`, `RoundVoice`; the new parts; `ReportOutcome`'s example (a meeting button, #35) |
| §9.5 | Crew's display names, No crew alive replaced, PickUp, Use, Sprint and Jump's ghost lines, the base mode's voice and movement numbers, the items' `hands` |
| §9.6 | `no_crew_alive.tres` in the data list; the `respawn` tag; the map asset |
| §9.7 | `WalkTo`'s ghost speed; the scenarios that script a ghost |
| §9.8 | the extensibility test's resurrection and meetings examples |
| §10 | the M5 row: dead chat and meetings out |

### The rework, for #125 to split into M4 issues
Counted on main on 2026-10-01: `git grep -l GHOST -- '*.gd'` lists 48 files, and
`git grep -l -i ghost -- '*.gd' '*.tres'` lists 78.

The order below keeps `verify` green after every item. Two rules hold for each of them:
- A new intent or event gets its wire row, its codec sample and a `JoinRules.PROTOCOL_VERSION` bump in the same PR,
  with ARCHITECTURE §4.1 to §4.3 updated for it: `WireSchema.encode` refuses a message with no row, so a later
  "protocol issue" would leave every earlier item red over ENet.
- The leak test's and `ScenarioInvariants`' checks change in the PR that changes what they check, written apart from
  the declarations, each new one proven by a planted leak.

1. **Respawn markers (levels, the designer).** `spawn_respawn` markers in the greybox. The host's marker reader
   already reads any `spawn_<tag>` group (`server/levels/marker_reader.gd`) and nothing demands the tag yet, so this
   lands first and independently, and item 4's demand finds the markers.
2. **The life model, in one PR, as a rename.** `PlayerState.Life` becomes {ALIVE, DOWNED, DEAD, LEFT}; `is_alive()`
   means ALIVE only. In this step DOWNED takes over GHOST's behaviour unchanged (0 health leads to it with no timer;
   the body, the speed factor, who sees and hears it), so behaviour and tests change only where names do, and DEAD
   is not reached yet; this transitional state exists only between M4's PRs. `AcceptSpec` gets an explicit DOWNED
   flag in GHOST's place, and Round's accepts in `base_mode.tres` are rewritten on purpose. GHOST's old bit is never
   reused for DEAD: that would accept the dead's `MoveClaim`. A DEAD flag is added only when a mode needs one, since
   the dead send no intents. The leak test's ghost invariant is renamed to the downed (true until item 4). The
   avatar's wire bit keeps the name `ghost` and is set from DOWNED (`core/match/snapshots.gd`), so this item changes
   no protocol. One PR, because a removed enum value is a parse error in every file that names it.
3. **The voice invariant.** `VoiceRule.speakers_of` drops every speaker who is not living and gives a dead listener
   nobody, before asking the mode's rule; `RoundVoice` keeps `living_m` only, a downed listener hearing from where
   they lie; the ghost radii leave `base_mode.tres`. Tested through a fixture mode whose rule lets everyone hear
   everyone. In the same PR the leak test checks: no peer's speakers include a downed or dead speaker; a dead peer's
   speakers are empty; a downed peer hears only living speakers. ARCHITECTURE §6.
4. **Knockdown, death and respawn.** The downed become what this ADR says: visible to everyone (the snapshot no
   longer hides them; the wire bit `ghost` is renamed `downed`, a version bump), crawling at the crawl speed, which
   replaces `PlayerRules.ghost_speed_factor` with `ModeCheck` bounds. The host's crawl check is named: the allowed
   travel is the crawl speed times the ticks covered, with no sprint ticks and no push allowance; a new jump is
   corrected; the allowed rise is the step height. `movement_rule_test` covers a downed claim with sprint, with a
   jump and with a step-height rise (today `movement_rule.gd` lets a ghost sprint and jump for free). A tick system
   in `core/life/` with per-player deadlines (the knockdown, which item 5 pauses; the respawn); the public events
   and their facts; bodies that live until their player respawns (`MatchState.bodies` is keyed by peer, enough
   while a player has at most one body); a respawn effect with the marker tag `respawn`, the RNG purpose `respawn`
   and a `Demands` entry of at least 1. A `Correction` at the knockdown (a new epoch, so walk-speed claims in flight
   drop as stale instead of failing the crawl check) and at the respawn, none at a death; the scenario runner and
   the bots treat both as placements (ARCHITECTURE §9.7 fails a scenario on a `Correction` outside one), and bots
   stop claiming while dead, crawl while downed and adopt the respawn's `Correction`. In the same PR, because with
   `is_alive()` meaning ALIVE a moment with every crew member down would otherwise end the round:
   `no_crew_alive.tres` is replaced by the no crew present win (`NoneAlive` limited to LEFT, in the same place in
   the order), and `dissident_kills_the_crew.tres` (the bots-over-ENet verify step, the only scenario with deaths)
   is rewritten to knock down, die, respawn and end by time up with a short match. The leak test drops the downed
   invariant of item 2 and checks: no snapshot holds a dead player's avatar; a dead peer receives no event or field
   it would not receive living. `life_rules_test` covers every transition, leaving while downed or dead included.
5. **The raise and the give-up.** A generic channel primitive (start, progress in a tick system, cancel or
   complete), which the zone task (#36) can reuse; the first action that targets a player (conditions: the target
   is downed, in reach, in sight, checked every tick); one raiser at a time; the knockdown timer paused; the downed
   player held in place while a raise runs; each cancel of the Revive section, the raise-stopped event naming no
   cause; the revive health from data; the give-up as data (a die effect accepted from the downed). Unit tests for
   each cancel and for a restarted raise that cannot move the downed player.
6. **Invulnerability.** An until-tick on the player; `Strike.targets` skips them before any `Damaged`; the player's
   own accepted attack ends it; a public avatar flag (a version bump); nobody has it at the round start;
   `strike_test` cases.
7. **Two hand slots.** `ItemKind.hands` (1 or 2), set on the package (2) and the knife (1) in the same PR; a belt
   slot on the player; `ItemState.Where` gains the belt; `Items.take`'s new rule; the swap intent and effect,
   refused while a two-handed item is in the hand; `Match._find_action` reads the hand only; death and leaving drop
   both slots. The owner never receives its own avatar, so its own slots follow from events. The avatar's belt item
   on the wire, and the 1024 B snapshot budget rechecked. `refusals.tres` (which expects a swap where the belt now
   takes the knife) is updated in the same PR.
8. **The task screen's data.** A public per-task progress or "tasks dealt" event, emitted by the deal and by
   Delivery, in the task events the leak test compares (`TASK_EVENTS`); a `description` on `TaskType`, checked by
   `ModeCheck` and filled in `delivery.tres`.
9. **More bot scenarios.** A revive, a give-up and a respawn, a hidden package, a two-handed pickup with a full
   belt; new steps for raise, give up and swap. (The scenarios an item breaks are fixed in that item.)
10. **Content data.** Crew's display names (Engineer, Engineers); the knockdown, raise, revive health, respawn,
    invulnerability and crawl numbers in `base_mode.tres` with `ModeCheck` bounds, where an earlier item did not
    already add them.
11. **The client (M4).** `ClientModel` folds an explicit life state from the life events instead of "has a body"
    (today `is_alive()` and `ClientSession._claims_accepted` would leave a respawned player dead). The own player:
    the downed pose and crawl (the ghosts' physics layer becomes the downed's), a third-person camera within the
    bound of the Knockdown section that collides with the level (for example a `SpringArm3D`), the give-up and
    hold-E inputs with the raise's progress, the own countdowns, the swap key, hand and belt in the HUD. Other
    players: the downed pose, the invulnerable flag, hand and belt on `RemotePlayerBody`, bodies appearing and being
    removed. The spectate camera from `ClientModel` only, with target cycling, its seeded generator, the world
    sounds and lift music. It needs the look pitch: M4's controller sends the camera's look vector in
    `MoveClaim.facing`, with `Strike` and `Swung` flattening it to the horizontal before use (it is `Strike`'s
    fallback zone direction and `Swung`'s public facing), or the avatar gains a pitch; M4 does not lower the
    snapshot rate without checking spectating. The Tab task screen and its map. `set_ghost` and its tests go.
12. **The map asset (levels).** A map asset per level inside the content hash (#118), with the task circles and item
    spawn points drawn over it (from the public events, or from the level's markers if "Needs the engineer" 2 goes
    the other way); the put-down rule of `levels/CLAUDE.md` checked in a playtest.
13. **Review.** M4's adversarial review checks that spectating and the task screen render nothing from private or
    out-of-sight data, and that the downed camera sees no more than a standing player at the body would.

### Issues
- #125 (M4 design) designs death, items and the HUD by this revision and splits the rework above.
- #34 (resurrection) and #35 (meetings mode) are closed or rewritten after the merge; the engineer closes #127.
- #126's edge case "a player leaving while downed or dead: as today, no body stays": its "as today" was wrong (today a
  ghost's body stays, ARCHITECTURE §3.5), but its rule stands under "Needs the engineer" 1 (a): a downed or dead
  player who leaves leaves no body. A comment on #126 of 2026-10-01 had read V7 as keeping the body of a player who
  left; the handoff comment on #126 retracts that reading.
