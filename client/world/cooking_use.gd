class_name CookingUse
extends RefCounted
## What E offers at Cooking's stations and boxes (#776, the cooking ADR's §8 C7, ARCHITECTURE
## §4.7.55), pure: from the own ClientModel and the client's own copy of the mode, never `core/`
## state. It mirrors the host's Cooking.use_problem() on what the client knows and leaves the rest
## to the host (§7.1); it only decides what to offer:
## - the herb board: never (a display kind with no rule, CE6; StationUse already stops it);
## - the order board (#1101): the own hand holds a plated burger whose place is not done (the serve;
##   any other hand: the host's `empty_hand`, `wrong_item` or `unavailable`);
## - a place: not done, and either its plate is full (E takes the burger, #1101) or the own hand
##   holds one of the type's buns, fried patties or herbs whose slot on the plate is free (a raw or
##   burnt patty, a knife, empty hands or a filled slot: the host's `wrong_item`, `empty_hand` or
##   `unavailable`). Nothing here compares a plate to its order: the host checks a burger only when
##   it is served.
## - the grill: empty, with a raw patty in the hand; occupied, always (the take-off is a take,
##   CD3 (b));
## - a bed: always (its herb's cap is the host's to judge, CE3).
## A box is an item kind with an Interact rule among its `target_actions` (the take, CE7): E taps it
## for an ingredient and holds it to pick the box up (CD4 (a), ItemInteractions).

enum Role { NONE, ORDER_BOARD, HERB_BOARD, GRILL, BED, PLACE }


## Every Cooking of `mode`, in the mode's order.
static func types_of(mode: GameMode) -> Array[Cooking]:
	return CookingClient.types_of(mode)


## The Cooking of `mode` one of whose five station kinds is `kind_id`, or null.
static func type_of(mode: GameMode, kind_id: StringName) -> Cooking:
	for type: Cooking in types_of(mode):
		if role_of(type, kind_id) != Role.NONE:
			return type
	return null


## Which of `type`'s station kinds `kind_id` is; NONE for none.
static func role_of(type: Cooking, kind_id: StringName) -> Role:
	if type == null:
		return Role.NONE
	var kinds: Array[StationKind] = [
		type.order_board, type.herb_board, type.grill, type.herb_bed, type.place
	]
	var roles: Array[Role] = [Role.ORDER_BOARD, Role.HERB_BOARD, Role.GRILL, Role.BED, Role.PLACE]
	for i in kinds.size():
		if kinds[i] != null and kinds[i].id == kind_id:
			return roles[i]
	return Role.NONE


## Whether E offers the cooking station `id` of `model` (of `type`) to the own player now (see the
## class doc); false for a station of no role of `type`.
static func usable(model: ClientModel, type: Cooking, id: int) -> bool:
	var station: ClientModel.Station = model.stations.get(id) if model != null else null
	if station == null:
		return false
	var hand: ClientModel.Item = model.items.get(model.hand_item(model.own_peer))
	var held := hand.kind if hand != null else &""
	match role_of(type, station.kind):
		Role.ORDER_BOARD:
			return _serves(model, type, hand)
		Role.PLACE:
			return not station.done and _plates(model, type, id, held)
		Role.GRILL:
			return station.grill_item >= 0 or _has(type.raw_patties, held)
		Role.BED:
			return true
	return false


## Whether a place (not done) takes E with `held` in hand: a full plate always (the take), else
## an ingredient whose slot is free.
static func _plates(model: ClientModel, type: Cooking, id: int, held: StringName) -> bool:
	var plated := model.plated_on(id)
	if plated.size() >= ClientModel.ORDER_SLOTS:
		return true
	if not takes(type, held):
		return false
	var slot := slot_of(type, held)
	for item_id: int in plated:
		if slot_of(type, model.items[item_id].kind) == slot:
			return false
	return true


## Whether `hand` is a plated burger of `type` whose place's order is not done (the serve).
static func _serves(model: ClientModel, type: Cooking, hand: ClientModel.Item) -> bool:
	if hand == null or type.burger == null or hand.kind != type.burger.id:
		return false
	var place: ClientModel.Station = model.stations.get(hand.place)
	return place != null and not place.done


## Whether a place takes an item of kind `kind_id` at all: a bun, a fried patty or
## a herb of `type` (the host's Cooking._takes).
static func takes(type: Cooking, kind_id: StringName) -> bool:
	return (
		_has(type.buns, kind_id) or _has(type.fried_patties, kind_id) or _has(type.herbs, kind_id)
	)


## Whether the item kind `kind_id` of `mode` is a box: it has an Interact rule among its
## `target_actions` (a take), so E taps it for what it gives and holds it to pick it up.
static func is_box(mode: GameMode, kind_id: StringName) -> bool:
	var kind := mode.find_item_kind(kind_id) if mode != null else null
	if kind == null:
		return false
	for rule: Rule in kind.target_actions:
		if rule != null and rule.trigger == Intents.INTERACT:
			return true
	return false


## The placed stations of `type`'s kind of role `role` in `model`, in ascending id (the host's
## station order: the k-th bed shows HerbsDealt's k-th herb, the k-th place the board's k-th row).
static func stations_of(model: ClientModel, type: Cooking, role: Role) -> Array[int]:
	var found: Array[int] = []
	if model == null or type == null:
		return found
	for id: int in model.stations:
		if role_of(type, model.stations[id].kind) == role:
			found.append(id)
	found.sort()
	return found


## Place `id`'s number on its plate and on the order board: its 1-based rank among the placed
## places of `type` in id order; 0 for no place.
static func place_number(model: ClientModel, type: Cooking, id: int) -> int:
	return stations_of(model, type, Role.PLACE).find(id) + 1


## Which group of `type`'s ingredients item kind `kind_id` is: 0 a bun, 1 a patty (raw, fried or
## burnt), 2 a herb, -1 none (the slot it is drawn at on a plate).
static func slot_of(type: Cooking, kind_id: StringName) -> int:
	if type == null:
		return -1
	if _has(type.buns, kind_id):
		return 0
	if (
		_has(type.raw_patties, kind_id)
		or _has(type.fried_patties, kind_id)
		or (type.burnt != null and type.burnt.id == kind_id)
	):
		return 1
	return 2 if _has(type.herbs, kind_id) else -1


static func _has(kinds: Array[ItemKind], kind_id: StringName) -> bool:
	if kind_id == &"":
		return false
	for kind: ItemKind in kinds:
		if kind != null and kind.id == kind_id:
			return true
	return false
