class_name FixtureRestedNote
extends RuleEffect
## A reaction effect on item_rested: emits a FixtureNoteEvent "rested <item> <cause> <position>",
## so tests see every item_rested with its fields, in order among the events.


func run(ctx: MatchContext) -> void:
	ctx.emit(FixtureNoteEvent.new(text(ctx.fact.item, ctx.fact.cause, ctx.fact.position)))


func emits() -> Array[Script]:
	return [FixtureNoteEvent]


static func text(item: int, cause: StringName, at: Vector3) -> String:
	return "rested %d %s %s" % [item, cause, at]
