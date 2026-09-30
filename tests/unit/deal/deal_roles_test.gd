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
