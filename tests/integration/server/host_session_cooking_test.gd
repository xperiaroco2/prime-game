extends GdUnitTestSuite
## Cooking over the real wire, without bots (#778, cooking C9; the cooking ADR's §7 "The wire,
## without bots", CE22; ARCHITECTURE §4.6, §9.5.20): ClientSessions against a HostSession over a
## LoopbackHub, the codec in between, on FixtureWireCooking's mode, which deals its Cooking on
## its one map KITCHEN. Two clients take from the boxes (one with a package in the hands, so the
## bun goes onto the belt, and a second take puts the belt's bun down at its feet), load the grill
## and take the patty off fried, plate a burger with a wrong bun, take it and serve it at the order
## board (wrong: thrown away), then plate the right one and serve it (right: done; the cooking ADR's
## amendment of 2026-10-15, #1101); what lay is left until it vanishes. No IngredientPlaced carries
## a word of right or wrong. What each client decoded equals its Match.view_of. And CE17's flood
## guard and CE3's cap against one peer's burst of
## Interact(item), which ChaosRun's idle-baseline comparison cannot hold (§4.6.5.3).

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

## The events §7 names, each of which every client decodes at least once.
const EVENTS: Array[StringName] = [
	&"OrderPosted",
	&"HerbsDealt",
	&"ItemSpawned",
	&"ItemPickedUp",
	&"ItemPlaced",
	&"GrillLoaded",
	&"ItemChanged",
	&"IngredientPlaced",
	&"BurgerPlated",
	&"BurgerServed",
	&"ItemVanished",
	&"TaskState",
	&"TaskProgress",
]
## The burst: one Interact(item) a frame for this long, past the cap at CE17's 4 takes a second.
const BURST_SECONDS := 5.0
## More than one tick of CE17's cooldown between two takes by one player.
const AFTER_TAKE_S := 0.4

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_a_burger_and_its_leftovers_reach_every_client_as_its_view() -> void:
	var second := _in_round()
	var game := _h.session.game
	var task_state := FixtureCookingModes.state_of(game)
	var order := task_state.orders[0]
	var place := order.station
	var second_peer := _h.peer_of(second)
	# The package in the hands: the bun goes onto the belt, a second onto the belt's second place;
	# a third, with both belt places full, puts the first down at the feet.
	second.send_intent(Intents.PICK_UP, {"item": _package(game).id})
	_h.pump_seconds(AFTER_TAKE_S)
	_take(second, game, order.bun.id)
	var first_bun := FixtureCookingModes.belted(game, second_peer)
	assert_object(first_bun).is_not_null()
	_take(second, game, order.bun.id)
	assert_int(first_bun.where).is_not_equal(ItemState.Where.GROUND)
	_take(second, game, order.bun.id)
	assert_str(FixtureCookingModes.held(game, second_peer).kind.id).is_equal("package")
	assert_int(first_bun.where).is_equal(ItemState.Where.GROUND)
	# A two-handed hand item at the place: refused, to the sender alone.
	_use(second, place)
	# A burger with the other bun (wrong), taken and served: thrown away, nothing done.
	_plate(game, _other_bun(game, order.bun), order)
	var wrong := FixtureCookingModes.held(game, _h.peer_of(_h.own))
	assert_str(wrong.kind.id).is_equal("burger")
	_use(_h.own, task_state.order_board)
	assert_bool(game.state.items.has(wrong.id)).is_false()
	assert_bool(order.done).is_false()
	# Made again whole, right: served, done.
	_plate(game, order.bun, order)
	_use(_h.own, task_state.order_board)
	assert_bool(order.done).is_true()
	# What lies loose (the bun at the feet) vanishes.
	_h.pump_seconds(FixtureWireCooking.VANISH_SECONDS + 0.5)
	assert_bool(game.state.items.has(first_bun.id)).is_false()
	for client: ClientSession in _h.clients:
		for event_name: StringName in EVENTS:
			(
				assert_array(client.view.events_named(event_name))
				. override_failure_message("no %s decoded" % event_name)
				. is_not_empty()
			)
		assert_array(_served(client)).is_equal([false, true])
		for placed: WireMessage in client.view.events_named(&"IngredientPlaced"):
			assert_array(placed.fields.keys()).is_equal(["item", "station"])
		assert_bool(_belted_seen(client)).is_true()
		assert_array(_h.mismatches(client)).is_empty()
	var refused := second.view.events_named(&"Rejected")
	assert_int(refused.size()).is_equal(1)
	assert_str(str(refused[0].fields["reason"])).is_equal("two_handed")
	assert_array(_h.own.view.events_named(&"Rejected")).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_burst_of_takes_gets_one_per_cooldown_and_never_passes_the_cap() -> void:
	var second := _in_round()
	var game := _h.session.game
	var bun := FixtureCookingModes.state_of(game).orders[0].bun
	var box := FixtureCookingModes.box_giving(game, bun.id)
	var events_before := second.view.events.size()
	var calls_before := _h.calls.size()
	var first_tick := game.ticked_through()
	var most := 0
	for _i in ceili(BURST_SECONDS * Harness.SECOND / Harness.FRAME_USEC):
		second.send_intent(Intents.INTERACT, {"station": -1, "item": box.id})
		_h.pump()
		most = maxi(most, _count_of(game, bun.id))
	_h.pump_seconds(0.5)
	var ticks := game.ticked_through() - first_tick
	var arrived := 0
	for entry: String in _h.calls.slice(calls_before):
		if entry.split(" ")[1] == String(Intents.INTERACT):
			arrived += 1
	var spawned := 0
	var too_soon := 0
	for event: WireMessage in second.view.events.slice(events_before):
		if event.name == &"ItemSpawned":
			spawned += 1
		elif event.name == &"Rejected":
			assert_str(str(event.fields["reason"])).is_equal("too_soon")
			too_soon += 1
	# Every Interact that reached the match is a take or too_soon; at most one take per 5 ticks.
	assert_int(spawned + too_soon).is_equal(arrived)
	assert_int(spawned).is_less_equal(floori(float(ticks) / FixtureWireCooking.TAKE_TICKS) + 1)
	assert_int(too_soon).is_greater(0)
	# Past the cap: the oldest loose bun vanished before each take (the burst is shorter than
	# VANISH_SECONDS, so no timed vanish), and never more than CAP lay though the burst would lay
	# about 2 * CAP (seen failing with the kind's max_items planted out).
	assert_int(spawned).is_greater(FixtureWireCooking.CAP)
	assert_int(most).is_equal(FixtureWireCooking.CAP)
	assert_array(second.view.events_named(&"ItemVanished")).is_not_empty()
	for client: ClientSession in _h.clients:
		assert_array(_h.mismatches(client)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


## The harness on FixtureWireCooking with a second client, both in the round: returns the second.
func _in_round() -> ClientSession:
	_h = Harness.new(FixtureWireCooking.mode(), true, null, FixtureWireCooking.layouts())
	assert_array(_h.session.errors).is_empty()
	assert_bool(_h.started).is_true()
	var second := _h.join()
	assert_bool(_h.welcome_all()).is_true()
	_h.pump_seconds(0.5)
	_h.ready_all()
	assert_bool(_h.run_until_phase(&"round", 800)).is_true()
	_h.pump_seconds(0.5)
	assert_object(FixtureCookingModes.task_of(_h.session.game)).is_not_null()
	return second


## `client` takes from the box that gives `kind_id` (Interact naming it), then waits out CE17.
func _take(client: ClientSession, game: Match, kind_id: StringName) -> void:
	var box := FixtureCookingModes.box_giving(game, kind_id)
	client.send_intent(Intents.INTERACT, {"station": -1, "item": box.id})
	_h.pump_seconds(AFTER_TAKE_S)


## The own client fills the order's place with `bun`, the order's patty (on the grill, fried, off)
## and its herb (from its bed), then takes the plated burger.
func _plate(game: Match, bun: ItemKind, order: Cooking.Order) -> void:
	var task_state := FixtureCookingModes.state_of(game)
	_take(_h.own, game, bun.id)
	_use(_h.own, order.station)
	_take(_h.own, game, order.raw_patty.id)
	_use(_h.own, task_state.grill)
	_h.pump_seconds(FixtureCookingModes.FRY_SECONDS + 0.2)
	_use(_h.own, task_state.grill)
	_use(_h.own, order.station)
	_use(_h.own, FixtureCookingModes.bed_of(game, order.herb.id))
	_use(_h.own, order.station)
	_use(_h.own, order.station)


## `client` uses `station` (Interact naming it).
func _use(client: ClientSession, station: int) -> void:
	client.send_intent(Intents.INTERACT, {"station": station, "item": -1})
	_h.pump_seconds(AFTER_TAKE_S)


static func _package(game: Match) -> ItemState:
	for item: ItemState in game.state.items.values():
		if item.kind.id == &"package":
			return item
	return null


static func _other_bun(game: Match, bun: ItemKind) -> ItemKind:
	for kind: ItemKind in FixtureCookingModes.type_of(game.mode).buns:
		if kind != bun:
			return kind
	return null


static func _count_of(game: Match, kind_id: StringName) -> int:
	var count := 0
	for item: ItemState in game.state.items.values():
		if item.kind.id == kind_id:
			count += 1
	return count


## The `right` of each BurgerServed `client` decoded, in order.
static func _served(client: ClientSession) -> Array[bool]:
	var found: Array[bool] = []
	for event: WireMessage in client.view.events_named(&"BurgerServed"):
		found.append(event.fields["right"] as bool)
	return found


## Whether `client` decoded an ItemPickedUp straight onto a belt.
static func _belted_seen(client: ClientSession) -> bool:
	for event: WireMessage in client.view.events_named(&"ItemPickedUp"):
		if event.fields["belted"] as bool:
			return true
	return false
