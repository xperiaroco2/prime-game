class_name ClientSeen
extends TutorialTrigger
## Trigger: one of the own client's signals (docs/design/tutorial.md §3), which never reach the
## host as anything it can react to. `Game` feeds them to the LessonRunner while a tutorial runs.

## The own claims report the player moving itself (ClientSession.claim_sent).
const MOVED := &"moved"
## The map screen opened (GameUi.map_opened).
const MAP_OPENED := &"map_opened"
## A how-to card opened from a task's «?» on the map.
const HOWTO_OPENED := &"howto_opened"
## The dead player switched the spectate target (LifeView.target_switched).
const SPECTATE_SWITCHED := &"spectate_switched"
## The own voice sent a frame (VoiceSender.sent rose).
const VOICE_SENT := &"voice_sent"
## The Esc menu opened (Game.open_esc).
const ESC_OPENED := &"esc_opened"
## The closed list.
const SIGNALS: Array[StringName] = [
	MOVED, MAP_OPENED, HOWTO_OPENED, SPECTATE_SWITCHED, VOICE_SENT, ESC_OPENED
]
## The signals that read `amount`.
const TIMED: Array[StringName] = [MOVED, VOICE_SENT]

## One of SIGNALS (the design's `signal`, a GDScript keyword).
@export var signal_name: StringName = &""
## Seconds. MOVED: of the own claims moving itself, in all, from the step's start (0: the first
## such claim). VOICE_SENT: D31 (a)'s fallback, seconds in a row in which the step's conditions
## hold and no microphone is open (0: none, only a frame completes it).
@export var amount := 0.0


func part_name() -> StringName:
	return &"ClientSeen"


func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if not SIGNALS.has(signal_name):
		found.append("ClientSeen: unknown signal '%s'" % signal_name)
	if amount < 0.0:
		found.append("ClientSeen %s: amount %s below 0" % [signal_name, amount])
	elif amount > 0.0 and not TIMED.has(signal_name):
		found.append("ClientSeen %s: amount on a signal that reads none" % signal_name)
	return found
