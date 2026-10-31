extends GdUnitTestSuite
## FirstPersonHand (client/player/first_person_hand.gd): the hand item in the camera's space, on
## PhotoLayers.LIVE_AVATAR (never in a shot's picture), keyed on the item's id so a photo swapped
## for another photo is rebuilt; the photo's picture kept across the rebuild of the same item; the
## holder's close-up (#787) in front of the eye, facing it, larger, ended by another item; the
## booth's strip (#1397) held up at its own scale and slid into the hand once printed.

var _hand: FirstPersonHand


func before_test() -> void:
	_hand = auto_free(FirstPersonHand.new())
	add_child(_hand)


func test_the_item_sits_one_or_two_handed_on_the_live_avatar_layer() -> void:
	_hand.show_item(&"photo", Color.WHITE, false, 5)
	assert_that(_hand.view().transform).is_equal(
		Transform3D(Basis.IDENTITY, FirstPersonHand.ONE_HANDED)
	)
	assert_int(PhotoLayers.layers_of(_hand)).is_equal(PhotoLayers.LIVE_AVATAR)
	_hand.show_item(&"package", Color.WHITE, true, 6)
	assert_that(_hand.view().transform.origin).is_equal(FirstPersonHand.TWO_HANDED)


func test_the_close_up_faces_the_eye_larger_and_goes_back() -> void:
	_hand.show_item(&"photo", Color.WHITE, false, 5)
	_hand.set_close(true)
	assert_bool(_hand.is_close()).is_true()
	var close := _hand.view().transform
	assert_that(close.origin).is_equal(FirstPersonHand.CLOSE)
	assert_float(close.basis.get_scale().x).is_equal_approx(FirstPersonHand.CLOSE_SCALE, 0.001)
	# The picture face (the look's +Y) turns to the eye, which looks along -Z from the origin.
	assert_bool(close.basis.y.normalized().is_equal_approx(Vector3.BACK)).is_true()
	assert_float(close.basis.z.normalized().dot(Vector3.DOWN)).is_greater(0.99)
	_hand.set_close(false)
	assert_bool(_hand.is_close()).is_false()
	assert_that(_hand.view().transform).is_equal(
		Transform3D(Basis.IDENTITY, FirstPersonHand.ONE_HANDED)
	)


func test_another_item_ends_the_close_up_and_the_same_one_keeps_it() -> void:
	_hand.show_item(&"photo", Color.WHITE, false, 5)
	_hand.set_close(true)
	_hand.show_item(&"photo", Color.WHITE, false, 5)
	assert_bool(_hand.is_close()).is_true()
	_hand.show_item(&"photo", Color.WHITE, false, 6)
	assert_bool(_hand.is_close()).is_false()
	assert_that(_hand.view().transform.origin).is_equal(FirstPersonHand.ONE_HANDED)


func test_no_close_up_with_an_empty_hand() -> void:
	_hand.set_close(true)
	assert_bool(_hand.is_close()).is_false()


func test_the_picture_stays_on_the_same_item_and_goes_with_another() -> void:
	var image := Image.create_empty(4, 4, false, Image.FORMAT_RGB8)
	var texture := ImageTexture.create_from_image(image)
	_hand.show_item(&"photo", Color.WHITE, false, 5)
	_hand.set_picture(texture)
	_hand.show_item(&"photo", Color.WHITE, false, 5)
	assert_object(_hand.view().picture()).is_same(texture)
	_hand.show_item(&"photo", Color.WHITE, false, 6)
	assert_object(_hand.view().picture()).is_null()


func test_a_strip_is_held_up_at_its_own_scale() -> void:
	_hand.show_item(StripLooks.STRIP, Color.WHITE, false, 7)
	_hand.set_close(true)
	var close := _hand.view().transform
	assert_that(close.origin).is_equal(FirstPersonHand.CLOSE)
	assert_float(close.basis.get_scale().x).is_equal_approx(StripLooks.CLOSE_SCALE, 0.001)


func test_a_slide_starts_below_the_hand_and_settles_in_it() -> void:
	_hand.show_item(StripLooks.STRIP, Color.WHITE, false, 7)
	_hand.begin_slide(0.6)
	assert_bool(_hand.is_sliding()).is_true()
	assert_that(_hand.view().transform.origin).is_equal(
		FirstPersonHand.ONE_HANDED + FirstPersonHand.SLIDE_FROM
	)
	_hand._process(0.3)
	var half := _hand.view().transform.origin
	assert_float(half.y).is_greater(FirstPersonHand.ONE_HANDED.y + FirstPersonHand.SLIDE_FROM.y)
	assert_float(half.y).is_less(FirstPersonHand.ONE_HANDED.y)
	_hand._process(0.4)
	assert_bool(_hand.is_sliding()).is_false()
	assert_that(_hand.view().transform.origin).is_equal(FirstPersonHand.ONE_HANDED)


func test_another_item_ends_the_slide_and_an_empty_hand_has_none() -> void:
	_hand.begin_slide(0.6)
	assert_bool(_hand.is_sliding()).is_false()
	_hand.show_item(StripLooks.STRIP, Color.WHITE, false, 7)
	_hand.begin_slide(0.6)
	_hand.show_item(&"photo", Color.WHITE, false, 8)
	assert_bool(_hand.is_sliding()).is_false()
	assert_that(_hand.view().transform.origin).is_equal(FirstPersonHand.ONE_HANDED)
