class_name StationKind
extends ContentPart
## A place where a task is done, placed by its task type (ARCHITECTURE §9.3): the MVP's delivery
## circle. Colours never repeat within a station kind, so the palette's size is a demand (§9.4).

@export var id: StringName
@export var spawn_tag: StringName
## Metres, 0.2 to 10. The neutral default is out of bounds on purpose: the data sets it (the
## delivery circle: 1), so the mode check refuses a station kind that forgot it.
@export var radius_m := 0.0
## Distinct colours, one per placed station.
@export var palette: PackedColorArray = PackedColorArray()


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if id.is_empty():
		found.append("a station kind has no id")
	if spawn_tag.is_empty():
		found.append("station kind %s has no spawn_tag" % id)
	append_found(found, [out_of_bounds("station kind %s radius_m" % id, radius_m, 0.2, 10)])
	for i in palette.size():
		for j in range(i + 1, palette.size()):
			if palette[i] == palette[j]:
				found.append("station kind %s repeats palette colour %d" % [id, j])
	return found
