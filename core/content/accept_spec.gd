class_name AcceptSpec
extends ContentPart
## One entry of a phase's allowlist (ARCHITECTURE §3.1): an intent and from whom the phase
## accepts it. An intent the allowlist does not name, or from a sender it does not name, is
## rejected with `not_accepted`.

## Who may send it; a sender matching any set flag is accepted.
enum From {
	NEWCOMER = 1,  ## a connected peer whose Hello was not accepted yet
	PLAYER = 2,  ## any player
	LIVING = 4,  ## a living player
	GHOST = 8,  ## a dead player
	HOST = 16,  ## the host's own player, peer 1
}

## An intent name (Intents).
@export var intent: StringName
@export_flags("Newcomer", "Player", "Living", "Ghost", "Host") var from := 0


static func of(intent_name: StringName, senders: int) -> AcceptSpec:
	var spec := AcceptSpec.new()
	spec.intent = intent_name
	spec.from = senders
	return spec
