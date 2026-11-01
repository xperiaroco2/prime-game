extends GdUnitTestSuite
## The four ship station looks ported from the art packages (#1550): each covers every surface of
## its device, keeps the meshes on the live cameras' layers, and holds the values it is given.

const CONSOLE := preload("res://assets/environment/start_console/start_console.glb")
const SOCKET := preload("res://levels/kit/crystal_socket/crystal_socket.tscn")
const BOARD := preload("res://levels/kit/breaker_board/breaker_board.tscn")
const CHARGER := preload("res://levels/kit/crystal_charger/crystal_charger.tscn")
const ShipDeviceArt := preload("res://tests/integration/client/world/ship_device_art.gd")


func test_each_look_covers_every_surface_and_stays_on_the_live_layers() -> void:
	if _no_art():
		return
	for scene: PackedScene in [CONSOLE, SOCKET, BOARD, CHARGER]:
		var root: Node3D = auto_free(scene.instantiate())
		var look: RefCounted = null
		match scene:
			CONSOLE:
				look = ShipConsoleLook.apply(root, 1.5)
			SOCKET:
				look = ShipSocketLook.apply(root)
			BOARD:
				look = ShipBoardLook.apply(root)
			CHARGER:
				look = ShipChargerLook.apply(root)
		assert_object(look).override_failure_message(scene.resource_path).is_not_null()
		for node: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh.mesh == null or mesh.get_parent() is CollisionObject3D:
				continue
			assert_int(mesh.layers & PhotoLayers.LIVE_VIEW).is_not_zero()
			for i: int in mesh.mesh.get_surface_count():
				(
					assert_object(mesh.get_surface_override_material(i))
					. override_failure_message("%s %s %d" % [scene.resource_path, mesh.name, i])
					. is_not_null()
				)


func test_a_look_refuses_another_device() -> void:
	var socket: Node3D = auto_free(SOCKET.instantiate())
	assert_object(ShipBoardLook.apply(socket)).is_null()
	assert_object(ShipChargerLook.apply(socket)).is_null()


func test_the_console_s_call_starts_on_its_t0_every_period() -> void:
	if _no_art():
		return
	var look := ShipConsoleLook.apply(auto_free(CONSOLE.instantiate()) as Node3D, 1.5)
	assert_float(look.call_phase()).is_equal(-1.0)
	look.set_calling(true, 0.75)
	look.set_clock(0.75)
	assert_float(look.call_phase()).is_equal_approx(0.0, 1e-5)
	look.set_clock(2.25)
	assert_float(look.call_phase()).is_equal_approx(0.0, 1e-5)
	look.set_clock(1.5)
	assert_float(look.call_phase()).is_equal_approx(0.5, 1e-5)


func test_each_broken_station_halves_the_console_s_spin() -> void:
	if _no_art():
		return
	var look := ShipConsoleLook.apply(auto_free(CONSOLE.instantiate()) as Node3D, 1.5)
	look.set_spin(1.0)
	assert_float(look.spin_rate()).is_equal_approx(1.0, 1e-5)
	look.set_station("vent_e", "broken", 2.5)
	look.set_station("socket_w", "broken", 1.0)
	assert_float(look.spin_rate()).is_equal_approx(0.25, 1e-5)
	look.set_station("vent_e", "fixed")
	assert_str(look.station_state("vent_e")).is_equal("ok")
	assert_float(look.spin_rate()).is_equal_approx(0.5, 1e-5)


func test_a_board_shell_trips_round_its_hinge_and_the_beacon_follows() -> void:
	if _no_art():
		return
	var look := ShipBoardLook.apply(auto_free(BOARD.instantiate()) as Node3D)
	look.set_shell(1, 1.0)
	look.set_lamp(1, ShipBoardLook.DARK)
	look.set_problem(true)
	assert_float(look.shell(1).rotation.x).is_equal_approx(ShipBoardLook.TRIP, 1e-5)
	assert_float(look.shell(0).rotation.x).is_equal_approx(0.0, 1e-5)
	assert_int(look.lamp_of(1)).is_equal(ShipBoardLook.DARK)
	assert_bool(look.problem()).is_true()


func test_the_shells_run_red_to_blue_along_the_board_s_x() -> void:
	if _no_art():
		return
	var look := ShipBoardLook.apply(auto_free(BOARD.instantiate()) as Node3D)
	var root := look.shell(0).owner as Node3D
	for i in 3:
		var here := ShipStationLooks.relative(look.shell(i), root).origin.x
		var next := ShipStationLooks.relative(look.shell(i + 1), root).origin.x
		assert_float(here).is_less(next)


func test_a_socket_lights_its_lamp_unless_charged_and_opens_its_claws() -> void:
	if _no_art():
		return
	var look := ShipSocketLook.apply(auto_free(SOCKET.instantiate()) as Node3D)
	assert_str(look.state()).is_equal("charged")
	assert_bool(look.lamp_lit()).is_false()
	look.set_state("empty")
	look.set_claws(1.0)
	assert_bool(look.lamp_lit()).is_true()
	assert_float(look.claws()).is_equal(1.0)


func test_a_charger_lowers_its_carrier_out_of_charging() -> void:
	if _no_art():
		return
	var look := ShipChargerLook.apply(auto_free(CHARGER.instantiate()) as Node3D)
	look.set_state("charging")
	look.set_carrier(1.0, 0.5)
	assert_float(look.carrier_rise()).is_equal(1.0)
	look.set_state("charged")
	assert_float(look.carrier_rise()).is_equal(0.0)
	assert_str(look.state()).is_equal("charged")


## Whether the packages' art is missing here (CI: LFS pointers); the test then skips.
func _no_art() -> bool:
	return ShipDeviceArt.missing(self)
