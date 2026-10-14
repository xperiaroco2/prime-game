class_name RagdollView
extends RigidBody3D
## A knocked-down player's body as this client draws it (the knockdown ADR's KE7, ARCHITECTURE
## §4.7.9): looks only, a ragdoll held to the host's point. On the placeholder avatar it is one
## capsule of the client's own PlayerRules (radius, standing height), on the `downed` layer with
## the world mask only, so it falls, flies and rolls against the level and never against a player,
## another ragdoll or a client-only object.
##
## With a character (#522, §4.7.53: setup() given a CharacterSet with ragdoll data) the capsule
## gives way to a fresh CharacterRig of its own, top_level, whose skeleton gets the art's
## PhysicalBone3Ds (RagdollBuilder) on the same layer and mask. This node stays as the anchor:
## frozen, with no mesh and no shape on no layer (never hidden through `visible`, which SightHider
## owns and which hides the rig with it), following the pelvis so `global_position` still says
## where it lies. The bones are the only ray target, named to their peer by of_collider(). The same
## spring holds the pelvis (the data's parentless body) to the lying centre (the point plus the
## pelvis' smallest half extent), the vertical term whole, across the floor faded by how much the
## pelvis lies, and it changes every bone's velocity alike, so it moves the body, not its joints;
## a snap moves every bone by the same offset, measured from where the pelvis belongs as it lies
## now (a standing one stands over the lying centre, so the feet stay on the point). The fall
## starts from the idle pose, tipped over as the capsule is (_tip_rig), one physics frame after the
## node enters the tree (the bodies need a space).
##
## The host's point (`held_point()`, the interpolated pose's position) is the host capsule's lowest
## point (KE14). The spring pulls the capsule's centre to the lying centre over it, the point plus
## the capsule's radius, so a ragdoll at rest lies exactly where the host's body rests and is never
## pressed into the floor. Each physics step `_integrate_forces` moves the centre there at once
## when it is farther than SNAP_M (keeping its turn and taking the host's velocity), else changes
## its velocity by a spring and a damper towards the point and the host's velocity; across the
## floor that pull grows from none while the capsule stands to all of it once it lies, so it falls
## over its lowest end rather than being held up by its centre. The engine's gravity acts on it as
## on the host's body, so in flight the two fall alike.
##
## start() stands it on the point, turned with the player's yaw, with the host's velocity, and
## tips it towards its horizontal velocity, or backwards with none: a balanced upright capsule
## pulled down through its centre would otherwise stay standing (every launch is 0 today).
## lie_at_rest() lays it along the yaw's forward axis at rest: a body with no ragdoll to keep.
##
## Nothing reads its pose (the render checklist's item 1): the raise's reach, the cameras, the ears
## and SightHider use the host's point (sight_point()). It never sleeps: a sleeping body gets no
## _integrate_forces, and a snap to a far point would wait. Always top_level: its transform is the
## physics', whatever node holds it.

## Farther than this from the lying centre over the host's point, the centre moves there at once
## (KE7's snap distance, a client constant): a placeholder, "not a decision".
const SNAP_M := 1.0
## The spring's stiffness (per s²) and its damper (per s), on a mass of 1: about critically damped,
## settling in a few tenths of a second. Placeholders, "not a decision".
const SPRING_K := 60.0
const SPRING_D := 12.0
## How fast start() tips the standing capsule over, in radians per second: a placeholder, "not a
## decision".
const TIP_RAD_PER_S := 2.0
## The capsule's friction on the level: low, so the spring slides a lying capsule back over the
## point rather than the floor holding it off (a placeholder, "not a decision").
const FRICTION := 0.2
## Below this horizontal speed start() tips it backwards, in m/s: a placeholder, "not a decision".
const STILL_MPS := 0.05

const RagdollBuilder := preload("res://client/player/character/ragdoll_builder.gd")

## The player it shows.
var peer := 0

var _rules: PlayerRules
var _point := Vector3.ZERO
var _velocity := Vector3.ZERO
var _dead := false
## The velocities start() and lie_at_rest() give, set on the body's state in its next step: one
## set on the node before it is in a physics space does not reach the body.
var _kick := false
var _kick_linear := Vector3.ZERO
var _kick_angular := Vector3.ZERO
var _mesh := MeshInstance3D.new()
var _shape := CollisionShape3D.new()
## The character's rig, its simulator, its ragdoll data, its bodies and its pelvis; null and empty
## on the capsule.
var _rig: CharacterRig
var _sim: PhysicalBoneSimulator3D
var _data: Dictionary = {}
var _bones: Array[PhysicalBone3D] = []
var _pelvis: PhysicalBone3D
## The pelvis' height over the point when it lies: its shape's smallest half extent.
var _pelvis_lying_m := 0.0
## The rig's fall waits for the tree: started, lying (lie_at_rest), at this velocity.
var _pending := false
var _pending_lying := false
var _pending_velocity := Vector3.ZERO
## The pelvis body's own axis that points up the body (from the feet to the head).
var _pelvis_up := Vector3.UP
## How far the standing (idle) pelvis is over the lying centre: the snap's measure (_pull_rig).
var _pelvis_stand_m := 0.0


## The RagdollView `node` belongs to (itself, or one of its rig's bones or their shapes), or null:
## what a ray's collider names.
static func of_collider(node: Object) -> RagdollView:
	var at := node as Node
	while at != null:
		if at is RagdollView:
			return at as RagdollView
		at = at.get_parent()
	return null


func _init() -> void:
	top_level = true
	collision_layer = PhysicsLayers.DOWNED
	collision_mask = PhysicsLayers.WORLD
	can_sleep = false
	continuous_cd = true
	custom_integrator = false
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = FRICTION
	_mesh.name = "Mesh"
	add_child(_mesh)
	_shape.name = "Shape"
	add_child(_shape)


## Sizes it from `rules` (the client's own copy of the mode's PlayerRules) for `peer` in `tint`;
## with `character` (and its ragdoll data) it is that character's skeleton instead (see above).
func setup(rules: PlayerRules, for_peer: int, tint: Color, character: CharacterSet = null) -> void:
	_rules = rules
	peer = for_peer
	name = "Ragdoll%d" % for_peer
	if character != null and not character.ragdoll.is_empty():
		_wear(character)
		_paint(tint)
		return
	var capsule := CapsuleShape3D.new()
	capsule.radius = rules.capsule_radius_m
	capsule.height = rules.capsule_height_m
	_shape.shape = capsule
	_mesh.mesh = LifeLooks.capsule(rules, tint)


## The character's rig, or null on the capsule.
func rig() -> CharacterRig:
	return _rig


## The rig's PhysicalBone3Ds (empty on the capsule).
func bones() -> Array[PhysicalBone3D]:
	return _bones


## The rig's pelvis body (the data's parentless one), or null on the capsule.
func pelvis() -> PhysicalBone3D:
	return _pelvis


## Stands it on `point`, turned by `yaw`, moving at `velocity`, and tips it over (see above).
func start(point: Vector3, yaw: float, velocity: Vector3) -> void:
	hold(point, velocity)
	if _rig != null:
		_place_rig(Transform3D(Basis(Vector3.UP, yaw), point), false)
		return
	var turn := Basis(Vector3.UP, yaw)
	transform = Transform3D(turn, point + Vector3.UP * _rules.capsule_height_m * 0.5)
	var flat := Vector3(_velocity.x, 0.0, _velocity.z)
	var towards := flat.normalized() if flat.length() > STILL_MPS else turn.z
	_set_velocities(_velocity, Vector3.UP.cross(towards) * TIP_RAD_PER_S)


## Lays it on `point` at rest, along the forward axis (-Z) of `yaw`.
func lie_at_rest(point: Vector3, yaw: float) -> void:
	hold(point, Vector3.ZERO)
	var lying := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)
	if _rig != null:
		_place_rig(Transform3D(lying, point), true)
		return
	transform = Transform3D(lying, lying_centre())
	_set_velocities(Vector3.ZERO, Vector3.ZERO)


## Holds it to the host's `point` moving at `velocity` from the next physics step on. A velocity
## that is not finite counts as none, and one faster than SnapshotBuffer.SNAP_SPEED_MPS, which no
## one runs or flies, is cut to it: the spring writes it into the body's state every step.
func hold(point: Vector3, velocity: Vector3) -> void:
	_point = point
	var finite := velocity if velocity.is_finite() else Vector3.ZERO
	_velocity = finite.limit_length(SnapshotBuffer.SNAP_SPEED_MPS)


## The velocity it is held to.
func held_velocity() -> Vector3:
	return _velocity


## The host's point it is held to.
func held_point() -> Vector3:
	return _point


## Where the spring pulls its centre: the lying capsule's centre (or the rig's lying pelvis) over
## the host's point.
func lying_centre() -> Vector3:
	if _rig != null:
		return _point + Vector3.UP * _pelvis_lying_m
	return _point + Vector3.UP * _rules.capsule_radius_m


## Where SightHider looks at it: the host's lying centre, never the tumbling pose (KE7).
func sight_point() -> Vector3:
	return lying_centre()


## Paints the capsule `tint` (the player's body colour, BodyColours); a dead one stays grey.
func set_colour(tint: Color) -> void:
	if _dead:
		return
	_paint(tint)


## The death (KD7 (a)): it keeps its pose, greyed, held still at the body's `point`, on no layer, so
## no ray (the raise, the items) stops at a body; BodyViews draws the cross over it.
func make_dead(point: Vector3) -> void:
	_paint(LifeLooks.BODY_COLOUR)
	_dead = true
	collision_layer = 0
	for bone: PhysicalBone3D in _bones:
		bone.collision_layer = 0
	hold(point, Vector3.ZERO)


func is_dead() -> bool:
	return _dead


## The capsule's (or the rig's tint) colour now.
func colour() -> Color:
	if _rig != null:
		return _rig.tint()
	var material := (_mesh.mesh as CapsuleMesh).material as StandardMaterial3D
	return material.albedo_color


func _physics_process(delta: float) -> void:
	if _rig == null or _rules == null:
		return
	if _pending:
		_begin_fall()
		return
	if _sim.is_simulating_physics():
		_pull_rig(delta)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _rules == null or _rig != null:
		return
	if _kick:
		_kick = false
		state.linear_velocity = _kick_linear
		state.angular_velocity = _kick_angular
	var target := lying_centre()
	var origin := state.transform.origin
	if origin.distance_to(target) > SNAP_M:
		state.transform = Transform3D(state.transform.basis, target)
		state.linear_velocity = _velocity
		return
	var pull := (target - origin) * SPRING_K + (_velocity - state.linear_velocity) * SPRING_D
	# Across the floor the spring pulls as hard as the capsule lies: standing, a pull of its centre
	# back over the point would hold it up against its fall, which pivots on its lowest end.
	var upright := absf(state.transform.basis.y.normalized().dot(Vector3.UP))
	var across := 1.0 - upright
	pull = Vector3(pull.x * across, pull.y, pull.z * across)
	state.linear_velocity += pull * state.step


func _set_velocities(linear: Vector3, angular: Vector3) -> void:
	linear_velocity = linear
	angular_velocity = angular
	_kick = true
	_kick_linear = linear
	_kick_angular = angular


## Gives up the capsule for `character`'s rig and bodies (see above).
func _wear(character: CharacterSet) -> void:
	remove_child(_mesh)
	_mesh.free()
	remove_child(_shape)
	_shape.free()
	collision_layer = 0
	collision_mask = 0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	_data = character.ragdoll
	_rig = CharacterRig.make(character)
	_rig.top_level = true
	add_child(_rig)
	_sim = RagdollBuilder.build(_rig.skeleton, _data)
	var by_bone: Dictionary = RagdollBuilder.bodies(_sim)
	for entry: Variant in _data["bones"] as Array:
		var bone := entry as Dictionary
		var body := by_bone.get(str(bone["bone"])) as PhysicalBone3D
		if body == null:
			continue
		body.collision_layer = PhysicsLayers.DOWNED
		body.collision_mask = PhysicsLayers.WORLD
		body.can_sleep = false
		# The capsule's low friction, not the data's: the floor must not hold the body off the point.
		body.friction = FRICTION
		_bones.append(body)
		if bone.get("parent") == null and _pelvis == null:
			_pelvis = body
			_pelvis_lying_m = _smallest_half(body)


## The smallest half extent of `body`'s first shape (a box's or a capsule's radius).
static func _smallest_half(body: PhysicalBone3D) -> float:
	for node: Node in body.get_children():
		var shape := (node as CollisionShape3D).shape if node is CollisionShape3D else null
		if shape is BoxShape3D:
			var size := (shape as BoxShape3D).size
			return minf(size.x, minf(size.y, size.z)) * 0.5
		if shape is CapsuleShape3D:
			return (shape as CapsuleShape3D).radius
	return 0.1


## Puts the rig at `at` (its feet's frame) and starts its fall at the next physics step in the
## tree; `lying`: the pelvis is moved over the lying centre and nothing moves.
func _place_rig(at: Transform3D, lying: bool) -> void:
	_rig.transform = at
	transform = at
	_pending = true
	_pending_lying = lying
	_pending_velocity = Vector3.ZERO if lying else _velocity


## Poses the rig idle, stops its animation and starts the simulation (the builder's start).
func _begin_fall() -> void:
	_pending = false
	if _pelvis == null:
		return
	_rig.tree.advance(0.0)
	_rig.tree.active = false
	if _pending_lying:
		_rig.global_position += lying_centre() - _pelvis_at_pose().origin
	# The pelvis axis that points up the body (the rig's up at the idle pose), whatever its bone's
	# own axes: the spring's measure of how much it lies.
	_pelvis_up = _pelvis_at_pose().basis.inverse() * _rig.global_basis.y.normalized()
	# The idle pelvis' height over the feet, along the rig's up, whether it stands or lies.
	var stand := (_rig.global_transform.affine_inverse() * _pelvis_at_pose().origin).y
	_pelvis_stand_m = maxf(stand - _pelvis_lying_m, 0.0)
	RagdollBuilder.start(_sim, _data, _pending_velocity)
	if not _pending_lying:
		_tip_rig()


## Tips the standing rig over as start() tips the capsule: each body gets the velocity of a turn
## about the feet at TIP_RAD_PER_S towards the horizontal velocity, or backwards with none, so the
## legs do not fold under a balanced body that would then sit on its pelvis.
func _tip_rig() -> void:
	var flat := Vector3(_pending_velocity.x, 0.0, _pending_velocity.z)
	var towards := flat.normalized() if flat.length() > STILL_MPS else _rig.global_basis.z
	var feet := _rig.global_position.y
	for bone: PhysicalBone3D in _bones:
		var up := maxf(bone.global_position.y - feet, 0.0)
		bone.linear_velocity = _pending_velocity + towards * TIP_RAD_PER_S * up


## The pelvis body's transform from the skeleton's pose (before the simulation runs).
func _pelvis_at_pose() -> Transform3D:
	var skeleton := _rig.skeleton
	var bone := skeleton.find_bone(str(_pelvis.get(&"bone_name")))
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone) * _pelvis.body_offset


## The spring on the rig (see above): from the pelvis' state, the same velocity change for every
## bone; farther than SNAP_M from where the pelvis belongs (the lying centre, raised by the
## standing pelvis height as much as it stands), every bone moved by the same offset at the held
## velocity.
func _pull_rig(delta: float) -> void:
	var pelvis_state := PhysicsServer3D.body_get_direct_state(_pelvis.get_rid())
	if pelvis_state == null:
		return
	var target := lying_centre()
	var origin := pelvis_state.transform.origin
	var up := (pelvis_state.transform.basis * _pelvis_up).normalized()
	var upright := absf(up.dot(Vector3.UP))
	# The snap measures from where the pelvis belongs as it lies now: a standing pelvis is
	# _pelvis_stand_m over the lying centre, so a standing pose is moved with its feet on the point,
	# never down into the floor.
	var belongs := target + Vector3.UP * _pelvis_stand_m * upright
	if origin.distance_to(belongs) > SNAP_M:
		var shift := belongs - origin
		for bone: PhysicalBone3D in _bones:
			var state := PhysicsServer3D.body_get_direct_state(bone.get_rid())
			if state == null:
				continue
			state.transform = Transform3D(state.transform.basis, state.transform.origin + shift)
			state.linear_velocity = _velocity
		global_transform = Transform3D(pelvis_state.transform.basis, belongs)
		return
	var pull := (target - origin) * SPRING_K + (_velocity - pelvis_state.linear_velocity) * SPRING_D
	var across := 1.0 - upright
	pull = Vector3(pull.x * across, pull.y, pull.z * across)
	for bone: PhysicalBone3D in _bones:
		var state := PhysicsServer3D.body_get_direct_state(bone.get_rid())
		if state != null:
			state.linear_velocity += pull * delta
	global_transform = pelvis_state.transform


func _paint(tint: Color) -> void:
	if _rig != null:
		if _rig.tint() != tint:
			_rig.set_tint(tint)
		return
	var material := (_mesh.mesh as CapsuleMesh).material as StandardMaterial3D
	if material.albedo_color != tint:
		material.albedo_color = tint
