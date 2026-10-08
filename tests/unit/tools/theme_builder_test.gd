extends GdUnitTestSuite
## The generated theme (#288): tools/theme/theme_builder.gd turns the pinned UI pack
## (client/ui/theme/pack/, ui-sync) into game_theme.tres and game_theme_large.tres through
## tools/theme/mapping.json. Every pack variation is mapped and every mapped engine item exists in
## the 4.7.2 class reference (Godot's default theme, or the mapping's list of items it binds but
## does not set); names are letters only; the committed files are what a fresh build writes (the
## stale test, with a planted change that must show); the uid is kept; spot values, the press
## motion and the ramp; the large-text theme; the legacy and kept names. Each check that guards
## data is also run on a broken copy and must name it.

const Builder := preload("res://tools/theme/theme_builder.gd")
const THEME_UID := "uid://c8behqt7jtcn8"
const SCRATCH := "user://theme_builder_test.tres"
const REGENERATE := "tools\\run.cmd run tools/theme/build_theme.gd --headless"
const DEPRECATED: Array[String] = ["ToyChipNew", "ToyChipNewText", "ToyHowtoCaption"]

var _mapping: Dictionary
var _pack: Dictionary


func before() -> void:
	_mapping = Builder.load_mapping()
	_pack = Builder.load_pack(_mapping)


func test_every_pack_variation_is_mapped() -> void:
	assert_bool(_pack.is_empty()).override_failure_message("no pinned pack").is_false()
	assert_array(Builder.check_pack(_pack, _mapping)).is_empty()
	var generated := Builder.generated_names(_pack)
	assert_int(generated.size() + DEPRECATED.size()).is_equal(
		(_pack["variations"] as Dictionary).size()
	)
	assert_array(Array(Builder.deprecated_names(_pack))).contains_exactly(DEPRECATED)
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
		"the name is not letters only",
		"the name is also a legacy or kept name",
		"member shiny is not in mapping.variation_members",
		"has a delay",
		"legacy LifeBar: ToyBarProgress is not a live pack variation",
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


func test_every_mapped_engine_item_exists_in_the_class_reference() -> void:
	assert_array(_unknown_items(_mapping)).is_empty()
	var broken: Dictionary = _mapping.duplicate(true)
	var items: Dictionary = broken["classes"]["Button"]["items"]
	(items["icon-hover-color"] as Dictionary)["name"] = "icon_hover_colour"
	var states: Dictionary = broken["classes"]["LineEdit"]["states"]
	states["read-only"] = "readonly"
	var press: Dictionary = broken["classes"]["Button"]["press"]
	press["depth"] = "h_separation"
	var found := "\n".join(_unknown_items(broken))
	assert_str(found).contains("Button colors icon_hover_colour")
	assert_str(found).contains("LineEdit styles readonly")
	assert_str(found).contains("Button custom constants h_separation shadows an engine item")


func test_names_are_letters_only_and_no_engine_class() -> void:
	var regex := RegEx.create_from_string(Builder.NAME_PATTERN)
	for key: String in ["default", "large"]:
		for type_name in _committed(key).get_type_list():
			assert_object(regex.search(type_name)).override_failure_message(type_name).is_not_null()
			(
				assert_bool(ClassDB.class_exists(type_name))
				. override_failure_message(type_name)
				. is_false()
			)


func test_the_committed_themes_are_not_stale() -> void:
	var themes: Dictionary = _mapping["themes"]
	for key: String in themes:
		var spec: Dictionary = themes[key]
		var built := _text(_pack, str(spec["text_size"]))
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
	assert_object(normal.bg_color).is_equal(Color(1, 0.7608, 0.2275, 1))
	assert_int(normal.border_width_bottom).is_equal(3)
	assert_int(normal.corner_radius_top_left).is_equal(18)
	assert_float(normal.content_margin_left).is_equal(22.0)
	assert_float(normal.content_margin_top).is_equal(12.0)
	var focus := theme.get_stylebox(&"focus", &"ToyButtonPrimary") as StyleBoxFlat
	assert_bool(focus.draw_center).is_false()
	assert_float(focus.expand_margin_left).is_equal(-3.0)
	assert_int(theme.get_constant(&"width", &"ToySlot")).is_equal(88)
	assert_int(theme.get_constant(&"shadow_offset_y", &"ToyLogo")).is_equal(6)
	assert_object(theme.get_color(&"font_shadow_color", &"ToyLogo")).is_equal(
		Color(1, 0.5176, 0.4, 1)
	)
	assert_object(theme.get_stylebox(&"normal", &"ToyTextOnDark")).is_instanceof(StyleBoxEmpty)
	assert_object(theme.get_stylebox(&"background", &"ToyBarHealth")).is_instanceof(StyleBoxEmpty)
	assert_object(theme.get_color(&"icon_on", &"ToyMic")).is_equal(Color(1, 0.9569, 0.8863, 1))
	assert_int(theme.get_constant(&"modulate_arrow", &"ToyDropdown")).is_equal(1)
	assert_object(theme.get_color(&"font_uneditable_color", &"ToyField")).is_not_null()
	# No theme icon yet: the pack's textures are deferred to #520 (mapping.json "textures").
	for type_name in theme.get_type_list():
		(
			assert_array(Array(theme.get_icon_list(type_name)))
			. override_failure_message(type_name)
			. is_empty()
		)


func test_the_press_motion_and_the_ramp() -> void:
	var theme := _committed("default")
	assert_int(theme.get_constant(&"press_duration_ms", &"ToyButton")).is_equal(70)
	assert_int(theme.get_constant(&"press_duration_reduced_ms", &"ToyButton")).is_equal(0)
	assert_int(theme.get_constant(&"press_trans", &"ToyButton")).is_equal(Tween.TRANS_SINE)
	assert_int(theme.get_constant(&"press_ease", &"ToyButton")).is_equal(Tween.EASE_OUT)
	assert_int(theme.get_constant(&"press_depth", &"ToyButtonPrimary")).is_equal(6)
	var button: Button = auto_free(Button.new())
	button.theme = theme
	button.theme_type_variation = &"ToyButtonPrimary"
	add_child(button)
	assert_int(button.get_theme_constant(&"press_duration_ms")).is_equal(70)
	assert_int(button.get_theme_constant(&"press_depth")).is_equal(6)
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
	assert_int(normal.get_font_size(&"font_size", &"ToyButtonPrimary")).is_equal(24)
	assert_int(large.get_font_size(&"font_size", &"ToyButtonPrimary")).is_equal(30)
	assert_int(normal.get_constant(&"min_width", &"ToyKeyOnDark")).is_equal(36)
	assert_int(large.get_constant(&"min_width", &"ToyKeyOnDark")).is_equal(42)
	assert_int(large.get_constant(&"wide_min_width", &"ToyKeyButton")).is_equal(96)
	assert_int(large.get_font_size(&"font_size", &"ToyLogo")).is_equal(64)
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
						or lines_normal[index].contains("/constants/min_width")
					)
				)
				. override_failure_message(lines_normal[index])
				. is_true()
			)


func test_legacy_names_are_thin_variations_of_toy_ones() -> void:
	var theme := _committed("default")
	var legacy: Dictionary = _mapping["legacy"]
	assert_int(legacy.size()).is_equal(16)
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


func test_the_font_hook_waits_for_520() -> void:
	var font: Dictionary = _mapping["font"]
	assert_str(str(font["family"])).is_equal("Comfortaa")
	assert_object(font["file"]).is_null()
	var theme := _committed("default")
	assert_object(theme.default_font).is_null()
	assert_int(theme.default_font_size).is_equal(-1)
	for type_name in theme.get_type_list():
		(
			assert_array(Array(theme.get_font_list(type_name)))
			. override_failure_message(type_name)
			. is_empty()
		)


## Engine items the mapping writes that Godot's default theme does not list for the class (or a
## class it inherits) and the mapping's not_in_default_theme does not name; and custom items that
## shadow an engine item.
func _unknown_items(mapping: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
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
