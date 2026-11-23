# The base alien alien_chameleon (prime-game-art)

- **Files:** `assets/characters/alien_chameleon/**`
- **Author:** the prime-game art track (own work: the body refitted to the approved concept, the paint and the look,
  the rig, the ragdoll data, the fitted clips), on Universal Base Characters by Quaternius (CC0 1.0) and Universal
  Animation Library by Quaternius (CC0 1.0); the back runs from The 100STYLE Dataset by Ian Mason (CC BY 4.0,
  https://doi.org/10.5281/zenodo.8127870)
- **Source:** xperiaroco2/prime-game-art `main` at `009f2b95` (PR xperiaroco2/prime-game-art#398, art #393),
  `assets/character/alien_chameleon/export/`: `alien_chameleon.glb` (SHA-256
  `e8a5c3bdf766dd2ddc0d33f4042025b7a8ba59b3a50286fe9818bf05d26ef55d`), `alien_chameleon.ragdoll.json` and `look/`
  (the look's scripts, shaders, JSON and mask, `alien_chameleon_mask.png` SHA-256
  `b2f26c256effa0ef0aaa60fdd1da2d458322d3e70d38b3901788754e258bf8f5`), each matching the package's `package.json`;
  the manifest `assets/character/alien_chameleon/manifest.toml`, approved by xperiaroco2 on 2026-11-23 in
  xperiaroco2/prime-game-art#398 (the engineer's pick, option A, prime-game#1095). Godot's importer may extract the
  GLB's embedded textures beside it.
- **License:** own work of the project (https://github.com/xperiaroco2/prime-game); the Quaternius parts CC0 1.0
  (https://creativecommons.org/publicdomain/zero/1.0/); the 100STYLE clips CC BY 4.0
  (https://creativecommons.org/licenses/by/4.0/; attribution: Ian Mason, The 100STYLE Dataset); the head (Meshy
  multi-image to 3D from the project's own OpenAI concept views) and the two crouch runs (Meshy text to motion) are
  owned output of the Meshy paid plan
- **AI generated:** true (the manifest's `ai_generated`: the head and the clips marked below)
- **Public repo OK:** true (the manifest's `public_repo_ok`)

M8's base alien (the recovered chameleon of art #196): the body, its humanoid rig and 18 clips in one GLB, the
ragdoll data (16 bodies) the game builds its `PhysicalBone3D`s from, and the look (`look/alien_dress.gd` swaps the
head's and the body's materials for the static-skin shader; a player's colour through `AlienStatic.set_skin`). The
clips, as Godot imports them (the `_Loop` suffix dropped):

| Clip | Source | License | AI generated |
|---|---|---|---|
| `Idle`, `Crouch_Idle`, `Jump_Air`, `Jump_Start`, `Jump_Land`, `Walk`, `Talk_Upper` | Quaternius Universal Animation Library | CC0 1.0 | false |
| `Jog_Fwd`, `Jog_Fwd_Left`, `Jog_Fwd_Right`, `Sprint_Fwd`, `Strafe_Left`, `Strafe_Right` | Quaternius Universal Animation Library, fitted (turned, mirrored, retimed) by the art track | CC0 1.0 | false |
| `Jog_Bwd`, `Jog_Bwd_Left`, `Jog_Bwd_Right` | The 100STYLE Dataset (`Neutral_BR`), fitted by the art track | CC BY 4.0 | false |
| `Crouch_Fwd`, `Crouch_Run` | Meshy text to motion (the art manifest: task ids lost with D:, art's `docs/research/2026-11-18-d-loss.md`) | owned output (Meshy paid plan) | true |

**Changed here:** the two look scripts, `look/alien_dress.gd` and `look/alien_static.gd`, carry `as` casts on the
values they read from JSON and dictionaries (14 lines), so they pass the game's warnings-as-errors typing (`check`);
nothing else differs from the package. The art track takes the casts back into its package.
