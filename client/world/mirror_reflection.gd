class_name MirrorReflection
extends Node3D
## The lobby mirror's reflection (#1395; ARCHITECTURE §4.7.68; GDD §3 "The mirror": you see
## yourself in the mirror, your reflection, in first person). A planar reflection: a second camera
## (`camera`, in its own SubViewport sharing the window's World3D) stands at the eye mirrored
## through the glass, looks square through it, and its off-axis frustum is exactly the glass, so
## its picture drawn on the glass flipped left to right (`glass`, unshaded) is what a mirror shows.
## Its near plane is the reflecting plane: nothing behind the glass (the greybox box, the wall) is
## drawn, and the glass itself, drawn GLASS_BEHIND_M behind that plane, never reflects itself.
##
## The own player has no body in its own view, so the mirror draws a stand-in (`self_body`): a
## RemotePlayerBody with no collision on PhotoLayers.MIRROR_SELF, which only this camera draws, in
## the own colour from the roster (the host's ProfileChanged: nothing is predicted), at the local
## player's own feet, look, crouch and move, only while the own body stands (not downed, limp or
## dead). Other players are in it as they are in the hall (their bodies on LIVE_AVATAR).
##
## Cost: the reflection renders only while the window's current camera is in front of the glass
## and the glass is inside its frustum (`seen`), at HEIGHT_PX rows, with no positional shadows and
## no occlusion culling (an occluder behind the mirrored eye would cull the room). Else its
## viewport is off and the stand-in hidden.
##
## The level gives the glass, a Marker3D in GLASS_GROUP: its origin the reflecting plane's centre,
## +X right and +Y up as seen from the room, +Z toward the room, its `size_m` metadata the width and
## height in metres. A level without one draws no glass. Provisional, not a decision: the size, the
## resolution and the plain unshaded glass (no frame, no tint).

const GLASS_GROUP := &"mirror_glass"
## The glass's width and height when its marker names none.
const DEFAULT_SIZE_M := Vector2(2.0, 2.5)
## The reflection's picture height in pixels; its width follows the glass's aspect.
const HEIGHT_PX := 512
## How far behind the reflecting plane the glass is drawn: behind the reflection's near plane.
const GLASS_BEHIND_M := 0.002
## An eye nearer to the plane than this (or behind it) sees no reflection.
const MIN_EYE_M := 0.05
const FAR_M := 80.0
const BODY := preload("res://client/player/remote_player_body.tscn")

var model: ClientModel
var rules: PlayerRules
var character: CharacterSet
## The local player: the stand-in follows it (ItemWorld.set_player).
var player: PlayerController
## The camera the window shows now, or null: () -> Camera3D. Unset: this viewport's current one.
var eye := Callable()
## The level the glass marker is in; setting it places the glass (ItemWorld.set_level).
var level: Node:
	set(value):
		level = value
		_place()

var glass := MeshInstance3D.new()
var viewport := SubViewport.new()
var camera := Camera3D.new()
## The own stand-in, or null before the reflection first showed the own body.
var self_body: RemotePlayerBody

## The reflecting plane: its origin the glass's centre, +Z toward the room (orthonormal).
var _plane := Transform3D.IDENTITY
var _size := DEFAULT_SIZE_M
var _has_glass := false
var _last_plan: AvatarClips.Plan


func _init() -> void:
	name = "MirrorReflection"
	# After the cameras moved this frame (the controller, the close-up, LifeView).
	process_priority = 100
	viewport.name = "Reflection"
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.use_occlusion_culling = false
	viewport.positional_shadow_atlas_size = 0
	viewport.audio_listener_enable_3d = false
	viewport.size = _pixels(DEFAULT_SIZE_M)
	camera.name = "Lens"
	camera.cull_mask = PhotoLayers.MIRROR_VIEW
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.current = true
	viewport.add_child(camera)
	add_child(viewport)
	glass.name = "Glass"
	glass.mesh = QuadMesh.new()
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	# A mirror swaps left and right: the picture is sampled at (1 - u, v).
	material.uv1_scale = Vector3(-1.0, 1.0, 1.0)
	material.uv1_offset = Vector3(1.0, 0.0, 0.0)
	glass.material_override = material
	glass.visible = false
	add_child(glass)


func _process(delta: float) -> void:
	refresh(delta)


## Renders the reflection this frame when it is seen, else turns it off; `delta` eases the
## stand-in's crouch.
func refresh(delta: float = 0.0) -> void:
	var seen := _eye_camera()
	if not _has_glass or model == null or seen == null or not seen_by(seen):
		_off()
		return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var at := seen.global_position
	camera.global_transform = lens_of(_plane, at)
	camera.set_frustum(_size.y, offset_of(_plane, at), distance_of(_plane, at), FAR_M)
	_show_self(delta)


## Whether the reflection is rendered now.
func rendering() -> bool:
	return viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED


## Whether `seen` (a camera in the tree) sees the glass's face: its eye in front of the plane and
## the glass not wholly outside one of its frustum's planes.
func seen_by(seen: Camera3D) -> bool:
	if not _has_glass or distance_of(_plane, seen.global_position) < MIN_EYE_M:
		return false
	var corners := corners_of(_plane, _size)
	for plane: Plane in seen.get_frustum():
		var outside := true
		for corner: Vector3 in corners:
			if not plane.is_point_over(corner):
				outside = false
				break
		if outside:
			return false
	return true


## The eye's distance in front of the reflecting plane `plane` (negative behind it).
static func distance_of(plane: Transform3D, at: Vector3) -> float:
	return (at - plane.origin).dot(plane.basis.z)


## The reflection camera for an eye at `at` before `plane`: at the eye mirrored through the plane,
## looking square through it into the room (its -Z the plane's +Z), its +Y the plane's +Y; so its
## +X is the plane's -X and its picture is the mirror image turned back, which the glass undoes.
static func lens_of(plane: Transform3D, at: Vector3) -> Transform3D:
	var n := plane.basis.z
	var mirrored := at - 2.0 * distance_of(plane, at) * n
	return Transform3D(Basis(-plane.basis.x, plane.basis.y, -n), mirrored)


## The reflection camera's frustum offset for an eye at `at`: where the glass's centre lies in the
## lens's X and Y at its near plane (the reflecting plane), so the frustum is exactly the glass.
static func offset_of(plane: Transform3D, at: Vector3) -> Vector2:
	var from := at - plane.origin
	return Vector2(from.dot(plane.basis.x), -from.dot(plane.basis.y))


## The glass's four corners on `plane`, `size` wide and high.
static func corners_of(plane: Transform3D, size: Vector2) -> Array[Vector3]:
	var half_x := plane.basis.x * size.x / 2.0
	var half_y := plane.basis.y * size.y / 2.0
	return [
		plane.origin - half_x + half_y,
		plane.origin + half_x + half_y,
		plane.origin + half_x - half_y,
		plane.origin - half_x - half_y,
	]


## The stand-in's pose: the local player's feet, look, move, crouch and sneak now, or null.
static func pose_of(local: PlayerController) -> SnapshotBuffer.Pose:
	if local == null or not local.is_inside_tree():
		return null
	var pose := SnapshotBuffer.Pose.new()
	pose.position = local.global_position
	pose.facing = SnapshotBuffer.unit_or(local.look_vector(), Vector3.FORWARD)
	var angles := SnapshotBuffer.look_angles(pose.facing, Vector2.ZERO)
	pose.yaw = angles.x
	pose.pitch = angles.y
	pose.velocity = local.velocity
	pose.crouched = local.is_crouched()
	pose.sneaking = local.is_sneaking()
	return pose


## Forgets the session (it ended): the reflection off, the stand-in gone.
func clear() -> void:
	_off()
	if self_body != null:
		self_body.queue_free()
		remove_child(self_body)
		self_body = null
	_last_plan = null
	model = null
	player = null


func _eye_camera() -> Camera3D:
	if eye.is_valid():
		return eye.call() as Camera3D
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func _off() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if self_body != null:
		self_body.visible = false


## Draws the stand-in where the own body stands, or hides it.
func _show_self(delta: float) -> void:
	var own := model.own_peer
	var pose := pose_of(player)
	if own <= 0 or pose == null or model.body_life_of(own) != ClientModel.Life.ALIVE:
		if self_body != null:
			self_body.visible = false
		return
	var first := self_body == null
	if first:
		self_body = BODY.instantiate() as RemotePlayerBody
		self_body.name = "Self"
		self_body.rules = rules
		self_body.peer = own
		add_child(self_body)
		# Never in the live physics: no device ray, sight cast or push search finds it.
		self_body.collision_layer = 0
		self_body.collision_mask = 0
		self_body.set_character(character)
		# No shadow: the own view has none of its own body.
		PhotoLayers.assign(self_body, PhotoLayers.MIRROR_SELF, false)
	self_body.visible = true
	pose.posed = model.posed
	self_body.set_colour(BodyColours.of(model.colour_of(own)))
	self_body.set_crouched(pose.crouched, INF if first else delta)
	self_body.set_sneaking(pose.sneaking)
	self_body.set_pose(pose)
	var state := AvatarClips.State.new()
	state.yaw = self_body.body_yaw
	state.crouched = pose.crouched
	state.posed = pose.posed
	state.drawn_move = pose.velocity
	state.was_back = _last_plan != null and _last_plan.back
	var walk := rules.walk_speed_mps if rules != null else 0.0
	var sprint := rules.sprint_speed_mps if rules != null else 0.0
	_last_plan = AvatarClips.plan(state, walk, sprint)
	self_body.apply_plan(_last_plan)


## Puts the glass on the level's marker, or hides it with none.
func _place() -> void:
	var marker := _marker()
	_has_glass = marker != null
	glass.visible = _has_glass
	if not _has_glass:
		_off()
		return
	_plane = marker.global_transform.orthonormalized()
	_size = DEFAULT_SIZE_M
	if marker.has_meta(&"size_m"):
		_size = marker.get_meta(&"size_m") as Vector2
	(glass.mesh as QuadMesh).size = _size
	glass.global_transform = _plane.translated(-_plane.basis.z * GLASS_BEHIND_M)
	viewport.size = _pixels(_size)


## The level's glass marker, or null (no level, none, or the level not in the tree).
func _marker() -> Node3D:
	if not is_inside_tree() or not is_instance_valid(level) or not level.is_inside_tree():
		return null
	for node: Node in level.get_tree().get_nodes_in_group(GLASS_GROUP):
		if level.is_ancestor_of(node) and node is Node3D:
			return node as Node3D
	return null


static func _pixels(size: Vector2) -> Vector2i:
	var wide := maxi(1, roundi(HEIGHT_PX * size.x / maxf(size.y, 0.01)))
	return Vector2i(wide, HEIGHT_PX)
