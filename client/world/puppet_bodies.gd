class_name PuppetBodies
extends RefCounted
## A still body drawn from a record row (#787's photo pictures, #1397's booth strip; ARCHITECTURE
## §4.7.58, §4.7.62): a RemotePlayerBody with no collision, the live avatars' rules and character,
## the colour it is given, standing (crouched as recorded) at the row's position, turned to its
## facing through SnapshotBuffer's guard (a relayed facing can be zero or vertical), seated when the
## row is `posed`, laid flat when the row is `downed` or `limp`. The caller adds the items and the
## layers. The colour comes from the caller: a photo's is the roster's now, a booth frame's the
## row's own (the colour at the flash).

const BODY := preload("res://client/player/remote_player_body.tscn")


## A puppet of record row `row` under `parent` (whose World3D draws it).
static func make(
	row: Dictionary, parent: Node, rules: PlayerRules, character: CharacterSet, colour: Color
) -> RemotePlayerBody:
	var peer := row.get("peer", 0) as int
	var body := BODY.instantiate() as RemotePlayerBody
	body.name = "Puppet%d" % peer
	body.rules = rules
	body.peer = peer
	parent.add_child(body)
	# Never in the live physics: no device ray, sight cast or push search finds it.
	body.collision_layer = 0
	body.collision_mask = 0
	body.set_character(character)
	body.set_colour(colour)
	var crouched := row.get("crouched", false) as bool
	body.set_crouched(crouched, INF)
	body.set_sneaking(row.get("sneaking", false) as bool)
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
		state.posed = row.get("posed", false) as bool
		var walk := rules.walk_speed_mps if rules != null else 0.0
		var sprint := rules.sprint_speed_mps if rules != null else 0.0
		body.apply_plan(AvatarClips.plan(state, walk, sprint))
		# Drawn this frame, before any physics step would run the tree: posed now, or the art's
		# arms-out rest (and the sockets' items with it) would be the picture.
		body.character().pose_now()
	if lies(row):
		var radius := rules.capsule_radius_m if rules != null else 0.0
		var flat := Basis(Vector3.UP, pose.yaw) * Basis(Vector3.RIGHT, -PI / 2.0)
		body.global_transform = Transform3D(flat, pose.position + Vector3.UP * radius)
	return body


## Whether row `row` is drawn lying: knocked down (a photo's `downed`) or limp (a booth frame's).
static func lies(row: Dictionary) -> bool:
	return row.get("downed", false) as bool or row.get("limp", false) as bool
