class_name VoiceRule
extends ContentPart
## Who hears whom in a phase (ARCHITECTURE §6): one per phase spec. Match records each peer's
## speakers per tick for view_of (§5), and server/ forwards a voice frame only along these pairs.
## This base class is silent: nobody hears anybody. The base mode's rules are SilentVoice,
## ProximityVoice and RoundVoice (`core/voice/`, 2i).
##
## Distances are between the players' last accepted positions (§7.1), in 3D, and a radius
## includes its edge, as the M1 spike's routing measured them (#15, `distance_to(...) <= cutoff`,
## accepted by the engineer): the listener's AudioStreamPlayer3D fades by 3D distance to the same
## cutoff (§6), hearing_radius_m(), which the client reads from its own mode (E41).

## The bounds of every voice radius, in metres (§9.4).
const MIN_RADIUS_M := 0.5
const MAX_RADIUS_M := 100.0


## Whether `listener` hears `speaker` now. Called only for a living speaker and a living or
## downed listener (speakers_of), never for a player who left or is dead.
func hears(_state: MatchState, _listener: int, _speaker: int) -> bool:
	return false


## The farthest this rule routes a voice, in metres, between the last accepted positions in 3D
## (a radius includes its edge); 0 when it routes nobody. The client's cutoff: a voice fades to
## silence there (E41, D12), so a rule must never route a speaker farther away, and the leak
## test's distance invariant checks every frame against it (§5, E45). This base class is silent.
func hearing_radius_m() -> float:
	return 0.0


## The hearing radius of a phase whose voice rule is `rule`: 0 for a phase with no voice rule,
## which hears nobody (Match.speakers_for). The one helper that the client's cutoff, its sender
## and the leak test read (E41).
static func radius_of(rule: VoiceRule) -> float:
	return rule.hearing_radius_m() if rule != null else 0.0


## The speakers `listener` hears now, in peer-id order. The voice invariant (§6, vision revision
## 1), enforced here before the rule's `hears` runs, so no mode's data can break it: only the
## living speak (nobody hears a downed or dead player), a dead listener hears nobody, and a player
## who left hears and is heard by nobody.
func speakers_of(state: MatchState, listener: int) -> PackedInt32Array:
	var heard := PackedInt32Array()
	if not state.is_present(listener):
		return heard
	if state.player(listener).life == PlayerState.Life.DEAD:
		return heard
	for speaker: int in state.present_peers():
		if speaker == listener:
			continue
		if not state.player(speaker).is_alive():
			continue
		if hears(state, listener, speaker):
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
