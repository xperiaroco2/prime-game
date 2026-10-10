# The photo task (#687): shoot, print, hang: its engine parts, who is in the frame, and the split

- **Status:** Proposed on 2026-10-10. Nothing here is built, and nothing is built now: the track only designs, its
  issues proposals for the M7 backlog
  ([PR #695, comment 6096108206](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096108206)). That
  comment's read-back answer on the Generator's GD7 also keeps every House chain off the flat greybox, so the photo
  task plays on House alone (PD14) and no bot plays it now (§8, PE18). The rules are the engineer's: #687's
  "Decided" list (chat with the game-design manager session, 2026-10-10) and his answers of 2026-10-10 to PD1 to PD15
  ([PR #704, comment 6095444907](https://github.com/xperiaroco2/prime-game/pull/704#issuecomment-6095444907)): every
  recommendation stands except PD1, PD6 and PD3, PD4 and PD11, which he answered otherwise (the camera takes a
  **film** loaded into it, not a memory card carried by the shooter), and PD2 and PD8, which he answered in his own
  words (§6); and his answers of the same day to PD16 to PD18, which those raised, and to §6.1's drafts
  ([comment 6096344994](https://github.com/xperiaroco2/prime-game/pull/704#issuecomment-6096344994)): each
  recommendation, and the drafts as drafted. His answers on the Generator's design
  ([PR #695, comments 6096176652](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096176652) and
  [6096191814](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096191814)) remove the shared task
  total everywhere (#738), which §1.2 and §4 follow. His belt rule on the cooking design
  ([PR #701, comments 6096140448](https://github.com/xperiaroco2/prime-game/pull/701#issuecomment-6096140448) and
  [6096157421](https://github.com/xperiaroco2/prime-game/pull/701#issuecomment-6096157421)): every take while holding
  a two-handed item goes onto the belt, a full belt's item dropping at the taker's feet, the two-handed item staying
  in the hands, while what is not a take keeps the busy-hands refusal; the film's, the photo's and the box's takes
  follow it (§2, §5). The PD items are game rules and taste (the
  [trust ADR](2026-10-04-trust-based-autonomy-gated-merge-into-main.md)'s tier (c)), all answered. The PE items are
  technical, the game-design manager session's to decide and report (tier (a)): decided here, each revertible in its
  issue.
- **Date:** 2026-10-10
- **Deciders:** the engineer (the rules; PD1 to PD18 and §6.1's drafts, answered on 2026-10-10 in PR #704's comments
  6095444907 and 6096344994); the game-design manager session of #676 (PE1 to PE18). Designed by the agent of #687,
  on the engineer's word (#687; the track's kickoff on #593, comment 6088751685).
- **Builds on:** [the Generator ADR](2026-10-10-generator-task.md) (#679, PR #695, proposed: `Interact(station)`, a
  station kind owning its rules, `AtStation`, `StationInSight`, `StationUsable` with `TaskType.use_problem`'s fixed
  list of public reasons, `UseStation`, `TaskType.use_station`, busy hands, exact demands (its GE10, G2), the station
  scenes of its GE11, the runners of its GE12, a task type listing the maps it plays on (`TaskType.maps`, its GE15,
  built in G8), House tests in place of bots (its §7, G7), its issues G0 to G8, and the engineer's GD7: the House's
  chains play on House alone),
  [content API v0](2026-09-29-content-api-v0.md) (task types are classes with settings; `Interact` is v1),
  [MVP rules](2026-09-29-mvp-rules.md) (Tasks: the engineer's decision of 2026-09-30, #79),
  [vision revision 1](2026-10-01-vision-revision-1.md) (V4's "living", no ghosts, two hands),
  [the M4 client design](2026-10-01-m4-first-person-client.md) (its render checklist, §3; E33's hearing range),
  [the zone task ADR](2026-10-09-m7-zone-task.md) (#36: the role-swap check, the station target),
  [level piece conventions](2026-10-09-level-piece-conventions.md) (station scenes in `levels/stations/`), the cooking
  design (#682, PR #701, proposed: `docs/decisions/2026-10-10-cooking-task.md` on its branch; its parts
  by name: `GiveItem.give_new` and the cap `ItemKind.max_items` (CE2, CE3; C1), `StationKind.display` (CE6; C1),
  `Items.give` making room by the engineer's CD3 (b) and CD5 (b) (CE19, CE20; C2), a pick-up beside a two-handed
  item onto the belt through the same move (CE21; C2), the moves that lock an item at a
  station or lay one there with the cause `on_station` (CE5; C2), `Items.vanish`, `ItemVanished` and an item's rest
  tick (C10), `TaskType.use_reasons()` (CE11; C11), the take `Cooldown` (CE17), what stands in for the bots (CE22),
  and the wire test's harness taking a map (C9)),
  [MVP content built by the engineer](2026-09-29-mvp-content-built-by-the-engineer.md) (content and levels are
  provisional, approved in their PRs), [the House map](../design/house-map.md) (§2 decision 7, the stations of §6),
  [tests on CI](2026-10-09-tests-on-ci-local-lint-and-check.md) (#605: what "green" means in §8). Decided since, not
  yet designed: the knockdown reworked (#728: no downed state beyond the knockdown, no movement or speech, a ragdoll)
  and a crouch for every player (#727); and no marker through a wall anywhere (the Delivery redesign's DD4,
  [PR #713, comment 6095445718](https://github.com/xperiaroco2/prime-game/pull/713#issuecomment-6095445718)).
- **Numbering:** PD and PE are this ADR's own; the issues are P2 to P10 (§9; P1 is withdrawn), which the manager
  opens from the PR's handoff. G0 to G8 are the Generator ADR's issues, C1 to C11 the cooking ADR's.

## Context
The engineer's rules (#687, "Decided", and his answers of 2026-10-10), in short: the photo is a task type whose
subtasks are hung photos with a person in them; the host sets how many. A camera stands on a tripod in the photo zone
(the gazebo in the north-west of the yard), facing the photo spot. It takes two: one player stands on the spot, another
uses the camera, which enters a viewfinder view; a press takes the shot, with a flash. The camera takes a **film
loaded into it**, of 5 frames, and the frames left are shown on the camera. The players shoot, then take the film
out (a hold of E over the camera, "for now"), possibly before every frame is used: then only the frames shot are
printed. A film is one-way: once shot it never goes back in, and the printer uses it up. New films come from a box in
storage. The film is carried to the computer and printer in the study (second floor), where its frames are printed. A
printed photo is an item held in the hand that shows exactly what the camera saw at the moment of the shot. It is
carried to the darkroom (basement) and hung on its board: it counts only if a person is really in it, and then it is
fixed for good; one without a person can be taken down and carried away. Any living player in the photo counts,
whatever the role, but nobody standing within the camera's reach: another player is always needed ("you cannot
photograph yourself"). "For now the simplest possible thing"; poses or gestures the photo must show come later. It
plays on the **House**, the map being built for the chains, and not on the flat greybox, which keeps what it deals
today: all these mechanics come with M7, and bots play them later, with the map (PD14, after the Generator's GD7).

The technical core: **the host decides whether a person is in the shot**, at the moment of the shot, from its own
world (architecture invariant 1: a client's image or field is never trusted), and the photo's picture is a client's
render of that moment, for looks only.

What already holds (ARCHITECTURE §9, §5), and what the Generator's design adds (proposed, #679, PR #695):
- **Tasks are shared** (#79): nobody owns one, any living player does any subtask, each type has its own subtasks
  setting. **"Living" means ALIVE** (V4): the knocked-down (`DOWNED`; #728 reworks the knockdown) are not living, and
  the dead have no avatar. **No shared total** (the engineer, on the Generator's design; #738, M7): the HUD's
  "Tasks x / y" and the task screen's "Shared progress" go everywhere; each task's row keeps its own count of done
  subtasks, and a task whose subtasks are all done is struck through.
- **Hidden by sight is a client rule.** Every living or knocked-down avatar and every item reaches every player; an
  honest client shows an item only where it lies, depth-tested, and plays a world sound only within 12 m (the M4
  render checklist, items 5 and 10); no marker shows through a wall (DD4). §5's invariant: every player receives the
  same task events.
- **The task slots:** a `TaskType` subclass with its task state as an inner class; `StationKind` (spawn tag, radius,
  height, palette); `ItemKind` (spawn tag, `hands`); `StationPlaced`, `ItemSpawned`, `TaskState` and `TaskProgress`;
  `Tasks.subtask_done`; `Items` as the one place that moves an item (§9.3).
- **From the Generator** (G1 unless named): `Interact(station)`, sent on E over a placed station; a station kind's
  `actions` tried first for it; `AtStation` (the feet in the station's cylinder, `out_of_reach`), `StationInSight`
  (`blocked`), `StationUsable` (`TaskType.use_problem`, a reason from a fixed list of public ones, else none),
  `UseStation` (`TaskType.use_station`, which alone writes the task state); `HandNotTwoHanded` in each station rule
  (busy hands, #679); a station on every marker of its tag, with exact demands (its GE10); station scenes with a
  use-spot marker and driven nodes, found by the client by the nearest point in 3D (its GE11, G4); the runners
  snapping station markers only on the scenario levels, so a basement station reads (its GE12, G3);
  `subtasks_setting` in `TaskType` (G0, optional); the client's station hint, E taking the target nearest along the
  crosshair (G6); exact marker demands (GE10, G2); `TaskType.maps`, the mode's maps a type plays on, so `DealTasks`
  and the fit check leave a type off a map it does not list (GE15, G8); a scenario step that interacts with stations
  (`StepInteract`, G1), ready for when bots play the chains.
- **From the cooking chain** (#682, designed in parallel; its issues): a source station gives an item through
  `GiveItem.give_new(ctx, kind, at)`, as its herb beds do from `Cooking.use_station` (CE2, CE6; C1): a new item
  spawned at the source (`ItemSpawned`) and given to the taker by `Items.give` (C2), which never refuses for full hands
  (the engineer's CD5 (b): the hand item goes to the belt, else down at the taker's feet) and, beside a two-handed hand
  item, puts the new one-handed item on the belt, a full belt's item down at the taker's feet first, the two-handed
  item staying in the hands (his CD3 (b), which reaches every take: a pick-up from the floor goes through the same belt
  move, CE21, C2; what is not a take keeps the busy-hands refusal), ending in `ItemPickedUp`; a take pays the existing
  `Cooldown` cost (`core/combat/cooldown.gd`, `too_soon`; CE17, 0.25 s by his CD17). A given kind has a cap,
  `ItemKind.max_items`: a take at the cap first vanishes the loose item of that kind that has lain longest (CE3; C1,
  through C10's `Items.vanish` and its public `ItemVanished`). C2 adds the `Items` moves that lock an item at a station
  (`ItemState.Where.LOCKED`, as a delivered package) and lay one on the ground at a station, interactive, raising
  `item_rested` with the cause `on_station` (CE5); C10 an item's rest tick, the tick it last came to rest, set by every
  move that leaves it lying and cleared by every move that lifts it, in one helper (P2 adds a move serial to that
  helper, PE17). C1 adds `StationKind.display`: a display station
  is refused `nothing_to_do` before any owner and skipped by the client's targeting (CE6). C11 extends G1's API with
  `TaskType.use_reasons()` (CE11): `StationUsable`'s one static `rejection_reason()` cannot name several, so a type
  lists every reason its `use_problem` may return (the base: [`unavailable`]) and the mode check tests each against
  the wire alphabet; `PhotoTask.use_reasons()` lists four after P2 and all six after P3, each reason joining the
alphabet in the issue that adds it to the list (PE16).

## Decision

### 1. The mapping (`new-mechanic` step 3)

#### 1.1 Each rule to its engine part

| # | What #687 needs | Engine part | Exists? |
|---|---|---|---|
| 1 | The photo is a task type, like the others | `PhotoTask extends TaskType` (`core/tasks/photo_task.gd`), no tick | missing: P2 |
| 2 | One hung photo with a person is one subtask; the host sets how many | the type's own subtasks setting: `subtasks_setting`, the property Delivery (`core/tasks/delivery.gd`), the zone task and the Generator share and G0 lifts into `TaskType`, names a whole-number `SettingSpec` of the mode (id `photos`, provisional), one lobby control (`client/ui/lobby_panel.gd`), as Delivery's `packages` and the Generator's | exists as a pattern; the setting P5; #256's shared part G0 |
| 3 | A camera on a tripod in the photo zone, facing the photo spot | two station kinds of the type: `camera` (the tripod; its use spot is where the shooter stands) and `photo_spot` (the floor mark the camera frames), each with its spawn tag, radius and height; both reach every client in `StationPlaced`. The photo spot is a display kind (`StationKind.display`, C1): no rule, refused `nothing_to_do`, never a target | the class exists (`core/content/station_kind.gd`); `display` C1; the data P5; the scenes P4 |
| 4 | It takes two: one on the spot, another at the camera | nobody standing within the camera's reach is in the photo: a player whose feet are in the camera's cylinder (where one can press it) is neither counted nor drawn, so the shooter never photographs itself (PD18 (a), the engineer's: "you cannot photograph yourself"; PD1: nobody is left out by who they are) | missing: P2 |
| 5 | Using the camera enters a viewfinder view | a client camera mode: E over a camera that holds a film, while the client's own reach and sight checks hold, puts the view at the frame's pose with the photo's aspect; the host never hears of it (PE1) | missing: P7 |
| 6 | A press takes the shot | `Interact(camera)`, sent from the viewfinder; the camera kind's rule: `HandNotTwoHanded`, `AtStation`, `StationInSight`, `StationUsable`, then `UseStation`, which calls `PhotoTask.use_station`: with a film in the camera, a shot | the parts: G1; the shot: P2 |
| 7 | With a flash | the public `ShotTaken` (§3.3); every client flashes a light at the lens, seen where the eye reaches, and plays the shutter within 12 m | the event P2; the flash and the sound P6 |
| 8 | The camera takes a film loaded into it, not carried by the shooter | a `film` item kind (one-handed, PD5); `Interact(camera)` on an empty camera with a fresh film carried loads it: C2's move lays the film on the ground at the camera (`on_station`), interactive, and `FilmLoaded(station, item)` tells everyone; the camera's film is derived from the item, never stored as a flag (PE17) | missing: P2; C2's move; the kind P5 |
| 9 | A film has 5 frames | `frames_per_film` in the type's data (5, the engineer's starting value); the task state keeps each film's shots by item id (PE6) | missing: P2 (the property), P5 (the value) |
| 10 | The frames left are shown on the camera | every client counts them from public events (`FilmLoaded`, `ShotTaken` naming the film, the film's `ItemPickedUp` or `ItemVanished`) and shows them on the camera's counter in the world, depth-tested, and in the viewfinder; no new field | missing: P7, P8 |
| 11 | The film is taken out, possibly before every frame is used | `PickUp` of the loaded film, the mode's existing rule (sent by a hold of E over the camera, PD17 (a), the engineer's); a film taken out is printable, and never goes back in once shot (`film_exposed`, PD16 (a), the engineer's) | `PickUp` exists; the client P7 |
| 12 | New films come from a box in storage | a `film_box` station kind in storage; its `Interact` rule, as cooking's herb bed's: `AtStation`, `StationInSight`, the cost `Cooldown` (key `photo_take`, a provisional id; CE17), then `UseStation`, for which `PhotoTask.use_station` gives a new film by `GiveItem.give_new` (PE7) | `Cooldown` exists (`core/combat/cooldown.gd`); `GiveItem` C1, `Items.give` C2; the rest P3, the data P5 |
| 13 | The host decides whether a person is in the frame, from its own world at that moment | `PhotoFrame` (`core/tasks/photo_frame.gd`, pure math: the frustum from two markers and the type's data, PE3) and `WorldQuery.line_of_sight` from the lens to each candidate's head, its answers recorded in the command log (PE2) | `line_of_sight` exists (`core/world/`); the rest P2 |
| 14 | A hung photo counts only if a person is really in it | the shot's `has_person`, kept in the task state, decided at the shot and never sent before the hang (PE5) | missing: P2 |
| 15 | A printed photo shows exactly what the camera saw at the moment of the shot | the shot's record in `ShotTaken`: every avatar near the lens at that tick; each client renders the picture as it folds the event (PE4) | the record P2; the render P8 |
| 16 | The film is carried to the computer and printer in the study, where its frames are printed; only the frames shot | a `printer` station kind; `Interact(printer)`: `PhotoTask.use_station` prints every shot of the carried film as `photo` items on the printer's tray marker, and the film is used up (PD3, PD16 (a), PE8) | missing: P3; `Items.vanish` C10 |
| 17 | A printed photo is an item held in the hand | a `photo` item kind (one-handed, PD5); `PickUp`, `PutDown` and `Swap` work on it as on any item (the mode's rules) | the rules exist; the kind P5 |
| 18 | It is carried to the darkroom and hung on its board | a `photo_board` station kind; `Interact(board)` with a photo carried: `PhotoHung(item, station, counted)` | missing: P3 |
| 19 | It counts; a counted photo is fixed for good, one without a person can be taken down and carried away (PD6) | a counted photo is locked on the board (C2's lock), then `Tasks.subtask_done`; one without a person lies on the board, interactive (C2's lay, `on_station`), so `PickUp` takes it down (PE9) | `Tasks.subtask_done` exists (`core/tasks/tasks.gd`); the moves C2; the call P3 |
| 20 | A dissident plays by the same rules (#679) | no condition reads a role, and a person in the frame counts whatever its role (PD1): a role-gated count would tell everyone a role through the board (§9.2, "a public event can reveal its rule's owner") | by design; the role-swap check P2, P3 |
| 21 | Busy hands (#679), and every take beside a two-handed item onto the belt (the engineer's CD3 (b) and its reach, on the cooking design) | what is not a take keeps the refusal: `HandNotTwoHanded` in the camera's (a load or a shot), the printer's and the board's rules; every take works beside a two-handed item and goes onto the belt, a full belt's item put down at the taker's feet first, the two-handed item staying in the hands: a film from the box (`Items.give`), the film out of the camera, a photo off the tray or the board, a film or a photo from the floor (`PickUp`, which C2 routes through the same belt move, CE21); at the box, full hands with a one-handed hand item put it down at the feet (CD5 (b)) | `HandNotTwoHanded` exists (`core/items/hand_not_two_handed.gd`); `Items.give` and the pick-up's belt move C2 |
| 22 | Only living players do subtasks (#79, V4) | the phase's allowlist: `Interact` from the living (G5's Round row), so the knocked-down get `not_accepted` and the dead send nothing | exists: `AcceptSpec` |
| 23 | The host's own player follows the same rules | its client sends `Interact` and `PickUp` like any other | exists |
| 24 | The stations in the photo zone, storage, the study and the darkroom | station scenes in `levels/stations/` (the Generator's GE11): `camera.tscn` (with its film slot and its frames counter), `photo_spot.tscn`, `film_box.tscn`, `printer.tscn` (with its tray marker), `photo_board.tscn` (with its slots), on House alone (PD14), in place of the markers `PoseScreen`, `Printer` and `PhotoBoard`, plus a camera, the box and the first film's marker at points the level task proposes | the markers exist (plain `Marker3D`s under `Stations` in `levels/house/rooms/photo_zone.tscn`, `study.tscn`, `darkroom.tscn`); the scenes P4 |
| 25 | Tested without bots on House (ARCHITECTURE §9.7) | unit tests from fixtures (P2, P3); integration tests on House in the host's real world (P9), which also check every event they emit against `ScenarioInvariants`, hold the leak plant and replay the match from its command log; the real wire in `HostSession` tests on a fixture map (P10); no bot plays the photo task (PD14, PE18) | missing |
| 26 | The photo task plays on the House, not on the flat greybox, which gets none of the House's chains and keeps what it deals today (PD14, as the Generator's GD7) | `TaskType.maps` (the Generator's GE15, built in its G8; not redefined here): the photo task's data lists House alone, so `DealTasks` never draws it on the greybox, and the fit check and `LayoutCheck` ask the greybox for none of its markers | missing: G8 (the part), P5 (the data) |

#### 1.2 Beside Delivery and the Generator

| | Delivery | Generator (#679) | Photo | Why |
|---|---|---|---|---|
| Subtasks | one per package, done when it rests in its circle | the active switches, done together at full charge | one per hung photo with a person, done at the hang | #687: "one hung photo with a person in it is one subtask" |
| Stations | one circle per package, on random markers, coloured | one per marker, exact counts | one per marker of five kinds, exact counts (one each on House), no colours | the stations are the level's devices (the Generator's GE10, GE11) |
| Items | packages, dealt | none | films (one dealt at the photo zone, PD4 (i); the rest from the box) and photos (printed) | the chain carries things between stations |
| Uses | none (`PickUp`, `PutDown`) | `Interact` on a switch and the button | `Interact` on the camera (a load or a shot), the box, the printer and the board; `PickUp` takes a film out of the camera and an uncounted photo off the board | one intent for every station (the Generator's GE1) |
| Host-side geometry | its own cylinder test (`core/tasks/delivery.gd`, `rests_in`) | the cylinder (`StationState.contains`, arriving with M7-Z on `release/m7`), the sight line | the cylinder, the sight line, and the frame: a frustum and a sight line from the lens to each candidate | invariant 1: the host decides who is in the shot |
| Events | `PackageDelivered` | `SwitchChanged`, `ButtonPressed`, `ZoneProgress` | `FilmLoaded`, `ShotTaken`, `PhotoPrinted`, `PhotoHung`, and the item events | each shows something new on the clients |
| Tick | none | the charge | none (PD7 (b) would add one) | nothing in the photo runs on time |
| Task screen | its row's own count, packages delivered of N | a progress bar of the charge (GD3) | its row's own count, photos counted of N, struck through once every photo is counted | no shared total: the HUD's "Tasks x / y" and the task screen's "Shared progress" go everywhere, each row keeps its own count and a done task is struck through (#738, the engineer's) |
| Maps | every map (`maps` empty) | House alone (GD7, `TaskType.maps`, G8) | House alone (PD14, the same part) | the House's chains come with M7 on the House; the greybox keeps what it deals today |

### 2. The rules as the engine runs them (with the engineer's answers)
1. **The deal** (when `DealTasks` draws the photo task, on a map its data lists: House, PD14): a station on every
   marker of each of its five kinds, with no draw for placement, in the order camera, photo spot, film box, printer,
   board (ids in that order, level order within a kind). The demands are exact, as the Generator's (GE10 there), on
   each map the type lists (GE15; the greybox is asked for none): one `camera`, one `photo_spot`, one `film_box`, one
   `printer`, one `photo_board` marker, one `photo` marker (the printer's tray, the photo kind's spawn tag, not
   snapped) and one `film` marker at the photo zone, where one fresh film is dealt (PD4 (i), the engineer's:
   `ItemSpawned`, then `item_rested` with the spawn cause). No RNG purpose: nothing is drawn. With 0 photos the task
   has no subtasks and is done (#79), and nothing is dealt (no station, no film), as Delivery's and Cooking's deals.
2. **A load** is `Interact(camera)` from a living player in Round, while the camera holds no film. In this order it is
   refused `two_handed`, `out_of_reach`, `blocked`, then the type's answer: `unavailable` once the task is done
   (PD12), `film_exposed` when every film the actor carries already has a shot (PD16 (a)), `no_film`
   when it carries none. Applied: the fresh film (the hand's, else the belt's) leaves the actor and lies at the camera
   (C2's lay, `on_station`, no `ItemPlaced`); `FilmLoaded` goes to everyone.
3. **A shot** is `Interact(camera)` while the camera holds a film (PE17): refused `two_handed`, `out_of_reach`,
   `blocked`, then `unavailable` (done) or `no_frames_left` (the film has `frames_per_film` shots). Applied: the film
   takes the next shot; the host checks who is in the frame (§3.2), stores the shot with its `has_person` and records
   the poses near the lens (§3.3); `ShotTaken` goes to everyone. One `Interact(camera)` thus loads or shoots by the
   camera's state, which every client knows; the client sends it from the viewfinder only for a shot (P7).
4. **Taking the film out** is `PickUp` of the loaded film (the mode's rule: reach, sight, the hands as for any item;
   PD17 (a) for the input). Applied as any pick-up (`ItemPickedUp`); the camera is empty from then on (PE17). It is a
   take, so a two-handed item in the hands does not refuse it: the film goes onto the belt, a full belt's item put
   down at the taker's feet first, the two-handed item staying in the hands (the engineer's belt rule, CE21's belt
   move in C2). Anyone may take it out, at any frame count; the task does not refuse it, done or not.
5. **A film from the box** is `Interact(film_box)`: refused `out_of_reach`, `blocked` or `too_soon` (the player took
   from a source less than the cooldown's seconds ago: CE17, PE14). Nothing in the hands refuses it, as at cooking's
   sources (the engineer's CD3 (b) and CD5 (b)). Applied (`PhotoTask.use_station`, PE7): at the film kind's cap the
   loose film that lay longest vanishes first (`ItemVanished`, CE3); a new film appears at the box (`ItemSpawned`) and
   is given to the taker by `Items.give`: into the hand, the hand item to the belt or, with the belt full, down at the
   feet; beside a two-handed hand item onto the belt, a full belt's item down at the feet first, the two-handed item
   staying in the hands; ending in `ItemPickedUp`. The box still gives once the task is done (PD12). A film with no
   shot has no entry in the task state: it is fresh.
6. **A print** is `Interact(printer)`: refused `two_handed`, `out_of_reach`, `blocked`, then `unavailable` (done) or
   `nothing_to_print` (no film carried has a shot). Applied (PD3 and PD16 (a), the engineer's): the film (the
   hand's if it has a shot, else the belt's) prints every shot it has, in shot order, each as a photo on the tray
   marker (at the photo kind's cap the loose photo that lay longest vanishing first; `ItemSpawned`, `PhotoPrinted`,
   then `item_rested`), and the film is used up (`Items.vanish`, `ItemVanished`). Unshot frames print nothing.
7. **A hang** is `Interact(photo_board)`: refused `two_handed`, `out_of_reach`, `blocked`, then `unavailable` (done)
   or `no_photo` (no photo carried). Applied to the hand's photo, else the belt's: if its shot has a person, the photo
   is locked on the board (C2's lock), `PhotoHung` with `counted` true, and the next undone subtask is done through
   `Tasks.subtask_done` (`TaskState`, `TaskProgress`, then `subtask_done` with the photo and its shot as the detail);
   it stays there for good (PD6). Otherwise it lies on the board, interactive (C2's lay, `on_station`), with
   `PhotoHung` and `counted` false: anyone takes it down with `PickUp` and carries it away (PD6); like a printed photo
   picked up off the tray, that is a take, onto the belt beside a two-handed item (CE21). With every subtask done the
   task is done, and every later use of the camera, the printer and the board is refused `unavailable` (PD12).
8. **Nothing else** changes a shot, a film or a hung photo: no hit, knockdown, death or leave. A carried film or photo
   drops at a death or a leave like any item, and keeps its shots; a knocked-down player keeps both slots (vision
   revision 1, ARCHITECTURE §7.1.11 and §7.1.13; if #728's rework changes that, it is cited here then, and the photo
   task needs no code of its own for it). A film in the camera belongs to no player and stays. The state stays in
   `MatchState` until `ResetMatch`.

### 3. The shot: who is in the frame, and the picture
#### 3.1 The frame (PE3)
- **The lens** is the camera station's position (its use spot, snapped to the floor) raised by the mode's
  `PlayerRules.eye_height_m`; **the aim** is the photo spot's position raised by the same height; the frame looks from
  the lens at the aim (`Basis.looking_at`, up the world's up), with a vertical field of view `fov_deg`, an aspect
  `aspect` (width over height) and a reach `range_m` from the type's data (PD9's numbers), and a near limit of 0.3 m.
  The lens is where a shooter's eye is when it stands on the use spot behind the tripod, wherever in the camera's
  cylinder the shooter actually stands, so the frame is the level's, never the player's.
- **`PhotoFrame.contains(point)`**: the point's distance along the view between 0.3 m and `range_m`, its sideways
  offset at most that distance times `aspect · tan(fov_deg / 2)`, its upward offset at most that distance times
  `tan(fov_deg / 2)`. Pure math in `core/`, so the host's check and its unit tests need no renderer.
- **The client uses the same frame.** It builds the viewfinder's `Camera3D` from the same `PhotoFrame` (the two
  stations' positions from `StationPlaced`, the numbers from its own copy of the mode): `fov` set to `fov_deg`,
  `keep_aspect` `KEEP_HEIGHT`, and the screen outside the photo's aspect masked. What the shooter frames is what the
  host checks; P7 tests that the frame's corner points project onto the mask's corners.

#### 3.2 Who is in it (PE2), on the host, in the shot's command
- **The candidates**, in peer-id order: every ALIVE player of any role, the shooter included (PD1, the engineer's:
  "excludes nobody"), whose feet are outside the camera's cylinder (`StationState.contains`; PD18 (a), the
  engineer's): whoever stands where the camera can be pressed is never in the photo, so it takes two (#687) without
  leaving anyone out by who they are.
- **A candidate counts** when its head, its last accepted position raised by the mode's eye height (a jump raises it,
  so the rule counts the head where the picture draws it; unlike `Items.eye_of`, whose floor keeps an actor from
  seeing over a wall from a jump, which does not apply to a subject), lies in the frame (`PhotoFrame.contains`) and
  the line from the lens to it is clear (`WorldQuery.line_of_sight`, recorded in the command log, so a replay agrees).
  When #727's crouch lands, a crouched claim's head is raised by the crouched eye height and the record carries the
  crouch, so the rule and the picture keep agreeing: whichever of #727's issue and P2 lands second adds it here.
- **`has_person`** is whether any candidate counts; the task state also keeps who counted (`subjects`), for a later
  rule that needs it (poses, #687's "later").
- **Only the level blocks a line** (layer 1): a player hidden behind another still counts, which changes nothing while
  any one person is enough (PD2, the engineer's: "all fine for now").

#### 3.3 The record and the picture (PE4)
- **The record** in `ShotTaken`: every player with an avatar (ALIVE or knocked down) whose position lies within
  `range_m` + 2 m of the lens (generous: the renderer clips the rest) and whose feet are outside the camera's cylinder
  (§3.2), as the snapshot's avatar row without its velocity: the peer, its position, its facing, its flags (`downed`;
  #727's crouch when it lands), its hand and belt items. At most the snapshot's 15 avatars. Ground items and bodies are
  not in it: they move only by events, so a client folding `ShotTaken` holds exactly the host's items and bodies at
  that tick, while avatars come from snapshots it draws about 100 ms late. The render itself runs on a later frame
  (below), so an item or a body that a later event of the same batch moves inside the frame is drawn where it lies
  then: rare (it needs a pick-up or a death in the frame within the shot's tick) and cosmetic, never a rule. A
  knocked-down avatar is drawn lying in a rest pose: #728's ragdoll, if it stays each client's own look as its open
  item 4 proposes, is not in the record, so the picture cannot copy it.
- **The picture.** As a client folds `ShotTaken` it renders the shot once: a `SubViewport` with
  `render_target_update_mode` `UPDATE_ONCE`, its `Camera3D` at the frame, puppets of the record's avatars
  (`client/player/remote_player_body.tscn`) on a visual layer only that camera sees, while it skips the live avatars'
  layer (`VisualInstance3D.layers`, `Camera3D.cull_mask`), to which the own first-person hand
  (`client/player/first_person_hand.gd`) moves too, so a subject's own client never draws its live hand item beside
  its puppet's; the flash (an `OmniLight3D` at the lens) on, its pulse lasting until the queued render has drawn
  (`UPDATE_ONCE` draws on the next frame, not while `ShotTaken` is folded); read back
  after `RenderingServer.frame_post_draw` into an `Image`, kept as JPEG bytes while a film or a photo of that shot
  exists (PE15's bound) (`ImageTexture.create_from_image`). A printed photo shows its shot's picture (`PhotoPrinted`
  names the shot). A headless client folds the record and renders nothing.
- **The render stays out of the live view.** Every live camera (the first-person one, the knocked-down and spectate
  cameras, the viewfinder; none sets a `cull_mask` today) drops the photo layer from its `cull_mask`, so no live view
  draws a puppet; the puppets cast no shadow (`GeometryInstance3D.cast_shadow` off), so none falls into the live view
  either. The render's flash is P6's flash itself, the one light at the lens at that moment, its `light_cull_mask`
  including the photo layer, so no second light shows in the live world. The render never changes a live view's
  `visible` (only `SightHider` sets those, `client/CLAUDE.md`): toggling one for the frame would draw it through a wall
  in the main view. So a picture rendered while the own player is knocked down leaves out the items and bodies
  `SightHider` hides then, and live avatars' shadows near the lens may fall into the picture (they stand about where
  the record does): both rare and cosmetic, never a rule.
- **The payload.** `ShotTaken(station, film, shot, record)`: the camera's station id, the film's item id, the shot's
  id (which `PhotoPrinted(item, shot)` names later, so a client binds a printed photo to its picture) and the record,
  at most 15 rows; the decoder refuses a longer record, and P2 adds a `WireBudget` case at 15 rows (about 535 bytes).
- **Bandwidth.** One `ShotTaken` is about 40 bytes plus about 33 per avatar in the record: under 400 bytes with 10
  players, to each player once. A picture sent as an image would be 10 to 50 KB per shot, uploaded and relayed to
  every player (the Alternatives).
- **Leaks (invariant 2).** The record holds avatar fields every player receives in the snapshots anyway (§5: every
  living or knocked-down avatar reaches every player of the match), taken at the shot's command rather than at the
  tick's end, so at most one movement claim apart; the one addition is the recipient's own pose, which it knows.
  `ShotTaken` names the camera and its film, never a player, and the record leaves out everyone in the camera's
  cylinder alike, so no event singles out the shooter: who stood at the camera stays what the snapshots show (PD13).
  So `ShotTaken` is a task event every player receives alike (§5's invariant holds), with no new audience and no role
  in it. `has_person` is never sent before the hang (PE5): `PhotoHung`'s `counted`, `TaskState` and `TaskProgress` at
  the hang tell what a look at the photo tells. A modified client could compute it from the record, as it could from
  the snapshots (PD13).
- **Lag (PE13).** The host uses its positions at the shot's tick, not rewound to what the shooter saw (remote avatars
  drawn about 100 ms late, plus half a round trip), as for hits (§10's lag compensation after the MVP). A subject
  standing on the spot is the same in both; one walking through the frame may differ by a step.

### 4. What everyone sees

| What | Who learns it | How |
|---|---|---|
| Where the camera, the spot, the box, the printer and the board stand | everyone | `StationPlaced` in the deal (and the level's own scenes) |
| A film loaded, and the frames left | everyone; an honest client shows the film in the camera's slot and the frames left on its counter, in the world, depth-tested (no marker through a wall, DD4), and in the shooter's viewfinder | `FilmLoaded`, `ShotTaken` (naming the film), the film's `ItemPickedUp` or `ItemVanished` |
| A shot: when, at which camera, onto which film | every client receives it; an honest one shows the flash where the eye reaches and plays the shutter within 12 m | `ShotTaken` |
| Who took a shot | no event names the shooter; the snapshots show who stood in the camera's cylinder, and an honest client shows only the flash | §3.3, PD13 |
| Who stood near the lens at the shot | every client receives it (as every snapshot shows); shown only in the photo's picture, depth-tested | `ShotTaken`'s record |
| Whether a shot has a person | nobody, through an event, before its photo is hung; whoever sees the photo sees its picture | the picture; at the hang `PhotoHung`'s `counted`, `TaskState` and `TaskProgress` |
| A film taken from the box or out of the camera, a photo printed, picked up, put down, hung, taken down | everyone | `ItemSpawned`, `ItemPickedUp`, `ItemPlaced`, `ItemVanished`, `PhotoPrinted`, `PhotoHung`; sounds within 12 m |
| Who took a film, printed or hung | no photo task event names a player (they name stations and items), but `ItemPickedUp` names the taker, as for any item, so every client knows who holds which film and photo; the snapshots show who stood there | as for a delivery |
| How many photos are needed and counted | everyone, on the task screen: the photo task's row shows the photos counted of N, struck through once every photo is counted; no shared total in the HUD or on the task screen (#738) | `TaskState`, `TaskProgress` |
| A photo's picture | whoever sees the photo: in a hand, on the tray, on the board, or held up by its holder | drawn on the photo in the world, depth-tested; the holder may look at its own up close (P8) |

### 5. Edge cases

| What happens | What the engine does | Why |
|---|---|---|
| Two players shoot in one tick | commands in their order (§4.5.3): two frames of the camera's film; with one frame left the second is refused `no_frames_left` | determinism |
| The subject steps out as the shot is taken | the host's position at the shot's tick decides; the picture shows the same moment (the record) | §3.3: one moment for the rule and the picture |
| The shooter steps in front of the lens, within the camera's reach, and shoots | not counted, not drawn: its feet are in the camera's cylinder, as anyone's who stands there | it takes two (#687); PD18 |
| The subject is knocked down in the frame | not counted (PD1, the engineer's: living players); drawn lying in a rest pose | V4: "living" means ALIVE; #728 |
| A player behind the gazebo's wall, inside the frame | not counted: the line from the lens is blocked; the picture shows the wall | §3.2 |
| A player far behind the spot, in the frame but beyond `range_m` | not counted; drawn small if the picture reaches it | PD9's range |
| Only a body without a head in the frame (the head cut off by the frame's edge) | not counted | §3.2: the head must be in the frame (PD1) |
| The subject jumps as the shot is taken | its head counts where it is in the air, the picture draws it there | §3.2: the record's position and the rule's head agree |
| Another player's body fills the lens, its own head outside the frame, the subject behind it | the subject counts (only the level blocks a line), though the picture shows the body in front | accepted as rare: any one person is enough (PD2); a later rule needing a visible subject would test lines against the avatars too |
| A package carrier loads or shoots at the camera, prints or hangs | `two_handed` | busy hands (#679): none of these is a take, so the engineer's belt rule keeps the refusal |
| A package carrier at the box | the film goes onto the belt; with the belt full, the belt's item drops at the taker's feet first and the film goes onto the belt; the package stays in the hands | the engineer's belt rule (CD3 (b) and its reach, PR #701's comments 6096140448 and 6096157421): every take works beside a two-handed item |
| A package carrier takes the film out of the camera, a photo off the tray or an uncounted one off the board | the same: onto the belt, a full belt's item at the feet first, the package kept; a film taken out so empties the camera like any pick-up (PE17) | the same rule, through the pick-up's belt move (CE21, C2) |
| A film taken out after two frames | prints those two; it cannot go back in (`film_exposed`, PD16 (a)) | the engineer: "then only the frames shot are printed" |
| The film taken out while someone looks through the viewfinder | that client leaves the view; a shot already sent is refused `no_film`, or, if its sender carries a fresh film, loads it: one intent loads or shoots by the camera's state | PE1, PE17 |
| Two players load an empty camera in one tick, each with a fresh film | the first loads; the second's `Interact(camera)` finds a film in the camera and is a shot nobody aimed: a frame used, `ShotTaken` to everyone, its photo likely without a person | accepted: one intent loads or shoots by the camera's state (PE1); it costs at most a frame, leaks nothing and trusts no field; an intent per action would need a new intent kind for one rare race |
| A camera with a film, a second film carried | E enters the viewfinder; the second film goes in only once the first is taken out | one film in a camera |
| A film with no frame left | `no_frames_left`; someone takes it out and fetches a new film from storage | #687 |
| A carried film dropped, or left at a death | an item like any other, with its shots; anyone picks it up and prints it | a film's shots belong to the film, not to a player |
| A photo without a person hung | lies on the board, counts nothing; anyone takes it down and carries it away, or hangs it again (counting nothing) | PD6, the engineer's |
| A dissident tries to take a counted photo down | it is locked: `PickUp` refuses it as any locked item | PD6: fixed for good |
| A photo hung after every subtask is done | `unavailable` (PD12) | the Generator's "done for good" |
| A dissident takes the film out and hides it, or hides a photo | an item like any other: the others search for it or fetch a new film; the box never runs out | the same play as hiding a package |
| A dissident wastes frames on an empty spot | the film fills; its frames print as photos without a person | same rules for everyone (#679) |
| A player in the viewfinder is hit or knocked down | the client leaves the view (P7); the host never knew of it | PE1 |
| A client sends `Interact(camera)` from afar or in a burst | `out_of_reach`; each accepted shot uses a frame of the camera's film; the reliable-intent bucket bounds the rest (§4.5.6) | PE14 |
| The box pressed again and again | refused `too_soon` but one take per the cooldown's seconds (0.25 s: 4 a second); each accepted take makes its own room (once the hands are full, a put-down at the feet) and goes to everyone; at the film cap (32, a placeholder) a loose fresh film vanishes first (the spammer's own, dropped at its feet), one with shots only when no fresh one is loose, and the film in a camera last (PE10's tiers), so spamming the box in storage never empties the gazebo's camera or loses the team's shots: that would take 31 other loose films each loaded and shot at the gazebo | PE10, PE14; CE3, CE17 |
| Round ends | nothing more counts; the state stays until `ResetMatch` | §9.1 |

### 6. PD items (the engineer's: game rules and taste)
The engineer answered PD1 to PD15 on 2026-10-10
([PR #704, comment 6095444907](https://github.com/xperiaroco2/prime-game/pull/704#issuecomment-6095444907)): every
recommendation stands except PD1, PD6 and the film (PD3, PD4, PD11), which he answered otherwise; PD2 and PD8 he
answered in his own words. PD16 to PD18, which those answers raised, and §6.1's drafts he answered the same day
([PR #704, comment 6096344994](https://github.com/xperiaroco2/prime-game/pull/704#issuecomment-6096344994)): each
recommendation, and the drafts as drafted. The options stay for the record; the last column is what holds now.

| # | Question | Options | Trade-offs, and the failure each prevents | Decided |
|---|---|---|---|---|
| PD1 | Who counts as "a person in the photo" (#687's open item 1) | Who: (i) any ALIVE player but the shooter, whatever the role; (ii) the knocked-down too. Where: (a) anywhere in the frame, with the head in the frame and in sight of the lens; (b) only standing on the spot (its cylinder) and in sight; (c) any part of the body in the frame | (ii) a knocked-down player lying in the frame counts, so knocking someone down on the spot becomes a way to do the task; (i) matches "only living players do subtasks" (V4). A role test would tell everyone a role through the board (§9.2), so "whatever the role" is also the leak-safe answer. (b) a person clearly in the picture but a step off the spot does not count. (c) a hand at the frame's edge counts | **The engineer's:** any living player counts, **the shooter included** (he sees no way the shooter could be in the frame, but excludes nobody), whatever the role, with (a). PD18 (a), his, keeps the shooter out of the frame by place |
| PD2 | Does the same player count for several photos (open item 1) | (a) yes: any photo with any living person in it counts; (b) each counted photo must show someone not yet counted | (b) needs as many subjects as photos, so the count would depend on the player count. (a) two players can do the task alone; others help by carrying | **(a), the engineer's words:** "one player in several photos, several players in one: all fine for now" |
| PD3 | The printing (open item 2) | One use prints: (a) every unprinted shot, onto the printer's tray; (b) one shot per use; (c) into the hands. Time: (i) at once; (ii) after N seconds at the printer. The card: (x) stays with the player, each shot printing once; (y) the printer keeps it | (b) up to five presses for one card. (c) the hands hold two items. (ii) a wait with nothing to decide. (y) a card with shots left is lost | **The engineer's film** (with PD4 and PD11): the frames shot on a film are printed, only those; one use prints them all, at once ((a) and (i), which his answer leaves as recommended). The printer uses the film up (PD16 (a), his) |
| PD4 | The supply (open item 3) | Supply: (a) a box in storage that hands one item into the hand per press of E, without limit; (b) a fixed stock dealt in storage; (c) a box with a limit. The first: (i) one lies at the photo zone at the round's start, later ones come from storage; (ii) every one comes from storage | (b) and (c) can run out, and a dissident who hides the stock ends the task for good. (ii) every round starts with a run from the gazebo down to the basement and back before the first shot | **(a) and (i), the engineer** ("PD4's box, as recommended"), for films: new films come from the box in storage, a fixed station, without limit; one fresh film lies at the photo zone at the round's start |
| PD5 | Hands (open item 3) | (a) the card (now the film) and the photo are one-handed: a player holds both at once (hand and belt); (b) the photo takes both hands; (c) photos take no slot | (b) a photo carrier cannot use the camera, and carries one photo at a time. (c) a new slot kind | **(a), the engineer** (the recommendation) |
| PD6 | A hung photo (open item 4) | (a) locked on the board for good, with or without a person; (b) one without a person can be taken down again; (c) any photo can be taken down, a counted one undoing its subtask | (c) a dissident undoes the team's progress, and `Tasks` never undoes a subtask. (a) junk photos clutter the board | **(b), the engineer's:** a photo with a person is fixed for good; one without can be taken down and carried away (PE9) |
| PD7 | A more natural touch (open item 5, the engineer's wish) | (a) none now; (b) a hung photo develops on the board for N seconds before it counts, its picture fading in; (c) hanging takes N seconds of holding E; (d) the printer prints blank photos that show their picture only once developed | (d) breaks "a printed photo shows exactly what the camera saw". (c) a wait with nothing to decide. (b) the darkroom becomes where photos develop | **(a), the engineer** (the recommendation); (b) stays the first candidate, a small change on top of P3 |
| PD8 | The words (open item 6) | the task's name; the task screen's description; the lobby label of the photo-count setting (`SettingSpec.display_name`) | the mode check refuses an empty description, so P5 cannot land without one | **The engineer: the agents draft them** (§6.1); he took every draft as drafted ([comment 6096344994](https://github.com/xperiaroco2/prime-game/pull/704#issuecomment-6096344994)), and P5 uses them |
| PD9 | The numbers (open item 6) | the photo count's default and range; the frame's `fov_deg`, `aspect` and `range_m`; each station's `radius_m` and `height_m`; the shortest time between two takes from the box by one player | a large range or a wide frame counts a distant passer-by in the yard; a narrow one makes the subject hunt for the frame | **The engineer, the recommendation:** placeholders in P5, "not a decision": 1 to 5 photos (one film's worth at most), default 3; 50° vertical, 4:3, 10 m; 2 m and 2 m for the stations, as the Generator's GD6; the take's cooldown 0.25 s, his CD17 answer for cooking's sources (CE17) |
| PD10 | The frame | (a) fixed: the camera always frames the spot, no turning, no zoom; (b) the shooter turns it within limits | (b) the shot's intent must carry a direction, a client claim the host clamps | **(a), the engineer** (the recommendation) |
| PD11 | The card and the camera | (a) the shooter carries the card and each shot goes onto it; (b) the card goes into the camera and stays there until someone takes it out | (b) two more uses (put in, take out), and a card left in the camera can be taken by anyone. (a) no state on the camera | **(b)'s kind, the engineer's film:** the camera on its tripod takes a film loaded into it; a film has 5 frames (#687), and the frames left are shown on the camera; the players shoot, then take the film out, possibly before every frame is used (then only the frames shot are printed); the film is loaded into the camera, not carried by the shooter while shooting. It is taken out by a hold of E over the camera (PD17 (a)) and never goes back in once shot (PD16 (a)) |
| PD12 | After the task is done | (a) the camera, the printer and the board refuse (`unavailable`); the box still gives; (b) everything keeps working and counts nothing | (b) photos and junk keep piling up for nothing | **(a), the engineer** (the recommendation); a film in the camera can still be taken out |
| PD13 | How hidden a photo's content is before it is hung, and who took a shot | Content: (a) hidden by sight: every client receives every shot's record and shows a picture only on a photo seen in the world or held; (b) hidden on the wire until the photo is picked up or hung. The shooter: (x) public on the wire; (y) hidden on the wire | (a) a modified client could tell which shots have a person, as it can draw every hidden package today. (b) a private task event, a photo in another player's hand drawn blank. (y) costed a second event or field while the card named its holder | **(a) and (x), the engineer** (the recommendation). With the film in the camera no event names the shooter any more at no cost (§3.3): less is public than (x) allowed, never more |
| PD14 | Where the photo task plays, and how many task types a match deals | the Generator's GD7: (a) in the base mode with P4's station scenes on the greybox too, at placeholder points above y = 0; (b) the base mode on House only, banned by hand elsewhere; (c) a per-map draw; and `tasks` every type or drawn | as GD7. The photo task needs seven tags on a map (five station kinds, the tray and the first film), so (a) costs the greybox five station scenes and two markers, one more task every match and scenarios to keep in step | **House only, as GD7, the engineer's** ([PR #695, comment 6096108206](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096108206), his read-back answer on the Generator's GD7, which replaces this row's first reading, (a) with the station scenes and scenarios on the greybox): the photo task plays in the base mode on the House, the map being built for the chains, with P4's station scenes, in every match, and **not on the flat greybox**, which "keeps only the basic Delivery and nothing else" (his words; it gets none of the House's chains; whether the zone task it deals today leaves too is the Generator's GD13, which changes nothing here): all these mechanics come with M7, and bots playing them comes later, with the map (ARCHITECTURE §9.7: bots do not play House). So no photo station scene, marker or scenario on the greybox. Neither (b)'s ban by hand nor (c)'s draw by markers: the photo task's data lists House alone in `TaskType.maps` (GE15, G8). `tasks` as GD7 (i): every type that plays on the map, every match. The match clock stays the base mode's until he retunes it after a playtest |
| PD15 | The flash and the sounds | a flash light at the lens on each shot, seen where the eye reaches; a shutter click; a printer sound while it prints; a sound at the hang; each within 12 m | #687: "with a flash"; the sounds are not in it | **The engineer, the recommendation:** the flash, the shutter and the printer; placeholder blips built in code, as `WorldSounds` makes today's, until his CC0 files arrive with their `docs/credits/` entries |
| PD16 | A film after it is taken out, and at the printer (from PD3 and PD11) | (a) one way: a film that has a shot never goes back into a camera (`film_exposed`), and the printer uses it up as it prints (it vanishes); (b) reusable: a film taken out goes back in with its frames left, and the printer leaves it with the player, each shot printing once; (c) as (a), but the printer hands the empty film back | (b) a film can go between the camera and the printer several times, so the task state must mark each shot printed, and a half-shot film looks the same as a fresh one in a hand. (c) an empty film nobody needs, left lying. (a) is how a real film goes (the engineer's "closer to a real photography process where it helps"), and "only the frames shot are printed" holds with nothing to remember; the cost is that a film taken out too early wastes its other frames | **(a), the engineer** ([comment 6096344994](https://github.com/xperiaroco2/prime-game/pull/704#issuecomment-6096344994)): "a film is one-way: used up at the printer" |
| PD17 | How a film is taken out of the camera | (a) hold E over the camera, as cooking's hold over a box (his CD4 (a)), which sends `PickUp` of the film; (b) a key in the viewfinder; (c) aim at the film in the camera's slot and press E | (b) a second key to learn, and taking the film out only from the viewfinder. (c) the film's slot is a small target on the tripod, next to the camera's own. (a) one gesture the player already knows from cooking's boxes, and the host needs nothing new: `PickUp` is the existing intent | **(a), the engineer** ([comment 6096344994](https://github.com/xperiaroco2/prime-game/pull/704#issuecomment-6096344994)): hold E over the camera to take the film out, "for now" |
| PD18 | How "it takes two" (#687) holds now that the shooter counts (PD1) | (a) nobody standing within the camera's reach (its cylinder, where one can press it) is in the photo: neither counted nor drawn; (b) as answered, literally: anyone in the frame counts, so a shooter who steps up to 2 m in front of the lens, still within the camera's reach, photographs itself and does the task alone | the engineer sees no way the shooter could be in the frame, but the camera's reach (2 m, PD9) extends in front of the lens, and the frame starts 0.3 m from it, so with (b) one player alone completes every photo. (a) makes his reading true by place, not by person: a second player standing in the camera's reach is left out too, which matters only if the spot is that near the camera (P4 places it farther) | **(a), the engineer** ([comment 6096344994](https://github.com/xperiaroco2/prime-game/pull/704#issuecomment-6096344994)): another player is always needed, and nobody within the camera's 2 m reach counts. His words: "you cannot photograph yourself, it is impossible in principle: you look through the frame, and the frame must hold a player" |

#### 6.1 The drafts (PD8), taken by the engineer as drafted
He asked the agents to draft the name, the description and the setting's label, and took every row below as drafted
([PR #704, comment 6096344994](https://github.com/xperiaroco2/prime-game/pull/704#issuecomment-6096344994): "fine, as
drafted"). P5 uses them; like every content file, P5's are provisional until he approves its PR.

| What | Draft | Why this draft |
|---|---|---|
| The task's name | "Photography" | one word beside "Delivery" and "Cooking"; the lobby label then reads "Photos (Photography)" |
| The subtasks setting's label (`SettingSpec.display_name`) | "Photos (Photography)" | Delivery's pattern, "Packages (Delivery)": what the number counts, then the task |
| The task screen's description | "Load a film into the camera, photograph a player on the spot, print the film, and hang the photos on the board: each one with a person in it counts." | the chain in the order it is played, and the one rule a player must know; no room names, so it holds on any later map that lists the task |
| The item names (the HUD's hand item) | "Film", "Photo" | short, and a film in the hand reads as what goes into the camera |

### 7. PE items (technical: the manager decides and reports)

| # | Choice | Options | The failure it prevents | Decision |
|---|---|---|---|---|
| PE1 | The intents at the camera, and the viewfinder | (a) the viewfinder is a client camera mode the host never hears of; a shot is `Interact(camera)` sent from it, a load `Interact(camera)` on an empty camera, the host telling them apart by the camera's state and checking everything again; the film comes out by `PickUp`; (b) the host keeps who uses the camera: enter and leave intents, one user at a time; (c) `Use(facing)` in the view | (c) `Use` goes to the hand item's rule first (§9.2): a knife holder would stab. (b) two more intents and a "busy" state to clear on every hit, knockdown, death and leave, for nothing the rules need. A shot and a take-out both by `Interact(camera)` could not be told apart, so one of them needs another intent, and `PickUp` already takes an item. (a) a modified client could shoot without looking: it gains nothing, the host decides who is in the frame | (a) |
| PE2 | Who decides "a person in the frame" | (a) the host, at the shot's tick, from its own state: `PhotoFrame` and `WorldQuery.line_of_sight` from the lens to each candidate's head, the candidates every ALIVE player whose feet are outside the camera's cylinder (§3.2); (b) the client reports whom it saw; (c) the client sends its picture and the host analyses it | (b) and (c) trust a client's field or image, against invariant 1: a modified client "sees" a person who was not there. (c) also needs image analysis on the host | (a) |
| PE3 | The frame's pose | (a) from two station markers, the camera's and the spot's (both snapped, both in `StationPlaced`), the mode's eye height and the type's numbers; one `PhotoFrame` in `core/` used by the host and the client; (b) an oriented marker: `LevelLayout` gains a rotation per marker, read from a lens node; (c) `StationPlaced` gains a facing | (b) changes `LevelLayout`, `MarkerReader` and the command log's layouts, and the client would still need the rotation sent. (c) a wire change for every station kind. Both let the level's lens node and the host's frame drift apart unseen. (a) needs no change to the layout, the reader or the wire, and the client builds the very frame the host checks from public data | (a); P9 tests on House that the camera scene's look matches the frame (the lens point clear of collision, the line from the lens to the aim clear) |
| PE4 | How the picture reaches the clients | (a) each client renders it from the shot's record (§3.3) as it folds `ShotTaken`; (a2) the same at `PhotoPrinted`; (b) the shooter's client renders and uploads an image that the host relays; (c) the host renders | (b) 10 to 50 KB per shot uploaded and relayed to every player, a large message split over ENet's reliable lane and WebRTC's message size, and a client-authored picture: a modified client shows a person who was not there, or anything at all. (c) a headless host has no renderer (its worlds are physics only, §4.5.9), and `core/` and `server/` hold no rendering. (a2) items moved since the shot would be drawn where they lie then, unless the record held them too, and the flash would not be in the same frame. (a) under 400 bytes per shot; the record holds only what the snapshots showed | (a) |
| PE5 | `has_person` on the wire | (a) never sent before the hang: kept in the task state; the hang's `PhotoHung` (`counted`), `TaskState` and `TaskProgress` are the only signal; (b) in `ShotTaken` or `PhotoPrinted` | (b) a client could print "person: yes" beside a photo nobody has looked at, which no picture says. At the hang `counted` says no more than `TaskProgress` does, and the client needs it to know a counted photo is fixed (PD6) | (a) |
| PE6 | Where the state lives | (a) the task state (`PhotoTask.State`): the station ids; per camera the film its last load laid there and that film's move serial after the load (PE17); per shot its id, film, tick, `has_person` and `subjects`; per film (item id) its shots; per photo (item id) its shot; the counted photos in hang order. An item's entry goes with the item: `PhotoTask` drops it in the same command as each vanish of a film or a photo (today every such vanish is its own: a cap at the box's take or at a print, and the used-up film), so an id C10 recycles (CE3) comes out fresh, never inheriting old shots; the same step clears a camera whose stored film is the vanished one, since a new item under a recycled id starts its move serial again and could reach the stored serial after a spawn, a give and a put-down, so the host would think the camera holds a film lying in storage (the design review); the print and the hang test the item's kind first, never only the map; the client drops its counters and pictures keyed by that id on `ItemVanished`; (b) the per-part state table; (c) fields on `ItemState` (shots on a film, a shot on a photo) | (b) splits one task over two homes where §9.1 names the task state. (c) fields every item carries for one type. With (a) a film the box gave is unknown to the state until its first shot, and counts as fresh | (a) |
| PE7 | Giving a film | (a) as cooking's herb bed (its CE6): the box's station kind holds a rule `AtStation`, `StationInSight`, the cost `Cooldown` (key `photo_take`, a provisional id; the seconds PD9's), then `UseStation`; `PhotoTask.use_station` for the box calls C1's `GiveItem.give_new(ctx, film, the box's position)`: the cap, `ItemSpawned`, `Items.give` (C2) and `ItemPickedUp`, in cooking's CE13 order; (b) a composed `GiveItem(film)` effect on the box's rule; (c) the box as cooking's carried box item (its CE1, CE7), taken from by `Interact(item)`; (d) a photo-only source | (b) C1's effect spawns at the rule's target item's rest position; a station target would extend C1 for one task. (c) a box that can be carried off and hidden ends the supply, against the engineer's "new films come from storage". (d) a second item source beside cooking's for the same thing | (a). The box's cooldown key is its own, so a film take and a cooking take never wait on each other: each source bounds its own spam |
| PE8 | Where printed photos appear, and the film after | (a) on the printer's tray: the photo kind's spawn tag (`photo`) on a marker in the printer's scene, not snapped; each photo `ItemSpawned` there, then `PhotoPrinted(item, shot)`, then `item_rested` (spawn); then the film vanishes (C10's `Items.vanish`, `ItemVanished`; PD16 (a)); (b) into the actor's hands; (c) at the printer's use spot on the floor | (b) the hands hold two items, one of them the film, and a film prints up to five photos. (c) photos lying on the floor in front of the printer. A new item kind reusing `ItemSpawned` keeps one way for a client to learn of a new item; `PhotoPrinted` adds only the binding to its shot, as `ItemSpawned` binds a package to its circle | (a) |
| PE9 | Hanging | (a) cooking's moves at a station (its CE5, built in C2): a counted photo locked at the board's position (`ItemState.Where.LOCKED`, as a delivered package), so no `PickUp` takes it; one without a person laid on the ground at the board (`on_station`), interactive, so `PickUp` takes it down (PD6); `PhotoHung(item, station, counted)` either way; then `Tasks.subtask_done` if counted; the client draws hung photos in hang order on the board scene's slots; (b) `Items.place` at the board for both, the type's `on_fact` locking a counted one | (b) a fact that every task type's check then reads for a photo no circle wants, and an `ItemPlaced` that says the photo lies on the floor. (a) two moves in `Items`, the one place that moves items (§9.3), shared with the grill and the plates | (a) |
| PE10 | A bound on items | (a) C1's cap per kind (CE3): the film kind's `max_items` 32 and the photo kind's 64 (placeholders, "not a decision"), applied by the box's take and by each photo a print makes: at the cap the loose one that lay longest vanishes first; neither kind has `vanish_seconds`, so nothing vanishes on a timer; (b) a bound on all items in `Items`, refusing a new one (`too_many_items`); (c) none | (c) a box "without limit" lets one client create a film per intent (a take makes its own room, CD5 (b)), 4 a second under PE14's cooldown: item ids are `u16`, and long before they run out every client draws thousands of items; the photos follow the films. (b) a second bound beside C1's for the same failure, and a refusal that lets one spammer block the box. A timer would lose a film or a photo set down for a minute, a game rule nobody asked for. With (a) only a spammer reaches a cap (normal play uses one or two films and a few photos), and C10's id reuse handles the rest. But CE3's plain order (the loose one that lay longest) would make the film cap a remote sabotage tool: a dissident pressing E at the box in storage for about 8 s would vanish the film loaded in the gazebo's camera, with the team's shots, nobody in sight (the design review). So the cap is tiered (P3 adds the hook to C1's cap): `TaskType.cap_tier(state, item) -> int`, 0 by default, asked of every dealt task type (the highest answer wins); the cap vanishes the loose item of the lowest tier first, then CE3's order (the earliest rest tick, then the lowest id). `PhotoTask`'s tiers: 0 a fresh film outside a camera, 1 a film with shots outside a camera, 2 the film in a camera; every photo 0, since a tier by `has_person` would tell everyone through `ItemVanished` which photos hold a person (PE5). The film tiers reveal nothing new: which film has shots and which lies in a camera are public (`FilmLoaded`, `ShotTaken`, `film_exposed`). A spammer's own fresh films always go first, so the bound and PE15's worst case hold unchanged, and nothing about the box's play changes for anyone who is not spamming: a cap the engineer never needs to rule on | (a), with the tiers |
| PE11 | Which item, and the order of events | a load takes the hand's film if it is fresh, else the belt's; a print the hand's film if it has a shot, else the belt's; a hang the hand's photo, else the belt's. One load: `FilmLoaded`. One shot: `ShotTaken`. One take from the box: CE13's (at the cap `ItemVanished`, `ItemSpawned`, a put-down's `ItemPlaced` if any, `ItemPickedUp`). One print: per photo in shot order (at the cap `ItemVanished`), `ItemSpawned`, `PhotoPrinted`, `item_rested`; then the film's `ItemVanished`. One hang: `PhotoHung`, then, if counted, `TaskState`, `TaskProgress`, `subtask_done`, as Delivery sends `PackageDelivered` first. The deal: `StationPlaced` per station in id order, then the first film's `ItemSpawned` | a `PhotoPrinted` before its item exists on the client; a film gone before its photos are bound to its shots; a count shown before the photo is on the board | as stated |
| PE12 | The mode checks and the demands | `PhotoTask.check`: the five station kinds set, with different spawn tags (and ZE3 across the mode); the photo spot a display kind (C1) with no rule; the film and photo item kinds set, declared by the mode, one-handed, with spawn tags different from every station kind's; `frames_per_film` at least 1; `fov_deg` within 1 to 179, `aspect` within 0.25 to 4, `range_m` within 0.5 to 100, their neutral defaults outside; the subtasks setting declared, a whole number, minimum at least 0; the camera's, box's, printer's and board's stations each holding an `Interact` rule whose effect is `UseStation`, the box's paying a `Cooldown`; the film kind's cap at least twice the mode's maximum of players plus 1, and the photo kind's at least twice that maximum plus the setting's maximum plus `frames_per_film` plus 1 (CE3's floor: the hands hold at most two a player and the board locks at most the setting's maximum, so at a cap a loose one always exists to vanish, and a print never vanishes a photo of its own batch; with none, which these floors make impossible today, C1 refuses the take `unavailable` and the print stops there). Demands (G2's exact counts), on each map the type lists (House; a map it does not list, the greybox, is asked for none, GE15): exactly one marker of each station kind's tag, exactly one `photo` marker and exactly one `film` marker, whatever the setting and the players; and the level fit check refuses a photo spot marker lying no farther than the camera kind's `radius_m` from the camera's marker horizontally (it keeps the frame off the vertical, where `Basis.looking_at` is degenerate on the host and the client, and the spot beyond the camera's reach, PD18) | a camera without a spot has no frame; a second printer would have no tray of its own; a box that gives another kind leaves no way to get a film; a cap a full table of players can hold entirely in their hands | as stated |
| PE13 | Lag | (a) the host's positions at the shot's tick; (b) rewind the subjects to what the shooter saw | (b) a rewind buffer the MVP has for nothing (§10: lag compensation after the MVP playtest); a subject standing still is the same in both | (a) |
| PE14 | A rate limit on the photo task's events | (a) no window: `FilmLoaded`, `ShotTaken` and `PhotoHung` follow one accepted intent each; a print's photos are bounded by the film's frames, the film used up; the box's takes, which emit up to four events each, are bounded by its `Cooldown` (CE17); (b) ZE4's window; (c) the bucket alone, for the box too | (c) a take makes its own room (CD5 (b)), so a spammer takes at the bucket's 20 intents a second, each take emitting up to four reliable events to every player: 80 a second (CE17), the rate the Generator's GE8 rejects; with the cooldown at 0.25 s, at most 16 a second, under today's 20 for `PickUp` and `PutDown` spam. For the rest the bucket bounds the intents (§4.5.6), and nothing in the photo task changes on its own over time | (a); P2's and P3's unit tests and P10's wire test check it (§8) |
| PE15 | The client's render | puppets on a photo-only visual layer that every live camera's `cull_mask` drops, casting no shadow, live avatars on a layer the photo camera skips (no second `World3D`, no copy of the level), the flash P6's own light, no live view's visibility touched (§3.3); 384 pixels high and as wide as `aspect` makes it (512 at 4:3), kept as JPEG bytes (`Image.save_jpg_to_buffer`, tens of KB) while a film or a photo of that shot exists, decoded (`Image.load_jpg_from_buffer`) into a texture only while a photo of it is drawn, all dropped at a new match; renders queued, one per frame; headless clients render nothing. The worst case one hostile peer can force on every client: the pictures kept are bounded by the caps (PE10), the films' unprinted shots plus the photos, 32 x 5 + 64 = 224 with the placeholders, under about 10 MB as JPEG (as raw `Image`s, about 0.6 MB each, it would be about 130 MB); renders follow the shots, each needing a film fetched from storage and loaded at the gazebo | a second world would copy the House's nodes; hiding the live avatars for one frame would flicker on screen; raw images kept for every shot let one film spammer cost every client over 100 MB; pictures kept for the whole match would grow with every film a spammer fetches, since a cap vanishes old films rather than refusing new ones; a render deferred to the print would lose the moment (PE4 (a2)) | as stated; P8 measures the memory over a normal match and at the caps' worst case |
| PE16 | The rejection reasons | (a) five new reasons, `no_film`, `no_frames_left`, `film_exposed` (PD16 (a)), `nothing_to_print` and `no_photo`, and `unavailable` reused, all returned by `PhotoTask.use_problem` through G1's `StationUsable` and listed in `PhotoTask.use_reasons()` (C11). The list grows with the issues, so the mode check (which tests every listed reason against the wire alphabet) passes after each: P2 lists the four it can return, `unavailable`, `no_film`, `no_frames_left` and `film_exposed`, and adds its three new ones to the alphabet; P3 adds `nothing_to_print` and `no_photo` to the list and the alphabet together. Each new reason joins the wire alphabet and ARCHITECTURE §3.2's rejection table, from which `ChaosOracle` is written (§4.6.5), in the issue that adds it to the list; (b) `unavailable` for everything | (b) a client hint that cannot say why the camera refused. Without `use_reasons()` the static `Condition.rejection_reason()` that `RuleRunner` and `ModeCheck` read names one reason per condition, so the five could be neither emitted nor checked, and a reason missing from the alphabet makes the encoder refuse the `Rejected`. Each reveals only public state or the sender's own: the camera's film and its frames (drawn on the camera), what the sender itself carries, and whether the task is done; P2 and P3 record each in ARCHITECTURE §9.4.1's `StationUsable` row, G1's reason-disclosure record, so a later reviewer judging a new reason sees these four reveal the sender's items, not the station's state | (a); P2 and P3 depend on C11 for `use_reasons()` |
| PE17 | The film in the camera | (a) derived from the item: the camera holds the film its last load laid there while that film's move serial is still the one the load left it (`ItemState.moves`, a host-only counter bumped by C10's one helper on every move that lays or lifts an item, never sent; P2 adds it to that helper), so any move that takes it away (a pick-up, into the hand or onto a two-handed carrier's belt (CE21), `PickUp`'s exchange, a later throw or knock) empties the camera with no code of its own, even when the film is picked up and comes to rest again in the load's own tick (a `PickUp` then a `PutDown` from one peer, or a pick-up then a death drop, all stamped with that tick, §4.5.3): a rest tick is not unique within a tick, a move serial is; a vanish (at the cap) empties it through PE6's drop of the vanished film's entries, which clears the camera's too, so a recycled id restarting its serial never matches; `FilmLoaded(station, item)` tells the clients, which empty the camera on the film's `ItemPickedUp` or `ItemVanished`; (b) a stored flag, cleared by a new `item_taken` fact that `Items` raises; (c) the film locked in the camera (C2's lock) and given back by a second intent | (b) every move, present and later, that lifts an item off the ground must raise the fact, and one that forgets leaves a camera shooting onto a film in someone's pocket. (c) a shot and a take-out would both be `Interact(camera)` (PE1), so a new intent for one of them. Keying on (film, rest tick) instead would say the camera still holds a film picked up and put down elsewhere in the load's tick, while every client emptied it on `ItemPickedUp` (the design review). (a) reads what `Items` keeps in its one move helper, and a film laid at the camera is a ground item the existing `PickUp` takes | (a); P2 tests each move that empties the camera, including both same-tick cases |
| PE18 | What stands in for the bots' coverage, now that no bot plays the photo task (PD14: no scenario on the greybox, and bots do not play House, ARCHITECTURE §9.7) | (a) as the Generator's §7 and cooking's CE22: unit tests (P2, P3); P9's integration tests on House in the host's real world, every call and tick checked by `ScenarioInvariants` (the record invariant included), with the leak plant and the record plant there and the match replayed from its command log (the shots' `line_of_sight` answers included); the real wire in `HostSession` tests over `tests/integration/server/host_session_harness.gd` with a fixture mode and a fixture map (P10: what each client decodes equals its `Match.view_of`, `ShotTaken`'s record included, with a codec plant; the box's flood guard and the film cap); the chaos run keeps only the rows that need no deal (the wrong-direction kinds); the scenario bot's folds of the photo events wait for the issue that lets bots play the photo task; (b) scenarios that play the photo task on a test-only flat map holding its markers, one in `bots`; (c) unit tests and P9 alone | (b) puts bots on the chains, which the engineer leaves for later, with the map, and a second flat map to keep in step with House's markers. (c) leaves the four new wire rows and the server's routing of them unexercised until a human plays House: a `ShotTaken` row that drops or mistypes a field of the record (a facing, a hand item) draws every client a picture the host never saw, and `ScenarioInvariants` alone never runs the codec. (a) keeps each check the scenarios gave: §5's invariants, the leak plant and the record plant over a real deal on House (P9), determinism by replay (P9), the codec with its plant (P10; a broadcast in place of the routed send reaches the same peers there, since every photo event goes to every player and Round refuses joins, so that class waits for the lurker of the scenarios that play the photo task, the routing being the generic `HostSession` path, as cooking's C9 says), the refusals of hostile input (P2's and P3's unit tests, P9), and the flood guard against one peer's burst at the box (P10) | (a) |

### 8. Testing
- **Unit tests** (P2, P3; fixtures only, never `content/`, ARCHITECTURE §9.6): `PhotoFrame` (a point at the centre,
  just inside and just outside each edge, nearer than 0.3 m, beyond `range_m`, behind the lens); the load (a fresh
  film from the hand, then from the belt; `film_exposed`; `no_film`; the film laid at the camera with `FilmLoaded`);
  the camera's film (PE17: emptied by a pick-up, by a package carrier's pick-up onto the belt (CE21), by `PickUp`'s
  exchange that leaves the picker's hand item where the film lay, and by a vanish at the cap, after which a new film
  given that recycled id and moved until its serial equals the stored one is not in the camera; another film that
  exchange leaves at its place not loaded; emptied by a
  `PickUp` then a `PutDown` of the film in the load's own tick, and by a pick-up then a death drop in that tick, the
  next `Interact(camera)` with a fresh film a load, not a shot); the shot: a subject counted, one outside the frame,
  one behind a `FlatWorldQuery` wall, one knocked down, the shooter and another player in front of the lens within
  the camera's cylinder (neither counted nor in the record), one beyond the range, a head cut off by the frame's
  edge; each refusal in its order (§2); `no_frames_left` after `frames_per_film` shots; the record's contents
  (the radius, the cylinder, the knocked-down flag); the box's take (a film into the hand, the hand's knife to
  the belt; a package carrier's empty belt, and its full belt, whose item drops at the feet, the film on the belt and
  the package kept; `too_soon`: one player's takes on 100 ticks in a row give at most 100 / 5 + 1 films at 0.25 s;
  `GiveItem`, `Items.give` and the pick-up's belt move themselves are C1's and C2's to test); a package carrier
  refused `two_handed` at a load, a shot, a print and a hang, and not refused taking a photo off the tray or the
  board; the print (every shot of
  the film once, in shot order, the tray's position, the film vanishing last, `nothing_to_print` for a fresh film);
  the caps (the film kind's at a take, the photo kind's at a print, the loose one that lay longest vanishing,
  its task state entry dropped: a new film given a recycled id loads as fresh and prints nothing old; PE10's tiers:
  at the film cap a fresh film that came to rest later vanishes before an older film with shots, and the camera's
  film, though it lay longest, stays while any other film is loose; `cap_tier` 0 for every photo); the hang
  (counted and locked, uncounted and taken down by `PickUp`, a counted one refused to `PickUp`, the last subtask,
  `unavailable` after done, `no_photo`); the deal, the exact demands and the fit check (a photo spot directly above
  the camera, or within its reach horizontally, refused); PE12's checks (each cap one below its floor refused, at
  its floor accepted); `ModeCheck` testing every reason `PhotoTask.use_reasons()` lists against the wire alphabet
  (one removed from the alphabet is found); the order of events (PE11); `ResetMatch` clearing the state; the wire
  rows' round trips; a replay of a shot agreeing on `line_of_sight`.
- **The role-swap check** (P2, P3): the same seed and commands with two players' forced roles swapped emit identical
  `FilmLoaded`, `ShotTaken`, `PhotoPrinted`, `PhotoHung`, `TaskState` and `TaskProgress` streams, as the zone task's.
  Planted once (the frame skips dissidents), it fails; reverted.
- **The leak test's lists** (P2, P3, each for its own events): the four events join the task events every player
  receives alike (`LeakCheck.TASK_EVENTS`, `ScenarioInvariants.TASK_EVENTS`), with a unit test that both lists name
  every class `PhotoTask.emits()` returns, as the Generator's G2. Both check only the events a run emits, and no bot
  plays the photo task now (PD14): P9 runs `ScenarioInvariants` over House's events instead, and `LeakCheck` checks
  them once bots play a map with the photo task. The scenario bot's folds of `FilmLoaded` and `PhotoHung` wait for the
  scenarios that play it (PE18).
- **The record invariant** (P2; P9 runs it). `ShotTaken` is the first event to carry other players' avatar rows, which
  until now only §5's snapshot rules guarded, and the leak test compares events against `view_of`, which reads the
  same record, so a record-building bug would pass it. P2 adds an invariant to `ScenarioInvariants` and `LeakCheck`
  written independently of the record builder: every row of a decoded `ShotTaken` names a peer that is ALIVE or
  knocked down at that tick (never dead, left or not a player), within one movement claim's longest step of its
  accepted position at the end of the tick before or of the shot's tick (the record is taken in the shot's command,
  and a claim later in the same tick moves the position `LeakCheck` records), and within `range_m` + 2 m of the lens
  plus that step. The cylinder is not checked: its edge flips with the same step, and the unit tests cover it. P2's
  unit cases feed it hand-built events (a dead player's row, a row beyond the bound: each caught); the record plant
  (the record builder dropping its distance test, so a player standing elsewhere on House at a shot gets a row; P9
  keeps a third player away from the gazebo for it) is P9's, over House's shots, planted once, reverted.
- **The chaos bots** (ARCHITECTURE §4.6.5.3; P2, P3: the rows that need no deal): the four new H→C kinds in the
  wrong-direction list. The chaos run plays the greybox, which holds no photo task (PD14), so a hostile `Interact`
  there never meets a camera, a box, a printer or a board. A dealt photo task's refusals of hostile input (from out
  of reach, without a film, in a burst: `out_of_reach`, `no_film`, `no_frames_left`, `film_exposed`,
  `nothing_to_print`, `no_photo`, `too_soon`, `two_handed`, `unavailable`) are P2's and P3's unit tests and P9's
  checks on House, and a burst of takes at the box is P10's (below).
- **No bot scenario plays the photo task now** (PD14: the greybox gets none of the House's chains; bots play them
  later, with the map, in issues of their own when the engineer asks). What stands in for the scenarios (PE18): a
  load, a shot with a subject and without, the take-out, a take from the box, a take beside a package, a print, a
  counted and an uncounted hang are unit tests (P2, P3), and the whole chain from players' commands is P9's House
  test; the leak plant and the record plant run in P9; the real wire is P10's; the role-swap is P2's and P3's unit
  check; the chaos rows above. `StepInteract` (the Generator's G1) is there for those scenarios when they come.
- **Integration tests on House** (P9; bots do not play House, ARCHITECTURE §9.7): `Match` over `HostWorldQuery` with
  House's level and at least two players present, checked by `ScenarioInvariants` per call and per tick as the
  runners check theirs (a `BotScenario` with no `never`), the record invariant included: a player on the photo spot is
  counted in a shot from the camera; one behind the gazebo's wall or outside the frame is not; the photo spot lies
  outside the camera's cylinder; the lens point is clear of the camera scene's collision and the line from the lens to
  the aim is clear; a scripted chain (the dealt film loaded, a shot, the film taken out, a film from the box in
  storage, the print in the study, the hang in the darkroom) completes a subtask; a player at each use spot passes
  `AtStation` and `StationInSight`; the five stations, the tray and the first film's marker read without errors. The
  leak plant (`ShotTaken` declared to the actor only fails P9's `ScenarioInvariants` check: a task event that reaches
  fewer than every present player) and the record plant, each planted once, reverted and recorded in the PR
  (ARCHITECTURE §4.6.4.1). And the replay: `Match.replay` of that House match from its command log emits the same
  events to the same recipients, with nothing in its `diagnostics` (no diverged `HostWorldQuery` answer: the shots'
  `line_of_sight`, the stations' sight checks).
- **The wire, without bots** (P10): a test over `tests/integration/server/host_session_harness.gd` (a `HostSession`
  on the loopback hub with `ClientSession`s, the codec in between) with a fixture mode that deals a fixture photo task
  on a fixture map, its markers given to the harness as layouts (the `layouts` parameter cooking's C9 adds; P10 adds
  it if C9 has not landed): one client stands on the spot while another loads the dealt film and shoots, takes it out,
  prints it and hangs a photo; what each client decoded (`StationPlaced`, `FilmLoaded`, `ShotTaken` with its record,
  `ItemPickedUp`, `ItemSpawned`, `PhotoPrinted`, `ItemVanished`, `PhotoHung`, `TaskState`, `TaskProgress` and a
  `Rejected`) equals its `Match.view_of`, as `host_session_end_to_end_test.gd` checks today. So a wire row that drops
  or mistypes a field of its core event, a record row's facing or hand item above all, fails before anyone plays
  House; planted once (`ShotTaken`'s wire row without the rows' facing), it fails, reverted, recorded in the PR. A
  broadcast in place of the routed send is not seen there: every photo event goes to every player, and in Round
  `RefuseJoins` keeps every other connection out, so that class waits for the bots' lurker in the scenarios that play
  the photo task, the routing being the generic `HostSession` path (cooking's C9). The box's flood guard and the film
  cap are proved there too, in the style of `tests/integration/server/host_session_chaos_test.gd`: one peer's burst of
  `Interact(film_box)` gets at most one applied take per 5 ticks and `too_soon` for the rest (PE14), and never more
  than `max_items` films exist (PE10). The fixture map's path is the same in the fixture mode's `maps`, the layouts'
  keys and the fixture photo task's `TaskType.maps` (or that list empty, every map, G8).
- **The maps** (P5): the content test's fit, House with the photo task and the greybox without it (G8: the greybox is
  asked for none of its markers), so the MVP's scenarios, the chaos run and the perf run play the greybox as before,
  with no ban.
- **The client** (P7, P8): the viewfinder's camera equals `PhotoFrame` (the frame's corner points project onto the
  mask's corners); each camera's film and frames left following `FilmLoaded`, `ShotTaken` and the film's pick-up or
  vanish (P7); the fold of `ShotTaken`'s record, `PhotoPrinted` and `PhotoHung` (P8); a headless client renders
  nothing; a rendered picture from a fixture record (`shot` previews); the hint over the camera, the box, the printer
  and the board only when usable, none over the photo spot; the M4 render checklist, no marker through a wall (DD4),
  the PRs routed to `netcode-security-reviewer` too.
- **Green** (#605): `verify` (lint and check) locally, then CI's full suite on the PR, for each issue of §9.

### 9. The split
Sizes as in M6 and M7: S up to about 400 changed lines, M up to about 900. Effort: high for `core/`, `net/` and
`tests/harness/`. Nothing is built now: these are proposals for the M7 backlog, which the manager opens after the
engineer's approval. Base (#676, comment 6095620770): the engine issues (P2, P3, P6 to P10) stack on `release/m7`,
with PRs into it, merged by the M7 manager and shipped with M7, protocol numbers kept in step with it; the level and
content issues (P4, P5) go into `main`, P5 once what it uses has reached main with M7's merge. Every engine issue lands
after the Generator's G1 (the station-use intent and its parts) and the cooking parts it names; G8's `TaskType.maps`
is shared. No issue adds a station, a marker or a scenario to the flat greybox, or changes the chaos and perf runs'
setups (PD14). **P1 is withdrawn**: the shared item parts it would have built are cooking's C1, C2, C10 and C11, by
that ADR's names and the engineer's answers there; if the photo task is scheduled first, those four go first.

| Issue | Labels | Goal | Acceptance | Files | Depends on | Size |
|---|---|---|---|---|---|---|
| P2 | needs-engine, area:core, area:net | The photo task type, the frame, the load and the shot | §2.1 to §2.4 with the engineer's answers (PD16 to PD18 included); §3.1 to §3.3's host half; PE2, PE3, PE5, PE6, PE11 to PE14 and PE17 for the load and the shot, with `ItemState.moves` bumped in C10's one move helper; `PhotoTask` with its deal, exact demands and checks (PE12); `PhotoFrame`; `FilmLoaded` and `ShotTaken` (§3.3's payload, the record capped at 15 rows with a `WireBudget` case) with their wire rows and a protocol bump; PE16: `PhotoTask.use_reasons()` listing the four reasons P2 returns (`unavailable`, `no_film`, `no_frames_left`, `film_exposed`), the three new ones in the wire alphabet and §3.2's rejection table; §8's unit tests for the frame, the load, the camera's film and the shot, the role-swap check, the chaos row (the wrong-direction kinds), both events in the leak test's lists with the unit test that they name every class `PhotoTask.emits()` returns, and §8's independent record invariant with its unit cases (its plant is P9's; no scenario bot fold, PE18); ARCHITECTURE: the photo task's entry beside Delivery's (§9.5), §4.2, §4.3.4, §9.4.1's `StationUsable` row (what each of P2's reasons reveals, by G1's record: `film_exposed` and `no_film` the sender's own carried items, `no_frames_left` the camera's drawn frames, `unavailable` the public task state), §5's task events, and §5's snapshot paragraph gaining the record's exception to "nobody gets their own avatar" with its audience reasoning (§3.3) | `core/tasks/photo_task.gd`, `core/tasks/photo_frame.gd`, `core/events/film_loaded_event.gd`, `core/events/shot_taken_event.gd`, `net/messages/`, `core/match/phases/join_rules.gd` (the version), `tests/harness/scenario_invariants.gd`, `tests/harness/bots/leak_check.gd`, `tests/harness/chaos/`, `tests/unit/tasks/`, `tests/scenarios/` (the invariant's cases, beside `scenario_runner_test.gd` and `bots_runner_test.gd`, which test the harness today), `tests/fixtures/tasks/`, `docs/ARCHITECTURE.md` | G1; G2 (exact demands, GE10); cooking's C1 (`StationKind.display`), C2 (the lay at a station, the pick-up's belt move), C10 (its one move helper, to which P2 adds the move serial; PE17 keys the camera on that serial, never on the rest tick), C11 (`use_reasons()`); G0 if it lands first | M |
| P3 | needs-engine, area:core, area:net | The box, the print and the hang | §2.5 to §2.8 with the engineer's PD3, PD6, PD12 and PD16 (a); PE7 to PE11; the box's `use_station` through `GiveItem.give_new`; `PhotoPrinted` and `PhotoHung` with their wire rows and a protocol bump; `nothing_to_print` and `no_photo` added to `PhotoTask.use_reasons()`, the wire alphabet and §3.2's rejection table together (PE16); the film used up at the print; the photo kind's cap at the print; PE10's tiered cap: `TaskType.cap_tier` (0 by default) added to C1's cap, with `PhotoTask`'s tiers for the film; the subtask count; §8's unit tests, the role-swap check over the whole chain, the chaos row (the wrong-direction kinds), both events in the leak test's lists (no scenario bot fold, PE18); ARCHITECTURE §9.5's entry completed, §4.2, §4.3.4, §5, and §9.4.1's `StationUsable` row for `nothing_to_print` and `no_photo` (each reveals only the sender's own carried items) | `core/tasks/photo_task.gd`, `core/events/photo_printed_event.gd`, `core/events/photo_hung_event.gd`, `net/messages/`, `core/match/phases/join_rules.gd`, `tests/harness/`, `tests/unit/tasks/`, `docs/ARCHITECTURE.md` | P2; cooking's C1 (`GiveItem.give_new`, the cap, which P3 extends with `cap_tier`), C2 (`Items.give`, the lock and the lay at a station), C10 (`Items.vanish`) | M |
| P4 | area:level | The station scenes, in place of the House markers | by the Generator's GE11: `levels/stations/camera.tscn` (a tripod: greybox look, collision on layer 1 kept below the line from the lens to the aim, its use-spot `Marker3D` in `spawn_camera` behind it, where the shooter stands; a `FilmSlot` node where the loaded film is drawn and a `FramesLeft` `Label3D`, depth-tested (`no_depth_test` off), for the frames left), `photo_spot.tscn` (a floor mark, `spawn_photo_spot`, placed farther from the camera's use spot than the camera's reach, PD18), `film_box.tscn` (`spawn_film_box`), `printer.tscn` (`spawn_printer`, and a `spawn_photo` tray marker on its top), `photo_board.tscn` (`spawn_photo_board`, and named slots for the hung photos); the tags provisional, "not a decision"; `photo_spot.tscn` instanced at the photo spot in place of `PoseScreen`, `printer.tscn` and `photo_board.tscn` in place of `Printer` and `PhotoBoard`, `camera.tscn` facing the spot in the photo zone and `film_box.tscn` in storage at points the PR proposes, a `spawn_film` marker beside the camera (PD4 (i)); `levels/CLAUDE.md`'s spawn points gain the tags; a `shot` of each room; no two markers of different tags at one (x, z), so House still reads through the runners' flat fake (ARCHITECTURE §9.7); no scene or marker on the greybox (PD14); provisional, named in the PR for the engineer's approval | `levels/stations/`, `levels/house/rooms/photo_zone.tscn`, `storage.tscn`, `study.tscn`, `darkroom.tscn`, `levels/CLAUDE.md`, `docs/design/house-map.md` (§6's three new points) | G4 (the station scene conventions it sets); before P5 | S |
| P5 | area:content | The photo task in the base mode, on House alone | `content/tasks/photo.tres` with §6.1's words, which the engineer took as drafted (PD8), and PD9's placeholders, `frames_per_film` 5, `maps` House alone (PD14, G8), the five station kinds with their rules (the camera, printer and board: `HandNotTwoHanded`, `AtStation`, `StationInSight`, `StationUsable`, then `UseStation`; the box: `AtStation`, `StationInSight`, `Cooldown` (key `photo_take`, 0.25 s), then `UseStation`, with no busy-hands condition, since a take is a take (CD3 (b)); the photo spot `display`, no rule); `content/items/film.tres` and `content/items/photo.tres` (one-handed, `max_items` 32 and 64, no `vanish_seconds`, their spawn tags `film` and `photo`), both listed in the base mode's `item_kinds`; the base mode: the type, its subtasks setting, `tasks` per GD7 (i) (every type that plays on the map, every match: its default and maximum the number of the mode's types), Round accepting `Interact` from the living (if G5 has not added it, with the chaos bots' `Interact` row following it); nothing on the greybox (PD14: it keeps what it deals today, so the MVP's scenarios, the chaos run and the perf run play it as before, with no ban); no bot scenario in `content/scenarios/`, an exception to the `new-mechanic` skill's step 7 (PD14, PE18: bots do not play House); the content test's fit, House with the photo task and the greybox without it; every test that loads the base mode still passes, each changed expectation named in the PR; provisional files named for the engineer's approval | `content/tasks/`, `content/items/`, `content/modes/base_mode.tres`, `tests/harness/chaos/` (the oracle's row, if this change adds `Interact` to Round), `tests/unit/content/`, `tests/integration/`, `docs/ARCHITECTURE.md` (§9.5, §9.6) | P2, P3, P4; G3 (the box in storage and the board in the darkroom are station markers below y = 0, which the runners read on House too), G5 (Round accepting `Interact`), G8 (`TaskType.maps`) | M |
| P6 | area:client | The flash and the sounds | `ShotTaken`'s flash: an `OmniLight3D` pulse at the lens, on at least until P8's queued render of that shot has drawn, with `shadow_enabled` and a short `omni_range`, so it never lights a room through a wall (a light without shadows passes through walls, which would show a flash where no eye reaches); the shutter, the printer's and the hang's sounds through `SoundChooser` and `WorldSounds`, within 12 m (`AudioStreamPlayer3D.max_distance`) and muffled behind the level (M5-7); placeholder blips (PD15); the M4 render checklist (items 5 and 10) | `client/world/world_sounds.gd`, `client/world/sound_chooser.gd`, `client/world/`, `tests/unit/client/` | P2, P3 | S |
| P7 | area:client | The viewfinder, the camera's state on the client and its inputs | `ClientModel` keeps each camera's film and frames left from `FilmLoaded` and `ShotTaken` (its film and shot count only), emptied on the film's `ItemPickedUp` or `ItemVanished`, with unit tests (P8 draws from it); E over a camera holding a film enters the view only while the client's own `AtStation` (the camera's cylinder) and `StationInSight` hold for its position, as G6's usable hint does, so no view from afar or through a window shows more than standing there (the M4 render checklist, items 3 and 5); it leaves when either stops holding, when the film leaves the camera, and on E, Esc, a hit, a knockdown or a death (tests: no view from outside the cylinder, none through a wall); the active camera at `PhotoFrame`'s pose (`Camera3D.fov`, `keep_aspect` `KEEP_HEIGHT`), the screen outside the aspect masked, movement held; the shot on the primary button sends `Interact(camera)`; E over an empty camera with a fresh film carried sends `Interact(camera)` (the load); a hold of E over a camera holding a film sends `PickUp` of it (PD17 (a)); the view shows the frames left; the hints over the camera, the box, the printer and the board only when usable (G6's `TargetChoice`), none over the photo spot (C1's display kind) or the loaded film; a test that the frame's corners project onto the mask's corners; ARCHITECTURE §4.7 | `client/net/client_model.gd`, `client/player/`, `client/world/`, `client/ui/hud.gd`, `tests/unit/client/`, `tests/integration/client/`, `docs/ARCHITECTURE.md` | P2, P4; G6; cooking's C10 (`ItemVanished`) | S |
| P8 | area:client | The pictures, the camera's counter and the photo's look | PE15: `ClientModel` folds `ShotTaken`'s record, `PhotoPrinted` and `PhotoHung` (each camera's film and frames left are P7's); each shot's picture rendered as it is folded (`SubViewport` `UPDATE_ONCE`, puppets on the photo layer, the flash on, read back after `RenderingServer.frame_post_draw`) and dropped when no film or photo of that shot remains; §3.3's isolation: every live camera's `cull_mask` drops the photo layer (a test for each), the puppets cast no shadow, the flash is P6's light, the render never sets a live view's `visible`; the loaded film drawn in the camera's `FilmSlot` and the frames left on its `FramesLeft` label from P7's camera state, depth-tested; the film and photo items drawn (`ItemView` gains `film` and `photo`), a photo with its picture, photos on the tray spread apart, hung photos on the board's slots in hang order (an uncounted one leaving its slot when taken down), all depth-tested, no marker through a wall (DD4); a way for the holder to look at its own photo up close; headless clients render nothing; memory measured over a normal match and at PE15's worst case (224 pictures with the placeholders); `shot` previews; the M4 render checklist (items 1, 3 and 5), the PR routed to `netcode-security-reviewer` too; ARCHITECTURE §4.7 | `client/net/client_model.gd`, `client/world/`, `client/player/first_person_hand.gd` (onto the live-avatar layer), `client/dev/`, `tests/unit/client/`, `docs/ARCHITECTURE.md` | P3, P4, P6 (its flash is the render's light), P7 | M |
| P9 | needs-engine, area:core | Integration tests: the photo task on House, with the §5 invariants and the plants | §8's House tests in the host's real world, every call and tick checked by `ScenarioInvariants` (the record invariant included); the match's replay from its command log (the same events to the same recipients, no `diagnostics`); the leak plant and the record plant (§8), each planted once and reverted, recorded in the PR | `tests/integration/levels/`, `docs/ARCHITECTURE.md` (§9.7's House line, §4.6.4.1's plants) | P3, P4, P5 (on whichever base holds all three first) | S |
| P10 | needs-engine, area:net | The photo task over the real wire, without bots (PE18; it replaces the greybox scenarios this row first held) | §8's wire test over `host_session_harness.gd` with a fixture mode dealing a fixture photo task on a fixture map: what each client decoded equals its `Match.view_of`, `ShotTaken`'s record included, with §8's codec plant planted once, reverted and recorded in the PR; the box's flood guard and the film cap against one peer's burst of `Interact(film_box)` (outside `ChaosRun`, whose baseline comparison cannot hold applied takes); the harness's `layouts` parameter beside `game_mode` (cooking's C9; added here if C9 has not landed), and the fixture map's path the same in the fixture mode's `maps`, the layouts' keys and the fixture photo task's `TaskType.maps` (§8) | `tests/integration/server/`, `tests/fixtures/`, `docs/ARCHITECTURE.md` (§4.6.5.3) | P3; G8 (`TaskType.maps`); cooking's C9 if it lands first | S |

### 10. Needs the engineer
His answers of 2026-10-10 settle every PD item and §6.1's drafts (§6): PD1 to PD15 in
[PR #704, comment 6095444907](https://github.com/xperiaroco2/prime-game/pull/704#issuecomment-6095444907), PD16 to
PD18 and the drafts in [comment 6096344994](https://github.com/xperiaroco2/prime-game/pull/704#issuecomment-6096344994).
Left for him: his approval of this design in PR #704, the content-area text with it (GDD §8's photo section and
house-map §6's photo rows). The manager then opens P2 to P10 as proposals for the M7 backlog.

The placeholder numbers (PD9's, and the manager's caps of 32 films and 64 photos of PE10) are tuned in the playtest;
none blocks an issue.

## Alternatives
- **A memory card carried by the shooter** (this ADR's first design, PD11 (a)): the engineer chose a film loaded into
  the camera.
- **A reusable film, or one the printer hands back empty** (PD16 (b), (c)): the engineer chose a one-way film, used
  up at the printer; a reusable one would need each shot marked printed, and an empty one would be left lying.
- **A key in the viewfinder, or the film's slot as a target** (PD17 (b), (c)): the engineer chose a hold of E over
  the camera, the gesture cooking's boxes teach, sent as the existing `PickUp`.
- **Anyone in the frame counts** (PD18 (b)): one player alone would photograph itself from the camera's reach; the
  engineer: "you cannot photograph yourself".
- **An image uploaded by the shooter** (PE4 (b)): 10 to 50 KB per shot relayed to every player, and a picture a
  modified client can fake.
- **A picture rendered on the host** (PE4 (c)): a headless host has no renderer, and `core/` and `server/` hold none.
- **The client deciding who is in the frame** (PE2 (b), (c)): a client's field or image, against invariant 1.
- **An oriented marker or a facing in `StationPlaced`** (PE3 (b), (c)): a layout, reader or wire change for what two
  positions already give.
- **A host-known viewfinder** (PE1 (b)): enter and leave intents and a busy state the rules never read.
- **A take-out fact, or the film locked in the camera** (PE17 (b), (c)): a fact every lifting move must remember, or a
  second intent at the camera.
- **`has_person` on the wire before the hang** (PE5 (b)): a flag a client could show where no picture says it.
- **The box as a carried item, a composed `GiveItem` rule, or a photo-only item source** (PE7 (b) to (d)): a supply a
  dissident can carry off, an extension of C1 for one task, or code for what cooking's source already does.
- **A bound on all items, refusing a new one** (PE10 (b)): a second bound beside C1's cap, which one spammer could
  use to block the box.
- **Hanging through `item_rested`** (PE9 (b)): a fact and an `ItemPlaced` that say the photo lies on the floor.
- **Rewinding the subjects** (PE13 (b)): lag compensation the MVP has nowhere else.
- **A second world for the render** (PE15): a copy of the level's nodes for one frame per shot.
- **The photo task on the greybox too, with scenarios that play it** (PD14 as first read): the engineer keeps the
  greybox free of the chains; they come with M7 on the House, and bots play them later, with the map.
- **Scenarios on a test-only flat map, or unit and House tests alone** (PE18 (b), (c)): bots on the chains before
  the engineer asks, and a second map to keep in step with House; or four wire rows nobody exercises before a
  playtest.

## Consequences
- GDD §8's photo section records the engineer's answers, every question settled; ARCHITECTURE §9.8's
  row and §10's open row point here; house-map §6 gains the camera, the box of films and the first film's point (to be
  placed by P4).
- When P2 and P3 land, ARCHITECTURE gains the photo task's entry in §9.5 and its four events in §4.2, §4.3.4 and §5,
  with their `Built in` lines; `GiveItem`, the caps, `Items.give`, the moves at a station, the vanish and
  `use_reasons()` arrive with cooking's C1, C2, C10 and C11.
- The task screen's rows change for every task in #738 (the shared total gone, a done task struck through); the photo
  task's row is an ordinary count of done subtasks, so it needs nothing of its own there.
- The protocol version goes up in P2 and in P3; kind numbers and versions are taken when each lands, in step with
  `release/m7`, never from here.
- The box reuses cooking's source as its herb beds do, and the camera and the board its moves at a station, by their
  names (CE2, CE3, CE5, CE6); the printer does not use `GiveItem`, since each photo binds its own shot and one print
  makes up to five photos (PE8).
- The picture is a render from public data, so later rules on a photo's content (poses, gestures, #687's "later")
  need only the host's check to read more of the subject (its facing, a gesture state, #727's crouch) and the record
  to carry it.
- Only House holds the photo task's station scenes (P4); the greybox holds none, and `TaskType.maps` (the Generator's
  GE15, G8) keeps the photo task off it, so the MVP's scenarios, the chaos run and the perf run play the greybox as
  before. A later map that lists the photo task needs the five station scenes, a tray and the first film's marker.
- No bot plays the photo task until the engineer asks, with the map (PD14): what stands in for the scenarios is §8's
  (PE18). The scenarios that later play it bring the scenario bot's folds of `FilmLoaded` and `PhotoHung`, a lurker
  run and the chaos rows against dealt stations.
