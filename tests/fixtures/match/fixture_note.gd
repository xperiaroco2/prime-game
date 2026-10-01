class_name FixtureNote
extends RuleEffect
## Emits a FixtureNoteEvent with `text`, to everyone unless told otherwise; with `with_argument`
## the text ends with the outcome's argument (a transition action's view of `won`).

@export var text := ""
@export var to_role: StringName
@export var to_downed := false
@export var to_actor := false
@export var to_server := false
@export var with_argument := false


static func of(note: String) -> FixtureNote:
	var effect := FixtureNote.new()
	effect.text = note
	return effect


func run(ctx: MatchContext) -> void:
	var audience := Audience.everyone()
	if not to_role.is_empty():
		audience = Audience.of_role(to_role)
	elif to_downed:
		audience = Audience.of_life(PlayerState.Life.DOWNED)
	elif to_actor:
		audience = Audience.only(ctx.actor)
	elif to_server:
		audience = Audience.server()
	var note := text
	if with_argument:
		note += " %s" % str(ctx.outcome_argument)
	ctx.emit(FixtureNoteEvent.new(note, audience))


func emits() -> Array[Script]:
	return [FixtureNoteEvent]
