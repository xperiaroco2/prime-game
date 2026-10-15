class_name FixtureCarRepairClient
extends RefCounted
## A client's view of a dealt car repair task (#811), for the client's tests: a ClientModel of
## FixtureCarRepairModes.basic() fed the events a client receives (StationPlaced for the car, the
## lift panel, the bins and the picture, PartNeeded, TaskState, LiftChanged, FitChanged,
## PartFitted, ItemSpawned, ItemPickedUp), never `core/` state. Station ids: CAR, PANEL, FIRST_BIN
## up (in `parts` order) and PICTURE, the deal's order; kind ids are the fixture's (`car`,
## `lift_panel`, `bin_<part>`, `part_picture`; parts `spark_plug`, `filter`, `belt`).
##
## for_scenes() fits the mode to R5's station scenes (`levels/stations/`): the bins' spawn tags
## become the shelf's `part_bin_1` to `part_bin_3`, in `parts` order, and the clearance R5's
## placeholder SCENE_CLEARANCE_M, above the crouched capsule and below the standing one (the
## fixture's 1.0 m is below the crouched capsule of the base mode). Not a decision: R6 (#810) sets
## the base mode's numbers and tags.

const CAR := 1
const PANEL := 2
const FIRST_BIN := 3
const PICTURE := 6
const TASK := 1
const OWN := 1
const OTHER := 2
## The raised car's underside above its floor for the scene suites: R5's placeholder.
const SCENE_CLEARANCE_M := 1.4


## A model of `mode` (FixtureCarRepairModes.basic() when null) in its round, the own peer OWN, the
## stations placed at `car_at`, `panel_at`, `bin_spots` and `picture_at` (the fixture layout's by
## default), the task's TaskState row (none fitted of `parts` needed) and PartNeeded of `first`.
static func dealt(
	mode: GameMode = null,
	first: StringName = &"spark_plug",
	car_at: Vector3 = FixtureCarRepairModes.CAR_AT,
	panel_at: Vector3 = FixtureCarRepairModes.PANEL_AT,
	bin_spots: Array[Vector3] = FixtureCarRepairModes.BIN_SPOTS,
	picture_at: Vector3 = FixtureCarRepairModes.PICTURE_AT
) -> ClientModel:
	var game_mode := mode if mode != null else FixtureCarRepairModes.basic()
	var model := ClientModel.new(game_mode)
	model.own_peer = OWN
	fold(model, PhaseChangedEvent.new(&"round", 1000))
	place_station(model, CAR, &"car", car_at)
	place_station(model, PANEL, &"lift_panel", panel_at)
	var parts := FixtureCarRepairModes.PARTS
	for i in parts.size():
		place_station(model, FIRST_BIN + i, StringName("bin_%s" % parts[i]), bin_spots[i])
	place_station(model, PICTURE, &"part_picture", picture_at)
	fold(model, PartNeededEvent.new(PICTURE, first))
	fold(model, TaskStateEvent.new(TASK, &"car_repair", 0, parts.size()))
	return model


## `mode` fitted to R5's scenes (see the class doc); `mode` itself, changed.
static func for_scenes(mode: GameMode) -> GameMode:
	var type := FixtureCarRepairModes.type_of(mode)
	type.clearance_m = SCENE_CLEARANCE_M
	type.car.height_m = SCENE_CLEARANCE_M
	for i in type.bins.size():
		type.bins[i].spawn_tag = StringName("part_bin_%d" % (i + 1))
	return mode


## Folds `event` into `model`, as the session does with what it decodes.
static func fold(model: ClientModel, event: MatchEvent) -> void:
	model.fold(event.event_name(), event.to_dict())


## Station `id` of kind `kind` placed at `at`.
static func place_station(model: ClientModel, id: int, kind: StringName, at: Vector3) -> void:
	fold(model, StationPlacedEvent.new(id, kind, Color.WHITE, at))


## Item `id` of kind `kind` spawned and picked up by `peer` (OWN by default).
static func hold(model: ClientModel, id: int, kind: StringName, peer: int = OWN) -> void:
	fold(model, ItemSpawnedEvent.new(id, kind, Vector3(0, 0, 40)))
	fold(model, ItemPickedUpEvent.new(peer, id))


## The lift going up (`up`) or down at host tick `tick` (LiftChanged on the panel).
static func lift(model: ClientModel, up: bool, tick: int) -> void:
	fold(model, LiftChangedEvent.new(PANEL, up, tick))


## The model's estimated host tick fixed at `tick` (AvatarViews sets it in the game).
static func at_tick(model: ClientModel, tick: int) -> void:
	model.host_tick_now = func() -> int: return tick
