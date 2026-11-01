extends SceneTree
## Renders the ship engine's placeholder sounds (#1501, engine_synth.gd) to
## assets/audio/prime_engine/<name>.wav and prints each file's SHA-256 for its credits entry
## (docs/credits/prime_engine.md). Run: `tools\run.cmd run tools/sfx/render_engine_sounds.gd
## --headless`, then `tools\run.cmd sfx-check assets/audio/prime_engine --page` to listen.

const Synth := preload("res://tools/sfx/engine_synth.gd")
const FOLDER := "res://assets/audio/prime_engine/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	for sound_name: StringName in Synth.NAMES:
		var values: PackedFloat32Array = Synth.samples(sound_name)
		var bytes: PackedByteArray = Synth.wav_bytes(values)
		var path := FOLDER + String(sound_name) + ".wav"
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			printerr("render_engine_sounds: cannot write %s" % path)
			quit(1)
			return
		file.store_buffer(bytes)
		file.close()
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(bytes)
		print(
			(
				"%s %.2f s SHA-256 %s"
				% [path, float(values.size()) / Synth.RATE, hashing.finish().hex_encode()]
			)
		)
	quit(0)
