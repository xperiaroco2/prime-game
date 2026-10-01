# Vulkan is the Windows rendering driver

- **Status:** Accepted
- **Date:** 2026-10-01
- **Deciders:** the engineer (chat with the M3 manager session, 2026-10-01: option (a); recorded on #124)

## Context
The project was created with `rendering_device/driver.windows="d3d12"` in `project.godot`, which overrode
the engine default (see Decision). The M1 kill spike #21 measured on the engineer's desktop (RTX 4060, NVIDIA
driver 616.92, D3D12 12_0): when a windowed D3D12 Godot process is hard-killed or starts, another windowed D3D12
process on the same PC often freezes for 5.0 to 5.2 s (one frame lasts 5 s). ENet runs on the main thread, so the
frozen process acknowledges nothing for that long.

| Run on one PC, three windows | Runs | Freezes of about 5 s |
|---|---|---|
| D3D12 (the project default then) | 12 | 8 (the host 7, client 1 once), each dropping a peer |
| `--rendering-driver vulkan` | 10 | none |
| OpenGL (Compatibility) | 5 | none |
| D3D12, windows off-screen | 5 | none |

Between two machines (the desktop and a laptop with an AMD Radeon 860M) 12 hard kills were all clean: the freeze is
local to one PC. `EnetTransport`'s 10 to 20 s peer timeout already rides a 5 s freeze out (#70), but a 5 s hitch
in two of three windowed runs on one PC spoils playtests. M4 runs windowed playtests on one PC (a host and two
clients), and ARCHITECTURE §4 left "whether Windows keeps `d3d12` as its default" to the humans.

The evidence is one machine and one driver. The laptop's AMD Radeon 860M also supports Vulkan (#124); the kill
test was not repeated on it with Vulkan.

## Decision
- **Vulkan is the Windows rendering driver**, with Forward+ unchanged. Other platforms are unchanged.
- In Godot 4.7.2 `rendering/rendering_device/driver.windows` takes `vulkan` or `d3d12`, and its engine default is
  `vulkan` (checked on the engine: `ProjectSettings.property_get_revert` and the property's hint `vulkan,d3d12`).
  The editor saves only values that differ from the default, so `project.godot` has no `[rendering]` entry at all:
  the file is exactly what the editor writes after the setting is changed to Vulkan. A line written by hand would
  disappear at the next settings save in the editor and show up as an unrelated diff.
- `tools\run.cmd shot` prints the driver it drew with (`renderer: vulkan forward_plus`), because the runner starts
  Godot with `--no-header`, which hides the engine's own driver line.
- `EnetTransport`'s minimum peer timeout stays at 10 s or more: a 5 s main-thread freeze can still come from
  elsewhere (a level load, a breakpoint, a driver).
- **Review before M6** (the slice for friends): with more machines and GPUs, either keep Vulkan or go back to D3D12.

## Alternatives
- **Keep D3D12 and switch only the tooling to Vulkan** for multi-window runs (`--rendering-driver vulkan` in `run`,
  `host` with windows and the playtest commands). The humans' editor runs would still use D3D12, so a playtest
  started from the editor next to a runner window meets the freeze, and two drivers have to be kept apart.
- **OpenGL (Compatibility)**: no freeze in 5 runs, but a different rendering method that looks different and lacks
  Forward+ features; out of scope for #124.

## Consequences
- Windowed runs on one PC (the editor plus runner windows, `host` and `join` with windows in M4) no longer meet the
  #21 freeze, as far as the 10 runs show.
- If Godot ever changes the engine default for Windows, an empty `project.godot` would follow it. The unit test
  `tests/unit/tools/rendering_driver_test.gd` fails then (and on a `d3d12` override), so `verify` and CI catch it;
  `shot`'s `renderer:` line shows the driver a window actually used.
- A Windows machine without Vulkan support would need `--rendering-driver d3d12`; none of the humans' machines is
  known to lack it.
