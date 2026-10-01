# client/: scenes, player controller, UI, audio playback (engineer)

Loaded when a file in `client/` is read. The invariants in the root `CLAUDE.md` apply. Design:
`docs/ARCHITECTURE.md`.

## Job
- The first-person player controller, camera and interactions; the local player's movement is client-side.
- Interpolation of remote players from the data `net/` delivers.
- UI: lobby, HUD, the Tab task screen (no map for now), end screen; the spectate camera of the dead.
- Audio playback: each remote speaker's voice plays through an `AudioStreamPlayer3D` on that speaker's avatar.
- The dev console and debug commands (spawn bots, force role, skip phase, show hidden info) for solo testing.

## Map
- `net/` (3g, `docs/ARCHITECTURE.md` §4.6): `ClientSession`, which every client and bot runs over a `NetTransport`
  (Hello, intents, claims, loading, voice), `DecodedView` (what it decoded, in `PeerView`'s shape) and `ClientModel`
  (what it knows now). Game code talks to the host only through a `ClientSession`. Its `view` stays empty unless
  `keep_history` is on (off by default; bots and the leak test turn it on).

## Rules
- The client knows only what `server/` sent it. Never read `core/` state, not even on the host's own machine, and
  never infer hidden information from anything else (node names, resource paths, timing).
- Showing hidden information is debug-build only (`OS.is_debug_build()`), in the dev console.
- The client sends intents through `net/`, never state.
- Scenes are single-owner. Build reusable pieces as small sub-scenes; level layout itself is the designer's
  (`levels/`). Hand-written `.tscn` follows `.claude/rules/godot-resources.md`.
- Visual changes come with a `shot` screenshot in the PR once `shot` exists.
- Dev-only scenes (test rooms) go in `client/dev/`, never `levels/`. Collision layers come from `PhysicsLayers`,
  movement and stamina numbers from `PlayerTuning` (`docs/ARCHITECTURE.md` §7).

## Tests
- Logic that can live outside a scene should, so it can be unit-tested headless.
- UI and input do not work in headless GdUnit4 runs (no `InputEvent`s): verify them with `shot` and a human
  playtest, and say so in the PR.
