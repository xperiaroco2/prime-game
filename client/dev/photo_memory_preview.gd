extends Node3D
## The photo pictures' memory (#787, photo P8; the photo ADR PE15) measured for
## `tools\run.cmd shot client/dev/photo_memory_preview.tscn --frames 450`: the base mode's camera
## and photo spot scenes, a fake ClientModel and the real PhotoPictures, PhotoFlashes, PhotoViews
## and ItemViews. 224 shots of two players render, one a frame: PE15's worst case with the
## placeholders (32 films x 5 unprinted frames plus 64 photos). The numbers are taken before any
## render, at 20 pictures kept (about a normal match), at 224, and then with 64 photos printed from
## distinct shots lying in view of the camera (each one's texture decoded). They are shown on
## screen and printed (tools/out/logs/shot.log). Dev only, nothing here reaches the game.

const Preview := preload("res://client/dev/screen_preview.gd")
const SCENES := "res://levels/stations/%s.tscn"
const OWN := 1
const OTHER := 2
const CAMERA := 1
const SPOT := 2
const CAMERA_AT := Vector3(0, 0, -2)
const SPOT_AT := Vector3(0, 0, -7)
## PE15's worst case: 32 films x 5 frames plus 64 photos.
const WORST := 224
const NORMAL := 20
const FRAMES := 5
const PHOTOS := 64
const FIRST_FILM := 100
const FIRST_PHOTO := 300
## Frames the window draws before the first measure, and the photo views get to ask for their
## textures before the last.
const SETTLE_FRAMES := 30

var _model: ClientModel
var _pictures := PhotoPictures.new()
var _level := Node3D.new()
var _label: Label
var _lines: Array[String] = []
var _stage := -1
var _start_ms := 0
var _settle := 0
var _flashes: PhotoFlashes


func _ready() -> void:
	var mode := load(Preview.MODE) as GameMode
	_model = ClientModel.new(mode)
	_model.own_peer = OWN
	_fold(PhaseChangedEvent.new(&"round", 100000))
	add_child(_level)
	_room()
	for row: Array in [[CAMERA, &"camera", CAMERA_AT], [SPOT, &"photo_spot", SPOT_AT]]:
		var scene := (load(SCENES % row[1]) as PackedScene).instantiate() as Node3D
		scene.position = row[2] as Vector3
		_level.add_child(scene)
		var at := (scene.get_node("UseSpot") as Node3D).global_position
		_fold(StationPlacedEvent.new(row[0] as int, row[1] as StringName, Color.WHITE, at))
	_flashes = PhotoFlashes.new()
	_flashes.model = _model
	_flashes.lens_m = mode.player_rules.eye_height_m
	add_child(_flashes)
	var views := PhotoViews.new()
	views.model = _model
	views.mode = mode
	add_child(views)
	views.level = _level
	var items := ItemViews.new()
	items.model = _model
	items.mode = mode
	items.station_point = views.drawn_point
	items.pictures = _pictures
	add_child(items)
	_pictures.model = _model
	_pictures.mode = mode
	_pictures.flashes = _flashes
	add_child(_pictures)
	var camera := Camera3D.new()
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 3.0, 4.0), Vector3(0, 0, 1.2))
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 16)
	layer.add_child(_label)


func _process(_delta: float) -> void:
	_settle += 1
	if _stage == -1 and _settle >= SETTLE_FRAMES:
		_stage = 0
		_settle = 0
		_measure("before any render")
		_start_ms = Time.get_ticks_msec()
		_shoot()
	elif _stage == 0 and _pictures.count() >= NORMAL:
		_stage = 1
		_measure("%d pictures kept (a normal match), renders going on" % NORMAL)
	elif _stage == 1 and _pictures.count() >= WORST and _pictures.pending() == 0:
		_stage = 2
		_settle = 0
		_measure("%d pictures kept, the last render in hand" % WORST)
	elif _stage == 2 and _settle >= SETTLE_FRAMES:
		_stage = 3
		_measure("%d pictures kept (PE15's worst case), no render" % WORST)
		_print_photos()
		_settle = 0
	elif _stage == 3 and _settle >= SETTLE_FRAMES:
		_stage = 4
		_measure("%d pictures kept, %d photos drawn in view" % [WORST, PHOTOS])


## Folds and forwards WORST shots of two players at the spot, five to a film.
func _shoot() -> void:
	var rows: Array[Dictionary] = [
		_row(OWN, SPOT_AT + Vector3(-0.6, 0, 0), Vector3.BACK, false),
		_row(OTHER, SPOT_AT + Vector3(0.7, 0, -0.4), Vector3.LEFT, true),
	]
	for shot in WORST:
		var film := FIRST_FILM + floori(shot / float(FRAMES))
		var event := ShotTakenEvent.new(CAMERA, film, shot, rows)
		_fold(event)
		_flashes.on_event(event.event_name(), event.to_dict())
		_pictures.on_event(event.event_name(), event.to_dict())


## Prints PHOTOS photos of the last shots (no film lists them any more, the photos keep them),
## lying in an 8 x 8 grid in view of the camera.
func _print_photos() -> void:
	for i in PHOTOS:
		var id := FIRST_PHOTO + i
		var at := Vector3((i % 8 - 3.5) * 0.3, 0.0, 1.2 + (floori(i / 8.0) - 3.5) * 0.3)
		_fold(ItemSpawnedEvent.new(id, &"photo", at))
		_fold(PhotoPrintedEvent.new(id, WORST - PHOTOS + i))


func _measure(what: String) -> void:
	var decoded := 0
	for shot in WORST:
		if _pictures.has_texture(shot):
			decoded += 1
	var line := (
		"%s: %d kept, %.1f KB JPEG, %d decoded, static %.1f MB, texture memory %.1f MB, %d ms"
		% [
			what,
			_pictures.count(),
			_pictures.bytes_kept() / 1024.0,
			decoded,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
			Time.get_ticks_msec() - _start_ms if _start_ms > 0 else 0,
		]
	)
	print("photo memory: ", line)
	_lines.append(line)
	_label.text = "\n".join(_lines)


func _row(peer: int, at: Vector3, facing: Vector3, downed: bool) -> Dictionary:
	return {
		"peer": peer,
		"position": at,
		"facing": facing,
		"downed": downed,
		"crouched": false,
		"held_item": -1,
		"belt_item": -1,
		"belt_item2": -1,
	}


func _fold(event: MatchEvent) -> void:
	_model.fold(event.event_name(), event.to_dict())


func _room() -> void:
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(14, 0.1, 16)
	var view := MeshInstance3D.new()
	view.mesh = floor_mesh
	view.position = Vector3(0, -0.05, -2)
	add_child(view)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.65, 0.75)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	add_child(environment)
