class_name AvatarViews
extends Node3D
## The `Avatars` node under World (ARCHITECTURE §4.7): one RemotePlayerBody per other player of
## the newest snapshot in the own ClientModel, placed at its position at physics priority -80, so
## the local player's push search (priority 0) sees this frame's capsules. M4-7 replaces the
## newest snapshot with SnapshotBuffer's interpolated poses.

const PHYSICS_PRIORITY := -80
const BODY := preload("res://client/player/remote_player_body.tscn")

var model: ClientModel

var _bodies: Dictionary[int, RemotePlayerBody] = {}


func _init() -> void:
	process_physics_priority = PHYSICS_PRIORITY


## How many bodies are shown.
func count() -> int:
	return _bodies.size()


## The body of `peer`, or null.
func body_of(peer: int) -> RemotePlayerBody:
	return _bodies.get(peer)


## Removes every body (the session ended, or a level was swapped).
func clear() -> void:
	for body: RemotePlayerBody in _bodies.values():
		body.queue_free()
	_bodies.clear()


func _physics_process(_delta: float) -> void:
	if model == null:
		return
	for peer: int in _bodies.keys():
		if not model.avatars.has(peer):
			_bodies[peer].queue_free()
			_bodies.erase(peer)
	for key: Variant in model.avatars:
		var peer: int = key
		var avatar: Dictionary = model.avatars[peer]
		var body: RemotePlayerBody = _bodies.get(peer)
		if body == null:
			body = BODY.instantiate() as RemotePlayerBody
			body.name = "Peer%d" % peer
			_bodies[peer] = body
			add_child(body)
		body.global_position = avatar["position"] as Vector3
