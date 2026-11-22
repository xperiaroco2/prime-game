extends GdUnitTestSuite
## ItemView's crystal kinds (#1672): the crystal model's size for the aim and the sight point, and
## the labelled box only where the model is missing (CI's Git LFS stand-in; the model itself:
## ship_device_looks_test.gd, in the nightly lfs job).


func test_the_crystal_kinds_take_the_crystal_s_size() -> void:
	for kind: StringName in ItemView.CRYSTAL_CHARGE:
		assert_bool(ItemView.size_of(kind).is_equal_approx(ItemView.CRYSTAL_SIZE)).is_true()
		var centre := ItemView.centre_of(kind, Vector3.ZERO)
		assert_float(centre.y).is_equal_approx(ItemView.CRYSTAL_SIZE.y * 0.5, 1e-6)
	assert_bool(ItemView.size_of(&"mug").is_equal_approx(ItemView.UNKNOWN_SIZE)).is_true()


func test_a_crystal_is_its_model_or_else_the_labelled_box() -> void:
	for kind: StringName in ItemView.CRYSTAL_CHARGE:
		var view: ItemView = auto_free(ItemView.make(3, kind, Color.WHITE))
		var label := view.look().find_child("Label", true, false)
		if view.crystal() == null:
			# No model here: the kind still shows, as any kind the client has no look for.
			assert_object(label).is_not_null()
			assert_object(view.look().find_child("Box", true, false)).is_not_null()
		else:
			assert_object(label).is_null()
			assert_object(view.crystal().node().get_parent()).is_same(view.look())
