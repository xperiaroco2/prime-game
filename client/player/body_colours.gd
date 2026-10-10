class_name BodyColours
extends RefCounted
## What each body colour index (PlayerColours, #551) looks like on this client: a player's capsule,
## standing or lying downed. The ten are a PLACEHOLDER, "not a decision": neither the engineer's
## answers on #73 nor the UI pack (prime-game-ui 0.4.0) name ten player colours, so these are the
## pack's own palette tokens (TOKENS, each colour equal to its token's hex; a test pins them), until
## the engineer picks the ten. A dead body stays LifeLooks.BODY_COLOUR, grey.

## The UI pack's palette token of each index (client/ui/theme/pack/toy.pack.json).
const TOKENS: PackedStringArray = [
	"palette.coral-deep",
	"palette.coral",
	"palette.honey",
	"palette.yellow",
	"palette.health-full",
	"palette.mint",
	"palette.lilac",
	"palette.keyshade",
	"palette.muted",
	"palette.cream",
]
## Each index's colour, the hex of its token.
const HEXES: PackedStringArray = [
	"#d9482f",
	"#ff8466",
	"#c98a10",
	"#ffc23a",
	"#5bcb4e",
	"#3cc4a8",
	"#d8cce3",
	"#b9a8c7",
	"#64566f",
	"#fff4e2",
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
