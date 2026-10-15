class_name PhotoLayers
extends RefCounted
## The visual layers that keep a shot's picture and the live view apart (the photo ADR's §3.3,
## #787; ARCHITECTURE §4.7). A picture is rendered in the live World3D (no copy of the level),
## so what it shows and what the live cameras show are told apart by layer alone:
## - GROUND (layer 1, Godot's default): the level, items on the ground or on a station, dead
##   bodies: they move only by events, so both the live view and the picture draw them;
## - LIVE_AVATAR: what moves by snapshots or belongs to the own view: remote players' bodies, a
##   knocked-down player's live ragdoll, items carried by a player, the first-person and spectate
##   hand items. The picture leaves them out and draws the record's puppets instead;
## - PHOTO: the record's puppets, which only the picture's camera sees.
## Every live Camera3D (the first-person camera, the knocked-down and spectate cameras, the
## viewfinder's lens) sets `cull_mask = LIVE_VIEW`; the picture's camera sets PHOTO_VIEW.

const GROUND := 1
## Visual layer 19.
const LIVE_AVATAR := 1 << 18
## Visual layer 20.
const PHOTO := 1 << 19
## Every one of the 20 visual layers (Camera3D's default cull mask).
const ALL := (1 << 20) - 1
## What every live camera draws: everything but the puppets.
const LIVE_VIEW := ALL & ~PHOTO
## What the picture's camera draws: everything but the live avatars and carried items.
const PHOTO_VIEW := ALL & ~LIVE_AVATAR


## Puts every VisualInstance3D under `root` (root included) on `layer` alone; `casts_shadow` false
## also turns their shadows off (the puppets: none falls into the live view).
static func assign(root: Node, layer: int, casts_shadow := true) -> void:
	if root == null:
		return
	var visual := root as VisualInstance3D
	if visual != null:
		visual.layers = layer
		var geometry := visual as GeometryInstance3D
		if geometry != null and not casts_shadow:
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in root.get_children():
		assign(child, layer, casts_shadow)


## The layer every VisualInstance3D under `root` is on, OR-ed together (0 with none): for tests
## and for a check that a node already sits on `layer` alone.
static func layers_of(root: Node) -> int:
	if root == null:
		return 0
	var found := 0
	var visual := root as VisualInstance3D
	if visual != null:
		found |= visual.layers
	for child: Node in root.get_children():
		found |= layers_of(child)
	return found
