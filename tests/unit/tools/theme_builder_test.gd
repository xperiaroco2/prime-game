extends GdUnitTestSuite
## The generated theme (#288): tools/theme/theme_builder.gd turns the pinned UI pack
## (client/ui/theme/pack/, ui-sync) into game_theme.tres and game_theme_large.tres through
## tools/theme/mapping.json. Every pack variation is mapped and every mapped engine item exists in
## the 4.7.2 class reference (Godot's default theme, or the mapping's list of items it binds but
## does not set); names are letters only; the committed files are what a fresh build writes (the
## stale test, with a planted change that must show); the uid is kept; spot values, the press
## motion and the ramp; the large-text theme; the legacy and kept names; the toy base and toggle
## hints in the themes' metadata (#289); the pack's textures as theme icons and the font hook
## (#520). Each check that guards data is also run on a broken copy and must name it.

const Builder := preload("res://tools/theme/theme_builder.gd")
const THEME_UID := "uid://c8behqt7jtcn8"
const SCRATCH := "user://theme_builder_test.tres"
const REGENERATE := "tools\\run.cmd run tools/theme/build_theme.gd --headless"
## The pack's deprecated variations at ui-2.5.4 the theme skips (all but mapping.deprecated_in_use).
const DEPRECATED: Array[String] = [
	"ToyBarAnger",
	"ToyBarAngerTrack",
	"ToyBarHealthAlarm",
	"ToyBarHealthCalm",
	"ToyBarStaminaAlarm",
	"ToyBarStaminaCalm",
	"ToyBaseCard",
	"ToyBasePanel",
	"ToyBasePrimaryOnDark",
	"ToyBasePrimaryOnLight",
	"ToyBaseRaisedOnDark",
	"ToyBaseRaisedOnLight",
	"ToyBaseTitle",
	"ToyButtonDangerOnMint",
	"ToyButtonPrimaryOnMint",
	"ToyChipNew",
	"ToyChipNewText",
	"ToyHowtoCaption",
	"ToyPlateCount",
	"ToyPlateHead",
	"ToyPlateHeadText",
]
## Deprecated since ui-2.0.0 but still the HUD's ToyBar (client/ui/toy_bar.gd) until #1319.
const IN_USE: Array[String] = ["ToyBarHealth", "ToyBarStamina", "ToyBarTrack"]

var _mapping: Dictionary
var _pack: Dictionary


func before() -> void:
	_mapping = Builder.load_mapping()
	_pack = Builder.load_pack(_mapping)


func test_every_pack_variation_is_mapped() -> void:
	assert_bool(_pack.is_empty()).override_failure_message("no pinned pack").is_false()
	assert_array(Builder.check_pack(_pack, _mapping)).is_empty()
	var generated := Builder.generated_names(_pack, _mapping)
	assert_int(generated.size() + DEPRECATED.size()).is_equal(
		(_pack["variations"] as Dictionary).size()
	)
	assert_array(Array(Builder.deprecated_names(_pack, _mapping))).contains_exactly(DEPRECATED)
	assert_array(Array(Builder.deprecated_names(_pack))).contains_exactly_in_any_order(
		DEPRECATED + IN_USE
	)
	for type_name in IN_USE:
		assert_bool(generated.has(type_name)).override_failure_message(type_name).is_true()
	var theme := _committed("default")
	for type_name in generated:
		(
			assert_str(str(theme.get_type_variation_base(type_name)))
			. override_failure_message(type_name)
			. is_not_empty()
		)
	for type_name in DEPRECATED:
		assert_bool(theme.get_type_list().has(type_name)).is_false()


func test_check_pack_names_what_the_mapping_does_not_cover() -> void:
	var cases: Array[String] = [
		"class Foo is not mapped",
		"state hover-presed is not mapped",
		"token tab.idle.items.bogus-color",
		"token tab.idle.normal.bg-colour",
		"schema 2 is not in mapping.pack_schemas",
		"20 stops for 20 steps",
		"texture bogus is not an icon of HSlider",
		"texture grabber: res://assets/ui/toy_pack/icons/gone.svg is not imported",
		"the name is not letters only",
		"the name is also a legacy or kept name",
		"member shiny is not in mapping.variation_members",
		"has a delay",
		"legacy LifeBar: ToyBarProgress is not a live pack variation",
		"lacks bg-color (a StyleBox field)",
		"base ToyBogus is not a live Panel variation",
		"base context night is not dark, light or any",
		"toggle ToyTabGone is not a live variation of its class",
	]
	for want in cases:
		var broken: Dictionary = _pack.duplicate(true)
		_plant(broken, want)
		var problems := "\n".join(Builder.check_pack(broken, _mapping))
		(
			assert_str(problems)
			. override_failure_message("planted: %s\ngot: %s" % [want, problems])
			. contains(want)
		)


func test_check_pack_names_a_bad_base_type() -> void:
	# Each planted mapping.base_types row (#576) and the problem it must cause.
	var cases := {
		"base type Bogus: not an engine Control or Window class": {"Bogus": {"from": "ToyField"}},
		"base type Node3D: not an engine Control or Window class":
		{"Node3D": {"constants": {"separation": 7}}},
		"base type LineEdit: neither from nor an item": {"LineEdit": {}},
		"base type LineEdit: member look is not one of": {"LineEdit": {"look": "ToyField"}},
		"base type HSlider: ToyField is not a live pack variation of HSlider":
		{"HSlider": {"from": "ToyField"}},
		"base type Label: ToyHowtoCaption is not a live pack variation of Label":
		{"Label": {"from": "ToyHowtoCaption"}},
		"base type Button: ToyButtonPrimary has a parent": {"Button": {"from": "ToyButtonPrimary"}},
		"base type Button: its styles normal would replace the default theme's on CheckBox":
		{"Button": {"from": "ToyButtonPrimary"}},
		"base type Button: its font_sizes font_size would replace the default theme's on CheckBox":
		{"Button": {"font_sizes": {"font_size": 27}}},
	}
	for want: String in cases:
		var broken: Dictionary = _mapping.duplicate(true)
		# CheckBox's own row (#1020) covers it: plant its gap by dropping that row.
		(broken["base_types"] as Dictionary).erase("CheckBox")
		(broken["base_types"] as Dictionary).merge(cases[want] as Dictionary, true)
		var problems := "\n".join(Builder.check_pack(_pack, broken))
		(
			assert_str(problems)
			. override_failure_message("planted: %s\ngot: %s" % [want, problems])
			. contains(want)
		)
	# A subclass's own row covers the item, so a row on the parent hides nothing there: give each
	# subclass the check names a row of its own and the problems go.
	var covered: Dictionary = _mapping.duplicate(true)
	var size := {"font_sizes": {"font_size": 27}}
	var rows: Dictionary = covered["base_types"]
	rows.erase("CheckBox")
	rows["Button"] = size
	var shadowed := Array(Builder.check_pack(_pack, covered)).filter(
		func(problem: String) -> bool: return problem.begins_with("base type Button:")
	)
	assert_array(shadowed).is_not_empty()
	for problem: String in shadowed:
		rows[problem.get_slice(" on ", 1)] = size
	assert_str("\n".join(Builder.check_pack(_pack, covered))).not_contains("base type Button:")
	_check_the_unbuilt_subclasses()
	_check_the_default_font_size()
	var inner: Dictionary = _mapping.duplicate(true)
	inner["engine_variations"] = {
		"SpinBoxInnerLineEdit": "TextEdit", "LineEdit": "Label", "Inner": "ToyPlate"
	}
	var found := "\n".join(Builder.check_pack(_pack, inner))
	assert_str(found).contains(
		"engine variation SpinBoxInnerLineEdit: TextEdit is not a base type or a live pack"
	)
	assert_str(found).contains("engine variation LineEdit: not letters only, an engine class")
	# ToyPlate is a live pack variation, but of PanelContainer, which is no base type.
	assert_str(found).contains("engine variation Inner: ToyPlate is not a base type or a live")


## The Button row (ToyButtonPlain, #1020) would give its look to the Button subclasses the game
## does not build; mapping.unbuilt names them, so the check skips them. Without that list the
## check names each, and an unbuilt name that is no engine class, or is a base type, is named.
func _check_the_unbuilt_subclasses() -> void:
	assert_array(_mapping["unbuilt"] as Array).contains_exactly_in_any_order(
		["CheckButton", "ColorPickerButton", "MenuButton"]
	)
	var listed := Array(Builder.check_pack(_pack, _mapping)).filter(
		func(problem: String) -> bool: return problem.begins_with("base type Button:")
	)
	assert_array(listed).is_empty()
	var unlisted: Dictionary = _mapping.duplicate(true)
	unlisted["unbuilt"] = []
	var named := {}
	for problem: String in Builder.check_pack(_pack, unlisted):
		if problem.begins_with("base type Button:"):
			named[problem.get_slice(" on ", 1)] = true
	assert_array(named.keys()).contains_exactly_in_any_order(
		["CheckButton", "ColorPickerButton", "MenuButton"]
	)
	var bad: Dictionary = _mapping.duplicate(true)
	bad["unbuilt"] = ["Bogus", "LineEdit"]
	var found := Array(Builder.check_pack(_pack, bad))
	(
		assert_array(found)
		. contains(
			[
				"unbuilt Bogus: not an engine class, or a base type",
				"unbuilt LineEdit: not an engine class, or a base type",
			]
		)
	)


## mapping.default_font_size names a pack token (#1020), a size at each text size.
func _check_the_default_font_size() -> void:
	var unknown: Dictionary = _mapping.duplicate(true)
	unknown["default_font_size"] = 27
	assert_array(Builder.check_pack(_pack, unknown)).contains(
		["default_font_size: 27 is not a pack token"]
	)
	var zero: Dictionary = _pack.duplicate(true)
	var large: Dictionary = (zero["modes"] as Dictionary)["textSize"]["large"]
	large["font.size.theme-default"] = {"type": "dimension", "px": 0}
	assert_array(Builder.check_pack(zero, _mapping)).contains(
		["default_font_size: font.size.theme-default is not a size (large text)"]
	)


## Breaks a copy of the pack the way the problem it must cause names.
func _plant(pack: Dictionary, problem: String) -> void:
	var tokens := _tokens(pack)
	match problem:
		"class Foo is not mapped":
			_variation(pack, "ToyPlate")["class"] = "Foo"
		"state hover-presed is not mapped":
			(_variation(pack, "ToyTab")["styleboxes"] as Array).append("hover-presed")
		"token tab.idle.items.bogus-color":
			tokens["tab.idle.items.bogus-color"] = {"type": "color"}
		"token tab.idle.normal.bg-colour":
			tokens["tab.idle.normal.bg-colour"] = {"type": "color"}
		"schema 2 is not in mapping.pack_schemas":
			pack["schema"] = 2
		"20 stops for 20 steps":
			tokens.erase("bar.health.ramp.stop-20")
		"texture bogus is not an icon of HSlider":
			(_variation(pack, "ToySlider")["textures"] as Dictionary)["bogus"] = "x"
		"texture grabber: res://assets/ui/toy_pack/icons/gone.svg is not imported":
			(_variation(pack, "ToySlider")["textures"] as Dictionary)["grabber"] = "icons/gone.svg"
		"the name is not letters only":
			_rename(pack, "ToyPlate", "ToyPlate2")
		"the name is also a legacy or kept name":
			_rename(pack, "ToyPlate", "HudText")
		"member shiny is not in mapping.variation_members":
			_variation(pack, "ToyPlate")["shiny"] = true
		"has a delay":
			(tokens["button.common.motion"] as Dictionary)["delayMs"] = 5
		"legacy LifeBar: ToyBarProgress is not a live pack variation":
			_variation(pack, "ToyBarProgress")["deprecated"] = {}
		"lacks bg-color (a StyleBox field)":
			var plate := _variation(pack, "ToyPlate")
			var state := str((plate["styleboxes"] as Array)[0])
			tokens.erase("%s.%s.bg-color" % [plate["prefix"], state])
		"base ToyBogus is not a live Panel variation":
			_variation(pack, "ToyButtonPrimary")["base"] = {"dark": "ToyBogus"}
		"base context night is not dark, light or any":
			_variation(pack, "ToyPanelMenu")["base"] = {"night": "ToyBasePanel"}
		"toggle ToyTabGone is not a live variation of its class":
			_variation(pack, "ToyTab")["toggle"] = {"selected": "ToyTabGone"}


func test_every_mapped_engine_item_exists_in_the_class_reference() -> void:
	assert_array(_unknown_items(_mapping)).is_empty()
	var broken: Dictionary = _mapping.duplicate(true)
	var items: Dictionary = broken["classes"]["Button"]["items"]
	(items["icon-hover-color"] as Dictionary)["name"] = "icon_hover_colour"
	var states: Dictionary = broken["classes"]["LineEdit"]["states"]
	states["read-only"] = "readonly"
	var press: Dictionary = broken["classes"]["Button"]["press"]
	press["depth"] = "h_separation"
	(broken["classes"]["HSlider"]["icons"] as Array).append("grabber_hilight")
	broken["base_types"]["VBoxContainer"] = {"constants": {"seperation": 7}}
	var found := "\n".join(_unknown_items(broken))
	assert_str(found).contains("Button colors icon_hover_colour")
	assert_str(found).contains("LineEdit styles readonly")
	assert_str(found).contains("Button custom constants h_separation shadows an engine item")
	assert_str(found).contains("HSlider icons grabber_hilight")
	assert_str(found).contains("base type VBoxContainer constants seperation")


func test_names_are_letters_only_and_no_engine_class() -> void:
	# The base types (#576) are the one place an engine class names a theme type, and each of
	# them is in both themes; every other name is still none.
	var base_types := Builder.base_type_names(_mapping)
	assert_array(Array(base_types)).contains(["LineEdit", "OptionButton", "HSlider"])
	var regex := RegEx.create_from_string(Builder.NAME_PATTERN)
	for key: String in ["default", "large"]:
		var types := _committed(key).get_type_list()
		for type_name in base_types:
			assert_bool(types.has(type_name)).override_failure_message(type_name).is_true()
			(
				assert_bool(ClassDB.class_exists(type_name))
				. override_failure_message(type_name)
				. is_true()
			)
		for type_name in types:
			assert_object(regex.search(type_name)).override_failure_message(type_name).is_not_null()
			(
				assert_bool(ClassDB.class_exists(type_name) and not base_types.has(type_name))
				. override_failure_message(type_name)
				. is_false()
			)


func test_base_types_share_the_toy_looks() -> void:
	var rows: Dictionary = _mapping["base_types"]
	for key: String in ["default", "large"]:
		var theme := _committed(key)
		for cls: String in rows:
			var row: Dictionary = rows[cls]
			if not row.has("from"):
				continue
			var from := str(row["from"])
			# Every item of the variation, the StyleBoxes the very objects (one sub-resource).
			for kind in Theme.DATA_TYPE_MAX:
				var items := theme.get_theme_item_list(kind, from)
				(
					assert_array(Array(theme.get_theme_item_list(kind, cls)))
					. override_failure_message("%s %s" % [cls, kind])
					. contains_exactly_in_any_order(Array(items))
				)
				for item in items:
					var theirs: Variant = theme.get_theme_item(kind, item, from)
					var ours: Variant = theme.get_theme_item(kind, item, cls)
					if theirs is Object:
						assert_object(ours).override_failure_message(cls + item).is_same(theirs)
					else:
						assert_that(ours).override_failure_message(cls + item).is_equal(theirs)
		# SpinBox's field is ToySpinField (#1020), a variation of LineEdit, so the row backs it.
		var inner := theme.get_type_variation_base(&"SpinBoxInnerLineEdit")
		assert_str(str(inner)).is_equal("ToySpinField")
		assert_str(str(theme.get_type_variation_base(inner))).is_equal("LineEdit")
		# The default font size is the pack's font.size.theme-default (#1020): 27, 34 in large text.
		assert_int(theme.default_font_size).is_equal(27 if key == "default" else 34)
		assert_int(theme.default_font_size).is_equal(
			Builder.default_font_size(_pack, _mapping, key)
		)
	for cls: String in ["Button", "CheckBox", "SpinBox"]:
		assert_bool(rows.has(cls)).override_failure_message(cls).is_true()
	assert_str(str((rows["Button"] as Dictionary)["from"])).is_equal("ToyButtonPlain")
	assert_str(str((rows["CheckBox"] as Dictionary)["from"])).is_equal("ToyCheckBox")
	assert_str(str((rows["SpinBox"] as Dictionary)["from"])).is_equal("ToySpinBox")
	var normal := _committed("default")
	assert_int(normal.get_font_size(&"font_size", &"LineEdit")).is_equal(22)
	assert_int(_committed("large").get_font_size(&"font_size", &"LineEdit")).is_greater(22)
	assert_int(normal.get_constant(&"separation", &"VBoxContainer")).is_equal(7)
	assert_int(normal.get_constant(&"line_spacing", &"Label")).is_equal(5)
	var text := FileAccess.get_file_as_string(_path("default"))
	assert_int(text.count('id="ToyField_normal"]')).is_equal(1)


func test_the_committed_themes_are_not_stale() -> void:
	var themes: Dictionary = _mapping["themes"]
	for key: String in themes:
		var spec: Dictionary = themes[key]
		var built := _text(_pack, str(spec["text_size"]))
		# Deterministic: a second build of the same pack writes the same text.
		assert_str(built).is_equal(_text(_pack, str(spec["text_size"])))
		var committed := Builder.without_uid(FileAccess.get_file_as_string(str(spec["path"])))
		(
			assert_str(_first_difference(committed, built))
			. override_failure_message(
				(
					"%s is stale at %s; regenerate it: %s"
					% [spec["path"], _first_difference(committed, built), REGENERATE]
				)
			)
			. is_empty()
		)
	var changed: Dictionary = _pack.duplicate(true)
	((_tokens(changed)["button.primary.normal.bg-color"] as Dictionary)["rgba"] as Array)[0] = 0.5
	var committed_default := Builder.without_uid(FileAccess.get_file_as_string(_path("default")))
	assert_str(_first_difference(committed_default, _text(changed, "default"))).contains(
		"Color(0.5,"
	)


## Two files of one name in two folders (icons/x.svg, icons/room/x.svg) get two ids in the saved
## theme (#520 review): one id for both would make the .tres invalid.
func test_external_ids_differ_for_one_file_name_in_two_folders() -> void:
	var theme := Theme.new()
	var first := PlaceholderTexture2D.new()
	first.resource_path = "res://tests/scratch/ids_a/x.svg"
	var second := PlaceholderTexture2D.new()
	second.resource_path = "res://tests/scratch/ids_b/x.svg"
	theme.set_icon(&"grabber", &"HSlider", first)
	theme.set_icon(&"arrow", &"OptionButton", second)
	var path := "res://tests/scratch/ids_theme.tres"
	Builder.name_external(theme, path)
	assert_str(first.get_id_for_path(path)).is_not_empty()
	assert_str(first.get_id_for_path(path)).is_not_equal(second.get_id_for_path(path))
	assert_str(first.get_id_for_path(path)).is_equal("tests_scratch_ids_a_x_svg")


func test_the_uids_are_kept() -> void:
	var themes: Dictionary = _mapping["themes"]
	assert_str(str((themes["default"] as Dictionary)["uid"])).is_equal(THEME_UID)
	for key: String in themes:
		var spec: Dictionary = themes[key]
		var path := str(spec["path"])
		var header := FileAccess.get_file_as_string(path).get_slice("\n", 0)
		assert_str(header).contains('uid="%s"' % spec["uid"])
		assert_int(ResourceLoader.get_resource_uid(path)).is_equal(
			ResourceUID.text_to_id(str(spec["uid"]))
		)
	assert_object(load(THEME_UID)).is_same(load(_path("default")))


func test_values_match_the_pack() -> void:
	var theme := _committed("default")
	var normal := theme.get_stylebox(&"normal", &"ToyButtonPrimary") as StyleBoxFlat
	assert_object(normal.bg_color).is_equal(Color(0.4353, 0.949, 0.7059, 1))
	assert_int(normal.border_width_bottom).is_equal(5)
	assert_int(normal.corner_radius_top_left).is_equal(9)
	assert_float(normal.content_margin_left).is_equal(21.0)
	assert_float(normal.content_margin_top).is_equal(14.0)
	var focus := theme.get_stylebox(&"focus", &"ToyButtonPrimary") as StyleBoxFlat
	assert_bool(focus.draw_center).is_false()
	assert_float(focus.expand_margin_left).is_equal(6.0)
	assert_int(theme.get_constant(&"width", &"ToySlot")).is_equal(132)
	# Since ui-2.0.0 the logo has no hard shadow: the pack's zero offset and clear colour (#1559).
	assert_int(theme.get_constant(&"shadow_offset_y", &"ToyLogo")).is_equal(0)
	assert_object(theme.get_color(&"font_shadow_color", &"ToyLogo")).is_equal(Color(0, 0, 0, 0))
	assert_object(theme.get_stylebox(&"normal", &"ToyTextOnDark")).is_instanceof(StyleBoxEmpty)
	assert_object(theme.get_stylebox(&"background", &"ToyBarHealth")).is_instanceof(StyleBoxEmpty)
	assert_object(theme.get_color(&"icon_on", &"ToyMic")).is_equal(Color(0.9255, 0.9098, 0.9686, 1))
	assert_int(theme.get_constant(&"modulate_arrow", &"ToyDropdown")).is_equal(1)
	assert_object(theme.get_color(&"font_uneditable_color", &"ToyField")).is_not_null()
	# The pack's textures are theme icons (#520), loaded from the imported copy at its import scale.
	var knob := theme.get_icon(&"grabber", &"ToySlider")
	assert_str(knob.resource_path).is_equal("res://assets/ui/toy_pack/icons/slider-knob.svg")
	# ui-2.x's knob is a 21 x 42 pill (svg_scale 1).
	assert_object(knob.get_size()).is_equal(Vector2(21, 42))
	assert_object(theme.get_icon(&"grabber_highlight", &"ToySlider")).is_same(knob)
	assert_str(theme.get_icon(&"grabber_disabled", &"ToySlider").resource_path).ends_with(
		"/slider-knob-disabled.svg"
	)
	assert_str(theme.get_icon(&"arrow", &"ToyDropdown").resource_path).ends_with(
		"/chevron-down.svg"
	)
	(
		assert_str(theme.get_icon(&"radio_unchecked_disabled", &"ToyDropdownList").resource_path)
		. ends_with("/radio-unchecked.svg")
	)
	# Exactly the pack's textures: no other type has an icon but the base types that copy them.
	var with_icons := []
	for type_name in theme.get_type_list():
		if not theme.get_icon_list(type_name).is_empty():
			with_icons.append(str(type_name))
	with_icons.sort()
	(
		assert_array(with_icons)
		. contains_exactly(
			[
				"CheckBox",
				"HSlider",
				"OptionButton",
				"PopupMenu",
				"SpinBox",
				"ToyCheckBox",
				"ToyDropdown",
				"ToyDropdownList",
				"ToySlider",
				"ToySpinBox",
			]
		)
	)
	# The CheckBox and SpinBox icons (#1020), at svg_scale 1: at ui-2.5.4 the box 42 px, the
	# chevrons 27 px.
	var box := theme.get_icon(&"unchecked_disabled", &"ToyCheckBox")
	assert_str(box.resource_path).ends_with("/checkbox-unchecked-disabled.svg")
	assert_object(box.get_size()).is_equal(Vector2(42, 42))
	var up := theme.get_icon(&"up_pressed", &"ToySpinBox")
	assert_str(up.resource_path).ends_with("/spin-up.svg")
	assert_object(up.get_size()).is_equal(Vector2(27, 27))
	assert_str(theme.get_icon(&"down_disabled", &"ToySpinBox").resource_path).ends_with(
		"/spin-down.svg"
	)
	assert_int(theme.get_constant(&"buttons_width", &"ToySpinBox")).is_equal(51)
	assert_int(theme.get_constant(&"h_separation", &"ToyCheckBox")).is_equal(12)


func test_the_press_motion_and_the_ramp() -> void:
	var theme := _committed("default")
	assert_int(theme.get_constant(&"press_duration_ms", &"ToyButton")).is_equal(70)
	assert_int(theme.get_constant(&"press_duration_reduced_ms", &"ToyButton")).is_equal(0)
	assert_int(theme.get_constant(&"press_trans", &"ToyButton")).is_equal(Tween.TRANS_SINE)
	assert_int(theme.get_constant(&"press_ease", &"ToyButton")).is_equal(Tween.EASE_OUT)
	# Since ui-2.0.0 a button does not sink (button.common.press.depth 0, #1559).
	assert_int(theme.get_constant(&"press_depth", &"ToyButtonPrimary")).is_equal(0)
	var button: Button = auto_free(Button.new())
	button.theme = theme
	button.theme_type_variation = &"ToyButtonPrimary"
	add_child(button)
	assert_int(button.get_theme_constant(&"press_duration_ms")).is_equal(70)
	assert_int(button.get_theme_constant(&"press_depth")).is_equal(0)
	var tokens := _tokens(_pack)
	for index in 21:
		var item := "ramp_stop_%02d" % index
		var rgba: Array = (tokens["bar.health.ramp.stop-%02d" % index] as Dictionary)["rgba"]
		var want := Color(rgba[0] as float, rgba[1] as float, rgba[2] as float, rgba[3] as float)
		assert_object(theme.get_color(item, &"ToyBarHealth")).is_equal(want)
	assert_bool(theme.has_color(&"ramp_stop_21", &"ToyBarHealth")).is_false()


func test_the_large_theme_differs_only_in_text_sizes() -> void:
	var normal := _committed("default")
	var large := _committed("large")
	assert_int(normal.get_font_size(&"font_size", &"ToyButtonPrimary")).is_equal(22)
	assert_int(large.get_font_size(&"font_size", &"ToyButtonPrimary")).is_equal(28)
	assert_int(normal.get_constant(&"min_width", &"ToyKeyOnDark")).is_equal(42)
	assert_int(large.get_constant(&"min_width", &"ToyKeyOnDark")).is_equal(50)
	assert_int(large.get_constant(&"wide_min_width", &"ToyKeyButton")).is_equal(144)
	assert_int(large.get_font_size(&"font_size", &"ToyLogo")).is_equal(78)
	assert_array(Array(large.get_type_list())).contains_exactly_in_any_order(
		Array(normal.get_type_list())
	)
	var lines_normal := FileAccess.get_file_as_string(_path("default")).split("\n")
	var lines_large := FileAccess.get_file_as_string(_path("large")).split("\n")
	assert_int(lines_large.size()).is_equal(lines_normal.size())
	for index in range(1, lines_normal.size()):
		if lines_normal[index] != lines_large[index]:
			(
				assert_bool(
					(
						lines_normal[index].contains("/font_sizes/font_size")
						# font.size.theme-default has a large value since ui-0.7.0 (#1020).
						or lines_normal[index].begins_with("default_font_size = ")
						or lines_normal[index].contains("/constants/min_width")
						# A Label's spacing follows its text size (#685; the line spacing test).
						or lines_normal[index].contains("/constants/line_spacing")
					)
				)
				. override_failure_message(lines_normal[index])
				. is_true()
			)


func test_the_hints_are_in_both_themes() -> void:
	var hints := Builder.hints(_pack)
	var bases: Dictionary = hints["bases"]
	var toggles: Dictionary = hints["toggles"]
	# Since ui-2.0.0 the plain tile has no hard shadow, so no variation has a base (#1559).
	assert_dict(bases).is_empty()
	(
		assert_dict(toggles)
		. is_equal(
			{
				"ToyChipToggleOnDark": "ToyChipToggleOnDarkSelected",
				"ToyChipToggleOnLight": "ToyChipToggleOnLightSelected",
				"ToyPresetCard": "ToyPresetCardSelected",
				"ToyRadio": "ToyRadioSelected",
				"ToySegmentEnd": "ToySegmentEndSelected",
				"ToySegmentStart": "ToySegmentStartSelected",
				"ToyTab": "ToyTabSelected",
			}
		)
	)
	var meta := StringName(str((_mapping["hints"] as Dictionary)["meta"]))
	for key: String in _mapping["themes"]:
		var theme := _committed(key)
		assert_dict(theme.get_meta(meta, {}) as Dictionary).is_equal(hints)
		for variation: String in bases:
			for context: String in bases[variation]:
				var base := StringName(str((bases[variation] as Dictionary)[context]))
				assert_str(str(theme.get_type_variation_base(base))).is_equal("Panel")
		for variation: String in toggles:
			var selected := StringName(str(toggles[variation]))
			assert_str(str(theme.get_type_variation_base(selected))).is_equal(
				str(theme.get_type_variation_base(StringName(variation)))
			)
	# The stale test sees a changed hint.
	var changed: Dictionary = _pack.duplicate(true)
	_variation(changed, "ToyTab")["toggle"] = {"selected": "ToyRadioSelected"}
	var committed := Builder.without_uid(FileAccess.get_file_as_string(_path("default")))
	assert_str(_first_difference(committed, _text(changed, "default"))).contains("ToyRadioSelected")


func test_legacy_names_are_thin_variations_of_toy_ones() -> void:
	var theme := _committed("default")
	var legacy: Dictionary = _mapping["legacy"]
	assert_int(legacy.size()).is_equal(18)
	for type_name: String in legacy:
		var entry: Dictionary = legacy[type_name]
		assert_str(str(theme.get_type_variation_base(type_name))).is_equal(str(entry["variation"]))
		assert_str(_engine_class(theme, type_name)).override_failure_message(type_name).is_equal(
			str(entry["base"])
		)
		if type_name != "LifeBar":
			(
				assert_array(Array(theme.get_stylebox_list(type_name)))
				. override_failure_message(type_name)
				. is_empty()
			)
			(
				assert_array(Array(theme.get_font_size_list(type_name)))
				. override_failure_message(type_name)
				. is_empty()
			)
	# A hint reads below the text it explains (HudHint under HudText, the lobby and the HUD).
	assert_int(theme.get_font_size(&"font_size", &"ToyHudCaption")).is_less(
		theme.get_font_size(&"font_size", &"ToyTextOnDark")
	)
	var bar := theme.get_stylebox(&"background", &"LifeBar")
	assert_float(bar.get_minimum_size().x).is_greater(100.0)
	assert_bool(theme.has_stylebox(&"fill", &"LifeBar")).is_false()
	var keep: Dictionary = _mapping["keep"]
	for type_name: String in keep:
		assert_str(_engine_class(theme, type_name)).is_equal(
			str((keep[type_name] as Dictionary)["base"])
		)
	assert_int(theme.get_constant(&"margin_bottom", &"LifeMargin")).is_equal(160)
	assert_object(theme.get_color(&"font_color", &"Shortfalls")).is_equal(Color(1, 0.75, 0.4, 1))


func test_the_base_must_be_the_packs_reference() -> void:
	assert_str(Builder.base_problem(_pack, 1152, 648)).contains("1920x1080")
	assert_str(Builder.base_problem(_pack, 1920, 1080)).is_empty()
	# build_theme.gd stops on this; here CI holds it, so the project and the pack cannot drift apart.
	var width := ProjectSettings.get_setting("display/window/size/viewport_width") as int
	var height := ProjectSettings.get_setting("display/window/size/viewport_height") as int
	assert_str(Builder.base_problem(_pack, width, height)).is_empty()


func test_the_committed_themes_have_the_fonts_only_once_they_are_in_the_project() -> void:
	var families: Dictionary = (_mapping["font"] as Dictionary)["families"]
	# Since ui-2.0.0 the pack draws in two families (#1559), each the pack's own TTF.
	assert_array(families.keys()).contains_exactly_in_any_order(["Onest", "Unbounded"])
	for family: String in families:
		assert_str(str((families[family] as Dictionary)["file"])).is_equal(
			"res://assets/ui/toy_pack/fonts/%s-VariableFont_wght.ttf" % family
		)
	var present := Builder.base_fonts(_mapping)
	for key: String in ["default", "large"]:
		var theme := _committed(key)
		# The pack's font.size.theme-default (#1020; test_base_types_share_the_toy_looks).
		assert_int(theme.default_font_size).is_equal(27 if key == "default" else 34)
		if present.is_empty():
			# A checkout without the files: no font, Godot's default draws.
			assert_object(theme.default_font).is_null()
			for type_name in theme.get_type_list():
				(
					assert_array(Array(theme.get_font_list(type_name)))
					. override_failure_message(type_name)
					. is_empty()
				)
			continue
		var default_font := theme.default_font as FontVariation
		assert_object(default_font).is_not_null()
		assert_str(default_font.base_font.resource_path).is_equal(
			str((families["Onest"] as Dictionary)["file"])
		)
		var logo := theme.get_font(&"font", &"ToyLogo") as FontVariation
		assert_str(logo.base_font.resource_path).is_equal(
			str((families["Unbounded"] as Dictionary)["file"])
		)


func test_the_font_becomes_a_variation_per_label_family_and_weight() -> void:
	var onest := ThemeDB.fallback_font
	var unbounded := FontVariation.new()
	unbounded.base_font = ThemeDB.fallback_font
	var stand_ins := {"Onest": onest, "Unbounded": unbounded}
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	# The OpenType tag itself, not only what the builder's own call returns (#520 review): a text
	# server that cannot map the name would give both sides the same wrong key.
	assert_int(wght).is_equal(0x77676874)
	for text_size: String in ["default", "large"]:
		var theme := Builder.build_with_fonts(_pack, _mapping, text_size, stand_ins)
		var body := theme.default_font as FontVariation
		# The default font is type.body's: Onest Medium 500; bold labels take 700, titles Unbounded.
		assert_object(body.base_font).is_same(onest)
		assert_object(body.variation_opentype).is_equal({wght: 500})
		var bold := theme.get_font(&"font", &"ToyButtonPrimary") as FontVariation
		assert_object(bold.variation_opentype).is_equal({wght: 700})
		var logo := theme.get_font(&"font", &"ToyLogo") as FontVariation
		assert_object(logo.base_font).is_same(unbounded)
		assert_object(logo.variation_opentype).is_equal({wght: 700})
		assert_object(theme.get_font(&"font", &"ToyTextOnDark")).is_not_null()
		# One object per family and weight, shared by every label of it and by the base types.
		var made := {}
		for type_name in theme.get_type_list():
			for item in theme.get_font_list(type_name):
				var variation := theme.get_font(item, type_name) as FontVariation
				made[variation.resource_scene_unique_id] = variation
				assert_bool(stand_ins.values().has(variation.base_font)).is_true()
		assert_array(made.keys()).contains_exactly_in_any_order(
			["Onest_wght_500", "Onest_wght_700", "Unbounded_wght_700"]
		)
		assert_object(theme.get_font(&"font", &"LineEdit")).is_same(
			theme.get_font(&"font", &"ToyField")
		)
		# Every variation with a label gets the font of its label token's family and weight.
		var tokens := _tokens(_pack)
		var owned := Builder.tokens_by_variation(_pack)
		for variation_name in Builder.generated_names(_pack, _mapping):
			var variation := _variation(_pack, variation_name)
			var key := "%s.label" % variation["prefix"]
			if not (owned[variation_name] as Array).has(key):
				continue
			var record: Dictionary = tokens[key]
			var got := theme.get_font(&"font", variation_name) as FontVariation
			(
				assert_object(got.variation_opentype)
				. override_failure_message("%s: %s" % [variation_name, got.variation_opentype])
				. is_equal({wght: record["fontWeight"] as int})
			)
			(
				assert_object(got.base_font)
				. override_failure_message("%s: %s" % [variation_name, record["fontFamily"]])
				. is_same(stand_ins[record["fontFamily"]])
			)
	# Without the files, the build writes no font at all.
	var none := Builder.build_with_fonts(_pack, _mapping, "default", {})
	assert_object(none.default_font).is_null()
	assert_array(Array(none.get_font_list(&"ToyButtonPrimary"))).is_empty()


## A deprecated_in_use name that is not a deprecated pack variation stops the build (#1559): the
## pack's next major release removes them, and the screens must move first.
func test_check_pack_names_a_kept_variation_that_is_not_deprecated() -> void:
	var mapping := _mapping.duplicate(true)
	((mapping["deprecated_in_use"] as Dictionary)["names"] as Array).append("ToyPlate")
	((mapping["deprecated_in_use"] as Dictionary)["names"] as Array).append("ToyGone")
	var problems := Builder.check_pack(_pack, mapping)
	(
		assert_array(Array(problems))
		. contains(
			[
				"deprecated_in_use ToyPlate: not a deprecated pack variation",
				"deprecated_in_use ToyGone: not a deprecated pack variation",
			]
		)
	)


## A label in a family the mapping has no font for stops the build (#1559), and so does a default
## token in one.
func test_check_pack_names_a_font_family_the_mapping_lacks() -> void:
	var pack := _pack.duplicate(true)
	((pack["tokens"] as Dictionary)["text.on-dark.label"] as Dictionary)["fontFamily"] = "Comic"
	var mapping := _mapping.duplicate(true)
	(mapping["font"] as Dictionary)["default"] = "title.plate.label"
	((mapping["font"] as Dictionary)["families"] as Dictionary).erase("Unbounded")
	var problems := "\n".join(Builder.check_pack(pack, mapping))
	assert_str(problems).contains(
		"variation ToyTextOnDark: token text.on-dark.label has the font family Comic, which is not"
	)
	assert_str(problems).contains(
		"font: the default token title.plate.label has the font family Unbounded, which is not"
	)


## Each Label variation's line is its label token's lineHeight tall with its family's font (#685):
## the spacing comes from the committed metrics, so a build with CI's stand-in font writes the
## same value; where the real fonts are in the project, their own heights must give that line.
func test_label_line_spacing_meets_the_token_line_height() -> void:
	var stand_in := ThemeDB.fallback_font
	var stand_ins := {"Onest": stand_in, "Unbounded": stand_in}
	# Spot values (#1559): ui-2.x's line heights are the fonts' own (Onest 22 px x 1.275 = 28.05,
	# a 28 px line, under Godot's ascent 22 plus descent 7, each rounded up), so the spacing is the
	# rounding: -1, or 0 where the line rounds the other way.
	var spots := {
		"default": {&"ToyTextOnDark": -1, &"ToyTitleOnDark": 0, &"ToyTitlePlate": -1},
		"large": {&"ToyTextOnDark": -1, &"ToyTitleOnDark": -1},
	}
	var families: Dictionary = (_mapping["font"] as Dictionary)["families"]
	var real := Builder.base_fonts(_mapping)
	var is_real := not real.is_empty()
	for family: String in real:
		is_real = is_real and (real[family] as FontFile).font_name == family
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	if is_real:
		# The committed metrics are each real font's (measured at size 1000).
		for family: String in families:
			var metrics: Dictionary = (families[family] as Dictionary)["metrics"]
			var at: int = metrics["size"]
			var ascent: float = metrics["ascent"]
			var descent: float = metrics["descent"]
			assert_float((real[family] as Font).get_ascent(at)).is_equal(ascent)
			assert_float((real[family] as Font).get_descent(at)).is_equal(descent)
	for text_size: String in spots:
		var theme := Builder.build_with_fonts(_pack, _mapping, text_size, stand_ins)
		var spot: Dictionary = spots[text_size]
		for type_name: StringName in spot:
			assert_int(theme.get_constant(&"line_spacing", type_name)).is_equal(spot[type_name])
		var tokens := _tokens(_pack)
		var large: Dictionary = ((_pack["modes"] as Dictionary)["textSize"] as Dictionary)["large"]
		var owned := Builder.tokens_by_variation(_pack)
		var checked := 0
		for variation_name in Builder.generated_names(_pack, _mapping):
			var key := "%s.label" % _variation(_pack, variation_name)["prefix"]
			if _engine_class(theme, variation_name) != "Label":
				continue
			if not (owned[variation_name] as Array).has(key):
				continue
			checked += 1
			var record: Dictionary = tokens[key]
			if text_size == "large" and large.has(key):
				record = large[key]
			var size: int = record["fontSizePx"]
			var line_height: float = record["lineHeight"]
			var weight: int = record["fontWeight"]
			var line := roundi(size * line_height)
			var spacing := theme.get_constant(&"line_spacing", variation_name)
			if is_real:
				var face := FontVariation.new()
				face.base_font = real[record["fontFamily"]]
				face.variation_opentype = {wght: weight}
				(
					assert_int(roundi(face.get_height(size)) + spacing)
					. override_failure_message("%s %s at %d" % [text_size, variation_name, size])
					. is_equal(line)
				)
			# Exactly the line less its family's committed ascent and descent at that size, each
			# rounded up (#1559: since ui-2.x the line heights are the fonts' own, so the spacing is
			# the rounding and may be below 0, which the bound 0 to the line held before).
			var metrics: Dictionary = (families[record["fontFamily"]] as Dictionary)["metrics"]
			var per: int = metrics["size"]
			var up_ascent := ceili(size * (metrics["ascent"] as int) / float(per))
			var up_descent := ceili(size * (metrics["descent"] as int) / float(per))
			(
				assert_int(spacing)
				. override_failure_message("%s %s" % [text_size, variation_name])
				. is_equal(line - up_ascent - up_descent)
			)
			assert_int(spacing).is_less(line)
		assert_int(checked).is_greater(20)
	# No font in the project: no spacing either, so Godot's default font keeps the base Label's.
	var none := Builder.build_with_fonts(_pack, _mapping, "default", {})
	assert_bool(none.has_constant(&"line_spacing", &"ToyTextOnDark")).is_false()


## Engine items the mapping writes that Godot's default theme does not list for the class (or a
## class it inherits) and the mapping's not_in_default_theme does not name; and custom items that
## shadow an engine item; and the literal items of the base types (#576) the default theme does not
## list for their class.
func _unknown_items(mapping: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	var rows: Dictionary = mapping.get("base_types", {})
	for cls: String in rows:
		for kind: String in ["constants", "font_sizes", "colors"]:
			var known := _default_items(cls, kind)
			for item: String in (rows[cls] as Dictionary).get(kind, {}) as Dictionary:
				if not known.has(item):
					found.append("base type %s %s %s" % [cls, kind, item])
	var listed: Dictionary = mapping.get("not_in_default_theme", {})
	for cls: String in mapping["classes"] as Dictionary:
		var engine := Builder.engine_items(mapping, cls)
		var extra: Dictionary = listed.get(cls, {})
		for kind: String in engine:
			var known := _default_items(cls, kind)
			for item: String in engine[kind]:
				if not known.has(item) and not (extra.get(kind, []) as Array).has(item):
					found.append("%s %s %s" % [cls, kind, item])
			# The list holds only what the default theme leaves out, or it hides nothing.
			for item: String in extra.get(kind, []) as Array:
				if known.has(item):
					found.append("%s %s %s is in the default theme" % [cls, kind, item])
		var custom := Builder.custom_items(mapping, cls)
		for kind: String in custom:
			var known := _default_items(cls, kind)
			for item: String in custom[kind]:
				if known.has(item):
					found.append("%s custom %s %s shadows an engine item" % [cls, kind, item])
	return found


func _default_items(cls: String, kind: String) -> PackedStringArray:
	var theme := ThemeDB.get_default_theme()
	var items := PackedStringArray()
	var type := cls
	while not type.is_empty():
		match kind:
			"styles":
				items.append_array(theme.get_stylebox_list(type))
			"colors":
				items.append_array(theme.get_color_list(type))
			"constants":
				items.append_array(theme.get_constant_list(type))
			"font_sizes":
				items.append_array(theme.get_font_size_list(type))
			"icons":
				items.append_array(theme.get_icon_list(type))
		type = ClassDB.get_parent_class(type)
	return items


func _engine_class(theme: Theme, type_name: String) -> String:
	var type := type_name
	while not ClassDB.class_exists(type) and not type.is_empty():
		type = str(theme.get_type_variation_base(type))
	return type


func _text(pack: Dictionary, text_size: String) -> String:
	return Builder.text_of(Builder.build(pack, _mapping, text_size), SCRATCH)


func _first_difference(want: String, got: String) -> String:
	var a := want.split("\n")
	var b := got.split("\n")
	for index in maxi(a.size(), b.size()):
		var left := a[index] if index < a.size() else "<end>"
		var right := b[index] if index < b.size() else "<end>"
		if left != right:
			return "line %d: %s -> %s" % [index + 1, left, right]
	return ""


func _committed(key: String) -> Theme:
	return load(_path(key)) as Theme


func _path(key: String) -> String:
	return str(((_mapping["themes"] as Dictionary)[key] as Dictionary)["path"])


func _variation(pack: Dictionary, type_name: String) -> Dictionary:
	return (pack["variations"] as Dictionary)[type_name]


func _tokens(pack: Dictionary) -> Dictionary:
	return pack["tokens"]


func _rename(pack: Dictionary, from: String, to: String) -> void:
	var variations: Dictionary = pack["variations"]
	variations[to] = variations[from]
	variations.erase(from)
