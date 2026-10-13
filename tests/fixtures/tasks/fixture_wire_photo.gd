class_name FixtureWirePhoto
extends RefCounted
## The fixture mode, map and PhotoTask of the photo wire test (#789, photo P10; the photo ADR's §8
## "The wire, without bots", PE18; its suite tests/integration/server/host_session_photo_test.gd),
## built in code (a part's tests never load `content/`, ARCHITECTURE §9.6). Its kinds, ids and
## numbers are fixture values (FixturePhotoModes'), not the engineer's provisional ones.
##
## mode(): the harness's fixture mode (FixtureBaseMode's phases with res:// levels) on the one map
## STUDIO, its `all_loaded` row placing the players in peer-id order onto the `round_player`
## markers in level order (PlacePlayers' `ordered`, so each test chooses who stands where), with
## the mode's actions PickUp (2 m) and PutDown (1 m), the item kinds `film` (capped at CAP) and
## `photo` (PHOTO_CAP), the settings `tasks` (1), `banned_task_types` and `photos` (PHOTOS, 0 to
## FixturePhotoModes.MOST_PHOTOS), photo_type() playing on STUDIO only (`TaskType.maps`), the deal
## (DealTasks) first on `loading, all_loaded -> pregame`, and Round accepting PickUp, PutDown and
## Interact from the living.
##
## layouts(): the harness's lobby and STUDIO with the base mode's knife and circle markers (its
## demands), one marker of each photo tag and the `round_player` markers `spots` (SUBJECT_SPOT,
## SHOOT_SPOT, OUT_SPOT by default): so no client walks. From SHOOT_SPOT a player uses the camera,
## the printer and the board and picks up the dealt film and the tray's photo; from SUBJECT_SPOT,
## on the photo spot in the middle of the camera's frame, it uses the film box; OUT_SPOT lies far
## beyond the record's reach of the lens (range_m plus PhotoTask.RECORD_MARGIN_M).

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

## The fixture map: the one path in the mode's `maps`, the layouts' keys and PhotoTask's `maps`.
const STUDIO := "res://tests/fixtures/server/studio.tscn"
## The photos to hang (the `photos` setting's default): one counted hang finishes the task.
const PHOTOS := 1
## The least film cap PhotoTask.check allows: twice the mode's 4 players, 1.
const CAP := 9
## The least photo cap it allows: twice 4 players, 3 photos at most, 2 frames, 1.
const PHOTO_CAP := 14
## The box's, the printer's and the board's cylinder radius: SHOOT_SPOT in the printer's and the
## board's, SUBJECT_SPOT in the box's.
const REACH_M := 3.0
## The box's Cooldown: FixturePhotoModes.BOX_COOLDOWN_S, 5 host ticks at 20 Hz.
const TAKE_TICKS := 5
## The camera looks along +Z at the photo spot 10 m away (FixturePhotoModes' range).
const CAMERA_AT := Vector3(0, 0, 20)
const SPOT_AT := Vector3(0, 0, 30)
const BOX_AT := Vector3(2, 0, 30)
const PRINTER_AT := Vector3(2, 0, 19.5)
const BOARD_AT := Vector3(-2, 0, 19.5)
## The dealt film's marker and the printer's tray, each 0.5 m from SHOOT_SPOT.
const FILM_AT := Vector3(0.5, 0, 19.5)
const TRAY_AT := Vector3(-0.5, 0, 19.5)
## Behind the lens, inside the camera's 1 m cylinder: a shooter, never in the frame or the record.
const SHOOT_SPOT := Vector3(0, 0, 19.5)
## On the photo spot, 0.5 m short of its marker (no two markers share a position).
const SUBJECT_SPOT := Vector3(0, 0, 29.5)
## 100 m from the lens: outside the frame and the record, and beyond the record invariant's bound
## (range_m, PhotoTask.RECORD_MARGIN_M and one claim's longest step, ScenarioInvariants.record_step:
## about 86 m), so a row naming it fails LeakCheck's decoded-side check too.
const OUT_SPOT := Vector3(100, 0, 20)
const SPOTS: Array[Vector3] = [SUBJECT_SPOT, SHOOT_SPOT, OUT_SPOT]


static func mode() -> GameMode:
	var made := Harness.fixture_mode()
	made.maps = PackedStringArray([STUDIO])
	made.actions.append(FixtureItemModes.pick_up_rule(FixtureItemModes.REACH_M))
	made.actions.append(FixtureItemModes.put_down_rule(FixtureItemModes.DISTANCE_M))
	made.item_kinds.append(FixturePhotoModes.item(&"film", CAP))
	made.item_kinds.append(FixturePhotoModes.item(&"photo", PHOTO_CAP))
	made.settings.append(FixtureModes.setting(&"tasks", 1, 1, 1))
	made.settings.append(FixtureDealModes.banned_setting())
	made.settings.append(FixtureModes.setting(&"photos", PHOTOS, 0, FixturePhotoModes.MOST_PHOTOS))
	made.task_types = [photo_type(made)]
	var loaded := made.find_transition(&"loading", LoadingPhase.ALL_LOADED)
	for action: RuleEffect in loaded.actions:
		if action is PlacePlayers:
			(action as PlacePlayers).ordered = true
	loaded.actions.insert(0, FixtureDealModes.deal_tasks())
	var round_phase := made.find_phase(&"round")
	for intent: StringName in [Intents.PICK_UP, Intents.PUT_DOWN, Intents.INTERACT]:
		round_phase.accepts.append(AcceptSpec.of(intent, AcceptSpec.From.LIVING))
	return made


## FixturePhotoModes' PhotoTask over `game_mode`'s film and photo kinds, on STUDIO only, its box,
## printer and board reaching REACH_M.
static func photo_type(game_mode: GameMode) -> PhotoTask:
	var made := FixturePhotoModes.photo_type(game_mode)
	made.maps = PackedStringArray([STUDIO])
	for kind: StationKind in [made.film_box, made.printer, made.board]:
		kind.radius_m = REACH_M
	return made


## The harness's lobby and STUDIO (the class comment), with `spots` as its round_player markers in
## level order: the i-th player in peer-id order stands on the i-th.
static func layouts(spots: Array[Vector3] = SPOTS) -> Dictionary[String, LevelLayout]:
	var lobby: LevelLayout = Harness.layouts()[Harness.LOBBY]
	var map := LevelLayout.new(STUDIO)
	for spot: Vector3 in spots:
		map.add_marker(&"round_player", spot)
	for i in 3:
		map.add_marker(&"knife", Vector3(20 + i, 0, 0))
		map.add_marker(&"circle", Vector3(30 + i, 0, 0))
	map.add_marker(&"camera", CAMERA_AT)
	map.add_marker(&"photo_spot", SPOT_AT)
	map.add_marker(&"film_box", BOX_AT)
	map.add_marker(&"printer", PRINTER_AT)
	map.add_marker(&"board", BOARD_AT)
	map.add_marker(&"film", FILM_AT)
	map.add_marker(&"photo", TRAY_AT)
	return {Harness.LOBBY: lobby, STUDIO: map}
