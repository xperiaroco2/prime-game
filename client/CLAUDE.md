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
- UI: lobby, HUD, the Tab task screen (no map for now), end screen, the Esc menu with tabs (#169).
- Audio playback: each remote speaker's voice through an `AudioStreamPlayer3D` on that speaker's avatar (M5); M4's
  placeholder world sounds and the dead's lift music.
- The dev console and debug commands (spawn bots, force role, skip phase, show hidden info) for solo testing.

## Map
- `net/` (3g, §4.6): `ClientSession`, which every client and bot runs over a `NetTransport` (Hello, intents, claims,
  loading, voice), `DecodedView` (what it decoded, in `PeerView`'s shape) and `ClientModel` (what it knows now). Game
  code talks to the host only through a `ClientSession`. Its `view` stays empty unless `keep_history` is on (off by
  default; bots and the leak test turn it on).
- `player/`: `PlayerController` (#46; it claims to the `ClientSession` it is `attach()`ed to, M4-7; its `life`
  and `held`, M4-9), `RemotePlayerBody`, `PlayerTuning`, `PredictedStamina`, `LifeLooks` (D8's greybox looks).
- `dev/`: dev rooms and the preview scenes that `shot` draws.
- `app/` (M4-6): `Game` (the main scene `game.tscn`: the sessions, the level swap, leaving), `GameFlow` (screen and
  level per phase, pure), `SessionNode`, `LaunchOptions`, `EndReasons` (every end reason in words; add a new one
  there), `MousePointer` (#169). `ui/`: the screens under `GameUi`, built in code, the HUD and the task screen
  (M4-8), and the shared theme `ui/theme/game_theme.tres`; `EscMenuState` (pure), `EscMenu`, its Lobby tab
  `LobbyPanel` and the lobby's `LobbyHud` (#169).
  `world/`: `SnapshotBuffer` and `AvatarViews` (M4-7), `BodyViews` (M4-9),
  `ItemWorld` (M4-8: item and circle views, the item keys, the world sounds).
  `life/` (M4-9): `LifeView` (the cameras, inputs and music by life), `DownedCamera`, `SightHider`, and the pure
  `SpectateTargets`, `LifeCountdowns` and `LifeHud`.

## Rules
- The client knows only what `server/` sent it. Never read `core/` state (`Match`, `MatchState`, `PeerView`,
  `Snapshots`), not even on the host's own machine, and never infer hidden information from anything else (node
  names, resource paths, timing). What is drawn, played or shown comes from the own `ClientModel`, the interpolated
  snapshot poses and the client's own copy of the game mode (its names and numbers).
- Only `app/` names `server/`, through the `HostNode` façade only (`host()` with an optional clock, `is_running()`,
  `own_client`, `errors`, `end_reason`, `ended`, debug counters, `skip_replay()`, `close()`). No `client/` file names
  `HostSession`, a `core/` state class, `.game`, `._session` or a path into `server/` other than `app/`'s
  `host_node.gd`; a source test holds it (E18).
- One persistent root: swap levels under `World`; never `SceneTree.change_scene_to_*`, no autoloads (E19):
  a freed scene would take the `HostNode` and the session with it.
- Spectating is built on the dead player's own client from the public snapshot. The target is drawn with the
  client's own seeded generator and never sent; there is no target HUD, health, stamina, role or private event.
- The downed camera stays at or below the standing eye height above the body and never passes through the level,
  and while it is in use no avatar, item or body out of sight of the body's eye is drawn (§4.7): every such view
  joins `SightHider.GROUP`, and nothing else sets those views' `visible`.
- A world sound plays only within the hearing range of the listener's camera (E33); a fading sound with
  no cut-off tells everyone, through walls, where a package was put down.
- Screens are styled only through the shared theme (`GameUi.THEME`, `client/ui/theme/game_theme.tres`): a type
  variation per look, no `add_theme_*_override`, `Color(...)` or font size in a screen's code; a source test holds it.
  Wording and looks stay greybox placeholders until the UI milestone (#150).
- Under the Esc menu no gameplay key is read and the keys held when it opened are released (`Game._process`);
  closing it in the lobby or the round captures the mouse again (#169).
- Showing hidden information is debug-build only (`OS.is_debug_build()`): the dev console and the debug overlay.
- The client sends intents through `net/`, never state, and predicts nothing of an action's outcome.
- Collision layers come from `PhysicsLayers`. Movement numbers (speeds, jump, capsule, eye and step height,
  stamina) come from the client's own copy of the mode's `PlayerRules`; `PlayerTuning` keeps client feel only (the
  push factors, the view's easing). Never copy a game number into `player_tuning.tres`: the host checks the mode's.
- Remote players are drawn from `SnapshotBuffer`'s poses only, never from a claimed velocity, and every head or
  basis built from a remote facing goes through its guard (`SnapshotBuffer.look_angles`): a relayed facing can be
  zero or vertical in honest play. A body placed in `_physics_process` for the push search is a `StaticBody3D` and
  calls `force_update_transform()` (§4.7: with Jolt a kinematic body's teleport shows only after the step).
- A new event's fold in `ClientModel` lands in the core PR that adds the event, since the bots need it (E25);
  client issues read the model.
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
- Key events do run headless: `Input.parse_input_event(event)` then `Input.flush_buffered_events()` reaches
  `_input`, `_unhandled_input` and the action states (#169's `esc_menu_input_test.gd`); release every key a test
  holds. The mouse mode does not (headless keeps none): give `Game` a `MousePointer` that remembers. How the UI
  looks and feels: `shot` of a preview scene and a human playtest (the M4 ADR's §6); say so in the PR.
- Never open a window yourself: `run`, `host` and `join` with `--headless` only.
