extends Node3D
## A preview of the zones (#650; the zone task ADR's ZD11 (b)) for `tools\run.cmd shot`: from left
## to right a zone with no progress, one counting (half full at the preview's host tick), one
## paused at three quarters and one done (full and dimmed), a delivery circle behind them, and a
## counting zone behind a wall. With `low`, the camera stands at eye height and the wall hides that
## zone and its fill (depth-tested, the M4 ADR's §3 item 5). Fed by a fake ClientModel; dev only,
## nothing here reaches the game.
##
## The zones are the client's own mode's ZoneTask when the base mode has one; until then a
## stand-in of the preview's own (radius 1.5 m, 10 s), not content and not a decision.

const Preview := preload("res://client/dev/screen_preview.gd")
## The preview's host tick: the counting zones extrapolate to it.
const NOW := 400
const STAND_IN_RADIUS := 1.5
const STAND_IN_SECONDS := 10.0
const YELLOWS: Array[Color] = [
	Color(0.95, 0.85, 0.2),
	Color(0.9, 0.75, 0.1),
	Color(1.0, 0.9, 0.4),
	Color(0.85, 0.8, 0.25),
	Color(0.95, 0.7, 0.2),
]

@export var low := false


func _ready() -> void:
	var base := load(Preview.MODE) as GameMode
	var mode := _with_zones(base)
	var model := Preview.fake_model(base, true)
	Preview.fold_round(model, false)
	_build_room()
	var zone_kind := _zone_task(mode).zone.id
	var needed := _zone_task(mode).needed_ticks()
	# id, position, ticks, counting, the event's tick
	var zones := [
		[11, Vector3(-6.0, 0, -2.0), 0, false, NOW],
		[12, Vector3(-2.0, 0, -2.0), roundi(needed * 0.5) - 20, true, NOW - 20],
		[13, Vector3(2.0, 0, -2.0), roundi(needed * 0.75), false, NOW - 40],
		[14, Vector3(6.0, 0, -2.0), needed, false, NOW - 60],
		[15, Vector3(0.0, 0, -12.5), roundi(needed * 0.5), true, NOW],
	]
	for i in zones.size():
		var zone: Array = zones[i]
		model.fold(
			&"StationPlaced",
			{"station": zone[0], "kind": zone_kind, "colour": YELLOWS[i], "position": zone[1]}
		)
		if zone[2] as int > 0:
			(
				model
				. fold(
					&"ZoneProgress",
					{
						"station": zone[0],
						"ticks": zone[2],
						"needed": needed,
						"counting": zone[3],
						"tick": zone[4],
					}
				)
			)
	model.fold(
		&"StationPlaced",
		{
			"station": 16,
			"kind": &"circle",
			"colour": Color(0.25, 0.45, 0.95),
			"position": Vector3(4.0, 0, -6.5)
		}
	)
	var circles := CircleViews.new()
	circles.model = model
	circles.mode = mode
	add_child(circles)
	var views := ZoneViews.new()
	views.model = model
	views.mode = mode
	views.host_tick = func() -> int: return NOW
	add_child(views)
	var camera := Camera3D.new()
	if low:
		camera.transform = Transform3D(Basis.from_euler(Vector3(-0.12, 0, 0)), Vector3(0, 1.6, 6))
	else:
		camera.transform = Transform3D(Basis.from_euler(Vector3(-0.95, 0, 0)), Vector3(0, 13.0, 3))
	add_child(camera)
	camera.current = true


## `base` itself when it has a ZoneTask; else a mode with its task types and the stand-in.
static func _with_zones(base: GameMode) -> GameMode:
	if _zone_task(base) != null:
		return base
	var mode := GameMode.new()
	mode.task_types.append_array(base.task_types)
	var kind := StationKind.new()
	kind.id = &"zone"
	kind.radius_m = STAND_IN_RADIUS
	kind.height_m = 2.5
	var task := ZoneTask.new()
	task.id = &"zone"
	task.zone = kind
	task.seconds = STAND_IN_SECONDS
	mode.task_types.append(task)
	return mode


static func _zone_task(mode: GameMode) -> ZoneTask:
	for type: TaskType in mode.task_types:
		if type is ZoneTask:
			return type as ZoneTask
	return null


## A floor, a wall in front of the last zone, light and a sky.
func _build_room() -> void:
	_box(Vector3(0, -0.05, -5), Vector3(20, 0.1, 20), Color(0.45, 0.45, 0.47))
	_box(Vector3(0, 1.5, -8.5), Vector3(6, 3, 0.3), Color(0.6, 0.58, 0.55))
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


func _box(at: Vector3, size: Vector3, colour: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	mesh.material = material
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.position = at
	add_child(view)
