extends GdUnitTestSuite
## UiOverlays (#488 rule 2): Esc closes the open overlay on top, one per press; the map key closes
## only a card.

var _stubs: Array[Stub] = []


## An overlay that remembers whether it is open and how often it was closed.
class Stub:
	extends Node
	var open := true
	var closes := 0

	func is_open() -> bool:
		return open

	func close() -> void:
		open = false
		closes += 1


func after_test() -> void:
	for stub: Stub in _stubs:
		if is_instance_valid(stub):
			stub.free()
	_stubs.clear()


func test_esc_walks_down_the_layers_one_overlay_per_press() -> void:
	var overlays := UiOverlays.new()
	# Added out of order: the layer decides, not the order.
	var esc_menu := _add(overlays, &"esc_menu", UiOverlays.ESC_MENU)
	var map := _add(overlays, &"map", UiOverlays.MAP)
	var dialog := _add(overlays, &"esc_dialog", UiOverlays.ESC_DIALOG)
	var card := _add(overlays, &"card", UiOverlays.CARD, true)
	var panel := _add(overlays, &"menu_panel", UiOverlays.MENU_PANEL)
	var closed: Array[StringName] = []
	for i in 5:
		assert_bool(overlays.is_any_open()).is_true()
		var top := overlays.top()
		assert_str(String(overlays.close_top())).is_equal(String(top))
		closed.append(top)
	assert_array(closed).contains_exactly(
		[&"esc_dialog", &"esc_menu", &"card", &"map", &"menu_panel"]
	)
	for stub: Stub in [esc_menu, map, dialog, card, panel]:
		assert_int(stub.closes).is_equal(1)
	assert_bool(overlays.is_any_open()).is_false()
	assert_str(String(overlays.close_top())).is_empty()


func test_a_closed_overlay_is_skipped_and_one_layer_takes_the_later_one() -> void:
	var overlays := UiOverlays.new()
	_add(overlays, &"map", UiOverlays.MAP)
	var card := _add(overlays, &"card", UiOverlays.CARD, true)
	card.open = false
	assert_str(String(overlays.top())).is_equal("map")
	_add(overlays, &"other", UiOverlays.MAP)
	assert_str(String(overlays.top())).is_equal("other")


func test_a_freed_overlay_counts_as_closed_and_an_id_added_again_replaces_it() -> void:
	var overlays := UiOverlays.new()
	_add(overlays, &"map", UiOverlays.MAP)
	var card := _add(overlays, &"card", UiOverlays.CARD, true)
	card.free()
	assert_str(String(overlays.top())).is_equal("map")
	var again := _add(overlays, &"card", UiOverlays.CARD, true)
	assert_str(String(overlays.close_top())).is_equal("card")
	assert_int(again.closes).is_equal(1)
	overlays.remove(&"card")
	assert_bool(overlays.has(&"card")).is_false()
	assert_bool(overlays.has(&"map")).is_true()


func test_the_map_key_closes_only_a_card() -> void:
	var overlays := UiOverlays.new()
	var map := _add(overlays, &"map", UiOverlays.MAP)
	var card := _add(overlays, &"card", UiOverlays.CARD, true)
	assert_bool(overlays.close_top_for_map_key()).is_true()
	assert_bool(card.open).is_false()
	assert_bool(map.open).is_true()
	# The map is on top now: the key is the map's, not the table's.
	assert_bool(overlays.close_top_for_map_key()).is_false()
	assert_bool(map.open).is_true()


## An open Stub registered as `id` on `layer`; freed after the test unless the test freed it.
func _add(overlays: UiOverlays, id: StringName, layer: int, card := false) -> Stub:
	var stub := Stub.new()
	overlays.add(id, layer, stub.is_open, stub.close, card)
	_stubs.append(stub)
	return stub
