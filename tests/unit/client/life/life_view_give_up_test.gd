extends GdUnitTestSuite
## LifeView's give-up hold (client/life/life_view.gd; the M4 ADR's D6): G held for GIVE_UP_HOLD_S
## while downed sends GiveUp() once, counted only from a press made while downed. G is also the
## throw key (#645): a living player who holds G for a throw as it is knocked down must not give
## up for holding on.

const Harness := preload("res://tests/unit/client/net/client_session_harness.gd")

var _harness: Harness
var _model: ClientModel
var _life: LifeView


func before_test() -> void:
	_harness = Harness.new()
	_harness.welcome(&"round")
	_model = _harness.session.model
	_life = auto_free(LifeView.new())
	var avatars: AvatarViews = auto_free(AvatarViews.new())
	_life.setup(_harness.session, _harness.mode, avatars)


func after_test() -> void:
	_harness.close()


func test_g_held_through_the_knockdown_gives_nothing_up_until_let_go() -> void:
	_knock_down()
	for i: int in 4:
		_life.hold_give_up(true, 0.5)
	assert_array(_gave_up()).is_empty()
	_life.hold_give_up(false, 0.1)
	_life.hold_give_up(true, 0.6)
	assert_array(_gave_up()).is_empty()
	_life.hold_give_up(true, 0.6)
	assert_array(_gave_up()).has_size(1)


func test_a_press_let_go_early_starts_the_hold_again() -> void:
	_knock_down()
	_life.hold_give_up(false, 0.1)
	_life.hold_give_up(true, LifeView.GIVE_UP_HOLD_S * 0.75)
	_life.hold_give_up(false, 0.1)
	_life.hold_give_up(true, LifeView.GIVE_UP_HOLD_S * 0.75)
	assert_array(_gave_up()).is_empty()
	_life.hold_give_up(true, LifeView.GIVE_UP_HOLD_S * 0.5)
	assert_array(_gave_up()).has_size(1)


func _knock_down() -> void:
	# Through the session, as the host sends it: the model folds it, then LifeView hears it.
	_harness.send(KnockedDownEvent.new(_model.own_peer, Vector3.ZERO))
	_harness.pump()
	assert_int(_model.life_of(_model.own_peer)).is_equal(ClientModel.Life.DOWNED)


func _gave_up() -> Array[WireMessage]:
	_harness.pump()
	return _harness.sent_named(Intents.GIVE_UP)
