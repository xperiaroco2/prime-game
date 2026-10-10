extends GdUnitTestSuite
## BodyColours (#551): one colour per PlayerColours index, ten distinct ones, each the delivery
## circles' palette colour of the same index (the engineer's choice until the UI pack has a
## player-colour list); an index outside them draws index 0's. RemotePlayerBody keeps a colour set
## before it is ready.

const DELIVERY := "res://content/tasks/delivery.tres"
const BODY := preload("res://client/player/remote_player_body.tscn")
## A hex string holds a channel to 1/255: half of that, and a little float slack, either way.
const CHANNEL_SLACK := 0.5 / 255.0 + 0.0001


func test_one_distinct_colour_per_index() -> void:
	assert_int(BodyColours.HEXES.size()).is_equal(PlayerColours.COUNT)
	var seen: Array[Color] = []
	for index: int in PlayerColours.COUNT:
		var colour := BodyColours.of(index)
		assert_bool(seen.has(colour)).override_failure_message(str(index)).is_false()
		assert_float(colour.a).is_equal(1.0)
		seen.append(colour)


func test_each_colour_is_the_delivery_circles_colour() -> void:
	var delivery := load(DELIVERY) as Delivery
	var palette := delivery.circle.palette
	assert_int(palette.size()).is_equal(PlayerColours.COUNT)
	for index: int in PlayerColours.COUNT:
		var body := BodyColours.of(index)
		var circle := palette[index]
		var apart := maxf(
			maxf(absf(body.r - circle.r), absf(body.g - circle.g)),
			maxf(absf(body.b - circle.b), absf(body.a - circle.a))
		)
		(
			assert_float(apart)
			. override_failure_message("%d: %s vs %s" % [index, body, circle])
			. is_less_equal(CHANNEL_SLACK)
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
