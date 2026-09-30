class_name MovementRule
extends RefCounted
## Where every accepted MoveClaim goes (ARCHITECTURE §7.1, §9.2). The skeleton of 2a keeps the
## claim of the current epoch as the player's last accepted position and drops a claim of an
## older epoch as stale; 2d adds the checks of §7.1 (speed for the life state and stamina,
## jumps, no teleport, the client tick's rate) with their Correction, and stamina settling.


func apply(ctx: MatchContext, command: MatchCommand) -> void:
	var player := ctx.state.player(command.peer)
	if player == null or command.get_int("epoch", -1) != player.epoch:
		return
	player.position = command.get_vector3("position", player.position)
	player.velocity = command.get_vector3("velocity", Vector3.ZERO)
	player.facing = command.get_vector3("facing", player.facing)
	player.on_floor = command.get_bool("on_floor", player.on_floor)
	player.claim_tick = command.get_int("client_tick", player.claim_tick)
