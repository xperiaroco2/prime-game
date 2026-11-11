extends Node3D
## A preview of the ship stations' extras (#1556, ARCHITECTURE §9.5.27) for `tools\run.cmd shot`:
## the estate's ship room (`levels/estate/rooms/ship.tscn`, the art ship, read only) with every
## engine station placed at its marker, driven by ShipEngineViews from a fake ClientModel, as
## ship_station_looks_ship_test places them. `view` picks the close-up: "board" (a breaker chain
## open with two shells tripped: their cores smoke), "socket" (its crystal charged),
## "socket_spent" (a crystal problem holds it), "charger" (half way through a charge: the arcs)
## or "flash" (the frame after a charge's end); and the engine made readable (#1500, GDD §8):
## "call" (the engine off: the turbines' pulse and the start button's glow at a pulse's height),
## "call_dim" (the same a second later, between pulses), "wiring" (started,
## the bar half full on the ring, two problems open: their lines dark, the countdown to the
## nearest), "steam" (a gills problem, two slits just opened) or "mist" (all five open, fixed).
## Dev only, nothing here reaches the game.

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
## The host tick drawn: "call_dim" a second after "call", between two pulses.
var _now := NOW


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
	# The console's call starts a pulse every PULSE_SECONDS from 0.75 s (ShipStationLooks), up by
	# a twentieth of the period: tick 1997 is its height, a second later its rest.
	if view == "call":
		_now = NOW - 3
	elif view == "call_dim":
		_now = NOW - 3 + Ticks.RATE
	_views.host_tick = func() -> int: return _now
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
		"call", "call_dim", "wiring":
			_hologram(camera, room, looks)
		"steam", "mist":
			_gills(camera, room)
		_:
			_board(camera, looks)
	camera.current = true


func _board(camera: Camera3D, looks: ShipStationLooks) -> void:
	var board_id: int = _first[&"breaker_board"]
	var order := _breakers_of(board_id, looks)
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


## The console's hologram from the hall's throat side: "call" leaves the engine off; "wiring"
## presses the start, fills half the bar and opens a problem at a socket and one at a breaker
## board (with its chain, as the host sends it), the socket's the nearest deadline.
func _hologram(camera: Camera3D, room: Node3D, looks: ShipStationLooks) -> void:
	var console: int = _first[&"engine_console"]
	var board_id: int = _first[&"breaker_board"]
	if view == "wiring":
		_model.fold(&"ButtonPressed", {"station": console})
		_model.fold(
			&"ZoneProgress",
			{"station": console, "ticks": 900, "needed": 1800, "counting": false, "tick": NOW}
		)
		var sites: Array[int] = [_first[&"cartridge_socket"], board_id]
		for i in sites.size():
			var fields := {
				"problem": i + 1,
				"stations": PackedInt32Array([sites[i]]),
				"deadline": NOW + 460 + 300 * i,
			}
			_model.fold(&"EngineProblemOpened", fields)
		var chain := {
			"problem": 2,
			"breakers": PackedInt32Array(_breakers_of(board_id, looks)),
			"next": 0,
			"since": -1,
		}
		_model.fold(&"BreakerChain", chain)
	_run(0.5)
	var centre := room.get_tree().get_first_node_in_group(&"engine_hologram") as Node3D
	var at := centre.global_position
	camera.look_at_from_position(at + Vector3(0.0, 0.55, -1.7), at + Vector3(0.0, -0.05, 0.0))


## The first gill set: a gills problem opened at every gill button (whichever the view binds the
## set to), then "steam" opens two slits (their puffs a moment later) and "mist" all five and
## fixes it (the cloud a moment later). No puff or cloud is an error: the shot would prove nothing.
func _gills(camera: Camera3D, room: Node3D) -> void:
	var gills := room.get_tree().get_first_node_in_group(&"engine_gills") as Node3D
	var buttons: Array[int] = []
	for id: int in _model.stations:
		if _model.stations[id].kind == &"gill_button":
			buttons.append(id)
	for i in buttons.size():
		var fields := {
			"problem": i + 1, "stations": PackedInt32Array([buttons[i]]), "deadline": NOW + 6000
		}
		_model.fold(&"EngineProblemOpened", fields)
	_run(0.2)
	var slits := [0, 1] if view == "steam" else [0, 1, 2, 3, 4]
	for i in buttons.size():
		for slit: int in slits:
			_model.fold(&"GillFlipped", {"station": buttons[i], "slit": slit, "open": true})
		if view == "mist":
			_model.fold(&"EngineProblemFixed", {"problem": i + 1})
	# The mist's particles age on real frames only: start its countdown with them.
	_run(0.3 if view == "steam" else FRAME_S)
	var shown := _views.steam().size() if view == "steam" else _views.mist().size()
	if shown == 0:
		push_error("ship_stations_preview: no %s at the gills" % view)
	var middle := Vector3.ZERO
	for slit in 5:
		middle += (gills.get_node("Slit%d" % (slit + 1)) as Node3D).global_position / 5.0
	var out := gills.global_basis.z.normalized()
	camera.look_at_from_position(middle + out * 3.2 + Vector3.UP * 0.1, middle)


## The breakers of board station `board_id`, in its shells' order.
func _breakers_of(board_id: int, looks: ShipStationLooks) -> Array[int]:
	var order: Array[int] = []
	for id: int in _model.stations:
		if looks.board_station_of(id) == board_id:
			order.append(id)
	order.sort_custom(func(a: int, b: int) -> bool: return looks.shell_of(a) < looks.shell_of(b))
	return order


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
