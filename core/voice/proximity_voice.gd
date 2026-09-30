class_name ProximityVoice
extends VoiceRule
## `Proximity` (ARCHITECTURE §6, §9.4): every pair of present players within `radius_m` of each
## other hear each other, except that a living player never hears a ghost (VoiceRule.speakers_of
## enforces it for every rule, §5): a ghost within the radius hears the living one-way. The base
## mode's Lobby and Countdown.

## The cutoff in metres, 0.5 to 100. The class default 0 is refused by the mode check: the mode's
## data writes the number (§9.5).
@export var radius_m := 0.0


func hears(state: MatchState, listener: int, speaker: int) -> bool:
	if not state.is_present(listener) or not state.is_present(speaker):
		return false
	return within(state, listener, speaker, radius_m)


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	append_found(found, [radius_out_of_bounds("radius_m", radius_m)])
	return found
