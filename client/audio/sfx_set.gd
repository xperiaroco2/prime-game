class_name SfxSet
extends RefCounted
## The game's sound effects (#525; ARCHITECTURE §4.7.40): Kenney's CC0 packs under
## `res://assets/audio/` (§11.1; docs/credits/), each sound id its own files, played as one
## AudioStreamRandomizer: a file at random, never the same twice in a row, with a small random
## pitch (PITCH) and volume (VOLUME_OFFSET_DB). The world's sounds (WorldSounds) and the UI's click
## and End's outro (UiSounds) take their streams here. Each file is loaded the first time its id
## plays; one that does not load is left out, and an id with no file that loads has no stream
## (null): nothing plays.
## Which files: placeholders the engineer picks by ear (sfx-check's listening page, its
## `sfx-verdicts.json` beside each set), "not a decision".

const IMPACT := "res://assets/audio/kenney_impact_sounds/"
const RPG := "res://assets/audio/kenney_rpg_audio/"
const INTERFACE := "res://assets/audio/kenney_interface_sounds/"
## A UI press (UiSounds).
const UI_CLICK := &"ui_click"
## The one sound of both outcomes when End starts (EndScreen.outro_began, #657).
const UI_OUTRO := &"ui_outro"
## Each id's files, but the footsteps' (footstep()). Arrays: a PackedStringArray value in a typed
## const Dictionary reported a wrong size() (24 for 3 paths, observed on 4.7.2).
const FILES: Dictionary[StringName, Array] = {
	SoundChooser.SWING: [RPG + "swing_1.ogg", RPG + "swing_2.ogg"],
	SoundChooser.PICK_UP: [RPG + "pick_up_1.ogg", RPG + "pick_up_2.ogg", RPG + "pick_up_3.ogg"],
	SoundChooser.PUT_DOWN: [RPG + "put_down_1.ogg", RPG + "put_down_2.ogg", RPG + "put_down_3.ogg"],
	UI_CLICK: [INTERFACE + "click_1.ogg", INTERFACE + "click_2.ogg", INTERFACE + "click_3.ogg"],
	UI_OUTRO: [INTERFACE + "ui_outro.ogg"],
}
## The variants of a footstep on each surface: footstep_<surface>_000 to _004 (Impact Sounds).
const FOOTSTEP_VARIANTS := 5
## The random pitch (a scale: from 1/PITCH to PITCH) and volume (± dB) of every play.
## Placeholders, "not a decision".
const PITCH := 1.06
const VOLUME_OFFSET_DB := 1.5

var _streams: Dictionary[StringName, AudioStreamRandomizer] = {}


## The id of a footstep on `surface` (one of FootstepSurface.SURFACES).
static func footstep(surface: StringName) -> StringName:
	return StringName("%s_%s" % [SoundChooser.FOOTSTEP, surface])


## Every id with files: FILES' and a footstep's on each surface.
static func ids() -> Array[StringName]:
	var all: Array[StringName] = FILES.keys()
	for surface: StringName in FootstepSurface.SURFACES:
		all.append(footstep(surface))
	return all


## The files of sound `id`; none for an unknown id.
static func paths_for(id: StringName) -> PackedStringArray:
	if FILES.has(id):
		return PackedStringArray(FILES[id])
	var paths := PackedStringArray()
	for surface: StringName in FootstepSurface.SURFACES:
		if id == footstep(surface):
			for i: int in FOOTSTEP_VARIANTS:
				paths.append(IMPACT + "footstep_%s_%03d.ogg" % [surface, i])
	return paths


## One AudioStreamRandomizer of the files at `paths` that load.
static func randomizer(paths: PackedStringArray) -> AudioStreamRandomizer:
	var stream := AudioStreamRandomizer.new()
	for path: String in paths:
		if not ResourceLoader.exists(path):
			continue
		var each := load(path) as AudioStream
		if each != null:
			stream.add_stream(-1, each)
	# No-repeats needs two files to choose between.
	stream.playback_mode = (
		AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
		if stream.streams_count > 1
		else AudioStreamRandomizer.PLAYBACK_RANDOM
	)
	stream.random_pitch = PITCH
	stream.random_volume_offset_db = VOLUME_OFFSET_DB
	return stream


## The stream of sound `id`, made once; null when none of its files loads.
func stream_for(id: StringName) -> AudioStreamRandomizer:
	if not _streams.has(id):
		_streams[id] = randomizer(paths_for(id))
	var stream := _streams[id]
	return stream if stream.streams_count > 0 else null
