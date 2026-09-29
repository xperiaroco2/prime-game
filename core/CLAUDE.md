# core/: pure game rules (engineer)

Loaded when a file in `core/` is read. The invariants in the root `CLAUDE.md` apply; this file adds what is specific
to `core/`. Design: `docs/ARCHITECTURE.md`.

## Boundaries
- Classes extend `RefCounted`. `Resource` subclasses are fine: they are `RefCounted`, and content data is stored
  as `Resource`s.
- No `Node`, scene, `SceneTree`, autoload, `MultiplayerAPI`, networking, audio, file or `OS` access in `core/`.
- Nothing in `core/` references `server/`, `net/`, `client/` or `voice/`. Dependencies point into `core/`, never
  out of it.
- Deterministic: the same seed and the same commands produce the same events.
  - Randomness only through an injected `RandomNumberGenerator` whose seed the caller sets.
  - Never the global RNG: `randi()`, `randf()`, `randi_range()`, `randf_range()`, `randfn()`, `randomize()`,
    `seed()`, and also `Array.shuffle()` and `Array.pick_random()`, which use it silently.
  - Time arrives inside commands (a tick or timestamp); never read `Time` or `OS` clocks here.
- Commands in, events out. `core/` never decides who may see an event; `server/` filters per peer.

## What lives here
- The game modes, each an explicit match state machine that defines its phases. Base mode: Lobby → Countdown →
  Loading → Round → End → Lobby; a later meetings mode (#35) adds Meeting → Vote → Resolution
  ([ADR](../docs/decisions/2026-09-29-game-modes-define-the-phases.md)).
- Intent validation rules and win conditions.
- Voice routing rules: for each speaker and listener pair, whether audio is delivered and how (proximity,
  occlusion, dead chat, meeting-wide, radio).
- The content-API parts (rules of trigger → conditions → effects; the kinds of ARCHITECTURE §9.3) that the
  designer composes. Adding or changing one updates the content-API section of `docs/ARCHITECTURE.md` in the same
  PR, because it is the designer's contract.

## Tests
- Most of the project's tests belong here. Put them in `tests/unit/`, mirroring the `core/` path:
  `core/match/vote.gd` → `tests/unit/match/vote_test.gd`.
- Drive a rule with commands and assert the events it emits. Seed the RNG in the test.
- Test voice routing with synthetic audio frames, never real capture.
- At finish, `netcode-security-reviewer` reviews every `core/` change (root Routing).
