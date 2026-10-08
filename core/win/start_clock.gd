class_name StartClock
extends RuleEffect
## Starts the match clock (ARCHITECTURE §3.3, §9.4): a transition action, alone on the row into
## the round (`Pregame, pregame_done -> Round`, #213: the deal ran on the row into the pregame,
## and the silent pregame's seconds do not count). It sets the clock's end to now plus
## the match setting `minutes_setting` (converted once, toward zero: 10 min is 12000 ticks) and
## emits RoundStarted. A forced clock (MatchState.forced_clock_s, the debug ForceClock command of
## the bot scenarios) replaces the setting, in seconds. Match then counts the clock down in the
## phases whose clock runs and announces its end tick in the PhaseChanged of the round it enters;
## at the end it raises `clock_ended`.
##
## Emits: RoundStarted (everyone), with the start tick. No demands.

## The match setting with the round's length in whole minutes (`match_duration`).
@export var minutes_setting: StringName


func run(ctx: MatchContext) -> void:
	if ctx.state.forced_clock_s > 0:
		ctx.state.clock_ticks_left = Ticks.from_seconds(ctx.state.forced_clock_s)
	else:
		ctx.state.clock_ticks_left = Ticks.from_minutes(ctx.setting(minutes_setting))
	ctx.state.clock_ended = false
	ctx.emit(RoundStartedEvent.new(ctx.tick))


func emits() -> Array[Script]:
	return [RoundStartedEvent]


## A clock of 0 minutes would never run and so never end: the setting must be a whole number
## that starts at 1 (a set of ids reads as 0).
func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if minutes_setting.is_empty():
		found.append("StartClock has no minutes_setting")
		return found
	var spec := mode.find_setting(minutes_setting)
	if spec != null and not spec.is_number():
		found.append("StartClock: setting %s is not a whole number" % minutes_setting)
	elif spec != null and spec.min_value < 1:
		found.append(
			(
				"StartClock: setting %s goes down to %d minutes; a clock needs at least 1"
				% [minutes_setting, spec.min_value]
			)
		)
	return found
