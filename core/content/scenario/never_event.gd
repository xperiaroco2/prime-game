class_name NeverEvent
extends Resource
## An event that one bot, or every bot, must never receive in a BotScenario (ARCHITECTURE §9.7).
## Data only. A field that names a player (`peer`) is written as the bot's number.

@export var event: StringName
## Fields the event must match (a subset of its payload); empty matches every such event.
@export var fields := {}
## The bot that must never receive it; 0 means every bot.
@export var bot := 0
