extends SceneTree
## Writes the game's themes from the pinned UI pack (#288): client/ui/theme/game_theme.tres (its uid
## kept) and game_theme_large.tres (the large-text mode), through tools/theme/mapping.json.
##   tools\run.cmd ui-sync ui-<version>
##   tools\run.cmd run tools/theme/build_theme.gd --headless
## It stops with an error when the pinned pack does not match its lock, when the mapping does not
## cover the pack, or when the project's UI base is not the size the pack is drawn at (#287); the
## user arg `-- --skip-base-check` turns that last one into a warning, for a branch built before
## #287 lands. The tests rebuild the same themes in memory and fail when a committed file is stale.

const Builder := preload("res://tools/theme/theme_builder.gd")


func _init() -> void:
	quit(_build())


func _build() -> int:
	var mapping := Builder.load_mapping()
	if mapping.is_empty():
		push_error("THEME %s is missing or not JSON" % Builder.MAPPING_PATH)
		return 1
	var pack := Builder.load_pack(mapping)
	var lock := Builder.load_json(str(mapping.get("lock", "")))
	var problems := _lock_problems(mapping, pack, lock)
	if problems.is_empty():
		problems = Builder.check_pack(pack, mapping)
	if not problems.is_empty():
		for problem in problems:
			push_error("THEME %s" % problem)
		return 1
	var base := (
		Builder
		. base_problem(
			pack,
			ProjectSettings.get_setting("display/window/size/viewport_width") as int,
			ProjectSettings.get_setting("display/window/size/viewport_height") as int,
		)
	)
	if not base.is_empty():
		if not OS.get_cmdline_user_args().has("--skip-base-check"):
			push_error("THEME %s; build after it (or pass -- --skip-base-check)" % base)
			return 1
		print("THEME warning: %s (--skip-base-check)" % base)
	for deprecated in Builder.deprecated_names(pack):
		print("THEME skipped deprecated variation %s" % deprecated)
	var themes: Dictionary = mapping.get("themes", {})
	for key: String in themes:
		var spec: Dictionary = themes[key]
		var theme := Builder.build(pack, mapping, str(spec.get("text_size")))
		var path := str(spec.get("path"))
		var err := Builder.write(theme, path, str(spec.get("uid", "")))
		if err != OK:
			push_error("THEME could not write %s: %s" % [path, error_string(err)])
			return 1
		print("THEME wrote %s (%d types)" % [path, theme.get_type_list().size()])
	return 0


func _lock_problems(mapping: Dictionary, pack: Dictionary, lock: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	if pack.is_empty() or lock.is_empty():
		problems.append(
			(
				"no pinned pack (%s, %s): run tools\\run.cmd ui-sync"
				% [mapping.get("pack"), mapping.get("lock")]
			)
		)
		return problems
	if lock.get("tag") != "ui-%s" % pack.get("version"):
		problems.append(
			(
				"the lock's tag %s is not the pack's version %s"
				% [lock.get("tag"), pack.get("version")]
			)
		)
	var files: Dictionary = lock.get("files", {})
	var sha := FileAccess.get_sha256(str(mapping.get("pack")))
	if files.get(str(mapping.get("pack")).get_file()) != sha:
		problems.append(
			"the pack differs from its lock: tools\\run.cmd ui-sync --check names what changed"
		)
	return problems
