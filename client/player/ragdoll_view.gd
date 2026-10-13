class_name RagdollView
extends RigidBody3D
## A knocked-down player's body as this client draws it (the knockdown ADR's KE7, ARCHITECTURE
## §4.7.9): looks only, a ragdoll held to the host's point. On today's placeholder avatar it is one
## capsule of the client's own PlayerRules (radius, standing height), on the `downed` layer with
## the world mask only, so it falls, flies and rolls against the level and never against a player,
## another ragdoll or a client-only object. #522's character replaces it with the skeleton's
## PhysicalBone3Ds.
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
## start() stands it on the point, turned with the player's yaw, with the snapshot's velocity, and
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


## Sizes it from `rules` (the client's own copy of the mode's PlayerRules) for `peer` in `tint`.
func setup(rules: PlayerRules, for_peer: int, tint: Color) -> void:
	_rules = rules
	peer = for_peer
	name = "Ragdoll%d" % for_peer
	var capsule := CapsuleShape3D.new()
	capsule.radius = rules.capsule_radius_m
	capsule.height = rules.capsule_height_m
	_shape.shape = capsule
	_mesh.mesh = LifeLooks.capsule(rules, tint)


## Stands it on `point`, turned by `yaw`, moving at `velocity`, and tips it over (see above).
func start(point: Vector3, yaw: float, velocity: Vector3) -> void:
	hold(point, velocity)
	var turn := Basis(Vector3.UP, yaw)
	transform = Transform3D(turn, point + Vector3.UP * _rules.capsule_height_m * 0.5)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var towards := flat.normalized() if flat.length() > STILL_MPS else turn.z
	_set_velocities(_velocity, Vector3.UP.cross(towards) * TIP_RAD_PER_S)


## Lays it on `point` at rest, along the forward axis (-Z) of `yaw`.
func lie_at_rest(point: Vector3, yaw: float) -> void:
	hold(point, Vector3.ZERO)
	var lying := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)
	transform = Transform3D(lying, lying_centre())
	_set_velocities(Vector3.ZERO, Vector3.ZERO)


## Holds it to the host's `point` moving at `velocity` from the next physics step on.
func hold(point: Vector3, velocity: Vector3) -> void:
	_point = point
	_velocity = velocity if velocity.is_finite() else Vector3.ZERO


## The host's point it is held to.
func held_point() -> Vector3:
	return _point


## Where the spring pulls its centre: the lying capsule's centre over the host's point.
func lying_centre() -> Vector3:
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
	hold(point, Vector3.ZERO)


func is_dead() -> bool:
	return _dead


## The capsule's colour now.
func colour() -> Color:
	var material := (_mesh.mesh as CapsuleMesh).material as StandardMaterial3D
	return material.albedo_color


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _rules == null:
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


func _paint(tint: Color) -> void:
	var material := (_mesh.mesh as CapsuleMesh).material as StandardMaterial3D
	if material.albedo_color != tint:
		material.albedo_color = tint
