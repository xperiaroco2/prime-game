class_name LiftMusic
extends AudioStreamPlayer
## The dead's lift music (ARCHITECTURE §4.7 What the dead hear, V11; the M4 ADR's D9): a
## non-positional player on the Music bus (D15; its quiet is the bus's default, AudioBuses) that
## only the dead player's own client plays, from Died to Respawned. The
## stream is a placeholder generated here, a slow, quiet arpeggio of sine tones in a loop, until a
## CC0 track with its docs/credits/ entry replaces it (a human picks it): set `stream` to that track
## and drop placeholder_stream().

const RATE := 11025
## The arpeggio's notes in hertz (A minor, C major, D minor, E major), one per NOTE_S.
const NOTES: Array[float] = [220.0, 261.63, 329.63, 261.63, 293.66, 349.23, 329.63, 415.30]
const NOTE_S := 0.5
## Peak amplitude of a note, of the 16-bit range.
const AMPLITUDE := 0.25


func _init() -> void:
	name = "LiftMusic"
	bus = AudioBuses.MUSIC


## Starts the music (its placeholder stream made at the first start) unless it plays.
func start() -> void:
	if playing:
		return
	if stream == null:
		stream = placeholder_stream()
	play()


## The placeholder: NOTES once each, NOTE_S long, with a soft attack and release, looping.
static func placeholder_stream() -> AudioStreamWAV:
	var per_note := roundi(RATE * NOTE_S)
	var data := PackedByteArray()
	data.resize(per_note * NOTES.size() * 2)
	var at := 0
	for hertz: float in NOTES:
		for i: int in per_note:
			var t := float(i) / RATE
			var envelope := minf(1.0, t / 0.05) * minf(1.0, (NOTE_S - t) / 0.15)
			var sample := sin(TAU * hertz * t) * envelope * AMPLITUDE
			data.encode_s16(at, roundi(sample * 32767.0))
			at += 2
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = per_note * NOTES.size()
	return wav
