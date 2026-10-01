class_name BotClient
extends ClientSession
## A bot's ClientSession (ARCHITECTURE §4.6): the client every player runs, with the decoded view
## kept, and the one thing a scenario adds. A bot loads no scene (load_levels off), so its session
## acknowledges every LoadMatch at once; while the bot's current step is LoadAck (§9.7), that
## automatic LoadAck is held back (`hold_load_ack`) and the step answers it, or with `skip` never.

## Returns true while the automatic LoadAck must be held back.
var hold_load_ack := Callable()

var _answering := false


func send_intent(intent: StringName, args: Dictionary = {}) -> int:
	if (
		intent == Intents.LOAD_ACK
		and not _answering
		and hold_load_ack.is_valid()
		and hold_load_ack.call()
	):
		return -1
	return super(intent, args)


## The bot's LoadAck step answers the LoadMatch of `match_id`.
func send_load_ack(match_id: int) -> int:
	_answering = true
	var seq := send_intent(Intents.LOAD_ACK, {"match_id": match_id})
	_answering = false
	return seq
