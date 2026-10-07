extends RefCounted
## The shared signalling transcripts in tests/fixtures/signal/ (ARCHITECTURE §4.8), one exchange
## per file, which SignalRouter, LanSignalling and the Worker (M6-5b) all replay. A file holds
## "config" ({"ice_servers", "codes"}: the service's ICE servers and the codes it hands out, in
## order) and "steps". A step is {"open": s} (socket s connects), {"gone": s} (s closes), or
## {"from": s, "send": {...}} or {"from": s, "raw": "text"} (s sends that message; "pad_to": n
## pads the text with spaces to n bytes, "repeat": n sends it n times). "expect" lists, in order,
## what the service sends after that step: {"to": s, "msg": {...}}, with "close": true when it then
## closes s. A file with "turn_only" (its text says why) needs TURN credentials minted, from the
## fake API answers in config "turn" ({"key_id", "minted"}): only the Worker replays it.

const FOLDER := "res://tests/fixtures/signal/"
## Every transcript, so a deleted one fails the suites: the flows, the caps and the forged types
## (the M6 ADR §5).
const NAMES: Array[String] = [
	"caps_candidates.json",
	"caps_forwarded_too_large.json",
	"caps_full.json",
	"caps_too_large.json",
	"flow_closed.json",
	"flow_host_left.json",
	"flow_join.json",
	"flow_no_room.json",
	"flow_wrong_version.json",
	"forged_candidate_to.json",
	"forged_close.json",
	"forged_from.json",
	"forged_offer.json",
	"forged_reopen.json",
	"forged_roles.json",
	"turn_per_joiner.json",
]


## Every transcript by file name, sorted.
static func all() -> Dictionary[String, Dictionary]:
	var found: Dictionary[String, Dictionary] = {}
	var names := Array(DirAccess.get_files_at(FOLDER))
	names.sort()
	for name: String in names:
		if not name.ends_with(".json"):
			continue
		var json := JSON.new()
		var error := json.parse(FileAccess.get_file_as_string(FOLDER + name))
		assert(error == OK and json.data is Dictionary, "transcript %s does not parse" % name)
		found[name] = json.data
	return found


## Whether only the Worker can replay the transcript: it needs TURN credentials minted (M6-10).
static func turn_only(transcript: Dictionary) -> bool:
	return transcript.has("turn_only")


## The steps with "repeat" unrolled, each one's text ready to send.
static func steps_of(transcript: Dictionary) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for raw_step: Dictionary in transcript["steps"]:
		var step := raw_step.duplicate(true)
		if step.has("send"):
			step["raw"] = JSON.stringify(step["send"], "", false)
		if step.has("pad_to"):
			var text: String = step["raw"]
			var pad_to: float = step["pad_to"]
			step["raw"] = text + " ".repeat(int(pad_to) - text.length())
		var repeat: float = step.get("repeat", 1.0)
		for i: int in int(repeat):
			steps.append(step)
	return steps


## The codes the transcript's service hands out, in order, as SignalRouter's code source.
static func code_source(transcript: Dictionary) -> Callable:
	var config: Dictionary = transcript["config"]
	var listed: Array = config["codes"]
	var codes := listed.duplicate()
	return func() -> String: return "" if codes.is_empty() else str(codes.pop_front())


static func ice_servers(transcript: Dictionary) -> Array:
	var config: Dictionary = transcript["config"]
	return config["ice_servers"]


## A message as canonical text (sorted keys, numbers as JSON reads them), to compare a message
## built in GDScript (ints) with one read from a file (floats).
static func canonical(message: Variant) -> String:
	var json := JSON.new()
	json.parse(JSON.stringify(message))
	return JSON.stringify(json.data, "", true)


## One expected or sent delivery as a line: "<socket> <message>[ close]".
static func line(socket: String, message: Variant, close: bool) -> String:
	return "%s %s%s" % [socket, canonical(message), " close" if close else ""]


## The expected lines of a step.
static func expected_lines(step: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for each: Dictionary in step.get("expect", []):
		var close: bool = each.get("close", false)
		lines.append(line(str(each["to"]), each["msg"], close))
	return lines
