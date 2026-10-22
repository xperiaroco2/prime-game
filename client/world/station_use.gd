class_name StationUse
extends RefCounted
## Which placed stations the own player may use with E, and which kinds are a Generator's (#801,
## ARCHITECTURE §4.7.54), pure: from the own ClientModel and the client's own copy of the mode,
## never `core/` state. The host checks everything again (§7.1); this only decides what to offer.
##
## A station is offered when its kind has an Interact rule (not a `display` kind), the own hand
## holds no two-handed item where that rule has HandNotTwoHanded (but for a photo camera holding a
## film: taking it out is a PickUp, a take, which a two-handed item does not refuse, the photo
## ADR's §2.4; only its viewfinder asks hand_allows_at()), and its task type says it can still be
## used. Only the task types this client draws a station view for answer that (today the
## Generator, #801: neither its generator nor a switch once the charge is done, the host's
## StationUsable; Cooking, #776: CookingUse; the photo task, #786: PhotoUse; the car repair, #811:
## CarRepairUse); a kind of any other type is never offered until its client issue adds its row
## here. The other conditions of a rule (AtStation, StationInSight) are TargetChoice's and
## ItemInteractions'; one this client does not know is left to the host. A fixed switch is no
## station at all (GE14), so it is never offered, and nothing here reads a switch's `on`: the hint
## never names a switch's state.


## The station kind `kind_id` of one of `mode`'s task types, or null.
static func kind_of(mode: GameMode, kind_id: StringName) -> StationKind:
	if mode == null:
		return null
	for kind: StationKind in Stations.kinds_in(mode):
		if kind.id == kind_id:
			return kind
	return null


## The Generator of `mode` whose generator or switch kind is `kind_id`, or null.
static func generator_of(mode: GameMode, kind_id: StringName) -> Generator:
	for generator: Generator in GeneratorClient.types_of(mode):
		if TaskClients.of(generator).owns(generator, kind_id):
			return generator
	return null


## Every Generator of `mode`, in the mode's order.
static func generators_of(mode: GameMode) -> Array[Generator]:
	return GeneratorClient.types_of(mode)


## Whether `kind_id` is a Generator's generator kind (the station that charges and hums).
static func is_generator(mode: GameMode, kind_id: StringName) -> bool:
	var type := generator_of(mode, kind_id)
	return type != null and type.generator != null and type.generator.id == kind_id


## The placed generator station of `type` in `model`, or -1 (the deal places one).
static func generator_station(model: ClientModel, type: Generator) -> int:
	if type == null or type.generator == null:
		return -1
	for id: int in model.stations:
		if model.stations[id].kind == type.generator.id:
			return id
	return -1


## The first Interact rule of `kind`, or null.
static func rule_of(kind: StationKind) -> Rule:
	if kind == null:
		return null
	for rule: Rule in kind.actions:
		if rule != null and rule.trigger == Intents.INTERACT:
			return rule
	return null


## The HoldStation that `kind`'s Interact rule ends in (a hold or a timed channel on the station,
## #808), or null.
static func hold_of(kind: StationKind) -> HoldStation:
	var rule := rule_of(kind)
	if rule == null or rule.effects.is_empty():
		return null
	return rule.effects[rule.effects.size() - 1] as HoldStation


## Whether E on station kind `kind_id` of `mode` starts a channel that E released ends: its
## Interact rule ends in a HoldStation, so the client sends StopRaise at the release (the car
## repair ADR's RE5, #811).
static func holds(mode: GameMode, kind_id: StringName) -> bool:
	return hold_of(kind_of(mode, kind_id)) != null


## Whether E offers station `id` of `model` to the own player now (see the class doc).
static func usable(model: ClientModel, mode: GameMode, id: int) -> bool:
	var station: ClientModel.Station = model.stations.get(id) if model != null else null
	if station == null:
		return false
	var kind := kind_of(mode, station.kind)
	if kind == null or kind.display:
		return false
	var rule := rule_of(kind)
	if rule == null:
		return false
	# The take-out is a take (the photo ADR's §2.4): a two-handed item refuses only the shot.
	if PhotoUse.is_loaded_camera(model, mode, id):
		return true
	if not _hand_allows(model, mode, rule):
		return false
	var photo := PhotoUse.type_of(mode, station.kind)
	if photo != null:
		return PhotoUse.usable(model, photo, id)
	# The first of the mode's types whose TaskClient owns the kind answers (#1260).
	for type: TaskType in mode.task_types:
		var client := TaskClients.of(type)
		if client != null and client.owns(type, station.kind):
			return client.usable(model, type, id)
	return false


## Whether the own hand passes the HandNotTwoHanded of station `id`'s Interact rule, if it has one
## (the photo camera's shot, #786); false for no such station or rule.
static func hand_allows_at(model: ClientModel, mode: GameMode, id: int) -> bool:
	var station: ClientModel.Station = model.stations.get(id) if model != null else null
	if station == null:
		return false
	var rule := rule_of(kind_of(mode, station.kind))
	return rule != null and _hand_allows(model, mode, rule)


## Whether the own hand passes `rule`'s HandNotTwoHanded, if it has one.
static func _hand_allows(model: ClientModel, mode: GameMode, rule: Rule) -> bool:
	for condition: Condition in rule.conditions:
		if not condition is HandNotTwoHanded:
			continue
		var item: ClientModel.Item = model.items.get(model.hand_item(model.own_peer))
		if item == null:
			return true
		var item_kind := mode.find_item_kind(item.kind)
		return item_kind == null or not item_kind.is_two_handed()
	return true
