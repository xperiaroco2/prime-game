extends GdUnitTestSuite
## LifeHud's words (ARCHITECTURE §4.7, the own player by life) from a fake ClientModel and the
## own LifeCountdowns: the raiser's progress, the raise hint, no own invulnerability; the
## knockdown countdown (paused while raised), who raises, the give-up hold; the respawn countdown
## and the cycling keys of a dead player, and nothing of the target's (the HUD names it, #168);
## every key named is the one bound now (#211).

const OWN := 2
const OTHER := 5

var _model: ClientModel
var _countdowns: LifeCountdowns
var _local: LifeHud.Local
var _locale := ""


func before_test() -> void:
	# The key words and the give-up line are the deck's translations (#208): English here,
	# whatever the machine's.
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
	assert_array(shown.lines).contains(["Dying in 10 s", "Hold F to give up"])
	_local.give_up_held_s = 0.5
	assert_float(_shown(19.0).progress).is_equal_approx(0.5, 1e-4)
	_fold(&"RaiseStarted", {"raiser": OTHER, "target": OWN}, 40.0)
	var raised := _shown(70.0)
	assert_array(raised.lines).contains(["Dying in 8 s (paused)", "Being raised by Player5"])
	assert_float(raised.progress).is_equal_approx(0.5, 1e-4)


func test_every_prompt_names_the_key_bound_now() -> void:
	# #211: the life view passes KeyLabel's labels of the current bindings; a rebind shows.
	_local.give_up_key = "K"
	_local.raise_key = "R"
	_local.next_key = "N"
	_local.previous_key = "P"
	_local.can_raise = true
	assert_array(_shown(0.0).lines).contains_exactly(["Hold R to raise"])
	_event(&"RaiseStarted", {"raiser": OWN, "target": OTHER}, 0.0)
	assert_str(_shown(30.0).progress_label).is_equal("Keep holding R")
	before_test()
	_local.give_up_key = "K"
	_fold(&"KnockedDown", {"peer": OWN, "position": Vector3.ZERO}, 0.0)
	assert_array(_shown(19.0).lines).contains(["Hold K to give up"])
	assert_str(" ".join(_shown(19.0).lines)).not_contains("Hold F")
	before_test()
	_local.next_key = "N"
	_local.previous_key = "P"
	_fold(&"Died", {"peer": OWN, "position": Vector3.ZERO}, 0.0)
	_local.watching = 1
	assert_array(_shown(100.0).lines).contains(["N and P: next and previous"])


func test_the_give_up_line_is_the_decks_sentence_with_the_key() -> void:
	assert_str(LifeHud.give_up_line("F")).is_equal("Hold F to give up")
	assert_str(LifeHud.give_up_line("А")).is_equal("Hold А to give up")
	# English in every language, as the rest of the greybox panel: the default panel is never
	# mixed (#211 review; the Toy downed screen, #497, translates the whole sentence).
	TranslationServer.set_locale("uk")
	assert_str(LifeHud.give_up_line("F")).is_equal("Hold F to give up")


func test_the_mouse_keys_before_read_keys_are_the_decks_words() -> void:
	assert_str(_local.next_key).is_equal("LMB")
	assert_str(_local.previous_key).is_equal("RMB")
	TranslationServer.set_locale("uk")
	var local := LifeHud.Local.new()
	assert_str(local.next_key).is_equal("ЛКМ")
	assert_str(local.previous_key).is_equal("ПКМ")


func test_the_dead_see_the_respawn_and_the_cycling_keys_only() -> void:
	_fold(&"Died", {"peer": OWN, "position": Vector3.ZERO}, 0.0)
	_local.watching = 1
	var shown := _shown(100.0)
	assert_str(shown.title).is_equal("Dead")
	var keys := "LMB and RMB: next and previous"
	assert_array(shown.lines).contains(["Respawn in 25 s", keys])
	# Nothing of the target's: no health, stamina or role words; whom it watches is the HUD's
	# "Watching: <name>" (dead.watching; #168, #489), not said twice.
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
