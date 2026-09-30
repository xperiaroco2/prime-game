class_name RoundVoice
extends VoiceRule
## `RoundVoice` (ARCHITECTURE §6, §9.4), the base mode's Round: the living hear the living within
## `living_m`; a ghost hears the living within `ghost_hears_living_m` and other ghosts within
## `ghost_hears_ghost_m`, each radius the listening ghost's; the living never hear the dead; a
## player who left hears and is heard by nobody. Hearing may be one-way: a ghost hears a living
## player who never hears it.

## Each radius in metres, 0.5 to 100. The class defaults 0 are refused by the mode check: the
## mode's data writes the numbers (§9.5).
@export var living_m := 0.0
@export var ghost_hears_living_m := 0.0
@export var ghost_hears_ghost_m := 0.0


func hears(state: MatchState, listener: int, speaker: int) -> bool:
	var ear := state.player(listener)
	var mouth := state.player(speaker)
	if ear == null or mouth == null:
		return false
	if ear.life == PlayerState.Life.ALIVE and mouth.life == PlayerState.Life.ALIVE:
		return within(state, listener, speaker, living_m)
	if ear.life == PlayerState.Life.GHOST and mouth.life == PlayerState.Life.ALIVE:
		return within(state, listener, speaker, ghost_hears_living_m)
	if ear.life == PlayerState.Life.GHOST and mouth.life == PlayerState.Life.GHOST:
		return within(state, listener, speaker, ghost_hears_ghost_m)
	# The living never hear the dead; a player who left hears and is heard by nobody.
	return false


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	append_found(
		found,
		[
			radius_out_of_bounds("living_m", living_m),
			radius_out_of_bounds("ghost_hears_living_m", ghost_hears_living_m),
			radius_out_of_bounds("ghost_hears_ghost_m", ghost_hears_ghost_m),
		]
	)
	return found
