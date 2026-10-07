# Bundled license texts

License texts of software a release build carries that is not an addon of its own (#422). `export` copies every file
of a folder here into both zips as `licenses/<folder>/<file>`, and its release check holds them against
`export.NOTICES` (docs/AGENT_WORKFLOW.md §11.24). Each text is the primary source's file, byte for byte: never
edit one; fetch the new file when the version changes, and update its row.

| File | Why a build carries it | Source (verbatim) | SHA-256 |
|---|---|---|---|
| `godot/LICENSE.txt` | The `.exe` is Godot 4.7.2-stable's release template (`pins.py`) | https://github.com/godotengine/godot/blob/4.7.2-stable/LICENSE.txt (tag commit `ed1daf0bf001b61586d9930840f2f1394092c079`) | `b0435e3b3e4e55238f05f4b306f30524a1b2e20147810d436eaa554fa6855c80` |
| `godot/COPYRIGHT.txt` | Godot's third-party notices for the same template | https://github.com/godotengine/godot/blob/4.7.2-stable/COPYRIGHT.txt (same commit) | `cb1980c88089573bcacd7221d777c689bb8bbd778799f24c27fca0fe5f774d6d` |
| `opus/COPYING` | Opus, built into TwoVoIP v6.5's `libtwovoip` | https://github.com/xiph/opus/blob/ddbe48383984d56acd9e1ab6a090c54ca6b735a6/COPYING (the `opus` submodule commit at two-voip-godot-4's tag v6.5) | `01e1167d54a096d123cf6dfbbeb19587278845c6481d2d66d545669846079551` |
| `rnnoise/COPYING` | RNNoise, built into the same library | https://github.com/xiph/rnnoise/blob/372f7b4b76cde4ca1ec4605353dd17898a99de38/COPYING (the `rnnoise` submodule commit at v6.5) | `45d37ca1cdb278c088e1aa85e0e65ca3a534ed86a28dcc96ca16810248a61d35` |
| `speexdsp/COPYING` | SpeexDSP, built into the same library | https://github.com/xiph/speexdsp/blob/1b28a0f61bc31162979e1f26f3981fc3637095c8/COPYING (the `speexdsp` submodule commit at v6.5) | `2654a4264b2bfe298dedc508748d140111840c315cc8eb646a3a68c13fa75b01` |

The codec versions come from the submodules of https://github.com/goatchurchprime/two-voip-godot-4 at tag v6.5
(`git ls-tree v6.5`), the release `docs/credits/twovoip.md` pins. That TwoVoIP's release workflow built `TwoVoIP.zip`
from those submodule commits is assumed, not proven from the binaries.
