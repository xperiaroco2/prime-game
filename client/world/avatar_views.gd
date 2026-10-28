class_name AvatarViews
extends Node3D
## The `Avatars` node under World (ARCHITECTURE §4.7): one RemotePlayerBody per other player of the
## own ClientModel's newest snapshot, placed each physics frame at SnapshotBuffer's interpolated
## pose (E23) at priority -80, after the session (-90) and before the local player (0), so the
## player's push search sees this frame's capsules (static bodies placed with
## force_update_transform(), RemotePlayerBody). A body is on the living layer only while the model's
## life fold says its player is living, and wears the invulnerable shell while the newest snapshot's
## avatar has the flag, and is painted its player's body colour as the model's roster has it
## (BodyColours, #551). It is crouched while its pose says so (the snapshot's flag at or before the
## drawn tick; RemotePlayerBody.set_crouched, the crouch ADR's KE7), before it is placed, so the
## push search sees the crouched capsule in the same frame. Every knocked-down player, the own one
## included (its snapshot carries its own avatar while it is knocked down, KE5), is drawn as a
## RagdollView held to its interpolated point (KE7, §4.7.9): started standing from the first pose
## with the host's velocity of a downed snapshot (none before one), a sibling of the bodies (a body
## turns with its player's look every frame), in SightHider's group by the host's point; the own
## player gets no RemotePlayerBody, and another's hides its capsule and turns its collision off
## while the ragdoll is its body. Every body is in SightHider's group: the downed camera hides those
## out of the body's eye's sight. A placement (PlayersPlaced) snaps the players it names; a new map
## (LoadMatch) and a phase on another level (End -> Lobby) forget the poses: drawn behind the
## interpolation delay, the round's would stand a player at its round spot in the lobby and push
## whoever was placed there (#241). A snapshot sent before such a change but arriving after it is
## kept by neither the buffer nor the model: both floor at the host tick estimated at the change
## (host_tick(), which the model reads, #251). A body whose player the model drops (a new map, the
## lobby, a leave, a death) leaves the tree at once and is freed after: a queued node stays in the
## physics space until the end of the physics frame (4.7.2), and the local player's push search runs
## later in that frame (#242). A ragdoll goes the same way once its player is no longer knocked down
## (a revive stands the avatar up at once, KD7 (a)), except at a death with a body: it is parked for
## BodyViews (-70) to take in the same physics frame (release_ragdoll()), which greys it where it
## lies; one not taken by the next frame goes.
##
## With a `character` (#522, §4.7.53) every body wears the animated rig: each physics frame it plays
## AvatarClips' plan of what is drawn (the drawn move since the last frame, a placement's jump
## counting as none, the pose's yaw and crouch bit, and a two-handed hand item from the model's
## events), never a claimed velocity. Picking up (ItemPickedUp) and putting down (ItemPlaced, the
## cause put_down only) play their one-shots on the holder's body once the interpolation delay has
## passed since the event arrived, when the drawn body does it; ItemPlaced names no holder and the
## model has cleared it by then, so the holder is the one the last physics frame drew holding it.

const PHYSICS_PRIORITY := -80
const BODY := preload("res://client/player/remote_player_body.tscn")

## Setting it hands it host_tick(), the floor of its snapshots at a cleared match (#251); the model
## it replaces gives it back.
var model: ClientModel:
	set(value):
		if model != null and model.host_tick_now == host_tick:
			model.host_tick_now = Callable()
		model = value
		if model != null:
			model.host_tick_now = host_tick

## The poses; the game makes one per session and feeds it every snapshot.
var buffer: SnapshotBuffer
## The client's own copy of the mode's PlayerRules: the bodies' capsules.
var rules: PlayerRules
## The clock in microseconds, the session's: Time.get_ticks_usec() unless a test sets one.
var clock := Callable()
## The character the bodies wear, or null: the greybox capsules. The game sets it
## (CharacterSet.load_default()); tests leave it null unless they test the character.
var character: CharacterSet
## The client's own copy of the mode: which item kinds take both hands (the carry layer).
var mode: GameMode

var _bodies: Dictionary[int, RemotePlayerBody] = {}
var _ragdolls: Dictionary[int, RagdollView] = {}
## Ragdolls of players who died in the last step, out of _ragdolls, kept for BodyViews.
var _parked: Dictionary[int, RagdollView] = {}
## The host tick the bodies were last drawn at; -1 before.
var _drawn_at := -1.0
## The highest host_tick() given so far: it never runs backwards; -1 before.
var _given_tick := -1
## The level of the model's phase when last seen (each physics frame and each PhaseChanged): a
## PhaseChanged to another level forgets the poses; -1 before the first look.
var _level := -1
## Peer -> its body's drawn position last physics frame (the drawn move picks the clip).
var _drawn_pos: Dictionary[int, Vector3] = {}
## Each drawn peer's last AvatarClips plan (#1334): its move family's hysteresis, and WorldSounds
## times the footsteps by it (plan_of).
var _plans: Dictionary[int, AvatarClips.Plan] = {}
## Item -> the peer the last physics frame drew holding it in the hand.
var _held: Dictionary[int, int] = {}
## One-shots waiting for the interpolation delay: [peer, clip, due in clock microseconds].
var _shots: Array[Array] = []


func _init() -> void:
	process_physics_priority = PHYSICS_PRIORITY


## How many bodies are shown.
func count() -> int:
	return _bodies.size()


## The body of `peer`, or null.
func body_of(peer: int) -> RemotePlayerBody:
	return _bodies.get(peer)


## The ragdoll of knocked-down `peer` (the own player too), or null.
func ragdoll_of(peer: int) -> RagdollView:
	return _ragdolls.get(peer)


## How many ragdolls are shown.
func ragdoll_count() -> int:
	return _ragdolls.size()


## Where knocked-down `peer`'s body is as this client draws it: its ragdoll's held point, the
## interpolated point of the host's body (never the ragdoll's pose, KE7); `fallback` without one
## (living, or before the first snapshot that carries it).
func point_of(peer: int, fallback: Vector3) -> Vector3:
	var ragdoll: RagdollView = _ragdolls.get(peer)
	return ragdoll.held_point() if ragdoll != null else fallback


## Hands over the ragdoll of `peer`, who died in this physics frame, out of this node: BodyViews
## keeps it as the body (KD7 (a)). Null when there is none.
func release_ragdoll(peer: int) -> RagdollView:
	var ragdoll: RagdollView = _parked.get(peer)
	if ragdoll == null:
		return null
	_parked.erase(peer)
	remove_child(ragdoll)
	return ragdoll


## The host tick the bodies were drawn at in this physics frame; -1 before the first snapshot.
func drawn_at() -> float:
	return _drawn_at


## The estimated host tick now (the countdowns and the clock read it), or the newest snapshot's
## before any arrived; -1 before both. It never runs backwards, though the estimate drops a little
## when the least delayed arrival leaves SnapshotBuffer's window: a countdown would show more time.
func host_tick() -> int:
	if buffer == null or not buffer.has_estimate():
		return model.snapshot_tick if model != null else -1
	_given_tick = maxi(_given_tick, floori(buffer.estimated_tick(now_usec())))
	return _given_tick


## The interpolation delay in use, in milliseconds (the debug overlay).
func delay_ms() -> float:
	return buffer.delay_ticks() * 1000.0 / Ticks.RATE if buffer != null else 0.0


func now_usec() -> int:
	return clock.call() as int if clock.is_valid() else Time.get_ticks_usec()


## Removes every body and ragdoll (the session ended, or a level was swapped).
func clear() -> void:
	for body: RemotePlayerBody in _bodies.values():
		_drop(body)
	_bodies.clear()
	for ragdoll: RagdollView in _ragdolls.values() + _parked.values():
		_drop(ragdoll)
	_ragdolls.clear()
	_parked.clear()
	_drawn_pos.clear()
	_plans.clear()
	_held.clear()
	_shots.clear()
	_drawn_at = -1.0
	_given_tick = -1
	_level = -1


## The session's events that move the others without a snapshot telling it (connected by the
## game to ClientSession.event_received).
func on_event(event_name: StringName, fields: Dictionary) -> void:
	if buffer == null:
		return
	match event_name:
		&"LoadMatch":
			buffer.clear(host_tick())
		&"PhaseChanged":
			var level := _level_now()
			if _level >= 0 and level != _level:
				buffer.clear(host_tick())
			_level = level
		&"PlayersPlaced":
			var tick := maxi(0, host_tick())
			var spots: Dictionary = fields["spots"]
			for key: Variant in spots:
				buffer.snap(key as int, tick)
		&"ItemPickedUp":
			_queue_shot(fields["peer"] as int, fields["item"] as int, AvatarClips.Shot.PICKUP)
		&"ItemPlaced":
			var item: int = fields["item"]
			if fields.get("cause", &"") == Items.PUT_DOWN and _held.has(item):
				_queue_shot(_held[item], item, AvatarClips.Shot.PUTDOWN)


func _physics_process(delta: float) -> void:
	if model == null or buffer == null:
		return
	_level = _level_now()
	for peer: int in _bodies.keys():
		if not model.avatars.has(peer):
			_drop(_bodies[peer])
			_bodies.erase(peer)
			_drawn_pos.erase(peer)
			_plans.erase(peer)
	_put_away_ragdolls()
	_drawn_at = buffer.render_tick(now_usec())
	for key: Variant in model.avatars:
		var peer: int = key
		var pose := buffer.pose_of(peer, _drawn_at)
		if pose == null:
			continue
		var downed := model.life_of(peer) == ClientModel.Life.DOWNED
		if downed:
			_hold_ragdoll(peer, pose)
		if peer == model.own_peer:
			continue  # the own avatar (KE5) is drawn as its ragdoll only, never as a stranger
		var body: RemotePlayerBody = _bodies.get(peer)
		# A body drawn for the first time takes its head's height at once (the crouch ADR, KE7).
		var ease_s := delta if body != null else INF
		if body == null:
			body = BODY.instantiate() as RemotePlayerBody
			body.name = "Peer%d" % peer
			body.rules = rules
			body.peer = peer
			_bodies[peer] = body
			body.add_to_group(SightHider.GROUP)
			add_child(body)
			body.set_character(character)
			PhotoLayers.assign(body, PhotoLayers.LIVE_AVATAR)
		body.set_living(model.is_alive(peer))
		body.set_downed(downed)
		body.set_invulnerable(model.is_invulnerable(peer))
		body.set_colour(BodyColours.of(model.colour_of(peer)))
		# Before set_pose places it: the push search of this frame reads the crouched capsule.
		body.set_crouched(pose.crouched, ease_s)
		body.set_sneaking(pose.sneaking)
		if _is_placement(peer, pose, delta):
			body.snap_look()
		body.set_pose(pose)
		_animate(body, pose, delta)
	_fire_shots()
	_held.clear()
	for key: Variant in model.avatars:
		var item := model.hand_item(key as int)
		if item >= 0:
			_held[item] = key as int


## `peer`'s last drawn AvatarClips plan (#1334), or null before its body was drawn (or for the
## own player, never drawn here).
func plan_of(peer: int) -> AvatarClips.Plan:
	return _plans.get(peer)


## Whether `pose` jumped from `peer`'s last drawn place faster than anyone moves: a placement (a
## respawn, a snap), no move.
func _is_placement(peer: int, pose: SnapshotBuffer.Pose, delta: float) -> bool:
	if not _drawn_pos.has(peer) or delta <= 0.0:
		return false
	var moved := pose.position - _drawn_pos[peer]
	return Vector2(moved.x, moved.z).length() > SnapshotBuffer.SNAP_SPEED_MPS * delta


## Plans AvatarClips' clips of what is drawn at `pose`, `delta` seconds after the last frame,
## against the body's yaw (it lags the aim, #1334), and plays them on `body`'s character (if any).
func _animate(body: RemotePlayerBody, pose: SnapshotBuffer.Pose, delta: float) -> void:
	var state := AvatarClips.State.new()
	state.downed = body.is_downed()
	state.yaw = body.body_yaw
	state.crouched = pose.crouched
	state.carrying = _two_handed(model.hand_item(body.peer))
	var last: AvatarClips.Plan = _plans.get(body.peer)
	state.was_back = last != null and last.back
	if _drawn_pos.has(body.peer) and delta > 0.0 and not _is_placement(body.peer, pose, delta):
		state.drawn_move = (pose.position - _drawn_pos[body.peer]) / delta
	_drawn_pos[body.peer] = pose.position
	var walk := rules.walk_speed_mps if rules != null else 0.0
	var sprint := rules.sprint_speed_mps if rules != null else 0.0
	var plan := AvatarClips.plan(state, walk, sprint)
	_plans[body.peer] = plan
	body.apply_plan(plan)


## Queues `peer`'s one-shot `shot` for `item` (two-handed or not) to play after the interpolation
## delay: the drawn body reaches the event's tick then. None for the own player or without a
## character.
func _queue_shot(peer: int, item: int, shot: AvatarClips.Shot) -> void:
	if character == null or model == null or peer == model.own_peer:
		return
	var clip := AvatarClips.one_shot(shot, _two_handed(item))
	_shots.append([peer, clip, now_usec() + int(delay_ms() * 1000.0)])


## Plays the one-shots whose time came, on bodies still drawn standing; drops them otherwise.
func _fire_shots() -> void:
	var now := now_usec()
	var waiting: Array[Array] = []
	for shot: Array in _shots:
		if (shot[2] as int) > now:
			waiting.append(shot)
			continue
		var body: RemotePlayerBody = _bodies.get(shot[0] as int)
		if body != null and not body.is_downed():
			body.play_one_shot(shot[1] as StringName)
	_shots = waiting


## Whether `item` (an id the model knows) is of a kind that takes both hands (the package).
func _two_handed(item: int) -> bool:
	var known: ClientModel.Item = model.items.get(item)
	if known == null or mode == null:
		return false
	var kind := mode.find_item_kind(known.kind)
	return kind != null and kind.is_two_handed()


## Starts `peer`'s ragdoll at `pose` the first time, then holds it to the pose's point. Only a
## snapshot that shows the player knocked down gives it a velocity, the host body's (KE14): the
## reliable KnockedDown can overtake the knockdown tick's snapshot, and the newest one before it
## carries the living player's claimed velocity, which never moves a body on another screen.
func _hold_ragdoll(peer: int, pose: SnapshotBuffer.Pose) -> void:
	var colour := BodyColours.of(model.colour_of(peer))
	var shown_downed: bool = (model.avatars[peer] as Dictionary).get("downed", false)
	var velocity := pose.velocity if shown_downed else Vector3.ZERO
	var ragdoll: RagdollView = _ragdolls.get(peer)
	if ragdoll == null:
		ragdoll = RagdollView.new()
		ragdoll.setup(rules, peer, colour, character)
		ragdoll.start(pose.position, pose.yaw, velocity)
		ragdoll.add_to_group(SightHider.GROUP)
		_ragdolls[peer] = ragdoll
		add_child(ragdoll)
		PhotoLayers.assign(ragdoll, PhotoLayers.LIVE_AVATAR)
		return
	ragdoll.hold(pose.position, velocity)
	ragdoll.set_colour(colour)


## Drops the ragdolls nobody took since the last step, and those of players no longer knocked
## down, but parks the ragdoll of a player who died with a body for BodyViews.
func _put_away_ragdolls() -> void:
	for ragdoll: RagdollView in _parked.values():
		_drop(ragdoll)
	_parked.clear()
	for peer: int in _ragdolls.keys():
		if model.avatars.has(peer) and model.life_of(peer) == ClientModel.Life.DOWNED:
			continue
		var ragdoll: RagdollView = _ragdolls[peer]
		_ragdolls.erase(peer)
		if model.bodies.has(peer):
			_parked[peer] = ragdoll
		else:
			_drop(ragdoll)


## Takes `node` (a body or a ragdoll) out of the tree, and so out of the physics space, now, then
## frees it. Only queued, a body would stay on the living layer for at least the rest of the
## physics frame, and the local player's push search (priority 0, after this node's -80) would
## push the player out of someone who is gone, or off the spot a Correction of the same frame put
## it on (#242).
func _drop(node: Node3D) -> void:
	remove_child(node)
	node.queue_free()


## The level the model's current phase plays on; NONE without one.
func _level_now() -> int:
	var spec := model.phase_spec() if model != null else null
	return spec.level if spec != null else PhaseSpec.Level.NONE
