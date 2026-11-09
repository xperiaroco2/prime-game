class_name DeadHall
extends Node3D
## The dead's hall inside a round map (#1489): the piece the map instances holds the markers, the
## stations' places and a floor, and no art, so a map stays cheap to read (the host and every test
## read each level whole; `lobby_hall.tscn` is a 9000-line scene). The art comes on the client the
## first time its own player waits here (HallVisibility, ensure_art): the host never needs it, and
## a dead player's movement is bound by the hall's radius, not the art's walls.

## The lobby's art hall, without the skat: its ship, its environment and its ship probe are freed
## on the client by the art's own script (`ship_free`).
const ART := "res://levels/lobby/lobby_hall.tscn"
const ART_NODE := &"Art"
const SHIP_FREE: Array[NodePath] = [^"Ship", ^"Environment", ^"Probes/probe_ship"]


## Puts the hall's art under this node, once.
func ensure_art() -> void:
	if has_node(NodePath(ART_NODE)):
		return
	var art := (load(ART) as PackedScene).instantiate()
	art.name = ART_NODE
	art.set(&"ship_free", SHIP_FREE)
	add_child(art)
