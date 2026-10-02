extends GdUnitTestSuite
## THROWAWAY: fails on purpose to prove CI turns red (PR is closed, branch deleted).


func test_ci_must_turn_red() -> void:
	assert_int(1 + 1).is_equal(3)
