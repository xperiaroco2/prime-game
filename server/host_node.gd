class_name HostNode
extends Node
## Steps a HostSession from the physics step with the real clock (ARCHITECTURE §4.5): its
## process_physics_priority runs it before the host's own client's nodes, so a step's messages to
## the own client are read in the same frame. Tests and the bots runner call HostSession.step with
## a clock of their own instead. Leaving the tree closes the session.

## Lower runs first: before any game node at the default 0.
const PHYSICS_PRIORITY := -100

var session: HostSession


func _init(host_session: HostSession = null) -> void:
	session = host_session
	process_physics_priority = PHYSICS_PRIORITY


func _physics_process(_delta: float) -> void:
	if session != null:
		session.step(Time.get_ticks_usec())


func _exit_tree() -> void:
	if session != null:
		session.close()
