# client/: the windowed game: scenes, player controller, UI, audio playback (engineer)

Loaded when a file in `client/` is read. The invariants in the root `CLAUDE.md` apply. Design:
`docs/ARCHITECTURE.md` §4.6 (the session and the model), §4.7 (the game client), §6 (voice) and §7 (movement); the
review checklists for client PRs: §3 of `docs/decisions/2026-10-01-m4-first-person-client.md` and of the M5 ADR.

## Job
- The windowed game: the main menu, hosting and joining, the lobby, loading, the pregame, the round and the end
  screen, in one persistent main scene that swaps levels under itself (§4.7).
- The first-person player controller, its cameras (first person, the downed camera, the spectate camera of the dead)
  and interactions; the local player's movement is client-side; remote players are interpolated from snapshots.
- UI: lobby, HUD, the map and tasks screen on M, end screen, the Esc menu with tabs.
- Audio: each remote speaker's voice on its avatar, world sounds, footsteps and UI clicks, the lift music.
- The dev console and debug commands (spawn bots, force role, skip phase, show hidden info) for solo testing.

## Map
Which class lives where: `ls client/*` and `docs/ARCHITECTURE.md` §4.7 (§4.6 for `net/`).
- Game code talks to the host only through a `ClientSession` (`net/`); its `view` stays empty unless `keep_history` is on
  (off by default; bots and the leak test turn it on).
- `app/EndReasons` holds every end reason (#494); a new one goes there. Voice code uses `res://voice/`, never the
  reverse.

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
  client's own seeded generator and never sent; nothing private of the target is shown (no health, stamina, role,
  teammates or private event).
  Of the target, the spectator sees only its name ("Watching: <name>", `LifeScreen`'s Spectate plate), and of
  itself the time to respawn; the HUD shows nothing while dead (#497, §4.7.41); from a living target's eyes its body and the item views at it are
  hidden, and its hand item shows in the spectate camera's first-person hand, as on its own screen (#168).
- The downed camera stays at or below the standing eye height above the body and never passes through the level,
  and while it is in use no avatar, item or body out of sight of the body's eye is drawn (§4.7): every such view
  joins `SightHider.GROUP`, and nothing else sets those views' `visible`.
- A world sound (bus Effects) plays only within the hearing range of the ears (E33, E40: never the downed camera);
  uncut, all would hear through walls where a package went down. The muffle (one ray, world layer) lowers and dulls. Footsteps follow the drawn poses only (none while downed, dead or off the floor; #525); a step at the crouch walk's speed is quieter and nearer, eased to a walk's at the fast crouch's, by its speed, never the crouch flag; a sneaking pose's step is silent only at that speed (plus a jitter margin), the sneak flag AND the drawn step's speed, so a claimed sneak at a walk is heard.
- Voice (the M5 ADR §3): only `voice_received` frames play, on the speaker's `RemotePlayerBody`, checked per frame:
  none while the own life is dead, in a phase hearing nobody, of a speaker not living or gone, past `max_distance`
  from the ears, or stamped at or below the tick of its flush (ENet orders no lanes), each flushed at its event.
  `max_distance`, and the sender's `may_speak` (the own life living, radius > 0; every chunk fed each frame, also
  while false), come from the own mode's `VoiceRule.radius_of()` (E41). No talking indicator (D14); F3 names no one.
- Screens are styled only through the shared theme (`GameUi.THEME`, `client/ui/theme/game_theme.tres`, generated from the UI pack,
  never edited by hand; UI px on the 1920x1080 base, ARCHITECTURE §4.7.24-25): a type variation per look, no `add_theme_*_override`,
  `Color(...)` or font size in a screen's code; a source test holds it. A bare base control takes its class's row (mapping `base_types`, §4.7.30); a new bare control class needs a row or a named gap in `base_controls_test.gd`. Text: `i18n/strings.csv` keys (§4.7.26), as a Control's text or `tr()`/`tr_n()`; a content name through `ContentNames`. A source test fails on a literal that reads as words and is no key (#549, §4.7.48): one the deck lacks yet, or one never shown, gets a line with its why (the issue tracking its key) in `tests/unit/client/i18n/literals_allowed.txt`; delete the line when the key lands. Toy buttons, panels and toggles: `UiParts` (§4.7.27).
- A key on screen is `KeyLabel`'s (the binding now, on the player's layout), never a letter in a string (#211).
- Under the Esc menu or the tutorial's invite (`GameUi.blocks_keys()`, #492) no gameplay key is read and the keys held when it opened are released (`Game._process`, `PlayerController.release_keys`: move, sprint, crouch, sneak, jump); the voice keeps working, the Talk key too, but not while a text field or a key capture has the keys (#488);
  closing it captures the mouse again (#169) where `GameFlow.pointer_on` does not free it (#517, §4.7.4 "The mouse"); a new screen closes a menu opened over another (#726). The map (#253, §4.7.33) frees the mouse but pauses no key (`PlayerController.mouse_free`; `GameUi.frees_mouse()` covers the map and the invite); `GameUi` alone holds it open; it draws rooms and zones from level data and no place but the own body's.
- Showing hidden information is debug-build only (`OS.is_debug_build()`): the dev console and the debug overlay.
- The client sends intents through `net/`, never state, and predicts no outcome but a throw's arc (§4.7.52).
- Collision layers come from `PhysicsLayers`. Visual layers: every live `Camera3D` culls with `PhotoLayers.LIVE_VIEW` and every live avatar part (remote bodies, a downed live ragdoll, the hands, carried item views) sits on `LIVE_AVATAR`, so a picture draws the record's puppets instead (#787, §4.7.58; `photo_isolation_test.gd`). Movement numbers (speeds, jump, capsule, eye and step height, stamina,
  the crouch's numbers; the crouch plays everywhere) come from the client's own copy of the mode's `PlayerRules`;
  `PlayerTuning` keeps client feel only (the push factors, the view's easing). Never copy a game number into `player_tuning.tres`: the host checks the mode's.
- Remote players are drawn from `SnapshotBuffer`'s poses only, never from a claimed velocity (their clips too: `AvatarClips` takes the drawn move), and every head or
  basis built from a remote facing goes through its guard (`SnapshotBuffer.look_angles`): a relayed facing can be
  zero or vertical in honest play. A body placed in `_physics_process` for the push search is a `StaticBody3D` and
  calls `force_update_transform()` (§4.7: with Jolt a kinematic body's teleport shows only after the step); one
  dropped leaves the tree before `queue_free`, or the push search later in that frame still finds it (#242).
- A new event's fold in `ClientModel` lands in the core PR adding it (bots need it, E25); client issues read the model.
- Scenes are single-owner. Build reusable pieces as small sub-scenes; level layout itself lives in the
  content area (`levels/`). Hand-written `.tscn` follows `.claude/rules/godot-resources.md`.
- Visual changes come with a `shot` screenshot in the PR. Dev-only scenes (test rooms, previews) go in
  `client/dev/`, never `levels/`.
- Client PRs get `netcode-security-reviewer` with the M4 ADR's checklist (voice: the M5 ADR's), besides `code-reviewer`.

## Tests
- Logic that can live outside a scene should (the flow, snapshot interpolation, stamina prediction, spectate
  targets, countdowns, HUD texts), so it can be unit-tested headless in `tests/unit/client/`.
- Physics runs headless: the controller through a `ClientSession` over a `LoopbackHub` to a `HostSession`, and the
  downed camera against a wall, go in `tests/integration/client/`.
- Several `Game`s in one test each go in a `SubViewport` with `own_world_3d` (`net_pair.gd`; in one world the others'
  remote bodies push its player, #238); a wait for a screen also waits for `game.ui.screen` to show it (`Game._process`
  sets the screens; under load several physics steps run before it, #225); the player's flags follow each event (#241).
- Audio mixes headless in real time (Dummy driver, fake codec, real players and buses, bus peak), a 3D player only with
  a `Camera3D` in the world (observed on 4.7.2, not in the docs): bounded real-time waits there await tests.md's OK.
- Key events do run headless: `Input.parse_input_event(event)` then `Input.flush_buffered_events()` reaches
  `_input`, `_unhandled_input` and the action states (#169's `esc_menu_input_test.gd`); release every key a test
  holds. The mouse mode does not (headless keeps none): give `Game` a `MousePointer` that remembers. How the UI
  looks and feels: `shot` of a preview scene, `playcheck` of the real game in off-screen windows (keys only, its
  scenarios in `tools/playcheck/`) and a human playtest (the M4 ADR's §6); say so in the PR.
- Never open a visible window: `run`, `host` and `join` with `--headless` only; `shot` and `playcheck` are the
  off-screen exceptions.
