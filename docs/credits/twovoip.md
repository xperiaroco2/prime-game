# TwoVoIP

- **Files:** `addons/twovoip/**`
- **Author:** Julian Todd (goatchurchprime), K. S. Ernest (iFire) Lee, Gordon MacPherson and Marc Weber (the
  copyright holders in the license)
- **Source:** https://github.com/goatchurchprime/two-voip-godot-4 (release v6.5, `TwoVoIP.zip`, SHA-256
  `811ac96d4b75314f90855e3136f9939f7a4bc4a01e51850640cff967afc20fc7`; v6.6 crashes on import,
  goatchurchprime/two-voip-godot-4#107)
- **License:** MIT (`addons/twovoip/LICENSE`: the source repository's `LICENSE` at tag v6.5, which the release
  archive does not ship; added by the engineer on 2026-10-03)
- **Bundled libraries:** the release archive names none and ships no license text for them. The Windows libraries'
  strings show Opus, RNNoise (the `DENOISER_RNNOISE` option) and Speex (the `DENOISER_SPEEX` option) built in. All
  three are BSD 3-Clause; their license texts, verbatim from the submodule commits at the source repository's tag v6.5,
  are in `docs/credits/licenses/` (`opus/`, `rnnoise/`, `speexdsp/`, sources in its README) and ship in both zips
  (#422): Opus (https://opus-codec.org), Xiph.Org, Skype Limited, Octasic, Jean-Marc Valin and others; RNNoise
  (https://github.com/xiph/rnnoise), Jean-Marc Valin, Amazon, Mozilla, the Xiph.Org Foundation and Mark Borgerding;
  SpeexDSP (https://github.com/xiph/speexdsp), the Xiph.org Foundation, Jean-Marc Valin and others.

The Opus voice codec, behind `voice/`'s `VoiceCodec` (`TwoVoipCodec` reaches it by class name only, the M5 ADR's E34).
Committed: the `.gdextension` and its `.uid` as shipped and the Windows libraries only (E35 (a)); the addon's helper
scripts are left out (untyped, they fail the warnings policy). CI and the night jobs on Linux delete the extension
before running Godot (`.github/workflows/ci.yml`, `nightly.yml`). Part of an exported game on Windows.
