extends GdUnitTestSuite
## The smoke at a tripped breaker core (#1556, ARCHITECTURE §9.5.27): ShipBoardSmoke on a plain
## root (no art), so CI runs it: an emitter per core at its centre holding only the smoke (GDD §8:
## the breakers "pop out and smoke"; no sparks, arcs or light), all quiet at first, one core on
## leaves the others quiet, off stops the emitting while the puffs outlive it, and every particle
## node stays on the live cameras' layers.

const CENTRES: Array[Vector3] = [
	Vector3(-0.504, 0.872, 0.18),
	Vector3(-0.168, 0.872, 0.18),
	Vector3(0.168, 0.872, 0.18),
	Vector3(0.504, 0.872, 0.18),
]

var _root: Node3D


func before_test() -> void:
	_root = auto_free(Node3D.new())
	# In the tree, so the emitters the test adds under it are no orphans.
	add_child(_root)


func test_an_emitter_sits_at_each_core_and_all_are_quiet_at_first() -> void:
	var smoke := ShipBoardSmoke.build(_root, CENTRES)
	assert_int(smoke.size()).is_equal(4)
	for i: int in 4:
		var at := smoke.emitter(i)
		assert_object(at.get_parent()).is_same(_root)
		assert_str(String(at.name)).is_equal("TrippedCore%d" % i)
		assert_vector(at.position).is_equal(CENTRES[i])
		assert_bool(smoke.smoking(i)).is_false()
		for p: CPUParticles3D in _particles(at):
			assert_bool(p.emitting).is_false()


func test_a_tripped_core_has_only_smoke() -> void:
	var smoke := ShipBoardSmoke.build(_root, CENTRES)
	for i: int in 4:
		smoke.set_smoking(i, true)
	for i: int in 4:
		var at := smoke.emitter(i)
		var kids := at.find_children("*", "", true, false)
		assert_int(kids.size()).is_equal(1)
		assert_str(String(kids[0].name)).is_equal("CoreSmoke")
		assert_bool(kids[0] is CPUParticles3D).is_true()
		assert_array(at.find_children("*", "MeshInstance3D", true, false)).is_empty()
		assert_array(at.find_children("*", "Light3D", true, false)).is_empty()


func test_one_core_smokes_and_the_others_stay_quiet() -> void:
	var smoke := ShipBoardSmoke.build(_root, CENTRES)
	smoke.set_smoking(2, true)
	assert_bool(smoke.smoking(2)).is_true()
	for p: CPUParticles3D in _particles(smoke.emitter(2)):
		assert_bool(p.emitting).is_true()
	for i: int in [0, 1, 3]:
		assert_bool(smoke.smoking(i)).is_false()
		for p: CPUParticles3D in _particles(smoke.emitter(i)):
			assert_bool(p.emitting).is_false()


func test_off_stops_the_emitting_and_the_puffs_outlive_it() -> void:
	var smoke := ShipBoardSmoke.build(_root, CENTRES)
	smoke.set_smoking(0, true)
	smoke.set_smoking(0, false)
	assert_bool(smoke.smoking(0)).is_false()
	# The puffs up fade on their own: the emitter stays, only its emitting stops.
	var puffs := smoke.emitter(0).get_node_or_null("CoreSmoke") as CPUParticles3D
	assert_object(puffs).is_not_null()
	assert_bool(puffs.emitting).is_false()
	assert_object(puffs.get_parent()).is_same(smoke.emitter(0))
	# They live on after the stop.
	assert_float(puffs.lifetime).is_greater(1.0)
	assert_bool(puffs.one_shot).is_false()


func test_every_node_stays_on_the_live_cameras_layers() -> void:
	var smoke := ShipBoardSmoke.build(_root, CENTRES)
	smoke.set_smoking(0, true)
	var found := _root.find_children("*", "VisualInstance3D", true, false)
	assert_int(_root.find_children("*", "CPUParticles3D", true, false).size()).is_equal(4)
	assert_int(found.size()).is_equal(4)
	for n: Node in found:
		var v := n as VisualInstance3D
		assert_int(v.layers & PhotoLayers.LIVE_VIEW).is_not_equal(0)
		assert_int(v.layers & PhotoLayers.PHOTO).is_equal(0)


static func _particles(at: Node3D) -> Array[CPUParticles3D]:
	var out: Array[CPUParticles3D] = []
	for n: Node in at.find_children("*", "CPUParticles3D", true, false):
		out.append(n as CPUParticles3D)
	return out
