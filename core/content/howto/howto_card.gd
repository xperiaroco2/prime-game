class_name HowtoCard
extends Resource
## A how-to card (#254; prime-game-ui's P8 at ui-0.4.0): 3 to 4 wordless frames, one action
## each, like an airline safety card, under a title and the corner label `howto.label`. Content
## data per task type (`content/howto/tasks/<task type id>.tres`) and per basic of the Esc menu's
## Guide (`content/howto/basics/<id>.tres`); HowtoCards finds them, HowtoCardView draws one. Not
## a rule: the host never reads it, so it is not part of the mode or its content hash. A
## content-API data class (ARCHITECTURE §9.3), as BotScenario: content/ names only the content API.

const MIN_FRAMES := 3
const MAX_FRAMES := 4

## The task type's id, or the basic's (`moving`, `voice`, `downed`).
@export var id: StringName
## The title's deck key (`task.delivery`; a basic's is its Guide chip's, `guide.moving`).
@export var title: StringName
@export var frames: Array[HowtoFrame] = []


## What is wrong with the card, one line each; empty for a valid card: an id and a title, 3 to 4
## frames, each with a picture (a res:// PNG) or words, and at most one finish frame, the last.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if id.is_empty():
		found.append("no id")
	if title.is_empty():
		found.append("no title")
	if frames.size() < MIN_FRAMES or frames.size() > MAX_FRAMES:
		found.append("%d frames, not %d to %d" % [frames.size(), MIN_FRAMES, MAX_FRAMES])
	for i in frames.size():
		var frame := frames[i]
		if frame == null:
			found.append("frame %d is empty" % (i + 1))
			continue
		if frame.art.is_empty() == frame.text.is_empty():
			found.append("frame %d needs a picture or words, not both or neither" % (i + 1))
		if not frame.art.is_empty() and not frame.art.begins_with("res://"):
			found.append("frame %d: its picture %s is not a res:// path" % [i + 1, frame.art])
		if not frame.art.is_empty() and frame.art.get_extension() != "png":
			found.append("frame %d: its picture %s is not a PNG" % [i + 1, frame.art])
		if frame.done and i != frames.size() - 1:
			found.append("frame %d shows the finish but is not the last" % (i + 1))
	return found
