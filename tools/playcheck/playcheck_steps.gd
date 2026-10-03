extends RefCounted
## The steps of one window of `tools\run.cmd playcheck` (#186; docs/AGENT_WORKFLOW.md §11): the
## plan's list for this window (tools/runner/playcheck.py parses the scenario file and writes it),
## advanced once per frame by tools/playcheck/playcheck_window.gd.
##
## A wait reads only the window's View: its own ClientSession and ClientModel (the host's own
## client included), its Esc menu, its pointer and what its Ui and camera draw (#275: the fields of
## `wait text` and `wait shown`); never HostSession, the match or core/ (invariant 2), so a window
## that draws before its filtered event arrives is not hidden by the host's state. A wait that does
## not hold within its `timeout_s` fails the run, naming the step's line and what the window saw.
## Every step but a wait or `frames` is an action the window performs in the frame advance()
## returns it (press, hold, release, button, shot, the host's setup).

enum Status { RUNNING, DONE, FAILED }

## The event fields that name a player: the plan holds the player's number (ScenarioPlay's
## PLAYER_FIELDS), mapped to its peer id through View.peer_of().
const PLAYER_FIELDS: Array[String] = ["peer", "raiser", "target"]
## The waits that read the window itself, not its model: they hold before a Welcome and after the
## session ended too (`wait screen menu` after a Leave or a host close).
const WINDOW_WAITS: Array[String] = ["screen", "esc", "pointer", "text", "shown"]

static var _whitespace := RegEx.create_from_string("\\s+")


## What a window's waits read. playcheck_window.gd reads its Game; a test fakes it.
class View:
	extends RefCounted

	func welcomed() -> bool:
		return false

	func phase() -> String:
		return ""

	## GameFlow.Screen's name in lower case.
	func screen() -> String:
		return ""

	func own_peer() -> int:
		return 0

	## The peer id of player `player` (1-based: the windows, then the bots); 0 while unknown.
	func peer_of(_player: int) -> int:
		return 0

	func roster_size() -> int:
		return 0

	## ClientModel.Life's name in lower case.
	func life_of(_peer: int) -> String:
		return ""

	func ready_of(_peer: int) -> bool:
		return false

	func esc_open() -> bool:
		return false

	## The pointer as the game asked for it (the window never captures the real mouse).
	func pointer_captured() -> bool:
		return false

	## Every event the window's session received, in order: [name: StringName, fields: Dictionary].
	func events() -> Array[Array]:
		return []

	## What the window has instead of a Welcome, for a timeout's message.
	func unwelcomed() -> String:
		return "no Welcome yet"

	## The text a field (playcheck.py's FIELDS) holds, shown or not.
	func field_text(_field: String) -> String:
		return ""

	## Whether the field's Control is visible in the tree (hand.item: an item in the hand).
	func field_shown(_field: String) -> bool:
		return false


var steps: Array[Dictionary] = []
var view: View
## The current step; steps.size() once done.
var index := 0
var status := Status.RUNNING
## Why it failed: the step and what the window saw.
var failure := ""
## Called with (index, step) as each step starts, for the window's PLAYCHECK step line.
var on_step := Callable()

var _started_ms := -1
## The action step advance() returned last, until the next advance(): the window is performing
## it, so a failure now is that step's.
var _acting := -1
var _frames := 0
## Events before this index were matched by an earlier wait (or skipped before that match).
var _event_cursor := 0


func _init(plan_steps: Array[Dictionary], window_view: View) -> void:
	steps = plan_steps
	view = window_view


## Advances by one frame at `now_ms`: passes every wait that holds, counts a `frames` step, and
## returns the action step the window performs in this frame ({} when there is none).
func advance(now_ms: int) -> Dictionary:
	_acting = -1
	while status == Status.RUNNING:
		if index >= steps.size():
			status = Status.DONE
			break
		var step := steps[index]
		if _started_ms < 0:
			_started_ms = now_ms
			_frames = 0
			if on_step.is_valid():
				on_step.call(index, step)
		var kind := str(step.get("do", ""))
		if kind == "wait" or kind == "setup":
			if not _holds(step):
				_check_timeout(step, now_ms)
				break
			_next()
			if kind == "setup":
				_acting = index - 1
				return step
		elif kind == "frames":
			if _frames < number(step.get("count", 0)):
				_frames += 1
				break
			_next()
		else:
			_next()
			_acting = index - 1
			return step
	return {}


## Fails the step the window is performing (the action advance() returned last), else the
## current one, with `why`.
func fail(why: String) -> void:
	if status != Status.RUNNING:
		return
	status = Status.FAILED
	failure = "%s: %s" % [describe(_acting if _acting >= 0 else index), why]


## "step <n> (line <l>: <text>)" of step `at`, or "after the last step".
func describe(at: int) -> String:
	if at >= steps.size():
		return "after the last step"
	var step := steps[at]
	return (
		"step %d (line %d: %s)" % [at + 1, number(step.get("line", 0)), str(step.get("text", ""))]
	)


func _next() -> void:
	index += 1
	_started_ms = -1


func _check_timeout(step: Dictionary, now_ms: int) -> void:
	var timeout_s: float = step.get("timeout_s", 0.0)
	if now_ms - _started_ms < roundi(timeout_s * 1000.0):
		return
	fail("timed out after %s s; the window saw %s" % [timeout_s, _saw(step)])


func _holds(step: Dictionary) -> bool:
	if str(step.get("do", "")) == "setup":
		return _setup_ready(step)
	if not view.welcomed() and str(step.get("what", "")) not in WINDOW_WAITS:
		return false
	var value: Variant = step.get("value")
	var holds := false
	match str(step.get("what", "")):
		"phase":
			holds = view.phase() == str(value)
		"screen":
			holds = view.screen() == str(value)
		"life":
			var peer := _peer(number(step.get("player", 0)))
			holds = peer != 0 and view.life_of(peer) == str(value)
		"ready":
			var peer := _peer(number(step.get("player", 0)))
			holds = peer != 0 and view.ready_of(peer) == flag(value)
		"players":
			holds = view.roster_size() >= number(value)
		"event":
			holds = _event_arrived(step)
		"esc":
			holds = view.esc_open() == flag(value)
		"pointer":
			holds = view.pointer_captured() == flag(value)
		"text":
			var seen := drawn(str(step.get("field", "")))
			holds = text_holds(str(step.get("op", "")), seen, str(value))
		"shown":
			holds = view.field_shown(str(step.get("field", ""))) == flag(value)
		_:
			fail("unknown wait '%s'" % step.get("what", ""))
	return holds


## What the window draws in `field`: its text with each run of whitespace one space, "" while
## hidden.
func drawn(field: String) -> String:
	return collapse(view.field_text(field)) if view.field_shown(field) else ""


## `text` with each run of whitespace (two spaces, a line break) one space, none at either end.
static func collapse(text: String) -> String:
	return _whitespace.sub(text, " ", true).strip_edges()


## Whether `seen` is (`is`), contains (`has`) or does not contain (`lacks`) `want`, collapsed.
static func text_holds(op: String, seen: String, want: String) -> bool:
	var wanted := collapse(want)
	match op:
		"is":
			return seen == wanted
		"has":
			return seen.contains(wanted)
		"lacks":
			return not seen.contains(wanted)
	return false


## The visible, enabled Buttons under `ui` (what a `button` step picks from), in tree order.
static func visible_buttons(ui: Node) -> Array[Button]:
	var found: Array[Button] = []
	for node: Node in ui.find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and not button.disabled:
			found.append(button)
	return found


## Those of `buttons` whose text is `text` (whitespace collapsed).
static func buttons_named(buttons: Array[Button], text: String) -> Array[Button]:
	var named: Array[Button] = []
	for button: Button in buttons:
		if collapse(button.text) == collapse(text):
			named.append(button)
	return named


## Why a `button <text>` step cannot press among `buttons`: none or several; "" for exactly one.
static func button_problem(buttons: Array[Button], text: String) -> String:
	var named := buttons_named(buttons, text)
	if named.size() == 1:
		return ""
	if named.size() > 1:
		return "%d buttons '%s'" % [named.size(), text]
	var texts := PackedStringArray()
	for button: Button in buttons:
		texts.append("'%s'" % collapse(button.text))
	return "no visible button '%s'; the window shows [%s]" % [text, ", ".join(texts)]


## A plan's whole number (JSON numbers arrive as floats; a dictionary key as text).
static func number(value: Variant) -> int:
	if value is int or value is float:
		var real: float = value
		return roundi(real)
	return str(value).to_int() if str(value).is_valid_int() else 0


## A plan's true or false.
static func flag(value: Variant) -> bool:
	return value is bool and str(value) == "true"


## The host's setup can go once every player is in its roster and each forced role's player has a
## known peer id.
func _setup_ready(step: Dictionary) -> bool:
	if not view.welcomed() or view.roster_size() < number(step.get("players", 0)):
		return false
	var roles: Dictionary = step.get("roles", {})
	for player: Variant in roles:
		if view.peer_of(number(player)) == 0:
			return false
	return true


## The player's peer id: 0 is the window's own player.
func _peer(player: int) -> int:
	return view.own_peer() if player == 0 else view.peer_of(player)


func _event_arrived(step: Dictionary) -> bool:
	var events := view.events()
	var want: Dictionary = step.get("fields", {})
	for i in range(_event_cursor, events.size()):
		var pair := events[i]
		if str(pair[0]) != str(step.get("event", "")):
			continue
		if _fields_match(pair[1] as Dictionary, want):
			_event_cursor = i + 1
			return true
	return false


func _fields_match(got: Dictionary, want: Dictionary) -> bool:
	for key: Variant in want:
		var name := str(key)
		var wanted: Variant = want[key]
		if PLAYER_FIELDS.has(name):
			var peer := view.peer_of(number(wanted))
			if peer == 0:
				return false
			wanted = peer
		if not got.has(name) or not _same(got[name], wanted):
			return false
	return true


## Numbers compare as numbers (a plan's JSON numbers are floats), everything else as text.
static func _same(got: Variant, want: Variant) -> bool:
	if (got is int or got is float) and (want is int or want is float):
		var got_number: float = got
		var want_number: float = want
		return is_equal_approx(got_number, want_number)
	return str(got) == str(want)


## What the window saw for the wait's subject, for a timeout's message.
func _saw(step: Dictionary) -> String:
	if str(step.get("do", "")) == "setup":
		return (
			"%d of %d players in its roster" % [view.roster_size(), number(step.get("players", 0))]
		)
	if not view.welcomed() and str(step.get("what", "")) not in WINDOW_WAITS:
		return view.unwelcomed()
	var peer := _peer(number(step.get("player", 0)))
	var seen := "nothing it can wait for"
	match str(step.get("what", "")):
		"phase":
			seen = "phase '%s'" % view.phase()
		"screen":
			seen = "screen '%s'" % view.screen()
		"life":
			seen = "life '%s'" % view.life_of(peer) if peer != 0 else "no peer id for that player"
		"ready":
			seen = "ready %s" % view.ready_of(peer) if peer != 0 else "no peer id for that player"
		"players":
			seen = "%d players" % view.roster_size()
		"event":
			var names := PackedStringArray()
			for pair: Array in view.events().slice(_event_cursor):
				names.append(str(pair[0]))
			seen = "since the last match: [%s]" % ", ".join(names.slice(-8))
		"esc":
			seen = "the Esc menu %s" % ("open" if view.esc_open() else "closed")
		"pointer":
			seen = "the pointer %s" % ("captured" if view.pointer_captured() else "free")
		"text":
			var field := str(step.get("field", ""))
			seen = "%s '%s'" % [field, drawn(field)]
		"shown":
			var field := str(step.get("field", ""))
			seen = "%s %s" % [field, "shown" if view.field_shown(field) else "hidden"]
	return seen
