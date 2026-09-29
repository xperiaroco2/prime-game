extends GdUnitTestSuite
## The layer bits in `PhysicsLayers` match the names in `project.godot`, so the editor's layer
## grid and the code mean the same thing.


func test_layer_names_match_the_bits() -> void:
	var names: Dictionary[int, String] = {
		PhysicsLayers.WORLD: "world",
		PhysicsLayers.LIVING: "living_players",
		PhysicsLayers.GHOSTS: "ghosts",
	}
	for bit: int in names:
		var layer := 1 + roundi(log(float(bit)) / log(2.0))
		var setting := "layer_names/3d_physics/layer_%d" % layer
		assert_str(str(ProjectSettings.get_setting(setting))).is_equal(names[bit])
