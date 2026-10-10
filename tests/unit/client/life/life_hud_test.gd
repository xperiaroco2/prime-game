extends GdUnitTestSuite
## LifeHud (#497; ARCHITECTURE §4.7.44): what the downed, dead and respawn screen shows, from a fake
## ClientModel and the own LifeCountdowns: nothing while living; downed, the bleed-out fraction and
## m:ss, the give-up hold and the key bound now (#211); raised, the raiser and the raise; dead, the
## respawn and the watched name and nothing of the target's; back, the respawn's protection
## counting 3, 2, 1 (none after a raise); the give-up sentence's pieces in English and Ukrainian.

const OWN := 2
const OTHER := 5

var _model: ClientModel
var _countdowns: LifeCountdowns
var _local: LifeHud.Local
var _locale := ""


func before_test() -> void:
	# The give-up sentence is the deck's (#208): English here, whatever the machine's.
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_model = ClientModel.new(FixtureBaseMode.mode())
	_model.own_peer = OWN
	for peer: int in [1, OWN, OTHER]:
		var member := ClientModel.Member.new()
		member.name = "Player%d" % peer
		_model.roster[peer] = member
	_countdowns = LifeCountdowns.new(FixtureModes.player_rules(), 3.0)
	_local = LifeHud.Local.new()


func after_test() -> void:
	TranslationServer.set_locale(_locale)


func test_a_living_player_shows_nothing() -> void:
	var shown := _shown(0.0)
	assert_int(shown.state).is_equal(LifeHud.State.NONE)
	assert_int(shown.protected).is_equal(0)
	# Raising someone else is the HUD's bar (#489), never this screen.
	_event(&"RaiseStarted", {"raiser": OWN, "target": OTHER}, 0.0)
	assert_int(_shown(30.0).state).is_equal(LifeHud.State.NONE)


func test_the_downed_see_the_bleed_out_and_the_give_up_hold() -> void:
	_fold(&"KnockedDown", {"peer": OWN, "position": Vector3.ZERO}, 0.0)
	var shown := _shown(60.0)
	assert_int(shown.state).is_equal(LifeHud.State.DOWN)
	assert_float(shown.bleed).is_equal_approx(0.7, 1e-4)
	assert_str(shown.time_left).is_equal("0:07")
	assert_float(shown.give_up).is_equal(0.0)
	assert_str(shown.give_up_key).is_equal("F")
	# A part second rounds up, as a countdown reads: 6.05 s left is "0:07".
	assert_str(_shown(79.0).time_left).is_equal("0:07")
	assert_str(_shown(81.0).time_left).is_equal("0:06")
	_local.give_up_held_s = 0.45
	assert_float(_shown(60.0).give_up).is_equal_approx(0.45, 1e-4)
	_local.give_up_held_s = 3.0
	assert_float(_shown(60.0).give_up).is_equal(1.0)


func test_the_give_up_key_is_the_one_bound_now() -> void:
	# #211: the life view passes KeyLabel's label of the binding now; a rebind shows.
	_fold(&"KnockedDown", {"peer": OWN, "position": Vector3.ZERO}, 0.0)
	_local.give_up_key = "K"
	assert_str(_shown(0.0).give_up_key).is_equal("K")
	assert_bool(_shown(0.0).give_up_wide).is_false()
	_local.give_up_wide = true
	assert_bool(_shown(0.0).give_up_wide).is_true()


func test_the_raised_see_the_raiser_and_the_raise_in_place_of_the_bleed_out() -> void:
	_fold(&"KnockedDown", {"peer": OWN, "position": Vector3.ZERO}, 0.0)
	_fold(&"RaiseStarted", {"raiser": OTHER, "target": OWN}, 40.0)
	var raised := _shown(76.0)
	assert_int(raised.state).is_equal(LifeHud.State.RAISE)
	assert_str(raised.raiser).is_equal("Player5")
	assert_float(raised.raise).is_equal_approx(0.6, 1e-4)
	# The teammate stops: the bleed-out returns where it paused (8 s of 10).
	_fold(&"RaiseStopped", {"raiser": OTHER, "target": OWN}, 80.0)
	var again := _shown(80.0)
	assert_int(again.state).is_equal(LifeHud.State.DOWN)
	assert_float(again.bleed).is_equal_approx(0.8, 1e-4)
	assert_str(again.time_left).is_equal("0:08")


func test_the_dead_see_the_respawn_and_whom_they_watch_only() -> void:
	_fold(&"Died", {"peer": OWN, "position": Vector3.ZERO}, 0.0)
	_local.watching = 1
	var shown := _shown(120.0)
	assert_int(shown.state).is_equal(LifeHud.State.DEAD)
	assert_str(shown.respawn).is_equal("0:24")
	assert_str(shown.watching).is_equal("Player1")
	# Nothing of the target's, and nothing of the downed plates.
	assert_str(shown.raiser).is_empty()
	assert_str(shown.time_left).is_empty()
	assert_int(shown.protected).is_equal(0)
	_local.watching = 0
	assert_str(_shown(120.0).watching).is_empty()
	# A minute or more reads m:ss.
	assert_str(LifeHud.clock_text(65)).is_equal("1:05")


func test_back_counts_the_respawns_protection_and_a_raise_shows_none() -> void:
	_fold(&"Died", {"peer": OWN, "position": Vector3.ZERO}, 0.0)
	_fold(&"Respawned", {"peer": OWN, "position": Vector3.ZERO}, 600.0)
	assert_int(_shown(600.0).state).is_equal(LifeHud.State.NONE)
	assert_int(_shown(600.0).protected).is_equal(3)
	assert_int(_shown(625.0).protected).is_equal(2)
	assert_int(_shown(645.0).protected).is_equal(1)
	assert_int(_shown(660.0).protected).is_equal(0)
	_fold(&"KnockedDown", {"peer": OWN, "position": Vector3.ZERO}, 700.0)
	_fold(&"Revived", {"peer": OWN}, 720.0)
	assert_int(_shown(720.0).protected).is_equal(0)


func test_the_give_up_sentence_splits_at_the_key_in_english_and_ukrainian() -> void:
	var english := LifeHud.give_up_pieces(tr("downed.give_up_hold"))
	assert_array(Array(english)).contains_exactly(["Hold", "to give up"])
	TranslationServer.set_locale("uk")
	var ukrainian := LifeHud.give_up_pieces(tr("downed.give_up_hold"))
	assert_array(Array(ukrainian)).contains_exactly(["Щоб здатися, утримуй", ""])
	assert_array(Array(LifeHud.give_up_pieces("no key here "))).contains_exactly(
		["no key here", ""]
	)


func _shown(tick: float) -> LifeHud.Shown:
	return LifeHud.of(_model, _countdowns, tick, _local)


## An event the model and the countdowns both take, as the game feeds them.
func _fold(event_name: StringName, fields: Dictionary, tick: float) -> void:
	_model.fold(event_name, fields)
	_event(event_name, fields, tick)


func _event(event_name: StringName, fields: Dictionary, tick: float) -> void:
	_countdowns.on_event(event_name, fields, OWN, tick)
