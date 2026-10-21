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


## Who can win, the mode's errors (#1237): a phase that checks the win conditions in a mode with
## none, whose round could end only by another outcome, or never.
static func mode_errors(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if _wins(mode).is_empty():
		for spec: PhaseSpec in mode.phases:
			if spec != null and spec.checks_wins:
				found.append("phase %s checks the win conditions, but the mode has none" % spec.id)
	return found


## Who can win, the mode's warnings (#1237): in a mode where a phase checks the win conditions, a
## side no win condition names, whose players could never win; a win condition whose side no role
## has, which could only win for nobody. A mode with no such phase (the tutorial) has no winner.
static func mode_warnings(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	var checked := false
	for spec: PhaseSpec in mode.phases:
		checked = checked or (spec != null and spec.checks_wins)
	if not checked:
		return found
	var winning: Array[StringName] = []
	for win: WinCondition in _wins(mode):
		winning.append(win.side)
	var played: Array[StringName] = []
	for role: GameRole in mode.roles:
		if role != null:
			played.append(role.side)
	for spec: SideSpec in mode.sides:
		if spec != null and not winning.has(spec.id):
			found.append("side %s has no win condition: its players could never win" % spec.id)
	for win: WinCondition in _wins(mode):
		if mode.find_side(win.side) != null and not played.has(win.side):
			found.append(
				(
					"win condition %s names side %s, which no role has: it wins for nobody"
					% [win.id, win.side]
				)
			)
	return found


static func _wins(mode: GameMode) -> Array[WinCondition]:
	var found: Array[WinCondition] = []
	for win: WinCondition in mode.win_conditions:
		if win != null:
			found.append(win)
	return found
