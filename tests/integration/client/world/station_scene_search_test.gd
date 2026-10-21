extends GdUnitTestSuite
## #1198: StationViews, CookingViews, PhotoViews and CarRepairViews search a level for their
## station scenes once per level, so a level that holds none of them is not rescanned every frame.
## A scene that turns up later is found only once the level is set again (Game sets each level
## whole, its scenes already in the tree, ItemWorld.set_level).

const SCENES := "res://levels/stations/%s.tscn"

var _level: Node3D


func before_test() -> void:
	_level = auto_free(Node3D.new())
	add_child(_level)


func test_the_generator_views_search_a_level_once() -> void:
	var views: StationViews = auto_free(StationViews.new())
	views.mode = FixtureGeneratorModes.basic()
	views.model = ClientModel.new(views.mode)
	await _searched_once(views, "generator")


func test_the_cooking_views_search_a_level_once() -> void:
	var views: CookingViews = auto_free(CookingViews.new())
	views.mode = FixtureCookingModes.basic(2)
	views.model = ClientModel.new(views.mode)
	await _searched_once(views, "grill")


func test_the_photo_views_search_a_level_once() -> void:
	var views: PhotoViews = auto_free(PhotoViews.new())
	views.mode = FixturePhotoModes.basic()
	views.model = ClientModel.new(views.mode)
	await _searched_once(views, "camera")


func test_the_car_repair_views_search_a_level_once() -> void:
	var views: CarRepairViews = auto_free(CarRepairViews.new())
	views.mode = FixtureCarRepairClient.for_scenes(FixtureCarRepairModes.basic())
	views.model = ClientModel.new(views.mode)
	await _searched_once(views, "lift_panel")


## Sets the empty level, adds `scene` to it after a search, and checks it is wrapped only after
## the level is set again.
func _searched_once(views: Node, scene: String) -> void:
	add_child(views)
	views.set(&"level", _level)
	await _frames()
	var root := (load(SCENES % scene) as PackedScene).instantiate() as Node3D
	_level.add_child(root)
	await _frames()
	assert_object(root.get_node_or_null(StationViews.WRAPPER)).is_null()
	views.set(&"level", _level)
	await _frames()
	assert_object(root.get_node_or_null(StationViews.WRAPPER)).is_not_null()


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
