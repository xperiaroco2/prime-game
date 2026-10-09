class_name NamePlates
extends Control
## The name plate layer (#257; ARCHITECTURE §4.7.29): under the rest of the Ui, one NamePlate per
## other player whose body AvatarViews draws, while GameUi shows it (the lobby and the round, the
## UI handoff's s4 and s7). A plate shows only for a body the viewport's camera sees: the body is
## drawn (SightHider leaves out what the downed body's eye cannot see; a target watched from its
## eyes has none), its eye is within RANGE_M of the camera and in front of it, and one ray from the
## camera to that eye meets no level geometry (SightHider.sees, the world layer only), so no name
## is ever drawn through a wall (the M4 ADR's §3). The ray runs in the physics frame, after the
## bodies moved and SightHider hid; each drawn frame centres the plates on the camera's projection
## of the point ABOVE_HEAD_M over the head.
##
## A plate holds the roster's (public) name and, only on a dissident's own client, the teammate
## mark: from its own Teammates knowledge, which the host sends only to the players of a role
## whose players know each other (marked; the per-peer rule). Nothing else: no role, no health.

## How far a plate shows, from the camera to the player's eye, in metres: the engineer's "within
## about 10 m, for now" (the engineer as the designer, 2026-10-03, on #257; revisit after the
## playtests).
const RANGE_M := 10.0
## The plate's centre over the head's eye point, in metres (the UI handoff s7: head + 0.35 m).
const ABOVE_HEAD_M := 0.35
## After AvatarViews (-80) placed the bodies and SightHider (10) hid those out of the body's eye's
## sight.
const PHYSICS_PRIORITY := 11

## The others' bodies and the own ClientModel (its `model`); the game sets it, null draws nothing.
var avatars: AvatarViews

## Peer -> its plate, while that peer has a body.
var _plates: Dictionary[int, NamePlate] = {}
## The peers whose eye the camera saw in the last physics frame, through no level geometry.
var _in_sight: Dictionary[int, bool] = {}


func _init() -> void:
	name = "Plates"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_physics_priority = PHYSICS_PRIORITY


## Whether the plate of `peer` shows now.
func shows(peer: int) -> bool:
	var plate: NamePlate = _plates.get(peer)
	return plate != null and plate.visible


## The plate of `peer`, shown or not; null when that peer has no body.
func plate_of(peer: int) -> NamePlate:
	return _plates.get(peer)


## The plates shown now.
func shown_count() -> int:
	return _plates.values().filter(func(plate: NamePlate) -> bool: return plate.visible).size()


## Whether `peer` gets the teammate mark on the client of `model`: a teammate of the own role in
## its own Teammates knowledge, never the own player. An engineer's client has no Teammates for
## its role (the host sends them only to the dissidents), so it never marks anyone.
static func marked(model: ClientModel, peer: int) -> bool:
	if peer == model.own_peer or not model.teammates.has(model.role):
		return false
	return model.teammates[model.role].has(peer)


## The eye point of `body`: the head standing, the lying capsule's middle downed.
static func eye_of(body: RemotePlayerBody) -> Vector3:
	return body.sight_point() if body.is_downed() else body.head().global_position


## The point the plate centres on: ABOVE_HEAD_M over the head, or over the lying capsule.
static func plate_point(body: RemotePlayerBody) -> Vector3:
	var top := eye_of(body)
	if body.is_downed():
		top += Vector3.UP * body.rules.capsule_radius_m
	return top + Vector3.UP * ABOVE_HEAD_M


## Whether `camera` could show the plate of `body`, the ray aside: the body drawn and not watched
## from its eyes, its eye within RANGE_M and its plate point in front of the camera.
static func in_view(camera: Camera3D, body: RemotePlayerBody) -> bool:
	if not body.is_visible_in_tree() or body.is_watched():
		return false
	if camera.global_position.distance_to(eye_of(body)) > RANGE_M:
		return false
	return not camera.is_position_behind(plate_point(body))


func _physics_process(_delta: float) -> void:
	_in_sight.clear()
	var camera := _camera()
	if camera == null or not visible or avatars == null or avatars.model == null:
		return
	var space := camera.get_world_3d().direct_space_state
	for peer: int in _bodies():
		var body := avatars.body_of(peer)
		if in_view(camera, body) and SightHider.sees(space, camera.global_position, eye_of(body)):
			_in_sight[peer] = true


func _process(_delta: float) -> void:
	refresh()


## Places and fills every plate from the last physics frame's rays (the drawn frame calls it).
func refresh() -> void:
	var camera := _camera()
	var model := avatars.model if avatars != null else null
	var bodies := _bodies() if visible and camera != null else PackedInt32Array()
	for peer: int in _plates.keys():
		if not bodies.has(peer):
			_plates[peer].queue_free()
			_plates.erase(peer)
	for peer: int in bodies:
		var body := avatars.body_of(peer)
		var member: ClientModel.Member = model.roster.get(peer)
		var plate: NamePlate = _plates.get(peer)
		var showing := member != null and _in_sight.has(peer) and in_view(camera, body)
		if plate == null:
			if not showing:
				continue
			plate = NamePlate.new()
			_plates[peer] = plate
			add_child(plate)
		plate.visible = showing
		if showing:
			plate.show_player(member.name, marked(model, peer))
			plate.centre_on(camera.unproject_position(plate_point(body)))


## The other players with a body drawn by AvatarViews.
func _bodies() -> PackedInt32Array:
	var peers := PackedInt32Array()
	if avatars == null or avatars.model == null:
		return peers
	for key: Variant in avatars.model.avatars:
		var peer: int = key
		if peer != avatars.model.own_peer and avatars.body_of(peer) != null:
			peers.append(peer)
	return peers


func _camera() -> Camera3D:
	return get_viewport().get_camera_3d() if is_inside_tree() else null
