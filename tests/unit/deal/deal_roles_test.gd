extends GdUnitTestSuite
## DealRoles (ARCHITECTURE §3.3, §9.4): from 0 to N-1 dissidents drawn from the roster in peer-id
## order with the `roles` stream, everyone else Crew; RoleAssigned to each player only, Teammates
## to the dissidents only; and the §5 invariants over view_of, written independently of the
## events' declared audiences.

const DISSIDENT := &"dissident"
const CREW := &"crew"


func test_dissidents_from_zero_to_n_minus_one() -> void:
	for n: int in [1, 2, 3, 5, 10]:
		var peers: Array[int] = []
		for i in n:
			peers.append(i + 1)
		for wanted: int in [0, 1, 2, 5, 9]:
			var game := FixtureDealModes.dealt(
				FixtureDealModes.deal_mode(), peers, {&"dissidents": wanted}
			)
			var expected := maxi(0, mini(wanted, n - 1))
			var dissidents := FixtureDealModes.players_of(game, DISSIDENT)
			var crew := FixtureDealModes.players_of(game, CREW)
			(
				assert_int(dissidents.size())
				. override_failure_message("%d players, %d wanted" % [n, wanted])
				. is_equal(expected)
			)
			assert_int(crew.size()).is_equal(n - expected)


func test_role_assigned_reaches_only_its_player() -> void:
	var peers: Array[int] = [1, 2, 3, 4]
	var game := FixtureDealModes.dealt(FixtureDealModes.deal_mode(), peers, {&"dissidents": 2})
	for emitted: EmittedEvent in game.emitted():
		if emitted.event is RoleAssignedEvent:
			var assigned := emitted.event as RoleAssignedEvent
			assert_array(Array(emitted.recipients)).is_equal([assigned.peer])
	for peer: int in peers:
		var own := game.view_of(peer).events_named(&"RoleAssigned")
		assert_int(own.size()).is_equal(1)
		var assigned := own[0] as RoleAssignedEvent
		assert_int(assigned.peer).is_equal(peer)
		assert_str(assigned.role).is_equal(game.state.player(peer).role)


func test_teammates_reach_every_dissident_and_nobody_else() -> void:
	var peers: Array[int] = [1, 2, 3, 4, 5, 6]
	var game := FixtureDealModes.dealt(FixtureDealModes.deal_mode(), peers, {&"dissidents": 2})
	var dissidents := FixtureDealModes.players_of(game, DISSIDENT)
	assert_int(dissidents.size()).is_equal(2)
	for peer: int in peers:
		var teammates := game.view_of(peer).events_named(&"Teammates")
		if dissidents.has(peer):
			assert_int(teammates.size()).is_equal(1)
			var event := teammates[0] as TeammatesEvent
			assert_str(event.role).is_equal(DISSIDENT)
			assert_array(Array(event.peers)).is_equal(dissidents)
		else:
			assert_array(teammates).is_empty()


func test_a_single_dissident_learns_it_is_alone() -> void:
	var game := FixtureDealModes.dealt(FixtureDealModes.deal_mode(), [1, 2, 3], {&"dissidents": 1})
	var dissident: int = FixtureDealModes.players_of(game, DISSIDENT)[0]
	var event := game.view_of(dissident).events_named(&"Teammates")[0] as TeammatesEvent
	assert_array(Array(event.peers)).is_equal([dissident])


func test_no_dissidents_no_teammates() -> void:
	var game := FixtureDealModes.dealt(FixtureDealModes.deal_mode(), [1, 2, 3], {&"dissidents": 0})
	assert_array(FixtureDealModes.players_of(game, DISSIDENT)).is_empty()
	assert_array(FixtureModes.names(game)).not_contains([&"Teammates"])
	assert_array(FixtureModes.names(game)).contains([&"RoleAssigned"])


func test_a_crew_member_knows_one_role_and_a_dissident_the_dissidents_only() -> void:
	# §5's invariant, from the payloads alone: a crew member's events never name the dissident
	# role, and a dissident's never name the crew role.
	var peers: Array[int] = [1, 2, 3, 4, 5, 6, 7]
	var game := FixtureDealModes.dealt(FixtureDealModes.deal_mode(), peers, {&"dissidents": 3})
	var dissidents := FixtureDealModes.players_of(game, DISSIDENT)
	for peer: int in peers:
		var view := game.view_of(peer)
		var known := _roles_known(view)
		if dissidents.has(peer):
			var expected := {}
			for dissident: int in dissidents:
				expected[dissident] = DISSIDENT
			assert_dict(known).is_equal(expected)
			assert_bool(_mentions(view, CREW)).is_false()
		else:
			assert_dict(known).is_equal({peer: CREW})
			assert_bool(_mentions(view, DISSIDENT)).is_false()


func test_the_draw_takes_the_roster_in_peer_id_order_with_the_roles_stream() -> void:
	var joined: Array[int] = [9, 2, 7, 4, 5]
	var seed_value := 11
	var game := FixtureDealModes.dealt(
		FixtureDealModes.deal_mode(), joined, {&"dissidents": 2}, seed_value
	)
	var roster: Array[int] = [2, 4, 5, 7, 9]
	var rng := RandomNumberGenerator.new()
	rng.seed = RngStreams.purpose_seed_of(RngStreams.match_seed_of(seed_value, 0), &"roles")
	var order := RngStreams.shuffled_indices(roster.size(), rng)
	var expected: Array[int] = [roster[order[0]], roster[order[1]]]
	expected.sort()
	assert_array(FixtureDealModes.players_of(game, DISSIDENT)).is_equal(expected)


func test_the_draw_depends_only_on_the_seed() -> void:
	var peers: Array[int] = [1, 2, 3, 4, 5, 6]
	var a := FixtureDealModes.dealt(FixtureDealModes.deal_mode(), peers, {&"dissidents": 2}, 5)
	var b := FixtureDealModes.dealt(FixtureDealModes.deal_mode(), peers, {&"dissidents": 2}, 5)
	assert_array(FixtureDealModes.players_of(a, DISSIDENT)).is_equal(
		FixtureDealModes.players_of(b, DISSIDENT)
	)
	var drawn: Array[Array] = []
	for seed_value in range(1, 9):
		var game := FixtureDealModes.dealt(
			FixtureDealModes.deal_mode(), peers, {&"dissidents": 2}, seed_value
		)
		var dissidents := FixtureDealModes.players_of(game, DISSIDENT)
		if not drawn.has(dissidents):
			drawn.append(dissidents)
	assert_int(drawn.size()).is_greater(1)


func test_quotas_draw_in_order_from_the_players_left() -> void:
	var mode := FixtureDealModes.deal_mode()
	mode.settings.append(FixtureModes.setting(&"detectives", 0, 0, 9))
	var detective := FixtureModes.role(&"detective", &"crew", false)
	mode.roles.append(detective)
	var deal := mode.transitions[0].actions[0] as DealRoles
	var second := RoleQuota.new()
	second.role = detective
	second.count_setting = &"detectives"
	deal.quotas.append(second)
	# 4 players: 2 dissidents (leaving 1), then min(3, 4 - 0) detectives, but only 2 are left.
	var game := FixtureDealModes.dealt(mode, [1, 2, 3, 4], {&"dissidents": 2, &"detectives": 3})
	assert_array(Array(game.refusals)).is_empty()
	assert_int(FixtureDealModes.players_of(game, DISSIDENT).size()).is_equal(2)
	assert_int(FixtureDealModes.players_of(game, &"detective").size()).is_equal(2)
	assert_array(FixtureDealModes.players_of(game, CREW)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_the_mode_check_refuses_an_incomplete_deal() -> void:
	var mode := FixtureDealModes.deal_mode()
	var deal := mode.transitions[0].actions[0] as DealRoles
	deal.rng_purpose = &""
	deal.default_role = FixtureModes.role(&"stranger", &"crew", false)
	var errors := "\n".join(ModeCheck.run(mode).errors)
	assert_str(errors).contains("DealRoles has no rng_purpose")
	assert_str(errors).contains("default_role stranger is not a role of the mode")
	deal.default_role = null
	assert_str("\n".join(ModeCheck.run(mode).errors)).contains("DealRoles has no default_role")


func test_a_quota_leaves_no_one_by_default() -> void:
	# The class default is neutral; the base mode writes its 1 in its data (#58's answer).
	var quota := RoleQuota.new()
	quota.count_setting = &"dissidents"
	assert_int(quota.leave_at_least).is_equal(0)
	assert_int(quota.count_for({&"dissidents": 9}, 4)).is_equal(4)
	quota.leave_at_least = 1
	assert_int(quota.count_for({&"dissidents": 9}, 4)).is_equal(3)
	assert_int(quota.count_for({&"dissidents": 9}, 1)).is_equal(0)


## Peer -> role for every role the view's events tell: RoleAssigned (its own) and Teammates.
func _roles_known(view: PeerView) -> Dictionary:
	var known := {}
	for event: MatchEvent in view.events_named(&"RoleAssigned"):
		known[view.peer] = (event as RoleAssignedEvent).role
	for event: MatchEvent in view.events_named(&"Teammates"):
		var teammates := event as TeammatesEvent
		for peer: int in teammates.peers:
			known[peer] = teammates.role
	return known


## Whether any payload in the view holds `word`, at any depth.
func _mentions(view: PeerView, word: StringName) -> bool:
	for event: MatchEvent in view.events:
		if _holds(event.to_dict(), word):
			return true
	return false


func _holds(value: Variant, word: StringName) -> bool:
	if value is Dictionary:
		var fields: Dictionary = value
		for key: Variant in fields:
			if _holds(key, word) or _holds(fields[key], word):
				return true
	elif value is Array:
		for element: Variant in value as Array:
			if _holds(element, word):
				return true
	elif value is StringName or value is String:
		return str(value) == String(word)
	return false


func test_a_forced_role_counts_toward_its_quota() -> void:
	# The engineer's answer A on #30: "dissidents 1" with peer 2 forced to dissident makes peer 2
	# the only dissident, whatever the seed.
	var peers: Array[int] = [1, 2, 3, 4]
	for seed_value: int in [1, 2, 3, 7, 11]:
		var game := _forced_deal(peers, {&"dissidents": 1}, {2: DISSIDENT}, seed_value)
		assert_array(FixtureDealModes.players_of(game, DISSIDENT)).is_equal([2])
		assert_array(FixtureDealModes.players_of(game, CREW)).is_equal([1, 3, 4])
		assert_array(Array(game.diagnostics)).is_empty()


func test_the_quota_draws_what_the_forced_roles_leave() -> void:
	var peers: Array[int] = [1, 2, 3, 4, 5, 6]
	var game := _forced_deal(peers, {&"dissidents": 2}, {5: DISSIDENT})
	var dissidents := FixtureDealModes.players_of(game, DISSIDENT)
	assert_int(dissidents.size()).is_equal(2)
	assert_bool(dissidents.has(5)).is_true()
	# More players forced than the quota: every forced one keeps its role, and the quota draws none.
	game = _forced_deal(peers, {&"dissidents": 1}, {2: DISSIDENT, 3: DISSIDENT})
	assert_array(FixtureDealModes.players_of(game, DISSIDENT)).is_equal([2, 3])


func test_a_player_forced_to_the_default_role_is_never_drawn() -> void:
	# Two players, one dissident: forcing peer 1 to crew leaves only peer 2 to draw.
	for seed_value: int in [1, 2, 3, 7, 11]:
		var game := _forced_deal([1, 2], {&"dissidents": 1}, {1: CREW}, seed_value)
		assert_array(FixtureDealModes.players_of(game, DISSIDENT)).is_equal([2])


func test_forced_roles_are_told_like_drawn_ones() -> void:
	# The same events and audiences as a draw: RoleAssigned to each player only, Teammates to the
	# dissidents only; nothing says a role was forced.
	var peers: Array[int] = [1, 2, 3]
	var game := _forced_deal(peers, {&"dissidents": 1}, {3: DISSIDENT})
	for peer: int in peers:
		var own := game.view_of(peer).events_named(&"RoleAssigned")
		assert_int(own.size()).is_equal(1)
		assert_str((own[0] as RoleAssignedEvent).role).is_equal(CREW if peer != 3 else DISSIDENT)
		var teammates := game.view_of(peer).events_named(&"Teammates")
		assert_int(teammates.size()).is_equal(1 if peer == 3 else 0)


func test_a_forced_role_the_mode_lacks_is_an_error_and_ignored() -> void:
	var game := _forced_deal([1, 2], {&"dissidents": 0}, {2: &"medic"})
	assert_array(FixtureDealModes.players_of(game, CREW)).is_equal([1, 2])
	assert_int(game.diagnostics.size()).is_equal(1)
	assert_str(game.diagnostics[0]).contains("medic")


func test_forced_roles_are_logged_and_replayed() -> void:
	var peers: Array[int] = [1, 2, 3, 4]
	var game := _forced_deal(peers, {&"dissidents": 1}, {4: DISSIDENT})
	var forcing: Array[MatchCommand] = []
	for command: MatchCommand in game.command_log.commands:
		if command.kind == Intents.FORCE_ROLE:
			forcing.append(command)
	assert_int(forcing.size()).is_equal(1)
	assert_int(forcing[0].peer).is_equal(4)
	var replayed := Match.replay(game.command_log, game.mode)
	assert_array(FixtureDealModes.players_of(replayed, DISSIDENT)).is_equal([4])
	assert_int(replayed.emitted().size()).is_equal(game.emitted().size())


func test_a_role_forced_after_the_players_joined_applies_to_the_deal() -> void:
	# server/'s debug path knows a joining player's peer id only after it connected (ENet): the
	# ForceRole comes in the lobby, after the Hello, and the deal still honours it.
	var peers: Array[int] = [1, 1002, 1003]
	for seed_value: int in [1, 2, 3]:
		var game := _forced_deal(peers, {&"dissidents": 1}, {1003: DISSIDENT}, seed_value)
		assert_array(FixtureDealModes.players_of(game, DISSIDENT)).is_equal([1003])
		assert_array(Array(game.diagnostics)).is_empty()


func test_reset_match_keeps_forced_roles_and_an_empty_role_clears_one() -> void:
	var game := _forced_deal([1, 2, 3], {&"dissidents": 1}, {2: DISSIDENT, 3: CREW})
	game.state.reset_match()
	assert_dict(game.state.forced_roles).is_equal({2: DISSIDENT, 3: CREW})
	FixtureModes.send(game, Intents.FORCE_ROLE, 3, {"role": ""})
	assert_dict(game.state.forced_roles).is_equal({2: DISSIDENT})
	assert_array(Array(game.diagnostics)).is_empty()


func _forced_deal(
	peers: Array[int],
	settings: Dictionary[StringName, int],
	forced: Dictionary[int, StringName],
	seed_value: int = 7
) -> Match:
	return FixtureDealModes.dealt(
		FixtureDealModes.deal_mode(),
		peers,
		settings,
		seed_value,
		FixtureDealModes.ITEM_MARKERS,
		PackedStringArray(),
		forced
	)
