class_name PhotoViewfinder
extends Node3D
## The photo camera's viewfinder (#786, photo P7; the photo ADR §3.1, §9; ARCHITECTURE §4.7.56):
## while it is up, the own screen looks through the camera station's lens instead of the own eye,
## framed as the host's shot is (PhotoUse.frame_of: PhotoFrame's pose, `Camera3D.fov` the type's
## `fov_deg`, `keep_aspect` KEEP_HEIGHT), the screen outside the photo's aspect masked black, and
## the frames left on the film shown in the photo's corner. It reads only the own ClientModel and
## the client's own copy of the mode, and sends nothing: ItemInteractions opens it (a tap of E on a
## camera holding a film) and sends the shot.
##
## It opens only while the own player could use the camera from where it stands, as G6's usable
## hint offers it: alive, the camera holding a film, the feet in its cylinder (TargetChoice.
## stands_at, the host's AtStation less the hint's margin) and, checked in each physics step as
## ItemInteractions' target is, the host's StationInSight from the own eye to the camera's lifted
## floor point. So no view opens from afar or through a window, and the lens shows no more than
## standing at the camera would (the M4 render checklist, items 3 and 5). It closes as soon as any
## of those stops holding (the film taken out or gone, the player pushed out, the line cut, a
## knockdown, a death), on a hit (Damaged), and on leave(): E again, Esc (Game), the keys no longer
## listening (ItemInteractions). While it is up the player's movement keys and look are held
## (PlayerController.held) and its first-person hand is hidden (it would float in front of the
## lens).

## After ItemInteractions (6), which cast this step's target.
const PHYSICS_PRIORITY := 7
## The mask's canvas layer: under GameUi's (1), so the HUD's vitals and slots draw over it.
const MASK_LAYER := 0
## The frames left's text height as a fraction of the photo's, and its inset from the photo's
## bottom right corner as one of the photo's height (looks; placeholders, "not a decision").
const COUNTER_HEIGHT := 0.06
const COUNTER_INSET := 0.03

var model: ClientModel
var mode: GameMode
var player: PlayerController
## The lens: current while the view is up (LifeView asks live_camera()).
var camera := Camera3D.new()
## The black bars outside the photo's aspect and the frames left, shown while the view is up.
var mask := CanvasLayer.new()
var counter := Label.new()

var _bars: Array[ColorRect] = []
var _station := -1


func _init() -> void:
	name = "PhotoViewfinder"
	process_physics_priority = PHYSICS_PRIORITY
	camera.name = "Lens"
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = PhotoFrame.NEAR_M
	camera.cull_mask = PhotoLayers.LIVE_VIEW
	add_child(camera)
	mask.name = "Mask"
	mask.layer = MASK_LAYER
	mask.visible = false
	for side: String in ["Left", "Right", "Top", "Bottom"]:
		var bar := ColorRect.new()
		bar.name = side
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mask.add_child(bar)
		_bars.append(bar)
	counter.name = "FramesLeft"
	counter.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counter.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	counter.label_settings = LabelSettings.new()
	counter.label_settings.font_color = Color.WHITE
	counter.label_settings.outline_color = Color.BLACK
	mask.add_child(counter)
	add_child(mask)


## Whether the view is up.
func active() -> bool:
	return _station >= 0


## The camera station the view looks through, -1 for none.
func station() -> int:
	return _station


## The camera the living see through now (LifeView's `view_camera`): the lens while the view is
## up, else null (the own eye).
func live_camera() -> Camera3D:
	return camera if active() else null


## Opens the view at camera station `id` if it may open now (can_enter()); whether it did.
func enter(id: int) -> bool:
	if active() or not can_enter(id):
		return false
	_station = id
	var frame := PhotoUse.frame_of(model, mode, id)
	camera.global_transform = Transform3D(frame.basis, frame.lens)
	_fit()
	camera.make_current()
	mask.visible = true
	player.hand_view().visible = false
	player.held = true
	return true


## Whether the view may open at camera station `id`: the own player alive with a body in the tree,
## no two-handed item in the hand (the shot's HandNotTwoHanded; E there only takes the film out),
## the camera holding a film and framing a placed photo spot, the feet in its cylinder. The line of
## sight is the target's (ItemInteractions) and, from then on, each physics step's (holds()).
func can_enter(id: int) -> bool:
	if model == null or mode == null or not _player_here():
		return false
	if model.life_of(model.own_peer) != ClientModel.Life.ALIVE:
		return false
	if not PhotoUse.is_loaded_camera(model, mode, id) or PhotoUse.frame_of(model, mode, id) == null:
		return false
	if not StationUse.hand_allows_at(model, mode, id):
		return false
	return TargetChoice.stands_at(model.stations[id], mode, player.global_position)


## Closes the view, if up: the own eye again, the hand shown, the keys free; whether it was up.
func leave() -> bool:
	if not active():
		return false
	_station = -1
	mask.visible = false
	if camera.is_inside_tree() and camera.current:
		camera.clear_current(false)
	if _player_here():
		player.hand_view().visible = true
		player.held = false
		player.get_camera().make_current()
	return true


## Whether the open view may stay up (see the class doc): can_enter() still holds for its camera
## and the line from the own eye to the camera's lifted floor point is clear of the level (the
## host's StationInSight). Reads the physics space: only in a physics step.
func holds() -> bool:
	if not active() or not can_enter(_station):
		return false
	var eye := player.get_camera().global_position
	var floor_point := Items.lifted(model.stations[_station].position)
	var sight := PhysicsRayQueryParameters3D.create(
		eye, floor_point, PhysicsLayers.WORLD, [player.get_rid()]
	)
	return get_world_3d().direct_space_state.intersect_ray(sight).is_empty()


## The session's events (ItemWorld): a hit closes the view, and so does any event after which the
## own player is no longer alive (a knockdown, a death) or the camera holds no film.
func on_event(event_name: StringName, _fields: Dictionary) -> void:
	if not active():
		return
	if event_name == &"Damaged" or not can_enter(_station):
		leave()


## Forgets the session (it ended).
func clear() -> void:
	leave()
	model = null
	player = null


## The vertical field of view, in degrees, that shows a frame of vertical field of view `fov_deg`
## and aspect `aspect` (width over height) whole on a `screen` with `keep_aspect` KEEP_HEIGHT: the
## frame's own where the screen is at least as wide as the photo; on a narrower screen the one
## whose width just holds the frame's (the mask then bars the top and bottom).
static func fov_for(fov_deg: float, aspect: float, screen: Vector2) -> float:
	if screen.x <= 0.0 or screen.y <= 0.0 or aspect <= 0.0:
		return fov_deg
	var screen_aspect := screen.x / screen.y
	if screen_aspect >= aspect:
		return fov_deg
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(fov_deg) / 2.0) * aspect / screen_aspect))


## Where a photo of `aspect` (width over height) shows on a `screen` (fov_for()'s frame): the full
## height and centred, or on a narrower screen the full width and centred.
static func photo_rect(aspect: float, screen: Vector2) -> Rect2:
	if aspect <= 0.0:
		return Rect2(Vector2.ZERO, screen)
	var size := Vector2(screen.y * aspect, screen.y)
	if size.x > screen.x:
		size = Vector2(screen.x, screen.x / aspect)
	return Rect2((screen - size) / 2.0, size)


func _physics_process(_delta: float) -> void:
	if active() and not holds():
		leave()


func _process(_delta: float) -> void:
	if active():
		_fit()


## The lens's field of view, the bars and the frames left for the screen now (it may be resized).
func _fit() -> void:
	var type := PhotoUse.type_of(mode, model.stations[_station].kind)
	var screen := get_viewport().get_visible_rect().size
	camera.fov = fov_for(type.fov_deg, type.aspect, screen)
	var photo := photo_rect(type.aspect, screen)
	var rects: Array[Rect2] = [
		Rect2(0.0, 0.0, photo.position.x, screen.y),
		Rect2(photo.end.x, 0.0, screen.x - photo.end.x, screen.y),
		Rect2(photo.position.x, 0.0, photo.size.x, photo.position.y),
		Rect2(photo.position.x, photo.end.y, photo.size.x, screen.y - photo.end.y),
	]
	for i in _bars.size():
		_bars[i].position = rects[i].position
		_bars[i].size = rects[i].size
	var height := photo.size.y * COUNTER_HEIGHT
	var inset := Vector2.ONE * photo.size.y * COUNTER_INSET
	counter.label_settings.font_size = maxi(roundi(height), 1)
	counter.label_settings.outline_size = maxi(roundi(height / 8.0), 1)
	counter.size = Vector2(photo.size.x / 4.0, height * 1.5)
	counter.position = photo.end - inset - counter.size
	counter.text = str(PhotoUse.frames_left(model, mode, _station))


## Whether the local player is set and in the tree.
func _player_here() -> bool:
	return is_instance_valid(player) and player.is_inside_tree()
