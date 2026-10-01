class_name ModeCheck
extends RefCounted
## The mode check without layouts (ARCHITECTURE §9.1): what a game mode alone gets wrong. Match
## refuses a mode with errors, listing them all; a unit test runs it on every mode in `content/`.
## The check with the levels' layouts (spawn tags, markers) is LayoutCheck (2b).
##
## Errors: a phase, outcome, intent, setting, role, side or item kind that a part names but the
## mode does not declare; a `_setting` property that reads a number but names a set of ids; an
## outcome a phase can report without a row; an accepted intent that neither the phase class, the
## movement rule nor any rule handles; a phase whose rules can knock a player down (an effect that
## emits KnockedDown: a Strike) that lists no LifeTicks, so the downed would never die (M4-3);
## two rules on one trigger in one owner; a number outside its
## part's bounds; an id outside the wire's alphabet (below). Warnings: a role-owned or role-gated
## rule with an effect whose event goes to everyone, which reveals the actor's role (§9.2).
##
## Ids travel on the wire as the content's own names (§4.3, E5), so every content id is 1 to
## MAX_ID_LENGTH characters of `a-z`, `0-9` and `_`: the `id` of every part that has one (roles,
## sides, item and station kinds, task types, settings, phases, win conditions), the sides and
## spawn tags parts name, and the reason each condition rejects with. D1 (a) in the wire ADR,
## the designer's answer on #96.

## The longest id the wire carries (§4.3 `id`).
const MAX_ID_LENGTH := 32
## The properties that hold an id (a StringName) of the content.
const ID_PROPERTIES: Array[String] = ["id", "side", "spawn_tag", "tag"]
const _ID_ALPHABET := "abcdefghijklmnopqrstuvwxyz0123456789_"

var errors := PackedStringArray()
var warnings := PackedStringArray()


static func run(mode: GameMode) -> ModeCheck:
	var check := ModeCheck.new()
	check._check_mode(mode)
	return check


func _check_mode(mode: GameMode) -> void:
	_add("mode", mode.check(mode))
	_check_unique("setting", _ids(mode.settings))
	_check_unique("side", _ids(mode.sides))
	_check_unique("role", _ids(mode.roles))
	_check_unique("item kind", _ids(mode.item_kinds))
	_check_unique("task type", _ids(mode.task_types))
	_check_unique("phase", _ids(mode.phases))
	_walk(mode, "mode", mode, {})
	_check_rules(mode)
	_check_phases(mode)
	_check_transitions(mode)


## Every part's own check, and every `*_setting` property against the declared settings.
func _walk(mode: GameMode, path: String, value: Variant, seen: Dictionary) -> void:
	if value is Script or not (value is Resource):
		if value is Array:
			var items: Array = value
			for i in items.size():
				_walk(mode, "%s[%d]" % [path, i], items[i], seen)
		return
	var resource: Resource = value
	if seen.has(resource):
		return
	seen[resource] = true
	if resource is ContentPart and resource != mode:
		var part: ContentPart = resource
		_add(path, part.check(mode))
	_check_ids(path, resource)
	for property: Dictionary in resource.get_property_list():
		var name: String = property["name"]
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_STORAGE == 0 or name == "script":
			continue
		var child: Variant = resource.get(name)
		if name.ends_with("_setting") and (child is StringName or child is String):
			var setting := StringName(str(child))
			var spec := mode.find_setting(setting) if not setting.is_empty() else null
			if not setting.is_empty() and spec == null:
				errors.append(
					(
						"%s.%s names setting %s, which the mode does not declare"
						% [path, name, setting]
					)
				)
			elif spec != null and not spec.is_number() and not _holds_set(resource, name):
				errors.append(
					(
						"%s.%s names setting %s, which is a set of ids, not a whole number"
						% [path, name, setting]
					)
				)
		else:
			_walk(mode, "%s.%s" % [path, name], child, seen)
	_check_nulls(path, resource)


## Whether `resource`'s `_setting` property `property` holds a set of ids
## (ContentPart.set_settings).
static func _holds_set(resource: Resource, property: String) -> bool:
	return resource is ContentPart and (resource as ContentPart).set_settings().has(property)


## Every owner's rules: known triggers, one rule per trigger, costs not negated, and the
## warning about public events of role-owned or role-gated rules.
func _check_rules(mode: GameMode) -> void:
	_check_owner("mode.actions", mode.actions, Intents.ALL, false)
	_check_owner("mode.reactions", mode.reactions, Facts.ALL, false)
	for role: GameRole in mode.roles:
		if role != null:
			_check_owner("role %s.actions" % role.id, role.actions, Intents.ALL, true)
	for kind: ItemKind in mode.item_kinds:
		if kind != null:
			_check_owner("item kind %s.actions" % kind.id, kind.actions, Intents.ALL, false)


func _check_owner(
	owner: String, rules: Array[Rule], triggers: Array[StringName], role_owned: bool
) -> void:
	var seen_triggers: Array[StringName] = []
	for rule: Rule in rules:
		if rule == null:
			continue
		if not triggers.has(rule.trigger):
			errors.append("%s: trigger %s is not one of %s" % [owner, rule.trigger, triggers])
		if seen_triggers.has(rule.trigger):
			errors.append("%s: two rules on %s" % [owner, rule.trigger])
		seen_triggers.append(rule.trigger)
		var gated := role_owned
		for condition: Condition in rule.conditions:
			if condition == null:
				continue
			if condition is Cost and condition.negate:
				errors.append("%s: rule %s negates a cost" % [owner, rule.trigger])
			gated = gated or condition.gates_on_role()
		for effect: RuleEffect in rule.effects:
			if effect != null and gated and _emits_to_everyone(effect):
				(
					warnings
					. append(
						(
							(
								"%s: rule %s is role-owned or role-gated and emits an event to everyone,"
								+ " which reveals the actor's role"
							)
							% [owner, rule.trigger]
						)
					)
				)


func _check_phases(mode: GameMode) -> void:
	for spec: PhaseSpec in mode.phases:
		if spec == null:
			continue
		var phase := spec.create_phase()
		if phase == null:
			continue
		for entry: AcceptSpec in spec.accepts:
			if entry == null or not Intents.ALL.has(entry.intent):
				continue
			if not _handled(mode, phase, entry.intent):
				errors.append(
					(
						"phase %s accepts %s, which neither its class nor any rule handles"
						% [spec.id, entry.intent]
					)
				)
			elif entry.from & AcceptSpec.From.NEWCOMER != 0 and not phase.handles(entry.intent):
				errors.append(
					(
						(
							"phase %s accepts %s from a newcomer, which its class does not handle:"
							+ " only a phase class can take an intent from a newcomer"
						)
						% [spec.id, entry.intent]
					)
				)
		var knocks_down := _knocking_down(mode, spec)
		if not knocks_down.is_empty() and not _lists_life_ticks(spec):
			errors.append(
				(
					(
						"phase %s runs %s, which can knock a player down, but lists no LifeTicks:"
						+ " the downed would stay downed until they leave"
					)
					% [spec.id, knocks_down]
				)
			)
		for outcome: StringName in reportable_outcomes(mode, spec):
			if mode.find_transition(spec.id, outcome) == null:
				errors.append(
					"phase %s can report %s, which has no transition row" % [spec.id, outcome]
				)


func _check_transitions(mode: GameMode) -> void:
	var keys: Array[String] = []
	for row: Transition in mode.transitions:
		if row == null:
			continue
		var from := mode.find_phase(row.from)
		if from == null:
			errors.append("a row from %s, which is not a phase" % row.from)
		elif not reportable_outcomes(mode, from).has(row.outcome):
			errors.append(
				(
					"the row %s, %s: phase %s never reports %s"
					% [row.from, row.outcome, row.from, row.outcome]
				)
			)
		if mode.find_phase(row.to) == null:
			errors.append(
				"the row %s, %s goes to %s, which is not a phase" % [row.from, row.outcome, row.to]
			)
		var key := "%s, %s" % [row.from, row.outcome]
		if keys.has(key):
			errors.append("two rows for %s" % key)
		keys.append(key)


## The outcomes a phase can report: its class's; `won` when it checks the win conditions; its
## tick systems'; every task type's; and those of ReportOutcome-like effects in the rules that
## can run in it (its accepted intents' actions, and every reaction).
static func reportable_outcomes(mode: GameMode, spec: PhaseSpec) -> Array[StringName]:
	var found: Array[StringName] = []
	var phase := spec.create_phase()
	if phase != null:
		found.append_array(phase.outcomes())
	if spec.checks_wins:
		found.append(Match.WON)
	var parts: Array[StringName] = []
	for system: TickSystem in spec.tick_systems:
		if system != null:
			parts.append_array(system.reported_outcomes())
	for type: TaskType in mode.task_types:
		if type != null:
			parts.append_array(type.reported_outcomes())
	for outcome: StringName in parts:
		if not found.has(outcome):
			found.append(outcome)
	var rules: Array[Rule] = []
	for entry: AcceptSpec in spec.accepts:
		if entry != null:
			rules.append_array(_actions_on(mode, entry.intent))
	rules.append_array(mode.reactions)
	for rule: Rule in rules:
		if rule == null:
			continue
		for effect: RuleEffect in rule.effects:
			if effect != null:
				for outcome: StringName in effect.reported_outcomes():
					if not found.has(outcome):
						found.append(outcome)
	return found


## The triggers of the rules that can run in `spec` (its accepted intents' actions, and every
## reaction) with an effect that can emit KnockedDown (a Strike), each once, in order.
static func _knocking_down(mode: GameMode, spec: PhaseSpec) -> Array[StringName]:
	var rules: Array[Rule] = []
	for entry: AcceptSpec in spec.accepts:
		if entry != null:
			rules.append_array(_actions_on(mode, entry.intent))
	rules.append_array(mode.reactions)
	var found: Array[StringName] = []
	for rule: Rule in rules:
		if rule == null or found.has(rule.trigger):
			continue
		for effect: RuleEffect in rule.effects:
			if effect != null and effect.emits().has(KnockedDownEvent):
				found.append(rule.trigger)
				break
	return found


static func _lists_life_ticks(spec: PhaseSpec) -> bool:
	for system: TickSystem in spec.tick_systems:
		if system is LifeTicks:
			return true
	return false


static func _handled(mode: GameMode, phase: Phase, intent: StringName) -> bool:
	return (
		phase.handles(intent)
		or intent == Intents.MOVE_CLAIM
		or not _actions_on(mode, intent).is_empty()
	)


## Every rule on `intent` among the mode's, the roles' and the item kinds' actions.
static func _actions_on(mode: GameMode, intent: StringName) -> Array[Rule]:
	var found: Array[Rule] = []
	var lists: Array[Array] = [mode.actions]
	for role: GameRole in mode.roles:
		if role != null:
			lists.append(role.actions)
	for kind: ItemKind in mode.item_kinds:
		if kind != null:
			lists.append(kind.actions)
	for rules: Array in lists:
		for rule: Variant in rules:
			if rule is Rule and (rule as Rule).trigger == intent:
				found.append(rule as Rule)
	return found


static func _emits_to_everyone(effect: RuleEffect) -> bool:
	for script: Script in effect.emits():
		var kind: Variant = script.get_script_constant_map().get("AUDIENCE_KIND")
		if kind is int and kind == Audience.Kind.EVERYONE:
			return true
	return false


## Empty entries in the lists of a resource (a rule, a row or a phase left empty in the editor).
func _check_nulls(path: String, resource: Resource) -> void:
	for property: Dictionary in resource.get_property_list():
		var name: String = property["name"]
		var type: int = property["type"]
		var usage: int = property["usage"]
		if type != TYPE_ARRAY or usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		var items: Array = resource.get(name)
		if items.is_typed() and items.get_typed_builtin() == TYPE_OBJECT and items.has(null):
			errors.append("%s.%s has an empty entry" % [path, name])


## Every id `resource` holds (ID_PROPERTIES, and a condition's rejection reason) against the
## wire's alphabet. An empty side or tag means "none" and is left to the part's own check.
func _check_ids(path: String, resource: Resource) -> void:
	for property: String in ID_PROPERTIES:
		var value: Variant = resource.get(property)
		if not (value is StringName or value is String):
			continue
		var id := str(value)
		if id.is_empty() and property != "id":
			continue
		if not is_wire_id(id):
			errors.append(_bad_id("%s.%s" % [path, property], id))
	if resource is Condition:
		var reason := String((resource as Condition).rejection_reason())
		if not is_wire_id(reason):
			errors.append(_bad_id("%s's rejection reason" % path, reason))


## Whether `id` fits the wire's `id` type (§4.3): 1 to MAX_ID_LENGTH characters of `a-z`, `0-9`
## and `_`.
static func is_wire_id(id: String) -> bool:
	if id.is_empty() or id.length() > MAX_ID_LENGTH:
		return false
	for character: String in id:
		if not _ID_ALPHABET.contains(character):
			return false
	return true


static func _bad_id(where: String, id: String) -> String:
	return (
		'%s is "%s": an id is 1 to %d characters of a-z, 0-9 and _ (the wire\'s alphabet)'
		% [where, id, MAX_ID_LENGTH]
	)


func _check_unique(what: String, ids: Array[StringName]) -> void:
	var seen: Array[StringName] = []
	for id: StringName in ids:
		if seen.has(id):
			errors.append("two %ss with the id %s" % [what, id])
		seen.append(id)


func _add(path: String, found: PackedStringArray) -> void:
	for message: String in found:
		errors.append("%s: %s" % [path, message])


static func _ids(parts: Array) -> Array[StringName]:
	var found: Array[StringName] = []
	for part: Variant in parts:
		if part is Object and part != null:
			var id: Variant = (part as Object).get("id")
			if id is StringName:
				found.append(id as StringName)
	return found
