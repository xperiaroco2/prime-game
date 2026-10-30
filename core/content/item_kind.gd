class_name ItemKind
extends ContentPart
## A thing a player can hold, and what using it does (ARCHITECTURE §9.3): the MVP's Package and
## Knife. Its actions apply while a player holds an item of this kind in the hand (the knife's
## `Use`), never on the belt; the display name is the HUD's hand or belt item; the spawn tag names
## the markers it is placed on (§9.6).

## The longest `vanish_seconds`: an hour (the cooking ADR, C10).
const MAX_VANISH_SECONDS := 3600

@export var id: StringName
@export var display_name: String
## The markers a deal places it on (§9.6), or empty for a kind no deal places: one only given or
## changed into (the cooking ADR's CE18 (a), C11). The kind's check takes an empty tag; each part
## that places a kind on markers (SpawnItems, Delivery's package) refuses one without a tag in its
## own check, where the tag is used.
@export var spawn_tag: StringName
## How many hands it takes, 1 or 2 (vision revision 1, Two hands): a one-handed item may go on the
## belt, a two-handed one never does, and a player holding one in the hand cannot swap (§7.1). The
## neutral default is out of bounds on purpose: the data sets it (the base mode's Package: 2,
## Knife: 1), so the mode check refuses an item kind that forgot it.
@export var hands := 0
## How long an item of this kind may lie on the ground before it vanishes, in whole seconds since
## it last came to rest (the cooking ADR, CD6 (c), CE3; VanishTicks, ARCHITECTURE §9.4.5): 0, the
## default, never; else 1 to MAX_VANISH_SECONDS. Only a phase that lists VanishTicks removes an
## item, so ModeCheck refuses a kind with it in a mode where no phase lists one.
@export var vanish_seconds := 0
## The most items of this kind that may exist at once, given or dealt (the cooking ADR, CE3, #770;
## GiveItem): 0, the default, no cap; else 1 to MatchState.MAX_ITEM_ID. A GiveItem of a kind at
## its cap first vanishes the loose one of the kind that has lain longest; with none loose it is
## refused `unavailable`. A technical bound far above play, not a game rule.
@export var max_items := 0
## Rules on the intents that name an item lying on the ground (Interact naming `item`; the cooking
## ADR's CE1, #770: a box's take): the only rules such an intent is routed to (Match), never the
## role's or the mode's, which are written for station targets. The rule's conditions say whether
## the item may be used now (ItemOnGround, InReach, InSight); a kind with none here refuses an
## Interact naming one of its items `nothing_to_do`.
@export var target_actions: Array[Rule] = []
## Rules on the intents a player sends while holding an item of this kind in the hand (Use,
## UseSecondary).
@export var actions: Array[Rule] = []


## Whether an item of this kind vanishes when left lying (`vanish_seconds` set).
func vanishes() -> bool:
	return vanish_seconds > 0


## Whether it takes both hands (`hands` 2): it is never on the belt.
func is_two_handed() -> bool:
	return hands >= 2


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if id.is_empty():
		found.append("an item kind has no id")
	append_found(found, [out_of_bounds("item kind %s hands" % id, hands, 1, 2)])
	if vanish_seconds != 0:
		var label := "item kind %s vanish_seconds" % id
		append_found(found, [out_of_bounds(label, vanish_seconds, 1, MAX_VANISH_SECONDS)])
	if max_items != 0:
		var cap_label := "item kind %s max_items" % id
		append_found(found, [out_of_bounds(cap_label, max_items, 1, MatchState.MAX_ITEM_ID)])
	return found


## Whether a GiveItem of this kind is capped (`max_items` set).
func is_capped() -> bool:
	return max_items > 0
