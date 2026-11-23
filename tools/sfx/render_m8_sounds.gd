extends SceneTree
## Renders the M8 sounds (#1674, m8_synth.gd) to <folder>/<sound>.wav and prints each file's length
## and SHA-256 for its credits entry (docs/credits/prime_m8.md). The folder is the first user
## argument, a res:// path (default m8_synth.gd's FOLDER, assets/audio/prime_m8/); the second, if
## any, a comma list of sounds (default all). Run: `tools\run.cmd run tools/sfx/render_m8_sounds.gd
## --headless`, then `tools\run.cmd sfx-check assets/audio/prime_m8 --page` to listen.

const Synth := preload("res://tools/sfx/m8_synth.gd")
const EngineSynth := preload("res://tools/sfx/engine_synth.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var folder: String = args[0] if args.size() > 0 else Synth.FOLDER
	if not folder.ends_with("/"):
		folder += "/"
	var sounds: Array[StringName] = Synth.PICKS.keys()
	if args.size() > 1:
		sounds.clear()
		for sound: String in args[1].split(",", false):
			sounds.append(StringName(sound))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for sound: StringName in sounds:
		var values: PackedFloat32Array = Synth.samples(sound)
		if values.is_empty():
			printerr("render_m8_sounds: no sound %s" % sound)
			quit(1)
			return
		var bytes: PackedByteArray = EngineSynth.wav_bytes(values)
		var path := folder + String(sound) + ".wav"
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			printerr("render_m8_sounds: cannot write %s" % path)
			quit(1)
			return
		file.store_buffer(bytes)
		file.close()
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(bytes)
		var seconds := float(values.size()) / EngineSynth.RATE
		print("%s %.2f s SHA-256 %s" % [path, seconds, hashing.finish().hex_encode()])
	quit(0)
