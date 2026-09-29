# The technical stack locked by the founding brief

- **Status:** Accepted
- **Date:** 2026-09-29 (locked by KICKOFF §2 and §3 before Phase A; recorded when the brief moved to history)
- **Deciders:** the engineer (the brief's author)

## Context
KICKOFF §7 asks M0 for "ADRs for the decisions above". The brief now lives in `docs/history/KICKOFF.md`; this record
keeps its locked technical choices findable in `docs/decisions/`.

## Decision
- **Engine:** Godot 4.7.x stable, the standard build (not .NET). The exact pin, 4.7.2, and how it is enforced:
  [toolchain pins](2026-09-28-toolchain-pins.md).
- **Language:** statically typed GDScript everywhere; untyped declarations fail `check`.
- **Tests and lint:** GdUnit4, headless from the CLI; gdtoolkit (`gdformat`, `gdlint`).
- **VCS and CI:** Git, GitHub and GitHub Actions running headless Godot.
- **Networking:** Godot's high-level multiplayer over ENet first, behind a transport abstraction. Steam networking or
  WebRTC with a signaling server for NAT traversal is decided by an ADR in M6. Narrowed on 2026-09-29: own messages
  over `MultiplayerPeer`, no RPCs, spawners or synchronizers ([listen server ADR](2026-09-29-listen-server-and-message-layer.md)).
- **Voice:** Opus. First candidate the `two-voip-godot-4` GDExtension, whose Windows build was described as
  incomplete; the M1 spike verifies Windows binaries first and compares fallbacks (`one-voip-godot-4`, Steam voice
  through GodotSteam, uncompressed or lightly compressed PCM). Its go/no-go is an M1 ADR.
- **Development platform:** native Windows first (editor, microphone, audio); never assume WSL. Godot is a portable
  zip: the agent runs the `*_console.exe` (`GODOT_BIN`), humans the regular exe (`GODOT_GUI_BIN`). Tooling stays
  cross-platform where cheap; CI runs on Linux.
- **Architecture principles** (host authority, per-peer filtering, pure `core/`, mechanics as data, the match state
  machine, voice routing as game logic, movement, debug tools): `docs/ARCHITECTURE.md` and the invariants in root
  `CLAUDE.md`. Changing one is a stop-and-ask item with its own ADR.

## Alternatives
None considered in the project: the brief fixed these before Phase A.

## Consequences
The open choices (voice codec, NAT traversal, protocol, content-API composition) are listed in
`docs/ARCHITECTURE.md` §10 with the milestone that decides each.
