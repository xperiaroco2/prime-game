extends GdUnitTestSuite
## NetRejects: counts and one summary line instead of one log line per bad packet.

const TRAILING := NetRejects.Reason.TRAILING_BYTES
const UNKNOWN := NetRejects.Reason.UNKNOWN_KIND


func test_counts_by_reason_and_peer() -> void:
	var rejects := NetRejects.new()
	rejects.count(7, TRAILING)
	rejects.count(7, TRAILING)
	rejects.count(9, UNKNOWN)
	assert_int(rejects.total()).is_equal(3)
	assert_int(rejects.of_reason(TRAILING)).is_equal(2)
	assert_int(rejects.of_reason(UNKNOWN)).is_equal(1)
	assert_int(rejects.of_reason(NetRejects.Reason.TOO_SHORT)).is_equal(0)
	assert_int(rejects.from_peer(7)).is_equal(2)
	assert_int(rejects.from_peer(9)).is_equal(1)


func test_nothing_to_summarise() -> void:
	assert_str(NetRejects.new().take_summary()).is_empty()


func test_summary_is_one_line_and_resets_only_the_pending_counts() -> void:
	var rejects := NetRejects.new()
	for _i in 1000:
		rejects.count(7, TRAILING)
	rejects.count(9, UNKNOWN)
	var summary := rejects.take_summary()
	(
		assert_str(summary)
		. is_equal(
			"net: rejected 1001 packet(s): TRAILING_BYTES x1000, UNKNOWN_KIND x1; from peer(s) 7 x1000, 9 x1"
		)
	)
	assert_int(rejects.pending()).is_equal(0)
	assert_str(rejects.take_summary()).is_empty()
	assert_int(rejects.total()).is_equal(1001)


func test_summary_names_at_most_a_few_peers() -> void:
	var rejects := NetRejects.new()
	for peer_id: int in range(10, 10 + NetRejects.SUMMARY_PEERS + 3):
		rejects.count(peer_id, UNKNOWN)
	var summary := rejects.take_summary()
	assert_str(summary).ends_with("and 3 more")
	assert_str(summary).contains("10 x1")
	assert_str(summary).not_contains("%d x1" % (10 + NetRejects.SUMMARY_PEERS))
