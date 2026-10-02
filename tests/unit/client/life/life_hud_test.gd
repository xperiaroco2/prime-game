extends GdUnitTestSuite
## LifeHud's words (ARCHITECTURE §4.7, the own player by life) from a fake ClientModel and the
## own LifeCountdowns: the raiser's progress, the raise hint, no own invulnerability; the
## knockdown countdown (paused while raised), who raises, the give-up hold; the respawn countdown
## and the cycling keys of a dead player, and nothing of the target's (the HUD names it, #168).

const OWN := 2
const OTHER := 5

var _model: ClientModel
var _countdowns: LifeCountdowns
var _local: LifeHud.Local


func before_test() -> void:
	_model = ClientModel.new(FixtureBaseMode.mode())
	_model.own_peer = OWN
	for peer: int in [1, OWN, OTHER]:
		var member := ClientModel.Member.new()
		member.name = "Player%d" % peer
		_model.roster[peer] = member
	_countdowns = LifeCountdowns.new(FixtureModes.player_rules(), 3.0)
	_local = LifeHud.Local.new()


func test_a_living_player_with_nothing_to_show_shows_no_panel() -> void:
	assert_str(_shown(0.0).title).is_empty()


func test_the_raiser_sees_its_progress_and_the_hint_over_a_downed_player() -> void:
	_local.can_raise = true
	var hint := _shown(0.0)
	assert_str("\n".join(hint.lines)).contains("Hold E to raise")
	assert_float(hint.progress).is_less(0.0)
	_event(&"RaiseStarted", {"raiser": OWN, "target": OTHER}, 0.0)
	var raising := _shown(30.0)
	assert_str(raising.title).is_equal("Raising Player5")
	assert_float(raising.progress).is_equal_approx(0.5, 1e-4)


func test_the_own_invulnerability_shows_no_panel() -> void:
	# The engineer's answer 2 on PR #167: no own invulnerability read-out for now (a later buffs
	# UI may show it); the countdown itself still runs (LifeCountdowns).
	_event(&"Respawned", {"peer": OWN, "position": Vector3.ZERO}, 0.0)
	assert_float(_countdowns.invulnerable_left_s(20.0)).is_greater(0.0)
	var shown := _shown(20.0)
	assert_str(shown.title).is_empty()
	assert_array(shown.lines).is_empty()
	# Over a downed player in reach the raise hint still shows, with no invulnerability words.
	_local.can_raise = true
	var hint := _shown(20.0)
	assert_str(hint.title).is_equal("Downed player")
	assert_array(hint.lines).contains_exactly(["Hold E to raise"])


func test_the_downed_see_the_countdown_the_raiser_and_the_give_up() -> void:
	_fold(&"KnockedDown", {"peer": OWN, "position": Vector3.ZERO}, 0.0)
	var shown := _shown(19.0)
	assert_str(shown.title).is_equal("Knocked down")
	assert_array(shown.lines).contains(["Dying in 10 s", "Hold G to give up"])
	_local.give_up_held_s = 0.5
	assert_float(_shown(19.0).progress).is_equal_approx(0.5, 1e-4)
	_fold(&"RaiseStarted", {"raiser": OTHER, "target": OWN}, 40.0)
	var raised := _shown(70.0)
	assert_array(raised.lines).contains(["Dying in 8 s (paused)", "Being raised by Player5"])
	assert_float(raised.progress).is_equal_approx(0.5, 1e-4)


func test_the_dead_see_the_respawn_and_the_cycling_keys_only() -> void:
	_fold(&"Died", {"peer": OWN, "position": Vector3.ZERO}, 0.0)
	_local.watching = 1
	var shown := _shown(100.0)
	assert_str(shown.title).is_equal("Dead")
	var keys := "Left and right click: next and previous"
	assert_array(shown.lines).contains(["Respawn in 25 s", keys])
	# Nothing of the target's: no health, stamina or role words; whom it watches is the HUD's
	# "Spectating <name>" (#168), not said twice.
	var all := ("\n".join(shown.lines)).to_lower()
	assert_str(all).not_contains("player1")
	for word: String in ["health", "stamina", "crew", "dissident", "role"]:
		assert_str(all).not_contains(word)
	_local.watching = 0
	assert_array(_shown(100.0).lines).contains(["Nobody to watch"])


func _shown(tick: float) -> LifeHud.Shown:
	return LifeHud.of(_model, _countdowns, tick, _local)


## An event the model and the countdowns both take, as the game feeds them.
func _fold(event_name: StringName, fields: Dictionary, tick: float) -> void:
	_model.fold(event_name, fields)
	_event(event_name, fields, tick)


func _event(event_name: StringName, fields: Dictionary, tick: float) -> void:
	_countdowns.on_event(event_name, fields, OWN, tick)
