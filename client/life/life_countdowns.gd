class_name LifeCountdowns
extends RefCounted
## The own player's life countdowns (ARCHITECTURE §4.7 Countdowns, V13; the M4 ADR's §3 item 8),
## from public events and the client's own copy of the mode's numbers only: the knockdown's from
## the own KnockedDown, paused from a RaiseStarted naming the own player until its RaiseStopped
## or Revived; the respawn's from the own Died; the own invulnerability from the own Revived or
## Respawned, and the respawn's protection (the downed screen's chip, #497) from the Respawned
## only; a raise's progress from RaiseStarted, for the raiser and the raised. Each event's
## host tick is the estimated host tick when it arrived (SnapshotBuffer's estimate, which the
## clock uses): the caller passes it. Display only: the host keeps every deadline.
##
## Pure: the game feeds it every event (on_event) and asks with the estimated host tick now.

const NONE := -1.0

var _knockdown_ticks := 0.0
var _respawn_ticks := 0.0
var _invulnerable_ticks := 0.0
var _raise_ticks := 0.0
## Host ticks (with a fraction) at which each ends; NONE when not running.
var _knockdown_end := NONE
var _respawn_end := NONE
var _invulnerable_end := NONE
## The invulnerability's end when it came from the own Respawned (not a Revived); NONE otherwise.
var _protection_end := NONE
## Ticks of the knockdown left while a raise pauses it; NONE when not paused.
var _knockdown_left := NONE
## The host tick the raise naming the own player (as raiser or raised) started; NONE when none.
var _raise_start := NONE
## The downed player the own player raises; 0 when none.
var _raising := 0


## `rules`: the client's own copy of the mode's PlayerRules; `raise_seconds`: its raise's time
## (raise_seconds_of), 0 when the mode has no raise.
func _init(rules: PlayerRules, raise_seconds: float) -> void:
	_knockdown_ticks = rules.knockdown_s * Ticks.RATE
	_respawn_ticks = rules.respawn_s * Ticks.RATE
	_invulnerable_ticks = rules.invulnerable_s * Ticks.RATE
	_raise_ticks = raise_seconds * Ticks.RATE


## The seconds of the mode's raise: the channel of its Raise action's rule; 0 when it has none.
static func raise_seconds_of(mode: GameMode) -> float:
	for rule: Rule in mode.actions:
		if rule.trigger != Intents.RAISE:
			continue
		for effect: RuleEffect in rule.effects:
			var channel := effect as ChannelEffect
			if channel != null:
				return channel.seconds
	return 0.0


## Forgets everything (a new match).
func clear() -> void:
	_knockdown_end = NONE
	_respawn_end = NONE
	_invulnerable_end = NONE
	_protection_end = NONE
	_knockdown_left = NONE
	_raise_start = NONE
	_raising = 0


## One decoded event, arrived when the estimated host tick was `tick`; `own` is the own peer id.
func on_event(event_name: StringName, fields: Dictionary, own: int, tick: float) -> void:
	match event_name:
		&"LoadMatch":
			clear()
		&"KnockedDown":
			if _peer(fields) == own:
				_knockdown_end = tick + _knockdown_ticks
				_knockdown_left = NONE
				_raise_start = NONE
		&"RaiseStarted":
			_raise_started(fields, own, tick)
		&"RaiseStopped":
			_raise_stopped(fields, own, tick)
		&"Revived":
			if _peer(fields) == own:
				_end_knockdown()
				_invulnerable_end = tick + _invulnerable_ticks
				_protection_end = NONE
			elif _peer(fields) == _raising:
				_end_raise()
		&"Died":
			if _peer(fields) == own:
				_end_knockdown()
				_respawn_end = tick + _respawn_ticks
		&"Respawned":
			if _peer(fields) == own:
				_respawn_end = NONE
				_invulnerable_end = tick + _invulnerable_ticks
				_protection_end = _invulnerable_end
		&"PlayerLeft":
			if _peer(fields) == _raising:
				_end_raise()


## Seconds until the own knockdown ends in a death, or NONE when not downed. Paused while raised.
func knockdown_left_s(tick: float) -> float:
	if _knockdown_left >= 0.0:
		return _knockdown_left / Ticks.RATE
	return _left_s(_knockdown_end, tick)


## The own knockdown's time left as a fraction of the mode's (1 at the knockdown, 0 at the death),
## or NONE when not downed. Paused while raised.
func knockdown_fraction(tick: float) -> float:
	var left := knockdown_left_s(tick)
	if left < 0.0 or _knockdown_ticks <= 0.0:
		return NONE
	return clampf(left * Ticks.RATE / _knockdown_ticks, 0.0, 1.0)


## Whether a raise pauses the own knockdown now.
func knockdown_paused() -> bool:
	return _knockdown_left >= 0.0


## Seconds until the own respawn, or NONE when not dead.
func respawn_left_s(tick: float) -> float:
	return _left_s(_respawn_end, tick)


## Seconds of the own invulnerability left, or NONE when not invulnerable.
func invulnerable_left_s(tick: float) -> float:
	return _left_s(_invulnerable_end, tick)


## Seconds of the own invulnerability left after a respawn, or NONE when not invulnerable or
## invulnerable from a raise (the downed screen's `back` draws the respawn's only, #497).
func protection_left_s(tick: float) -> float:
	return _left_s(_protection_end, tick)


## The raise naming the own player (raising or raised) done, from 0 to 1; NONE when none runs.
func raise_progress(tick: float) -> float:
	if _raise_start < 0.0 or _raise_ticks <= 0.0:
		return NONE
	return clampf((tick - _raise_start) / _raise_ticks, 0.0, 1.0)


## The downed player the own player raises, 0 when none.
func raising() -> int:
	return _raising


func _raise_started(fields: Dictionary, own: int, tick: float) -> void:
	var target: int = fields["target"]
	var raiser: int = fields["raiser"]
	if target == own:
		if _knockdown_end >= 0.0:
			_knockdown_left = maxf(0.0, _knockdown_end - tick)
			_knockdown_end = NONE
		_raise_start = tick
	elif raiser == own:
		_raising = target
		_raise_start = tick


func _raise_stopped(fields: Dictionary, own: int, tick: float) -> void:
	var target: int = fields["target"]
	if target == own:
		if _knockdown_left >= 0.0:
			_knockdown_end = tick + _knockdown_left
			_knockdown_left = NONE
		_raise_start = NONE
	elif fields["raiser"] as int == own:
		_end_raise()


func _end_knockdown() -> void:
	_knockdown_end = NONE
	_knockdown_left = NONE
	_raise_start = NONE


func _end_raise() -> void:
	_raising = 0
	_raise_start = NONE


static func _left_s(end: float, tick: float) -> float:
	if end < 0.0:
		return NONE
	return maxf(0.0, end - tick) / Ticks.RATE


static func _peer(fields: Dictionary) -> int:
	return fields.get("peer", 0) as int
