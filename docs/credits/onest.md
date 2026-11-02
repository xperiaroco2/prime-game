# Onest

- **Files:** `assets/ui/toy_pack/fonts/Onest-VariableFont_wght.ttf` (the UI pack's font, which ui-sync lands from the
  pinned pack's assets list since #1559 (ui-2.5.4); the theme loads it)
- **Author:** The Onest Project Authors (https://github.com/simpals/onest)
- **Source:** https://github.com/google/fonts/blob/45e3d5269e4a17d823f6d84470bc084dc5ae46f6/ofl/onest/Onest%5Bwght%5D.ttf (google/fonts' variable `Onest[wght].ttf`, `wght` 100 to 900, with Cyrillic, unmodified,
  renamed by the UI track), through the UI pack https://github.com/xperiaroco2/prime-game-ui/tree/ui-2.5.4/dist/pack
  (`fonts/Onest-VariableFont_wght.ttf`, 193,056 bytes; SHA-256 `966c5c29b4755da84b6854d5c21dd4eaa2420225d0e9874de602de176d4a9f31`; its record in the pack's `fonts/LICENCES.json`)
- **License:** SIL Open Font License 1.1 (https://openfontlicense.org/); shipped unmodified; the license text is
  `docs/credits/licenses/onest/OFL.txt` (https://github.com/google/fonts/blob/45e3d5269e4a17d823f6d84470bc084dc5ae46f6/ofl/onest/OFL.txt, byte for byte the pack's `fonts/OFL-Onest.txt`), which a build carries
  as `licenses/onest/OFL.txt` (`docs/credits/licenses/README.md`)
- **AI generated:** false
- **Public repo OK:** true (OFL 1.1)

The game's text and number font (the UI track's choice since `ui-2.0.0`, which replaced Comfortaa; the engineer approved the pack at
`ui-2.5.4`: https://github.com/xperiaroco2/prime-game/issues/507#issuecomment-6561300899). The theme builder
(`tools/theme/mapping.json` `font.families`) makes one `FontVariation` of the file per weight the pack's labels in this
family use, Medium 500 and Bold 700, and the 500 one is the theme's default font.
