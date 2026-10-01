extends GdUnitTestSuite
## ClientModel (ARCHITECTURE §4.6): what a client knows, folded from decoded events (here core/'s
## own events through to_dict(), which the codec reproduces exactly): the roster, settings, phase,
## items with every player's hand and belt (E29), stations, tasks (E30), bodies, each player's life
## (E25), avatars and its own SelfStatus; a match's
## facts cleared on LoadMatch and on entering the lobby, the roster and settings kept.

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
