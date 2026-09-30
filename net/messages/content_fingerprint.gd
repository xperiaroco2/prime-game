class_name ContentFingerprint
extends RefCounted
## The content hash that Hello carries (ARCHITECTURE §4.3 "The content", E1): the game mode's
## ContentHash combined with the SHA-256 of every level file the mode names (the lobby, then the
## maps in order). ContentHash covers scripts and levels only by path, so without the files a
## designer's branch that moved a wall would join main and meet unexplained corrections. The host's
## server/ and every client compute it from their own copy of the mode, so both sides must call
## this one function. Any byte of a level counts; a missing file counts as missing.


## The fingerprint of `mode` and its level files, an s64.
static func of(mode: GameMode) -> int:
	var lines := PackedStringArray(["mode %d" % ContentHash.of(mode)])
	var paths := PackedStringArray([mode.lobby_level])
	paths.append_array(mode.maps)
	for path: String in paths:
		var digest := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
		lines.append("level %s %s" % [path, digest if not digest.is_empty() else "missing"])
	return "\n".join(lines).sha256_buffer().decode_s64(0)
