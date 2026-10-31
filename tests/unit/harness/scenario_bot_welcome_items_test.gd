extends GdUnitTestSuite
## ScenarioBot learns the hall's items from its Welcome (#1404; ARCHITECTURE §4.2, §9.7): a bot
## that joins after items were put down or taken knows each by id, kind, position and rest state,
## at no station, in place of any it knew.

const PEER := 5


func test_a_welcomed_bot_knows_the_lying_and_the_carried_items() -> void:
	var steps: Array[ScenarioStep] = []
	var bot := ScenarioBot.new(1, PEER, steps)
	bot.items[99] = {"kind": &"old", "position": Vector3.ZERO, "where": 0, "station": -1}
	var rows: Array[Dictionary] = [
		_row(3, &"mug", ScenarioBot.Where.HAND, 1, 0, Vector3(0, 0, -0.5)),
		_row(4, &"mug_empty", ScenarioBot.Where.GROUND, 0, 0, Vector3(2, 0, 1)),
	]
	var welcome := {
		"peer": PEER,
		"epoch": 1,
		"spot": Vector3.ZERO,
		"phase": &"lobby",
		"positions": {},
		"items": rows,
	}
	assert_str(bot.receive(&"Welcome", welcome)).is_empty()
	assert_array(bot.items.keys()).contains_exactly_in_any_order([3, 4])
	assert_dict(bot.items[3]).is_equal(
		{
			"kind": &"mug",
			"position": Vector3(0, 0, -0.5),
			"where": ScenarioBot.Where.HAND,
			"station": -1
		}
	)
	assert_dict(bot.items[4]).is_equal(
		{
			"kind": &"mug_empty",
			"position": Vector3(2, 0, 1),
			"where": ScenarioBot.Where.GROUND,
			"station": -1
		}
	)
	# A later take of the lying one is folded as for any item the bot knew.
	assert_str(bot.receive(&"ItemPickedUp", {"peer": 1, "item": 4, "place": 1})).is_empty()
	assert_int(bot.items[4]["where"]).is_equal(ScenarioBot.Where.HAND)


func _row(
	id: int, kind: StringName, where: int, holder: int, place: int, at: Vector3
) -> Dictionary:
	return {
		"item": id, "kind": kind, "where": where, "holder": holder, "place": place, "position": at
	}
