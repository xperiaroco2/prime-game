extends GdUnitTestSuite
## The car repair over the real wire, without bots (#813, car repair R9; the car repair ADR's §7
## "The wire, without bots", RD13; ARCHITECTURE §4.6, §9.5.21): ClientSessions against a
## HostSession over a LoopbackHub, the codec in between, on FixtureWireCarRepair's mode, which
## deals its CarRepair on its one map GARAGE. The host's client holds the lift, a second client
## takes each needed part from its bin and fits it under the car (refused once while the car is
## down), a third stands in the footprint box, and the holder lets go: the two in the box die.
## What each client decoded equals its Match.view_of. And RD2's flood guard and the cap against
## one peer's burst of Interact at a bin, and the reliable-intents bucket (§4.5.6) against a burst
## of Interact at the panel and of StopRaise (§4.6.5.3).

const Harness := preload("res://tests/integration/server/host_session_harness.gd")

## The events §7 names, each of which every client decodes at least once.
const EVENTS: Array[StringName] = [
	&"StationPlaced",
	&"PartNeeded",
	&"LiftChanged",
	&"FitChanged",
	&"PartFitted",
	&"ItemSpawned",
	&"ItemPickedUp",
	&"TaskState",
	&"TaskProgress",
	&"Died",
]
## The burst at a bin: one Interact a frame for this long, past the cap at 4 takes a second.
const BURST_SECONDS := 5.0
## More than one tick of the bins' cooldown between two takes by one player.
const AFTER_TAKE_S := 0.4
## A burst past the reliable-intents bucket (PeerBudget.INTENTS) in one frame.
const BURST := 130

var _h: Harness


func after_test() -> void:
	if _h != null:
		_h.close()
		_h = null


func test_a_repair_and_a_drop_reach_every_client_as_its_view() -> void:
	_h = _in_round(FixtureWireCarRepair.SPOTS, 3)
	var fitter := _h.clients[1]
	var bystander := _h.clients[2]
	var game := _h.session.game
	var task_state := FixtureCarRepairModes.state_of(game)
	assert_int(task_state.needed.size()).is_equal(FixtureWireCarRepair.PARTS_NEEDED)
	# The first part from its bin; the car is down: the fit is refused, to the fitter alone.
	_take(fitter, game, task_state.next_part())
	_use(fitter, task_state.car)
	# The holder raises the car; each part is fitted once it is up.
	_use(_h.own, task_state.panel)
	_h.pump_seconds(FixtureCarRepairModes.RISE_SECONDS)
	for i in task_state.needed.size():
		if i > 0:
			_take(fitter, game, task_state.next_part())
		_use(fitter, task_state.car)
		_h.pump_seconds(FixtureCarRepairModes.FIT_SECONDS + 0.2)
		assert_int(task_state.fitted).is_equal(i + 1)
	assert_bool(task_state.is_done()).is_true()
	# The holder lets go: the fitter and the bystander lie in the box, the holder does not.
	_h.own.send_intent(Intents.STOP_RAISE)
	_h.pump_seconds(0.5)
	var died: Array[int] = []
	for event: WireMessage in _h.own.view.events_named(&"Died"):
		died.append(event.fields["peer"] as int)
	assert_array(died).is_equal([_h.peer_of(fitter), _h.peer_of(bystander)])
	for client: ClientSession in _h.clients:
		for event_name: StringName in EVENTS:
			(
				assert_array(client.view.events_named(event_name))
				. override_failure_message("no %s decoded" % event_name)
				. is_not_empty()
			)
		assert_array(_lifts(client)).is_equal([true, false])
		assert_array(_h.mismatches(client)).is_empty()
	var refused := fitter.view.events_named(&"Rejected")
	assert_int(refused.size()).is_equal(1)
	assert_str(str(refused[0].fields["reason"])).is_equal("unavailable")
	assert_array(_h.own.view.events_named(&"Rejected")).is_empty()
	assert_array(bystander.view.events_named(&"Rejected")).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_a_burst_of_takes_gets_one_per_cooldown_and_never_passes_the_cap() -> void:
	_h = _in_round(FixtureWireCarRepair.SPOTS, 2)
	var taker := _h.clients[1]
	var game := _h.session.game
	var part := FixtureCarRepairModes.state_of(game).next_part()
	var bin := FixtureWireCarRepair.bin_giving(game, part)
	var events_before := taker.view.events.size()
	var calls_before := _h.calls.size()
	var first_tick := game.ticked_through()
	var most := 0
	for _i in ceili(BURST_SECONDS * Harness.SECOND / Harness.FRAME_USEC):
		taker.send_intent(Intents.INTERACT, {"station": bin, "item": -1})
		_h.pump()
		most = maxi(most, _count_of(game, part))
	_h.pump_seconds(0.5)
	var ticks := game.ticked_through() - first_tick
	var arrived := _arrived(calls_before, Intents.INTERACT)
	var spawned := 0
	var too_soon := 0
	for event: WireMessage in taker.view.events.slice(events_before):
		if event.name == &"ItemSpawned":
			spawned += 1
		elif event.name == &"Rejected":
			assert_str(str(event.fields["reason"])).is_equal("too_soon")
			too_soon += 1
	# Every Interact that reached the match is a take or too_soon; at most one take per 5 ticks.
	assert_int(spawned + too_soon).is_equal(arrived)
	assert_int(spawned).is_less_equal(floori(float(ticks) / FixtureWireCarRepair.TAKE_TICKS) + 1)
	assert_int(too_soon).is_greater(0)
	# Past the cap the oldest loose part vanished before each take (a part never vanishes on its
	# own), and never more than CAP existed though the burst would make about twice as many.
	assert_int(spawned).is_greater(FixtureWireCarRepair.CAP)
	assert_int(most).is_equal(FixtureWireCarRepair.CAP)
	assert_array(taker.view.events_named(&"ItemVanished")).is_not_empty()
	for client: ClientSession in _h.clients:
		assert_array(_h.mismatches(client)).is_empty()
	assert_array(Array(game.diagnostics)).is_empty()


func test_bursts_at_the_panel_and_of_stop_raise_stop_at_the_intents_bucket() -> void:
	# The second client stands at the panel (the host's own client has no budget, §4.5.6).
	var spots: Array[Vector3] = [FixtureWireCarRepair.OUT_SPOT, FixtureWireCarRepair.PANEL_SPOT]
	_h = _in_round(spots, 2)
	var holder := _h.clients[1]
	var panel := FixtureCarRepairModes.state_of(_h.session.game).panel
	# One hold, and `busy` for every other Interact the bucket let through.
	var interacts := _burst(holder, Intents.INTERACT, {"station": panel, "item": -1})
	assert_array(_lifts(holder)).is_equal([true])
	assert_array(_reasons(holder)).is_equal(_times(&"busy", interacts - 1))
	# The bucket refilled: one stop, and `not_channeling` for every other StopRaise let through.
	var stops := _burst(holder, Intents.STOP_RAISE, {})
	assert_array(_lifts(holder)).is_equal([true, false])
	var reasons := _times(&"busy", interacts - 1)
	reasons.append_array(_times(&"not_channeling", stops - 1))
	assert_array(_reasons(holder)).is_equal(reasons)
	assert_array(_h.own.view.events_named(&"Rejected")).is_empty()
	assert_array(_h.own.view.events_named(&"Died")).is_empty()
	assert_bool(holder.is_ended()).is_false()
	assert_int(_h.session.malformed_disconnects).is_equal(0)
	for client: ClientSession in _h.clients:
		assert_array(_h.mismatches(client)).is_empty()
	assert_array(Array(_h.session.game.diagnostics)).is_empty()


## The harness on FixtureWireCarRepair, its players on `spots` in peer-id order, with `players`
## clients (the host's own among them), all in the round, the car repair dealt.
func _in_round(spots: Array[Vector3], players: int) -> Harness:
	var made := Harness.new(
		FixtureWireCarRepair.mode(), true, null, FixtureWireCarRepair.layouts(spots)
	)
	assert_array(made.session.errors).is_empty()
	assert_bool(made.started).is_true()
	for _i in players - 1:
		made.join()
	assert_bool(made.welcome_all()).is_true()
	made.pump_seconds(0.5)
	made.ready_all()
	assert_bool(made.run_until_phase(&"round", 800)).is_true()
	made.pump_seconds(0.5)
	assert_object(FixtureCarRepairModes.task_of(made.session.game)).is_not_null()
	for i in players:
		var at := made.session.game.state.player(made.peer_of(made.clients[i])).position
		assert_vector(at).is_equal(spots[i])
	return made


## `client` takes `part_id` from its bin, then waits out the bins' cooldown.
func _take(client: ClientSession, game: Match, part_id: StringName) -> void:
	_use(client, FixtureWireCarRepair.bin_giving(game, part_id))


## `client` uses `station` (Interact naming it).
func _use(client: ClientSession, station: int) -> void:
	client.send_intent(Intents.INTERACT, {"station": station, "item": -1})
	_h.pump_seconds(AFTER_TAKE_S)


## `client` sends BURST `intent`s in one frame once its intents bucket is full; returns how many
## reached the match. The rest are over budget: dropped, unanswered, nobody disconnected.
func _burst(client: ClientSession, intent: StringName, args: Dictionary) -> int:
	_h.pump_seconds(PeerBudget.INTENTS / PeerBudget.INTENTS_PER_SECOND)
	var over_before := _h.session.over_budget
	var calls_before := _h.calls.size()
	for _i in BURST:
		client.send_intent(intent, args)
	_h.pump_seconds(0.5)
	var arrived := _arrived(calls_before, intent)
	# At most the bucket (the claim twin sent before the first action takes one token, #429).
	assert_int(arrived).is_less_equal(int(PeerBudget.INTENTS))
	assert_int(arrived).is_greater_equal(int(PeerBudget.INTENTS) - 1)
	assert_int(_h.session.over_budget - over_before).is_equal(BURST - arrived)
	return arrived


## How many `intent` commands reached the match since the observer's call `calls_before`.
func _arrived(calls_before: int, intent: StringName) -> int:
	var arrived := 0
	for entry: String in _h.calls.slice(calls_before):
		if entry.split(" ")[1] == String(intent):
			arrived += 1
	return arrived


static func _count_of(game: Match, kind_id: StringName) -> int:
	var count := 0
	for item: ItemState in game.state.items.values():
		if item.kind.id == kind_id:
			count += 1
	return count


## The `up` of each LiftChanged `client` decoded, in order.
static func _lifts(client: ClientSession) -> Array[bool]:
	var found: Array[bool] = []
	for event: WireMessage in client.view.events_named(&"LiftChanged"):
		found.append(event.fields["up"] as bool)
	return found


## The reason of each Rejected `client` decoded, in order.
static func _reasons(client: ClientSession) -> Array[StringName]:
	var found: Array[StringName] = []
	for event: WireMessage in client.view.events_named(&"Rejected"):
		found.append(StringName(str(event.fields["reason"])))
	return found


static func _times(reason: StringName, count: int) -> Array[StringName]:
	var found: Array[StringName] = []
	for _i in count:
		found.append(reason)
	return found
