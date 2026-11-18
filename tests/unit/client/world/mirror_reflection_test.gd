extends GdUnitTestSuite
## The lobby mirror's reflection (#1395, ARCHITECTURE §4.7.68): a point before the glass is drawn
## on the glass where the eye sees its mirror image (the lens, its off-axis frustum and the glass's
## left-right flip together); the glass lies behind the lens's near plane; the reflection renders
## only while the window's camera sees the glass from the front; the own stand-in stands at the
## local player in the own roster colour, on the layer only the mirror draws, with no collision, and
## hides while the own body is down; clear() forgets it all.

const PLAYER := preload("res://client/player/player.tscn")
const MODE := "res://content/modes/base_mode.tres"
const OWN := 2
## The lobby's glass (levels/lobby/lobby.tscn's Mirror/Glass): facing +X, its right -Z.
const GLASS_AT := Vector3(-19.79, 1.25, 8.0)
const GLASS_BASIS := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
const SIZE := Vector2(2.0, 2.5)

var _viewport: SubViewport
var _level: Node3D
var _marker: Marker3D
var _eye: Camera3D
var _mirror: MirrorReflection
var _model: ClientModel


func before_test() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1920, 1080)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_level = Node3D.new()
	_viewport.add_child(_level)
	_marker = Marker3D.new()
	_marker.transform = Transform3D(GLASS_BASIS, GLASS_AT)
	_marker.set_meta(&"size_m", SIZE)
	_marker.add_to_group(MirrorReflection.GLASS_GROUP)
	_level.add_child(_marker)
	_eye = Camera3D.new()
	_viewport.add_child(_eye)
	_eye.make_current()
	_model = ClientModel.new(load(MODE) as GameMode)
	_model.own_peer = OWN
	_member(OWN, 4)
	_mirror = MirrorReflection.new()
	_mirror.model = _model
	_mirror.eye = func() -> Camera3D: return _eye
	_mirror.set_process(false)
	_viewport.add_child(_mirror)
	_mirror.level = _level


func after_test() -> void:
	_viewport.free()


func test_the_lens_draws_the_live_view_and_the_own_stand_in_and_no_puppet() -> void:
	assert_int(_mirror.camera.cull_mask).is_equal(PhotoLayers.MIRROR_VIEW)
	var mask := _mirror.camera.cull_mask
	assert_int(mask & PhotoLayers.MIRROR_SELF).is_equal(PhotoLayers.MIRROR_SELF)
	assert_int(mask & PhotoLayers.LIVE_AVATAR).is_equal(PhotoLayers.LIVE_AVATAR)
	assert_int(mask & PhotoLayers.GROUND).is_equal(PhotoLayers.GROUND)
	assert_int(mask & PhotoLayers.PHOTO).is_equal(0)


func test_the_glass_takes_the_marker_s_place_and_size() -> void:
	assert_bool(_mirror.glass.visible).is_true()
	assert_vector((_mirror.glass.mesh as QuadMesh).size).is_equal(SIZE)
	var expected := GLASS_AT - GLASS_BASIS.z * MirrorReflection.GLASS_BEHIND_M
	assert_vector(_mirror.glass.global_position).is_equal_approx(expected, Vector3.ONE * 1e-5)
	# The picture keeps the glass's aspect.
	var pixels := _mirror.viewport.size
	assert_int(pixels.y).is_equal(MirrorReflection.HEIGHT_PX)
	assert_float(float(pixels.x) / pixels.y).is_equal_approx(SIZE.x / SIZE.y, 0.01)


## The whole chain, from both a square-on and an oblique eye: a point P before the glass is seen in
## a mirror where the line from the eye to P's mirror image crosses the glass; the lens must draw P
## at the picture's texel the glass shows there (the quad's own UV, then the material's flip).
func test_a_point_is_drawn_where_the_eye_sees_its_mirror_image() -> void:
	var n := GLASS_BASIS.z
	var eyes: Array[Vector3] = [GLASS_AT + n * 1.5, GLASS_AT + n * 2.0 + Vector3(0, 0.4, 0.7)]
	var points: Array[Vector3] = [
		GLASS_AT + n * 0.8 + Vector3(0, -0.5, 0.3),
		GLASS_AT + n * 1.2 + Vector3(0, 0.6, -0.5),
		GLASS_AT + n * 0.3 + Vector3(0, 0.2, 0.6),
	]
	for at: Vector3 in eyes:
		_eye.look_at_from_position(at, GLASS_AT)
		_mirror.refresh()
		assert_bool(_mirror.rendering()).is_true()
		for point: Vector3 in points:
			var image := point - 2.0 * (point - GLASS_AT).dot(n) * n
			var hit: Variant = Plane(n, GLASS_AT).intersects_segment(at, image)
			assert_object(hit).is_not_null()
			var on_glass := (hit as Vector3) - GLASS_AT
			var texel := _texel_at(on_glass.dot(GLASS_BASIS.x), on_glass.dot(GLASS_BASIS.y))
			var drawn := _mirror.camera.unproject_position(point) / Vector2(_mirror.viewport.size)
			(
				assert_vector(drawn)
				. override_failure_message("%s from %s" % [point, at])
				. is_equal_approx(texel, Vector2.ONE * 1e-3)
			)


func test_the_glass_lies_behind_the_lens_near_plane_and_the_room_before_it() -> void:
	_eye.look_at_from_position(GLASS_AT + GLASS_BASIS.z * 1.5 + Vector3(0, 0.2, 0.4), GLASS_AT)
	_mirror.refresh()
	var ahead := -_mirror.camera.global_basis.z
	var glass_depth := (_mirror.glass.global_position - _mirror.camera.global_position).dot(ahead)
	assert_float(glass_depth).is_less(_mirror.camera.near)
	var room := GLASS_AT + GLASS_BASIS.z * 0.01
	assert_float((room - _mirror.camera.global_position).dot(ahead)).is_greater(_mirror.camera.near)


func test_it_renders_only_while_the_eye_sees_the_glass_from_the_front() -> void:
	var front := GLASS_AT + GLASS_BASIS.z * 2.0
	_eye.look_at_from_position(front, GLASS_AT)
	_mirror.refresh()
	assert_bool(_mirror.rendering()).is_true()
	# Turned away: the glass is behind the eye.
	_eye.look_at_from_position(front, front + GLASS_BASIS.z)
	_mirror.refresh()
	assert_bool(_mirror.rendering()).is_false()
	# Looking along the wall, the glass out of the frustum's side.
	_eye.look_at_from_position(front, front + Vector3(0, 0, 10))
	_mirror.refresh()
	assert_bool(_mirror.rendering()).is_false()
	# Behind the glass, looking at it.
	var behind := GLASS_AT - GLASS_BASIS.z * 2.0
	_eye.look_at_from_position(behind, GLASS_AT)
	_mirror.refresh()
	assert_bool(_mirror.rendering()).is_false()


func test_a_level_without_glass_draws_nothing() -> void:
	_eye.look_at_from_position(GLASS_AT + GLASS_BASIS.z * 2.0, GLASS_AT)
	_mirror.level = Node3D.new()
	_mirror.refresh()
	assert_bool(_mirror.glass.visible).is_false()
	assert_bool(_mirror.rendering()).is_false()
	(_mirror.level as Node3D).free()
	_mirror.level = _level
	_mirror.refresh()
	assert_bool(_mirror.rendering()).is_true()


func test_unset_the_eye_is_the_window_s_current_camera() -> void:
	_mirror.eye = Callable()
	_eye.look_at_from_position(GLASS_AT + GLASS_BASIS.z * 2.0, GLASS_AT)
	_mirror.refresh()
	assert_bool(_mirror.rendering()).is_true()


func test_the_stand_in_is_the_own_body_in_the_own_colour_seen_only_by_the_mirror() -> void:
	var player := _player_at(GLASS_AT + GLASS_BASIS.z * 0.8 + Vector3(0, -1.25, 0))
	_eye.look_at_from_position(player.global_position + Vector3(0, 1.6, 0), GLASS_AT)
	_mirror.refresh()
	var body := _mirror.self_body
	assert_object(body).is_not_null()
	assert_bool(body.visible).is_true()
	assert_int(body.peer).is_equal(OWN)
	assert_vector(body.global_position).is_equal_approx(player.global_position, Vector3.ONE * 1e-5)
	assert_object(body.color).is_equal(BodyColours.of(4))
	assert_int(PhotoLayers.layers_of(body)).is_equal(PhotoLayers.MIRROR_SELF)
	assert_int(body.collision_layer).is_equal(0)
	assert_int(body.collision_mask).is_equal(0)
	# The host's ProfileChanged moved the own colour in the roster: the stand-in follows.
	_member(OWN, 6)
	_mirror.refresh()
	assert_object(body.color).is_equal(BodyColours.of(6))
	# Neither the live view nor a picture draws it.
	assert_int(PhotoLayers.LIVE_VIEW & PhotoLayers.MIRROR_SELF).is_equal(0)
	assert_int(PhotoLayers.PHOTO_VIEW & PhotoLayers.MIRROR_SELF).is_equal(0)


func test_the_stand_in_hides_while_the_own_body_is_down_or_the_glass_unseen() -> void:
	var player := _player_at(GLASS_AT + GLASS_BASIS.z * 0.8 + Vector3(0, -1.25, 0))
	var eye_at := player.global_position + Vector3(0, 1.6, 0)
	_eye.look_at_from_position(eye_at, GLASS_AT)
	_mirror.refresh()
	assert_bool(_mirror.self_body.visible).is_true()
	# Limp: the own ragdoll (AvatarViews) is the body then.
	_model.avatars[OWN] = {"limp": true}
	_mirror.refresh()
	assert_bool(_mirror.rendering()).is_true()
	assert_bool(_mirror.self_body.visible).is_false()
	_model.avatars.erase(OWN)
	_mirror.refresh()
	assert_bool(_mirror.self_body.visible).is_true()
	_eye.look_at_from_position(eye_at, eye_at + GLASS_BASIS.z)
	_mirror.refresh()
	assert_bool(_mirror.self_body.visible).is_false()


func test_no_stand_in_without_an_own_peer() -> void:
	_player_at(GLASS_AT + GLASS_BASIS.z * 0.8 + Vector3(0, -1.25, 0))
	_model.own_peer = 0
	_eye.look_at_from_position(GLASS_AT + GLASS_BASIS.z * 2.0, GLASS_AT)
	_mirror.refresh()
	assert_bool(_mirror.rendering()).is_true()
	assert_object(_mirror.self_body).is_null()


func test_clear_forgets_the_session() -> void:
	_player_at(GLASS_AT + GLASS_BASIS.z * 0.8 + Vector3(0, -1.25, 0))
	_eye.look_at_from_position(GLASS_AT + GLASS_BASIS.z * 2.0, GLASS_AT)
	_mirror.refresh()
	assert_object(_mirror.self_body).is_not_null()
	_mirror.clear()
	# The stand-in leaves the tree at once and is freed at the frame's end.
	await get_tree().process_frame
	assert_bool(_mirror.rendering()).is_false()
	assert_object(_mirror.self_body).is_null()
	assert_object(_mirror.model).is_null()
	assert_object(_mirror.player).is_null()
	_mirror.refresh()
	assert_bool(_mirror.rendering()).is_false()


## The texel of the reflection's picture the glass shows at glass point (x right, y up), read from
## the quad's own UVs (no assumption on QuadMesh's layout) and the material's UV transform.
func _texel_at(x: float, y: float) -> Vector2:
	var arrays := (_mirror.glass.mesh as QuadMesh).get_mesh_arrays()
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var uvs := arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	var right := 0.0
	var up := 0.0
	for index: int in vertices.size():
		right += uvs[index].x * signf(vertices[index].x)
		up += uvs[index].y * signf(vertices[index].y)
	# Over the four corners: the sum is 2 when u grows to the right (1 + 1 - 0 - 0), else -2.
	var uv := Vector2(0.5 + signf(right) * x / SIZE.x, 0.5 + signf(up) * y / SIZE.y)
	var material := _mirror.glass.material_override as StandardMaterial3D
	var scale := Vector2(material.uv1_scale.x, material.uv1_scale.y)
	var offset := Vector2(material.uv1_offset.x, material.uv1_offset.y)
	return uv * scale + offset


func _player_at(feet: Vector3) -> PlayerController:
	var player := PLAYER.instantiate() as PlayerController
	_viewport.add_child(player)
	player.set_physics_process(false)
	player.global_position = feet
	# Facing the glass.
	player.look_at(feet - GLASS_BASIS.z, Vector3.UP)
	_mirror.player = player
	return player


func _member(peer: int, colour: int) -> void:
	var member := ClientModel.Member.new()
	member.name = "Peer%d" % peer
	member.colour = colour
	_model.roster[peer] = member
