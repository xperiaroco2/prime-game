extends GdUnitTestSuite
## PhotoLayers (#787, the photo ADR's §3.3): the live cameras' mask drops the puppets' layer and
## keeps the level's and the live avatars'; the picture's camera's mask is the reverse; assign()
## walks the whole tree and turns the shadows off only when asked.


func test_the_live_view_drops_the_photo_layer_and_keeps_the_rest() -> void:
	assert_int(PhotoLayers.LIVE_VIEW & PhotoLayers.PHOTO).is_equal(0)
	assert_int(PhotoLayers.LIVE_VIEW & PhotoLayers.LIVE_AVATAR).is_equal(PhotoLayers.LIVE_AVATAR)
	assert_int(PhotoLayers.LIVE_VIEW & PhotoLayers.GROUND).is_equal(PhotoLayers.GROUND)


func test_the_photo_view_drops_the_live_avatars_and_keeps_the_rest() -> void:
	assert_int(PhotoLayers.PHOTO_VIEW & PhotoLayers.LIVE_AVATAR).is_equal(0)
	assert_int(PhotoLayers.PHOTO_VIEW & PhotoLayers.PHOTO).is_equal(PhotoLayers.PHOTO)
	assert_int(PhotoLayers.PHOTO_VIEW & PhotoLayers.GROUND).is_equal(PhotoLayers.GROUND)


func test_all_is_the_default_camera_mask() -> void:
	var camera := auto_free(Camera3D.new()) as Camera3D
	assert_int(PhotoLayers.ALL).is_equal(camera.cull_mask)
	assert_int(PhotoLayers.GROUND).is_equal(
		(auto_free(MeshInstance3D.new()) as MeshInstance3D).layers
	)


func test_assign_walks_the_tree_and_keeps_shadows_unless_told() -> void:
	var root := auto_free(Node3D.new()) as Node3D
	var mesh := MeshInstance3D.new()
	var deep := MeshInstance3D.new()
	var label := Label3D.new()
	root.add_child(mesh)
	mesh.add_child(Node3D.new())
	mesh.get_child(0).add_child(deep)
	root.add_child(label)
	PhotoLayers.assign(root, PhotoLayers.LIVE_AVATAR)
	for visual: VisualInstance3D in [mesh, deep, label]:
		assert_int(visual.layers).is_equal(PhotoLayers.LIVE_AVATAR)
	assert_int(deep.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	PhotoLayers.assign(root, PhotoLayers.PHOTO, false)
	for visual: GeometryInstance3D in [mesh, deep, label]:
		assert_int(visual.layers).is_equal(PhotoLayers.PHOTO)
		assert_int(visual.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_int(PhotoLayers.layers_of(root)).is_equal(PhotoLayers.PHOTO)
