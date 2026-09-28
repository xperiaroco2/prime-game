extends GdUnitTestSuite
## Smoke test: proves the GdUnit4 pipeline (runner, headless run, JUnit report, CI) works.


func test_pipeline_runs() -> void:
	assert_int(1 + 1).is_equal(2)


func test_engine_is_pinned_version() -> void:
	var info: Dictionary = Engine.get_version_info()
	assert_str("%d.%d.%d" % [info["major"], info["minor"], info["patch"]]).is_equal("4.7.2")
