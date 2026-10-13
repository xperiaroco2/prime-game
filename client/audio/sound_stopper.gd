class_name SoundStopper
extends RefCounted
## Stops the sounds before the process quits (#891; Game.quit): a player freed while it plays
## leaves its playback, and so its stream, held by the audio server past the tree, which the
## engine reports at exit as resources still in use (an engine error line: playcheck fails the
## window that prints one). The audio server lets go of a stopped playback on its own thread a mix
## or two later, so the quit waits for that.

## The longest released() waits.
const WAIT_MS := 500


## Stops every sound under the root of `tree`, calls `leave` (ending the session), and quits once
## the audio server has let go of the sounds stopped (or after WAIT_MS).
static func quit(tree: SceneTree, leave: Callable) -> void:
	var playbacks := stop_and_leave(tree.root, leave)
	await released(tree, playbacks)
	tree.quit()


## Stops every sound player under `root`, calls `leave`, and stops them again: leaving can start
## sounds (a voice speaker's flush on its way out restarts its playback, then is queue_free'd and
## so still in the tree this frame). A weak reference to each playback stopped, of both sweeps.
static func stop_and_leave(root: Node, leave: Callable) -> Array[WeakRef]:
	var playbacks := stop(root)
	leave.call()
	playbacks.append_array(stop(root))
	return playbacks


## Stops every sound player under `root`: a weak reference to each playback it stopped (a player
## with polyphony, its latest).
static func stop(root: Node) -> Array[WeakRef]:
	var playbacks: Array[WeakRef] = []
	for node: Node in root.find_children("*", "", true, false):
		if not (
			node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D
		):
			continue
		if node.call(&"has_stream_playback"):
			playbacks.append(weakref(node.call(&"get_stream_playback")) as WeakRef)
		node.call(&"stop")
	return playbacks


## Returns once every playback in `playbacks` is freed, or after WAIT_MS, waiting frame by frame
## of `tree`.
static func released(tree: SceneTree, playbacks: Array[WeakRef]) -> void:
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while held(playbacks) and Time.get_ticks_msec() < deadline:
		await tree.process_frame


## Whether any playback in `playbacks` is not freed yet.
static func held(playbacks: Array[WeakRef]) -> bool:
	return playbacks.any(func(playback: WeakRef) -> bool: return playback.get_ref() != null)
