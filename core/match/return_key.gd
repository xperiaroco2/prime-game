class_name ReturnKey
extends RefCounted
## A return key (ARCHITECTURE §3.5; the returning-players ADR, Decision 1, P1 (c), P7 (a)): the
## text a client sends in every Hello so that the host can give a player who left and joined again
## its old number. The client makes it from the random secret of its settings file (UserSettings)
## and the join's target (a room code or a Direct address and port, JoinTarget.return_target): one
## secret and two targets give two keys, one target twice the same key. The secret never leaves
## the client; the host keeps keys in MatchState.numbers only. Pure: both sides use it, the host to
## tell a usable key (is_valid), the client to make one (of). No randomness here: the secret's
## bytes come from the client (Crypto), never from core/.

## A key, and a secret, are BYTES bytes, written as LENGTH lowercase hex characters.
const BYTES := 16
const LENGTH := 32


## Whether `value` is a usable key: a String (a StringName is not, P7) of LENGTH characters, each
## of 0-9 or a-f. Anything else is no key: its Hello still joins, with a new number and no
## binding, never Rejected (P7 (a)).
static func is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = value
	if text.length() != LENGTH:
		return false
	for i: int in text.length():
		var code := text.unicode_at(i)
		if not ((code >= 0x30 and code <= 0x39) or (code >= 0x61 and code <= 0x66)):
			return false
	return true


## The key for `secret` at `target`: the first 16 bytes of SHA-256 of the secret, "|" and the
## target (UTF-8), as LENGTH lowercase hex characters.
static func of(secret: String, target: String) -> String:
	return (secret + "|" + target).sha256_buffer().slice(0, BYTES).hex_encode()
