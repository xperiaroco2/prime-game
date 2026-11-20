extends GdUnitTestSuite
## The first-person hands (client/player/FpHands, FpView; #1587, ARCHITECTURE §4.7.69), on a
## fixture built in memory with the package's node and clip names (the real GLB is Git LFS content,
## absent on CI): the state clips, the hit and the return from it, the run's speed, the crystal on
## the socket at 40 % of its light and never lighting the hands, the colour, the HANDS layer, the
## hand item's crystal left to the hands, and the hands' own camera.

const CLIPS: Array[StringName] = [
	&"Idle", &"Run", &"Punch", &"Crystal_Idle", &"Crystal_Run", &"Crystal_Hit"
]
const SKIN := Color(0.8, 0.6, 0.5)
## A second arm's own albedo (a package may split the two arms into meshes or surfaces).
const SKIN_2 := Color(0.6, 0.5, 0.4)
## The package's two morph targets (art#387's HANDOFF): the right fist and the left.
const FISTS: Array[StringName] = [&"fist", &"fist_L"]
## One frame of the game at 60 Hz, the step _play_for advances the clips by.
const FRAME_S := 1.0 / 60.0


## The fists each clip keys (HANDOFF "Clips"): closed with an empty hand, open on the crystal.
static func _fist_of(clip: StringName) -> float:
	return 0.0 if String(clip).begins_with("Crystal") else 1.0


## A triangle with the package's two morph targets, its surface in `skin`.
static func _fist_mesh(skin: StandardMaterial3D) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for target: StringName in FISTS:
		mesh.add_blend_shape(target)
	var points := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var shape: Array = []
	shape.resize(Mesh.ARRAY_MAX)
	shape[Mesh.ARRAY_VERTEX] = points
	var shapes: Array[Array] = [shape, shape.duplicate()]
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	mesh.surface_set_material(0, skin)
	return mesh


func _fixture(
	with_player := true, looping_hit := false, second_arm := false, fists := false
) -> PackedScene:
	var root := Node3D.new()
	root.name = "Fixture"
	if with_player:
		var player := AnimationPlayer.new()
		player.name = "AnimationPlayer"
		var library := AnimationLibrary.new()
		for clip: StringName in CLIPS:
			var animation := Animation.new()
			animation.length = 0.5
			# As the package imports them: the state clips loop (their `_Loop` names), the hits not.
			if (clip != &"Punch" and clip != &"Crystal_Hit") or looping_hit:
				animation.loop_mode = Animation.LOOP_LINEAR
			if fists:
				for target: StringName in FISTS:
					var track := animation.add_track(Animation.TYPE_BLEND_SHAPE)
					animation.track_set_path(track, NodePath("FPArms:%s" % target))
					animation.blend_shape_track_insert_key(track, 0.0, _fist_of(clip))
			library.add_animation(clip, animation)
		player.add_animation_library(&"", library)
		root.add_child(player)
		player.owner = root
	var socket := Node3D.new()
	socket.name = "CrystalSocket"
	root.add_child(socket)
	socket.owner = root
	var arms := MeshInstance3D.new()
	arms.name = "FPArms"
	var box := BoxMesh.new()
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SKIN
	box.material = skin
	arms.mesh = _fist_mesh(skin) if fists else box
	root.add_child(arms)
	arms.owner = root
	if second_arm:
		# A mesh of its own under a bone attachment, with its own material: a test name, not the
		# package's (HANDOFF: both arms are FPArms' one skin today).
		var attachment := Node3D.new()
		attachment.name = "Attachment"
		root.add_child(attachment)
		attachment.owner = root
		var other := MeshInstance3D.new()
		other.name = "SecondArm"
		var other_box := BoxMesh.new()
		var other_skin := StandardMaterial3D.new()
		other_skin.albedo_color = SKIN_2
		other_box.material = other_skin
		other.mesh = other_box
		attachment.add_child(other)
		other.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


func _hands(with_player := true) -> FpHands:
	var hands: FpHands = auto_free(FpHands.new(_fixture(with_player)))
	add_child(hands)
	return hands


func test_the_state_clip_follows_the_speed_and_the_crystal() -> void:
	assert_str(FpHands.clip_for(0.0, false)).is_equal("Idle")
	assert_str(FpHands.clip_for(FpHands.RUN_FROM_MPS - 0.01, false)).is_equal("Idle")
	assert_str(FpHands.clip_for(FpHands.RUN_FROM_MPS, false)).is_equal("Run")
	assert_str(FpHands.clip_for(0.0, true)).is_equal("Crystal_Idle")
	assert_str(FpHands.clip_for(4.0, true)).is_equal("Crystal_Run")
	assert_str(FpHands.hit_clip(false)).is_equal("Punch")
	assert_str(FpHands.hit_clip(true)).is_equal("Crystal_Hit")
	assert_bool(FpHands.is_crystal(&"crystal_charged")).is_true()
	assert_bool(FpHands.is_crystal(&"crystal_spent")).is_true()
	assert_bool(FpHands.is_crystal(&"mug")).is_false()
	assert_bool(FpHands.is_crystal(&"")).is_false()


func test_the_run_plays_at_the_own_speed_within_its_bounds() -> void:
	assert_float(FpHands.run_scale(FpHands.RUN_CLIP_MPS)).is_equal_approx(1.0, 1e-6)
	assert_float(FpHands.run_scale(0.1)).is_equal_approx(FpHands.RUN_SCALE_MIN, 1e-6)
	assert_float(FpHands.run_scale(50.0)).is_equal_approx(FpHands.RUN_SCALE_MAX, 1e-6)
	var hands := _hands()
	hands.update(FpHands.RUN_CLIP_MPS * 1.2)
	assert_str(hands.current_clip()).is_equal("Run")
	assert_float(hands.player.speed_scale).is_equal_approx(1.2, 1e-6)
	hands.update(0.0)
	assert_str(hands.current_clip()).is_equal("Idle")
	assert_float(hands.player.speed_scale).is_equal_approx(1.0, 1e-6)


func test_a_hit_plays_once_then_the_state_clip_again() -> void:
	var hands := _hands()
	assert_str(hands.current_clip()).is_equal("Idle")
	hands.play_hit()
	assert_str(hands.current_clip()).is_equal("Punch")
	# The state does not cut the hit short.
	hands.update(4.0)
	assert_str(hands.current_clip()).is_equal("Punch")
	hands.player.animation_finished.emit(&"Punch")
	assert_str(hands.current_clip()).is_equal("Run")
	hands.set_held(&"crystal_spent")
	assert_str(hands.current_clip()).is_equal("Crystal_Run")
	hands.play_hit()
	assert_str(hands.current_clip()).is_equal("Crystal_Hit")
	hands.player.animation_finished.emit(&"Crystal_Hit")
	assert_str(hands.current_clip()).is_equal("Crystal_Run")


func test_a_held_button_chains_the_hits() -> void:
	# The next Swung comes as the last hit ends (both at the swing rate): it starts over.
	var hands := _hands()
	hands.play_hit()
	hands.player.seek(0.45, true)
	hands.play_hit()
	assert_str(hands.current_clip()).is_equal("Punch")
	assert_float(hands.player.current_animation_position).is_equal_approx(0.0, 1e-4)


func test_the_hits_play_once_and_the_states_loop_whatever_the_package_says() -> void:
	var hands: FpHands = auto_free(FpHands.new(_fixture(true, true)))
	add_child(hands)
	assert_int(hands.player.get_animation(&"Punch").loop_mode).is_equal(Animation.LOOP_NONE)
	assert_int(hands.player.get_animation(&"Crystal_Hit").loop_mode).is_equal(Animation.LOOP_NONE)
	assert_int(hands.player.get_animation(&"Run").loop_mode).is_equal(Animation.LOOP_LINEAR)


func test_the_hands_environment_is_the_views_without_its_extra_passes() -> void:
	var looks := Environment.new()
	looks.background_mode = Environment.BG_SKY
	looks.ssao_enabled = true
	looks.ssil_enabled = true
	looks.glow_enabled = true
	looks.fog_enabled = true
	looks.ssr_enabled = true
	looks.ambient_light_energy = 0.7
	var own := FpView.hands_environment(looks)
	assert_object(own).is_not_same(looks)
	assert_int(own.background_mode).is_equal(Environment.BG_CLEAR_COLOR)
	(
		assert_bool(own.ssao_enabled or own.ssil_enabled or own.glow_enabled or own.fog_enabled)
		. is_false()
	)
	assert_float(own.ambient_light_energy).is_equal_approx(0.7 * FpView.AMBIENT_SHARE, 1e-6)
	assert_bool(own.ssr_enabled).is_false()
	assert_int(looks.background_mode).is_equal(Environment.BG_SKY)
	assert_object(FpView.hands_environment(null)).is_null()


func test_a_hit_that_stopped_without_finishing_frees_the_state() -> void:
	var hands := _hands()
	hands.play_hit()
	hands.player.stop()
	hands.update(4.0)
	assert_str(hands.current_clip()).is_equal("Run")


func test_the_hands_are_on_their_own_layer_with_no_shadow() -> void:
	var hands := _hands()
	assert_int(PhotoLayers.layers_of(hands.model)).is_equal(PhotoLayers.HANDS)
	var arms := hands.model.find_child("FPArms", true, false) as MeshInstance3D
	assert_int(arms.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	# Neither the live view nor a picture draws the hands; only their own camera does.
	assert_int(PhotoLayers.LIVE_VIEW & PhotoLayers.HANDS).is_zero()
	assert_int(PhotoLayers.PHOTO_VIEW & PhotoLayers.HANDS).is_zero()
	# Nor the lobby mirror's lens (#1395), whose layer is the next one up.
	assert_int(PhotoLayers.MIRROR_VIEW & PhotoLayers.HANDS).is_zero()
	assert_int(PhotoLayers.MIRROR_SELF & PhotoLayers.HANDS).is_zero()
	var view: FpView = auto_free(FpView.new())
	assert_int(view.camera.cull_mask).is_equal(PhotoLayers.HANDS)
	assert_int(view.fill.layers).is_equal(PhotoLayers.HANDS)
	assert_int(view.fill.light_cull_mask).is_equal(PhotoLayers.HANDS)


func test_the_hands_take_the_own_body_colour() -> void:
	var hands := _hands()
	var arms := hands.model.find_child("FPArms", true, false) as MeshInstance3D
	var material := arms.get_active_material(0) as BaseMaterial3D
	# Before the own colour is known: the package's default (HANDOFF, sRGB 0.40 0.86 0.80).
	assert_that(material.albedo_color).is_equal(SKIN * FpHands.DEFAULT_TINT)
	var colour := BodyColours.of(3)
	hands.set_tint(colour)
	assert_that(material.albedo_color).is_equal(SKIN * colour)
	# Its own copy: the package's material keeps its albedo.
	assert_object((arms.mesh as BoxMesh).material).is_not_same(material)
	assert_that(((arms.mesh as BoxMesh).material as BaseMaterial3D).albedo_color).is_equal(SKIN)


func test_every_arm_takes_the_colour_and_the_layer() -> void:
	# The two hands in view (art#387, 2026-11-20) are one skin today; a package that splits the
	# arms into meshes still gets both in the own colour, on HANDS alone, with no shadow.
	var hands: FpHands = auto_free(FpHands.new(_fixture(true, false, true)))
	add_child(hands)
	var colour := BodyColours.of(5)
	hands.set_tint(colour)
	var skins: Array[Color] = [SKIN, SKIN_2]
	var names: Array[String] = ["FPArms", "SecondArm"]
	for i: int in names.size():
		var arm := hands.model.find_child(names[i], true, false) as MeshInstance3D
		assert_object(arm).is_not_null()
		assert_that((arm.get_active_material(0) as BaseMaterial3D).albedo_color).is_equal(
			skins[i] * colour
		)
		assert_int(arm.layers).is_equal(PhotoLayers.HANDS)
		assert_int(arm.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func _assert_fists(arms: MeshInstance3D, value: float) -> void:
	for target: StringName in FISTS:
		var index := arms.find_blend_shape_by_name(target)
		assert_int(index).is_not_equal(-1)
		assert_float(arms.get_blend_shape_value(index)).is_equal_approx(value, 1e-3)


## Plays `hands` on for `seconds` in frames of FRAME_S, as the game's frames do, then one empty
## step: a cross-fade's weight reaches the morphs one advance() late (Godot 4.7.2, seen on the
## real package too), and the empty step settles it.
func _play_for(hands: FpHands, seconds: float) -> void:
	var left := seconds
	while left > 1e-6:
		var step := minf(FRAME_S, left)
		hands.player.advance(step)
		left -= step
	hands.player.advance(0.0)


func test_the_fists_are_the_clips_and_open_onto_the_crystal_in_the_blend() -> void:
	# Both morphs (art#387: fist the right, fist_L the left) are the clips' alone: the code keys
	# and resets none, so the fists close with an empty hand, open on the crystal over the
	# switch's blend (HANDOFF "Clips") and close again; a hit keeps them as its clip keys them.
	var hands: FpHands = auto_free(FpHands.new(_fixture(true, false, false, true)))
	add_child(hands)
	var arms := hands.model.find_child("FPArms", true, false) as MeshInstance3D
	_play_for(hands, 0.1)
	_assert_fists(arms, 1.0)
	hands.set_held(&"crystal_charged")
	_play_for(hands, FpHands.BLEND_S / 2.0)
	for target: StringName in FISTS:
		var halfway := arms.get_blend_shape_value(arms.find_blend_shape_by_name(target))
		assert_float(halfway).is_between(0.1, 0.9)
	_play_for(hands, FpHands.BLEND_S)
	_assert_fists(arms, 0.0)
	hands.play_hit()
	_play_for(hands, FpHands.HIT_BLEND_S * 2.0)
	assert_str(hands.current_clip()).is_equal("Crystal_Hit")
	_assert_fists(arms, 0.0)
	hands.player.animation_finished.emit(&"Crystal_Hit")
	hands.set_held(&"")
	assert_str(hands.current_clip()).is_equal("Idle")
	_play_for(hands, FpHands.BLEND_S * 2.0)
	_assert_fists(arms, 1.0)
	hands.play_hit()
	_play_for(hands, FpHands.HIT_BLEND_S * 2.0)
	assert_str(hands.current_clip()).is_equal("Punch")
	# The Punch pins the hit's own keys (1, against the state's 1 and a missing track's 0); the
	# crystal hit's 0 above is the state's too.
	_assert_fists(arms, 1.0)


func test_a_crystal_taken_or_dropped_in_a_hit_ends_the_hit() -> void:
	# The hit's clip keys its own fists: the crystal shown in a closed fist, or open hands round
	# none, until it ended. It ends at once and the new state's clip blends in.
	var hands: FpHands = auto_free(FpHands.new(_fixture(true, false, false, true)))
	add_child(hands)
	var arms := hands.model.find_child("FPArms", true, false) as MeshInstance3D
	hands.play_hit()
	_play_for(hands, FpHands.HIT_BLEND_S)
	hands.set_held(&"crystal_charged")
	assert_str(hands.current_clip()).is_equal("Crystal_Idle")
	_play_for(hands, FpHands.BLEND_S * 2.0)
	_assert_fists(arms, 0.0)
	hands.play_hit()
	_play_for(hands, FpHands.HIT_BLEND_S)
	hands.set_held(&"")
	assert_str(hands.current_clip()).is_equal("Idle")
	_play_for(hands, FpHands.BLEND_S * 2.0)
	_assert_fists(arms, 1.0)
	# A change that keeps the hit's state (charged to spent) lets the hit play on.
	hands.set_held(&"crystal_charged")
	_play_for(hands, FpHands.BLEND_S * 2.0)
	hands.play_hit()
	hands.set_held(&"crystal_spent")
	assert_str(hands.current_clip()).is_equal("Crystal_Hit")


func test_a_held_crystal_sits_on_the_socket_at_forty_percent_light() -> void:
	var hands := _hands()
	hands.set_held(&"crystal_charged")
	assert_str(hands.current_clip()).is_equal("Crystal_Idle")
	if hands.crystal == null:
		# CI: the crystal's GLB is a Git LFS stand-in with none of its surfaces.
		return
	assert_object(hands.crystal.node().get_parent()).is_same(hands.socket)
	assert_bool(hands.crystal.shown()).is_true()
	var omni := hands.crystal.omni()
	assert_float(omni.light_energy).is_equal_approx(
		ShipCrystalLook.OMNI_ENERGY * FpHands.LIGHT_SHARE, 1e-5
	)
	# Its light lights the room round the eye and never the hands.
	assert_int(omni.layers).is_equal(PhotoLayers.LIVE_AVATAR)
	assert_int(omni.light_cull_mask & PhotoLayers.HANDS).is_zero()
	# Its meshes are on the hands' layer.
	for node: Node in hands.crystal.node().find_children("*", "GeometryInstance3D", true, false):
		assert_int((node as VisualInstance3D).layers).is_equal(PhotoLayers.HANDS)
	hands.set_held(&"crystal_spent")
	assert_float(omni.light_energy).is_equal_approx(0.0, 1e-6)
	hands.set_held(&"")
	assert_bool(hands.crystal.shown()).is_false()
	assert_str(hands.current_clip()).is_equal("Idle")


func test_without_the_package_every_call_is_harmless() -> void:
	var hands := _hands(false)
	assert_object(hands.model).is_null()
	hands.update(3.0)
	hands.set_held(&"crystal_charged")
	hands.play_hit()
	hands.set_tint(Color.RED)
	assert_str(hands.current_clip()).is_empty()
	assert_object(hands.crystal).is_null()


func test_the_hand_item_leaves_the_crystal_to_the_hands() -> void:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	var camera := Camera3D.new()
	holder.add_child(camera)
	var hand := FirstPersonHand.new()
	camera.add_child(hand)
	var hands := FpHands.new(_fixture())
	hands.build()
	hands.attach(holder, camera, hand)
	assert_array(hand.hidden_kinds).contains_exactly(FpHands.CRYSTAL_KINDS)
	hand.show_item(&"crystal_charged", Color.WHITE)
	assert_str(hand.shown_kind()).is_equal("crystal_charged")
	assert_object(hand.find_child("HandItem", false, false)).is_null()
	hand.show_item(&"mug", Color.WHITE)
	assert_object(hand.find_child("HandItem", false, false)).is_not_null()
	# The hands' own camera follows the player camera at the package's field of view.
	assert_object(hands.view.source).is_same(camera)
	assert_float(hands.view.camera.fov).is_equal_approx(FpView.FOV_DEG, 1e-6)
	hands.update(0.0, false)
	assert_bool(hands.view.drawn()).is_false()
	assert_int(hands.view.viewport.positional_shadow_atlas_size).is_zero()
	# Without the package nothing is drawn at all: no view, no pass.
	var bare_camera := Camera3D.new()
	holder.add_child(bare_camera)
	var bare_hand := FirstPersonHand.new()
	bare_camera.add_child(bare_hand)
	var bare := FpHands.new(_fixture(false))
	bare.build()
	bare.attach(holder, bare_camera, bare_hand)
	assert_object(bare.view).is_null()
	assert_array(bare_hand.hidden_kinds).is_empty()


func test_the_level_lights_that_reach_the_ground_light_the_hands_too() -> void:
	var level: Node3D = auto_free(Node3D.new())
	var lamp := OmniLight3D.new()
	level.add_child(lamp)
	var lobby := OmniLight3D.new()
	lobby.layers = 1 << 10
	lobby.light_cull_mask = 1 << 10
	level.add_child(lobby)
	var puppets_only := OmniLight3D.new()
	puppets_only.layers = PhotoLayers.PHOTO
	puppets_only.light_cull_mask = PhotoLayers.PHOTO
	level.add_child(puppets_only)
	FpView.light_level(level)
	assert_int(lamp.layers & PhotoLayers.HANDS).is_equal(PhotoLayers.HANDS)
	assert_int(lamp.light_cull_mask & PhotoLayers.HANDS).is_equal(PhotoLayers.HANDS)
	# The lobby's own lights (layer 11, lighting its layer-11 meshes) light the hands too.
	assert_int(lobby.light_cull_mask).is_equal((1 << 10) | PhotoLayers.HANDS)
	# A light the live view never draws stays as it was.
	assert_int(puppets_only.layers).is_equal(PhotoLayers.PHOTO)
	assert_int(puppets_only.light_cull_mask).is_equal(PhotoLayers.PHOTO)
