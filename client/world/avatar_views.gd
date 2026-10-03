class_name AvatarViews
extends Node3D
## The `Avatars` node under World (ARCHITECTURE §4.7): one RemotePlayerBody per other player of the
## own ClientModel's newest snapshot, placed each physics frame at SnapshotBuffer's interpolated
## pose (E23) at priority -80, after the session (-90) and before the local player (0), so the
## player's push search sees this frame's capsules (static bodies placed with
## force_update_transform(), RemotePlayerBody). A body is on the living layer only while the
## model's life fold says its player is living, lies while it says downed (M4-9), and wears the
## invulnerable shell while the newest snapshot's avatar has the flag. Every body is in
## SightHider's group: the downed camera hides those out of the body's eye's sight. A placement
## (PlayersPlaced) snaps the players it names; a new map (LoadMatch) forgets the poses. A body whose
## player the model drops (a new map, the lobby, a leave, a death) leaves the tree at once and is
## freed after: a queued node stays in the physics space until the end of the physics frame
## (4.7.2), and the local player's push search runs later in that frame (#242).

const PHYSICS_PRIORITY := -80
const BODY := preload("res://client/player/remote_player_body.tscn")

var model: ClientModel
## The poses; the game makes one per session and feeds it every snapshot.
var buffer: SnapshotBuffer
## The client's own copy of the mode's PlayerRules: the bodies' capsules.
var rules: PlayerRules
## The clock in microseconds, the session's: Time.get_ticks_usec() unless a test sets one.
var clock := Callable()

var _bodies: Dictionary[int, RemotePlayerBody] = {}
## The host tick the bodies were last drawn at; -1 before.
var _drawn_at := -1.0
## The highest host_tick() given so far: it never runs backwards; -1 before.
var _given_tick := -1


func _init() -> void:
	process_physics_priority = PHYSICS_PRIORITY


## How many bodies are shown.
func count() -> int:
	return _bodies.size()


## The body of `peer`, or null.
func body_of(peer: int) -> RemotePlayerBody:
	return _bodies.get(peer)


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


## Removes every body (the session ended, or a level was swapped).
func clear() -> void:
	for body: RemotePlayerBody in _bodies.values():
		_drop(body)
	_bodies.clear()
	_drawn_at = -1.0
	_given_tick = -1


## The session's events that move the others without a snapshot telling it (connected by the
## game to ClientSession.event_received).
func on_event(event_name: StringName, fields: Dictionary) -> void:
	if buffer == null:
		return
	match event_name:
		&"LoadMatch":
			buffer.clear()
		&"PlayersPlaced":
			var tick := maxi(0, host_tick())
			var spots: Dictionary = fields["spots"]
			for key: Variant in spots:
				buffer.snap(key as int, tick)


func _physics_process(_delta: float) -> void:
	if model == null or buffer == null:
		return
	for peer: int in _bodies.keys():
		if not model.avatars.has(peer):
			_drop(_bodies[peer])
			_bodies.erase(peer)
	_drawn_at = buffer.render_tick(now_usec())
	for key: Variant in model.avatars:
		var peer: int = key
		var pose := buffer.pose_of(peer, _drawn_at)
		if pose == null:
			continue
		var body: RemotePlayerBody = _bodies.get(peer)
		if body == null:
			body = BODY.instantiate() as RemotePlayerBody
			body.name = "Peer%d" % peer
			body.rules = rules
			body.peer = peer
			_bodies[peer] = body
			body.add_to_group(SightHider.GROUP)
			add_child(body)
		body.set_living(model.is_alive(peer))
		body.set_downed(model.life_of(peer) == ClientModel.Life.DOWNED)
		body.set_invulnerable(model.is_invulnerable(peer))
		body.set_pose(pose)


## Takes `body` out of the tree, and so out of the physics space, now, then frees it. Only queued,
## it would stay on the living layer for at least the rest of the physics frame, and the local
## player's push search (priority 0, after this node's -80) would push the player out of someone
## who is gone, or off the spot a Correction of the same frame put it on (#242).
func _drop(body: RemotePlayerBody) -> void:
	remove_child(body)
	body.queue_free()
