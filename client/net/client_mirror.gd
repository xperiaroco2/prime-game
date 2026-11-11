class_name ClientMirror
extends RefCounted
## The lobby mirror's places as the own client knows them (#1394; ARCHITECTURE §7.1.24), folded
## from its public MirrorPlaces alone: ClientModel.fold hands it every event and it keeps the last
## list whole. A match fact that clear_match forgets (the host's ResetMatch starts every place
## free). The own peer holding one opens the mirror's colour menu (MirrorMenu).

## The places in use: station -> the peer holding it.
var places: Dictionary[int, int] = {}


## Folds one decoded event; any but MirrorPlaces changes nothing.
func fold(event_name: StringName, fields: Dictionary) -> void:
	if event_name != &"MirrorPlaces":
		return
	places.clear()
	var stations: PackedInt32Array = fields["stations"]
	var peers: PackedInt32Array = fields["peers"]
	for i in mini(stations.size(), peers.size()):
		places[stations[i]] = peers[i]


## The station of the place `peer` holds, or -1.
func place_of(peer: int) -> int:
	for station: int in places:
		if places[station] == peer:
			return station
	return -1
