extends GdUnitTestSuite
## RngStreams: SplitMix64 and FNV-1a against outputs of an independent implementation (Python,
## unsigned 64-bit arithmetic, written as signed ints here), and the stream properties of
## ARCHITECTURE §3.3.


func test_splitmix64_matches_the_reference() -> void:
	assert_int(RngStreams.splitmix64(0)).is_equal(-2152535657050944081)
	assert_int(RngStreams.splitmix64(1)).is_equal(-7995527694508729151)
	assert_int(RngStreams.splitmix64(-1)).is_equal(-1956407806741107680)


func test_match_seeds_are_the_splitmix64_sequence() -> void:
	# The published first outputs of SplitMix64 seeded with 1234567.
	assert_int(RngStreams.match_seed_of(1234567, 0)).is_equal(6457827717110365317)
	assert_int(RngStreams.match_seed_of(1234567, 1)).is_equal(3203168211198807973)
	assert_int(RngStreams.match_seed_of(1234567, 2)).is_equal(-8629252141511181193)
	assert_int(RngStreams.match_seed_of(42, 0)).is_equal(-4767286540954276203)
	assert_int(RngStreams.match_seed_of(42, 1)).is_equal(2949826092126892291)


func test_fnv1a64_matches_the_reference() -> void:
	assert_int(RngStreams.fnv1a64("")).is_equal(-3750763034362895579)
	assert_int(RngStreams.fnv1a64("a")).is_equal(-5808556873153909620)
	assert_int(RngStreams.fnv1a64("roles")).is_equal(6362746547845726270)
	assert_int(RngStreams.fnv1a64("spawns")).is_equal(3223605006523448401)


func test_purpose_seeds_match_the_reference() -> void:
	var seed_of_match := RngStreams.match_seed_of(42, 0)
	assert_int(RngStreams.purpose_seed_of(seed_of_match, &"roles")).is_equal(-301083017902004497)
	assert_int(RngStreams.purpose_seed_of(seed_of_match, &"spawns")).is_equal(6108055049671969200)


func test_a_stream_is_seeded_by_its_purpose() -> void:
	var streams := RngStreams.new(42)
	var expected := RngStreams.purpose_seed_of(RngStreams.match_seed_of(42, 0), &"roles")
	assert_int(streams.stream(&"roles").seed).is_equal(expected)


func test_same_session_seed_gives_the_same_draws() -> void:
	var a := RngStreams.new(99)
	var b := RngStreams.new(99)
	for i in 5:
		assert_int(a.stream(&"roles").randi()).is_equal(b.stream(&"roles").randi())


func test_a_new_purpose_never_shifts_the_draws_of_another() -> void:
	var alone := RngStreams.new(5)
	var mixed := RngStreams.new(5)
	var first := alone.stream(&"roles").randi()
	assert_int(mixed.stream(&"roles").randi()).is_equal(first)
	mixed.stream(&"knives").randi()
	mixed.stream(&"a new purpose").randi()
	assert_int(mixed.stream(&"roles").randi()).is_equal(alone.stream(&"roles").randi())


func test_purposes_draw_differently() -> void:
	var streams := RngStreams.new(5)
	assert_int(streams.stream(&"roles").seed).is_not_equal(streams.stream(&"spawns").seed)


func test_the_next_match_starts_every_purpose_again_from_its_own_seed() -> void:
	var streams := RngStreams.new(5)
	var first := streams.stream(&"roles").seed
	streams.next_match()
	assert_int(streams.match_index).is_equal(1)
	var expected := RngStreams.purpose_seed_of(RngStreams.match_seed_of(5, 1), &"roles")
	assert_int(streams.stream(&"roles").seed).is_equal(expected)
	assert_int(streams.stream(&"roles").seed).is_not_equal(first)


func test_shuffled_indices_is_a_deterministic_permutation() -> void:
	var a := RandomNumberGenerator.new()
	a.seed = 11
	var b := RandomNumberGenerator.new()
	b.seed = 11
	var order := RngStreams.shuffled_indices(10, a)
	assert_array(Array(order)).is_equal(Array(RngStreams.shuffled_indices(10, b)))
	var sorted := Array(order)
	sorted.sort()
	assert_array(sorted).is_equal([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
	assert_array(Array(RngStreams.shuffled_indices(0, a))).is_empty()
	assert_array(Array(RngStreams.shuffled_indices(1, a))).is_equal([0])
