class_name PinballKeys
extends Node
## The seated player's flipper keys (#1400; ARCHITECTURE §4.7.63, §7.1.22): the held state of
## `flipper_left` and `flipper_right` (Settings rows, §4.7.28) goes to the host as one
## `Flippers(left, right)` intent on each change, and only while the own player holds the seat
## (ClientPinball.player). Nothing is predicted: the table view turns the flippers from the host's
## PinballState, which everyone gets.
##
## - No stuck flipper: a key counts only while `listening` (GamePlayer.apply_flags: no Esc menu,
##   the lobby screen), `reads_device_input` and the window has the focus; when one stops holding,
##   the next step sends the release.
## - At most one intent per SEND_GAP_MSEC, under PeerBudget's 20 a second with room for the other
##   keys. A change inside the gap waits for its end and is never dropped: a press and a release
##   inside one gap go out in order, a gap apart; more changes merge into the newest state.
## - Reconcile: the intent is reliable and the same state again changes nothing on the host
##   (§7.1.22), so when the host's PinballState still differs from the last state sent
##   RECONCILE_MSEC after the last send and nothing waits, that state goes again.

## The flipper actions (project.godot, Controls.ACTIONS).
const LEFT := &"flipper_left"
const RIGHT := &"flipper_right"
## The least time between two intents, in milliseconds (not a decision: 16 a second at most).
const SEND_GAP_MSEC := 60
## How long the host's state may differ from the last state sent before it goes again, ms.
const RECONCILE_MSEC := 250

## Sends one intent: (intent: StringName, args: Dictionary) -> int (ClientSession.send_intent).
var send := Callable()
var model: ClientModel
## The keys count (GamePlayer.apply_flags: not frozen, no Esc menu or invite, the lobby screen).
var listening := false
## Read the keyboard in the physics step; tests call update() themselves.
var reads_device_input := true
## Whether the window has the focus: () -> bool. A key held while the focus leaves is released.
var focused := func() -> bool: return is_inside_tree() and get_window().has_focus()

## The last state sent, [left, right]; what the host should have.
var _sent: Array[bool] = [false, false]
## The states waiting for the gap's end, oldest first (at most two: the next edge and the newest).
var _queue: Array[Array] = []
var _last_send := -1
var _seated := false


func _init() -> void:
	name = "PinballKeys"


func _physics_process(_delta: float) -> void:
	var left := reads_device_input and Input.is_action_pressed(LEFT)
	var right := reads_device_input and Input.is_action_pressed(RIGHT)
	update(left, right, Time.get_ticks_msec())


## Whether the own player holds the machine's seat now.
func seated() -> bool:
	return model != null and model.own_peer > 0 and model.pinball.player == model.own_peer


## One step: the keys `left_down` and `right_down` as held now, at `now_msec`.
func update(left_down: bool, right_down: bool, now_msec: int) -> void:
	if not seated():
		_seated = false
		_queue.clear()
		return
	if not _seated:
		# A new seat: the host's state is where the flippers start (rest, for a new game).
		_seated = true
		_sent = [model.pinball.left, model.pinball.right]
		_queue.clear()
	var active := listening and (not focused.is_valid() or focused.call() as bool)
	_want([left_down and active, right_down and active])
	var due := _last_send < 0 or now_msec - _last_send >= SEND_GAP_MSEC
	if not _queue.is_empty():
		if due:
			_send(_queue.pop_front() as Array, now_msec)
		return
	var host: Array[bool] = [model.pinball.left, model.pinball.right]
	if host != _sent and (_last_send < 0 or now_msec - _last_send >= RECONCILE_MSEC):
		_send(_sent, now_msec)


## Forgets the seat and anything waiting (the session ended, the match was cleared).
func clear() -> void:
	_seated = false
	_queue.clear()
	_sent = [false, false]
	_last_send = -1


func _want(state: Array[bool]) -> void:
	var last: Array = _queue.back() if not _queue.is_empty() else _sent
	if last == state:
		return
	if _queue.size() >= 2:
		_queue[-1] = state
		if _queue[-1] == _queue[-2]:
			_queue.pop_back()
		return
	_queue.append(state)


func _send(state: Array, now_msec: int) -> void:
	_sent = [state[0] as bool, state[1] as bool]
	_last_send = now_msec
	if send.is_valid():
		send.call(Intents.FLIPPERS, {"left": _sent[0], "right": _sent[1]})
