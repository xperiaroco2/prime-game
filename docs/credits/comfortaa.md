# Comfortaa

- **Files:** `assets/ui/comfortaa/**`
- **Pending:** the engineer adds the font by hand (#520): `Comfortaa[wght].ttf` saved as
  `assets/ui/comfortaa/comfortaa.ttf`; its source and weights are still open on xperiaroco2/prime-game-ui#44
- **Author:** The Comfortaa Project Authors (the source repository google/fonts' `ofl/comfortaa/METADATA.pb` names:
  https://github.com/alexeiva/comfortaa)
- **Source:** proposed on prime-game-ui#44: https://github.com/google/fonts/tree/main/ofl/comfortaa (one variable
  file, `Comfortaa[wght].ttf`, `wght` 300 to 700, with Cyrillic; google/fonts commit `db64f6b`); the commit and the
  file's SHA-256 are recorded here when it lands
- **License:** SIL Open Font License 1.1 (https://openfontlicense.org/), Reserved Font Name "Comfortaa"; shipped
  unmodified; the license text is the folder's `OFL.txt` (https://github.com/google/fonts/blob/main/ofl/comfortaa/OFL.txt)
- **AI generated:** false
- **Public repo OK:** true (OFL 1.1)

The game's UI font (prime-game-ui `docs/ui-decisions.md` § Type; the engineer's yes on prime-game-ui#44, 2026-10-07):
the theme builder (`tools/theme/mapping.json` `font`) makes one `FontVariation` of the file per weight the pack's
labels use, SemiBold 600 and Bold 700, and the 600 one the theme's default font. Until the file lands, the themes
have no font and Godot's default draws.
