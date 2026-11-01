# The lobby hall (prime-game-art)

- **Files:** `assets/environment/lobby/**`
- **Author:** the prime-game art track (own work: the hall, its metal, the shaders, the light rig, made by the art
  pipeline's code); the Earth's textures from NASA imagery (below)
- **Source:** the art manifest `assets/environment/lobby/manifest.toml` in xperiaroco2/prime-game-art (art #356, PR
  xperiaroco2/prime-game-art#364, rebaked on the ship package v8 by PR xperiaroco2/prime-game-art#372, `main` at
  `01823cd5`); the files are the package's export `lobby/hall/v19/export` from the art's raw folder, each matching
  the SHA-256 its `package.json` lists but `levels/lobby/lobby_hall.tscn` (it points at the `levels/kit` wrappers and
  takes the ship's clearing ground off layer 1) and `levels/lobby/lobby_hall.gd` (comments rewrapped at 100
  columns). The PNGs beside the GLBs are their embedded textures as Godot's importer extracts them. The art
  manifest's `approved_by` is still empty; the engineer approved the lobby for the M8 slice:
  https://github.com/xperiaroco2/prime-game/issues/507#issuecomment-6549409184. The Earth: NASA's Black Marble 2016
  (Joshua Stevens and Miguel Roman, Suomi NPP VIIRS), Blue Marble Next Generation (December 2004) and the Blue Marble
  clouds (Reto Stockli), NASA Earth Observatory / Goddard Space Flight Center, from eoimages.gsfc.nasa.gov (records
  144898, 73909, 57747; downloaded 2026-10-30; the art's `sources/nasa_earth_lobby.toml`), scaled by the art's
  `lobby --earth-tex`. Credit line: "Earth imagery: NASA".
- **License:** own work, under the game's terms (the engineer's E1, 2026-10-11: the public game repo has no licence
  file, so all rights reserved); the Earth's textures: NASA public domain imagery (NASA-PD,
  https://www.nasa.gov/nasa-brand-center/images-and-media/; no NASA logos or insignia, no implied endorsement)
- **AI generated:** false
- **Public repo OK:** true (own work and NASA public domain)
