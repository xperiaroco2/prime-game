class_name SelfStatusFeed
extends RefCounted
## SelfStatus to each player on change, at most once per tick (ARCHITECTURE §4.2, §7.1). A rule
## that changes a player's health, stamina or sprint availability touches that player (the
## movement rule, StaminaCost, later the knife's Strike); at the end of every tick Match flushes:
## each touched player whose status differs from the last one it was sent gets one SelfStatus,
## with the tick's final numbers. The first touch after a join or ResetMatch always sends one,
## because the record of what was sent lives in the per-part state, which ResetMatch clears.

## Its key in MatchState's per-part state (§9.1).
const PART_KEY := &"self_status"


## What the feed remembers between ticks.
class FeedState:
	extends RefCounted
	## Peers touched since the last flush.
	var touched: Dictionary[int, bool] = {}
	## Peer -> the last SelfStatus it was sent, as [health, stamina, sprint available].
	var sent: Dictionary[int, Array] = {}


## Marks `peer`'s status as possibly changed in this tick.
static func touch(state: MatchState, peer: int) -> void:
	_feed(state).touched[peer] = true


## Sends one SelfStatus to each touched player whose status changed since its last one. Match
## calls it at the end of every tick.
static func flush(ctx: MatchContext) -> void:
	var feed := _feed(ctx.state)
	if feed.touched.is_empty():
		return
	var peers: Array[int] = []
	peers.assign(feed.touched.keys())
	peers.sort()
	feed.touched.clear()
	for peer: int in peers:
		var player := ctx.state.player(peer)
		if player == null or not player.is_present():
			continue
		var available := StaminaLedger.sprint_available(player, ctx.state.player_rules)
		var status: Array = [player.health, player.stamina, available]
		if feed.sent.get(peer, []) == status:
			continue
		feed.sent[peer] = status
		ctx.emit(SelfStatusEvent.new(peer, player.health, player.stamina, available))


static func _feed(state: MatchState) -> FeedState:
	return state.part_state(PART_KEY, func() -> RefCounted: return FeedState.new()) as FeedState
