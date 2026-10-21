class_name ContentFingerprintCache
extends RefCounted
## ContentFingerprint once per process (#1172): the fingerprint of a mode's parts, computed the
## first time they are asked for and kept, keyed by the mode's ContentHash and its level paths, and
## computed again when a level file's modified time or size changed. The walk hashes every file
## the levels reach (2016 files, 5.5 s on the engineer's PC since the House assets), and a join
## asked for it twice (game.gd's join_target, then its ClientSession), a host start twice
## (HostSession.start_with, then its own client's session): an 11 s freeze per join.
##
## Only the level files are checked (the engineer's decision on #1172): reading the modified time
## and size of every file the levels reach costs about 0.3 s, a freeze of its own, and a running
## game reads its scenes once anyway (the editor's Run starts a new process). So a room or an asset
## edited while a process runs keeps its old hash until a level file changes or the process
## restarts. `ContentFingerprint.of` itself never caches: its tests rewrite files and expect
## another value at once.
##
## The host's server/ and every client call it the same way, from their own copy of the mode:
## `ContentFingerprintCache.of(ContentHash.of(mode), mode.lobby_level, mode.maps)`. net/ names no
## core/ class (§1), so the caller passes the mode's parts.


## What one computation kept: the fingerprint and the level files' stamps it was computed with.
class Entry:
	extends RefCounted
	var value := 0
	var stamps := PackedInt64Array()


## The process's cache, which `of` uses; made on first use.
static var _shared: ContentFingerprintCache

## How many fingerprints this cache was asked for, and how many of them it computed (the rest it
## had kept): its tests count them.
var asked := 0
var computed := 0
var _entries: Dictionary[String, Entry] = {}
## (levels: PackedStringArray) -> PackedInt64Array, as `stamps_of`; invalid: `stamps_of` itself.
var _stamper := Callable()


## A cache of its own, reading the levels' stamps through `stamper` (a test's fake clock), or
## through `stamps_of` when it is not valid.
func _init(stamper := Callable()) -> void:
	_stamper = stamper


## The process's cache: `ContentFingerprint.of(content_hash, lobby_level, maps)`, computed again
## only when these parts were never asked for in this process or a level file changed since.
static func of(content_hash: int, lobby_level: String, maps: PackedStringArray) -> int:
	return shared().fingerprint(content_hash, lobby_level, maps)


## The cache `of` uses.
static func shared() -> ContentFingerprintCache:
	if _shared == null:
		_shared = ContentFingerprintCache.new()
	return _shared


## Each level file's modified time (Unix seconds) and size, in the levels' order: 0 and -1 for a
## missing one (a fixture mode's levels; an export's, which ships a `.remap` in their place and
## never changes).
static func stamps_of(levels: PackedStringArray) -> PackedInt64Array:
	var stamps := PackedInt64Array()
	for path: String in levels:
		# Both print an engine error for a file that is not there.
		var there := FileAccess.file_exists(path)
		stamps.append(FileAccess.get_modified_time(path) if there else 0)
		stamps.append(FileAccess.get_size(path) if there else -1)
	return stamps


## `ContentFingerprint.of(content_hash, lobby_level, maps)`, kept per mode hash and level list
## until a level file's stamp changes.
func fingerprint(content_hash: int, lobby_level: String, maps: PackedStringArray) -> int:
	asked += 1
	var levels := PackedStringArray([lobby_level])
	levels.append_array(maps)
	var key := "%d\n%s" % [content_hash, "\n".join(levels)]
	var stamps: PackedInt64Array
	if _stamper.is_valid():
		stamps = _stamper.call(levels)
	else:
		stamps = stamps_of(levels)
	var kept: Entry = _entries.get(key)
	if kept != null and kept.stamps == stamps:
		return kept.value
	var entry := Entry.new()
	entry.value = ContentFingerprint.of(content_hash, lobby_level, maps)
	entry.stamps = stamps
	_entries[key] = entry
	computed += 1
	return entry.value
