class_name HowtoFrame
extends Resource
## One frame of a how-to card (#254, HowtoCard): one picture of one action, wordless (the
## engineer's ui-0.4.0 note: no captions). A frame that has no picture yet (the Guide's basics,
## whose art is not drawn) shows the words of a deck key instead, filled with the bound key of
## `key_action` where the words hold `{key}`. Content data: the designer writes it.

## The picture: a res:// path to a PNG of the UI pack (640x480, transparent, drawn in its own
## colours). A path, not a Texture2D, so a card still loads while its picture is missing: the
## card then shows a placeholder naming the file (HowtoCardView).
@export_file("*.png") var art := ""
## The deck key whose words stand in for a picture (the basics); &"" for a frame with art.
@export var text: StringName = &""
## The action whose bound key fills `{key}` in `text` (KeyLabel); &"" for none.
@export var key_action: StringName = &""
## This frame shows the finish: drawn as ToyHowtoFrameDone.
@export var done := false
