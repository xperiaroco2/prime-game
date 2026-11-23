class_name SfxSet
extends RefCounted
## The game's sound effects (#525; ARCHITECTURE §4.7.43): Kenney's CC0 packs and the project's
## own task sounds (#1341, §4.7.60) and ship engine sounds (#1501, §4.7.64) under
## `res://assets/audio/` (§11.1; docs/credits/), each sound
## id its own files, played as one AudioStreamRandomizer: a file at random, never the same twice
## in a row, with a small random
## pitch (PITCH) and volume (VOLUME_OFFSET_DB). The world's sounds (WorldSounds) and the UI's click,
## End's outro and the pregame's role sounds (UiSounds) take their streams here. Each file is
## loaded the first time its id plays; one that does not load is left out, and an id with no file
## that loads has no stream (null): nothing plays.
## Which files: placeholders the engineer picks by ear (sfx-check's listening page, its
## `sfx-verdicts.json` beside each set), "not a decision".

const IMPACT := "res://assets/audio/kenney_impact_sounds/"
const RPG := "res://assets/audio/kenney_rpg_audio/"
const INTERFACE := "res://assets/audio/kenney_interface_sounds/"
## The project's own synthesis (docs/credits/prime_task_feedback.md), the engineer's picks on #1333.
const TASK_FEEDBACK := "res://assets/audio/prime_task_feedback/"
## Every task's success, at its station (SoundChooser, #1341): the task or one of its subtasks done.
## U2, a kalimba's three rising notes.
const TASK_SUCCESS := &"task_success"
## Every task's error, at its station (SoundChooser, #1341): a miss by the task's own rules. P1,
## the same kalimba falling a minor third.
const TASK_ERROR := &"task_error"
## The ship engine's placeholders, the project's own synthesis (docs/credits/prime_engine.md,
## tools/sfx/engine_synth.gd; #1501, ARCHITECTURE §4.7.64), each played where ShipEngineSounds says
## (GDD §8 "The ship's engine"):
const ENGINE := "res://assets/audio/prime_engine/"
## The ship calls: a soft beep at each pulse of the hologram's turbines while the engine is off.
const ENGINE_CALL := &"engine_call"
## A beep at each lamp of the breakers' order the hologram plays.
const ENGINE_BEEP := &"engine_beep"
## A problem opens: a rising wail at each of its stations.
const ENGINE_WAIL := &"engine_wail"
## A short circuit at a breaker: its zap (K1, an M8 sound since #1674).
const ENGINE_ZAP := &"engine_zap"
## A problem's timer ran out: the blast through the ship.
const ENGINE_BLAST := &"engine_blast"
## The M8 sounds (#1674), the project's own synthesis the engineer picked by ear
## (docs/credits/prime_m8.md, tools/sfx/m8_synth.gd), each file named by its id. Where and to whom
## each plays: SoundChooser (the events), ShipEngineSounds (the engine), PinballSounds (the
## pinball), StationHums (the charging loop), WorldSounds (the hit, the lobby's limp) and UiSounds
## (the mirror, the clock's ticks). The swing (SoundChooser.SWING) and the zap are M8 files too.
const M8 := "res://assets/audio/prime_m8/"
## A hit landed on the own player: a fist's (any one-handed hand) or a two-handed item's.
const HIT_FIST := &"hit_fist"
const HIT_HEAVY := &"hit_heavy"
## A swing with a two-handed item in the hand (the crystal).
const SWING_HEAVY := &"swing_heavy"
## A player knocked down (or gone limp in the lobby), raised, dead, back from the dead.
const KNOCKDOWN := &"knockdown"
const REVIVE := &"revive"
const DEATH := &"death"
const RESPAWN := &"respawn"
## The bar: a mug poured at the tap, a drink.
const TAP_POUR := &"tap_pour"
const DRINK := &"drink"
## The pinball: a flipper raised, a bumper, kicker or target scored, a ball launched, a ball lost,
## a new best.
const PINBALL_FLIPPER := &"pinball_flipper"
const PINBALL_BUMPER := &"pinball_bumper"
const PINBALL_LAUNCH := &"pinball_launch"
const PINBALL_DRAIN := &"pinball_drain"
const PINBALL_BEST := &"pinball_best"
## The mirror's colour menu opening (the own player's only).
const MIRROR_OPEN := &"mirror_open"
## The engine: a gill opened or shut again, breakers tripped, one switched on, its lamp green, a
## crystal into a charger or its socket, a charger charging (a loop) and done.
const ENGINE_GILL_OPEN := &"engine_gill_open"
const ENGINE_GILL_SHUT := &"engine_gill_shut"
const ENGINE_BREAKER_TRIP := &"engine_breaker_trip"
const ENGINE_BREAKER_ON := &"engine_breaker_on"
const ENGINE_BREAKER_GREEN := &"engine_breaker_green"
const ENGINE_CRYSTAL_CHARGER := &"engine_crystal_charger"
const ENGINE_CRYSTAL_SOCKET := &"engine_crystal_socket"
const ENGINE_CHARGING := &"engine_charging"
const ENGINE_CHARGED := &"engine_charged"
## One of the match clock's last seconds, on the HUD's clock.
const TIMER_TICK := &"timer_tick"
## A UI press (UiSounds).
const UI_CLICK := &"ui_click"
## The one sound of both outcomes when End starts (EndScreen.outro_began, #657).
const UI_OUTRO := &"ui_outro"
## The own side's sound when the pregame reveals the own role (PregameScreen.role_revealed, #716):
## one per side of the base mode, the engineers' (`crew`) and the dissidents'.
const UI_ROLE_ENGINEERS := &"ui_role_engineers"
const UI_ROLE_DISSIDENTS := &"ui_role_dissidents"
## Each id's files, but the footsteps' (footstep()). Arrays: a PackedStringArray value in a typed
## const Dictionary reported a wrong size() (24 for 3 paths, observed on 4.7.2).
const FILES: Dictionary[StringName, Array] = {
	SoundChooser.SWING: [M8 + "swing.wav"],
	SoundChooser.PICK_UP: [RPG + "pick_up_1.ogg", RPG + "pick_up_2.ogg", RPG + "pick_up_3.ogg"],
	SoundChooser.PUT_DOWN: [RPG + "put_down_1.ogg", RPG + "put_down_2.ogg", RPG + "put_down_3.ogg"],
	UI_CLICK: [INTERFACE + "click_1.ogg", INTERFACE + "click_2.ogg", INTERFACE + "click_3.ogg"],
	UI_OUTRO: [INTERFACE + "ui_outro.ogg"],
	UI_ROLE_ENGINEERS: [INTERFACE + "ui_role_engineers.ogg"],
	UI_ROLE_DISSIDENTS: [INTERFACE + "ui_role_dissidents.ogg"],
	TASK_SUCCESS: [TASK_FEEDBACK + "task_success.wav"],
	TASK_ERROR: [TASK_FEEDBACK + "task_error.wav"],
	ENGINE_CALL: [ENGINE + "engine_call.wav"],
	ENGINE_BEEP: [ENGINE + "engine_beep.wav"],
	ENGINE_WAIL: [ENGINE + "engine_wail.wav"],
	ENGINE_ZAP: [M8 + "engine_zap.wav"],
	ENGINE_BLAST: [ENGINE + "engine_blast.wav"],
	HIT_FIST: [M8 + "hit_fist.wav"],
	HIT_HEAVY: [M8 + "hit_heavy.wav"],
	SWING_HEAVY: [M8 + "swing_heavy.wav"],
	KNOCKDOWN: [M8 + "knockdown.wav"],
	REVIVE: [M8 + "revive.wav"],
	DEATH: [M8 + "death.wav"],
	RESPAWN: [M8 + "respawn.wav"],
	TAP_POUR: [M8 + "tap_pour.wav"],
	DRINK: [M8 + "drink.wav"],
	PINBALL_FLIPPER: [M8 + "pinball_flipper.wav"],
	PINBALL_BUMPER: [M8 + "pinball_bumper.wav"],
	PINBALL_LAUNCH: [M8 + "pinball_launch.wav"],
	PINBALL_DRAIN: [M8 + "pinball_drain.wav"],
	PINBALL_BEST: [M8 + "pinball_best.wav"],
	MIRROR_OPEN: [M8 + "mirror_open.wav"],
	ENGINE_GILL_OPEN: [M8 + "engine_gill_open.wav"],
	ENGINE_GILL_SHUT: [M8 + "engine_gill_shut.wav"],
	ENGINE_BREAKER_TRIP: [M8 + "engine_breaker_trip.wav"],
	ENGINE_BREAKER_ON: [M8 + "engine_breaker_on.wav"],
	ENGINE_BREAKER_GREEN: [M8 + "engine_breaker_green.wav"],
	ENGINE_CRYSTAL_CHARGER: [M8 + "engine_crystal_charger.wav"],
	ENGINE_CRYSTAL_SOCKET: [M8 + "engine_crystal_socket.wav"],
	ENGINE_CHARGING: [M8 + "engine_charging.wav"],
	ENGINE_CHARGED: [M8 + "engine_charged.wav"],
	TIMER_TICK: [M8 + "timer_tick.wav"],
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
