extends GdUnitTestSuite
## The lesson runner stays pure (docs/design/tutorial.md §3, E63; #602): a RefCounted that reads
## only what it is handed. Its source (comments and strings stripped) names no node, no input, no
## scene tree, no session or host, and sends nothing: `next_stage_requested` is its one way out.

const BOUNDARY := preload("res://tests/unit/client/app/client_boundary_test.gd")
const RUNNER := "res://client/tutorial/lesson_runner.gd"
const FORBIDDEN := (
	"\\b(Node|Node3D|Input|InputMap|get_tree|ClientSession|HostNode|SessionNode|Game|"
	+ "VoiceSender|LifeView|GameUi|MapScreen|send_[a-z_]*|get_node[a-z_]*)\\b"
)


func test_the_runner_names_no_node_input_session_or_send() -> void:
	var script := load(RUNNER) as Script
	assert_str(script.get_instance_base_type()).is_equal("RefCounted")
	assert_array(problems(FileAccess.get_file_as_string(RUNNER))).is_empty()


func test_it_rejects_the_planted_reads() -> void:
	assert_array(problems("var s: ClientSession")).has_size(1)
	assert_array(problems('session.send_intent(&"NextStage")')).has_size(1)
	assert_array(problems('if Input.is_action_pressed(&"map"):')).has_size(1)
	assert_array(problems("var tree := get_tree()")).has_size(1)
	assert_array(problems("# Input in a comment\nvar x := 1")).is_empty()
	assert_array(problems('var s := "send_intent in a string"')).is_empty()


static func problems(source: String) -> PackedStringArray:
	var found := PackedStringArray()
	for hit: RegExMatch in RegEx.create_from_string(FORBIDDEN).search_all(BOUNDARY.strip(source)):
		found.append("names %s" % hit.get_string())
	return found
