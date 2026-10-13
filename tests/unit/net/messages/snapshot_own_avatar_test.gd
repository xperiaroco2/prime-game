extends GdUnitTestSuite
## A full match's knocked-down viewer gets its whole snapshot over the wire, its own avatar
## included (the knockdown rework's KE5, #847): every player's avatar under WireSchema.MAX_AVATARS
## (= MAX_PLAYERS, 16), within the unreliable cap, decoded back unchanged; a living viewer's holds
## the others only. A mode holds at most PlayerColours.COUNT players (the mode check), so the
## match is full at that count, and the wire's own worst case, 16 avatars, is its snapshot padded
## to MAX_PLAYERS.

const Samples := preload("res://tests/unit/net/messages/wire_samples.gd")


func test_a_full_matchs_knocked_down_viewer_gets_its_own_avatar_with_every_other() -> void:
	var peers: Array[int] = []
	for peer in range(1, PlayerColours.COUNT + 1):
		peers.append(peer)
	var mode := FixtureModes.basic()
	mode.max_players = peers.size()
	var game := Match.new(mode, 7, FlatWorldQuery.new(), FixtureModes.layouts(peers.size()))
	assert_array(Array(game.refusals)).is_empty()
	game.keep_history = true
	game.start(0)
	for peer: int in peers:
		FixtureModes.send(game, Intents.HELLO, peer, {"name": "p%d" % peer})
	for peer: int in peers:
		FixtureModes.send(game, Intents.SET_READY, peer, {"ready": true})
	assert_int(game.state.present_peers().size()).is_equal(peers.size())
	assert_str(str(game.phase_id())).is_equal("round")
	var viewer := peers.back() as int
	game.state.player(viewer).life = PlayerState.Life.DOWNED
	FixtureModes.run_ticks(game, 1)
	var schema := WireSchema.game(false)
	var avatars: Dictionary = game.snapshot_for(viewer)["avatars"]
	var downed := _round_trip(schema, game.ticked_through(), avatars)
	assert_int(downed.size()).is_equal(peers.size())
	assert_bool(downed.has(viewer)).is_true()
	assert_bool(downed[viewer]["downed"] as bool).is_true()
	assert_bool(Samples.same(downed, avatars)).is_true()
	var living := _round_trip(
		schema, game.ticked_through(), game.snapshot_for(1)["avatars"] as Dictionary
	)
	assert_int(living.size()).is_equal(peers.size() - 1)
	assert_bool(living.has(1)).is_false()
	# The wire's worst case: a knocked-down viewer among MAX_PLAYERS, 16 avatars.
	var padded := avatars.duplicate(true)
	for peer in range(peers.size() + 1, WireSchema.MAX_PLAYERS + 1):
		padded[peer] = (avatars[1] as Dictionary).duplicate()
	assert_int(padded.size()).is_equal(WireSchema.MAX_AVATARS)
	var full := _round_trip(schema, game.ticked_through(), padded)
	assert_int(full.size()).is_equal(WireSchema.MAX_PLAYERS)
	assert_bool(Samples.same(full, padded)).is_true()


## A Snapshot of `avatars` at `at_tick`, encoded and decoded as HostSession sends it: its avatars.
func _round_trip(schema: WireSchema, at_tick: int, avatars: Dictionary) -> Dictionary:
	var fields := {"tick": at_tick, "avatars": avatars}
	var encoded := schema.write(WireMessage.new(&"Snapshot", fields))
	assert_str(encoded.problem).is_empty()
	var decoded := schema.decode(schema.kind_of(&"Snapshot"), encoded.payload)
	assert_object(decoded).is_not_null()
	return decoded.fields["avatars"] if decoded != null else {}
