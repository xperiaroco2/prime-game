class_name FixtureFreeMarkers
extends RuleEffect
## Notes the markers of `tag` that Items.free_markers counts as free, as "free <tag> <markers>",
## so a test sees what a deal would draw from.

@export var tag := &""


static func of(marker_tag: StringName) -> FixtureFreeMarkers:
	var effect := FixtureFreeMarkers.new()
	effect.tag = marker_tag
	return effect


func run(ctx: MatchContext) -> void:
	ctx.emit(FixtureNoteEvent.new(text(tag, Items.free_markers(ctx, tag))))


func emits() -> Array[Script]:
	return [FixtureNoteEvent]


static func text(marker_tag: StringName, markers: PackedVector3Array) -> String:
	return "free %s %s" % [marker_tag, markers]
