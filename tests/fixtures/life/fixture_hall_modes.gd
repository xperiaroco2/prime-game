class_name FixtureHallModes
extends RefCounted
## A combat mode whose Round's dead wait in a hall and come back through a print (#1489): the
## markers FixtureModes.HALLS, a hall radius of RADIUS_M around their middle, a print of PRINT_S
## seconds (PRINT_TICKS host ticks at 20 Hz), and a Round that lets the dead move, interact, pick up
## and use.

const MIDDLE := Vector3(1005, 0, 1000)
const RADIUS_M := 20.0
const PRINT_S := 2.0
const PRINT_TICKS := 40


static func mode() -> GameMode:
	var mode := FixtureCombatModes.respawning()
	var respawn := FixtureCombatModes.life_ticks(mode).respawn
	respawn.print_s = PRINT_S
	respawn.hall_tag = FixtureModes.HALL_TAG
	respawn.hall_rng_purpose = &"hall"
	respawn.hall_radius_m = RADIUS_M
	mode.actions.append(FixtureModes.rule(Intents.INTERACT, [], []))
	var round_spec := mode.find_phase(&"round")
	for intent: StringName in [Intents.MOVE_CLAIM, Intents.INTERACT, Intents.PICK_UP, Intents.USE]:
		round_spec.accepts.append(AcceptSpec.of(intent, AcceptSpec.From.DEAD))
	return mode
