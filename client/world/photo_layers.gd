class_name PhotoLayers
extends RefCounted
## The visual layers that keep a shot's picture and the live view apart (the photo ADR's §3.3,
## #787; ARCHITECTURE §4.7.58). A picture is rendered in the live World3D (no copy of the level),
## so what it shows and what the live cameras show are told apart by layer alone:
## - GROUND (layer 1, Godot's default): the level, items on the ground or on a station, dead
##   bodies: they move only by events, so both the live view and the picture draw them;
## - LIVE_AVATAR: what moves by snapshots or belongs to the own view: remote players' bodies, a
##   knocked-down player's live ragdoll, items carried by a player, the first-person and spectate
##   hand items. The picture leaves them out and draws the record's puppets instead;
## - PHOTO: the record's puppets, which only the picture's camera sees.
## STATION (#1556) is no photo layer: both views draw it. It holds the ship's crystal sockets' and
## chargers' meshes, so a seated crystal's own light can skip them and still light the hull round
## it (ShipCrystalLook.seat); ShipStationLooks adds it to every level light that reaches GROUND.
## MIRROR_SELF (#1395) is no photo layer either: the lobby mirror's stand-in of the own body, which
## only the mirror's reflection camera draws (MIRROR_VIEW); the live view and a picture do not.
## Every live Camera3D (the first-person camera, the knocked-down and spectate cameras, the
## viewfinder's lens) sets `cull_mask = LIVE_VIEW`; the picture's camera sets PHOTO_VIEW.

const GROUND := 1
## Visual layer 17.
const MIRROR_SELF := 1 << 16
## Visual layer 18 (the lobby uses layer 11, the ship's hull skin layer 2).
const STATION := 1 << 17
## Visual layer 19.
const LIVE_AVATAR := 1 << 18
## Visual layer 20.
const PHOTO := 1 << 19
## Every one of the 20 visual layers (Camera3D's default cull mask).
const ALL := (1 << 20) - 1
## What every live camera draws: everything but the puppets and the mirror's own stand-in.
const LIVE_VIEW := ALL & ~PHOTO & ~MIRROR_SELF
## What the picture's camera draws: everything but the live avatars and carried items (and the
## mirror's stand-in).
const PHOTO_VIEW := ALL & ~LIVE_AVATAR & ~MIRROR_SELF
## What the mirror's reflection camera draws (#1395): the live view and the own stand-in.
const MIRROR_VIEW := LIVE_VIEW | MIRROR_SELF


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
