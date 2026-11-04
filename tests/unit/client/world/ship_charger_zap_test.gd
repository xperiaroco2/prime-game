extends GdUnitTestSuite
## The charger's lightning (#1556, ARCHITECTURE §9.5.27): ShipChargerZap and ShipZapBolts on a
## plain rig (a ring and a cylinder crystal under a root, no art), so CI runs them: the gating, the
## arcs' ends on the electrodes and the crystal, the ring's turn, the spark cap, the determinism,
## and ShipStationLooks.flash_left's edge.

const CRYSTAL_RADIUS := 0.03
const CRYSTAL_HEIGHT := 0.2
const CRYSTAL_AT := Vector3(0.0, 1.0, 0.38)

var _root: Node3D
var _ring: Node3D
var _crystal: Node3D


func before_test() -> void:
	_root = _rig()
	# In the tree, so the arcs and lights a test adds under it are no orphans.
	add_child(_root)
	_ring = _root.get_node("Ring") as Node3D
	_crystal = _root.get_node("Crystal") as Node3D


func test_no_arcs_idle_charged_or_without_a_crystal() -> void:
	var zap := ShipChargerZap.bind(_root, _ring, _crystal, 263)
	zap.step(0.05, false, 0.0, 0.0)
	assert_bool(zap.arcing()).is_false()
	zap.step(0.05, true, 0.0, 0.0)
	assert_bool(zap.arcing()).is_false()
	zap.step(0.05, true, 1.0, 0.0)
	assert_bool(zap.arcing()).is_false()
	zap.step(0.05, false, 1.0, 0.0)
	assert_bool(zap.arcing()).is_false()
	for light: OmniLight3D in zap.lights():
		assert_bool(light.visible).is_false()
	_crystal.visible = false
	zap.step(0.05, true, 0.5, 1.0)
	assert_bool(zap.arcing()).is_false()
	assert_bool(zap.flashing()).is_false()


func test_arcs_run_while_charging_from_the_electrodes_into_the_crystal() -> void:
	var zap := ShipChargerZap.bind(_root, _ring, _crystal, 263)
	var hits := 0
	for frame: int in 40:
		zap.step(0.05, true, 0.5, 0.0)
		assert_bool(zap.arcing()).is_true()
		for ends: PackedVector3Array in zap.ends():
			hits += 1
			_assert_on_an_electrode(zap, ends[0])
			_assert_on_the_crystal(ends[1])
	assert_int(hits).is_greater(0)
	assert_int(zap.spark_count()).is_greater(0)
	assert_int(zap.spark_count()).is_less_equal(ShipChargerZap.MAX_SPARKS)
	assert_int(zap.node().mesh.get_surface_count()).is_equal(1)


func test_the_arcs_follow_the_turning_ring() -> void:
	var zap := ShipChargerZap.bind(_root, _ring, _crystal, 263)
	_ring.rotation.y = PI / 2.0
	for frame: int in 20:
		zap.step(0.05, true, 0.5, 0.0)
		for ends: PackedVector3Array in zap.ends():
			_assert_on_an_electrode(zap, ends[0])
	# A quarter turn takes the left and right prongs to the front and back.
	var tip := _ring.transform * zap.electrodes()[0]
	assert_float(absf(tip.x)).is_less(0.01)


func test_the_flash_arcs_every_electrode_at_full_charge() -> void:
	var zap := ShipChargerZap.bind(_root, _ring, _crystal, 263)
	zap.step(0.05, false, 1.0, 1.0)
	assert_bool(zap.flashing()).is_true()
	assert_bool(zap.arcing()).is_true()
	assert_int(zap.ends().size()).is_equal(4)
	for light: OmniLight3D in zap.lights():
		assert_bool(light.visible).is_true()
		assert_float(light.light_energy).is_equal_approx(ShipChargerZap.FLASH_ENERGY, 1e-4)
	assert_int(zap.spark_count()).is_greater_equal(ShipChargerZap.SPARK_BURST)
	zap.step(0.05, false, 1.0, 0.0)
	assert_bool(zap.flashing()).is_false()
	assert_bool(zap.arcing()).is_false()
	# The burst lives out its short life, then the charger is quiet.
	for frame: int in 30:
		zap.step(0.05, false, 1.0, 0.0)
	assert_int(zap.spark_count()).is_equal(0)


func test_the_same_seed_draws_the_same_arcs() -> void:
	var other := _rig()
	var a := ShipChargerZap.bind(_root, _ring, _crystal, 300)
	var b := ShipChargerZap.bind(
		other, other.get_node("Ring") as Node3D, other.get_node("Crystal") as Node3D, 300
	)
	for frame: int in 10:
		a.step(0.05, true, 0.5, 0.0)
		b.step(0.05, true, 0.5, 0.0)
		assert_str(str(a.ends())).is_equal(str(b.ends()))
	assert_int(a.spark_count()).is_equal(b.spark_count())


func test_a_bolt_keeps_its_ends_and_halves_its_segments() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pts := ShipZapBolts.bolt(rng, Vector3.ZERO, Vector3(0.0, 0.0, 1.0), 4, 0.28)
	assert_int(pts.size()).is_equal(17)
	assert_vector(pts[0]).is_equal(Vector3.ZERO)
	assert_vector(pts[pts.size() - 1]).is_equal(Vector3(0.0, 0.0, 1.0))
	var profile := ShipZapBolts.profile(_crystal)
	assert_float(profile.lo).is_equal_approx(0.0, 1e-4)
	assert_float(profile.hi).is_equal_approx(CRYSTAL_HEIGHT, 1e-4)
	assert_float(profile.radius(0.1)).is_equal_approx(CRYSTAL_RADIUS, 1e-3)


func test_the_flash_starts_on_the_edge_from_charging_to_waiting_only() -> void:
	var full := ShipStationLooks.FLASH_SECONDS
	var charging := CrystalProblem.CHARGING
	var waiting := CrystalProblem.WAITING
	assert_float(ShipStationLooks.flash_left(charging, waiting, false, 0.0)).is_equal(full)
	# A view built late (its first frame) plays no old edge.
	assert_float(ShipStationLooks.flash_left(charging, waiting, true, 0.0)).is_equal(0.0)
	assert_float(ShipStationLooks.flash_left(waiting, waiting, false, 0.0)).is_equal(0.0)
	assert_float(ShipStationLooks.flash_left(waiting, waiting, false, 0.2)).is_equal(0.2)
	assert_float(ShipStationLooks.flash_left(-1, waiting, false, 0.0)).is_equal(0.0)
	# A blast or a take ends it.
	var empty := CrystalProblem.EMPTY
	assert_float(ShipStationLooks.flash_left(waiting, empty, false, 0.4)).is_equal(0.0)
	assert_float(ShipStationLooks.flash_left(waiting, -1, false, 0.4)).is_equal(0.0)


func _rig() -> Node3D:
	var root: Node3D = auto_free(Node3D.new())
	var ring := Node3D.new()
	ring.name = "Ring"
	# The ring turns round the crystal's axis, as on the charger.
	ring.position = Vector3(0.0, 0.0, CRYSTAL_AT.z)
	root.add_child(ring)
	var crystal := Node3D.new()
	crystal.name = "Crystal"
	crystal.position = CRYSTAL_AT
	root.add_child(crystal)
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = CRYSTAL_RADIUS
	cylinder.bottom_radius = CRYSTAL_RADIUS
	cylinder.height = CRYSTAL_HEIGHT
	cylinder.rings = 40
	mesh.mesh = cylinder
	mesh.position = Vector3(0.0, CRYSTAL_HEIGHT / 2.0, 0.0)
	crystal.add_child(mesh)
	return root


## An arc starts on an electrode's surface: within its radius (and a little) of one.
func _assert_on_an_electrode(zap: ShipChargerZap, start: Vector3) -> void:
	var nearest := INF
	for local: Vector3 in zap.electrodes():
		nearest = minf(nearest, start.distance_to(_ring.transform * local))
	assert_float(nearest).is_less_equal(0.0101)


## An arc lands on the crystal: at its radius from the axis, within its height.
func _assert_on_the_crystal(hit: Vector3) -> void:
	var local := hit - CRYSTAL_AT
	assert_float(Vector2(local.x, local.z).length()).is_less_equal(CRYSTAL_RADIUS + 1e-3)
	assert_float(local.y).is_between(0.0, CRYSTAL_HEIGHT)
