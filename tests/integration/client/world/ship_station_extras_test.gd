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
	# The crystal's light skips the stations' own layer (the art's layer 20 trick).
	assert_int(crystal.omni().light_cull_mask & PhotoLayers.GROUND).is_equal(0)
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
	assert_int(crystal.omni().light_cull_mask & PhotoLayers.GROUND).is_equal(0)
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


func test_a_charge_s_share_runs_from_its_start_to_its_end() -> void:
	assert_float(ShipStationLooks.charge_share(100, 300, 200)).is_equal(0.0)
	assert_float(ShipStationLooks.charge_share(50, 300, 200)).is_equal(0.0)
	assert_float(ShipStationLooks.charge_share(150, 300, 200)).is_equal(0.25)
	assert_float(ShipStationLooks.charge_share(300, 300, 200)).is_equal(1.0)
	assert_float(ShipStationLooks.charge_share(900, 300, 200)).is_equal(1.0)
	assert_float(ShipStationLooks.charge_share(0, 300, 0)).is_equal(1.0)


## Whether the packages' art is missing here (CI: LFS pointers); the test then skips.
func _no_art() -> bool:
	return ShipDeviceArt.missing(self, true)
