extends GdUnitTestSuite
## The own screen at the ship's zap (client/world/ShipZapScreen, #1585): ShipZapped starts the blue
## flash and the notice for the mode's seconds, each ends on its own, a phase change ends both, any
## other event starts nothing and a mode without the crystal never starts.

const DT := 0.05


func _screen(with_crystal: bool = true) -> ShipZapScreen:
	var screen: ShipZapScreen = auto_free(ShipZapScreen.new())
	var kinds: Array[ProblemKind] = []
	if with_crystal:
		kinds.append(FixtureEngineKindModes.crystal())
	screen.set_mode(FixtureEngineKindModes.of(kinds))
	return screen


func _run(screen: ShipZapScreen, seconds: float) -> void:
	for _i in roundi(seconds / DT):
		screen._process(DT)


func test_the_numbers_are_the_crystal_kinds() -> void:
	var kinds: Array[ProblemKind] = [FixtureEngineKindModes.crystal()]
	assert_object(ShipZapScreen.crystal_of(FixtureEngineKindModes.of(kinds))).is_not_null()
	var none: Array[ProblemKind] = []
	assert_object(ShipZapScreen.crystal_of(FixtureEngineKindModes.of(none))).is_null()
	assert_object(ShipZapScreen.crystal_of(null)).is_null()


func test_nothing_shows_until_the_zap() -> void:
	var screen := _screen()
	assert_bool(screen.notice_showing()).is_false()
	assert_float(screen.flash_alpha()).is_equal(0.0)
	screen.on_event(&"ItemPlaced", {"cause": CrystalProblem.ZAPPED})
	assert_bool(screen.notice_showing()).is_false()
	assert_float(screen.flash_alpha()).is_equal(0.0)


func test_the_flash_is_blue_and_fades_in_its_seconds_and_the_notice_stays() -> void:
	var screen := _screen()
	screen.on_event(&"ShipZapped", {})
	var peak := screen.flash_alpha()
	assert_float(peak).is_equal_approx(ShipZapScreen.FLASH_PEAK.a, 0.001)
	assert_float(ShipZapScreen.FLASH_PEAK.b).is_greater(ShipZapScreen.FLASH_PEAK.r)
	_run(screen, FixtureEngineKindModes.ZAP_FLASH_SECONDS * 0.5)
	assert_float(screen.flash_alpha()).is_greater(0.0)
	assert_float(screen.flash_alpha()).is_less(peak)
	_run(screen, FixtureEngineKindModes.ZAP_FLASH_SECONDS * 0.5 + DT)
	assert_float(screen.flash_alpha()).is_equal(0.0)
	assert_bool(screen.overlay.visible).is_false()
	assert_bool(screen.notice_showing()).is_true()


func test_the_notice_ends_after_its_seconds() -> void:
	var screen := _screen()
	screen.on_event(&"ShipZapped", {})
	_run(screen, FixtureEngineKindModes.ZAP_NOTICE_SECONDS - 2 * DT)
	assert_bool(screen.notice_showing()).is_true()
	_run(screen, 3 * DT)
	assert_bool(screen.notice_showing()).is_false()
	assert_bool(screen.is_processing()).is_false()


func test_a_phase_change_ends_both_at_once() -> void:
	var screen := _screen()
	screen.on_event(&"ShipZapped", {})
	screen.on_event(&"PhaseChanged", {})
	assert_bool(screen.notice_showing()).is_false()
	assert_float(screen.flash_alpha()).is_equal(0.0)
	assert_bool(screen.is_processing()).is_false()


func test_a_mode_without_the_crystal_shows_nothing() -> void:
	var screen := _screen(false)
	screen.on_event(&"ShipZapped", {})
	assert_bool(screen.notice_showing()).is_false()
	assert_float(screen.flash_alpha()).is_equal(0.0)
