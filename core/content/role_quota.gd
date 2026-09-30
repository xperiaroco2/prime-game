class_name RoleQuota
extends ContentPart
## One quota of DealRoles (2c, ARCHITECTURE §9.4): draws max(0, min(setting, N - leave_at_least))
## players of the roster for `role`.

@export var role: GameRole
## The match setting that holds the count (`dissidents`).
@export var count_setting: StringName
@export var leave_at_least := 1


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if role == null:
		found.append("a role quota has no role")
	elif mode.find_role(role.id) == null:
		found.append("a role quota names role %s, which the mode does not declare" % role.id)
	append_found(found, [out_of_bounds("leave_at_least", leave_at_least, 0, 10)])
	return found


## The number of players this quota draws from `players`.
func count_for(settings: Dictionary[StringName, int], players: int) -> int:
	var wanted: int = settings.get(count_setting, 0)
	return maxi(0, mini(wanted, players - leave_at_least))
