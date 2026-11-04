extends GdUnitTestSuite
## The ship stations' extras (#1556, ARCHITECTURE §9.5.27): the energy crystal in a socket and in a
## charger, the charger's lightning and the smoke at a tripped breaker core, driven by
## ShipStationLooks from a ClientModel folded from the engine's events and a host tick the test
## sets. A test of the art's nodes skips where the packages are Git LFS pointers (CI); the logic
## the looks take (charge shares, arcs, flashes, smoke emitters) runs without the art.

const BASE_MODE := "res://content/modes/base_mode.tres"
const ShipDeviceArt := preload("res://tests/integration/client/world/ship_device_art.gd")
const Rig := preload("res://tests/integration/client/world/ship_station_rig.gd")

var _mode: GameMode
var _model: ClientModel
var _view: ShipEngineViews
var _now := 0


func before_test() -> void:
	_mode = load(BASE_MODE) as GameMode
	_model = ClientModel.new(_mode)
	_now = 0
	_view = auto_free(ShipEngineViews.new())
	_view.model = _model
	_view.mode = _mode
	_view.host_tick = func() -> int: return _now
	_view.level = Rig.devices(self)
	add_child(_view)
	Rig.place(_model)
	_view._process(0.0)


func test_the_crystal_look_lights_by_its_charge() -> void:
	if _no_art():
		return
	var crystal := ShipCrystalLook.apply()
	assert_object(crystal).is_not_null()
	auto_free(crystal.node())
	for m: Node in crystal.node().find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		for i: int in mesh.mesh.get_surface_count():
			assert_object(mesh.get_surface_override_material(i)).is_not_null()
	assert_float(crystal.charge()).is_equal(1.0)
	assert_bool(crystal.omni().visible).is_true()
	assert_float(crystal.omni().light_energy).is_equal_approx(ShipCrystalLook.OMNI_ENERGY, 1e-5)
	var shell := crystal.materials()[0] as ShaderMaterial
	var light := crystal.materials()[2] as StandardMaterial3D
	assert_float(shell.get_shader_parameter("charge") as float).is_equal(1.0)
	crystal.set_charge(0.0)
	assert_bool(crystal.omni().visible).is_false()
	assert_float(shell.get_shader_parameter("charge") as float).is_equal(0.0)
	var spent := ShipCrystalLook.LIGHT_ENERGY * ShipCrystalLook.LIGHT_SPENT
	assert_float(light.emission_energy_multiplier).is_equal_approx(spent, 1e-5)
	crystal.set_charge(0.5)
	assert_float(crystal.omni().light_energy).is_equal_approx(
		ShipCrystalLook.OMNI_ENERGY * 0.5, 1e-5
	)


func test_the_socket_draws_its_crystal_charged_spent_or_not_while_it_is_out() -> void:
	if _no_art():
		return
	var socket := _view.station_looks().socket_of(Rig.SOCKET)
	var crystal := socket.crystal()
	assert_object(crystal).is_not_null()
	assert_str(String(crystal.node().get_parent().name)).is_equal("crystal_anchor")
	assert_bool(crystal.node().transform.is_equal_approx(Transform3D.IDENTITY)).is_true()
	_assert_lights_the_hull_not_the_station(crystal)
	assert_bool(crystal.shown()).is_true()
	assert_float(crystal.charge()).is_equal(1.0)
	_model.fold(&"EngineProblemOpened", Rig.opened(1, [Rig.SOCKET], 600))
	_view._process(0.1)
	assert_bool(crystal.shown()).is_true()
	assert_float(crystal.charge()).is_equal(0.0)
	_model.fold(&"CrystalChanged", Rig.crystal(-1, CrystalProblem.EMPTY, 7))
	_view._process(0.1)
	assert_bool(crystal.shown()).is_false()
	_model.fold(&"CrystalChanged", Rig.crystal(-1, CrystalProblem.EMPTY, -1))
	_model.fold(&"EngineProblemFixed", {"problem": 1})
	_view._process(0.1)
	assert_bool(crystal.shown()).is_true()
	assert_float(crystal.charge()).is_equal(1.0)


func test_the_charger_draws_the_crystal_it_holds_with_its_charge() -> void:
	if _no_art():
		return
	var looks := _view.station_looks()
	var crystal := looks.charger_of(Rig.CHARGER).crystal()
	var west := looks.charger_of(Rig.CHARGER_WEST).crystal()
	assert_object(crystal).is_not_null()
	assert_bool(crystal.shown()).is_false()
	assert_float(crystal.omni().omni_range).is_equal_approx(ShipCrystalLook.SEATED_OMNI_RANGE, 1e-5)
	_assert_lights_the_hull_not_the_station(crystal)
	_model.fold(&"EngineProblemOpened", Rig.opened(1, [Rig.SOCKET], 6000))
	_model.fold(&"CrystalChanged", Rig.crystal(Rig.CHARGER, CrystalProblem.LOADED, 7))
	_view._process(0.05)
	assert_bool(crystal.shown()).is_true()
	assert_float(crystal.charge()).is_equal(0.0)
	assert_bool(west.shown()).is_false()
	var ticks := Rig.crystals(_mode).charge_ticks()
	var ends := 400
	_model.fold(&"CrystalChanged", Rig.crystal(Rig.CHARGER, CrystalProblem.CHARGING, 7, ends))
	_now = ends - ticks + Ticks.RATE
	var rest := crystal.node().global_position
	_view._process(0.05)
	assert_float(crystal.charge()).is_equal_approx(float(Ticks.RATE) / ticks, 1e-5)
	assert_float(crystal.omni().light_energy).is_equal_approx(
		ShipCrystalLook.SEATED_OMNI_ENERGY * crystal.charge(), 1e-5
	)
	# Seated on the carrier, it rises with it.
	assert_float(crystal.node().global_position.y).is_greater(rest.y)
	_model.fold(&"CrystalChanged", Rig.crystal(Rig.CHARGER, CrystalProblem.WAITING, 7))
	_view._process(0.05)
	assert_float(crystal.charge()).is_equal(1.0)
	_model.fold(&"CrystalChanged", Rig.crystal(-1, CrystalProblem.EMPTY, 7))
	_view._process(0.05)
	assert_bool(crystal.shown()).is_false()


func test_the_charger_arcs_while_it_charges_and_flashes_once_at_its_end() -> void:
	if _no_art():
		return
	var looks := _view.station_looks()
	var zap := looks.charger_of(Rig.CHARGER).zap()
	assert_object(zap).is_not_null()
	var root := zap.node().get_parent() as Node3D
	assert_str(root.scene_file_path).is_equal(Rig.CHARGER_KIT.resource_path)
	_model.fold(&"EngineProblemOpened", Rig.opened(1, [Rig.SOCKET], 6000))
	_model.fold(&"CrystalChanged", Rig.crystal(Rig.CHARGER, CrystalProblem.LOADED, 7))
	_view._process(0.05)
	assert_bool(zap.arcing()).is_false()
	var ticks := Rig.crystals(_mode).charge_ticks()
	var ends := 400
	_model.fold(&"CrystalChanged", Rig.crystal(Rig.CHARGER, CrystalProblem.CHARGING, 7, ends))
	_now = ends - floori(ticks / 2.0)
	_view._process(0.05)
	assert_bool(zap.arcing()).is_true()
	assert_bool(zap.flashing()).is_false()
	assert_bool(looks.charger_of(Rig.CHARGER_WEST).zap().arcing()).is_false()
	# The arcs land on the crystal: within its radius of the carrier's axis.
	var crystal := looks.charger_of(Rig.CHARGER).crystal().node()
	for frame: int in 10:
		_view._process(0.05)
		var axis := ShipStationLooks.relative(crystal, root)
		for arc: PackedVector3Array in zap.ends():
			var local := axis.affine_inverse() * arc[1]
			assert_float(Vector2(local.x, local.z).length()).is_less(0.1)
	_model.fold(&"CrystalChanged", Rig.crystal(Rig.CHARGER, CrystalProblem.WAITING, 7))
	_now = ends
	_view._process(0.05)
	assert_bool(zap.flashing()).is_true()
	assert_float(looks.flash_of(Rig.CHARGER)).is_greater(0.0)
	for frame: int in 13:
		_view._process(0.05)
	assert_bool(zap.flashing()).is_false()
	assert_bool(zap.arcing()).is_false()
	assert_float(looks.flash_of(Rig.CHARGER)).is_equal(0.0)


func test_a_blast_ends_the_flash_and_a_late_view_plays_none() -> void:
	if _no_art():
		return
	var looks := _view.station_looks()
	_model.fold(&"EngineProblemOpened", Rig.opened(1, [Rig.SOCKET], 6000))
	_model.fold(&"CrystalChanged", Rig.crystal(Rig.CHARGER, CrystalProblem.CHARGING, 7, 400))
	_view._process(0.05)
	_model.fold(&"CrystalChanged", Rig.crystal(Rig.CHARGER, CrystalProblem.WAITING, 7))
	_view._process(0.05)
	assert_float(looks.flash_of(Rig.CHARGER)).is_greater(0.0)
	_model.fold(&"CrystalChanged", Rig.crystal(-1, CrystalProblem.EMPTY, -1))
	_view._process(0.05)
	assert_float(looks.flash_of(Rig.CHARGER)).is_equal(0.0)
	assert_bool(looks.charger_of(Rig.CHARGER).zap().flashing()).is_false()
	# A view built while the charger already waits saw no edge: no flash.
	_model.fold(&"CrystalChanged", Rig.crystal(Rig.CHARGER, CrystalProblem.WAITING, 7))
	var late: ShipEngineViews = auto_free(ShipEngineViews.new())
	late.model = _model
	late.mode = _mode
	late.host_tick = func() -> int: return _now
	late.level = Rig.devices(self)
	add_child(late)
	late._process(0.05)
	late._process(0.05)
	assert_float(late.station_looks().flash_of(Rig.CHARGER)).is_equal(0.0)
	assert_bool(late.station_looks().charger_of(Rig.CHARGER).zap().flashing()).is_false()


func test_a_charge_s_share_runs_from_its_start_to_its_end() -> void:
	assert_float(ShipStationLooks.charge_share(100, 300, 200)).is_equal(0.0)
	assert_float(ShipStationLooks.charge_share(50, 300, 200)).is_equal(0.0)
	assert_float(ShipStationLooks.charge_share(150, 300, 200)).is_equal(0.25)
	assert_float(ShipStationLooks.charge_share(300, 300, 200)).is_equal(1.0)
	assert_float(ShipStationLooks.charge_share(900, 300, 200)).is_equal(1.0)
	assert_float(ShipStationLooks.charge_share(0, 300, 0)).is_equal(1.0)


func test_a_tripped_core_smokes_once_its_shell_is_open_and_stops_when_it_is_on() -> void:
	if _no_art():
		return
	var looks := _view.station_looks()
	var east := looks.board_of(Rig.BOARD_EAST)
	var smoke := east.smoke()
	# Each core's emitter sits at its centre, HANDOFF.md's (u, 0.872, 0.18) in the board's frame.
	for i: int in ShipBoardLook.COLOURS.size():
		var want := Vector3(ShipBoardLook.CORE_U[i], 0.872, 0.18)
		assert_float(smoke.emitter(i).position.distance_to(want)).is_less(0.01)
	_model.fold(&"EngineProblemOpened", Rig.opened(1, [Rig.BOARD_EAST], 900))
	_model.fold(&"BreakerChain", Rig.chain(1, [5, 6, 7, 8], 2, 99))
	_now = 100
	_view._process(0.1)
	var seven := looks.shell_of(7)
	# 0.4 open: the core is still behind its shell.
	assert_bool(east.smoking(seven)).is_false()
	_view._process(0.2)
	assert_bool(east.smoking(seven)).is_true()
	assert_bool(east.smoking(looks.shell_of(8))).is_true()
	assert_bool(east.smoking(looks.shell_of(5))).is_false()
	assert_bool(east.smoking(looks.shell_of(6))).is_false()
	for i: int in 4:
		assert_bool(looks.board_of(Rig.BOARD_WEST).smoking(i)).is_false()
	# On again: the smoke stops emitting at once, while the shell is still closing.
	_model.fold(&"BreakerChain", Rig.chain(1, [5, 6, 7, 8], 3, 200))
	_now = 200
	_view._process(0.05)
	assert_float(east.open_of(seven)).is_greater(0.5)
	assert_bool(east.smoking(seven)).is_false()
	assert_bool(east.smoking(looks.shell_of(8))).is_true()


func test_a_view_built_late_shows_a_tripped_core_smoking_at_once() -> void:
	if _no_art():
		return
	_model.fold(&"EngineProblemOpened", Rig.opened(1, [Rig.BOARD_EAST], 900))
	_model.fold(&"BreakerChain", Rig.chain(1, [5, 6, 7, 8], 3, 99))
	var late: ShipEngineViews = auto_free(ShipEngineViews.new())
	late.model = _model
	late.mode = _mode
	late.host_tick = func() -> int: return _now
	late.level = Rig.devices(self)
	add_child(late)
	late._process(0.0)
	var looks := late.station_looks()
	assert_bool(looks.board_of(Rig.BOARD_EAST).smoking(looks.shell_of(8))).is_true()
	assert_bool(looks.board_of(Rig.BOARD_EAST).smoking(looks.shell_of(7))).is_false()


## The art's layer 20 trick on the live layers: the seated crystal's light reaches the hull
## (GROUND) and skips its station's meshes (STATION), which the level's inside light still reaches;
## the crystal's own meshes stay on GROUND.
func _assert_lights_the_hull_not_the_station(crystal: ShipCrystalLook) -> void:
	var mask := crystal.omni().light_cull_mask
	assert_int(mask & PhotoLayers.GROUND).is_not_equal(0)
	assert_int(mask & PhotoLayers.STATION).is_equal(0)
	var station := crystal.node().get_parent()
	while station.get_parent() != _view.level:
		station = station.get_parent()
	var meshes := 0
	for m: Node in station.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		# The station's own meshes: not the crystal's, the collision shapes' or the code-built
		# lightning's (no owner).
		if (
			crystal.node().is_ancestor_of(mesh)
			or mesh.get_parent() is CollisionObject3D
			or mesh.owner == null
		):
			continue
		assert_int(mesh.layers).is_equal(PhotoLayers.STATION)
		meshes += 1
	assert_int(meshes).is_greater(0)
	for m: Node in crystal.node().find_children("*", "MeshInstance3D", true, false):
		assert_int((m as MeshInstance3D).layers).is_equal(PhotoLayers.GROUND)
	var lamp := _view.level.find_child(Rig.INSIDE_LAMP, false, false) as Light3D
	assert_int(lamp.light_cull_mask & PhotoLayers.STATION).is_not_equal(0)


## Whether the packages' art is missing here (CI: LFS pointers); the test then skips.
func _no_art() -> bool:
	return ShipDeviceArt.missing(self, true)
