extends GdUnitTestSuite
## The first-person hands on the art (the package of prime-game-art#387, run g5; #1587, ARCHITECTURE
## §4.7.69): both arms in FPArms' one skin, its two fist morphs keyed on FPArms in every clip and
## played by the clips through the switch's blend, every mesh in the own colour on HANDS alone. A
## checkout without the Git LFS content (CI) imports a stand-in with no AnimationPlayer: no hands,
## and each test says skip and checks only that the GLB is a pointer. The nightly `lfs` job runs it.

const Check := preload("res://tools/assets/asset_check.gd")
const CLIPS: Array[StringName] = [
	&"Idle", &"Run", &"Punch", &"Crystal_Idle", &"Crystal_Run", &"Crystal_Hit"
]
## The package's morph targets (its HANDOFF): the right fist and the left.
const FISTS: Array[StringName] = [&"fist", &"fist_L"]
const FRAME_S := 1.0 / 60.0


## The fists each clip keys (HANDOFF "Clips"): closed with an empty hand, open on the crystal.
static func _fist_of(clip: StringName) -> float:
	return 0.0 if String(clip).begins_with("Crystal") else 1.0


func test_every_clip_keys_both_fists_on_the_drawn_arms() -> void:
	var hands := _hands()
	if hands == null:
		return
	var arms := _arms(hands)
	assert_int(arms.get_blend_shape_count()).is_equal(FISTS.size())
	var root := hands.player.get_node(hands.player.root_node)
	for clip: StringName in CLIPS:
		var animation := hands.player.get_animation(clip)
		var keyed: Array[String] = []
		for track: int in animation.get_track_count():
			if animation.track_get_type(track) != Animation.TYPE_BLEND_SHAPE:
				continue
			var path := animation.track_get_path(track)
			keyed.append(String(path.get_concatenated_subnames()))
			# The track moves the mesh drawn, not a renamed or a second one.
			var node := root.get_node_or_null(NodePath(String(path.get_concatenated_names())))
			assert_object(node).override_failure_message("%s: %s" % [clip, path]).is_same(arms)
			for key: int in animation.track_get_key_count(track):
				var value := animation.track_get_key_value(track, key) as float
				assert_float(value).is_equal_approx(_fist_of(clip), 1e-3)
		assert_array(keyed).override_failure_message(String(clip)).contains_exactly_in_any_order(
			["fist", "fist_L"]
		)


func test_the_fists_open_onto_the_crystal_and_close_again() -> void:
	var hands := _hands()
	if hands == null:
		return
	var arms := _arms(hands)
	_play_for(hands, 0.1)
	_assert_fists(arms, 1.0)
	hands.set_held(&"crystal_charged")
	_play_for(hands, FpHands.BLEND_S / 2.0)
	for target: StringName in FISTS:
		var halfway := arms.get_blend_shape_value(arms.find_blend_shape_by_name(target))
		assert_float(halfway).is_between(0.1, 0.9)
	_play_for(hands, FpHands.BLEND_S)
	_assert_fists(arms, 0.0)
	hands.set_held(&"")
	_play_for(hands, FpHands.BLEND_S * 2.0)
	_assert_fists(arms, 1.0)
	hands.play_hit()
	_play_for(hands, 0.15)
	assert_str(hands.current_clip()).is_equal("Punch")
	_assert_fists(arms, 1.0)


func test_both_arms_take_the_own_colour_on_hands_alone() -> void:
	var hands := _hands()
	if hands == null:
		return
	var colour := BodyColours.of(2)
	hands.set_tint(colour)
	var meshes := hands.model.find_children("*", "MeshInstance3D", true, false)
	assert_array(meshes).is_not_empty()
	for node: Node in meshes:
		var mesh := node as MeshInstance3D
		assert_int(mesh.layers).is_equal(PhotoLayers.HANDS)
		assert_int(mesh.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		for i: int in mesh.get_surface_override_material_count():
			var material := mesh.get_active_material(i) as BaseMaterial3D
			# The skin's factor is white (HANDOFF): the hands are the own colour.
			assert_that(material.albedo_color).is_equal(colour)


## The hands on the package, playing; null (after the skip check) without the art.
func _hands() -> FpHands:
	var hands: FpHands = auto_free(FpHands.new())
	add_child(hands)
	if hands.model == null:
		print(
			"skip: %s has no Git LFS content here: the hands on the art are unchecked" % FpHands.GLB
		)
		assert_bool(Check.is_lfs_pointer(FpHands.GLB)).is_true()
		return null
	return hands


func _arms(hands: FpHands) -> MeshInstance3D:
	var arms := hands.model.find_child("FPArms", true, false) as MeshInstance3D
	assert_object(arms).is_not_null()
	return arms


## Plays on for `seconds` in 60 Hz frames, then one empty step: a cross-fade's weight reaches the
## morphs one advance() late (Godot 4.7.2), and the empty step settles it.
func _play_for(hands: FpHands, seconds: float) -> void:
	var left := seconds
	while left > 1e-6:
		var step := minf(FRAME_S, left)
		hands.player.advance(step)
		left -= step
	hands.player.advance(0.0)


func _assert_fists(arms: MeshInstance3D, value: float) -> void:
	for target: StringName in FISTS:
		var index := arms.find_blend_shape_by_name(target)
		assert_int(index).is_not_equal(-1)
		assert_float(arms.get_blend_shape_value(index)).is_equal_approx(value, 1e-3)
