# webrtc-native

- **Files:** `addons/webrtc_native/**`
- **Author:** the Godot Engine contributors (the license's "Copyright (c) 2018 Godot Engine")
- **Source:** https://github.com/godotengine/webrtc-native (tag `1.2.2-stable`, release zip
  `godot-extension-webrtc_native.zip`, SHA-256 `98e9446921740d995bd9ca1be48798dc3c2ceed51e044a25ce18b3cff11f56e5`)
- **License:** MIT (`addons/webrtc_native/LICENSE.webrtc-native`, as shipped in the release zip)
- **Bundled libraries:** the libraries are built with these, each license text as shipped beside them in
  `addons/webrtc_native/`:
  - libdatachannel (https://github.com/paullouisageneau/libdatachannel), Paul-Louis Ageneau: MPL 2.0,
    `LICENSE.libdatachannel`; its source is at that URL;
  - libjuice (https://github.com/paullouisageneau/libjuice), Paul-Louis Ageneau: MPL 2.0, `LICENSE.libjuice`; its
    source is at that URL;
  - Mbed TLS (https://github.com/Mbed-TLS/mbedtls), the Mbed TLS contributors: Apache 2.0 or GPL 2.0 or later, used
    under Apache 2.0, `LICENSE.mbedtls`;
  - libSRTP (https://github.com/cisco/libsrtp), Cisco Systems: BSD 3-Clause, `LICENSE.libsrtp`;
  - usrsctp (https://github.com/sctplab/usrsctp), Randall Stewart and Michael Tuexen: BSD 3-Clause,
    `LICENSE.usrsctp`;
  - plog (https://github.com/SergiusTheBest/plog), Sergey Podobry: MIT, `LICENSE.plog`.

WebRTC for Godot outside the web export: the extension behind `WebRTCPeerConnection` and `WebRTCMultiplayerPeer`,
which the M6 WebRTC transport uses (`docs/decisions/2026-10-04-m6-playable-over-the-internet.md`, E57). Committed:
the `.gdextension` as shipped, its `.uid` from Godot's import, the Windows x86_64 and Linux x86_64 libraries (debug
and release) and the seven license files; the other platforms' libraries are left out. CI and cloud sessions load it
on Linux. Part of an exported game on Windows.
