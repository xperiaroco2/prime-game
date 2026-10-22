extends GdUnitTestSuite
## ItemWorld's children (#1260, ARCHITECTURE §4.7.59): the task types' views come from
## TaskClients, yet the children keep their names, classes and tree order (the order they process
## in), and every view has the model, the mode and the level after setup and set_level.

## Today's children of ItemWorld, by name and class, in their tree order.
const CHILDREN: Array[Array] = [
	[&"ItemViews", "ItemViews"],
	[&"CircleViews", "CircleViews"],
	[&"ZoneViews", "ZoneViews"],
	[&"ItemInteractions", "ItemInteractions"],
	[&"WorldSounds", "WorldSounds"],
	[&"PhotoFlashes", "PhotoFlashes"],
	[&"StationViews", "StationViews"],
	[&"StationHums", "StationHums"],
	[&"CookingViews", "CookingViews"],
	[&"PhotoViewfinder", "PhotoViewfinder"],
	[&"CarRepairViews", "CarRepairViews"],
	[&"PhotoViews", "PhotoViews"],
	[&"PhotoPictures", "PhotoPictures"],
]


func test_the_children_keep_their_names_classes_and_order() -> void:
	var world: ItemWorld = auto_free(ItemWorld.new())
	var found: Array[Array] = []
	for child: Node in world.get_children():
		found.append([child.name, (child.get_script() as Script).get_global_name()])
	assert_str(world.name).is_equal("Items")
	assert_array(found).is_equal(CHILDREN)


func test_every_task_view_is_a_child_with_the_level_after_set_level() -> void:
	var world: ItemWorld = auto_free(ItemWorld.new())
	var level: Node = auto_free(Node.new())
	world.set_level(level)
	assert_bool(world.task_views.is_empty()).is_false()
	for view: Node3D in world.task_views.values():
		assert_object(view.get_parent()).is_same(world)
		if &"level" in view:
			assert_object(view.get(&"level")).is_same(level)
