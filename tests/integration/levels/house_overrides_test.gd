extends GdUnitTestSuite
## Every House room and the plot keep each property they set through a re-save (#1056): the scene
## instantiated in edit state and packed again, as the editor and `normalize` save it, still sets
## every property on every node the file sets it on. An override inside an instance (the art's kit
## materials and `plan_at`, a door body's layer) needs its instance's [editable path] entry, and a
## line at its default value is dropped: either fails here, as `normalize` would refuse the file.
## The text check (`check`, tools/runner/editables.py) cannot see an instance nested inside an
## instanced scene; this packs the scenes as Godot does.

const ROOMS := "res://levels/house/rooms/"
const PLOT := "res://levels/house/outdoor.tscn"
const BOILER := "res://levels/house/rooms/boiler_room.tscn"
## The boiler room's first wall module: an instance of a kit wrapper whose mesh the room overrides.
const WALL := "Shell/wall_basement_2m_1"


func test_every_house_room_and_the_plot_keep_their_properties_through_a_re_save() -> void:
	var paths := _scenes()
	assert_int(paths.size()).is_greater(30)
	for path: String in paths:
		var scene := load(path) as PackedScene
		var dropped := _dropped(scene.get_state(), _repacked(scene, ""))
		(
			assert_array(dropped)
			. override_failure_message("%s: a re-save drops %s" % [path, dropped])
			. is_empty()
		)


func test_an_instance_that_is_not_editable_loses_its_overrides() -> void:
	# The check above can fail: with the wall's Editable Children off, its mesh's lines are dropped.
	var scene := load(BOILER) as PackedScene
	var dropped := _dropped(scene.get_state(), _repacked(scene, WALL))
	(
		assert_array(dropped)
		. contains(
			[
				WALL + "/wall_basement_2m: surface_material_override/0",
				WALL + "/wall_basement_2m: instance_shader_parameters/plan_at",
			]
		)
	)


## Each room under ROOMS, then the plot.
func _scenes() -> Array[String]:
	var paths: Array[String] = []
	for file: String in ResourceLoader.list_directory(ROOMS):
		if file.ends_with(".tscn"):
			paths.append(ROOMS + file)
	paths.append(PLOT)
	return paths


## The scene instantiated in edit state and packed again (tools/normalize/normalize.gd), with the
## instance at `not_editable` (a node path, or "") no longer editable; its state.
func _repacked(scene: PackedScene, not_editable: String) -> SceneState:
	var root := scene.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	if not not_editable.is_empty():
		root.set_editable_instance(root.get_node(not_editable), false)
	var packed := PackedScene.new()
	var error := packed.pack(root)
	root.free()
	assert_int(error).is_equal(OK)
	return packed.get_state()


## "<node path>: <property>" for each property `before` sets that `after` does not.
func _dropped(before: SceneState, after: SceneState) -> Array[String]:
	var kept := _properties(after)
	var dropped: Array[String] = []
	for key: String in _properties(before):
		if not kept.has(key):
			dropped.append(key)
	return dropped


func _properties(state: SceneState) -> Dictionary[String, bool]:
	var found: Dictionary[String, bool] = {}
	for node: int in state.get_node_count():
		var path := str(state.get_node_path(node)).trim_prefix("./")
		for property: int in state.get_node_property_count(node):
			found["%s: %s" % [path, state.get_node_property_name(node, property)]] = true
	return found
