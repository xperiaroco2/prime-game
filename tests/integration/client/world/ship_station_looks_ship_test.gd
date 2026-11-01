extends GdUnitTestSuite
## The ship's station devices bound in the real estate ship (#1550, ARCHITECTURE §9.5.27): every
## engine station placed at its marker binds to a device of its own, each board's four breakers to
## its four shells, and each site to its own wiring point on the console by its side in the
## console's frame (the console turned to face the mouth: the ship's east is its -X).

const SHIP := "res://levels/estate/rooms/ship.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
const SPAWN := "spawn_"
const ShipDeviceArt := preload("res://tests/integration/client/world/ship_device_art.gd")

var _model: ClientModel
var _view: ShipEngineViews
var _markers: Dictionary[int, Marker3D] = {}


func before() -> void:
	var mode := load(BASE_MODE) as GameMode
	_model = ClientModel.new(mode)
	var ship: Node3D = auto_free((load(SHIP) as PackedScene).instantiate())
	add_child(ship)
	var id := 1
	for node: Node in ship.find_children("*", "Marker3D", true, false):
		for group: StringName in node.get_groups():
			if not String(group).begins_with(SPAWN):
				continue
			var marker := node as Marker3D
			_markers[id] = marker
			var fields := {
				"station": id,
				"kind": StringName(String(group).trim_prefix(SPAWN)),
				"colour": Color.WHITE,
				"position": marker.global_position,
			}
			_model.fold(&"StationPlaced", fields)
			id += 1
	_view = auto_free(ShipEngineViews.new())
	_view.model = _model
	_view.mode = mode
	_view.host_tick = func() -> int: return 0
	_view.level = ship
	add_child(_view)
	_view._process(0.0)


func test_every_station_binds_to_a_device_of_its_own() -> void:
	if _no_art():
		return
	var looks := _view.station_looks()
	assert_object(looks.console()).is_not_null()
	var sockets: Array[ShipSocketLook] = []
	var boards: Array[ShipBoardLook] = []
	var chargers: Array[ShipChargerLook] = []
	for id: int in _markers:
		match _kind(id):
			&"cartridge_socket":
				assert_object(looks.socket_of(id)).is_not_null()
				assert_bool(sockets.has(looks.socket_of(id))).is_false()
				sockets.append(looks.socket_of(id))
			&"breaker_board":
				assert_object(looks.board_of(id)).is_not_null()
				assert_bool(boards.has(looks.board_of(id))).is_false()
				boards.append(looks.board_of(id))
			&"cartridge_charger":
				assert_object(looks.charger_of(id)).is_not_null()
				assert_bool(chargers.has(looks.charger_of(id))).is_false()
				chargers.append(looks.charger_of(id))
	assert_int(sockets.size()).is_equal(4)
	assert_int(boards.size()).is_equal(2)
	assert_int(chargers.size()).is_equal(2)


func test_each_board_s_four_breakers_take_its_four_shells_and_lamps_of_their_colour() -> void:
	if _no_art():
		return
	var looks := _view.station_looks()
	var shells: Dictionary[int, Array] = {}
	for id: int in _markers:
		if _kind(id) != &"breaker":
			continue
		var board := looks.board_station_of(id)
		assert_int(board).is_not_equal(-1)
		if not shells.has(board):
			shells[board] = []
		shells[board].append(looks.shell_of(id))
		var wing := 4 if looks.slot_of(board) == "breaker_e" else 0
		assert_int(looks.lamp_of(id)).is_equal(wing + looks.shell_of(id))
	assert_int(shells.size()).is_equal(2)
	for board: int in shells:
		var taken: Array = shells[board]
		taken.sort()
		assert_array(taken).is_equal([0, 1, 2, 3])


func test_each_site_takes_its_own_wiring_point_by_its_side_and_end() -> void:
	if _no_art():
		return
	var looks := _view.station_looks()
	var console := _first(&"engine_console")
	var taken: Array[String] = []
	for id: int in _markers:
		var slot := looks.slot_of(id)
		if slot == "":
			continue
		assert_bool(taken.has(slot)).override_failure_message(slot).is_false()
		taken.append(slot)
		var at := _markers[id].global_position - _markers[console].global_position
		# The ship's east is +X; the console's front faces -Z, where the front sockets stand.
		assert_str(slot.right(1)).is_equal("e" if at.x > 0.0 else "w")
		if _kind(id) == &"cartridge_socket":
			assert_bool(slot.begins_with("socket_f")).is_equal(at.z < 0.0)
	assert_int(taken.size()).is_equal(8)


func _kind(id: int) -> StringName:
	return _model.stations[id].kind


func _first(kind: StringName) -> int:
	for id: int in _markers:
		if _kind(id) == kind:
			return id
	return -1


## Whether the packages' art is missing here (CI: LFS pointers); the test then skips.
func _no_art() -> bool:
	return ShipDeviceArt.missing(self)
