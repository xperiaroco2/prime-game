class_name PinballCloseUp
extends Node3D
## The seated player's close-up of the pinball table (#1400; ARCHITECTURE §4.7.63): while the host
## says the own player holds the machine's seat (ClientPinball.player, PinballState), the own
## screen eases from the eye to a fixed view over the table (the level's close-up marker) and
## stays there; when the seat ends it eases back to the live eye. Only the seated player's own
## window: everyone else's keeps its camera and sees the machine from where they stand.
##
## - While seated the player's movement keys and look are held (PlayerController.held, as the
##   photo viewfinder holds them) and its first-person hand is hidden; the crosshair stays on the
##   machine, so E there still gives the seat up. The held flag is let go when the ease out starts
##   (the player may walk at once), and only if the close-up set it.
## - It never touches the controller's head, pitch or yaw: a separate camera, so the view after a
##   respawn or a new match (§4.7.13) is the controller's own.
## - Snap, no ease, back to the eye: on snap() (LoadMatch, a level swapped, the session gone), when
##   the own life is no longer living (a knockdown: LifeView's downed camera takes over) or the
##   marker or the player is gone. The eye is made current again only if the lens still was, so it
##   never steals the view from the downed or the spectate camera.
## - LifeView asks live_camera() (through ItemWorld.live_camera) and keeps the lens current while
##   it is up; the Esc menu opens over it and changes nothing here (PinballKeys lets the flippers
##   go).
##
## The marker's pose, the field of view and the ease time are provisional, not a decision: the
## engineer frames the shot in the editor (the marker) and on the pictures.

## The lens's vertical field of view, degrees, and near plane (provisional).
const FOV_DEG := 50.0
const NEAR_M := 0.05
## The ease from the eye to the close-up and back, seconds (provisional).
const EASE_S := 0.6

var model: ClientModel
var player: PlayerController
## The level's close-up marker (PinballViews: group `pinball_closeup`), or null.
var marker: Node3D
## The lens: current while the close-up is up.
var camera := Camera3D.new()

## 0 at the eye, 1 at the marker.
var _blend := 0.0
var _up := false
var _held_by_us := false


func _init() -> void:
	name = "PinballCloseUp"
	camera.name = "Lens"
	camera.fov = FOV_DEG
	camera.near = NEAR_M
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.cull_mask = PhotoLayers.LIVE_VIEW
	add_child(camera)


func _process(delta: float) -> void:
	step(delta)


## Whether the close-up is up (easing in, seated or easing out).
func active() -> bool:
	return _up


## How far the view is from the eye (0) toward the close-up (1), eased.
func blend() -> float:
	return _blend


## The lens while the close-up is up, else null (LifeView's view_camera through ItemWorld).
func live_camera() -> Camera3D:
	return camera if _up else null


## Whether the own player holds the seat and the close-up can show: living, here, with a marker.
func seated() -> bool:
	if model == null or model.own_peer <= 0 or model.pinball.player != model.own_peer:
		return false
	return _can_show() and model.body_life_of(model.own_peer) == ClientModel.Life.ALIVE


## One frame of `delta` seconds: eases toward the close-up while seated, back to the eye after.
func step(delta: float) -> void:
	if seated():
		if not _up:
			_up = true
			_blend = 0.0
			player.hand_view().visible = false
			camera.make_current()
		if not player.held:
			player.held = true
			_held_by_us = true
		_blend = minf(1.0, _blend + delta / EASE_S)
	elif _up:
		if (
			model == null
			or not _can_show()
			or model.body_life_of(model.own_peer) != ClientModel.Life.ALIVE
		):
			snap()
			return
		_let_go()
		_blend = maxf(0.0, _blend - delta / EASE_S)
		if _blend <= 0.0:
			snap()
			return
	else:
		return
	camera.global_transform = pose_between(
		player.get_camera().global_transform, marker.global_transform, _blend
	)


## Back to the eye at once (no ease): the lens let go, the eye current if the lens was, the hand
## shown, the keys free.
func snap() -> void:
	if not _up:
		return
	_up = false
	_blend = 0.0
	var was_current := camera.is_inside_tree() and camera.current
	if was_current:
		camera.clear_current(false)
	_let_go()
	if _player_here():
		player.hand_view().visible = true
		if was_current:
			player.get_camera().make_current()


## Forgets the session (it ended).
func clear() -> void:
	snap()
	model = null
	player = null
	marker = null


## The camera pose `weight` (0 to 1, smoothstepped) of the way from `eye` to `close_up`.
static func pose_between(eye: Transform3D, close_up: Transform3D, weight: float) -> Transform3D:
	var t := smoothstep(0.0, 1.0, clampf(weight, 0.0, 1.0))
	return eye.interpolate_with(close_up, t).orthonormalized()


func _let_go() -> void:
	if _held_by_us and _player_here():
		player.held = false
	_held_by_us = false


func _can_show() -> bool:
	return (
		is_inside_tree()
		and _player_here()
		and is_instance_valid(marker)
		and marker.is_inside_tree()
	)


func _player_here() -> bool:
	return is_instance_valid(player) and player.is_inside_tree()
