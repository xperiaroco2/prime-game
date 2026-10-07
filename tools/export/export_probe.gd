extends SceneTree
## The content hash as an exported build computes it (#369, `tools/runner/export.py`): run by the
## editor binary against an exported pack, from outside it (tools/ is not exported):
##   godot --headless --main-pack <PrimeGame.pck> --script <abs path of this file>
## For each game mode in res://content/modes/ it prints, one line each:
##   EXPORT mode <path> <ContentFingerprint.of>
##   EXPORT text <path> <a line of ContentFingerprint.text_of>
##   EXPORT missing <path> <a file the mode's levels reach that is not there>
## For each level path given after `--` (`export`'s walk proof, the test fixtures):
##   EXPORT walk <level> <ContentFingerprint.of with a zero mode hash>
##   EXPORT reached <level> <a file the level reaches>
##   EXPORT missing <level> <a reached file that is not there>
## then `EXPORT done <modes>`. Scripts are loaded by path: outside the pack's res:// the global
## class names do not resolve, and net/ names no core/ class (ContentFingerprint's caller does).

const MODES := "res://content/modes/"
const FINGERPRINT := "res://net/messages/content_fingerprint.gd"
const CONTENT_HASH := "res://core/content/content_hash.gd"


func _initialize() -> void:
	var fingerprint: Script = load(FINGERPRINT)
	var content_hash: Script = load(CONTENT_HASH)
	var modes := 0
	for path: String in _modes():
		var mode: Resource = load(path)
		var lobby: String = mode.get("lobby_level")
		var maps: PackedStringArray = mode.get("maps")
		var levels := PackedStringArray([lobby])
		levels.append_array(maps)
		var mode_hash: int = content_hash.call("of", mode)
		print("EXPORT mode %s %d" % [path, fingerprint.call("of", mode_hash, lobby, maps) as int])
		var text: String = fingerprint.call("text_of", mode_hash, lobby, maps)
		for line: String in text.split("\n"):
			print("EXPORT text %s %s" % [path, line])
		var missing: PackedStringArray = fingerprint.call("missing_from", levels)
		for file: String in missing:
			print("EXPORT missing %s %s" % [path, file])
		modes += 1
	for level: String in OS.get_cmdline_user_args():
		var walked := PackedStringArray([level])
		var value: int = fingerprint.call("of", 0, level, PackedStringArray())
		print("EXPORT walk %s %d" % [level, value])
		var reached: PackedStringArray = fingerprint.call("reached_from", walked)
		for file: String in reached:
			print("EXPORT reached %s %s" % [level, file])
		var gone: PackedStringArray = fingerprint.call("missing_from", walked)
		for file: String in gone:
			print("EXPORT missing %s %s" % [level, file])
	print("EXPORT done %d" % modes)
	quit(0)


## The modes' resource paths, as the project names them: an export lists a converted resource as
## `<name>.remap`.
func _modes() -> PackedStringArray:
	var paths := PackedStringArray()
	for file: String in DirAccess.get_files_at(MODES):
		var name := file.trim_suffix(".remap")
		if name.get_extension() in ["tres", "res"] and not paths.has(MODES + name):
			paths.append(MODES + name)
	paths.sort()
	return paths
