class_name FixtureGeneratorClient
extends RefCounted
## A client's view of a dealt Generator (#801), for the client's tests: a ClientModel of
## FixtureGeneratorModes.basic() fed the events a client receives (StationPlaced for the generator
## and the active switches, ZoneProgress, SwitchChanged, ButtonPressed), never `core/` state.
## Station ids: GENERATOR for the generator at FixtureGeneratorModes.GENERATOR_AT, then FIRST_SWITCH
## up for the active switches, at FixtureGeneratorModes.SWITCH_SPOTS in order.

const GENERATOR := 3
const FIRST_SWITCH := 4
const OWN := 1


## A model of `mode` (FixtureGeneratorModes.basic(active) when null) in its round, the own peer
## OWN living, with the generator and `active` switches placed and the charge's ZoneProgress at 0.
static func dealt(
	active: int = FixtureGeneratorModes.SWITCHES, mode: GameMode = null
) -> ClientModel:
	var game_mode := mode if mode != null else FixtureGeneratorModes.basic(active)
	var model := ClientModel.new(game_mode)
	model.own_peer = OWN
	fold(model, PhaseChangedEvent.new(&"round", 1000))
	fold(
		model,
		StationPlacedEvent.new(
			GENERATOR, &"generator", Color.WHITE, FixtureGeneratorModes.GENERATOR_AT
		)
	)
	for i in active:
		fold(
			model,
			StationPlacedEvent.new(
				FIRST_SWITCH + i, &"switch", Color.WHITE, FixtureGeneratorModes.SWITCH_SPOTS[i]
			)
		)
	fold(model, ZoneProgressEvent.new(GENERATOR, 0, FixtureGeneratorModes.NEEDED, false, 0))
	return model


## Folds `event` into `model`, as the session does with what it decodes.
static func fold(model: ClientModel, event: MatchEvent) -> void:
	model.fold(event.event_name(), event.to_dict())


## Switch `index` (0 up) turned `on`.
static func switch_to(model: ClientModel, index: int, on: bool) -> void:
	fold(model, SwitchChangedEvent.new(FIRST_SWITCH + index, on))


## The charge: `ticks` of NEEDED at host tick `tick`, `counting` or not.
static func charge(model: ClientModel, ticks: int, counting: bool, tick: int) -> void:
	fold(
		model, ZoneProgressEvent.new(GENERATOR, ticks, FixtureGeneratorModes.NEEDED, counting, tick)
	)
