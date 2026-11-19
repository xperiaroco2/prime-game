class_name SettingEquals
extends Condition
## Passes when the match setting `setting` holds `value` (ARCHITECTURE §9.4): the host's lobby
## settings (ChangeSettings, a default the lobby keeps by the player count) as the match plays
## with them. Every player saw them in the lobby (SettingsChanged and LoadMatch are public), so a
## win condition may hold it and name its id as MatchEnded's reason (#548) without telling anyone
## anything new. Part of "time up with no humans" (`dissidents` 0, #1627): the aliens-only match
## the M8 release plays. Win conditions check facts only, so it never rejects an intent.

## A SettingSpec id of the mode.
@export var setting: StringName
## The value it must hold.
@export var value := 0


static func of(setting_id: StringName, wanted: int) -> SettingEquals:
	var condition := SettingEquals.new()
	condition.setting = setting_id
	condition.value = wanted
	return condition


## It reads the match's settings, not the actor: a win condition may hold it.
func reads_actor_state() -> bool:
	return false


func _test(ctx: MatchContext) -> bool:
	return ctx.setting(setting) == value


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if setting.is_empty():
		found.append("SettingEquals has no setting")
		return found
	var spec := mode.find_setting(setting)
	if spec == null:
		found.append("SettingEquals names setting %s, which the mode does not declare" % setting)
	elif not spec.is_number():
		found.append("SettingEquals names setting %s, which holds no number" % setting)
	else:
		append_found(
			found,
			[
				out_of_bounds(
					"SettingEquals %s value" % setting, value, spec.min_value, spec.max_value
				)
			]
		)
	return found
