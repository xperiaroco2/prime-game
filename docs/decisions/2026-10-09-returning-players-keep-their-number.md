# Returning players: a return key, the old number in the lobby, and #73's M7 split

- **Status:** Proposed (#73). The items marked *the engineer's* are game rules or taste, tier (c) of the
  [trust ADR](2026-10-04-trust-based-autonomy-gated-merge-into-main.md): they wait for the engineer (Needs the engineer,
  below). The *technical* items are tier (a): each stands as recommended unless the engineer or the M7 manager says
  otherwise.
- **Date:** 2026-10-09
- **Deciders:** the engineer; designed by the agent in #73 under the meta manager session, on the engineer's word
  ([#302, item 3](https://github.com/xperiaroco2/prime-game/issues/302#issuecomment-6079969242))
- **Builds on:** the engineer's naming decision of 2026-09-30 on #58 ([MVP rules](2026-09-29-mvp-rules.md), Player
  names); the engineer's answers on #73 of 2026-10-08
  ([comment](https://github.com/xperiaroco2/prime-game/issues/73#issuecomment-6055665386)), which moved the own name
  and the body colour to M6.2 (#550, #551); [listen server and the message
  layer](2026-09-29-listen-server-and-message-layer.md) (no reconnection in the MVP); [wire format and the host
  session](2026-09-30-wire-format-and-host-session.md) (E1, E13, E14); [the M6
  design](2026-10-04-m6-playable-over-the-internet.md) (WebRTC, E50's peer ids, the service's closed rooms)
- **Numbering:** this design's choices are **P1 to P12** and its proposed issues **73-A to 73-D**, not the next E and D
  numbers: three M7 designs (#36, #37 and this one) ran at once from `main`, which does not hold M6.2's E62 to E72 and
  D25 to D36, so shared numbers would collide. The engineer may renumber them on acceptance.

## Context
What the MVP does (ARCHITECTURE §3.2, §3.5, §4):
- The host names every joiner `Player<n>`, n counted by accepted joins over the host session (`MatchState.joins`), and
  never reuses a number: Player1 to Player3 join, Player2 leaves, the next joiner is Player4. `ResetMatch` keeps the
  count.
- A player is a peer id, and `core/` keys every player by it. Each connection gets a new one (ENet's, or the WebRTC
  host's next, E50), so a player who comes back is a new peer.
- Joins are taken in Lobby and Countdown only. In every other phase `server/` refuses connections
  (`set_refuse_new_connections`) and the signalling service answers a join of the closed room with "the match has
  started" (§4.8), which the client reads as `joins_closed`. A player who leaves mid-round is `left`, which "no crew
  present" counts, and `ResetMatch` drops it.
- The host notices a crashed client only at its transport's timeout (ENet: 10 to 20 s, §4 Timeouts; WebRTC: 20 s
  of silence, `WebRtcTransport.SILENCE_MS`, §4's silence rule).

What the engineer asked (2026-09-30): a freed number stays with the player who had it, for a reconnection; binding the
number to that player (the engineer named the IP) comes with reconnection. The answers of 2026-10-08 settled two of
the issue's four open questions and split the issue:
- **Duplicate names get a suffix** ("Dima", then "Dima 2"), decided by the host: #550 (M6.2), `Hello.name` and a
  protocol bump.
- **A taken colour:** the host gives the first free of the 10; **the colour is public**: #551 (M6.2), `SetProfile` in
  the lobby. The settings UI is #491 (the Esc menu's Character tab) and #493 (the main menu).
- **This issue keeps, for M7,** the number on a return, what identifies a returning player, and what the rest of a
  return restores.

What constrains the design:
- **Invariant 1:** the host decides who returns; a client claims nothing but a key.
- **Invariant 2:** a key that reached another peer would let that peer take its owner's number now, and its role if a
  later design lets a player return into a round: a key is hidden information, and the leak test must say so.
- **Invariant 3:** `core/` stays deterministic: the key is an argument of `Hello` like the version, logged and
  replayed; the host draws no randomness for it.
- **The transport abstraction:** `NetTransport` exposes no address. In Godot 4.7.2 `ENetPacketPeer.get_remote_address`
  exists, `WebRTCPeerConnection` has no address method, and the loopback has no address at all.
- **One PC, several windows:** the windows of `tools\run.cmd host --clients N` share one `user://` folder but each
  keeps its own settings file (`PRIME_INSTANCE`, `UserSettings`).

The cases a return must survive:

| # | Case | What must happen |
|---|---|---|
| S1 | A player's Wi-Fi drops for 30 s in the lobby; the game says the host is lost; the player joins again with the same code | the old number back |
| S2 | The game crashes or is closed by mistake; the player starts it again and joins | the old number back |
| S3 | Two friends play from one house behind one router (one public address), or through one VPN exit | two players, each with its own number |
| S4 | The engineer's one-PC test: `host --clients 2` | three players |
| S5 | A player starts the exported game twice on one PC (one settings file) | neither window breaks |
| S6 | The host quits and hosts again (a new session, a new code) | everyone starts afresh, as today |

## Decision
Recommended; each item's options and the failure each leaves are in the table of choices below.

1. **A return key identifies a returning player** (P1). Each settings file holds a random key: 16 bytes from
   `Crypto.new().generate_random_bytes(16)`, written as 32 lowercase hex characters (`PackedByteArray.hex_encode`),
   made on the first read when absent or malformed and written at once; settings kept in memory (tests, bots) make
   their own. The client sends it in every `Hello`. It survives a dropped connection and a restart (S1, S2), differs
   between two players behind one address (S3) and between the windows of one PC (S4), and costs no host randomness.
2. **The host binds a key to a number** (P5). `MatchState` keeps `numbers`, key → number, session state like `joins`
   (`ResetMatch` keeps it, a leave never removes it); `PlayerState` gains `number`; no `PlayerState` holds a key, so no
   event built from a player's fields can carry one. After the version, content and room checks (a full lobby
   refuses a returner with `full`, as any joiner: no seat waits for a leaver), `JoinRules.hello`:
   1. reads the key: a String of 32 characters of `0-9a-f`, else none (P7: never a `Rejected`);
   2. a key bound to a number that no present player holds: the joiner gets that number back, and `joins` does not
      count it;
   3. otherwise the number is `joins` + 1, and a key not bound yet is bound to it. A key whose number a present player
      holds stays with that player: the newcomer is a new player with a new number and no binding (P2; S5, and a
      restart faster than the host's timeout).

   The fallback name is `Player<number>`. #550's own name and #551's colour apply to a returner exactly as to any
   joiner, against the present players (P3). `joins` becomes the highest number given.
3. **Only where joins are allowed** (P4). A return is a join: Lobby and Countdown take it (in Countdown it cancels the
   countdown, as any join does); every other phase refuses it as today, at the transport and the service. A player
   who left a round comes back in the next lobby with its number.
4. **The wire** (P6, P8). `Hello` gains `key: id` at its end, after #550's `name`: 32 lowercase hex characters fit
   the `id` alphabet (`a-z`, `0-9`, `_`) and its 32-byte maximum, 33 bytes on the wire and no new wire type. The row
   declares it `WireField.id("key", true)`, which decodes as a String: a plain `id` decodes as a StringName, which
   item 2's first check reads as no key. `Intents.FIELDS[HELLO]` declares `key` beside #550's `name`
   (`MatchCommand.field` reads declared fields only). The protocol version goes up by one; the two-step decode of
   `Hello` keeps an old client's `wrong_version` (§4.3, Frozen). No event carries the key or the number: the number
   shows only through the fallback name.
5. **The client.** `UserSettings` gains the key, beside the entry #550 adds for the name. `ClientSession` sends the
   key it is given, or one of its own when given none, so every test and bot `Hello` stays encodable, and so does a
   stand-in's of the tutorial design on `release/m6.2` (#552), which then needs no key of its own. Joining again needs
   nothing new in the menus (P9 asks whether the main menu should start with the last code and address).
6. **Never leaves the host** (ARCHITECTURE §5 gains it when 73-A builds it): a player's key arrives from its owner and
   reaches no other peer. The command log holds it, as it holds the session seed, on the host's disk only (§4.5.10;
   P10).
7. **Tests.** `core/` unit tests for each rule above; the wire row; a loopback test of a leave and a return over every
   client's roster; a bot scenario of a leave and a return in the lobby and after a round (73-B); the leak test's
   independent invariant "no decoded message holds a key"; a malformed but wire-valid key (an `id` that is not 32 hex
   characters, `zz`) as a core unit test and a wire-fuzz case; chaos: the hostile peer's own joining `Hello` carries
   the key of an honest bot that is already in, so the hostile joins as a new number and that bot plays on. A chaos
   peer sends only one joining `Hello`, and `JoinRules.hello` refuses every later one with `not_accepted` before it
   reads a field, so the extra `Hello`s the hostile already sends stay `not_accepted` whatever key they carry.

Not designed here: a return into a running round (P4 (b), (c): 73-D if the engineer wants it) and masks and
ready-made parts (P11).

### The choices
| # | Whose | Choice | Options | The failure each leaves | Recommendation |
|---|---|---|---|---|---|
| P1 | the engineer's (he named the IP) | What identifies a returning player | (a) the IP address (`ENetPacketPeer.get_remote_address`); (b) the name; (c) a random key per settings file, sent in `Hello`; (d) a random key per launch, in memory only; (e) a ticket the host makes and sends in `Welcome`, kept by the client; (f) the device id (`OS.get_unique_id`); (g) a platform account (a Steam id) | (a) S3: two friends behind one router are one "player" to the host, so the second to join takes the first's number (and, with a later return into a round, its role); over WebRTC the host never learns an address (`NetTransport` exposes none, `WebRTCPeerConnection` has no address method in 4.7.2) and through TURN it would be the relay's; a router that reconnects may change it (S1). (b) anyone who types a leaver's name takes its number; a player who renamed (`SetProfile`, #551) is a stranger. (c) S5: the second window shares the key and joins as a new player (P2), so only the first can return. (d) S2: a restarted game has a new key. (e) as (c) or (d) by where the client keeps it, plus a `Welcome` field, tickets the client must file per code or address, and host randomness (a new `RngStreams` purpose). (f) S4: every window of one PC has the same id; on the Web it is empty; a hardware id goes to every host. (g) needs Steam networking, which D16 (a) did not choose | **(c)** |
| P2 | technical | A `Hello` whose key a present player holds | (a) the newcomer joins as a new player: a new number, no binding; (b) the newcomer takes the seat: the host disconnects the holder first; (c) the newcomer's join waits until the holder leaves; (d) `Rejected` | (a) a player who restarts faster than the host's timeout (ENet: 10 to 20 s; WebRTC: 20 s) gets a new number. (b) S5: the second window disconnects the first, every time. (c) a pending join in `core/` with a deadline of its own, for a race of seconds. (d) S5's second window cannot play | **(a)** |
| P3 | the engineer's | What a return restores in the lobby | (a) the number only: the name and the colour follow #550's and #551's rules as for any joiner, ready off, a free lobby spot; (b) the number, and the leaver's final name and colour stay reserved for it for the session; (c) the number, and the leaver's final name and colour back when free, whatever the client sends now | (a) a returner whose colour a newcomer took gets the first free one: "Dima was blue, now he is green"; and a returning "Dima" whose name a newcomer took is "Dima 2". (b) 10 players and 10 colours: a reserved colour can leave a newcomer none, so a reservation must give way anyway; a leaver who never returns keeps its name taken all evening (the next "Dima" is "Dima 2"). (c) overrides a name or colour the player changed while away | **(a)** |
| P4 | the engineer's | A return while a round runs | (a) none: every phase but Lobby and Countdown refuses joins as today, and the leaver returns in the next lobby; (b) a waiting return: the returner connects during the round, receives nothing of it, and becomes a player in the next lobby; (c) back into the round: the same role, a life state and a place the engineer decides | (a) a player whose connection drops 2 minutes into a round sits out the rest, and its side plays one short ("no crew present" counts it as left). (b) for a few minutes' convenience: `server/` accepts connections mid-round and `core/` refuses all but returners (`set_refuse_new_connections` cannot tell them apart); the signalling service passes a join of a closed room to its host (a protocol change and a Worker redeploy); `core/` gains a waiting non-player. (c) all of (b), plus: the peer id changes, so every client re-keys the player's avatar, name plate and voice (a new event, or a stable player id in every event); a mid-round `Welcome` with the round's public state and the returner's own (role, teammates, health, stamina); a level load outside Loading for one client; the leak test over a return; and game rules: does the avatar vanish or stay, defenceless, while its player is away; where and in which life state the returner comes back; are its dropped items lost; how long a seat waits. Without such rules a cornered player quits and comes back across the map | **(a)** in M7; (c) as its own design (73-D) only if playtests show mid-round drops matter |
| P5 | technical | Where the binding lives | (a) `MatchState.numbers` (key → number, session state) and `PlayerState.number`; no key on a player; (b) the key on `PlayerState`; (c) in `server/` | (b) a later event, debug dump or `Welcome` roster built from a player's fields carries the key to every peer. (c) a rule outside `core/`, which neither the core tests nor a replay would see (invariant 3) | **(a)** |
| P6 | technical | The key on the wire | (a) `key: id`, appended to `Hello`; (b) a new wire type of 16 raw bytes; (c) two `s64` | (b) one more decoder to write, fuzz and pin, to save 17 bytes once per join. (c) a key in two halves and GDScript's signed ints | **(a)** |
| P7 | technical | A key `core/` cannot use: not a String, or not 32 characters of `0-9a-f` (the scenario runner and the test fixtures reach `core/` without the codec) | (a) none: a new number, no binding, the `Hello` still joins; (b) `Rejected(bad_args)` and `DisconnectPeer` | (a) a client with a broken settings file never returns (it still plays). (b) every test helper and core caller that sends no key stops joining | **(a)** |
| P8 | technical | The number on the wire | (a) not sent: it shows only as `Player<n>`; (b) `PlayerJoined` and the `Welcome` roster carry `number: u16` | (a) no screen can show that a player with an own name returned. (b) a protocol change no screen reads yet | **(a)**, until a screen orders or shows players by number |
| P9 | the engineer's (the menus are taste) | Joining again | (a) nothing new: the player types or pastes the code or address again; (b) the main menu's code and Direct fields start with the last code and address a join used (the settings file); (c) a "Join again" button on the screen a lost connection ends on; (d) automatic retries after a lost connection | (a) after a Wi-Fi drop the player asks in chat for the code again. (b) a stale code (the host hosted again) gets the usual "no such room". (c) a new control the UI track must draw and translate. (d) retries against a host that really quit, each until a timeout, and a rejoin the player did not want | **(b)**, its own small issue after #493 (73-C) |
| P10 | technical | The key in the command log | (a) as sent; (b) `server/` hands `core/` a SHA-256 of the key (`HashingContext`), so a log holds no usable key | (a) a replay shared outside the group (attached to a public issue, say) holds keys that would take their owners' numbers at a later session of a host they left: the key per settings file is the same in every session. (b) one more step between the codec and `core/`, which the scenario runner and the fixtures must repeat, or `core/` sees two forms | **(a)**: the log stays on the host's disk and already holds the session seed, which is worth more (§4.5.10); revisit with P4 (c), where a seat holds a role |
| P11 | the engineer's | Masks and ready-made parts: [vision revision 1](2026-10-01-vision-revision-1.md) lists "customization from ready-made parts and masks with an animated mouth (#73)" after the MVP, and [the M5 design](2026-10-02-m5-voice-integrated-with-the-rules.md)'s D14 answer "a mouth animation with the masks of #73" | (a) outside #73: the 3D track's cosmetics (#165) and the Character tab's hidden Hat row (#491) take them, designed when the art exists (a part would be a content id in the profile, checked by the host and public like the colour); (b) designed in #73 now | (a) the vision's line, D14's answer and ARCHITECTURE §6.5.6, §6.5.10 and §10 point at #73 until the engineer names the issue that takes masks. (b) a design for parts and masks that do not exist, whose names and rules would be invented | **(a)**; on acceptance the pointers move to the issue the engineer names |
| P12 | technical (no new step: the engineer adds steps, §9.7) | A leave and a return in a bot scenario, where a `Join` is a script's first step, at most once | (a) a `Join` may also follow the bot's own `Leave`; each bot keeps one fixed key from its number, in the core runner and the net bots alike; (b) a new step `Return` | (a) `BotScenario.problems()` (which today reports a second `Join` and a `Join` that is not the first step) and §9.7's rule change; the runners give the returning bot a new peer id, and `ScenarioPeers` and the leak check learn that one bot had two peers. (b) one more step class doing what `Join` does. **Either way, the timing of a returning `Join`:** a bot that left receives nothing, so it cannot wait for `ReturnToLobby`; `Join(at_s)` counts from the start, and a `joins_closed` or a refused connection fails the step at once (§4.6.7). (t1) `at_s` of a `Join` after a `Leave` counts from that `Leave`: real-clock bots still race the host's `ReturnToLobby`; (t2) a `Join` after the bot's own `Leave` retries a `joins_closed` or a refused connection every 0.5 s, as a join that found `no_room` does, until a deadline the step carries, then fails naming the last reason: no race, one more rule in the runners; (t3) the scenario forces the host bot's `ReturnToLobby` and `clock_s` so that `at_s` falls after it with a margin it names: holds in the core runner, flaky over ENet and WebRTC under load | **(a)**, with **(t2)** |

### The split
Sizes as in M6: S up to about 400 changed lines, M up to about 900, L up to about 1500. Effort as in AGENT_WORKFLOW §7
(`core/ server/ net/` and the harness: high). Every issue's base is `release/m7` when M7 has one, else `main`.

| Issue | Goal | Acceptance | Files | Depends on | Protocol | Effort | Size |
|---|---|---|---|---|---|---|---|
| 73-A | net, core, client: the return key and the old number in the lobby | the key in `UserSettings` (made once per settings file, kept across reads, a malformed one replaced) and in every `Hello`; `JoinRules` gives a returner its number and the fallback name `Player<number>` (Decision 2); a key a present player holds joins as a new number (P2 (a)); an unusable key joins with none (P7 (a); a core unit test with the wire-valid `zz`, and the wire fuzz over the new row); a return in Countdown cancels it; a return after End → Lobby keeps its number; `joins` is not counted by a return; `Hello.key: id`, decoded as a String and declared in `Intents.FIELDS` (Decision 4), the protocol version plus one; ARCHITECTURE §3.5, §4.1, §4.3.2, the Frozen bullet and §5's "Never leaves the host"; tests: core unit tests for each rule, the wire row byte for byte and a strict round trip, a loopback `host_session_test` (a leave and a return: every client's roster names the returner as before; the next joiner gets the next number; a window with a present player's key joins as new), `user_settings_test`, `client_session_test` | `core/match/match_state.gd`, `player_state.gd`, `phases/join_rules.gd`, `intents.gd`; `net/messages/wire_schema.gd`; `client/app/user_settings.gd`, `client/net/client_session.gd`, `client/app/game.gd`; every test helper that builds a `Hello` (`fixture_base_mode.gd`, `host_session_harness.gd`, `bot_watcher.gd`, `chaos_hostile.gd`, `scenario_runner.gd`, `wire_samples.gd`); their tests; `docs/ARCHITECTURE.md` | #550 (its `Hello.name` first: one wire change at a time), #551 if it changes `Hello`; P1, P3, P4 | yes | high | M |
| 73-B | tests: a leave and a return in the bots, and the key in the leak test | a `Join` may follow the bot's own `Leave` (P12 (a)), in `BotScenario.problems()` and §9.7, the returning bot on a peer id not used before in the session; such a `Join` retries a `joins_closed` or a refused connection every 0.5 s until its deadline (P12 (t2)), in §9.7's `Join` row and §4.6.7; `ScenarioPeers` maps the bot to its current peer and each peer it had to the bot; `LeakCheck` checks each connection of a returning bot as its own view (`check_bot` per peer id, the earlier one as a prefix); each bot's key fixed from its number in the core runner and the net bots, over ENet and WebRTC alike (`bots --transport webrtc` passes the scenario too); a scenario in `content/scenarios/` (provisional under the [MVP content ADR](2026-09-29-mvp-content-built-by-the-engineer.md): the engineer approves it in the PR): three bots join, bot 2 leaves in the lobby, bot 4 joins as Player4, bot 2 returns as Player2, then a round in which bot 3 leaves and, after `ReturnToLobby`, returns as Player3; `bots` passes it; the invariant "no decoded message of any peer holds any player's key" in `LeakCheck` and `ScenarioInvariants`, seen failing on a planted leak and reverted; `bots --chaos`: the hostile peer's joining `Hello` (the one its `ClientSession` sends) carries the key of an honest bot, sent only after that bot's `PlayerJoined`, so the hostile joins as a new number with no binding and that bot plays on (`ChaosOracle` checks both); the extra `Hello`s the hostile already sends on its joined connection stay `not_accepted` whatever key they carry, and some carry one; a malformed key is 73-A's core unit test and a wire-fuzz case, not a chaos case (a chaos peer joins once) | `core/content/scenario/bot_scenario.gd`, `step_join.gd`, `tests/harness/` (`scenario_runner.gd`, `scenario_play.gd`, `scenario_bot.gd`, `scenario_peers.gd`, `scenario_invariants.gd`, `bots/bots_runner.gd`, `bots/bots_enet.gd`, `bots/bot_client.gd`, `bots/net_play.gd`, `bots/bot_web_rtc.gd`, `bots/view_file.gd`, `bots/leak_check.gd`, `chaos/chaos_hostile.gd`, `chaos/chaos_scenario.gd`, `chaos/chaos_oracle.gd`, `chaos/chaos_run.gd`), `content/scenarios/<new>.tres`, `docs/ARCHITECTURE.md` §4.6.4, §4.6.5.3, §9.7 | 73-A; P12 | no | high | M |
| 73-C | client: the main menu starts with the last code and address | only with P9 (b): the settings file keeps the last code and Direct address a join used; the main menu's fields start with them; `user_settings_test`; a `shot` of the menu | `client/app/user_settings.gd`, the main menu's script (#493), its tests | #493; P9 | no | medium | S |
| 73-D | design: a return into a running round | only with P4 (b) or (c): an ADR with the engineer's rules (the avatar while away, where and how the returner comes back, its items, how long a seat waits, "no crew present"), the transport and signalling changes, the peer id across a return, the mid-round `Welcome`, the leak test's cases and a split | `docs/decisions/`, `docs/ARCHITECTURE.md` | P4; playtests with mid-round drops | no | high | S |

The own name and the colour need no M7 issue: #550 and #551 build them in M6.2, #491 and #493 their screens.

### Needs the engineer
One batch; each item's options and the failure each leaves are in the table of choices.
1. **P1**, what identifies a returning player: (a) the IP; (b) the name; (c) a random key per settings file; (d) a key
   per launch; (e) a host ticket; (f) the device id; (g) a platform account. Recommended (c): the IP joins two friends
   behind one router into one player and is unknown to the host over WebRTC.
2. **P3**, what a return restores in the lobby: (a) the number only; (b) the number, with the name and colour reserved;
   (c) the number, with the old name and colour back when free. Recommended (a).
3. **P4**, a return while a round runs: (a) none, the next lobby; (b) a waiting return; (c) back into the round.
   Recommended (a) in M7, and 73-D's design only if playtests show mid-round drops matter.
4. **P9**, joining again from the menu: (a) nothing new; (b) the last code and address filled in; (c) a "Join again"
   button; (d) automatic retries. Recommended (b), as 73-C.
5. **P11**, masks and ready-made parts: (a) outside #73, with the cosmetics (#165, #491's Hat row); (b) in #73 now.
   Recommended (a).
6. **The split:** (a) 73-A and 73-B in M7, 73-C with P9 (b), 73-D only with P4 (b) or (c); (b) 73-A and 73-B wait
   for 73-D: once #550 lets a player name itself, the old number shows only on a player who set no name (P8 (a)), so
   in M7 a return is mostly the key's groundwork; (c) with the changes you name. Recommended (a): it is what you asked
   for on 2026-09-30, and the key, its binding and the leak test's invariant are what 73-D would build on.

## Alternatives
- **The IP address** (P1 (a)), the engineer's first idea: it identifies a router or a VPN exit, not a player, and
  WebRTC hides it.
- **A ticket from the host** (P1 (e)): as good as a client key, but it needs a `Welcome` field, host randomness and a
  ticket store per host on the client, for the one gain that the host would make the key.
- **Reserving a leaver's name and colour** (P3 (b)): 10 colours for 10 players cannot hold a reservation, and a name
  held for someone who never returns renames the next player with that name.
- **Taking a seat over** (P2 (b)): fixes the seconds after a crash, breaks a second window for good.
- **A return into a running round now** (P4 (c)): the transport, the signalling service, the peer ids, a mid-round
  state transfer and new game rules, for a case no playtest has measured yet.
- **Hashing the key before `core/`** (P10 (b)): kept for when a seat holds a role.
- **Bindings that outlive the host session:** the host's own exit ends the session (the listen-server ADR), and the next
  session starts from Player1 as today (S6); a table kept in the host's `user://` would carry keys of sessions nobody
  plays any more.

## Consequences
- `Hello` grows by 33 bytes, and the protocol version rises once more after M6.2's own bumps (#550, #551 and any other;
  9 on `main` and `release/m6.2` today), by the M4 ADR's rule: the base's plus one at the rebase before the merge.
- `UserSettings` sends a second value to the host (#550 sends the name first); its header's "Never sent to anyone"
  changes with #550.
- ARCHITECTURE §5's "Never leaves the host" gains the key, and the leak test an invariant that does not trust the
  audience declarations.
- A debug forced role (`MatchState.forced_roles`, by peer id) does not follow a returner, whose peer id is new. The
  scenarios force roles at the start only, so none is affected.
- On acceptance: a dated note in the MVP rules' Player names (the return: this ADR) and in the listen-server ADR (no
  reconnection in the MVP; M7 returns to the lobby only). ARCHITECTURE's pointers to #73 for the own name (§3.5's Names
  bullet, §4.1's `Hello` row, §4.3's `text` row, the Frozen bullet and the content-hash paragraph) move to #550 when
  #550 rewrites those lines on `release/m6.2`; this design leaves them, so the next merge of `main` into `release/m6.2`
  does not conflict with #550's edits.
