# prime-game-audio: the success and error sounds of every task

- **Files:** `assets/audio/prime_task_feedback/*`
- **Author:** prime-game-audio, the project's audio track (https://github.com/xperiaroco2/prime-game-audio): own
  synthesis, rendered by the audio manager on 2026-10-27
- **Source:** the audio track's sound board (variants U2 and P1), picked by the engineer on xperiaroco2/prime-game#1333
  ([comment 6439733924](https://github.com/xperiaroco2/prime-game/issues/1333#issuecomment-6439733924),
  [comment 6439920556](https://github.com/xperiaroco2/prime-game/issues/1333#issuecomment-6439920556)); the plan in
  prime-game-audio's `sound-map/README.md`
- **License:** own work of the project: no third party's sample, preset or recording is in either file
- **AI generated:** false
- **Public repo OK:** true (own work)

Two WAV files, mono 44.1 kHz 16-bit, each normalised to a peak of 0.8. Both come from one kalimba-like FM voice: a sine
carrier whose frequency a sine modulator at 5.2 times the note pushes, the modulation depth falling from 1.1 times
the note's frequency to 1 Hz over half the note; the level rises over 4 ms and falls exponentially to the note's end.
- `task_success.wav` (0.75 s, SHA-256 `b4442e494123dca1f5d7726f94a9b39457867b733c67e331206522f53ca11bb6`): U2, three
  rising notes C5, E5, G5 (523.25, 659.25, 783.99 Hz), 80 ms apart, each 0.5 s at level 0.15.
- `task_error.wav` (0.8 s, SHA-256 `c6fdec657ef1b95b4c007afdea243f99c19c8ab9b269677dd3a29188ff302148`): P1, G4
  (392 Hz, 0.45 s) then E-flat4 (311.13 Hz, 0.6 s) 130 ms later, both at level 0.26: the same voice falling a minor
  third.

Every task plays them through `SfxSet` (`client/audio/`): `TASK_SUCCESS` and `TASK_ERROR` (#1341, ARCHITECTURE
§4.7.60).
