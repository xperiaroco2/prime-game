class_name FixtureVanishModes
extends RefCounted
## Game modes for the unit tests of items that vanish when left lying (VanishTicks, Items.vanish,
## the item ids; the cooking ADR §7, C10), built in code on FixtureItemModes.basic() (a part's
## unit tests never load `content/`, ARCHITECTURE §9.6). The numbers are a test's, not a decision.
##
## basic(): FixtureItemModes.basic() with the one-handed item kind `crumb`, which vanishes after
## CRUMB_S seconds, and Round listing VanishTicks; `crumb` items spawned (FixtureSpawnItem) at the
## SPOTS when the round starts. The spots are in P1's reach from HERE.

## How long a crumb lies before it vanishes: 1200 ticks.
const CRUMB_S := 60
const CRUMB_TICKS := 1200
## Where P1 stands: its round spot (FixtureModes.layouts).
const HERE := Vector3(10, 0, 5)
const SPOTS: Array[Vector3] = [Vector3(11, 0, 5), Vector3(10, 0, 6), Vector3(9, 0, 5)]


static func basic(crumbs: int = 1) -> GameMode:
	var mode := FixtureItemModes.basic()
	mode.item_kinds.append(vanishing(&"crumb", CRUMB_S))
	mode.find_phase(&"round").tick_systems.append(VanishTicks.new())
	for i in crumbs:
		spawn_at_start(mode, &"crumb", SPOTS[i])
	return mode


## Takes VanishTicks off the mode's phase `phase_id`.
static func unlist(mode: GameMode, phase_id: StringName) -> void:
	var spec := mode.find_phase(phase_id)
	var kept: Array[TickSystem] = []
	for system: TickSystem in spec.tick_systems:
		if not system is VanishTicks:
			kept.append(system)
	spec.tick_systems = kept


## A one-handed item kind of `id` that vanishes after `seconds`.
static func vanishing(id: StringName, seconds: int) -> ItemKind:
	var kind := FixtureItemModes.item_kind(id, [])
	kind.vanish_seconds = seconds
	return kind


## An item of the mode's kind `kind_id` spawned at `at` when the round starts (Lobby's
## `all_ready` row), as a deal would.
static func spawn_at_start(mode: GameMode, kind_id: StringName, at: Vector3) -> void:
	mode.find_transition(&"lobby", &"all_ready").actions.append(spawn(mode, kind_id, at))


static func spawn(mode: GameMode, kind_id: StringName, at: Vector3) -> FixtureSpawnItem:
	var made := FixtureSpawnItem.new()
	made.kind = mode.find_item_kind(kind_id)
	made.at = at
	return made


## Every ItemVanished emitted so far, in order, as [tick, item].
static func vanished(game: Match) -> Array[Array]:
	var found: Array[Array] = []
	for emitted: EmittedEvent in game.emitted():
		if emitted.event is ItemVanishedEvent:
			found.append([emitted.tick, (emitted.event as ItemVanishedEvent).item])
	return found
