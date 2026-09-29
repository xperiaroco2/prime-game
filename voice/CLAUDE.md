# voice/: capture, codec, jitter buffer, playback plumbing (engineer)

Loaded when a file in `voice/` is read. The invariants in the root `CLAUDE.md` apply. Design:
`docs/ARCHITECTURE.md`.

## Job
- Microphone capture, Opus encode and decode, the jitter buffer, and handing decoded audio to `client/` playback.
- Push-to-talk and voice activity detection (M5).

## Rules
- Plumbing only. Whether a listener hears a speaker, and how, is decided by the routing rules in `core/` and applied
  by `server/`. `voice/` never decides routing itself.
- Spatialization happens on the receiving client through an `AudioStreamPlayer3D` on the speaker's avatar.
- The codec sits behind an interface: TwoVoIP (`two-voip-godot-4`) **v6.5**, not v6.6 (it crashes the editor).
  Settings, measurements and lessons: `docs/decisions/2026-09-29-voice-approach.md`, `docs/ARCHITECTURE.md` §6.
- Any addon or GDExtension is a stop-and-ask item and lives in `addons/`.

## Tests
- Codec and jitter-buffer logic get unit tests with synthetic frames (silence, a sine, packet loss, reordering).
- Real capture and playback cannot be verified headless: measure latency and CPU cost in the spike, and give the
  human exact steps for a listening test.
