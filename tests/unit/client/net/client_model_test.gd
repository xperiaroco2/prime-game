extends GdUnitTestSuite
## ClientModel (ARCHITECTURE §4.6): what a client knows, folded from decoded events (here core/'s
## own events through to_dict(), which the codec reproduces exactly): the roster, settings, phase,
## items with every player's hand and belt (E29), stations with a zone's progress (ZE8 of the zone
## task ADR), tasks (E30), bodies, each player's life (E25), avatars and its own SelfStatus; a
## match's facts cleared on LoadMatch and on entering the lobby, the roster and settings kept.

const OWN := 2

var _model: ClientModel


func before_test() -> void:
	_model = ClientModel.new(FixtureBaseMode.mode())
	var welcome := WelcomeEvent.new(OWN, Vector3(1, 0, 2), 3)
	(
		welcome
		. roster
		. assign(
			[
				{"peer": 1, "name": "Player1", "ready": true},
				{"peer": OWN, "name": "Player2", "ready": false},
			]
		)
	)
	welcome.settings = {&"knives": 2}
	welcome.map = "res://levels/a.tscn"
	welcome.phase = &"lobby"
	welcome.positions = {1: Vector3(5, 0, 5)}
	_fold(welcome)


func test_welcome_gives_the_peer_epoch_roster_settings_and_phase() -> void:
	assert_int(_model.own_peer).is_equal(OWN)
	assert_int(_model.epoch).is_equal(3)
	assert_array(_model.roster.keys()).contains_exactly([1, OWN])
	assert_str(_model.roster[1].name).is_equal("Player1")
	assert_bool(_model.roster[1].ready).is_true()
	assert_int(_model.settings[&"knives"]).is_equal(2)
	assert_str(_model.map).is_equal("res://levels/a.tscn")
	assert_str(String(_model.phase)).is_equal("lobby")
	assert_vector(_model.spots[OWN]).is_equal(Vector3(1, 0, 2))
	assert_vector(_model.spots[1]).is_equal(Vector3(5, 0, 5))


func test_the_roster_follows_joins_leaves_and_ready() -> void:
	_fold(PlayerJoinedEvent.new(3, "Player3", Vector3(0, 0, 9)))
	_fold(ReadyChangedEvent.new(3, true))
	assert_bool(_model.roster[3].ready).is_true()
	assert_vector(_model.spots[3]).is_equal(Vector3(0, 0, 9))
	_fold(PlayerLeftEvent.new(1))
	assert_array(_model.roster.keys()).contains_exactly([OWN, 3])


func test_settings_changed_and_phase_changed() -> void:
	var numbers: Dictionary[StringName, int] = {&"knives": 4}
	var sets: Dictionary[StringName, PackedStringArray] = {
		&"banned_task_types": PackedStringArray(["delivery"])
	}
	var problems := PackedStringArray(["2 knife marker(s) needed, the map has 0"])
	_fold(
		SettingsChangedEvent.new(
			numbers, "res://levels/b.tscn", 2, Demands.new(null), null, problems, sets
		)
	)
	assert_int(_model.settings[&"knives"]).is_equal(4)
	assert_array(_model.id_sets[&"banned_task_types"]).contains_exactly(["delivery"])
	assert_str(_model.map).is_equal("res://levels/b.tscn")
	assert_array(_model.shortfalls).has_size(1)
	_fold(PhaseChangedEvent.new(&"countdown", 100))
	assert_str(String(_model.phase)).is_equal("countdown")
	assert_int(_model.end_tick).is_equal(100)


func test_items_stations_and_bodies_follow_the_events() -> void:
	_to_round()
	_fold(StationPlacedEvent.new(0, &"circle", Color.RED, Vector3(9, 0, 9)))
	_fold(ItemSpawnedEvent.new(0, &"package", Vector3(1, 0, 1), 0, Color.RED))
	_fold(ItemSpawnedEvent.new(1, &"knife", Vector3(2, 0, 2)))
	assert_int(_model.items[0].station).is_equal(0)
	assert_int(_model.items[1].station).is_equal(-1)
	_fold(ItemPickedUpEvent.new(OWN, 0))
	assert_int(_model.items[0].holder).is_equal(OWN)
	_fold(ItemPlacedEvent.new(0, Vector3(8, 0, 8), &"put_down"))
	assert_int(_model.items[0].holder).is_equal(ClientModel.NO_HOLDER)
	assert_vector(_model.items[0].position).is_equal(Vector3(8, 0, 8))
	_fold(PackageDeliveredEvent.new(0, 0))
	assert_bool(_model.items[0].delivered).is_true()
	assert_bool(_model.stations[0].done).is_true()
	_fold(TaskProgressEvent.new(1, 3))
	assert_int(_model.tasks_done).is_equal(1)
	assert_int(_model.tasks_total).is_equal(3)
	_fold(DiedEvent.new(1, Vector3(4, 0, 4)))
	assert_bool(_model.is_alive(1)).is_false()
	assert_bool(_model.is_alive(OWN)).is_true()
	_fold(MatchEndedEvent.new(&"crew"))
	assert_str(String(_model.winner)).is_equal("crew")


func test_a_zones_progress_follows_its_zone_progress_and_done_comes_only_from_it() -> void:
	_to_round()
	_fold(StationPlacedEvent.new(3, &"zone", Color.YELLOW, Vector3(0, 0, 20)))
	var zone := _model.stations[3]
	assert_int(zone.ticks).is_equal(0)
	assert_int(zone.needed).is_equal(0)
	assert_bool(zone.counting).is_false()
	assert_int(zone.progress_tick).is_equal(-1)
	assert_bool(zone.done).is_false()
	_fold(ZoneProgressEvent.new(3, 1, 20, true, 100))
	assert_int(zone.ticks).is_equal(1)
	assert_int(zone.needed).is_equal(20)
	assert_bool(zone.counting).is_true()
	assert_int(zone.progress_tick).is_equal(100)
	assert_bool(zone.done).is_false()
	_fold(ZoneProgressEvent.new(3, 12, 20, false, 111))
	assert_int(zone.ticks).is_equal(12)
	assert_bool(zone.counting).is_false()
	assert_int(zone.progress_tick).is_equal(111)
	assert_bool(zone.done).is_false()
	# Another zone's event and one of a station the model does not know change nothing here.
	_fold(ZoneProgressEvent.new(9, 20, 20, false, 112))
	assert_int(zone.ticks).is_equal(12)
	assert_bool(_model.stations.has(9)).is_false()
	_fold(ZoneProgressEvent.new(3, 20, 20, false, 130))
	assert_int(zone.ticks).is_equal(20)
	assert_bool(zone.counting).is_false()
	assert_bool(zone.done).is_true()


func test_every_players_hand_and_belt_follow_pickups_swaps_and_drops() -> void:
	# The own player's slots come only from the events: its avatar is never sent to it (E29).
	_to_round()
	_fold(ItemSpawnedEvent.new(1, &"knife", Vector3(1, 0, 0)))
	_fold(ItemSpawnedEvent.new(2, &"package", Vector3(2, 0, 0), 7, Color.BLUE))
	_fold(ItemSpawnedEvent.new(3, &"knife", Vector3(3, 0, 0)))
	assert_int(_model.hand_item(OWN)).is_equal(-1)
	assert_int(_model.belt_item(OWN)).is_equal(-1)
	_fold(ItemPickedUpEvent.new(OWN, 1))
	assert_int(_model.hand_item(OWN)).is_equal(1)
	# The knife goes to the empty belt as the package comes into the hand.
	_fold(ItemPickedUpEvent.new(OWN, 2, 1))
	assert_int(_model.hand_item(OWN)).is_equal(2)
	assert_int(_model.belt_item(OWN)).is_equal(1)
	assert_int(_model.items[1].holder).is_equal(OWN)
	assert_bool(_model.items[1].belted).is_true()
	_fold(ItemPlacedEvent.new(2, Vector3(5, 0, 5), &"put_down"))
	assert_int(_model.hand_item(OWN)).is_equal(-1)
	assert_int(_model.belt_item(OWN)).is_equal(1)
	_fold(SwappedEvent.new(OWN))
	assert_int(_model.hand_item(OWN)).is_equal(1)
	assert_int(_model.belt_item(OWN)).is_equal(-1)
	# Another player's slots fold the same way; a full belt sends the hand item to rest (ItemPlaced).
	_fold(ItemPickedUpEvent.new(1, 3))
	_fold(SwappedEvent.new(1))
	assert_int(_model.hand_item(1)).is_equal(-1)
	assert_int(_model.belt_item(1)).is_equal(3)
	_fold(ItemPickedUpEvent.new(1, 2))
	assert_int(_model.hand_item(1)).is_equal(2)
	assert_int(_model.belt_item(1)).is_equal(3)
	assert_int(_model.hand_item(OWN)).is_equal(1)
	# A death drops both: an ItemPlaced for each.
	_fold(ItemPlacedEvent.new(2, Vector3(6, 0, 6), &"death"))
	_fold(ItemPlacedEvent.new(3, Vector3(6, 0, 6), &"death"))
	assert_int(_model.hand_item(1)).is_equal(-1)
	assert_int(_model.belt_item(1)).is_equal(-1)
	assert_bool(_model.items[3].belted).is_false()


func test_an_item_thrown_leaves_the_hand_and_keeps_its_flight_until_it_rests() -> void:
	# §7.1.16: ItemThrown carries the launch, exactly as the host's flight holds it; the item is in
	# no hand and rests nowhere until its ItemPlaced (cause thrown).
	_to_round()
	_fold(ItemSpawnedEvent.new(2, &"package", Vector3(2, 0, 0), 7, Color.BLUE))
	_fold(ItemPickedUpEvent.new(OWN, 2))
	assert_bool(_model.items[2].rests()).is_false()
	var origin := Vector3(1.25, 1.6, -3.5)
	var velocity := Vector3(0.1, 4.999999, -8.660254)
	var gravity := Vector3(0, -9.8, 0)
	_fold(ItemThrownEvent.new(2, OWN, origin, velocity, gravity, 77))
	var item: ClientModel.Item = _model.items[2]
	assert_int(_model.hand_item(OWN)).is_equal(-1)
	assert_int(item.holder).is_equal(ClientModel.NO_HOLDER)
	assert_bool(item.belted).is_false()
	assert_bool(item.flying).is_true()
	assert_bool(item.rests()).is_false()
	assert_int(item.thrower).is_equal(OWN)
	assert_bool(item.flight_origin == origin).is_true()
	assert_bool(item.flight_velocity == velocity).is_true()
	assert_bool(item.flight_gravity == gravity).is_true()
	assert_int(item.flight_tick).is_equal(77)
	assert_bool(item.position == origin).is_true()
	_fold(ItemPlacedEvent.new(2, Vector3(6, 0, -9), Items.THROWN))
	assert_bool(item.flying).is_false()
	assert_bool(item.rests()).is_true()
	assert_bool(item.position == Vector3(6, 0, -9)).is_true()
	# A belted item thrown after a swap leaves the belt flag behind it.
	_fold(ItemPickedUpEvent.new(OWN, 7))
	_fold(ItemPickedUpEvent.new(OWN, 2, 7))
	_fold(SwappedEvent.new(OWN))
	_fold(ItemThrownEvent.new(7, OWN, origin, velocity, gravity, 90))
	assert_int(_model.hand_item(OWN)).is_equal(-1)
	assert_int(_model.belt_item(OWN)).is_equal(2)
	assert_bool(_model.items[7].belted).is_false()


func test_a_thrown_package_delivered_or_another_players_throw_or_an_unknown_item() -> void:
	_to_round()
	_fold(ItemSpawnedEvent.new(2, &"package", Vector3(2, 0, 0), 7, Color.BLUE))
	# Another player's throw empties that player's hand, never the own one.
	_fold(ItemPickedUpEvent.new(1, 2))
	_fold(ItemPickedUpEvent.new(OWN, 7))
	_fold(ItemThrownEvent.new(2, 1, Vector3.ONE, Vector3.FORWARD, Vector3.DOWN, 50))
	assert_int(_model.hand_item(1)).is_equal(-1)
	assert_int(_model.hand_item(OWN)).is_equal(7)
	assert_int(_model.items[2].thrower).is_equal(1)
	# A package thrown into its circle rests there (ItemPlaced), then is delivered.
	_fold(ItemPlacedEvent.new(2, Vector3(0, 0, 1), Items.THROWN))
	_fold(PackageDeliveredEvent.new(2, 7))
	assert_bool(_model.items[2].flying).is_false()
	assert_bool(_model.items[2].delivered).is_true()
	# PackageDelivered alone ends a flight too.
	_fold(ItemSpawnedEvent.new(3, &"package", Vector3(3, 0, 0), 7, Color.BLUE))
	_fold(ItemPickedUpEvent.new(1, 3))
	_fold(ItemThrownEvent.new(3, 1, Vector3.ONE, Vector3.FORWARD, Vector3.DOWN, 60))
	_fold(PackageDeliveredEvent.new(3, 7))
	assert_bool(_model.items[3].flying).is_false()
	# An item the client never heard of is ignored.
	_fold(ItemThrownEvent.new(40, OWN, Vector3.ONE, Vector3.FORWARD, Vector3.DOWN, 61))
	assert_bool(_model.items.has(40)).is_false()
	assert_int(_model.items.size()).is_equal(3)
	# A new match forgets the flight with the items.
	_fold(ItemThrownEvent.new(2, OWN, Vector3.ONE, Vector3.FORWARD, Vector3.DOWN, 62))
	_fold(LoadMatchEvent.new(2, "res://levels/a.tscn", {} as Dictionary[StringName, int]))
	_assert_no_match_facts()


func test_task_state_gives_each_tasks_row_for_the_task_screen() -> void:
	_to_round()
	assert_int(_model.tasks.size()).is_equal(1)
	_fold(TaskStateEvent.new(2, &"delivery", 1, 2))
	_fold(TaskStateEvent.new(1, &"delivery", 1, 3))
	assert_int(_model.tasks.size()).is_equal(2)
	var task: ClientModel.Task = _model.tasks[1]
	assert_str(String(task.type)).is_equal("delivery")
	assert_int(task.done).is_equal(1)
	assert_int(task.total).is_equal(3)
	assert_int(_model.tasks[2].total).is_equal(2)


func test_its_own_status_role_and_correction() -> void:
	_fold(SelfStatusEvent.new(OWN, 100000, 80000, true))
	assert_int(_model.health).is_equal(100000)
	assert_int(_model.stamina).is_equal(80000)
	assert_bool(_model.sprint_available).is_true()
	_fold(DamagedEvent.new(OWN, 25000, 75000))
	assert_int(_model.health).is_equal(75000)
	_fold(RoleAssignedEvent.new(OWN, &"dissident"))
	_fold(TeammatesEvent.new(&"dissident", PackedInt32Array([OWN, 3])))
	assert_str(String(_model.role)).is_equal("dissident")
	assert_array(_model.teammates[&"dissident"]).contains_exactly([OWN, 3])
	_fold(CorrectionEvent.new(OWN, 9, Vector3.ONE, Vector3.ZERO))
	assert_int(_model.epoch).is_equal(9)


func test_a_newer_snapshot_replaces_the_avatars_and_an_older_one_does_not() -> void:
	_model.fold_snapshot({"tick": 5, "avatars": {1: {"position": Vector3.ONE}}})
	_model.fold_snapshot({"tick": 4, "avatars": {}})
	assert_int(_model.snapshot_tick).is_equal(5)
	assert_array(_model.avatars.keys()).contains_exactly([1])
	_model.fold_snapshot({"tick": 6, "avatars": {}})
	assert_bool(_model.avatars.is_empty()).is_true()


func test_load_match_clears_the_match_and_keeps_the_roster() -> void:
	_to_round()
	var settings: Dictionary[StringName, int] = {&"knives": 1}
	_fold(LoadMatchEvent.new(4, "res://levels/c.tscn", settings))
	_assert_no_match_facts()
	assert_int(_model.match_id).is_equal(4)
	assert_str(_model.map).is_equal("res://levels/c.tscn")
	assert_int(_model.settings[&"knives"]).is_equal(1)
	assert_array(_model.roster.keys()).contains_exactly([1, OWN])


func test_entering_the_lobby_clears_the_match() -> void:
	_to_round()
	_fold(PhaseChangedEvent.new(&"end", -1))
	assert_int(_model.items.size()).is_equal(1)
	_fold(PhaseChangedEvent.new(&"lobby", -1))
	_assert_no_match_facts()
	assert_array(_model.roster.keys()).contains_exactly([1, OWN])
	assert_int(_model.settings[&"knives"]).is_equal(2)


func test_a_round_snapshot_that_arrives_after_end_to_lobby_is_not_kept() -> void:
	# #251: snapshots travel on the unreliable lane, events on the reliable one. The round's
	# snapshot of tick 49, sent before the PhaseChanged of tick 50, arrives after it: it is newer
	# than every snapshot held (41), so only the host tick estimated at the change rejects it.
	var host_tick := [50]
	_model.host_tick_now = func() -> int: return host_tick[0]
	_to_round()
	_fold(PhaseChangedEvent.new(&"end", -1))
	_fold(PhaseChangedEvent.new(&"lobby", -1))
	_model.fold_snapshot({"tick": 49, "avatars": {1: {"position": Vector3.ONE}}})
	_model.fold_snapshot({"tick": 50, "avatars": {1: {"position": Vector3.ONE}}})
	assert_int(_model.snapshot_tick).is_equal(-1)
	assert_bool(_model.avatars.is_empty()).is_true()
	# The lobby's own snapshots fold.
	_model.fold_snapshot({"tick": 51, "avatars": {1: {"position": Vector3.ZERO}}})
	assert_int(_model.snapshot_tick).is_equal(51)
	assert_vector(_model.avatars[1]["position"]).is_equal(Vector3.ZERO)


func test_a_snapshot_that_arrives_after_load_match_is_not_kept_and_a_later_match_folds() -> void:
	var host_tick := [50]
	_model.host_tick_now = func() -> int: return host_tick[0]
	_to_round()
	_fold(PhaseChangedEvent.new(&"end", -1))
	_fold(PhaseChangedEvent.new(&"lobby", -1))
	_model.fold_snapshot({"tick": 60, "avatars": {1: {"position": Vector3.ZERO}}})
	# The next match: the host's tick runs on, so its snapshots stay above the lobby's floor.
	host_tick[0] = 300
	var settings: Dictionary[StringName, int] = {&"knives": 1}
	_fold(LoadMatchEvent.new(2, "res://levels/c.tscn", settings))
	_model.fold_snapshot({"tick": 299, "avatars": {1: {"position": Vector3.ZERO}}})
	assert_int(_model.snapshot_tick).is_equal(-1)
	assert_bool(_model.avatars.is_empty()).is_true()
	_model.fold_snapshot({"tick": 301, "avatars": {1: {"position": Vector3.ONE}}})
	assert_int(_model.snapshot_tick).is_equal(301)
	assert_vector(_model.avatars[1]["position"]).is_equal(Vector3.ONE)


func test_without_a_host_tick_the_floor_is_the_newest_snapshot_held() -> void:
	# A bot draws nothing and has no estimate: a snapshot no newer than one of the match it forgot
	# is still not kept.
	_to_round()
	_model.fold_snapshot({"tick": 45, "avatars": {1: {"position": Vector3.ONE}}})
	_fold(PhaseChangedEvent.new(&"end", -1))
	_fold(PhaseChangedEvent.new(&"lobby", -1))
	_model.fold_snapshot({"tick": 44, "avatars": {1: {"position": Vector3.ONE}}})
	_model.fold_snapshot({"tick": 45, "avatars": {1: {"position": Vector3.ONE}}})
	assert_int(_model.snapshot_tick).is_equal(-1)
	_model.fold_snapshot({"tick": 46, "avatars": {}})
	assert_int(_model.snapshot_tick).is_equal(46)


func test_a_cancelled_countdown_back_to_the_lobby_clears_nothing() -> void:
	_fold(PhaseChangedEvent.new(&"countdown", 100))
	_fold(DiedEvent.new(1, Vector3.ZERO))
	_fold(PhaseChangedEvent.new(&"lobby", -1))
	# Both play in the lobby: no match's facts to clear (a Died here is only a probe).
	assert_bool(_model.is_alive(1)).is_false()


func test_life_folds_from_the_public_events() -> void:
	# E25: KnockedDown makes a player downed, Died dead with its body; a leave removes the body
	# (E26); every other player is living.
	_to_round()
	_fold(KnockedDownEvent.new(OWN, Vector3(6, 0, 6)))
	assert_int(_model.life_of(OWN)).is_equal(ClientModel.Life.DOWNED)
	assert_bool(_model.is_alive(OWN)).is_false()
	assert_bool(_model.bodies.has(OWN)).is_false()
	_fold(DiedEvent.new(OWN, Vector3(6, 0, 6)))
	assert_int(_model.life_of(OWN)).is_equal(ClientModel.Life.DEAD)
	assert_vector(_model.bodies[OWN]).is_equal(Vector3(6, 0, 6))
	assert_int(_model.life_of(1)).is_equal(ClientModel.Life.DEAD)
	assert_int(_model.life_of(9)).is_equal(ClientModel.Life.ALIVE)
	_fold(PlayerLeftEvent.new(1))
	assert_int(_model.life_of(1)).is_equal(ClientModel.Life.LEFT)
	assert_bool(_model.bodies.has(1)).is_false()
	assert_bool(_model.bodies.has(OWN)).is_true()


func test_a_respawn_makes_the_player_living_and_removes_its_body() -> void:
	# E25, E26: Respawned of a dead player (peer 1 died in _to_round) makes it living again and
	# removes its body; nobody else's life or body changes.
	_to_round()
	_fold(DiedEvent.new(OWN, Vector3(6, 0, 6)))
	_fold(RespawnedEvent.new(1, Vector3(14, 0, -5)))
	assert_int(_model.life_of(1)).is_equal(ClientModel.Life.ALIVE)
	assert_bool(_model.is_alive(1)).is_true()
	assert_bool(_model.bodies.has(1)).is_false()
	assert_int(_model.life_of(OWN)).is_equal(ClientModel.Life.DEAD)
	assert_vector(_model.bodies[OWN]).is_equal(Vector3(6, 0, 6))
	_fold(RespawnedEvent.new(OWN, Vector3(-14, 0, 5)))
	assert_int(_model.life_of(OWN)).is_equal(ClientModel.Life.ALIVE)
	assert_dict(_model.bodies).is_empty()
	assert_int(_model.lives.size()).is_equal(0)


func test_a_raise_is_folded_from_its_start_to_its_stop() -> void:
	# M4-4: RaiseStarted records who raises whom; RaiseStopped forgets it and the target stays
	# downed.
	_to_round()
	_fold(KnockedDownEvent.new(OWN, Vector3(6, 0, 6)))
	_fold(RaiseStartedEvent.new(5, OWN))
	assert_int(_model.raiser_of(OWN)).is_equal(5)
	assert_int(_model.raised_by(5)).is_equal(OWN)
	assert_int(_model.raiser_of(5)).is_equal(0)
	_fold(RaiseStoppedEvent.new(5, OWN))
	assert_int(_model.raiser_of(OWN)).is_equal(0)
	assert_int(_model.raised_by(5)).is_equal(0)
	assert_int(_model.life_of(OWN)).is_equal(ClientModel.Life.DOWNED)


func test_silencings_count_each_phase_change_and_each_time_the_own_life_leaves_living() -> void:
	# #241: VoiceSender compares the count between its steps, so a cycle folded between two of them
	# is not missed. Another player's life, a revive and a respawn count nothing.
	_to_round()
	var count := _model.silencings
	_fold(KnockedDownEvent.new(1, Vector3(6, 0, 6)))
	_fold(RaiseStartedEvent.new(5, OWN))
	assert_int(_model.silencings).is_equal(count)
	_fold(KnockedDownEvent.new(OWN, Vector3(6, 0, 6)))
	assert_int(_model.silencings).is_equal(count + 1)
	_fold(RevivedEvent.new(OWN))
	assert_int(_model.silencings).is_equal(count + 1)
	_fold(DiedEvent.new(OWN, Vector3(6, 0, 6)))
	_fold(RespawnedEvent.new(OWN, Vector3(-14, 0, 5)))
	assert_int(_model.silencings).is_equal(count + 2)
	_fold(PhaseChangedEvent.new(&"end", -1))
	_fold(PhaseChangedEvent.new(&"lobby", -1))
	assert_int(_model.silencings).is_equal(count + 4)


func test_a_revive_ends_the_raise_and_makes_the_player_living() -> void:
	_to_round()
	_fold(KnockedDownEvent.new(OWN, Vector3(6, 0, 6)))
	_fold(KnockedDownEvent.new(5, Vector3(1, 0, 1)))
	_fold(RaiseStartedEvent.new(1, OWN))
	_fold(RevivedEvent.new(OWN))
	assert_int(_model.life_of(OWN)).is_equal(ClientModel.Life.ALIVE)
	assert_bool(_model.is_alive(OWN)).is_true()
	assert_int(_model.raiser_of(OWN)).is_equal(0)
	assert_dict(_model.raises).is_empty()
	# Nobody else's life changes.
	assert_int(_model.life_of(5)).is_equal(ClientModel.Life.DOWNED)


func test_a_leave_or_a_new_match_forgets_the_raises() -> void:
	_to_round()
	_fold(RaiseStartedEvent.new(5, OWN))
	_fold(RaiseStartedEvent.new(OWN, 6))
	_fold(PlayerLeftEvent.new(5))
	assert_int(_model.raiser_of(OWN)).is_equal(0)
	assert_int(_model.raiser_of(6)).is_equal(OWN)
	var settings: Dictionary[StringName, int] = {&"knives": 1}
	_fold(LoadMatchEvent.new(4, "res://levels/c.tscn", settings))
	assert_dict(_model.raises).is_empty()


func test_the_invulnerable_flag_comes_from_the_newest_snapshot() -> void:
	_to_round()
	var shielded := {"position": Vector3.ONE, "downed": false, "invulnerable": true}
	var plain := {"position": Vector3.ZERO, "downed": false, "invulnerable": false}
	_model.fold_snapshot({"tick": 42, "avatars": {1: shielded, 9: plain}})
	assert_bool(_model.is_invulnerable(1)).is_true()
	assert_bool(_model.is_invulnerable(9)).is_false()
	# No avatar (the own player, the dead, a stranger): not invulnerable as far as it knows.
	assert_bool(_model.is_invulnerable(OWN)).is_false()
	_model.fold_snapshot({"tick": 43, "avatars": {1: plain}})
	assert_bool(_model.is_invulnerable(1)).is_false()


func test_a_new_match_makes_everyone_living_again() -> void:
	_to_round()
	_fold(KnockedDownEvent.new(OWN, Vector3(6, 0, 6)))
	var settings: Dictionary[StringName, int] = {&"knives": 1}
	_fold(LoadMatchEvent.new(4, "res://levels/c.tscn", settings))
	assert_int(_model.life_of(OWN)).is_equal(ClientModel.Life.ALIVE)
	assert_int(_model.life_of(1)).is_equal(ClientModel.Life.ALIVE)
	assert_int(_model.lives.size()).is_equal(0)


## Plays a match up to the round: loading, an item, a station, a body, a role, a snapshot.
func _to_round() -> void:
	var settings: Dictionary[StringName, int] = {&"knives": 2}
	_fold(LoadMatchEvent.new(1, "res://levels/a.tscn", settings))
	_fold(PhaseChangedEvent.new(&"loading", -1))
	_fold(PlayerLoadedEvent.new(OWN))
	_fold(RoleAssignedEvent.new(OWN, &"crew"))
	_fold(StationPlacedEvent.new(7, &"circle", Color.BLUE, Vector3.ZERO))
	_fold(ItemSpawnedEvent.new(7, &"knife", Vector3.ZERO))
	_fold(TaskStateEvent.new(1, &"delivery", 0, 2))
	_fold(TaskProgressEvent.new(0, 2))
	_fold(RoundStartedEvent.new(40))
	_fold(PhaseChangedEvent.new(&"round", 12040))
	_fold(DiedEvent.new(1, Vector3(3, 0, 3)))
	_model.fold_snapshot({"tick": 41, "avatars": {1: {"position": Vector3.ONE}}})
	assert_int(_model.items.size()).is_equal(1)
	assert_int(_model.stations.size()).is_equal(1)
	assert_bool(_model.is_alive(1)).is_false()


func _assert_no_match_facts() -> void:
	assert_int(_model.items.size()).is_equal(0)
	assert_int(_model.stations.size()).is_equal(0)
	assert_int(_model.bodies.size()).is_equal(0)
	assert_int(_model.loaded.size()).is_equal(0)
	assert_str(String(_model.role)).is_empty()
	assert_int(_model.teammates.size()).is_equal(0)
	assert_int(_model.tasks_total).is_equal(0)
	assert_int(_model.tasks.size()).is_equal(0)
	assert_int(_model.start_tick).is_equal(-1)
	assert_str(String(_model.winner)).is_empty()
	assert_int(_model.snapshot_tick).is_equal(-1)
	assert_bool(_model.avatars.is_empty()).is_true()


func _fold(event: MatchEvent) -> void:
	_model.fold(event.event_name(), event.to_dict())
