# The slice character slice_m1 (prime-game-art)

- **Files:** `assets/characters/slice_m1/**`
- **Author:** the prime-game art track (own work: the cast recipe, the clay look, the face kit, the rig and the
  ragdoll data), on Quaternius's packs: Ultimate Modular Men Pack by Quaternius (CC0 1.0); Universal Animation
  Library 2 by Quaternius (CC0 1.0); Universal Animation Library by Quaternius (CC0 1.0)
- **Source:** xperiaroco2/prime-game-art `main` at `45f73ac` (PR xperiaroco2/prime-game-art#182),
  `assets/character/slice_m1/export/`: `slice_m1.glb` (SHA-256
  `b9716a446b935078caadaa01dcfacf0088ea36c4cd1268d155c7aab22aac06b2`) and `slice_m1.ragdoll.json` (SHA-256
  `5956866fb54e51932d84baa707896f9ad456e58b3b7ce970b643352a841466d3`); the manifest `assets/character/slice_m1/
  manifest.toml`, approved by xperiaroco2 on 2026-10-12 in xperiaroco2/prime-game-art#139. The PNGs beside the GLB
  are its embedded textures as Godot's importer extracts them.
- **License:** own work of the project (https://github.com/xperiaroco2/prime-game); the Quaternius parts CC0 1.0
  (https://creativecommons.org/publicdomain/zero/1.0/); the four Meshy text-to-motion clips are owned output of the
  Meshy Pro plan
- **AI generated:** true (the manifest's `ai_generated`: the clips marked below)
- **Public repo OK:** true (the manifest's `public_repo_ok`)

The character of #522: the body, its 64-bone rig and the clips of the art MVP set in one GLB, and the ragdoll data
(16 bodies, 15 joints, art #115) the game builds its `PhysicalBone3D`s from. The clips, as Godot imports them:

| Clip | Source | License | AI generated |
|---|---|---|---|
| `Idle`, `Jog_Fwd`, `Jog_Bwd`, `Sprint_Fwd`, `Crouch_Idle`, `Crouch_Fwd`, `Jump_Start`, `Jump_Air`, `Jump_Land`, `Push_Upper`, `Raise_In`, `Raise_Work`, `Raise_Out`, `Talk_Upper` | Quaternius Universal Animation Library | CC0 1.0 | false |
| `Carry_Upper`, `Pickup_One`, `Putdown_One` | Quaternius Universal Animation Library 2 | CC0 1.0 | false |
| `Knife_Swing` | Quaternius Ultimate Modular Men Pack (`Sword_Slash`) | CC0 1.0 | false |
| `Turn_Left`, `Turn_Right`, `Strafe_Left`, `Strafe_Right`, `Shove_Stumble`, `Pickup_Package`, `Putdown_Package` | Meshy text-to-motion (task ids in the art manifest) | owned output (Meshy Pro) | true |
