extends GdUnitTestSuite
## The base controls (#576, #1020): the screens build bare LineEdit, OptionButton, HSlider,
## ScrollContainer and Button (with their popup and scroll bar) and set no type variation on them;
## SpinBox and CheckBox have looks too. The generated theme styles those classes under their own
## name from the pack's Toy looks (tools/theme/mapping.json `base_types`; Button, CheckBox and
## SpinBox from ui-0.7.0's base-type sources), and gives the text no type sizes (a bare Label,
## ProgressBar) the pack's default font size, so their size does not hang on
## gui/theme/default_theme_scale (1 since #1020). Each item is resolved through a live control
## under GameUi's themes, as a screen resolves it. A source test lists every engine control class
## client/ui/ builds: each is a base type, or named here with what it still takes from Godot's
## default theme.

const Boundary := preload("res://tests/unit/client/app/client_boundary_test.gd")
const Builder := preload("res://tools/theme/theme_builder.gd")
const UI := "res://client/ui"
## The pack's font.size.theme-default (#1020), 34 in large text.
const TEXT_SIZE := 27
const LARGE_TEXT_SIZE := 34
## #287's greybox spacing at the 1920x1080 base (Godot's default x 5/3): not a design decision.
const SEPARATION := 7
## prime-game-ui#59: ToySpinField's 12 px above and below make each SpinBox arrow this high.
const ARROW_HEIGHT := 24
## The engine control classes client/ui/ builds that are no base type, and why.
const NAMED := {
	"Control": "draws nothing",
	"MarginContainer": "its margins come from kept names or are 0",
	"CenterContainer": "draws nothing",
	"ColorRect": "its colour comes from the model",
	"Panel": "every one gets a variation (ToyRaised's base, UiParts.backdrop)",
	"PanelContainer": "Godot's panel, no margins, so no size change (gap)",
	"ProgressBar": "the default font size; Godot's StyleBoxes on the voice meter (gap)",
	"TextureRect": "draws its texture only: a how-to card picture (#254), a tinted HUD icon (#489)",
	"GridContainer": "every one gets a spacing variation (the Role tab's team: ToyGridList, #491)",
}


func test_bare_fields_take_toy_field() -> void:
	for theme: Theme in [GameUi.THEME, GameUi.THEME_LARGE]:
		var holder := _holder(theme)
		var line := LineEdit.new()
		holder.add_child(line)
		var spin := SpinBox.new()
		holder.add_child(spin)
		# The spin box's own field is a SpinBoxLineEdit with the engine's variation
		# SpinBoxInnerLineEdit, which the theme makes a thin variation of ToySpinField (#1020).
		var looks := {line: &"ToyField", spin.get_line_edit(): &"ToySpinField"}
		for field: LineEdit in looks:
			var look: StringName = looks[field]
			for item: StringName in [&"normal", &"focus", &"read_only"]:
				assert_object(field.get_theme_stylebox(item)).is_same(
					theme.get_stylebox(item, look)
				)
			assert_int(field.get_theme_font_size(&"font_size")).is_equal(
				theme.get_font_size(&"font_size", look)
			)
			assert_object(field.get_theme_color(&"font_color")).is_equal(
				theme.get_color(&"font_color", look)
			)
	var bare := LineEdit.new()
	_holder(GameUi.THEME).add_child(bare)
	assert_int(bare.get_theme_font_size(&"font_size")).is_equal(22)


func test_bare_spin_boxes_take_toy_spin_box() -> void:
	var metrics: Dictionary = (Builder.load_mapping()["font"] as Dictionary)["metrics"]
	for theme: Theme in [GameUi.THEME, GameUi.THEME_LARGE]:
		var spin := SpinBox.new()
		_holder(theme).add_child(spin)
		for state: String in ["", "_hovered", "_pressed", "_disabled"]:
			for item: String in ["up_background" + state, "down_background" + state]:
				assert_object(spin.get_theme_stylebox(item)).is_same(
					theme.get_stylebox(item, &"ToySpinBox")
				)
		for item: StringName in [&"up", &"up_disabled", &"down", &"down_hover"]:
			assert_object(spin.get_theme_icon(item)).is_same(theme.get_icon(item, &"ToySpinBox"))
		for item: StringName in [&"buttons_width", &"field_and_buttons_separation"]:
			assert_int(spin.get_theme_constant(item)).is_equal(
				theme.get_constant(item, &"ToySpinBox")
			)
		assert_object(spin.get_theme_color(&"up_icon_modulate")).is_equal(
			theme.get_color(&"up_icon_modulate", &"ToySpinBox")
		)
		# Each arrow is (the spin box's height - the separation) / 2 (spin_box.cpp, 4.7.2), and
		# the height is its field's: the field's content margins and one line of Comfortaa.
		# CI imports a stand-in font (#520), so the line comes from the committed metrics, and the
		# margins from the field's StyleBox (the font does not enter them).
		var field := spin.get_line_edit()
		var size := field.get_theme_font_size(&"font_size")
		var height := spin.get_combined_minimum_size().y
		assert_float(height).is_equal(field.get_combined_minimum_size().y)
		var margins := field.get_theme_stylebox(&"normal").get_minimum_size().y
		assert_float(margins).is_equal(24.0)
		var per_unit := float(size) / float(metrics["size"] as int)
		var line := ceilf(per_unit * (metrics["ascent"] as int))
		line += ceilf(per_unit * (metrics["descent"] as int))
		var separation := spin.get_theme_constant(&"buttons_vertical_separation")
		assert_int(separation).is_equal(2)
		var arrow := floori((margins + line - separation) / 2.0)
		assert_int(arrow).is_greater_equal(ARROW_HEIGHT)


func test_bare_option_buttons_and_their_lists_take_toy_dropdown() -> void:
	for theme: Theme in [GameUi.THEME, GameUi.THEME_LARGE]:
		var option := OptionButton.new()
		_holder(theme).add_child(option)
		for item: StringName in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
			assert_object(option.get_theme_stylebox(item)).is_same(
				theme.get_stylebox(item, &"ToyDropdown")
			)
		assert_int(option.get_theme_font_size(&"font_size")).is_equal(
			theme.get_font_size(&"font_size", &"ToyDropdown")
		)
		# The list is a PopupMenu window inside the button: it inherits the theme as well.
		var popup := option.get_popup()
		assert_bool(popup.is_inside_tree()).is_true()
		for item: StringName in [&"panel", &"hover", &"separator"]:
			assert_object(popup.get_theme_stylebox(item)).is_same(
				theme.get_stylebox(item, &"ToyDropdownList")
			)
		assert_int(popup.get_theme_font_size(&"font_size")).is_equal(
			theme.get_font_size(&"font_size", &"ToyDropdownList")
		)
		# The pack's icons (#520): the dropdown's arrow and the list's radio checks.
		assert_object(option.get_theme_icon(&"arrow")).is_same(
			theme.get_icon(&"arrow", &"ToyDropdown")
		)
		assert_str(option.get_theme_icon(&"arrow").resource_path).ends_with("/chevron-down.svg")
		for item: StringName in [&"radio_checked", &"radio_checked_disabled", &"radio_unchecked"]:
			assert_object(popup.get_theme_icon(item)).is_same(
				theme.get_icon(item, &"ToyDropdownList")
			)


func test_bare_sliders_and_scroll_bars_take_toy_looks() -> void:
	var theme := GameUi.THEME
	var holder := _holder(theme)
	var slider := HSlider.new()
	holder.add_child(slider)
	for item: StringName in [&"slider", &"grabber_area", &"grabber_area_highlight"]:
		assert_object(slider.get_theme_stylebox(item)).is_same(
			theme.get_stylebox(item, &"ToySlider")
		)
	# The pack's grabbers (#520), the knob at its import size.
	for item: StringName in [&"grabber", &"grabber_highlight", &"grabber_disabled"]:
		assert_object(slider.get_theme_icon(item)).is_same(theme.get_icon(item, &"ToySlider"))
	assert_object(slider.get_theme_icon(&"grabber").get_size()).is_equal(Vector2(28, 28))
	var scroll := ScrollContainer.new()
	holder.add_child(scroll)
	assert_int(scroll.get_theme_constant(&"scrollbar_h_separation")).is_equal(
		theme.get_constant(&"scrollbar_h_separation", &"ToyScroll")
	)
	var bar := scroll.get_v_scroll_bar()
	for item: StringName in [&"scroll", &"grabber", &"grabber_highlight", &"grabber_pressed"]:
		assert_object(bar.get_theme_stylebox(item)).is_same(
			theme.get_stylebox(item, &"ToyScrollBar")
		)


func test_text_and_spacing_take_the_default_size_and_their_greybox_spacing() -> void:
	var holder := _holder(GameUi.THEME)
	var label := Label.new()
	var button := Button.new()
	var check := CheckBox.new()
	var meter := ProgressBar.new()
	var column := VBoxContainer.new()
	var row := HBoxContainer.new()
	var line := VSeparator.new()
	for each: Control in [label, button, check, meter, column, row, line]:
		holder.add_child(each)
	for each: Control in [label, meter]:
		(
			assert_int(each.get_theme_font_size(&"font_size"))
			. override_failure_message(each.get_class())
			. is_equal(TEXT_SIZE)
		)
	# A bare Button and CheckBox take their Toy looks' label sizes (#1020), not the default size.
	assert_int(button.get_theme_font_size(&"font_size")).is_equal(
		GameUi.THEME.get_font_size(&"font_size", &"ToyButtonPlain")
	)
	assert_int(check.get_theme_font_size(&"font_size")).is_equal(
		GameUi.THEME.get_font_size(&"font_size", &"ToyCheckBox")
	)
	assert_int(label.get_theme_constant(&"line_spacing")).is_equal(5)
	assert_int(check.get_theme_constant(&"h_separation")).is_equal(
		GameUi.THEME.get_constant(&"h_separation", &"ToyCheckBox")
	)
	for each: Control in [column, row, line]:
		assert_int(each.get_theme_constant(&"separation")).is_equal(SEPARATION)
	# A variation still wins over the class row and the default size (HudText -> ToyTextOnDark).
	var hud := Label.new()
	hud.theme_type_variation = &"HudText"
	holder.add_child(hud)
	assert_int(hud.get_theme_font_size(&"font_size")).is_equal(
		GameUi.THEME.get_font_size(&"font_size", &"ToyTextOnDark")
	)
	assert_int(hud.get_theme_font_size(&"font_size")).is_not_equal(TEXT_SIZE)


func test_each_button_class_the_screens_build_takes_its_own_toy_look() -> void:
	# The Button row (ToyButtonPlain, #1020) comes before Godot's own look of every subclass (the
	# type chain is searched in our theme first): CheckBox and OptionButton have rows of their own,
	# which win over the Button row, so each takes its own Toy look.
	for theme: Theme in [GameUi.THEME, GameUi.THEME_LARGE]:
		var holder := _holder(theme)
		var looks := {
			Button.new(): &"ToyButtonPlain",
			CheckBox.new(): &"ToyCheckBox",
			OptionButton.new(): &"ToyDropdown",
		}
		for each: Button in looks:
			holder.add_child(each)
			var look: StringName = looks[each]
			for item: StringName in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
				(
					assert_object(each.get_theme_stylebox(item))
					. override_failure_message("%s %s" % [each.get_class(), item])
					. is_same(theme.get_stylebox(item, look))
				)
			assert_object(each.get_theme_color(&"font_color")).is_equal(
				theme.get_color(&"font_color", look)
			)
		var check := CheckBox.new()
		holder.add_child(check)
		for item: StringName in [&"checked", &"unchecked", &"checked_disabled"]:
			assert_object(check.get_theme_icon(item)).is_same(theme.get_icon(item, &"ToyCheckBox"))
		# A Toy variation of Button still wins over the Button row.
		var primary := Button.new()
		primary.theme_type_variation = &"ToyButtonPrimary"
		holder.add_child(primary)
		assert_object(primary.get_theme_stylebox(&"normal")).is_same(
			theme.get_stylebox(&"normal", &"ToyButtonPrimary")
		)


func test_large_text_grows_the_fields_and_the_default_size() -> void:
	var normal := LineEdit.new()
	var large := LineEdit.new()
	_holder(GameUi.THEME).add_child(normal)
	_holder(GameUi.THEME_LARGE).add_child(large)
	assert_int(large.get_theme_font_size(&"font_size")).is_greater(
		normal.get_theme_font_size(&"font_size")
	)
	# The pack's font.size.theme-default has a large value since ui-0.7.0 (#1020).
	var label := Label.new()
	_holder(GameUi.THEME_LARGE).add_child(label)
	assert_int(label.get_theme_font_size(&"font_size")).is_equal(LARGE_TEXT_SIZE)
	var bare := Label.new()
	_holder(GameUi.THEME).add_child(bare)
	assert_int(bare.get_theme_font_size(&"font_size")).is_equal(TEXT_SIZE)


func test_every_control_class_the_screens_build_is_covered_or_named() -> void:
	var covered := Array(Builder.base_type_names(Builder.load_mapping()))
	var built := PackedStringArray()
	for file: String in DirAccess.get_files_at(UI):
		if file.ends_with(".gd"):
			built.append_array(classes(FileAccess.get_file_as_string(UI.path_join(file))))
	assert_array(Array(built)).contains(
		["LineEdit", "ScrollContainer", "OptionButton", "GridContainer", "Button"]
	)
	var unknown := PackedStringArray()
	for cls in built:
		if not covered.has(cls) and not NAMED.has(cls) and not unknown.has(cls):
			unknown.append(cls)
	assert_array(Array(unknown)).is_empty()
	# The planted miss: a screen that starts to build a TextEdit is named.
	var planted := classes('var notes := TextEdit.new()\nvar name := "Tree.new()"')
	assert_array(Array(planted)).contains_exactly(["TextEdit"])
	for cls: String in NAMED:
		assert_bool(covered.has(cls)).override_failure_message(cls).is_false()
	# The Button subclasses the shadow check skips (mapping.unbuilt, #1020) are built nowhere, and
	# never named here: a screen that starts to build one fails above until it gets a row.
	for cls: Variant in Builder.load_mapping()["unbuilt"] as Array:
		assert_bool(built.has(str(cls))).override_failure_message(str(cls)).is_false()
		assert_bool(NAMED.has(cls)).override_failure_message(str(cls)).is_false()
	assert_array(Array(classes("var toggle := CheckButton.new()"))).contains_exactly(
		["CheckButton"]
	)


## The engine Control classes `source` builds with `.new()`, comments and strings stripped.
static func classes(source: String) -> PackedStringArray:
	var found := PackedStringArray()
	var regex := RegEx.create_from_string("\\b([A-Z][A-Za-z0-9]*)\\.new\\(\\)")
	for hit: RegExMatch in regex.search_all(Boundary.strip(source)):
		var cls := hit.get_string(1)
		if ClassDB.class_exists(cls) and ClassDB.is_parent_class(cls, "Control"):
			found.append(cls)
	return found


func _holder(theme: Theme) -> Control:
	var holder: Control = auto_free(Control.new())
	holder.theme = theme
	add_child(holder)
	return holder
