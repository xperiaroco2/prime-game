# Roadmap

Milestones and their goals only ([KICKOFF §7](history/KICKOFF.md)). Task-level status lives in GitHub: issues,
the project board and [milestones](https://github.com/xperiaroco2/prime-game/milestones). Owned by the engineer; a change to a
milestone's goal is agreed with the designer. Acceptance criteria belong in each milestone's issues.

The **MVP** spans M2 to M5. At its end the base mode ([MVP rules](decisions/2026-09-29-mvp-rules.md) as changed by
[vision revision 1](decisions/2026-10-01-vision-revision-1.md): Engineers and dissidents, Delivery tasks with hiding
packages as the sabotage, knives, two hands, a knockdown with revives, spectating and respawns, the Tab task screen
and proximity voice) is playable over a LAN or a VPN.

| Milestone | Goal |
|---|---|
| **M0** Agent setup and foundation | Repo structure, `.gitattributes`, LFS and `.gitignore`, `CLAUDE.md` files, docs skeletons, ADRs, the task runner, GdUnit4, gdtoolkit, CI, CODEOWNERS, issue and PR templates, labels, subagents, skills and hooks. Output: a trivial test passing in CI and the first M1 issues on the board |
| **M1** Risk spike (throwaway branch) | Host and two clients over ENet on one machine, first-person capsules walking in a greybox room, proximity voice through the Opus addon with 3D falloff. Measure latency and CPU cost; confirm the addon builds or ships for Windows first, then other platforms. Output: an ADR with a go/no-go on the voice approach, and lessons learned. The spike code is not merged as is: its branches `*/12-…` to `*/16-…` stay on `origin` as the M1 archive |
| **M2** Core rules, headless | Roles, tasks, win conditions and voice-routing rules, fully unit-tested, no visuals. The core architecture and the content API are designed first. (Meetings and voting were planned here; the MVP rules moved them to a later mode, which vision revision 1 dropped) |
| **M3** Networked match loop | Lobby, role assignment, the intent and event protocol, per-peer filtering, the bot harness and information-leak tests |
| **M4** First-person greybox | A map, movement, interactions and tasks in 3D, host-side movement checks, interpolation |
| **M5** Voice integrated with rules | Proximity, occlusion, push-to-talk or voice activity. (Dead chat and the meeting mode were dropped by vision revision 1: nobody hears the downed or the dead, and the dead hear no voice) |
| **M6** Playable vertical slice | Playable with friends over the internet: the NAT traversal ADR (Steam vs WebRTC) and its implementation |
| **M7+** Mechanics | Co-designed roles, abilities, items and sabotages, one at a time, each with tests and a bot scenario. Then the low-poly art pass, audio and polish |
