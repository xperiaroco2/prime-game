class_name PinballTable
extends RefCounted
## The lobby pinball's table physics on the host (#1399; ARCHITECTURE §7.1.22): a ball and two
## flippers on a table that does not move, in a World3D of its own through PhysicsServer3D (no
## Nodes in a tree, as HostBodies), reporting into core/ through the table interface
## (Intents.TABLE_REPORTS): BallLaunched, TargetHit, BallLost and BallMoved, each naming the game.
##
## HostSession hands step() the live game once per physics frame (Pinball.game, read only: the
## seat, the serial, the ball in play, the balls left, the held flippers) and puts reports() at the
## head of each step-4 batch, after the bodies' (§4.5). The table follows one game at a time: a new
## serial or no seated player frees the ball and rests the flippers. While a game runs it launches
## a ball launch_delay_s after the game starts or a ball is lost (no plunger: the engineer's
## provisional answer), while core/ has no ball in play and balls are left; a ball past the Drain,
## outside the walls (the catch) or still for stuck_s while no flipper is held is lost. A target
## scores once per touch. Idle (no game) the space is inactive and holds no ball, and the scene is
## read only at the first game: a lobby nobody plays at costs nothing.
##
## The scene contract (levels/pinball/pinball_table.tscn, a greybox the engineer replaces): a
## StaticBody3D is a wall, a scoring target when it has metadata `target_id` (a PinballTarget's id;
## `kick`, m/s, its own push); the AnimatableBody3Ds FlipperLeft and FlipperRight turn about their
## own origin and Y axis (the left one's tip up the table for a positive turn, the right one's for a
## negative); Marker3D BallStart (its -Z the launch), Marker3D Drain (the ball is lost past its Z).
## Positions are the scene's root frame, metres: BallMoved's.

const SCENE := "res://levels/pinball/pinball_table.tscn"
const SPEC := "res://levels/pinball/pinball_table_spec.tres"
const TARGET_ID := &"target_id"
const KICK := &"kick"
## The table's own layers: its walls, targets and flippers; the ball.
const TABLE_LAYER := 1
const BALL_LAYER := 1 << 1
## The most TargetHits one batch keeps (a hostile flipper rhythm cannot grow the queue); a launch
## or a loss is always kept (one per ball, so they cannot grow it either).
const MOST_PENDING := 64

## The scene's problems (read at the first game); a table with any is inert.
var errors := PackedStringArray()

var _scene_path: String
var _spec: PinballTableSpec
var _built := false
var _world: World3D = null
var _space := RID()
## Every static body, and the Shape3Ds they use (kept alive).
var _statics: Array[RID] = []
var _shapes: Array[Shape3D] = []
## A target body -> its id; -> its push (m/s).
var _target_of: Dictionary[RID, StringName] = {}
var _kick_of: Dictionary[RID, float] = {}
## The targets the ball touched at the last step.
var _touching: Dictionary[RID, bool] = {}
var _flippers: Array[_Flipper] = []
var _ball_shape := RID()
var _ball := RID()
var _start := Transform3D.IDENTITY
var _drain_z := 0.0
var _bounds := AABB()
## The game followed (its serial), 0 for none.
var _game := 0
var _wait_s := 0.0
var _still_s := 0.0
var _pending: Array[MatchCommand] = []


## One flipper: its body, its rest place, the side its tip turns up, its turn now.
class _Flipper:
	extends RefCounted
	var body := RID()
	var rest := Transform3D.IDENTITY
	var sign := 1.0
	var angle := 0.0
	var held := false


## A table of the scene at `scene_path` with `spec` (the shipped ones by default; tests pass
## theirs). Nothing is read until the first game.
func _init(scene_path := SCENE, spec: PinballTableSpec = null) -> void:
	_scene_path = scene_path
	_spec = spec


## One physics frame of `delta` seconds against `played`, the live game (Pinball.game; null or
## no seated player: idle).
func step(played: Pinball.Machine, delta: float) -> void:
	if played == null or played.player < 0:
		if _game != 0:
			_rest()
		return
	if played.serial != _game:
		_rest()
		_game = played.serial
		if not _build() or not errors.is_empty():
			return
		PhysicsServer3D.space_set_active(_space, true)
	if not errors.is_empty():
		return
	_flippers[0].held = played.left
	_flippers[1].held = played.right
	for flipper: _Flipper in _flippers:
		_turn(flipper, delta)
	if _ball.is_valid():
		_watch_ball(delta)
	elif not played.in_play and played.balls_left > 0:
		_wait_s += delta
		if _wait_s >= _spec.launch_delay_s:
			_launch()


## The reports since the last call, oldest first, then the ball's place while it is on the table;
## each a command server/ originates (peer 0, as HostBodies.reports).
func reports() -> Array[MatchCommand]:
	var found := _pending
	_pending = []
	if _ball.is_valid():
		var args := {"game": _game, "position": ball_position()}
		found.append(MatchCommand.new(Intents.BALL_MOVED, 0, 0, args))
	return found


## Stops following a game: the ball freed, the flippers at rest, the space inactive, the reports
## not taken yet dropped (HostSession's end).
func clear() -> void:
	_rest()
	_pending.clear()


## Whether the table follows a game (its space steps).
func is_active() -> bool:
	return _game != 0 and _built and errors.is_empty()


## Whether a ball is on the table, and its place in the table's frame.
func has_ball() -> bool:
	return _ball.is_valid()


func ball_position() -> Vector3:
	var at: Transform3D = PhysicsServer3D.body_get_state(
		_ball, PhysicsServer3D.BODY_STATE_TRANSFORM
	)
	return at.origin


func ball_velocity() -> Vector3:
	var moving: Vector3 = PhysicsServer3D.body_get_state(
		_ball, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY
	)
	return moving


## Puts the ball at `position` moving at `velocity` (tests: a ball where a test needs it).
func place_ball(position: Vector3, velocity: Vector3) -> void:
	if not _ball.is_valid():
		_ball = _new_ball()
	PhysicsServer3D.body_set_state(
		_ball, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis.IDENTITY, position)
	)
	PhysicsServer3D.body_set_state(_ball, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
	_still_s = 0.0


## The flipper's turn up from its rest, radians (0: left, 1: right).
func flipper_angle(index: int) -> float:
	return _flippers[index].angle


## The target ids the scene holds.
func target_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_target_of.values())
	return ids


## The spec in use.
func spec() -> PinballTableSpec:
	return _spec


## Reads the scene once (the first game): false when it cannot be read (errors says why).
func _build() -> bool:
	if _built:
		return true
	_built = true
	if _spec == null:
		_spec = load(SPEC) as PinballTableSpec
	if _spec == null:
		errors.append("the pinball table's spec %s cannot be loaded" % SPEC)
		return false
	var packed := load(_scene_path) as PackedScene
	var root: Node = packed.instantiate() if packed != null else null
	if root == null:
		errors.append("the pinball table %s cannot be instanced" % _scene_path)
		return false
	_world = World3D.new()
	_space = _world.space
	PhysicsServer3D.space_set_active(_space, false)
	var flippers: Dictionary[String, _Flipper] = {}
	var markers: Dictionary[String, Transform3D] = {}
	_read(root, root, flippers, markers)
	root.free()
	for needed: String in ["FlipperLeft", "FlipperRight"]:
		if not flippers.has(needed):
			errors.append("the pinball table %s has no %s" % [_scene_path, needed])
	for needed: String in ["BallStart", "Drain"]:
		if not markers.has(needed):
			errors.append("the pinball table %s has no Marker3D %s" % [_scene_path, needed])
	if not errors.is_empty():
		for problem: String in errors:
			push_error(problem)
		return false
	_flippers = [flippers["FlipperLeft"], flippers["FlipperRight"]]
	_flippers[1].sign = -1.0
	_start = markers["BallStart"]
	_drain_z = markers["Drain"].origin.z
	_bounds = _bounds.grow(_spec.bounds_margin_m)
	_ball_shape = PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(_ball_shape, _spec.ball_radius_m)
	return true


func _read(
	node: Node,
	root: Node,
	flippers: Dictionary[String, _Flipper],
	markers: Dictionary[String, Transform3D]
) -> void:
	if node is AnimatableBody3D and String(node.name) in ["FlipperLeft", "FlipperRight"]:
		var flipper := _Flipper.new()
		flipper.rest = LevelWorld.transform_in_scene(node as Node3D, root)
		flipper.body = _body(node, root, PhysicsServer3D.BODY_MODE_KINEMATIC)
		flippers[String(node.name)] = flipper
	elif node is StaticBody3D:
		var body := _body(node, root, PhysicsServer3D.BODY_MODE_STATIC)
		if body.is_valid() and node.has_meta(TARGET_ID):
			_target_of[body] = StringName(str(node.get_meta(TARGET_ID)))
			var kick: float = _spec.kick_mps
			var given: Variant = node.get_meta(KICK, _spec.kick_mps)
			if given is float or given is int:
				kick = given
			_kick_of[body] = kick
	elif node is Marker3D:
		markers[String(node.name)] = LevelWorld.transform_in_scene(node as Node3D, root)
	for child: Node in node.get_children():
		_read(child, root, flippers, markers)


# A body of the table's layer for `node`'s CollisionShape3D children, in the table's space.
func _body(node: Node, root: Node, mode: PhysicsServer3D.BodyMode) -> RID:
	var at := LevelWorld.transform_in_scene(node as Node3D, root)
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, mode)
	PhysicsServer3D.body_set_collision_layer(body, TABLE_LAYER)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_BOUNCE, _spec.wall_bounce)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_FRICTION, 0.0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, at)
	for child: Node in node.get_children():
		var collision := child as CollisionShape3D
		if collision == null or collision.disabled or collision.shape == null:
			continue
		_shapes.append(collision.shape)
		PhysicsServer3D.body_add_shape(body, collision.shape.get_rid(), collision.transform)
		var box := at * collision.transform * collision.shape.get_debug_mesh().get_aabb()
		_bounds = box if _bounds.size == Vector3.ZERO else _bounds.merge(box)
	PhysicsServer3D.body_set_space(body, _space)
	_statics.append(body)
	return body


func _new_ball() -> RID:
	var ball := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(ball, PhysicsServer3D.BODY_MODE_RIGID_LINEAR)
	PhysicsServer3D.body_add_shape(ball, _ball_shape)
	PhysicsServer3D.body_set_collision_layer(ball, BALL_LAYER)
	PhysicsServer3D.body_set_collision_mask(ball, TABLE_LAYER)
	PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_MASS, _spec.ball_mass_kg)
	PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_BOUNCE, _spec.ball_bounce)
	PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_FRICTION, _spec.ball_friction)
	PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, _spec.ball_damp)
	PhysicsServer3D.body_set_axis_lock(ball, PhysicsServer3D.BODY_AXIS_LINEAR_Y, true)
	PhysicsServer3D.body_set_enable_continuous_collision_detection(ball, true)
	PhysicsServer3D.body_set_constant_force(
		ball, Vector3(0.0, 0.0, _spec.slope_mps2 * _spec.ball_mass_kg)
	)
	PhysicsServer3D.body_set_space(ball, _space)
	_touching.clear()
	return ball


func _launch() -> void:
	_wait_s = 0.0
	place_ball(_start.origin, -_start.basis.z.normalized() * _spec.launch_mps)
	_report(Intents.BALL_LAUNCHED, {"game": _game})


# Turns `flipper` toward its held or rest angle at the spec's speed.
func _turn(flipper: _Flipper, delta: float) -> void:
	var goal := deg_to_rad(_spec.flipper_swing_deg) if flipper.held else 0.0
	if is_equal_approx(flipper.angle, goal):
		return
	flipper.angle = move_toward(flipper.angle, goal, deg_to_rad(_spec.flipper_speed_deg_s) * delta)
	var turned := flipper.rest * Transform3D(Basis(Vector3.UP, flipper.sign * flipper.angle))
	PhysicsServer3D.body_set_state(flipper.body, PhysicsServer3D.BODY_STATE_TRANSFORM, turned)


func _watch_ball(delta: float) -> void:
	var at := ball_position()
	if not at.is_finite() or at.z > _drain_z or not _bounds.has_point(at):
		_lose()
		return
	_touch_targets(at)
	var held := _flippers[0].held or _flippers[1].held
	if held or ball_velocity().length() >= _spec.stuck_mps:
		_still_s = 0.0
		return
	_still_s += delta
	if _spec.stuck_s > 0.0 and _still_s >= _spec.stuck_s:
		_lose()


# Each target the ball touches now and did not at the last step scores once, and pushes it away.
func _touch_targets(at: Vector3) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	var reach := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(reach, _spec.ball_radius_m + _spec.touch_m)
	query.shape_rid = reach
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = TABLE_LAYER
	var hits := PhysicsServer3D.space_get_direct_state(_space).intersect_shape(query, 16)
	PhysicsServer3D.free_rid(reach)
	var now: Dictionary[RID, bool] = {}
	for hit: Dictionary in hits:
		var body: RID = hit["rid"]
		if not _target_of.has(body):
			continue
		now[body] = true
		if _touching.has(body):
			continue
		_report(Intents.TARGET_HIT, {"game": _game, "target": String(_target_of[body])})
		var centre: Transform3D = PhysicsServer3D.body_get_state(
			body, PhysicsServer3D.BODY_STATE_TRANSFORM
		)
		var away := at - centre.origin
		away.y = 0.0
		if _kick_of[body] > 0.0 and away.length() > 0.0:
			var pushed := ball_velocity() + away.normalized() * _kick_of[body]
			PhysicsServer3D.body_set_state(
				_ball, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, pushed
			)
	_touching = now


func _lose() -> void:
	_free_ball()
	_wait_s = 0.0
	_report(Intents.BALL_LOST, {"game": _game})


# Past MOST_PENDING only a TargetHit is dropped: a lost launch or loss would leave core/ and the
# table disagreeing on the ball for the rest of the game.
func _report(kind: StringName, args: Dictionary) -> void:
	if _pending.size() < MOST_PENDING or kind != Intents.TARGET_HIT:
		_pending.append(MatchCommand.new(kind, 0, 0, args))


func _free_ball() -> void:
	if _ball.is_valid():
		PhysicsServer3D.free_rid(_ball)
	_ball = RID()
	_still_s = 0.0
	_touching.clear()


# No game followed: no ball, the flippers at rest, the space inactive.
func _rest() -> void:
	_game = 0
	_wait_s = 0.0
	_free_ball()
	for flipper: _Flipper in _flippers:
		flipper.held = false
		flipper.angle = 0.0
		PhysicsServer3D.body_set_state(
			flipper.body, PhysicsServer3D.BODY_STATE_TRANSFORM, flipper.rest
		)
	if _space.is_valid():
		PhysicsServer3D.space_set_active(_space, false)


# Frees the RIDs directly: no method of this object is called while it is deleted.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if _ball.is_valid():
		PhysicsServer3D.free_rid(_ball)
	for body: RID in _statics:
		PhysicsServer3D.free_rid(body)
	_statics.clear()
	if _ball_shape.is_valid():
		PhysicsServer3D.free_rid(_ball_shape)
