extends GdUnitTestSuite
## The UI pack's icons (client/ui/ToyIcons, #489; ARCHITECTURE §4.7.37): each icon the HUD draws
## can be read, at the size the pack's `assets` list gives it (its `drawn_px`), from the scale
## (`svg_scale`) read off the pack, so a HUD with no glyph or a wrongly scaled one fails here.


func test_the_huds_icons_are_read_at_the_packs_drawn_size() -> void:
	# [icon, svg_scale, drawn px] from the pinned pack (ui-0.4.0) `assets` list.
	var rows: Array[Array] = [
		[&"mic", 1.17, 28],
		[&"mic-off", 1.17, 28],
		[&"item", 2.0, 48],
		[&"knife", 1.0, 48],
	]
	for row: Array in rows:
		var icon: StringName = row[0]
		(
			assert_float(ToyIcons.scale_of(icon))
			. override_failure_message(String(icon))
			. is_equal_approx(row[1] as float, 0.001)
		)
		var texture := ToyIcons.texture(icon)
		assert_object(texture).override_failure_message(String(icon)).is_not_null()
		var px: int = row[2]
		assert_int(texture.get_width()).override_failure_message(String(icon)).is_between(
			px - 1, px + 1
		)
		assert_int(texture.get_height()).override_failure_message(String(icon)).is_between(
			px - 1, px + 1
		)


func test_an_icon_is_made_once() -> void:
	assert_object(ToyIcons.texture(&"mic")).is_same(ToyIcons.texture(&"mic"))


func test_an_unlisted_icon_scales_at_one() -> void:
	assert_float(ToyIcons.scale_of(&"no-such-icon")).is_equal(1.0)
