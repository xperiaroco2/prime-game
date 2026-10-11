class_name WinCondition
extends ContentPart
## Which side wins, and when (ARCHITECTURE §3.4, §9.2): a side and its conditions, all of which
## must pass. Checked in the mode's order, in phases whose spec says so, after every fact and at
## the end of every step; the first that holds reports `won(side)`, and MatchEnded names its `id`
## to every player as the reason (#548): the id is public, so which condition held must be a fact
## every player may learn (the tasks done, the clock, who is left).

@export var id: StringName
## A SideSpec id of the mode.
@export var side: StringName
@export var conditions: Array[Condition] = []


func holds(ctx: MatchContext) -> bool:
	for condition: Condition in conditions:
		if not condition.passes(ctx):
			return false
	return true


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if mode.find_side(side) == null:
		found.append("win condition %s names side %s, which the mode does not declare" % [id, side])
	if conditions.is_empty():
		found.append("win condition %s has no conditions" % id)
	return found
