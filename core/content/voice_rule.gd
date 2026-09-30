class_name VoiceRule
extends ContentPart
## Who hears whom in a phase (ARCHITECTURE §6): one per phase spec. Match records each peer's
## speakers per tick for view_of (§5), and server/ forwards a voice frame only along these pairs.
## This base class is silent: nobody hears anybody. The base mode's rules are SilentVoice,
## ProximityVoice and RoundVoice (`core/voice/`, 2i).
##
## Distances are between the players' last accepted positions (§7.1), in 3D: the listener's
## AudioStreamPlayer3D fades by 3D distance to the host's cutoff (§6). Whether the radius should
## be horizontal instead is open for the engineer (#65).

## The bounds of every voice radius, in metres (§9.4).
const MIN_RADIUS_M := 0.5
const MAX_RADIUS_M := 100.0


## Whether `listener` hears `speaker` now. Never called for a player who left.
func hears(_state: MatchState, _listener: int, _speaker: int) -> bool:
	return false


## The speakers `listener` hears now, in peer-id order. A player who left hears and is heard by
## nobody.
func speakers_of(state: MatchState, listener: int) -> PackedInt32Array:
	var heard := PackedInt32Array()
	if not state.is_present(listener):
		return heard
	for speaker: int in state.present_peers():
		if speaker != listener and hears(state, listener, speaker):
			heard.append(speaker)
	return heard


## Whether the last accepted positions of `a` and `b` are at most `radius_m` apart (3D).
static func within(state: MatchState, a: int, b: int, radius_m: float) -> bool:
	var from := state.player(a).position
	var to := state.player(b).position
	return from.distance_squared_to(to) <= radius_m * radius_m


## The mode check's message for a radius outside MIN_RADIUS_M to MAX_RADIUS_M, or "".
static func radius_out_of_bounds(name: String, radius_m: float) -> String:
	return out_of_bounds(name, radius_m, MIN_RADIUS_M, MAX_RADIUS_M)
