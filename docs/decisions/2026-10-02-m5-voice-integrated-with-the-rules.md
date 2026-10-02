# M5: voice integrated with the rules, and the M5 task split

- **Status:** Proposed (#177). The technical choices E34 to E45 and E47 are for the M5 manager session under the
  engineer's delegation (#134), which reports them; E46 changes an architecture boundary and is the engineer's; D11 to
  D15 (who hears whom and how it sounds) are the engineer's, with the designer by relay; the two stop-and-ask items
  (the addon, LFS in CI) are the engineer's. Until answered, the design proceeds with each recommendation where it can
  be reverted.
- **Date:** 2026-10-02
- **Deciders:** designed by the agent in #177 under the M5 manager session
- **Builds on:** [the voice approach](2026-09-29-voice-approach.md) (go with TwoVoIP v6.5 on Windows, the relay, the go
  thresholds), [vision revision 1](2026-10-01-vision-revision-1.md) (Voice, the life table, Hidden information),
  [the M4 client](2026-10-01-m4-first-person-client.md) (E33, D9, its §3 checklist and its shape),
  [wire format and the host session](2026-09-30-wire-format-and-host-session.md) (E7, E11),
  [Git LFS](2026-09-29-git-lfs-for-binary-assets.md), [a release branch per milestone](2026-10-01-release-branch-per-milestone.md)
- **Numbering:** the choices continue the M4 design's: **E34 to E47** and **D11 to D15**. The issues are **M5-1 to
  M5-7** (and M5-4b only if M5-4's measurement asks for it); their numbers come when the manager opens them.

## Context
M5's goal (ROADMAP, as amended by vision revision 1): proximity voice integrated with the rules, occlusion,
push-to-talk or voice activity; nobody hears the downed or the dead, and the dead hear no voice. Built before M5
(main after #167): the routing in `core/` (`VoiceRule.speakers_of` with the voice invariant; `SilentVoice`,
`ProximityVoice`, `RoundVoice`), the relay in `server/` (`VoiceRelay`: the last tick's routing, per-stream renumbering,
the host tick on each frame, the newest 5 frames per speaker per poll), E7's voice bucket (`PeerBudget`), the VOICE
lane, `ClientSession.send_voice` and `voice_received`, and the leak test's routing check for every frame. Not built:
capture, the gate, encoding, the jitter buffer, decoding, playback, the ears, occlusion, buses and volumes. `voice/`
holds only its `CLAUDE.md`. The addon is not in the repo.

What constrains the design:
- **Invariants 1, 2 and 6.** The host decides who hears whom from `core/`'s rule every tick; a client renders only the
  frames the host sent, may narrow what it plays, and never widens it. The host's own client is a normal recipient.
- **The voice invariant** (vision revision 1, M4-1): nobody hears a downed or dead speaker; a dead listener hears no
  voice; a downed listener hears the living from where they lie.
- **The leak test** changes in the PR that changes what it checks, each new check proven by a planted leak.
- **The stage's budget:** set by the engineer once the first wave's usage is seen (#190 holds it; a budget is moving
  state). The split is sized by reviewable PRs (at most about 1500 changed lines) and at most three tasks at once.
- **The humans** write no code; agents open no window, use no microphone and download nothing; audio files, the
  addon's download and the listening tests are the engineer's steps. The game targets Windows; CI runs on Linux.
- **A hobby project:** no anti-cheat or privacy hardening beyond the invariants (root `CLAUDE.md`).

Checked for this design on 2026-10-02, live rather than from memory:
- In the 4.7.2 API dump (`tools/out/godot-api/4.7.2/extension_api.json`): `AudioServer.input_device`,
  `get_input_device_list`, `set_input_device_active`, `get_input_frames_available`, `get_input_frames`,
  `get_input_mix_rate`, `get_input_buffer_length_frames`, `get_output_latency`, `add_bus`, `set_bus_name`,
  `set_bus_send`, `set_bus_volume_db`, `get_bus_peak_volume_left_db`; `AudioStreamPlayer3D.attenuation_model`
  (`ATTENUATION_DISABLED` = 3), `max_distance`, `attenuation_filter_cutoff_hz`, `attenuation_filter_db`, `bus`,
  `volume_db`; `AudioListener3D.make_current`; `AudioEffectLowPassFilter` (`AudioEffectFilter.cutoff_hz`);
  `AudioStreamGenerator`, `AudioStreamGeneratorPlayback.push_buffer`; `ClassDB.class_exists`, `ClassDB.instantiate`;
  `GDExtensionManager.is_extension_loaded`; `ConfigFile`; `ENetConnection.pop_statistic` (`HOST_TOTAL_SENT_DATA`,
  `HOST_TOTAL_SENT_PACKETS`); `PhysicsRayQueryParameters3D.create`. **Not** in it: any call that reports a
  microphone's channel count (`AudioServer.get_input_channel_count` does not exist).
- The addon's classes are not in the engine dump. As used in the M1 spike (`git show
  origin/voice/16-m1-spike-measure-voice-latency-cpu-cost:spike/voice/<file>`): `TwovoipOpusEncoder` with
  `initialize(input_rate, 48000, 1, DENOISER_RNNOISE or DENOISER_DISABLED, AGC_DISABLED, 960)`,
  `create_opus_encoder(24000, 5, true)`, `get_required_input_chunk_size()`, `process_chunk(frames)`, `get_peak()`,
  `encode_chunk(PackedByteArray())` (`voice_source.gd`); `AudioStreamOpus` with `set_opus_sample_rate`,
  `set_opus_channels`, and its playback `AudioStreamPlaybackOpus` with `push_opus_packet(packet, 0, fec)`,
  `mark_end_opus_stream(bool)`, `queue_length_frames()`, `available_space_frames()` (`voice_speaker.gd`), `start()`,
  `get_skips(overflow)` (`codec_roundtrip.gd`, `loopback.gd`). #12's handoff: v6.5's `encode_chunk` takes one
  argument and `push_opus_packet` returns nothing; the addon's own helper scripts are untyped and fail the warnings
  policy, so only the `.gdextension` and its libraries are installed. `spike/voice/fetch-twovoip.ps1` names the asset
  URL and the archive's layout (`project\addons\twovoip\`). TwoVoIP's README (read on github.com) names no DTX setting.
- Godot 4.7.2's source (tag `4.7.2-stable`, read on github.com): with a `.gdextension` and no library for the platform,
  `ERR_PRINT("No GDExtension library found for current OS and architecture (%s) in configuration file: %s")`
  (`core/extension/gdextension_library_loader.cpp`); a listed library that is missing or fails to open,
  `ERR_FAIL_COND_V_MSG(... "Can't open dynamic library, file not found: '%s'.")` or `ERR_FAIL_NULL_V_MSG(... "Can't
  open dynamic library: %s. Error: %s.")` (`drivers/unix/os_unix.cpp`). Each prints an `ERROR:` line.
- The runner: `launch.ERROR_RE` (`^(?:USER )?(?:SCRIPT |SHADER )?ERROR: `) fails `run` on any engine error line, so
  `verify`'s `enet`, `freeze`, `stall`, `bots` and `bots-enet` steps, and `game` through `hostjoin`'s use of
  `launch.error_lines`; `check` judges the import's exit code and `check_project.gd`'s own logger, `test` GdUnit4's exit
  code and `results.xml`. CI checks out with `lfs: false`; `.gitattributes` routes `*.ogg` and `*.wav` through LFS and
  keeps `addons/**` out of it. `launch.MAX_INSTANCES` is 8.
- The code: the bots send one synthetic frame per client tick (20 a second) of 8 to 14 bytes (`NetPlay._speak`,
  `LeakCheck.voice_frame`); `RecordingWorldQuery` appends every answer to the command log; `speakers_for` is called by
  `HostSession` after each tick and again by `Match._record_views` with `keep_history`; no client code saves user
  settings yet; `LiftMusic` plays at −14 dB on the Master bus.

## Decision

### 1. The voice path, end to end

| Stage | Where | What it does | The failure it prevents |
|---|---|---|---|
| Capture | `voice/` `VoiceCapture`; opened by `client/app/` | the device the player picked, 20 ms chunks from the 4.7 microphone API (E36) | a 4-channel laptop array freezing the game at every start (#22) |
| Gate | `voice/` `VoiceGate` (pure) | push-to-talk or voice activity; sends nothing in silence, nothing while its `may_speak` input is false (E37) | a silent player's steady stream showing where they are; bandwidth and decodes for nothing |
| The sender | `client/voice/` `VoiceSender` | wires capture, encoder and gate to `ClientSession.send_voice`; decides `may_speak` from the own life fold and the phase's `hearing_radius_m()` (nothing while downed or dead, nothing in a silent phase) | `voice/` reading the life fold or core state, where the E18 boundary test does not look (invariant 2) |
| Encode | `voice/` `VoiceCodec`, `TwoVoipCodec` | 48 kHz mono Opus, 20 ms, 24 kbit/s, complexity 5, RNNoise on by default (E34, E38) | a script naming an addon class failing to parse where the addon is absent |
| Send, relay | `ClientSession.send_voice`, `server/VoiceRelay`, `core/` `VoiceRule` (as built) | the host routes each frame by the last tick's routing, renumbers per stream, stamps the tick, never decodes | a client hearing what it is not entitled to (invariant 2) |
| Receive | `client/world/` `VoiceViews` | plays only `voice_received` frames, for a speaker with a `RemotePlayerBody`, never while the own player is dead (§3) | a dead spectator hearing voice; a frame played for a player not drawn |
| Jitter buffer | `voice/` `VoiceJitter` (pure) | reorder, conceal or FEC, an adaptive prebuffer, talk spurts, fade and flush (E39) | the spike's fixed 60 ms underrunning over Wi-Fi |
| Decode, play | `voice/` `VoiceSpeaker` on the speaker's `RemotePlayerBody` | an `AudioStreamPlayer3D` at mouth height, bus Voice, `max_distance` the phase's cutoff (E40, E41, D12) | a fade that ends somewhere else than the host's cutoff |
| The ears | `client/life/` `Ears` | an `AudioListener3D` at the own eye, the own body, or the spectated target's eye or body (E40) | a downed player hearing from the camera behind and above them, over the cover the body lies behind |
| Occlusion | `client/world/` `VoiceViews`, `WorldSounds` | one ray from the ears; behind the level a voice or a world sound is muffled (E42, D13) | a wall that sounds like air |

**1.1 Capture** (E36). `VoiceCapture` reads the 4.7 `AudioServer` input API the spike used: the device list, the
chosen `input_device`, `set_input_device_active`, then every frame as many 20 ms chunks as `get_input_frames_available`
holds. The encoder resamples the device's rate (`get_input_mix_rate`) to 48 kHz and encodes mono from Godot's stereo
frames, as in the spike; a device at 44.1 kHz costs about 400 µs more per frame, so the Voice tab advises 48 kHz.
`project.godot` turns on `audio/driver/enable_input`, which the spike set in `override.cfg` (#12); the PR that adds it
shows the headless runs print no new error line. Headless runs use the Dummy driver, so they cannot show whether
WASAPI on 4.7.2 touches the default capture device at startup once input is enabled: before M5-6 merges, the engineer
starts the game windowed on the #22 laptop with input enabled and no device picked (§6), expecting no freeze and no
`WASAPI` channel-count line. **The fallback** if it freezes: `project.godot` keeps input off, and `VoiceCapture`
turns it on through `override.cfg` (the spike's way) only after the player picks a device, at the next start. **The microphone stays off until the player picks a device** in the
Voice tab; the choice is remembered (§1.7). Godot 4.7.2 freezes on a microphone with more than two channels and cannot
tell the channel count beforehand, so before opening a device `VoiceCapture` writes an "opening" mark to the settings
and clears it after the first second of samples: at the next start a mark still set means the last opening never
finished (the game froze or was killed), and the device is not opened again until the player picks it, with a line
that names #22 and advises a headset. Windows' microphone privacy refusing the device shows the error
`set_input_device_active` returns. Echo cancellation is not built: a player on loudspeakers sends the others' voices
back through their microphone, so the Voice tab advises headphones, and push-to-talk is the default (D11).

**1.2 The gate** (E37). While the microphone is open every 20 ms chunk is encoded, so Opus's and RNNoise's state stay
continuous, and `VoiceGate` decides per chunk whether its frame is sent:
- **Push-to-talk:** while `voice_talk` (V, D11) is held, with no Esc menu open (the menu already releases the keys
  held when it opened, #169).
- **Voice activity:** while the chunk's peak is over the threshold (a slider with a live meter, D11), and for a
  hangover of 300 ms after it falls below (a placeholder, "not a decision").
- **Pre-roll:** when the gate opens, the 2 frames before go out first, so the first syllable is not cut. Pre-roll and
  the current frame make at most 3 frames in one send, under the relay's newest 5 per poll. The pre-roll ring is
  emptied whenever `may_speak` is false, so it only ever holds frames captured while the player could be heard: a
  downed player whispering with V held while being raised sends nothing of it when the revive lands, and nothing
  recorded in Loading or End opens the next phase. A gate test covers it (`may_speak` false then true with the key
  held sends no frame captured before the change), seen failing on a plant.
- **Never:** while the own player is downed or dead (nobody hears them by the voice invariant), or in a phase whose
  voice rule hears nobody (`hearing_radius_m()` 0 in the client's own mode: Loading and End). Not sending narrows
  nothing: the host would route none of them anyway. `VoiceGate` only takes `may_speak` as an input; `client/`'s
  `VoiceSender` (`client/voice/`) decides it from the own life fold and the client's own mode, never from `Match` or
  `MatchState` (the host's own client included, invariant 2), so `voice/` stays plumbing that reads no game state.
  M5-2 extends the E18 boundary test (`tests/unit/client/app/client_boundary_test.gd`) so its forbidden names also
  apply to `res://voice`, seen failing on a planted read.
- The level is the peak of the raw chunk, computed in `VoiceGate` (pure, so a test feeds it silence and a sine), not
  the addon's `get_peak()`. Both are measured before noise suppression, so a loud fan can hold voice activity open;
  the addon PR checks whether v6.5 offers RNNoise's speech probability (TwoVoIP's current README names
  `get_speech_probability()`), which voice activity could then use instead. RNNoise is on by default (the spike's
  setting, which the engineer listened to) and a toggle turns it off (−23 ms, encoding 4.6 times cheaper). Opus DTX is not used: the gate already sends nothing in silence,
  and the spike never showed v6.5 exposing it.

**1.3 The codec boundary** (E34). `voice/` holds `VoiceCodec` (`available()`, `new_encoder()`, a stream for an
`AudioStreamPlayer3D`, and a `VoicePlayback` over that player's playback), `VoiceEncoder` (`start(input_rate, denoise)`
with an error text, `encode(chunk) -> PackedByteArray`) and `VoicePlayback` (`push(frame, conceal)`, `queued_frames()`,
`free_frames()`, `set_running(on)`, `flush()`). `TwoVoipCodec` reaches the addon only by class name:
`ClassDB.class_exists(&"TwovoipOpusEncoder")`, `ClassDB.instantiate`, and `Object.call` on the result with typed casts,
so no script in the project names a TwoVoIP class and every script parses with or without the addon. `flush()` stops
and plays the player again for a fresh playback (the spike shows no clear call; the addon PR checks it). Without the
addon `available()` is false and the game runs with voice unavailable: the Voice tab says so, nothing is captured or
played. **Tests never load the addon or open a microphone:** a fake codec in `tests/fixtures/voice/` (8 kHz µ-law
frames of 160 bytes, played through an `AudioStreamGenerator`) stands in for it in headless tests, and `VoiceGate` and
`VoiceJitter` are pure. The real codec's round trip (a sine encoded, decoded and measured, as the spike's
`codec_roundtrip.gd`) is a headless script that the addon's PR, and any later codec change, runs on Windows with
`tools\run.cmd run <script> --headless`; it prints SKIP where the addon is absent and is not a `verify` step.
**FEC:** whether v6.5 turns on Opus in-band FEC is unknown. The jitter buffer asks for `push_opus_packet(next, 0, 1)`
for a single missing frame as the spike did, which is FEC when the data is there and concealment otherwise; the addon
PR's round trip drops one frame and compares both ways against the original and records which it is.

**1.4 The jitter buffer** (E39). `VoiceJitter`, one per speaker on the listener, pure, fed `(seq, tick, frame,
arrival_usec)` and asked every frame what to decode, given the decoded audio queued. On main
`ClientSession.voice_received(speaker, tick, opus)` drops the `VoiceDown`'s seq, so M5-5 changes it to
`voice_received(speaker, seq, tick, opus)`, with its callers and tests (#155 edits the same file and merges first):
- **Order:** by the stream's seq, which the host renumbers per speaker and listener and which runs on across talk
  spurts (the relay renumbers only what it relays). A duplicate or a frame older than the next due is dropped. A
  missing frame is waited for until the queue would run dry before it, then decoded from the next packet with
  `conceal` (FEC or concealment, §1.3); two or more missing in a row are concealed once and skipped. A frame
  missing across a stop (the last of a spurt) is skipped, not concealed at the start of the next spurt.
- **Start and stop:** playback starts (`set_running(true)`) when the queue reaches the prebuffer, and stops when the
  queue runs dry with nothing pending: a talk spurt ended, or an underrun. The next frame starts again with a fresh
  prebuffer. The spike's reset on a jump of 25 seqs would never fire now, since the renumbered seqs have no gaps across
  silence.
- **Adaptive prebuffer:** at each start, the spread of the arrival offsets within each talk spurt (a frame's arrival
  against its spurt's first frame plus 20 ms per frame since) over the last 2 s of that stream's frames, plus 20 ms,
  within 40 to 120 ms (placeholders, "not a decision"); a silence between spurts is not jitter. Arrivals are stamped when
  `ClientSession` polls, once per frame, so a low frame rate widens the spread and the prebuffer follows it. No
  time-stretching within a spurt: TwoVoIP offers no resampler per stream.
- **Fade and flush:** when a speaker must not be heard any more (below), its player fades over 50 ms and its queue
  is flushed, so the 60 to 120 ms already queued do not play on at the last gain (the spike measured them 2.7 m past
  the cutoff, at −46 dB). A flush also empties the frames pending below the prebuffer, and pending frames that have
  not started playback within 200 ms (a placeholder, "not a decision") are discarded, so old speech never waits in
  the buffer to play in front of the speaker's next spurt.
- Tests with synthetic frames: silence, a sine, 3% loss, reordering by up to 2 frames, duplicates, a burst after a
  stall, spurts with gaps of 0.1 to 5 s, arrivals with 0, 30 and 80 ms of jitter (the prebuffer then lies near 40, 50
  and 100 ms, and underruns stay under a bound the test pins).

**1.5 Playback, the ears and the falloff** (E40, E41, D12).
- **One `AudioStreamPlayer3D` per remote speaker** (`VoiceSpeaker`), a child of its `RemotePlayerBody` at mouth height
  (eye height − 0.1 m, a placeholder), on the Voice bus, created at its first frame and freed with the body: a dead
  player has no avatar and so no player. Its `attenuation_model` is `ATTENUATION_DISABLED` and its `max_distance` the
  current phase's `hearing_radius_m()` from the client's own mode (E41), which `client/`'s `VoiceViews` sets (the
speaker never reads the phase itself), and which Godot documents as linear attenuation
  clamped to a sphere: the voice fades to silence where the host stops delivering (D12). 3D, as the host measures.
- **What a listener hears near the edge:** at 7 m of 8 a voice is at one eighth of its amplitude (−18 dB), at 8 m
  silent. The host measures feet to feet between the last accepted positions, the client ears to mouth between
  interpolated ones a tick or so behind: they differ by a few tenths of a metre (up to about a metre more for a downed
  listener, whose ears lie near the floor), which matters only at the edge, at near-silence. Crossing out, the host
  stops at the next tick and the client fades and flushes once its own distance passes `max_distance`; crossing in,
  the first frames start under a prebuffer at near-zero gain, with no pop.
- **The ears** (`client/life/` `Ears`, an `AudioListener3D` made current): the own eye (living), the own body's head
  where it lies (downed: vision revision 1's "from where they lie", not the downed camera up to 2 m behind and 1.6 m
  above), the target's eye (spectating a living target), the target's body (a downed target). The dead hear no voice,
  so their ears serve the world sounds around their target (V11). The world-sound chooser measures its 12 m from the
  ears too: E33's "the listener's camera" becomes "the ears", a shift of at most about 2.5 m for the downed.
- **What `VoiceViews` plays** (§3): only frames of `ClientSession.voice_received`; nothing for a speaker without a
  `RemotePlayerBody`; nothing while the own life fold is dead (and every speaker flushed at the own `Died`); a speaker
  whose life fold turns downed, dead or left is faded and flushed at once; entering a phase whose rule hears nobody
  flushes every speaker; a speaker past `max_distance` from the ears is faded and flushed. **Late frames:** voice
  travels on the unreliable unordered VOICE lane and events on a reliable one, and ENet orders nothing across
  channels, so a frame stamped before a knockdown can arrive after the client folded `KnockedDown`. `VoiceViews`
  therefore drops every frame of a speaker whose life fold is not living (or who left) and every frame while the
  current phase's `hearing_radius_m()` is 0, not only at the event; and at each flush it records the newest host tick
  the client has seen, then drops that speaker's frames stamped at or below it (E11's tick is there for this).

**1.6 Occlusion** (E42, D13). Recommended (D13 (a)): the listener decides how a wall sounds, the host's routing stays
distance only. `VoiceViews` casts one ray per audible speaker per physics frame from the ears to the speaker's mouth
against the world layer of the client's own level (as `SightHider` does for sight), at most 9 rays a frame; a hit
muffles that speaker (quieter and duller: D13's numbers), eased over 100 ms so a door jamb's edge does not click.
`WorldSounds` casts one ray from the ears to a sound's position when it starts and muffles it the same way; E33's 12 m
range stays. How the muffle is made, the player's own `attenuation_filter_cutoff_hz` and `volume_db` or a muffled bus
with an `AudioEffectLowPassFilter`, the PR decides by a headless measurement of the Voice bus's peak under the Dummy
driver, which mixes (#15). **Drop first** if the budget runs out: anything beyond this one ray (several rays,
thickness, portals) is not built. If the engineer picks D13 (b), the host's routing changes as E42 (b) says, inside
M5-1.

**1.7 Buses, settings and the Voice tab** (E43, D15). `client/audio/` `AudioBuses` makes the buses Voice, World and
Music, sending to Master, when the game starts (tests make them the same way): voice players on Voice, `WorldSounds` on
World, `LiftMusic` on Music (its −14 dB moves to the bus default). `client/app/` `UserSettings` keeps the microphone,
the mode, the threshold, RNNoise and the three volumes in `user://settings.cfg` (`ConfigFile`), read at the start and
written on each change. All windows that `tools\run.cmd host --clients N` starts share one `user://` folder (the runner
sets only `PRIME_INSTANCE`), so the file is `user://settings.cfg` when `PRIME_INSTANCE` is unset or 1 and
`user://settings_<n>.cfg` otherwise, and §1.1's "opening" mark lives in that same per-instance file: three windows on
one PC then neither overwrite each other's choices nor read each other's mark (a unit test covers the file name; no
runner change, so E47 holds). The Esc menu (#169) gains a tab, Voice, in every screen: the microphone (Off and the devices),
push-to-talk or voice activity, the key shown, the threshold with a live meter, RNNoise, the three volume sliders, and
the line that says voice is unavailable without the addon. It is built with the shared greybox theme
(`client/ui/theme/game_theme.tres`); its look is #150's.

**1.8 World sounds and the lift music.** M4's placeholders stay until the engineer's CC0 files arrive (D9 (a)):
`WorldSounds`' blips for `Swung`, `ItemPickedUp` and `ItemPlaced`, and `LiftMusic.placeholder_stream()`. The files go
to `client/audio/sounds/swing.ogg`, `pick_up.ogg`, `put_down.ogg` and `client/audio/music/lift_music.ogg` (`.ogg` or
`.wav`; both go through LFS), each with a `docs/credits/` entry that the agent writes from the author, source and
license the engineer gives; the music loops through its import settings. They are the first LFS assets outside
`addons/`, so LFS in CI is decided first (the stop-and-ask below). The world sounds go to the World bus, measure from
the ears and are muffled by occlusion (§1.6).

### 2. The addon in the repo, and CI on Linux
**The engineer's step** (a stop-and-ask, the voice ADR's "What follows"): download TwoVoIP **v6.5**, check its SHA-256,
copy the `.gdextension`, its `.uid`, its license and the Windows libraries into `addons/twovoip/`, and run `check` (the
commands are in §6). `addons/**` stays out of LFS, so the libraries are plain git files like GdUnit4's. The agent in
M5-3 then commits them and runs the round trip (§1.3) and `verify`, and writes `docs/credits/twovoip.md` (author,
source URL, v6.5, the license, and the licenses of the bundled Opus and RNNoise libraries the archive names) and
regenerates `CREDITS.md` with `tools\run.cmd credits`, as GdUnit4 did (`docs/credits/gdunit4.md`). v6.6 or later only after
goatchurchprime/two-voip-godot-4#107 is fixed and `check` passes with it.

**What Godot prints on Linux when it loads a `.gdextension`** (from the 4.7.2 source above; the addon PR's CI run on its
branch shows it before anything merges):

| Case | Godot prints | What `verify` does |
|---|---|---|
| No Linux entry in the `.gdextension` | `ERROR: No GDExtension library found for current OS and architecture (...)` | `enet`, `freeze`, `stall`, `bots`, `bots-enet` and `game` fail on the `ERROR:` line; whether `check` and `test` fail is not known (they judge exit codes and their own loggers) |
| A Linux entry, its file not committed | `ERROR: Can't open dynamic library, file not found: '...'` | the same |
| The Linux file committed, failing to load (a missing library, another glibc) | `ERROR: Can't open dynamic library: ... Error: ...` | the same |
| The Linux file loads | nothing (v6.5 on Linux is untested) | green, if the extension also behaves headless |

**The plan** (E35 (a)): commit the Windows libraries only, the `.gdextension` as shipped, and one CI step that removes
`addons/twovoip/` before `verify`. CI then runs the game without the addon, which E34 (a) makes a normal state: no
script names an addon class, tests never load it, and voice is unavailable. `verify`'s clean-tree check compares the
tree before and after its steps, so a folder removed before it does not count. CI stays green whether or not a Linux
binary would load, and Windows `verify` (every agent's and the engineer's, and `publish`'s) runs with the addon, which
covers the import and `check` where the game runs. **If the Linux library is wanted later** (a Linux player), the
fallback order is: commit the Linux libraries on a branch, see CI load them, then drop the CI step; if they fail, keep
the step, and Linux players have no voice.

### 3. What the client renders, and what it may not (M5's review checklist)
Each M5 client PR is reviewed against this list by `netcode-security-reviewer` as well as `code-reviewer`, besides the
M4 list (the M4 ADR §3):
1. Only frames that `ClientSession.voice_received` delivered are decoded and played; none for a speaker with no
   `RemotePlayerBody`; the client never plays a voice from anything else.
2. A dead own player plays no voice, even if a frame arrives: frames are dropped while the own life fold is dead,
   and every speaker is flushed at the own `Died`.
3. A speaker whose life fold turns downed, dead or left is faded (≤ 50 ms) and flushed at once; a phase whose voice
   rule hears nobody flushes every speaker; a speaker past `max_distance` from the ears is flushed. Frames that
   arrive late are dropped too: any frame of a speaker whose life fold is not living, any frame in a phase whose rule
   hears nobody, and any frame stamped at or below the tick recorded at that speaker's flush (§1.5).
4. The ears are the own eye, the own body's head when downed, a living target's eye or a downed target's body when
   spectating; never the downed camera's arm.
5. `max_distance` is the current phase's `hearing_radius_m()` from the client's own mode; no radius is copied into
   client tuning.
6. The microphone sends nothing in silence (the gate), nothing while the own player is downed or dead, nothing in a
   phase whose rule hears nobody.
7. The own transmit icon shows only what the own gate does; nothing tells a speaker who hears it (the host never
   sends it).
8. A remote talking indicator, if built (D14), shows only while that speaker's audio plays, drawn in the world,
   depth-tested and hidden with its avatar (`SightHider.GROUP`); no screen lists who is talking.
9. Muffling uses the client's own level and the interpolated poses only.
10. World sounds play within the hearing range of the ears and are muffled by the same ray.
11. Voice statistics on the F3 overlay exist in debug builds only (E47).

**Host trust:** a client sends `VoiceUp` frames only, never a routing claim; the host relays along `core/`'s routing,
drops frames of a peer that is not a present player, bounds the rate (E7) and never decodes. A client that ignores
the gate costs its own bucket and reveals only itself.

### 4. Wire budgets
No wire change in M5 unless M5-4's measurement asks for it (E44). The numbers, with a 45-byte Opus frame (the spike's
speech mean is 48.7 B at 24 kbit/s, 25.5 B in silence, peaks to 67 B):

| Quantity | Value | Basis |
|---|---|---|
| `VoiceUp` payload / `VoiceDown` payload | 49 B / 57 B | §4.3's fields: seq 2, length 2, frame 45; speaker 4, seq 2, tick 4, length 2, frame 45 |
| One `VoiceDown` on the wire | about 108 B: 57 + 3 (frame header) + about 20 (ENet and Godot, the spike's measured difference) + 28 (IP and UDP) | #15, #16 |
| One stream | about 43 kbit/s (50 frames a second) | |
| Host upload, 10 players all talking and hearing each other | 81 streams on the wire (the host's own client listens over the loopback): about 3.5 Mbit/s, plus 0.6 Mbit/s of snapshots, about 4.1 Mbit/s; about 4.8 with every frame at the 67 B peak | against the 5 Mbit/s threshold |
| Host upload with the gate, 2 talkers heard by everyone | at most 18 streams: about 0.8 Mbit/s, plus snapshots | |
| Host download | 9 remote speakers: about 0.4 Mbit/s | |
| Host sends per 20 ms at 81 streams | 81: 0.8 ms at 10 µs each, 9 to 13.5 ms (45 to 68% of a core) at the spike's unexplained 111 to 167 µs | M5-4 measures it |

- **E7's voice bucket** (500 frames, 50 a second) holds for 20 ms frames: a talker spends what the bucket refills, so it
  stays where it is; 500 frames are 10 s of burst, so a thawed 5 s backlog (250 frames) passes and the relay's newest 5
  per poll drops its old part; pre-roll adds 2 frames per spurt; an audio clock 0.1% fast drains 0.05 frames a second.
  10 ms frames would spend 100 a second and empty the bucket after 10 s of talk (E38).
- **The relay's newest 5 per poll** (100 ms): at 60 polls a second a talker's frames come 1 or 2 per poll, 3 at a
  spurt's start with pre-roll, 5 after a 100 ms client hitch. It stays.
- **E11's tick** stays on every frame: the leak test checks each frame against that tick's routing and, from M5-1, the
  distance at that tick (§5).
- **The measurement** (M5-4, headless, one PC): a scenario `voice_load` with 8 bots (`launch.MAX_INSTANCES`) standing
  within the lobby's 8 m, each sending 50 synthetic frames a second of 30 to 60 B, continuously for 30 s, then with 2
  talkers for 30 s: `tools\run.cmd bots voice_load --instances 8`. The host (instance 1) prints, from debug counters:
  frames relayed and sent, the time spent in the relay's flush and sends (`Time.get_ticks_usec`), and the ENet upload
  in bytes and packets (`ENetConnection.pop_statistic`), voice and snapshots apart. 8 players give 49 streams on the
  wire; the 10-player figure is scaled to 81. Eight processes on one PC share its cores, so the per-send time is an
  upper bound; the humans' two-machine test reads the host's counters on the F3 overlay.
- **Batching** (M5-4b, only if needed): if the relay's time at 81 streams exceeds 2 ms per 20 ms (10% of a core) or
  the host's upload 4.5 Mbit/s (placeholders, "not a decision"), a new row sends one packet per listener per poll with
  that poll's frames for it (`tick`, then per frame `speaker`, `seq`, `opus`), under the 1024-byte unreliable cap,
  with a version bump, its codec samples and the leak test decoding it; `ClientSession` emits `voice_received` per
  frame with its seq. At 81 streams it cuts the sends from 81 to 9
  per 20 ms and the upload by about 40 B per frame.

### 5. The leak test and the rendering tests for M5
| Issue | Checks | Planted leak |
|---|---|---|
| M5-1 | **The distance invariant**, written apart from `VoiceRule.hears`: no peer decodes a frame of a speaker farther than the phase's `hearing_radius_m()` at the frame's tick, in 3D between the last accepted positions that `LeakCheck.record_tick` now records (also in `ScenarioInvariants` per tick on `speakers_for`). A scenario where two bots talk 10 m apart, then walk within the radius (`voice_beyond_the_radius`). The bots' synthetic voice at 50 frames a second, 30 to 60 B, in talk spurts by default (continuous in `voice_load`), so every scenario starts and stops streams and the seq check runs across silence | `RoundVoice.hears` ignoring its radius: the routing subset check passes it (view_of reads the same rule), the distance invariant fails |
| M5-4b, if built | The batched row decoded and each frame in it checked as a `VoiceDown` (routing, distance, the voice invariant, bytes unchanged, seqs) | the relay batching a frame to a listener whose routing lacks the speaker |
| M5-5 | Client tests, not the wire: `VoiceViews` plays nothing while the own life is dead, flushes a speaker at its `KnockedDown`, plays nothing of a frame delivered after `KnockedDown` (stamped before it), plays nothing for a speaker without a body; the ears sit at the body while downed | each rule removed in turn (the dead check, the flush, the late-frame drop, the ears left at the camera), seen failing |
| M5-6 | The gate sends nothing in silence, while downed or dead, or in a silent phase (pure tests) | the downed check removed, seen failing |

The voice invariant's checks (M4-1, M4-2), the lurker's (no `VoiceDown` before a `Hello`), the bytes-unchanged check
and the renumbering check stay as built.

### 6. Testing M5
- **Headless, every PR** (`tools\run.cmd verify`, CI): `VoiceGate` and `VoiceJitter` with synthetic frames; the fake
  codec through `VoiceSpeaker` and real `AudioStreamPlayer3D`s and buses under the Dummy driver (the bus peak falls
  with distance, is zero past `max_distance`, drops with the muffle, and goes to zero within the fade after a flush);
  `VoiceViews`' rules over a `ClientModel`; `UserSettings` round trips under `user://`; the bots with spurts and the
  distance invariant over the loopback and over ENet. Agents run `run`, `host` and `join` with `--headless` only.
- **On Windows, not in CI:** the TwoVoIP round trip (§1.3) in the addon's PR and in any PR that changes the codec
  adapter.
- **`shot`:** the Voice tab (`client/dev/esc_voice_preview.tscn`), the HUD's transmit icon, the talking indicator over
  an avatar (D14), and the F3 overlay's Voice section, each fed by fake data.
- **The playtest worktree** on each PC, as in M4 (the M4 ADR §6), once:
  ```powershell
  cd D:\prime-game
  git fetch origin
  git worktree add D:\prime-game\.claude\worktrees\playtest-m5 --detach origin/release/m5
  ```
  Before each test:
  ```powershell
  cd D:\prime-game\.claude\worktrees\playtest-m5
  git fetch origin
  git switch --detach origin/release/m5
  ```
  After M5: `git worktree remove D:\prime-game\.claude\worktrees\playtest-m5`, from `D:\prime-game`.
- **The addon download** (the engineer, in M5-3's worktree after the manager's `start` and before M5-3's workflow
  launches, so the files are there when the agent starts; `<n>` is M5-3's issue number):
  ```powershell
  cd D:\prime-game\.claude\worktrees\<n>
  $Zip = "$env:TEMP\TwoVoIP-v6.5.zip"
  $Tmp = "$env:TEMP\TwoVoIP-v6.5"
  Invoke-WebRequest -Uri 'https://github.com/goatchurchprime/two-voip-godot-4/releases/download/v6.5/TwoVoIP.zip' -OutFile $Zip -UseBasicParsing
  (Get-FileHash $Zip -Algorithm SHA256).Hash.ToLower()
  ```
  It must print `811ac96d4b75314f90855e3136f9939f7a4bc4a01e51850640cff967afc20fc7` (the voice ADR); stop otherwise.
  ```powershell
  Expand-Archive -Path $Zip -DestinationPath $Tmp -Force
  New-Item -ItemType Directory -Force addons\twovoip\libs
  Copy-Item "$Tmp\project\addons\twovoip\twovoip.gdextension", "$Tmp\project\addons\twovoip\twovoip.gdextension.uid" addons\twovoip\
  Copy-Item "$Tmp\project\addons\twovoip\libs\*windows*" addons\twovoip\libs\
  Get-ChildItem -Recurse -Filter "LICENSE*" $Tmp
  ```
  Copy the license file the last line finds into `addons\twovoip\`, run `tools\run.cmd check`, and tell the manager,
  who then launches M5-3: its agent commits the files (they stay untracked until then).
- **Input enabled on the #22 laptop** (the engineer, on M5-6's branch before it merges; §1.1): on the laptop whose
  4-channel array 4.7.2 cannot read, in the playtest worktree on M5-6's pushed branch (`<branch>` as its PR names it):
  ```powershell
  cd D:\prime-game\.claude\worktrees\playtest-m5
  git fetch origin
  git switch --detach origin/<branch>
  tools\run.cmd host --seconds 30
  ```
  With no microphone picked (a fresh `user://`), the window must not freeze and the log under `tools\out\logs\` must
  hold no `WASAPI` line about the channel count. If it freezes, M5-6 takes §1.1's fallback.
- **The one-PC listening test** (the engineer, headphones on; after M5-6), in the playtest worktree:
  ```powershell
  cd D:\prime-game\.claude\worktrees\playtest-m5
  tools\run.cmd host --clients 2
  ```
  Three windows, each keeping its own settings (`settings.cfg`, `settings_2.cfg`, `settings_3.cfg`, §1.7). Window 1:
  Esc → Voice → the USB microphone, push-to-talk. Window 2: the source "test tone" (debug
  builds). Windows 1 and 2: "mute this window" (debug builds, not saved), so only window 3 is heard. Checks: the tone and
  the voice come from their avatars' directions and fade to silence at 8 m, with no pop at the edge; push-to-talk sends
  only while V is held, voice activity follows the meter; a player knocked down falls silent at once, and while window 3
  is downed it hears from its body; while window 3 is dead it hears no voice, but the world sounds around its target
  and the music; behind a wall a voice is muffled (after M5-7); the Voice, World and Music sliders; the F3 Voice
  section (queues, losses, underruns); the settings survive a restart.
- **The two-machine test** (#21's setup; after M5-6, again at M5's end): on the host PC `tools\run.cmd host`, on the
  other `tools\run.cmd join <the host's address>`, both in the playtest worktree on the same commit (`git rev-parse
  --short HEAD`). The laptop's microphone does not work under 4.7.2 (#22): a headset microphone, or the test tone.
  Besides the one-PC list: voice over Wi-Fi without stutter (the F3 underruns), and the device advice of the voice ADR
  (headphones, Windows enhancements off, 48 kHz, with and without Discord).
- **Latency and CPU against the go thresholds**, read from the F3 Voice section on both machines: the game's own path
  ≈ the speaker's frame age at encoding + half of each machine's round trip to the host + the listener's reorder wait
  and playback queue + `AudioServer.get_output_latency()` + 23 ms with RNNoise: at most 200 ms on one machine and over
  the LAN. CPU for 10 talkers ≈ (encode µs + 9 × decode µs) / 20 000 on the laptop: at most 15% of a core. The host's
  upload: M5-4's figure and the overlay's counter, at most 5 Mbit/s. The engineer writes the numbers on M5's plan issue.
- **The CC0 files** (#144, #145; any time, after the LFS-in-CI answer): the engineer copies them to the paths of §1.8 in
  that task's worktree and gives the agent each file's author, source and license:
  ```powershell
  cd D:\prime-game\.claude\worktrees\<n>
  New-Item -ItemType Directory -Force client\audio\sounds, client\audio\music
  Copy-Item <the swing file> client\audio\sounds\swing.ogg
  Copy-Item <the pick-up file> client\audio\sounds\pick_up.ogg
  Copy-Item <the put-down file> client\audio\sounds\put_down.ogg
  Copy-Item <the music file> client\audio\music\lift_music.ogg
  ```

### 7. The split
Seven issues, and M5-4b only if M5-4 asks for it. The full text of each (goal, acceptance criteria, out of scope,
files, dependencies, size, effort) is in the handoff on #177. Not in M5: NAT traversal (M6); radios, role abilities and
items that change voice (M7+); masks with a mouth (#73); the UI's look (#150); echo cancellation beyond the advice;
per-player mute.

| # | Title | Depends on | May run beside | Protocol | Effort | Size |
|---|---|---|---|---|---|---|
| M5-1 | core: the cutoff for the client, the distance invariant in the leak test, bots that talk in spurts | the answers (D13) | M5-2, M5-3 | no | xhigh | ~900 (~1500 with D13 (b)) |
| M5-2 | voice: the codec boundary, the gate and the jitter buffer, tested without the addon | E34, E37, E39 | M5-1, M5-3 | no | high | ~1300 |
| M5-3 | voice: TwoVoIP v6.5 in `addons/`, and CI without it (the engineer present) | the engineer's yes and download | M5-1, M5-2 | no | high | ~150 and the libraries |
| M5-4 | server: measure the host's voice relay cost and upload with bots | M5-1 | M5-5 | no | high | ~500 |
| M5-5 | client: hearing voice (players on avatars, the ears, the client's rules, buses, world sounds from the ears) | M5-1, M5-2 | M5-4 | no | high | ~1400 |
| M5-6 | client: speaking (capture, push-to-talk and voice activity, the Voice tab, settings, the transmit icon, debug tone and overlay) | M5-2, M5-5 | M5-7 | no | high | ~1400 |
| M5-7 | client: occlusion's muffle, the talking indicator, and the CC0 sounds when they arrive | M5-5 | M5-6 | no | high | ~900 |
| M5-4b | protocol: batched voice to each listener (only past E44's thresholds) | M5-4 | M5-6, M5-7 | yes | xhigh | ~700 |

Waves of at most three (two while #170's track runs beside, as #134's M5 kickoff says): (M5-1, M5-2, M5-3 while
the engineer is present), (M5-4, M5-5), (M5-6, M5-7, M5-4b if needed). The critical path is M5-2, M5-5, then M5-6. **M5-3 edits `addons/` and `.github/`**, which prompt unless the
session runs in bypass: the manager runs it while the engineer is present; M5-7's LFS-in-CI step edits `.github/` too.
No M5 issue edits `.claude/`.

**What to drop first** if the budget runs out, in this order: occlusion beyond one ray (never built here; if even the
one ray must go, M5-7 keeps the indicator and the CC0 wiring), then the voice-activity mode (M5-6 keeps
push-to-talk), then the fillers (the in-world talking indicator, the debug tone after the first listening test,
M5-4b's batching unless M5-4 shows the host overloaded).

**Folded, and why:**
- The client's cutoff (`hearing_radius_m()`) into M5-1, the core issue: the leak test's distance invariant reads it,
  and M5-5 needs it.
- The bots' spurts into M5-1: the distance invariant's scenario needs talking bots, and M5-4's load reuses the pattern.
- Buses and world sounds from the ears into M5-5, which builds the ears and the Voice bus.
- Settings and the Voice tab into M5-6, which needs them to pick a microphone.
- The CC0 wiring into M5-7 (it waits for the engineer's files and the LFS answer).

**Kept apart, and why:**
- Hearing (M5-5) and speaking (M5-6): together about 2800 lines.
- The measurement (M5-4) and batching (M5-4b): batching only if the numbers ask for it.
- The addon (M5-3) from the code (M5-2): the code merges without it, and the addon's task needs the engineer present.

**Files several issues touch:**

| File | Writers, in merge order | Rule |
|---|---|---|
| `core/content/voice_rule.gd`, `core/voice/` | M5-1 | `hearing_radius_m()` is the name M5-5 and M5-6 read; a rename changes both issues' text |
| `tests/harness/` (`LeakCheck`, `ScenarioInvariants`, `NetPlay`), `content/scenarios/` | M5-1, M5-4 (`voice_load`), M5-4b | a check changes in the PR that changes what it checks; the scenarios are provisional content (MVP content ADR) |
| `voice/` | M5-2 (codec, gate, jitter), M5-5 (`VoiceSpeaker`), M5-6 (`VoiceCapture`) | new files per issue; M5-5 and M5-6 edit no file M5-2 created except to add a function; nothing in `voice/` reads the life fold, the phase or `ClientSession` |
| `client/voice/` | M5-6 (`VoiceSender`: `may_speak` and `send_voice`) | |
| `client/net/client_session.gd` | #155 (claim flags), M5-5 (`voice_received` carries the seq), M5-4b (the batched row, emitting per frame with its seq) | M5-5 after #155; `voice_received`'s signature is what M5-4b emits |
| `client/app/game.gd` | M5-5 (`VoiceViews`, `Ears`, `AudioBuses` wiring), M5-6 (capture, settings) | each its own function; the second to merge rebases |
| `client/world/world_sounds.gd`, `sound_chooser.gd` | M5-5 (the ears, the World bus), M5-7 (the muffle, the CC0 streams) | M5-7 after M5-5 |
| `client/life/lift_music.gd` | M5-5 (the Music bus), M5-7 (the CC0 stream) | |
| `client/ui/debug_overlay.gd` | M5-4 (the host's relay counters), M5-5 (per speaker), M5-6 (the own microphone) | each its own lines and function |
| `client/ui/esc_menu_state.gd`, the Voice tab, `client/ui/hud.gd` | M5-6 | |
| `client/player/remote_player_body.gd` | M5-5 (the mouth point), M5-7 (the indicator) | M5-7 after M5-5 |
| `project.godot` | M5-6 (`voice_talk` on V, `audio/driver/enable_input`) | added lines; the editor's format |
| `.github/workflows/ci.yml` | M5-3 (remove the addon before `verify`), M5-7 (LFS, if the answer is (a)) | coordinate with #176's pipeline v2 and #170's tasks, which also edit `.github/` |
| `docs/ARCHITECTURE.md` | §6 by each voice issue as built; §4.5 and §10 by M5-4; §4.3 by M5-4b; §4.7 by M5-5 to M5-7; §5 and §9.7 by M5-1 | rewrite only the issue's own sections |

## Needs the engineer
The technical choices. E34 to E45 and E47 are for the M5 manager session under the engineer's delegation (#134),
which reports its answers; **E46 is the engineer's** (an architecture boundary). Every number marked so is a
placeholder, "not a decision".

| # | Choice | Options | Recommendation, and the failure it prevents |
|---|---|---|---|
| E34 | The codec boundary, and a game without the addon | (a) `VoiceCodec` in `voice/`; `TwoVoipCodec` reaches the addon only through `ClassDB` by class name and `Object.call`; a fake codec in `tests/fixtures/voice/`; without the addon voice is unavailable and the game runs; (b) scripts name `TwovoipOpusEncoder` and `AudioStreamPlaybackOpus`, as the spike did; (c) (a) with a PCM codec for players without the addon | (a). Under (b) a machine where the extension does not load (CI on Linux, a fresh clone before the engineer's download) fails `check` on every script that names a TwoVoIP class ("not declared"), and every test suite that loads one. (c) would cost about 8 Mbit/s of host upload at 10 players (160-byte frames), above the 5 Mbit/s threshold |
| E35 | Linux CI with the addon | (a) the Windows libraries only, the `.gdextension` as shipped, and CI removes `addons/twovoip/` before `verify`; (b) the Windows and Linux libraries, CI loads the Linux one, and falls back to (a) the first time it fails; (c) only Windows listed in the `.gdextension`, and the runner ignores its "No GDExtension library found" line | (a). With any `.gdextension` present Godot 4.7.2 prints an `ERROR:` line on Linux unless the library loads (§2), and `run`, `bots` and `game` fail on it: under (b) CI's colour depends on an untested binary and on the next runner image; (c) teaches the engineer's runner to hide an error class. Windows `verify` keeps covering the addon where the game runs |
| E36 | Capture and the microphone | (a) the 4.7 `AudioServer` input API; 48 kHz mono via the encoder; `audio/driver/enable_input` on; the microphone off until the player picks a device, remembered; an "opening" mark that keeps a device that froze the game from being opened at the next start; (b) the Windows default microphone opened at every session's start; (c) `AudioStreamMicrophone` with an `AudioEffectCapture` bus | (a). Under (b) a laptop player whose 4-channel array Godot 4.7.2 cannot read (#22, the spike's laptop) freezes at the lobby with no way to pick another device, and again at every start: 4.7.2 has no call that tells the channel count. (c) adds a bus and an effect for what the 4.7 API gives directly, unmeasured |
| E37 | The gate and what is sent | (a) encode every chunk while the microphone is open, send only while the gate is open (push-to-talk held, or voice activity with a 300 ms hangover), 2 frames of pre-roll (emptied while `may_speak` is false), nothing while downed, dead or in a silent phase, the level from the raw samples, RNNoise on by default with a toggle, no DTX; (b) Opus DTX alone; (c) the microphone opened only while the key is held | (a): nothing leaves in silence, so a silent player's stream never shows where they stand (§6's lesson), and the first syllable is not cut. Under (b) v6.5 shows no DTX setting in the spike or the README, and DTX still sends now and then in silence; under (c) every press waits for the device to start, and voice activity cannot work |
| E38 | The frame duration | (a) 20 ms, as measured; (b) 10 ms | (a). (b) saves about 10 ms of frame age but doubles the host's sends (the unexplained per-send cost), the headers (half of each packet) and the rate E7's bucket refills: after 10 s of talk half of every frame would be dropped, unless E7 changes too |
| E39 | The jitter buffer | (a) `VoiceJitter` (§1.4): order by the renumbered seq, conceal or FEC a single loss, start at a prebuffer adapted at each start from a 2 s window (40 to 120 ms), stop when dry, fade and flush on demand; (b) the spike's: a fixed 60 ms and a reset on a jump of 25 seqs; (c) time-stretching within a spurt | (a). Over Wi-Fi the spike's queue doubled to 75 ms (p90 93): a fixed 60 ms underruns there and wastes 20 ms on a LAN; and (b)'s reset never fires, since the renumbered seqs run on across silence. (c) needs a resampler per stream that TwoVoIP does not offer |
| E40 | Playback and the ears | (a) one `AudioStreamPlayer3D` per speaker on its `RemotePlayerBody`, bus Voice; an `AudioListener3D` placed by life (own eye; own body when downed; the target's eye or body when spectating); world sounds measured from the ears (this part amends E33, which the engineer decided: the engineer confirms it); (b) Godot's default listener, the current camera | (a). Under (b) a downed engineer hears from the downed camera, up to 2 m behind and 1.6 m above the body: a dissident whispering behind the crate the body lies against is heard clearly, since the muffle's ray passes over the crate, where at the body the crate would muffle it (vision revision 1: from where they lie) |
| E41 | How the client knows the cutoff | (a) `VoiceRule.hearing_radius_m()` (Silent 0, `Proximity.radius_m`, `RoundVoice.living_m`), read from the client's own mode for the current phase; (b) a copy of 8 m in client tuning; (c) the radius on the wire | (a): the fade ends at the host's cutoff in every phase and mode, and the leak test reads the same number. Under (b) a mode with a 12 m radius fades to silence at 8 m while the host delivers to 12 m (client/CLAUDE.md forbids copying a game number); (c) sends what the client's mode already holds |
| E42 | Occlusion's test | (a) on the listener: one ray per audible speaker per physics frame from the ears to the mouth, and one per world sound as it starts, against the client's own level; nothing on the host; (b) also the host's routing (D13 (b)): `VoiceRule` gets the `WorldQuery`, `Match` computes the routing once per tick and caches it, at most 45 rays a tick at 10 players | (a) costs at most 9 rays a frame on a client, as `SightHider` already casts, and nothing on the host. Under (b) every answer joins the command log (about 900 a second at 10 players, about 13 MB over 10 minutes), and the routing must move into `Match`'s tick: today `HostSession` and `Match._record_views` both call `speakers_for`, and a replay, which runs no `HostSession`, would read the recorded answers out of step and diverge |
| E43 | Buses, settings and the Voice tab | (a) Voice, World and Music made in code by `AudioBuses`; `user://settings.cfg` through `ConfigFile`; a Voice tab in the Esc menu; (b) an editor-made `default_bus_layout.tres` named in `project.godot`; (c) no persistence | (a): one place, built the same way in tests. (b) is a file no test builds, from which a merge can drop a bus unseen; under (c) every start asks for the microphone again, and with E36 there is no voice until the player does |
| E44 | Wire budgets and the measurement | (a) no wire change in M5; M5-4 measures headlessly with bots; a batched row (M5-4b) only past 2 ms per 20 ms of relay time or 4.5 Mbit/s at 81 streams; (b) batch now; (c) no measurement | (a): batching changes the protocol and the leak test for a cost nobody has measured since M1's unexplained 111 to 167 µs. Under (c) the first 10-player playtest finds the host's main thread, which also runs the ticks and the claims, at half a core for voice |
| E45 | The leak test for M5 | (a) the distance invariant, apart from `VoiceRule.hears`, in `LeakCheck` and `ScenarioInvariants`, with a scenario of bots talking beyond the radius; the bots talk in spurts at 50 frames a second; client tests for the dead, the downed and the ears, each seen failing on a planted widening; (b) the routing subset check alone | (a). Today a `RoundVoice` that lets everyone hear everyone passes the subset check, because `view_of` reads the same rule (§5 of ARCHITECTURE: the invariants that do not trust the declarations) |
| E46 (the engineer's: a boundary) | Which of `client/` and `voice/` uses the other | (a) `client/` uses `voice/`; `voice/` uses nothing outside itself (the engine, the addon by name); §1's rows say so; (b) §1 as written: `voice/` may use `net/` and `client/` playback, so `voice/` drives players on `client/`'s avatars | (a): the players hang on `client/`'s avatars and follow `client/`'s rules (the life fold, the ears, the phase), so `client/` decides what to play and `voice/` stays plumbing that a test drives without a scene. Under (b) `voice/` reads the life fold and the avatars, and the rendering rules of §3 live in two folders |
| E47 | Debug tooling for the humans' voice tests | (a) in debug builds: the F3 overlay's Voice section (own: gate, peak, frame age, encode µs; per speaker: queue, prebuffer, late, lost, FEC, underruns, decode µs; the host: relayed, dropped, over budget, relay µs); a test tone as a microphone source and "mute this window", neither saved; (b) launch flags per instance through `host --clients` | (a): no runner change while #170's tasks edit `tools/`, and three windows on one PC still have one microphone (the spike's tone client) and one pair of headphones |

**Stop-and-ask items:**
- **The addon** (the voice ADR's "What follows"): adding TwoVoIP v6.5 to `addons/` (M5-3), downloaded by the engineer
  (§6). Recommendation: yes, as E35 (a).
- **LFS in CI before the first audio file** (the LFS ADR's open item; it spends the account's LFS bandwidth quota):
  (a) CI fetches LFS content, cached by the list of LFS files (`git lfs ls-files -l`), so it downloads only when the
  audio changes; (b) `client/audio/**` stays out of LFS like `addons/` (one `.gitattributes` line; a few MB in git
  history); (c) the game keeps its generated placeholders where a file is an LFS pointer (CI). Recommendation: (a). Under
  (c) Godot's import of a pointer file is not an audio file, and a run that loads it prints errors that fail `verify`;
  (b) goes against KICKOFF §2's routing for a small saving.

**Game rules no ADR settles:** none beyond D11 to D15. Not reopened: vision revision 1's voice rules (V11), the MVP's
8 m, the phase table of ARCHITECTURE §6.

## Needs the engineer: how voice and sound feel
The engineer's, with the designer by relay (`docs/AGENT_WORKFLOW.md` §9; @SwiftySinister may object on the PR).

| # | Choice | Options | Recommendation, and the failure it prevents |
|---|---|---|---|
| D11 | Push-to-talk or voice activity | (a) both, push-to-talk the default, held on V (`voice_talk`); voice activity at a threshold set with a meter (a peak of 0.1, about −20 dBFS: a placeholder); (b) both, voice activity the default; (c) push-to-talk only | (a): by default only what a player means goes out. The game has no echo cancellation: with (b), the designer on laptop speakers sends everyone's voices back, and the engineer hears himself about a second late in every lobby; a fan, a keyboard or a Discord call opens the gate too. (a)'s cost: a new player forgets to press, which the HUD's transmit icon shows. Drop order: voice activity goes first, leaving (c) |
| D12 | The falloff | (a) linear to silence at the host's cutoff (`ATTENUATION_DISABLED` and `max_distance`, the spike's curve the engineer listened to), 3D, 8 m (the MVP's placeholder); (b) full volume within 2 m, then linear to silence at the cutoff (a scripted volume); (c) inverse distance (Godot's default) cut at the cutoff | (a). (c) stays loud to 8 m and stops dead: every crossing makes an audible step, and the step tells a listener exactly where the cutoff lies. (b) is clearer up close and costs a volume script per speaker per frame. 3D: a player on the floor above is heard, muffled by the floor (D13), not as if beside |
| D13 | Occlusion: who decides, and how much a wall muffles | (a) the listener only: behind the level (one ray) a voice or a world sound is 8 dB quieter and duller (a low-pass near 1 kHz; placeholders); the host still routes by distance, so a voice within 8 m is heard through a wall, muffled; (b) the host too: behind a wall a voice reaches only within a shorter radius (4 m, a placeholder), muffled; (c) walls silence: no voice through any wall | (a): a dissident plotting in the storeroom is heard, muffled, by the crew member passing the door: someone is there, not every word. (b) makes walls private between 4 and 8 m, at E42 (b)'s cost in `core/`; (c) silences two players on either side of a crate or a door jamb, since one ray cannot tell a crate from a wall |
| D14 | A talking indicator | (a) the own: a microphone icon on the HUD while the gate sends, crossed out while nobody can hear by the rules (downed, dead, a silent phase); others: an icon over a speaker's head while its audio plays, drawn in the world with the avatar; never a list of names; (b) the own icon only; (c) a HUD list of who talks | (a): the own icon answers "am I sending?" for push-to-talk; the in-world icon shows which player in view talks, which the audio and the eyes already tell. Under (c) a crew member hears a muffled voice behind a wall and the list names the dissident. Neither icon tells a speaker who hears them (the host never says). The in-world icon is a filler (drop order) |
| D15 | The mix | (a) three sliders, Voice, World and Music, defaults 0, −6 and −14 dB (placeholders); no ducking; the dead hear the music under the world sounds around their target; (b) one master slider; (c) world sounds ducked while someone talks | (a): a player tired of the lift music turns it down without losing the swings. Under (c) a swing behind a player is ducked by the very voice warning them about it |

## Alternatives
- **Scripts that name the addon's classes** (E34 (b)); **a PCM fallback codec for players** (E34 (c)).
- **CI loading the Linux binaries** (E35 (b)); **a runner that ignores the extension's error line** (E35 (c)).
- **The default microphone opened at every start** (E36 (b)); **`AudioStreamMicrophone` with a capture bus** (E36 (c)).
- **Opus DTX instead of a gate** (E37 (b)); **a microphone opened only while the key is held** (E37 (c)).
- **10 ms frames** (E38 (b)).
- **The spike's fixed prebuffer and seq-jump reset** (E39 (b)); **time-stretching** (E39 (c)).
- **Godot's default listener at the current camera** (E40 (b)).
- **A copied radius in client tuning** or **the radius on the wire** (E41 (b), (c)).
- **Occlusion in the host's routing** (E42 (b), D13 (b)), **walls that silence** (D13 (c)).
- **An editor-made bus layout**, **no saved settings** (E43 (b), (c)).
- **Batching now**, **no measurement** (E44 (b), (c)).
- **The routing subset check alone** (E45 (b)).
- **`voice/` driving `client/`'s players** (E46 (b)).
- **Launch flags per window for the one-PC test** (E47 (b)).
- **Voice activity by default** (D11 (b)); **a flat-then-fading curve** or **inverse distance** (D12 (b), (c)); **a HUD
  list of talkers** (D14 (c)); **one master slider** or **ducking** (D15 (b), (c)).
- **One issue for the whole client** (about 3700 lines), **one issue for hearing and speaking** (about 2800).

## Consequences
- `docs/ARCHITECTURE.md` §6 gains the design (the path, the gate, the jitter buffer, playback and the ears, the
  falloff, occlusion, buses), and §10 the M5 rows; the sections each issue builds are rewritten as built (§7's table).
- `voice/CLAUDE.md` gains the codec boundary, the tests without the addon, the gate's rule and the 20 ms frame.
- After the answers, the manager opens M5-1 to M5-7 from the handoff on #177, with the answers applied, in §7's order;
  M5-4b only if M5-4's numbers cross E44's thresholds.
- `project.godot` gets `voice_talk` (V) and `audio/driver/enable_input` (M5-6); CI removes the addon before `verify`
  (M5-3); `client/CLAUDE.md` gains §3's rules with M5-5.
- If E46 is (a), §1's rows for `client/` and `voice/` change in M5-5, the first PR in which `client/` uses `voice/`.
- The CC0 files close #144's and #145's open human steps once wired (M5-7).
