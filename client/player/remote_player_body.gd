class_name RemotePlayerBody
extends StaticBody3D
## Another player as the local client sees it: a capsule on the living layer while that player is
## living, else on the downed layer, which no push searches (a downed player pushes nobody and
## nobody pushes it, §7.1; `set_living`). While its player is knocked down its capsule, head and
## collision are off (`set_downed`): AvatarViews draws the body as a RagdollView (KE7, §4.7.9),
## which the crosshair's search for a downed player to raise finds; this body keeps the attach
## points, the mouth and the sight point at the host's point. An invulnerable one wears a pulsing
## white shell (`set_invulnerable`, the avatar's flag). It has the size of the client's own copy
## of the mode's PlayerRules (`rules`), with a head that turns and nods. Only its owner's data
## moves it:
## AvatarViews places it each physics frame at SnapshotBuffer's interpolated pose (ARCHITECTURE
## §4.7), the yaw on the body and the pitch on the head, both already guarded against a degenerate
## facing. The local player never collides with it like a wall and never moves it: it pushes into
## it, and is pushed out of it when it comes into the local player (§7.1 "Pushing apart"). The
## origin is at the feet.
##
## It is teleported, and the push search of the same physics frame must see where (§4.7): so it is
## a static body, placed with force_update_transform(). Checked on 4.7.2 with Jolt: a transform
## set in `_physics_process` reaches the physics server only after the whole pass unless the
## node forces it, and a kinematic body (an AnimatableBody3D, `sync_to_physics` on or off, or a
## CharacterBody3D) shows a teleport to shape queries only after the physics step, even when set
## on the server directly; a static body shows it at once. Nothing collides with it as a wall: the
## local player's mask is the world, and its push search reads the living layer.
##
## A crouched player (the crouch ADR, KE7; `set_crouched`, from the pose's flag) has the crouched
## capsule (PlayerRules.crouch_height_m) at once, collision, greybox look, shell and sight point,
## still on its layer and placed before set_pose's force_update_transform(), so the push search of
## the same frame finds the crouched capsule; its head and everything hung on it (the mouth its
## voice plays from, the hand, belt and carry points) ease down by the eye heights' difference at
## the step's catch-up rate (`tuning`), as the own view does. A downed body lies at standing size.
##
## With a character (`set_character`, #522, §4.7.53) the animated rig draws the body in the
## capsule's place, tinted by the body colour and hidden by the same rule (downed, watched); the
## clips come from AvatarViews (`apply_plan`, `play_one_shot`), and the hand, belt and carry points
## are the rig's sockets on its bones. The collision capsule, the head, the mouth and the sight
## point are the capsule's, with or without it.

## The visor's size and how far it sits in front of the eyes, in metres (greybox looks).
const VISOR_SIZE := Vector3(0.3, 0.1, 0.12)
const VISOR_AHEAD := 0.25
## Where another player's items hang (M4-8), from the feet in the body's space, in metres (looks):
## the hand item at the right hand, the belt item at the left hip, and a two-handed item (the
## package) held in front with both hands.
const HAND_POINT := Vector3(0.45, 0.95, -0.15)
const BELT_POINT := Vector3(-0.48, 0.85, 0.0)
const CARRY_POINT := Vector3(0.0, 0.8, -0.72)
## The mouth, below the eyes (the M5 ADR §1.5: a placeholder, "not a decision"): this player's
## VoiceSpeaker hangs there (M5-5), and the muffle's ray aims at it (M5-7).
const MOUTH_BELOW_EYE_M := 0.1
## How far the aim turns from the body before the body follows (art #196: the engineer's 45
## degrees).
const BODY_DEAD_ZONE := deg_to_rad(45.0)

## The client's own copy of the mode's PlayerRules: the capsule and the eyes. Applied at once
## when set in the tree.
@export var rules: PlayerRules:
	set = set_rules
@export var color: Color = LifeLooks.PLAYER_COLOUR
## The client's feel only: the head eases to a new eye height at the step's catch-up rate
## (`view_catch_up_seconds`, as the own view does).
@export var tuning: PlayerTuning = preload("res://client/player/player_tuning.tres")
## The player it shows; 0 when none (the controller's tests).
var peer := 0
## The body's yaw (#1334, art #196): it lags the aim (the pose's yaw) inside BODY_DEAD_ZONE and
## turns once the aim leaves it (HeadLook.body_follow). Derived on each observer from the poses it
## draws, never relayed. Only the character rig turns by it: the root, the head, the mouth and the
## sight point keep the aim, as spectate reads them.
var body_yaw := 0.0

var _head: Node3D
var _shell: MeshInstance3D
var _downed := false
var _watched := false
var _crouched := false
var _sneaking := false
## Whether the capsule, meshes and shell have the crouched height now (crouched, not downed).
var _fitted_low := false
## How far the head and the points hung on it are below their standing places now, in metres:
## easing to the eye heights' difference while crouched, to 0 standing.
var _lowered := 0.0
var _hand_point := Node3D.new()
var _belt_point := Node3D.new()
var _carry_point := Node3D.new()
var _mouth_point := Node3D.new()
## The animated character (set_character, #522), or null: then the greybox capsule and visor.
var _rig: CharacterRig
## Whether body_yaw holds a drawn pose's yaw yet: the first pose (and snap_look) seeds it.
var _body_seeded := false

@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	collision_layer = PhysicsLayers.LIVING
	collision_mask = 0
	_head = Node3D.new()
	_head.name = "Head"
	add_child(_head)
	_shell = MeshInstance3D.new()
	_shell.name = "Shell"
	_shell.visible = false
	add_child(_shell)
	set_process(false)
	_add_attach_points()
	if rules != null:
		_apply_rules()


func set_rules(value: PlayerRules) -> void:
	rules = value
	if rules != null and is_node_ready():
		_apply_rules()


## Gives the body `with_set`'s animated character (#522, §4.7.53) in place of the greybox capsule
## and visor, once; null keeps the capsule. The collision capsule, the head, the mouth and the sight
## point stay as they are; the hand, belt and carry points become the rig's sockets, which follow
## its bones. Call it once the body is in the tree.
func set_character(with_set: CharacterSet) -> void:
	if with_set == null or _rig != null:
		return
	_rig = CharacterRig.make(with_set, true)
	add_child(_rig)
	_rig.set_tint(color)
	_show_looks()


## The animated character, or null (the greybox capsule).
func character() -> CharacterRig:
	return _rig


## Plays AvatarClips' `plan` on the character; nothing without one.
func apply_plan(plan: AvatarClips.Plan) -> void:
	if _rig != null:
		_rig.apply(plan)


## Plays the one-shot `clip` on the character; nothing without one.
func play_one_shot(clip: StringName) -> void:
	if _rig != null:
		_rig.play_one_shot(clip)


## Paints the capsule `value` (the player's body colour, BodyColours, #551), or tints the
## character by it. Only a change touches the mesh: AvatarViews calls it every physics frame.
## Before the body is ready, or before its rules, the colour waits for _apply_rules.
func set_colour(value: Color) -> void:
	if value == color:
		return
	color = value
	if _rig != null:
		_rig.set_tint(color)
	if not is_node_ready() or not _mesh.mesh is CapsuleMesh:
		return
	var material := (_mesh.mesh as CapsuleMesh).material as StandardMaterial3D
	material.albedo_color = color


## Puts the body on the living layer (`living`) or the downed layer, where no push finds it.
func set_living(living: bool) -> void:
	collision_layer = PhysicsLayers.LIVING if living else PhysicsLayers.DOWNED


## Hides the capsule and the head and turns the collision capsule off while the player is knocked
## down (its RagdollView is its body then), or shows them again.
func set_downed(downed: bool) -> void:
	if downed == _downed:
		return
	_downed = downed
	_show_looks()


## Whether the player is knocked down (set_downed).
func is_downed() -> bool:
	return _downed


## Crouches or stands the body (the pose's flag, the crouch ADR, KE7): the capsule, the looks and
## the sight point switch now, before set_pose places the body; the head and the points hung on it
## ease towards their new height over `delta` seconds (INF: at once, a body drawn for the first
## time).
func set_crouched(crouched: bool, delta: float) -> void:
	var changed := crouched != _crouched
	_crouched = crouched
	if rules == null or not is_node_ready():
		return
	# Called every physics frame for every body: the looks (shape, mesh and shell transforms) are
	# written only when the flag turns, as set_downed does.
	if changed:
		_show_looks()
	# At once (INF) when no rate is known: a first draw (delta INF), a mode without a step height
	# (0 * INF would be NaN) or a tuning without a catch-up time.
	var step := INF
	if (
		tuning != null
		and tuning.view_catch_up_seconds > 0.0
		and rules.step_height_m > 0.0
		and not is_inf(delta)
	):
		step = rules.step_height_m / tuning.view_catch_up_seconds * delta
	# A downed body keeps its standing size (its crouch flag can trail the life by the interpolation
	# delay): its points stay with the standing pose.
	var target := (
		rules.eye_height_m - rules.crouch_eye_height_m if crouched and not _downed else 0.0
	)
	_lowered = move_toward(_lowered, target, step)
	_place_points()


## Whether the body is drawn crouched (set_crouched): the crouched capsule, unless it lies.
func is_crouched() -> bool:
	return _crouched


## Sets whether the player sneaks (#990, the pose's flag): it changes nothing drawn (whether a
## sneaking player looks different is the engineer's open question on #989); WorldSounds reads it
## for the silent step.
func set_sneaking(value: bool) -> void:
	_sneaking = value


## Whether the pose says the player sneaks (set_sneaking).
func is_sneaking() -> bool:
	return _sneaking


## Shows the invulnerable shell (the avatar's flag): it pulses while shown.
func set_invulnerable(invulnerable: bool) -> void:
	_shell.visible = invulnerable and not _watched
	set_process(invulnerable)


func is_invulnerable() -> bool:
	return _shell.visible


## Hides the meshes while the spectate camera looks out of this player's eyes, which would sit
## inside the capsule behind the visor; the body stays where it is (a downed target's is watched
## from above and stays drawn). The node's own `visible` belongs to SightHider.
func set_watched(watched: bool) -> void:
	_watched = watched
	_show_looks()
	_shell.visible = _shell.visible and not watched


## Whether the spectate camera looks out of this player's eyes (set_watched).
func is_watched() -> bool:
	return _watched


## The point SightHider casts its ray at: the capsule's middle (crouched or not), or while knocked
## down the lying centre over the host's point, as its RagdollView's.
func sight_point() -> Vector3:
	var up := rules.capsule_radius_m if _downed else rules.height_of(_crouched) * 0.5
	return global_position + Vector3.UP * up


## Whether the body is on the living layer.
func is_living() -> bool:
	return collision_layer == PhysicsLayers.LIVING


## Places the body at `pose`: its position, the aim's yaw on the body and the pitch on the head.
## body_yaw follows the aim (BODY_DEAD_ZONE); the character turns by the body's lag behind the aim
## and its head looks the rest of the way.
func set_pose(pose: SnapshotBuffer.Pose) -> void:
	global_position = pose.position
	rotation = Vector3(0.0, pose.yaw, 0.0)
	_head.rotation = Vector3(pose.pitch, 0.0, 0.0)
	if _body_seeded:
		body_yaw = HeadLook.body_follow(body_yaw, pose.yaw, BODY_DEAD_ZONE)
	elif is_finite(pose.yaw):
		body_yaw = pose.yaw
		_body_seeded = true
	if _rig != null:
		var lag := wrapf(body_yaw - pose.yaw, -PI, PI)
		_rig.rotation = Vector3(0.0, lag, 0.0)
		_rig.set_look(-lag, pose.pitch)
	# Now, not after the pass: the local player's push search (priority 0) reads it this frame.
	force_update_transform()


## Lets the next pose seed body_yaw at its aim: a placement (a teleport, a respawn) draws the body
## facing the aim, without a turn from where it stood.
func snap_look() -> void:
	_body_seeded = false


## The head: it holds the pitch (tests read it), at the drawn eye, standing or crouched: the
## spectate camera and the ears of a dead player watching this one sit here.
func head() -> Node3D:
	return _head


func _process(_delta: float) -> void:
	LifeLooks.pulse(_shell, Time.get_ticks_msec() / 1000.0)


## Stands or crouches the mesh, the shell and the collision capsule; shows the mesh and the head
## unless knocked down or watched, and the collision unless knocked down.
func _show_looks() -> void:
	if rules == null:
		return
	var low := _crouched and not _downed
	if low != _fitted_low:
		_fit(low)
	var pose := LifeLooks.standing(rules, low)
	_shape.transform = pose
	_shape.disabled = _downed
	_mesh.transform = pose
	_shell.transform = pose
	var shown := not _downed and not _watched
	# The character draws the body and its face: the capsule and the visor stay hidden then.
	_mesh.visible = shown and _rig == null
	_head.visible = shown
	var visor := _head.get_node_or_null(^"Visor") as Node3D
	if visor != null:
		visor.visible = _rig == null
	if _rig != null:
		_rig.visible = shown


## Where this player's hand item is drawn (M4-8): the character's hand socket with one.
func hand_point() -> Node3D:
	return _rig.socket(&"Hand") if _rig != null else _hand_point


## Where this player's belt item is drawn: the belt is visible (vision revision 1, Two hands).
func belt_point() -> Node3D:
	return _rig.socket(&"Belt") if _rig != null else _belt_point


## Where this player's two-handed item (the package) is drawn: in front, with both hands.
func carry_point() -> Node3D:
	return _rig.socket(&"Carry") if _rig != null else _carry_point


## This player's mouth, MOUTH_BELOW_EYE_M below the eyes, lowered with the head while crouched: its
## voice plays from here (the M5 ADR §1.5). It stays with the standing pose while downed: nobody
## hears a downed player (the voice invariant).
func mouth_point() -> Node3D:
	return _mouth_point


func _add_attach_points() -> void:
	_hand_point.name = "HandPoint"
	_belt_point.name = "BeltPoint"
	_carry_point.name = "CarryPoint"
	_mouth_point.name = "MouthPoint"
	for point: Node3D in [_hand_point, _belt_point, _carry_point, _mouth_point]:
		add_child(point)
	_place_points()


## The head, the mouth and the item points, `_lowered` below their standing places.
func _place_points() -> void:
	var down := Vector3.DOWN * _lowered
	_hand_point.position = HAND_POINT + down
	_belt_point.position = BELT_POINT + down
	_carry_point.position = CARRY_POINT + down
	if rules == null:
		return
	_head.position = Vector3(0.0, rules.eye_height_m, 0.0) + down
	_mouth_point.position = Vector3(0.0, rules.eye_height_m - MOUTH_BELOW_EYE_M, 0.0) + down


## The capsule, the mesh and the shell at the crouched height (`low`) or the standing one; the
## mesh keeps the body's colour.
func _fit(low: bool) -> void:
	_fitted_low = low
	var capsule := CapsuleShape3D.new()
	capsule.radius = rules.capsule_radius_m
	capsule.height = rules.height_of(low)
	_shape.shape = capsule
	_mesh.mesh = LifeLooks.capsule(rules, color, 0.0, low)
	_shell.mesh = LifeLooks.shell(rules, low)


func _apply_rules() -> void:
	_fit(_crouched and not _downed)
	_show_looks()
	_place_points()
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = VISOR_SIZE
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.12)
	visor_mesh.material = dark
	var old := _head.get_node_or_null(^"Visor")
	if old != null:
		old.free()
	var visor := MeshInstance3D.new()
	visor.name = "Visor"
	visor.mesh = visor_mesh
	visor.position = Vector3(0.0, 0.0, -VISOR_AHEAD)
	visor.visible = _rig == null
	_head.add_child(visor)
