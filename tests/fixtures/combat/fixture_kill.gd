class_name FixtureKill
extends RuleEffect
## A test effect that kills (LifeRules.kill; the car repair ADR's RE6 and RE17, #806): first it
## queues each of `later` (LifeRules.kill_later), then kills each of `now` at once, then emits a
## FixtureNoteEvent `note` to everyone (none when empty), so a test sees where the queued kills
## land against the command's own events.

@export var later: Array[int] = []
@export var now: Array[int] = []
@export var note := ""


static func of(queued: Array[int], at_once: Array[int] = [], note_text := "") -> FixtureKill:
	var effect := FixtureKill.new()
	effect.later = queued
	effect.now = at_once
	effect.note = note_text
	return effect


func run(ctx: MatchContext) -> void:
	for peer: int in later:
		LifeRules.kill_later(ctx, peer)
	for peer: int in now:
		LifeRules.kill(ctx, peer)
	if not note.is_empty():
		ctx.emit(FixtureNoteEvent.new(note))


func emits() -> Array[Script]:
	return [FixtureNoteEvent, DiedEvent, SelfStatusEvent, ItemPlacedEvent]
