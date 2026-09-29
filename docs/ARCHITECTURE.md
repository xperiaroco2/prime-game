# Architecture

| | |
|---|---|
| **Owner** | The engineer. The **content API** section is the contract with the designer: changes to it are reviewed by both. |
| **Status** | Skeleton (M0). The boundaries below are locked ([KICKOFF §3](history/KICKOFF.md); stack: [ADR](decisions/2026-09-29-technical-stack-from-the-brief.md)). Everything marked *open* is designed before M2 (core and content API) or in the milestone named. |
| **Rules for agents** | The invariants are repeated in the root `CLAUDE.md`, so they survive compaction. Area rules: `core/`, `server/`, `net/`, `client/`, `voice/` `CLAUDE.md`. |

## 1. Layers and boundaries

| Folder | Contains | May use | Owner |
|---|---|---|---|
| `core/` | Pure rules: match state machine, intent validation rules, win conditions, voice routing rules, content-API primitives. `RefCounted` only; no Nodes, scenes, networking or audio | nothing outside `core/` | engineer |
| `server/` | Host logic: wraps `core/`, validates intents, filters state and events per peer, movement sanity checks | `core/`, the `net/` abstraction | engineer |
| `net/` | Transport abstraction (ENet first), message schemas, serialization, sync | nothing game-specific | engineer |
| `client/` | Scenes, player controller, UI, camera, audio playback, dev console | the filtered view it receives; `net/` to send intents | engineer |
| `voice/` | Capture, Opus encode and decode, jitter buffer, playback plumbing | `net/`, `client/` playback | engineer |
| `content/` | Roles, abilities, items, sabotages, task types as `Resource`s built from content-API parts | the content API only | designer |
| `levels/` | Maps from reusable room, prop, interactable and task-station sub-scenes | the content API only | designer |
| `tools/`, `tests/` | Task runner, checks, bot harness; unit, integration and bot-match tests | everything (tests) | engineer |

Changing a boundary is a stop-and-ask item and gets an ADR.

## 2. Data flow

```
client (local player)                host                                         every client
  input ──► intent ──► net ──► server: validate ──► core: command ──► events
                                     server: filter per peer ◄───────────┘
                                           │  one message per recipient
                                           └──► net ──► client: filtered view ──► UI, avatars, audio
```

- Clients send **intents**, never state. The host's own client is a normal recipient of the filtered stream.
- `core/` is deterministic: the same seed and commands give the same events, so a match can be replayed in tests.

## 3. Match state machine

Lobby → RoleAssign → Roam → Meeting → Vote → Resolution → (Roam | End).
*Open (pre-M2):* the exact transitions and their triggers, what each state allows, timers.

## 4. Protocol

*Open (M3):* intent and event schemas, encoding, versioning, reliability per message type, rate limits.
Every schema change updates this section in the same PR.

## 5. Per-peer information filtering

- Each outgoing message is built for one recipient from what that peer is entitled to know.
- The information-leak test (bot harness, M3) asserts that no client ever receives anything it is not entitled to.
  It is the most important test in the project. Once it exists, prove it: inject a leak, see it fail, revert.
- `tools\run.cmd bots` (M3) starts a headless host and N headless bot clients that play a full scripted match, then
  asserts: the match ends, the winner is correct, no errors are logged, and no client received information it was
  not entitled to. It joins `verify` and CI. `host` and `join` launch a local host and clients for the humans'
  playtests.
- *Open (pre-M2):* how entitlement is expressed (per event, per field, per content part), and how reveals
  (meetings, deaths, end of match) widen it.

## 6. Voice pipeline

capture → encode (Opus) → routing decision per speaker and listener (`core/` rules, applied by the host's
`server/`) → listener → decode → jitter buffer → `AudioStreamPlayer3D` on the speaker's avatar.
- Routing inputs from the brief: distance, walls (occlusion), death (dead chat), meetings (everyone), items such as
  radios, role abilities.
- *Open (M1 spike, ADR):* the codec addon (`two-voip-godot-4` first; Windows build risk), fallbacks
  (`one-voip-godot-4`, Steam voice through GodotSteam, uncompressed or lightly compressed PCM), measured
  latency and CPU cost. *Open (M1, M5):* whether audio is relayed through the host or sent directly under the
  host's decision (bandwidth for 10 players), push-to-talk and voice activity.

## 7. Movement

Client-side movement for the local player; the host checks speed and teleports; remote players are interpolated.
*Open (M4):* tick rate, snapshot format, correction policy.

## 8. Debug tooling

A dev console and debug commands (spawn bots, force role, skip phase, show hidden info locally) in debug builds
only, so the designer can test a mechanic alone.

## 9. Content API (the engineer–designer contract)

A mechanic is data: a `Resource` composed from parts the engine provides. The designer's agent uses **only** the
parts listed here. A missing part becomes an `engine-request` issue; the engineer adds it with tests and lists it
here in the same PR.

| Kind | Answers | Parts available |
|---|---|---|
| Trigger | *when* something happens (a phase starts, a player uses an ability, a task completes, …) | none yet |
| Condition | *only if* (alive, role, distance, cooldown ready, …) | none yet |
| Effect | *what happens* (kill, reveal to someone, a sabotage, change who hears whom, …) | none yet |
| Interactable | a thing in the world players use | none yet |
| Task station | a place where a task is done | none yet |

The examples in the "Answers" column only explain the kinds; none of them is a decided part.

Each part, once it exists, gets one entry:

```
### <PartName> (<kind>)
What it does: one sentence.
Settings: name: type (allowed values, default).
Produces: events or state changes.
Visible to: who learns the result, and when.
Since: PR link. Tests: path.
```

*Open (pre-M2, one design run):* the composition model itself (how triggers, conditions and effects chain), where
the `Resource` classes live, how bot scenarios exercise a mechanic (format and location), and the first set of
parts, drawn from the designer's GDD.

## 10. Open questions

| Question | When |
|---|---|
| Composition model and first content-API parts | pre-M2 design |
| Bot-scenario format and location | pre-M2 design |
| Intent and event protocol | M3 |
| Voice codec go/no-go | M1 spike ADR |
| NAT traversal: Steam networking vs WebRTC with a signaling server | M6 ADR |
