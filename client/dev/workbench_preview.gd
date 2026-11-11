extends Control
## A preview of the mutation workbench's screen for `tools\run.cmd shot` (#1572): prime-game-ui
## `ui-2.5.4` `docs/handoff/s11-workbench.md`'s states, the 960 x 540 screen centred in the frame
## as the review page draws it (in the game a machine shows it in the world, #1285):
## - `idle`: nobody uses the machine;
## - `choose`: the handoff's sample, 7 points, Quick feet (4), Spring legs (3, under the pointer)
##   and Thick skin (9, two short);
## - `step`: Spring legs chosen, 6 of 10 pips.
## The mutations and prices are the handoff's samples, not the game's (points and mutations are not
## planned yet, docs/ROADMAP.md). Dev only: nothing here reaches the game.

@export_enum("idle", "choose", "step") var state := "idle"
## The language of the words (Languages.ENGLISH or UKRAINIAN).
@export var language := Languages.ENGLISH


func _ready() -> void:
	TranslationServer.set_locale(language)
	theme = GameUi.THEME
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var ground := Panel.new()
	ground.theme_type_variation = &"ToyBackdropFullScreen"
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ground)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var screen := WorkbenchScreen.new()
	centre.add_child(screen)
	match state:
		"choose":
			var offer: Array[WorkbenchScreen.Mutation] = [
				WorkbenchScreen.Mutation.new(
					&"fast", "mutation.fast.name", "mutation.fast.effect", 4
				),
				WorkbenchScreen.Mutation.new(
					&"jump", "mutation.jump.name", "mutation.jump.effect", 3
				),
				WorkbenchScreen.Mutation.new(
					&"health", "mutation.health.name", "mutation.health.effect", 9
				),
			]
			screen.show_choose(7, offer)
			# The crosshair on Spring legs' button: its card pointed.
			screen.card_of(&"jump").mouse_entered.emit()
		"step":
			screen.show_step("mutation.jump.name", 0.6)
