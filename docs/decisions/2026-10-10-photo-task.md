# The photo task (#687): shoot, print, hang: its engine parts, who is in the frame, and the split

- **Status:** Proposed on 2026-10-10. Nothing here is built. The rules are the engineer's: #687's "Decided" list
  (chat with the game-design manager session, 2026-10-10). The PD items are game rules and taste that list leaves
  open: they are his (the [trust ADR](2026-10-04-trust-based-autonomy-gated-merge-into-main.md)'s tier (c)), each with
  options and a recommendation, and the design proceeds with the recommendation where it can be reverted. The PE items
  are technical, the game-design manager session's to decide and report (tier (a)): decided here, each revertible in
  its issue.
- **Date:** 2026-10-10
- **Deciders:** the engineer (the rules, PD1 to PD15); the game-design manager session of #676 (PE1 to PE16).
  Designed by the agent of #687, on the engineer's word (#687; the track's kickoff on #593, comment 6088751685).
- **Builds on:** [the Generator ADR](2026-10-10-generator-task.md) (#679, proposed: `Interact(station)`, a station
  kind owning its rules, `AtStation`, `StationInSight`, `StationUsable`, `UseStation`, `TaskType.use_problem` and
  `use_station`, busy hands, the station scenes of its GE11, the runners of its GE12, its issues G0 to G8),
  [content API v0](2026-09-29-content-api-v0.md) (task types are classes with settings; `Interact` is v1),
  [MVP rules](2026-09-29-mvp-rules.md) (Tasks: the engineer's decision of 2026-09-30, #79),
  [vision revision 1](2026-10-01-vision-revision-1.md) (V4's "living", no ghosts, two hands),
  [the M4 client design](2026-10-01-m4-first-person-client.md) (its render checklist, §3; E33's hearing range),
  [the zone task ADR](2026-10-09-m7-zone-task.md) (#36: the role-swap check, the scenario bans of M7-Z2, the station
  target), [level piece conventions](2026-10-09-level-piece-conventions.md) (station scenes in `levels/stations/`),
  the cooking design (#682, proposed in parallel: `docs/decisions/2026-10-10-cooking-task.md` on its branch; its
  item source of CE2, CE3, CD5 and CD6, its items locked on a station of CE5, its issues C1 to C8),
  [MVP content built by the engineer](2026-09-29-mvp-content-built-by-the-engineer.md) (content and levels are
  provisional, approved in their PRs), [the House map](../design/house-map.md) (§2 decision 7, the stations of §6),
  [tests on CI](2026-10-09-tests-on-ci-local-lint-and-check.md) (#605: what "green" means in §8)
- **Numbering:** PD and PE are this ADR's own; the issues are P1 to P10 (§9), which the manager opens from the PR's
  handoff. G0 to G8 are the Generator ADR's issues.

## Context
The engineer's rules (#687, "Decided"), in short: the photo is a task type whose subtasks are hung photos with a
person in them; the host sets how many. A camera stands on a tripod in the photo zone (the gazebo in the north-west of
the yard), facing the photo spot. It takes two: one player stands on the spot, another uses the camera, which enters a
viewfinder view; a press takes the shot, with a flash. The camera records onto a memory card of 5 shots; once they are
used, a new card is taken in storage. The card is carried to the computer and printer in the study (second floor),
where the photos are printed. A printed photo is an item held in the hand that shows exactly what the camera saw at
the moment of the shot. It is carried to the darkroom (basement) and hung on its board, and it counts only if a
person is really in it. "For now the simplest possible thing"; poses or gestures the photo must show come later.

#687's six "Open" items are the engineer's; with the questions the mapping raises they are PD1 to PD15 (§6).

The technical core: **the host decides whether a person is in the shot**, at the moment of the shot, from its own
world (architecture invariant 1: a client's image or field is never trusted), and the photo's picture is a client's
render of that moment, for looks only.

What already holds (ARCHITECTURE §9, §5), and what the Generator's design adds (proposed, #679, PR #695):
- **Tasks are shared** (#79): nobody owns one, any living player does any subtask, each type has its own subtasks
  setting. **"Living" means ALIVE** (V4): the downed are not living, and the dead have no avatar.
- **Hidden by sight is a client rule.** Every living or downed avatar and every item reaches every player; an honest
  client shows an item only where it lies, depth-tested, and plays a world sound only within 12 m (the M4 render
  checklist, items 5 and 10). §5's invariant: every player receives the same task events.
- **The task slots:** a `TaskType` subclass with its task state as an inner class; `StationKind` (spawn tag, radius,
  height, palette); `ItemKind` (spawn tag, `hands`); `StationPlaced`, `ItemSpawned`, `TaskState` and `TaskProgress`;
  `Tasks.subtask_done`; `Items` as the one place that moves an item (§9.3).
- **From the Generator** (G1 unless named): `Interact(station)`, sent on E over a placed station; a station kind's
  `actions` tried first for it; `AtStation` (the feet in the station's cylinder, `out_of_reach`), `StationInSight`
  (`blocked`), `StationUsable` (`TaskType.use_problem`, else its reason), `UseStation` (`TaskType.use_station`, which
  alone writes the task state); `HandNotTwoHanded` in each station rule (busy hands, #679); a station on every marker
  of its tag, with exact demands (its GE10); station scenes with a use-spot marker and driven nodes, found by the
  client by the nearest point in 3D (its GE11, G4); the runners snapping station markers only on the scenario levels,
  so a basement station reads (its GE12, G3); `subtasks_setting` in `TaskType` (G0, optional); the client's station
  hint, E taking the target nearest along the crosshair (G6); scenarios that interact with stations (`StepInteract`,
  G8).
- **The cooking chain** (#682, designed in parallel) designs an item source: `GiveItem(kind, max_items)`, a new item
  spawned at the rule's target and taken into the hand (`ItemSpawned`, then `ItemPickedUp`), held under
  `HandsHaveRoom` (`hands_full`), with a cap per given kind (32, a placeholder) at which the oldest loose item of that
  kind comes to the taker instead (its CE2, CE3, CD5, CD6; issue C1); a herb bed is a station kind whose rule pays the
  existing `Cooldown` cost (`core/combat/cooldown.gd`, `too_soon`; its CE17, the seconds its CD17) and ends in
  `GiveItem`. It also locks an item at a station, as a delivered package is locked (its CE5; issue C2). The card box
  uses the first and the board the second, by the same names (PE7, PE9). And it extends G1's API with
  `TaskType.use_reasons()` (its CE11, built in C1): `StationUsable`'s one static `rejection_reason()` cannot name
  several, so a type lists every reason its `use_problem` may return (the base: [`unavailable`]) and the mode check
  tests each against the wire alphabet; `PhotoTask.use_reasons()` lists its five (PE16).

## Decision

### 1. The mapping (`new-mechanic` step 3)

#### 1.1 Each rule to its engine part

| # | What #687 needs | Engine part | Exists? |
|---|---|---|---|
| 1 | The photo is a task type, like the others | `PhotoTask extends TaskType` (`core/tasks/photo_task.gd`), no tick | missing: P2 |
| 2 | One hung photo with a person is one subtask; the host sets how many | the type's own subtasks setting: `subtasks_setting`, the property Delivery (`core/tasks/delivery.gd`), the zone task and the Generator share and G0 lifts into `TaskType`, names a whole-number `SettingSpec` of the mode (id `photos`, provisional), one lobby control (`client/ui/lobby_panel.gd`), as Delivery's `packages` and the Generator's | exists as a pattern; the setting P5; #256's shared part G0 |
| 3 | A camera on a tripod in the photo zone, facing the photo spot | two station kinds of the type: `camera` (the tripod; its use spot is where the shooter stands) and `photo_spot` (the floor mark the camera frames), each with its spawn tag, radius and height; both reach every client in `StationPlaced` | the class exists (`core/content/station_kind.gd`); the data P5; the scenes P4 |
| 4 | It takes two: one on the spot, another at the camera | the shooter is never counted in its own shot: the actor is left out of the frame check and of the shot's record (§3.2) | missing: P2 |
| 5 | Using the camera enters a viewfinder view | a client camera mode: E over the camera puts the view at the frame's pose with the photo's aspect; the host never hears of it (PE1) | missing: P7 |
| 6 | A press takes the shot | `Interact(camera)`, sent from the viewfinder; the camera kind's rule: `HandNotTwoHanded`, `AtStation`, `StationInSight`, `StationUsable`, then `UseStation`, which calls `PhotoTask.use_station` | the parts: G1; the shot: P2 |
| 7 | With a flash | the public `ShotTaken` (§3.3); every client flashes a light at the lens, seen where the eye reaches, and plays the shutter within 12 m | the event P2; the flash and the sound P6 |
| 8 | The camera records onto a memory card | a `memory_card` item kind (`hands` per PD5); the shooter carries the card (PD11); each shot takes one of its shots; the task state keeps each card's shots by item id (PE6) | missing: P2; the kind P5 |
| 9 | A card holds 5 shots | `shots_per_card` in the type's data (5, the engineer's starting value) | missing: P2 (the property), P5 (the value) |
| 10 | Once they are used, a new card is taken in storage | a `card_box` station kind in storage; its `Interact` rule, as a herb bed's: `HandNotTwoHanded`, `AtStation`, `StationInSight`, `HandsHaveRoom`, the cost `Cooldown` (key `photo_take`, a provisional id; #682's CE17), then `GiveItem` (kind `memory_card`), the cooking design's item source (PE7) | `Cooldown` exists (`core/combat/cooldown.gd`); `GiveItem` and `HandsHaveRoom` missing: #682's C1 (or P1, if the photo task comes first); the data P5 |
| 11 | The host decides whether a person is in the frame, from its own world at that moment | `PhotoFrame` (`core/tasks/photo_frame.gd`, pure math: the frustum from two markers and the type's data, PE3) and `WorldQuery.line_of_sight` from the lens to each candidate's head, its answers recorded in the command log (PE2) | `line_of_sight` exists (`core/world/`); the rest P2 |
| 12 | A hung photo counts only if a person is really in it | the shot's `has_person`, kept in the task state, decided at the shot and never sent (PE5) | missing: P2 |
| 13 | A printed photo shows exactly what the camera saw at the moment of the shot | the shot's record in `ShotTaken`: every avatar near the lens at that tick; each client renders the picture as it folds the event (PE4) | the record P2; the render P8 |
| 14 | The card is carried to the computer and printer in the study, where the photos are printed | a `printer` station kind; `Interact(printer)`: `PhotoTask.use_station` prints the card's unprinted shots as `photo` items on the printer's tray marker (PD3, PE8) | missing: P3 |
| 15 | A printed photo is an item held in the hand | a `photo` item kind (`hands` per PD5); `PickUp`, `PutDown` and `Swap` work on it as on any item (the mode's rules) | the rules exist; the kind P5 |
| 16 | It is carried to the darkroom and hung on its board | a `photo_board` station kind; `Interact(board)` with a photo in the hand: the photo is locked on the board, by the cooking design's move that locks an item at a station (PE9), then `PhotoHung` | missing: P3; the move #682's C2 (or P1) |
| 17 | It counts | `Tasks.subtask_done` when the photo's shot has a person and a subtask is left | exists (`core/tasks/tasks.gd`); the call P3 |
| 18 | A dissident plays by the same rules (#679) | no condition reads a role, and a person in the frame counts whatever its role (PD1): a role-gated count would tell everyone a role through the board (§9.2, "a public event can reveal its rule's owner") | by design; the role-swap check P2, P3 |
| 19 | Busy hands (#679) | `HandNotTwoHanded` in every station rule of the type; the box's also `HandsHaveRoom` (no free hand and no free belt for the hand's item) | `HandNotTwoHanded` exists (`core/items/hand_not_two_handed.gd`); `HandsHaveRoom` #682's C1 (or P1) |
| 20 | Only living players do subtasks (#79, V4) | the phase's allowlist: `Interact` from the living (G5's Round row), so the downed get `not_accepted` and the dead send nothing | exists: `AcceptSpec` |
| 21 | The host's own player follows the same rules | its client sends `Interact` like any other | exists |
| 22 | The stations in the photo zone, storage, the study and the darkroom | station scenes in `levels/stations/` (the Generator's GE11): `camera.tscn`, `photo_spot.tscn`, `card_box.tscn`, `printer.tscn` (with its tray marker), `photo_board.tscn` (with its slots), in place of the markers `PoseScreen`, `Printer` and `PhotoBoard`, plus a camera and a card box at points the level task proposes | the markers exist (plain `Marker3D`s under `Stations` in `levels/house/rooms/photo_zone.tscn`, `study.tscn`, `darkroom.tscn`); the scenes P4 |
| 23 | Tested without bots on House (ARCHITECTURE §9.7) | unit tests from fixtures (P1 to P3); integration tests on House in the host's real world (P9); scenarios on the greybox, whose station scenes stand above y = 0 (P10) | missing |

#### 1.2 Beside Delivery and the Generator

| | Delivery | Generator (#679) | Photo | Why |
|---|---|---|---|---|
| Subtasks | one per package, done when it rests in its circle | the active switches, done together at full charge | one per hung photo with a person, done at the hang | #687: "one hung photo with a person in it is one subtask" |
| Stations | one circle per package, on random markers, coloured | one per marker, exact counts | one per marker of five kinds, exact counts (one each on House), no colours | the stations are the level's devices (the Generator's GE10, GE11) |
| Items | packages, dealt | none | cards (from the box; PD4: one dealt at the photo zone) and photos (printed) | the chain carries things between stations |
| Uses | none (`PickUp`, `PutDown`) | `Interact` on a switch and the button | `Interact` on the camera, the box, the printer and the board | one intent for every station (the Generator's GE1) |
| Host-side geometry | the cylinder (`StationState.contains`) | the cylinder, the sight line | the cylinder, the sight line, and the frame: a frustum and a sight line from the lens to each candidate | invariant 1: the host decides who is in the shot |
| Events | `PackageDelivered` | `SwitchChanged`, `ButtonPressed`, `ZoneProgress` | `ShotTaken`, `PhotoPrinted`, `PhotoHung`, and the item events | each shows something new on the clients |
| Tick | none | the charge | none (PD7 (b) would add one) | nothing in the photo runs on time |

### 2. The rules as the engine runs them (with the recommendations)
1. **The deal** (when `DealTasks` draws the photo task): a station on every marker of each of its five kinds, with no
   draw for placement, in the order camera, photo spot, card box, printer, board (ids in that order, level order within
   a kind). The demands are exact, as the Generator's (GE10 there): one `camera`, one `photo_spot`, one `card_box`, one
   `printer`, one `photo_board` marker, and one `photo` marker (the printer's tray, the photo kind's spawn tag, not
   snapped); with PD4's recommendation also one `memory_card` marker at the photo zone, where one card is dealt at the
   round's start (`ItemSpawned`, then `item_rested` with the spawn cause). No RNG purpose: nothing is drawn. With 0
   photos the task has no subtasks and is done (#79).
2. **A shot** is `Interact(camera)` from a living player in Round. In this order it is refused `two_handed`,
   `out_of_reach`, `blocked`, then the type's answer: `unavailable` once the task is done (PD12), `no_card` when the
   actor carries no card, `card_full` when no card it carries has a shot left. Applied: the card (the hand's if it has
   a shot left, else the belt's) takes the next shot; the host checks who is in the frame (§3.2), stores the shot with
   its `has_person` and records the poses near the lens (§3.3); `ShotTaken` goes to everyone.
3. **A card from the box** is `Interact(card_box)`: refused `two_handed`, `out_of_reach`, `blocked`, `hands_full`
   (`HandsHaveRoom`: the hand holds an item that cannot move to the belt) or `too_soon` (the player took a card less
   than the cooldown's seconds ago: #682's CE17, PE14). Applied: a new card appears at the box and
   goes into the hand, a one-handed hand item to the empty belt (`ItemSpawned`, then `ItemPickedUp`); at the cap the
   oldest loose card comes instead, as it is (PE10). A card nobody has used yet has no entry in the task state: it is
   fresh.
4. **A print** is `Interact(printer)`: refused `two_handed`, `out_of_reach`, `blocked`, then `unavailable` (done),
   `nothing_to_print` (no carried card has an unprinted shot). Applied (PD3's recommendation): every
   unprinted shot of the card (the hand's if it has one, else the belt's), in shot order, becomes a photo on the tray
   marker (`ItemSpawned`, `PhotoPrinted`, then `item_rested`), and is marked printed, so a shot prints once. The card
   stays with the player.
5. **A hang** is `Interact(photo_board)`: refused `two_handed`, `out_of_reach`, `blocked`, then `unavailable` (done)
   or `no_photo` (the hand holds no photo). Applied: the photo leaves the hand and is locked on the board (PE9);
   `PhotoHung`; if its shot has a person, the next undone subtask is done through `Tasks.subtask_done` (`TaskState`,
   `TaskProgress`, then `subtask_done` with the photo and its shot as the detail). With every subtask done the task is
   done, and every later use of its stations is refused `unavailable` (PD12).
6. **Nothing else** changes a shot, a card or a hung photo: no hit, knockdown, death or leave. A card or a photo drops
   at a death or a leave like any item, and keeps its shots. The state stays in `MatchState` until `ResetMatch`.

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
- **The candidates**, in peer-id order: every ALIVE player but the actor (PD1's recommendation).
- **A candidate counts** when its head, the point `Items.eye_of` gives (the floor it stands on raised by the eye
  height, as `InSight`'s eye), lies in the frame (`PhotoFrame.contains`) and the line from the lens to it is clear
  (`WorldQuery.line_of_sight`, recorded in the command log, so a replay agrees).
- **`has_person`** is whether any candidate counts; the task state also keeps who counted (`subjects`), for a later
  rule that needs it (PD2 (b), poses).
- **Only the level blocks a line** (layer 1): a player hidden behind another still counts, which changes nothing while
  any one person is enough (PD2 (a)).

#### 3.3 The record and the picture (PE4)
- **The record** in `ShotTaken`: every player with an avatar (ALIVE or DOWNED) but the actor whose position lies within
  `range_m` + 2 m of the lens (generous: the renderer clips the rest), as the snapshot's avatar row without its
  velocity: the peer, its position, its facing, its flags (`downed`), its hand and belt items. At most the snapshot's 15
  avatars. Ground items and bodies are not in it: they move only by events, so a client folding `ShotTaken` holds
  exactly the host's items and bodies at that tick, while avatars come from snapshots it draws about 100 ms late.
- **The picture.** As a client folds `ShotTaken` it renders the shot once: a `SubViewport` with
  `render_target_update_mode` `UPDATE_ONCE`, its `Camera3D` at the frame, puppets of the record's avatars
  (`client/player/remote_player_body.tscn`) on a visual layer only that camera sees, while it skips the live avatars'
  layer (`VisualInstance3D.layers`, `Camera3D.cull_mask`), and the flash (an `OmniLight3D` at the lens) on; read back
  after `RenderingServer.frame_post_draw` into an `Image` kept per shot for the match
  (`ImageTexture.create_from_image`). A printed photo shows its shot's picture (`PhotoPrinted` names the shot). A
  headless client folds the record and renders nothing.
- **Bandwidth.** One `ShotTaken` is about 40 bytes plus about 33 per avatar in the record: under 400 bytes with 10
  players, to each player once. A picture sent as an image would be 10 to 50 KB per shot, uploaded and relayed to
  every player (the Alternatives).
- **Leaks (invariant 2).** The record holds avatar fields every player receives in the snapshots anyway (§5: every
  living or downed avatar reaches every player of the match), taken at the shot's command rather than at the tick's
  end, so at most one movement claim apart; the one addition is the recipient's own pose, which it knows. So
  `ShotTaken` is a task event every player receives alike (§5's invariant holds), with no new audience and no role in
  it. `has_person` is never sent (PE5): the board's `TaskState` and `TaskProgress` at the hang tell what a look at the
  photo tells. A modified client could compute it from the record, as it could from the snapshots (PD13).
- **Lag (PE13).** The host uses its positions at the shot's tick, not rewound to what the shooter saw (remote avatars
  drawn about 100 ms late, plus half a round trip), as for hits (§10's lag compensation after the MVP). A subject
  standing on the spot is the same in both; one walking through the frame may differ by a step.

### 4. What everyone sees

| What | Who learns it | How |
|---|---|---|
| Where the camera, the spot, the box, the printer and the board stand | everyone | `StationPlaced` in the deal (and the level's own scenes) |
| A shot: when, at which camera, onto which card | every client receives it; an honest one shows the flash where the eye reaches and plays the shutter within 12 m | `ShotTaken` |
| Who stood near the lens at the shot | every client receives it (as every snapshot shows); shown only in the photo's picture, depth-tested | `ShotTaken`'s record |
| Whether a shot has a person | nobody, through an event, before its photo is hung; whoever sees the photo sees its picture | the picture; at the hang `TaskState` and `TaskProgress` |
| A card taken, a photo printed, picked up, put down, hung | everyone | `ItemSpawned`, `ItemPickedUp`, `ItemPlaced`, `PhotoPrinted`, `PhotoHung`; sounds within 12 m |
| Who took a card, printed or hung | nobody, through an event of the photo task (its events name stations and items, never a player); `ItemPickedUp` names the taker, as for any item; the snapshots show who stood there | as for a delivery |
| How many photos are needed and counted | everyone, on the task screen too | `TaskState`, `TaskProgress` |
| A photo's picture | whoever sees the photo: in a hand, on the tray, on the board, or held up by its holder | drawn on the photo in the world, depth-tested; the holder may look at its own up close (P8) |

### 5. Edge cases

| What happens | What the engine does | Why |
|---|---|---|
| Two players shoot in one tick | commands in their order (§4.5.3): two shots, each on its shooter's card | determinism |
| The subject steps out as the shot is taken | the host's position at the shot's tick decides; the picture shows the same moment (the record) | §3.3: one moment for the rule and the picture |
| The shooter stands in front of its own lens | never counted, never drawn in its own shot | #687: "it takes two" |
| The subject is knocked down in the frame | not counted (PD1's recommendation); drawn lying, as in the record | V4: "living" means ALIVE |
| A player behind the gazebo's wall, inside the frame | not counted: the line from the lens is blocked; the picture shows the wall | §3.2 |
| A player far behind the spot, in the frame but beyond `range_m` | not counted; drawn small if the picture reaches it | PD9's range |
| Only a body without a head in the frame (the head cut off by the frame's edge) | not counted | §3.2: the head must be in the frame (PD1) |
| A package carrier at the camera, the box, the printer or the board | `two_handed` | busy hands (#679) |
| A shooter with a knife in hand and a card on the belt | the shot goes onto the belt's card | the card may be in the hand or on the belt (PD11) |
| A card with no shot left | `card_full`; the player fetches a new card from storage | #687 |
| A card dropped, or left at a death | an item like any other, with its shots; anyone picks it up, shoots or prints with it | the card's shots belong to the card, not to a player |
| A second print of a card | prints only shots not yet printed; with none, `nothing_to_print` | a shot prints once (PD3) |
| A photo without a person hung | locked on the board, counts nothing (PD6) | #687: "one without a person does not count" |
| A photo hung after every subtask is done | `unavailable` (PD12) | the Generator's "done for good" |
| A dissident hides a card or a photo | an item like any other: the others search for it or take a new card | the same play as hiding a package |
| A dissident wastes shots on an empty spot | the card fills; the shots print as photos without a person | same rules for everyone (#679) |
| A player in the viewfinder is hit or knocked down | the client leaves the view (P7); the host never knew of it | PE1 |
| A client sends `Interact(camera)` from afar or in a burst | `out_of_reach`; each accepted shot uses a shot of its own card; the reliable-intent bucket bounds the rest (§4.5.6) | PE14 |
| The box pressed again and again, each card put down | refused `too_soon` but one take per the cooldown's seconds (0.25 s, a placeholder: 4 a second); each accepted take goes to everyone; at the cap (32 cards, a placeholder) the oldest loose card comes back to the taker, with whatever shots it holds | PE10, PE14; #682's CE17, CD6 |
| Round ends | nothing more counts; the state stays until `ResetMatch` | §9.1 |

### 6. PD items (the engineer's: game rules and taste)

| # | Question | Options | Trade-offs, and the failure each prevents | Recommendation |
|---|---|---|---|---|
| PD1 | Who counts as "a person in the photo" (#687's open item 1) | Who: (i) any ALIVE player but the shooter, whatever the role; (ii) the downed too. Where: (a) anywhere in the frame, with the head in the frame and in sight of the lens; (b) only standing on the spot (its cylinder) and in sight; (c) any part of the body in the frame | (ii) a downed player lying in the frame counts, so knocking someone down on the spot becomes a way to do the task; (i) matches "only living players do subtasks" (V4). A role test would tell everyone a role through the board (§9.2), so "whatever the role" is also the leak-safe answer. (b) a person clearly in the picture but a step off the spot does not count, against "counts only if a person is really in it" and "shows exactly what the camera saw". (c) a hand at the frame's edge counts: a "photo with a person" in which nobody can be seen | (i) and (a): the rule and the picture agree, and the spot is where players stand because the camera frames it |
| PD2 | Does the same player count for several photos (open item 1) | (a) yes: any photo with any living person in it counts; (b) each counted photo must show someone not yet counted | (b) needs as many subjects as photos (4 players: at most 3 subjects, the shooter excluded), so the count would depend on the player count, and the host must say why a photo does not count. (a) two players can do the task alone; others help by carrying | (a), "the simplest possible thing" |
| PD3 | The printing (open item 2) | One use prints: (a) every unprinted shot of the card, onto the printer's tray; (b) one shot per use; (c) into the hands. Time: (i) at once; (ii) after N seconds standing at the printer (a channel, like the raise). The card: (x) stays with the player, each shot printing once; (y) the printer keeps it | (b) up to five presses for one card, no new decision in them. (c) the hands hold two items, one of them the card, so five photos cannot go there. (ii) adds a wait with nothing to decide. (y) a card with shots left is lost, and every trip needs a new one from storage. A shot that prints twice would make one good shot every subtask | (a), (i), (x) |
| PD4 | The cards in storage (open item 3) | Supply: (a) a box of cards in storage that hands one card into the hand per press of E, without limit (as #682's boxes and herb beds); (b) a fixed stock dealt in storage at the round's start; (c) a box with a limit. The first card: (i) one card lies at the photo zone at the round's start, later ones come from storage; (ii) every card comes from storage | (b) and (c) can run out, and a dissident who hides the stock ends the task for good. (a) never runs out; its only bound is the engine's item cap (PE10). (ii) every round starts with a run from the gazebo down to the basement and back before the first shot; house-map decision 5 lists the chains that start in storage, and the photo is not one of them; #687 says "once they are used, a new card is taken in storage" | (a) and (i) |
| PD5 | Hands (open item 3) | (a) the card and the photo are one-handed: a player holds a card and a photo at once (hand and belt), like the cooking chain's ingredients (#682); (b) the photo takes both hands; (c) photos take no slot (a pocket) | (b) a photo carrier cannot use the camera or the box, and carries one photo at a time. (c) a new slot kind in the engine. (a) is the item rules as they are: one in the hand, one on the belt | (a) |
| PD6 | A hung photo (open item 4) | (a) locked on the board for good, with or without a person: nobody takes it down; (b) one without a person can be taken down again; (c) any photo can be taken down, a counted one undoing its subtask | (c) a dissident undoes the team's progress, and `Tasks` never undoes a subtask (the shared progress would go down on every screen). (b) one more use of the board for a photo that changes nothing. (a) junk photos clutter the board and change nothing | (a) |
| PD7 | A more natural touch (open item 5, the engineer's wish) | (a) none now; (b) a hung photo develops on the board for N seconds before it counts, its picture fading in (one tick, `TaskTicks`, and one number); (c) hanging takes N seconds of holding E (a channel); (d) the printer prints blank photos that show their picture only once developed in the darkroom | (d) breaks the decided "a printed photo shows exactly what the camera saw". (c) a wait with nothing to decide. (b) the darkroom becomes where photos develop, as in a real one; with photos locked once hung (PD6 (a)) nobody can spoil one while it develops, so it delays the count without adding a decision | (a) for the first build; (b) as the first candidate, a small change on top of P3 |
| PD8 | The words (open item 6) | the task's name; the task screen's description; the lobby label of the photo-count setting (`SettingSpec.display_name`). For comparison: "Carry each package to the circle of its colour. Packages take both hands." (Delivery), "Switch on every active switch, then press the generator's button to charge it." (the Generator) | the mode check refuses an empty description, so P5 cannot land without one | his words; until then P5 carries placeholders marked "not a decision", his to approve in its PR |
| PD9 | The numbers (open item 6) | the photo count's default and range; the frame's `fov_deg`, `aspect` and `range_m`; each station's `radius_m` and `height_m` (how near a player must stand to use it, as the Generator's GD6); the shortest time between two card takes by one player (the box's `Cooldown`, PE14) | a large range or a wide frame counts a distant passer-by in the yard; a narrow one makes the subject hunt for the frame. For comparison: Delivery 1 to 10 (default 6), the Generator 2 to 4 (default 3), Cooking default 1; the gazebo is 10 x 10 m | his numbers; until then placeholders in P5, "not a decision": for example 1 to 5 photos (one card's worth at most), default 3; 50° vertical, 4:3, 10 m; 2 m and 2 m for the stations, as the Generator's GD6; the take's cooldown his answer to #682's CD17 (0.25 s there, a placeholder) |
| PD10 | The frame | (a) fixed: the camera always frames the spot ("facing the photo spot"), no turning, no zoom; (b) the shooter turns it within limits | (b) the shot's intent must carry a direction, a client claim the host clamps, and the frame on the host is no longer the level's. (a) is #687's decided "facing the photo spot" read literally | (a) |
| PD11 | The card and the camera | (a) the shooter carries the card (in the hand or on the belt) and each shot goes onto it; (b) the card goes into the camera and stays there until someone takes it out | (b) two more uses (put in, take out), and a card left in the camera can be taken by anyone. (a) no state on the camera; the shooter walks off with its shots | (a) |
| PD12 | After the task is done | (a) the camera, the printer and the board refuse (`unavailable`); the box still gives cards; (b) everything keeps working and counts nothing | (b) photos and junk keep piling up for nothing. (a) as the Generator's decided "can no longer be used"; the box is a plain item source, like #682's beds | (a) |
| PD13 | How hidden a photo's content is before it is hung | (a) hidden by sight: every client receives every shot's record and shows a picture only on a photo seen in the world or held (PE4); (b) hidden on the wire: a peer receives a shot's record only when it picks up that photo, or when it is hung | (a) a modified client could tell which shots have a person, as it can draw every hidden package today, the record holding only what the snapshots showed. (b) a private task event (§5's "every player receives the same task events" would change), a photo in another player's hand drawn blank, and a render at pick-up that can no longer show the items as they lay at the shot | (a), as the Generator's GD11 (a) |
| PD14 | Where the photo task plays, and how many task types a match deals | as the Generator's GD7: (a) in the base mode, with the five station scenes instanced on the greybox at placeholder points; (b) on House only, banned on the greybox by hand; and `tasks`: every type every match, or drawn | as there; with every chain's type in every match the match clock (10 minutes) may want a retune | the same answer as his GD7 for the Generator |
| PD15 | The flash and the sounds | a flash light at the lens on each shot, seen where the eye reaches; a shutter click; a printer sound while it prints; a sound at the hang; each within 12 m | #687: "with a flash"; the sounds are not in it | the flash, the shutter and the printer; placeholder blips built in code, as `WorldSounds` makes today's, until his CC0 files arrive with their `docs/credits/` entries |

### 7. PE items (technical: the manager decides and reports)

| # | Choice | Options | The failure it prevents | Decision |
|---|---|---|---|---|
| PE1 | The shot's intent, and the viewfinder | (a) the viewfinder is a client camera mode the host never hears of; the shot is `Interact(camera)` sent from it, the host checking everything again; (b) the host keeps who uses the camera: enter and leave intents, one user at a time, and a `Use` takes the shot; (c) `Use(facing)` in the view | (c) `Use` goes to the hand item's rule first (§9.2): a knife holder would stab. (b) two more intents and a "busy" state to clear on every hit, knockdown, death and leave, for nothing the rules need. (a) a modified client could shoot without looking: it gains nothing, the host decides who is in the frame | (a) |
| PE2 | Who decides "a person in the frame" | (a) the host, at the shot's tick, from its own state: `PhotoFrame` and `WorldQuery.line_of_sight` from the lens to each candidate's head (§3.2); (b) the client reports whom it saw; (c) the client sends its picture and the host analyses it | (b) and (c) trust a client's field or image, against invariant 1: a modified client "sees" a person who was not there. (c) also needs image analysis on the host | (a) |
| PE3 | The frame's pose | (a) from two station markers, the camera's and the spot's (both snapped, both in `StationPlaced`), the mode's eye height and the type's numbers; one `PhotoFrame` in `core/` used by the host and the client; (b) an oriented marker: `LevelLayout` gains a rotation per marker, read from a lens node; (c) `StationPlaced` gains a facing | (b) changes `LevelLayout`, `MarkerReader` and the command log's layouts, and the client would still need the rotation sent. (c) a wire change for every station kind. Both let the level's lens node and the host's frame drift apart unseen. (a) needs no change to the layout, the reader or the wire, and the client builds the very frame the host checks from public data | (a); P9 tests on House that the camera scene's look matches the frame (the lens point clear of collision, the line from the lens to the aim clear) |
| PE4 | How the picture reaches the clients | (a) each client renders it from the shot's record (§3.3) as it folds `ShotTaken`; (a2) the same at `PhotoPrinted`; (b) the shooter's client renders and uploads an image that the host relays; (c) the host renders | (b) 10 to 50 KB per shot uploaded and relayed to every player, a large message split over ENet's reliable lane and WebRTC's message size, and a client-authored picture: a modified client shows a person who was not there, or anything at all. (c) a headless host has no renderer (its worlds are physics only, §4.5.9), and `core/` and `server/` hold no rendering. (a2) items moved since the shot would be drawn where they lie then, unless the record held them too, and the flash would not be in the same frame. (a) under 400 bytes per shot; the record holds only what the snapshots showed | (a) |
| PE5 | `has_person` on the wire | (a) never sent: kept in the task state; the hang's `TaskState` and `TaskProgress` are the only signal; (b) in `ShotTaken` or `PhotoPrinted` | (b) a client could print "person: yes" beside a photo nobody has looked at, which no picture says | (a) |
| PE6 | Where the state lives | (a) the task state (`PhotoTask.State`): the station ids; per shot its id, card, tick, `has_person`, `subjects` and whether it is printed; per card (item id) its shots; per photo (item id) its shot; the hung photos in order; (b) the per-part state table; (c) fields on `ItemState` (shots on a card, a shot on a photo) | (b) splits one task over two homes where §9.1 names the task state. (c) fields every item carries for one type. With (a) a card the box gave is unknown to the state until its first shot, and counts as fresh | (a) |
| PE7 | Giving a card | (a) the cooking design's item source, by its names: a composed rule on the box's station kind, `HandNotTwoHanded`, `AtStation`, `StationInSight`, `HandsHaveRoom` (`hands_full`), the cost `Cooldown` (#682's CE17: key `photo_take`, a provisional id; the seconds PD9's, CD17's answer reused; `too_soon`), then `GiveItem(kind, max_items)`: a new card at the box's position, taken into the hand in the same command (`ItemSpawned`, then `ItemPickedUp` with `belted`), no `item_rested` as it never rests; (b) `PhotoTask.use_station` for the box too; (c) a photo-only effect | (b) a task-type call for something that touches no task state. (c) a second item source beside #682's for the same thing. (a) a herb bed and the card box are the same rule with another kind; the printer is not one (PE8) | (a); if the photo task is built before #682's C1, P1 builds these parts by #682's CE2, CE3, CD5 and CD6, and C1 adds only its item target. The box's cooldown key is its own, so a card take and a herb take never wait on each other: each source bounds its own spam |
| PE8 | Where printed photos appear | (a) on the printer's tray: the photo kind's spawn tag (`photo`) on a marker in the printer's scene, not snapped; each photo `ItemSpawned` there, then `PhotoPrinted(item, shot)`, then `item_rested` (spawn); (b) into the actor's hands; (c) at the printer's use spot on the floor | (b) the hands hold two items, one of them the card (PD3). (c) photos lying on the floor in front of the printer. A new item kind reusing `ItemSpawned` keeps one way for a client to learn of a new item; `PhotoPrinted` adds only the binding to its shot, as `ItemSpawned` binds a package to its circle | (a) |
| PE9 | Hanging | (a) the cooking design's move that locks an item at a station (its CE5, built in C2): the photo out of the hand, locked at the board's position (`ItemState.Where.LOCKED`, as a delivered package), no `item_rested`; then `PhotoHung(item, station)`; then `Tasks.subtask_done` if it counts; the client draws hung photos in hang order on the board scene's slots; (b) `Items.place` at the board, raising `item_rested`, and the type's `on_fact` locks it | (b) a fact that every task type's check then reads for a photo no circle wants, and an `ItemPlaced` that says the photo lies on the floor. (a) one move in `Items`, the one place that moves items (§9.3), shared with the grill and the plates | (a); P1 builds the move if #682's C2 has not landed |
| PE10 | A bound on items | (a) the cooking design's cap per given kind (`GiveItem.max_items`, 32, a placeholder; its CE3) with the engineer's answer to its CD6 at the cap (recommended: the oldest loose item of the kind comes to the taker); photos need no cap of their own, as each shot prints once and the shots are bounded by the cards (at most `max_items` x `shots_per_card`); (b) a bound on all items in `Items`, refusing a new one (`too_many_items`); (c) none | (c) a box "without limit" lets one client create a card per two intents (take, put down), about 10 a second within the bucket (4 under PE14's cooldown): item ids are `u16`, and long before they run out every client draws thousands of items. (b) a second bound beside #682's for the same failure, and a refusal that lets one spammer block the box. With (a) a card that comes back at the cap keeps its shots, since it is the same item; only a spammer reaches 32 cards, as normal play uses one or two | (a) |
| PE11 | Which card, and the order of events | a shot uses the hand's card if it has a shot left, else the belt's; a print the hand's card if it has an unprinted shot, else the belt's. One shot: `ShotTaken`. One print: per photo in shot order `ItemSpawned`, `PhotoPrinted`, `item_rested`. One hang: `PhotoHung`, then, if counted, `TaskState`, `TaskProgress`, `subtask_done`, as Delivery sends `PackageDelivered` first. The deal: `StationPlaced` per station in id order, then the first card's `ItemSpawned` | a `PhotoPrinted` before its item exists on the client; a count shown before the photo is on the board | as stated |
| PE12 | The mode checks and the demands | `PhotoTask.check`: the five station kinds set, with different spawn tags (and ZE3 across the mode); the card and photo item kinds set, declared by the mode, with spawn tags different from every station kind's; `shots_per_card` at least 1; `fov_deg` within 1 to 179, `aspect` within 0.25 to 4, `range_m` within 0.5 to 100, their neutral defaults outside; the subtasks setting declared, a whole number, minimum at least 0; the camera's, printer's and board's stations each holding an `Interact` rule whose effect is `UseStation`; the box's holding one that pays a `Cooldown` and whose effect is `GiveItem` of the card kind. Demands: exactly one marker of each station kind's tag, exactly one `photo` marker, and with PD4 (i) exactly one `memory_card` marker, whatever the setting and the players | a camera without a spot has no frame; a second printer would have no tray of its own; a box that gives another kind leaves no way to get a card | as stated |
| PE13 | Lag | (a) the host's positions at the shot's tick; (b) rewind the subjects to what the shooter saw | (b) a rewind buffer the MVP has for nothing (§10: lag compensation after the MVP playtest); a subject standing still is the same in both | (a) |
| PE14 | A rate limit on the photo task's events | (a) no window: `ShotTaken` and `PhotoHung` follow one accepted intent each; a print's photos are bounded by the shots, each printing once; the box's takes, which emit two events each (`ItemSpawned`, then `ItemPickedUp`), are bounded by its `Cooldown` (#682's CE17); (b) ZE4's window; (c) the bucket alone, for the box too | (c) a spammer alternating a take and a put-down sends about 30 reliable events a second to every player (#682's CE17), the rate the Generator's GE8 rejects; with the cooldown at 0.25 s, 12 a second, under today's `PickUp` and `PutDown` spam. For the rest the bucket bounds the intents (§4.5.6), and nothing in the photo task changes on its own over time, unlike a zone's presence | (a); the chaos bots' burst rows check it (§8) |
| PE15 | The client's render | puppets on a photo-only visual layer, live avatars on a layer the photo camera skips (no second `World3D`, no copy of the level); 384 pixels high and as wide as `aspect` makes it (512 at 4:3), kept as an `Image` per shot for the match, about 0.6 MB each, dropped at a new match; headless clients render nothing | a second world would copy the House's nodes; hiding the live avatars for one frame would flicker on screen | as stated; P8 measures the memory over a match |
| PE16 | The rejection reasons | (a) four new reasons, `no_card`, `card_full`, `nothing_to_print` and `no_photo`, and `unavailable` reused, all returned by `PhotoTask.use_problem` through G1's `StationUsable` and listed in `PhotoTask.use_reasons()` (#682's CE11, which extends G1's API); each joins the wire alphabet and ARCHITECTURE §3.2's rejection table, from which `ChaosOracle` is written (§4.6.5), in the issue that first returns it; (b) `unavailable` for everything | (b) a client hint that cannot say why the camera refused. Without `use_reasons()` the static `Condition.rejection_reason()` that `RuleRunner` and `ModeCheck` read names one reason per condition, so the four could be neither emitted nor checked, and a reason missing from the alphabet makes the encoder refuse the `Rejected`. Each reveals only what the sender carries and whether the task is done, both public | (a); P2 and P3 depend on #682's C1 for `use_reasons()`, or P1 builds it by CE11 |

### 8. Testing
- **Unit tests** (P1 to P3; fixtures only, never `content/`, ARCHITECTURE §9.6): `PhotoFrame` (a point at the centre,
  just inside and just outside each edge, nearer than 0.3 m, beyond `range_m`, behind the lens); the shot: a subject
  counted, one outside the frame, one behind a `FlatWorldQuery` wall, one downed, the shooter in front of its own lens,
  one beyond the range, a head cut off by the frame's edge; each refusal in its order (§2); the card choice (hand, then
  belt); `card_full` after `shots_per_card` shots; the record's contents (the actor left out, the radius, the downed
  flag); the print (every unprinted shot once, the tray's position, `nothing_to_print`); the hang (counted or not, the
  last subtask, `unavailable` after done, `no_photo`); the card box's rule (a card into the hand, the hand's knife to
  the belt, `hands_full`, `too_soon`: one player's takes on 100 ticks in a row give at most 100 / 5 + 1 cards at 0.25 s;
  `GiveItem` itself is #682's C1's to test); the deal, the exact demands and the fit check;
  PE12's checks; `ModeCheck` testing every reason `PhotoTask.use_reasons()` lists against the wire alphabet (one
  removed from the alphabet is found); the order of events (PE11);
  `ResetMatch` clearing the state; the wire rows' round trips; a replay of a shot agreeing on `line_of_sight`.
- **The role-swap check** (P2, P3): the same seed and commands with two players' forced roles swapped emit identical
  `ShotTaken`, `PhotoPrinted`, `PhotoHung`, `TaskState` and `TaskProgress` streams, as the zone task's. Planted once
  (the frame skips dissidents), it fails; reverted.
- **The leak test's lists** (P2, P3): the three events join the task events every player receives alike
  (`LeakCheck`, `ScenarioInvariants`); the plant waits for P10's scenario, as the Generator's G8.
- **The chaos bots** (P2, P3; P10 against dealt stations): the three new H→C kinds in the wrong-direction list; a
  hostile `Interact` at the camera, the box, the printer and the board from out of reach, without a card, and in a
  burst, getting only its `Rejected`s (`out_of_reach`, `no_card`, `card_full`, `nothing_to_print`, `no_photo`,
  `hands_full`, `too_soon`, `two_handed`, `unavailable`), the burst stopped at the bucket, and a burst of takes at the
  box refused `too_soon` but one per the cooldown's seconds.
- **Integration tests on House** (P9; bots do not play House, ARCHITECTURE §9.7): `Match` over `HostWorldQuery` with
  House's level: a player on the photo spot is counted in a shot from the camera; one behind the gazebo's wall or
  outside the frame is not; the lens point is clear of the camera scene's collision and the line from the lens to the
  aim is clear; a scripted chain (a card, a shot, the print in the study, the hang in the darkroom) completes a
  subtask; the five stations and the tray read without errors.
- **Scenarios on the greybox** (P10, content, provisional): bots play the chain on the greybox's station scenes (a
  subject walks to the spot, a shooter interacts with the camera, a carrier prints and hangs), one of them in `bots`
  over the real wire; the leak plant there (`ShotTaken` declared to the actor only fails `LeakCheck` and
  `ScenarioInvariants`); reverted, recorded in the PR.
- **The client** (P7, P8): the viewfinder's camera equals `PhotoFrame` (the frame's corner points project onto the
  mask's corners); the fold of `ShotTaken`, `PhotoPrinted` and `PhotoHung`; a headless client renders nothing; a
  rendered picture from a fixture record (`shot` previews); the hint over the camera, the box, the printer and the
  board only when usable; the M4 render checklist, the PRs routed to `netcode-security-reviewer` too.
- **Green** (#605): `verify` (lint and check) locally, then CI's full suite on the PR, for each issue of §9.

### 9. The split
Sizes as in M6 and M7: S up to about 400 changed lines, M up to about 900. Base: `main`. Effort: high for `core/`,
`net/` and `tests/harness/`. Every issue below lands after the Generator's G1 (the station-use intent and its parts),
which lands after `release/m7` in main.

| Issue | Labels | Goal | Acceptance | Files | Depends on | Size |
|---|---|---|---|---|---|---|
| P1 | needs-engine, area:core | Only if the photo task is built before the cooking chain's C1 and C2: the shared item parts | the cooking design's parts by its names and choices (CE2, CE3, CD5, CD6, CE5's lock): `HandsHaveRoom` (`hands_full`), `GiveItem(kind, max_items)` with the cap and the engineer's CD6 answer, the `Items` move that locks an item at a station; `TaskType.use_reasons()` (base: [`unavailable`]) with `ModeCheck` testing each listed reason against the wire alphabet, by CE11; no `Interact(item)`, which stays C1's; unit tests; ARCHITECTURE §9.3 (`Items`), §9.4.1, §9.4.2. Opened only if the photo task is scheduled first; else P3 and P5 depend on C1 and C2 | `core/items/hands_have_room.gd`, `core/items/give_item.gd`, `core/items/items.gd`, `core/content/task_type.gd`, `core/content/mode_check.gd`, `tests/unit/items/`, `tests/unit/content/`, `docs/ARCHITECTURE.md` | G1 | S |
| P2 | needs-engine, area:core, area:net | The photo task type, the frame and the shot | §2.1 and §2.2 with the recommendations taken (PD1, PD9's placeholders in fixtures, PD10, PD11); §3.1 to §3.3's host half; PE2, PE3, PE5, PE6, PE11 to PE14 for the shot; `PhotoTask` with its deal, exact demands and checks; `PhotoFrame`; `ShotTaken` with its wire row and a protocol bump; PE16: `PhotoTask.use_reasons()` listing all five reasons, and `no_card` and `card_full` in the wire alphabet and §3.2's rejection table; §8's unit tests for the frame and the shot, the role-swap check, the chaos row (the wrong-direction kind), `ShotTaken` in the leak test's lists; ARCHITECTURE: the photo task's entry beside Delivery's (§9.5), §4.2, §4.3.4, §5's task events | `core/tasks/photo_task.gd`, `core/tasks/photo_frame.gd`, `core/events/shot_taken_event.gd`, `net/messages/`, `core/match/phases/join_rules.gd` (the version), `tests/harness/scenario_invariants.gd`, `tests/harness/bots/leak_check.gd`, `tests/harness/chaos/`, `tests/unit/tasks/`, `tests/fixtures/tasks/`, `docs/ARCHITECTURE.md` | G1; #682's C1 (`use_reasons()`, PE16) or P1; G0 if it lands first; the engineer's PD1, PD10, PD11 (each revertible, so P2 may start on the recommendations) | M |
| P3 | needs-engine, area:core, area:net | The print and the hang | §2.4 to §2.6 with PD2, PD3, PD6 and PD12's recommendations; PE8, PE9, PE11; `PhotoPrinted` and `PhotoHung` with their wire rows and a protocol bump; `nothing_to_print` and `no_photo` in the wire alphabet and §3.2's rejection table (PE16); the subtask count; §8's unit tests, the role-swap check over the whole chain, the chaos rows, both events in the leak test's lists; ARCHITECTURE §9.5's entry completed, §4.2, §4.3.4, §5 | `core/tasks/photo_task.gd`, `core/events/photo_printed_event.gd`, `core/events/photo_hung_event.gd`, `net/messages/`, `core/match/phases/join_rules.gd`, `tests/harness/`, `tests/unit/tasks/`, `docs/ARCHITECTURE.md` | P2; #682's C1 and C2 (or P1); the engineer's PD2, PD3, PD6, PD12 | M |
| P4 | area:level | The station scenes, in place of the House markers | by the Generator's GE11: `levels/stations/camera.tscn` (a tripod: greybox look, collision on layer 1 kept below the line from the lens to the aim, its use-spot `Marker3D` in `spawn_camera` behind it, where the shooter stands), `photo_spot.tscn` (a floor mark, `spawn_photo_spot`), `card_box.tscn` (`spawn_card_box`), `printer.tscn` (`spawn_printer`, and a `spawn_photo` tray marker on its top), `photo_board.tscn` (`spawn_photo_board`, and named slots for the hung photos); the tags provisional, "not a decision"; `photo_spot.tscn` instanced at the photo spot in place of `PoseScreen`, `printer.tscn` and `photo_board.tscn` in place of `Printer` and `PhotoBoard`, `camera.tscn` facing the spot in the photo zone and `card_box.tscn` in storage at points the PR proposes, a `spawn_memory_card` marker beside the camera (PD4 (i)); `levels/CLAUDE.md`'s spawn points gain the tags; a `shot` of each room; provisional, named in the PR for the engineer's approval | `levels/stations/`, `levels/house/rooms/photo_zone.tscn`, `storage.tscn`, `study.tscn`, `darkroom.tscn`, `levels/CLAUDE.md`, `docs/design/house-map.md` (§6's two new points) | G4 (the station scene conventions it sets); before P5 | S |
| P5 | area:content | The photo task in the base mode | `content/tasks/photo.tres` with the engineer's words (PD8) and numbers (PD9), `shots_per_card` 5, the five station kinds with their `Interact` rules (the camera, printer and board: `HandNotTwoHanded`, `AtStation`, `StationInSight`, `StationUsable`, then `UseStation`; the box: `HandNotTwoHanded`, `AtStation`, `StationInSight`, `HandsHaveRoom`, `Cooldown` (key `photo_take`, the seconds PD9's), then `GiveItem`); `content/items/memory_card.tres` and `content/items/photo.tres` (`hands` per PD5); the base mode: the type, its subtasks setting, `tasks` per PD14; P4's station scenes on the greybox at placeholder points (PD14 (a)), above y = 0; the MVP's scenarios ban the photo task too (M7-Z2's bans) and keep dealing Delivery alone; every test that loads the base mode still passes, each changed expectation named in the PR; provisional files named for the engineer's approval | `content/tasks/`, `content/items/`, `content/modes/base_mode.tres`, `levels/greybox/greybox.tscn`, `content/scenarios/`, `tests/unit/content/`, `tests/integration/`, `tests/scenarios/`, `docs/ARCHITECTURE.md` (§9.5, §9.6) | P2, P3, P4; #682's C1 (or P1); G3 (the darkroom's board is below y = 0), G5 (Round accepting `Interact`); the engineer's PD5, PD8, PD9, PD14 | M |
| P6 | area:client | The flash and the sounds | `ShotTaken`'s flash: an `OmniLight3D` pulse at the lens with `shadow_enabled` and a short `omni_range`, so it never lights a room through a wall (a light without shadows passes through walls, which would show a flash where no eye reaches); the shutter, the printer's and the hang's sounds through `SoundChooser` and `WorldSounds`, within 12 m (`AudioStreamPlayer3D.max_distance`) and muffled behind the level (M5-7); placeholder blips (PD15); the M4 render checklist (items 5 and 10) | `client/world/world_sounds.gd`, `client/world/sound_chooser.gd`, `client/world/`, `tests/unit/client/` | P2, P3; the engineer's PD15 | S |
| P7 | area:client | The viewfinder | E over the camera enters the view: the active camera at `PhotoFrame`'s pose (`Camera3D.fov`, `keep_aspect` `KEEP_HEIGHT`), the screen outside the aspect masked, movement held; the shot on the primary button sends `Interact(camera)`; E or Esc leaves, as does a hit, a knockdown or a death; the HUD shows the carried card's shots left (counted from `ShotTaken`); the hints over the camera, the box, the printer and the board only when usable (G6's `TargetChoice`); a test that the frame's corners project onto the mask's corners; ARCHITECTURE §4.7 | `client/player/`, `client/world/`, `client/ui/hud.gd`, `tests/unit/client/`, `tests/integration/client/`, `docs/ARCHITECTURE.md` | P2, P4; G6 | S |
| P8 | area:client | The pictures and the photo's look | PE15: `ClientModel` folds `ShotTaken`'s record, `PhotoPrinted` and `PhotoHung`; each shot's picture rendered as it is folded (`SubViewport` `UPDATE_ONCE`, puppets on the photo layer, the flash on, read back after `RenderingServer.frame_post_draw`); the photo item drawn with its picture (`ItemView` gains `photo` and `memory_card`), photos on the tray spread apart, hung photos on the board's slots in hang order, all depth-tested; a way for the holder to look at its own photo up close; headless clients render nothing; memory measured over a match; `shot` previews; the M4 render checklist (items 1, 3 and 5), the PR routed to `netcode-security-reviewer` too; ARCHITECTURE §4.7 | `client/net/client_model.gd`, `client/world/`, `client/player/first_person_hand.gd`, `client/dev/`, `tests/unit/client/`, `docs/ARCHITECTURE.md` | P3, P4, P7 | M |
| P9 | needs-engine, area:core | Integration tests: the photo task on House | §8's House tests in the host's real world | `tests/integration/levels/`, `docs/ARCHITECTURE.md` (§9.7's House line) | P3, P4, P5 | S |
| P10 | area:content, area:tooling | Scenarios that play the photo task, its leak plant | §8's greybox scenarios (provisional, the engineer approves the scripts), one in `bots`; the leak plant planted once and reverted, recorded in the PR; the chaos bots against dealt stations; the scenario runner's and `bots`' tests still pass | `content/scenarios/`, `tests/scenarios/`, `tests/harness/chaos/`, `docs/ARCHITECTURE.md` (§9.7, §4.6.5.3) | P3, P5; G8 (`StepInteract`) | S |

### 10. Needs the engineer
One batched question: PD1 to PD15 (§6), each with its options and a recommendation. "Every recommendation" is a full
answer to PD1 to PD7 and PD10 to PD15; PD8's words and PD9's numbers are his to give, or to approve as placeholders
marked "not a decision" in P5's PR. P1 and P4 need none of them; P2 and P3 start on the recommendations, each
revertible in its code.

## Alternatives
- **An image uploaded by the shooter** (PE4 (b)): 10 to 50 KB per shot relayed to every player, and a picture a
  modified client can fake.
- **A picture rendered on the host** (PE4 (c)): a headless host has no renderer, and `core/` and `server/` hold none.
- **The client deciding who is in the frame** (PE2 (b), (c)): a client's field or image, against invariant 1.
- **An oriented marker or a facing in `StationPlaced`** (PE3 (b), (c)): a layout, reader or wire change for what two
  positions already give.
- **A host-known viewfinder** (PE1 (b)): enter and leave intents and a busy state the rules never read.
- **`has_person` on the wire** (PE5 (b)): a flag a client could show where no picture says it.
- **The box as a task-type call, or a photo-only item source** (PE7 (b), (c)): code for what #682's item source
  already does.
- **A bound on all items, refusing a new one** (PE10 (b)): a second bound beside #682's cap, which one spammer could
  use to block the box.
- **Hanging through `item_rested`** (PE9 (b)): a fact and an `ItemPlaced` that say the photo lies on the floor.
- **Rewinding the subjects** (PE13 (b)): lag compensation the MVP has nowhere else.
- **A second world for the render** (PE15): a copy of the level's nodes for one frame per shot.

## Consequences
- GDD §8 gains the photo chain's section with its open questions; ARCHITECTURE §9.8 gains the photo task's row and
  §10 its open row, pointing here; house-map §6 gains the camera and the card box (to be placed by P4).
- When P2 and P3 land, ARCHITECTURE gains the photo task's entry in §9.5 and its three events in §4.2, §4.3.4 and §5,
  with their `Built in` lines; `HandsHaveRoom`, `GiveItem`, its cap and the lock at a station arrive with #682's C1
  and C2 (or P1).
- The protocol version goes up in P2 and in P3; kind numbers and versions are taken when each lands, never from here.
- The card box and the board reuse the cooking design's item source and its lock at a station by their names (#682's
  CE2, CE3, CE5); the printer does not use `GiveItem`, since each photo binds its own shot and one print makes up to
  five photos (PE8).
- The picture is a render from public data, so later rules on a photo's content (poses, gestures, #687's "later")
  need only the host's check to read more of the subject (its facing, a gesture state) and the record to carry it.
- With PD14 (a) every map of the base mode needs the five station scenes and a tray; House has them once P4 lands,
  the greybox in P5.
