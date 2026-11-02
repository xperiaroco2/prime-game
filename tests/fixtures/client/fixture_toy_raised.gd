class_name FixtureToyRaised
extends RefCounted
## The UI pack ui-0.8.0's raised looks, for the ToyRaised and ToyPress suites (#1559). Since
## ui-2.0.0 no button has a base layer and every press depth is 0, so the live themes neither show
## a base nor move a face; the suites test the mechanism on these values instead. The names and
## numbers are ui-0.8.0's (the last pack with raised faces), a fixture, not a look.
## Use: `FixtureToyRaised.install()` in before_test (the toy base hints on the shared theme's
## metadata, which ToyHints reads), `FixtureToyRaised.uninstall()` in after_test, and
## `FixtureToyRaised.themed(GameUi.THEME)` for a node's theme with the press depths.

## Variation: [press_hover, press_held] (press_disabled stays the pack's 0).
const DEPTHS := {
	&"ToyButtonPrimary": [-1, 5],
	&"ToyButtonSecondary": [-1, 4],
	&"ToyPresetCard": [-1, 3],
	&"ToyPresetCardSelected": [-1, 3],
}
## ToyHints' `bases` table: variation -> {context: base variation}.
const BASES := {
	"ToyButtonDanger": {"dark": "ToyBaseRaisedOnDark", "light": "ToyBaseRaisedOnLight"},
	"ToyButtonPrimary": {"dark": "ToyBasePrimaryOnDark", "light": "ToyBasePrimaryOnLight"},
	"ToyButtonSecondary": {"dark": "ToyBaseRaisedOnDark", "light": "ToyBaseRaisedOnLight"},
	"ToyMapBoard": {"any": "ToyBasePanel"},
	"ToyPanelMenu": {"any": "ToyBasePanel"},
	"ToyPresetCard": {"any": "ToyBaseCard"},
	"ToyPresetCardSelected": {"any": "ToyBaseCard"},
	"ToyTitlePlate": {"any": "ToyBaseTitle"},
}

static var _live_hints: Variant = null


## Puts BASES into the shared theme's hints; the live hints come back with uninstall().
static func install() -> void:
	if _live_hints == null:
		_live_hints = ToyHints.THEME.get_meta(ToyHints.META, {})
	var hints: Dictionary = (_live_hints as Dictionary).duplicate(true)
	hints["bases"] = BASES.duplicate(true)
	ToyHints.THEME.set_meta(ToyHints.META, hints)


static func uninstall() -> void:
	if _live_hints != null:
		ToyHints.THEME.set_meta(ToyHints.META, _live_hints)
		_live_hints = null


## A copy of `theme` whose raised variations carry DEPTHS.
static func themed(theme: Theme) -> Theme:
	var copy := theme.duplicate() as Theme
	for variation: StringName in DEPTHS:
		var depths: Array = DEPTHS[variation]
		copy.set_constant(&"press_hover", variation, depths[0] as int)
		copy.set_constant(&"press_held", variation, depths[1] as int)
	return copy
