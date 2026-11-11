extends GdUnitTestSuite
## The mouse under the mirror's colour menu (#1394, ARCHITECTURE §4.7.4 "The mouse"; the code review
## of #1394): a host's Game alone over a LoopbackHub on a simulated clock, in the base mode's lobby,
## whose own player is told it holds a mirror place (a MirrorPlaces folded into its own model, as
## the host would send it). The menu frees the mouse; Esc's close leaves it free while the menu is
## up; the place given up captures it again, but not under the Esc menu nor without the focus.
## Headless Godot keeps no mouse mode, so the game's pointer is a FakePointer.

const GAME := preload("res://client/app/game.tscn")
const PORT := 7394
const STEP_USEC := 250000
const MAX_FRAMES := 200
const S := GameFlow.Screen

var _hub: LoopbackHub
var _now := 1000000


## Remembers what the game asked of the mouse, and has the focus while `focus` says so.
class FakePointer:
	extends MousePointer
	var on := false
	var focus := true

	func capture(value: bool) -> void:
		on = value

	func captured() -> bool:
		return on

	func focused() -> bool:
		return focus


func before_test() -> void:
	_hub = LoopbackHub.new()
	_now = 1000000


func after_test() -> void:
	Input.action_release(&"ui_cancel")


func test_the_menu_frees_the_mouse_and_giving_the_place_up_captures_it_again() -> void:
	var game := await _lobby_game(PORT)
	game.pointer.capture(true)
	_hold_place(game, true)
	assert_bool(await _until(func() -> bool: return game.ui.mirror.visible)).is_true()
	assert_bool(game.pointer.captured()).is_false()
	assert_bool(game.player().mouse_free).is_true()
	_hold_place(game, false)
	assert_bool(await _until(func() -> bool: return not game.ui.mirror.visible)).is_true()
	assert_bool(game.pointer.captured()).is_true()
	assert_bool(game.player().mouse_free).is_false()
	await _leave(game)


func test_closing_the_esc_menu_over_it_leaves_the_mouse_free() -> void:
	var game := await _lobby_game(PORT + 1)
	_hold_place(game, true)
	assert_bool(await _until(func() -> bool: return game.ui.mirror.visible)).is_true()
	game.open_esc()
	game.close_esc()
	assert_bool(game.pointer.captured()).is_false()
	# The code review of #1394: a leave hides the menu, so the main menu frees no mouse for it.
	await _leave(game)
	assert_bool(game.ui.mirror.visible).is_false()
	assert_bool(game.ui.frees_mouse()).is_false()


func test_a_place_given_up_under_the_esc_menu_captures_only_when_it_closes() -> void:
	var game := await _lobby_game(PORT + 2)
	_hold_place(game, true)
	assert_bool(await _until(func() -> bool: return game.ui.mirror.visible)).is_true()
	game.open_esc()
	_hold_place(game, false)
	assert_bool(await _until(func() -> bool: return not game.ui.mirror.visible)).is_true()
	assert_bool(game.pointer.captured()).is_false()
	game.close_esc()
	assert_bool(game.pointer.captured()).is_true()
	await _leave(game)


func test_a_place_given_up_without_the_focus_captures_nothing() -> void:
	var game := await _lobby_game(PORT + 3)
	_hold_place(game, true)
	assert_bool(await _until(func() -> bool: return game.ui.mirror.visible)).is_true()
	(game.pointer as FakePointer).focus = false
	_hold_place(game, false)
	assert_bool(await _until(func() -> bool: return not game.ui.mirror.visible)).is_true()
	assert_bool(game.pointer.captured()).is_false()
	await _leave(game)


## The own player leaves; the nodes the leave queued for freeing go before the test ends (orphans
## fail it).
func _leave(game: Game) -> void:
	game.leave()
	await get_tree().process_frame
	await get_tree().process_frame


## The own player holds the lobby's first mirror place (`held`) or none, as a MirrorPlaces from the
## host would say.
func _hold_place(game: Game, held: bool) -> void:
	var model := game.client().model
	var place := -1
	for id: int in model.stations:
		if model.stations[id].kind == &"mirror" and (place < 0 or id < place):
			place = id
	assert_int(place).is_not_equal(-1)
	var stations := PackedInt32Array([place]) if held else PackedInt32Array()
	var peers := PackedInt32Array([model.own_peer]) if held else PackedInt32Array()
	model.fold(&"MirrorPlaces", MirrorPlacesEvent.new(stations, peers).to_dict())


func _lobby_game(port: int) -> Game:
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.load_character = false
	game.launch_args = PackedStringArray(["--host", "--local", "--no-replay", "--port=%d" % port])
	game.clock = func() -> int: return _now
	game.make_transport = _transport
	game.pointer = FakePointer.new()
	add_child(game)
	auto_free(game)
	assert_bool(await _until(func() -> bool: return game.screen() == S.LOBBY)).is_true()
	await _until(func() -> bool: return _has_places(game))
	await _frames(2)
	return game


func _has_places(game: Game) -> bool:
	var model := game.client().model
	for id: int in model.stations:
		if model.stations[id].kind == &"mirror":
			return true
	return false


func _transport() -> NetTransport:
	return LoopbackTransport.new(WireSchema.game(OS.is_debug_build()).kind_table(), _hub)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _until(done: Callable, frames := MAX_FRAMES) -> bool:
	for i in frames:
		if done.call():
			return true
		_now += STEP_USEC
		await get_tree().physics_frame
	return done.call()
