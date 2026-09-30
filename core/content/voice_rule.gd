class_name VoiceRule
extends ContentPart
## Who hears whom in a phase (ARCHITECTURE §6): one per phase spec. Match records each peer's
## speakers per tick for view_of (§5), and server/ forwards a voice frame only along these pairs.
## This base class is silent: nobody hears anybody. Subclasses (Silent, Proximity, RoundVoice)
## come in 2i.


## Whether `listener` hears `speaker` now. Never called for a player who left.
func hears(_state: MatchState, _listener: int, _speaker: int) -> bool:
	return false


## The speakers `listener` hears now, in peer-id order. A player who left hears and is heard by
## nobody.
func speakers_of(state: MatchState, listener: int) -> PackedInt32Array:
	var heard := PackedInt32Array()
	if not state.is_present(listener):
		return heard
	for speaker: int in state.present_peers():
		if speaker != listener and hears(state, listener, speaker):
			heard.append(speaker)
	return heard
