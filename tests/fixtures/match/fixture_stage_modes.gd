class_name FixtureStageModes
extends RefCounted
## A mode staged by the host, as the tutorial's (docs/design/tutorial.md §2.3, §2.4; #599), built
## in code on FixtureCombatModes.raising() (§9.6: no `content/`): Round also accepts NextStage from
## the host, whose action rule is ReportOutcome(next); `round, next -> stage` runs `first` and
## enters `stage` (RoundPhase on the map: NextStage from the host, Raise and StopRaise from the
## living, MoveClaim from the living and the downed; ChannelTicks and no LifeTicks, as
## `raise_stage`); `stage, next -> last` runs `second` and enters `last` (the same with LifeTicks
## and a Respawn, as `death_stage`, and no NextStage). Neither stage checks wins or runs a clock.

const STAGE := &"stage"
const LAST := &"last"
const NEXT := &"next"


static func staged(first: Array[RuleEffect] = [], second: Array[RuleEffect] = []) -> GameMode:
	var mode := FixtureCombatModes.raising()
	mode.actions.append(next_stage_rule())
	mode.find_phase(&"round").accepts.append(host_next_stage())
	var stage := _stage(STAGE)
	stage.accepts.append(host_next_stage())
	stage.tick_systems = [ChannelTicks.new()]
	var last := _stage(LAST)
	var life_ticks := LifeTicks.new()
	life_ticks.respawn = FixtureCombatModes.respawn()
	last.tick_systems = [life_ticks, ChannelTicks.new()]
	mode.phases.append_array([stage, last])
	mode.transitions.append(FixtureModes.row(&"round", NEXT, STAGE, first))
	mode.transitions.append(FixtureModes.row(STAGE, NEXT, LAST, second))
	return mode


## The tutorial's NextStage rule: no condition, ReportOutcome(next).
static func next_stage_rule(argument: StringName = &"") -> Rule:
	return FixtureModes.rule(Intents.NEXT_STAGE, [], [report(NEXT, argument)])


static func report(outcome: StringName, argument: StringName = &"") -> ReportOutcome:
	var effect := ReportOutcome.new()
	effect.outcome = outcome
	effect.argument = argument
	return effect


static func host_next_stage() -> AcceptSpec:
	return AcceptSpec.of(Intents.NEXT_STAGE, AcceptSpec.From.HOST)


static func knock_down(pick: int, then_die: bool = false) -> KnockDown:
	var effect := KnockDown.new()
	effect.pick = pick
	effect.then_die = then_die
	return effect


## `peer` sends NextStage, applied on the next host tick.
static func next_stage(game: Match, peer: int, seq: int = 0) -> void:
	FixtureModes.send(game, Intents.NEXT_STAGE, peer, {}, seq)


static func _stage(id: StringName) -> PhaseSpec:
	var living := AcceptSpec.From.LIVING
	var spec := (
		FixtureModes
		. phase(
			id,
			RoundPhase,
			{},
			[
				AcceptSpec.of(Intents.MOVE_CLAIM, living | AcceptSpec.From.DOWNED),
				AcceptSpec.of(Intents.RAISE, living),
				AcceptSpec.of(Intents.STOP_RAISE, living),
			]
		)
	)
	spec.level = PhaseSpec.Level.MAP
	spec.snapshots = true
	spec.voice_rule = FixtureVoice.new()
	return spec
