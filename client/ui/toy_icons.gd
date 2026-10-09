class_name ToyIcons
extends RefCounted
## The UI pack's white icons (prime-game-ui `dist/pack/icons/`, own work) for the screens that draw
## them in a TextureRect tinted through `self_modulate` (#489; ARCHITECTURE §4.7.36). An icon is
## its imported copy, `res://assets/ui/toy_pack/icons/<name>.svg` (#520's ui-sync imports it at the
## pack's `svg_scale`), once that exists. Until #520 lands, the pinned copy the theme is built from
## (`client/ui/theme/pack/icons/`, `.gdignore`d, so never imported) is rasterised here at the scale
## the pack's `assets` list gives it, the same pixels the import makes. That copy is not exported
## (a `.gdignore`d folder is not packed): an exported build draws no icon until #520 lands.

## The imported copy (#520) and the pinned one, by icon name.
const IMPORTED := "res://assets/ui/toy_pack/icons/%s.svg"
const PINNED := "res://client/ui/theme/pack/icons/%s.svg"
## The pack, whose `assets` list gives each file's `svg_scale`.
const PACK := "res://client/ui/theme/pack/toy.pack.json"

## Name -> texture, made once per run (null for an icon that could not be read).
static var _made: Dictionary[StringName, Texture2D] = {}
## The pack's `svg_scale` by asset path (icons/<name>.svg), read once.
static var _scales: Dictionary[String, float] = {}


## The pack icon `icon` (`mic`, `item`, `knife`, ...): the imported copy, else the pinned SVG
## rasterised at the pack's scale; null when neither can be read.
static func texture(icon: StringName) -> Texture2D:
	if _made.has(icon):
		return _made[icon]
	var made: Texture2D = null
	var imported := IMPORTED % icon
	if ResourceLoader.exists(imported):
		made = load(imported) as Texture2D
	else:
		made = _rasterised(icon)
	_made[icon] = made
	return made


## The pack's `svg_scale` for `icon`, 1.0 when the pack does not list it.
static func scale_of(icon: StringName) -> float:
	if _scales.is_empty():
		_scales = _read_scales()
	var path := "icons/%s.svg" % icon
	return _scales[path] if _scales.has(path) else 1.0


static func _rasterised(icon: StringName) -> Texture2D:
	var svg := FileAccess.get_file_as_string(PINNED % icon)
	if svg.is_empty():
		return null
	var image := Image.new()
	if image.load_svg_from_string(svg, scale_of(icon)) != OK:
		return null
	return ImageTexture.create_from_image(image)


static func _read_scales() -> Dictionary[String, float]:
	var scales: Dictionary[String, float] = {}
	var pack: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK))
	if not pack is Dictionary:
		return scales
	for asset: Variant in (pack as Dictionary).get("assets", []):
		if not asset is Dictionary:
			continue
		var entry := asset as Dictionary
		if entry.has("svg_scale"):
			scales[str(entry["path"])] = float(str(entry["svg_scale"]))
	return scales
