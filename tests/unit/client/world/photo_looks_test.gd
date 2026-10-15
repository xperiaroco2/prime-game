extends GdUnitTestSuite
## PhotoLooks (#787, photo P8): the film and the photo are drawn by their own looks, not labelled
## boxes; the photo shows its picture's texture (grey with none); every material is depth-tested;
## the first-person hand tells two photos apart by their item ids.


func test_the_film_and_the_photo_have_their_looks_and_no_label() -> void:
	for kind: StringName in [PhotoLooks.FILM, PhotoLooks.PHOTO]:
		var view := auto_free(ItemView.make(4, kind, Color.WHITE)) as ItemView
		assert_object(view.look().find_child("Label", true, false)).is_null()
		assert_vector(ItemView.size_of(kind)).is_equal(PhotoLooks.size_of(kind))
	var photo := auto_free(ItemView.make(5, PhotoLooks.PHOTO, Color.WHITE)) as ItemView
	assert_object(PhotoLooks.picture_of(photo.look())).is_not_null()
	var film := auto_free(ItemView.make(6, PhotoLooks.FILM, Color.WHITE)) as ItemView
	assert_object(PhotoLooks.picture_of(film.look())).is_null()


func test_a_photo_shows_its_picture_and_the_blank_without_one() -> void:
	var view := auto_free(ItemView.make(5, PhotoLooks.PHOTO, Color.WHITE)) as ItemView
	var picture := PhotoLooks.picture_of(view.look())
	var material := picture.material_override as StandardMaterial3D
	assert_object(view.picture()).is_null()
	assert_that(material.albedo_color).is_equal(PhotoLooks.BLANK_COLOUR)
	var texture := ImageTexture.create_from_image(Image.create(4, 3, false, Image.FORMAT_RGB8))
	view.set_picture(texture)
	assert_object(view.picture()).is_same(texture)
	assert_that(material.albedo_color).is_equal(Color.WHITE)
	view.set_picture(null)
	assert_object(view.picture()).is_null()
	assert_that(material.albedo_color).is_equal(PhotoLooks.BLANK_COLOUR)


func test_no_photo_material_skips_the_depth_test() -> void:
	for kind: StringName in [PhotoLooks.FILM, PhotoLooks.PHOTO]:
		var look := auto_free(PhotoLooks.build(kind)) as Node3D
		for node: Node in look.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			for material: Material in [mesh.material_override, mesh.mesh.surface_get_material(0)]:
				if material is BaseMaterial3D:
					assert_bool((material as BaseMaterial3D).no_depth_test).is_false()


func test_each_photo_look_has_its_own_picture_material() -> void:
	var first := auto_free(PhotoLooks.build(PhotoLooks.PHOTO)) as Node3D
	var second := auto_free(PhotoLooks.build(PhotoLooks.PHOTO)) as Node3D
	var texture := ImageTexture.create_from_image(Image.create(4, 3, false, Image.FORMAT_RGB8))
	PhotoLooks.set_picture(first, texture)
	var other := PhotoLooks.picture_of(second).material_override as StandardMaterial3D
	assert_object(other.albedo_texture).is_null()


func test_the_hand_tells_two_photos_apart_and_drops_the_picture_at_a_swap() -> void:
	var hand := auto_free(FirstPersonHand.new()) as FirstPersonHand
	var texture := ImageTexture.create_from_image(Image.create(4, 3, false, Image.FORMAT_RGB8))
	hand.show_item(PhotoLooks.PHOTO, Color.WHITE, false, 60)
	hand.set_picture(texture)
	assert_object(hand.view().picture()).is_same(texture)
	var first := hand.view()
	hand.show_item(PhotoLooks.PHOTO, Color.WHITE, false, 60)
	assert_object(hand.view()).is_same(first)
	hand.show_item(PhotoLooks.PHOTO, Color.WHITE, false, 61)
	assert_object(hand.view()).is_not_same(first)
	assert_int(hand.shown_id()).is_equal(61)
	assert_object(hand.view().picture()).is_null()
