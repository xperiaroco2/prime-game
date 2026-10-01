class_name RoundVoice
extends VoiceRule
## `RoundVoice` (ARCHITECTURE §6, §9.4), the base mode's Round: a listener hears a speaker within
## `living_m`. VoiceRule.speakers_of asks only about living speakers and living or downed
## listeners (the voice invariant), so the living hear the living, and a downed player hears the
## living from where it lies, its own last accepted position (§7.1); nobody hears the downed or
## the dead, and the dead hear nobody.

## The radius in metres, 0.5 to 100. The class default 0 is refused by the mode check: the mode's
## data writes the number (§9.5).
@export var living_m := 0.0


func hears(state: MatchState, listener: int, speaker: int) -> bool:
	if state.player(listener) == null or state.player(speaker) == null:
		return false
	return within(state, listener, speaker, living_m)


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	append_found(found, [radius_out_of_bounds("living_m", living_m)])
	return found
