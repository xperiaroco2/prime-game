class_name ScriptedPinballTable
extends PinballTable
## The pinball table with no physics (#1510; ARCHITECTURE §4.5, §7.1.22): the reports server/'s
## table sends, scripted against the live game, for a host whose frames are not engine physics
## frames. The bots runner and the core runner play every frame in one synchronous loop, so a real
## PinballTable (its World3D steps only on the engine's physics frames) would never move a ball;
## BotsRunner (and so the chaos run), BotsEnet and ScenarioRunner step this one instead
## (for_scenarios), and host_session_pinball_test scripts it by hand. The real table:
## pinball_table_test.gd.
##
## While a game runs with no ball in play and balls left, it launches a ball (`launches` of them;
## UNLIMITED never runs out) and places it each batch (a BallMoved, moving along x within a bounded
## stretch), so every snapshot shows it. `lose` loses the ball at the next step. With
## `hit_on_left`, each press of the left flipper (held now, not at the last step) hits a target;
## with `lose_on_right`, each press of the right flipper loses the ball. The target is the first of
## the live game's targets by id (Pinball.Machine.points, the mode's UsePinball), so no content id
## or number is written here. It never reads a scene: errors stays empty and was_read() false.

## `launches` that never runs out.
const UNLIMITED := -1
## Where the ball is placed first, how far it moves each batch, and the x past which it starts its
## stretch again (each a multiple of 1/8, exact on the wire).
const FIRST_AT := Vector3(0.25, 0.0, -0.5)
const STEP_BY := Vector3(0.125, 0.0, 0.0)
const LAST_X := 1.0

## The balls it still launches (UNLIMITED: always).
var launches := 1
## Loses the ball at the next step (then clears).
var lose := false
## A press of the left flipper hits the first target; a press of the right loses the ball.
var hit_on_left := false
var lose_on_right := false
## The ball's last place (BallMoved).
var at := FIRST_AT
## The steps taken.
var steps := 0
## The left flipper as the last step() was handed it.
var seen_left := false
## The targets hit (their ids, in order).
var hits: Array[StringName] = []

var _ball_game := 0
var _was_left := false
var _was_right := false
var _scripted: Array[MatchCommand] = []


## The table BotsRunner, BotsEnet and ScenarioRunner step: a ball after every loss, a hit on each
## left press, a loss on each right press.
static func for_scenarios() -> ScriptedPinballTable:
	var table := ScriptedPinballTable.new()
	table.launches = UNLIMITED
	table.hit_on_left = true
	table.lose_on_right = true
	return table


func step(played: Pinball.Machine, _delta: float) -> void:
	steps += 1
	seen_left = played != null and played.left
	if played == null or played.player < 0:
		_ball_game = 0
		_was_left = false
		_was_right = false
		return
	if _ball_game != 0 and _ball_game != played.serial:
		_ball_game = 0
	var pressed_left := played.left and not _was_left
	var pressed_right := played.right and not _was_right
	_was_left = played.left
	_was_right = played.right
	if _ball_game == 0:
		if launches != 0 and not played.in_play and played.balls_left > 0:
			if launches > 0:
				launches -= 1
			_ball_game = played.serial
			_scripted.append(_scripted_report(Intents.BALL_LAUNCHED, {"game": played.serial}))
		return
	if lose or (lose_on_right and pressed_right and played.in_play):
		lose = false
		_scripted.append(_scripted_report(Intents.BALL_LOST, {"game": _ball_game}))
		_ball_game = 0
		return
	if hit_on_left and pressed_left and played.in_play and not played.points.is_empty():
		var ids: Array[StringName] = []
		ids.assign(played.points.keys())
		ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		hits.append(ids[0])
		var args := {"game": _ball_game, "target": String(ids[0])}
		_scripted.append(_scripted_report(Intents.TARGET_HIT, args))


func reports() -> Array[MatchCommand]:
	var found := _scripted
	_scripted = []
	if _ball_game != 0:
		at += STEP_BY
		if at.x > LAST_X:
			at.x = FIRST_AT.x
		found.append(_scripted_report(Intents.BALL_MOVED, {"game": _ball_game, "position": at}))
	return found


func clear() -> void:
	_scripted.clear()
	_ball_game = 0


func is_active() -> bool:
	return _ball_game != 0


func has_ball() -> bool:
	return _ball_game != 0


func ball_position() -> Vector3:
	return at


static func _scripted_report(kind: StringName, args: Dictionary) -> MatchCommand:
	return MatchCommand.new(kind, 0, 0, args)
