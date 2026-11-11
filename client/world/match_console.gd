class_name MatchConsole
extends Node3D
## The ship's match console in the world (#1604; ARCHITECTURE §4.7.67; prime-game-ui `ui-2.5.4`
## s04 `console-host`, `console-guest`): the match settings on a screen by the lobby's spawn, a
## SubViewport whose root is ConsoleScreen (960 x 540, the shared theme) and whose texture a quad
## on the level's screen marker shows, so whoever looks at the console reads the same screen.
##
## The crosshair works it (the handoff: "the game raycasts the screen mesh and pushes the hit point
## into the SubViewport"): each physics step the own eye's ray meets the screen's plane; within
## REACH_M, from the front and with no level or other player in between, the hit point moves the
## SubViewport's pointer (mouse motion, so the control under the crosshair hovers), and Interact
## clicks there (a left press and release) unless another E target claims the press (`yields`). Only
## the host's screen has steppers and chips to click (ConsoleScreen.refresh); a change is
## ConsoleScreen's setting_changed, which the game sends as ChangeSettings and the host checks.
## Nothing is predicted: the values come back in the model.
##
## The level gives the place: a Marker3D in SCREEN_GROUP, the screen's centre, facing its +Z (a
## placeholder the engineer moves in the editor). A level without one has no console.

signal setting_changed(id: StringName, value: Variant)

const SCREEN_GROUP := &"match_console_screen"
## The screen on the console, metres (provisional, not a decision).
const SCREEN_M := Vector2(0.96, 0.54)
## How far from the eye the crosshair works the screen, metres (provisional).
const REACH_M := 2.5
## No point on the screen.
const NOWHERE := Vector2(-1, -1)
## The screen draws its SubViewport only with the own eye this near, metres (provisional): farther
## its last frame stays on the quad. With no own player (a preview) it always draws.
const DRAW_M := 12.0
## The screen stands this far in front of anything of the level the ray may meet behind it.
const BLOCK_MARGIN_M := 0.02

var model: ClientModel
var player: PlayerController
## Read the interact key. Tests turn it off and call click() themselves.
var reads_device_input := true
## Whether the keys apply now (GamePlayer: the lobby, no Esc menu over it).
var listening := false
## Whether another E consumer has a target now (Game sets it: an item, a station, a hand-over, a
## raise, the open viewfinder): `() -> bool`; true makes E leave the screen alone, so one press
## sends one intent. Unset: the screen always takes E while aimed at.
var yields := Callable()
## The level the marker is in; setting it places the screen.
var level: Node:
	set(value):
		level = value
		_place()

var screen := ConsoleScreen.new()
var viewport := SubViewport.new()
var quad := MeshInstance3D.new()

## The level's screen marker, or null.
var _screen_at: Node3D
## The pointer's place on the screen, in its pixels (NOWHERE: the crosshair is off it).
var _point := NOWHERE


func _init() -> void:
	name = "MatchConsole"
	viewport.name = "Viewport"
	viewport.size = Vector2i(ConsoleScreen.SIZE)
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	screen.theme = GameUi.THEME
	viewport.add_child(screen)
	add_child(viewport)
	quad.name = "Screen"
	var mesh := QuadMesh.new()
	mesh.size = SCREEN_M
	quad.mesh = mesh
	quad.visible = false
	add_child(quad)
	screen.setting_changed.connect(
		func(id: StringName, value: Variant) -> void: setting_changed.emit(id, value)
	)


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	quad.material_override = material
	_place()


func _physics_process(_delta: float) -> void:
	aim(_cast())
	var draws := _screen_at != null and (not _acts() or _near())
	var update := SubViewport.UPDATE_ALWAYS if draws else SubViewport.UPDATE_DISABLED
	if viewport.render_target_update_mode != update:
		viewport.render_target_update_mode = update


func _process(_delta: float) -> void:
	if reads_device_input and listening and Input.is_action_just_pressed(&"interact"):
		press_interact()


## Whether the crosshair is on the screen now (E is the screen's then, not a chair's).
func aimed() -> bool:
	return _point != NOWHERE


## The pointer's place on the screen in its pixels, NOWHERE off it.
func point() -> Vector2:
	return _point


## E: click() unless another E consumer has a target (`yields`); whether it clicked.
func press_interact() -> bool:
	if yields.is_valid() and yields.call() as bool:
		return false
	return click()


## Interact on the screen: a left click where the crosshair is; false when it is off the screen.
func click() -> bool:
	if _point == NOWHERE:
		return false
	for down: bool in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = down
		button.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		button.position = _point
		button.global_position = _point
		viewport.push_input(button, true)
	return true


## Forgets the session (it ended): the pointer leaves the screen.
func clear() -> void:
	aim(NOWHERE)
	model = null
	player = null


## How far along `look` (a unit vector) from `eye` the ray meets the front of the screen placed at
## `at` (its centre, facing its +Z, SCREEN_M wide and high), within `reach_m`; -1 when it misses,
## meets it from behind or beyond the reach.
static func ray_hit(at: Transform3D, eye: Vector3, look: Vector3, reach_m: float) -> float:
	var normal := at.basis.z.normalized()
	var facing := look.dot(normal)
	if facing >= 0.0:
		return -1.0
	var along := (at.origin - eye).dot(normal) / facing
	if along <= 0.0 or along > reach_m:
		return -1.0
	var local := at.affine_inverse() * (eye + look * along)
	if absf(local.x) > SCREEN_M.x * 0.5 or absf(local.y) > SCREEN_M.y * 0.5:
		return -1.0
	return along


## The screen's pixel (ConsoleScreen.SIZE) at the world `point` on the screen placed at `at`.
static func pixel_of(at: Transform3D, point_at: Vector3) -> Vector2:
	var local := at.affine_inverse() * point_at
	var u := local.x / SCREEN_M.x + 0.5
	var v := 0.5 - local.y / SCREEN_M.y
	return Vector2(u, v) * ConsoleScreen.SIZE


## Where the own eye's ray meets the screen now, in its pixels, or NOWHERE.
func _cast() -> Vector2:
	if _screen_at == null or not listening or not _acts():
		return NOWHERE
	var eye := player.get_camera().global_position
	var look := player.look_vector()
	var at := quad.global_transform
	var along := ray_hit(at, eye, look, REACH_M)
	if along < 0.0:
		return NOWHERE
	var hit_at := eye + look * along
	# The level or another player's body between the eye and the screen hides it.
	var blocking := PhysicsLayers.WORLD | PhysicsLayers.LIVING | PhysicsLayers.DOWNED
	var query := PhysicsRayQueryParameters3D.create(
		eye, hit_at - look * BLOCK_MARGIN_M, blocking, [player.get_rid()]
	)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return NOWHERE
	return pixel_of(at, hit_at)


## Moves the SubViewport's pointer to `now`, the screen's pixel (NOWHERE: off the screen), entering
## and leaving the screen as it crosses it; each physics step gives the crosshair's.
func aim(now: Vector2) -> void:
	if now == _point:
		return
	var before := _point
	_point = now
	if now == NOWHERE:
		viewport.notify_mouse_exited()
		return
	if before == NOWHERE:
		viewport.notify_mouse_entered()
	var motion := InputEventMouseMotion.new()
	motion.position = now
	motion.global_position = now
	motion.relative = Vector2.ZERO if before == NOWHERE else now - before
	viewport.push_input(motion, true)


## Whether the own eye is within DRAW_M of the screen.
func _near() -> bool:
	return player.get_camera().global_position.distance_to(quad.global_position) <= DRAW_M


## Whether the own player works the console: a session, a local player in the tree, living.
func _acts() -> bool:
	return (
		model != null
		and player != null
		and player.is_inside_tree()
		and model.body_life_of(model.own_peer) == ClientModel.Life.ALIVE
	)


## Places the screen on the level's marker; with none the console is hidden and draws nothing.
func _place() -> void:
	_screen_at = _marker()
	quad.visible = _screen_at != null
	viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if _screen_at != null else SubViewport.UPDATE_DISABLED
	)
	if _screen_at != null:
		quad.global_transform = _screen_at.global_transform
	else:
		aim(NOWHERE)


## The level's screen marker, or null (no level, none, or the level not in the tree).
func _marker() -> Node3D:
	if not is_inside_tree() or not is_instance_valid(level) or not level.is_inside_tree():
		return null
	for node: Node in level.get_tree().get_nodes_in_group(SCREEN_GROUP):
		if level.is_ancestor_of(node) and node is Node3D:
			return node as Node3D
	return null
