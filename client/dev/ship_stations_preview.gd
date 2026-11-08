extends Node3D
## A preview of the ship stations' extras (#1556, ARCHITECTURE §9.5.27) for `tools\run.cmd shot`:
## the estate's ship room (`levels/estate/rooms/ship.tscn`, the art ship, read only) with every
## engine station placed at its marker, driven by ShipEngineViews from a fake ClientModel, as
## ship_station_looks_ship_test places them. `view` picks the close-up: "board" (a breaker chain
## open with two shells tripped: their cores smoke), "socket" (its crystal charged),
## "socket_spent" (a crystal problem holds it), "charger" (half way through a charge: the arcs)
## or "flash" (the frame after a charge's end). Dev only, nothing here reaches the game.

const Preview := preload("res://client/dev/screen_preview.gd")
const ROOM := "res://levels/estate/rooms/ship.tscn"
const SPAWN := "spawn_"
const NOW := 2000
const FRAME_S := 0.05
const ITEM := 7

@export var view := "board"

var _model: ClientModel
var _views: ShipEngineViews
var _first: Dictionary[StringName, int] = {}


func _ready() -> void:
	var mode := load(Preview.MODE) as GameMode
	_model = ClientModel.new(mode)
	_model.own_peer = 1
	var phase := PhaseChangedEvent.new(&"round", NOW + 60000)
	_model.fold(phase.event_name(), phase.to_dict())
	var room := (load(ROOM) as PackedScene).instantiate() as Node3D
	room.name = "Level"
	add_child(room)
	_build_sky()
	_place(room)
	_views = ShipEngineViews.new()
	_views.model = _model
	_views.mode = mode
	_views.host_tick = func() -> int: return NOW
	add_child(_views)
	_views.level = room
	_views._process(0.0)
	var looks := _views.station_looks()
	var camera := Camera3D.new()
	add_child(camera)
	match view:
		"socket", "socket_spent":
			_socket(camera, looks)
		"charger", "flash":
			_charger(camera, looks, mode)
		_:
			_board(camera, looks)
	camera.current = true


func _board(camera: Camera3D, looks: ShipStationLooks) -> void:
	var board_id: int = _first[&"breaker_board"]
	var order: Array[int] = []
	for id: int in _model.stations:
		if looks.board_station_of(id) == board_id:
			order.append(id)
	order.sort_custom(func(a: int, b: int) -> bool: return looks.shell_of(a) < looks.shell_of(b))
	_model.fold(
		&"EngineProblemOpened",
		{"problem": 1, "stations": PackedInt32Array([board_id]), "deadline": NOW + 6000}
	)
	_model.fold(
		&"BreakerChain", {"problem": 1, "breakers": PackedInt32Array(order), "next": 2, "since": -1}
	)
	_run(1.2)
	var board := looks.board_of(board_id)
	var root := board.smoke().emitter(0).get_parent() as Node3D
	var t := root.global_transform
	camera.look_at_from_position(t * Vector3(0.35, 1.05, 1.1), t * Vector3(0.15, 0.85, 0.15))


func _socket(camera: Camera3D, looks: ShipStationLooks) -> void:
	var socket_id: int = _first[&"cartridge_socket"]
	if view == "socket_spent":
		_model.fold(
			&"EngineProblemOpened",
			{"problem": 1, "stations": PackedInt32Array([socket_id]), "deadline": NOW + 6000}
		)
	_run(0.5)
	# The socket device: the kit instance the crystal's anchor sits under.
	var root: Node = looks.socket_of(socket_id).crystal().node()
	while root != null and not root.scene_file_path.ends_with("crystal_socket.tscn"):
		root = root.get_parent()
	var t := (root as Node3D).global_transform
	camera.look_at_from_position(t * Vector3(0.45, 1.6, 0.9), t * Vector3(0.0, 1.2, 0.0))


func _charger(camera: Camera3D, looks: ShipStationLooks, mode: GameMode) -> void:
	var socket_id: int = _first[&"cartridge_socket"]
	var charger_id: int = _first[&"cartridge_charger"]
	var ticks := 600
	for kind: ProblemKind in ShipEngineClient.types_of(mode)[0].kinds:
		if kind is CrystalProblem:
			ticks = (kind as CrystalProblem).charge_ticks()
	_model.fold(
		&"EngineProblemOpened",
		{"problem": 1, "stations": PackedInt32Array([socket_id]), "deadline": NOW + 60000}
	)
	var charging := {
		"station": socket_id,
		"charger": charger_id,
		"phase": CrystalProblem.CHARGING,
		"item": ITEM,
		"tick": NOW + floori(ticks / 2.0),
	}
	_model.fold(&"CrystalChanged", charging)
	_run(1.0)
	if view == "flash":
		var waiting := charging.duplicate()
		waiting["phase"] = CrystalProblem.WAITING
		waiting["tick"] = -1
		_model.fold(&"CrystalChanged", waiting)
		_run(0.1)
	var root := looks.charger_of(charger_id).zap().node().get_parent() as Node3D
	var t := root.global_transform
	camera.look_at_from_position(t * Vector3(0.7, 1.55, 1.3), t * Vector3(0.0, 1.05, 0.0))


## Every station of the room at its `spawn_<kind>` marker, as the host places them.
func _place(room: Node3D) -> void:
	var id := 1
	for node: Node in room.find_children("*", "Marker3D", true, false):
		for group: StringName in node.get_groups():
			if not String(group).begins_with(SPAWN):
				continue
			var kind := StringName(String(group).trim_prefix(SPAWN))
			var fields := {
				"station": id,
				"kind": kind,
				"colour": Color.WHITE,
				"position": (node as Marker3D).global_position,
			}
			_model.fold(&"StationPlaced", fields)
			if not _first.has(kind):
				_first[kind] = id
			id += 1


func _run(seconds: float) -> void:
	for i in roundi(seconds / FRAME_S):
		_views._process(FRAME_S)


## A dim hall light and some ambient, so the smoke, the arcs and the crystal's glow show.
func _build_sky() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.8, 0)
	sun.light_energy = 0.3
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.09, 0.12)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.3, 0.3, 0.34)
	environment.environment.glow_enabled = true
	add_child(environment)
