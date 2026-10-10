extends GdUnitTestSuite
## BodyColours (#551): one colour per PlayerColours index, ten distinct ones, each the hex of the
## UI pack's palette token it names (a placeholder until the engineer picks the ten); an index
## outside them draws index 0's. RemotePlayerBody keeps a colour set before it is ready.

const PACK := "res://client/ui/theme/pack/toy.pack.json"
const BODY := preload("res://client/player/remote_player_body.tscn")


func test_one_distinct_colour_per_index() -> void:
	assert_int(BodyColours.HEXES.size()).is_equal(PlayerColours.COUNT)
	assert_int(BodyColours.TOKENS.size()).is_equal(PlayerColours.COUNT)
	var seen: Array[Color] = []
	for index: int in PlayerColours.COUNT:
		var colour := BodyColours.of(index)
		assert_bool(seen.has(colour)).override_failure_message(str(index)).is_false()
		assert_float(colour.a).is_equal(1.0)
		seen.append(colour)


func test_each_colour_is_its_pack_token() -> void:
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PACK))
	var tokens: Dictionary = pack["tokens"]
	for index: int in PlayerColours.COUNT:
		var token: Dictionary = tokens[BodyColours.TOKENS[index]]
		assert_str(token["type"] as String).is_equal("color")
		(
			assert_object(BodyColours.of(index))
			. override_failure_message(BodyColours.TOKENS[index])
			. is_equal(Color(token["hex"] as String))
		)


func test_an_index_outside_the_palette_draws_index_zero() -> void:
	for outside: int in [-1, PlayerColours.COUNT, 255]:
		assert_object(BodyColours.of(outside)).is_equal(BodyColours.of(0))


func test_a_body_keeps_a_colour_set_before_it_is_ready() -> void:
	var body := BODY.instantiate() as RemotePlayerBody
	body.rules = FixtureModes.player_rules()
	body.set_colour(BodyColours.of(3))
	add_child(body)
	var mesh := body.get_node(^"Mesh") as MeshInstance3D
	var material := (mesh.mesh as CapsuleMesh).material as StandardMaterial3D
	assert_object(material.albedo_color).is_equal(BodyColours.of(3))
	body.set_colour(BodyColours.of(5))
	assert_object(material.albedo_color).is_equal(BodyColours.of(5))
	body.free()
