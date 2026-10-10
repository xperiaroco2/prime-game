class_name BodyColours
extends RefCounted
## What each body colour index (PlayerColours, #551) looks like on this client: a player's capsule,
## standing or lying downed. The ten are the delivery circles' ten colours (the palette of the
## circle StationKind in content/tasks/delivery.tres, in its order; a test pins them), the
## engineer's choice for now (PR #745, comment 6098097836). The UI track is asked for a
## player-colour list on #150 (comment 6098103407); its ten replace HEXES later. A dead body stays
## LifeLooks.BODY_COLOUR, grey.

## Each index's colour as a hex string: red, orange, yellow, green, cyan, blue, purple, pink,
## brown, white.
const HEXES: PackedStringArray = [
	"#e61a1a",
	"#f2800d",
	"#f2d91a",
	"#26b333",
	"#1accd9",
	"#264df2",
	"#8c33d9",
	"#f266b3",
	"#804d1a",
	"#f2f2f2",
]

## HEXES parsed once: AvatarViews asks for every remote body's colour on every physics frame.
static var _colours: Array[Color] = []


## The colour of index `colour`; index 0's for one outside the palette (the host never sends one).
static func of(colour: int) -> Color:
	if _colours.is_empty():
		for hex: String in HEXES:
			_colours.append(Color(hex))
	var index := colour if colour >= 0 and colour < _colours.size() else 0
	return _colours[index]
