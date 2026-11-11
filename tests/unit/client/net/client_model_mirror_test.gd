extends GdUnitTestSuite
## The mirror's places on the client (#1394): ClientModel hands MirrorPlaces to its ClientMirror,
## which keeps the list whole (a later one replaces the earlier); place_of finds a peer's place, and
## clear_match forgets them (the host's ResetMatch starts every place free).


func test_mirror_places_are_folded_whole_and_a_later_one_replaces_them() -> void:
	var model := ClientModel.new(FixtureMirror.mode())
	model.fold(&"MirrorPlaces", _places([4, 6], [2, 3]))
	assert_dict(model.mirror.places).is_equal({4: 2, 6: 3})
	assert_int(model.mirror.place_of(3)).is_equal(6)
	assert_int(model.mirror.place_of(1)).is_equal(-1)
	model.fold(&"MirrorPlaces", _places([5], [3]))
	assert_dict(model.mirror.places).is_equal({5: 3})
	assert_int(model.mirror.place_of(2)).is_equal(-1)


func test_an_empty_list_frees_every_place_and_clear_match_forgets_them() -> void:
	var model := ClientModel.new(FixtureMirror.mode())
	model.fold(&"MirrorPlaces", _places([4], [2]))
	model.fold(&"MirrorPlaces", _places([], []))
	assert_dict(model.mirror.places).is_empty()
	model.fold(&"MirrorPlaces", _places([4], [2]))
	model.clear_match()
	assert_dict(model.mirror.places).is_empty()


func test_another_event_changes_nothing() -> void:
	var mirror := ClientMirror.new()
	mirror.fold(&"MirrorPlaces", _places([4], [2]))
	mirror.fold(&"OfferMade", {"giver": 1, "target": 2})
	assert_dict(mirror.places).is_equal({4: 2})


## A MirrorPlaces' fields as the wire decodes them.
static func _places(stations: Array[int], peers: Array[int]) -> Dictionary:
	return MirrorPlacesEvent.new(PackedInt32Array(stations), PackedInt32Array(peers)).to_dict()
