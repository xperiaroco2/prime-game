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
## The strength of a drunk_max drunk speaker's voice (#1392): the wire's U8.
const MAX_STRENGTH := 255

## How a drunk speaker sounds to whoever hears it (#1392; ARCHITECTURE §6): null, the class
## default, for no change. Its strength follows the speaker's public drunk value (effect_strength).
@export var drunk_effect: VoiceEffect


## Whether `listener` hears `speaker` now. Called only for a living speaker and a living or
## downed listener (speakers_of), never for a player who left or is dead.
func hears(_state: MatchState, _listener: int, _speaker: int) -> bool:
	return false


## `hears` with the two players' last accepted positions already read: speakers_of reads each
## position once per call and asks this (#1282). It defaults to `hears`, so a rule that does not
## measure distance needs only that; one that does overrides this and measures `listener_at` to
## `speaker_at` (within_at), its `hears` reading the positions and calling it.
func hears_at(
	state: MatchState, listener: int, speaker: int, _listener_at: Vector3, _speaker_at: Vector3
) -> bool:
	return hears(state, listener, speaker)


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
## who left hears and is heard by nobody. Each position is read once per call (#1282).
func speakers_of(state: MatchState, listener: int) -> PackedInt32Array:
	var heard := PackedInt32Array()
	if not state.is_present(listener):
		return heard
	var own := state.player(listener)
	if own.life == PlayerState.Life.DEAD:
		return heard
	var listener_at := own.position
	for speaker: int in state.present_peers():
		if speaker == listener:
			continue
		var other := state.player(speaker)
		if not other.is_alive():
			continue
		if hears_at(state, listener, speaker, listener_at, other.position):
			heard.append(speaker)
	return heard


## How strongly `speaker`'s voice sounds drunk now, 0 to MAX_STRENGTH (#1392): 0 with no
## drunk_effect or for a sober speaker, else strength_of its drunk value. Asked only for a present
## player.
func effect_strength(state: MatchState, speaker: int) -> int:
	if drunk_effect == null or state.player_rules == null:
		return 0
	return strength_of(state.player(speaker).drunk, state.player_rules.drunk_max)


## The strength of a voice `drunk` points drunk of `drunk_max`: 0 when sober (or drunk_max 0),
## else drunk / drunk_max of MAX_STRENGTH rounded up, so a drunk speaker always has at least 1 and
## a drunk_max one MAX_STRENGTH.
static func strength_of(drunk: int, drunk_max: int) -> int:
	if drunk <= 0 or drunk_max <= 0:
		return 0
	@warning_ignore("integer_division")
	var scaled := (drunk * MAX_STRENGTH + drunk_max - 1) / drunk_max
	return clampi(scaled, 1, MAX_STRENGTH)


## The routing's effects for `listener` (#1392): each speaker it hears now (speakers_of) whose
## voice sounds drunk, with its strength (1 to MAX_STRENGTH). A speaker it does not hear, or a
## sober one, has no entry, so no effect ever reaches a listener for a speaker it cannot hear.
func effects_of(state: MatchState, listener: int) -> Dictionary[int, int]:
	var found: Dictionary[int, int] = {}
	if drunk_effect == null:
		return found
	for speaker: int in speakers_of(state, listener):
		var strength := effect_strength(state, speaker)
		if strength > 0:
			found[speaker] = strength
	return found


## The mode check (§9.1): a drunk_effect needs a mode with a drunk scale (PlayerRules.drunk_max),
## else it would never sound. Every voice rule's check appends these.
func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if drunk_effect == null:
		return found
	if mode.player_rules == null or mode.player_rules.drunk_max <= 0:
		found.append("drunk_effect is set, but the mode has no drunk_max, so it would never sound")
	return found


## Whether the last accepted positions of `a` and `b` are at most `radius_m` apart (3D).
static func within(state: MatchState, a: int, b: int, radius_m: float) -> bool:
	return within_at(state.player(a).position, state.player(b).position, radius_m)


## Whether `from` and `to` are at most `radius_m` apart (3D), its edge included: the one
## comparison within and every distance-measuring rule's hears_at use.
static func within_at(from: Vector3, to: Vector3, radius_m: float) -> bool:
	return from.distance_squared_to(to) <= radius_m * radius_m


## The mode check's message for a radius outside MIN_RADIUS_M to MAX_RADIUS_M, or "".
static func radius_out_of_bounds(name: String, radius_m: float) -> String:
	return out_of_bounds(name, radius_m, MIN_RADIUS_M, MAX_RADIUS_M)
