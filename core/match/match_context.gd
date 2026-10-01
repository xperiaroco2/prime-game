class_name MatchContext
extends RefCounted
## What a part sees while it runs (ARCHITECTURE §9.2): the match state, the mode, the geometry
## port, the tick, and who and what it runs for: the actor and its intent (an action), the fact (a
## reaction or a task type's check), or the outcome and its argument (a transition action). Every
## change a part makes that others can observe goes through here: events, facts, outcomes.
## Match creates one per run; a part never keeps it.

var state: MatchState
var mode: GameMode
var world: WorldQuery
var tick: int
## The acting player, or 0 (a fact, a transition action, a tick system).
var actor := 0
## The intent being handled, or null.
var command: MatchCommand
## The fact being handled, or null.
var fact: Fact
## The outcome of the row whose actions run, or empty.
var outcome: StringName
var outcome_argument: Variant
## The level of the current phase; for a transition action, the level of the phase it enters.
var layout: LevelLayout
## Who runs, for error messages: "rule Use of item kind knife", "row Loading, all_loaded".
var source := ""

var _match: Match


func _init(owner: Match) -> void:
	_match = owner


## The host's content hash, which a joiner's Hello must carry (§4.3, E1).
func content_hash() -> int:
	return _match.content_hash


## A copy for another part of the same step, with the same actor, intent, fact and outcome.
func copy() -> MatchContext:
	var other := MatchContext.new(_match)
	other.state = state
	other.mode = mode
	other.world = world
	other.tick = tick
	other.actor = actor
	other.command = command
	other.fact = fact
	other.outcome = outcome
	other.outcome_argument = outcome_argument
	other.layout = layout
	other.source = source
	return other


## A match setting's value (§9.1).
func setting(id: StringName) -> int:
	return state.settings.get(id, 0)


## The value of a set setting (SettingSpec.Kind.TASK_TYPES), empty when never changed.
func id_set(id: StringName) -> PackedStringArray:
	return state.id_sets.get(id, PackedStringArray())


## The generator of one RNG purpose of this match (§3.3).
func rng(purpose: StringName) -> RandomNumberGenerator:
	return state.rng.stream(purpose)


## The layout of the match's chosen map (state.map), or null: the lobby's fit check (§9.4).
func map_layout() -> LevelLayout:
	return _match.layout(state.map)


## The actor's player state, or null.
func actor_state() -> PlayerState:
	return state.player(actor)


## Emits `event` to the audience its class declares, evaluated now (§5).
func emit(event: MatchEvent) -> void:
	_match.emit_event(event)


## Rejects `rejected` with `reason`, to its sender only.
func reject(rejected: MatchCommand, reason: StringName) -> void:
	_match.emit_event(RejectedEvent.new(rejected.peer, rejected.seq, reason))


## Raises a fact: its rules run at once, depth first, then the win conditions are checked, and
## only then does the caller go on (§9.2).
func raise_fact(raised: Fact) -> void:
	_match.raise_fact(raised)


## Reports an outcome of the current phase (§3.1). A later outcome of the same step is dropped;
## when it came from the intent being handled, its sender gets `outcome_dropped`.
func report_outcome(reported: StringName, argument: Variant = null) -> void:
	_match.report_outcome(reported, argument, command)


## A rule error that must not pass silently: logged in every build with its source.
func error(message: String) -> void:
	_match.record_error("%s: %s" % [source, message] if not source.is_empty() else message)
