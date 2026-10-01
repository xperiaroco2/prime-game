# client/: the windowed game: scenes, player controller, UI, audio playback (engineer)

Loaded when a file in `client/` is read. The invariants in the root `CLAUDE.md` apply. Design:
`docs/ARCHITECTURE.md` §4.6 (the session and the model), §4.7 (the game client, M4) and §7 (movement); M4's
choices: `docs/decisions/2026-10-01-m4-first-person-client.md` (its §3 is the review checklist for client PRs).

## Job
- The windowed game: the main menu, hosting and joining, the lobby, loading, the round and the end screen, in one
  persistent main scene that swaps levels under itself (§4.7).
- The first-person player controller, its cameras (first person, the downed camera, the spectate camera of the dead)
  and interactions; the local player's movement is client-side.
- Interpolation of remote players from the snapshots `net/` delivers.
- UI: lobby, HUD, the Tab task screen (no map for now), end screen.
- Audio playback: each remote speaker's voice through an `AudioStreamPlayer3D` on that speaker's avatar (M5); M4's
  placeholder world sounds and the dead's lift music.
- The dev console and debug commands (spawn bots, force role, skip phase, show hidden info) for solo testing.

## Map
- `net/` (3g, §4.6): `ClientSession`, which every client and bot runs over a `NetTransport` (Hello, intents, claims,
  loading, voice), `DecodedView` (what it decoded, in `PeerView`'s shape) and `ClientModel` (what it knows now). Game
  code talks to the host only through a `ClientSession`. Its `view` stays empty unless `keep_history` is on (off by
  default; bots and the leak test turn it on).
- `player/`: `PlayerController` (#46), `RemotePlayerBody`, `PlayerTuning`, the stamina sources.
- `dev/`: dev rooms and the preview scenes that `shot` draws.
- M4's new code (§4.7): `app/` (the main scene `game.tscn`, the sessions, the level swap, the launch options, the
  end reasons), `ui/` (the screens), `world/` (snapshot interpolation; the views of avatars, items, stations and
  bodies), `life/` (the downed and spectate cameras, the countdowns).

## Rules
- The client knows only what `server/` sent it. Never read `core/` state (`Match`, `MatchState`, `PeerView`,
  `Snapshots`), not even on the host's own machine, and never infer hidden information from anything else (node
  names, resource paths, timing). What is drawn, played or shown comes from the own `ClientModel`, the interpolated
  snapshot poses and the client's own copy of the game mode (its names and numbers).
- Only `app/` names `server/` (`HostSession`, `HostNode`): to start, step, close and read `errors`, `ended` and a
  debug build's counters; nothing reads `HostSession.game`. A source test holds it (E18, proposed).
- One persistent root: swap levels under `World`; never `SceneTree.change_scene_to_*`, no autoloads (E19, proposed):
  a freed scene would take the `HostNode` and the session with it.
- Spectating is built on the dead player's own client from the public snapshot. The target is drawn with the
  client's own seeded generator and never sent; there is no target HUD, health, stamina, role or private event.
- The downed camera stays at or below the standing eye height above the body and never passes through the level,
  and while it is in use no avatar, item or body out of sight of the body's eye is drawn (§4.7).
- A world sound plays only within the hearing range of the listener's camera (E33, proposed); a fading sound with
  no cut-off tells everyone, through walls, where a package was put down.
- Showing hidden information is debug-build only (`OS.is_debug_build()`): the dev console and the debug overlay.
- The client sends intents through `net/`, never state, and predicts nothing of an action's outcome.
- Collision layers come from `PhysicsLayers`. M4-7's target (proposed; the code on the base still reads speeds,
  capsule, eye height and stamina from `player_tuning.tres`): movement numbers come from the mode's `PlayerRules`,
  and `PlayerTuning` keeps client feel only. Until M4-7, leave that split to it rather than moving numbers in passing.
- A new event's fold in `ClientModel` lands in the core PR that adds the event, since the bots need it (E25,
  proposed); client issues read the model.
- Scenes are single-owner. Build reusable pieces as small sub-scenes; level layout itself is the designer's
  (`levels/`). Hand-written `.tscn` follows `.claude/rules/godot-resources.md`.
- Visual changes come with a `shot` screenshot in the PR. Dev-only scenes (test rooms, previews) go in
  `client/dev/`, never `levels/`.
- Client PRs get `netcode-security-reviewer` with the M4 ADR's checklist, besides `code-reviewer`.

## Tests
- Logic that can live outside a scene should (the flow, snapshot interpolation, stamina prediction, spectate
  targets, countdowns, HUD texts), so it can be unit-tested headless in `tests/unit/client/`.
- Physics runs headless: the controller through a `ClientSession` over a `LoopbackHub` to a `HostSession`, and the
  downed camera against a wall, go in `tests/integration/client/`.
- UI and input do not work in headless GdUnit4 runs (no `InputEvent`s): verify them with `shot` of a preview scene
  and a human playtest (the M4 ADR's §6), and say so in the PR.
- Never open a window yourself: `run`, `host` and `join` with `--headless` only.
