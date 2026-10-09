# prime-game-ui: the UI pack's icons and Delivery cards

- **Files:** `assets/ui/toy_pack/icons/**`, `assets/ui/toy_pack/cards/**`, `client/ui/theme/pack/icons/**`,
  `client/ui/theme/pack/cards/**` (the art folders only: a font the pack may ship later in a fonts folder is a third
  party's and needs its own entry)
- **Author:** prime-game-ui, the project's UI track (https://github.com/xperiaroco2/prime-game-ui)
- **Source:** https://github.com/xperiaroco2/prime-game-ui/tree/ui-0.4.0/dist/pack (tag `ui-0.4.0`, commit
  `d7650db6590d925fc509fa1b2d793fc336c3b37d`; each file's SHA-256 in `client/ui/theme/pack.lock.json`, copied by
  `tools\run.cmd ui-sync`)
- **License:** own work of the project: every entry of the pack's `icons/LICENCES.json`, `icons/room/LICENCES.json`
  and `cards/LICENCES.json` reads `"licence": "own work", "author": "prime-game-ui"` (the UI track's answer on
  xperiaroco2/prime-game-ui#44: nothing in the pack is a third party's)
- **AI generated:** true (drawn as SVG markup by the UI track's Claude Code sessions, the card PNGs rendered from
  those SVGs; no image generator; to be confirmed by the engineer, #520)
- **Public repo OK:** true (own work; prime-game-ui#44, item 3)

The 17 icons of `icons/`, the 8 room pictograms of `icons/room/` (for the map board) and the Delivery how-to cards
`cards/delivery-1..4.png` (for the how-to card, #254), imported by Godot from `assets/ui/toy_pack/` at the import
scale the pack's `assets` list gives (#520); the pinned copy under `client/ui/theme/pack/` (#288) is text Godot does
not import. Each file's "what" is in its folder's `LICENCES.json`.
