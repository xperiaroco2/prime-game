# The tutorial: an offline solo session with stand-ins, host-staged lessons and a client-side lesson runner

- **Status:** Proposed (#552). The D items (D25 to D36) are the engineer's, tier (c) of the
  [trust ADR](2026-10-04-trust-based-autonomy-gated-merge-into-main.md); the E items (E62 to E72) are the M6.2 manager
  session's, tier (a), each standing as recommended unless it reports otherwise, but for E64's new kind in the
  `content/` row of ARCHITECTURE §1 (a boundary) and E65's wire row, which go to the engineer with the D items
  (Needs the engineer, below)
- **Date:** 2026-10-08
- **Deciders:** the engineer (the D items, E64, E65); the M6.2 manager session (the other E items); designed by the
  agent in #552 under the M6.2 manager session
- **Design:** [`docs/design/tutorial.md`](../design/tutorial.md) holds the design, every E and D item with its options,
  the failure each prevents and its recommendation, and the split (its §8)
- **Builds on:** the engineer's answer that the tutorial is offline, in a room of its own (#552's body, 2026-10-08);
  M6.2's [scope option A](https://github.com/xperiaroco2/prime-game/issues/516#issuecomment-6055436108);
  [the M4 client](2026-10-01-m4-first-person-client.md) (E18: the host's own player sees only its decoded view; E19:
  one persistent root); [wire format and the host session](2026-09-30-wire-format-and-host-session.md);
  [game modes define the phases](2026-09-29-game-modes-define-the-phases.md);
  [content API v0](2026-09-29-content-api-v0.md);
  [the MVP content built by the engineer](2026-09-29-mvp-content-built-by-the-engineer.md)
- **Numbering:** the choices continue [the M6 design](2026-10-04-m6-playable-over-the-internet.md)'s: **E62 to E72**
  and **D25 to D36**. The proposed issues are **T1 to T4** (the design's §8), plus the existing #492

## Context
The UI track drew the tutorial (prime-game-ui `docs/handoff/s01-tutorial.md` at `ui-0.4.0`, built by #492): an
invite on the first launch, nine lessons that each advance when the game sees its action, and the main menu after
lesson 9. No issue covered what runs behind the screens. The engineer answered that the tutorial is offline, in a room
of its own: a solo session with no network and a small room with its own stations.

What constrains the design:
- **Invariants 1 to 4.** The host is authoritative, the host's own client sees only its filtered view, `core/` is
  pure, mechanics are data. A solo session still runs a host: the screens of a round read a `ClientModel`, never
  `core/` state.
- **Five of the nine actions never reach the host**: opening the map, pressing a task's «?», switching the
  spectate target, speaking, opening the Esc menu. They are screens and the microphone of the own client.
- **Three lessons need another player**: someone down to raise (6), someone to watch while dead (7), someone near to
  talk to (8). The raise, spectating and voice routing all work on players the host knows.
- **Networked play must not change**, beyond what a new feature cannot avoid.
- What exists: `LoopbackTransport` and `LoopbackHub` (`net/transport/`, built for the host's own client and the
  tests), `HostNode` as the game's narrow handle on the host, `ClientSession.load_levels` (off for the bots), the
  bot scenarios' data classes in `core/content/scenario/`, and `ReportOutcome`, listed in ARCHITECTURE §9.4.2 since 2a
  for the first mechanic that needs it.

## Decision
Recommended, each item in the design's tables:
1. **The session** (E62): `Game` hosts the tutorial mode on a `LoopbackTransport` over a private `LoopbackHub`, through
   the unchanged `HostNode` façade, and joins its own `ClientSession` as when hosting. No socket opens and nobody else
   can join. Every layer above the transport is the networked game's own code.
2. **Stand-ins** (D25, D26, D35, E67): two in-process `ClientSession`s on the same hub, real players to the host, that
   only join, ready, acknowledge the load and stand where they were placed. The game never shows anything from their
   own views.
3. **Stages** (E65, E66, E68, E72): the tutorial mode joins its players in a `gather` phase with no level, where a
   join stands at the origin with no match error, then chains `lessons → raise_stage → death_stage` on an outcome
   `next`, reported by `ReportOutcome` from the mode's rule on a new host-only intent, `NextStage`. The rows knock
   stand-in 1 down (lesson 6) and knock the own player down and dead (lesson 7) through a new transition action,
   `KnockDown`; `PlacePlayers` gains an ordered placement. No new event and no new audience.
4. **The lesson runner** (E63, E64): a pure client class reads the own events, the own claims, the own model and the
   client's own signals, and sends nothing but `NextStage`. The lessons are data: data-only classes in
   `core/content/tutorial/`, the nine lessons in `content/tutorial/tutorial.tres`, the runner in `client/tutorial/`.
5. **The room** (D34): a greybox scene with one station per lesson along its walls, its markers fixed for the mode's
   checks; the environment track dresses it later.
6. **The flow** (E69, E70): the session's mode is chosen per session; a phase with no level shows the loading
   screen; the first launch starts the tutorial only with no launch option and settings read from a file;
   `--tutorial` starts it for tooling.

## Needs the engineer
One batch; each item's options and the failure each leaves are in the design's §7 (the D items) and §6 (E64, E65).
1. **D25**, lessons 6 to 8: (a) stand-ins, real players staged by the host; (b) client-side puppets; (c) shortened
   lessons. Recommended (a).
2. **D26**, how many stand-ins: (a) 2; (b) 1. Recommended (a).
3. **D27**, how the stand-in goes down: (a) the host knocks it down as lesson 6 starts; (b) the other stand-in strikes
   it in view. Recommended (a).
4. **D28**, how the player dies: (a) down and dead at once as lesson 7 starts; (b) down, then dead when the knockdown
   runs out or the player gives up; (c) struck by a stand-in. Recommended (a).
5. **D29**, lesson 3's one-handed item: (a) the knife, the plate as drawn; (b) (a) plus a first instruction to pick
   it up, from the UI track; (c) lesson 3 left out. Recommended (b), and (a) until the UI track draws it.
6. **D30**, lesson 4's text describes Delivery v2 (#255, out of M6.2): (a) wait for v2; (b) a v1 text from the UI
   track; (c) the v2 text over v1. Recommended (b).
7. **D31**, lesson 8 with no open microphone: (a) done on the first frame sent within the radius, or after 3 s within
   it with no open microphone; (b) only on a frame; (c) left out. Recommended (a).
8. **D32**, back to the main menu after lesson 9: (a) as the Esc menu opens; (b) as it closes; (c) after a pause.
   Recommended (b).
9. **D33**, the tutorial's numbers: the design's placeholders (2 stand-ins, 1 package, 1 knife, `respawn_s` 10, 1 s
   of walking, 3 s for D31, a room of about 12 × 10 m), "not a decision", tuned in your playtest. Recommended: keep
   them as placeholders.
10. **D34**, the room: (a) one room, one room record named by you; (b) two rooms; (c) a room of the house (#523).
    Recommended (a); the room's name on the map is yours.
11. **D35**, the stand-ins' names and looks: (a) the host's default for any joiner; (b) their own. Recommended (a).
12. **D36**, lesson 7 when the respawn comes before the switch: (a) the lesson completes on the switch or on the own
    respawn, whichever comes first; (b) no respawn until the switch (a fourth phase and a new host part); (c) only the
    switch, with a long respawn. Recommended (a).
13. **E64**, a boundary: `content/` gains a kind, the tutorial's lessons, whose data classes join the content API
    in `core/content/tutorial/` as the bot scenarios' did in `core/content/scenario/`; ARCHITECTURE §1's `content/`
    row names it. (a) that; (b) the classes in `client/tutorial/`, which `content/` may not name. Recommended (a).
14. **E65**, one new client-to-host wire row, `NextStage`, so the protocol version goes up by one; the base mode
    refuses it in every phase. (a) the row; (b) a `HostNode` call with no wire row. Recommended (a).
15. **The split** (the design's §8): (a) T1 to T4 as proposed, then #492; (b) with the changes you name. Recommended
    (a).

## Alternatives
- **ENet on 127.0.0.1** (E62 (b)): the `--host --local` path exists, but it opens a UDP port that a second game window
  or another program can hold, for a feature that needs no network.
- **A `Match` run by the client** (E62 (c)): the screens would need a second source of truth, and the host's own
  client would read `core/` state, against invariant 2 and E18.
- **Lessons as `core/` rules on the host** (E63 (b)): the five client-only actions would each need an intent and the
  lesson's progress an event on the wire, all for an offline feature.
- **Lesson classes in `client/`** (E64 (b)): `content/` data would name a `client/` script, which §1 of ARCHITECTURE
  allows the content API only.
- **A `HostNode` method for the stages** (E65 (b)): no wire row, but the own client gets a path into `Match` that no
  remote client has and no bot scenario can drive, and E18's façade widens.
- **Stages from host facts alone** (E65 (c)): lesson 6's stand-in would fall while the player still reads the map,
  and a player who raises it early would die before lesson 7 shows.
- **Role-based targets** (E66 (b)): an invented "stand-in" role and a deal in peer order, for what a pick by peer
  order says directly; and a role is hidden information the tutorial does not need.
- **Scripted stand-ins** (E67 (b), D27 (b), D28 (c)): the bots' step player moved into the game, a mover with no
  walls, an attacker the player can outrun, and violence between crew stand-ins.
- **One lesson phase with rows back to itself** (E68 (b)): a repeated `next` would stage twice, and one phase cannot
  both leave the downed stand-in waiting (no LifeTicks) and respawn the player (LifeTicks).
- **Puppets drawn by the client** (D25 (b)): the client would show a raise and a spectate target the host never
  sent, which the client's rule forbids, and the raise taught would not be the real one.
- **A second main scene for the tutorial** (E69 (b)): breaks the one persistent root (E19).
- **`gather` in the room as the lobby** (E72 (b)): no `core/` change, but the client loads the room at the Welcome,
  drops it and loads it again when `loading` starts, with the lobby screen between.
- **A marker-only lobby scene** (E72 (c)): the lobby screen, and the own player walking with no floor until
  `loading`.
- **No respawn until the spectate switch** (D36 (b)): a fourth phase and a host part that respawns by a row, for
  one lesson.

## Consequences
- `core/` gains `NextStage`, `ReportOutcome`, `KnockDown` and `PlacePlayers`' ordered placement (T1), each in §9.4
  of ARCHITECTURE with its events, all of them events that exist, and a join at no level stands at the origin with
  no error (a phase no base-mode phase is); `net/`'s schema gains one row and the protocol version one step; the
  chaos bots cover the row's refusals.
- `content/` gains the tutorial mode, its bot scenario and the lessons; `levels/` the tutorial room (T2, T4), all
  provisional under the MVP content ADR, for the engineer's approval in their PRs.
- `client/` gains `client/tutorial/` (the stand-ins, the runner) and `Game.start_tutorial`; `GameFlow` shows the
  loading screen for a phase with no level (T3, T4). Nothing in `server/` or the transports changes.
- The tutorial runs the networked game's own code in one process, so a change that breaks a round's screen breaks
  the tutorial too, and its tests (T3's integration test, T2's scenario, #492's `playcheck`) catch it.
- The UI track gets a request for D29 (b) and D30 (b) if the engineer takes them.
- `docs/ARCHITECTURE.md` §10 points at this design until T1 to T4 write their sections.
