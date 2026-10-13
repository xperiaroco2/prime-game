class_name FixtureWireCarRepair
extends RefCounted
## The fixture mode, map and CarRepair of the car repair wire test (#813, car repair R9; the car
## repair ADR's §7 "The wire, without bots"; its suite
## tests/integration/server/host_session_car_repair_test.gd), built in code (a part's tests
## never load `content/`, ARCHITECTURE §9.6). Its ids and numbers are fixture values
## (FixtureCarRepairModes'), not the engineer's provisional ones.
##
## mode(): the harness's fixture mode (FixtureBaseMode's phases with res:// levels) on the one map
## GARAGE, its `all_loaded` row placing the players in peer-id order onto the `round_player`
## markers in level order (PlacePlayers' `ordered`, so each test chooses who stands where), with
## the settings `tasks` (1), `banned_task_types` and `car_parts` (PARTS_NEEDED, 0 to MAX_PARTS),
## car_repair_type() playing on GARAGE only (`TaskType.maps`), the deal (DealTasks) first on
## `loading, all_loaded -> pregame`, StopRaise's rule (Channeling), and Round accepting Interact and
## StopRaise from the living and listing LifeTicks with a Respawn (the mode check's rule for a type
## that kills, RE6), then ChannelTicks.
##
## layouts(): the harness's lobby and GARAGE with the base mode's knife and circle markers (its
## demands), the respawn markers, the car repair's markers and the `round_player` markers `spots`
## (PANEL_SPOT, FIT_SPOT, BOX_SPOT, OUT_SPOT by default): so no client walks.

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

## The fixture map: the one path in the mode's `maps`, the layouts' keys and CarRepair's `maps`.
const GARAGE := "res://tests/fixtures/server/garage.tscn"
## The parts the deal draws (the `car_parts` setting's default), and its most.
const PARTS_NEEDED := 2
const MAX_PARTS := 3
## The least cap CarRepair.check allows: twice the mode's 4 players, MAX_PARTS, 1.
const CAP := 12
## The bins' cylinder radius: every bin holds FIT_SPOT.
const BIN_REACH_M := 3.0
## A bin's take: FixtureCarRepairModes.TAKE_SECONDS, 5 host ticks at 20 Hz.
const TAKE_TICKS := 5
## The car's footprint box: |x| up to FixtureCarRepairModes.HALF_WIDTH_M (1.2 m), z from 28 to 32.
const CAR_AT := FixtureCarRepairModes.CAR_AT
const CAR_END_AT := FixtureCarRepairModes.CAR_END_AT
const PANEL_AT := Vector3(4, 0, 30)
const BIN_SPOTS: Array[Vector3] = [Vector3(-1.5, 0, 29), Vector3(-1.5, 0, 30), Vector3(-1.5, 0, 31)]
const PICTURE_AT := Vector3(0, 0, 40)
## In the panel's 1 m cylinder, outside the box.
const PANEL_SPOT := Vector3(3.5, 0, 30)
## Under the car: in the car's 1 m cylinder, inside the box, and in every bin's reach.
const FIT_SPOT := Vector3(0.5, 0, 30)
## Inside the box, out of the car's cylinder.
const BOX_SPOT := Vector3(0, 0, 31.5)
## Outside the box and every station's cylinder.
const OUT_SPOT := Vector3(7, 0, 30)
const SPOTS: Array[Vector3] = [PANEL_SPOT, FIT_SPOT, BOX_SPOT, OUT_SPOT]


static func mode() -> GameMode:
	var made := Harness.fixture_mode()
	made.maps = PackedStringArray([GARAGE])
	made.settings.append(FixtureModes.setting(&"tasks", 1, 1, 1))
	made.settings.append(FixtureDealModes.banned_setting())
	made.settings.append(FixtureModes.setting(&"car_parts", PARTS_NEEDED, 0, MAX_PARTS))
	var type := car_repair_type()
	made.task_types = [type]
	made.item_kinds.append_array(type.parts)
	made.actions.append(FixtureCombatModes.stop_raise_rule())
	var loaded := made.find_transition(&"loading", LoadingPhase.ALL_LOADED)
	for action: RuleEffect in loaded.actions:
		if action is PlacePlayers:
			(action as PlacePlayers).ordered = true
	loaded.actions.insert(0, FixtureDealModes.deal_tasks())
	var round_phase := made.find_phase(&"round")
	for intent: StringName in [Intents.INTERACT, Intents.STOP_RAISE]:
		round_phase.accepts.append(AcceptSpec.of(intent, AcceptSpec.From.LIVING))
	var life := LifeTicks.new()
	life.respawn = FixtureCombatModes.respawn()
	round_phase.tick_systems.append(life)
	round_phase.tick_systems.append(ChannelTicks.new())
	return made


## FixtureCarRepairModes' CarRepair on GARAGE only, its parts capped at CAP and its bins reaching
## BIN_REACH_M.
static func car_repair_type() -> CarRepair:
	var made := FixtureCarRepairModes.car_repair_type()
	made.maps = PackedStringArray([GARAGE])
	for part: ItemKind in made.parts:
		part.max_items = CAP
	for bin: StationKind in made.bins:
		bin.radius_m = BIN_REACH_M
	return made


## The harness's lobby and GARAGE (the class comment), with `spots` as its round_player markers in
## level order: the i-th player in peer-id order stands on the i-th.
static func layouts(spots: Array[Vector3] = SPOTS) -> Dictionary[String, LevelLayout]:
	var lobby: LevelLayout = Harness.layouts()[Harness.LOBBY]
	var map := LevelLayout.new(GARAGE)
	for spot: Vector3 in spots:
		map.add_marker(&"round_player", spot)
	for i in 3:
		map.add_marker(&"knife", Vector3(20 + i, 0, 0))
		map.add_marker(&"circle", Vector3(30 + i, 0, 0))
	for spot: Vector3 in FixtureModes.RESPAWNS:
		map.add_marker(FixtureModes.RESPAWN_TAG, spot)
	map.add_marker(&"car", CAR_AT)
	map.add_marker(&"car_end", CAR_END_AT)
	map.add_marker(&"lift_panel", PANEL_AT)
	for i in FixtureCarRepairModes.PARTS.size():
		map.add_marker(StringName("bin_%s" % FixtureCarRepairModes.PARTS[i]), BIN_SPOTS[i])
	map.add_marker(&"part_picture", PICTURE_AT)
	return {Harness.LOBBY: lobby, GARAGE: map}


## The bin's station id that gives `part_id`.
static func bin_giving(game: Match, part_id: StringName) -> int:
	var task_state := FixtureCarRepairModes.state_of(game)
	for i in FixtureCarRepairModes.PARTS.size():
		if FixtureCarRepairModes.PARTS[i] == part_id:
			return task_state.bins[i]
	return -1
