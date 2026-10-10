class_name ItemFlights
extends RefCounted
## The thrown items this client draws in flight (ARCHITECTURE §4.7.25, §7.1.16; the throwing ADR's
## TE5 (a); 37e), pure: an ItemArc per item, from the own key press or the host's events, moved
## along each physics frame by ItemViews (advance()), which places each item's view at its arc.
##
## - The key press (predict()): the own hand item's arc from the own camera with the rule's
##   numbers, found in the client's own copy of the mode as core finds the rule; the hand shows no
##   item while it waits (hides_hand()). Its Rejected (by the Throw's seq) drops the arc and the
##   hand shows the item again; so does no answer within PREDICTION_TIMEOUT_S.
## - ItemThrown: the own prediction adopts the host's vectors; any other throw gets an arc on the
##   avatars' timeline.
## - ItemPlaced with the cause `thrown`: the arc ends at its rest (ItemArc.end_at()).
## - PhaseChanged and LoadMatch drop every arc: an item still in flight is hidden (ItemViews hides
##   a flying item with no arc) until its ItemPlaced, if one ever comes; no later phase draws it
##   again (the host's flown ticks would no longer be the host tick less the launch tick).
## - An item someone picked up, or one the model no longer has, loses its arc.
##
## The thrower's own arc is swept through its own scene each frame (the `sweep` ItemViews gives:
## a sphere of the rule's radius against the level) until its ItemPlaced, and held where the
## sweep stops it: presentation only, which the host never reads. Other arcs are not swept: the
## host's contacts end them through ItemPlaced.
##
## Sounds: the launch sound plays at the press for the own throw (the predicted origin), else when
## the drawn time reaches the launch; the landing sound (the ItemPlaced) when the drawn item gets
## to its rest. take_due() hands them out as [event name, fields], for WorldSounds.on_event, which
## cuts them beyond the hearing range of the ears at that moment and muffles them behind the level.

## How long the own prediction waits for its ItemThrown or Rejected, in seconds: the reliable lane
## always answers, so this only covers a lost session. A placeholder, "not a decision".
const PREDICTION_TIMEOUT_S := 2.0

var arcs: Dictionary[int, ItemArc] = {}

var _pending_seq := -1
var _pending_item := -1
var _pending_left_s := 0.0
## The item whose launch sounded at a press the prediction then gave up on: its late ItemThrown
## does not sound again.
var _heard_item := -1
var _due: Array[Array] = []


## The own throw of the own hand item, sent as `seq`, from the camera at `eye` along `look`: its
## predicted arc and the launch sound. False (nothing predicted) without a hand item, a Throw rule
## for it, or with a prediction still waiting.
func predict(model: ClientModel, mode: GameMode, seq: int, eye: Vector3, look: Vector3) -> bool:
	var item_id := model.hand_item(model.own_peer)
	var item: ClientModel.Item = model.items.get(item_id)
	if item == null or seq < 0 or is_predicting():
		return false
	var rule := ItemArc.rule_of(mode, item.kind, model.role)
	if rule == null:
		return false
	arcs[item_id] = ItemArc.predict(rule, item_id, model.own_peer, eye, look)
	_pending_seq = seq
	_pending_item = item_id
	_pending_left_s = PREDICTION_TIMEOUT_S
	_due.append([&"ItemThrown", {"item": item_id, "peer": model.own_peer, "origin": eye}])
	return true


## A prediction waits for its ItemThrown or Rejected.
func is_predicting() -> bool:
	return _pending_seq >= 0


## The own hand must not show item `item_id`: it was thrown at the press, not answered yet.
func hides_hand(item_id: int) -> bool:
	return is_predicting() and item_id == _pending_item


func has(item_id: int) -> bool:
	return arcs.has(item_id)


## Where item `item_id` is drawn: Vector3.INF before its launch is drawn; null with no arc.
func position_of(item_id: int) -> Variant:
	var arc: ItemArc = arcs.get(item_id)
	if arc == null:
		return null
	return arc.position()


## A decoded event, already folded into `model`. `host_tick` is the estimated host tick at its
## arrival (AvatarViews.host_tick()): no flight can have stopped later.
func on_event(
	event_name: StringName, fields: Dictionary, model: ClientModel, host_tick: float
) -> void:
	match event_name:
		&"ItemThrown":
			var item_id := fields["item"] as int
			var arc: ItemArc = arcs.get(item_id)
			var thrower: int = fields["peer"]
			if arc != null and arc.predicted and thrower == model.own_peer:
				arc.adopt(fields)
				_forget_prediction()
			else:
				var thrown := ItemArc.thrown(fields)
				thrown.launch_heard = item_id == _heard_item and thrower == model.own_peer
				arcs[item_id] = thrown
			if item_id == _heard_item:
				_heard_item = -1
		&"ItemPlaced":
			if fields.get("cause", &"") != Items.THROWN:
				return
			var arc: ItemArc = arcs.get(fields["item"] as int)
			if arc == null:
				_due.append([event_name, fields])
				return
			arc.end_at(fields, arc.n if arc.own else host_tick - arc.launch_tick)
		&"ItemPickedUp":
			var arc: ItemArc = arcs.get(fields["item"] as int)
			if arc != null and not arc.predicted:
				arcs.erase(arc.item)
		&"Rejected":
			var seq: int = fields.get("seq", -1)
			if is_predicting() and seq == _pending_seq:
				_drop_prediction()
		&"PhaseChanged", &"LoadMatch":
			clear()


## One physics frame, `delta` seconds after the last, with the avatars drawn at host tick
## `drawn_tick` (-1 before any snapshot): moves every arc's drawn time, sweeps the own arc
## through `sweep` (from, to, radius) -> the farthest point clear of the level, and ends the arcs
## whose item lies at its rest.
func advance(delta: float, drawn_tick: float, model: ClientModel, sweep: Callable) -> void:
	if is_predicting():
		_pending_left_s -= delta
		var arc: ItemArc = arcs.get(_pending_item)
		if (
			_pending_left_s <= 0.0
			or arc == null
			or model.hand_item(model.own_peer) != _pending_item
		):
			_heard_item = _pending_item
			_drop_prediction()
	for item_id: int in arcs.keys():
		var arc: ItemArc = arcs[item_id]
		var item: ClientModel.Item = model.items.get(item_id)
		if item == null or (not arc.predicted and item.holder != ClientModel.NO_HOLDER):
			arcs.erase(item_id)
			continue
		if arc.own:
			arc.n += delta * Ticks.RATE
			arc.ease_by(delta)
		else:
			arc.n = drawn_tick - arc.launch_tick if drawn_tick >= 0.0 else -INF
		if not arc.launch_heard and arc.n >= 0.0:
			arc.launch_heard = true
			_due.append([&"ItemThrown", {"item": item_id, "origin": arc.origin}])
		var at := arc.position()
		if arc.own and not arc.ended and not arc.blocked_at.is_finite() and sweep.is_valid():
			var clear_to := sweep.call(arc.drawn, at, arc.radius) as Vector3
			if clear_to != at:
				arc.blocked_at = clear_to
				at = clear_to
		arc.drawn = at
		if arc.ended and arc.finished():
			_due.append([&"ItemPlaced", arc.landing])
			arcs.erase(item_id)


## The sounds now due, each [event name, fields], once.
func take_due() -> Array[Array]:
	var due := _due
	_due = []
	return due


## Forgets every arc and the prediction (a phase change, a new match, the session ended).
func clear() -> void:
	arcs.clear()
	_heard_item = -1
	_forget_prediction()


func _drop_prediction() -> void:
	var arc: ItemArc = arcs.get(_pending_item)
	if arc != null and arc.predicted:
		arcs.erase(_pending_item)
	_forget_prediction()


func _forget_prediction() -> void:
	_pending_seq = -1
	_pending_item = -1
	_pending_left_s = 0.0
