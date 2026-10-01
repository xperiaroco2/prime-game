class_name ChannelTicks
extends TickSystem
## The tick system of the channels (ARCHITECTURE §3.3, §9.4; M4-4): every tick of the phase that
## lists it, each running channel, in actor-id order, checks its rule's conditions again (the first
## that fails stops it), then runs one more tick, and completes in the tick that reaches its time
## (Channels.advance). A phase that accepts an intent whose rule starts a channel (a ChannelEffect)
## lists it, or the mode check refuses the phase (§9.1).
##
## Emits: what the channels' effects emit when they stop or complete (the raise: RaiseStopped,
## Revived and the revived player's SelfStatus); each ChannelEffect lists its own, and the rule
## that holds it is where a review reads them. No demands.


func run(ctx: MatchContext) -> void:
	Channels.advance(ctx)
