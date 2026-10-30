class_name LimpState
extends RefCounted
## A limp player's clock (#1393; ARCHITECTURE §7.1.21): PlayerState.limp while the player lies as a
## rag-doll. Host only; the snapshot relays only that the player is limp.

## The host tick at which LimpTicks gets the player up.
var until := 0
## The host tick of the last push (LimpTicks), or -1: one push per LimpTicks.cooldown_s.
var push_tick := -1
## Whether the player gets up with full health: a hit to 0 health in a phase with
## PhaseSpec.hit_limp (#1439). LifeRules.get_up and clear_limp refill a living player; the drink's
## limp keeps its health.
var refill := false


func _init(ends_at: int) -> void:
	until = ends_at
