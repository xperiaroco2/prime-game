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

Lessons from the M1 spike (#13, #15; [voice ADR](decisions/2026-09-29-voice-approach.md)):
- Read packets from `ENetMultiplayerPeer` directly. `SceneMultiplayer` parses RPC, spawn and sync commands even if we
  send none, so any `@rpc` method under its root becomes callable by clients.
- Godot 4.7.2 `ENetMultiplayerPeer.create_server` passes `max_channels` as the host's incoming bandwidth
  (godotengine/godot#123963). Keep it 0 on the server and let clients ask for channels, or unreliable packets are
  throttled to 1/32.
- Bind each message type to its channel and reliability. Voice uses its own unreliable **unordered** channel;
  unreliable ordered drops reordered frames before the jitter buffer sees them.
- Decode defensively: a size cap, type and length checks, finite vectors, `bytes_to_var` without objects. Compare
  the re-encoded size, because `bytes_to_var` ignores trailing bytes.
- Count rejected and malformed packets and log a summary: one client can flood per-packet log lines.
- Budget floods by bytes, not messages. `var_to_bytes` framing is as large as an Opus frame: use a compact header.
- A 2–4 s ENet timeout drops any peer whose main thread freezes that long (level loads, breakpoints): use a longer
  timeout or reconnection. Cache `get_unique_id()`: it errors after the connection closes.
- Broadcast only public message types; everything else is built per peer by `server/` (§5).
- #21 (open): on one machine, a hard-killed windowed client can make the host lose the other client too. Test
  between machines before M3 depends on ENet.

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
- **Decided by the M1 spike** ([voice ADR](decisions/2026-09-29-voice-approach.md): **go**; numbers in #15
  and #16):
  - Codec: TwoVoIP (`two-voip-godot-4`) **v6.5** on Windows with Godot 4.7.2: 48 kHz mono, 20 ms frames,
    24 kbit/s, RNNoise. v6.6 crashes the editor on import (goatchurchprime/two-voip-godot-4#107).
  - Audio is **relayed through the host**, which routes each frame and never decodes it. Clients then receive only
    the voice they are entitled to (§5), and no peer-to-peer connection is needed.
  - Falloff happens on the listener: the `AudioStreamPlayer3D`'s `max_distance` equals the host's cutoff, so the
    sound fades to about zero where delivery stops. Only the host's rule decides who hears; the fade is cosmetic.
  - Measured: mouth to ear 365–375 ms on one machine, of which ~70 % is the audio devices and Windows, which
    Godot does not see. The game's own path is ~85 ms, plus ~23 ms for RNNoise. CPU for 10 players talking at once:
    ≤ 11 % of one core. A speaker uploads ~54 kbit/s on the wire.
- Lessons for M5:
  - Voice routing follows the same visibility rules as snapshots.
  - Stop sending during silence (voice activity detection or Opus DTX). A silent player's steady stream costs
    bandwidth and decodes, and shows roughly where they are once snapshots are filtered.
  - The host renumbers each speaker→listener stream. Forwarding the speaker's own sequence number shows a listener
    how much the speaker sent to others.
  - Replace the fixed 60 ms prebuffer with an adaptive one: over Wi-Fi the playback queue doubled to 75 ms.
  - After a listener leaves the cutoff, the audio already queued still plays at the last gain: flush or fade it.
  - Check whether TwoVoIP enables Opus in-band FEC; `decode_fec` may only conceal a lost frame.
  - Measure the host's per-send ENet cost with many listeners. In the spike, relaying one frame to one listener,
    ENet send included, cost 111–167 µs against 10 µs without the send, unexplained. At 81 sends per 20 ms that
    would be ~40 % of one core.
  - Godot 4.7.2 WASAPI reads only mono or stereo microphones; laptop arrays need 4.8 (#22). There is no
    input-latency API in 4.7.
- *Open (M5):* occlusion, dead chat, meetings, radios, push-to-talk or voice activity, echo cancellation, and
  lowering the device latency (options in the ADR).

## 7. Movement

Client-side movement for the local player; the host checks speed and teleports; remote players are interpolated.
*Open (M4):* tick rate, snapshot format, correction policy.

Lessons from the M1 spike (#13, #14):
- A starting point: 20 Hz snapshots, remote players drawn 2 ticks (100 ms) behind an estimated host clock. The
  delay must cover one tick interval plus the jitter; 100 ms covers about 30 ms of jitter. With 100 ms of jitter it
  starved 25 % of frames: M4 needs an adaptive delay.
- Stamp snapshots from the host clock and skip ticks; never count sends, or tick time falls behind for good after a
  host hitch. Estimate the host clock from a sliding window of arrivals, not an all-time maximum.
- The host's movement check should compare distance with the *client's* tick delta and separately bound the
  client's tick rate. The spike's budget, refilled from host time, rejected an honest player after a network stall. If a budget is used,
  refill it before reading a frame's packets.
- A correction is a reliable placement with an epoch. Moves in flight from the old epoch are dropped as stale, so
  one correction does not cascade.
- Client-side movement is a claim: walls and height need their own host checks (a ray or navmesh test) if they
  matter. Inputs expire or are bound to a tick, so a killed client's last intent does not keep it moving.

## 8. Debug tooling

A dev console and debug commands (spawn bots, force role, skip phase, show hidden info locally) in debug builds
only, so the designer can test a mechanic alone.

## 9. Content API (the engineer–designer contract)

A mechanic is data: a `Resource` composed from parts the engine provides. Adding a mechanic should usually mean
adding data plus at most one new effect class, never changing the core loop: that is the test of this API. The
designer's agent uses **only** the parts listed here. A missing part becomes an `engine-request` issue; the engineer adds it with tests and lists it
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
| Voice integration: occlusion, dead chat, meetings, radios, push-to-talk or voice activity, echo cancellation, device latency | M5 |
| NAT traversal: Steam networking vs WebRTC with a signaling server | M6 ADR |
