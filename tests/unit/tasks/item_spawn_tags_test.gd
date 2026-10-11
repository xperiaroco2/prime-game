extends GdUnitTestSuite
## Where a task type's items may lie (TaskType.item_spawn_tags, #253): the map screen lights the
## rooms holding a level marker of such a tag. A task type names none by default; Delivery names
## its package kind's spawn tag (the base mode's: `package`), never its circles'.

const BASE_MODE := "res://content/modes/base_mode.tres"


func test_a_task_type_names_no_tag_by_default() -> void:
	assert_array(TaskType.new().item_spawn_tags()).is_empty()


func test_delivery_names_its_package_kinds_spawn_tag_only() -> void:
	var delivery := (load(BASE_MODE) as GameMode).find_task_type(&"delivery") as Delivery
	assert_array(delivery.item_spawn_tags()).contains_exactly([delivery.package.spawn_tag])
	assert_array(delivery.item_spawn_tags()).not_contains([delivery.circle.spawn_tag])
	var kind := ItemKind.new()
	kind.spawn_tag = &"crate"
	delivery = Delivery.new()
	delivery.package = kind
	assert_array(delivery.item_spawn_tags()).contains_exactly([&"crate"])


func test_a_delivery_with_no_package_kind_names_none() -> void:
	assert_array(Delivery.new().item_spawn_tags()).is_empty()
