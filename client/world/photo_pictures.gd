class_name PhotoPictures
extends Node3D
## Each shot's picture, rendered on this client from its ShotTaken record (#787, photo P8;
## ARCHITECTURE §4.7.58; the photo ADR §3.3, PE15). A shot folded into the own ClientModel queues
## its render; one render a frame: a SubViewport (UPDATE_ONCE, 384 px high and as wide as the type's
## aspect makes it) sharing the live World3D (no copy of the level), its Camera3D at the camera's
## frame (PhotoUse.frame_of: the host's lens, basis and the type's fov) seeing only
## PhotoLayers.PHOTO_VIEW, and a puppet per record row on PhotoLayers.PHOTO (no collision, no
## shadow), standing where the record has it (a downed row laid flat), its hand, belt and carried
## items with it. The flash is PhotoFlashes' light, still on: after RenderingServer.frame_post_draw
## the picture is read back, kept as JPEG bytes, the viewport and puppets freed, then the flash
## released. A render whose shot went is discarded, its flash released.
##
## A picture lives while the model holds the same ClientModel.Shot (a film lists it or a photo shows
## it; a recycled shot id is a new picture). Its texture decodes when first asked for
## (texture_of) and is freed after TEXTURE_FRAMES frames nobody asked for it; the bytes stay.
## Headless (`enabled` false) it renders nothing and the flash ends at PhotoFlashes' fallback.
## The live views never draw a puppet (their cull masks drop PHOTO) and no live node's `visible`
## changes. Sizes are placeholders, "not a decision".

## The picture's height in pixels (PE15: 512 x 384 at 4:3).
const HEIGHT_PX := 384
## The JPEG quality kept. Placeholder, "not a decision".
const JPEG_QUALITY := 0.8
## A texture nobody asked for this many frames is freed (the JPEG bytes stay). Placeholder.
const TEXTURE_FRAMES := 30
const BODY := preload("res://client/player/remote_player_body.tscn")

var model: ClientModel
var mode: GameMode
## The live avatars' rules and character, which the puppets copy; null: the mode's rules, no
## character.
var avatars: AvatarViews
## The flashes the renders release.
var flashes: PhotoFlashes
## Whether pictures are rendered: never on a headless client.
var enabled := DisplayServer.get_name() != "headless"
## The signal a render waits for before it reads the picture back (tests inject their own).
var drawn: Signal = RenderingServer.frame_post_draw
## Reads a drawn SubViewport into an Image (tests inject one); unset: its texture's image.
var reader := Callable()

var _pictures: Dictionary[int, Picture] = {}
var _queue: Array[Queued] = []
var _render: Render
var _frame := 0


## One kept picture.
class Picture:
	extends RefCounted
	var shot: ClientModel.Shot
	var jpeg := PackedByteArray()
	var texture: ImageTexture
	var asked_frame := 0


## A shot waiting for its render.
class Queued:
	extends RefCounted
	var id := -1
	var shot: ClientModel.Shot


## The render in hand.
class Render:
	extends RefCounted
	var id := -1
	var shot: ClientModel.Shot
	var viewport: SubViewport
	var camera: Camera3D
	var puppets: Array[RemotePlayerBody] = []


## The session's events (ItemWorld forwards them after PhotoFlashes): a ShotTaken the model folded
## queues its render. A recycled shot id drops the older one's queued render.
func on_event(event_name: StringName, fields: Dictionary) -> void:
	if event_name != &"ShotTaken" or model == null or not enabled:
		return
	var id := fields.get("shot", -1) as int
	var shot: ClientModel.Shot = model.shots.get(id)
	if shot == null:
		return
	for queued: Queued in _queue.duplicate():
		if queued.id == id:
			_queue.erase(queued)
	var queued := Queued.new()
	queued.id = id
	queued.shot = shot
	_queue.append(queued)


## Shot `shot`'s picture as a texture, decoded now if it is not; null while it has none.
func texture_of(shot: int) -> Texture2D:
	var picture: Picture = _pictures.get(shot)
	if picture == null or not _current(shot, picture.shot):
		return null
	picture.asked_frame = _frame
	if picture.texture == null:
		var image := Image.new()
		if image.load_jpg_from_buffer(picture.jpeg) != OK:
			return null
		picture.texture = ImageTexture.create_from_image(image)
	return picture.texture


func has_picture(shot: int) -> bool:
	return _pictures.has(shot)


## Whether shot `shot`'s texture is decoded now.
func has_texture(shot: int) -> bool:
	var picture: Picture = _pictures.get(shot)
	return picture != null and picture.texture != null


## How many pictures are kept.
func count() -> int:
	return _pictures.size()


## The JPEG bytes kept over every picture.
func bytes_kept() -> int:
	var total := 0
	for picture: Picture in _pictures.values():
		total += picture.jpeg.size()
	return total


## Renders queued or in hand.
func pending() -> int:
	return _queue.size() + (1 if _render != null else 0)


## The render in hand's viewport, or null (tests).
func rendering() -> SubViewport:
	return _render.viewport if _render != null else null


## The render in hand's puppets (tests).
func puppets() -> Array[RemotePlayerBody]:
	return _render.puppets if _render != null else ([] as Array[RemotePlayerBody])


## Forgets every picture and render (the session ended); queued and in-hand flashes are released.
func clear() -> void:
	for queued: Queued in _queue:
		_release(queued.id)
	_queue.clear()
	if _render != null:
		_release(_render.id)
		_free(_render)
		_render = null
	_pictures.clear()


func _process(_delta: float) -> void:
	_frame += 1
	if model == null:
		if _render != null or not _queue.is_empty() or not _pictures.is_empty():
			clear()
		return
	_drop_gone()
	if _render == null and not _queue.is_empty():
		var next: Queued = _queue.pop_front()
		_start(next.id, next.shot)


## Drops the pictures, queued renders and render in hand whose shot the model no longer holds, and
## the textures nobody asked for lately.
func _drop_gone() -> void:
	for id: int in _pictures.keys():
		var picture := _pictures[id]
		if not _current(id, picture.shot):
			_pictures.erase(id)
		elif picture.texture != null and _frame - picture.asked_frame > TEXTURE_FRAMES:
			picture.texture = null
	for queued: Queued in _queue.duplicate():
		if not _current(queued.id, queued.shot):
			_queue.erase(queued)
			_release(queued.id)
	if _render != null and not _current(_render.id, _render.shot):
		_release(_render.id)
		_free(_render)
		_render = null


func _current(id: int, shot: ClientModel.Shot) -> bool:
	return model != null and model.shots.get(id) == shot


func _start(id: int, shot: ClientModel.Shot) -> void:
	var frame := PhotoUse.frame_of(model, mode, shot.station)
	var station: ClientModel.Station = model.stations.get(shot.station)
	var type := PhotoUse.type_of(mode, station.kind) if station != null else null
	if frame == null or type == null:
		_release(id)
		return
	var render := Render.new()
	render.id = id
	render.shot = shot
	render.viewport = SubViewport.new()
	render.viewport.name = "Picture%d" % id
	render.viewport.size = Vector2i(roundi(HEIGHT_PX * type.aspect), HEIGHT_PX)
	render.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	render.viewport.transparent_bg = false
	render.viewport.msaa_3d = Viewport.MSAA_DISABLED
	render.viewport.own_world_3d = false
	render.camera = Camera3D.new()
	render.camera.cull_mask = PhotoLayers.PHOTO_VIEW
	render.camera.fov = type.fov_deg
	render.camera.keep_aspect = Camera3D.KEEP_HEIGHT
	render.camera.near = PhotoFrame.NEAR_M
	render.viewport.add_child(render.camera)
	add_child(render.viewport)
	render.camera.global_transform = Transform3D(frame.basis, frame.lens)
	render.camera.current = true
	for row: Dictionary in shot.record:
		render.puppets.append(_puppet(row))
	_render = render
	_finish(render)


## Waits for the draw, keeps the picture, frees the render and releases the flash; nothing when
## the render was discarded meanwhile.
func _finish(render: Render) -> void:
	await drawn
	if _render != render:
		return
	var image: Image = null
	if reader.is_valid():
		image = reader.call(render.viewport) as Image
	elif render.viewport.get_texture() != null:
		image = render.viewport.get_texture().get_image()
	if image != null and not image.is_empty():
		var picture := Picture.new()
		picture.shot = render.shot
		picture.jpeg = image.save_jpg_to_buffer(JPEG_QUALITY)
		picture.asked_frame = _frame
		if not picture.jpeg.is_empty():
			_pictures[render.id] = picture
	_free(render)
	_render = null
	_release(render.id)


## A puppet of record row `row`: the live avatars' rules and character, the peer's colour,
## standing (crouched as recorded) at its position, turned to its facing through SnapshotBuffer's
## guard (a relayed facing can be zero or vertical), a downed one laid flat; with its items.
func _puppet(row: Dictionary) -> RemotePlayerBody:
	var rules: PlayerRules = avatars.rules if avatars != null else null
	if rules == null and mode != null:
		rules = mode.player_rules
	var peer := row.get("peer", 0) as int
	var body := BODY.instantiate() as RemotePlayerBody
	body.name = "Puppet%d" % peer
	body.rules = rules
	body.peer = peer
	add_child(body)
	# Never in the live physics: no device ray, sight cast or push search finds it.
	body.collision_layer = 0
	body.collision_mask = 0
	body.set_character(avatars.character if avatars != null else null)
	body.set_colour(BodyColours.of(model.colour_of(peer)))
	var crouched := row.get("crouched", false) as bool
	body.set_crouched(crouched, INF)
	var facing := row.get("facing", Vector3.FORWARD) as Vector3
	var angles := SnapshotBuffer.look_angles(facing, Vector2.ZERO)
	var pose := SnapshotBuffer.Pose.new()
	pose.position = row.get("position", Vector3.ZERO) as Vector3
	pose.facing = SnapshotBuffer.unit_or(facing, Vector3.FORWARD)
	pose.yaw = angles.x
	pose.pitch = angles.y
	pose.crouched = crouched
	body.set_pose(pose)
	if body.character() != null:
		var state := AvatarClips.State.new()
		state.yaw = pose.yaw
		state.crouched = crouched
		var walk := rules.walk_speed_mps if rules != null else 0.0
		var sprint := rules.sprint_speed_mps if rules != null else 0.0
		body.apply_plan(AvatarClips.plan(state, walk, sprint))
		# Drawn this frame, before any physics step would run the tree: posed now, or the art's
		# arms-out rest (and the sockets' items with it) would be the picture.
		body.character().pose_now()
	if row.get("downed", false) as bool:
		var radius := rules.capsule_radius_m if rules != null else 0.0
		var flat := Basis(Vector3.UP, pose.yaw) * Basis(Vector3.RIGHT, -PI / 2.0)
		body.global_transform = Transform3D(flat, pose.position + Vector3.UP * radius)
	_hold(body, row.get("held_item", -1) as int, false)
	_hold(body, row.get("belt_item", -1) as int, true)
	_hold(body, row.get("belt_item2", -1) as int, true, true)
	PhotoLayers.assign(body, PhotoLayers.PHOTO, false)
	return body


## Item `id`, as the model knows it, at `body`'s hand (or carried in front), or on its belt (the
## second belt item beside the first, as `ItemViews` draws it).
func _hold(body: RemotePlayerBody, id: int, belted: bool, second := false) -> void:
	var item: ClientModel.Item = model.items.get(id) if id >= 0 else null
	if item == null:
		return
	var kind := mode.find_item_kind(item.kind) if mode != null else null
	var point := body.belt_point()
	if not belted:
		point = body.carry_point() if kind != null and kind.is_two_handed() else body.hand_point()
	var view := ItemView.make(id, item.kind, item.colour, mode)
	point.add_child(view)
	if second:
		view.position = ItemViews.SECOND_BELT_OFFSET


func _free(render: Render) -> void:
	for puppet: RemotePlayerBody in render.puppets:
		if is_instance_valid(puppet):
			puppet.queue_free()
	render.puppets.clear()
	if is_instance_valid(render.viewport):
		render.viewport.queue_free()


func _release(id: int) -> void:
	if flashes != null:
		flashes.release(id)
