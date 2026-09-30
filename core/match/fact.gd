class_name Fact
extends RefCounted
## A fact an effect raised (ARCHITECTURE §9.2), with the fields its table row names. Hidden
## fields (a subtask's owner) must not be copied into an event with a wider audience.

## A name from Facts.
var name: StringName
## The item (item_rested), or -1.
var item := -1
## The player (player_died, player_left), or 0.
var player := 0
## The task (subtask_done), or -1.
var task := -1
## The rest position (item_rested) or the body position (player_died).
var position := Vector3.ZERO
## Why an item came to rest: put_down, swap, death, leave, spawn, thrown.
var cause: StringName


func _init(fact_name: StringName) -> void:
	name = fact_name
