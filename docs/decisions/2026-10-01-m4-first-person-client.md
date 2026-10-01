# M4: the first-person client on the network, and the split of vision revision 1's rework

- **Status:** Proposed. The engineer answers E18 to E33 and relays the designer's answers to D4 to D10; the answers
  are written in here before the manager merges this ADR's PR into `release/m4` and before M4's code starts
- **Date:** 2026-10-01
- **Deciders:** designed by the agent in #125 (the M4 design, under the M4 manager session, #134); the engineer
  decides the E items and relays the designer's D items (`docs/AGENT_WORKFLOW.md` §9)
- **Builds on:** [vision revision 1](2026-10-01-vision-revision-1.md) (its rules and its rework list),
  [wire format and the host session](2026-09-30-wire-format-and-host-session.md),
  [listen server and the message layer](2026-09-29-listen-server-and-message-layer.md),
  [match loop, intents, events and entitlement](2026-09-29-match-loop-intents-events-and-entitlement.md),
  [content API v0](2026-09-29-content-api-v0.md), [MVP rules](2026-09-29-mvp-rules.md),
  [Vulkan on Windows](2026-10-01-vulkan-on-windows.md),
  [a release branch per milestone](2026-10-01-release-branch-per-milestone.md)
- **Numbering:** the choices continue the M3 design's E1 to E17 and D1 to D3, which `docs/ARCHITECTURE.md` cites, so
  "E8 (a)" never means two things: this ADR's are **E18 to E33** and **D4 to D10**. The proposed issues are **M4-1
  to M4-9** and the designer's **L-1**; the manager maps them to issue numbers when it opens them.

## Context
M4's goal (ROADMAP): a map, movement, interactions and tasks in 3D, host-side movement checks, interpolation. M3
built the network and left it headless: `HostSession` and `HostNode` (`server/`), `ClientSession`, `ClientModel` and
`DecodedView` (`client/net/`), the wire codec, `HostWorldQuery`, the bots runner with the information-leak test, and
headless `host` and `join` (ARCHITECTURE §4.3 to §4.6). The client beyond that is the first-person controller of #46
and PR #69 (`client/player/`, with a ghost mode that vision revision 1 removes), `RemotePlayerBody` capsules that
nothing moves yet, `LocalStamina` and a dev room. There is no main scene, no UI and no view of an item, a circle or a
body.

Vision revision 1 (PR #133) changed the rules M4 renders: no ghosts; knockdown, crawl, revive, give-up, death with a
client-side spectate camera, respawn and invulnerability; two hand slots; Engineers as display names; "no crew
present"; the voice invariant; the Tab task screen with no map (the engineer's answers V1 to V13 on PR #127 and 1 to
9 on PR #133). Its Consequences hold a rework list for this design to split (item 12, the map asset, left with
answer 2) and the ARCHITECTURE sections each item rewrites with its code.

What constrains the design:
- **Invariants 1, 2, 7 and 8.** The host's own client is a normal recipient: in a window it still shows only what
  its `ClientSession` decoded, and hidden information appears in debug builds only.
- **The wire.** `WireSchema.encode` refuses a message with no row, so a new intent or event ships its row, its codec
  sample and a `JoinRules.PROTOCOL_VERSION` bump in the PR that adds it (the M3 answers on PR #117).
- **The leak test** changes in the PR that changes what it checks, each new check proven by a planted leak.
- **ARCHITECTURE describes the code as built.** Each section the rework changes is rewritten in the issue that
  changes its code; this ADR describes those changes, and ARCHITECTURE gets only the client's design (§4.7).
- **The stage's budget** (#134): about 8 tasks, each one issue-task workflow (up to 5 agents, 25 to 60 minutes);
  PRs of at most about 1500 changed lines; at most three tasks at once.
- **The humans** write no code and hand-make only the designer's level layout; agents open no windows; Windows only,
  rendering with Vulkan; CI on Linux as a free extra check.

Checked for this design on 2026-10-01, on the code and the 4.7.2 API dump rather than from memory:
- `SceneTree.change_scene_to_node` and `change_scene_to_packed` remove the current scene at once and free it at the
  end of the frame; `HostNode._exit_tree` closes its session (`server/host_node.gd`).
- `core/` already flattens a facing before using it: `Strike.horizontal` for the hit zone and `Swung`'s facing
  (`core/combat/strike.gd`), and `PutDownInFront` (`core/items/put_down_in_front.gd`); `MovementRule` only requires a
  finite facing.
- In the API dump: `SpringArm3D` (`spring_length`, `collision_mask`, `shape`, `margin`, `add_excluded_object`),
  `Camera3D.cull_mask`, `VisualInstance3D.layers`, `SceneTree.auto_accept_quit`, `Node.NOTIFICATION_WM_CLOSE_REQUEST`,
  `AudioStreamPlayer`, `AudioStreamPlayer3D`, `RandomNumberGenerator.seed`, `DisplayServer.window_set_position`.
- Claude Code sets `CLAUDECODE=1` in an agent's shell; a human's PowerShell has no such variable.
- A snapshot's avatar takes 43 bytes with its peer key (650 bytes for 15, §4.3); a belt item makes it 45 (680).

## Decision

### 1. The client
`docs/ARCHITECTURE.md` §4.7 holds the client's design: one persistent main scene, `client/app/game.tscn`, that hosts
or joins and swaps levels under itself (E19); `client/app/` as the only part of `client/` that names `server/`
(E18); the order of one physics frame; the flow from the main menu through the lobby, loading, the round and the end
screen back to the lobby, and every way a session ends, each with its reason in words (#119 by E21); movement on the
network (claims with the look's pitch, E22; interpolation, E23; predicted stamina, E24; the numbers from the mode's
`PlayerRules`); the revision in 3D (the life fold, E25; the downed camera; spectating; hands and belt; the HUD; the
task screen); what stays headless; and `host` and `join` with windows (E20). The rest of this ADR is what §4.7 does
not hold: the controls, the review checklist, the core rework as M4 issues, the levels, the testing and the split.

### 2. Controls and the debug overlay
The input actions (D6 (a); every existing action keeps its key in `project.godot`):

| Action | Key | Sends |
|---|---|---|
| Move, sprint, jump | WASD, Shift, Space | `MoveClaim` (as built) |
| Pick up the item under the crosshair; held on a downed player, raise them | E (`interact`) | `PickUp(item)`; `Raise(target)` on press and `StopRaise()` on release |
| Put the hand item down | Q (`put_down`) | `PutDown(facing)` |
| Use the hand item | left mouse button (`use`); the click that captures the mouse is not a use | `Use(facing)` |
| Swap hand and belt | X (`swap`) | `Swap()` |
| Give up, while downed | hold G for 1 s (`give_up`, a placeholder) | `GiveUp()` |
| Task screen | hold Tab (`task_screen`) | nothing |
| Next and previous spectate target, while dead | left and right mouse buttons | nothing: the target never leaves the client |
| Menu (Leave, Quit); frees the mouse | Esc | `ClientSession.leave()` on Leave |
| Debug overlay (debug builds only) | F3 | nothing |

The **debug overlay** (invariant 8: debug builds only, local) shows the own client's count of `Correction`s, the
estimated host tick and the interpolation delay, and on the host `HostSession`'s counters (budgets, malformed
messages, voice). The playtests read it (§6), above all for #76's tuning.

### 3. What the client renders, and what it may not (rework item 13)
Each client issue's PR is reviewed against this list by `netcode-security-reviewer` as well as `code-reviewer`: this
design routes it for M4's client PRs, although the root routing names it only for `core/ server/ net/ tests/harness/`.
1. Everything drawn, played or shown comes from the own `ClientModel`, the interpolated snapshot poses and the
   client's own copy of the mode, never from `server/` or `core/` state, also on the host (E18's source test).
2. Spectating renders the public snapshot only: no target HUD, health, stamina, role, teammates or private event;
   the target is never told and nothing about it is sent; the target is drawn with the client's own generator.
3. The downed camera stays at or below the standing eye height above the body and never passes through the level
   (answer 9 (a)), and it shows over cover or around corners no more than standing at the body would (vision
   revision 1, the downed). The arm alone does not meet that: 2 m back with a wide view, it sees past the end of a
   short wall the body lies against. So while the own player is downed, or a spectator watches a downed target,
   `client/life/` hides every remote avatar, item and body view with no line of sight from the arm's pivot (the
   body's eye): one ray per object per physics frame against the world layer. The level itself is public and stays
   drawn.
4. The task screen shows each task's type, description and shared progress: no position of an item, a player or a
   spawn point, and no map (answer 2).
5. No screen lists items or players with a position or a distance: an item is seen only where it lies in the 3D
   world, so a hidden package is hidden by sight (vision revision 1, Hidden information). A name or a marker over a
   player or an item is drawn in the world and hidden by the level like what it marks (no `no_depth_test`
   overlays), or it would show through walls what the eye could not; only the fixed, public circles may be marked
   through walls (D10).
6. A dissident's own HUD may name its teammates (`Teammates`, its own knowledge); no other screen names a role.
7. The attacker gets no hit confirmation beyond the accepted exceptions (a knockdown; a raise stopping in the tick of
   a swing): the client has no `Damaged` of another player and plays no hit sound or effect on the attacker's side.
8. Countdowns come from public events and the mode's numbers (V13); nothing is inferred from timing or packet sizes.
9. The debug overlay and anything else that shows hidden information exist in debug builds only.
10. A world sound plays only within a hearing range around the listener's camera, the same for the living, the
    downed and the dead (E33 (a): `AudioStreamPlayer3D.max_distance` and a sound chooser that plays nothing for an
    event from farther away; about 12 m, a placeholder, "not a decision"). `Swung`, `ItemPickedUp` and
    `ItemPlaced` reach everyone with a position, and a fading but uncut sound would tell every crew client, through
    the walls, where a dissident just put a package down. Occlusion is M5's.

**Host trust:** the client sends intents only, and the host checks every one again (reach, sight, life, slots,
stamina, the raise's conditions every tick). The facing is a claim whose only effects are the hit zone's direction,
a put-down's direction and the avatar's look. The cameras, the spectate target and the countdowns stay on the client.
Remote facings and velocities are claims relayed by the host, and an honest one can be degenerate (a bot falling
straight down claims the facing (0, -1, 0); a standing one may claim zero): from M4-2 `MovementRule` stores a unit
facing, keeps the last one when a claim's has no direction, and clamps its pitch to ±89°; every client camera, head
or basis built from a remote facing guards against a zero or vertical vector anyway; and remote players are drawn
from interpolated positions and facings, with a velocity used only to pick an animation, so no claimed velocity
moves anything on another screen.

### 4. The rework as M4 issues
The order is the revision's rework list (each step keeps `verify` green); the client issues run beside the core
chain. Until the chain is through, `release/m4` holds transitional states (M4-1's DOWNED behaves as GHOST did); only
the engineer merges `release/m4` into `main`, after M4, so `main` never holds one.

**The protocol.** Kinds are allotted here, so two PRs in flight never take the same one. Every protocol-changing PR
sets `JoinRules.PROTOCOL_VERSION` (and `WireSchema.VERSION`, the same number) to its base's plus one when it is
rebased for the merge, adds its codec samples and updates §4.1 to §4.3; they merge one at a time.

| Issue | New intents (C→H, RELIABLE, each with `seq`) | New events (H→C, RELIABLE) | Changed rows | Bump |
|---|---|---|---|---|
| M4-1 | none | none | none: the avatar's flag keeps the name `ghost`, set from DOWNED | no |
| M4-2 | none | 59 `KnockedDown(peer, position)`, everyone, no attacker | `Snapshot` (96): the avatar's flag 1 renamed `downed`; downed avatars reach everyone | yes |
| M4-3 | none | 60 `Respawned(peer, position)`, everyone; it removes the body (E26) | `Snapshot`: the avatar's flag 2, `invulnerable` | yes |
| M4-4 | 10 `Raise(target: peer)`, 11 `StopRaise()`, 12 `GiveUp()` (E28) | 61 `RaiseStarted(raiser, target)`, 62 `RaiseStopped(raiser, target)` (no cause), 63 `Revived(peer)`, everyone | none | yes |
| M4-5 | 13 `Swap()`, which Round accepts from the living only (`AcceptSpec.From.LIVING`; `PLAYER` would let a downed player swap, which the revision forbids, and a dead player's intent in flight reach the effect); a `Swap` from the downed or the dead gets `not_accepted`, unit-tested | 64 `Swapped(peer)`, 65 `TaskState(task: u8, type: id, done: u16, total: u16)`, everyone (E30) | `ItemPickedUp` (48) gains `belted: item`, optional (E29); the avatar gains `belt_item: item`, optional (680 of 1024 bytes for 15) | yes |
| M4-6 (#119) | none | 58 `Disconnecting(reason: id)`, only that player (E21) | none | yes |
| #76, M4-7 to M4-9 | none | none | none | no |

**The leak test and `ScenarioInvariants`**, written apart from the declarations (§5 of ARCHITECTURE), each new check
seen failing on a planted leak recorded in its PR:

| Issue | Checks | Planted leak |
|---|---|---|
| M4-1 | The ghost invariant renamed: a living peer decodes no downed avatar or voice frame (true until M4-2). New: no peer's speakers include a downed speaker; a downed peer hears only living speakers; a dead peer's speakers are empty (a unit test with a fixture: nobody is dead before M4-2) | `VoiceRule.speakers_of` keeps a downed speaker, under a fixture mode whose rule lets everyone hear everyone |
| M4-2 | The renamed invariant goes (the downed are public). New: no snapshot holds a dead player's avatar; no peer's speakers include a dead speaker, and a dead peer hears nobody (now reachable); every event a peer decodes while dead is either for itself alone (the subject check, as built) or also decoded by every living peer present then, so nothing reaches only the dead; the knockdown's `Correction` counts as a placement | `Snapshots.for_peer` sends a dead player's avatar to the dead (the old ghost rule) |
| M4-3 | The respawn's `Correction` counts as a placement; no `Damaged` reaches a player whose invulnerability runs (from the match state) | `Strike` ignores invulnerability |
| M4-4 | None new: every raise event is public, and `RaiseStopped` carries the raiser and the target only, which the table-against-core test pins | none |
| M4-5 | `TaskState` joins `LeakCheck.TASK_EVENTS`: every player present for a whole round decodes the same task events. The check can only see the plant when a bot present for the whole match is downed or dead as a `TaskState` is emitted (at the deal everyone is living), so M4-5 adds a scenario where a crew bot is knocked down, or dies, before another bot completes a delivery in the same match, and runs the plant on it | `TaskState` declared to the living only, run on that scenario |
| M4-6 | `Disconnecting` is an event for one player: `&"Disconnecting"` is added by hand to `LeakCheck.FOR_ONE` (its comment requires it; `for_one()` adds a class only while it declares ONLY, so a wrong declaration would hide it), and the core `DisconnectingEvent` holds an int `peer`, its subject, as `CorrectionEvent` does although the wire row has no peer field, so `_check_subjects` compares it: only its subject decodes it | `Disconnecting` declared *everyone*: the check names "decoded Disconnecting of peer N" |

**The ARCHITECTURE sections** each issue rewrites (vision revision 1's table, assigned):

| Issue | Sections |
|---|---|
| M4-1 | §3 intro, §3.1 (life states, `AcceptSpec` senders, the meetings example), §3.2 (Round's accepts, `ResetMatch`'s ghost note), §3.3 (the meeting example), §5's invariants, §6 (the voice invariant, `RoundVoice`; dead chat and meetings out of the open items), §9.1 (#35's votes as the example), §9.3, §9.4 (`RoundVoice`, `Proximity`, `ReportOutcome`'s example), §9.5 (Crew, the base mode's voice numbers), §9.7 (`WalkTo`), §10 (the M5 row) |
| M4-2 | §3.4 (no crew present), §3.5 (leaving while downed or dead), §4.1 (`MoveClaim` from the downed), §4.2 (`KnockedDown`, `Died`, `Correction`), §4.3, §4.6 (the client's life, the bots), §5 (widening, knowledge never shrinks), §7 and §7.1 (the crawl replaces ghost movement), §9.2 (§3.4's ordering example), §9.3, §9.4 (`NoneAlive`, `Strike`, the life tick system), §9.5 (No crew present, Sprint and Jump), §9.6, §9.7 |
| M4-3 | §4.2 (`Respawned`, the respawn's `Correction`), §4.3, §5 (widening at a respawn), §7.1 (invulnerability in `Strike`), §9.3, §9.4 (the respawn effect, `Demands`), §9.5, §9.6 (the `respawn` tag), §9.7 |
| M4-4 | §3.2, §4.1, §4.2, §4.3, §7.1 (the raise's reach and sight, the downed held in place), §9.1 and §9.4 (the channel, its conditions and effects), §9.5, §9.7 (steps), §9.8 (the resurrection example replaced) |
| M4-5 | §4.1 (`PickUp`'s two slots, `Swap`), §4.2, §4.3 (and the snapshot budget), §7.1 (pick-up and swap), §9.1, §9.2 (the `item_rested` causes), §9.3 (`ItemState`, `Items`), §9.4 (`TakeIntoHand`, the swap), §9.5 (the items' `hands`, PickUp, Delivery's description), §9.7 |
| M4-6 | §4.7 as built, §4.6's `host` and `join`, §4.2 and §4.3 (`Disconnecting`) |
| M4-7 | §7 (snapshot rate, interpolation, correction policy), §4.7 |
| #76 | §7.1 |
| M4-8, M4-9 | §4.7 |

### 5. The levels for M4
**The lobby** (`levels/lobby/lobby.tscn`, the path the mode names):
- a floor and walls or edges that keep players in, as `StaticBody3D` nodes with `CollisionShape3D` children on layer
  1 (D2; the host refuses CSG or `GridMap` collision, #112);
- at least the mode's maximum of players (10) `lobby_player` markers, at least 1 m apart (a joiner takes the first
  free one, §3.2);
- light and an environment, so a window shows it. Nothing else: Ready and the settings are UI, not level objects.

**The greybox map** (`levels/greybox/greybox.tscn`):
- rooms, corridors and props built from pieces (D4), collision as above, with places to hide a package: rooms off
  the main paths, corners, behind and on top of crates;
- markers, each a `Marker3D` in exactly one `spawn_<tag>` group: 10 `round_player` (the maximum of players); at least
  10 `package` and 10 `circle` (the most packages), each on the floor; `knife` markers for the most knives the host
  should be able to set (4 today); `respawn` markers, at least 1 by the layout check (M4-3) and in practice 4 to 6
  spread over the map, away from the round's start, each with 1 m free around it (a marker is free with no player
  within 1 m); the counts beyond the checks' minimums are placeholders, "not a decision";
- no `package` marker within 1.5 m of a `circle` marker (the circle's 1 m radius and a margin, a placeholder), or a
  package may spawn inside its own circle and count at once;
- **put-down reachability** (vision revision 1): every spot a put-down reaches is reachable for a pickup, within the
  pick-up's reach (2 m from the feet) and line of sight from somewhere a player can stand. A put-down travels 1 m from
  the eye along the facing, stops 0.2 m before a wall and drops to the floor below (§7.1), so the places to check are
  crate tops, ledges, gaps behind props and the floor behind thin walls. No gap, ledge, shelf out of reach or thin
  wall may keep a package for good. The designer checks it in the playtests (§6);
- **the fit check:** `tests/unit/content/content_modes_test.gd` stays green: the greybox fits 10 players at the
  default settings and at the most packages, and from M4-3 has at least 1 `respawn` marker.

**Order:** #118 (the content hash covers the scenes a level instances) merges before any level instances a piece;
otherwise a host and a client with different builds of one room join each other and disagree about its walls, with
endless corrections and nothing saying why.

**Who builds what** (D5 (a)): the designer builds the pieces (`new-level-piece`, with D4's conventions written into
the skill first) and lays out the lobby and the greybox by hand in the editor (L-1); the engineer's agent adds only
the respawn markers to today's flat greybox in M4-3 (provisional, under the MVP content ADR), unless L-1 has added
them already. A change the designer agrees to may be made by the engineer's agent under the relayed agreement
(`docs/AGENT_WORKFLOW.md` §9); a scene in the designer's open PR is never edited.

### 6. Testing M4
- **Headless, every PR** (`tools\run.cmd verify`, CI): the unit and integration suites, the bots with the revised
  scenarios over the loopback and over ENet (`bots`, `bots-enet`), the leak test with each issue's checks. Agents
  run `run`, `host` and `join` with `--headless` only.
- **`shot` for every visual change:** each screen through a preview scene in `client/dev/` fed by a fake
  `ClientModel` (`tools\run.cmd shot client/dev/<preview>.tscn`), each view (item, circle, body, the downed pose, the
  invulnerable look), each level piece and map. The PNG goes into the PR.
- **The one-PC windowed playtest** (a human; after M4-7, again after M4-8 and M4-9). Between two of the manager's
  merges, on the engineer's PC:
  ```powershell
  cd D:\prime-game\.claude\worktrees\release-m4
  tools\run.cmd host --clients 2
  ```
  Three windows open, tiled (E20). It checks: the menu skipped, all three in the lobby; walking, sprinting, jumping,
  steps and pushing each other; the host's settings and shortfalls; Ready, the 5 s countdown, loading, the round; the
  debug overlay (F3) showing no `Correction` for honest play; picking up, putting down, swapping, carrying the
  package with both hands, using the knife, a delivery, the HUD's progress and the Tab screen (after M4-8); a
  knockdown by two hits, crawling, the downed camera (no peeking over a crate a standing player could not see over),
  a raise by holding E, a cancelled raise, a give-up, spectating (first target, cycling, no target HUD, lift music),
  the respawn at a marker and its 3 s of visible invulnerability (after M4-9); time up, the end screen and the host's
  return to the lobby; a client window killed in the Task Manager (the others go on, no 5 s freeze: #21 under
  Vulkan); the host's window closed (the clients return to the menu, saying why).
- **The two-machine playtest** (#21's setup, LAN or VPN; after M4-7, then at M4's end). On the host PC, as above but
  `tools\run.cmd host` (every interface; it prints its LAN address; allow the firewall prompt on private networks).
  On the other PC, on the same commit (`git rev-parse --short HEAD` equal on both, or the join says `wrong_version`
  or `wrong_content`):
  ```powershell
  cd <the clone, for example D:\prime-game>
  git fetch origin
  git switch --detach origin/release/m4
  tools\run.cmd join <the host's address>
  ```
  If the windows cannot connect, the M3 check first: `tools\run.cmd host --headless` and
  `tools\run.cmd join <address> --headless`. It checks, besides the one-PC list: a push over a real round trip (§7.1:
  the overlap limit sets about 1 m/s; does a doorway stay passable?); remote players smooth over Wi-Fi; the knife's
  feel without lag compensation (§7.1: "the playtest decides"); hiding a package and finding it, and the put-down
  reachability of the map (§5); the playtest target of vision revision 1, a match with 0 dissidents at the default
  settings finished within about 60% of the match time.
- **#76's tuning** (both playtests): honest play gets no `Correction` (the overlay's count per player, per minute,
  while walking, sprinting, on stairs and slopes, pushing in a doorway and after a host freeze). Each correction seen
  is written on #76 with what the player did, and the placeholders of `MovementRule` change in a follow-up PR.

### 7. The split
Nine issues and the designer's L-1, beside #118 (running since wave 1) and #76, with #119 folded into M4-6. The full
text of each (goal, acceptance criteria, out of scope, verification, files, protocol, leak test, sections) is in the
handoff on #125. Not in M4: voice capture and playback (M5; the voice invariant's rule in `core/` is M4-1's),
internet play (M6), art beyond greybox, the Tab map (later, as item zones), and lag compensation (§7.1: after the
MVP playtest).

| # | Title | Depends on | May run beside | Protocol | Size |
|---|---|---|---|---|---|
| M4-1 | core: the life model ALIVE, DOWNED, DEAD and LEFT, the voice invariant and the Engineers' names | the answers | M4-6 | no | ~1200, most of it the rename |
| M4-2 | core: knockdown and death, the crawl check and "no crew present" | M4-1 | M4-7 | yes | ~1500 |
| M4-3 | core: respawn and invulnerability, with the greybox's respawn markers | M4-2 | #76, M4-7 | yes | ~900 |
| M4-4 | core: the raise, the revive and the give-up, with their bot scenarios | M4-3 | M4-7 | yes | ~1500 |
| M4-5 | core: two hand slots and the task screen's data, with their bot scenarios | M4-4 | M4-9 | yes | ~1300 |
| #76 | core: tighten the push allowance and the slope rise of the movement checks | M4-2 | M4-3, M4-7 | no | ~500 |
| M4-6 | client: the game shell (menu, hosting and joining, the lobby, loading and end screens, windows for host and join) and the drop reason (#119) | the answers | M4-1, M4-2 | yes | ~1400 |
| M4-7 | client: movement on the network (claims, corrections, interpolation, predicted stamina) | M4-6 | M4-2, M4-3, #76 | no | ~1250 |
| M4-8 | client: items, hands, the HUD and the Tab task screen | M4-5, M4-7 | M4-9 | no | ~1300 |
| M4-9 | client: knockdown, death, spectating and respawn in 3D | M4-4, M4-7 | M4-5, M4-8 | no | ~1400 |
| L-1 | level: the lobby and the greybox for M4 (the designer) | #118, D4; after M4-3 if it adds the markers | any | no | the designer's |

Waves of at most three: (M4-1, M4-6), (M4-2, M4-7), (M4-3, #76, M4-7 if still open), (M4-4), (M4-5, M4-9), (M4-8).
The critical path is the core chain M4-1 to M4-5, then M4-8.

**Folded, and why:**
- Rework item 1 (respawn markers) into M4-3, which demands them: nothing reads them before it.
- Item 3 (the voice invariant) into M4-1: it removes the ghost radii that the rename touches anyway, and both rewrite
  the same leak-test invariant.
- Item 6 (invulnerability) into M4-3, whose respawn grants it first; M4-4's revive calls the same helper.
- Item 8 (the task screen's data) into M4-5: two small protocol additions that M4-8 renders, merged one at a time
  in the core chain anyway.
- Item 9 (bot scenarios) into the issues they test: the respawn into M4-3; the revive, the cancelled raise, the
  give-up and the respawn after it into M4-4; the two-handed pickup, the refused swap and the hidden package into
  M4-5.
- Item 10 (content data): the Engineers' names into M4-1 (names only, like the rename); each life number into the
  issue that introduces it (M4-2 the knockdown time and the crawl speed, M4-3 the respawn and invulnerability times,
  M4-4 the raise time and the revive health).
- Item 11 (the client) into four client issues, cut where a playtest can check each: the shell, movement, items,
  life.
- Item 13 (the review) into the client issues' acceptance criteria (§3's checklist) and a routed
  `netcode-security-reviewer` on each client PR.
- #119 into M4-6, which builds the screen that shows the reason.

**Kept apart, and why:**
- Item 4 as M4-2 (knockdown and death) and M4-3 (respawn and invulnerability): together about 2000 lines (E31 (b)).
- #76 apart from M4-2's crawl check, which also changes `MovementRule`: together about 2000 lines. It runs beside
  M4-3 instead.
- The client as four issues: each 1200 to 1400 lines, together over 5000.
- L-1 is the designer's hand work, not an agent workflow, unless D5 (b).

**Files several issues touch:**

| File | Writers, in merge order | Rule |
|---|---|---|
| `net/messages/wire_schema.gd` (the wire table), `JoinRules.PROTOCOL_VERSION`, `WireSchema.VERSION`, the codec samples | M4-6 (whenever it merges), M4-2, M4-3, M4-4, M4-5 | kinds as allotted in §4; the version is the base's plus one at the rebase before the merge; one protocol PR merges at a time |
| `content/modes/base_mode.tres` | M4-1, M4-2, M4-3, M4-4, M4-5 | the core chain, one at a time; `normalize` after every edit |
| `core/life/`, `core/match/player_state.gd`, `core/match/snapshots.gd` | M4-1 to M4-5 | the core chain |
| `core/movement/movement_rule.gd` and its tests | M4-1 (names), M4-2 (the crawl), #76 (the push allowance, the slope, the jump count), M4-4 (the downed held in place) | #76 beside M4-3 only, which does not touch it |
| `tests/harness/` (`LeakCheck`, `ScenarioInvariants`, the steps, the bots) | M4-1 to M4-5, M4-6 | a check changes in the PR that changes what it checks |
| `content/scenarios/` (`refusals.tres` included) | M4-2 (`dissident_kills_the_crew`, the `bots-enet` step), M4-3, M4-4, M4-5 (`refusals.tres`), M4-6 (`dropped_at_the_loading_deadline`) | a renamed `bots-enet` scenario updates `tools/runner/verify.py` in the same PR |
| `client/net/client_model.gd`, `client_session.gd` | M4-2 to M4-5 (each folds its events, E25), M4-6 (the end reasons, `Disconnecting`), M4-7 (a snapshot signal, the correction count) | small, separate functions; the second to merge rebases |
| `client/player/` | M4-7 (the network, stamina), M4-9 (the crawl, the downed layer, `set_ghost` removed) | M4-9 after M4-7 |
| The HUD scene | M4-8 creates it | M4-9 adds a life panel scene of its own under `Ui` |
| `project.godot` | M4-6 (the main scene), M4-8 (`swap`, `task_screen`), M4-9 (`give_up`, the spectate actions, layer 3 renamed `downed`) | added lines; the editor's format |
| `docs/ARCHITECTURE.md` | each issue its sections (§4) | rewrite only the issue's own sections |
| `levels/greybox/greybox.tscn` | M4-3 (respawn markers, if absent), L-1 | never both open at once; L-1 keeps the markers |
| `levels/lobby/lobby.tscn` | L-1 | |

## Needs the engineer
Each choice has a recommendation, which this design and `docs/ARCHITECTURE.md` §4.7 follow until answered; each can
be reverted. Not reopened: V1 to V13 and the answers 1 to 9 on PR #133.

| # | Choice | Options | Recommendation, and the failure it prevents |
|---|---|---|---|
| E18 | Where the windowed game composes `server/` and `client/` (a boundary of §1) | (a) `client/app/` alone may name `server/`, and only through a narrow handle: `HostNode` becomes a façade (a static `HostNode.host(transport, mode, port)` that builds and starts the session, then `own_client`, `errors`, `end_reason`, `ended`, a debug build's counters and `close()`; its `session` field turns private, while `tools/` and the tests keep using `HostSession` itself). A source test over every `client/` file, `app/` included, strips comments and strings, then fails on the identifiers `HostSession`, `Match`, `MatchState`, `PeerView` and `Snapshots` (case-sensitive and word-bounded, so `SnapshotBuffer` and `DecodedView.snapshots` pass) and on any `.game` access; it is shown rejecting a planted `Snapshots.for_peer` call and a planted `_host.game`, and accepting `SnapshotBuffer`. A textual "names `HostSession.game`" test would miss `_host.game` on a typed variable, the very accident it is for; (b) a new top-level folder `game/` for the composition, with its own rows in §1, `CODEOWNERS` and the ownership tables; (c) the main scene in `tools/`, where `host` and `join` compose them today | (a): one small exception inside an engineer-owned folder, held by a test. It prevents a HUD script on the host reading `session.game` for a number, which would hand the host's player a hidden fact with nothing failing. (b) prevents the same at the cost of a folder in every ownership list; (c) would ship `tools/` in the game |
| E19 | The scene structure | (a) one persistent root; levels swapped under `World`; no `change_scene_to_*`, no autoload; (b) `change_scene_to_packed` per level, with an autoload that owns the sessions and the `HostNode` | (a). A scene change frees the outgoing scene at the end of the frame: a `HostNode` inside the lobby would close the session at the first map load, and every client would see `host_lost`. (b) avoids that only through an autoload, which `check` and every test run would load |
| E20 | `host` and `join` in M4 | (a) windows by default (the game scene, tiled on one PC with `--position`), `--headless` for M3's session; in a shell where `CLAUDECODE` is set (an agent's) the default stays headless; (b) headless by default, `--windows` for the humans; (c) a new `play` command for windows, `host` and `join` stay headless | (a): the humans type what `docs/AGENT_WORKFLOW.md` §12 promised ("M4 gives it windows"), and an unattended agent that forgets `--headless` at night still opens no window on the engineer's screen. (b) and (c) prevent that too, at the cost of a flag or a second command for every human run |
| E21 | #119: tell a player dropped at the loading deadline why | (a) a private event `Disconnecting(reason)`, reason `load_deadline`, right before `DisconnectPeer` (kind 58, a version bump); the client ends with that reason; (b) the client infers it: `host_lost` while its phase is Loading and its own load is not confirmed | (a): the reason is exact. Under (b) a host that crashes or quits during Loading is reported as "your map loaded too slowly"; a later kick needs (a) anyway, and ENet already delivers what was sent before a disconnect (§4) |
| E22 | The look's pitch, for remote heads and the spectate camera | (a) `MoveClaim.facing` is the camera's 3D look vector: no wire or `core/` change (`Strike.horizontal`, `Swung` and `PutDownInFront` flatten it); snapshots stay at 20 Hz; (b) a `pitch` field on the avatar (a version bump, 4 bytes per avatar); (c) no pitch | (a). (c) shows a spectator the horizon while the player they watch looks down at a package; a lower snapshot rate would make the spectate camera stutter |
| E23 | Remote players | (a) drawn at an estimated host tick minus a delay of one tick plus the observed jitter over a sliding window, between 100 and 250 ms; no extrapolation (a player holds at the newest snapshot); a placement or a respawn snaps; (b) a fixed 100 ms; (c) extrapolation past the newest snapshot | (a), its numbers placeholders: the M1 spike starved 25% of frames at a fixed 100 ms under 100 ms of jitter (§7); extrapolation draws a player who stopped running on into a wall |
| E24 | The client's stamina | (a) predicted with `core/`'s rule (today's `LocalStamina`, its only client copy) and set to each `SelfStatus` as it arrives; sprint and jump gated by the prediction; (b) `SelfStatus` only | (a): under (b) a player whose stamina ran out sprints on for a round trip, and the host corrects them each time |
| E25 | Who folds a new event into `ClientModel` | (a) the core issue that adds the event (M4-2 to M4-5), with a unit test in `tests/unit/client/net/`; (b) the client issues (M4-8, M4-9) | (a): the bots are `ClientSession`s, and M4-2 must have dead bots stop claiming; under (b) no bot knows it is dead until M4-9, and `ClientSession` keeps claiming for it as a downed player ("has a body") |
| E26 | How a body's removal is told | (a) `Respawned` removes the respawned player's body and `PlayerLeft` a leaver's: no event of its own; (b) a `BodyRemoved(peer)` event besides them | (a): one fact, one event, and no order between two events of one respawn to get wrong. Nothing else removes a body in a round; `ResetMatch` clears them all, which clients mirror on entering the lobby |
| E27 | Where the life numbers live | (a) `PlayerRules` gains the knockdown time, the respawn time, the invulnerability time, the crawl speed and a respawn marker's free radius, beside health and stamina, which `LifeRules` already reads; the raise's time and reach and the revive health are the raise rule's part settings; (b) everything in part settings (a life tick system's, a respawn effect's) | (a): the client's countdowns and its crawl read `PlayerRules`, which it already loads. Under (b) the client digs through Round's tick systems for a number, and a part reads another part's settings (§9.1 forbids it) |
| E28 | The raise's intents | (a) `Raise(target)` on pressing E and `StopRaise()` on release, RELIABLE; the host checks the conditions at the start and every tick; (b) a `raising` target in `MoveClaim`; (c) one intent `Raise(target, on)` | (a): a start and a stop are one-off facts, which go RELIABLE (§4). Under (b) the LATEST merge swallows a stop and a new start in one poll |
| E29 | The two slots on the wire | (a) `ItemPickedUp` gains `belted` (the hand item this pickup moved to the belt, or none), a new `Swapped(peer)`, the avatar's `belt_item`; (b) a state event `HandsChanged(peer, hand, belt)` after every slot change, besides `ItemPickedUp` and `ItemPlaced` | (a): each fact once. Under (b) one pickup sends two events that a client folding both can see disagree |
| E30 | The task screen's data (rework item 8) | (a) a public `TaskState(task, type, done, total)` per task, after the deal and after each subtask done; `TaskProgress` stays for the HUD; (b) `TaskProgress` grows a per-task list (a changed row); (c) `TasksDealt(types)` once, with the client counting deliveries | (a): additive, and generic for #36's zone task; (c) works for Delivery only |
| E31 | M4's size | (a) as split (§7): nine issues and #76, with #118 running and #119 folded: 11 workflow tasks against about 8 in the stage's budget; (b) M4-2 and M4-3 as one PR, rework item 4 whole (about 2000 lines): 10 tasks; (c) as (a), with #76 moved to M5 (its placeholders stay until then): 10 tasks | (a): every PR stays near 1500 lines or under, which a fresh reviewer can check. If the budget runs short, (c) is what to drop first, then M4-9's lift music and M4-8's placeholder sounds |
| E32 | The Open knowledge pillar after answer 2 (found by the review of PR #133's last commit) | (a) keep it: "known to everyone" means not secret and learnable in play (items start on their markers, in view), while a later map draws only zones; (b) reword its "the item spawn points" to "the zones where items may appear" (the vision revision ADR and `docs/GDD.md` §1, relayed to the designer); (c) a later map shows spawn points after all | (b): answer 2's "never points" is the newer and more specific word, and newer answers win. Under (a) a later agent reads the pillar as licence for a spawn-point list or overlay that the engineer ruled out. It changes no code: `ItemSpawned` still reaches everyone (#32) |
| E33 | How far a world sound carries (found by M4's design review; no ADR sets it) | (a) a hearing range: a world sound for `Swung`, `ItemPickedUp` or `ItemPlaced` plays only within about 12 m of the listener's camera (`AudioStreamPlayer3D.max_distance`, a placeholder), for the living, the downed and the dead alike; no occlusion until M5; (b) no world sounds in M4; (c) sounds that fade with distance but never cut off (Godot's default) | (a): the events reach everyone with a position, so under (c) a dissident who hides a package in a far storeroom is heard putting it down, from its direction, by every crew client, and every fight on the map is heard too: a hidden package would no longer be hidden by sight. (b) is safe but leaves the dead's "world sounds around the target" (V11) silent |

## Needs the designer
The engineer answers each by relay (`docs/AGENT_WORKFLOW.md` §9); @SwiftySinister may object on the PR, and a
follow-up reverts.

| # | Choice | Options | Recommendation, and the failure it prevents |
|---|---|---|---|
| D4 | Level conventions (the questions of `new-level-piece` step 1) | (a) pieces in `levels/pieces/rooms/` and `levels/pieces/props/`, one `snake_case.tscn` each, maps in `levels/<map>/<map>.tscn`; metres, 1 unit = 1 m; a piece's origin on its floor at y = 0; collision as `StaticBody3D` with `CollisionShape3D` children on layer 1 (D2), looks from CSG or primitive meshes without collision; one flat greybox colour per kind of surface (floor, wall, prop); spawn points only in the map, as `Marker3D` in one `spawn_<tag>` group (§9.6, confirmed); (b) the designer's own list | (a): it matches what the host reads and refuses (§4.5, §9.6), so a piece never fails the host's level check. Markers only in the map keep the fit check readable in one file: a room instanced three times would otherwise triple its markers unseen. The skill's step 5 then says "CSG for looks only" |
| D5 | Who builds M4's lobby and greybox | (a) the designer: pieces with `new-level-piece` and the layout by hand (L-1); the engineer's agent adds only the respawn markers to the flat greybox (M4-3); (b) the engineer's agent builds a provisional dressed lobby and greybox under a relayed agreement, which the designer adopts or replaces | (a), with (b) as the fallback if L-1 has not started when M4-8 merges: hiding packages, the revision's sabotage, needs rooms, and a flat map would leave the windowed playtests unable to test it |
| D6 | Controls | (a) the table of §2: E picks up and, held, raises; Q puts down; the left button uses; X swaps; holding G for 1 s gives up; holding Tab shows the task screen; the left and right buttons cycle the spectate target; Esc for the menu; (b) the designer's own | (a): every existing key stays. Holding G keeps a downed player from dying by a stray key press; holding Tab never leaves the screen open while walking. All are input-map entries, cheap to change after a playtest |
| D7 | How items, circles and bodies are drawn | (a) greybox views in `client/` chosen by the kind's id, with a labelled box for an unknown kind; (b) a view scene on `ItemKind` and `StationKind` (a content-API change) that the designer's art fills | (a) for M4: no content-API change before the art pass, and a new item kind still shows up. (b) when the art pass (M7+) has the designer own the looks |
| D8 | How a downed player, a body and invulnerability read (GDD §14) | (a) greybox stand-ins: a downed player is their capsule lying on its side in their colour; a body the same in grey with a dark cross; invulnerability a translucent white shell that pulses for the 3 s; (b) the designer's own | (a), as placeholders distinct at a glance in a `shot` |
| D9 | Lift music and placeholder world sounds | (a) CC0 placeholders the engineer's agent picks, each with its `docs/credits/` entry (a lift-music loop; a swing, a pick-up and a put-down sound); (b) silence until the designer picks them | (a): the dead hear something the first time the feature is played, and `check` keeps each licence on record |
| D10 | A package's destination on the HUD (MVP rules, HUD) | (a) a swatch of its circle's colour; (b) the swatch and a marker on screen over the destination circle, through walls too (circles are fixed, public places) | (b): "shows its destination" reads as where to go, and the marker reveals nothing that is not public; a new player otherwise searches the map for a colour |

## Alternatives
- **`change_scene_to_packed` per level** with an autoload holding the sessions (E19 (b)), or a scene change with the
  `HostNode` inside the lobby: the first map load closes the host's session.
- **A top-level `game/` folder** for the composition (E18 (b)), or the main scene in `tools/` (E18 (c)).
- **A host-routed spectator feed:** already rejected by vision revision 1 (a new path for private data).
- **A fixed interpolation delay** (E23 (b)) or **extrapolation** (E23 (c)); **a pitch field** on the avatar (E22
  (b)) or **no pitch** (E22 (c)); **`SelfStatus` only** for stamina (E24 (b)).
- **The client inferring a drop at the loading deadline** (E21 (b)).
- **The client issues folding every new event** (E25 (b)); **a `BodyRemoved` event** (E26 (b)); **life numbers in
  part settings** (E27 (b)).
- **A `raising` flag in `MoveClaim`** (E28 (b)); **a `HandsChanged` state event** (E29 (b)); **`TaskProgress` with
  per-task lists** or **`TasksDealt` with the client counting** (E30 (b), (c)).
- **Windows by default with no agent guard:** a forgotten `--headless` in an unattended run opens windows on the
  engineer's screen.
- **One issue per rework item** (about 14 tasks, against a budget of about 8), **one client issue** (over 5000
  lines), **M4-2 and M4-3 as one** (E31 (b)), **#76 folded into M4-2's crawl check** (about 2000 lines).
- **A downed camera at eye level on the body** (first person): the engineer chose third person (V4, answer 9 (a)).
- **Item views owned by the content** in M4 (D7 (b)): a content-API change before any art exists.

## Consequences
- `docs/ARCHITECTURE.md` gains §4.7, the client's design, with pointers in its status row, below §1's table, in §4.6,
  §7 and §10. The sections the rework changes stay as built until their issues (§4's table).
- `client/CLAUDE.md` gains the rules of the shell (E18, E19), the rendering rules (§3) and where M4's code goes.
- The vision revision ADR's Context and Alternatives take the fixes of PR #133's last review; its pillar waits for
  E32.
- After the answers: the manager opens M4-1 to M4-9 and L-1 from the handoff on #125, with the answers applied and
  #76 and #119 amended (#76 after M4-2; #119 closed by M4-6's PR), in §7's order.
- `project.godot` gets the main scene and the new input actions, and layer 3 becomes `downed` (M4-6, M4-8, M4-9).
- `docs/AGENT_WORKFLOW.md` §11 and §12 and the root `CLAUDE.md`'s commands row change when M4-6 builds windows for
  `host` and `join` (E20).
- The `new-level-piece` skill's step 5 says "CSG greybox"; D4 writes "CSG for looks only, collision as
  `StaticBody3D`" into it (the designer's file, in L-1).
