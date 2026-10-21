extends Node3D
## A preview of the car repair's client view (#811, the car repair ADR's §8 R7) for
## `tools\run.cmd shot`: R5's real station scenes (`levels/stations/car.tscn`, `lift_panel.tscn`,
## `parts_shelf.tscn` and `part_picture.tscn`) driven by CarRepairViews from a fake ClientModel.
## The car stands at `lift` of its rise (0: lowered, 1: fully up, its hull's underside at the
## clearance), the panel's lamp lit while the lift is held up, and three wall pictures, each
## needing one part, beside the shelf, each wearing the plate of its part's bin. With `crouch_eye`
## the camera stands beside the car at the mode's crouched eye height.
## The CarRepair is built here (R6, #810: `content/` has none yet), its clearance R5's 1.4 m
## placeholder and its rise seconds the preview's; dev only, nothing here reaches the game.

const Preview := preload("res://client/dev/screen_preview.gd")
const Kit := preload("res://client/dev/preview_kit.gd")
const SCENES := "res://levels/stations/%s.tscn"
const OWN := 1
const CAR := 1
const PANEL := 2
const FIRST_BIN := 3
const FIRST_PICTURE := 10
const PARTS: Array[StringName] = [&"spark_plug", &"filter", &"belt"]
const CLEARANCE_M := 1.4
const RISE_SECONDS := 2.0
const NOW := 2000
const CAR_AT := Vector3(0, 0, 0)
const PANEL_AT := Vector3(2.4, 0, 1.2)
const SHELF_AT := Vector3(-4.6, 0, -1.5)
## The wall pictures, left of the shelf, in `PARTS` order (as the bins are).
const PICTURES_AT: Array[Vector3] = [
	Vector3(-7.9, 0, -1.5), Vector3(-7.2, 0, -1.5), Vector3(-6.5, 0, -1.5)
]

## The car's height, 0 (lowered) to 1 (fully up): the panel is held up unless 0.
@export var lift := 1.0
@export var crouch_eye := false

var _level := Node3D.new()


func _ready() -> void:
	var mode := _mode()
	var type := CarRepairUse.types_of(mode)[0]
	var model := ClientModel.new(mode)
	model.own_peer = OWN
	_fold(model, PhaseChangedEvent.new(&"round", NOW + 2000))
	_level.name = "Level"
	add_child(_level)
	_build_room()
	Kit.place(model, CAR, &"car", _spot(_add(&"car", CAR_AT)))
	Kit.place(model, PANEL, &"lift_panel", _spot(_add(&"lift_panel", PANEL_AT)))
	var shelf := _add(&"parts_shelf", SHELF_AT)
	for i: int in PARTS.size():
		var bin := shelf.get_node("Bin%d" % (i + 1))
		Kit.place(model, FIRST_BIN + i, StringName("bin_%s" % PARTS[i]), _spot(bin))
		var picture := _add(&"part_picture", PICTURES_AT[i])
		Kit.place(model, FIRST_PICTURE + i, &"part_picture", _spot(picture))
		_fold(model, PartNeededEvent.new(FIRST_PICTURE + i, PARTS[i]))
	if lift > 0.0:
		var rise_tick := NOW - roundi(clampf(lift, 0.0, 1.0) * type.rise_ticks())
		_fold(model, LiftChangedEvent.new(PANEL, true, rise_tick))
	var views := CarRepairViews.new()
	views.model = model
	views.mode = mode
	views.host_tick = func() -> int: return NOW
	add_child(views)
	views.level = _level
	var camera := Camera3D.new()
	add_child(camera)
	if crouch_eye:
		var eye := mode.player_rules.crouch_eye_height_m
		camera.look_at_from_position(Vector3(2.6, eye, 3.2), Vector3(0, 0.9, 0))
	else:
		camera.look_at_from_position(Vector3(-2.2, 3.4, 7.4), Vector3(-2.6, 0.9, -0.5))
	camera.current = true


## Folds `event` into `model`, as the session does with what it decodes.
func _fold(model: ClientModel, event: MatchEvent) -> void:
	model.fold(event.event_name(), event.to_dict())


func _add(scene: StringName, at: Vector3) -> Node3D:
	var made := (load(SCENES % scene) as PackedScene).instantiate() as Node3D
	made.position = at
	_level.add_child(made)
	return made


func _spot(root: Node) -> Vector3:
	return (root.get_node("UseSpot") as Node3D).global_position


## A CarRepair with R5's scene tags on a copy of the base mode; its kind ids, rise seconds and
## clearance are the preview's, "not a decision".
func _mode() -> GameMode:
	var base := load(Preview.MODE) as GameMode
	var mode := base.duplicate() as GameMode
	var type := CarRepair.new()
	type.id = &"car_repair"
	type.rise_seconds = RISE_SECONDS
	type.half_width_m = 1.2
	type.clearance_m = CLEARANCE_M
	type.car = _station(&"car", &"car")
	type.lift_panel = _station(&"lift_panel", &"lift_panel")
	type.picture = _station(&"part_picture", &"part_picture")
	type.picture.display = true
	for i: int in PARTS.size():
		var part := ItemKind.new()
		part.id = PARTS[i]
		part.hands = 1
		type.parts.append(part)
		var bin := _station(StringName("bin_%s" % PARTS[i]), StringName("part_bin_%d" % (i + 1)))
		var give := GiveItem.new()
		give.kind = part
		var rule := Rule.new()
		rule.trigger = Intents.INTERACT
		rule.effects = [give]
		bin.actions = [rule]
		type.bins.append(bin)
	var types: Array[TaskType] = mode.task_types.duplicate()
	types.append(type)
	mode.task_types = types
	return mode


func _station(id: StringName, tag: StringName) -> StationKind:
	var kind := StationKind.new()
	kind.id = id
	kind.spawn_tag = tag
	return kind


func _build_room() -> void:
	Kit.box(self, Vector3(0, -0.05, 0), Vector3(20, 0.1, 16), Color(0.45, 0.45, 0.47))
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.65, 0.75)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	add_child(environment)
