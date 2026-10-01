# Game modes define the phases (architecture invariant 5)

- **Status:** Accepted
- **Date:** 2026-09-29
- **Deciders:** the engineer (approved in chat with the M2 manager session on 2026-09-29); recorded from #31
- **Amended by:** [vision revision 1](2026-10-01-vision-revision-1.md) (#126, 2026-10-01): the meetings mode (#35)
  is dropped, so no mode adds Meeting → Vote → Resolution. "A mode can add phases" stays a requirement: the parked
  deathmatch mode is its example now, and the zone task (#36) the example of a mechanic that needs no new phase.

## Context
Architecture invariant 5, from the founding brief, fixed one phase chain for every match:
Lobby → RoleAssign → Roam → Meeting → Vote → Resolution → (Roam | End). The [MVP rules](2026-09-29-mvp-rules.md)
have no meetings or voting, and meetings come back later as a separate game mode (#35). One fixed chain cannot hold
both.

## Decision
The **game mode** defines its phases, still as an **explicit state machine** (the invariant keeps its first half).
- **Base mode:** Lobby → Countdown → Loading → Round → End → Lobby.
  - Lobby: players walk and talk, and press Ready.
  - Countdown: 5 seconds once all are ready; anyone un-readying, joining or leaving cancels it (back to Lobby).
  - Loading: everyone loads the game scene; the round starts when every peer confirmed it loaded
    ([listen server](2026-09-29-listen-server-and-message-layer.md)).
  - Round: roles are dealt and packages scattered when Round starts; it ends on a win condition.
  - End: the end screen shows only the winning side, with no names and no roles (corrected by the engineer in #32);
    the host's button returns everyone to the Lobby.
- **A later meetings mode** (#35) adds Meeting → Vote → Resolution; its transitions are designed there.

Changed to match: invariant 5 in the root `CLAUDE.md`, "What lives here" in `core/CLAUDE.md`, and §3 of
`docs/ARCHITECTURE.md`.

## Alternatives
Keeping the brief's single chain: the base mode cannot follow it, because it has no meetings. No other option was
recorded.

## Consequences
- The detailed state machine (every transition, its trigger, what each phase allows, timers) is designed in #32.
  How a game mode is expressed, and whether it is content data, belongs to #32 and the content API v0 (#33).
- `docs/GDD.md` §3 still names the brief's chain; the designer updates it in #38. `docs/history/` keeps the old chain
  as history.
