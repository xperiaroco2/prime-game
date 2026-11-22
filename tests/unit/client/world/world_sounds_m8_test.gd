extends GdUnitTestSuite
## WorldSounds' M8 sounds (#1674) on the base mode: a hit lands only on the victim's own client,
## from its Damaged just after a swing within strike reach (heavy for a two-handed item in the
## swinger's hand; none after no such swing or the own swing), at its ears; the events' sounds (a
## heavy swing, the death, the return, the raise, the tap, the drink, a knockdown) through
## SoundChooser; and a player going limp in the lobby falls with the knockdown's sound, edges only.

const BASE_MODE := "res://content/modes/base_mode.tres"
const OWN := 1
const OTHER := 2
const FAR := 3
const EARS := Vector3(0, 1.5, 0)

var _mode: GameMode
var _model: ClientModel
var _sounds: Placed


## WorldSounds with its players drawn where a test says (no AvatarViews).
class Placed:
	extends WorldSounds
	var at: Dictionary[int, Vector3] = {}

	func position_of(peer: int) -> Variant:
		return at.get(peer)


func before_test() -> void:
	_mode = load(BASE_MODE) as GameMode
	_model = ClientModel.new(_mode)
	_model.own_peer = OWN
	_sounds = auto_free(Placed.new())
	add_child(_sounds)
	_sounds.model = _model
	_sounds.mode = _mode
	_sounds.listener = func() -> Variant: return EARS
	_sounds.at = {OWN: Vector3.ZERO, OTHER: Vector3(1, 0, 1)}


func test_a_hit_after_a_swing_plays_at_the_victims_ears() -> void:
	_sounds.on_event(&"Swung", {"peer": OTHER, "facing": Vector3.FORWARD})
	_sounds.on_event(&"Damaged", _damaged())
	assert_int(_sounds.hits()).is_equal(1)
	var hit := _last()
	assert_that(hit.position).is_equal(EARS)
	assert_object(hit.stream).is_same(_sounds.sfx.stream_for(SfxSet.HIT_FIST))


func test_a_two_handed_swing_lands_heavy() -> void:
	_hold(OTHER, 30, &"crystal_charged")
	_sounds.on_event(&"Swung", {"peer": OTHER, "facing": Vector3.FORWARD})
	assert_object(_last().stream).is_same(_sounds.sfx.stream_for(SfxSet.SWING_HEAVY))
	_sounds.on_event(&"Damaged", _damaged())
	assert_object(_last().stream).is_same(_sounds.sfx.stream_for(SfxSet.HIT_HEAVY))


func test_no_swing_near_or_the_own_swing_lands_nothing() -> void:
	# The engine's zap of a crystal's carrier damages with no swing: its own zap plays.
	_sounds.on_event(&"Damaged", _damaged())
	_sounds.on_event(&"Swung", {"peer": OWN, "facing": Vector3.FORWARD})
	_sounds.on_event(&"Damaged", _damaged())
	assert_int(_sounds.hits()).is_equal(0)
	# A swing far beyond any blow's reach is no hit's, and a crystal swung there makes no own hit
	# heavy: a fist's blow by the side lands as a fist's.
	_sounds.at[FAR] = Vector3(30, 0, 0)
	_hold(FAR, 31, &"crystal_charged")
	_sounds.on_event(&"Swung", {"peer": FAR, "facing": Vector3.FORWARD})
	_sounds.on_event(&"Damaged", _damaged())
	assert_int(_sounds.hits()).is_equal(0)
	_sounds.on_event(&"Swung", {"peer": OTHER, "facing": Vector3.FORWARD})
	_sounds.on_event(&"Swung", {"peer": FAR, "facing": Vector3.FORWARD})
	_sounds.on_event(&"Damaged", _damaged())
	assert_object(_last().stream).is_same(_sounds.sfx.stream_for(SfxSet.HIT_FIST))
	assert_float(SoundChooser.strike_reach_m(_mode)).is_greater(0.0)


func test_each_event_plays_its_m8_sound() -> void:
	var events: Array[Array] = [
		[&"Died", {"peer": OTHER, "position": Vector3(2, 0, 0)}, SfxSet.DEATH],
		[&"Respawned", {"peer": OTHER, "position": Vector3(0, 0, 3)}, SfxSet.RESPAWN],
		[&"Revived", {"peer": OTHER}, SfxSet.REVIVE],
		[&"KnockedDown", {"peer": OTHER, "position": Vector3(1, 0, 0)}, SfxSet.KNOCKDOWN],
		[
			&"ItemSpawned",
			{"item": 50, "kind": &"mug", "position": Vector3(0, 1, 2)},
			SfxSet.TAP_POUR
		],
	]
	for each: Array in events:
		_model.fold(each[0] as StringName, each[1] as Dictionary)
		_sounds.on_event(each[0] as StringName, each[1] as Dictionary)
		var label := String(each[0] as StringName)
		var stream := _sounds.sfx.stream_for(each[2] as StringName)
		assert_object(stream).override_failure_message(label).is_not_null()
		assert_object(_last().stream).override_failure_message(label).is_same(stream)
	# The drink: the mug in a hand turns empty, its gulps at its holder.
	_model.fold(&"ItemPickedUp", {"peer": OTHER, "item": 50})
	_model.fold(&"ItemChanged", {"item": 50, "kind": &"mug_empty"})
	_sounds.on_event(&"ItemChanged", {"item": 50, "kind": &"mug_empty"})
	assert_object(_last().stream).is_same(_sounds.sfx.stream_for(SfxSet.DRINK))
	assert_that(_last().position).is_equal(Vector3(1, 0, 1))


func test_a_player_going_limp_falls_with_the_knockdowns_sound_once() -> void:
	_model.avatars[OTHER] = {"limp": false}
	_sounds._physics_process(0.016)
	var played_before := _sounds.played()
	_model.avatars[OTHER] = {"limp": true}
	_sounds._physics_process(0.016)
	_sounds._physics_process(0.016)
	assert_int(_sounds.played()).is_equal(played_before + 1)
	assert_object(_last().stream).is_same(_sounds.sfx.stream_for(SfxSet.KNOCKDOWN))
	assert_that(_last().position).is_equal(Vector3(1, 0, 1))


## The own player is in its own snapshot only while it holds still: its first sight limp is its
## fall.
func test_the_own_player_going_limp_falls_too() -> void:
	_sounds._physics_process(0.016)
	_model.avatars[OWN] = {"limp": true}
	_sounds._physics_process(0.016)
	assert_int(_sounds.played()).is_equal(1)
	assert_object(_last().stream).is_same(_sounds.sfx.stream_for(SfxSet.KNOCKDOWN))
	assert_that(_last().position).is_equal(Vector3.ZERO)


func test_a_player_first_seen_limp_plays_nothing() -> void:
	_model.avatars[OTHER] = {"limp": true}
	_sounds._physics_process(0.016)
	assert_int(_sounds.played()).is_equal(0)


## A Damaged's fields as the wire decodes them: the victim alone gets one, and it names nobody.
func _damaged() -> Dictionary:
	return DamagedEvent.new(OWN, 250, 750).to_dict()


func _hold(peer: int, item: int, kind: StringName) -> void:
	_model.fold(&"ItemSpawned", {"item": item, "kind": kind, "position": Vector3.ZERO})
	_model.fold(&"ItemPickedUp", {"peer": peer, "item": item})


func _last() -> AudioStreamPlayer3D:
	var started := _sounds.find_children("*", "AudioStreamPlayer3D", false, false)
	return started[-1] as AudioStreamPlayer3D
