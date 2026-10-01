class_name Match
extends RefCounted
## The one match loop (ARCHITECTURE §3.1, §3.3, §9.2). It knows no game mode: it runs the one it
## is given, owns the MatchState, creates a fresh phase object on every phase entry, sends each
## accepted intent to the phase class, the movement rule or a rule, handles facts depth first,
## checks the win conditions, resolves outcomes through the mode's transition table, emits
## events with their recipients, and records everything it is given in the command log.
##
## server/ (and the tests) drive it: start(tick) once, then for every host tick first apply()
## each command stamped with that tick, in the order received, then tick(tick). Each of these is
## a step; after every step the first outcome reported in it moves the match on.

## A chain of facts deeper than this is a bug (§9.2).
const MAX_FACT_DEPTH := 16
## A step that moves through more phases than this is a bug (a cycle of rows on entry).
const MAX_TRANSITIONS_PER_STEP := 16
## The outcome of a win condition; its argument is the side.
const WON := &"won"

var mode: GameMode
var state: MatchState
## The host's content hash (§4.3, E1): its game mode's ContentHash combined with the SHA-256 of
## every level file the mode names and of every scene and resource those levels reach (#118),
## which server/ computes; each Hello's `content` must equal it.
var content_hash := 0
var command_log: CommandLog
## Why the mode was refused (ModeCheck, §9.1), each problem once; empty when it runs.
var refusals := PackedStringArray()
## ModeCheck's warnings (a role-owned rule with a public event, §9.2).
var warnings := PackedStringArray()
## Errors and dropped outcomes while running, in order; each is also logged, in every build.
var diagnostics := PackedStringArray()
## Records each peer's snapshot and speakers per tick for view_of() (tests, the leak test). Off
## by default: on, a 10-player, 10-minute match at 20 Hz keeps about 1 GiB.
var keep_history := false

var _world: WorldQuery
var _layouts: Dictionary[String, LevelLayout] = {}
var _movement := MovementRule.new()
var _phase: Phase
var _phase_spec: PhaseSpec
var _started := false
var _now := 0
var _ticked_through := -1
var _in_tick := false
## True while a row's actions and the old phase's exit run: no outcome may be reported then.
var _in_transition := false
## Errors recorded while a row's actions and the old phase's exit ran (row_error_count()).
var _row_errors := 0
var _step_has_outcome := false
var _step_outcome: StringName
var _step_argument: Variant
var _fact_chain: Array[StringName] = []
var _emitted: Array[EmittedEvent] = []
var _outbox_from := 0
## Peer -> {tick: snapshot}.
var _snapshots: Dictionary[int, Dictionary] = {}
## Peer -> {tick: PackedInt32Array of speakers}.
var _speakers: Dictionary[int, Dictionary] = {}


## A match of `game_mode`, seeded by the session seed, asking `world` its geometry, with the
## layouts of the mode's levels by path (§9.1), and the host's content hash that every joiner's
## Hello must carry (§4.3, E1). A mode with errors is refused: see `refusals`.
func _init(
	game_mode: GameMode,
	session_seed: int,
	world: WorldQuery,
	layouts: Dictionary[String, LevelLayout],
	host_content_hash: int = 0
) -> void:
	mode = game_mode
	state = MatchState.new(session_seed)
	content_hash = host_content_hash
	command_log = CommandLog.new()
	command_log.session_seed = session_seed
	command_log.content_hash = host_content_hash
	command_log.layouts = layouts.duplicate()
	_layouts = layouts.duplicate()
	_world = RecordingWorldQuery.new(world, command_log)
	if mode == null:
		refusals.append("no game mode")
		return
	command_log.mode_path = mode.resource_path
	command_log.mode_hash = ContentHash.of(mode)
	var check := ModeCheck.run(mode)
	refusals = check.errors
	# The second part of the check (§9.1): the mode against the layouts handed in (2b).
	refusals.append_array(LayoutCheck.run(mode, _layouts))
	warnings = check.warnings
	for warning: String in warnings:
		push_warning("match: %s" % warning)
	state.settings = mode.default_settings()
	state.player_rules = mode.player_rules
	state.map = mode.maps[0] if not mode.maps.is_empty() else ""


## Replays a recorded match (§3.3): the same mode, seed, layouts, commands and ticks, with the
## recorded WorldQuery answers. Refused, with nothing run, when the mode's content hash differs.
## A replay that asked other questions than the recorded ones, or left answers unread, diverged:
## it says so in `diagnostics`.
static func replay(recorded: CommandLog, game_mode: GameMode) -> Match:
	var world := ReplayWorldQuery.new(recorded.world_answers)
	var replayed := Match.new(
		game_mode, recorded.session_seed, world, recorded.layouts, recorded.content_hash
	)
	if replayed.command_log.mode_hash != recorded.mode_hash:
		replayed.refusals.append(
			(
				"replay: the content of %s differs from the recorded %s (hash %d, recorded %d)"
				% [
					replayed.command_log.mode_path,
					recorded.mode_path,
					replayed.command_log.mode_hash,
					recorded.mode_hash
				]
			)
		)
		return replayed
	if not replayed.start(recorded.start_tick):
		return replayed
	for command: MatchCommand in recorded.commands:
		while replayed.ticked_through() < command.tick - 1:
			replayed.tick(replayed.ticked_through() + 1)
		replayed.apply(MatchCommand.from_dict(command.to_dict()))
	while replayed.ticked_through() < recorded.ticked_through:
		replayed.tick(replayed.ticked_through() + 1)
	if world.diverged or world.unread() > 0:
		replayed.record_error(
			(
				"replay: diverged from the recorded WorldQuery answers (%d left unread)"
				% world.unread()
			)
		)
	return replayed


## Enters the mode's first phase on `at_tick`: the "(start)" row. False when refused.
func start(at_tick: int) -> bool:
	if not refusals.is_empty():
		push_error("match: the game mode is refused: %s" % "; ".join(refusals))
		return false
	if _started:
		record_error("start: the match has started already")
		return false
	_started = true
	_now = at_tick
	_ticked_through = at_tick - 1
	command_log.start_tick = at_tick
	command_log.ticked_through = _ticked_through
	_begin_step()
	_world.use_level(_level_path(mode.find_phase(mode.first_phase)))
	_enter_phase(mode.first_phase)
	_finish_step()
	return true


## One command, stamped with the next tick to run: an intent or a server command. False when it
## cannot be applied (not started, or the wrong tick); a rejected intent still returns true.
## The command log keeps `command` itself: never change it after this call.
func apply(command: MatchCommand) -> bool:
	if not _started:
		record_error("apply: the match has not started")
		return false
	if command.tick != _ticked_through + 1:
		record_error(
			(
				"apply: %s is stamped with tick %d, the next tick is %d"
				% [command.kind, command.tick, _ticked_through + 1]
			)
		)
		return false
	_now = command.tick
	command_log.commands.append(command)
	_begin_step()
	_dispatch(command)
	_finish_step()
	# A rule that read a field its intent does not declare is a bug a test must see (§4.4).
	for key: String in command.undeclared_reads:
		record_error(
			(
				"%s from peer %d: a rule read field %s, which Intents.FIELDS does not declare"
				% [command.kind, command.peer, key]
			)
		)
	command.undeclared_reads.clear()
	return true


## Runs tick `at_tick`, which must be the next one (§3.3): the phase's own timers, its tick
## systems in order, then the match clock if the phase's clock runs, then the SelfStatus of each
## player whose own numbers changed in the tick.
func tick(at_tick: int) -> bool:
	if not _started:
		record_error("tick: the match has not started")
		return false
	if at_tick != _ticked_through + 1:
		record_error("tick: tick %d, the next tick is %d" % [at_tick, _ticked_through + 1])
		return false
	_now = at_tick
	_in_tick = true
	_begin_step()
	_phase.on_tick(_context("phase %s" % _phase_spec.id))
	for system: TickSystem in _phase_spec.tick_systems:
		system.run(_context("tick system of phase %s" % _phase_spec.id))
	if _phase_spec.clock_runs and state.clock_ticks_left > 0:
		state.clock_ticks_left -= 1
		if state.clock_ticks_left == 0 and not state.clock_ended:
			state.clock_ended = true
			raise_fact(Fact.new(Facts.CLOCK_ENDED))
	_finish_step()
	# SelfStatus goes out on change, at most once per tick, with the tick's final numbers (§4.2).
	SelfStatusFeed.flush(_context("self status"))
	_ticked_through = at_tick
	command_log.ticked_through = at_tick
	_in_tick = false
	_record_views(at_tick)
	return true


## The last tick run.
func ticked_through() -> int:
	return _ticked_through


## The current phase's id.
func phase_id() -> StringName:
	return _phase_spec.id if _phase_spec != null else &""


## The current phase object (for tests and server/'s inspection; parts get a MatchContext).
func current_phase() -> Phase:
	return _phase


## The layout of the level at `path`, as handed in on creation, or null. The lobby's fit check
## reads the chosen map's (2b); parts get theirs through MatchContext.
func layout(path: String) -> LevelLayout:
	return _layouts.get(path)


## Every event emitted so far, in order, with its recipients.
func emitted() -> Array[EmittedEvent]:
	return _emitted.duplicate()


## The events emitted since the last call: what server/ sends next, one message per recipient.
func take_outbox() -> Array[EmittedEvent]:
	var batch := _emitted.slice(_outbox_from)
	_outbox_from = _emitted.size()
	return batch


## What `peer` is entitled to now: its snapshot, or empty when the phase sends none (§5).
func snapshot_for(peer: int) -> Dictionary:
	if _phase_spec == null or not _phase_spec.snapshots or not state.is_present(peer):
		return {}
	return Snapshots.for_peer(state, peer)


## The speakers `listener` may hear now (§6).
func speakers_for(listener: int) -> PackedInt32Array:
	if _phase_spec == null or _phase_spec.voice_rule == null:
		return PackedInt32Array()
	return _phase_spec.voice_rule.speakers_of(state, listener)


## Everything an honest client of `peer` can know (§5): its events in order, its snapshots and
## its speakers per tick.
func view_of(peer: int) -> PeerView:
	var view := PeerView.new(peer)
	for emitted_event: EmittedEvent in _emitted:
		if emitted_event.recipients.has(peer):
			view.events.append(emitted_event.event)
	var snapshots: Dictionary = _snapshots.get(peer, {})
	for at_tick: int in snapshots:
		view.snapshots[at_tick] = snapshots[at_tick]
	var speakers: Dictionary = _speakers.get(peer, {})
	for at_tick: int in speakers:
		view.speakers[at_tick] = speakers[at_tick]
	return view


## Emits `event` now, to the recipients its audience names against the current state (§5).
## Parts call MatchContext.emit().
func emit_event(event: MatchEvent) -> void:
	var audience := event.audience()
	var directive := audience.kind == Audience.Kind.SERVER
	_emitted.append(EmittedEvent.new(_now, event, audience.recipients(state), directive))


## Handles a fact at once, depth first (§9.2): the mode's reactions, then each task type's check
## in the mode's order, then the win conditions. Parts call MatchContext.raise_fact().
func raise_fact(fact: Fact) -> void:
	if _fact_chain.size() >= MAX_FACT_DEPTH:
		record_error(
			(
				"a chain of more than %d facts, stopped at %s: %s"
				% [MAX_FACT_DEPTH, fact.name, " > ".join(_fact_chain)]
			)
		)
		return
	_fact_chain.append(fact.name)
	for rule: Rule in mode.reactions:
		if rule.trigger == fact.name:
			var ctx := _context("reaction on %s of the mode" % fact.name)
			ctx.fact = fact
			RuleRunner.run(rule, ctx)
	for type: TaskType in mode.task_types:
		var ctx := _context("task type %s on %s" % [type.id, fact.name])
		ctx.fact = fact
		type.on_fact(ctx)
	_check_wins()
	_fact_chain.pop_back()


## Records `outcome` as this step's, unless the step has one already (§3.1): then it is dropped
## and logged, and when `sender`'s intent reported it, the sender gets `outcome_dropped`. Parts
## call MatchContext.report_outcome().
func report_outcome(outcome: StringName, argument: Variant, sender: MatchCommand) -> void:
	if _in_transition:
		# The row is already moving the match on; an outcome now would be taken as the next
		# phase's (a row action raising a fact that re-reports `won`, say).
		record_error("outcome %s reported during the row actions of %s" % [outcome, phase_id()])
		return
	if _step_has_outcome:
		var message := (
			"dropped: outcome %s of phase %s, because %s was reported first in this step"
			% [outcome, phase_id(), _step_outcome]
		)
		diagnostics.append(message)
		push_warning("match: %s" % message)
		# Rejected answers intents only (§4.2): a dropped outcome of PeerConnected is only logged.
		if sender != null and Intents.ALL.has(sender.kind):
			emit_event(RejectedEvent.new(sender.peer, sender.seq, RejectReasons.OUTCOME_DROPPED))
		return
	_step_has_outcome = true
	_step_outcome = outcome
	_step_argument = argument


## Logs an error in every build and keeps it in `diagnostics`.
func record_error(message: String) -> void:
	diagnostics.append("error: %s" % message)
	push_error("match: %s" % message)
	if _in_transition:
		_row_errors += 1


## How many errors were recorded while a transition row ran (its actions, the deal's included,
## and the old phase's exit) since the match was created. server/ reads it after every apply()
## and tick(): a new one ends the session, so a round never starts from a failed deal, and server/
## names no phase or outcome of the mode (§4.5 "A failed deal is fatal"). Errors outside a row (a
## ForceRole naming a role the mode lacks, a phase's own timers) are only logged.
func row_error_count() -> int:
	return _row_errors


func _begin_step() -> void:
	_step_has_outcome = false
	_step_outcome = &""
	_step_argument = null


## The end of a step: the win check, then the first outcome's row, which enters the next phase;
## that entry is a step of its own, so a condition that already holds moves on at once.
func _finish_step() -> void:
	var transitions := 0
	while true:
		_check_wins()
		if not _step_has_outcome:
			return
		transitions += 1
		if transitions > MAX_TRANSITIONS_PER_STEP:
			record_error("more than %d transitions in one step" % MAX_TRANSITIONS_PER_STEP)
			_begin_step()
			return
		var outcome := _step_outcome
		var argument: Variant = _step_argument
		_begin_step()
		if not _transition(outcome, argument):
			return


func _check_wins() -> void:
	if _in_transition or _step_has_outcome or _phase_spec == null or not _phase_spec.checks_wins:
		return
	for condition: WinCondition in mode.win_conditions:
		if condition.holds(_context("win condition %s" % condition.id)):
			report_outcome(WON, condition.side, null)
			return


## Runs the row of `outcome` from the current phase: its actions, the exit, the next entry. An
## outcome without a row fails loudly (§3.1).
func _transition(outcome: StringName, argument: Variant) -> bool:
	var from := _phase_spec.id
	var row := mode.find_transition(from, outcome)
	if row == null:
		record_error("phase %s reported %s, which has no transition row" % [from, outcome])
		return false
	var ctx := _context("row %s, %s" % [from, outcome])
	ctx.outcome = outcome
	ctx.outcome_argument = argument
	var to_spec := mode.find_phase(row.to)
	ctx.layout = _layout_of(to_spec)
	# The row's actions ask about the level of the phase it enters (§4.5, E9).
	_world.use_level(_level_path(to_spec))
	_in_transition = true
	for action: RuleEffect in row.actions:
		action.run(ctx)
	_phase.exit(_context("phase %s" % from))
	_in_transition = false
	_enter_phase(row.to)
	return true


func _enter_phase(id: StringName) -> void:
	_phase_spec = mode.find_phase(id)
	_phase = _phase_spec.create_phase()
	_phase.entered_tick = _now
	var end := _phase.end_tick()
	if end < 0 and _phase_spec.clock_runs and state.clock_ticks_left > 0:
		end = _next_clock_tick() + state.clock_ticks_left - 1
	emit_event(PhaseChangedEvent.new(id, end))
	_phase.enter(_context("phase %s" % id))


## The first tick whose clock step is still to run: during tick t's own step it has run.
func _next_clock_tick() -> int:
	return _ticked_through + (2 if _in_tick else 1)


func _dispatch(command: MatchCommand) -> void:
	var ctx := _context("%s from peer %d" % [command.kind, command.peer])
	ctx.actor = command.peer
	ctx.command = command
	if command.kind == Intents.PEER_CONNECTED:
		_phase.on_peer_connected(ctx, command.peer)
	elif command.kind == Intents.PEER_LEFT:
		_phase.on_peer_left(ctx, command.peer)
	elif command.kind == Intents.FORCE_ROLE:
		_force_role(command)
	elif not Intents.ALL.has(command.kind):
		record_error("unknown command %s from peer %d" % [command.kind, command.peer])
	elif not _accepts(command):
		_refuse(command, ctx)
	elif _phase.handles(command.kind):
		_phase.handle_intent(ctx, command)
	elif command.kind == Intents.MOVE_CLAIM:
		_movement.apply(ctx, command)
	else:
		_run_action(command, ctx)


## ForceRole (debug builds only, §8): in any phase, for the deals that follow; DealRoles gives the
## peer its role when it is present. An empty role clears it; a role the mode lacks is a match
## error and ignored. Kept in the command log like every command, so a replay deals the same.
func _force_role(command: MatchCommand) -> void:
	var role_id := StringName(command.get_string("role"))
	if role_id.is_empty():
		state.forced_roles.erase(command.peer)
	elif mode.find_role(role_id) == null:
		record_error("ForceRole: peer %d, role %s, which the mode lacks" % [command.peer, role_id])
	else:
		state.forced_roles[command.peer] = role_id


## An intent the phase's allowlist refuses (§3.1, §4.3) gets Rejected (`not_accepted`), except:
## - a MoveClaim is dropped silently (E15): one in flight at a phase change, which has no seq for
##   a Rejected to name and which clients ignore, so a looping client cannot fill the command log
##   and the outbox with Rejected events;
## - a Hello from a peer that is not a player gets Rejected (`joins_closed`) and, when it is a
##   newcomer, DisconnectPeer (E14): the phase takes no joins, so the joiner is told why at once
##   and does not linger. A peer that is neither was disconnected already (its connection was
##   refused, or Loading's entry dropped it) and gets no second DisconnectPeer.
func _refuse(command: MatchCommand, ctx: MatchContext) -> void:
	if command.kind == Intents.MOVE_CLAIM:
		return
	if command.kind == Intents.HELLO and state.player(command.peer) == null:
		ctx.reject(command, RejectReasons.JOINS_CLOSED)
		if state.newcomers.erase(command.peer):
			emit_event(DisconnectPeerEvent.new(command.peer))
		return
	ctx.reject(command, RejectReasons.NOT_ACCEPTED)


## An accepted intent that no phase class handles goes to the first rule for it (§9.2).
func _run_action(command: MatchCommand, ctx: MatchContext) -> void:
	# Only a phase class can take an intent from a newcomer (ModeCheck refuses the rest).
	if state.player(command.peer) == null:
		ctx.reject(command, RejectReasons.NOT_ACCEPTED)
		return
	var rule := _find_action(command, ctx)
	if rule == null:
		ctx.reject(command, RejectReasons.NOTHING_TO_DO)
		return
	var reason := RuleRunner.run(rule, ctx)
	if not reason.is_empty():
		ctx.reject(command, reason)


## Whether the current phase's allowlist accepts the intent from its sender (§3.1).
func _accepts(command: MatchCommand) -> bool:
	var from := _phase_spec.senders_of(command.kind)
	var player := state.player(command.peer)
	if player == null:
		return from & AcceptSpec.From.NEWCOMER != 0
	if not player.is_present():
		return false
	if from & AcceptSpec.From.PLAYER != 0:
		return true
	if from & AcceptSpec.From.LIVING != 0 and player.life == PlayerState.Life.ALIVE:
		return true
	if from & AcceptSpec.From.DOWNED != 0 and player.life == PlayerState.Life.DOWNED:
		return true
	return from & AcceptSpec.From.HOST != 0 and command.peer == 1


## The first rule for the intent among the held item's actions, the actor's role's and the
## mode's (§9.2), with ctx.source naming it; null when none.
func _find_action(command: MatchCommand, ctx: MatchContext) -> Rule:
	var player := state.player(command.peer)
	if player.held_item >= 0 and state.items.has(player.held_item):
		var kind := state.items[player.held_item].kind
		var rule := _first_rule(kind.actions, command.kind)
		if rule != null:
			ctx.source = "action %s of item kind %s" % [command.kind, kind.id]
			return rule
	var role := mode.find_role(player.role)
	if role != null:
		var rule := _first_rule(role.actions, command.kind)
		if rule != null:
			ctx.source = "action %s of role %s" % [command.kind, role.id]
			return rule
	var mode_rule := _first_rule(mode.actions, command.kind)
	if mode_rule != null:
		ctx.source = "action %s of the mode" % command.kind
	return mode_rule


static func _first_rule(rules: Array[Rule], trigger: StringName) -> Rule:
	for rule: Rule in rules:
		if rule.trigger == trigger:
			return rule
	return null


func _context(source: String) -> MatchContext:
	var ctx := MatchContext.new(self)
	ctx.state = state
	ctx.mode = mode
	ctx.world = _world
	ctx.tick = _now
	ctx.layout = _layout_of(_phase_spec)
	ctx.source = source
	return ctx


func _layout_of(spec: PhaseSpec) -> LevelLayout:
	var path := _level_path(spec)
	return _layouts.get(path) if not path.is_empty() else null


## The path of the level `spec` plays in: the mode's lobby, the match's map, or empty.
func _level_path(spec: PhaseSpec) -> String:
	if spec == null:
		return ""
	match spec.level:
		PhaseSpec.Level.LOBBY:
			return mode.lobby_level
		PhaseSpec.Level.MAP:
			return state.map
	return ""


func _record_views(at_tick: int) -> void:
	if not keep_history:
		return
	for peer: int in state.present_peers():
		if _phase_spec.snapshots:
			if not _snapshots.has(peer):
				_snapshots[peer] = {}
			_snapshots[peer][at_tick] = Snapshots.for_peer(state, peer)
		if not _speakers.has(peer):
			_speakers[peer] = {}
		_speakers[peer][at_tick] = speakers_for(peer)
