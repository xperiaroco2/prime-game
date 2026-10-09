extends GdUnitTestSuite
## The throw on the wire (ARCHITECTURE §4.3, §7.1.16; the throwing ADR, TE3 and TE6): a client
## that decodes ItemThrown and calls ItemFlight.point with its origin, velocity and gravity gets
## the very points FlightTicks sweeps on the host, bit for bit, on every tick of the flight, with n
## the host tick less ItemThrown's tick (#642's criterion, carried to #643). And the two rows.

const Samples := preload("res://tests/unit/net/messages/wire_samples.gd")
const P1 := 1
const P2 := 2
const HERE := Vector3(1, 0, 2)


func test_the_points_from_a_decoded_item_thrown_are_the_ones_flight_ticks_sweeps() -> void:
	var world := FixtureFlightWorld.new()
	var game := FixtureItemModes.in_round(FixtureThrowModes.basic(), [P1, P2], world)
	FixtureItemModes.stand(game, P2, Vector3(-20, 0, 20))
	FixtureFlightModes.holding(game, P1, HERE)
	FixtureThrowModes.throw(game, P1, Vector3(0.3, 0.7, -0.5))
	var item := FixtureFlightModes.flying(game)
	var seen := FixtureThrowModes.thrown_seen_by(game, P2)
	assert_array(seen).has_size(1)
	var schema := WireSchema.game(false)
	var message := WireMessage.new(&"ItemThrown", seen[0].to_dict())
	var decoded := schema.decode(schema.kind_of(&"ItemThrown"), schema.encode(message))
	assert_object(decoded).is_not_null()
	var origin: Vector3 = decoded.fields["origin"]
	var velocity: Vector3 = decoded.fields["velocity"]
	var gravity: Vector3 = decoded.fields["gravity"]
	var launch: int = decoded.fields["tick"]
	assert_bool(Samples.same(decoded.fields, seen[0].to_dict())).is_true()
	var before := world.sweeps.size()
	var flown := 0
	while item.is_in_flight():
		FixtureModes.run_ticks(game, 1)
		var n := game.ticked_through() - launch
		# The launch tick moves nothing: after tick L + k the flight has swept k segments.
		assert_int(world.sweeps.size() - before).is_equal(n)
		if n == 0:
			continue
		flown = n
		var sweep: Array = world.sweeps[before + n - 1]
		assert_vector(sweep[0] as Vector3).is_equal(
			ItemFlight.point(origin, velocity, gravity, n - 1)
		)
		assert_vector(sweep[1] as Vector3).is_equal(ItemFlight.point(origin, velocity, gravity, n))
		assert_int(game.ticked_through()).is_less(launch + 200)
	# A whole flight, up and down to the floor, not one tick of it.
	assert_int(flown).is_greater(20)
	assert_int(item.where).is_equal(ItemState.Where.GROUND)


func test_the_throw_row_is_a_reliable_intent_and_item_thrown_an_event() -> void:
	var schema := WireSchema.game(false)
	var throw_row := schema.row_named(&"Throw")
	assert_int(throw_row.kind).is_equal(15)
	assert_int(throw_row.direction).is_equal(NetKindTable.Direction.CLIENT_TO_HOST)
	assert_int(throw_row.lane).is_equal(NetKindTable.Lane.RELIABLE)
	assert_int(throw_row.cap).is_equal(16)
	assert_array(Array(throw_row.field_names())).is_equal(["facing"])
	var thrown := schema.row_named(&"ItemThrown")
	assert_int(thrown.kind).is_equal(67)
	assert_int(thrown.direction).is_equal(NetKindTable.Direction.HOST_TO_CLIENT)
	assert_int(thrown.lane).is_equal(NetKindTable.Lane.RELIABLE)
	assert_int(thrown.cap).is_equal(46)
	assert_int(thrown.max_size()).is_equal(46)
	assert_array(Array(thrown.field_names())).is_equal(
		["item", "peer", "origin", "velocity", "gravity", "tick"]
	)
