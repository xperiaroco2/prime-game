class_name Audience
extends RefCounted
## Who receives an event (ARCHITECTURE §5): each event class declares one, as a rule evaluated
## when the event is emitted, against the state after the command. server/ delivers to exactly
## these recipients and never adds one; *server* directives reach no peer.

enum Kind {
	EVERYONE,  ## every player who has not left
	ONLY,  ## one present player: the joiner, the victim; not after it left
	ROLE,  ## every present player of one role
	LIFE,  ## every player in one life state (the downed, say)
	SERVER,  ## a directive to server/ (RefuseJoins, DisconnectPeer): no peer
	SENDER,  ## an intent's sender, a player or a connected newcomer: Rejected only
}

var kind: Kind
## The peer of ONLY and SENDER.
var peer := 0
## The role id of ROLE.
var role: StringName
## The life state of LIFE.
var life := PlayerState.Life.DOWNED


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


## An intent's sender, which may be a connected peer whose Hello was not accepted yet. Only
## Rejected uses it (the engineer's answer on #49), so no other event reaches a non-player.
static func sender(from_peer: int) -> Audience:
	var audience := Audience.new(Kind.SENDER)
	audience.peer = from_peer
	return audience


## The peers entitled to the event now, in peer-id order. ONLY names a present player; SENDER may
## also name a connected peer that is not a player yet (a Rejected before its Hello was accepted).
## Neither names a peer id of 0 or less (no actor; to MultiplayerPeer those ids mean a broadcast).
func recipients(state: MatchState) -> PackedInt32Array:
	var found := PackedInt32Array()
	match kind:
		Kind.EVERYONE:
			for p: int in state.present_peers():
				found.append(p)
		Kind.ONLY:
			if peer > 0 and state.is_present(peer):
				found.append(peer)
		Kind.SENDER:
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
