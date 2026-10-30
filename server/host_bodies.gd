class_name HostBodies
extends RefCounted
## The host's knocked-down and limp bodies (the knockdown rework's KE13, KD11, KD13 (a); #1393;
## ARCHITECTURE §4.5.9, §7.1.21): one rigid body per body in motion, in the current level's
## world, through PhysicsServer3D. core/ asks for one with LaunchBody and frees it with StopBody
## (HostSession carries both out); a level change (HostWorldQuery.use_level to another level)
## and the host's end free every body. server/ reads no core/ state: each body keeps the epoch
## its LaunchBody named, and reports() turns the bodies into the BodyMoved commands of the next
## step-4 batch (KE14).
##
## Each body is the crouching player's collider, a capsule of PlayerRules.capsule_radius_m and
## crouch_height_m whatever the player's pose (KD11), in BODY_MODE_RIGID_LINEAR: it flies, slides
## and falls, but never tips or rolls (KD13 (a)). It starts upright with its lowest point at the
## origin (its centre half its height above), the launch as its velocity, on the `downed` layer
## with the world mask only, with continuous collision detection, under the engine's gravity,
## mass, friction and bounce. A World3D.new() space steps its rigid bodies as the physics frames
## run (the probe in tests/integration/server/host_bodies_test.gd), so no space_set_active.
##
## With no world to move it (no level, a mode without a capsule, or a host on a fake world with
## no physics: the bots' and the scenario runners' FlatWorldQuery), a launched body is held still
## where it started and reported so, at rest: nothing would move it. It still answers to
## StopBody and a level change.

## project.godot's layer 3, `downed`: a body collides with the level's world layer only.
const DOWNED_LAYER := 1 << 2

var _radius := 0.0
var _height := 0.0
var _space := RID()
var _shape := RID()
## peer -> the body's RID.
var _bodies: Dictionary[int, RID] = {}
## peer -> the lowest point of a body held still (no world to move it).
var _still: Dictionary[int, Vector3] = {}
## peer -> the epoch its LaunchBody named.
var _epochs: Dictionary[int, int] = {}


## Bodies of a capsule `radius` wide and `height` tall (the mode's crouching collider). A size
## that is not a capsule (a mode without player rules) has no shape: its bodies are held still.
func _init(radius: float = 0.0, height: float = 0.0) -> void:
	_radius = radius
	_height = height
	if radius > 0.0 and height >= 2.0 * radius:
		_shape = PhysicsServer3D.capsule_shape_create()
		PhysicsServer3D.shape_set_data(_shape, {"radius": radius, "height": height})


## Switches to the world whose space holds the current level (null: no level), freeing every body
## when it is another one: a body never outlives its level.
func use_world(world: World3D) -> void:
	var space := world.space if world != null else RID()
	if space == _space:
		return
	clear()
	_space = space


## Starts `peer`'s body (LaunchBody): upright, its lowest point at `origin`, moving at `velocity`,
## replacing a body the peer still had. With no level or no capsule it is held still at `origin`.
func launch(peer: int, epoch: int, origin: Vector3, velocity: Vector3) -> void:
	stop(peer)
	_epochs[peer] = epoch
	if not _space.is_valid() or not _shape.is_valid():
		_still[peer] = origin
		return
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID_LINEAR)
	PhysicsServer3D.body_add_shape(body, _shape)
	PhysicsServer3D.body_set_collision_layer(body, DOWNED_LAYER)
	PhysicsServer3D.body_set_collision_mask(body, LevelWorld.WORLD_LAYER)
	PhysicsServer3D.body_set_enable_continuous_collision_detection(body, true)
	PhysicsServer3D.body_set_space(body, _space)
	var centre := origin + Vector3.UP * (_height / 2.0)
	PhysicsServer3D.body_set_state(
		body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis.IDENTITY, centre)
	)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
	_bodies[peer] = body


## Frees `peer`'s body (StopBody); nothing when it has none.
func stop(peer: int) -> void:
	if _bodies.has(peer):
		PhysicsServer3D.free_rid(_bodies[peer])
		_bodies.erase(peer)
	_still.erase(peer)
	_epochs.erase(peer)


## Frees every body (a level change, the host's end).
func clear() -> void:
	for peer: int in peers():
		stop(peer)


## The peers whose bodies move (or are held still), in peer-id order.
func peers() -> Array[int]:
	var found: Array[int] = []
	found.assign(_epochs.keys())
	found.sort()
	return found


## `peer`'s body's transform: its centre, and a basis that stays the identity (it never turns).
func transform_of(peer: int) -> Transform3D:
	if _still.has(peer):
		return Transform3D(Basis.IDENTITY, _still[peer] + Vector3.UP * (_height / 2.0))
	var placed: Transform3D = PhysicsServer3D.body_get_state(
		_bodies[peer], PhysicsServer3D.BODY_STATE_TRANSFORM
	)
	return placed


## `peer`'s body's lowest point (its centre lowered by half its height: it never turns).
func position_of(peer: int) -> Vector3:
	return transform_of(peer).origin - Vector3.UP * (_height / 2.0)


## `peer`'s body's linear velocity (zero for a body held still).
func velocity_of(peer: int) -> Vector3:
	if _still.has(peer):
		return Vector3.ZERO
	var moving: Vector3 = PhysicsServer3D.body_get_state(
		_bodies[peer], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY
	)
	return moving


## One BodyMoved(peer, epoch, position, velocity) per body, in peer-id order (KE14): HostSession
## puts them at the head of a step-4 batch.
func reports() -> Array[MatchCommand]:
	var found: Array[MatchCommand] = []
	for peer: int in peers():
		var args := {
			"epoch": _epochs[peer], "position": position_of(peer), "velocity": velocity_of(peer)
		}
		found.append(MatchCommand.new(Intents.BODY_MOVED, peer, 0, args))
	return found


# Frees the RIDs directly: no method of this object is called while it is deleted.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for body: RID in _bodies.values():
			PhysicsServer3D.free_rid(body)
		_bodies.clear()
		if _shape.is_valid():
			PhysicsServer3D.free_rid(_shape)
