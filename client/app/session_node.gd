class_name SessionNode
extends Node
## Steps the game's ClientSession from the physics step (ARCHITECTURE §4.7, one physics frame):
## at priority -90, after the host's HostNode (-100), whose messages to the own client it reads in
## the same frame, and before the avatars (-80) and the local player (0), so a Correction
## teleports the player before it moves. It runs while the tree is paused, like HostNode.

const PHYSICS_PRIORITY := -90

var session: ClientSession
## The clock in microseconds: Time.get_ticks_usec() unless a test sets one.
var clock := Callable()


func _init(client: ClientSession = null) -> void:
	session = client
	process_physics_priority = PHYSICS_PRIORITY
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(_delta: float) -> void:
	if session != null and not session.is_ended():
		session.step(clock.call() as int if clock.is_valid() else Time.get_ticks_usec())
