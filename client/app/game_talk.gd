class_name GameTalk
extends RefCounted
## Game's per-frame voice wiring, out of game.gd to keep it under lint's 1000 lines: whether the
## talk key counts (#488 rule 4) and the Voice panel on screen fed with the microphone's facts
## (#301, #495). The two bits of state it keeps between frames are this object's.

## The talk key was held while the keys were typing: it counts again only after one release.
var talk_blocked := false
## The Voice panel was on screen in the last frame (the device list is read again as it opens).
var panel_shown := false


## Each frame: the talk key counts, under the Esc menu too (#488 rule 4), but never while the
## keys are typing, nor after it, until the talk key has been let go once (a V that ended a typing
## or bound a key is still held, and must not key the microphone); an open Voice panel (the Esc
## menu's tab, or the main menu's page with no session, #301) shows the settings and the
## microphone's level (the device list read again as it opens); the lobby's hint and mic (#495).
func refresh(game: Game) -> void:
	var sender := game.sender()
	var control := game.voice_control()
	sender.reads_device_input = game.device_input
	var is_typing := typing(game)
	if is_typing:
		talk_blocked = true
	elif not Input.is_action_pressed(VoiceSender.TALK_ACTION):
		talk_blocked = false
	sender.listening = not is_typing and not talk_blocked
	var panel := game.shown_voice_panel()
	if panel != null and not panel_shown:
		control.refresh_devices()
	panel_shown = panel != null
	if panel != null:
		panel.show_facts(control.facts())
	game.ui.lobby_hud.show_voice_hint(control.lobby_hint())
	game.ui.lobby_hud.show_mic(sender.live())


## A text field has the focus (the Lobby tab's name, #214) or Settings > Controls captures a key:
## the keys are letters or a binding then, and V must not key the microphone.
static func typing(game: Game) -> bool:
	var focus := game.get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit or GameSettings.capturing(game)
