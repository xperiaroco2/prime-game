class_name StationKind
extends ContentPart
## A place where a task is done, placed by its task type (ARCHITECTURE §9.3): Delivery's circle or
## ZoneTask's zone, an invisible cylinder standing on the floor at its marker (#79). Colours never
## repeat within a station kind, so the palette's size is a demand (§9.4).

@export var id: StringName
@export var spawn_tag: StringName
## Metres, 0.2 to 10. The neutral default is out of bounds on purpose: the data sets it (the
## delivery circle: 1), so the mode check refuses a station kind that forgot it.
@export var radius_m := 0.0
## Metres, 0.1 to 10: how far above its floor (the marker's height) the station reaches. The
## neutral default is out of bounds on purpose: the data sets it (the delivery circle: 2, a
## placeholder, "not a decision").
@export var height_m := 0.0
## Distinct colours, one per placed station.
@export var palette: PackedColorArray = PackedColorArray()
## Rules on the intents that name a station (Interact; the Generator ADR's GE2, #796): Match tries
## the named station's kind first, before the actor's role's and the mode's, and never the hand
## item's (§9.2). Its conditions say who may use it and from where (HandNotTwoHanded, AtStation,
## StationInSight, StationUsable); its effect is UseStation, which hands the use to the kind's
## task type. Empty for a station nobody uses (a delivery circle, a zone).
@export var actions: Array[Rule] = []
## A display station (the cooking ADR's CE6, #770: the order board, the herb board): placed by its
## task type's deal so the fit check demands its marker and the client finds its scene, but never
## used. Match refuses an Interact naming one `nothing_to_do` before any owner is tried (the
## station's kind, the role's, the mode's), as an unknown station id, so no role or mode rule ever
## receives it; it holds no `actions` (its check refuses them).
@export var display := false


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if id.is_empty():
		found.append("a station kind has no id")
	if display and not actions.is_empty():
		found.append("station kind %s is a display kind and holds actions, which never run" % id)
	if spawn_tag.is_empty():
		found.append("station kind %s has no spawn_tag" % id)
	append_found(
		found,
		[
			out_of_bounds("station kind %s radius_m" % id, radius_m, 0.2, 10),
			out_of_bounds("station kind %s height_m" % id, height_m, 0.1, 10),
		]
	)
	for i in palette.size():
		for j in range(i + 1, palette.size()):
			if palette[i] == palette[j]:
				found.append("station kind %s repeats palette colour %d" % [id, j])
	return found
