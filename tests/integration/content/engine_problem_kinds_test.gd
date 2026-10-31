extends GdUnitTestSuite
## The ship engine's provisional problem kinds in content/ (#1461, part 2 of #1225; the engineer
## approves them in the PR): content/tasks/gills.tres, breakers.tres and crystal.tres and the
## crystal's item kinds load with GDD §8's placeholder numbers, and each kind's check passes on a
## mode holding them (the fixture engine mode with the content kinds; base_mode wiring is #1462).

const GILLS := "res://content/tasks/gills.tres"
const BREAKERS := "res://content/tasks/breakers.tres"
const CRYSTAL := "res://content/tasks/crystal.tres"
const SPENT := "res://content/items/crystal_spent.tres"
const CHARGED := "res://content/items/crystal_charged.tres"


func test_the_numbers_are_gdd_section_8_s_placeholders() -> void:
	var gills := load(GILLS) as GillsProblem
	assert_float(gills.seconds).is_equal(10.0)
	assert_float(gills.step_seconds).is_equal(0.6)
	assert_int(gills.site_count).is_equal(2)
	assert_str(String(gills.site.spawn_tag)).is_equal("gill_button")
	var breakers := load(BREAKERS) as BreakersProblem
	assert_float(breakers.seconds).is_equal(30.0)
	assert_array(Array(breakers.trips)).is_equal([2, 4, 6])
	assert_array(Array(breakers.side_changes)).is_equal([0, 1, 5])
	assert_str(String(breakers.site.spawn_tag)).is_equal("breaker_board")
	assert_str(String(breakers.fixtures[0].spawn_tag)).is_equal("breaker")
	var crystal := load(CRYSTAL) as CrystalProblem
	assert_float(crystal.seconds).is_equal(30.0)
	assert_float(crystal.charge_seconds).is_equal(10.0)
	assert_int(crystal.site_count).is_equal(4)
	assert_str(String(crystal.site.spawn_tag)).is_equal("cartridge_socket")
	assert_str(String(crystal.fixtures[0].spawn_tag)).is_equal("cartridge_charger")
	assert_bool(crystal.spent.is_two_handed()).is_true()
	assert_bool(crystal.charged.is_two_handed()).is_true()


func test_each_kind_checks_clean_on_a_mode_holding_it() -> void:
	var kinds: Array[ProblemKind] = [
		load(GILLS) as ProblemKind, load(BREAKERS) as ProblemKind, load(CRYSTAL) as ProblemKind
	]
	var mode := FixtureEngineModes.basic()
	FixtureEngineModes.type_of(mode).kinds = kinds
	mode.item_kinds.append(load(SPENT) as ItemKind)
	mode.item_kinds.append(load(CHARGED) as ItemKind)
	for kind: ProblemKind in kinds:
		assert_array(Array(kind.check(mode))).is_empty()
	for item_kind: ItemKind in [load(SPENT) as ItemKind, load(CHARGED) as ItemKind]:
		assert_array(Array(item_kind.check(mode))).is_empty()
