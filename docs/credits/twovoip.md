# TwoVoIP

- **Files:** `addons/twovoip/**`
- **Author:** goatchurchprime (GitHub) and the project's contributors
- **Source:** https://github.com/goatchurchprime/two-voip-godot-4 (release v6.5, `TwoVoIP.zip`, SHA-256
  `811ac96d4b75314f90855e3136f9939f7a4bc4a01e51850640cff967afc20fc7`; v6.6 crashes on import,
  goatchurchprime/two-voip-godot-4#107)
- **License:** MIT, as the source repository states it; not checked against the license text, which the v6.5 release
  archive does not ship (no license file is committed with the addon)
- **Bundled libraries:** the release archive names none and ships no license text for them. The Windows libraries'
  strings show Opus, RNNoise (the `DENOISER_RNNOISE` option) and Speex (the `DENOISER_SPEEX` option) built in. Their
  upstream licenses, not checked against the copies in v6.5's build: Opus (https://opus-codec.org) BSD 3-Clause,
  Xiph.Org Foundation and contributors; RNNoise (https://github.com/xiph/rnnoise) BSD 3-Clause, Jean-Marc Valin, the
  Xiph.Org Foundation and Mozilla; SpeexDSP (https://github.com/xiph/speexdsp) BSD 3-Clause, Xiph.Org Foundation and
  contributors.

The Opus voice codec, behind `voice/`'s `VoiceCodec` (`TwoVoipCodec` reaches it by class name only, the M5 ADR's E34).
Committed: the `.gdextension` and its `.uid` as shipped and the Windows libraries only (E35 (a)); the addon's helper
scripts are left out (untyped, they fail the warnings policy). CI and the night jobs on Linux delete the extension
before running Godot (`.github/workflows/ci.yml`, `nightly.yml`). Part of an exported game on Windows.
