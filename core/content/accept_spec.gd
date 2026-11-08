class_name AcceptSpec
extends ContentPart
## One entry of a phase's allowlist (ARCHITECTURE §3.1): an intent and from whom the phase
## accepts it. An intent the allowlist does not name, or from a sender it does not name, is
## rejected with `not_accepted`.

## Who may send it; a sender matching any set flag is accepted. 8 was the ghosts' bit: it is never
## reused, so a mode written for ghosts is refused by the mode check (PhaseSpec) instead of
## silently accepting someone else. Match accepts nothing from the dead under PLAYER, LIVING or
## DOWNED; HOST still accepts the host's own player dead (its session controls, such as
## ReturnToLobby on the end screen). DEAD (#1489) is the only flag for the dead: a row with it
## accepts the intent from a dead player in the hall (PlayerState.in_hall), and from no dead player
## anywhere else.
enum From {
	NEWCOMER = 1,  ## a connected peer whose Hello was not accepted yet
	PLAYER = 2,  ## any player but the dead
	LIVING = 4,  ## a living player
	HOST = 16,  ## the host's own player, peer 1
	DOWNED = 32,  ## a downed player
	DEAD = 64,  ## a dead player waiting in the dead's hall
}

## Every flag of From: a `from` with another bit names no sender.
const ALL_FROM := From.NEWCOMER | From.PLAYER | From.LIVING | From.HOST | From.DOWNED | From.DEAD

## An intent name (Intents).
@export var intent: StringName
@export_flags("Newcomer:1", "Player:2", "Living:4", "Host:16", "Downed:32", "Dead:64") var from := 0


static func of(intent_name: StringName, senders: int) -> AcceptSpec:
	var spec := AcceptSpec.new()
	spec.intent = intent_name
	spec.from = senders
	return spec
