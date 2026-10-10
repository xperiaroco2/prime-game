class_name SoundChooser
extends RefCounted
## Which placeholder world sound an event plays, and where (ARCHITECTURE §4.7, a hearing range;
## the M4 ADR's §3 item 10, E33 (a), D9; M4-8), pure. `Swung`, `ItemPickedUp` and `ItemPlaced`
## reach everyone with a position: a sound with no cut-off would tell every client, through the
## walls, where a package was just put down or a fight goes on. So a sound plays only within
## HEARING_RANGE_M of the ears (E40's amendment of E33, the engineer's: the own eye, the own body's
## head while downed, the spectated target's eye or body; LifeView's Ears), and nothing at all for
## an event from farther away; each player also sets `AudioStreamPlayer3D.max_distance` to it.
## Occlusion muffles, never cuts: WorldSounds casts one ray to a chosen sound's `aim` as it starts
## (M5-7).
##
## Where each one plays:
## - Swung: at the swinger: the local player for the own swing, else its interpolated pose;
## - ItemPickedUp: where the item lay (the model's fold keeps the item's last resting place);
## - ItemPlaced: at the event's position;
## - ItemThrown: at the launch's origin, the thrower's eye (37e: ItemViews hands it over when the
##   drawn item launches, and a thrown item's ItemPlaced when it lands at its rest). ItemThrown
##   reaches everyone with its origin: uncut, the launch would tell every client where a package
##   was just thrown to hide it.

## About 12 m (E33 (a)): a placeholder, "not a decision".
const HEARING_RANGE_M := 12.0
## How far above where it plays the occlusion ray aims (M5-7). A swing plays at the swinger's feet
## and an item on what it lies on: a ray to a point on a floor, a step or a table reaches it only
## from above, so ears below that surface, or a curb in front of the feet, would muffle a sound in
## plain view. A swing aims at about a standing player's chest, an item a hand above its surface.
## Placeholders, "not a decision".
const SWING_AIM_M := 1.0
const ITEM_AIM_M := 0.3
## A launch plays at the thrower's eye, in the air: the ray aims at the origin itself.
const THROW_AIM_M := 0.0

const SWING := &"swing"
const PICK_UP := &"pick_up"
const PUT_DOWN := &"put_down"
const THROW := &"throw"


## One sound to play: where it plays, and where the occlusion ray aims (`lift` above it).
class Sound:
	extends RefCounted
	var id: StringName
	var position := Vector3.ZERO
	var aim := Vector3.ZERO

	func _init(sound_id: StringName, at: Vector3, lift: float) -> void:
		id = sound_id
		position = at
		aim = at + Vector3.UP * lift


## The sound for event `event_name` (already folded into `model`) within `hearing_m` of
## `listener`, or null: a silent event, an unknown place, or too far. `position_of` gives a peer's
## position (a Vector3), or null when the client draws no such player.
static func choose(
	event_name: StringName,
	fields: Dictionary,
	model: ClientModel,
	position_of: Callable,
	listener: Vector3,
	hearing_m := HEARING_RANGE_M
) -> Sound:
	var sound := source(event_name, fields, model, position_of)
	if sound == null or not audible(sound.position, listener, hearing_m):
		return null
	return sound


## The sound an event makes and where, wherever the listener is; null for a silent event or an
## unknown place.
static func source(
	event_name: StringName, fields: Dictionary, model: ClientModel, position_of: Callable
) -> Sound:
	match event_name:
		&"Swung":
			var at: Variant = position_of.call(fields["peer"] as int)
			return Sound.new(SWING, at as Vector3, SWING_AIM_M) if at is Vector3 else null
		&"ItemPickedUp":
			var item: ClientModel.Item = model.items.get(fields["item"] as int)
			return Sound.new(PICK_UP, item.position, ITEM_AIM_M) if item != null else null
		&"ItemPlaced":
			return Sound.new(PUT_DOWN, fields["position"] as Vector3, ITEM_AIM_M)
		&"ItemThrown":
			return Sound.new(THROW, fields["origin"] as Vector3, THROW_AIM_M)
	return null


## Whether a sound at `at` is within `hearing_m` of `listener`.
static func audible(at: Vector3, listener: Vector3, hearing_m := HEARING_RANGE_M) -> bool:
	return at.distance_to(listener) <= hearing_m
