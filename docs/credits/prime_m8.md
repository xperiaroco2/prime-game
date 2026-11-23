# prime-game: the M8 sounds

- **Files:** `assets/audio/prime_m8/*`
- **Author:** prime-game, own synthesis: rendered from code by `tools/sfx/render_m8_sounds.gd` (the sums in
  `tools/sfx/m8_synth.gd`, `m8_life_takes.gd`, `m8_lobby_takes.gd`, `m8_engine_takes.gd` and `synth_voices.gd`) on
  2026-11-23 for #1674
- **Source:** the synthesis code in this repository; `tools\run.cmd run tools/sfx/render_m8_sounds.gd --headless`
  writes the same files again (its noise has a fixed seed)
- **License:** own work of the project: no third party's sample, preset or recording is in any file
- **AI generated:** false (sums of sines, FM pairs and seeded filtered noise in code; no generative model)
- **Public repo OK:** true (own work)

27 WAV files, mono 44.1 kHz 16-bit, each with its mean taken out and scaled to its peak. The engineer picked each
by ear from 61 takes on a listening page (2026-11-23, "все по рекомендаціях по звуку": the recommended take of
every moment; #1674). `SfxSet` (`client/audio/`) plays each under the id of its file name (ARCHITECTURE §4.7.43).
- `hit_fist.wav` (0.35 s, peak 0.8, SHA-256 `2d060007dd4c585f897c46ab966de9b68112dec3f8ca4e8aa51db6788f95d7be`):
  a fist's hit landing, a low body thump (140 to 55 Hz) under a short muffled smack.
- `hit_heavy.wav` (0.9 s, peak 0.85, SHA-256 `1294757633283cf43777135fc68444ce06252d2859b83b31c9597721edf74e4c`):
  a two-handed item's (the crystal's) hit landing, a heavy thump, a crunch and a glassy ring.
- `swing.wav` (0.24 s, peak 0.5, SHA-256 `29427be79ee3e3f172652ffc7e9aae1c998d7161286caf9c273f5f343f0e540e`):
  a fist's whoosh, noise through a band that sweeps up and back.
- `swing_heavy.wav` (0.4 s, peak 0.6, SHA-256 `c6c7686459817c3d7fc2bba0bb24691cd0fb16e94365f617701697b4b3886285`):
  a two-handed swing, a lower, longer whoosh with a faint shimmer.
- `knockdown.wav` (0.8 s, peak 0.8, SHA-256 `1628464e090c16abec31fe804164fe8df80f6bf6b0b4027567440b77c7a7f31f`):
  a body falls: the knees, the body, a soft settle of cloth.
- `revive.wav` (0.6 s, peak 0.5, SHA-256 `5481caa17608d2fd83aff36c4f41794e89e095b13d2174f4717da364420b4ee8`):
  back on the feet, a soft rising sweep and a light pop.
- `death.wav` (1.8 s, peak 0.55, SHA-256 `c86763efad741fc7148a307f56e5d1ccae5f05e797bc72c055419e8de5caa745`):
  a soft low bell, twice, falling a fourth.
- `respawn.wav` (2.4 s, peak 0.55, SHA-256 `e01cbeab2d31860f6d9908e9bf8dd917fee5cb83f1c002f5b3213fdb8818fedf`):
  a dead player back, a hover hum under stepping chirps rising, a "ding" when done (made as the drone's print).
- `tap_pour.wav` (1.7 s, peak 0.55, SHA-256 `df628a3beb1acc44a1c02d027c6110275233f0fc6515d25b8265889e0348d8e8`):
  the bar's tap pours a mug, a fizzing stream rising as it fills, and bubbles.
- `drink.wav` (0.7 s, peak 0.65, SHA-256 `843e1c82a2cdb2d37b6066a9c13419cdd8fa642f4561831f7dcb2742ef221035`):
  two quick gulps.
- `pinball_flipper.wav` (0.2 s, peak 0.6, SHA-256 `8ccf2f6fb90f26180681a36cf617988d33cd929088a4ace625034c3180aa8a4c`):
  a solenoid's clack with a low thunk.
- `pinball_bumper.wav` (0.5 s, peak 0.6, SHA-256 `6cb71a5dd7e9ff7b62d27a71a84ef6757901592b7522cffd87c610b0dd0f33e3`):
  a pop and a bright bell (a bumper, a kicker or a target scored).
- `pinball_launch.wav` (0.8 s, peak 0.6, SHA-256 `993c28970e026e49335894e5c79b6b8f8e5bbb96ec3ea5d6bee45f43b17c7111`):
  a spring released, the ball rolling off.
- `pinball_drain.wav` (0.9 s, peak 0.55, SHA-256 `827e0fa9161359c528aeb4cb49591ccab58f3bd14947a813bb453c0ca21c600f`):
  the ball lost, three notes falling.
- `pinball_best.wav` (1.0 s, peak 0.5, SHA-256 `993f83f632045b08c8d46da277be3134696886f54a92257c9c2f2f035d59789b`):
  a new best score, a quick rising arpeggio.
- `mirror_open.wav` (0.8 s, peak 0.45, SHA-256 `30e510958c68afa62e9ddc2e91d274e2c99adef31086b3b8b314d47cea5495ea`):
  the mirror's menu opens, a soft glassy shimmer rising.
- `engine_gill_open.wav` (0.6 s, peak 0.55, SHA-256
  `6d6045ec69cd7af4fbf8b3ca2f89b635e39a630d377e9cd1b03ef3bf8f51b66e`): a gill opens, a puff of steam and a soft tick.
- `engine_gill_shut.wav` (0.4 s, peak 0.6, SHA-256
  `d4df09d16ce4625b2c3de18233eb6b96fc82e82efebba5f2b8cbfd83bb656451`): an open gill shut again, a dull clack and a
  short hiss.
- `engine_breaker_trip.wav` (1.6 s, peak 0.7, SHA-256
  `d82388f128f9607aa13b611eacd2f4849885f85c283dd9770499a214ace52428`): breakers trip, a pop like a cork, then smoke
  fizzing.
- `engine_breaker_on.wav` (1.6 s, peak 0.65, SHA-256
  `35e0ad0803f961759378863015931213cede195101e095c6a67e1af4b11f8a69`): a breaker switched on, its clunk and the hum
  Г1 (110 Hz with overtones and a slow beat) doubling in pitch.
- `engine_breaker_green.wav` (0.3 s, peak 0.4, SHA-256
  `17fa22ea3b23b0e29b8b8654ff67cd8b95f27df099652570792229d610c0de57`): the breaker's lamp turns green, a light
  two-note ding.
- `engine_zap.wav` (0.45 s, peak 0.7, SHA-256 `6a3203feb14f7cf878df1b3101fb86594e9850531be89e47cfe06d8fa4d7dea4`):
  a short circuit, К1: three falling zips, then an FM "bzzzt" falling from 260 to 120 Hz (it replaces
  `prime_engine/engine_zap.wav`).
- `engine_crystal_charger.wav` (0.3 s, peak 0.65, SHA-256
  `e808cc400cfdea2fe517b56e71dce5631255d84c08b6577b0d20fa69a45b384a`): the crystal into the charger, a latch, a
  knock and a low click.
- `engine_crystal_socket.wav` (0.8 s, peak 0.65, SHA-256
  `e25c97994aac2f348ca21b9dbea48fbe3eb59c0be56987ebbad72da83715bc46`): the crystal into its socket, the latch, then
  its light rising back.
- `engine_charging.wav` (1.95 s, peak 0.5, SHA-256
  `db3c2c11943fb069eaa46ba0e5a2873420fb16a2612d009fcf83a5e0d35fe238`): the charger charging, a loop (imported with a
  forward loop): a warm hum with a tremolo, a whistle orbiting and sparse crackles.
- `engine_charged.wav` (1.6 s, peak 0.5, SHA-256 `7ca639a44c6ccc05f6c5e921116c6a527cc617a54e8869e05404bafb586726d9`):
  the crystal charged, a glassy bell of two notes and glints.
- `timer_tick.wav` (0.12 s, peak 0.4, SHA-256 `86974b2fbb77beabd7f05553bdfe9872135ed668568a8a44ecfb97ea8f578875`):
  one of the match's last ten seconds, a soft wooden tick.
