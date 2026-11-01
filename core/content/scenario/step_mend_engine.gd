class_name StepMendEngine
extends ScenarioStep
## Mends the ship's engine (ARCHITECTURE §9.7, §9.5.27; #1498): the one step whose moves a policy
## picks as the match goes, since the engine draws its problems' moments, kinds, sites and breaker
## orders at random and no fixed script can name them. With `start`, the bot first presses the
## console. Then it takes each open problem whose id leaves `share` over `of` (every bot of the step
## reads the same events, so they split the problems without talking): it walks to the problem's
## station and presses the gill button while the bar is on a shut slit, switches the next breaker
## on in its green window, and carries the crystal from its socket to a charger, presses it and
## brings it back charged. Below a station's floor it walks `boarding` first, in order (the ship's
## ramp). It decides only from what the bot was told (its ClientEngineBook) and the mode's content.
## Done when the console's bar is full (the engine done) or a MatchEnded arrives; a refusal
## `unavailable` (the problem closed before the press landed) or any while the bot is down is
## no failure, the step goes on.

## This bot's problems: those whose id % `of` is `share`.
@export var share := 0
@export var of := 1
## Whether this bot presses the console's start.
@export var start := false
## The points from the ground up onto the deck (the ship's ramp), walked in order whenever the
## bot stands below the station it heads for.
@export var boarding := PackedVector3Array()


func step_name() -> StringName:
	return &"MendEngine"


func problems() -> PackedStringArray:
	var found := super()
	if of < 1:
		found.append("a MendEngine shares the problems among at least one bot: of >= 1")
	elif share < 0 or share >= of:
		found.append("a MendEngine's share is 0 to of - 1")
	return found
