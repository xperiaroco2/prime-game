class_name LobbyName
extends RefCounted
## The rules of the lobby's name (ARCHITECTURE §3.5, #214; the engineer's answers on #214): the host
## sets it, at most MAX_CHARS characters, cleaned like a player's name (PlayerNames: invisible
## characters and controls dropped, blank edges trimmed), never refused for its content. "" is the
## default, which the client shows as `lobby.default_name` with the host's name: the default is not
## a stored string, so it follows the host's name and each client's language.

## The most characters (Unicode code points) the lobby's name keeps: the engineer's answer on #214.
## At most 4 UTF-8 bytes each, so it fits the wire's `name` type (a test pins the two).
const MAX_CHARS := 20


## `raw` as the lobby's name: PlayerNames.clean_to with MAX_CHARS. "" is the default.
static func clean(raw: Variant) -> String:
	return PlayerNames.clean_to(raw, MAX_CHARS)
