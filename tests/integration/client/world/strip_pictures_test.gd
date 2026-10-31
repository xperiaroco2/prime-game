extends GdUnitTestSuite
## StripPictures (#1397, ARCHITECTURE §4.7.62), with a test `drawn` signal and `reader`: nothing
## renders while the session runs or before a strip is asked for; then one frame a process frame in
## a private world, a puppet per row in the row's colour, and the strip composed from the frames.

signal test_drawn

const STATION := 4

var _book: BoothBook
var _pictures: StripPictures
var _reads := 0


func before_test() -> void:
	_book = BoothBook.new()
	_pictures = auto_free(StripPictures.new())
	_pictures.book = _book
	_pictures.mode = FixtureBaseMode.mode()
	_pictures.enabled = true
	_pictures.drawn = test_drawn
	_pictures.reader = _read
	_reads = 0
	add_child(_pictures)


func _read(_viewport: SubViewport) -> Image:
	var colours: Array[Color] = [Color.RED, Color.GREEN, Color.BLUE]
	var image := Image.create_empty(16, 12, false, Image.FORMAT_RGBA8)
	image.fill(colours[_reads % colours.size()])
	_reads += 1
	return image


func _step(kind: int, extra: Dictionary = {}) -> void:
	var fields := {"station": STATION, "strip": 1, "step": kind}
	fields.merge(extra, true)
	_book.fold(&"BoothStep", fields)


func _row(peer: int, colour: int, x: float) -> Dictionary:
	return {
		"peer": peer,
		"colour": colour,
		"position": Vector3(x, 0, 0),
		"facing": Vector3.FORWARD,
		"crouched": false,
		"sneaking": false,
		"posed": false,
		"limp": false,
	}


## A three-frame session of different people, printed as strip item 30.
func _session() -> BoothBook.Session:
	_step(BoothStepEvent.STARTED, {"frames": 3})
	_step(BoothStepEvent.FLASH, {"frame": 0, "record": [_row(1, 2, 0.0)]})
	_step(BoothStepEvent.FLASH, {"frame": 1, "record": [_row(1, 2, 0.0), _row(2, 5, 1.0)]})
	_step(BoothStepEvent.FLASH, {"frame": 2, "record": [_row(3, 7, 0.5)]})
	return _book.running_at(STATION)


func test_nothing_renders_while_the_session_runs_or_before_an_ask() -> void:
	var session := _session()
	assert_object(_pictures.texture_of(session)).is_null()
	_pictures._process(0.0)
	assert_int(_pictures.pending()).is_zero()
	assert_object(_pictures.rendering()).is_null()
	_step(BoothStepEvent.PRINTED, {"items": PackedInt32Array([30])})
	_pictures._process(0.0)
	assert_int(_pictures.pending()).is_zero()
	assert_int(_pictures.get_child_count()).is_zero()


func test_an_ask_renders_each_frame_in_a_private_world_then_composes_the_strip() -> void:
	var session := _session()
	_step(BoothStepEvent.PRINTED, {"items": PackedInt32Array([30])})
	assert_object(_pictures.texture_of(session)).is_null()
	assert_object(_pictures.texture_of(session)).is_null()
	assert_int(_pictures.pending()).is_equal(1)
	var colours: Array[Array] = [[2], [2, 5], [7]]
	for index in 3:
		_pictures._process(0.0)
		var viewport := _pictures.rendering()
		assert_object(viewport).is_not_null()
		assert_bool(viewport.own_world_3d).is_true()
		assert_object(viewport.find_world_3d()).is_not_same(get_viewport().find_world_3d())
		var puppets := _pictures.puppets()
		assert_int(puppets.size()).is_equal(colours[index].size())
		for k in puppets.size():
			assert_that(puppets[k].color).is_equal(BodyColours.of(colours[index][k] as int))
			assert_object(puppets[k].get_viewport()).is_same(viewport)
		test_drawn.emit()
	_pictures._process(0.0)
	var texture := _pictures.texture_of(session)
	assert_object(texture).is_not_null()
	var image := texture.get_image()
	assert_that(image.get_size()).is_equal(StripLayout.size(3))
	assert_that(image.get_pixelv(StripLayout.frame_rect(0).get_center())).is_equal(Color.RED)
	assert_that(image.get_pixelv(StripLayout.frame_rect(1).get_center())).is_equal(Color.GREEN)
	assert_that(image.get_pixelv(StripLayout.frame_rect(2).get_center())).is_equal(Color.BLUE)
	assert_int(_pictures.pending()).is_zero()
	assert_int(_pictures.count()).is_equal(1)


func test_a_strip_whose_items_went_is_dropped() -> void:
	var session := _session()
	_step(BoothStepEvent.PRINTED, {"items": PackedInt32Array([30])})
	_pictures.texture_of(session)
	_pictures._process(0.0)
	_book.fold(&"ItemVanished", {"item": 30})
	test_drawn.emit()
	_pictures._process(0.0)
	assert_int(_pictures.pending()).is_zero()
	assert_int(_pictures.count()).is_zero()


func test_a_headless_client_renders_nothing() -> void:
	var headless: StripPictures = auto_free(StripPictures.new())
	assert_bool(headless.enabled).is_false()
	var session := _session()
	_step(BoothStepEvent.PRINTED, {"items": PackedInt32Array([30])})
	headless.book = _book
	assert_object(headless.texture_of(session)).is_null()
	assert_int(headless.pending()).is_zero()
