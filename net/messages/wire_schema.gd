class_name WireSchema
extends RefCounted
## The one declarative table of ARCHITECTURE §4.3 (E4) and the codec of §4.4 that walks it: every
## intent, debug command, event, the snapshot and the voice frames, each a row of kind, name,
## direction, lane, cap and fields with their wire types. NetKindTable.game() is built from it.
##
## encode() refuses, with an error in the log, whatever decode() would reject and any payload over
## its cap: it never truncates. decode() trusts nothing and returns null at the first problem;
## nothing of a rejected message may reach core/. Field names are core/'s, as strings: an intent
## decodes to its MatchCommand's args (and seq), an event to its name and a Dictionary equal to
## its to_dict(), with the same Variant types.

## The protocol version: the same number as core/'s JoinRules.PROTOCOL_VERSION (a test pins them).
## Every change to a row (a kind, lane, direction, cap, field, its type or its order) bumps it:
## 9 since #429 added MoveClaimReliable (kind 14); 10 since #550 added Hello's `name` and made
## PlayerJoined's and the Welcome roster's names the `name` type (UTF-8); 11 since #214 added
## the lobby's name to ChangeSettings, Welcome and SettingsChanged and widened `name` to 80 bytes;
## 12 since #599 added NextStage (kind 15);
## 13 since #548 turned SettingsChanged's shortfalls into host text (ids plus arguments) and gave
## MatchEnded its reason;
## 14 since #551 added SetProfile (kind 16), ProfileChanged (kind 66) and the body colour of
## PlayerJoined and the Welcome roster;
## 15 since release/m7 reached main (#837): #647 added ZoneProgress (kind 67) and #643 added Throw
## (kind 17) and ItemThrown (kind 68). On release/m7 they were its own 11 and 12 (kinds 66, 15, 67),
## renumbered above main's highest as one bump when it merged second;
## 16 since #796 added Interact (kind 18);
## 17 since #779 added ItemVanished (kind 69);
## 18 since #797 added the Generator's SwitchChanged (kind 70) and ButtonPressed (kind 71);
## 19 since #771 added ItemChanged (kind 72);
## 20 since #770 made Interact's `station` optional and added its optional `item`;
## 21 since #780 let a station refuse a use `wrong_item` (StationUsable.REASONS, the cooking ADR's
## CE11): a new Rejected reason, no row changed, so a client of 20 never meets it;
## 22 since #772 added Cooking's OrderPosted (kind 73) and HerbsDealt (kind 74);
## 23 since #807 added the car repair's LiftChanged (kind 75) and PartNeeded (kind 76), and the
## host text `short_axis`.
## 24 since #781 added the photo task's FilmLoaded (kind 77) and ShotTaken (kind 78) and the
## Rejected reasons `no_film`, `no_frames_left` and `film_exposed` and the host text
## `photo_spot_near` (the photo ADR §3.2, §3.3, PE12);
## 25 since #638 added Hello's return `key` (an id decoded as a String; the returning-players ADR,
## Decision 4);
## 26 since #773 added Cooking's GrillLoaded (kind 79) and IngredientPlaced (kind 80).
## 27 since #808 added the car repair's FitChanged (kind 81) and PartFitted (kind 82).
## 28 since #782 added the photo task's PhotoPrinted (kind 83) and PhotoHung (kind 84) and the
## Rejected reasons `nothing_to_print` and `no_photo` (the photo ADR §2.6, §2.7, PE16);
## 29 since #790 added the `crouched` flag to MoveClaim's and MoveClaimReliable's flags (8), the
## snapshot avatar's (4) and ShotTaken's record row's (2) (the crouch ADR, KE1, KE2).
## 30 since #847 lets a knocked-down viewer's snapshot carry its own avatar (MAX_AVATARS, 16) and
## the Rejected reason `moving` (the knockdown rework's KE5, KE12).
## 31 since #990 added the `sneaking` flag to MoveClaim's and MoveClaimReliable's flags (16) and the
## snapshot avatar's (8).
## 32 since #775 raised SettingsChanged's shortfalls from 32 to 64 entries (the base mode now
## demands 29 spawn tags, and a text per demanded tag is a shortfall; WireBudget sizes it as one
## subject). No row changed otherwise.
## 34 since #810 raised SettingsChanged's needed_markers and map_markers from 32 to 64 entries (the
## base mode's House with the car repair demands 36 spawn tags). No row changed otherwise. (33 was
## held by #1101's open PR #1109: whichever of the two lands second takes its base's plus one at
## its rebase. A skipped number is harmless: the versions only have to match.)
## 35 since #1101 dropped IngredientPlaced's `right` (kind 80) and added Cooking's BurgerPlated
## (kind 85) and BurgerServed (kind 86): a burger is checked when it is served. (It was 33 before
## its rebase onto #810's 34.)
## 36 since #1218 (GDD §6, drawing from the belt): the intent Draw (kind 19, its place), the
## `place` of ItemPickedUp (48) and Swapped (64), and the avatar rows' `belt_item2` (Snapshot 96,
## ShotTaken 78), appended after `belt_item`.
## 37 since #1296 (the seated watcher, GDD §12): the intent Pose (kind 20, no argument) and the
## avatar rows' fifth flag `posed` (Snapshot 96), after `sneaking`. ShotTaken's record is unchanged.
## 38 since #1390 (the bar, GDD §3): the avatar rows' `drunk` (U8, Snapshot 96), after the flags,
## and SelfStatus' `drunk` (U8, kind 54), after `claim_tick`. ShotTaken's record is unchanged.
## 39 since #1389 (GDD §6, the hand-over): the intent HandOver (kind 21, its target).
## 40 since #1393 (the limp, GDD §3): the avatar rows' sixth flag `limp` (Snapshot 96), after
## `posed`. ShotTaken's record is unchanged.
## 41 since #1383 (the poser's own state): SelfStatus's `posed` (kind 54), after `drunk`.
## 42 since #1434 (GDD §6, the hand-over offer): the intents TakeOffer (kind 22, its target, the
## giver) and CancelOffer (kind 23, no argument), the events OfferMade (87) and OfferEnded (88),
## each its giver and target.
## 43 since #1438 (an item's own action on the right mouse button): the intent UseSecondary
## (kind 24, its facing, as Use's); the debug kinds moved to 28 (ForceRole) and 29 (ForceClock),
## the intents' range now 1 to 27.
## 44 since #1404 (a joiner learns the hall's items): Welcome's `items` (kind 33), after
## `lobby_name`, a list of item, kind, where, holder, place and position; its cap 2048 -> 8192.
## 45 since #1295 (the world toggles): SwitchChanged (kind 70) may name a world toggle's station,
## whose level parts an older client would not move; no row changed.
## 46 since #1453 (GDD §8, the ship's engine): the events EngineProblemOpened (kind 89, its problem,
## stations and deadline), EngineProblemFixed (90, its problem) and EngineBlast (91, the stage after
## the drop).
## 47 since #1461 (GDD §8, the engine's problem kinds): the events GillFlipped (kind 92, its
## station, slit and open), BreakerChain (93, its problem, the order of its breakers, how many are
## on and the tick the last one's window counts from or none) and CrystalChanged (95, its socket,
## its charger or none, the charger's phase, its item or none and the charge's end tick or none).
## 48 since #1398 (the pinball): the intent Flippers (kind 25, the seated player's two flippers)
## and the event PinballState (94, the machine's game, its seated player or none, the flippers,
## the ball in play, the score, the balls left, the best score and its owner's name).
## 49 since #1392 (the drunk voice): VoiceBatch's frame record (kind 114) gains `strength` (U8,
## after `seq`), and MAX_BATCH_FRAMES falls from 113 to 101.
## 50 since #1396 (GDD §3, the photo booth): the event BoothStep (kind 96, the booth's steps: its
## station, strip, step, presser, frames, countdown, gap, frame, record and items). Kind 94 was the
## last free event kind (PinballState took it), so the event range widens in the same bump (#1475):
## FIRST_STATE and Snapshot move from 96 to 104, and 96 to 103 are events.
## 51 since #1485 (the pose wheel): the intent WheelPose (kind 26, the leg stance and the arm
## gesture, a byte each), and a `wheel_pose` byte (WheelPoseCode) after `drunk` on the Snapshot's
## avatar and after `posed` on SelfStatus.
## 52 since #1399 (the pinball table): Snapshot (kind 104) gains the optional ball block
## (`has_ball`, then `ball`, the vec3 of the ball's table-local place) before `avatars`, the last.
const VERSION := 52

## MoveClaim's RELIABLE twin (§4.3, #429): the claims a client must not lose (an epoch's first, and
## its last claim again right before a player action) go on it; the host hands it to core/ as the
## plain MoveClaim command (WireRow.command).
const RELIABLE_CLAIM := &"MoveClaimReliable"

## Frozen rows (§4.3): any client can send its version and read Rejected(wrong_version).
const HELLO := 1
const REJECTED := 32

## Kind ranges (§4.3): 0 is the transport's ADMIT.
const FIRST_INTENT := 1
const FIRST_DEBUG := 28
const FIRST_EVENT := 32
const FIRST_STATE := 104
const FIRST_VOICE := 112
const LAST_VOICE := 127

## The wire's maxima (§4.3): they bound the decoder, not the payload; WireBudget checks the content.
const MAX_PLAYERS := 16
## A snapshot holds the viewer's own avatar only while it is knocked down (the knockdown rework's
## KE5 (a)): every player's, at most. 16 take 789 bytes of the unreliable cap.
const MAX_AVATARS := MAX_PLAYERS
## The avatars of every player but one: the photo camera's shot of a living photographer.
const MAX_OTHER_AVATARS := MAX_PLAYERS - 1
## Settings, colours, palettes and station kinds per map (SettingsChanged's spawn tags take
## MAX_MARKERS).
const MAX_ENTRIES := 32
## SettingsChanged's spawn tags (needed_markers, map_markers): 64 since #810 (the base mode's House
## demands 36 with the car repair).
const MAX_MARKERS := 64
const MAX_TASK_TYPES := 16
## Cooking's herbs (HerbsDealt's lists, #772): a list's count is a u8, as an order's icon is.
const MAX_HERBS := 255
const MAX_SHORTFALLS := 64
## Welcome's item rows (#1404): core's WelcomeEvent.MAX_ITEMS (a test pins the two).
const MAX_WELCOME_ITEMS := 96
## The stations of one ship engine problem (EngineProblemOpened, #1453): core's
## ShipEngine.MAX_PROBLEM_STATIONS, which a unit test pins equal (net/ names no core/ class).
const MAX_PROBLEM_STATIONS := 8
## Host text (#548): the most subject ids and whole-number arguments of one text.
const MAX_TEXT_IDS := 2
const MAX_TEXT_NUMBERS := 4
## One 20 ms Opus frame.
const MAX_OPUS := 500
## A VoiceBatch's frames: as many 1-byte frames as fit its 1024-byte cap behind its tick and
## count (each takes speaker 4, seq 2, strength 1, length 2 and its bytes). The cap bounds it first.
const MAX_BATCH_FRAMES := 101

## Built once per build kind: the rows never change at run time.
static var _built: Dictionary[bool, WireSchema] = {}

var _by_kind: Dictionary[int, WireRow] = {}
var _by_name: Dictionary[StringName, WireRow] = {}


## An encoded payload, or why it was refused (`payload` then holds what was written, so WireBudget
## can name the size of a payload over its cap).
class Encoded:
	var kind := 0
	var payload := PackedByteArray()
	var problem := ""


## The game's table. `debug`: a debug build's, the only one with the debug commands (kinds 28 to
## 31, E17): a release build neither sends nor decodes them.
static func game(debug: bool) -> WireSchema:
	if not _built.has(debug):
		var schema := WireSchema.new()
		for each: WireRow in _intents() + _events() + _state_and_voice():
			schema._add(each)
		if debug:
			for each: WireRow in _debug_commands():
				schema._add(each)
		_built[debug] = schema
	return _built[debug]


## Every row in kind order.
func rows() -> Array[WireRow]:
	var kinds := _by_kind.keys()
	kinds.sort()
	var found: Array[WireRow] = []
	for kind: int in kinds:
		found.append(_by_kind[kind])
	return found


## The row of a kind, or null.
func row(kind: int) -> WireRow:
	return _by_kind.get(kind)


## The row of a name, or null.
func row_named(row_name: StringName) -> WireRow:
	return _by_name.get(row_name)


## The kind of a name; 0 (never a message) for an unknown one.
func kind_of(row_name: StringName) -> int:
	var found := row_named(row_name)
	return found.kind if found != null else 0


## The transport's table: each row's lane, direction and cap.
func kind_table() -> NetKindTable:
	var table := NetKindTable.new()
	for each: WireRow in rows():
		var added := table.add(each.kind, each.lane, each.direction, each.cap)
		if added != OK:
			# Logged too: a release build strips the assert and would drop the row silently.
			push_error("wire: row %d does not fit NetKindTable" % each.kind)
		assert(added == OK, "wire: row %d does not fit NetKindTable" % each.kind)
	return table


## The payload of `message`, or an empty array after logging why it was refused: an unknown name,
## a missing or undeclared field, a value its wire type rejects, or a payload over the cap. No row
## has an empty payload, so empty always means refused.
func encode(message: WireMessage) -> PackedByteArray:
	var encoded := write(message)
	if not encoded.problem.is_empty():
		push_error("wire: refused to encode %s: %s" % [message.name, encoded.problem])
		return PackedByteArray()
	return encoded.payload


## encode() without the log: the payload and the problem, for callers that report it themselves.
func write(message: WireMessage) -> Encoded:
	var encoded := Encoded.new()
	var found := row_named(message.name)
	if found == null:
		encoded.problem = "no row named %s" % message.name
		return encoded
	encoded.kind = found.kind
	var writer := WireWriter.new()
	encoded.problem = WireField.write_all(found.fields, message.fields, writer, message)
	encoded.payload = writer.bytes
	if encoded.problem.is_empty() and writer.bytes.size() > found.cap:
		encoded.problem = "%d bytes, over its cap of %d" % [writer.bytes.size(), found.cap]
	return encoded


## The message in a payload of `kind`, or null when anything is wrong with it. NetFrame has
## checked the kind's direction, lane and cap.
func decode(kind: int, payload: PackedByteArray) -> WireMessage:
	var reader := WireReader.new(payload)
	var message := _read(kind, reader)
	return null if reader.failed else message


## Why decode() rejects a payload; empty when it does not.
func explain(kind: int, payload: PackedByteArray) -> String:
	var reader := WireReader.new(payload)
	_read(kind, reader)
	return reader.problem


func _read(kind: int, reader: WireReader) -> WireMessage:
	var found := row(kind)
	if found == null:
		reader.fail("no row of kind %d" % kind)
		return null
	var message := WireMessage.new(found.name)
	message.kind = kind
	var fields := found.fields
	if kind == HELLO:
		# Two steps (§4.3): another version is its version alone, whatever follows it.
		var version := reader.u16()
		if reader.failed:
			return null
		message.fields["version"] = version
		if version != VERSION:
			return message
		var after_version: Array[WireField] = []
		after_version.assign(fields.slice(1))
		fields = after_version
	WireField.read_all(fields, reader, message.fields, message)
	if not reader.failed and not reader.at_end():
		reader.fail("%d bytes after the last field" % reader.left())
	return message


func _add(added: WireRow) -> void:
	assert(not _by_kind.has(added.kind) and not _by_name.has(added.name))
	_declare(added)


## The assert in `_add` is stripped in a release build: this logs a row declared twice and keeps
## the first instead of overwriting it.
func _declare(added: WireRow) -> void:
	if _by_kind.has(added.kind) or _by_name.has(added.name):
		push_error("wire: row %d (%s) is already declared" % [added.kind, added.name])
		return
	_by_kind[added.kind] = added
	_by_name[added.name] = added


static func _intents() -> Array[WireRow]:
	var settings := WireField.map(
		"settings", _id(""), WireField.setting("", MAX_TASK_TYPES), MAX_ENTRIES, false
	)
	var has_map := WireField.when("has_map", [_of("map", WireField.Type.PATH)])
	# The return key (#638) decodes as a String: a StringName is no key to core/ (ReturnKey).
	var hello := _up(
		HELLO,
		&"Hello",
		8192,
		[
			_u16("version"),
			_of("content", WireField.Type.S64),
			_name("name"),
			WireField.id("key", true),
		]
	)
	var has_lobby_name := WireField.when("has_lobby_name", [_name("lobby_name")])
	var change := _up(3, &"ChangeSettings", 2048, [_seq(), settings, has_map, has_lobby_name])
	change.content_sized = true
	# No seq: it is a claim, so a failed check gets a Correction, never a Rejected (§4.3).
	var twin := _up(14, RELIABLE_CLAIM, 55, _claim_fields())
	twin.command = &"MoveClaim"
	return [
		hello,
		_up(2, &"SetReady", 5, [_seq(), _bool("ready")]),
		change,
		_up(4, &"LoadAck", 8, [_seq(), _u32("match_id")]),
		_row(
			5,
			&"MoveClaim",
			NetKindTable.Direction.CLIENT_TO_HOST,
			NetKindTable.Lane.LATEST,
			55,
			_claim_fields()
		),
		_up(6, &"PickUp", 6, [_seq(), _of("item", WireField.Type.ITEM)]),
		_up(7, &"PutDown", 16, [_seq(), _vec3("facing")]),
		_up(8, &"Use", 16, [_seq(), _vec3("facing")]),
		_up(9, &"ReturnToLobby", 4, [_seq()]),
		_up(10, &"Raise", 8, [_seq(), _peer("target")]),
		_up(11, &"StopRaise", 4, [_seq()]),
		_up(12, &"GiveUp", 4, [_seq()]),
		_up(13, &"Swap", 4, [_seq()]),
		twin,
		_up(15, &"NextStage", 4, [_seq()]),
		# seq 4, name 81 (its length byte and 80 bytes), colour 1.
		_up(16, &"SetProfile", 86, [_seq(), _name("name"), _of("colour", WireField.Type.U8)]),
		_up(17, &"Throw", 16, [_seq(), _vec3("facing")]),
		# seq 4, station 2, item 2: exactly one names something, the other 0xFFFF, none (#770).
		_up(
			18,
			&"Interact",
			8,
			[
				_seq(),
				WireField.maybe("station", WireField.Type.STATION),
				WireField.maybe("item", WireField.Type.ITEM),
			]
		),
		# seq 4, place 1 (0..2; PlaceInRange refuses another byte, #1218).
		_up(19, &"Draw", 5, [_seq(), _of("place", WireField.Type.U8)]),
		# seq 4 (#1296: the client sends its claim twin first, as before every player action).
		_up(20, &"Pose", 4, [_seq()]),
		# seq 4, target 4 (#1389: as Raise's, a peer id; TargetLiving refuses one nobody has).
		_up(21, &"HandOver", 8, [_seq(), _peer("target")]),
		_up(22, &"TakeOffer", 8, [_seq(), _peer("target")]),
		_up(23, &"CancelOffer", 4, [_seq()]),
		# seq 4, facing 12 (#1438: as Use's; the mug's Drink ignores it, a later rule may aim).
		_up(24, &"UseSecondary", 16, [_seq(), _vec3("facing")]),
		# seq 4, flags 1 (#1398): no claim twin goes before it, a flipper hangs on no position.
		_up(25, &"Flippers", 5, [_seq(), WireField.bits(PackedStringArray(["left", "right"]))]),
		# seq 4, legs 1, arms 1 (#1485: indices into the mode's WheelPoses; WheelPoseInRange refuses
		# a half or out-of-range pick, so 255 is a byte like any other).
		_up(
			26,
			&"WheelPose",
			6,
			[_seq(), _of("legs", WireField.Type.U8), _of("arms", WireField.Type.U8)]
		),
	]


## MoveClaim's fields in wire order, shared with its RELIABLE twin so the two never drift.
static func _claim_fields() -> Array[WireField]:
	return [
		_u32("epoch"),
		_u32("client_tick"),
		_vec3("position"),
		_vec3("velocity"),
		_vec3("facing"),
		WireField.bits(PackedStringArray(["sprint", "moving", "on_floor", "crouched", "sneaking"])),
		_u16("jumps"),
		_u32("sprint_ticks"),
		_u32("moved_ticks"),
	]


## Debug builds only (E17): server/ takes them from the host's own client and turns each into the
## command it names. The role decodes as a String, as Match reads it; false clears it ("").
## ForceClock names the sender itself (the host's own player) in `peer`, as every debug kind
## names a player.
static func _debug_commands() -> Array[WireRow]:
	var role := WireField.when("has_role", [WireField.id("role", true)], {"role": ""})
	return [
		_up(28, &"ForceRole", 42, [_seq(), WireField.target_peer(), role]),
		_up(29, &"ForceClock", 10, [_seq(), WireField.target_peer(), _u16("seconds")]),
	]


static func _events() -> Array[WireRow]:
	var roster_entry := WireField.record(
		"", [_peer("peer"), _name("name"), _bool("ready"), _of("colour", WireField.Type.U8)]
	)
	var numbers := _numbers("settings")
	# Welcome's item rows (#1404): `where` is the rest state (0 on the floor, 1 hand, 2 locked at a
	# station, 3 belt), `holder` 0 for none (so u32, not peer), `place` 0..2.
	var item_entry := (
		WireField
		. record(
			"",
			[
				_item("item"),
				_id("kind"),
				_of("where", WireField.Type.U8),
				_u32("holder"),
				_of("place", WireField.Type.U8),
				_vec3("position"),
			]
		)
	)
	var welcome := _down(
		33,
		&"Welcome",
		8192,
		[
			_peer("peer"),
			_vec3("spot"),
			_u32("epoch"),
			WireField.list("roster", roster_entry, MAX_PLAYERS),
			numbers,
			_path("map"),
			_id("phase"),
			WireField.map("positions", _peer(""), _vec3(""), MAX_PLAYERS),
			_name("lobby_name"),
			WireField.list("items", item_entry, MAX_WELCOME_ITEMS),
		]
	)
	var id_sets := WireField.map(
		"id_sets",
		_id(""),
		WireField.list("", _id(""), MAX_TASK_TYPES, TYPE_PACKED_STRING_ARRAY),
		MAX_ENTRIES
	)
	var settings_changed := _down(
		37,
		&"SettingsChanged",
		8192,
		[
			_numbers("settings"),
			id_sets,
			_path("map"),
			_of("players", WireField.Type.U8),
			_numbers("needed_markers", MAX_MARKERS),
			_numbers("map_markers", MAX_MARKERS),
			_numbers("needed_colours"),
			_numbers("palettes"),
			WireField.list("shortfalls", WireField.record("", _host_text()), MAX_SHORTFALLS),
			_name("lobby_name"),
		]
	)
	var spots := WireField.map("spots", _peer(""), _vec3(""), MAX_PLAYERS)
	var players_placed := _down(40, &"PlayersPlaced", 257, [spots])
	var load_match := _down(
		41, &"LoadMatch", 2048, [_u32("match_id"), _path("map"), _numbers("settings")]
	)
	var peers := WireField.list("peers", _peer(""), MAX_PLAYERS, TYPE_PACKED_INT32_ARRAY)
	var teammates := _down(45, &"Teammates", 98, [_id("role"), peers])
	var station_placed := _down(
		46,
		&"StationPlaced",
		63,
		[_station("station"), _id("kind"), _colour("colour"), _vec3("position")]
	)
	var package := WireField.when("has_station", [_station("station"), _colour("colour")])
	var item_spawned := _down(
		47, &"ItemSpawned", 66, [_item("item"), _id("kind"), _vec3("position"), package]
	)
	# Cooking's herb per icon and per bed (#772, the cooking ADR's CE9): a u8 count each, as many as
	# the herbs; WireBudget sizes them from the mode's Cooking types.
	var herbs_dealt := _down(
		74,
		&"HerbsDealt",
		2048,
		[
			WireField.list("code", _id(""), MAX_HERBS, TYPE_PACKED_STRING_ARRAY),
			WireField.list("beds", _id(""), MAX_HERBS, TYPE_PACKED_STRING_ARRAY),
		]
	)
	for sized: WireRow in [
		welcome,
		settings_changed,
		players_placed,
		load_match,
		teammates,
		station_placed,
		item_spawned,
		herbs_dealt,
	]:
		sized.content_sized = true
	return [
		_down(REJECTED, &"Rejected", 37, [_u32("seq"), _id("reason")]),
		welcome,
		_down(
			34,
			&"PlayerJoined",
			98,
			[_peer("peer"), _name("name"), _vec3("spot"), _of("colour", WireField.Type.U8)]
		),
		_down(35, &"PlayerLeft", 4, [_peer("peer")]),
		_down(36, &"ReadyChanged", 5, [_peer("peer"), _bool("ready")]),
		settings_changed,
		_down(38, &"PhaseChanged", 37, [_id("phase"), WireField.maybe("end_tick", _tick())]),
		_down(39, &"CountdownCancelled", 33, [_id("reason")]),
		players_placed,
		load_match,
		_down(42, &"PlayerLoaded", 4, [_peer("peer")]),
		_down(43, &"RoundStarted", 4, [_of("start_tick", _tick())]),
		_down(44, &"RoleAssigned", 33, [_id("role")]),
		teammates,
		station_placed,
		item_spawned,
		_down(
			48,
			&"ItemPickedUp",
			9,
			[
				_peer("peer"),
				_item("item"),
				WireField.maybe("belted", WireField.Type.ITEM),
				_of("place", WireField.Type.U8),
			]
		),
		_down(49, &"ItemPlaced", 47, [_item("item"), _vec3("position"), _id("cause")]),
		_down(50, &"PackageDelivered", 4, [_item("item"), _station("station")]),
		_down(51, &"TaskProgress", 4, [_u16("done"), _u16("total")]),
		_down(52, &"Swung", 16, [_peer("peer"), _vec3("facing")]),
		_down(53, &"Damaged", 8, [_s32("amount"), _s32("health")]),
		_down(
			54,
			&"SelfStatus",
			20,
			[
				_s32("health"),
				_s32("stamina"),
				_bool("sprint_available"),
				_of("claim_tick", WireField.Type.S64),
				_of("drunk", WireField.Type.U8),
				_bool("posed"),
				_of("wheel_pose", WireField.Type.U8),
			]
		),
		_down(55, &"Died", 16, [_peer("peer"), _vec3("position")]),
		_down(56, &"Correction", 28, [_u32("epoch"), _vec3("position"), _vec3("velocity")]),
		_down(
			57,
			&"MatchEnded",
			216,
			[
				_id("side"),
				WireField.when("has_reason", [_id("reason"), _text_numbers("numbers")]),
			]
		),
		_down(58, &"Disconnecting", 33, [_id("reason")]),
		_down(59, &"KnockedDown", 16, [_peer("peer"), _vec3("position")]),
		_down(60, &"Respawned", 16, [_peer("peer"), _vec3("position")]),
		_down(61, &"RaiseStarted", 8, [_peer("raiser"), _peer("target")]),
		_down(62, &"RaiseStopped", 8, [_peer("raiser"), _peer("target")]),
		_down(63, &"Revived", 4, [_peer("peer")]),
		_down(64, &"Swapped", 5, [_peer("peer"), _of("place", WireField.Type.U8)]),
		_down(
			65,
			&"TaskState",
			38,
			[_of("task", WireField.Type.U8), _id("type"), _u16("done"), _u16("total")]
		),
		_down(
			66,
			&"ProfileChanged",
			86,
			[_peer("peer"), _name("name"), _of("colour", WireField.Type.U8)]
		),
		_down(
			67,
			&"ZoneProgress",
			11,
			[
				_station("station"),
				_u16("ticks"),
				_u16("needed"),
				_bool("counting"),
				_of("tick", _tick())
			]
		),
		_down(
			68,
			&"ItemThrown",
			46,
			[
				_item("item"),
				_peer("peer"),
				_vec3("origin"),
				_vec3("velocity"),
				_vec3("gravity"),
				_of("tick", _tick())
			]
		),
		_down(69, &"ItemVanished", 2, [_item("item")]),
		_down(70, &"SwitchChanged", 3, [_station("station"), _bool("on")]),
		_down(71, &"ButtonPressed", 2, [_station("station")]),
		_down(72, &"ItemChanged", 35, [_item("item"), _id("kind")]),
		_down(
			73,
			&"OrderPosted",
			69,
			[_station("station"), _id("bun"), _id("patty"), _of("icon", WireField.Type.U8)]
		),
		herbs_dealt,
		_down(75, &"LiftChanged", 7, [_station("station"), _bool("up"), _of("tick", _tick())]),
		_down(
			76,
			&"PartNeeded",
			36,
			[_station("station"), WireField.when("has_kind", [_id("kind")], {"kind": &""})]
		),
		_down(77, &"FilmLoaded", 4, [_station("station"), _item("item")]),
		_shot_taken(),
		_down(
			79,
			&"GrillLoaded",
			12,
			[_station("station"), _item("item"), _of("fried", _tick()), _of("burnt", _tick())]
		),
		_down(80, &"IngredientPlaced", 4, [_item("item"), _station("station")]),
		_down(
			81,
			&"FitChanged",
			11,
			[
				_station("station"),
				WireField.when("has_fitter", [_peer("fitter")], {"fitter": 0}),
				_of("tick", _tick()),
			]
		),
		_down(82, &"PartFitted", 4, [_station("station"), _item("item")]),
		_down(83, &"PhotoPrinted", 4, [_item("item"), _u16("shot")]),
		_down(84, &"PhotoHung", 5, [_item("item"), _station("station"), _bool("counted")]),
		_down(
			85,
			&"BurgerPlated",
			103,
			[_item("item"), _station("station"), _id("bun"), _id("patty"), _id("herb")]
		),
		_down(86, &"BurgerServed", 3, [_station("station"), _bool("right")]),
		_down(87, &"OfferMade", 8, [_peer("giver"), _peer("target")]),
		_down(88, &"OfferEnded", 8, [_peer("giver"), _peer("target")]),
		_down(
			89,
			&"EngineProblemOpened",
			23,
			[
				_u16("problem"),
				WireField.list(
					"stations", _station(""), MAX_PROBLEM_STATIONS, TYPE_PACKED_INT32_ARRAY
				),
				_of("deadline", _tick()),
			]
		),
		_down(90, &"EngineProblemFixed", 2, [_u16("problem")]),
		_down(91, &"EngineBlast", 2, [_u16("stage")]),
		_down(
			92,
			&"GillFlipped",
			4,
			[_station("station"), _of("slit", WireField.Type.U8), _bool("open")]
		),
		_down(
			93,
			&"BreakerChain",
			24,
			[
				_u16("problem"),
				WireField.list(
					"breakers", _station(""), MAX_PROBLEM_STATIONS, TYPE_PACKED_INT32_ARRAY
				),
				_of("next", WireField.Type.U8),
				WireField.maybe("since", _tick()),
			]
		),
		_down(
			94,
			&"PinballState",
			99,
			[
				_u32("game"),
				WireField.maybe("player", WireField.Type.PEER),
				WireField.bits(PackedStringArray(["left", "right", "in_play"])),
				_u32("score"),
				_of("balls_left", WireField.Type.U8),
				_u32("best"),
				_name("best_name"),
			]
		),
		_down(
			95,
			&"CrystalChanged",
			11,
			[
				_station("station"),
				WireField.maybe("charger", WireField.Type.STATION),
				_of("phase", WireField.Type.U8),
				WireField.maybe("item", WireField.Type.ITEM),
				WireField.maybe("tick", _tick()),
			]
		),
		_booth_step(),
	]


## The photo booth's step (#1396): every field always, the ones a step does not use 0 or empty
## (BoothStepEvent). A record row is the lobby avatar's public look and pose: its peer, colour,
## position, facing and the crouched, sneaking, posed and limp flags; at most MAX_PLAYERS rows
## and MAX_PLAYERS strips, so its size is the schema's, not the content's.
static func _booth_step() -> WireRow:
	var frame_row := (
		WireField
		. record(
			"",
			[
				_peer("peer"),
				_of("colour", WireField.Type.U8),
				_vec3("position"),
				_vec3("facing"),
				WireField.bits(PackedStringArray(["crouched", "sneaking", "posed", "limp"])),
			]
		)
	)
	return _down(
		96,
		&"BoothStep",
		529,
		[
			_station("station"),
			_u16("strip"),
			_of("step", WireField.Type.U8),
			_of("presser", WireField.Type.U32),
			_of("frames", WireField.Type.U8),
			_u16("countdown"),
			_u16("gap"),
			_of("frame", WireField.Type.U8),
			WireField.list("record", frame_row, MAX_PLAYERS),
			WireField.list("items", _item(""), MAX_PLAYERS, TYPE_PACKED_INT32_ARRAY),
		]
	)


## The photo camera's shot (the photo ADR §3.3): the record is the snapshot's avatar row without
## its velocity and invulnerability, with its peer, at most MAX_OTHER_AVATARS rows (15 * 35
## bytes): a downed player takes no shot, so its own avatar is never in it. Its
## rows grow with the mode's players, so WireBudget holds its worst case (the photo ADR §3.3).
static func _shot_taken() -> WireRow:
	var shot_row := (
		WireField
		. record(
			"",
			[
				_peer("peer"),
				_vec3("position"),
				_vec3("facing"),
				WireField.bits(PackedStringArray(["downed", "crouched"])),
				WireField.maybe("held_item", WireField.Type.ITEM),
				WireField.maybe("belt_item", WireField.Type.ITEM),
				WireField.maybe("belt_item2", WireField.Type.ITEM),
			]
		)
	)
	var shot := _down(
		78,
		&"ShotTaken",
		532,
		[
			_station("station"),
			_item("film"),
			_u16("shot"),
			WireField.list("record", shot_row, MAX_OTHER_AVATARS),
		]
	)
	shot.content_sized = true
	return shot


static func _state_and_voice() -> Array[WireRow]:
	var avatar := (
		WireField
		. record(
			"",
			[
				_vec3("position"),
				_vec3("velocity"),
				_vec3("facing"),
				WireField.bits(
					PackedStringArray(
						["downed", "invulnerable", "crouched", "sneaking", "posed", "limp"]
					)
				),
				_of("drunk", WireField.Type.U8),
				_of("wheel_pose", WireField.Type.U8),
				WireField.maybe("held_item", WireField.Type.ITEM),
				WireField.maybe("belt_item", WireField.Type.ITEM),
				WireField.maybe("belt_item2", WireField.Type.ITEM),
			]
		)
	)
	var avatars := WireField.map("avatars", _peer(""), avatar, MAX_AVATARS, false)
	# The pinball's ball (#1399): its key is absent when no ball is on the table. The avatars stay the
	# last field: SnapshotEncoder patches the map's count, the header's last byte.
	var ball := WireField.when("has_ball", [_vec3("ball")])
	var snapshot := _row(
		104,
		&"Snapshot",
		NetKindTable.Direction.HOST_TO_CLIENT,
		NetKindTable.Lane.LATEST,
		1024,
		[_of("tick", _tick()), ball, avatars]
	)
	var voice_up := _row(
		112,
		&"VoiceUp",
		NetKindTable.Direction.CLIENT_TO_HOST,
		NetKindTable.Lane.VOICE,
		2 + MAX_OPUS,
		[_u16("seq"), WireField.opus("opus", MAX_OPUS)]
	)
	# One poll's relayed frames for one listener (M5-4b, #374); kind 113, the single-frame
	# VoiceDown of protocol 7, is retired. Each frame decodes to a VoiceDown (DecodedView). Its
	# strength is how drunk the speaker's voice sounds, 0 to 255 (#1392; core's VoiceRule).
	var frame := (
		WireField
		. record(
			"",
			[
				_peer("speaker"),
				_u16("seq"),
				_of("strength", WireField.Type.U8),
				WireField.sized_opus("opus", MAX_OPUS),
			],
		)
	)
	var voice_batch := _row(
		114,
		&"VoiceBatch",
		NetKindTable.Direction.HOST_TO_CLIENT,
		NetKindTable.Lane.VOICE,
		NetKindTable.MAX_UNRELIABLE_PAYLOAD,
		[_of("tick", _tick()), WireField.list("frames", frame, MAX_BATCH_FRAMES)]
	)
	return [snapshot, voice_up, voice_batch]


static func _row(
	kind: int,
	row_name: StringName,
	direction: NetKindTable.Direction,
	lane: NetKindTable.Lane,
	cap: int,
	fields: Array[WireField]
) -> WireRow:
	return WireRow.new(kind, row_name, direction, lane, cap, fields)


## A RELIABLE client-to-host row.
static func _up(kind: int, row_name: StringName, cap: int, fields: Array[WireField]) -> WireRow:
	return _row(
		kind,
		row_name,
		NetKindTable.Direction.CLIENT_TO_HOST,
		NetKindTable.Lane.RELIABLE,
		cap,
		fields
	)


## A RELIABLE host-to-client row (every event).
static func _down(kind: int, row_name: StringName, cap: int, fields: Array[WireField]) -> WireRow:
	return _row(
		kind,
		row_name,
		NetKindTable.Direction.HOST_TO_CLIENT,
		NetKindTable.Lane.RELIABLE,
		cap,
		fields
	)


static func _of(field_name: String, type: WireField.Type) -> WireField:
	return WireField.of(field_name, type)


static func _seq() -> WireField:
	return WireField.seq_number()


static func _u16(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.U16)


static func _u32(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.U32)


static func _s32(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.S32)


static func _bool(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.BOOL)


static func _vec3(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.VEC3)


static func _colour(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.COLOUR)


static func _peer(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.PEER)


static func _item(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.ITEM)


static func _station(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.STATION)


static func _tick() -> WireField.Type:
	return WireField.Type.TICK


static func _id(field_name: String) -> WireField:
	return WireField.id(field_name)


static func _path(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.PATH)


## A player's or the lobby's name (#550, #214): UTF-8, at most WireField.NAME_MAX_BYTES bytes.
static func _name(field_name: String) -> WireField:
	return _of(field_name, WireField.Type.NAME)


## A map<id, s32>: whole-number settings, markers or colours per id, at most `most` entries.
static func _numbers(field_name: String, most: int = MAX_ENTRIES) -> WireField:
	return WireField.map(field_name, _id(""), _s32(""), most)


## Host text (#548): an id, its subject ids and its whole-number arguments, never a sentence; the
## client words it in its own language. Core's HostText.to_dict().
static func _host_text() -> Array[WireField]:
	return [
		_id("id"),
		WireField.list("ids", _id(""), MAX_TEXT_IDS, TYPE_PACKED_STRING_ARRAY),
		_text_numbers("numbers"),
	]


## A host text's arguments: a map<id, s32> of at most MAX_TEXT_NUMBERS.
static func _text_numbers(field_name: String) -> WireField:
	return WireField.map(field_name, _id(""), _s32(""), MAX_TEXT_NUMBERS)
