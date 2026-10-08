# core/: pure game rules (engineer)

Loaded when a file in `core/` is read. The invariants in the root `CLAUDE.md` apply; this file adds what is specific
to `core/`. Design: `docs/ARCHITECTURE.md` (§3 the loop, §5 entitlement, §7.1 authority, §9 the content API).

## Boundaries
- Classes extend `RefCounted`. `Resource` subclasses are fine: they are `RefCounted`, and content data is stored
  as `Resource`s.
- No `Node`, scene, `SceneTree`, autoload, `MultiplayerAPI`, networking, audio, file or `OS` access in `core/`.
  `server/` and the tests load the game mode and the levels' `LevelLayout`s and hand them in; geometry comes
  through the `WorldQuery` port (§7.1).
- Nothing in `core/` references `server/`, `net/`, `client/` or `voice/`. Dependencies point into `core/`, never
  out of it.
- Deterministic: the same seed and the same commands produce the same events and command log.
  - Randomness only through `RngStreams`: one `RandomNumberGenerator` per purpose named in the part's data (§3.3).
  - Never the global RNG: `randi()`, `randf()`, `randi_range()`, `randf_range()`, `randfn()`, `randomize()`,
    `seed()`, and also `Array.shuffle()` and `Array.pick_random()`, which use it silently. Shuffle with
    `RngStreams.shuffled_indices`.
  - Time arrives as host ticks on commands (`Ticks` converts seconds once, toward zero); never read `Time` or `OS`
    clocks here.
- Commands in, events out. **`core/` decides who is entitled to every event** (§5): each event class declares one
  audience (and its `AUDIENCE_KIND`), evaluated at emission; `Match` records the recipients and `view_of(peer)`.
  `server/` delivers to exactly those recipients and never adds one. Data and effects never choose recipients.

## What lives here
- `Match`, `MatchState` and `Phase` (`core/match/`). `Match` knows no game mode: a **game mode is `core/` classes
  plus content data**, a `GameMode` `.tres` in `content/modes/` that names its phases (phase classes in
  `core/match/phases/`), rows, rules and settings ([ADR](../docs/decisions/2026-09-29-game-modes-define-the-phases.md)).
  A stage-2 task adds its own files; it never edits the loop (2d's end-of-tick `SelfStatus` flush is the one
  exception, §9.3).
- The base class of every content-API kind (`core/content/`, §9.3). A global class name must not shadow an enum or
  class elsewhere in the project: hence `GameRole` and `RuleEffect`, not `Role` and `Effect`.
- The validation of every intent against the rules: the phase's allowlist, life state, hand, reach, stamina,
  cooldowns and the movement checks (§7.1). `server/` checks only what the transport knows and calls these.
- Win conditions, and voice routing rules (who hears whom, per phase).
- Parts are stateless definitions: what changes lives in `MatchState` (items, tasks with their task state,
  stations, bodies, cooldowns, counters, `part_state`) or in the phase object, which `Match` creates fresh on every
  entry (§9.1). Adding or changing a part updates §9 of `docs/ARCHITECTURE.md` in the same PR (the content
  contract), with the events it can emit and the reason each condition rejects with.

## Tests
- Most of the project's tests belong here. Put them in `tests/unit/`, mirroring the `core/` path:
  `core/match/vote.gd` → `tests/unit/match/vote_test.gd`. Fixtures (modes built in code, test parts) live in
  `tests/fixtures/<area>/` (`match/`, `items/`, `tasks/`); a part's unit test never loads `content/` or `levels/`
  (§9.6).
- Drive a rule with commands and assert the events it emits and who received them (`view_of`). Seed the match.
- Test voice routing with synthetic audio frames, never real capture.
- At finish, `netcode-security-reviewer` reviews every `core/` change (root Routing).
