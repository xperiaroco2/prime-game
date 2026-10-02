# voice/: capture, codec, jitter buffer, playback plumbing (engineer)

Loaded when a file in `voice/` is read. The invariants in the root `CLAUDE.md` apply. Design:
`docs/ARCHITECTURE.md` §6; M5's choices: `docs/decisions/2026-10-02-m5-voice-integrated-with-the-rules.md` (proposed:
E34 to E47, D11 to D15; its §3 is the review checklist for what the client plays).

## Job
- Microphone capture, Opus encode and decode, the jitter buffer, and the per-speaker playback helper that `client/`
  hangs on a speaker's avatar.
- The gate: push-to-talk and voice activity (M5).

## Rules
- Plumbing only. Whether a listener hears a speaker, and how, is decided by the routing rules in `core/` and applied
  by `server/`. `voice/` never decides routing itself; the client may narrow what it plays, never widen it.
- Spatialization happens on the receiving client through an `AudioStreamPlayer3D` on the speaker's avatar.
- The codec sits behind `VoiceCodec`: TwoVoIP (`two-voip-godot-4`) **v6.5**, not v6.6 (it crashes the editor). No
  script names an addon class: `TwoVoipCodec` reaches it only through `ClassDB` by class name, so the project parses
  and runs where the addon is absent (CI on Linux removes it; voice is then unavailable). Name addon methods as the M1
  spike used them (`git show origin/voice/16-m1-spike-measure-voice-latency-cpu-cost:spike/voice/<file>`), never from
  memory: the engine's API dump does not hold them. Settings, measurements and lessons:
  `docs/decisions/2026-09-29-voice-approach.md`, `docs/ARCHITECTURE.md` §6.
- Nothing is sent in silence: a frame leaves only while the gate is open, never while the own player is downed or dead
  or in a phase whose voice rule hears nobody. A steady stream would show where a silent player stands.
- Frames are 20 ms (48 kHz mono, 24 kbit/s): E7's voice bucket refills 50 a second and the relay keeps the newest 5
  per poll; a shorter frame changes both.
- Any addon or GDExtension is a stop-and-ask item and lives in `addons/`. Only the `.gdextension`, its `.uid`, its
  license and its libraries are installed: the addon's helper scripts are untyped and fail the warnings policy.

## Tests
- Tests never load the addon or open a microphone. The gate and the jitter buffer are pure classes tested with
  synthetic frames (silence, a sine, packet loss, reordering, duplicates, talk spurts, arrival jitter); playback
  through real players and buses uses the fake codec in `tests/fixtures/voice/` under the Dummy driver, which mixes.
- The real codec's round trip is a headless script run on Windows with `tools\run.cmd run <script> --headless` in a
  PR that adds or changes the codec adapter; it prints SKIP without the addon and is not a `verify` step.
- Real capture and playback cannot be verified headless: give the human the exact steps of the M5 ADR's §6 (the
  one-PC and two-machine listening tests, latency and CPU from the F3 overlay against the voice ADR's thresholds).
