# prime-game: the ship engine's placeholder sounds

- **Files:** `assets/audio/prime_engine/*`
- **Author:** prime-game, own synthesis: rendered from code by `tools/sfx/render_engine_sounds.gd` (the sums in
  `tools/sfx/engine_synth.gd`) on 2026-11-01 for #1501
- **Source:** the synthesis code in this repository; `tools\run.cmd run tools/sfx/render_engine_sounds.gd --headless`
  writes the same files again (its noise has a fixed seed)
- **License:** own work of the project: no third party's sample, preset or recording is in any file
- **AI generated:** false (sums of sines and seeded noise in code; no generative model)
- **Public repo OK:** true (own work)

Six WAV files, mono 44.1 kHz 16-bit, each with its mean taken out and scaled to its peak. Placeholders for the
engineer to pick by ear (`tools\run.cmd sfx-check assets/audio/prime_engine --page`), "not a decision"; the final
sounds come from the audio track (#1333). GDD §8 "The ship's engine" says when each plays.
- `engine_call.wav` (0.35 s, peak 0.45, SHA-256 `87e01dff5fa33e3b50e44c0b3f9e39b545e5d4d3b9f509e2ce4e73bdb4252feb`):
  the ship calls while the engine is off, a soft E5 (659.25 Hz) with a quarter of its octave, falling away.
- `engine_beep.wav` (0.13 s, peak 0.25, SHA-256 `a701acfd9b7f70b4dff9109ce1e0e1e35d8b621f474fed5c210d3d405dce164a`):
  one lamp of the breakers' order, E6 (1318.5 Hz) with a third of its third harmonic.
- `engine_wail.wav` (1.4 s, peak 0.6, SHA-256 `cc45c26809a35dd72d2f7c8e232eacf2be7ec2e1d50ba0d9832c22329c100b0a`):
  a problem, a siren rising from 380 Hz to 1100 Hz, a soft sawtooth of four harmonics with a 7 Hz tremolo.
- `engine_zap.wav` (0.45 s, peak 0.8, SHA-256 `fcd7c6d2d326afa3532beeee93907c4298cd16d02185ab17c1253ffd3b1c73ab`):
  a short circuit, crackling noise in 4 ms bursts over a clipped buzz falling from 110 Hz to 70 Hz.
- `engine_blast.wav` (2.0 s, peak 0.8, SHA-256 `30e8487c324f69be1ed631ad5e94fde152d64735bacef8be3a39b06905c93126`):
  a fail's blast, a thump falling from 55 Hz to 35 Hz under noise whose low-pass closes from 3 kHz to 200 Hz.
- `engine_roar.wav` (2.8 s, peak 0.8, SHA-256 `a958e226569274058c7d2a52ae2404e3303a944e8b2eafaff7f61e446c607f57`):
  the finish, a turbine's sawtooth spinning up from 70 Hz to 190 Hz in a rumble whose low-pass opens to 2.5 kHz.

`SfxSet` (`client/audio/`) plays them: `ENGINE_CALL`, `ENGINE_BEEP`, `ENGINE_WAIL`, `ENGINE_ZAP`, `ENGINE_BLAST` and
`ENGINE_ROAR` (#1501, ARCHITECTURE §4.7.64).
