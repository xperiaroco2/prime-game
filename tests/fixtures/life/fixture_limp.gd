class_name FixtureLimp
extends RefCounted
## FixtureBar's bar with the limp as the base mode has it (#1393; a part's unit test never loads
## `content/`, ARCHITECTURE §9.6): a reaction on `drunk_too_much` runs GoLimp for LIMP_S; Lobby and
## Countdown list LifeTicks (the body's longest motion) and LimpTicks with the numbers below;
## `countdown_done` runs EndLimps. limp() pours and drinks a drinker past too much.

const P1 := FixtureBar.P1
const P2 := FixtureBar.P2
const P3 := FixtureBar.P3
const LIMP_S := 6.0
const REACH := 1.0
const HEIGHT := 1.8
const MIN_SPEED := 0.5
const GAIN := 1.0
const MAX_SPEED := 3.0
const COOLDOWN_S := 0.25


static func mode() -> GameMode:
	var made := FixtureBar.mode()
	var go := GoLimp.new()
	go.limp_s = LIMP_S
	made.reactions.append(FixtureModes.rule(Facts.DRUNK_TOO_MUCH, [], [go] as Array[RuleEffect]))
	var ticks := limp_ticks()
	for phase_id: StringName in [&"lobby", &"countdown"]:
		var spec := made.find_phase(phase_id)
		spec.tick_systems.append(LifeTicks.new())
		spec.tick_systems.append(ticks)
	for row: Transition in made.transitions:
		if row.from == &"countdown" and row.outcome == CountdownPhase.COUNTDOWN_DONE:
			row.actions.append(EndLimps.new())
	return made


## The LimpTicks of mode().
static func limp_ticks() -> LimpTicks:
	var ticks := LimpTicks.new()
	ticks.reach_m = REACH
	ticks.height_m = HEIGHT
	ticks.min_speed_mps = MIN_SPEED
	ticks.gain = GAIN
	ticks.max_speed_mps = MAX_SPEED
	ticks.cooldown_s = COOLDOWN_S
	return ticks


## A match of `made` with `peers` at the bar, `drinker` limp after three mugs.
static func limp(made: GameMode, peers: Array[int], drinker: int) -> Match:
	var game := FixtureBar.at_bar(made, peers)
	drink_to_limp(game, drinker)
	return game


## `drinker` pours and drinks three mugs (seqs 100..105): past too much on the third.
static func drink_to_limp(game: Match, drinker: int) -> void:
	for i in 3:
		FixtureBar.pour(game, drinker, 100 + 2 * i)
		FixtureBar.drink(game, drinker, 101 + 2 * i)
