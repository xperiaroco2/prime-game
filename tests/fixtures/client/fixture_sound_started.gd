class_name FixtureSoundStarted
extends RefCounted
## Whether a short sound was started, for the client's tests (#1195). Not `player.playing`: a UI
## sound lasts about 0.12 s and the headless (Dummy) audio driver mixes it on its own thread in
## real time, so on a loaded runner it has ended and `playing` is false again before the assert
## (#948). play() makes a playback, which the player keeps until its next frame, and no frame
## runs in a plain test: `has_stream_playback()` stays true until then or until stop().
## Use: `assert_bool(FixtureSoundStarted.of(player)).is_true()`.


static func of(player: AudioStreamPlayer) -> bool:
	return player.has_stream_playback()
