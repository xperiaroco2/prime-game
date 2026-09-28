# Godot MCP servers vs pure CLI

## Summary

As of 2026-09-28 there are many Godot MCP servers: about 18 distinct ones in the official MCP registry, plus paid ones. None is official. Most have one maintainer and were created in 2026.

**Main servers**
- **Coding-Solo/godot-mcp** is the most popular (5.9k stars, 14 tools, no editor plugin).
  - Its npm package (0.1.1, published 2026-02-03) predates the April 2026 fix for arbitrary script execution (PR #99).
  - `run_project` spawns `godot -d` and allows only one Godot process at a time.
  - Its Windows auto-detection will not find our portable Godot.
  - Nobody has answered the question about 4.7 support (issue #111).
- **Editor-plugin servers** (GDAI $19, Godot MCP Pro $15, hybridindie, tomyud1) need an addon in the repo and a running editor. Most also run arbitrary GDScript and open a localhost port.
- **Runtime-bridge servers** (tugcantopaloglu, which says it was tested with 4.7; Erodenn/godot-mcp-runtime, which needs no addon) add screenshots, input simulation and eval.
- One server, better-godot-mcp, was archived on 2026-09-13 with the advice to use the editor plus the GDScript CLI toolchain instead.

**What the CLI already covers (tested locally with Godot 4.7.2 console on this machine)**
- **Godot 3 idioms:** `--check-only` reports them with explicit messages: removed `export` and `yield`, 3-argument `connect`, `OS.get_ticks_msec`, `rset`, `move_and_slide(v)`. It also reports untyped variables as errors when the project warning is set to error. gdlint misses all of these idioms.
- **Screenshots:** a small SceneTree script saves a PNG in about 6 seconds, and the agent can read the image. The same script hangs under `--headless`.
- **Class reference:** `--dump-extension-api-with-docs` writes the full class reference with descriptions, locked to the binary, in 1.4 seconds.
- **Signatures:** a ClassDB lookup script returns exact signatures, for example that `KinematicBody` does not exist.

**Context cost is not the deciding factor.** Claude Code 2.1.195 defers MCP tool schemas by default (tool search). An MCP server can also be defined inside one subagent so its tools never appear in the main conversation.

**The deciding factors are:**
- CI parity: CI can never call MCP tools.
- Security and supply-chain risk.
- Two humans each approving and maintaining an extra runtime.
- Conflicts between an editor plugin and scenes the humans edit by hand.
- A single-process limit that does not fit host + N bots.

**Recommendation:** no Godot MCP in M0–M3; revisit at M4 with written criteria. godot-api-checker should get its API information from the engine binary itself: the parse check, ClassDB lookup, and a locally dumped API reference. Web docs should be pinned to docs.godotengine.org/en/4.7/. Context7 is optional at most, pinned to /websites/godotengine_en_4_7, and never the default, because of CVE-2026-75130 and its 3.6 library.

The test scripts are in the scratchpad: C:\Users\xperi\AppData\Local\Temp\claude\D--prime-game\40c5c58a-0dc5-4821-beca-a406804c7d8a\scratchpad\proj\tools\ (check_scripts.gd, shot.gd, api_lookup.gd).

## Facts (with verification)

- **godot_mcp-01** [confirmed] Coding-Solo/godot-mcp: MIT, 5,858 stars, 72 open issues+PRs, last commit 2026-04-16 (merge of PR #99), no GitHub releases.  
  src: local-test: gh api repos/Coding-Solo/godot-mcp ; gh api "repos/Coding-Solo/godot-mcp/commits?per_page=1" (repo: https://github.com/Coding-Solo/godot-mcp) (repo)
- **godot_mcp-02** [confirmed] Coding-Solo/godot-mcp exposes exactly 14 tools: launch_editor, run_project, get_debug_output, stop_project, get_godot_version, list_projects, get_project_info, create_scene, add_node, load_sprite, export_mesh_library, save_scene, get_uid, update_project_uids. No editor plugin; Node >=18; env GODOT_PATH and DEBUG; README install: `claude mcp add godot -- npx @coding-solo/godot-mcp`.  
  src: https://github.com/Coding-Solo/godot-mcp (repo)
- **godot_mcp-03** [confirmed] npm @coding-solo/godot-mcp latest is 0.1.1, published 2026-02-03 (only version). PR #82 (2026-03-18) and the RCE fix PR #99 (2026-04-16: nodeType like "res://evil.gd" could load and instantiate an arbitrary script, running its _init()) landed after it, so the README's `npx` install ships without those fixes.  
  src: local-test: npm view @coding-solo/godot-mcp time --json ; https://github.com/Coding-Solo/godot-mcp/pull/99 (local-test)
- **godot_mcp-04** [confirmed] Coding-Solo PR #67 (merged 2026-01-29) switched child_process exec to execFile to mitigate shell injection (issue #64).  
  src: https://github.com/Coding-Solo/godot-mcp/pull/67 (repo)
- **godot_mcp-05** [confirmed] Coding-Solo run_project spawns `godot -d --path <projectPath> [scene]` with stdio 'pipe', and kills any existing activeProcess first. So only one Godot process at a time, and it has no headless option.  
  src: https://github.com/Coding-Solo/godot-mcp/blob/main/src/index.ts (repo)
- **godot_mcp-06** [confirmed] Coding-Solo Windows auto-detection only probes C:\Program Files\Godot\Godot.exe, C:\Program Files (x86)\Godot\Godot.exe, the Godot_4 variants and %USERPROFILE%\Godot\Godot.exe. A portable zip under D:\ requires GODOT_PATH.  
  src: https://github.com/Coding-Solo/godot-mcp/blob/main/src/index.ts (repo)
- **godot_mcp-07** [corrected] Coding-Solo issue #111 (2026-05-11) asks when Godot 4.7 will be supported and has 0 replies. Windows bug #49 (JSON argument quoting breaks create_scene on Windows 11) is still open.  
  src: https://github.com/Coding-Solo/godot-mcp/issues/111 ; https://github.com/Coding-Solo/godot-mcp/issues/49 (issue)
  - CORRECTED: Issue #111 (2026-05-11, asking about Godot 4.7 support) is open with 0 comments. Issue #49 is still open, but its stated root cause (child_process.exec quoting of the JSON argument) was replaced by execFile with argument arrays in PR #67 (2026-01-29). That change ships in npm 0.1.1, so the bug may already be fixed in practice. Windows behaviour is unverified, not known-broken.
  - evidence: https://github.com/Coding-Solo/godot-mcp/issues/49 ; https://github.com/Coding-Solo/godot-mcp/pull/67
- **godot_mcp-08** [confirmed] In Godot 4.7.2, `-d` (local stdout debugger) without interactive stdin loops forever at `debug>` on a runtime script error: 4,321 prompts in 20 s, killed by timeout. GdUnit4's runtest.cmd documents the same issue and passes `--remote-debug tcp://127.0.0.1:0` to avoid it.  
  src: local-test: timeout 20 "$GODOT_BIN" -d --headless --path <scratchpad>/proj res://rt_err.tscn < /dev/null ; D:\prime-game\addons\gdUnit4\runtest.cmd (local-test)
- **godot_mcp-09** [confirmed] Godot 4.7.2 exits with code 0 even when a runtime SCRIPT ERROR occurred (run with --quit-after), so exit codes alone do not show runtime errors.  
  src: local-test: "$GODOT_BIN" -d --remote-debug tcp://127.0.0.1:0 --headless --quit-after 60 --path <scratchpad>/proj res://rt_err.tscn (local-test)
- **godot_mcp-10** [corrected] ee0pdt/Godot-MCP: MIT, 616 stars, last commit 2025-03-19, requires an editor plugin, 19 tools (get-scene-tree, read-script, modify-script, run-project, ...).  
  src: https://github.com/ee0pdt/Godot-MCP (repo)
  - CORRECTED: ee0pdt/Godot-MCP: MIT, 616 stars, last commit 2025-03-19, requires the addons/godot_mcp editor plugin. Its README lists 19 kebab-case 'commands' (get-scene-tree, read-script, run-project, ...), but the server source registers only 16 snake_case tools: create_node, create_resource, create_scene, create_script, create_script_template, delete_node, edit_script, execute_editor_script, get_current_scene, get_node_properties, get_project_info, get_script, list_nodes, open_scene, save_scene, update_node_property. There is no run-project tool in code, and execute_editor_script runs arbitrary code.
  - evidence: https://github.com/ee0pdt/Godot-MCP/tree/main/server/src/tools
- **godot_mcp-11** [confirmed] bradypp/godot-mcp: MIT, 90 stars, last commit 2025-05-31. It is a Coding-Solo-style toolset plus edit_node/remove_node, has READ_ONLY_MODE, and claims Godot 3.5+/4.x.  
  src: https://github.com/bradypp/godot-mcp (repo)
- **godot_mcp-12** [confirmed] GDAI MCP: $19 one-time, '© Delano Lourenco. All rights reserved'. Requires an editor plugin and `uv` (Python). The Godot editor must stay open. HTTP port 9090. Claude Code install: `claude mcp add gdai-mcp uv run /absolute/path/to/addons/gdai-mcp-plugin-godot/gdai_mcp_server.py`. Claims Godot 4.2+.  
  src: https://gdaimcp.com/docs/installation ; https://gdaimcp.com (official-docs)
- **godot_mcp-13** [corrected] GDAI tools include get_godot_errors, get_editor_screenshot, get_running_scene_screenshot, play_scene and execute_editor_script (arbitrary GDScript). It has no docs lookup or input simulation. The changelog's latest is 0.3.3; 0.3.0 added Godot 4.6 compatibility; there is no explicit 4.7 entry.  
  src: https://gdaimcp.com/docs/supported-tools ; https://gdaimcp.com/changelog (changelog)
  - CORRECTED: GDAI tools include get_godot_errors, get_editor_screenshot, get_running_scene_screenshot, play_scene and execute_editor_script. It has no docs lookup, but it DOES have input simulation: changelog 0.2.7 'Now AI can simulate inputs in your game!' and 'Added tools get_input_map and simulate_input', and the homepage says 'Simulate keyboard input in games'. The supported-tools page omits them. The latest changelog entry is 0.3.3; 0.3.0 mentions Godot 4.6; nothing mentions 4.7.
  - evidence: https://gdaimcp.com/changelog
- **godot_mcp-14** [corrected] Godot MCP Pro (youichi-uda): $15, proprietary. The GitHub repo holds only the addon; the MCP server ships only in the paid zip. 187 tools with Full/3D/Lite(88)/Minimal(35) modes, WebSocket port 6505 (scans to 6509). v1.17.1 released 2026-09-24. The Asset Library lists Godot 4.4.  
  src: https://github.com/youichi-uda/godot-mcp-pro ; https://godotengine.org/asset-library/asset/4961 (repo)
  - CORRECTED: Godot MCP Pro (youichi-uda): $15 one-time. The public repo holds only the addon, which is MIT-licensed per LICENSE; the TypeScript MCP server is proprietary and ships only in the paid zip. The README gives 187 tools, Full(187)/--3d/Lite(88)/Minimal(35), and WebSocket 6505 with an auto-scan of 6505-6509 (the GitHub description still says 162 tools). GitHub release v1.17.1 is from 2026-09-24. The Asset Library entry 4961 shows godot_version 4.4, v1.16.0, cost 'Proprietary'.
  - evidence: https://github.com/youichi-uda/godot-mcp-pro/blob/main/LICENSE ; https://godotengine.org/asset-library/api/asset/4961
- **godot_mcp-15** [corrected] tugcantopaloglu/godot-mcp: MIT, 468 stars, v3.1.0 (2026-07-13), 157 tools, description says 'Tested with Godot 4.7', Node >=18. Runtime tools need an autoload McpInteractionServer (TCP 127.0.0.1:9090). Includes game_eval ('Execute arbitrary GDScript'), validate_scripts and game_screenshot. Individual tools cannot be disabled; GODOT_MCP_ALLOWED_DIRS restricts paths.  
  src: https://github.com/tugcantopaloglu/godot-mcp (repo)
  - CORRECTED: tugcantopaloglu/godot-mcp: MIT, 468 stars, v3.1.0 (2026-07-13), 157 tools, 'Tested with Godot 4.7', Node >=18. The game_* tools need an McpInteractionServer autoload (TCP 127.0.0.1:9090). It includes game_eval (arbitrary GDScript), validate_scripts and game_screenshot. GODOT_MCP_ALLOWED_DIRS restricts only run_project, not all paths. The server has no documented per-tool toggle, but Claude Code deny rules (e.g. mcp__godot__game_eval) can remove individual tools. The MCP registry still lists it at 1.0.0 (2026-03-07).
  - note: Its README also says validate_script moved from --check-only at _init() to _initialize() to avoid false 'Identifier not found' errors for autoloads. That is directly relevant to the proposed `check` (see missed facts).
  - evidence: https://github.com/tugcantopaloglu/godot-mcp#environment-variables
- **godot_mcp-16** [corrected] hybridindie/godot-mcp: MIT, 25 stars, release 2026.09.28. Python 3.11+ (PyPI godot-editor-mcp); the addon dials ws://127.0.0.1:9080. 193 tools in 27 toggleable toolsets; '4.7 validated'. Safety classes (read_only/mutating/destructive/runtime), confirm=True for destructive tools, dry_run for mutations.  
  src: https://github.com/hybridindie/godot-mcp (repo)
  - CORRECTED: hybridindie/godot-mcp: MIT, 25 stars, release 2026.09.28, PyPI godot-editor-mcp, Python 3.11+; the addon dials ws://127.0.0.1:9080. 193 tools across 29 categories: an always-on core plus 28 toggleable toolsets, of which only 'inspection' is on by default (27 gated off). Godot '4.7 (validated target)'. Safety classes read_only/mutating/destructive/runtime, confirm=True for destructive tools, dry_run for mutations. Runtime input tools need an extra mcp_runtime_probe.gd autoload.
  - evidence: https://github.com/hybridindie/godot-mcp
- **godot_mcp-17** [corrected] Erodenn/godot-mcp-runtime: MIT, 78 stars, registry v3.8.0 (2026-09-20), Node 20+. No addon: it injects a transient autoload McpBridge with a localhost TCP listener during run_project/attach_project. Screenshots come back as a 960x540 inline preview plus a PNG on disk. run_script is gated by GODOT_MCP_STRICT/GODOT_MCP_DISABLE_SECURITY.  
  src: https://github.com/Erodenn/godot-mcp-runtime (repo)
  - CORRECTED: Erodenn/godot-mcp-runtime: MIT, 78 stars, Node >=20; the registry latest is 3.8.0 (2026-09-20), GitHub/package.json 3.8.1 (2026-09-25). There is no addon, but run_project/attach_project write an [autoload] McpBridge entry into project.godot (read-modify-write), add '.mcp/' to .gitignore and create .mcp/godot-runtime/, and clean up on stop. So tracked files change during a session, which is not 'no repo footprint'. Like Coding-Solo it keeps a single activeProcess (it kills the previous spawn) and refuses to run without a display. Screenshots: a 960x540 inline preview plus the PNG on disk. run_script/run_project pass a static-scan and elicitation gate. GODOT_MCP_STRICT="true" hard-rejects, and GODOT_MCP_DISABLE_SECURITY="true" disables the gate. The source entry point is dist/index.js.
  - evidence: https://github.com/Erodenn/godot-mcp-runtime/blob/main/src/utils/bridge-manager.ts ; https://github.com/Erodenn/godot-mcp-runtime/blob/main/src/utils/godot-runner.ts ; https://github.com/Erodenn/godot-mcp-runtime/blob/main/docs/security.md
- **godot_mcp-18** [confirmed] n24q02m/better-godot-mcp (Apache-2.0) was archived 2026-09-13. Notice: 'Use the Godot editor + GDScript CLI toolchain instead of this MCP server.'  
  src: https://github.com/n24q02m/better-godot-mcp (repo)
- **godot_mcp-19** [confirmed] The official MCP registry search for 'godot' returns about 18 distinct servers (latest versions), e.g. Erodenn/godot-mcp-runtime, tugcantopaloglu/godot-mcp, beckettlab/beckett-godot-mcp, FunplayAI/funplay-godot-mcp, satelliteoflove/godot-mcp, tomyud1/godot-mcp, salvo10f/godotiq, gregario/godot-forge. None is published by godotengine.  
  src: https://registry.modelcontextprotocol.io/v0/servers?search=godot&limit=100 (official-docs)
- **godot_mcp-20** [confirmed] There is no official Godot MCP effort. The godotengine org has no MCP repo, and a godot-proposals search for 'MCP' finds only unrelated or general items (e.g. #14090 'LLM tie in', open). bebabinlarsson-blip/Godot-MCP calls itself the 'Official Plugin' but is a personal repo created 2026-09-17 with 21 stars.  
  src: local-test: gh search issues MCP --repo godotengine/godot-proposals ; gh search repos mcp --owner godotengine ; https://github.com/bebabinlarsson-blip/Godot-MCP (local-test)
- **godot_mcp-21** [confirmed] Claude Code tool search is on by default. At session start only MCP tool names and server instructions load; full schemas load on demand. ENABLE_TOOL_SEARCH can be unset/true (deferred), auto (load upfront while definitions are under 10% of context), auto:N, or false. Per-server `alwaysLoad: true` skips deferral.  
  src: https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search (official-docs)
- **godot_mcp-22** [confirmed] The context-cost table lists MCP servers as 'Tool names; full schemas on demand' with cost 'Low until a tool is used'. `/context all` shows how many tokens each loaded MCP tool uses.  
  src: https://code.claude.com/docs/en/features-overview (official-docs)
- **godot_mcp-23** [confirmed] MCP output: warning above 10,000 tokens, default max 25,000 (MAX_MCP_OUTPUT_TOKENS); text over the limit is saved to a file in tool-results. Saving MCP image results to a file requires Claude Code v2.1.283 or later.  
  src: https://code.claude.com/docs/en/mcp (official-docs)
- **godot_mcp-24** [confirmed] Project-scoped .mcp.json servers need interactive approval per user. Controls: enableAllProjectMcpServers, enabledMcpjsonServers, disabledMcpjsonServers. .mcp.json supports ${VAR} and ${VAR:-default} expansion. Docs: 'Verify you trust each server before connecting it.'  
  src: https://code.claude.com/docs/en/mcp (official-docs)
- **godot_mcp-25** [corrected] Subagent frontmatter `mcpServers` accepts inline definitions (stdio/http/sse/ws) that connect only while the subagent runs and stay out of the main context; they need folder trust. Subagents inherit the main session's MCP tools by default. tools/disallowedTools accept `mcp__<server>` and `mcp__<server>__*`.  
  src: https://code.claude.com/docs/en/sub-agents (official-docs)
  - CORRECTED: Subagent `mcpServers` accepts inline stdio/http/sse/ws definitions that connect only while the subagent runs and stay out of the main context. Subagents inherit all available tools, including MCP, when `tools` is omitted. tools/disallowedTools accept mcp__<server> and mcp__<server>__*. The folder-trust requirement for inline servers in project agent files applies only from v2.1.238 ('Before v2.1.238, Claude Code loaded these servers without checking trust'). On the installed 2.1.195 they load without any trust check.
  - evidence: https://code.claude.com/docs/en/sub-agents#scope-mcp-servers-to-a-subagent
- **godot_mcp-26** [confirmed] Installed Claude Code is 2.1.195; the public changelog head is 2.1.283. `alwaysLoad` was added in 2.1.121, and inline agent `mcpServers` handling exists by 2.1.153, so both are available locally. Features documented for later versions (e.g. MCP image-to-file in 2.1.283) are not.  
  src: local-test: claude --version ; https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (changelog)
- **godot_mcp-27** [confirmed] `godot --headless --path P --check-only --script res://file.gd` on 4.7.2 reports Godot 3 idioms explicitly: 'The "export" keyword was removed in Godot 4...', '"yield" was removed in Godot 4. Use "await" instead.', 'argument 2 should be "Callable"' (3-argument connect), 'Static function "get_ticks_msec()" not found', 'Function "rset()" not found', 'Too many arguments for "move_and_slide()"'. Exit 1, about 0.4–0.5 s per file.  
  src: local-test: & $env:GODOT_BIN --headless --path <scratchpad>\proj --check-only --script res://godot3c.gd (local-test)
- **godot_mcp-28** [confirmed] gdlint 4.5.0 reports 'no problems found' on files using yield(), 3-argument connect(), OS.get_ticks_msec() and rset(). It only fails on syntax it cannot parse (e.g. `export var`).  
  src: local-test: "$GDTOOLKIT_DIR/gdlint.exe" <scratchpad>/proj/godot3b.gd <scratchpad>/proj/godot3c.gd (local-test)
- **godot_mcp-29** [confirmed] With `gdscript/warnings/untyped_declaration=2` under [debug] in project.godot, --check-only fails with 'Variable "untyped" has no static type. (Warning treated as error.)'.  
  src: local-test: & $env:GODOT_BIN --headless --path <scratchpad>\proj --check-only --script res://typed_bad.gd (local-test)
- **godot_mcp-30** [confirmed] Per-file --check-only fails with 'Could not find type "NewRole"' for a class_name declared in a new file until `godot --headless --path P --import` refreshes the global class cache (3.4 s on a tiny project). After that it passes.  
  src: local-test: "$GODOT_BIN" --headless --path <scratchpad>/proj --check-only --script res://uses_role.gd (before/after) "$GODOT_BIN" --headless --path <scratchpad>/proj --import (local-test)
- **godot_mcp-31** [confirmed] A SceneTree script that loads every .gd with ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE) and checks can_instantiate() reports all parse failures in one process (checked=5 failed=4, exit 1). When it also loaded itself, Godot crashed with exit 139.  
  src: local-test: "$GODOT_BIN" --headless --path <scratchpad>/proj --script res://tools/check_scripts.gd (local-test)
- **godot_mcp-32** [confirmed] A non-headless SceneTree screenshot script (await RenderingServer.frame_post_draw; root.get_viewport().get_texture().get_image().save_png()) produced a correct 640x360 PNG in 5.8 s (Vulkan Forward+, RTX 4060), and the agent could read the image. The same script under --headless hung for more than 120 s and had to be killed.  
  src: local-test: "$GODOT_BIN" --path <scratchpad>/proj --resolution 640x360 --script res://tools/shot.gd -- res://shot_scene.tscn <scratchpad>/shot.png (local-test)
- **godot_mcp-33** [confirmed] `godot --headless --doctool <dir>` dumps 1,076 XML files (4.1 MB) in 1.6 s, including modules/gdscript/doc_classes/@GDScript.xml with all annotations (@export*, @onready, @rpc, @abstract, ...). In the official build every description is empty and there are 0 deprecated attributes (CharacterBody3D.xml is 5,573 B vs 17,440 B upstream). It prints 'Erasing old docs at: ...' for the target path.  
  src: local-test: & $env:GODOT_BIN --headless --doctool <scratchpad>\doctool (local-test)
- **godot_mcp-34** [confirmed] `godot --headless --dump-extension-api-with-docs` writes extension_api.json (11.9 MB) to the current directory in 1.4 s. The header says version 4.7.2 stable official. It has 1,036 classes with brief/full descriptions and per-method descriptions (e.g. CharacterBody3D.move_and_slide) but no GDScript annotations.  
  src: local-test: (cwd <scratchpad>\extapi) & $env:GODOT_BIN --headless --dump-extension-api-with-docs (local-test)
- **godot_mcp-35** [confirmed] Tag 4.7.2-stable is commit ed1daf0bf..., which matches the local binary's build hash (4.7.2.stable.official.ed1daf0bf). Upstream doc/classes/*.xml at that tag include descriptions and deprecated= attributes. godot-docs has a 4.7 branch, and https://docs.godotengine.org/en/4.7/ is live, including the upgrading_to_godot_4 page (converter flags --convert-3to4 / --validate-conversion-3to4).  
  src: local-test: gh api repos/godotengine/godot/git/refs/tags/4.7.2-stable ; https://github.com/godotengine/godot/tree/4.7.2-stable/doc/classes ; https://docs.godotengine.org/en/4.7/tutorials/migrating/upgrading_to_godot_4.html (official-docs)
- **godot_mcp-36** [confirmed] A headless ClassDB lookup script (ClassDB.class_exists / class_get_method_list / class_has_method) on the pinned binary returned 'NO SUCH CLASS ... KinematicBody', 'NOT FOUND: Node.rset' and 'func move_and_slide()'. Variant-typed args print as 'Nil' (cosmetic).  
  src: local-test: "$GODOT_BIN" --headless --path <scratchpad>/proj --script res://tools/api_lookup.gd -- Node rset (local-test)
- **godot_mcp-37** [confirmed] Context7 has library /websites/godotengine_en_4_7 (source docs.godotengine.org/en/4.7, 24,864 snippets, about 2.7M tokens, updated about 2 weeks ago). It also has /websites/godotengine_en_3_6 and /websites/godotengine_en (latest).  
  src: https://context7.com/websites/godotengine_en_4_7 (official-docs)
- **godot_mcp-38** [confirmed] Context7 MCP tools are resolve-library-id(query, libraryName) and query-docs(libraryId, query); remote endpoint https://mcp.context7.com/mcp. A free API key raises rate limits. CLI alternative ctx7 (0.5.12, Node 18+): `ctx7 docs <libraryId> <query>`. @upstash/context7-mcp is 4.1.1; the repo is MIT with 62k stars.  
  src: https://github.com/upstash/context7 ; local-test: npm view @upstash/context7-mcp version ; npm view ctx7 version (repo)
- **godot_mcp-39** [confirmed] CVE-2026-75130 (published 2026-08-18): 'Context7 through 2.1.2' allowed prompt injection via Custom AI Instructions served through the MCP server, enabling credential exfiltration and file deletion. CVSS 3.1 9.0 CRITICAL / CVSS 4.0 6.4 MEDIUM.  
  src: https://nvd.nist.gov/vuln/detail/CVE-2026-75130 (local-test: curl "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-75130") (official-docs)
- **godot_mcp-40** [confirmed] `godot --headless -e --path P --lsp-port 6123` starts the GDScript language server listening on 127.0.0.1 within about 1 s. Anthropic's official code-intelligence plugin list has no GDScript entry. Community TCP-to-stdio bridge plugins exist: Sods2/claude-code-gdscript-lsp (7 stars, last push 2026-03-15), twaananen/claude-code-gdscript (5 stars).  
  src: local-test: Start-Process $env:GODOT_BIN '--headless','-e','--path',<scratchpad>\proj,'--lsp-port','6123' + Get-NetTCPConnection -LocalPort 6123 ; https://code.claude.com/docs/en/plugins/code-intelligence ; https://github.com/Sods2/claude-code-gdscript-lsp (local-test)
- **godot_mcp-41** [confirmed] Godot docs MCPs: tkmct/godot-doc-mcp indexes --doctool XML (tools godot_search, godot_get_class, godot_get_symbol, godot_list_classes; posted 2025-09-22). Nihilantropy/godot-mcp-docs: 74 stars, last push 2025-07-25.  
  src: https://forum.godotengine.org/t/made-a-mcp-server-for-offline-godot-api-documentation-reference/123041 ; https://github.com/Nihilantropy/godot-mcp-docs (blog)
- **godot_mcp-42** [confirmed] GdUnit4 6.2.1 runtest.cmd reads GODOT_BIN (or --godot_binary) and runs `"%GODOT_BIN%" --path . -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd`. CLI options: -a/--add, -i/--ignore, -c/--continue, -conf, -rd/--report-directory, -rc/--report-count, --ignoreHeadlessMode ('running GdUnit4 in headless mode is not allowed' by default).  
  src: D:\prime-game\addons\gdUnit4\runtest.cmd ; D:\prime-game\addons\gdUnit4\src\core\runners\GdUnitTestCIRunner.gd (repo)
- **godot_mcp-43** [unverifiable] Estimate: with tool search, an idle server costs about 10–15 tokens per tool name per request (about 150–200 tokens for Coding-Solo's 14 tools, about 1.5–2.5k for a 157–193 tool server), plus server instructions. Each schema loaded on demand costs a few hundred tokens.  
  src: inferred from https://code.claude.com/docs/en/context-window.md ('MCP tools (deferred)' ~120 tokens example) (inferred)
  - note: The context-window page's '120 tokens' is one illustrative example for the whole deferred-MCP block, not a per-name rate. No primary source gives per-tool-name costs; measure with /context all.

## Missed facts (from verifier)

- **mf-01** Both the per-file `--check-only --script` and the proposed SceneTree batch check running in `_init()` report FALSE errors ('Compile Error: Identifier not found: GameBus') for any script that references an autoload singleton. Running the same batch loop from `_initialize()` passes. Every networked Godot game uses autoloads, so the proposed `check` would be red from day one.  
  src: local-test: project with [autoload] GameBus="*res://game_bus.gd"; check-only uses_bus.gd -> exit 1; check_scripts.gd (_init) -> failed=1; same loop in _initialize -> failed=0. Corroborated by https://github.com/tugcantopaloglu/godot-mcp (validate_script note)
- **mf-02** `untyped_declaration=2` alone does not catch calls to nonexistent methods on autoloads or other loosely typed values (`GameBus.nope()` passed). With `gdscript/warnings/unsafe_method_access=2` (and unsafe_property_access=2) the batch check fails with 'The method "nope()" is not present on the inferred type "res://game_bus.gd"'.  
  src: local-test: <scratch>/zz_mcpfc_9q7 equivalent project (p3), check loop in _initialize before/after adding unsafe_* =2
- **mf-03** The 4.7.2 binary's `--headless --path P --validate-conversion-3to4` is a read-only, whole-project Godot-3-idiom detector (files were unchanged by md5). It reports several idioms per file with the 4.x replacement (KinematicBody->CharacterBody3D, Camera->Camera3D, yield->await, 3-arg connect->Callable, export->@export, OS.get_ticks_msec->Time.get_ticks_msec) in about 0.3 s. It exits 0, so parse its 'files which would be converted(N)' line, and it emitted an 'ERROR: PCRE2 Error: unknown substring' line. It missed rset().  
  src: local-test: "$GODOT_BIN" --headless --path <scratch>/zz_mcpfc_9q7/p4 --validate-conversion-3to4 ; https://docs.godotengine.org/en/4.7/tutorials/migrating/upgrading_to_godot_4.html
- **mf-04** The ClassDB lookup prototype gives false negatives: `CharacterBody3D velocity` prints 'NOT FOUND' (properties, signals and constants are not checked), and `Vector3 lerp` prints 'NO SUCH CLASS' (Variant built-ins and @GDScript/@GlobalScope are not in ClassDB). extension_api.json contains builtin_classes, properties, return types, default args, is_vararg and utility_functions.  
  src: local-test: "$GODOT_BIN" --headless --path <proj> --script res://tools/api_lookup.gd -- CharacterBody3D velocity | Vector3 lerp
- **mf-05** Running without -d at all still prints 'SCRIPT ERROR: ...' plus a GDScript backtrace for runtime errors and exits 0. Copying GdUnit4's `--remote-debug tcp://127.0.0.1:0` adds two 'ERROR:' lines to every run (port must be 1-65535; Unable to connect to host '127.0.0.1:0').  
  src: local-test: "$GODOT_BIN" [-d --remote-debug tcp://127.0.0.1:0] --headless --quit-after 60 --path <proj> res://rt_err.tscn
- **mf-06** Erodenn/godot-mcp-runtime writes an [autoload] McpBridge entry into project.godot (its code notes an accepted race window when two servers read-modify-write it), appends '.mcp/' to .gitignore and creates .mcp/. It keeps one active Godot process (it kills the previous spawn) and throws 'No display server available' without DISPLAY/WAYLAND_DISPLAY. The documented strict value is GODOT_MCP_STRICT="true", and the source entry point is dist/index.js.  
  src: https://github.com/Erodenn/godot-mcp-runtime/blob/main/src/utils/bridge-manager.ts
- **mf-07** `enableAllProjectMcpServers: false` in a committed settings.json is a no-op: it is the default and only concerns auto-approving .mcp.json entries. Enforcing controls, all valid in 'Any file': disabledMcpjsonServers (rejects named .mcp.json servers), deniedMcpServers (serverName/serverCommand/serverUrl patterns, merged across files), and allowedMcpServers (an empty array blocks every user-added server, including the humans' personal ones). Claude Code permission deny rules such as mcp__<server>__<tool> can remove single tools such as eval.  
  src: https://code.claude.com/docs/en/settings-reference (enableAllProjectMcpServers, disabledMcpjsonServers, deniedMcpServers, allowedMcpServers)
- **mf-08** The installed Claude Code 2.1.195 predates several trust gates the proposal relies on: inline subagent mcpServers trust check (v2.1.238), project-agent frontmatter hooks trust check (v2.1.218), ignoring committed .mcp.json approvals in untrusted folders (v2.1.196), and local-settings approvals waiting for trust (v2.1.207).  
  src: https://code.claude.com/docs/en/sub-agents#scope-mcp-servers-to-a-subagent ; https://code.claude.com/docs/en/mcp#project-server-approvals-and-workspace-trust
- **mf-09** In Godot 4.7 `debug/gdscript/warnings/exclude_addons` no longer exists (ProjectSettings returns MISSING). It is replaced by `debug/gdscript/warnings/directory_rules` with default {"res://addons": 0}, so addons (GdUnit4) are excluded from warnings-as-errors by default.  
  src: local-test: SceneTree script printing ProjectSettings.get_setting("debug/gdscript/warnings/directory_rules") on 4.7.2
- **mf-10** Neither `shot` nor any runtime MCP works on a display-less CI runner. The screenshot script hangs under --headless (frame_post_draw never fires), and Erodenn refuses to run without DISPLAY. CI screenshots need xvfb plus a software renderer, or should be local-only.  
  src: local-test: headless shot.gd killed by timeout 30 ; https://github.com/Erodenn/godot-mcp-runtime/blob/main/src/utils/godot-runner.ts (checkDisplayAvailable)

## Options

### A. Pure CLI (no MCP); task runner + engine-derived API reference
All verification goes through the committed task runner:
- `check`: `--import`, then a batch parse via a SceneTree script, with strict typing warnings as errors.
- `test`: GdUnit4 `runtest.cmd`.
- `shot`: a non-headless SceneTree PNG script; the agent reads the PNG with the Read tool.
- `bots`: multi-process headless host plus clients.
- Logs: `--log-file`/stdout scanned for SCRIPT ERROR.

godot-api-checker uses, in order: the parse check, a ClassDB lookup script, and a locally dumped `extension_api.json` plus doctool XML (and upstream XML at tag 4.7.2-stable) in `tools/out/`. For guides it uses WebFetch pinned to docs.godotengine.org/en/4.7/.
- pros: Same commands and binary in CI and locally, so the agent's verification matches CI exactly; Engine-authoritative: the 4.7.2 binary itself rejects Godot 3 syntax and wrong APIs (verified locally); No new runtime, addon, port or third-party code; nothing extra for either human to approve or trust; Supports what the project really needs: multiple processes (host + N bots), log assertions, info-leak tests; All tooling is committed text that humans can review in Rider; the designer's agent gets the same commands; Zero MCP context cost
- cons: No live editor introspection (editor scene tree, editor screenshots) while a human has the editor open; No ready-made input simulation or runtime eval; must be built into the bot harness and dev console (the project needs those anyway); A few hundred lines of runner/lookup scripts to write and maintain; Screenshots need a GPU desktop session (not --headless)
### B. Add a headless MCP (Coding-Solo/godot-mcp) on top of the CLI
Add the 14-tool Node server via .mcp.json or scoped to a subagent. It gives launch_editor, run_project + get_debug_output, and scene-building helpers.
- pros: Popular (5.9k stars), MIT, no editor plugin; Small tool surface and low context cost with tool search
- cons: Duplicates what the runner does, with less control (single process, no headless, no log assertions); run_project uses `-d`, which freezes on the first runtime error without interactive stdin (verified behaviour of -d); npm 0.1.1 predates the April 2026 RCE fix; would need a pinned git build; 4.7 support question unanswered; Windows quoting bug open; portable-path detection fails without GODOT_PATH; Not usable in CI, so verification parity breaks
### C. Editor-plugin MCP (GDAI, Godot MCP Pro, hybridindie, tomyud1, ...)
An addon in addons/ plus a local server (Node, Python/uv or HTTP) that drives the live Godot editor: scene tree read/edit, editor and game screenshots, input simulation, errors panel, arbitrary editor scripts.
- pros: Live view of what the designer sees in the editor; useful for level-design help at M4+; Screenshots and input simulation out of the box; hybridindie has toolset gating, dry_run and confirm, and says it is 4.7 validated
- cons: Adds an addon (KICKOFF: ask before adding) that runs code inside both humans' editors and opens localhost ports; Agent edits of open scenes through the editor conflict with the single-owner scene rule and with human edits; The editor must be open, which breaks unattended/headless verification; unusable in CI; The two best-featured are paid and proprietary (GDAI $19 all rights reserved; MCP Pro $15, server closed); Most expose arbitrary GDScript execution; young projects with one maintainer each
### D. Runtime-bridge MCP scoped to one playtest subagent (Erodenn/godot-mcp-runtime or tugcantopaloglu/godot-mcp)
The server injects a transient or required autoload into a running game for live scene-tree inspection, screenshots, input simulation and eval. It is defined inline in one subagent's `mcpServers`, so the main sessions never see its tools.
- pros: Erodenn needs no addon and makes no permanent project change; tugcantopaloglu says it was tested with 4.7; Input simulation plus screenshots are useful for first-person UX checks at M4/M5; Inline subagent scoping keeps main-context cost at zero
- cons: Eval/arbitrary GDScript and a TCP listener in the game process; Overlaps with the bot harness and dev console the project must build anyway (bots need scripted input for CI); Young projects (78 and 468 stars); another Node runtime to pin and review; Still not usable in CI
### E. Context7 (MCP or ctx7 CLI) for Godot docs, pinned to /websites/godotengine_en_4_7
Cloud search over the 4.7 docs site (tutorials plus class reference prose), given only to godot-api-checker.
- pros: Good for tutorial-style questions (high-level multiplayer, audio buses) that signatures cannot answer; The 4.7-specific library exists and was updated recently; Can be scoped to the subagent; the CLI variant avoids MCP entirely
- cons: Third-party cloud; queries leave the machine; API key and rate limits; CVE-2026-75130 shows doc content can carry prompt injection; Also hosts 3.6 and 'latest' libraries, so an unpinned resolve can return Godot 3 docs; WebFetch pinned to docs.godotengine.org/en/4.7/ gives the same content from the first-party source
### F. Community GDScript LSP plugin (TCP-to-stdio bridge to the Godot language server)
The Claude Code LSP tool plus automatic diagnostics after each .gd edit, served by a headless Godot editor with --lsp-port.
- pros: Engine-authoritative diagnostics right after each edit, plus go-to-definition; Verified locally that a headless editor serves LSP on 127.0.0.1 within about 1 s
- cons: Third-party plugins with fewer than 10 stars; plugin plus Node bridge to review and pin; Keeps an editor process running that writes .godot/ alongside the human's editor; port clashes with the human editor's default 6005; A PostToolUse hook running the parse check gives similar feedback with no new dependency

## Recommendation

**MCP decision (for approval):** adopt Option A (pure CLI) for M0–M3 and do not install any Godot MCP server. Record this as an ADR with a revisit point at the start of M4 (first-person greybox and level work).

**Why this fits this project:**
- **Humans write zero code and verify by reading.** Every verification step should be a committed command that CI runs identically. MCP tools are invisible to CI and to the other human's session unless both approve and maintain them.
- **The hard problems here are multi-process** (listen-server host + N bot clients, information-leak assertions). The most popular MCP runs one process at a time with `-d`, which freezes on the first runtime error.
- **The CLI already does the MCP value-adds, tested locally on 4.7.2:**
  - parse and API errors with explicit Godot-3-removal messages
  - PNG screenshots the agent can read
  - an exact API reference dumped from the pinned binary
- **Security and maintenance:** the ecosystem is 18+ competing servers with one maintainer each, RCE fixes that lag npm, eval tools, localhost ports and impostor 'official' names. That is a poor trade for a two-person repo, where adding a dependency needs human approval.
- **Context cost is not the argument.** Tool search makes idle MCP cheap, and an inline subagent `mcpServers` makes it free for the main context. So if M4 needs live runtime inspection or input simulation, trial Option D inside a single `playtest-observer` subagent with a pinned commit. Erodenn/godot-mcp-runtime is first choice because it needs no addon. Only do this after the bot harness exists and only if the harness cannot cover the need.

**godot-api-checker:**
- **Authority order:**
  1. `tools/run check`: `--import` then the batch parse with untyped_declaration as error, run by the same binary as CI.
  2. `tools/run api <Class> [member]`: a ClassDB lookup on the pinned binary.
  3. Grep over `tools/out/godot-api/4.7.2/` (`extension_api.json` with docs, doctool XML for GDScript annotations, and optionally upstream XML at tag 4.7.2-stable for deprecations), regenerated by `doctor` when the version changes.
  4. WebFetch restricted to https://docs.godotengine.org/en/4.7/ for guides.
- **Never:** memory, /stable/, /latest/, 3.x docs, or unpinned Context7.
- **Context7:** optional and off by default. If the engineer wants it, use the ctx7 CLI or an inline subagent MCP pinned to /websites/godotengine_en_4_7.
- **Idiom grep list:** add a short Godot-3 deny-list in the checker prompt for things the parser cannot see (comments, docs, strings, untyped dynamic calls).
- **Model and tools:** a cheaper model (haiku) with tools Read, Grep, Glob, Bash, WebFetch.

## Verifier critique of recommendation

The direction holds up: pure CLI for M0-M3, no Godot MCP, an ADR with a revisit at M4. Every popular server I checked keeps one active Godot process (Coding-Solo, Erodenn), needs an editor plugin/autoload (ee0pdt, GDAI, Pro, tugcan, hybridindie) or ships closed (Pro server, GDAI). None can drive a listen-server host plus N bot clients. The Coding-Solo security point is stronger than stated: the npm 0.1.1 build on unpkg still has the load(name) RCE fallback.

Four parts of the justification need fixing before this goes to the humans:
1. The 'CLI already does it' claim rests on a `check` that is broken for real projects. --check-only and the _init()-based batch loop both fail every script that references an autoload. The loop must run in _initialize(), and per-file --check-only should not be used in hooks. tugcan's MCP already documents this fix; the researcher missed it.
2. `untyped_declaration=2` is not enough for API checking. unsafe_method_access and unsafe_property_access as errors are what caught a bad call through an autoload. Present that as an option for the humans because it costs explicit casts.
3. The ClassDB 'api' oracle should not outrank extension_api.json. It misreports properties and all Variant built-ins. Make extension_api.json (plus doctool XML for annotations) the signature source, or extend the script to cover properties, signals, constants and builtin_classes and to print return types and defaults.
4. The Godot-3 idiom grep list duplicates an engine feature. `--validate-conversion-3to4` is read-only, whole-project and suggests replacements. Keep grep only for comments and docs.

Weaker points:
- 'Erodenn first choice, no repo footprint' is inaccurate: it edits project.godot and .gitignore during runs and is single-process. For M4 input simulation, a debug-only input/inspection autoload inside the game is reviewable and CI-runnable; it fits the bot harness and 'humans read diffs' better than any MCP. If an MCP is trialled anyway, compare Erodenn with GDAI, which does have simulate_input (claim 13 was wrong).
- 'Individual tools cannot be disabled' is not a real blocker: Claude Code deny rules remove single MCP tools.
- The security argument for inline subagent MCP assumes trust gating that the installed 2.1.195 lacks (added in 2.1.238). Updating Claude Code is a human decision the document should surface.
- godot-api-checker is called read-only but gets Bash. Scope Bash with a PreToolUse hook that allows only `tools/run check|api|api-ref`, or with permission rules. WebFetch can be limited to docs.godotengine.org by domain only; the /en/4.7/ path limit is prompt-only.
- haiku is reasonable, but test for false positives, given how many ways the oracles can mislead (see 3 above).
- Context7: the real unpinned risk is the master-branch godot-docs (future API), not only 3.6. The CVE framing is fair.
- Context cost: the estimate in claim 43 is unsourced. Rely on the doc statement and /context all.

## Concrete config (researcher)

PROPOSAL ONLY: nothing below has been applied. The scratch prototypes that were tested are in C:\Users\xperi\AppData\Local\Temp\claude\D--prime-game\40c5c58a-0dc5-4821-beca-a406804c7d8a\scratchpad\proj\tools\ (check_scripts.gd, shot.gd, api_lookup.gd).

# 1) No Godot MCP in M0. Make the policy explicit in the shared .claude/settings.json:
{
  "enableAllProjectMcpServers": false
}
# (No .mcp.json is committed. Any future MCP server is added only through an ADR and scoped inline to one subagent.)

# 2) project.godot: strict typing as errors (verified to fail --check-only)
[debug]
gdscript/warnings/untyped_declaration=2

# 3) Task runner subcommands (inside the runner; GODOT_BIN from env)
# check  (whole-project, engine-authoritative)
"$GODOT_BIN" --headless --path . --import                         # refreshes the class_name cache; needed before parsing
"$GODOT_BIN" --headless --path . --script res://tools/check/check_scripts.gd
#   loads every res://**/*.gd except addons/ and itself with ResourceLoader.CACHE_MODE_IGNORE; exit 1 on any failure
# api-ref  (run by doctor when tools/out/godot-api/<ver>/ is missing or the version differs)
#   cwd = tools/out/godot-api/4.7.2   (dump writes into CWD; doctool ERASES its target dir, so never point it at the repo)
"$GODOT_BIN" --headless --dump-extension-api-with-docs            # extension_api.json, ~12 MB, with descriptions
"$GODOT_BIN" --headless --doctool tools/out/godot-api/4.7.2/xml   # signatures incl. @GDScript annotations (no prose)
gh api "repos/godotengine/godot/contents/modules/gdscript/doc_classes/@GDScript.xml?ref=4.7.2-stable" --jq .content  # base64 -> annotation prose (optional)
# api  (exact signatures from the running engine)
"$GODOT_BIN" --headless --path . --script res://tools/check/api_lookup.gd -- <Class> [member]
# shot  (never --headless: frame_post_draw never fires there; add an in-script watchdog timer + quit)
"$GODOT_BIN" --path . --resolution 1280x720 --script res://tools/shot/shot.gd -- <res://scene.tscn> tools/out/shots/<name>.png
# test
addons/gdUnit4/runtest.cmd -a res://tests -rd tools/out/reports --ignoreHeadlessMode   # (or runtest.sh); runtest reads GODOT_BIN
# Rule: never pass -d to Godot from the runner or an agent. If a debugger flag is needed, copy GdUnit4's `--remote-debug tcp://127.0.0.1:0`.
# Rule: exit code 0 is not success. Scan stdout/--log-file for 'SCRIPT ERROR' / '^ERROR:'.

# 4) .claude/agents/godot-api-checker.md
---
name: godot-api-checker
description: Read-only. Checks GDScript and scene changes against the pinned Godot 4.7.2 API and flags Godot 3 idioms. Use after editing .gd/.tscn files and before opening a PR.
model: haiku
tools: Read, Grep, Glob, Bash, WebFetch
---
You verify, you never edit. Sources of truth, in this order:
1. `tools/run check` output (engine parser, same binary as CI).
2. `tools/run api <Class> [member]` (ClassDB of the pinned 4.7.2 binary).
3. Grep in tools/out/godot-api/4.7.2/ (extension_api.json, xml/). If missing, run `tools/run api-ref`.
4. WebFetch only under https://docs.godotengine.org/en/4.7/ . Never /stable/, /latest/, /3.x/, blogs or memory.
Also grep changed files (code, comments, docs) for Godot 3 idioms: `yield(`, `^\s*export var`, `^\s*onready var`, `setget`, `KinematicBody`, `Spatial\b`, `remote func|master func|puppet func|remotesync`, `rset(`, `.instance()`, `connect\("[^"]+",\s*\w+,\s*"`, `OS.get_ticks_msec`, `File.new()`, `Directory.new()`, `PoolStringArray`, `deg2rad`, `rand_range`, `get_world()`.
Report: file:line, problem, the 4.7 replacement, and which source above confirmed it. If no source confirms, say "unverified".

# 5) Only if the M4 revisit approves a runtime MCP (Option D): scope it to one subagent, pinned, never in .mcp.json.
# Entry-point path, env-var expansion inside agent frontmatter, and GODOT_MCP_STRICT semantics are UNVERIFIED; check them before use.
---
name: playtest-observer
description: Observes a running local build (screenshots, scene tree, simulated input) for M4+ UX checks. Never edits files.
model: sonnet
tools: Read, Bash, mcp__godot-runtime
mcpServers:
  - godot-runtime:
      type: stdio
      command: node
      args: ["<local clone of Erodenn/godot-mcp-runtime at a pinned commit>/<built entry>.js"]
      env:
        GODOT_PATH: "<console exe path>"
        GODOT_MCP_STRICT: "1"
---

## Config corrections (verifier)

1) `"enableAllProjectMcpServers": false` is a no-op: it is the default and only covers auto-approval of .mcp.json. Drop it and put the policy in the ADR and CLAUDE.md. If enforcement is wanted, use `disabledMcpjsonServers` or `deniedMcpServers` patterns. Do not use `allowedMcpServers: []`, which blocks the humans' personal servers.
2) project.godot: `untyped_declaration=2` works as written. Offer `gdscript/warnings/unsafe_method_access=2` and `unsafe_property_access=2` (optionally unsafe_call_argument) as a human-approved option. Do not add `exclude_addons`: in 4.7 it is replaced by `directory_rules`, whose default already excludes res://addons.
3) check: check_scripts.gd must do its work in `_initialize()`, not `_init()`, or every autoload reference fails. It must exclude its own path (loading itself crashes with signal 11); excluding all of tools/ is not required. Keep `--import` first; it is required on a fresh clone and CI.
4) api-ref: the cwd is inconsistent. With cwd = tools/out/godot-api/4.7.2, `--doctool tools/out/godot-api/4.7.2/xml` would nest a second tools/out tree; use `--doctool xml` or absolute paths. The comment 'doctool ERASES its target dir' should say it merges and erases XML only in doc/classes and modules/*/doc_classes under the target. The gh api @GDScript.xml fetch works (51 KB).
5) api: api_lookup.gd must also check properties, signals and constants (class_get_property_list, class_has_signal, class_has_integer_constant). It must fall back to extension_api.json builtin_classes and utility_functions for Variant types such as Vector3 and Array, print return types, defaults and varargs, and exit non-zero on NOT FOUND. Until then, rank extension_api.json above it in the checker's authority order.
6) Debugger rule: do not copy `--remote-debug tcp://127.0.0.1:0`. It prints two ERROR: lines per run and trips the '^ERROR:' scan. Simply never pass -d; runtime SCRIPT ERROR lines and backtraces are still printed. Keep the log-scan rule, but whitelist or ignore known benign lines. Do not scan editor-mode output for translated strings; it is localized.
7) test: `runtest.cmd -a res://tests -rd tools/out/reports --ignoreHeadlessMode` has no `--headless`, so a window opens and --ignoreHeadlessMode does nothing. Add `--headless` for CI and agent runs (runtest forwards extra args to Godot; verify this). From PowerShell, call it as `& .\addons\gdUnit4\runtest.cmd` from the project root, because it uses `--path .`.
8) shot: correct that it must not be headless. Add a note that it cannot run on a display-less CI runner without xvfb and a software renderer.
9) godot-api-checker: 'Read-only' plus `Bash` is not read-only. Add a frontmatter PreToolUse hook (or permissions) that limits Bash to `tools/run check|api|api-ref`, and restrict WebFetch with `WebFetch(domain:docs.godotengine.org)`; the /en/4.7/ path limit can only be prompt-enforced. Replace most of the idiom grep list with `"$GODOT_BIN" --headless --path . --validate-conversion-3to4`, parsing the 'files which would be converted(N)' summary because the exit code is 0. Keep grep for comments, docs and strings.
10) playtest-observer (if ever used): GODOT_MCP_STRICT must be "true", not "1". The entry point is `<clone>/dist/index.js` (package.json main/bin), and the package requires Node >=20. Note that it writes project.godot [autoload] and .gitignore during runs, and that on 2.1.195 inline agent MCP servers load without a folder-trust check (the check arrived in 2.1.238). The inline `mcpServers` list syntax and `tools: ... mcp__godot-runtime` match current docs.

## Windows notes

- **Godot binary:** use the console exe (`$env:GODOT_BIN` = D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe). All captures in this research used it.
  - MCP servers do not read GODOT_BIN. Coding-Solo auto-detects only Program Files and %USERPROFILE%\Godot paths, so any MCP would need GODOT_PATH set explicitly (in .mcp.json via `${GODOT_BIN}` expansion).
- **PowerShell 5.1:**
  - `2>&1` on native exes wraps stderr as ErrorRecords, and redirected UTF-8 output shows as mojibake.
  - The headless *editor* (`-e`, `--import`) printed Ukrainian-localized progress lines (the OS/editor locale). In game/script mode, parse and runtime errors stayed English ('SCRIPT ERROR: Parse Error: ...').
  - The runner should use `--log-file` or Git Bash capture, read as UTF-8, and match only English engine markers and exit codes.
- **Screenshots** need an interactive desktop plus GPU: Vulkan Forward+ on the RTX 4060 took 5.8 s including init. `--headless` screenshots hang. A future Windows CI runner without a GPU may need `--rendering-driver opengl3` or to skip `shot` (open question).
- **Background processes:** kill only the specific Godot PID or command line you started (Get-CimInstance Win32_Process filtered by CommandLine), never all Godot processes. The human's editor may be running.
- **LSP port:** the human's editor serves GDScript LSP on the default port 6005. Any agent-started headless editor must use a different `--lsp-port` and should not run while the human's editor has the same project open (both write `.godot/`).
- **npx on Windows:** it is `npx.cmd`. Older Claude Code docs required a `cmd /c` wrapper for npx-launched stdio servers on native Windows; the current MCP page no longer mentions it (inferred risk). If an MCP is ever adopted, launch `node <abs path>` of a pinned local build instead of npx.
- **Python** is not on PATH. Runner parts that use Python must call `$env:PYTHON_BIN`. The API-lookup path proposed here uses GDScript (ClassDB) instead, so it needs no Python.
- **gdtoolkit** exes live in `$env:GDTOOLKIT_DIR` (gdlint.exe 4.5.0 verified).

## Gotchas

- gdlint/gdformat do NOT catch Godot 3 APIs: yield(), 3-argument connect(), OS.get_ticks_msec(), rset() all passed gdlint 4.5.0. Only the engine parse check (`--check-only` or loading scripts) rejects them.
- Per-file `--check-only` gives false 'Could not find type X' errors for a class_name declared in a new, not-yet-imported file. Run `--headless --import` first (3.4 s on a tiny project; grows with assets). A PostToolUse hook doing a per-file check must handle this, e.g. by re-running after import before reporting.
- A batch checker that loads ITSELF with CACHE_MODE_IGNORE crashed Godot (exit 139). Exclude the running script and addons/.
- `-d` (local stdout debugger) with non-interactive stdin loops forever at `debug>` on the first runtime error (4,321 prompts in 20 s). Never pass -d. Coding-Solo's run_project always passes -d.
- Godot exits 0 even after a runtime SCRIPT ERROR. Success must include a log scan, which the KICKOFF 'no errors are logged' bot invariant needs anyway.
- `--doctool <path>` prints 'Erasing old docs at: ...' and merges or erases in the target. Point it only at tools/out/. In the official build its XML has empty descriptions and no deprecated= attributes, so doctool-based docs MCPs (e.g. tkmct/godot-doc-mcp) serve signatures only unless fed upstream XML.
- `--dump-extension-api-with-docs` takes no path and writes extension_api.json into the CWD. Set the working directory to tools/out/godot-api/<ver>/ first. The file is about 12 MB, so the checker must grep it or use the ClassDB lookup, not Read it whole.
- Headless screenshots hang (RenderingServer.frame_post_draw never fires with the dummy renderer). The shot script needs a watchdog timer that quits non-zero.
- Context7 hosts /websites/godotengine_en_3_6 and /websites/godotengine_en (latest) next to _4_7. resolve-library-id without pinning can return Godot 3 docs. docs.godotengine.org/en/stable/ will silently move to 4.8, so pin /en/4.7/.
- The Coding-Solo README install (`npx @coding-solo/godot-mcp`) pulls npm 0.1.1 (2026-02-03), which lacks the April 2026 fix for arbitrary GDScript instantiation (PR #99).
- Several servers include eval tools (tugcantopaloglu game_eval, GDAI execute_editor_script, Erodenn run_script) and listen on localhost ports (9090, 9080, 6505–6509). Any local process can reach them, and a prompt-injected agent can run arbitrary code through them.
- 'Official' in a Godot MCP name means nothing: bebabinlarsson-blip/Godot-MCP says 'Official Plugin' but is an 11-day-old personal repo. The godotengine org publishes no MCP.
- The Claude Code docs describe features up to v2.1.283; this machine runs 2.1.195. alwaysLoad (2.1.121) and inline subagent mcpServers (by 2.1.153) are available; MCP image-to-file saving (2.1.283) is not. Verify with /context and /mcp, not the docs alone.
- Subagents inherit all main-session MCP tools by default. If an MCP is ever added via .mcp.json, every subagent (including the designer's) sees it unless `disallowedTools: mcp__<server>` is set, which is why inline scoping is preferred.
- If a subagent's `tools:` allowlist is used together with an inline MCP, the MCP tools must be listed explicitly (e.g. `mcp__godot-runtime`), or the subagent will not get them.
- MCP tools cannot run in GitHub Actions, so anything verified only through MCP is invisible to CI. Keep MCP, if ever adopted, to observation and exploration, never to the definition of done.
- ClassDB lookups print Variant-typed parameters as 'Nil' (type_string(TYPE_NIL)). Map TYPE_NIL with PROPERTY_USAGE_NIL_IS_VARIANT to 'Variant' in the real script.

## Open questions

- Does the engineer approve 'no Godot MCP in M0–M3, revisit at M4 with written criteria'? Proposed criteria for revisiting: the bot harness cannot drive a needed input or observation, or the designer's agent repeatedly needs live editor state that .tscn files and `shot` cannot provide.
- Should godot-api-checker have WebFetch at all (restricted by instruction to docs.godotengine.org/en/4.7/), or run fully offline from the engine-derived reference? Claude Code permission rules could enforce the domain; the permissions researcher should confirm the exact WebFetch domain-rule syntax.
- Is Context7 wanted as an optional tutorial source (it needs an API key and sends queries to Upstash, and CVE-2026-75130 shows the injection risk), or is WebFetch against the pinned 4.7 docs enough?
- Where should the generated API reference live: gitignored tools/out/godot-api/4.7.2/ regenerated by `doctor` (proposed; about 16 MB), or a small committed index? Committing 12 MB of JSON would bloat the repo.
- Should the per-edit engine parse check be a PostToolUse hook (about 0.5 s per file, plus handling for new class_names), or only part of `check`/`verify` plus the subagent? This overlaps with the hooks research.
- Can GitHub Actions run `shot` at all (GPU or software rendering on windows-latest or ubuntu with xvfb/lavapipe)? This affects whether screenshots can be CI-verified. It is out of scope here but relevant to the 'CLI covers screenshots' claim.
- Not verified: whether `${VAR}` environment expansion works inside a subagent's inline `mcpServers` block the way it does in .mcp.json. It matters only if Option D is ever adopted.
- Not verified: whether the Claude desktop app's Code tab handles project .mcp.json approval and inline subagent MCP servers the same way the CLI does.