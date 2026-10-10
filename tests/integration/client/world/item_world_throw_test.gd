extends GdUnitTestSuite
## ItemWorld's throw (ARCHITECTURE §4.7.25; #645) with a real local player, a ClientSession
## harness and the throw fixture mode as the client's own mode copy: the throw key starts the
## predicted arc and its launch sound at once; the host's own ItemThrown repeats no sound; the
## thrown item's ItemPlaced plays its landing sound only once the drawn item lands, while a
## put-down's plays at once.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")

var _world: Node3D
var _player: PlayerController
var _harness: Harness
var _model: ClientModel
var _items: ItemWorld


func before_test() -> void:
	AudioBuses.ensure()
	_world = World.new()
	add_child(_world)
	_player = _world.call(&"add_player", Vector3.ZERO) as PlayerController
	_harness = Harness.new()
	_harness.welcome(&"round")
	_model = _harness.session.model
	_items = ItemWorld.new()
	_world.add_child(_items)
	var avatars := AvatarViews.new()
	_world.add_child(avatars)
	_items.setup(_harness.session, FixtureThrowModes.basic(), avatars)
	_items.set_player(_player)
	_items.interactions.reads_device_input = false
	_items.sounds.listener = func() -> Variant: return _player.global_position + Vector3.UP


func after_test() -> void:
	_world.free()
	_harness.close()


func test_the_launch_plays_at_the_press_and_the_landing_when_the_drawn_item_lands() -> void:
	_event(&"ItemSpawned", {"item": 5, "kind": &"tool", "position": Vector3(0, 0, -1)})
	_event(&"ItemPickedUp", {"peer": _model.own_peer, "item": 5})
	await get_tree().physics_frame
	# The pick-up made its own sound.
	var heard := _items.sounds.played()
	var seq := _items.interactions.throw()
	assert_int(seq).is_greater(0)
	assert_int(_items.sounds.played()).is_equal(heard + 1)
	assert_bool(_items.items.is_predicting()).is_true()
	# The host's answer: the launch from the same eye and velocity; no second launch sound.
	var arc: ItemArc = _items.items.flights.arcs[5]
	var launch := {
		"item": 5,
		"peer": _model.own_peer,
		"origin": arc.origin,
		"velocity": arc.velocity,
		"gravity": arc.gravity,
		"tick": 40,
	}
	_event(&"ItemThrown", launch)
	assert_int(_items.sounds.played()).is_equal(heard + 1)
	# The item lands under the arc's point 6 ticks on, once the thrower's clock is past it.
	while arc.n < 6.0:
		await get_tree().physics_frame
	var above := ItemFlight.point(arc.origin, arc.velocity, arc.gravity, 6)
	var rest := Vector3(above.x, 0, above.z)
	_event(&"ItemPlaced", {"item": 5, "position": rest, "cause": Items.THROWN})
	assert_int(_items.sounds.played()).is_equal(heard + 1)
	var frames := 0
	while _items.sounds.played() < heard + 2 and frames < 120:
		await get_tree().physics_frame
		frames += 1
	assert_int(_items.sounds.played()).is_equal(heard + 2)
	assert_vector(_items.items.view_of(5).global_position).is_equal(rest)
	# A put-down's sound plays at once.
	_event(&"ItemPlaced", {"item": 5, "position": Vector3(1, 0, 0), "cause": &"put_down"})
	assert_int(_items.sounds.played()).is_equal(heard + 3)


## An event as the session delivers it: folded into the model, then heard by ItemWorld.
func _event(event_name: StringName, fields: Dictionary) -> void:
	_model.fold(event_name, fields)
	_items.on_event(event_name, fields)
