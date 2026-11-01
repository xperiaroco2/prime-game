extends Node3D
## The estate's ship piece (#1499): the art ship of `levels/ship/ship.tscn` (prime-game-art#335's
## package, the one the lobby instances too, #1451) under `Art`, with the engine's markers and
## stand-ins under `Engine` on the art's station spots. A saved scene cannot remove a node inside
## an instance, so the package's nodes the estate must not have (its forest `Clearing` with its
## ground at y 0, its `Environment` with a second WorldEnvironment, its moon and key light) are
## saved hidden, their colliders off layer 1 (the host never runs this script, so it never sees
## them either), and freed here on _ready, as the package's HANDOFF S7 asks. One frame later every
## reflection probe (UPDATE_ONCE) is taken out of the tree and put back, so it captures again
## without them.

## The nodes freed on _ready, relative to this node.
@export var art_free: Array[NodePath] = []


func _ready() -> void:
	var freed: int = 0
	for p: NodePath in art_free:
		var n: Node = get_node_or_null(p)
		if n == null:
			push_warning("ship.gd: no node %s to free" % p)
			continue
		n.get_parent().remove_child(n)
		n.free()
		freed += 1
	set_meta("art_freed", freed)
	_recapture.call_deferred()


## Each probe out of the tree and back in its place: a probe entering the scenario again renders
## its capture again.
func _recapture() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var probes: Array[Node] = find_children("*", "ReflectionProbe", true, false)
	for probe: Node in probes:
		var parent: Node = probe.get_parent()
		var at: int = probe.get_index()
		parent.remove_child(probe)
		parent.add_child(probe)
		parent.move_child(probe, at)
	set_meta("probes_recaptured", probes.size())
