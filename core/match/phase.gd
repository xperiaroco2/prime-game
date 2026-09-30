class_name Phase
extends RefCounted
## The base of the phase classes (ARCHITECTURE §3.1, §9.3): what a phase does itself, its own
## intents, timers and outcomes. Match creates a fresh object on every entry (from its PhaseSpec)
## and drops it on exit, so what lives as long as the phase (the countdown's end tick, the
## loading acks, later the votes) is a field here and never leaks into the next entry (§9.1).
## A result that must outlive the phase leaves as an outcome's argument or goes into MatchState.

## The spec this object was created from.
var spec: PhaseSpec
## The host tick of the entry; set by Match before enter().
var entered_tick := 0


## The intents this class handles itself (Lobby: Hello, SetReady, ChangeSettings). An accepted
## intent it does not handle goes to the movement rule (MoveClaim) or to a rule (§9.2).
func handled_intents() -> Array[StringName]:
	return []


func handles(intent: StringName) -> bool:
	return handled_intents().has(intent)


## The outcomes this class can report; ModeCheck requires a transition row for each.
func outcomes() -> Array[StringName]:
	return []


## Problems with `settings` (unknown keys, numbers out of bounds); empty when fine.
func check_settings(settings: Dictionary[StringName, float]) -> PackedStringArray:
	var found := PackedStringArray()
	for key: StringName in settings:
		found.append("unknown setting %s" % key)
	return found


## The host tick its own countdown ends on, announced in PhaseChanged, or -1. Match asks it after
## setting `entered_tick` and before enter().
func end_tick() -> int:
	return -1


func enter(_ctx: MatchContext) -> void:
	pass


func exit(_ctx: MatchContext) -> void:
	pass


## Its own timers, once per tick, before the tick systems.
func on_tick(_ctx: MatchContext) -> void:
	pass


## An accepted intent of handled_intents().
func handle_intent(ctx: MatchContext, command: MatchCommand) -> void:
	ctx.reject(command, RejectReasons.NOTHING_TO_DO)


## server/'s PeerConnected: a connected peer that is not a player yet.
func on_peer_connected(_ctx: MatchContext, _peer: int) -> void:
	pass


## server/'s PeerLeft (§3.5).
func on_peer_left(_ctx: MatchContext, _peer: int) -> void:
	pass


## The setting `key` of the spec, or `default`.
func setting(key: StringName, default: float) -> float:
	if spec == null:
		return default
	return spec.settings.get(key, default)


## For check_settings(): "" when `key` is absent or within the bounds, else the problem.
static func check_setting(
	settings: Dictionary[StringName, float], key: StringName, low: float, high: float
) -> String:
	if not settings.has(key):
		return ""
	return ContentPart.out_of_bounds(String(key), settings[key], low, high)


## check_settings() for a class whose settings are `bounds` (key -> Vector2(low, high)).
static func check_known_settings(
	settings: Dictionary[StringName, float], bounds: Dictionary[StringName, Vector2]
) -> PackedStringArray:
	var found := PackedStringArray()
	for key: StringName in settings:
		if not bounds.has(key):
			found.append("unknown setting %s" % key)
	for key: StringName in bounds:
		var problem := check_setting(settings, key, bounds[key].x, bounds[key].y)
		if not problem.is_empty():
			found.append(problem)
	return found
