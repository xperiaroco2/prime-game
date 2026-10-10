extends GdUnitTestSuite
## When a launch starts the tutorial by itself (GameTutorial.first_launch, E70, #601): only with no
## launch option, settings read from a file and the tutorial flag absent. Every test and runner
## window keeps its settings in memory or gives an option, so none of them starts it.


func test_only_a_bare_launch_with_a_settings_file_and_no_flag_starts_it() -> void:
	# [arguments, settings path, flag seen, starts]
	var rows: Array[Array] = [
		[[], "user://settings.cfg", false, true],
		[[], "user://settings.cfg", true, false],
		[[], "", false, false],
		[["--port=24999"], "user://settings.cfg", false, false],
		[["--tutorial"], "user://settings.cfg", false, false],
		[["--nonsense"], "user://settings.cfg", false, false],
	]
	for row: Array in rows:
		var options := LaunchOptions.parse(PackedStringArray(row[0] as Array), true)
		var settings := UserSettings.new(row[1] as String)
		settings.tutorial_seen = row[2] as bool
		var starts := GameTutorial.first_launch(options, settings)
		assert_bool(starts).override_failure_message(str(row)).is_equal(row[3] as bool)
