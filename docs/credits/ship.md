# The ship (prime-game-art)

- **Files:** `assets/environment/ship/**`
- **Author:** the prime-game art track (own work: built from code in headless Blender and Godot; no part generated
  or downloaded)
- **Source:** the art manifest `assets/environment/ship/manifest.toml` in xperiaroco2/prime-game-art (art #263 and
  #335; package v10, PR xperiaroco2/prime-game-art#386: v9 without the hall's red cup and its spill by the console,
  `cup_c` and `spill_c`, the engineer's answer 9 at the M8 review,
  https://github.com/xperiaroco2/prime-game/issues/1095#issuecomment-7021998428; on v9's
  xperiaroco2/prime-game-art#376, the console's spot at the hall's centre and the breaker boards raised, and v8's
  xperiaroco2/prime-game-art#370, the old nozzle look); the files are the package's export `ship/v5/export/v10` from
  the art's raw folder, each matching the SHA-256 its `package.json` lists but `levels/ship/ship.tscn`, which
  `colliders` points at the `levels/kit/ship` wrappers and which keeps the node ids of the game's v9 copy (v10 gives
  every node a new id; the lobby hall's and the estate lot's overrides stay on the old ones, #1667). The lobby
  hall instances its `levels/ship/ship.tscn` (#1451), the estate's ship lot too (#1499). The art manifest's
  `approved_by` is still empty; the engineer picked v8 on prime-game-art#370 ("Так, зливай"), approved the M8 slice (the lobby and the ship):
  https://github.com/xperiaroco2/prime-game/issues/507#issuecomment-6549409184, and asked for v9's console and boards
  after he played the slice: https://github.com/xperiaroco2/prime-game/issues/507#issuecomment-6573041745.
- **Updated:** the package v12 (`ship/v5/export/v12`, xperiaroco2/prime-game-art#408: the rest of the bronze cold steel), from prime-game-art `main` at `37fd1767`; approved by the engineer (relayed by the director,
  2026-11-23), in the game since #1700.
- **License:** own work, under the game's terms (the engineer's E1, 2026-10-11: the public game repo has no licence
  file, so all rights reserved)
- **AI generated:** false
- **Public repo OK:** true (own work)
