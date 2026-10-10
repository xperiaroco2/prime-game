# Kenney Interface Sounds: the UI click and the end outro

- **Files:** `assets/audio/kenney_interface_sounds/**`
- **Author:** Kenney (www.kenney.nl)
- **Source:** https://kenney.nl/assets/interface-sounds (Interface Sounds 1.0, `kenney_interface-sounds.zip`,
  downloaded 2026-10-09; the zip's SHA-256 `f2193d072726d6758a5f7871b2dcc54dcce0d5c35c6f0a62f92549b327c81232`)
- **License:** CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/, the pack's `License.txt`)
- **AI generated:** false
- **Public repo OK:** true (CC0)

The click of a Toy button press (#525; Ogg Vorbis, mono 44.1 kHz), renamed (the pack's name, then ours):
`click_001.ogg` `click_1.ogg`, `tick_001.ogg` `click_2.ogg`, `tick_002.ogg` `click_3.ogg`. The one sound of both
outcomes when End starts (#657; Ogg Vorbis, mono 44.1 kHz), renamed: `bong_001.ogg` `ui_outro.ogg`. Played by
`UiSounds` (`client/ui/`) through `SfxSet`; the engineer's verdicts go to `assets/audio/sfx-verdicts.json`. The pack's
`click_002.ogg` is also the Ogg stand-in for LFS pointer files in CI (`tools/runner/lfs.py`, the LFS ADR's
amendment of 2026-10-10); it is not a game asset.
