extends GdUnitTestSuite
## The ship's match console in the world (#1604): the crosshair's ray to the screen's pixel, the
## pointer and Interact pushed into the SubViewport (only the host's screen changes a setting),
## and the lobby level's console by the spawn.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"
const LOBBY := "res://levels/lobby/lobby.tscn"


## A screen facing +Z at the origin, the eye 1 m in front of it.
func test_the_ray_meets_the_screens_front_within_reach() -> void:
	var at := Transform3D.IDENTITY
	var eye := Vector3(0, 0, 1)
	assert_float(MatchConsole.ray_hit(at, eye, Vector3.FORWARD, 2.0)).is_equal_approx(1.0, 1e-5)
	# Beyond the reach, from behind, looking away or past the edge: no hit.
	assert_float(MatchConsole.ray_hit(at, eye, Vector3.FORWARD, 0.5)).is_equal(-1.0)
	assert_float(MatchConsole.ray_hit(at, Vector3(0, 0, -1), Vector3.BACK, 2.0)).is_equal(-1.0)
	assert_float(MatchConsole.ray_hit(at, eye, Vector3.BACK, 2.0)).is_equal(-1.0)
	var past := Vector3(MatchConsole.SCREEN_M.x, 0, -1).normalized()
	assert_float(MatchConsole.ray_hit(at, eye, past, 2.0)).is_equal(-1.0)


func test_a_point_on_the_screen_is_its_pixel() -> void:
	var at := Transform3D(Basis(Vector3.UP, PI), Vector3(2, 1, 3))
	var size := MatchConsole.SCREEN_M
	assert_vector(MatchConsole.pixel_of(at, at.origin)).is_equal_approx(
		ConsoleScreen.SIZE * 0.5, Vector2(0.01, 0.01)
	)
	# The screen's own top left (its -X and +Y half sizes) is pixel (0, 0).
	var top_left := at * Vector3(-size.x * 0.5, size.y * 0.5, 0)
	assert_vector(MatchConsole.pixel_of(at, top_left)).is_equal_approx(
		Vector2.ZERO, Vector2(0.01, 0.01)
	)
	var bottom_right := at * Vector3(size.x * 0.5, -size.y * 0.5, 0)
	assert_vector(MatchConsole.pixel_of(at, bottom_right)).is_equal_approx(
		ConsoleScreen.SIZE, Vector2(0.01, 0.01)
	)


func _console(host: bool) -> MatchConsole:
	var mode := load(MODE) as GameMode
	var console: MatchConsole = auto_free(MatchConsole.new())
	add_child(console)
	console.screen.set_mode(mode)
	console.screen.refresh(Preview.fake_model(mode, host), host, host, true)
	return console


## The centre of `control` in the console's SubViewport, in its pixels.
func _centre(control: Control) -> Vector2:
	return control.get_global_rect().get_center()


func test_interact_on_the_hosts_screen_clicks_the_button_under_the_crosshair() -> void:
	var console := _console(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var sent: Array = []
	console.setting_changed.connect(
		func(id: StringName, value: Variant) -> void: sent.append([id, value])
	)
	var more := console.screen.stepper_of(&"match_duration").more
	var before := console.screen.stepper_of(&"match_duration").value
	assert_bool(console.click()).is_false()
	console.aim(_centre(more))
	assert_bool(console.aimed()).is_true()
	assert_object(console.viewport.gui_get_hovered_control()).is_same(more)
	assert_bool(console.click()).is_true()
	assert_array(sent).contains_exactly([[&"match_duration", before + 1]])
	# Off the screen: the hover ends and Interact clicks nothing.
	console.aim(MatchConsole.NOWHERE)
	assert_bool(console.aimed()).is_false()
	assert_bool(console.click()).is_false()
	assert_int(sent.size()).is_equal(1)


func test_interact_on_a_players_screen_changes_nothing() -> void:
	var console := _console(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var sent: Array = []
	console.setting_changed.connect(
		func(id: StringName, value: Variant) -> void: sent.append([id, value])
	)
	var value := console.screen.stepper_of(&"match_duration").value_label
	console.aim(_centre(value))
	assert_bool(console.click()).is_true()
	# The value's right, where the host's More would be.
	console.aim(_centre(value) + Vector2(value.size.x, 0))
	console.click()
	assert_array(sent).is_empty()


func test_the_lobby_puts_the_console_by_the_spawn_facing_it() -> void:
	# The engineer's word (#1095, the M8 review (3)): the console by the lobby's spawn.
	var level: Node3D = auto_free((load(LOBBY) as PackedScene).instantiate())
	add_child(level)
	var screens := get_tree().get_nodes_in_group(MatchConsole.SCREEN_GROUP).filter(
		func(node: Node) -> bool: return level.is_ancestor_of(node)
	)
	assert_int(screens.size()).is_equal(1)
	var screen := screens[0] as Node3D
	var spawns := get_tree().get_nodes_in_group(&"spawn_lobby_player").filter(
		func(node: Node) -> bool: return level.is_ancestor_of(node)
	)
	assert_bool(spawns.is_empty()).is_false()
	var nearest := INF
	for spawn: Node in spawns:
		var at := (spawn as Node3D).global_position
		nearest = minf(
			nearest,
			Vector2(at.x, at.z).distance_to(
				Vector2(screen.global_position.x, screen.global_position.z)
			)
		)
		# The screen faces the spawn row: its +Z points from the screen towards the spawns.
		var towards := at - screen.global_position
		assert_float(screen.global_basis.z.dot(towards)).is_greater(0.0)
	assert_float(nearest).is_less(5.0)
	# The console placed on it shows its screen there.
	var console: MatchConsole = auto_free(MatchConsole.new())
	add_child(console)
	console.level = level
	assert_bool(console.quad.visible).is_true()
	assert_vector(console.quad.global_position).is_equal_approx(
		screen.global_position, Vector3(0.001, 0.001, 0.001)
	)
	assert_int(console.viewport.render_target_update_mode).is_equal(SubViewport.UPDATE_ALWAYS)
	console.level = null
	assert_bool(console.quad.visible).is_false()


func test_e_leaves_the_screen_to_another_target() -> void:
	# One press, one intent (#1604): with a hand-over, an item or a raise under the crosshair too,
	# E is theirs and the screen clicks nothing.
	var console := _console(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var sent: Array = []
	console.setting_changed.connect(
		func(id: StringName, value: Variant) -> void: sent.append([id, value])
	)
	var other := [true]
	console.yields = func() -> bool: return other[0]
	console.aim(_centre(console.screen.stepper_of(&"match_duration").more))
	assert_bool(console.press_interact()).is_false()
	assert_array(sent).is_empty()
	other[0] = false
	assert_bool(console.press_interact()).is_true()
	assert_int(sent.size()).is_equal(1)
