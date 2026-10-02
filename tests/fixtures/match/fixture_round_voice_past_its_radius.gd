class_name FixtureRoundVoicePastItsRadius
extends RoundVoice
## M5-1's planted leak (ARCHITECTURE §5, E45): a RoundVoice whose hears ignores its radius, so a
## listener hears every present living speaker at any distance while hearing_radius_m() still says
## living_m. view_of reads the same rule, so the leak test's routing subset check passes it; the
## distance invariant, written apart from the rule, fails it.


func hears(state: MatchState, listener: int, speaker: int) -> bool:
	return state.is_present(listener) and state.is_present(speaker)


## A copy of `mode` whose round hears through this rule at the round's own radius; `mode` itself,
## a cached resource other tests load too, is left unchanged.
static func planted_in(mode: GameMode) -> GameMode:
	var copy := mode.duplicate() as GameMode
	var phases: Array[PhaseSpec] = []
	for spec: PhaseSpec in mode.phases:
		var phase := spec.duplicate() as PhaseSpec
		if spec.voice_rule is RoundVoice:
			var leaky := FixtureRoundVoicePastItsRadius.new()
			leaky.living_m = (spec.voice_rule as RoundVoice).living_m
			phase.voice_rule = leaky
		phases.append(phase)
	copy.phases = phases
	return copy
