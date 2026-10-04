class_name BotClient
extends ClientSession
## A bot's ClientSession (ARCHITECTURE §4.6): the client every player runs, with the decoded view
## kept, and the one thing a scenario adds. A bot loads no scene (load_levels off), so its session
## acknowledges every LoadMatch at once; while the bot's current step is LoadAck (§9.7), that
## automatic LoadAck is held back (`hold_load_ack`) and the step answers it, or with `skip` never.
## With `hold_claims` its step() only polls, and the runner sends the MoveClaim due with claim()
## once the bot moved in that frame (NetPlay.claims_after_moves, #284).

## Returns true while the automatic LoadAck must be held back.
var hold_load_ack := Callable()
## step() sends no MoveClaim: claim() does, after the bot moved.
var hold_claims := false

var _answering := false
var _claiming := false


func send_intent(intent: StringName, args: Dictionary = {}) -> int:
	if (
		intent == Intents.LOAD_ACK
		and not _answering
		and hold_load_ack.is_valid()
		and hold_load_ack.call()
	):
		return -1
	return super(intent, args)


## Its transport, for the leak test's counters (LeakCheck.check_counters).
func transport() -> NetTransport:
	return _transport


## The bot's LoadAck step answers the LoadMatch of `match_id`.
func send_load_ack(match_id: int) -> int:
	_answering = true
	var seq := send_intent(Intents.LOAD_ACK, {"match_id": match_id})
	_answering = false
	return seq


## Sends the MoveClaim due by `now_usec` (one per client tick), with the bot's motion of this frame.
func claim(now_usec: int) -> void:
	_claiming = true
	_claim(now_usec)
	_claiming = false


func _claim(now_usec: int) -> void:
	if hold_claims and not _claiming:
		return
	super(now_usec)
