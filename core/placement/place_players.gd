class_name PlacePlayers
extends RuleEffect
## Places every present player at a distinct random marker of `tag` (ARCHITECTURE §3.2, §9.4): a
## transition action of the deal (`round_player`) and of `End -> Lobby` (`lobby_player`). The
## markers come from the layout of the level being entered; players are taken in peer-id order
## and the markers are shuffled with the RNG purpose `rng_purpose`. Each placed player gets a new
## epoch, so claims still in flight from the old scene are dropped as stale.
##
## Emits: PlayersPlaced (everyone: positions are public), then a Correction per player, in
## peer-id order (that player only: its new epoch). Demands: one `tag` marker per player.

@export var tag: StringName = &"round_player"
@export var rng_purpose: StringName = &"spawns"


func run(ctx: MatchContext) -> void:
	if ctx.layout == null:
		ctx.error("PlacePlayers: no layout for the level being entered")
		return
	var spots := ctx.layout.positions(tag)
	var peers := ctx.state.present_peers()
	if spots.size() < peers.size():
		ctx.error(
			"PlacePlayers: %d %s marker(s) for %d players" % [spots.size(), tag, peers.size()]
		)
		return
	var order := RngStreams.shuffled_indices(spots.size(), ctx.rng(rng_purpose))
	var placed: Dictionary[int, Vector3] = {}
	for i in peers.size():
		var player := ctx.state.players[peers[i]]
		player.position = spots[order[i]]
		player.velocity = Vector3.ZERO
		player.epoch += 1
		placed[player.peer] = player.position
	ctx.emit(PlayersPlacedEvent.new(placed))
	for peer: int in peers:
		var player := ctx.state.players[peer]
		ctx.emit(CorrectionEvent.new(peer, player.epoch, player.position, player.velocity))


func emits() -> Array[Script]:
	return [PlayersPlacedEvent, CorrectionEvent]


func add_demands(_settings: Dictionary[StringName, int], players: int, into: Demands) -> void:
	into.add_markers(tag, players)


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if tag.is_empty():
		found.append("PlacePlayers has no tag")
	if rng_purpose.is_empty():
		found.append("PlacePlayers has no rng_purpose")
	return found
