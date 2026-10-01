class_name ContentFingerprint
extends RefCounted
## The content hash that Hello carries (ARCHITECTURE §4.3 "The content", E1): the game mode's
## ContentHash combined with the SHA-256 of every level file the mode names (the lobby, then the
## maps in order). ContentHash covers scripts and levels only by path, so without the files a
## designer's branch that moved a wall would join main and meet unexplained corrections. Any byte
## of a level counts; a missing file counts as missing.
##
## net/ names no core/ class (§1), so the caller passes the mode's parts. The host's server/ and
## every client call it the same way, from their own copy of the mode:
## `ContentFingerprint.of(ContentHash.of(mode), mode.lobby_level, mode.maps)`.


## The fingerprint of a mode whose ContentHash is `content_hash`, with its lobby level and maps,
## an s64.
static func of(content_hash: int, lobby_level: String, maps: PackedStringArray) -> int:
	var lines := PackedStringArray(["mode %d" % content_hash])
	var paths := PackedStringArray([lobby_level])
	paths.append_array(maps)
	for path: String in paths:
		var digest := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
		lines.append("level %s %s" % [path, digest if not digest.is_empty() else "missing"])
	return "\n".join(lines).sha256_buffer().decode_s64(0)
