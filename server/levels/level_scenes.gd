class_name LevelScenes
extends RefCounted
## The level scenes one host start reads (ARCHITECTURE §4.5 Starting, #1068): each level's
## PackedScene loaded from disk once and held here, so LevelWorld.build (HostWorldQuery.for_mode)
## and MarkerReader.read_scene (read_levels) share it. Without a held reference ResourceLoader
## frees the scene when the first reader returns and the second reads the file again: about
## 2 s for the House. HostWorldQuery.for_mode makes one and HostSession.start releases it once
## the markers are read, so the node-heavy scene is not held for the whole match.
##
## load_packed() is the one place server/ loads a level scene; `reads` counts its loads per path
## (the tests' proof of one read per start, a process-wide count: compare before and after).

## How many times load_packed() loaded each path in this process.
static var reads: Dictionary[String, int] = {}

var _scenes: Dictionary[String, PackedScene] = {}


## The PackedScene at `level_path`, loaded now; null (and no read counted) when there is none.
static func load_packed(level_path: String) -> PackedScene:
	if not ResourceLoader.exists(level_path, "PackedScene"):
		return null
	reads[level_path] = reads.get(level_path, 0) + 1
	return load(level_path) as PackedScene


## The PackedScene at `level_path`, loaded on the first ask and held until release(); null when
## there is none (asked again, it is looked for again).
func scene(level_path: String) -> PackedScene:
	if _scenes.has(level_path):
		return _scenes[level_path]
	var loaded := load_packed(level_path)
	if loaded != null:
		_scenes[level_path] = loaded
	return loaded


## Drops every held scene: ResourceLoader frees each one nothing else holds.
func release() -> void:
	_scenes.clear()


## A level scene from `scenes` when given, else loaded directly (no cache).
static func scene_of(level_path: String, scenes: LevelScenes) -> PackedScene:
	return scenes.scene(level_path) if scenes != null else load_packed(level_path)
