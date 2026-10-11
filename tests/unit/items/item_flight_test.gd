extends GdUnitTestSuite
## ItemFlight (ARCHITECTURE §7.1.16; the throwing ADR, TE3): the one arc function, each point
## computed from the three stored vectors, and the FLYING state appended after BELT.

const O := Vector3(1.5, 1.6, -2.0)
const V := Vector3(7.071, 7.071, 0.0)
const G := Vector3(0.0, -9.8, 0.0)


func test_the_arc_starts_at_the_origin_exactly() -> void:
	assert_vector(ItemFlight.point(O, V, G, 0)).is_equal(O)


func test_the_first_tick_already_moves() -> void:
	# s = float(n) / RATE: an integer division would keep the item at o for the whole first second.
	assert_vector(ItemFlight.point(O, V, G, 1)).is_not_equal(O)
	assert_vector(ItemFlight.point(O, V, G, Ticks.RATE - 1)).is_not_equal(O)


func test_a_point_one_second_out_is_exact() -> void:
	# Numbers float32 holds exactly: s = 1, so p = o + v + g / 2.
	var at := ItemFlight.point(Vector3(0, 2, 0), Vector3(4, 0, 0), Vector3(0, -8, 0), Ticks.RATE)
	assert_vector(at).is_equal(Vector3(4, -2, 0))
	@warning_ignore("integer_division")
	var half := ItemFlight.point(
		Vector3(0, 2, 0), Vector3(4, 0, 0), Vector3(0, -8, 0), Ticks.RATE / 2
	)
	assert_vector(half).is_equal(Vector3(2, 1, 0))


func test_every_point_follows_the_closed_form() -> void:
	for n in 61:
		var s := float(n) / Ticks.RATE
		var expected := O + V * s + G * 0.5 * s * s
		assert_vector(ItemFlight.point(O, V, G, n)).is_equal_approx(
			expected, Vector3(1e-5, 1e-5, 1e-5)
		)


func test_points_depend_only_on_the_stored_vectors() -> void:
	# A client builds its flight from the decoded vectors and must get the host's bits.
	var host := ItemFlight.new(O, V, G, Vector3.ZERO, 1, 0.15, 60)
	host.ticks = 17
	var client := ItemFlight.new(Vector3(O), Vector3(V), Vector3(G))
	for n in 61:
		assert_vector(client.at(n)).is_equal(host.at(n))
		assert_vector(host.at(n)).is_equal(ItemFlight.point(O, V, G, n))


func test_flying_comes_after_belt() -> void:
	assert_int(ItemState.Where.BELT).is_equal(3)
	assert_int(ItemState.Where.FLYING).is_equal(4)


func test_only_a_flying_item_is_in_flight_and_none_is_carried() -> void:
	var item := ItemState.new(1, null, Vector3.ZERO)
	for where: int in ItemState.Where.values():
		item.where = where as ItemState.Where
		assert_bool(item.is_in_flight()).is_equal(where == ItemState.Where.FLYING)
	item.where = ItemState.Where.FLYING
	assert_bool(item.is_carried()).is_false()
