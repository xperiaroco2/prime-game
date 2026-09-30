# Wire format and the host session

- **Status:** Proposed: the engineer reviews it in #89's PR, with the choices E1 to E16 below
- **Date:** 2026-09-30
- **Deciders:** designed by the agent in #89 (M3 design); the engineer decides E1 to E16
- **Builds on:** [listen server and the message layer](2026-09-29-listen-server-and-message-layer.md),
  [match loop, intents, events and entitlement](2026-09-29-match-loop-intents-events-and-entitlement.md),
  [content API v0](2026-09-29-content-api-v0.md), [voice approach](2026-09-29-voice-approach.md),
  [MVP rules](2026-09-29-mvp-rules.md)

## Context
Stage 2 (M2) built `core/`'s intents, events, snapshots, voice routing and the projection `view_of`; #40 and #70
built the transport, its one kind table and the LATEST merge. M3 carries `core/` between machines: what goes on the
wire, how `server/` wraps `core/` on a host, what a client decodes, and the test that nothing leaks. Before any M3 code,
as #32 and #33 did for M2, the engineer reviews this design (#30, stage 3). What constrains it:
- **Invariants 1 and 2.** Clients send intents; every message is built per recipient from `core/`'s recipients; the
  host's own client goes through the same codec and the same filter.
- **Freezes** (#21, #70, PR #84). After a 5 s freeze a peer's backlog arrives in one poll. The LATEST lane keeps only
  the newest message per sender and kind between two of that sender's reliable messages, so a LATEST message must stand
  alone, and a host-to-client LATEST kind must hold every visible player in one message. #84 left two questions for
  M3: `MoveClaim`'s lane (a merged claim loses its `jumped`), and advancing the host's ticks after its own freeze
  before it applies the first claims.
- **The M1 lessons** (ARCHITECTURE §4, §7): a compact header, because `var_to_bytes` framing is as large as an Opus
  frame; defensive decoding, because `bytes_to_var` ignores trailing bytes; ticks stamped from the host's clock;
  budgets refilled before a frame's packets are read; voice on an unordered lane, renumbered per stream.
- **`core/`'s contract.** `Match.apply` takes only the next tick to run; the command log records everything a replay
  needs; `view_of(peer)` is what an honest client of that peer can know, which the leak test compares against.
- **The 4.7.2 API.** `World3D.direct_space_state` is limited to `_physics_process` when physics runs on its own
  thread; `PackedByteArray.decode_*` "fails" when too few bytes are left.
- **A hobby project** (root `CLAUDE.md`): the protections here prevent accidents (a looping client, a build or content
  mismatch, a frozen PC), not attackers.

## Decision
The details are in `docs/ARCHITECTURE.md`: §4.3 (the schemas), §4.4 (the codec), §4.5 (the host session) and §4.6 (the
client, the bots and the leak test). The main choices:

1. **One declarative schema table** in `net/messages/`, with `core/`'s field names (`MatchCommand.args`, each event's
   `to_dict()`), from which `NetKindTable.game()` is built (E4). A decoded message equals what `core/` emitted, so the
   leak test compares exactly, and a test in `tests/` checks the table against `core/`'s intents
   (`Intents.FIELDS`, which 3e adds: on `main` an intent declares no fields) and events.
2. **Compact, lossless, defensive binary.** Little-endian fixed-width fields through `PackedByteArray.encode_*`; `f32`
   for every float (E6); ids as the content's own names in the alphabet `a-z 0-9 _` (E5); a reader that checks the
   bytes left before every read and rejects the whole message at the first problem; never `var_to_bytes`. The
   encoder refuses what the decoder would reject.
3. **Lanes.** Every intent and every event is RELIABLE, state sent only on change (`SelfStatus`) included. `MoveClaim`
   and the snapshot are LATEST; voice is VOICE. `MoveClaim` carries `jumps`, the client's jump count since it adopted
   the epoch, which survives a merge (E2).
4. **The snapshot holds avatars only** (E3); items and bodies travel in the reliable events that change them.
5. **Versions.** `Hello` (kind 1, the version first) and `Rejected` (kind 32) never change, so a client of any version
   reads `wrong_version`. The protocol version is one number with `core/`'s `JoinRules.PROTOCOL_VERSION`. `Hello` also
   carries the game mode's content hash (E1).
6. **The host session** steps from the physics step on the host's clock: it catches up the ticks a freeze skipped
   before it applies anything, keeps one queue by arrival, delivers each event to exactly its recipients, carries out
   the directives in the outbox's order, sends snapshots after a tick's events, relays voice along the last tick's
   routing with that tick on each frame (E11), enforces the hello deadline, bounds each peer's rate and disconnects a
   peer that keeps sending malformed packets (E7).
7. **Geometry.** Per level, a `World3D.new()` holding the level's static colliders through `PhysicsServer3D`, built
   when the session starts (E8); `Match` tells the port which level it asks about (E9); a player's floor is the highest
   under the capsule's footprint and an item's is one ray below it (E10); whether a fresh space answers before its
   first step is probed first (3c).
8. **Clients and bots.** A `ClientSession` decodes into a view shaped like `PeerView`; a bot is a `ClientSession` and
   a script. The leak test compares each bot's decoded view with `view_of` (the events exactly, the snapshots' avatars
   and the voice frames as subsets) and checks invariants that read the events' own fields. One process with a
   simulated clock, and ENet with the real clock (E12); a failed match leaves a log that replays it (E13).

## Alternatives
- **For choice 1.** *A hand-written class per message* (E4 b): about 30 classes whose encoder and decoder can drift
  apart, each checked against `core/` by hand. *Encoding in `server/` and decoding in `client/`* (E4 c): two codecs of
  one format. *`var_to_bytes` and `bytes_to_var`*, even without objects: the M1 lessons above. *A generic serializer
  of `core/` objects*: it would bypass the per-peer filter (`net/CLAUDE.md`).
- **For choice 2.** *Half floats for velocity and facing* (E6 b): a snapshot 30% smaller, but lossy, so the leak test
  would compare with tolerances; and a huge claimed velocity overflows to infinity, which the decoder rejects, so one
  client's claim could make every snapshot of that tick undecodable. *Indices into the mode's lists for ids* (E5 b):
  compact, but when two builds' content differs an index silently names the wrong thing. *UTF-8 text in the MVP*: it
  needs a validating decoder, and no MVP string needs more than ASCII; names in UTF-8 come with #73.
- **For choice 3.** *`MoveClaim` on RELIABLE* (E2 b): a lost claim holds every later channel-0 message of that client
  until it is resent, claims arrive in bursts that remote players see as stutter, and a freeze's backlog of 100 claims
  is applied whole. *A separate reliable `Jump` intent* (E2 c): two messages that `core/` must pair (the take-off's
  position comes in the next claim), a new intent in the catalogue and a split movement rule. *Claims that repeat the
  last N claims*: larger, and a merge still loses what is older than N. *`SelfStatus` on LATEST*: losing the last
  change (stamina back to full) leaves a stale number for good.
- **For choice 4.** *Every item and body in every snapshot* (E3 b): about 920 bytes at 10 players with 20 items, past
  the 1024-byte unreliable cap as a map gets more knives, and a split LATEST kind keeps only its last part. *Items and
  bodies in a second LATEST kind at a lower rate* (E3 c): it duplicates the reliable events, and two sources for an
  item's position can disagree on the client.
- **For choice 5.** *The version only* (E1 b): a content mismatch between host and client shows only as endless
  corrections. *The content hash in `Welcome`, and the client leaving* (E1 c): the joiner is already a player, and
  everyone saw it join, when it leaves. *A version in the transport's `ADMIT`*: the transport knows no game (§4).
- **For choice 6.** *Physics frames counted as ticks*: after a freeze the count falls behind the clients' clocks for
  good (the M1 lesson). *The waiting claims applied before the catch-up*: the first claim after a host freeze covers
  about 100 client ticks against a credit of about ten and is corrected (#84's note). *Polling only on core ticks*: voice
  would wait up to 50 ms more. *Snapshots for the catch-up ticks*: a hundred stale snapshots per peer, of which the
  client's merge keeps one. *No rate limits, counting only* (E7 b): a looping client grows the command log without
  end. *Disconnecting on the first malformed packet, or on any excess* (E7 c): a corrupted packet or a thawed backlog
  would drop an honest player. *Voice without the tick* (E11 b): the leak test could check voice only against the
  invariants, not against the routing `view_of` records.
- **For choice 7.** *The level in a `SubViewport` with its own `World3D`* (E8 b): the level's meshes and scripts
  would live twice on the host (a scripted door, later, would run twice). *The host client's scene* (E8 c): a headless
  host has none, and it holds player capsules (§7.1). *`server/` switching the port's level between steps* (E9 b): a
  row action that asks geometry would get the old level. *The level as an argument of every port method* (E9 c): every
  call site changes, for what one call per transition does. *One footprint answer for every caller* (E10 a): a
  package put down within a capsule radius of a low ledge rests at its height, which decides a delivery. *One ray at
  the feet for every caller* (E10 c): a jump from a ledge's edge is corrected (§7.1's note).
- **For choice 8.** *Bots that read `core/` state or `view_of`*: they would not show that a mechanic is playable with
  what a player is told (§9.7), and the leak test would compare a thing with itself. *A real clock in the one-process
  runner* (E12 b): a 10-minute scenario takes 10 minutes of every `verify`, and its timing varies. *No saved logs*
  (E13 c): a failure in an unattended run cannot be replayed.

## Consequences
- **Tasks.** #89's handoff proposes the M3 issues 3c to 3i; they replace #30's draft 3c to 3e.
- **`core/` changes** (3e, with the engineer's approval, because one touches the loop): `MovementRule` reads `jumps`
  instead of `jumped`; `JoinRules` compares `Hello.content` (`wrong_content`); `Match` calls `WorldQuery.use_level`
  on start and in each transition; `ModeCheck` refuses an id outside the wire's alphabet; a `Hello` the phase refuses
  gets `joins_closed` and `DisconnectPeer`, and Loading's entry disconnects waiting newcomers (E14); a refused
  `MoveClaim` is dropped without `Rejected` (E15); `Intents.FIELDS` declares each intent's fields and types, which
  the rules read through and 3d's test compares with the table (so 3d follows that commit of 3e).
  `WorldQuery` gains `stand_floor_below` for a player's standing, which `MovementRule` and the reach use (E10).
- **The designer** is told in the PR: content ids stay lowercase snake_case of at most 32 characters, which every MVP
  id already is. Nothing else in `content/` changes. With E8 (a), a level's collision is `StaticBody3D` nodes, not
  CSG or `GridMap` (their collision exists only in a tree): a point for 4e's level conventions.
- **`net/`** gains `net/messages/`; `NetKindTable.game()` stops being empty; the transport gives `server/` its
  rejects per peer (3f). Every new event or intent costs one row and a version bump (§9.8 said so).
- **Bandwidth.** The host uploads about 0.6 Mbit/s of snapshots at 10 players, plus voice (voice ADR: about
  3.3 Mbit/s with everyone talking and a compact header, far less with voice activity).
- **Risks, each with where it is settled.**
  - A fresh space under Jolt may not answer before its first step: 3c probes it first; the fallback is one physics
    step before `Match.start`.
  - Whether `decode_*` past the end prints an engine error, and whether typed and untyped Dictionaries compare equal:
    3d's tests pin both; the design does not depend on either.
  - The host's own client's messages lead the network's by at most one frame (§4.5).
  - A command that waited in the socket during a host freeze can lose to a timer (the countdown, the loading deadline).
  - The one-process bots runner does not exercise ENet's timing; the ENet run does, if it is fast enough for `verify`.
  - The rate-limit numbers are placeholders; a playtest with voice may need others.

## Needs the engineer
The design follows each recommendation, and each can be reverted before its task lands.

| # | Choice | Options | Recommendation |
|---|---|---|---|
| E1 | What `Hello` checks | (a) the version and a content hash (the game mode's `ContentHash` and the SHA-256 of each level file it names, since `ContentHash` covers levels only by path), `wrong_content` on a mismatch; (b) the version only; (c) the hash in `Welcome`, the client leaves | (a): a designer's branch and `main` in one playtest fail at the join with a reason, not with endless corrections |
| E2 | `MoveClaim`'s lane and the jump | (a) LATEST with `jumps`, a count per epoch: one jump allowance per claim, stamina per counted jump; (b) RELIABLE; (c) a reliable `Jump` intent | (a), as §4 sketched and #84 recommended. Accepted: one jump height per merged burst, a sprint during a freeze may go unpaid |
| E3 | What the snapshot holds | (a) the avatars; (b) the avatars, items and bodies; (c) items and bodies in a second LATEST kind | (a): it stays far under the unreliable cap at 16 players, and items and bodies already travel reliably |
| E4 | Where the schemas live | (a) one declarative table in `net/messages/` with `core/`'s field names, decoded into plain dictionaries; (b) a class per message; (c) encoder in `server/`, decoder in `client/` | (a): one place, and a decoded event compares with `to_dict()` |
| E5 | Ids on the wire | (a) the content's names, `a-z 0-9 _`, at most 32, the mode check enforcing it; (b) indices into the mode's lists | (a): a content mismatch shows as an unknown id, not the wrong one |
| E6 | Floats | (a) `f32` everywhere, lossless; (b) half floats for a snapshot's velocity and facing | (a): exact comparisons in the leak test, no overflow to infinity |
| E7 | Rate limits and malformed packets | (a) per-peer budgets of voice frames, reliable intents and bytes of the rest (voice apart, so talking never starves a `SetReady`), over-budget messages dropped, a disconnect after 50 malformed messages in 10 s; (b) count and log only; (c) a disconnect on the first malformed packet or any excess | (a), numbers as placeholders: bounds a looping client's growth of the command log without dropping a thawed honest player |
| E8 | The host's collision world | (a) per level a `World3D.new()` with the static colliders through `PhysicsServer3D`, built at the start; (b) the level in a `SubViewport` with its own world; (c) the host client's scene | (a): only the colliders, the same on a headless host. Its cost: CSG and `GridMap` collision exist only in a tree, so levels give collision as `StaticBody3D` nodes (4e's conventions, with the designer), or (b) is taken |
| E9 | Which level the port answers for | (a) `Match` calls `WorldQuery.use_level(path)` on start and before each row's actions; (b) `server/` switches between steps; (c) every port method takes the level | (a): two lines in the loop, and a row action can never get the old level |
| E10 | `floor_below` | (a) the highest floor under the capsule's footprint (five rays), for every caller; (b) two methods: the footprint for a player's standing (`stand_floor_below`, new), one ray for items and bodies (`floor_below`); (c) one ray | (b): with (a) a package put down next to a low ledge rests at the ledge's height, and the delivery check reads that height; one port method more |
| E11 | Voice frames carry the host tick | (a) yes, 4 bytes; (b) no | (a): the leak test checks each frame against `view_of`'s routing for that tick |
| E12 | The bots runner's clock | (a) simulated in one process over `LoopbackHub`, real over ENet; (b) real everywhere | (a): fast and repeatable in `verify`, with ENet still covered |
| E13 | Command logs | (a) the bots runner saves a failed scenario's log; a debug-build host writes the session's log to `user://replays/` when the session ends (not per match: the log holds the seed of the matches still to come) and keeps the last 10; (b) the bots runner only; (c) none | (a): a failure in an unattended run or a playtest can be replayed |
| E14 | A `Hello` the phase refuses (Loading, Round, End; on `main`: `not_accepted`, seq 0, no disconnect) | (a) a reason of its own, `joins_closed`, then `DisconnectPeer`, and the entry into Loading disconnects every waiting newcomer; (b) keep `not_accepted`, and the client ends its join on any `Rejected` before `Welcome`; the hello deadline disconnects it | (a), with the client rule of (b) as well: the joiner is told why at once, and no newcomer lingers into the Round |
| E15 | A `MoveClaim` the phase refuses (in flight at a phase change) | (a) dropped silently by `core/`, no `Rejected`; (b) `Rejected(not_accepted)` with seq 0 as on `main`, `MoveClaim` counted against the intent budget | (a): clients ignore it anyway, and a looping client could otherwise add a reliable `Rejected` to the log and the outbox every poll |
| E16 | Payloads that legal content can push over a cap (`SettingsChanged`'s `id_sets` can reach about 18 KB at the declared maxima; a shortfall naming a 32-character id or a 255-byte path passes `text`'s 64 bytes) | (a) shortfalls as a `note` (`u16` length, up to 320 bytes), `SettingsChanged`'s cap at 8192, and `WireBudget` (`server/`) computing every content-sized kind's worst case from the mode, refusing a mode over a cap at host start and in a test over `content/`; (b) `core/` emits structured shortfalls (a reason id and numbers) that the client formats, and the maxima shrink until every kind fits its cap at them; (c) test the MVP's worst case only | (a): no change to `core/`'s events, and a designer's edit that would break the wire fails `verify` with the kind named, not a playtest with a silent missing event |
