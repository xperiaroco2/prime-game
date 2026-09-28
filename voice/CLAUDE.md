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
- The codec sits behind an interface: the first candidate is the `two-voip-godot-4` GDExtension. Its README has
  described the Windows build as incomplete, and Windows is the primary platform. The M1 spike verifies Windows
  binaries first and compares fallbacks (`one-voip-godot-4`, Steam voice via GodotSteam, lightly compressed PCM).
  The go/no-go goes into an ADR.
- Any addon or GDExtension is a stop-and-ask item and lives in `addons/`.

## Tests
- Codec and jitter-buffer logic get unit tests with synthetic frames (silence, a sine, packet loss, reordering).
- Real capture and playback cannot be verified headless: measure latency and CPU cost in the spike, and give the
  human exact steps for a listening test.
