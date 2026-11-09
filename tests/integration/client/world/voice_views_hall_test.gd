extends GdUnitTestSuite
## VoiceViews.hears in the dead's hall (#1489; ARCHITECTURE §6): a dead listener waiting in the
## hall hears only the dead; a dead listener outside a hall nobody; the living no dead.

const World := preload("res://tests/integration/client/world/voice_test_world.gd")
const OWN := World.OWN
const TALKER := World.TALKER
const OTHER := World.OTHER
const AT_TICK := 1000

var _world: World


func before_test() -> void:
	AudioBuses.ensure()
	_world = World.new()
	add_child(_world)


func after_test() -> void:
	_world.free()


func test_the_dead_in_the_hall_hear_only_the_dead() -> void:
	_to_phase(&"round", ClientModel.Life.DEAD)
	assert_bool(_world.voices.hears(TALKER, AT_TICK)).is_true()
	assert_bool(_world.voices.hears(OTHER, AT_TICK)).is_false()


func test_the_living_hear_no_dead() -> void:
	_to_phase(&"round", ClientModel.Life.ALIVE)
	assert_bool(_world.voices.hears(TALKER, AT_TICK)).is_false()
	assert_bool(_world.voices.hears(OTHER, AT_TICK)).is_true()


func test_the_dead_outside_a_hall_hear_nobody() -> void:
	_to_phase(&"lobby", ClientModel.Life.DEAD)
	assert_bool(_world.voices.hears(TALKER, AT_TICK)).is_false()
	assert_bool(_world.voices.hears(OTHER, AT_TICK)).is_false()


## The own player `own`, TALKER dead and OTHER living, in `phase`.
func _to_phase(phase: StringName, own: ClientModel.Life) -> void:
	_world.model.phase = phase
	_world.voices.on_event(&"PhaseChanged", {"phase": phase, "end_tick": -1})
	_world.model.lives[OWN] = own
	_world.model.lives[TALKER] = ClientModel.Life.DEAD
	_world.model.lives[OTHER] = ClientModel.Life.ALIVE
