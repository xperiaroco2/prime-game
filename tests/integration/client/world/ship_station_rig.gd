extends RefCounted
## The level and the events of the station looks' suites (#1550, #1556): a level of the art console,
## a crystal socket, two breaker boards and two crystal chargers, the stations ShipEngineViews binds
## to them, and the engine's events a test folds.

const CONSOLE_GLB := preload("res://assets/environment/start_console/start_console.glb")
const SOCKET_KIT := preload("res://levels/kit/crystal_socket/crystal_socket.tscn")
const BOARD_KIT := preload("res://levels/kit/breaker_board/breaker_board.tscn")
const CHARGER_KIT := preload("res://levels/kit/crystal_charger/crystal_charger.tscn")
const INSIDE_LAMP := "InsideLamp"
const CONSOLE := 1
const GILLS := 2
const BOARD_EAST := 3
const BOARD_WEST := 4
## Breakers 5 to 8 hang by the east board, 9 to 12 by the west one.
const FIRST_BREAKER := 5
const SOCKET := 13
const CHARGER := 14
const CHARGER_WEST := 15


## The devices' level, a child of `suite` (auto-freed).
static func devices(suite: GdUnitTestSuite) -> Node3D:
	var level: Node3D = suite.auto_free(Node3D.new())
	suite.add_child(level)
	var console: Node3D = CONSOLE_GLB.instantiate()
	console.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 1.2, 0.6))
	level.add_child(console)
	_add(level, SOCKET_KIT, Vector3(1.5, 0.0, 3.1))
	_add(level, BOARD_KIT, Vector3(6.65, 1.0, -1.0))
	_add(level, BOARD_KIT, Vector3(-6.65, 1.0, -1.0))
	_add(level, CHARGER_KIT, Vector3(10.3, 3.2, 3.0))
	_add(level, CHARGER_KIT, Vector3(-10.3, 3.2, 3.0))
	# An inside light as the ship's: it reaches GROUND alone.
	var lamp := OmniLight3D.new()
	lamp.name = INSIDE_LAMP
	lamp.light_cull_mask = PhotoLayers.GROUND
	level.add_child(lamp)
	return level


## Every station of the level, folded into `model`.
static func place(model: ClientModel) -> void:
	_station(model, CONSOLE, &"engine_console", Vector3(0.0, 1.2, -0.4))
	_station(model, GILLS, &"gill_button", Vector3(2.0, 1.2, -3.0))
	_station(model, BOARD_EAST, &"breaker_board", Vector3(6.5, 1.2, -0.2))
	_station(model, BOARD_WEST, &"breaker_board", Vector3(-6.5, 1.2, -0.2))
	for i in 8:
		var side := 1.0 if i < 4 else -1.0
		var at := Vector3(side * (5.8 + 0.5 * (i % 4)), 1.2, -0.2)
		_station(model, FIRST_BREAKER + i, &"breaker", at)
	_station(model, SOCKET, &"cartridge_socket", Vector3(1.5, 1.2, 2.4))
	_station(model, CHARGER, &"cartridge_charger", Vector3(10.4, 1.2, 1.8))
	_station(model, CHARGER_WEST, &"cartridge_charger", Vector3(-10.4, 1.2, 1.8))


## The mode's crystal problem kind.
static func crystals(mode: GameMode) -> CrystalProblem:
	for kind: ProblemKind in ShipEngineClient.types_of(mode)[0].kinds:
		if kind is CrystalProblem:
			return kind as CrystalProblem
	return null


static func opened(problem: int, stations: Array[int], deadline: int) -> Dictionary:
	return {"problem": problem, "stations": PackedInt32Array(stations), "deadline": deadline}


static func chain(problem: int, order: Array[int], next: int, since: int) -> Dictionary:
	return {"problem": problem, "breakers": PackedInt32Array(order), "next": next, "since": since}


## The socket's CrystalChanged; `tick` the charge's end (-1 when not charging).
static func crystal(charger: int, phase: int, item: int, tick := -1) -> Dictionary:
	return {"station": SOCKET, "charger": charger, "phase": phase, "item": item, "tick": tick}


static func _add(level: Node3D, scene: PackedScene, at: Vector3) -> void:
	var device: Node3D = scene.instantiate()
	device.position = at
	level.add_child(device)


static func _station(model: ClientModel, id: int, kind: StringName, at: Vector3) -> void:
	model.fold(
		&"StationPlaced", {"station": id, "kind": kind, "colour": Color.WHITE, "position": at}
	)
