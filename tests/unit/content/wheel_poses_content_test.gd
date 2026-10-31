extends GdUnitTestSuite
## The pose wheel's poses in `content/` (#1485, provisional data; GDD §8 "Photo", "The pose wheel";
## ARCHITECTURE §7.1.23): `content/poses/wheel_poses.tres` holds the decided 6 leg stances and 8 arm
## gestures (#1102 c6412817038) as snake_case ids in wheel order, each unique; the base mode
## references it, passes ModeCheck, takes WheelPose from the living in the Lobby, the Countdown and
## the Round (never in Loading, Pregame or End), and its rule holds WheelPoseInRange, a negated
## Posed, a negated CrouchedOrSneaking and HandNotTwoHanded, then TakeWheelPose. One pick in the
## hall reaches the other peer's snapshot. Loads `content/` and the levels on purpose (§9.6).

const BASE_MODE := "res://content/modes/base_mode.tres"
const POSES := "res://content/poses/wheel_poses.tres"
const ScenarioLevels := preload("res://tests/fixtures/scenario_levels.gd")
const GREYBOX := "res://levels/greybox/greybox.tscn"
const P1 := 1
const P2 := 2
const LEGS: Array[String] = [
	"stand", "on_one_leg", "squat", "on_one_knee", "lunge", "sit_on_ground"
]
const ARMS: Array[String] = [
	"hands_on_hips",
	"arms_out_like_a_plane",
	"flex",
	"heart",
	"finger_to_the_sky",
	"hands_behind_the_head",
	"palms_to_the_camera",
	"salute",
]


func test_the_poses_are_the_decided_six_legs_and_eight_arms_each_unique() -> void:
	var poses := load(POSES) as WheelPoses
	assert_object(poses).is_not_null()
	assert_array(Array(poses.legs)).is_equal(LEGS)
	assert_array(Array(poses.arms)).is_equal(ARMS)
	for ids: PackedStringArray in [poses.legs, poses.arms]:
		var unique: Dictionary[String, bool] = {}
		for id: String in ids:
			unique[id] = true
		assert_int(unique.size()).is_equal(ids.size())
	assert_array(Array(poses.check(null))).is_empty()


func test_the_base_mode_references_the_poses_and_passes_the_check() -> void:
	var mode := load(BASE_MODE) as GameMode
	assert_str(mode.wheel_poses.resource_path).is_equal(POSES)
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()


func test_the_living_take_it_in_the_hall_and_the_round_only() -> void:
	var mode := load(BASE_MODE) as GameMode
	for phase_id: StringName in [&"lobby", &"countdown", &"round"]:
		(
			assert_int(mode.find_phase(phase_id).senders_of(Intents.WHEEL_POSE))
			. override_failure_message(String(phase_id))
			. is_equal(AcceptSpec.From.LIVING)
		)
	for phase_id: StringName in [&"loading", &"pregame", &"end"]:
		(
			assert_int(mode.find_phase(phase_id).senders_of(Intents.WHEEL_POSE))
			. override_failure_message(String(phase_id))
			. is_equal(0)
		)


func test_the_rule_refuses_a_bad_pick_the_seated_the_lowered_and_two_hands() -> void:
	var mode := load(BASE_MODE) as GameMode
	var found: Array[Rule] = []
	for rule: Rule in mode.actions:
		if rule.trigger == Intents.WHEEL_POSE:
			found.append(rule)
	assert_array(found).has_size(1)
	var rule := found[0]
	assert_int(rule.conditions.size()).is_equal(4)
	assert_object(rule.conditions[0]).is_instanceof(WheelPoseInRange)
	assert_bool(rule.conditions[0].negate).is_false()
	assert_object(rule.conditions[1]).is_instanceof(Posed)
	assert_bool(rule.conditions[1].negate).is_true()
	assert_object(rule.conditions[2]).is_instanceof(CrouchedOrSneaking)
	assert_bool(rule.conditions[2].negate).is_true()
	assert_object(rule.conditions[3]).is_instanceof(HandNotTwoHanded)
	assert_bool(rule.conditions[3].negate).is_false()
	assert_int(rule.effects.size()).is_equal(1)
	assert_object(rule.effects[0]).is_instanceof(TakeWheelPose)


func test_a_pick_in_the_hall_reaches_the_other_peer_s_snapshot() -> void:
	var mode := load(BASE_MODE) as GameMode
	var levels := MarkerReader.read_levels(
		mode, FlatWorldQuery.new(), ScenarioLevels.unsnapped(mode)
	)
	assert_array(Array(levels.errors)).is_empty()
	var game := Match.new(mode, 7, FlatWorldQuery.new(), levels.layouts)
	game.state.map = GREYBOX
	game.keep_history = true
	assert_bool(game.start(0)).is_true()
	for peer: int in [P1, P2]:
		FixtureBaseMode.join(game, peer)
	FixtureModes.run_ticks(game, 1)
	FixtureMoves.wheel_pose(game, P1, LEGS.size() - 1, ARMS.size() - 1, 1)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_empty()
	var avatars: Dictionary = game.snapshot_for(P2).get("avatars", {})
	var avatar: Dictionary = avatars.get(P1, {})
	assert_int(avatar.get("wheel_pose", WheelPoseCode.NONE)).is_equal(
		WheelPoseCode.encode(LEGS.size() - 1, ARMS.size() - 1)
	)
	FixtureMoves.wheel_pose(game, P1, LEGS.size(), 0, 2)
	FixtureModes.run_ticks(game, 1)
	assert_array(FixtureModes.rejections(game, P1)).is_equal([WheelPoseInRange.NO_SUCH_POSE])
