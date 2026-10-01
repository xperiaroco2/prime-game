class_name FixtureVoice
extends VoiceRule
## Every present player hears every other present player of the same life state: under the
## voice invariant (§6) that leaves the living hearing the living.


func hears(state: MatchState, listener: int, speaker: int) -> bool:
	return state.player(listener).life == state.player(speaker).life
