class_name FixtureEveryoneHears
extends VoiceRule
## A voice rule that lets every listener hear every speaker, at any distance and in any life
## state: what is left after VoiceRule.speakers_of is the voice invariant alone (§6).


func hears(_state: MatchState, _listener: int, _speaker: int) -> bool:
	return true
