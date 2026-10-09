extends RefCounted
## Builds the game's Theme from the UI pack (#288): client/ui/theme/pack/toy.pack.json (pinned by
## `ui-sync`) through tools/theme/mapping.json (the engine knowledge: which Godot 4.7.2 theme item
## each pack field becomes). Static and in memory, so build_theme.gd (which writes the files) and
## the tests (which rebuild the theme and compare it with the committed one) share one path.
## No editor and no scene: it reads two JSON files and returns Theme objects.

const MAPPING_PATH := "res://tools/theme/mapping.json"
## The theme test's pattern for a variation name (tests/unit/client/ui/theme_test.gd).
const NAME_PATTERN := "^[A-Za-z]+$"
## One StyleBoxEmpty serves every `empty` state; its sub-resource id in the file.
const EMPTY_ID := "StyleBoxEmpty_empty"
const INT_FIELDS: Array[String] = [
	"border_width_left",
	"border_width_top",
	"border_width_right",
	"border_width_bottom",
	"corner_radius_top_left",
	"corner_radius_top_right",
	"corner_radius_bottom_right",
	"corner_radius_bottom_left",
]
## What a mapping.base_types row may hold (#576): a pack variation to copy, or literal items.
const BASE_TYPE_MEMBERS: Array[String] = ["from", "constants", "font_sizes", "colors"]


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data as Dictionary if data is Dictionary else {}


static func load_mapping() -> Dictionary:
	return load_json(MAPPING_PATH)


static func load_pack(mapping: Dictionary) -> Dictionary:
	return load_json(str(mapping.get("pack", "")))


## "" when the project's UI base is the size the pack is drawn at, else what is wrong (#287).
static func base_problem(pack: Dictionary, width: int, height: int) -> String:
	var drawn_at: Dictionary = _dict(pack, "reference")
	var want := Vector2i(_int(drawn_at.get("width", 0)), _int(drawn_at.get("height", 0)))
	if want == Vector2i(width, height):
		return ""
	return (
		"the UI base is %dx%d, but the pack is drawn at %dx%d (#287 sets the base)"
		% [width, height, want.x, want.y]
	)


## The variations the theme gets: every pack variation except the deprecated ones, sorted.
static func generated_names(pack: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	var variations: Dictionary = _dict(pack, "variations")
	for name: String in variations:
		if not _dict(variations, name).has("deprecated"):
			names.append(name)
	names.sort()
	return names


## The engine classes the theme styles under their own name (mapping.base_types, #576), sorted:
## a bare control of such a class takes the Toy look with no variation set.
static func base_type_names(mapping: Dictionary) -> PackedStringArray:
	var names := PackedStringArray(_dict(mapping, "base_types").keys())
	names.sort()
	return names


static func deprecated_names(pack: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	var variations: Dictionary = _dict(pack, "variations")
	for name: String in variations:
		if _dict(variations, name).has("deprecated"):
			names.append(name)
	names.sort()
	return names


## Every problem that stops the build: an unknown pack, a variation, state, token or texture the
## mapping does not cover, a bad name, a broken ramp or motion, a legacy or kept name that clashes.
## Empty when the pack can be built.
static func check_pack(pack: Dictionary, mapping: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	if pack.get("format") != "prime-game-ui/pack":
		problems.append("pack: format %s is not prime-game-ui/pack" % pack.get("format"))
	if not _array(mapping, "pack_schemas").has(pack.get("schema")):
		problems.append("pack: schema %s is not in mapping.pack_schemas" % pack.get("schema"))
	var variations: Dictionary = _dict(pack, "variations")
	if variations.is_empty():
		problems.append("pack: no variations")
	var members: Dictionary = _dict(mapping, "variation_members")
	var known_members: Array = (
		_array(members, "used")
		+ _array(members, "ignored")
		+ _array(_dict(mapping, "hints"), "members")
	)
	var classes: Dictionary = _dict(mapping, "classes")
	var regex := RegEx.create_from_string(NAME_PATTERN)
	var reserved: Array = _dict(mapping, "legacy").keys() + _dict(mapping, "keep").keys()
	var tokens: Dictionary = _dict(pack, "tokens")
	for name: String in variations:
		var variation: Dictionary = _dict(variations, name)
		var where := "variation %s" % name
		if regex.search(name) == null:
			problems.append("%s: the name is not letters only" % where)
		if ClassDB.class_exists(name):
			problems.append("%s: the name is an engine class" % where)
		if reserved.has(name):
			problems.append("%s: the name is also a legacy or kept name in the mapping" % where)
		for member: String in variation:
			if not known_members.has(member):
				problems.append(
					"%s: member %s is not in mapping.variation_members" % [where, member]
				)
		var cls := str(variation.get("class", ""))
		if not classes.has(cls):
			problems.append("%s: class %s is not mapped" % [where, cls])
			continue
		var spec: Dictionary = _dict(classes, cls)
		var parent: Variant = variation.get("parent")
		if parent != null:
			var parent_variation: Dictionary = _dict(variations, str(parent))
			if parent_variation.get("class") != cls or parent_variation.has("deprecated"):
				problems.append(
					"%s: parent %s is not a live variation of %s" % [where, parent, cls]
				)
		for state: String in _array(variation, "styleboxes") + _array(variation, "empty"):
			if not _dict(spec, "states").has(state):
				problems.append("%s: state %s is not mapped for %s" % [where, state, cls])
		# A missing field would silently keep StyleBoxFlat's default (an opaque grey centre).
		for state: String in _array(variation, "styleboxes"):
			for field: String in _dict(mapping, "stylebox_fields"):
				var key := "%s.%s.%s" % [variation.get("prefix"), state, field]
				if not tokens.has(key):
					problems.append(
						"%s: state %s lacks %s (a StyleBox field)" % [where, state, field]
					)
		var textures: Dictionary = _dict(variation, "textures")
		for key: String in textures:
			if not _array(spec, "icons").has(key.replace("-", "_")):
				problems.append("%s: texture %s is not an icon of %s" % [where, key, cls])
		if not variation.has("deprecated"):
			problems.append_array(_hint_problems(variations, variation, where))
	var owned := tokens_by_variation(pack)
	for name: String in owned:
		var variation: Dictionary = _dict(variations, name)
		var spec: Dictionary = _dict(classes, str(variation.get("class", "")))
		if spec.is_empty():
			continue
		for key: String in owned[name]:
			var problem := _token_problem(pack, mapping, variation, spec, key)
			if not problem.is_empty():
				problems.append("variation %s: token %s %s" % [name, key, problem])
		problems.append_array(_ramp_problems(pack, variation, owned[name] as Array))
	problems.append_array(_legacy_problems(pack, mapping))
	problems.append_array(_base_type_problems(pack, mapping))
	return problems


## Each variation's tokens: pack token keys under the variation's prefix, by variation name.
static func tokens_by_variation(pack: Dictionary) -> Dictionary:
	var by_prefix := {}
	var variations: Dictionary = _dict(pack, "variations")
	for name: String in variations:
		by_prefix[str(_dict(variations, name).get("prefix", ""))] = name
	var owned := {}
	for name: String in variations:
		owned[name] = []
	var tokens: Dictionary = _dict(pack, "tokens")
	for key: String in tokens:
		var parts := key.split(".")
		var owner := ""
		for count in range(1, parts.size()):
			var candidate := ".".join(parts.slice(0, count))
			if by_prefix.has(candidate):
				owner = str(by_prefix[candidate])
		if not owner.is_empty():
			(owned[owner] as Array).append(key)
	for name: String in owned:
		(owned[name] as Array).sort()
	return owned


## The theme for one text size ("default" or "large"): every live pack variation, the base types
## (#576), then the legacy names and the kept ones, and the default font size. Deterministic: the
## same pack and mapping give the same file.
static func build(pack: Dictionary, mapping: Dictionary, text_size: String) -> Theme:
	var theme := Theme.new()
	var variations: Dictionary = _dict(pack, "variations")
	var classes: Dictionary = _dict(mapping, "classes")
	var owned := tokens_by_variation(pack)
	var empty := StyleBoxEmpty.new()
	empty.resource_scene_unique_id = EMPTY_ID
	for name in generated_names(pack):
		var variation: Dictionary = _dict(variations, name)
		var cls := str(variation.get("class", ""))
		var spec: Dictionary = _dict(classes, cls)
		var parent: Variant = variation.get("parent")
		theme.set_type_variation(name, cls if parent == null else str(parent))
		var states: Dictionary = _dict(spec, "states")
		for state: String in _array(variation, "styleboxes"):
			var box := _stylebox(pack, mapping, "%s.%s" % [variation.get("prefix"), state])
			box.resource_scene_unique_id = "%s_%s" % [name, str(states[state])]
			theme.set_stylebox(str(states[state]), name, box)
		for state: String in _array(variation, "empty"):
			theme.set_stylebox(str(states[state]), name, empty)
		for key: String in owned[name]:
			_apply_token(theme, pack, mapping, name, spec, key, text_size)
	_add_base_types(theme, mapping)
	_add_legacy(theme, pack, mapping)
	_add_kept(theme, mapping)
	if mapping.has("default_font_size"):
		theme.default_font_size = _int(mapping["default_font_size"])
	var meta := str(_dict(mapping, "hints").get("meta", ""))
	if not meta.is_empty():
		theme.set_meta(StringName(meta), hints(pack))
	return theme


## The pack's hints a theme item cannot hold, for the Toy components (#289): `bases`, the toy
## base Panel's variation under each raised variation by context ("dark", "light" or "any"), and
## `toggles`, each toggle's selected partner. Live variations only, in name order.
static func hints(pack: Dictionary) -> Dictionary:
	var bases := {}
	var toggles := {}
	var variations: Dictionary = _dict(pack, "variations")
	for name in generated_names(pack):
		var variation: Dictionary = _dict(variations, name)
		var base: Dictionary = _dict(variation, "base")
		if not base.is_empty():
			var by_context := {}
			var contexts: Array = base.keys()
			contexts.sort()
			for context: String in contexts:
				by_context[context] = str(base[context])
			bases[name] = by_context
		var toggle: Dictionary = _dict(variation, "toggle")
		if not toggle.is_empty():
			toggles[name] = str(toggle.get("selected", ""))
	return {"bases": bases, "toggles": toggles}


## Saves the theme at path and gives the file its fixed uid (a headless save writes none).
static func write(theme: Theme, path: String, uid_text: String) -> Error:
	var err := ResourceSaver.save(theme, path)
	if err != OK or uid_text.is_empty():
		return err
	return ResourceSaver.set_uid(path, ResourceUID.text_to_id(uid_text))


## The text a theme saves to, its header without the uid: what the stale test compares.
static func text_of(theme: Theme, scratch_path: String) -> String:
	var err := ResourceSaver.save(theme, scratch_path)
	if err != OK:
		return "save failed: %s" % error_string(err)
	var text := FileAccess.get_file_as_string(scratch_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))
	return without_uid(text)


static func without_uid(text: String) -> String:
	var regex := RegEx.create_from_string(' uid="uid://[a-z0-9]+"')
	var cut := text.find("\n")
	return regex.sub(text.substr(0, cut), "") + text.substr(cut)


## Every engine item the mapping writes for a class, by kind (styles, colors, constants,
## font_sizes, and the icons the pack's textures may name): what the keys test looks up in the
## class reference. Custom items are left out.
static func engine_items(mapping: Dictionary, cls: String) -> Dictionary:
	var spec: Dictionary = _dict(_dict(mapping, "classes"), cls)
	var items := {"styles": [], "colors": [], "constants": [], "font_sizes": []}
	items["icons"] = _array(spec, "icons").duplicate()
	var custom_states: Array = _array(spec, "custom_states")
	var states: Dictionary = _dict(spec, "states")
	for state: String in states:
		if not custom_states.has(state):
			(items["styles"] as Array).append(str(states[state]))
	var state_colors: Dictionary = _dict(spec, "state_colors")
	for field: String in state_colors:
		var table: Dictionary = _colour_table(mapping, state_colors[field])
		for state: String in table:
			(items["colors"] as Array).append(str(table[state]))
	var item_map: Dictionary = _dict(spec, "items")
	for key: String in item_map:
		var item: Dictionary = _dict(item_map, key)
		if not item.get("custom", false):
			var kind := "colors" if item.get("kind") == "color" else "constants"
			(items[kind] as Array).append(str(item.get("name")))
	if spec.has("label"):
		(items["font_sizes"] as Array).append(str(spec["label"]))
	return items


## Every custom item the mapping writes for a class (no engine class binds them), by kind.
static func custom_items(mapping: Dictionary, cls: String) -> Dictionary:
	var spec: Dictionary = _dict(_dict(mapping, "classes"), cls)
	var items := {"styles": [], "colors": [], "constants": []}
	var states: Dictionary = _dict(spec, "states")
	for state: String in _array(spec, "custom_states"):
		(items["styles"] as Array).append(str(states[state]))
	var item_map: Dictionary = _dict(spec, "items")
	for key: String in item_map:
		var item: Dictionary = _dict(item_map, key)
		if item.get("custom", false):
			var kind := "colors" if item.get("kind") == "color" else "constants"
			(items[kind] as Array).append(str(item.get("name")))
	for section: String in ["press", "size", "motion"]:
		var names: Dictionary = _dict(spec, section)
		for key: String in names:
			(items["constants"] as Array).append(str(names[key]))
	if spec.has("ramp"):
		(items["colors"] as Array).append(str(_dict(spec, "ramp").get("stop")) + "00")
	return items


static func _token_problem(
	pack: Dictionary, mapping: Dictionary, variation: Dictionary, spec: Dictionary, key: String
) -> String:
	var record: Dictionary = _dict(_dict(pack, "tokens"), key)
	var type := str(record.get("type", ""))
	var rest := key.substr(str(variation.get("prefix")).length() + 1).split(".")
	var head := rest[0]
	var tail := rest[1] if rest.size() > 1 else ""
	if rest.size() > 2:
		return "is nested deeper than the mapping knows"
	if head == "items":
		var item: Dictionary = _dict(_dict(spec, "items"), tail)
		if item.is_empty():
			return "is not in mapping.classes.%s.items" % variation.get("class")
		if (item.get("kind") == "color") != (type == "color"):
			return "has type %s, which the %s item %s cannot take" % [type, item.get("kind"), tail]
		return ""
	if head == "label":
		return "" if spec.has("label") and type == "typography" else "label is not mapped"
	if head in ["press", "size", "motion"]:
		if head == "motion":
			return (
				_motion_problem(pack, key, record) if spec.has("motion") else "motion is not mapped"
			)
		return "" if _dict(spec, head).has(tail) and type == "dimension" else "is not mapped"
	if head == "ramp":
		var ramp: Dictionary = _dict(spec, "ramp")
		if ramp.is_empty():
			return "ramp is not mapped"
		if tail.begins_with("stop-") and type == "color":
			return ""
		return "" if _array(ramp, "checked").has(tail) else "is not a ramp stop"
	var states: Array = _array(variation, "styleboxes") + _array(variation, "empty")
	if not states.has(head):
		return "names no state, item or section the mapping knows"
	if _dict(mapping, "stylebox_fields").has(tail):
		return "" if _array(variation, "styleboxes").has(head) else "is a field of an empty state"
	var table := _colour_table(mapping, _dict(spec, "state_colors").get(tail))
	if table.has(head) and type == "color":
		return ""
	return "is not a StyleBox field or a state colour of %s" % variation.get("class")


static func _motion_problem(pack: Dictionary, key: String, record: Dictionary) -> String:
	if _int(record.get("delayMs", -1)) != 0:
		return "has a delay, which the press motion constants cannot carry"
	var reduced: Dictionary = _dict(_dict(_dict(pack, "modes"), "motion"), "reduced")
	if not reduced.has(key):
		return "has no modes.motion.reduced record"
	if not _dict(record, "godot").has("transValue") or not _dict(record, "godot").has("easeValue"):
		return "has no godot.transValue or godot.easeValue"
	return ""


static func _ramp_problems(
	pack: Dictionary, variation: Dictionary, keys: Array
) -> PackedStringArray:
	var problems := PackedStringArray()
	var prefix := "%s.ramp." % variation.get("prefix")
	var stops := PackedStringArray()
	for key: String in keys:
		if key.begins_with(prefix + "stop-"):
			stops.append(key)
	if stops.is_empty():
		return problems
	var tokens: Dictionary = _dict(pack, "tokens")
	var steps := _int(_dict(tokens, prefix + "steps").get("value", -1))
	if stops.size() != steps + 1:
		problems.append("%s: %d stops for %d steps" % [prefix, stops.size(), steps])
	for index in stops.size():
		if stops[index] != "%sstop-%02d" % [prefix, index]:
			problems.append("%s: stop %d is %s" % [prefix, index, stops[index]])
	var ends := {"empty": stops[0], "full": stops[stops.size() - 1]}
	for end: String in ends:
		var want: Variant = _dict(tokens, str(ends[end])).get("rgba")
		if _dict(tokens, prefix + end).get("rgba") != want:
			problems.append("%s%s is not the colour of %s" % [prefix, end, ends[end]])
	return problems


static func _legacy_problems(pack: Dictionary, mapping: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var variations: Dictionary = _dict(pack, "variations")
	var legacy: Dictionary = _dict(mapping, "legacy")
	for name: String in legacy:
		var entry: Dictionary = _dict(legacy, name)
		var target := str(entry.get("variation", ""))
		var target_variation: Dictionary = _dict(variations, target)
		if target_variation.is_empty() or target_variation.has("deprecated"):
			problems.append("legacy %s: %s is not a live pack variation" % [name, target])
		elif target_variation.get("class") != entry.get("base"):
			problems.append(
				(
					"legacy %s: %s is a %s, not a %s"
					% [name, target, target_variation.get("class"), entry.get("base")]
				)
			)
		var own: Dictionary = _dict(entry, "own_styles")
		for item: String in own:
			if not _array(target_variation, "styleboxes").has(str(_dict(own, item).get("from"))):
				problems.append(
					"legacy %s: %s has no StyleBox to copy for %s" % [name, target, item]
				)
	var keep: Dictionary = _dict(mapping, "keep")
	for name: String in keep:
		if legacy.has(name) or not ClassDB.class_exists(str(_dict(keep, name).get("base"))):
			problems.append("keep %s: a legacy name too, or its base is no engine class" % name)
	return problems


## A base_types row names an engine Control (or Window: PopupMenu) class and copies a live pack
## variation of that very class with no parent, or gives literal items; and none of its items may
## replace what Godot's default theme gives an engine subclass. A theme on a node is searched
## through a control's whole type chain before Godot's default theme is, so a Button row would
## restyle every CheckBox (the plan review of #576, seen in a probe).
static func _base_type_problems(pack: Dictionary, mapping: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var variations: Dictionary = _dict(pack, "variations")
	var rows: Dictionary = _dict(mapping, "base_types")
	for cls: String in rows:
		var where := "base type %s" % cls
		var row: Dictionary = _dict(rows, cls)
		var themed := (
			ClassDB.class_exists(cls)
			and (ClassDB.is_parent_class(cls, "Control") or ClassDB.is_parent_class(cls, "Window"))
		)
		if not themed:
			problems.append("%s: not an engine Control or Window class" % where)
			continue
		if row.is_empty():
			problems.append("%s: neither from nor an item" % where)
		for member: String in row:
			if not BASE_TYPE_MEMBERS.has(member):
				problems.append(
					"%s: member %s is not one of %s" % [where, member, BASE_TYPE_MEMBERS]
				)
		if row.has("from"):
			var from := str(row["from"])
			if not _is_live(variations, from, cls):
				problems.append("%s: %s is not a live pack variation of %s" % [where, from, cls])
			elif _dict(variations, from).get("parent") != null:
				problems.append(
					"%s: %s has a parent, whose items the copy would miss" % [where, from]
				)
		problems.append_array(_shadow_problems(mapping, cls, where))
	var engine_variations: Dictionary = _dict(mapping, "engine_variations")
	var regex := RegEx.create_from_string(NAME_PATTERN)
	var taken: Array = (
		variations.keys() + _dict(mapping, "legacy").keys() + _dict(mapping, "keep").keys()
	)
	for name: String in engine_variations:
		var base := str(engine_variations[name])
		if regex.search(name) == null or ClassDB.class_exists(name) or taken.has(name):
			problems.append(
				"engine variation %s: not letters only, an engine class or a name in use" % name
			)
		if not rows.has(base):
			problems.append("engine variation %s: %s is not a base type" % [name, base])
	var size: Variant = mapping.get("default_font_size")
	if size != null and _int(size) <= 0:
		problems.append("default_font_size: %s is not a size" % size)
	return problems


## The items of a base_types row's class that would hide the default theme's own item of an
## engine subclass (or a class between the two), walking up from each subclass: a row of a class
## on the way (this theme's, so searched first) covers its items from there up.
static func _shadow_problems(mapping: Dictionary, cls: String, where: String) -> PackedStringArray:
	var found := {}
	var rows: Dictionary = _dict(mapping, "base_types")
	var items := base_type_items(mapping, cls)
	var default := ThemeDB.get_default_theme()
	var subclasses := Array(ClassDB.get_inheriters_from_class(cls))
	subclasses.sort()
	for sub: String in subclasses:
		var covered := {}
		var type := sub
		while not type.is_empty() and type != cls:
			if rows.has(type):
				var own := base_type_items(mapping, type)
				for kind: String in own:
					for item: String in own[kind]:
						covered["%s %s" % [kind, item]] = true
			for kind: String in items:
				for item: String in items[kind]:
					var key := "%s %s" % [kind, item]
					if not covered.has(key) and _default_has(default, kind, item, type):
						found["%s: its %s would replace the default theme's on %s" % [where, key, type]] = true
			type = ClassDB.get_parent_class(type)
	return PackedStringArray(found.keys())


## The items a base_types row writes, by kind: for `from`, every engine item the mapping can write
## for the class (a superset of what the variation holds); then its literal items.
static func base_type_items(mapping: Dictionary, cls: String) -> Dictionary:
	var row: Dictionary = _dict(_dict(mapping, "base_types"), cls)
	var items := {"styles": [], "colors": [], "constants": [], "font_sizes": [], "icons": []}
	if row.has("from"):
		var engine := engine_items(mapping, cls)
		for kind: String in engine:
			(items[kind] as Array).append_array(engine[kind] as Array)
	for kind: String in ["constants", "font_sizes", "colors"]:
		(items[kind] as Array).append_array(_dict(row, kind).keys())
	return items


## Whether `theme` sets the item on `type` itself: its lists, since Theme.has_font_size is also
## true for every type of a theme with a default font size (Godot's default theme has one).
static func _default_has(theme: Theme, kind: String, item: String, type: String) -> bool:
	match kind:
		"styles":
			return theme.get_stylebox_list(type).has(item)
		"colors":
			return theme.get_color_list(type).has(item)
		"constants":
			return theme.get_constant_list(type).has(item)
		"font_sizes":
			return theme.get_font_size_list(type).has(item)
		"icons":
			return theme.get_icon_list(type).has(item)
	return false


static func _apply_token(
	theme: Theme,
	pack: Dictionary,
	mapping: Dictionary,
	name: String,
	spec: Dictionary,
	key: String,
	text_size: String,
) -> void:
	var variation: Dictionary = _dict(_dict(pack, "variations"), name)
	var record := _record(pack, key, text_size)
	var rest := key.substr(str(variation.get("prefix")).length() + 1).split(".")
	var head := rest[0]
	var tail := rest[1] if rest.size() > 1 else ""
	match head:
		"items":
			var item: Dictionary = _dict(_dict(spec, "items"), tail)
			if item.get("kind") == "color":
				theme.set_color(str(item.get("name")), name, _colour(record))
			else:
				theme.set_constant(str(item.get("name")), name, _number(record))
		"label":
			theme.set_font_size(str(spec.get("label")), name, _int(record.get("fontSizePx", 0)))
		"press", "size":
			theme.set_constant(str(_dict(spec, head).get(tail)), name, _number(record))
		"motion":
			var names: Dictionary = _dict(spec, "motion")
			var godot: Dictionary = _dict(record, "godot")
			var reduced := _dict(_dict(_dict(_dict(pack, "modes"), "motion"), "reduced"), key)
			theme.set_constant(str(names["duration"]), name, _int(record.get("durationMs", 0)))
			theme.set_constant(str(names["reduced"]), name, _int(reduced.get("durationMs", 0)))
			theme.set_constant(str(names["trans"]), name, _int(godot.get("transValue", 0)))
			theme.set_constant(str(names["ease"]), name, _int(godot.get("easeValue", 0)))
		"ramp":
			if tail.begins_with("stop-"):
				var item_name := str(_dict(spec, "ramp").get("stop")) + tail.trim_prefix("stop-")
				theme.set_color(item_name, name, _colour(record))
		_:
			var table := _colour_table(mapping, _dict(spec, "state_colors").get(tail))
			if table.has(head):
				theme.set_color(str(table[head]), name, _colour(record))


static func _stylebox(pack: Dictionary, mapping: Dictionary, prefix: String) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	var tokens: Dictionary = _dict(pack, "tokens")
	var fields: Dictionary = _dict(mapping, "stylebox_fields")
	for field: String in fields:
		var record: Dictionary = _dict(tokens, "%s.%s" % [prefix, field])
		var property := str(fields[field])
		match str(record.get("type", "")):
			"color":
				box.set(property, _colour(record))
			"boolean":
				box.set(property, _bool(record.get("value", false)))
			"dimension":
				if INT_FIELDS.has(property):
					box.set(property, _int(record.get("px", 0)))
				else:
					box.set(property, _float(record.get("px", 0)))
	return box


static func _add_legacy(theme: Theme, pack: Dictionary, mapping: Dictionary) -> void:
	var legacy: Dictionary = _dict(mapping, "legacy")
	var names := legacy.keys()
	names.sort()
	for name: String in names:
		var entry: Dictionary = _dict(legacy, name)
		var target := str(entry.get("variation"))
		theme.set_type_variation(name, target)
		var own: Dictionary = _dict(entry, "own_styles")
		var prefix := str(_dict(_dict(pack, "variations"), target).get("prefix"))
		for item: String in own:
			var spec: Dictionary = _dict(own, item)
			var box := _stylebox(pack, mapping, "%s.%s" % [prefix, spec.get("from")])
			var changes: Dictionary = _dict(spec, "set")
			for property: String in changes:
				box.set(property, changes[property])
			box.resource_scene_unique_id = "%s_%s" % [name, item]
			theme.set_stylebox(item, name, box)


## Each base type (#576) under its engine class's name: every item its `from` variation holds, the
## same objects (a StyleBox stays one sub-resource, `<Variation>_<item>`), then its literal items.
## Then the engine's own variations (mapping.engine_variations, SpinBox's SpinBoxInnerLineEdit) as
## thin variations of a base type: Godot takes a control's type chain from the theme that names
## its variation, and from its default theme the inner field would find this theme's default font
## size before the LineEdit row (seen in a probe).
static func _add_base_types(theme: Theme, mapping: Dictionary) -> void:
	var rows: Dictionary = _dict(mapping, "base_types")
	for cls in base_type_names(mapping):
		var row: Dictionary = _dict(rows, cls)
		if row.has("from"):
			var from := str(row["from"])
			for kind in Theme.DATA_TYPE_MAX:
				var names := theme.get_theme_item_list(kind, from)
				names.sort()
				for item in names:
					theme.set_theme_item(kind, item, cls, theme.get_theme_item(kind, item, from))
		_set_literal_items(theme, cls, row)
	var engine_variations: Dictionary = _dict(mapping, "engine_variations")
	var names := engine_variations.keys()
	names.sort()
	for name: String in names:
		theme.set_type_variation(name, str(engine_variations[name]))


static func _add_kept(theme: Theme, mapping: Dictionary) -> void:
	var keep: Dictionary = _dict(mapping, "keep")
	for name: String in keep:
		var entry: Dictionary = _dict(keep, name)
		theme.set_type_variation(name, str(entry.get("base")))
		_set_literal_items(theme, name, entry)


## The constants, font sizes and colours an entry of `keep` or `base_types` writes as they are.
static func _set_literal_items(theme: Theme, name: String, entry: Dictionary) -> void:
	var constants: Dictionary = _dict(entry, "constants")
	for item: String in constants:
		theme.set_constant(item, name, _int(constants[item]))
	var sizes: Dictionary = _dict(entry, "font_sizes")
	for item: String in sizes:
		theme.set_font_size(item, name, _int(sizes[item]))
	var colours: Dictionary = _dict(entry, "colors")
	for item: String in colours:
		theme.set_color(item, name, _colour({"rgba": colours[item]}))


## A token's record at a text size: the large mode's own record where it has one.
static func _record(pack: Dictionary, key: String, text_size: String) -> Dictionary:
	var modes: Dictionary = _dict(_dict(pack, "modes"), "textSize")
	var mode: Dictionary = _dict(modes, text_size)
	if mode.has(key):
		return _dict(mode, key)
	return _dict(_dict(pack, "tokens"), key)


static func _colour_table(mapping: Dictionary, value: Variant) -> Dictionary:
	if value is String:
		return _dict(mapping, str(value))
	return value as Dictionary if value is Dictionary else {}


static func _colour(record: Dictionary) -> Color:
	var rgba: Array = _array(record, "rgba")
	if rgba.size() != 4:
		return Color(0, 0, 0, 0)
	return Color(_float(rgba[0]), _float(rgba[1]), _float(rgba[2]), _float(rgba[3]))


## A live variation's `base` must name live Panel variations by context, and its `toggle` a live
## variation of its own class.
static func _hint_problems(
	variations: Dictionary, variation: Dictionary, where: String
) -> PackedStringArray:
	var problems := PackedStringArray()
	var base: Variant = variation.get("base")
	if base != null and not base is Dictionary:
		problems.append("%s: base is not an object" % where)
	for context: String in _dict(variation, "base"):
		var target := str(_dict(variation, "base")[context])
		if not ["dark", "light", "any"].has(context):
			problems.append("%s: base context %s is not dark, light or any" % [where, context])
		if not _is_live(variations, target, "Panel"):
			problems.append("%s: base %s is not a live Panel variation" % [where, target])
	var toggle: Variant = variation.get("toggle")
	if toggle != null and not toggle is Dictionary:
		problems.append("%s: toggle is not an object" % where)
	if toggle is Dictionary:
		var selected := str((toggle as Dictionary).get("selected", ""))
		if not _is_live(variations, selected, str(variation.get("class", ""))):
			problems.append(
				"%s: toggle %s is not a live variation of its class" % [where, selected]
			)
	return problems


static func _is_live(variations: Dictionary, name: String, cls: String) -> bool:
	var variation: Dictionary = _dict(variations, name)
	return variation.get("class") == cls and not variation.has("deprecated")


static func _number(record: Dictionary) -> int:
	return _int(record.get("px", record.get("value", 0)))


static func _dict(from: Dictionary, key: String) -> Dictionary:
	var value: Variant = from.get(key)
	return value as Dictionary if value is Dictionary else {}


static func _array(from: Dictionary, key: String) -> Array:
	var value: Variant = from.get(key)
	return value as Array if value is Array else []


static func _int(value: Variant) -> int:
	match typeof(value):
		TYPE_INT, TYPE_BOOL:
			var whole: int = value
			return whole
		TYPE_FLOAT:
			var number: float = value
			return roundi(number)
	return 0


static func _float(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			var number: float = value
			return number
	return 0.0


static func _bool(value: Variant) -> bool:
	return value is bool and value == true
