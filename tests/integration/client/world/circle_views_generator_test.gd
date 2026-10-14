extends GdUnitTestSuite
## CircleViews leaves a Generator's stations to the level's station scenes (#801, ARCHITECTURE
## §4.7.53; G6: only Delivery's circles): no cylinder for the generator or a switch, while a
## station of a kind no task type
## holds still gets the fallback cylinder.

const G := preload("res://tests/fixtures/client/fixture_generator_client.gd")
const OTHER := 9

var _views: CircleViews


func before_test() -> void:
	_views = CircleViews.new()
	_views.mode = FixtureGeneratorModes.basic()
	_views.model = G.dealt()
	add_child(_views)


func after_test() -> void:
	_views.free()


func test_no_cylinder_for_the_generator_or_a_switch() -> void:
	assert_bool(CircleViews.draws(_views.mode, &"generator")).is_false()
	assert_bool(CircleViews.draws(_views.mode, &"switch")).is_false()
	G.fold(_views.model, StationPlacedEvent.new(OTHER, &"circle", Color.RED, Vector3(2, 0, 2)))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_object(_views.view_of(G.GENERATOR)).is_null()
	for i in FixtureGeneratorModes.SWITCHES:
		assert_object(_views.view_of(G.FIRST_SWITCH + i)).is_null()
	assert_object(_views.view_of(OTHER)).is_not_null()
