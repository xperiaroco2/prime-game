class_name BotVoice
extends RefCounted
## When a bot's synthetic voice sends a frame (ARCHITECTURE §4.6, the M5 ADR §5): one frame per
## 20 ms of the runner's clock, 50 a second as a player's gate sends (E38), each
## LeakCheck.voice_frame (30 to 60 B, the speaker's peer id and a counter first). By default in
## talk spurts, a deterministic pattern per bot: a spurt, then a silence, each of a length of its
## own per bot and shifted per bot, so every scenario starts and stops streams at different times
## and the leak test's seq check runs across silence (the relay renumbers only what it relays);
## continuously when the scenario says so (BotScenario.voice), the load of everyone talking at once.
## Every length is a placeholder, "not a decision".

## One frame of voice, 20 ms (E38).
const FRAME_USEC := 20000
## After a hitch of the runner's clock (over ENet) at most this many frames go out at once: the
## relay keeps the newest 5 of a speaker per poll anyway.
const MAX_FRAMES_PER_STEP := 5
## Bot n's spurt lasts SPURT_FRAMES + SPURT_STEP * (n % 4) frames (0.8 to 1.7 s), its silence
## SILENCE_FRAMES + SILENCE_STEP * (n % 3) (0.3 to 0.9 s, each longer than two host ticks), and its
## cycle starts OFFSET_STEP * n frames early.
const SPURT_FRAMES := 40
const SPURT_STEP := 15
const SILENCE_FRAMES := 15
const SILENCE_STEP := 15
const OFFSET_STEP := 17


## The number of the 20 ms frame of the runner's clock at `now_usec`.
static func frame_at(now_usec: int) -> int:
	@warning_ignore("integer_division")
	return now_usec / FRAME_USEC


## Whether bot `bot` talks in frame `frame` under `voice`.
static func talks(bot: int, frame: int, voice: BotScenario.Voice) -> bool:
	if voice == BotScenario.Voice.CONTINUOUS:
		return true
	var spurt := SPURT_FRAMES + SPURT_STEP * (bot % 4)
	var cycle := spurt + SILENCE_FRAMES + SILENCE_STEP * (bot % 3)
	return posmod(frame + OFFSET_STEP * bot, cycle) < spurt


## The frames bot `bot` sends when the runner's clock moved from frame `last` to `now` under
## `voice`, in order: those after `last` up to `now` in which it talks, at most the newest
## MAX_FRAMES_PER_STEP of them.
static func frames_due(bot: int, last: int, now: int, voice: BotScenario.Voice) -> Array[int]:
	var due: Array[int] = []
	for frame in range(maxi(last + 1, now - MAX_FRAMES_PER_STEP + 1), now + 1):
		if talks(bot, frame, voice):
			due.append(frame)
	return due
