extends Node3D
## A preview of the photo's pictures (#787, photo P8) for `tools\run.cmd shot`: the base mode's
## photo task with the real camera, printer and board scenes of `levels/stations/`, driven by
## PhotoViews, ItemViews and PhotoPictures from a fake ClientModel. Four shots of two players (one
## downed) at the photo spot render, then four photos are printed: two hang on the board (the
## second uncounted), two lie spread on the printer's tray, and a fresh film in the camera shows
## its counter. With `picture` the screen shows the first shot's picture itself, with `character`
## the puppets wear the art's character (CharacterSet.load_default(), the game's case), with
## `close_on` ("camera/FramesLeft", "printer/Tray") the view is close on that node. Dev only,
## nothing here reaches the game.

const Preview := preload("res://client/dev/screen_preview.gd")
const SCENES := "res://levels/stations/%s.tscn"
const OWN := 1
const OTHER := 2
const CAMERA := 1
const SPOT := 2
const PRINTER := 3
const BOARD := 4
const FILM := 20
const SECOND_FILM := 21
const CAMERA_AT := Vector3(0, 0, 0)
const SPOT_AT := Vector3(0, 0, -5)
const PRINTER_AT := Vector3(2.5, 0, 1.5)
const BOARD_AT := Vector3(-2.5, 0, 1.5)
## Shots rendered and printed: two hang on the board, two lie on the tray.
const SHOTS := 4

## Show the first picture full screen instead of the room.
@export var picture := false
## The puppets wear the art's character, as in the game (needs the Git LFS content).
@export var character := false
## Look close at this node, "<station scene>/<node>", instead of the room; empty: the room.
@export var close_on := ""

var _model: ClientModel
var _pictures := PhotoPictures.new()
var _level := Node3D.new()
var _step := 0
var _shown: TextureRect
var _scenes: Dictionary[StringName, Node3D] = {}
var _avatars: AvatarViews


func _ready() -> void:
	var mode := load(Preview.MODE) as GameMode
	_model = ClientModel.new(mode)
	_model.own_peer = OWN
	_fold(PhaseChangedEvent.new(&"round", 100000))
	add_child(_level)
	_room()
	var stations: Array[Array] = [
		[CAMERA, &"camera", CAMERA_AT, 0.0],
		[SPOT, &"photo_spot", SPOT_AT, 0.0],
		[PRINTER, &"printer", PRINTER_AT, 0.0],
		[BOARD, &"photo_board", BOARD_AT, 0.0],
	]
	for row: Array in stations:
		var scene := (load(SCENES % row[1]) as PackedScene).instantiate() as Node3D
		scene.position = row[2] as Vector3
		scene.rotation.y = row[3] as float
		_level.add_child(scene)
		_scenes[row[1] as StringName] = scene
		var at := (scene.get_node("UseSpot") as Node3D).global_position
		var kind := row[1] as StringName
		_fold(StationPlacedEvent.new(row[0] as int, kind, Color.WHITE, at))
	var flashes := PhotoFlashes.new()
	flashes.model = _model
	flashes.lens_m = mode.player_rules.eye_height_m
	add_child(flashes)
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
	_pictures.flashes = flashes
	if character:
		_avatars = AvatarViews.new()
		_avatars.character = CharacterSet.load_default()
		_pictures.avatars = _avatars
	add_child(_pictures)
	_fold(ItemSpawnedEvent.new(FILM, &"film", CAMERA_AT))
	_fold(ItemPickedUpEvent.new(OWN, FILM))
	_fold(FilmLoadedEvent.new(CAMERA, FILM))
	var rows: Array[Dictionary] = [
		_row(OWN, SPOT_AT + Vector3(-0.6, 0, 0), Vector3.BACK, false),
		_row(OTHER, SPOT_AT + Vector3(0.7, 0, -0.4), Vector3.LEFT, true),
	]
	for shot in SHOTS:
		# The first shot has both players, the others one of them in turn.
		var record: Array[Dictionary] = rows.duplicate()
		if shot > 0:
			record = [rows[shot % 2]]
		var event := ShotTakenEvent.new(CAMERA, FILM, shot, record)
		_fold(event)
		flashes.on_event(event.event_name(), event.to_dict())
		_pictures.on_event(event.event_name(), event.to_dict())
	var camera := Camera3D.new()
	add_child(camera)
	if not close_on.is_empty():
		var parts := close_on.split("/")
		var node := _scenes[StringName(parts[0])].get_node(parts[1]) as Node3D
		var at := node.global_position
		camera.look_at_from_position(at + node.global_basis.z * 0.6 + Vector3.UP * 0.3, at)
	else:
		camera.look_at_from_position(Vector3(0, 2.2, 5.5), Vector3(0, 1.0, 0))
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	_shown = TextureRect.new()
	_shown.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_shown.visible = picture
	layer.add_child(_shown)


func _process(_delta: float) -> void:
	if _step == 0 and _pictures.count() == SHOTS:
		_step = 1
		var tray := (_scenes[&"printer"].get_node("Tray") as Node3D).global_position
		for i in SHOTS:
			_fold(ItemSpawnedEvent.new(50 + i, &"photo", tray))
			_fold(PhotoPrintedEvent.new(50 + i, i))
		_fold(ItemVanishedEvent.new(FILM))
		for i in 2:
			_fold(ItemPickedUpEvent.new(OWN, 50 + i))
			_fold(PhotoHungEvent.new(50 + i, BOARD, i == 0))
		_fold(ItemSpawnedEvent.new(SECOND_FILM, &"film", CAMERA_AT))
		_fold(ItemPickedUpEvent.new(OWN, SECOND_FILM))
		_fold(FilmLoadedEvent.new(CAMERA, SECOND_FILM))
	if picture and _step == 1:
		_shown.texture = _pictures.texture_of(0)


func _exit_tree() -> void:
	if _avatars != null:
		_avatars.free()


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
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.65, 0.75)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	add_child(environment)
