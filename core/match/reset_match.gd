class_name ResetMatch
extends RuleEffect
## Resets the match state from the roster (ARCHITECTURE §3.2, §9.1, §9.4): a transition action of
## `End -> Lobby`. MatchState.reset_match() clears items, stations, tasks and their task states,
## bodies, roles, life, health, stamina, cooldowns, counters, per-part state, the clock and the
## winner, and drops the players who left; then everyone is un-ready. It keeps the roster's
## players and the session's join count (MatchState.joins, §3.5), so Player<n> numbering runs on.
##
## It must run before the row's PlacePlayers: placed first, a downed or dead player would be placed
## in the lobby still downed or dead, a dead one with no avatar in anyone's snapshot.
##
## Emits: ReadyChanged(peer, false) (everyone), per player in peer-id order; then SettingsChanged
## (everyone, FitCheck), as a leave in the lobby does (#737): the players who left mid-match are
## dropped here, so the lobby may be short of the mode's min_players again, and the shortfalls
## every client last got are the empty ones of before the countdown. No demands.


func run(ctx: MatchContext) -> void:
	ctx.state.reset_match()
	for peer: int in ctx.state.present_peers():
		ctx.emit(ReadyChangedEvent.new(peer, false))
	ctx.emit(FitCheck.settings_changed(ctx))


func emits() -> Array[Script]:
	return [ReadyChangedEvent, SettingsChangedEvent]
