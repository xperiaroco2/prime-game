# Unbounded

- **Files:** `assets/ui/toy_pack/fonts/Unbounded-VariableFont_wght.ttf` (the UI pack's font, which ui-sync lands from the
  pinned pack's assets list since #1559 (ui-2.5.4); the theme loads it)
- **Author:** The Unbounded Project Authors (https://github.com/googlefonts/unbounded)
- **Source:** https://github.com/google/fonts/blob/45e3d5269e4a17d823f6d84470bc084dc5ae46f6/ofl/unbounded/Unbounded%5Bwght%5D.ttf (google/fonts' variable `Unbounded[wght].ttf`, `wght` 200 to 900, with Cyrillic, unmodified,
  renamed by the UI track), through the UI pack https://github.com/xperiaroco2/prime-game-ui/tree/ui-2.5.4/dist/pack
  (`fonts/Unbounded-VariableFont_wght.ttf`, 778,272 bytes; SHA-256 `323b511be380c8d474ef030686b71aedde501f8d9cd46da558b7c40454372c3f`; its record in the pack's `fonts/LICENCES.json`)
- **License:** SIL Open Font License 1.1 (https://openfontlicense.org/); shipped unmodified; the license text is
  `docs/credits/licenses/unbounded/OFL.txt` (https://github.com/google/fonts/blob/45e3d5269e4a17d823f6d84470bc084dc5ae46f6/ofl/unbounded/OFL.txt, byte for byte the pack's `fonts/OFL-Unbounded.txt`), which a build carries
  as `licenses/unbounded/OFL.txt` (`docs/credits/licenses/README.md`)
- **AI generated:** false
- **Public repo OK:** true (OFL 1.1)

The game's display font: the loud titles, the logo and the tiles' kickers (the UI track's choice since `ui-2.0.0`, which replaced Comfortaa; the engineer approved the pack at
`ui-2.5.4`: https://github.com/xperiaroco2/prime-game/issues/507#issuecomment-6561300899). The theme builder
(`tools/theme/mapping.json` `font.families`) makes one `FontVariation` of the file per weight the pack's labels in this
family use, Bold 700.
