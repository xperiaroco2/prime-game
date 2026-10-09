class_name PerfScenario
extends RefCounted
## The match a perf run plays (ARCHITECTURE §9.7, #187), built in code so that `bots` and the
## scenario suites never run it and content/ gains no file: the base mode on its first map, a fixed
## seed (the deal draws the roles from it), every bot joins at the start, readies, and once the
## round starts walks back and forth between a point near the middle and one further out on its own
## spoke, so the bots cross and every snapshot moves; then it waits for the end. The round lasts the
## run's seconds (`clock_s`, ForceClock, a debug command) and ends by time up, which the base mode's
## win conditions give to the dissidents: nobody delivers a package or swings a knife. It deals the
## default draw, both task types since #649 (ZD8 (a)): with 10 bots two spokes cross the greybox's
## zones (z = 7), so the run measures ZoneProgress too; a zone done on the way wins nothing while
## every package rests where it spawned.

const MODE := "res://content/modes/base_mode.tres"
## A fixed seed: the same deal, spawns and walks every run.
const SEED := 187_000_000_001
## Where each bot's spoke starts and ends, metres from the middle.
const INNER_M := 4.0
const OUTER_M := 16.0
## The share of the round the walks fill, so the last leg (and the first, from the spawn, up to
## about 25 m on the greybox) ends before time up.
const WALK_SHARE := 0.6
## The run's time limit: the round plus the countdown, the loading and this margin.
const MARGIN_S := 30.0


## `bots` bots (2 to the mode's maximum), a round of `seconds`, and `legs` walks per bot (-1: as
## many as fill WALK_SHARE of the round at walking speed).
static func build(bots: int, seconds: int, legs := -1) -> BotScenario:
	var scenario := BotScenario.new()
	scenario.mode = load(MODE) as GameMode
	scenario.session_seed = SEED
	scenario.bots = bots
	scenario.clock_s = seconds
	scenario.time_limit_s = seconds + MARGIN_S
	scenario.expected_ends = [&"dissidents"]
	if scenario.mode == null:
		return scenario
	var speed := scenario.mode.player_rules.walk_speed_mps
	var count := legs
	if count < 0:
		count = maxi(1, floori(seconds * WALK_SHARE * speed / (OUTER_M - INNER_M)))
	for number in range(1, bots + 1):
		scenario.scripts.append(_script(number, bots, count))
	return scenario


static func _script(number: int, bots: int, legs: int) -> BotScript:
	var script := BotScript.new()
	script.steps.append(StepReady.new())
	script.steps.append(_wait_for(&"PhaseChanged", {"phase": "round"}))
	var angle := TAU * number / bots
	var spoke := Vector3(cos(angle), 0.0, sin(angle))
	for leg in legs:
		var walk := StepWalkTo.new()
		walk.target = ScenarioTarget.new()
		walk.target.kind = ScenarioTarget.Kind.POINT
		walk.target.point = spoke * (OUTER_M if leg % 2 == 0 else INNER_M)
		script.steps.append(walk)
	script.steps.append(_wait_for(&"MatchEnded", {}))
	return script


static func _wait_for(event: StringName, fields: Dictionary) -> StepWaitFor:
	var step := StepWaitFor.new()
	step.event = event
	step.fields = fields
	return step
