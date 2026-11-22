extends SceneTree
## Renders the M8 sounds (#1674, m8_synth.gd) to <folder>/<take>.wav and prints each file's length
## and SHA-256 for its credits entry. The folder is the first user argument, a res:// path (default
## res://tests/scratch/m8_sounds/, gitignored: the takes to listen to); the second, if any, a comma
## list of takes (default all). Run: `tools\run.cmd run tools/sfx/render_m8_sounds.gd --headless --
## <folder> [<takes>]`, then `tools\run.cmd sfx-check <folder> --page` to listen.

const Synth := preload("res://tools/sfx/m8_synth.gd")
const EngineSynth := preload("res://tools/sfx/engine_synth.gd")
const DEFAULT_FOLDER := "res://tests/scratch/m8_sounds/"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var folder := args[0] if args.size() > 0 else DEFAULT_FOLDER
	if not folder.ends_with("/"):
		folder += "/"
	var takes: Array[StringName] = Synth.CANDIDATES.keys()
	if args.size() > 1:
		takes.clear()
		for take: String in args[1].split(",", false):
			takes.append(StringName(take))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for take: StringName in takes:
		var values: PackedFloat32Array = Synth.samples(take)
		if values.is_empty():
			printerr("render_m8_sounds: no take %s" % take)
			quit(1)
			return
		var bytes: PackedByteArray = EngineSynth.wav_bytes(values)
		var path := folder + String(take) + ".wav"
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
