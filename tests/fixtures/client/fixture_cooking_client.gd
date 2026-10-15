class_name FixtureCookingClient
extends RefCounted
## A client's view of a dealt Cooking task (#776), for the client's tests: a ClientModel of
## FixtureCookingModes.basic() fed the events a client receives (StationPlaced for the two boards,
## the grill, the beds and the places, OrderPosted, HerbsDealt, ItemSpawned, ItemPickedUp,
## IngredientPlaced, GrillLoaded, BurgerPlated, BurgerServed), never `core/` state. Station ids:
## ORDER_BOARD, HERB_BOARD and GRILL at FixtureCookingModes' spots, then FIRST_BED up at BED_SPOTS
## and FIRST_PLACE up at PLACE_SPOTS, in level order. Kind ids are the fixture's (`bun_a`,
## `fried_a`, `herb_a`, ...).

const ORDER_BOARD := 10
const HERB_BOARD := 11
const GRILL := 12
const FIRST_BED := 13
const FIRST_PLACE := 20
const OWN := 1
const OTHER := 2


## A model of `mode` (FixtureCookingModes.basic(burgers) when null) in its round, the own peer OWN,
## with the stations of `burgers` places placed, an order posted on each (bun_a, fried_a, icon i)
## and the herbs dealt (herb_a, herb_b, herb_c on the code and the beds).
static func dealt(burgers: int = 2, mode: GameMode = null) -> ClientModel:
	var game_mode := mode if mode != null else FixtureCookingModes.basic(burgers)
	var model := ClientModel.new(game_mode)
	model.own_peer = OWN
	fold(model, PhaseChangedEvent.new(&"round", 1000))
	place_station(model, ORDER_BOARD, &"order_board", FixtureCookingModes.ORDER_BOARD_AT)
	place_station(model, HERB_BOARD, &"herb_board", FixtureCookingModes.HERB_BOARD_AT)
	place_station(model, GRILL, &"grill", FixtureCookingModes.GRILL_AT)
	for i in FixtureCookingModes.BED_SPOTS.size():
		place_station(model, FIRST_BED + i, &"herb_bed", FixtureCookingModes.BED_SPOTS[i])
	for i in burgers:
		place_station(model, FIRST_PLACE + i, &"place", FixtureCookingModes.PLACE_SPOTS[i])
		fold(model, OrderPostedEvent.new(FIRST_PLACE + i, &"bun_a", &"fried_a", i))
	var herbs := PackedStringArray(["herb_a", "herb_b", "herb_c"])
	fold(model, HerbsDealtEvent.new(herbs, herbs))
	return model


## Folds `event` into `model`, as the session does with what it decodes.
static func fold(model: ClientModel, event: MatchEvent) -> void:
	model.fold(event.event_name(), event.to_dict())


## Station `id` of kind `kind` placed at `at`.
static func place_station(model: ClientModel, id: int, kind: StringName, at: Vector3) -> void:
	fold(model, StationPlacedEvent.new(id, kind, Color.WHITE, at))


## Item `id` of kind `kind` spawned at `at` (a take from a box or a bed, mid-round).
static func spawn(model: ClientModel, id: int, kind: StringName, at: Vector3) -> void:
	fold(model, ItemSpawnedEvent.new(id, kind, at))


## Item `id` of kind `kind` spawned and picked up by `peer` (OWN by default).
static func hold(model: ClientModel, id: int, kind: StringName, peer: int = OWN) -> void:
	spawn(model, id, kind, Vector3(0, 0, 25))
	fold(model, ItemPickedUpEvent.new(peer, id))


## Item `id` put on place `index` (0 up): locked on its free slot, never compared to the order
## before the burger is served (#1101).
static func put(model: ClientModel, id: int, index: int) -> void:
	fold(model, IngredientPlacedEvent.new(id, FIRST_PLACE + index))


## The take of place `index`'s full plate as the host sends it (#1101): each item in `plated`
## vanishes, burger `id` spawns into `peer`'s hand, then BurgerPlated names its kinds.
static func plate_burger(
	model: ClientModel,
	id: int,
	index: int,
	plated: Array[int],
	kinds: Array[StringName] = [&"bun_a", &"fried_a", &"herb_a"],
	peer: int = OWN
) -> void:
	for item_id in plated:
		fold(model, ItemVanishedEvent.new(item_id))
	hold(model, id, &"burger", peer)
	fold(model, BurgerPlatedEvent.new(id, FIRST_PLACE + index, kinds[0], kinds[1], kinds[2]))


## The serve of burger `id` checked against place `index`'s order (#1101): BurgerServed, then the
## burger vanishes.
static func serve(model: ClientModel, id: int, index: int, right: bool) -> void:
	fold(model, BurgerServedEvent.new(FIRST_PLACE + index, right))
	fold(model, ItemVanishedEvent.new(id))


## Item `id` put on the grill, fried at host tick `fried` and burnt at `burnt`.
static func grill(model: ClientModel, id: int, fried: int, burnt: int) -> void:
	fold(model, GrillLoadedEvent.new(GRILL, id, fried, burnt))
