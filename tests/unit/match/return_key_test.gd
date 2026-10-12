extends GdUnitTestSuite
## ReturnKey (ARCHITECTURE §3.5; the returning-players ADR, Decision 1, P7): a usable key is a
## String of 32 lowercase hex characters, and the key for a secret at a target is the first 16
## bytes of SHA-256 of "secret|target", hex-encoded.

const SECRET := "0123456789abcdef0123456789abcdef"


func test_a_usable_key_is_32_lowercase_hex_characters() -> void:
	assert_bool(ReturnKey.is_valid(SECRET)).is_true()
	assert_bool(ReturnKey.is_valid("f".repeat(32))).is_true()


func test_anything_else_is_no_key() -> void:
	for value: Variant in [
		"zz",
		"",
		SECRET.left(31),
		SECRET + "0",
		SECRET.to_upper(),
		SECRET.left(31) + "g",
		SECRET.left(31) + "_",
		SECRET.left(31) + " ",
		StringName(SECRET),
		42,
		null,
		PackedByteArray([1, 2]),
	]:
		assert_bool(ReturnKey.is_valid(value)).override_failure_message(str(value)).is_false()


func test_the_key_is_the_first_16_bytes_of_sha256_hex_encoded() -> void:
	# Pinned with `printf '%s' "<secret>|ABCD" | sha256sum | cut -c1-32`.
	assert_str(ReturnKey.of(SECRET, "ABCD")).is_equal("90ccb95c9652389046a45c3222b2d8a7")
	assert_str(ReturnKey.of("secret", "target")).is_equal("95e16fa63a1bac44b457c95df953d2b9")


func test_one_secret_gives_one_key_per_target() -> void:
	var at_code := ReturnKey.of(SECRET, "ABCD")
	assert_str(ReturnKey.of(SECRET, "ABCD")).is_equal(at_code)
	assert_str(ReturnKey.of(SECRET, "abcd")).is_not_equal(at_code)
	assert_str(ReturnKey.of(SECRET, "192.168.1.5:24600")).is_not_equal(at_code)
	assert_str(ReturnKey.of("f".repeat(32), "ABCD")).is_not_equal(at_code)
	assert_bool(ReturnKey.is_valid(at_code)).is_true()
