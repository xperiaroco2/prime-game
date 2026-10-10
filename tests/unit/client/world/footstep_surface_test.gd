extends GdUnitTestSuite
## FootstepSurface (#525): a floor's tag (metadata `surface` on its collider or an ancestor) names
## its surface; an untagged floor or an unknown tag is the default, the greybox's one surface.


func test_a_known_tag_names_its_surface_and_anything_else_is_the_default() -> void:
	for surface: StringName in FootstepSurface.SURFACES:
		assert_str(String(FootstepSurface.resolve(surface))).is_equal(String(surface))
		assert_str(String(FootstepSurface.resolve(String(surface)))).is_equal(String(surface))
	var default := String(FootstepSurface.DEFAULT)
	assert_bool(FootstepSurface.DEFAULT in FootstepSurface.SURFACES).is_true()
	assert_str(String(FootstepSurface.resolve(&"lava"))).is_equal(default)
	assert_str(String(FootstepSurface.resolve(null))).is_equal(default)
	assert_str(String(FootstepSurface.resolve(3))).is_equal(default)


func test_the_nearest_tag_of_the_collider_or_its_ancestors_counts() -> void:
	var room: Node3D = auto_free(Node3D.new())
	var floor_body := StaticBody3D.new()
	room.add_child(floor_body)
	assert_str(String(FootstepSurface.of(floor_body))).is_equal(String(FootstepSurface.DEFAULT))
	room.set_meta(FootstepSurface.META, &"carpet")
	assert_str(String(FootstepSurface.of(floor_body))).is_equal("carpet")
	floor_body.set_meta(FootstepSurface.META, "wood")
	assert_str(String(FootstepSurface.of(floor_body))).is_equal("wood")
	assert_str(String(FootstepSurface.of(null))).is_equal(String(FootstepSurface.DEFAULT))
