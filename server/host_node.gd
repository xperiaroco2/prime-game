class_name HostNode
extends Node
## Steps a HostSession from the physics step with the real clock (ARCHITECTURE §4.5): its
## process_physics_priority runs it before the host's own client's nodes, so a step's messages to
## the own client are read in the same frame. Tests and the bots runner call HostSession.step with
## a clock of their own instead.
##
## Start the session with HostNode.now_usec() (HostSession.start's now_usec): the session counts
## host ticks from it, so any other clock makes the first step catch up the difference at once.
## Leaving the tree closes the session, so the node is never reparented. It runs while the tree is
## paused: a paused host would freeze every remote client.

## Lower runs first: before any game node at the default 0.
const PHYSICS_PRIORITY := -100

var session: HostSession


func _init(host_session: HostSession = null) -> void:
	session = host_session
	process_physics_priority = PHYSICS_PRIORITY
	process_mode = Node.PROCESS_MODE_ALWAYS


## The clock HostNode steps its session with, in microseconds.
static func now_usec() -> int:
	return Time.get_ticks_usec()


func _physics_process(_delta: float) -> void:
	if session != null:
		session.step(now_usec())


func _exit_tree() -> void:
	if session != null:
		session.close()
