# Match loop, intents and events, and who may see what

- **Status:** Proposed: the engineer reviews it in #32's PR
- **Date:** 2026-09-29
- **Deciders:** designed by the agent in #32; the rule gaps it found were answered by the engineer in #32's session
  and recorded in the [MVP rules](2026-09-29-mvp-rules.md)
- **Refined by:** [content API v0](2026-09-29-content-api-v0.md) (#33): the intent `Hit` is now `Use`, the event
  `DissidentTeam` is now `Teammates`, and win conditions are checked after every fact and at the end of every step
  instead of as a tick system

## Context
Stage 2 of M2 writes the core rules (#30). Before any core code, the base mode's phases, the MVP's intents and
events, and how per-peer entitlement is expressed must be fixed, so that every stage-2 task builds the same loop and
the M3 information-leak test has a model to compare against. The rules come from the
[MVP rules](2026-09-29-mvp-rules.md), the phases from [game modes define the phases](2026-09-29-game-modes-define-the-phases.md),
and the hosting model from [listen server and the message layer](2026-09-29-listen-server-and-message-layer.md).
Later mechanics must fit without a change to the core loop: the meetings mode (#35), a zone task (#36),
resurrection (#34), physics throwing (#37).

## Decision
The details are in `docs/ARCHITECTURE.md` §3, §4.1, §4.2, §5, §6 and §7.1. The main choices:

1. **A mode-agnostic loop, and the game mode as data.** `Match` owns the match state and runs the current phase. A
   game mode lists its phases (a phase class plus parameters); per phase the intents it accepts, its tick systems
   in order (the win conditions run only in Round), whether the clock runs and which voice rule applies; and a
   transition table *from phase, outcome → to phase, actions*. Phases and content parts report named outcomes,
   checked after every command, tick and phase entry; the first outcome of a step wins, and a later one is refused
   visibly. Intents are handled by the phase or by the
   content part that owns the action. Transition actions (such as the deal) are content parts. The match state
   outlives phases.
2. **Validation of the rules lives in `core/`**, movement included: the phase's allowlist, life state, hand slot,
   reach, stamina, cooldowns. `server/` checks what the transport knows (sender, decoding, size, rate) and stamps the
   host tick.
3. **Entitlement per event type, and per entity for snapshots, decided in `core/`.** Each event class declares one
   audience (*everyone*, *only(peer)*, *role(r)*, *life(ghost)*, *server*), evaluated at emission; facts with
   different audiences are separate events. Snapshots are built per peer from visibility rules per entity kind.
   `server/` applies the recipients and builds one message per recipient. `Match.view_of(peer)` (events, snapshots
   and voice routing per tick) is the projection unit tests assert and the M3 leak test compares against, plus
   invariants written independently of the audience declarations.
4. **Geometry through a port.** `core/` asks an abstract `WorldQuery` (line of sight, floor, where a placed item
   rests); `server/` implements it over its own `World3D` of the level's static colliders, from the physics step;
   tests use a fake, and replays read the logged answers.
5. **The host's positions decide every range rule.** Hits pick their targets from the host's latest positions, with
   no lag compensation in the MVP; a put-down sends only the facing and the host places the item; delivery is one check
   that runs whenever an item comes to rest, whatever brought it there, as the rule says.
6. **Players push each other apart on their own clients.** The host tolerates overlap and never corrects it; ghosts
   never reach a living client, so no invisible blocker can exist.
7. **Time is ticks at 20 Hz** (a placeholder), stamped by the host; stamina is accounted per claim over the client
   ticks it covers; one 64-bit session seed from the operating system, and a separate RNG per purpose derived from the
   match seed and the purpose's name; health and stamina are integers in thousandths.
8. **A scene change places everyone** at a spawn point (public `PlayersPlaced`) with a new correction epoch sent to
   each player privately, so claims from the old scene are dropped as stale and no one learns how often another
   player was corrected.

The engineer's answers to the rule gaps (0 stamina, settings defaults, loading failures, what each player learns,
leaving mid-round, the end screen, and the small rules), and the engineer's correction that ghosts hear by distance,
are in the MVP rules ADR. The engineer answered "A" to where entitlement lives (choice 3), with the rewording of
`core/CLAUDE.md` moved to stage 2a because #32 changes only `docs/ARCHITECTURE.md` and `docs/decisions/`. How a
client notices that the host is gone is the transport's (#40), not this ADR's.

## Alternatives
- **Phases hard-coded per mode** (a `match` statement over a phase enum, or a mode subclass that overrides the base
  mode's methods): the meetings mode would edit the base mode's code, and a transition could exist with no recorded
  trigger. **A fixed tick order inside `Match`:** a vote timer (#35) would need a new slot in the loop. **Intents
  handled only by phase classes:** a body report (#35) or a throw (#37) would edit the Round class. Rejected for
  choice 1.
- **Dealing roles when Round is entered** instead of on the transition: returning from a meeting (#35) would deal
  again. Rejected for transition actions.
- **Validation of the rules in `server/`:** the rules would split between two layers, and unit tests of `core/`
  could not show that an intent is refused. Rejected for choice 2.
- **Entitlement per field** (one event, a mask per field and recipient): every encoder must honour the masks, one
  forgotten field leaks, and the leak test must reason about partial events. **Per content part** (a part says who
  sees its effects): too coarse, because one part emits both public and private facts (a hit). **Filtering in
  `server/`** by lists of event types: the rules of who is entitled depend on roles and life state, which are game
  rules, and they could not be unit-tested in `core/` without networking. **Broadcasting public events through the
  transport:** it also reaches peers that are not players yet. Rejected for choice 3.
- **Raycasts in `core/`:** impossible without Nodes. **`server/` precomputing hit targets and passing them in:** the
  hit zone rule would live half in `server/`, half in `core/`. Rejected for choice 4.
- **Client-reported hit targets or placement positions:** a client could hit anyone or deliver from across the map.
  **Lag compensation (rewinding targets to the attacker's view):** more state and code before a playtest shows a
  need. **Delivering only on a put-down:** the first draft read the rule that way; the engineer corrected it in
  review (a package counts however it came to rest in its circle). Rejected for choice 5; rewinding stays the
  fallback.
- **Host-enforced separation of players:** two clients that see each other late would be corrected back and forth.
  Rejected for choice 6.
- **Stamina charged per host tick:** a client that sends a claim every other tick regenerates on the empty ones and
  sprints almost for free. **One RNG stream for the whole deal:** adding a draw anywhere would reshuffle every later
  draw and break recorded replays. **`String.hash()` for seeding:** its algorithm is not a documented contract.
  Rejected for choice 7.

## Consequences
- The extensibility test on paper:
  - **Meetings mode (#35):** new mode data and the phase classes Meeting, Vote and Resolution; a trigger part
    (button, body report) that handles its intent and reports `meeting_called`; the clock stopped by Meeting's phase
    flag and its end re-announced on resume; a meeting-wide voice rule; vote events with their own audiences. No
    change to `Match`.
  - **Zone task (#36):** one task-type class, run as a tick system, that reads positions from the match state and
    completes subtasks; the crew's win already counts subtasks. No change to the loop.
  - **Resurrection (#34):** the life state is reversible (alive, ghost, left) and audiences are evaluated at
    emission, so one effect class and a `Revived` event suffice. Knowledge never shrinks: a revived player keeps
    what they saw as a ghost; #34 decides whether that matters.
  - **Physics throwing (#37):** a throw action part, and `server/` reporting `ItemRested` from its physics; whether
    a thrown package delivers is #37's open question, and the check is the same one.
- Stage 2a rewords `core/CLAUDE.md` ("`core/` never decides who may see an event"; game modes as `core/` classes plus
  content data) and `server/CLAUDE.md` (the phase and range checks and the movement sanity checks move to `core/`
  rules that `server/` calls). ARCHITECTURE §1 already says so.
- The M3 leak test compares each bot's decoded stream, voice included, with `Match.view_of` of its peer, and asserts
  the independent invariants of §5.
- Risks: without lag compensation, knife hits may feel unfair at 1.5 m reach (the playtest decides); corrections at
  the edge of the sprint threshold, where the client's predicted stamina and the host's differ (M4 tolerances);
  `World3D` queries from a space the host builds itself are untested under Jolt (stage 2).
