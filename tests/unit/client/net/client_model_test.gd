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
				{"peer": 1, "name": "Player1", "ready": true, "colour": 0},
				{"peer": OWN, "name": "Player2", "ready": false, "colour": 1},
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


## #214: the lobby's name comes with the Welcome and each SettingsChanged; "" is the default, built
## by the UI from host_name().
func test_the_lobby_name_follows_welcome_and_settings_changed() -> void:
	assert_str(_model.lobby_name).is_empty()
	assert_str(_model.host_name()).is_equal("Player1")
	var other := ClientModel.new(FixtureBaseMode.mode())
	assert_str(other.host_name()).is_empty()
	var welcome := WelcomeEvent.new(3, Vector3.ZERO, 1)
	welcome.lobby_name = "Den"
	other.fold(welcome.event_name(), welcome.to_dict())
	assert_str(other.lobby_name).is_equal("Den")
	# A roster without the host (it left) has no host name.
	assert_str(other.host_name()).is_empty()
	var no_sets: Dictionary[StringName, PackedStringArray] = {}
	var problems: Array[HostText] = []
	var renamed_event := SettingsChangedEvent.new(
		{}, "res://levels/a.tscn", 2, Demands.new(null), null, problems, no_sets, "Діма's den"
	)
	_fold(renamed_event)
	assert_str(_model.lobby_name).is_equal("Діма's den")
	_fold(SettingsChangedEvent.new({}, "res://levels/a.tscn", 2, Demands.new(null), null, problems))
	assert_str(_model.lobby_name).is_empty()


func test_the_roster_follows_joins_leaves_and_ready() -> void:
	_fold(PlayerJoinedEvent.new(3, "Player3", Vector3(0, 0, 9), 2))
	_fold(ReadyChangedEvent.new(3, true))
	assert_bool(_model.roster[3].ready).is_true()
	assert_vector(_model.spots[3]).is_equal(Vector3(0, 0, 9))
	_fold(PlayerLeftEvent.new(1))
	assert_array(_model.roster.keys()).contains_exactly([OWN, 3])


## #551: every body colour is public; the Welcome, a join and a profile change carry it.
func test_the_colours_follow_welcome_joins_and_profile_changes() -> void:
	assert_int(_model.colour_of(1)).is_equal(0)
	assert_int(_model.colour_of(OWN)).is_equal(1)
	_fold(PlayerJoinedEvent.new(3, "Player3", Vector3(0, 0, 9), 2))
	assert_int(_model.colour_of(3)).is_equal(2)
	_fold(ProfileChangedEvent.new(1, "Діма", 7))
	assert_str(_model.roster[1].name).is_equal("Діма")
	assert_int(_model.colour_of(1)).is_equal(7)
	assert_bool(_model.roster[1].ready).is_true()
	assert_str(_model.host_name()).is_equal("Діма")
	# A peer not on the roster: colour 0, and a profile of it adds nobody.
	assert_int(_model.colour_of(9)).is_equal(0)
	_fold(ProfileChangedEvent.new(9, "Ghost", 4))
	assert_array(_model.roster.keys()).contains_exactly([1, OWN, 3])


func test_settings_changed_and_phase_changed() -> void:
	var numbers: Dictionary[StringName, int] = {&"knives": 4}
	var sets: Dictionary[StringName, PackedStringArray] = {
		&"banned_task_types": PackedStringArray(["delivery"])
	}
	var problems: Array[HostText] = [
		HostText.of(HostText.MARKERS, PackedStringArray(["knife"]), {&"need": 2, &"have": 0})
	]
	_fold(
		SettingsChangedEvent.new(
			numbers, "res://levels/b.tscn", 2, Demands.new(null), null, problems, sets
		)
	)
	assert_int(_model.settings[&"knives"]).is_equal(4)
	assert_array(_model.id_sets[&"banned_task_types"]).contains_exactly(["delivery"])
	assert_str(_model.map).is_equal("res://levels/b.tscn")
	assert_array(_model.shortfalls).is_equal(HostText.to_dicts(problems))
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
	assert_str(String(_model.ended_by)).is_empty()
	assert_int(_model.round_seconds).is_equal(-1)
	_fold(MatchEndedEvent.new(&"dissidents", &"time_up", {&"time": 600}))
	assert_str(String(_model.ended_by)).is_equal("time_up")
	assert_int(_model.round_seconds).is_equal(600)
	_fold(MatchEndedEvent.new(&"crew", &"no_crew_present", {}))
	assert_str(String(_model.ended_by)).is_equal("no_crew_present")
	assert_int(_model.round_seconds).is_equal(-1)


func test_a_drop_off_is_done_only_when_every_item_routed_to_it_is_delivered() -> void:
	# DE7 of the delivery-by-meaning ADR: two bottles routed to one table; the table dims after
	# the second, never on StationPlaced or ItemSpawned, and an item routed elsewhere is not counted.
	_to_round()
	_fold(StationPlacedEvent.new(0, &"drop_a", Color.WHITE, Vector3(9, 0, 9)))
	_fold(StationPlacedEvent.new(1, &"drop_b", Color.WHITE, Vector3(-9, 0, 9)))
	assert_bool(_model.stations[0].done).is_false()
	_fold(ItemSpawnedEvent.new(0, &"wine", Vector3(1, 0, 1), 0, Color.WHITE))
	_fold(ItemSpawnedEvent.new(1, &"wine", Vector3(2, 0, 1), 0, Color.WHITE))
	_fold(ItemSpawnedEvent.new(2, &"oil", Vector3(3, 0, 1), 1, Color.WHITE))
	assert_bool(_model.stations[0].done).is_false()
	assert_bool(_model.stations[1].done).is_false()
	_fold(PackageDeliveredEvent.new(0, 0))
	assert_bool(_model.items[0].delivered).is_true()
	assert_bool(_model.stations[0].done).is_false()
	_fold(PackageDeliveredEvent.new(2, 1))
	assert_bool(_model.stations[1].done).is_true()
	assert_bool(_model.stations[0].done).is_false()
	_fold(PackageDeliveredEvent.new(1, 0))
	assert_bool(_model.stations[0].done).is_true()


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
	_fold(ItemPickedUpEvent.new(OWN, 2, 1, 1))
	assert_int(_model.hand_item(OWN)).is_equal(2)
	assert_int(_model.belt_item(OWN)).is_equal(1)
	assert_int(_model.items[1].holder).is_equal(OWN)
	assert_bool(_model.items[1].belted).is_true()
	_fold(ItemPlacedEvent.new(2, Vector3(5, 0, 5), &"put_down"))
	assert_int(_model.hand_item(OWN)).is_equal(-1)
	assert_int(_model.belt_item(OWN)).is_equal(1)
	_fold(SwappedEvent.new(OWN, 0))
	assert_int(_model.hand_item(OWN)).is_equal(1)
	assert_int(_model.belt_item(OWN)).is_equal(-1)
	# Another player's slots fold the same way; a full belt sends the hand item to rest (ItemPlaced).
	_fold(ItemPickedUpEvent.new(1, 3))
	_fold(SwappedEvent.new(1, 1))
	assert_int(_model.hand_item(1)).is_equal(-1)
	assert_int(_model.belt_item(1)).is_equal(3)
	_fold(ItemPickedUpEvent.new(1, 2, -1, 1))
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
	_fold(ItemPickedUpEvent.new(OWN, 2, 7, 1))
	_fold(SwappedEvent.new(OWN, 0))
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


func test_an_item_vanished_is_forgotten_and_its_id_may_name_a_new_one() -> void:
	# The cooking ADR, CE3: an item left lying vanishes; ItemVanished removes its view. Past the
	# wire's id limit the host may reuse its id for a new item, which arrives as ItemSpawned.
	_to_round()
	_fold(ItemSpawnedEvent.new(4, &"crumb", Vector3(4, 0, 0)))
	_fold(ItemSpawnedEvent.new(5, &"crumb", Vector3(5, 0, 0)))
	_fold(ItemVanishedEvent.new(4))
	assert_bool(_model.items.has(4)).is_false()
	assert_bool(_model.items.has(5)).is_true()
	# An item the client never heard of, or one already gone, changes nothing.
	_fold(ItemVanishedEvent.new(4))
	_fold(ItemVanishedEvent.new(40))
	assert_array(_model.items.keys()).is_equal([7, 5])
	_fold(ItemSpawnedEvent.new(4, &"knife", Vector3(0, 0, 4)))
	assert_str(String(_model.items[4].kind)).is_equal("knife")
	assert_vector(_model.items[4].position).is_equal(Vector3(0, 0, 4))
	assert_int(_model.items[4].holder).is_equal(ClientModel.NO_HOLDER)


func test_an_item_changed_takes_its_new_kind_where_it_is() -> void:
	# The cooking ADR, CE4: a patty on the grill turns fried, then burnt; it keeps its id, its place
	# and its holder.
	_to_round()
	_fold(ItemSpawnedEvent.new(4, &"patty", Vector3(4, 0, 0)))
	_fold(ItemSpawnedEvent.new(5, &"bun", Vector3(5, 0, 0)))
	_fold(ItemPickedUpEvent.new(OWN, 5))
	_fold(ItemChangedEvent.new(4, &"patty_fried"))
	_fold(ItemChangedEvent.new(5, &"bun_toasted"))
	assert_str(String(_model.items[4].kind)).is_equal("patty_fried")
	assert_vector(_model.items[4].position).is_equal(Vector3(4, 0, 0))
	assert_int(_model.items[4].holder).is_equal(ClientModel.NO_HOLDER)
	assert_str(String(_model.items[5].kind)).is_equal("bun_toasted")
	assert_int(_model.hand_item(OWN)).is_equal(5)
	# An item the client never heard of changes nothing and is not made up.
	_fold(ItemChangedEvent.new(40, &"patty_burnt"))
	assert_bool(_model.items.has(40)).is_false()


func test_a_hand_over_moves_the_item_from_the_givers_hand_to_the_receivers() -> void:
	# #1389: HandOver's ItemPickedUp names the receiver and an item another player carries; the
	# giver's hand empties with no event of its own, and the take remembers who handed it.
	_fold(ItemSpawnedEvent.new(4, &"mug", Vector3(5, 0, 5)))
	_fold(ItemPickedUpEvent.new(1, 4))
	assert_int(_model.items[4].handed_from).is_equal(ClientModel.NO_HOLDER)
	_fold(ItemPickedUpEvent.new(OWN, 4))
	assert_int(_model.hand_item(1)).is_equal(-1)
	assert_int(_model.hand_item(OWN)).is_equal(4)
	assert_int(_model.items[4].holder).is_equal(OWN)
	assert_int(_model.items[4].handed_from).is_equal(1)
	assert_bool(_model.items[4].rests()).is_false()
	# Put down and taken from the floor again, it was handed by nobody.
	_fold(ItemPlacedEvent.new(4, Vector3(1, 0, 1), &"put_down"))
	_fold(ItemPickedUpEvent.new(1, 4))
	assert_int(_model.items[4].handed_from).is_equal(ClientModel.NO_HOLDER)


func test_a_pick_up_straight_onto_the_belt_keeps_the_hand_item_held() -> void:
	# The cooking ADR, CE20, CE21: beside a two-handed hand item a one-handed take goes onto the
	# belt, ItemPickedUp's `belted` naming the item itself; a full belt's item was put down first.
	_to_round()
	_fold(ItemSpawnedEvent.new(1, &"package", Vector3(1, 0, 0), 7, Color.BLUE))
	_fold(ItemSpawnedEvent.new(2, &"knife", Vector3(2, 0, 0)))
	_fold(ItemSpawnedEvent.new(3, &"knife", Vector3(3, 0, 0)))
	_fold(ItemPickedUpEvent.new(OWN, 1))
	_fold(ItemPickedUpEvent.new(OWN, 2, 2, 1))
	assert_int(_model.hand_item(OWN)).is_equal(1)
	assert_int(_model.belt_item(OWN)).is_equal(2)
	assert_bool(_model.items[2].belted).is_true()
	assert_bool(_model.items[1].belted).is_false()
	_fold(ItemPlacedEvent.new(2, Vector3(0, 0, 0), &"put_down"))
	_fold(ItemPickedUpEvent.new(OWN, 3, 3, 1))
	assert_int(_model.hand_item(OWN)).is_equal(1)
	assert_int(_model.belt_item(OWN)).is_equal(3)
	assert_bool(_model.items[2].rests()).is_true()
	# Another player's take folds the same way.
	_fold(ItemPickedUpEvent.new(1, 2, 2, 1))
	assert_int(_model.hand_item(1)).is_equal(-1)
	assert_int(_model.belt_item(1)).is_equal(2)


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


func test_its_own_drunk_value_follows_self_status_and_a_new_match_forgets_it() -> void:
	# The bar's drunk value (#1390) for the sway and the drift (#1391): only the host's word.
	assert_int(_model.drunk).is_equal(0)
	_fold(SelfStatusEvent.new(OWN, 100000, 80000, true, -1, 89))
	assert_int(_model.drunk).is_equal(89)
	_fold(SelfStatusEvent.new(OWN, 100000, 80000, true, -1, 88))
	assert_int(_model.drunk).is_equal(88)
	var settings: Dictionary[StringName, int] = {&"knives": 1}
	_fold(LoadMatchEvent.new(4, "res://levels/c.tscn", settings))
	assert_int(_model.drunk).is_equal(0)


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
	_fold(MatchEndedEvent.new(&"crew", &"every_task_done", {&"time": 461}))
	var settings: Dictionary[StringName, int] = {&"knives": 1}
	_fold(LoadMatchEvent.new(4, "res://levels/c.tscn", settings))
	_assert_no_match_facts()
	assert_int(_model.match_id).is_equal(4)
	assert_str(_model.map).is_equal("res://levels/c.tscn")
	assert_int(_model.settings[&"knives"]).is_equal(1)
	assert_array(_model.roster.keys()).contains_exactly([1, OWN])


func test_entering_the_lobby_clears_the_match() -> void:
	_to_round()
	_fold(MatchEndedEvent.new(&"crew", &"every_task_done", {&"time": 461}))
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


func test_the_crouched_flag_comes_from_the_newest_snapshot() -> void:
	_to_round()
	var low := {"position": Vector3.ONE, "downed": false, "crouched": true}
	var standing := {"position": Vector3.ZERO, "downed": false, "crouched": false}
	_model.fold_snapshot({"tick": 42, "avatars": {1: low, 9: standing}})
	assert_bool(_model.is_crouched(1)).is_true()
	assert_bool(_model.is_crouched(9)).is_false()
	# No avatar (the own player, the dead, a stranger): standing as far as it knows.
	assert_bool(_model.is_crouched(OWN)).is_false()
	_model.fold_snapshot({"tick": 43, "avatars": {1: standing}})
	assert_bool(_model.is_crouched(1)).is_false()


func test_a_new_match_makes_everyone_living_again() -> void:
	_to_round()
	_fold(KnockedDownEvent.new(OWN, Vector3(6, 0, 6)))
	var settings: Dictionary[StringName, int] = {&"knives": 1}
	_fold(LoadMatchEvent.new(4, "res://levels/c.tscn", settings))
	assert_int(_model.life_of(OWN)).is_equal(ClientModel.Life.ALIVE)
	assert_int(_model.life_of(1)).is_equal(ClientModel.Life.ALIVE)
	assert_int(_model.lives.size()).is_equal(0)


func test_a_switch_is_off_until_its_first_switch_changed_and_the_button_counts_presses() -> void:
	_to_round()
	_fold(StationPlacedEvent.new(3, &"generator", Color.WHITE, Vector3(0, 0, 20)))
	_fold(StationPlacedEvent.new(4, &"switch", Color.WHITE, Vector3(4, 0, 20)))
	var button := _model.stations[3]
	var switch := _model.stations[4]
	assert_bool(switch.on).is_false()
	assert_int(button.presses).is_equal(0)
	_fold(SwitchChangedEvent.new(4, true))
	assert_bool(switch.on).is_true()
	_fold(SwitchChangedEvent.new(4, false))
	assert_bool(switch.on).is_false()
	_fold(ButtonPressedEvent.new(3))
	_fold(ButtonPressedEvent.new(3))
	assert_int(button.presses).is_equal(2)
	assert_int(switch.presses).is_equal(0)
	# A station the model does not know changes nothing and is not added.
	_fold(SwitchChangedEvent.new(9, true))
	_fold(ButtonPressedEvent.new(9))
	assert_bool(_model.stations.has(9)).is_false()
	# Nobody is told who switched: a station keeps no peer.
	for property: Dictionary in switch.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var property_name: String = property["name"]
			for word: String in ["peer", "player", "actor", "by"]:
				(
					assert_bool(property_name.contains(word))
					. override_failure_message(property_name)
					. is_false()
				)


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
	assert_str(String(_model.ended_by)).is_empty()
	assert_int(_model.round_seconds).is_equal(-1)
	assert_int(_model.snapshot_tick).is_equal(-1)
	assert_bool(_model.avatars.is_empty()).is_true()


func _fold(event: MatchEvent) -> void:
	_model.fold(event.event_name(), event.to_dict())


func test_the_lift_folds_up_and_its_tick_and_the_picture_its_needed_part() -> void:
	# The car repair (#807): LiftChanged on the panel's station, PartNeeded on the picture's.
	_to_round()
	_fold(StationPlacedEvent.new(2, &"lift_panel", Color.WHITE, Vector3(3, 0, 20)))
	_fold(StationPlacedEvent.new(5, &"part_picture", Color.WHITE, Vector3(0, 0, 25)))
	var panel := _model.stations[2]
	var shown := _model.stations[5]
	assert_bool(panel.up).is_false()
	assert_int(panel.lift_tick).is_equal(-1)
	assert_int(panel.rise_tick).is_equal(-1)
	assert_str(String(shown.part)).is_empty()
	_fold(PartNeededEvent.new(5, &"spark_plug"))
	assert_str(String(shown.part)).is_equal("spark_plug")
	_fold(LiftChangedEvent.new(2, true, 40))
	assert_bool(panel.up).is_true()
	assert_int(panel.lift_tick).is_equal(40)
	assert_int(panel.rise_tick).is_equal(40)
	# The stop keeps the rise's start (#811: the view drops the car from the height it reached).
	_fold(LiftChangedEvent.new(2, false, 55))
	assert_bool(panel.up).is_false()
	assert_int(panel.lift_tick).is_equal(55)
	assert_int(panel.rise_tick).is_equal(40)
	_fold(LiftChangedEvent.new(2, true, 70))
	assert_int(panel.rise_tick).is_equal(70)
	_fold(LiftChangedEvent.new(2, false, 75))
	_fold(PartNeededEvent.new(5, &""))
	assert_str(String(shown.part)).is_empty()
	# A station the model does not know changes nothing and is not added.
	_fold(LiftChangedEvent.new(9, true, 60))
	_fold(PartNeededEvent.new(9, &"spark_plug"))
	assert_bool(_model.stations.has(9)).is_false()


func test_the_car_folds_its_fitter_and_a_fitted_part_leaves_the_hand() -> void:
	# The car repair (#808): FitChanged on the car's station, PartFitted locks the part there.
	_to_round()
	var car_at := Vector3(0, 0, 30)
	_fold(StationPlacedEvent.new(1, &"car", Color.WHITE, car_at))
	_fold(ItemSpawnedEvent.new(4, &"spark_plug", Vector3(0, 0, 40)))
	_fold(ItemPickedUpEvent.new(OWN, 4))
	var car := _model.stations[1]
	assert_int(car.fitter).is_equal(0)
	assert_int(car.fit_tick).is_equal(-1)
	assert_int(car.fitted).is_equal(0)
	_fold(FitChangedEvent.new(1, OWN, 40))
	assert_int(car.fitter).is_equal(OWN)
	assert_int(car.fit_tick).is_equal(40)
	_fold(FitChangedEvent.new(1, 0, 45))
	assert_int(car.fitter).is_equal(0)
	assert_int(car.fit_tick).is_equal(45)
	_fold(FitChangedEvent.new(1, OWN, 50))
	assert_int(_model.hand_item(OWN)).is_equal(4)
	_fold(PartFittedEvent.new(1, 4))
	assert_int(car.fitter).is_equal(0)
	assert_int(car.fitted).is_equal(1)
	assert_int(_model.hand_item(OWN)).is_equal(-1)
	var part: ClientModel.Item = _model.items[4]
	assert_bool(part.fitted).is_true()
	assert_int(part.holder).is_equal(ClientModel.NO_HOLDER)
	assert_vector(part.position).is_equal(car_at)
	# Locked at the car, it rests nowhere: no view draws it, no crosshair names it (RE12, #811).
	assert_bool(part.rests()).is_false()
	# A station the model does not know changes nothing and is not added.
	_fold(FitChangedEvent.new(9, OWN, 60))
	_fold(PartFittedEvent.new(9, 4))
	assert_bool(_model.stations.has(9)).is_false()


## GDD §6 (#1218): three places; an item keeps its place, `Swapped` names the place now in the
## hand, and the belt reads the two other places in place order (belt_item the lower).
func test_three_places_follow_the_places_of_pickups_and_swaps() -> void:
	_to_round()
	for id: int in [1, 2, 3]:
		_fold(ItemSpawnedEvent.new(id, &"knife", Vector3(id, 0, 0)))
	_fold(ItemPickedUpEvent.new(OWN, 1))
	_fold(ItemPickedUpEvent.new(OWN, 2, 1, 1))
	_fold(ItemPickedUpEvent.new(OWN, 3, 2, 2))
	assert_int(_model.selected_place(OWN)).is_equal(2)
	assert_int(_model.hand_item(OWN)).is_equal(3)
	assert_int(_model.belt_item(OWN)).is_equal(1)
	assert_int(_model.belt_item2(OWN)).is_equal(2)
	(
		assert_array([0, 1, 2].map(func(at: int) -> int: return _model.item_in_place(OWN, at)))
		. is_equal([1, 2, 3])
	)
	# Draw (Swapped) of place 0: the knife in place 0 comes into the hand, the others hang.
	_fold(SwappedEvent.new(OWN, 0))
	assert_int(_model.hand_item(OWN)).is_equal(1)
	assert_int(_model.belt_item(OWN)).is_equal(2)
	assert_int(_model.belt_item2(OWN)).is_equal(3)
	assert_int(_model.items[3].carry_place).is_equal(2)
	# An empty place is an empty hand: place 1's knife put down, then place 1 drawn.
	_fold(ItemPlacedEvent.new(2, Vector3(5, 0, 5), &"put_down"))
	_fold(SwappedEvent.new(OWN, 1))
	assert_int(_model.hand_item(OWN)).is_equal(-1)
	assert_int(_model.belt_item(OWN)).is_equal(1)
	assert_int(_model.belt_item2(OWN)).is_equal(3)
	# Another player's places fold apart from the own ones.
	_fold(ItemPickedUpEvent.new(1, 2, -1, 2))
	assert_int(_model.selected_place(1)).is_equal(2)
	assert_int(_model.hand_item(1)).is_equal(2)
	assert_int(_model.selected_place(OWN)).is_equal(1)
