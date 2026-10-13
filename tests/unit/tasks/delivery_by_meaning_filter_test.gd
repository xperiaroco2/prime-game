extends GdUnitTestSuite
## The host's per-peer filter over a dealt and delivered round of DeliveryByMeaning (#683's ADR §3,
## §7): nothing in it is secret, so a crew player and a dissident receive the same task events.
## The leak test (`bots`) checks only the greybox's Delivery, so this round is checked here.

const P1 := 1
const P2 := 2
const P3 := 3
const TASK_EVENTS: Array[StringName] = [
	&"StationPlaced", &"ItemSpawned", &"PackageDelivered", &"TaskState", &"TaskProgress"
]


func test_every_peer_receives_the_same_task_events() -> void:
	var mode := FixtureMeaningModes.basic(5)
	mode.settings.append(FixtureModes.setting(&"dissidents", 1, 0, 2))
	var deal := mode.find_transition(&"lobby", &"all_ready")
	deal.actions.insert(0, FixtureDealModes.deal_roles(mode.roles[1], mode.roles[0]))
	var game := FixtureMeaningModes.in_round(mode, [P1, P2, P3])
	var task := FixtureMeaningModes.task_of(game)
	var role_ids := {}
	for peer: int in [P1, P2, P3]:
		role_ids[game.state.player(peer).role] = true
	# A crew player and a dissident are in the round (the fixture deals both).
	assert_int(role_ids.size()).is_greater(1)
	for i in 2:
		FixtureDeliveryModes.carry_to(
			game,
			P2 if i == 0 else P3,
			FixtureMeaningModes.item_of(game, i),
			FixtureMeaningModes.station_of(game, i).position
		)
	var seen: Array = []
	for peer: int in [P1, P2, P3]:
		var own: Array[Dictionary] = []
		for event: MatchEvent in game.view_of(peer).events:
			if event.event_name() != &"TaskState":
				assert_bool(event.to_dict().has("task")).is_false()
			if TASK_EVENTS.has(event.event_name()):
				own.append({"name": event.event_name(), "fields": event.to_dict()})
		seen.append(own)
	# 4 places, 5 items, 2 deliveries, TaskState and TaskProgress at the deal and each delivery.
	assert_int((seen[0] as Array).size()).is_equal(4 + 5 + 2 + 2 + 4)
	assert_array(seen[1] as Array).is_equal(seen[0] as Array)
	assert_array(seen[2] as Array).is_equal(seen[0] as Array)
	for emitted: EmittedEvent in game.emitted():
		if TASK_EVENTS.has(emitted.event.event_name()):
			assert_array(Array(emitted.recipients)).is_equal([P1, P2, P3])
	for script: Script in task.type.emits():
		assert_int(script.get_script_constant_map()["AUDIENCE_KIND"]).is_equal(
			Audience.Kind.EVERYONE
		)
