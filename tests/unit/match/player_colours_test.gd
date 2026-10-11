extends GdUnitTestSuite
## The body colours (ARCHITECTURE §3.5, #551): ten indexes, the first free one, and a wanted colour
## kept when free, else moved to the first free one (the engineer's answer on #73).


func test_ten_colours() -> void:
	assert_int(PlayerColours.COUNT).is_equal(10)


func test_the_first_free_colour() -> void:
	assert_int(PlayerColours.first_free([])).is_equal(0)
	assert_int(PlayerColours.first_free([0, 1, 3])).is_equal(2)
	assert_int(PlayerColours.first_free([3, 1, 0])).is_equal(2)
	assert_int(PlayerColours.first_free([1, 2])).is_equal(0)
	var all_but_last: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8]
	assert_int(PlayerColours.first_free(all_but_last)).is_equal(9)


func test_every_colour_taken_gives_colour_zero_not_a_failure() -> void:
	# GameMode.check makes it unreachable (at most ten players); a duplicate, never a refused join.
	var all: Array[int] = [9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
	assert_int(PlayerColours.first_free(all)).is_equal(0)


func test_a_free_wanted_colour_is_kept_and_a_taken_one_moves_to_the_first_free() -> void:
	assert_int(PlayerColours.resolve(7, [0, 1])).is_equal(7)
	assert_int(PlayerColours.resolve(1, [0, 1])).is_equal(2)
	assert_int(PlayerColours.resolve(0, [0, 2])).is_equal(1)
	assert_int(PlayerColours.resolve(-1, [])).is_equal(0)
	assert_int(PlayerColours.resolve(10, [0])).is_equal(1)


func test_only_an_int_in_range_is_a_colour() -> void:
	for good: int in [0, 5, 9]:
		assert_bool(PlayerColours.is_valid(good)).is_true()
	for bad: Variant in [-1, 10, 255, "3", 3.0, null, true]:
		assert_bool(PlayerColours.is_valid(bad)).override_failure_message(str(bad)).is_false()
