class_name FixturePhase
extends Phase
## A test phase class whose outcomes its spec's settings switch on:
## - `reports_all_ready`: Hello joins, SetReady sets the flag, and `all_ready` is reported when
##   every player is ready, after a SetReady and on entry;
## - `reports_back`: ReturnToLobby reports `back`;
## - `go_after_ticks` n: reports `go` on its n-th tick;
## - `countdown_ticks` n: announces an end tick n ticks after the entry;
## - `reports_twice_on_connect`: PeerConnected reports `back` twice (the second is dropped);
## - `reads_undeclared`: SetReady also reads `target`, a field SetReady does not declare (a rule's
##   bug that Match must record).
## It counts its entries, exits and ticks, so a test can see that every entry gets a fresh object.

var entries := 0
var exits := 0
var ticks_seen := 0
## What `reads_undeclared` read: the default, since SetReady declares no `target`.
var target_read := -1


func handled_intents() -> Array[StringName]:
	return [Intents.HELLO, Intents.SET_READY, Intents.RETURN_TO_LOBBY]


func outcomes() -> Array[StringName]:
	var found: Array[StringName] = []
	if setting(&"reports_all_ready", 0) > 0:
		found.append(&"all_ready")
	if setting(&"reports_back", 0) > 0:
		found.append(&"back")
	if setting(&"go_after_ticks", 0) > 0:
		found.append(&"go")
	return found


func check_settings(settings: Dictionary[StringName, float]) -> PackedStringArray:
	return check_known_settings(
		settings,
		{
			&"reports_all_ready": Vector2(0, 1),
			&"reports_back": Vector2(0, 1),
			&"go_after_ticks": Vector2(0, 1000),
			&"countdown_ticks": Vector2(0, 1000),
			&"reports_twice_on_connect": Vector2(0, 1),
			&"reads_undeclared": Vector2(0, 1),
		}
	)


func end_tick() -> int:
	var ticks := int(setting(&"countdown_ticks", 0))
	return entered_tick + ticks if ticks > 0 else -1


func enter(ctx: MatchContext) -> void:
	entries += 1
	_check_all_ready(ctx)


func exit(_ctx: MatchContext) -> void:
	exits += 1


func on_tick(ctx: MatchContext) -> void:
	ticks_seen += 1
	var go_after := int(setting(&"go_after_ticks", 0))
	if go_after > 0 and ticks_seen == go_after:
		ctx.report_outcome(&"go")


func on_peer_connected(ctx: MatchContext, _peer: int) -> void:
	if setting(&"reports_twice_on_connect", 0) > 0:
		ctx.report_outcome(&"back")
		ctx.report_outcome(&"back")


func handle_intent(ctx: MatchContext, command: MatchCommand) -> void:
	if command.kind == Intents.HELLO:
		ctx.state.add_player(command.peer, "p%d" % command.peer)
	elif command.kind == Intents.SET_READY:
		if setting(&"reads_undeclared", 0) > 0:
			target_read = command.get_int("target")
		ctx.state.player(command.peer).ready = command.get_bool("ready", true)
		_check_all_ready(ctx)
	elif command.kind == Intents.RETURN_TO_LOBBY:
		ctx.report_outcome(&"back")


func _check_all_ready(ctx: MatchContext) -> void:
	if setting(&"reports_all_ready", 0) <= 0 or ctx.state.peers().is_empty():
		return
	for peer: int in ctx.state.peers():
		if not ctx.state.player(peer).ready:
			return
	ctx.report_outcome(&"all_ready")
