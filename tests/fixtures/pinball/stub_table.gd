class_name StubTable
extends RefCounted
## The pinball table with no physics (#1398, the table interface of ARCHITECTURE §7.1.22): sends
## the reports server/'s table (#1399) sends, as commands server/ originates (peer 0), each naming
## a game. play() runs a script against the live game, one report per tick: &"launch",
## [&"hit", target id] and &"lost".


## BallLaunched of game `serial`.
static func launch(game: Match, serial: int) -> void:
	_send(game, Intents.BALL_LAUNCHED, {"game": serial})


## TargetHit of `target` in game `serial`.
static func hit(game: Match, serial: int, target: StringName) -> void:
	_send(game, Intents.TARGET_HIT, {"game": serial, "target": String(target)})


## BallLost of game `serial`.
static func lost(game: Match, serial: int) -> void:
	_send(game, Intents.BALL_LOST, {"game": serial})


## BallMoved of game `serial`: the ball at `position` (table-local, #1399).
static func moved(game: Match, serial: int, position: Vector3) -> void:
	_send(game, Intents.BALL_MOVED, {"game": serial, "position": position})


## Each step of `steps` against the game live when it is sent, then a tick.
static func play(game: Match, steps: Array) -> void:
	for step: Variant in steps:
		var serial := Pinball.game(game.state).serial
		if step is Array:
			hit(game, serial, (step as Array)[1] as StringName)
		elif step == &"launch":
			launch(game, serial)
		else:
			lost(game, serial)
		FixtureModes.run_ticks(game, 1)


## A whole ball: launched, `hits` (target ids) hit, lost.
static func ball(hits: Array[StringName]) -> Array:
	var steps: Array = [&"launch"]
	for target: StringName in hits:
		steps.append([&"hit", target])
	steps.append(&"lost")
	return steps


static func _send(game: Match, kind: StringName, args: Dictionary) -> void:
	game.apply(MatchCommand.new(kind, 0, game.ticked_through() + 1, args))
