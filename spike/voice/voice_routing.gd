class_name SpikeVoiceRouting
extends RefCounted
## Spike (#15): the host's voice routing rule, a stand-in for the real rule in core/ (ARCHITECTURE
## §6): pure, no nodes, no audio. It decides for each speaker and listener pair whether the
## speaker's voice is delivered at all. How loud it sounds is the listener's job (the
## AudioStreamPlayer3D on the speaker's avatar), with the same cutoff as its max_distance, so the
## volume reaches zero about where delivery stops. Not exactly: the host measures between accepted
## capsule centres, the audio engine from the listener's camera to the speaker's drawn mouth, one
## interpolation delay behind; the two differ by up to walking speed x (that delay + half a round
## trip), a few tenths of a metre. Fading is cosmetic: only the host's cutoff limits who hears.
## M1 rule: a plain distance cutoff. Walls, death, meetings and radios come in M5.

var cutoff := 8.0  # metres


func hears(speaker_pos: Vector3, listener_pos: Vector3) -> bool:
	return speaker_pos.distance_to(listener_pos) <= cutoff


## The peers that hear `speaker`, in ascending id order. `positions` holds every placed player,
## the speaker included; a speaker never hears itself, and an unplaced speaker is heard by no one.
func listeners_of(speaker: int, positions: Dictionary[int, Vector3]) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not positions.has(speaker):
		return out
	var from := positions[speaker]
	var ids: Array[int] = positions.keys()
	ids.sort()
	for id: int in ids:
		if id != speaker and hears(from, positions[id]):
			out.append(id)
	return out
