extends GdUnitTestSuite
## The ship's match console in the running game (#1604): a host and a guest, two Game roots over a
## LoopbackHub on a simulated clock (as game_map_choice_test.gd, each in its own SubViewport world),
## in the lobby level with its console. Each player stands in front of the screen looking at a
## stepper: the crosshair's ray finds it (MatchConsole._cast through the level's physics), the
## host's Interact changes the setting for everyone, the guest's changes nothing, and under the Esc
## menu the screen takes no key.

const GAME := preload("res://client/app/game.tscn")
const PORT := 7452
## The simulated clock moves this much per physics frame: five host ticks.
const STEP_USEC := 250000
const MAX_FRAMES := 600
## How far in front of the screen the player stands, metres (within MatchConsole.REACH_M).
const STAND_M := 1.0

const S := GameFlow.Screen

var _hub: LoopbackHub
var _now := 1000000


func before_test() -> void:
	_hub = LoopbackHub.new()
	_now = 1000000


func test_the_hosts_interact_on_the_console_changes_the_setting_for_everyone() -> void:
	var host := _game(["--host", "--local", "--no-replay", "--port=%d" % PORT])
	var guest := _game(["--join=127.0.0.1", "--port=%d" % PORT])
	var games: Array[Game] = [host, guest]
	assert_bool(await _until(_all_in_lobby.bind(games))).is_true()
	for game: Game in games:
		assert_bool(game.items().console.quad.visible).is_true()
		assert_bool(game.items().console.listening).is_true()
	var before: int = host.client().model.settings[&"match_duration"]
	# The host looks at the duration's More: the ray finds it, the host's screen has the arrows.
	var more := host.items().console.screen.stepper_of(&"match_duration").more
	assert_bool(more.is_visible_in_tree()).is_true()
	_look_at(host, more)
	assert_bool(await _until(func() -> bool: return host.items().console.aimed())).is_true()
	assert_bool(host.items().console.press_interact()).is_true()
	assert_bool(await _until(_setting_is.bind(games, &"match_duration", before + 1))).is_true()
	# The host steps aside, out of the guest's way to the screen.
	var host_player := host.player()
	var aside := host.items().console.quad.global_transform.basis.x.normalized() * 3.0
	host_player.teleport(Transform3D(host_player.global_basis, host_player.global_position + aside))
	# The guest's screen shows the value alone; its Interact where More would be changes nothing.
	var guest_more := guest.items().console.screen.stepper_of(&"match_duration").more
	assert_bool(guest_more.is_visible_in_tree()).is_false()
	var value := guest.items().console.screen.stepper_of(&"match_duration").value_label
	_look_at(guest, value)
	assert_bool(await _until(func() -> bool: return guest.items().console.aimed())).is_true()
	guest.items().console.press_interact()
	for i in 20:
		_now += STEP_USEC
		await get_tree().physics_frame
	assert_bool(_setting_is(games, &"match_duration", before + 1)).is_true()
	# Under the Esc menu the screen takes no key and the pointer leaves it.
	_look_at(host, more)
	assert_bool(await _until(func() -> bool: return host.items().console.aimed())).is_true()
	host.open_esc()
	assert_bool(await _until(func() -> bool: return not host.items().console.aimed())).is_true()
	assert_bool(host.items().console.listening).is_false()
	await _leave(host, guest)


## Stands `game`'s own player STAND_M in front of the console's screen, looking at `control`'s
## centre on it.
func _look_at(game: Game, control: Control) -> void:
	var console := game.items().console
	var at := console.quad.global_transform
	var pixel := control.get_global_rect().get_center()
	var uv := pixel / ConsoleScreen.SIZE - Vector2(0.5, 0.5)
	var target := at * Vector3(uv.x * MatchConsole.SCREEN_M.x, -uv.y * MatchConsole.SCREEN_M.y, 0)
	var player := game.player()
	var feet := at.origin + at.basis.z.normalized() * STAND_M
	feet.y = player.global_position.y
	player.teleport(Transform3D(player.global_basis, feet))
	var eye := player.get_camera().global_position
	var towards := target - eye
	player.face(towards)
	var level := Vector2(towards.x, towards.z).length()
	player.look(0.0, atan2(towards.y, level))


func _leave(host: Game, guest: Game) -> void:
	guest.leave()
	host.leave()
	var on_menu := func() -> bool: return host.screen() == S.MENU and guest.screen() == S.MENU
	assert_bool(await _until(on_menu)).is_true()
	await get_tree().process_frame
	await get_tree().process_frame


func _game(args: Array[String]) -> Game:
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.load_character = false
	game.launch_args = PackedStringArray(args)
	game.clock = _clock
	game.make_transport = _transport
	var machine := SubViewport.new()
	machine.own_world_3d = true
	machine.render_target_update_mode = SubViewport.UPDATE_DISABLED
	machine.add_child(game)
	add_child(machine)
	auto_free(game)
	auto_free(machine)
	return game


func _clock() -> int:
	return _now


func _transport() -> NetTransport:
	return LoopbackTransport.new(WireSchema.game(OS.is_debug_build()).kind_table(), _hub)


## Steps the clock and the frames until `done` holds, at most MAX_FRAMES physics frames.
func _until(done: Callable) -> bool:
	for i in MAX_FRAMES:
		if done.call():
			return true
		_now += STEP_USEC
		await get_tree().physics_frame
	return done.call()


func _all_in_lobby(games: Array[Game]) -> bool:
	for game: Game in games:
		if game.client() == null or game.screen() != S.LOBBY or game.ui.screen != S.LOBBY:
			return false
		if game.client().model.roster.size() != games.size() or game.player() == null:
			return false
		if game.level() == null:
			return false
	return true


func _setting_is(games: Array[Game], id: StringName, value: int) -> bool:
	for game: Game in games:
		if game.client() == null or game.client().model.settings.get(id, -1) != value:
			return false
	return true
