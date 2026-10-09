class_name ConnectingScreen
extends Control
## The black screen of a join, its failures and the map loading (prime-game-ui's s3 handoff at
## ui-0.4.0, #494; ARCHITECTURE §4.7.32), node for node as drawn: under Night (opaque, it takes the
## mouse) one of three parts shows.
## - JOIN (Connecting): the spinner, the title and the step (JoinProgress), a code join's code and
##   the time since Join, and Cancel, focused; Game makes Esc do the same.
## - FAILURE (Failure): what failed in plain words from the EndReasons id (its state:
##   EndReasons.failure_state), the host's and this game's version when known, then Try again or
##   Join directly with a flat Back beside it, or Back alone and raised; Esc is Back.
## - LOAD (Loading and Tip): this machine's load, a row per player (the host first, then in join
##   order), one random tip; or, given a how-to card (show_card, #490 and #254), Head and Card.
## Every text is a deck key; a key with placeholders and every text from data are set here with
## `auto_translate_mode` DISABLED and rebuilt on NOTIFICATION_TRANSLATION_CHANGED.

signal cancel_requested
signal back_requested
signal retry_requested
signal direct_requested

enum Part { JOIN, FAILURE, LOAD }
## What a failure's Primary button does; NONE leaves Back alone.
enum Action { NONE, RETRY, DIRECT }

const STEP_KEYS: Dictionary[JoinProgress.Step, String] = {
	JoinProgress.Step.FINDING: "connect.step.finding",
	JoinProgress.Step.CONNECTING: "connect.step.connecting",
	JoinProgress.Step.JOINED: "connect.step.joined",
}
## Each failure state's title key, body key and Action (the handoff's states).
const FAILURES: Dictionary[StringName, Array] = {
	&"fail-no-room": ["connect.fail.title", "connect.fail.no_room", Action.NONE],
	&"fail-started": ["connect.fail.title", "connect.fail.started", Action.RETRY],
	&"fail-version": ["connect.fail.title", "connect.fail.version", Action.NONE],
	&"fail-full": ["connect.fail.title", "connect.fail.full", Action.RETRY],
	&"fail-service": ["connect.fail.title", "connect.fail.service", Action.DIRECT],
	&"fail-unreachable": ["connect.fail.title", "connect.fail.unreachable", Action.DIRECT],
	&"fail-no-answer": ["connect.fail.title", "connect.fail.body", Action.RETRY],
	&"lost": ["connect.lost.title", "connect.lost.body", Action.NONE],
	&"map-failed": ["connect.map_fail.title", "connect.map_fail.body", Action.NONE],
	&"error": ["connect.error.title", "connect.error.body", Action.NONE],
	&"host-failed": ["connect.host_fail.title", "connect.error.body", Action.RETRY],
}
const ACTION_KEYS: Dictionary[Action, String] = {
	Action.RETRY: "connect.fail.retry",
	Action.DIRECT: "connect.fail.direct",
}
## The deck's tips (`tip.*`), one drawn per loading; a test holds it to the deck.
const TIPS: Array[String] = ["tip.two_hands"]
## The spinner's turns per second; half under reduced motion (UiPrefs).
const TURNS_PER_SECOND := 1.0
## The widths and the places of the handoff (px at the 1920x1080 base, #287).
const JOIN_WIDTH := 768.0
const FAILURE_WIDTH := 848.0
const BAR_SIZE := Vector2(768, 16)
const LOADING_TOP := 368.0
const TIP_WIDTH := 1072.0
const TIP_TEXT_WIDTH := 1036.0
const TIP_BOTTOM := -88.0
const HEAD_TOP := 64.0
const CARD_WIDTH := 1616.0
const CARD_TOP := 40.0

## The part shown now.
var part := Part.JOIN
## The failure state shown last (EndReasons.failure_state); &"" before any.
var failure_state: StringName = &""

var night := Panel.new()
var connecting := VBoxContainer.new()
var spinner := Panel.new()
## The spinner's holder in the column: a plain Control, so that no sort resets the turn.
var spinner_box := Control.new()
var title_label := Label.new()
var step_label := Label.new()
var code_row := HBoxContainer.new()
var code_key := PanelContainer.new()
var code_label := Label.new()
var elapsed_label := Label.new()
var cancel: ToyRaised

var failure := VBoxContainer.new()
var failure_title := Label.new()
var failure_body := Label.new()
## The two version lines (fail-version, when the game can name both).
var versions := VBoxContainer.new()
var version_host := Label.new()
var version_own := Label.new()
var primary: ToyRaised
var back_ghost := Button.new()
var back_solo: ToyRaised

var loading := VBoxContainer.new()
var bar := ProgressBar.new()
## One row per player (HBoxContainer: Name, State), keyed by peer.
var players := VBoxContainer.new()
var tip := PanelContainer.new()
var tip_label := Label.new()
var head := VBoxContainer.new()
var head_bar := ProgressBar.new()
## The how-to card on load-card (show_card); null shows the players and the tip.
var card: ToyRaised

var _step := JoinProgress.Step.FINDING
## The host's lobby name as Connecting's title shows it ("": connect.connecting_unnamed).
var _lobby := ""
var _versions := PackedStringArray()
## What the player rows show now: [peer, own, loaded, name] each, to rebuild only on a change.
var _rows_shown: Array = []
var _tips := RandomNumberGenerator.new()


func _init() -> void:
	name = "ConnectingScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	night.name = "Night"
	night.theme_type_variation = &"ToyBackdropNight"
	night.set_anchors_preset(Control.PRESET_FULL_RECT)
	night.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(night)
	_build_connecting()
	_build_failure()
	_build_loading()
	_tips.randomize()
	show_join("", JoinProgress.Step.FINDING)


func _process(delta: float) -> void:
	if spinner.is_visible_in_tree():
		var turns := TURNS_PER_SECOND * (0.5 if UiPrefs.reduced_motion else 1.0)
		spinner.rotation = fmod(spinner.rotation + TAU * turns * delta, TAU)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		retext()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_focus.call_deferred()


## A join under way: `code` is a code join's (shown as a keycap; "" for a Direct join or a host,
## which show no code), from `step`; the title waits for the lobby's name (set_lobby).
func show_join(code: String, step: JoinProgress.Step) -> void:
	code_label.text = code
	code_row.visible = not code.is_empty()
	_lobby = ""
	_retext_title()
	set_elapsed(0)
	set_step(step)
	_show_part(Part.JOIN)


func set_step(step: JoinProgress.Step) -> void:
	_step = step
	step_label.text = STEP_KEYS[step]


## The host's lobby name for the title (#214 sends it; until then nobody calls this): `typed`, the
## name the host typed, or while it is the default the deck's default name with `host_name`;
## both empty: connect.connecting_unnamed.
func set_lobby(typed: String, host_name := "") -> void:
	_lobby = typed
	if typed.is_empty() and not host_name.is_empty():
		_lobby = _word("lobby.default_name").format({"name": host_name})
	_retext_title()


## The time since Join, as m:ss.
func set_elapsed(seconds: int) -> void:
	elapsed_label.text = elapsed_text(seconds)


static func elapsed_text(seconds: int) -> String:
	var whole := maxi(seconds, 0)
	return "%d:%02d" % [floori(whole / 60.0), whole % 60]


## The failure state `shown` (EndReasons.failure_state), with the host's and this game's version
## (JoinProgress.found_versions) when known; false, showing nothing new, for a state it lacks.
func show_failure(shown: StringName, version_lines := PackedStringArray()) -> bool:
	if not FAILURES.has(shown):
		return false
	failure_state = shown
	var look: Array = FAILURES[shown]
	failure_title.text = str(look[0])
	failure_body.text = str(look[1])
	_versions = version_lines if shown == &"fail-version" else PackedStringArray()
	versions.visible = _versions.size() == 2
	_retext_versions()
	var act := action()
	primary.visible = act != Action.NONE
	back_ghost.visible = act != Action.NONE
	back_solo.visible = act == Action.NONE
	if act != Action.NONE:
		(primary.face as Button).text = ACTION_KEYS[act]
	_show_part(Part.FAILURE)
	return true


## The Primary button's action of the failure shown.
func action() -> Action:
	if not FAILURES.has(failure_state):
		return Action.NONE
	var look: Array = FAILURES[failure_state]
	return look[2]


## The map loading starts: the players and a tip (`tip_key`, or one drawn from TIPS), no card.
func show_loading(tip_key := "") -> void:
	var drawn := TIPS[_tips.randi_range(0, TIPS.size() - 1)]
	tip_label.text = tip_key if not tip_key.is_empty() else drawn
	show_card(null)
	set_load_fraction(0.0)
	_show_part(Part.LOAD)


## This machine's load, 0 to 1 (ClientSession.load_progress).
func set_load_fraction(fraction: float) -> void:
	bar.value = clampf(fraction, 0.0, 1.0) * bar.max_value
	head_bar.value = bar.value


## The rows of `model`'s roster: the host first, then in join order (the roster's), the own row
## player.you; each loading (muted) until the host confirmed its load.
func refresh_loading(model: ClientModel) -> void:
	var shown: Array = []
	for peer: int in loading_order(model):
		var member: ClientModel.Member = model.roster[peer]
		shown.append([peer, peer == model.own_peer, model.loaded.has(peer), member.name])
	if shown == _rows_shown:
		return
	_rows_shown = shown
	for row: Node in players.get_children():
		players.remove_child(row)
		row.free()
	for each: Array in shown:
		var row := _player_row(each[0] as int, each[1] as bool, each[2] as bool, each[3] as String)
		players.add_child(row, true)


## The roster's peers, the host (NetTransport.HOST_ID) first, then the rest in the roster's order.
static func loading_order(model: ClientModel) -> Array[int]:
	var order: Array[int] = []
	if model.roster.has(NetTransport.HOST_ID):
		order.append(NetTransport.HOST_ID)
	for peer: int in model.roster:
		if peer != NetTransport.HOST_ID:
			order.append(peer)
	return order


## load-card (the hook of #490 and #254): `made` is the shared how-to card (a ToyRaised of
## ToyPanelHowto) of a task type the player has not completed, placed as drawn instead of the
## players and the tip; null takes the card away again.
func show_card(made: ToyRaised) -> void:
	if card != null and card != made:
		remove_child(card)
		card.queue_free()
	card = made
	if made != null:
		made.set_anchors_preset(Control.PRESET_CENTER)
		_place(made, CARD_TOP, Control.GROW_DIRECTION_BOTH)
		made.custom_minimum_size = Vector2(CARD_WIDTH, 0)
		if made.get_parent() == null:
			add_child(made)
	_show_part(part)


## The state as the handoff names it: finding, connecting-direct, joined, a failure's, load or
## load-card.
func state() -> StringName:
	match part:
		Part.FAILURE:
			return failure_state
		Part.LOAD:
			return &"load-card" if card != null else &"load"
	if _step == JoinProgress.Step.JOINED:
		return &"joined"
	return &"finding" if code_row.visible else &"connecting-direct"


## Every text set from code again, in the language now.
func retext() -> void:
	_retext_title()
	_retext_versions()


func _show_part(which: Part) -> void:
	part = which
	connecting.visible = which == Part.JOIN
	failure.visible = which == Part.FAILURE
	loading.visible = which == Part.LOAD and card == null
	tip.visible = loading.visible
	head.visible = which == Part.LOAD and card != null
	if card != null:
		card.visible = head.visible
	_focus.call_deferred()


## The button drawn focused: Cancel, the Primary, or the lone Back; only while shown.
func _focus() -> void:
	if not is_visible_in_tree():
		return
	var target: Control = null
	match part:
		Part.JOIN:
			target = cancel.face
		Part.FAILURE:
			target = primary.face if action() != Action.NONE else back_solo.face
	if target != null:
		target.grab_focus()


func _retext_title() -> void:
	if _lobby.is_empty():
		title_label.text = _word("connect.connecting_unnamed")
	else:
		title_label.text = _word("connect.connecting").format({"lobby": _lobby})


func _retext_versions() -> void:
	if _versions.size() != 2:
		return
	version_host.text = _word("connect.fail.version_host").format({"version": _versions[0]})
	version_own.text = _word("connect.fail.version_own").format({"version": _versions[1]})


func _fit_spinner_box() -> void:
	spinner_box.custom_minimum_size = spinner.custom_minimum_size


func _build_connecting() -> void:
	connecting.name = "Connecting"
	connecting.theme_type_variation = &"ToyColumnTwentyFour"
	connecting.alignment = BoxContainer.ALIGNMENT_CENTER
	connecting.custom_minimum_size = Vector2(JOIN_WIDTH, 0)
	connecting.set_anchors_preset(Control.PRESET_CENTER)
	_place(connecting, 0.0, Control.GROW_DIRECTION_BOTH)
	add_child(connecting)
	spinner.name = "Spinner"
	spinner.theme_type_variation = &"ToySpinner"
	spinner.pivot_offset_ratio = Vector2(0.5, 0.5)
	spinner.set_anchors_preset(Control.PRESET_FULL_RECT)
	# A container resets the rotation of its children at every sort (Container.fit_child_in_rect),
	# which would snap the turning spinner back: a plain Control keeps it out of the layout, and
	# takes its size.
	spinner_box.name = "SpinnerBox"
	spinner_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	spinner_box.add_child(UiParts.sized(spinner))
	spinner.minimum_size_changed.connect(_fit_spinner_box)
	_fit_spinner_box()
	connecting.add_child(spinner_box)
	var texts := _column("Texts", &"ToyColumnEight")
	connecting.add_child(texts)
	_label(title_label, "Title", &"ToyTitleOnDark", JOIN_WIDTH, true)
	title_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	texts.add_child(title_label)
	_label(step_label, "Step", &"ToyTextOnDark")
	texts.add_child(step_label)
	code_row.name = "CodeRow"
	code_row.theme_type_variation = &"ToyRowEight"
	code_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	connecting.add_child(code_row)
	var code_word := UiParts.styled_label("common.code", &"ToyTextMutedOnDark")
	code_word.name = "Label"
	code_word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	code_row.add_child(code_word)
	code_key.name = "Code"
	code_key.theme_type_variation = &"ToyKeyOnDark"
	code_key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	code_row.add_child(UiParts.sized(code_key))
	_label(code_label, "Text", &"ToyKeyText")
	code_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	code_key.add_child(code_label)
	_label(elapsed_label, "Elapsed", &"ToyTextMutedOnDark")
	elapsed_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	connecting.add_child(elapsed_label)
	cancel = _raised_button("Cancel", "common.cancel", &"ToyButtonSecondary", cancel_requested)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	connecting.add_child(cancel)


func _build_failure() -> void:
	failure.name = "Failure"
	failure.theme_type_variation = &"ToyColumnThirtyTwo"
	failure.alignment = BoxContainer.ALIGNMENT_CENTER
	failure.custom_minimum_size = Vector2(FAILURE_WIDTH, 0)
	failure.set_anchors_preset(Control.PRESET_CENTER)
	_place(failure, 0.0, Control.GROW_DIRECTION_BOTH)
	add_child(failure)
	var texts := _column("Texts", &"ToyColumnSixteen")
	failure.add_child(texts)
	_label(failure_title, "Title", &"ToyTitleOnDark", FAILURE_WIDTH, true)
	texts.add_child(failure_title)
	_label(failure_body, "Body", &"ToyTextMutedOnDark", FAILURE_WIDTH, true)
	texts.add_child(failure_body)
	versions.name = "Versions"
	versions.theme_type_variation = &"ToyColumnFour"
	texts.add_child(versions)
	for line: Label in [version_host, version_own]:
		_label(line, "Host" if line == version_host else "Own", &"ToyTextOnDark")
		line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		versions.add_child(line)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.theme_type_variation = &"ToyRowSixteen"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	failure.add_child(buttons)
	primary = _raised_button("Primary", "connect.fail.retry", &"ToyButtonPrimary", Signal())
	(primary.face as Button).pressed.connect(_on_primary)
	buttons.add_child(primary)
	back_ghost.name = "BackGhost"
	back_ghost.text = "common.back"
	back_ghost.theme_type_variation = &"ToyButtonGhostOnDark"
	back_ghost.pressed.connect(func() -> void: back_requested.emit())
	ToyPress.attach(back_ghost)
	buttons.add_child(back_ghost)
	back_solo = _raised_button("BackSolo", "common.back", &"ToyButtonSecondary", back_requested)
	buttons.add_child(back_solo)


func _build_loading() -> void:
	loading.name = "Loading"
	loading.theme_type_variation = &"ToyColumnSixteen"
	loading.custom_minimum_size = Vector2(JOIN_WIDTH, 0)
	loading.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_place(loading, LOADING_TOP, Control.GROW_DIRECTION_END)
	add_child(loading)
	loading.add_child(_load_title())
	_bar(bar)
	loading.add_child(bar)
	players.name = "Players"
	players.theme_type_variation = &"ToyColumnEight"
	loading.add_child(players)
	tip.name = "Tip"
	tip.theme_type_variation = &"ToyPlate"
	tip.custom_minimum_size = Vector2(TIP_WIDTH, 0)
	tip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_place(tip, TIP_BOTTOM, Control.GROW_DIRECTION_BOTH)
	add_child(tip)
	_label(tip_label, "Text", &"ToyPlateText", TIP_TEXT_WIDTH, true)
	tip.add_child(tip_label)
	head.name = "Head"
	head.theme_type_variation = &"ToyColumnTwelve"
	head.custom_minimum_size = Vector2(JOIN_WIDTH, 0)
	head.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_place(head, HEAD_TOP, Control.GROW_DIRECTION_END)
	add_child(head)
	head.add_child(_load_title())
	_bar(head_bar)
	head.add_child(head_bar)


## A player's row: the host's HostRow, the own Row (player.you), the others OtherRow (Godot
## numbers the repeats); the state muted while it loads.
func _player_row(peer: int, own: bool, loaded: bool, player_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.theme_type_variation = &"ToyRowTwelve"
	row.name = "HostRow" if peer == NetTransport.HOST_ID else ("Row" if own else "OtherRow")
	var name_label := UiParts.styled_label("player.you" if own else player_name, &"ToyTextOnDark")
	name_label.name = "Name"
	if not own:
		name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)
	var state_label := UiParts.styled_label(
		"loading.player_ready" if loaded else "loading.player_loading",
		&"ToyTextOnDark" if loaded else &"ToyTextMutedOnDark"
	)
	state_label.name = "State"
	row.add_child(state_label)
	return row


func _load_title() -> Label:
	var title := UiParts.styled_label("loading.title", &"ToyTitleOnDark")
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return title


func _bar(made: ProgressBar) -> void:
	made.name = "Bar"
	made.theme_type_variation = &"ToyBarProgress"
	made.custom_minimum_size = BAR_SIZE
	made.max_value = 100
	made.show_percentage = false


## A raised Toy button named `face_name` (its wrapper `<face_name>Raised`), with no minimum size
## of its own (the handoff gives none), emitting `said` when pressed.
func _raised_button(
	face_name: String, key: String, variation: StringName, said: Signal
) -> ToyRaised:
	var made := UiParts.button(key, Callable(), variation, ToyHints.DARK)
	made.face.name = face_name
	made.name = "%sRaised" % face_name
	made.custom_minimum_size = Vector2.ZERO
	if not said.is_null():
		(made.face as Button).pressed.connect(func() -> void: said.emit())
	return made


func _on_primary() -> void:
	if action() == Action.RETRY:
		retry_requested.emit()
	elif action() == Action.DIRECT:
		direct_requested.emit()


static func _column(column_name: String, variation: StringName) -> VBoxContainer:
	var made := VBoxContainer.new()
	made.name = column_name
	made.theme_type_variation = variation
	return made


## `label` named and styled; centred, at least `width` wide and word-wrapped when `wraps`.
static func _label(
	label: Label, label_name: String, variation: StringName, width := 0.0, wraps := false
) -> void:
	label.name = label_name
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if width > 0.0:
		label.custom_minimum_size = Vector2(width, 0)
	if wraps:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Offsets 0 left and right and `top` at top and bottom, growing both ways across.
static func _place(control: Control, top: float, grow_down: Control.GrowDirection) -> void:
	control.offset_left = 0.0
	control.offset_right = 0.0
	control.offset_top = top
	control.offset_bottom = top
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = grow_down


static func _word(key: String) -> String:
	return String(TranslationServer.translate(key))
