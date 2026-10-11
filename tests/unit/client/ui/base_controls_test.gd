extends GdUnitTestSuite
## The base controls (#576): the screens build bare LineEdit, SpinBox, OptionButton, HSlider and
## ScrollContainer (with their popup, inner field and scroll bar) and set no type variation on
## them. The generated theme styles those classes under their own name from the pack's Toy looks
## (tools/theme/mapping.json `base_types`), and gives the text no type sizes (a bare Label, Button,
## CheckBox) its default font size, so their size does not hang on gui/theme/default_theme_scale
## (held at 1.6667 for the gaps named below). Each item is resolved through a live control under
## GameUi's themes, as a screen resolves it. A source test lists every engine control class
## client/ui/ builds: each is a base type, or named here with what it still takes from Godot's
## default theme.

const Boundary := preload("res://tests/unit/client/app/client_boundary_test.gd")
const Builder := preload("res://tools/theme/theme_builder.gd")
const UI := "res://client/ui"
## #287's greybox sizes at the 1920x1080 base (Godot's default x 5/3): not a design decision.
const TEXT_SIZE := 27
const SEPARATION := 7
## The engine control classes client/ui/ builds that are no base type, and why. (CheckBox is one,
## for its h_separation only: its icons and StyleBoxes are Godot's, a gap like those below.)
const NAMED := {
	"Control": "draws nothing",
	"MarginContainer": "its margins come from kept names or are 0",
	"CenterContainer": "draws nothing",
	"ColorRect": "its colour comes from the model",
	"Panel": "every one gets a variation (ToyRaised's base, UiParts.backdrop)",
	"SpinBox": "its field is a LineEdit (ToyField); its arrows are Godot's (gap)",
	"Button": "the default font size; Godot's StyleBoxes on Copy, Ready and the keys (gap)",
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
		# The spin box's own field is a SpinBoxLineEdit: it finds the LineEdit row too.
		for field: LineEdit in [line, spin.get_line_edit()]:
			for item: StringName in [&"normal", &"focus", &"read_only"]:
				assert_object(field.get_theme_stylebox(item)).is_same(
					theme.get_stylebox(item, &"ToyField")
				)
			assert_int(field.get_theme_font_size(&"font_size")).is_equal(
				theme.get_font_size(&"font_size", &"ToyField")
			)
			assert_object(field.get_theme_color(&"font_color")).is_equal(
				theme.get_color(&"font_color", &"ToyField")
			)
	var bare := LineEdit.new()
	_holder(GameUi.THEME).add_child(bare)
	assert_int(bare.get_theme_font_size(&"font_size")).is_equal(22)


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


func test_text_and_spacing_keep_their_greybox_size() -> void:
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
	for each: Control in [label, button, check, meter]:
		(
			assert_int(each.get_theme_font_size(&"font_size"))
			. override_failure_message(each.get_class())
			. is_equal(TEXT_SIZE)
		)
	assert_int(label.get_theme_constant(&"line_spacing")).is_equal(5)
	assert_int(check.get_theme_constant(&"h_separation")).is_equal(SEPARATION)
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


func test_a_base_type_leaves_the_subclasses_godot_styles_alone() -> void:
	# A row on Button would come before Godot's own CheckBox look (the type chain is searched in
	# our theme first): the check box keeps Godot's box, the button Godot's too, since no base
	# type restyles them.
	var holder := _holder(GameUi.THEME)
	var check := CheckBox.new()
	var button := Button.new()
	holder.add_child(check)
	holder.add_child(button)
	var default := ThemeDB.get_default_theme()
	assert_object(check.get_theme_stylebox(&"normal")).is_same(
		default.get_stylebox(&"normal", &"CheckBox")
	)
	assert_object(button.get_theme_stylebox(&"normal")).is_same(
		default.get_stylebox(&"normal", &"Button")
	)


func test_large_text_grows_the_fields_but_not_the_default_size() -> void:
	# Pinned as it is: the pack has a large size for ToyField, none for the default size (a gap).
	var normal := LineEdit.new()
	var large := LineEdit.new()
	_holder(GameUi.THEME).add_child(normal)
	_holder(GameUi.THEME_LARGE).add_child(large)
	assert_int(large.get_theme_font_size(&"font_size")).is_greater(
		normal.get_theme_font_size(&"font_size")
	)
	var label := Label.new()
	_holder(GameUi.THEME_LARGE).add_child(label)
	assert_int(label.get_theme_font_size(&"font_size")).is_equal(TEXT_SIZE)


func test_every_control_class_the_screens_build_is_covered_or_named() -> void:
	var covered := Array(Builder.base_type_names(Builder.load_mapping()))
	var built := PackedStringArray()
	for file: String in DirAccess.get_files_at(UI):
		if file.ends_with(".gd"):
			built.append_array(classes(FileAccess.get_file_as_string(UI.path_join(file))))
	assert_array(Array(built)).contains(
		["LineEdit", "ScrollContainer", "OptionButton", "GridContainer"]
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
