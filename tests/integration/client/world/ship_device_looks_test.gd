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


## The crystal as an item (#1672): lying, thrown or in another player's hands it is its own model
## at the kind's charge, not the labelled box; its light skips the stations and the first-person
## hands, and the whole look follows the item's layer.
func test_an_item_crystal_is_the_model_at_its_charge() -> void:
	if ShipDeviceArt.missing(self, true):
		return
	for kind: StringName in ItemView.CRYSTAL_CHARGE:
		var view: ItemView = auto_free(ItemView.make(7, kind, Color.WHITE))
		var crystal := view.crystal()
		assert_object(crystal).override_failure_message(String(kind)).is_not_null()
		assert_float(crystal.charge()).is_equal(ItemView.CRYSTAL_CHARGE[kind])
		assert_object(view.look().find_child("Label", true, false)).is_null()
		assert_object(view.look().find_child("Box", true, false)).is_null()
		var mask := crystal.omni().light_cull_mask
		assert_int(mask & (PhotoLayers.STATION | PhotoLayers.HANDS)).is_zero()
		# Its light stops at walls (the photo flash's P6): a carrier behind one is not lit through.
		assert_bool(crystal.omni().shadow_enabled).is_true()
		assert_int(crystal.omni().light_bake_mode).is_equal(Light3D.BAKE_DISABLED)
		for node: Node in crystal.node().find_children("*", "GeometryInstance3D", true, false):
			assert_int((node as GeometryInstance3D).cast_shadow).is_equal(
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)
		# Its light goes with a hidden look or view (a held one, the downed camera's sight hiding).
		add_child(view)
		assert_bool(crystal.omni().is_visible_in_tree()).is_equal(kind == &"crystal_charged")
		view.show_look(false)
		assert_bool(crystal.omni().is_visible_in_tree()).is_false()
		view.show_look(true)
		view.visible = false
		assert_bool(crystal.omni().is_visible_in_tree()).is_false()
		remove_child(view)
		view.set_layer(PhotoLayers.LIVE_AVATAR)
		assert_int(PhotoLayers.layers_of(view)).is_equal(PhotoLayers.LIVE_AVATAR)
		# The model stands on the view's origin at CRYSTAL_SIZE, where the aim and the sight point
		# look for it.
		var box := _bounds(crystal.node())
		assert_float(box.position.y).is_equal_approx(0.0, 0.01)
		assert_vector(box.size).is_equal_approx(ItemView.CRYSTAL_SIZE, Vector3.ONE * 0.01)


## The spectate hand's crystal (FirstPersonHand) keeps the first-person hands' light share, as the
## carrier's own screen shows it (#1672).
func test_a_crystal_in_the_first_person_hand_keeps_the_hands_light_share() -> void:
	if ShipDeviceArt.missing(self, true):
		return
	var hand: FirstPersonHand = auto_free(FirstPersonHand.new())
	hand.show_item(&"crystal_charged", Color.WHITE, true)
	var view := hand.find_child("HandItem", false, false) as ItemView
	assert_float(view.crystal().omni().light_energy).is_equal_approx(
		ShipCrystalLook.OMNI_ENERGY * FpHands.LIGHT_SHARE, 1e-5
	)


## The merged bounds of the meshes under `root`, in its space.
func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var b: AABB = ShipStationLooks.relative(mesh, root) * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
