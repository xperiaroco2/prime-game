class_name SessionNode
extends Node
## Steps the game's ClientSession from the physics step (ARCHITECTURE §4.7, one physics frame):
## at priority -90, after the host's HostNode (-100), whose messages to the own client it reads in
## the same frame, and before the avatars (-80) and the local player (0), so a Correction
## teleports the player before it moves. It runs while the tree is paused, like HostNode.
##
## The session's clock is the count of physics steps, not the real clock: the client tick is then
## the physics step divided by 3 at 60 Hz (§7.1 "The client tick's rate"), so a claim's travel
## always matches the client ticks it covers. On the real clock, Godot's back-to-back catch-up
## steps after a hitch (or steps running late on a fast display) put 4 or more steps of travel in
## a claim of one client tick, which the host's crawl check, with no fixed slack, corrects.

const PHYSICS_PRIORITY := -90

var session: ClientSession

## The physics steps run so far.
var _steps := 0


func _init(client: ClientSession = null) -> void:
	session = client
	process_physics_priority = PHYSICS_PRIORITY
	process_mode = Node.PROCESS_MODE_ALWAYS


## The session's clock in microseconds: the physics steps run so far, each 1 / the physics rate.
func now_usec() -> int:
	@warning_ignore("integer_division")
	return _steps * 1000000 / Engine.physics_ticks_per_second


func _physics_process(_delta: float) -> void:
	_steps += 1
	if session != null and not session.is_ended():
		session.step(now_usec())
