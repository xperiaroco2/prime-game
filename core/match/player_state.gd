class_name PlayerState
extends RefCounted
## One player of the roster in MatchState (ARCHITECTURE §3.1): a peer whose Hello was accepted.
## Health and stamina are thousandths (§3.3). The movement rule (2d) keeps the last accepted
## MoveClaim here, and every range rule reads it (§7.1).

## Alive, a ghost, or left. Left counts as dead for the win conditions (§3.5).
enum Life { ALIVE, GHOST, LEFT }

var peer: int
var name: String
var ready := false
## A GameRole id, or empty before the deal.
var role: StringName
var life := Life.ALIVE
## The last accepted claim (§7.1).
var position := Vector3.ZERO
var velocity := Vector3.ZERO
var facing := Vector3.FORWARD
var on_floor := true
## The client tick of the last accepted claim, or -1.
var claim_tick := -1
## Raised by every placement; a claim of another epoch is dropped as stale (§7).
var epoch := 0
## The held item's id, or -1: the hand slot.
var held_item := -1
var health := 0
var stamina := 0
## The host tick up to which stamina is settled (§7.1), or -1.
var stamina_settled_tick := -1
var sprinting := false
## The last accepted claim's sprint flag, and whether it gave movement input and moved
## horizontally: settle_ahead() settles the ticks no claim covers yet with them (§7.1).
var sprint_held := false
var moving := false


func _init(peer_id: int, player_name: String) -> void:
	peer = peer_id
	name = player_name


func is_alive() -> bool:
	return life == Life.ALIVE


func is_present() -> bool:
	return life != Life.LEFT
