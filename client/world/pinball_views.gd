class_name PinballViews
extends Node3D
## The lobby's pinball in every window (#1400; ARCHITECTURE §4.7.63; GDD §3 "The pinball"): the
## table drawn on the machine for everyone (PinballTableView: the flippers from PinballState's
## `left` and `right`, the ball from the snapshots at the remote bodies' render tick), the
## machine's display (PinballDisplay), and for the seated player alone the close-up camera
## (PinballCloseUp) and the flipper keys (PinballKeys). Everything comes from the own ClientModel
## (ClientPinball, §7.1.22): the client predicts nothing and sends only the keys' intents.
##
## The level gives the places, Marker3Ds found by group (placeholders the engineer moves in the
## editor): the table's mount (TABLE_GROUP, the table scene's origin and axes: its -Z up the
## table), the close-up's camera pose (CLOSE_UP_GROUP) and the display's (DISPLAY_GROUP, its text
## facing its +Z). A level without the mount draws no table; without the close-up marker the seat
## shows no close-up; without the display marker no display.

## After AvatarViews (-80), which sets this frame's render tick (drawn_at), and the viewfinder (7).
const PHYSICS_PRIORITY := 8
const TABLE_GROUP := &"pinball_table"
const CLOSE_UP_GROUP := &"pinball_closeup"
const DISPLAY_GROUP := &"pinball_display"

var model: ClientModel
## The render tick of the remote bodies this frame: () -> float (AvatarViews.drawn_at).
var drawn_at := Callable()
## The level the markers are in; setting it places the views (ItemWorld.set_level).
var level: Node:
	set(value):
		level = value
		_place()

var table := PinballTableView.new()
var display := PinballDisplay.new()
var close_up := PinballCloseUp.new()
var keys := PinballKeys.new()
var track := PinballBallTrack.new()

var _game := 0
## The level's display marker, or null: the display shows only with one.
var _display_at: Node3D


func _init() -> void:
	name = "PinballViews"
	process_physics_priority = PHYSICS_PRIORITY
	table.visible = false
	display.visible = false
	for each: Node in [table, display, close_up, keys]:
		add_child(each)


func _physics_process(delta: float) -> void:
	if model == null or not table.visible:
		return
	table.left = model.pinball.left
	table.right = model.pinball.right
	table.step(delta)
	var render := drawn_at.call() as float if drawn_at.is_valid() else -1.0
	table.show_ball(track.at(render) if render >= 0.0 else null)


func _process(_delta: float) -> void:
	if _display_at != null:
		display.show_state(model)


## Every snapshot (ClientSession.snapshot_received, emitted after the model folded it, also for
## one it skipped): the newest folded ball joins the track; a new game starts it afresh.
func on_snapshot(_tick: int, _avatars: Dictionary) -> void:
	if model == null:
		return
	if model.pinball.game_serial() != _game:
		_game = model.pinball.game_serial()
		track.clear()
	track.add(model.pinball.ball_tick, model.pinball.ball_shown, model.pinball.ball)


## The session's events (ItemWorld): a LoadMatch clears the match, so the close-up snaps back.
func on_event(event_name: StringName, _fields: Dictionary) -> void:
	if event_name == &"LoadMatch":
		close_up.snap()
		track.clear()
		keys.clear()


## Forgets the session (it ended).
func clear() -> void:
	close_up.clear()
	keys.clear()
	keys.model = null
	keys.send = Callable()
	track.clear()
	table.rest()
	display.show_state(null)
	model = null
	drawn_at = Callable()
	_game = 0


## Places the table and the display on `level`'s markers and gives the close-up its marker; with
## no level (or no marker) each is hidden, and a close-up up snaps back to the eye.
func _place() -> void:
	close_up.snap()
	var mount := _marker(TABLE_GROUP)
	table.visible = mount != null and table.build()
	if table.visible:
		table.global_transform = mount.global_transform
	else:
		table.rest()
	_display_at = _marker(DISPLAY_GROUP)
	display.visible = _display_at != null
	if _display_at != null:
		display.global_transform = _display_at.global_transform
	close_up.marker = _marker(CLOSE_UP_GROUP)


## The level's marker of `group`, or null (no level, none, or the level not in the tree).
func _marker(group: StringName) -> Node3D:
	if not is_inside_tree() or not is_instance_valid(level) or not level.is_inside_tree():
		return null
	for node: Node in level.get_tree().get_nodes_in_group(group):
		if level.is_ancestor_of(node) and node is Node3D:
			return node as Node3D
	return null
