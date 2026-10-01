# Vision revision 1: no ghosts, knockdown and respawn, two hands, hiding as sabotage

- **Status:** Proposed: Dmytro confirmed every item on 2026-10-01; the designer confirms in the PR (#126)
- **Date:** 2026-10-01
- **Deciders:** Dmytro (xperiaroco2), from the meeting with the designer on 2026-09-30 and the idea inbox (IDEA-1 to
  IDEA-20), item by item on 2026-10-01 in the project chat; recorded on #126

## Context
The [MVP rules](2026-09-29-mvp-rules.md) were decided before the game had a vision of its own. Since then a vision
formed: fun from the first second, deduction not central, no permanent death, active sabotage, a "cringe-fun" vibe,
an audience that is not only guys, and macro skill over micro skill. Several MVP rules contradict it, and code is
already built on them (ghosts in `core/life/`, `core/voice/round_voice.gd`, `client/player/player_controller.gd`; one
hand slot in `core/items/items.gd`; the `no_crew_alive` win condition in `content/`). M4's design (#125) would build
ghosts, the one hand slot and the HUD in 3D. This revision changes the rules before M4 builds more on the old ones.

## Decision

### Vision pillars (GDD §1)
- **Fun from the first second.** The lobby, customization, gestures and proximity voice are fun before any match.
- **Deduction is not central.** Each side plays to its own goal; knowing who the dissident is helps, but does not
  end the match.
- **Death does not take you out of the game, and killing is not a win.**
- **Action over long discussions.** Run, do tasks, outwit.
- **Cringe-fun vibe**, and an audience that is not only guys.
- **Macro skill over micro skill.** Mechanics are simple; no aim-heavy or one-shot mechanics. Decisions, teamwork
  and communication win, and a player who never plays shooters has as much fun as anyone.
- **Open knowledge.** How every mechanic works and where things are is known to everyone, dissidents included. Only
  who the dissidents are is hidden.

### Roles
- The good side is shown to players as **Engineers**. Only the display name changes: the id in the data stays
  `crew`.
- **Dissidents sabotage actively.** In the MVP the sabotage is **hiding packages**: a dissident carries a package
  away and puts it down where the engineers will not find it soon. It needs no new mechanic: anyone may already carry
  any package. A dissident cannot win by waiting.

### Win conditions
- **Removed:** "the dissidents win when every crew member is dead" (`no_crew_alive`). Killing takes time from the
  engineers; it never wins.
- The dissidents' only win: the timer ends with tasks left (unchanged, also with 0 dissidents).
- The engineers' only win: every task done before the timer ends (unchanged).

### Items: two hands
- A player has **two one-handed slots**: one **in hand** and one **on the belt**. A key swaps them. The belt item is
  **visible** on the body to everyone who sees the player.
- A **two-handed item** (the Delivery package) is either on the ground or in both hands, never on the belt.
- Picking up a two-handed item needs the hand slot free. The belt item stays on the belt, but while the two-handed
  item is held the player cannot swap to it.
- Picking up a two-handed item with a one-handed item in hand: if the belt is empty, the hand item goes onto the
  belt; if the belt is full, the hand item drops from the hand (put down in front of the player, as by the put-down
  key). Either way the player then holds the two-handed item, and the belt item stays where it is.

### Health: knockdown, death, respawn
Replaces "Death and ghosts". There are no ghosts.
- **Knocked down** at 0 health: the player falls, the camera goes third person above the body, and for about 10 s
  they can **crawl**. Nobody hears a downed player.
- **Revive:** any living player can raise a downed player during those 10 s.
- **Give up:** a downed player can press a button to die at once, which starts the respawn timer. It works even while
  someone is raising them, so nobody can keep a player out of the game by downing and raising them again and again.
- **Dead:** not raised within 10 s, or gave up. The dead player **spectates** in first person through the eyes of any
  other player, dissidents included, and hears **no game voice** at all, so the dead cannot overhear the dissidents'
  plans. Instead they hear funny waiting music, like in a lift. Nobody hears the dead.
- **Respawn** after about 30 s at a random respawn point of the map.
- **Invulnerable for 3 s** after a revive or a respawn.
- **What drops:** nothing at the knockdown: a downed player keeps their items, and a revive costs only time. At death
  both slots drop at the body (the hand item or the two-handed package, and the belt item).
- **A downed player cannot be hit.** A knockdown ends only by a revive, giving up, or its 10 s running out.
- **A downed player hears the living** as before the fall; nobody hears them.

### Voice
- The living hear the living by proximity (unchanged).
- Downed and dead players are heard by nobody. The dead hear no game voice (above). The ghost hearing radii are gone.

### HUD and the task screen
- A **task screen** on Tab, seen by everyone: the match's tasks with a short description, their shared progress, and
  a **map** showing where the tasks are done.

### Placeholder numbers: not a decision
| Number | Placeholder |
|---|---|
| Knockdown time (crawl, can be raised) | 10 s |
| Time to raise a downed player | 3 s |
| Respawn time after death | 30 s |
| Invulnerability after a revive or a respawn | 3 s |
| Crawl speed | 1 m/s |

### Closed and parked
- **Meetings mode (#35):** closed; it does not fit "deduction is not central".
- **Resurrection (#34):** replaced by this revision's knockdown and respawn; closed or rewritten.
- **Classes:** not planned.
- **Parked:** deathmatch mode, fixed task locations, maps and settings, other sabotages (light panel, generator,
  molotov).
- **Later, and the content API must allow it:** loot (consumables, gear, cases with mega-items). Nothing is built for
  it now.
- **Later, after the MVP:** customization from ready-made parts and masks with an animated mouth (#73), gestures and
  a hand ping seen only in view.

## Alternatives
- Many small mechanic issues, one per change: each would be decided alone, and M4 would keep building on the rest of
  the old rules in the meantime.
- Rewriting the MVP rules file in place with no record: the history of why ghosts were dropped would be lost.

## Consequences
- Changed in the same PR: the [MVP rules](2026-09-29-mvp-rules.md) (Roles, Win conditions, Items, Collisions,
  "Death and ghosts" replaced by "Knockdown, death and respawn", Voice, Meetings, HUD, the placeholder table and
  "Not in the MVP"), and `docs/GDD.md` §1 (the pillars), §3 (Round, later modes) and §9.
- Left to the engineer: `docs/ARCHITECTURE.md` (§3.4, §5, §6, §7.1, §9.5) and `docs/ROADMAP.md` (M2 and M5 mention
  meetings; the MVP sentence mentions ghosts and dead chat), with the rework below.
- Rework, split into M4 issues by the engineer: ghosts out of `core/life/`, `core/voice/round_voice.gd`,
  `client/player/` and the leak test; knockdown, revive, give up, spectate and respawn in `core/` with their intents
  and per-peer filtering (a spectated player's view goes only to its spectators); two hand slots in `core/items/`;
  `no_crew_alive` out of `content/`; respawn points in levels; the task screen with its map in the client.
- #125 (M4 design) designs death, items and the HUD by this revision. #34 (resurrection) and #35 (meetings mode) are
  closed or rewritten after the merge.
