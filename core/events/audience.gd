class_name Audience
extends RefCounted
## Who receives an event (ARCHITECTURE §5): each event class declares one, as a rule evaluated
## when the event is emitted, against the state after the command. server/ delivers to exactly
## these recipients and never adds one; *server* directives reach no peer.

enum Kind {
	EVERYONE,  ## every player who has not left
	ONLY,  ## one peer: the joiner, the sender, the victim; not after it left
	ROLE,  ## every present player of one role
	LIFE,  ## every player in one life state (the ghosts)
	SERVER,  ## a directive to server/ (RefuseJoins, DisconnectPeer): no peer
}

var kind: Kind
## The peer of ONLY.
var peer := 0
## The role id of ROLE.
var role: StringName
## The life state of LIFE.
var life := PlayerState.Life.GHOST


func _init(audience_kind: Kind) -> void:
	kind = audience_kind


static func everyone() -> Audience:
	return Audience.new(Kind.EVERYONE)


static func only(to_peer: int) -> Audience:
	var audience := Audience.new(Kind.ONLY)
	audience.peer = to_peer
	return audience


static func of_role(role_id: StringName) -> Audience:
	var audience := Audience.new(Kind.ROLE)
	audience.role = role_id
	return audience


static func of_life(life_state: PlayerState.Life) -> Audience:
	var audience := Audience.new(Kind.LIFE)
	audience.life = life_state
	return audience


static func server() -> Audience:
	return Audience.new(Kind.SERVER)


## The peers entitled to the event now, in peer-id order. ONLY may name a connected peer that is
## not a player yet (a Rejected before its Hello was accepted), never a peer id of 0 or less (no
## actor; to MultiplayerPeer those ids mean a broadcast).
func recipients(state: MatchState) -> PackedInt32Array:
	var found := PackedInt32Array()
	match kind:
		Kind.EVERYONE:
			for p: int in state.present_peers():
				found.append(p)
		Kind.ONLY:
			var player := state.player(peer)
			if peer > 0 and (player == null or player.is_present()):
				found.append(peer)
		Kind.ROLE:
			for p: int in state.present_peers():
				if state.players[p].role == role:
					found.append(p)
		Kind.LIFE:
			for p: int in state.peers():
				if state.players[p].life == life:
					found.append(p)
	return found
