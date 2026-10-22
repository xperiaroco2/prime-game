# The knockdown reworked (#728): still and mute, a ragdoll, and the body a rigid body in the host's physics

- **Status:** Accepted; built in part, see the issues (amended 2026-10-22, #1243). First written as: Proposed on 2026-10-10. Nothing here is built, and nothing will be until the engineer says so: for now
  the track only designs
  ([PR #695, comment 6096108206](https://github.com/xperiaroco2/prime-game/pull/695#issuecomment-6096108206)). The
  rules are his: #728's "Decided" list and his answer A in its comment 6095620279 (first given as RD7 on PR #709,
  comment 6095445261). The KD items are game rules and taste (the
  [trust ADR](2026-10-04-trust-based-autonomy-gated-merge-into-main.md)'s "ask and wait"), and KE1 and KE5 are his
  too: KE1 answers #728's open question 4 ("Open (the engineer's)") and departs from its sketch (a client-only
  ragdoll, the host keeping the rest position), as the throwing ADR's TE1 is his; KE5 changes ARCHITECTURE §5's
  per-peer rule "nobody gets their own avatar", an architecture boundary. **He answered every one on 2026-10-10**
  ([PR #754, comment 6097876326](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6097876326), chat
  with the game-design manager session: "agrees with every recommendation"): KD1 to KD8 (a), KD9 (b), KE1 (a) and
  KE5 (a), each in its row's "Decided" column (§2, §3), and the launch plays on **the House only**: the flat greybox
  keeps the reworked knockdown (still, mute, a ragdoll) with no launch (KE12). **He answered KD10 the same day**
  ([PR #754, comment 6100602989](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6100602989)): the
  body is a real rigid body simulated by the host's physics engine in `server/`, which rolls or slides it off any
  slope, roof or stairs by itself. There is no slide rule (KD3 (a) and 728c go), and **KE1 changes from (a) to (b)**.
  The other KE items are technical, and each recommendation stands until he says otherwise. No number here is his:
  each is a placeholder marked "not a decision" (KD9 (b)). **He answered KD11 on 2026-10-11**
  ([PR #754, comment 6108669765](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6108669765)), where
  a body may come to rest, raised in the review of the KD10 (A) update: the knocked-down body's collision shape in the
  host's physics is the crouching player's collider, so a body comes to rest only where a crouching player fits, and a
  raised player gets up crouched there and stands up by the crouch's rules once there is room. His answer settles the
  first of KD11's two scenarios; the second, a body launched where nobody can reach it, is **KD12** (§2). His
  words name the collider, not its pose: that the host's capsule never turns, so it slides and falls but never rolls,
  is the agent's reading, read back to him as **KD13** (§2). **He answered both the same day with (a)**
  ([PR #754, comment 6109457234](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6109457234)): KD12,
  the levels keep every surface a launch can reach within a raise's reach of a spot a player can walk to, tables and
  the roof included (#646's TD5 (a) reach convention applied to bodies), checked on the House by tests, with no rule
  in `core/` (728f); KD13, the host's capsule is the crouching player's collider, stays upright and never turns (KE13
  as written). The review of that update found two cases those answers leave open, read back to him as **KD14** (his
  own words "make tables have colliders so nothing can be thrown under them") and **KD15** (a body launched into the
  lowered car, which only the clients collide with). **He answered both the same day with (a)**
  ([PR #754, comment 6110171062](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6110171062)): KD14,
  the confirmed read-back stands as is: tables keep the space under them, and a body may rest under a table a
  crouching player fits under, as long as a raise can reach it (KD11, KD12 (a)), with no level rule that closes
  tables; KD15, RE8's accepted quirk: a body launched into the lowered car and raised there is pushed out by the
  raised player's own client, as the car repair ADR's RD6 (a) already accepts, with nothing new in code (§2). The
  review of that answer corrected KD15's premise (RD6 (a)'s push is at most 0.4 m from the footprint box's edge; this
  one starts inside the box), so (a) stood on a test in 728e that stops it if the host corrects the push more than
  once (§2, §10). It did (3 `Correction`s), and the engineer answered KD15 again with **(b2)**
  ([#976, comment 6162445237](https://github.com/xperiaroco2/prime-game/issues/976#issuecomment-6162445237)): the
  raised player's own client walks its capsule out of the car at walk speed over its first claims, ignoring
  `movers` until clear, with no `core/` change (§2).
- **Amended 2026-10-13 (#925):** the engineer lifted "backlog for now" on 2026-10-11, "Implementation starts now"
  ([#676, comment 6109559003](https://github.com/xperiaroco2/prime-game/issues/676#issuecomment-6109559003)), so
  "nothing here is built" above is history. What is built is read from the issues, not from a list here: the plan issue #676 and the issues named in §10.
- **Date:** 2026-10-10
- **Deciders:** the engineer (the decided rules; his answers to KD1 to KD9, KE1 and KE5, and the House only, in PR
  #754's comment 6097876326; KD10 (A) and KE1 (b) in its comment 6100602989; KD11 in its comment 6108669765; KD12
  (a) and KD13 (a) in its comment 6109457234; KD14 (a) and KD15 (a) in its comment 6110171062); designed by the
  agent of #728 in the game-design manager session's workflow (#676)
- **Builds on:** [vision revision 1](2026-10-01-vision-revision-1.md) (Life: knockdown, death, respawn; Voice;
  Hidden information), [the M4 client design](2026-10-01-m4-first-person-client.md) (its §3, the render checklist,
  items 1, 3 and 5), [the M5 voice design](2026-10-02-m5-voice-integrated-with-the-rules.md) (E40, the ears; E41, the
  cutoff), [the throwing design](2026-10-09-throwing-held-items.md) (its TE1, whose option (b), `server/`'s physics,
  is this design's KE1 (b)), the car repair design (#688, PR #709: the lift's drop kills the living and the
  knocked-down, `LifeRules.kill`, a car only the clients collide with) and [the crouch](2026-10-10-crouch.md) (#727,
  PR #752: its crouched capsule, which the host's body takes under KD11, and its KD4 (a) and controller step 7, by
  which a raised player gets up crouched and stands once there is room).
- **Revises, once built:** vision revision 1's crawl (the Downed row's "crawls" and "crawl and give up", the crawl
  speed, and its "Needs the engineer" 8, the hold while raised), and ARCHITECTURE §7.1.7 and §7.1.8. A dated note in
  vision revision 1 points here.
- **Words:** "knocked down" is the players' word and this ADR's; `DOWNED` stays the code's name for it (KE11).
- **Numbering:** KD1 to KD15 (the engineer's, all answered), KE1 to KE15 (technical, KE1 and KE5 the engineer's;
  KE2 withdrawn by KD10 (A)), and the proposed issues 728a, 728b, 728d, 728e and 728f (728c withdrawn by
  KD10 (A); 728f builds KD12 (a)).

## Context

**What exists** (vision revision 1; built in M4-2 to M4-4 and M4-9, #145). At 0 health `LifeRules.knock_down` stops
the player's channels, lays it on the floor below its last accepted position with a new epoch and a `Correction`,
and tells everyone (`KnockedDown`, which names no attacker). It stays knocked down for `PlayerRules.knockdown_s`
(10 s, a placeholder), and `LifeTicks` lets it die then; any living player raises it by holding E for 3 s (`Raise`,
a channel that pauses the timer); `GiveUp` kills it at once; a death drops both slots at the body, and the respawn
follows 30 s later. A knocked-down player **crawls** at `PlayerRules.crawl_speed_mps` (1 m/s): its `MoveClaim`s get
the crawl's bounds (ARCHITECTURE §7.1.7), and while raised it is held in place (`MovementRule.held_against`, the
engineer's answer 8 on PR #133). Its client crawls on the `downed` physics layer under a lying mesh, the others draw
a lying capsule (`RemotePlayerBody`), and its camera is `DownedCamera`, a `SpringArm3D` above the body that never
rises above the standing eye height, with `SightHider` hiding what the body's eye could not see (the M4 ADR's §3,
item 3).

**Voice already mutes the knocked-down.** Since M4-1 (#137) `VoiceRule.speakers_of` drops every speaker who is not
living before any mode's rule runs, so nobody hears a knocked-down player under any voice rule, and a knocked-down
listener hears the living within the radius from where it lies. Its client sends no voice
(`VoiceSender.may_speak_of` asks for a living own life). The HUD is not built yet: the round HUD's mic (#489) and
#497's down screen, both open M6.2 issues, are to show the mic off while downed; main's client has no mic indicator
and no `downed.title`.

**Bodies are the host's.** Where a knocked-down player lies is its last accepted position; where a dead one lies is
`MatchState.bodies`. The raise's reach and sight, the voice "from where it lies", a respawn marker's free radius and
the car's footprint (#688) all read that point. Nobody receives their own avatar in the snapshot: it moves
client-side, and `Correction` settles disagreement (ARCHITECTURE §5).

**What the engineer decided** (#728; comment 6095620279, answer A): the knockdown stays as it is today (0 health →
knocked down, another player can raise it, else it dies after a while), with these changes only. There is no separate
"downed/wounded" state. The knocked-down player **cannot move** and **cannot talk** (it hears, but cannot speak).
There is no animation but **a rigid body**: "a hit can send the body flying (for example a punch), and a body knocked
down on the sloped roof can roll off the roof". His answers to this design (PR #754, comment 6097876326) take every
recommendation below, and add where it plays: "the launch and the slide play on **the House only**. The flat greybox
keeps the knockdown without launch or slide (the standing rule: no new mechanic on the greybox) ... The rework itself
(still, mute, ragdoll) applies wherever today's knockdown does." On KD10 (PR #754, comment 6100602989) he said "this
just needs a rigid body with normal physics", read back as a real physics body run by the host's engine, and chose it.

**The House has no sloped roof.** Every collider under `levels/house/` is an untilted box (263 `BoxShape3D`s, every
transform's basis the identity, checked on 2026-10-10): the roof (`levels/house/rooms/roof.tscn`) is four flat 0.2 m
floors inside a 0.8 m parapet, behind a door locked in the MVP ([the House's](../design/house-map.md) decision 11),
and no other floor tilts. So what a body can roll or fall off on the House is its stairs, its ledges, the balcony and
the roof's edge. A slide rule for steep floors (KD3 (a)) would have played nowhere there; the review found this and
asked KD10, and the engineer's answer drops the rule: the host's physics rolls or slides a body off whatever the
level's colliders give it.

**What that asks of the engine.** Mute is built. Still is a removal: the crawl. The ragdoll is new looks. The motion
is the hard part: a body that flies or rolls moves the point that the raise, the voice and the car read. A ragdoll
left to each client's physics would roll off the roof on one screen and stay on it on another, and the host, which
keeps no ragdoll, would keep the body where it fell: a teammate standing over the body in the yard could not raise
it, because for the host it still lies on the roof. So the body's place stays the host's: the host's physics moves
it (KD10 (A), KE1 (b)), `core/` keeps where it is from the host's reports, and the ragdoll is only how each client
draws a body at that place.

## Decision

### 1. The rules as the engine runs them

| # | Rule | Engine part | Today | What changes |
|---|---|---|---|---|
| 1 | At 0 health a living player is knocked down where it stands (decided: as today) | `LifeRules.damage`, then `knock_down` | exists | the blow may launch the body (§4; KD1, KD2) |
| 2 | Another living player raises it: E held for 3 s, within reach and in sight; the timer pauses (as today) | `RaiseDowned`, a channel; `TargetDowned` | exists | a body still moving cannot be raised: `TargetDowned` rejects `moving` (KD4). The hold of answer 8 goes: there is nothing left to hold |
| 3 | Else it dies when its knockdown time runs out, or when it gives up (as today) | `LifeTicks`; `Die` | exists | a death during the motion ends it (KD8) |
| 4 | It cannot move | `MovementRule`; the client's `PlayerController` | the crawl | its claims move nothing: the host takes their facing only (KE4); the crawl, its slack and `crawl_speed_mps` go |
| 5 | It cannot talk, and it hears | `VoiceRule.speakers_of`; `VoiceSender.may_speak_of`; the HUD's mic (#489, #497) | built, but the HUD (#489, #497) is open and has no mic yet | nothing (KE10); KD5 reads "hears" |
| 6 | Its body falls as a ragdoll, with no animation | the client's views of knocked-down avatars and bodies | a lying capsule | a ragdoll held to the host's point (KE7) |
| 7 | A hit can send the body flying, on the House only | `Strike`, then `damage`, then `knock_down(launch)`; the host's body (`server/`, KE13); `PlayerRules.motion_maps` | none | §4; the greybox launches nothing (KE12) |
| 8 | A body rolls or slides off a slope, a roof or stairs by itself, on the House only | the host's physics (`server/`, KD10 (A)), reported to `core/` (KE14) | none | §4: no slide rule of its own; the greybox moves no body (KE12) |
| 9 | The lift's drop kills the living and the knocked-down under the car (RD7) | #688's drop, `LifeRules.kill` (PR #709, its RE6) | designed in #688 | it reads the body's point at the drop's tick, moving or not (§7) |

### 2. The engineer's questions (KD), answered

Every "Decided" is the engineer's answer of 2026-10-10
([PR #754, comment 6097876326](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6097876326)): each
recommendation. By the same answer the launch (KD1, KD2) plays on the House only (KE12). KD10 came up after his
answers, in the review of that update; he answered it the same day
([PR #754, comment 6100602989](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6100602989)) with (A),
which supersedes KD3 (a) and changes KE1 to (b). KD11 came up in the review of that update; he answered it on
2026-10-11 ([PR #754, comment 6108669765](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6108669765))
for its first scenario, with none of its options as written. Its second scenario, which his answer leaves open, is
KD12. KD13 reads his answer back: whether the host's capsule may turn. He answered both on 2026-10-11 with (a)
([PR #754, comment 6109457234](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6109457234)).
KD14 and KD15 came up in the review of that update: two cases those answers leave open, read back to him. He
answered both on 2026-10-11 with (a)
([PR #754, comment 6110171062](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6110171062)).

| Item | Question | Options | Recommendation, and the failure it prevents | Decided |
|---|---|---|---|---|
| **KD1** | Which hits send a body flying (two readings of "a hit can send the body flying, for example a punch") | (a) only the blow that knocks the player down launches its body; strikes skip a knocked-down body afterwards, as today; (b) as (a), and a later hit on a knocked-down body launches it again, with no damage | **(a)**. (b) lets a dissident keep a body away from its raisers, one swing per cooldown (a raise stops when its body moves, KD4), or knock a package carrier's body off a ledge at will, and it brings back hits on a lying body, which vision revision 1 ruled out ("cannot be hit"). (b) can come later as a flag on a weapon's strike | **(a), the engineer**: only the blow that knocks a player down launches its body |
| **KD2** | The launch: which weapon launches a body, which way, how hard | (a) every strike has a launch in its data, a speed away from the attacker and one upwards, 0 launching nothing; the knife's numbers come with KD9; (b) the knife launches nothing (the body drops where it stands, as today) until a weapon made for it exists: the game has no punch; (c) as (a), in a random direction | **(a)**: the knife is the only weapon, so (b) shows the launch to nobody until a new item. A body flying away from the blow shows which side the blow came from to every present peer, the victim, the dead and players across the map, whatever their sight: the moving position and the body's velocity are in every snapshot, as every position is public; no event names anyone, and most victims saw the swing. It is an accepted hint, as the knockdown itself confirms the hit (vision revision 1). (c) hides it, but a body flying towards its attacker reads as a bug | **(a), the engineer**: every strike has a launch, the knife's too; on the House only (KE12) |
| **KD3** | Which floors make a body roll | (a) a floor steeper than an angle (data) makes a resting body slide downhill at a speed (data) until a gentler floor, a wall, or an edge, off which it falls and lands again; stairs do not (their treads are flat); (b) only surfaces a level marks (a group on the collider) make a body slide; (c) no slide: a body rests where it lands | **(a)**: one rule for every map, read from the floor's own slope, with no marking. (b) is the fallback if (a) catches a slope the levels did not mean (a steep driveway); (c) drops half of the example | **(a), the engineer; superseded by KD10 (A)**: no slide rule. The host's physics rolls or slides a body off any slope, roof or stairs by itself |
| **KD4** | Raising a body that still moves (flying, rolling or sliding) | (a) refused until it rests: `TargetDowned` rejects `moving`, and a raise stops if its body starts to move (that happens only under KD1 (b)); (b) a raise catches a moving body and stops it | **(a)**: a flight lasts about a second and a roll as long as the stairs, and a raise needs a body that stays within reach. (b) adds a rule for what a caught body does on a slope or in the air | **(a), the engineer**: a moving body cannot be raised (`moving`) |
| **KD5** | "Hears, but cannot speak": whom a knocked-down player hears | (a) as today: the living within the voice radius, from where its body is (which now moves with it); (b) every living player, at any distance | **(a)**: nothing changes in `core/` or in the client's cutoff (E41). (b) makes a knockdown a way to overhear the whole map: an information gain from being hit | **(a), the engineer**: the living within the radius, as today |
| **KD6** | What a knocked-down player sees and does | (a) today's camera above the body (the arm and its mouse look, the render checklist's item 3), following the body through its motion; it may give up and open the task screen and the Esc menu, nothing else; (b) first person from the ragdoll's head; (c) a fixed camera with no look | **(a)**: built and tested, and the player watches its own ragdoll. (b) tumbles with physics that differ on each screen, and its eye can pass through a wall the host knows nothing of. (c) leaves ten seconds with nothing to do | **(a), the engineer**: the camera as today, above the body, following it |
| **KD7** | How a dead body and a revive look | (a) at the death the ragdoll keeps its pose, greyed and with today's dark cross, until the respawn removes it; a revived player stands up at once, with no clip; (b) the dead switch to today's body capsule; (c) as (a), plus a get-up clip from #522's set, blended from the ragdoll's pose | **(a)**: no pop at the death, and a dead body still reads as dead at a glance (GDD §14). (c) needs a clip and a blend that #522 does not plan; it can replace the pop-up later | **(a), the engineer**: a grey ragdoll with the cross; a raised player stands up |
| **KD8** | A death during the motion (the time running out, a give-up, the car's drop) | (a) the motion ends: the body lies on the floor below its point at that tick, and both slots drop there, as a death does today; (b) the body moves on to where its motion ends, and its items drop below where it died | **(a)**: a body and its items stay together, and the dead body never becomes a second moving thing. Such a death is rare (a flight lasts about a second; a give-up takes a 1 s hold). Its cost: a body that stops short on a roof | **(a), the engineer**: the motion ends; the body and its items rest where it stopped |
| **KD9** | The numbers: each strike's launch speeds (the knife's), the body's gravity, the slide's angle and speed, the longest motion | (a) the engineer gives them; (b) the agents pick placeholders to taste, "not a decision", as he chose for the car (RD2) | **(b)**, so that no build waits for them. Each number gets bounds that refuse a forgotten value where 0 is not a valid one, as `PlayerRules` does (its class defaults are 0 on purpose); a launch of 0 is valid and launches nothing | **(b), the engineer**: the agents set placeholders marked "not a decision". Under KD10 (A) they are the launch speeds, the rest's speed and time, and the longest motion (KE15); the gravity, mass, friction and bounce are the physics engine's ("normal physics"), and the slide's numbers go |
| **KD10** | The slide on the House, which has no floor to slide on (Context: every collider under `levels/house/` is an untilted box, and the roof is flat, behind a locked door). His "a body knocked down on the sloped roof can roll off the roof" and "the House only" assume a slope the House does not have | (a) 728c waits until a level has a floor steeper than the slide angle, laid by hand by the engineer or the designer (a scene change, theirs), and is built then with an integration test on that level; 728e launches only; (b) 728c is built now, checked on a fixture level only: on the House it slides nothing until a slope exists; 728e launches only; (c) the engineer or the designer lays a sloped roof or ramp on the House (the content area), and 728c and 728e slide there as first planned | **(a)**: (b) ships code and a `WorldQuery` answer that no map exercises, so a break in it stays unseen until the first slope arrives, and its only tests run against a fixture nobody plays. (c) changes the House's layout for a body that would slide on a roof locked in the MVP, his call on his map | **(A), the engineer** ([PR #754, comment 6100602989](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6100602989)), none of (a) to (c): the body is a real rigid body simulated by the host's physics engine (`server/`); a blow launches it, and it rolls or slides off any slope, roof or stairs by itself. No slide rule: 728c goes, KD3 (a) and KE2 with it, and KE1 becomes (b). The launch stays on the House only |
| **KD11** | Where a body may come to rest (raised by the review of the KD10 (A) update). The host's capsule stops wherever the level's colliders hold it: under a table, wedged behind furniture, on a railing, where no standing player fits; or on a top no player can walk to, the locked roof. A raise there stands its player inside the table (KE6). And a dissident chooses the launch's direction by where it stands (KE9), so it can knock a package carrier towards the roof's edge: nobody can reach the body to raise it, it dies when its time runs out, and the package drops there (KD8) for the rest of the match, which can block the crew's delivery | (a) as the engineer's TD5 (a) for a thrown item (#646: "an item may rest wherever the flight ends, with a level convention"): wherever the physics holds it, and the levels' convention covers bodies too (every surface a launch can reach is within a raise's reach of a spot where a player can stand), checked on the House by 728e's tests beside #646's; a revive where a standing player does not fit stands it there all the same (crouched by #727's rule where that fits; else the client's solver pushes it out); (b) as (a), and the rest counts only where a standing player fits: `core/` asks a new logged `WorldQuery` answer (the mode's standing capsule at the rest point, clear of the world), and where it does not fit the body rests at the fallback, the floor below where it was knocked down, on every screen (the ragdolls snap there, KE7); (c) wherever the physics holds it, with no convention and no fit: a body out of reach dies there with its items | **(b)**: the reach is his own TD5 (a) answer, applied to bodies, so a package carried by a launch stays where a player can pick it up, and a raised player always stands where a player fits. Its cost: a body that rolled under a table snaps back to where it fell, and one more `WorldQuery` answer. (a) leaves a raised player inside furniture to the client's solver, which can push it through the level. (c) lets a launch hide a package for the match | **None of (a) to (c), the engineer** ([PR #754, comment 6108669765](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6108669765)), on scenario 1: "the body must have the collider of a crouching player, so wherever it gets up, it must be crouched". The knocked-down body's collision shape in the host's physics is the crouching player's collider, so a body comes to rest only where a crouching player fits; a raised player gets up crouched at the rest point and stands up by the crouch's rules once there is room (the [crouch ADR](2026-10-10-crouch.md)'s KD4 (a) and its controller's step 7, PR #752; KE6 here). No `WorldQuery` answer is added. That the host's capsule keeps that shape upright and never turns (KE13) is the agent's reading of his words, which name only the collider: read back to him as **KD13**, answered (a). Scenario 2, a body out of everyone's reach, is not settled by this answer: it is KD12, answered (a) |
| **KD12** | A body a launch carries where nobody can reach it (KD11's scenario 2, split out by the engineer's answer). A dissident chooses the launch's direction by where it stands (KE9), so it can knock a package carrier towards the locked roof's edge: KD11's answer rests the body only where a crouching player fits, but nobody can get there to raise it, it dies when its time runs out, and the package drops there (KD8) for the rest of the match, which can block the crew's delivery | (a) the engineer's TD5 (a) reach convention for a thrown item (#646), applied to bodies: the levels keep every surface a launch can reach within a raise's reach of a spot where a crouching player can stand (#646's line in `levels/CLAUDE.md` names launched bodies beside thrown items), and 728e's tests check it on the House beside #646's roof check; no rule in `core/`; (b) a body that comes to rest where nobody can reach it is moved back to where it was knocked down (the fallback, the floor below its last accepted position, where its player stood, so KD11's fit holds there): `core/` learns "nobody can reach" from a mark the levels put on such places, as the throwing design's TD5 (b) marks "no rest" volumes for an item, and the ragdolls snap to the fallback on every screen (KE7); (c) no rule: a body out of reach dies there with its items | **(a)**: his own TD5 (a) answer for an item, so one convention covers what a throw and a launch can reach, at no cost in code, and a House whose launch reaches the locked roof fails 728e's test before any player meets it. (b) needs a marker kind and its rule that every level keeps up to date, and a body snaps back across the room on every screen. (c) lets a launch hide a package for the match | **(a), the engineer** ([PR #754, comment 6109457234](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6109457234)): the levels are built so a launch cannot carry a body where no player can reach it, tables and the roof included: every surface a launch can reach lies within a raise's reach of a spot a player can walk to (a floor players reach from the spawn, never a furniture top or the locked roof; 728f names them), crouched there if it must (#646's TD5 (a) reach convention applied to bodies), checked on the House by tests; no rule in `core/`. His words "make tables have colliders so nothing can be thrown under them" are read back as KD14, answered (a): tables keep the space under them. 728f builds the convention line in `levels/CLAUDE.md` and the House's check (beside #646's roof check, in 728e's House tests); 728a, 728b, 728d and 728e do not wait on it |
| **KD13** | The read-back of KD11: does the host's capsule turn? His words name the crouching player's collider, not its pose. A crouched capsule free to turn lies down and rolls under a table a crouching player does not fit under, which his answer closes, so the agent reads it as upright and never turning (`BODY_MODE_RIGID_LINEAR`, KE13). What that costs in play: the host's body slides and falls but never rolls, against his KD10 (A) "rolls or slides"; it slides off only a slope steeper than its friction angle (about 45° at the engine's default friction of 1.0), so a body knocked down with no launch on a gentler ramp stays put; only each screen's ragdoll rolls (KE7) | (a) the lock, with the engine's materials (KE13 as written); (b) the lock, plus a body friction (`PhysicsServer3D.body_set_param` with `BODY_PARAM_FRICTION`), a `PlayerRules` number with bounds, a placeholder marked "not a decision" (KD9 (b)), so a body slides off gentler slopes; (c) a capsule free to turn (`BODY_MODE_RIGID`): it rolls, but lies down twice its radius tall and rests under a table a crouching player does not fit under | **(a)**: no House floor slopes (KD10's Context: untilted boxes and a flat roof), so on the House the lock costs nothing a player meets, and (b)'s number would change nothing until a level has a slope; it can be added then. (c) reopens KD11's scenario 1 | **(a), the engineer** ([PR #754, comment 6109457234](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6109457234)): the host's capsule is the crouching player's collider, stays upright and never turns (`BODY_MODE_RIGID_LINEAR`, KE13 as written), so it slides and falls but never rolls, and each screen's ragdoll rolls (KE7). Pushing a body out if it stands up inside a collider (his idea) is not needed for a collider in the host's world, such as a table: a crouched-size body cannot rest inside one in the first place (KD11). The lowered car is a collider only the clients have, where it can: KD15, answered (a), RE8's accepted quirk. 728b builds the lock |
| **KD14** | His words while answering KD12: "make tables have colliders so nothing can be thrown under them". The read-back he confirmed is the general reach convention (KD12 (a)), which lets a body rest under a table a crouching player fits under while a raise reaches it; his words close the space under every table. Raised by the review of the KD12 update: left as context, they would quietly decide a level rule, and §8's table row and 728e's playtest list say the opposite of them | (a) the confirmed read-back as written: a table is a surface like any other; a body (or a thrown item) may rest under a table a crouching player fits under while a raise reaches it from a spot a player can walk to, and the House's tables stay as built; (b) his words as a level rule: every table's collider closes the space under it down to the floor, so nothing thrown or launched rests under one, and no player crouches under one either; the convention line in `levels/CLAUDE.md` says so, 728f's House check asserts that no launch rests a body under a table, and 728f stops and reports the tables whose collider leaves the space open (a scene change, the humans'); §8's table row and 728e's playtest item change with it | **(b)**: they are his own words, and they leave no raise under furniture at all: a raised player never gets up beside a table leg, and a package never lies where a raiser must crouch to see it. Its cost: a collider change on each House table that leaves the space open (the humans' scene work), and a crouching player can no longer hide under a table. (a) keeps the House's tables as built and keeps that hiding place | **(a), the engineer** ([PR #754, comment 6110171062](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6110171062)): the confirmed read-back stands as is; tables keep the space under them. A body may rest under a table a crouching player fits under, as long as a raise can reach it (KD11, KD12 (a)). No level rule closes tables: the House's tables stay as built, and 728f's check holds a rest point under a table to the same reach as any other |
| **KD15** | A body launched into the lowered car (#688). The car is an `AnimatableBody3D` on a client-only layer (the car repair ADR's RE8 (a)): the host's world never holds it, lowered or raised. The host's capsule collides with the world only (KE13), so a launch at the lowered car carries the body into its footprint on the host, where it rests on the floor; every ragdoll collides with the world only (KE7), so each screen draws it inside the car. A raise reaches it (the host's sight passes through the car, RE8), and KE6 stands the raised player crouched there, inside the car's collider on its own screen, which its client's solver pushes out: KD11's failure, which his push-out idea covers, and which KD13's "not needed" does not cover | (a) RE8's accepted quirk, as the car repair ADR's RD6 (a) accepts it for a player left under the lowered car: the lowered car pushes the raised player out on its client, a push the host's world does not see, and the host checks the claims that follow as any claims; no new rule; (b) his push-out, for client-only colliders only: at the revive's placement the raised client's controller moves its crouched capsule out of the `movers` layer (the car's) to the nearest spot clear of it on the floor, before its first claim, which the host checks as any claim; a client rule in `client/`, no `core/` change; (c) the car's footprint as no rest place: a body that `core/` rests inside the lowered car's footprint box (RE7's, which `core/` already knows) rests instead at the fallback, the floor below where it was knocked down, on every screen (the ragdolls snap there, KE7) | **(a)**: it is the same geometry as RD6 (a)'s player left under the lowered car (a crouched capsule on the floor under the car's body), which he accepted (a premise the review of his answer corrected: see the Decided column), so no rule is added for a case only a launch at the car's side reaches. Its cost: the client's push can carry the raised player into a nearby wall on its screen, which the host's movement check then corrects. (b) costs a client rule that `ScenarioBot` cannot see. (c) snaps a body across the room on every screen | **(a), the engineer** ([PR #754, comment 6110171062](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6110171062)): RE8's accepted quirk: a body launched into the lowered car and raised there is pushed out by the raised player's own client, as the car repair ADR's RD6 (a) already accepts; the host checks the claims that follow as any claims. Nothing new in code. The review of his answer corrected its premise: RE8 accepts only a push of at most the capsule's 0.4 m, sideways from the footprint box's edge (RD6 (a) kills every player whose feet lie inside the box), and R7's test records whether one `Correction` follows. Here the raised player's feet lie inside the box, so the push can be deeper (up to about half the car's width) or upward onto the car, and the host's horizontal bound (ARCHITECTURE §7.1.5) may refuse it and correct the player back into the car, again and again. (a) stands, resting on 728e's test (§10): if more than one `Correction` follows, or the push lifts the player onto the car, 728e stops and puts KD15 back to the engineer with (b), (c) and that cost. **Then (b2), the engineer** ([#976, comment 6162445237](https://github.com/xperiaroco2/prime-game/issues/976#issuecomment-6162445237)): 728e's test measured (a)'s push down into the floor (about 0.56 m) and 3 `Correction`s on the way out, and (b) as worded cannot pass (`core/movement/movement_rule.gd` lets the first claim after a placement travel at most 4.5 / 20 + 0.05 = 0.275 m, and leaving the car takes at least 1.4 m). So after the revive's placement the raised player's own client walks its capsule out of `movers` to the nearest clear floor over its first claims, at no more than walk speed, ignoring `movers` until clear; client-only, the host's check unchanged; the search's reach is a placeholder (`PlayerController.MOVER_EXIT_REACH_M`, 3 m, not a decision). Built in #976: the stand-in test measures no sink and no `Correction` |

### 3. The technical choices (KE)

| Item | Choice | Options | Recommendation, and the failure it prevents |
|---|---|---|---|
| **KE1** (the engineer's: **(b)**, PR #754 comment 6100602989, replacing his (a) of comment 6097876326) | Where the body's motion runs | (a) in `core/`: the throw's arc swept through `WorldQuery.sweep` each core tick, a stop and drop, and a slide down a steep floor; (b) `server/` simulates a rigid body in the host's level space and reports where it is; (c) the knocked-down player's own client simulates its ragdoll and claims where its body is, as it claimed its crawl | **Decided (b)** (KD10 (A)); this design recommended (a) before his answer. (c) breaks invariant 1 for the rule "cannot move": a hacked client rolls its body, and the package it holds, along any slope into its place, and headless bots have no ragdoll. What (b) costs, as the throwing design's TE1 (b) lists it, and how this design meets each: the same commands can rest a body in two places on two runs (Godot 4.7.2 steps the host's spaces by physics frames, with no call that steps one space, and drops frames under load, ARCHITECTURE §4.5.2), so `core/` takes the host's reports as logged commands (KE14): a replay reproduces every rest and runs no physics, `core/` stays deterministic in what it is given (invariant 3: no physics in `core/`), and the motion is checked by host-side integration tests that assert where a body may rest, never an exact point (§9); the spaces hold no players, so the body passes through them, as the crawling downed did; `core/` would know no position in flight, so `server/` reports one each core tick (KE14); and "when is it at rest" would become a game rule in `server/`, so `core/` decides it from the reports (KE15) |
| **KE2** (withdrawn by KD10 (A)) | The slope | Was: a new `WorldQuery` answer, `floor_normal_below(p)`, for KD3 (a)'s slide | Withdrawn: the host's physics reads every slope from the level's colliders itself, so `core/` asks for none and `WorldQuery` gains no answer |
| **KE3** | Where the motion's state lives in `core/` | `PlayerState.motion`, a `BodyMotion` (`RefCounted`, `core/life/`): the epoch of the knockdown that started it, the fallback rest, the tick of its last report faster than the rest speed (KE15) and its own tick count; null at rest. `core/` holds no physics: the point is `PlayerState.position` and the velocity `PlayerState.velocity`, set from the reports (KE14). `LifeTicks` counts the longest motion, in peer-id order; `die`, `leave`, `revive` and `ResetMatch` clear the motion, each emitting `StopBody` | Prevents: a new tick system every mode must list (the mode check already demands `LifeTicks` where a rule can knock down, ARCHITECTURE §9.1), and a second place for the body's point that a rule could read stale |
| **KE4** | What a knocked-down player's `MoveClaim` does | The host takes its facing only (unit, as for every claim) and ignores its position, velocity, jumps, sprint and crouch: no movement check, no `Correction`, no stamina spent (it regenerates as today). A taken claim still advances the claim bookkeeping as `_accept` does today (`player.claim_tick`, and the credit it covers spent), so a claim whose tick does not rise is dropped as today, an old twin (`MoveClaimReliable`, §7.1.15) or a reordered claim sets no older facing, the past-credit drop below can fire, and `SelfStatus`'s `claim_tick` names the last claim taken. Today a malformed claim, a negative client tick and a claim past its credit each get a `Correction` (`MovementRule.apply`); from a knocked-down sender each is dropped instead, with no `Correction` and its facing not taken, since the host takes no place from it to correct; a claim of an old epoch is dropped as stale, as today. `ChaosOracle`'s class 5 (ARCHITECTURE §4.6.5) is rewritten from this rule, not from the docs: no `Correction` to a knocked-down peer | The facing still matters: a dead player watching a knocked-down target looks through that target's look (vision revision 1, V9: "a downed player's third person"). Prevents: a client that still crawls (an old build, a hostile peer) moving its body, and a `Correction` storm while the host moves a body its client does not predict |
| **KE5** (the engineer's: **(a)**, PR #754 comment 6097876326) | How a knocked-down client learns where its own body is | Its snapshot holds its own avatar while it is knocked down (`Snapshots.for_peer` skips the viewer's avatar unless it is `DOWNED`); the client draws its body and places its camera and ears from it, on the interpolated timeline of the other avatars | Prevents: a `Correction` on every tick of a motion (reliable, at 20 Hz), and a client simulating a body that only the host's physics moves. Nothing hidden: a player's own place. The wire bounds a snapshot's avatars by `WireSchema.MAX_AVATARS`, today `MAX_PLAYERS - 1` (15, "a snapshot never holds the viewer's own avatar"), and the codec refuses a map past it on both ends: in a full 16-player match a knocked-down player's snapshot would be refused for the whole knockdown. So `MAX_AVATARS` becomes `MAX_PLAYERS` (16) with its comment, and the cap holds at the declared maximum: 16 avatars take about 725 bytes of the 1024 (45 bytes each with its key; today 15 take 680, pinned in `wire_schema_test.gd`). It changes ARCHITECTURE §5's "nobody gets their own avatar" and §4.3.5's `Snapshot` row, and the protocol number goes up with it: an older client would draw itself as a stranger |
| **KE6** | The revive | `revive` sends a `Correction` (a new epoch, the body's rest point), as a respawn does. There the raised client gets up crouched and stands only once the standing capsule fits (KD11, the engineer's): the crouch's controller already does so at every life change into the living (the [crouch ADR](2026-10-10-crouch.md)'s step 7: the crouched capsule first, then its stand-up test, KD4 (a)), so this design adds no rule to it. The host's `PlayerState.crouched`, false at a placement (the crouch's 727a), follows the raised player's first claim, as after a revive under the raised car. Until that claim the host judges the raised player standing (the standing eye for `Items.eye_of`, the standing capsule for `Strike`), under the table its body rested under too: accepted, as the crouch accepts it after every placement, for the few ticks before an honest client's first claim | Today it sends none, because a raised client claimed where it lay. A knocked-down client now claims no place, so without one it would stand up where its last walking claim was. The revive becomes a placement: `ScenarioBot`, which fails any `Correction` outside one, expects it, and the honest-bot check stays as strict (728a). The crouched get-up prevents a raised player standing up inside the table its body rested under, which the solver then pushes out through the level |
| **KE7** | The ragdoll | Looks only, on each client: every knocked-down avatar (the own included) and every body is a ragdoll whose root is held to the host's point by a spring each physics step (`_integrate_forces` of a `PhysicalBone3D` or a `RigidBody3D`), and moved there at once when farther than a snap distance (a client constant). Its parts are on the `downed` layer and collide with the world layer only: never with players, another ragdoll or a client-only object (#688's car). On today's placeholder avatar (a capsule, on every map) it is one `RigidBody3D` capsule; with #522's character, the skeleton's `PhysicalBone3D`s under a `PhysicalBoneSimulator3D`. It starts from the standing pose with the avatar's velocity. Nothing reads it: the raise's reach, the camera, the ears and `SightHider` use the host's point. It makes no sound; a later impact or landing sound plays only within the hearing range around the listener's ears (the M4 ADR's §3, item 10, E33 as amended), so a body thrown or rolling off a roof is not heard through walls on every client | Prevents: two screens disagreeing on where a body is by more than its limbs, and a pose that feeds back into what the client shows (the render checklist's item 1). The host's body (KE13) is the truth; the ragdoll only follows it. Each Godot name is checked in 4.7.2's API |
| **KE8** | The camera and the ears of a moving body | `DownedCamera`'s pivot, for its own knocked-down player and for a spectator watching a knocked-down target alike (ARCHITECTURE §4.7.9), rises from the body's point by the standing eye height, but never higher than the standing eye height above the floor below the point (a ray down the client's own level), so a body in flight or falling off a ledge lifts it no higher than a player standing under the body would see; and it stops 0.1 m (a placeholder) below the first world hit straight above it; the arm and `SightHider` work from it as today. The ears stay at the body's lying head height above the point (today's "the own body's head") | Prevents: a body flying up against a ceiling, or lying under a low one, lifting the pivot into the room above (the render checklist's item 3: never through the level), and a body in mid-air showing its player, or a dead spectator, over a fence or onto the locked roof (item 3: never over cover more than standing at the body). Today a body lies only where a player stood, so the eye height always fitted |
| **KE9** | The launch's direction | Horizontal, from the attacker's feet towards the victim's (both last accepted positions); when they coincide, the horizontal part of the facing the strike aims with (the Use's own `facing`, else the last accepted claim's, as `Strike` picks it for `Swung`); when that has none, straight up only | Prevents: the direction resting on a claimed facing (harmless, but a glancing swing would launch a body sideways) |
| **KE10** | Voice and the mic | No change: `VoiceRule.speakers_of` drops every speaker who is not living, `VoiceSender.may_speak_of` sends nothing unless the own life is living, and #489's mic, once built, shows off while downed. The tests that pin the first two stay (ARCHITECTURE §6.3) | Prevents: a second mute path (a knocked-down check inside a voice rule) that a mode's data could route around |
| **KE11** | The code's name | `PlayerState.Life.DOWNED`, the wire's `downed` and the tests keep their names; players read "knocked down" ("You're down", #497's planned `downed.title`) | The engineer's "no downed state" is about the game (no wounded state that crawls), not an identifier. A rename touches about 160 files and the wire's flag for no change in behaviour |
| **KE12** | How the launch and the host's body play on the House alone (the engineer's answer: not on the flat greybox), while the base mode keeps both maps and the knife is one item on both | (a) one list in the mode's data: `PlayerRules.motion_maps`, the paths of the mode's maps on which a knockdown launches a body and the host simulates it, empty (the class default) for every map, the shape of `TaskType.maps` (the Generator ADR's GE15 (a), its issue G8). `knock_down` compares the match's map (`MatchState.map`) with it: on a map it does not list a knockdown takes no launch, whatever the strike's numbers, and starts no host body, so it is today's knockdown (§4, step 2). The mode check refuses a listed path that is not one of the mode's maps, as G8's does, and a map on which a body moves but the crouch does not play (`PlayerRules.crouch_maps`, the crouch ADR's KE10, read the same way: an empty `motion_maps`, every map, beside a `crouch_maps` that lists some, or a listed map `crouch_maps` leaves out). The base mode lists the House alone from 728b on, where the field arrives, before any launch has a number (728e); (b) a mode of its own for the House; (c) the numbers in the House's scene (a node or metadata the host reads with the markers); (d) a list on each `Strike`; (e) as (a), with an empty list meaning no map | **(a)**: the data says where bodies move, read the same way as where a task type plays, so the next House-only mechanic follows one pattern. It prevents the knife's launch numbers, which live in `content/items/knife.tres` and travel with the knife to every map, moving bodies on the greybox: the base mode's first map, where every scenario, the chaos run and the perf run play. (b) fails as GE15 (d) does: the client loads one mode (`Game.MODE_PATH`), so a second needs a mode choice in the lobby and splits the settings a host knows. (c) puts a game rule in a level scene, which the humans lay out by hand, outside the content API and the mode check's bounds. (d) puts an answer about the map on every weapon: a new weapon without its list would launch on the greybox, and the host's body, which every knockdown on a listed map starts, would follow another list than the launch. (e) keeps a forgotten list from reaching the greybox, but unlike `TaskType.maps`, and every fixture mode would have to list its map; 728e's test that the base mode on the greybox moves no body catches a forgotten list instead. The crouch check: a body rests where only a crouching player fits (KD11), and a raised player gets up crouched there only where the crouch plays, so it prevents a raised player standing up inside a table on a map without the crouch. Not dependent on G8: G8 changes the deal and the demands, this changes the life rules. **Superseded in part 2026-10-14 (#991, #989):** the crouch plays everywhere, so `crouch_maps` and the mode check's KD11 clause are gone; `motion_maps` stays as it is |
| **KE13** | The host's body (`server/`, KD10 (A), KD11) | `HostBodies` (`server/`) keeps one rigid body per moving body through `PhysicsServer3D` (`body_create`; `body_set_mode` with `BODY_MODE_RIGID_LINEAR`, a rigid body that cannot rotate; `body_add_shape` of a `capsule_shape_create` shape sized by `shape_set_data` to the crouching player's collider, `PlayerRules.capsule_radius_m` and `crouch_height_m` (the crouch's 727a), whatever the player's pose at the knockdown (KD11); `body_set_space`), in the current level's world, the `World3D` that answers `WorldQuery` (ARCHITECTURE §4.5.9). On `LaunchBody` it starts upright where its player stood, its lowest point at the origin (the player's feet, so its centre half its height above them; `body_set_state` with `BODY_STATE_TRANSFORM`), with the launch as its velocity (`BODY_STATE_LINEAR_VELOCITY`), and stays upright: it flies, slides and falls, but never tips or rolls, while each screen's ragdoll (KE7) tumbles; with a launch of 0 it rests where its player stood, unless the floor there sends it on (a stair's edge); it is on the `downed` layer with the world mask only (`body_set_collision_layer`, `body_set_collision_mask`), with continuous collision detection (`body_set_enable_continuous_collision_detection`), and moves under the engine's gravity, mass, friction and bounce. On `StopBody`, a level change or the host's end it frees the body (`free_rid`). Whether a `World3D.new()` space steps its rigid bodies as the physics frames run is unproven: 728b probes it first, as 3c probed the first query, and if it does not, `server/` sets the space active (`PhysicsServer3D.space_set_active`). Each Godot name is checked in 4.7.2's API | The crouching player's collider is the engineer's KD11; upright and never turning is the agent's reading of it, which he confirmed (KD13 (a)): the physics then holds the body only where that collider fits, so it comes to rest only where a crouching player fits, with no fit query. A capsule free to turn (`BODY_MODE_RIGID`, as this row first had, with a topple about the axis across the fall) lies down, twice its radius tall, and rolls under a table a crouching player does not fit under: the scenario KD11 closes. Read back for his KD10 (A) "rolls or slides": the host's capsule slides and falls off a ledge, the balcony or a stair's edge, and the ragdoll every screen draws rolls. Upright at its player's feet: prevents a body started lying across a wall its player stood beside, or a capsule centred on the feet starting half inside the floor, each of which the solver would push out through the wall or the floor; a crouching player's collider is no taller than its player's own, standing or crouched, so it never starts inside a low ceiling. The world mask only: prevents a body resting on a player or a client-only object (#688's car) only one side knows, since the host's space holds neither. Continuous collision: prevents a launch tunnelling through a thin floor or the parapet. The engine's own gravity and materials: "a rigid body with normal physics", and no numbers to agree on until a playtest asks |
| **KE14** | How the body's place reaches `core/` and the filtered views | In each host step that runs step 4 (ARCHITECTURE §4.5.3), `server/` puts one `BodyMoved(peer, epoch, position, velocity)` for each body it simulates at the head of that step's batch, so it is stamped with t, the tick the batch runs, and applied before every network command stamped t, those carried over from an earlier step included; step 1's catch-up ticks get no report (the host's physics did not run through the freeze either). The reports go in peer-id order, each naming the epoch its `LaunchBody` named (`HostBodies` keeps it with the body, so `server/` reads no `core/` state, and a report of a body freed after a give-up cannot pass for one of the same player's next knockdown), the capsule's lowest point (its centre lowered by half its height: it never turns, KE13) and its linear velocity (`body_get_state`). It is a command `server/` originates, as `PeerConnected` is: it goes into the command log (ARCHITECTURE §3.3), and no message type carries it, so no peer can send one. `core/` takes it only for a body in motion whose epoch it names, and only finite: it sets `PlayerState.position` and `velocity`, which every rule reads as today (the raise's reach and sight, the voice distance, a respawn marker's free radius, the car's footprint) and the snapshot carries to everyone, and through KE5 to its own player. A report that is not finite ends the motion at the fallback, with an error. A replay reads the reports from the log, runs no physics and ignores `LaunchBody` and `StopBody` | Prevents: a rule reading a point the host's physics has left; a replay that diverges because physics ran again; a peer forging a body's place; and a raise taken in the same tick against an older point than the snapshot shows |
| **KE15** | When the body rests | `core/` decides, from the reports, counting in core ticks: once the newest report is slower than the rest speed and the reports since the last faster one (or since the knockdown) span the rest time, counted only in ticks that brought this body's report, or when the motion reaches the longest motion (counted by `LifeTicks` in every tick), the motion ends. A freeze's catch-up ticks bring no report, so they never fill the rest time: a hitch just after a launch's apex, where the newest report is slow in mid-air, cannot end the motion there and rest the body on whatever lies under the apex (the locked roof, a table top), where the host's physics never carried it. The longest motion counts them, so a host whose reports stop still ends the motion. The point becomes `stand_floor_below` (a standing player's floor, the highest under the capsule's footprint, ARCHITECTURE §4.5.9) of the reported lowest point raised by `PlayerRules.capsule_radius_m`, lifted as `Items.lifted` lifts a point (logged), else the fallback with an error (§4, step 6); the velocity is zero, and `core/` emits `StopBody(peer)`. The rest speed, the rest time and the longest motion are `PlayerRules` numbers with bounds, placeholders marked "not a decision" (KD9 (b)) | Prevents: "when is a tumbling body at rest" becoming a game rule in `server/` or in the engine's sleep thresholds (project settings, outside the mode's data and its bounds), and a body rocking on an edge, or a host whose reports stop, keeping a body unraisable for its whole knockdown. `stand_floor_below`, not `floor_below`: the capsule never turns (KE13), so it can rest with its round bottom on a stair's nosing, a railing or the parapet's edge and its centre past the edge (at a 45° contact, the default friction's angle, up to r·sin 45° ≈ 0.28 m past); one ray at its lowest point would then miss the support and snap the body to the floor below, the lower tread, where a crouched capsule overlaps the riser above, or the yard under the balcony: the raised player inside the stairs or below the balcony. The five rays find the support, as they keep a player on a ledge's edge on the ledge (the movement rule's floor, ARCHITECTURE §7.1.5). They start a radius up, inside the capsule's own volume, which the world does not enter at rest: from the lowest point itself, a ray beside it would start inside the ledge it rests on and miss it. `floor_below` stays for the fallback (§4, step 2) and for an item |

### 4. The body's motion (KE1 (b), KD10 (A) and KD11; KD1, KD2, KD4 and KD8 (a), the engineer's)

The body is a rigid body in the host's physics (KD10 (A)): `server/` simulates it in the level's world, the same
`World3D` that answers `WorldQuery` (ARCHITECTURE §4.5.9), and `core/` keeps where it is: the knocked-down player's
`PlayerState.position`, the floor point under the body at rest, which it learns from `server/`'s reports (KE14) and
every rule reads as today. `core/` holds no physics (invariant 3).

**Where.** A body moves only on a map that `PlayerRules.motion_maps` lists (KE12; the base mode lists the House
alone, from 728b on). On every other map, the flat greybox included, the host simulates no body: a knockdown takes no
launch and is step 2's with no launch, today's, and the body lies still and mute, drawn as a ragdoll (KE7), as the
engineer answered ("the rework itself (still, mute, ragdoll) applies wherever today's knockdown does").

1. **The launch.** `Strike` hands `damage` the launch of its rule (KD2): `launch_mps` away from the attacker (KE9)
   and `launch_up_mps` upwards, both 0 by default. `damage` hands it on to `knock_down` only when the hit knocks the
   player down: a hit that does not pushes nothing, because the living move client-side (invariant 7). A knockdown
   by anything else (nothing else knocks down today) launches nothing, and `knock_down` drops the launch on a map
   `motion_maps` does not list (KE12).
2. **The knockdown.** On a map `motion_maps` does not list it is today's, unchanged: the body lies at `floor_below`
   of the last accepted position at once, mid-jump included, `KnockedDown` and the `Correction` name that point, and
   no motion starts. On a listed map every knockdown starts a motion, with the launch as its velocity, 0 included (a
   body knocked down at a stair's edge goes down by itself, KE13): `knock_down` asks once for the fallback
   rest, `floor_below` of the last accepted position (logged like every answer), keeps the motion (KE3), and emits
   the directive `LaunchBody(peer, epoch, origin, velocity)`, the epoch being the knockdown's (the one its `Correction`
   names and the motion keeps, KE3) and the origin the last accepted position. A directive has
   the audience *server* and reaches no peer (ARCHITECTURE §4.2). `KnockedDown(peer, position)` names the origin, and
   its `Correction` (a new epoch) still drops the walking claims in flight. Until the first report the point is the
   origin and the velocity the launch (`knock_down` sets both), so the knockdown tick's snapshot starts each ragdoll
   (KE7) moving the way the host's body starts.
3. **The host's body** (KE13). `server/` starts a rigid capsule, the crouching player's collider (KD11), upright where
   the player stood, with the launch as its velocity, colliding with the world only; it never turns (KD13 (a)).
   Each physics frame the engine moves it: it flies, lands, slides, and falls off whatever the level's colliders give
   it, a roof's edge, a ledge, the balcony or the stairs, while each screen's ragdoll tumbles (KE7). It
   passes through players, living or knocked down, and through every other body, as the crawling downed did (vision
   revision 1).
4. **The reports** (KE14). Each core tick `server/` reports the body's lowest point and velocity in `BodyMoved`;
   `core/` sets the point and the velocity, which the snapshot carries.
5. **The rest** (KE15). Once the reports stay slower than the rest speed for the rest time, the motion ends: the
   point is the standing floor under the capsule at the last reported point (`stand_floor_below`, so a body on a
   stair's nosing or a railing rests on it, not on the floor below it), the velocity zero, and `StopBody` lets `server/` free the body.
   No event: the snapshot shows the position and velocity to everyone, as for any avatar. A body at rest never moves
   again: a later blow skips it (KD1 (a)).
6. **No floor** (launched off the map's edge or into a hole): the reports fall on until the longest motion ends the
   motion; with no floor under its capsule the body rests at the fallback, and the match logs an error (a level with a
   hole), as the throwing design's TD11 (a) does for an item.
7. **The longest motion** (data): a motion still running then ends as at rest (step 5), at the standing floor under its
   capsule or at the fallback.

The snapshot's velocity is the host body's, so each client starts its ragdoll moving. The voice distance, the raise's
reach and sight, a respawn marker's free radius and the car's footprint read the point as it moves. A death ends the
motion where it is (KD8 (a): `die` takes the floor below its point, as today, and emits `StopBody`); a leave ends it,
leaving no body; at the round's end the body moves on and rests by the reports; `ResetMatch` clears it. On a map
`motion_maps` leaves out, step 2 is today's knockdown (the same event, the same `Correction`, no motion, no
`LaunchBody`, so a `Raise` on the knockdown's tick is not rejected as `moving`), and every life test of today holds
there whatever the numbers: the greybox's scenarios, chaos run and perf run see no motion. On a listed map a `Raise`
is rejected as `moving` until the body rests, at least the rest time after the knockdown.

**Determinism.** `core/` stays deterministic in what it is given: commands in (the reports among them), events out
(the directives among them). The physics is not: the same match played twice can rest a body in two places, since
the engine steps the host's spaces by physics frames, which drop under load, and 4.7.2 has no call that steps one
space. That is the cost the engineer took with KE1 (b). A replay of the command log reproduces every rest, because
the reports are in it, and runs no physics. The tests split accordingly (§9): `core/`'s handling of the reports by
unit tests with scripted reports, and the body's motion by host-side integration tests that wait real physics frames
and assert where a body may rest.

Where a body may come to rest: wherever the level's colliders hold the host's capsule, the top of the parapet, a
stair or a railing included, which a throw's arc cannot reach (an item rests at `floor_below`, the throwing design's
TD5). That capsule is a crouching player's and never turns (KD11; KE13, KD13 (a)), so a body rests only where a
crouching player fits: not under a table lower than a crouching player. A raised player gets up crouched there and
stands up by the crouch's rules once there is room (KE6). A launch never carries a body where no player can reach it
to raise it, tables and the roof included: the levels' reach convention covers bodies (KD12 (a), §2), with no rule in
`core/`, and the House's check that no throw reaches the locked roof (#646) gets a launched body beside it (728f).

### 5. Voice and the mic

- Nothing changes (KE10): the knocked-down speak to nobody under any voice rule (ARCHITECTURE §6.3), their clients
  send nothing, and the mic is to show off while knocked down and on again at the revive (#489 and #497, open: not
  built yet).
- A knocked-down player hears the living within the radius (KD5 (a)), measured by the host from the body's point and
  by the client's ears placed there (KE8), both following the motion.
- The leak test's voice checks (ARCHITECTURE §5) keep asserting that no frame of a speaker who is not living reaches
  anyone; 728a runs them unchanged.

### 6. What each player gets

| What | Who | Change |
|---|---|---|
| A knocked-down avatar: position, velocity, facing, the flag `downed`, the hand and belt items | everyone, in the snapshot (as today) | on the House the position moves after the knockdown; the velocity is the host body's (KE14) |
| The own avatar while knocked down | that player only | new (KE5) |
| `KnockedDown(peer, position)` | everyone; no attacker, no cause | the position is where the motion starts |
| `LaunchBody`, `StopBody` | `server/` only (directives) | new; no peer gets them |
| Which side the blow came from | on the House only (KE12): every present peer, the dead and the knocked-down included, whatever their sight: the moving position and the body's velocity are in every snapshot (public, as every position is; `Swung` already names the swinger to everyone) | an accepted hint (KD2); on the greybox, nothing new |
| The ragdoll's limbs | nobody: each client's own physics | new looks, never sent, never read (KE7) |
| A knocked-down player's voice | nobody | unchanged (the invariant) |
| A knocked-down player's look | everyone, as the avatar's facing; a spectator's camera follows it | unchanged (KE4 keeps it) |

No marker shows a knocked-down body through walls (the engineer's DD4 on PR #713: no through-walls markers): the
ragdoll is a thing in the world, which `SightHider` hides like the avatar it replaces.

### 7. The client, and the other designs

- **The own player, knocked down:** its controller moves nothing (today's `held` path, for the whole knockdown; no
  crawl) and its claims carry its look (KE4); its camera above the body follows its own avatar (KE5, KE8); it may
  give up (G today; F once #211 lands), open
  the task screen and the Esc menu; it sees its own ragdoll from the arm.
- **Others:** a ragdoll held to the interpolated point (KE7). The raise hint casts the same ray as today (the world and
  `downed` layers), but today's cast takes only a `RemotePlayerBody` as its target, so it maps a hit ragdoll part to
  its peer (the ragdoll's root and parts carry the peer) and measures the reach from the own feet to that peer's
  interpolated point, never to the part it hit. The item ray stops at a ragdoll as it stops at today's lying capsule.
- **The revive:** the `Correction` places the player (KE6); the ragdoll ends and the standing avatar returns (KD7 (a)).
- **The HUD** (#497, #489, both open, not built): its planned down, down-holding and raise states fit as drawn. No
  movement hint exists to remove, its planned "You're down" (`downed.title`) reads as a knockdown, and its mic is to
  show off.

| Design | Where it meets the knockdown | Here |
|---|---|---|
| The crouch (#727, PR #752) | a knocked-down player cannot crouch; the host's body is a crouching player's collider (KD11) | its claims' crouch is ignored (KE4), and a knockdown ends a crouch. The host's capsule takes the crouch's `crouch_height_m` (KE13), and bodies move only on maps where the crouch plays (KE12). A raised player gets up crouched and stands once there is room, by the crouch ADR's KD4 (a) and its controller's step 7 (KE6): under a table where its body rested, or under the raised car |
| Car repair (#688, PR #709) | the drop kills the knocked-down under the car (RD7) | by the body's point at the drop's tick, moving or at rest. The raised car is not in the host's world (RE8), so the host's body launched at it passes under or through it; the ragdoll collides with the world layer only (KE7), so no screen rests it on a car the host's body is under. The lowered car is not in the host's world either, so a body launched at it rests inside it on every screen, and its raised player is pushed out by its own client, RE8's quirk (KD15 (a), §8; 728e's test bounds it) |
| Throwing (#37) | a thrown item and a knocked-down body | an item flies over a body (TD12 (a)), unchanged: to `core/` the body is a point. The two motions share nothing: the body is the host's physics (KE1 (b)), the item's flight is the throwing design's TE1, still the engineer's |
| Delivery by meaning (#683, PR #713) | a knocked-down carrier keeps its items | a launch can carry a package into or out of its place; it counts once it rests on the ground (a death drops it), "however it got there" |
| The animated character (#522) | its mapping has "knockdown, then lying downed" and "get up when revived" | the first becomes this ragdoll on the skeleton's physical bones; the second follows KD7 |

### 8. Edge cases

| Case | What happens | What it prevents |
|---|---|---|
| Knocked down in a jump, feet in the air | on a map `motion_maps` leaves out, as today: the point drops to the floor below at once, and the ragdoll falls to it, held by its spring (KE7); on the House the host's body starts in the air and falls | a knockdown off the House that changes what today's tests assert |
| Knocked down against a wall, launched into it | the host's body hits the wall and falls at its foot; it started upright where its player stood and moves with continuous collision (KE13) | a body pushed through the wall |
| Launched off the balcony or a ledge | it lands below and can be raised there | a body resting in the air over the yard |
| Launched over no floor | the longest motion ends it at the fallback; the match logs an error | a body nobody can reach, and its items with it |
| It comes to rest on the parapet, a railing or a stair's nosing, its centre past the edge | it rests on top, where the physics holds it (the rest point is `stand_floor_below`'s, the highest floor under the capsule, KE15), and can be raised there from within reach | a body snapped to a floor it never reached |
| Launched at a table, or into a gap behind furniture | the host's capsule, a crouching player's that never turns, goes only where a crouching player fits (KD11, KE13; KD13 (a)): it rests beside or on a table a crouching player does not fit under, and only under one it fits under; a raised player gets up crouched there and stands once there is room (KE6). Tables keep the space under them (KD14 (a)): a body rests under one a crouching player fits under, as long as a raise reaches it (KD12 (a)) | a raised player standing up inside the table, pushed out through the level |
| Launched where no player can reach (the locked roof's edge) | the levels leave no such surface: their reach convention covers bodies, tables and the roof included, checked on the House by 728f's tests; no rule in `core/` (KD12 (a)) | a package launched out of everyone's reach for the match |
| Two bodies land on one spot | both lie there; the host's bodies and the ragdolls pass through each other | a pile that differs on each screen |
| A `Raise` while the body moves | `Rejected(moving)` (KD4 (a)) | a raise of a body that leaves reach a tick later |
| A give-up or the time running out during the motion | the body lies on the floor below where it is (KD8 (a)); `StopBody` frees the host's body | items dropped away from their body |
| A leave during the motion | no body; the items drop on the floor below its point; `StopBody` | items hanging in the air, and a host body nobody owns |
| The round ends during the motion | the body moves on and rests by the reports; the reset clears it and frees the host's body | a host body left in the next match's space |
| The host's frames drop under load | its physics runs slower against the clock; the reports and the longest motion (in core ticks) still bound the motion; the rest time counts only ticks with a report, so a hitch's catch-up ticks never end a motion at a slow report in mid-air (KE15) | a body unraisable for its whole knockdown, and one rested under a launch's apex where the physics never carried it |
| A replay of the match | the reports come from the log; no physics runs | a replay that rests a body elsewhere |
| A knocked-down client claims a walk (an old build or a hostile peer) | nothing moves; no `Correction` (KE4) | a crawl the engineer ruled out |
| A knocked-down client sends voice | the host routes none (the invariant); an honest client sends none | a voice from a body |
| A body lies under the raised car when it drops (it fell, slid or was launched there) | it dies (RD7) | a body that survives under the car on one screen |
| Launched into the lowered car (client-only, the car repair ADR's RE8) | the host's body passes into the car's footprint, which its world does not hold, and rests on the floor there; each screen's ragdoll lies inside the car (KE7); a raise reaches it (RE8: the host's sight passes through the car); the lowered car pushes the raised player out on its own client, RE8's quirk (KD15 (a)), a push deeper than the 0.4 m from the box's edge RD6 (a) accepts, and the host checks the claims that follow as any claims; 728e's test records the push and the `Correction`s that follow (§10) | a raised player left standing inside the car's collider with no answer for what its client does |
| Snapshots lost or late | the client interpolates as for any avatar; the ragdoll snaps when farther than its snap distance | a ragdoll drifting away from the host's point |
| The host's own player is knocked down | the same: its client gets its own filtered snapshot, its own avatar included | the host's player seeing more than a guest |
| A knife knockdown on the flat greybox (a map `motion_maps` does not list) | no launch and no host body, whatever the knife's numbers: the body lies where it fell, still and mute, drawn as a ragdoll; the own avatar still reaches its player (KE5), at rest | a new mechanic on the greybox, against the engineer's answer and his standing rule |

### 9. Testing

- `core/` (`tests/unit/life/`, `tests/unit/combat/`), with scripted reports (the test plays `server/`, feeding
  `BodyMoved`): on a map `motion_maps` leaves out a knockdown is today's (its event, its `Correction`, no motion, no
  `LaunchBody`), and every existing life test passes there; on a listed map the knockdown emits `LaunchBody` with
  KE9's velocity and a `Raise` is rejected as `moving`; reports move the point and the velocity; a report of an old
  epoch, of a body at rest or not finite is handled as KE14 says; the rest (KE15) once the rest time has passed
  since the last fast report, and not before; the longest motion; ticks with no report (a host freeze) counted
  toward the longest motion and never toward the rest time (a slow report at an apex followed by a rest time of
  catch-up ticks ends nothing); no floor (the fallback and its error); a death, a give-up and a leave during a motion, each emitting
  `StopBody`; the command log replays the same rest with no physics.
- Where bodies move (KE12; `tests/unit/life/`, `tests/unit/content/`): on a fixture mode with two maps whose
  `motion_maps` lists one, a launching strike starts a motion on the listed map, and on the other the knockdown is
  today's, step for step; an empty list moves bodies on every map; the mode check refuses a listed path that is not
  one of the mode's maps.
- Movement (`tests/unit/movement/`): a knocked-down claim of a far place moves nothing and sends no `Correction`; its
  facing is taken; a malformed, a negative-tick and a past-credit claim of a knocked-down sender are dropped with no
  `Correction` and no facing taken; stale claims are dropped as before; a taken claim advances `claim_tick` and
  spends credit, so an older twin sets no older facing and a run of claims ahead of the host's ticks meets the
  past-credit drop.
- Entitlement: the own avatar reaches a knocked-down player only. No check guards that today: `LeakCheck` compares
  the decoded avatars with `view_of`, which reads `Snapshots.for_peer` itself, so a wrong exception (inverted, or
  `life != DEAD`) would pass it. 728b adds a check that does not trust the declaration, in `LeakCheck` and in the core
  runner's `ScenarioInvariants`: a decoded snapshot holds the viewer's own avatar exactly when the host's state has
  that viewer `DOWNED`, read from the life state, never from `for_peer`. It is seen failing on a planted own avatar of
  a living player and on a missing own avatar of a knocked-down one (the leak test is proven so, ARCHITECTURE §5).
- The invariants with a body in motion: no scenario moves a body (the greybox), so 728b adds a core-runner test on a
  fixture mode whose `motion_maps` lists its fixture map, with a launching strike and scripted reports, that runs
  `ScenarioInvariants` (the `view_of` comparison, the own-avatar check, the voice distance) on every tick of the
  motion. Prevents: a check that reads a cached knockdown point instead of the moving one staying green because no
  checked run ever has a moving body.
- The host's body, by integration tests in the host's world (`tests/integration/server/`, 728b): first the probe that
  a rigid body in a `World3D.new()` space falls as the physics frames step it (KE13); then, on a fixture level with a
  ledge, a ramp, stairs, a wall, a hole and a low table, through `HostBodies` and a `Match` on a fixture mode that
  lists it (and the crouch on it, KE12): a body launched off the ledge rests on the floor below, one launched down
  the ramp or the stairs ends lower on them or at their foot, one knocked down with no launch on a flat floor rests
  where it stood with its capsule's axis vertical (it never turns), one launched at the low table, whose underside is
  lower than a crouching player is tall and higher than the capsule is wide, never rests under it (KD11: a capsule
  free to turn would roll under), one crouched under a low fixture ceiling starts below it, one launched at the wall
  rests on its near side, one that comes to rest on a stair's nosing and one on a thin railing, each with its centre
  past the edge, rest on the step and on the railing, not on the floor below (KE15's `stand_floor_below`), and one
  over the hole ends at the longest motion with the fallback and its error; each waits real physics frames and
  asserts where the body may rest (on a floor, inside the level, within the longest motion, and with a crouching
  player's capsule at the rest point, lifted by `Items.SURFACE_CLEARANCE_M` so touching the floor is not a hit, clear
  of the level by `PhysicsDirectSpaceState3D.intersect_shape`, KD11), never an exact point. A `StopBody`, a death and a level change
  free the host's body.
- Chaos and bots: a knocked-down hostile peer's walking claims (its rows, ARCHITECTURE §4.6.5.3);
  `dissident_kills_the_crew` loses "and it crawls": a knocked-down bot's `WalkTo` fails the step, as a dead bot's does.
  No scenario, chaos run or perf run plays the launch or the host's body: they play the greybox, where no body moves
  (KE12), and bots do not play the House (ARCHITECTURE §9.7).
- The House, by integration tests in the host's world of the map (`LevelWorld`, `HostWorldQuery` and `HostBodies`, as
  `tests/integration/levels/house_markers_test.gd` builds the first two; 728e): the base mode's knife launches there,
  each body coming to rest on a floor within the longest motion; and the base mode on the greybox starts no host
  body, whatever the knife's numbers. Under KD12 (a), 728f adds that none rests where no player can reach it to
  raise it: none on the locked roof (beside #646's throw check), and each rest point within a raise's reach of a
  spot a player can walk to (728f's named floors, never a furniture top or the locked roof); a rest point under a
  table is held to the same reach (KD14 (a)).
- The client, over the loopback: a knocked-down joiner holding the move keys stays where the host has it with 0
  `Correction`s; launched, its camera follows its own avatar and stops under a low ceiling; the ragdoll's root stays
  within the snap distance of the point every frame; the raise hint aimed at a ragdoll's limb names its peer, and one
  aimed past it names none; a revived joiner stands at the host's point.
- `shot`: `life_preview` shows a ragdoll at rest and a dead body in place of the lying capsule.
- The human playtest, on the House: the launch's feel (KD2, KD9), how bodies roll off the stairs, ledges and balcony
  (KD10 (A)), the rest's numbers, and the camera (KD6); on the greybox, that a knocked-down body lies still where it
  fell.

### 10. The split

Proposals for the M7 backlog, each `base: release/m7`; the manager opens them now that the engineer has answered
(§11), and none is built until he says so. Every content file named is provisional under the
[MVP content ADR](2026-09-29-mvp-content-built-by-the-engineer.md), for his approval in its PR, and every number in
one is a placeholder marked "not a decision" (KD9 (b)). 728a and 728d apply on every map, the greybox included (the
rework "applies wherever today's knockdown does"); the motion of 728b and 728e moves bodies on the House only (KE12).
The engineer answered KD12 and KD13 with (a) (§2, §11). 728f builds KD12 (a), the levels' convention and the House's
check; 728b builds KD13 (a), the capsule that never turns. He answered KD14 and KD15 with (a) (§2, §11): tables
keep the space under them, so 728f's check holds a rest point under a table to the same reach as any other; and RE8's
accepted quirk covers a body raised in the lowered car, so nothing is built for KD15 but 728e's test of that push,
which stops 728e if the host corrects it more than once (the review of his answer corrected KD15's premise, §2).

- **728a core and client: a knocked-down player holds still and looks** (size M). Goal: a knocked-down player cannot
  move; its claims carry its look only. Acceptance: `MovementRule` takes a knocked-down claim's facing only (KE4),
  ignores the rest, sends no `Correction`, and settles stamina as regenerating; the crawl check,
  `CRAWL_SLACK_FRACTION`, `held_against`, `HOLD_SLACK_M` and `Channel.held_at` go, and with them what only the hold
  used: `RaiseDowned`'s `holds_target` and its `held_at`, `ChannelEffect.holds_target`, `Channels.holds` and
  `holding`; `PlayerRules.crawl_speed_mps` and its bound go, from `content/modes/base_mode.tres`, the fixture modes,
  `player_rules_test.gd` and the harness's `WalkTo` crawl (`scenario_play.gd`) too; `revive` sends a `Correction`
  (KE6), and the revive is a placement for the honest bot: `ScenarioBot`'s `Revived` branch sets its correction due
  (as `KnockedDown` and `Respawned` do), `ChaosRun`'s `Correction` accounting counts it, and the check that an honest
  bot is never corrected outside a placement stays as strict; `PlayerController` no longer crawls (a knocked-down
  controller moves nothing and claims its look), and the game's raised-player hold (`game.gd`'s `_player.held`) and
  the test room's F1 "downed mode crawls" go with the crawl; the harness's `WalkTo` fails while knocked down;
  `dissident_kills_the_crew` without the crawl; the chaos rows, and `ChaosOracle`'s class 5 expecting no
  `Correction` to a knocked-down peer for any claim (KE4); the tests of §9 that need no motion; ARCHITECTURE: every
  line that names the crawl or the raise's hold (`grep -n -i crawl` and `held in place` find them): §3.2, §4.1's
  `MoveClaim` row, §4.2's `RaiseStarted`, `Revived` and `Correction` rows ("none at a revive"), §4.6.1, §4.6.2,
  §4.6.5, §4.7.6 to §4.7.9, §7's opening, §7.1.3 to §7.1.5, §7.1.7, §7.1.8, §9.4.2's `RaiseDowned` row, §9.5.1's
  `PlayerRules`, §9.5.6, §9.5.15, §9.5.16 and §9.7. Depends on: nothing (decided). Files:
  `core/movement/movement_rule.gd`, `core/content/player_rules.gd`,
  `core/life/life_rules.gd`, `core/life/raise_downed.gd`, `core/channel/` (`channel.gd`, `channel_effect.gd`,
  `channels.gd`), `client/player/player_controller.gd`, `client/app/game.gd`, `client/dev/test_room.gd`,
  `tests/harness/scenario_bot.gd`, `tests/harness/scenario_play.gd`, `tests/harness/chaos/` (`chaos_oracle.gd`,
  `chaos_run.gd`), `tests/fixtures/match/fixture_modes.gd`, `tests/unit/content/player_rules_test.gd`,
  `tests/unit/movement/`, `tests/unit/life/`, `tests/integration/client/`, `content/modes/base_mode.tres`,
  `content/scenarios/dissident_kills_the_crew.tres`, `docs/ARCHITECTURE.md`.
- **728b core and server: the body a rigid body in the host's physics: the launch, the reports and the rest** (size
  L). Goal: on the House a knockdown blow can launch the body, the host's physics moves it, and `core/` knows where it
  is and where it rests, where everyone sees it. Acceptance: `BodyMotion` in `PlayerState.motion` (KE3); `Strike`'s
  `launch_mps` and `launch_up_mps` with their bounds; `damage` and `knock_down` take the launch (KE9); the directives
  `LaunchBody` and `StopBody` (audience *server*); `HostBodies` in `server/` (KE13: the crouching player's collider,
  `capsule_radius_m` and `crouch_height_m`, as a `BODY_MODE_RIGID_LINEAR` body that never turns, KD11 and KD13 (a)), with the
  probe of §9 first; the
  command `BodyMoved` that `server/` originates and logs (KE14), never decodable from the network, named beside
  `PEER_CONNECTED` under `Intents`' "Commands server/ originates", documented in `MatchCommand`, and taken in every
  phase (never rejected, as `PeerConnected` is; it acts only on a body in motion, which Round and End can hold:
  at the round's end the body moves on), with `HostWorldQuery` giving `HostBodies` the current level's world and
  telling it of a level change, which frees every body; the rest, the no
  floor and the longest motion in `core/` (KE15, §4's steps 5 to 7); `TargetDowned` rejects `moving`; KD8 in `die`;
  `leave` and `ResetMatch` clear the motion; the own avatar in a knocked-down viewer's snapshot
  (KE5), with `WireSchema.MAX_AVATARS` raised to `MAX_PLAYERS` and a test that a full match's knocked-down viewer
  gets its 16-avatar snapshot, the own-avatar check of §9 (from the life state, not from `for_peer`) in `LeakCheck`
  and `ScenarioInvariants`, seen failing on both plants, §9's run of the invariants through a motion, and the
  protocol number, and the client's `AvatarViews` and the bots' fold skipping it until 728d draws it, so no client
  draws itself as a stranger in between; `ChaosOracle`'s reason table gains `moving`; on a map `motion_maps` leaves
  out a knockdown is today's, step for step (§4, step 2). Where bodies move (KE12): `PlayerRules.motion_maps`,
  compared with `MatchState.map` in `knock_down`, the mode check refusing a path that is not one of the mode's maps
  and a map where a body moves but the crouch does not play (`crouch_maps`, KE12, KD11; gone since #991), and the base
  mode listing the House alone from this issue on, so no later change can give the greybox a launch by leaving
  the list out; the rest speed, the rest time and the longest motion in `PlayerRules`
  with their bounds, set in the base mode and the fixture modes as placeholders marked "not a decision" (KD9 (b));
  §9's unit tests and the
  host's-body integration tests on a fixture level. 728b ships with every launch at 0 (the knife sets none) until
  728d draws the motion: before it, a launched player's camera and ears would stay where the knockdown started while
  every other screen showed the body fly, and its client's voice cutoff (E41) would measure from the wrong place.
  With no launch the host's capsule rests where its player stood (KE13), unless the floor there sends it on (a
  stair's edge), so on the House a knockdown then holds a raise back about the rest time. ARCHITECTURE: §1's
  `server/` row (it simulates knocked-down bodies on the maps `motion_maps` lists); §3.3's replay (`BodyMoved` among
  the commands `server/` originates); §4.1's note after its table ("A connection and a leave are not intents": the
  reports are not either); §4.2's directives (`LaunchBody`, `StopBody`); §4.5.3 (the reports at the head of step
  4's batch, stamped t, none in step 1's catch-up); §4.5.9 (the level's world holds the bodies, and a level change
  frees them); §5
  (the per-peer rule, and its "Widening" bullet: a knockdown now widens its own player's snapshot by its avatar);
  §4.6.2 (the bots' fold skips the own avatar); §4.6.4 (the leak test's list of invariants: the own-avatar check)
  and §4.6.4.1 (its two plants, seen failing); §4.1's `Raise` row and §9.5.13's rejection list (`moving`); §4.2's
  `KnockedDown` row and its `Swapped` row ("its avatar is never sent to it"); §4.3.1's bound ("the snapshot's
  avatars at most 15: never the viewer's own"); §4.3.5's `Snapshot` row ("16 avatars: 725" for "15 avatars: 680");
  §4.4's "the snapshot's 15 avatars take 680 bytes"; §4.6.1.1 and §4.6.1.2 ("the own player's never arrives");
  §4.7.8 ("since the own avatar never arrives"); §9.4's `Strike` row (its launch fields, 0 launching nothing, and
  their bounds), its `TargetDowned` row and §9.4.5's `LifeTicks` row (the longest motion and the no-floor error);
  §9.5.1's `PlayerRules` (the rest's numbers, the longest motion, `motion_maps`: the House, and its check against
  `crouch_maps`); §7.1.18. Depends on: 728a; 727a (#790: `crouch_height_m` and `crouch_maps`, which the host's
  capsule and the mode check read); KE1 (b), KE5, KD1, KD2, KD4, KD8, KD10, KD11 and KD13 (a) (answered; it builds
  KD13 (a)'s lock); not on 728f: KD12 (a) adds nothing here. Not on the throwing issues:
  the host's physics needs neither their sweep nor their arc. Files: `core/life/`,
  `core/combat/strike.gd`, `core/content/player_rules.gd`,
  `core/match/player_state.gd`, `core/match/snapshots.gd`, `core/match/reset_match.gd`,
  `core/match/phases/join_rules.gd` (`PROTOCOL_VERSION`), `core/match/intents.gd`, `core/match/match_command.gd`,
  `core/match/phase.gd`, `core/match/match.gd`, a new `server/host_bodies.gd`, `server/host_session.gd`,
  `server/host_world_query.gd`, `server/level_world.gd`, `net/messages/wire_schema.gd` (`MAX_AVATARS`),
  `tests/unit/net/messages/wire_schema_test.gd` (680 becomes 725), `client/world/avatar_views.gd`,
  `client/net/client_model.gd` (its docs say the own avatar is never sent; `avatars` holds it while knocked down),
  `tests/harness/scenario_bot.gd`, `tests/harness/chaos/chaos_oracle.gd`, `tests/unit/life/`, `tests/unit/combat/`,
  `tests/unit/content/player_rules_test.gd`, `tests/fixtures/match/fixture_modes.gd`, `tests/fixtures/levels/`,
  `tests/integration/server/`, `tests/harness/bots/leak_check.gd`, `tests/harness/scenario_invariants.gd`,
  `content/modes/base_mode.tres`, `docs/ARCHITECTURE.md`.
- **728d client: a knocked-down body drawn as a ragdoll** (size M). Goal: a knocked-down body falls and flies as a
  ragdoll held to where the host has it. Acceptance: the ragdoll view (KE7) for remote knocked-down avatars and the
  own one, on every map; on today's placeholder capsule avatar one `RigidBody3D` capsule on the `downed` layer with
  the world mask only, started from the standing pose with the snapshot's velocity, held by a spring to the
  interpolated point and snapped when far; the own camera and ears from the own avatar; the pivot's two clamps
  (KE8: the eye height above the floor
  below, and the ceiling) for the own camera and for a spectator watching a knocked-down target, with a loopback test
  of each in mid-flight; dead bodies keep the pose, greyed, with the cross (KD7); the raise hint's cast maps a hit
  ragdoll part to its peer and measures the reach to that peer's interpolated point (§7), with a loopback test (§9);
  the revive returns the standing avatar; `RemotePlayerBody`'s lying pose and `LifeLooks`' lying capsule go; the render checklist's items 1, 3 and 5
  hold; the tests and the `shot` of §9; ARCHITECTURE §4.7.9. Depends on: 728b; KD6, KD7. Files:
  `client/player/remote_player_body.gd`, `client/player/life_looks.gd`, a new `client/player/ragdoll_view.gd`,
  `client/world/avatar_views.gd`, `client/world/body_views.gd`, `client/life/life_view.gd`,
  `client/life/downed_camera.gd`, `client/life/ears.gd`, `client/dev/life_preview.tscn`, `tests/integration/client/`,
  `docs/ARCHITECTURE.md`.
- **728e content: the launch on the House, its integration tests and the playtest** (size S). Goal: on the House a
  knife knockdown launches the body, and the host's physics slides it or drops it off what it lands on (the host's
  capsule never rolls, KD13 (a); each screen's ragdoll does); the greybox moves no body.
  Acceptance: the knife's `launch_mps` and `launch_up_mps` (`content/items/knife.tres`), placeholders the agents
  pick, marked "not a decision" (KD9 (b)), provisional under the MVP content ADR for the engineer's approval in its
  PR; `motion_maps` still the House alone (KE12, from 728b). Integration tests on the House in the host's world
  (`LevelWorld`, `HostWorldQuery` and `HostBodies`, as `house_markers_test.gd` builds the first two), since bots do
  not play the House (ARCHITECTURE §9.7): a knife launch in each direction from a sample of places players stand (the
  yard, the terrace, the balcony, the top of the stairs) rests the body on a floor within the longest motion, with a
  crouching player's capsule at the rest point clear of the level (KD11); KD15 (a)'s push, in a test with the lowered
  car's collider on the client's `movers` layer: a revive `Correction` places a crouched player at the centre of the
  car's footprint, and the test records the client's push and how many `Correction`s the host sends after it; if more
  than one follows, or the push lifts the player onto the car, the issue stops and puts KD15 back to the engineer with
  (b), (c) and that cost (§2); and the base mode on the greybox starts no
  host body with these numbers (a knife knockdown there is today's, step for step). Nothing of KD12 (728f).
  Each test asserts where a body may rest, never an exact point
  (KE1 (b)). No bot scenario: the scenarios, the chaos run and the perf run play the greybox, where nothing moves,
  and stay as they are. The playtest's list, on the House (KD2, KD6, KD10 (A), KD11 and KD14 (a): a body launched
  under a table and raised there; KD15 (a): a body launched into the lowered car and raised there). ARCHITECTURE §9.5.6 (the knife's launch). Depends on: 728b, 728d (the first
  non-zero launch in the base mode needs the own avatar's camera and ears to follow the body) and 727b
  (#791: a launch can rest a body where only a crouching player fits, and the raised player's crouched get-up is its
  controller's, KE6). Files: `content/items/knife.tres`, `tests/integration/levels/`, `docs/ARCHITECTURE.md`.
- **728f content: a body launched out of everyone's reach (KD12 (a))** (size S). Goal: the engineer's KD12 (a), a
  launch never carries a body where no player can reach it to raise it, kept by the levels with no rule in `core/`.
  Acceptance: the convention line in `levels/CLAUDE.md` names launched bodies beside thrown items: every surface a
  launch can reach, tables and the roof included, lies within a raise's reach of a spot a player can walk to. If
  #646 has written its throw line by then (TD5 (a)), 728f adds bodies to it; if it has not (on main the
  throwing ADR is still "Proposed"), 728f writes the bodies' line itself beside "Hiding spots", and #646 adds thrown
  items to it later. A spot a player can walk to is one on a named set of the House's floors that a player reaches
  from the spawn on foot (the yard, the rooms, the terrace, the balcony, the stairs; never a furniture top or the
  locked roof), where a crouching player's capsule stands clear of the level (`stand_floor_below` and the crouched
  capsule, KD11); the list lives in the test, beside the House's scene, and a floor added to the House is added to
  it. The House's check, in `tests/integration/levels/` beside #646's roof check if it has landed: from a sample of
  points on those floors, a launch in each direction by every strike whose launch the base mode gives on the House (its numbers read from the
  mode's data, never copied into the test, so a retuned or new weapon is checked as it is) rests no body on the
  locked roof, and every rest point lies within the raise's reach (`TargetInReach` from the feet, and
  `TargetInSight` from the crouched eye) of a point on one of the named floors. A rest point on a table top or the
  locked roof passes only through that reach, never as a spot of its own; a rest point under a table is held to the
  same reach as any other, since tables keep the space under them (KD14 (a)). If a launch does rest a body out of
  reach, the issue stops and reports it: the House's layout is the humans' (a scene change), never a rule in
  `core/`. Depends on: 728e; not on #646 (728f uses its line if it lands first). Files: `levels/CLAUDE.md`,
  `tests/integration/levels/`, `docs/ARCHITECTURE.md`.
- **#522 (not a new issue):** its mapping's "knockdown, then lying downed" becomes 728d's ragdoll on the skeleton's
  `PhysicalBone3D`s under a `PhysicalBoneSimulator3D` (`physical_bones_start_simulation`), and its "get up when
  revived" follows KD7; the manager adds this to #522.

### 11. The engineer's answers

All answered on 2026-10-10
([PR #754, comment 6097876326](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6097876326)), every
recommendation: **KD1** (a) only the knocking blow launches; **KD2** (a) every strike has a launch, the knife's
included; **KD3** (a) floors steeper than an angle slide a body, stairs excluded (superseded by KD10 (A)); **KD4**
(a) a moving body cannot be raised (`moving`); **KD5** (a) it hears the living within the radius, as today; **KD6**
(a) today's camera above the body, following it; **KD7** (a) a grey ragdoll with the cross, and a raised player
stands up; **KD8** (a) a death ends the motion, and the body and its items rest where it stopped; **KD9** (b) the
agents set placeholders marked "not a decision"; **KE1** (a), replaced by (b) below; **KE5** (a) the host sends a
knocked-down player its own avatar, the one exception to §5's "nobody gets their own avatar" (`MAX_AVATARS` 16, a
protocol bump). And **the House only**: the launch plays on the House; the flat greybox keeps the reworked knockdown
(still, mute, a ragdoll) with no launch (KE12), and no bot scenario plays it (728e). Its issues open as proposals for
the M7 backlog, none built until he says so.

**KD10 (A)**, the same day
([PR #754, comment 6100602989](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6100602989)): the
knocked-down body is a real physics rigid body simulated by the host's physics engine in `server/`; a blow launches
it, and it rolls or slides off any slope, roof or stairs by itself. No separate slide rule: 728c goes. **KE1
changes from (a) to (b)**: the body's motion is host physics in `server/`, not computed in `core/`, and `core/`
keeps knowing where the body rests (invariant 3 stays). The motion is checked by host-side integration tests, not
core determinism. The launch stays on the House only; the greybox keeps the knockdown (still, mute, a ragdoll)
without it. The design stays approved with this change.

**KD11**, on 2026-10-11
([PR #754, comment 6108669765](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6108669765)), on its
scenario 1 (a body rolls under a table, a teammate raises it, the player stands up inside the table): "the body must
have the collider of a crouching player, so wherever it gets up, it must be crouched". None of (a) to (c) as written:
the knocked-down body's collision shape in the host's physics is the crouching player's collider, so a body comes to
rest only where a crouching player fits; a raised player gets up crouched at the rest point and stands up by the
crouch rules of PR #752 once there is room. His answer does not settle scenario 2 (a launch carries a body where
nobody can reach it), split out as **KD12**. His words name the collider only: that the host's capsule never turns,
so it slides and falls but never rolls, is the agent's reading, read back as **KD13**.

**KD12 and KD13**, the same day
([PR #754, comment 6109457234](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6109457234)), read back
and confirmed in a chat with the game-design manager session. He asked how a body could get onto the locked roof at
all: not on today's House (the launch has no numbers yet, and the roof is above level 2); it is a reviewer's case for
a launch that carries a body several metres. His own words pointed at the levels: "make tables have colliders so
nothing can be thrown under them". **KD12** (a): the levels are built so a launch cannot carry a body where no player
can reach it, tables and the roof included: #646's TD5 (a) reach convention applied to bodies, checked on the House
by tests, with no rule in `core/`; 728f builds the convention line and the House's check. **KD13** (a): the host's
body has the crouching player's collider, stays upright and never turns (`BODY_MODE_RIGID_LINEAR`, KE13 as written).
Pushing the body out if it stands up inside a collider, his idea, is not needed for a collider in the host's world,
such as a table: a crouched-size body cannot rest inside one in the first place (KD11).

The review of the KD12 and KD13 update found two cases those answers leave open, read back to him with options and a
recommendation (§2). He answered both on 2026-10-11 with (a)
([PR #754, comment 6110171062](https://github.com/xperiaroco2/prime-game/pull/754#issuecomment-6110171062)): **KD14**
(a): the confirmed read-back stands as is; tables keep the space under them. A body may rest under a table a
crouching player fits under, as long as a raise can reach it (KD11, KD12 (a)); no level rule closes tables. **KD15**
(a): RE8's accepted quirk: a body launched into the lowered car and raised there is pushed out by the raised
player's own client, as the car repair ADR's RD6 (a) already accepts. Nothing new in code. The review of his answer
corrected KD15's premise: RD6 (a)'s push is at most 0.4 m from the box's edge, and this one starts with the feet inside
the box, so it can be deeper and the host may correct it back into the car; (a) stands on 728e's test of it (§2,
§10).

## Alternatives

- **A ragdoll free on each client** (no host motion): the body rolls off the roof on one screen only, and a raise
  fails at a body the raiser stands over (Context).
- **`core/` moving the body** (KE1 (a), this design's first recommendation, with a slide rule for steep floors, KD3
  (a), and a slope answer, KE2), **or the victim's client** (KE1 (c)): the engineer chose the host's physics (KD10
  (A), KE1 (b)).
- **The engine's sleep as the rest:** its thresholds are project settings, outside the mode's data and its bounds
  (KE15).
- **The host's body started lying:** it can start across a wall its player stood beside (KE13).
- **The host's capsule free to turn, with a topple** (KE13 before KD11; KD13 (c)): it lies down, twice its radius
  tall, and rolls under a table a crouching player does not fit under, where a raised player would get up inside the
  table; the engineer chose (a), the lock.
- **The lock plus a body friction** (KD13 (b)): a `PlayerRules` number that changes nothing while no House floor
  slopes; it can come with the first sloped level. **Pushing a body out of a collider it stands up in** (the
  engineer's idea while answering): not needed for a collider in the host's world, since a crouched-size body cannot
  rest inside a table (KD11). For the lowered car, which only the clients have, a push-out of the client's own
  (KD15 (b): a client rule `ScenarioBot` cannot see) **or no rest in the car's footprint** (KD15 (c): a body
  snapping across the room on every screen): the engineer chose RE8's accepted quirk (a), resting on 728e's test of the push (§2).
- **Tables closed underneath** (KD14 (b), his words "make tables have colliders so nothing can be thrown under
  them" as a level rule: a collider change on each House table that leaves the space open, the humans' scene work,
  and no player crouching under a table): the engineer kept the confirmed read-back (a), tables as built.
- **A body out of everyone's reach moved back by a level mark** (KD12 (b): a marker kind and its rule every level
  keeps up to date, and a body snapping back across the room on every screen) **or left there** (KD12 (c): a launch
  hides a package for the match): the engineer chose the levels' reach convention (a).
- **Where a body may rest by a fit query** (KD11 (b): a standing player's capsule at the rest point, else the
  fallback), **by the levels' convention alone** (KD11 (a)), **or with no rule** (KD11 (c)): the engineer chose the
  crouching player's collider instead, which needs no query and no snap back.
- **Keeping the crawl, with a ragdoll only for looks:** against "cannot move".
- **A new life state for a body in motion:** a knockdown in motion is still a knockdown; a state would touch every
  reader of the life state, the wire's flag and the client's life fold, for what `PlayerState.motion` holds.
- **A lying animation, or a get-up clip now:** against "no animation"; the get-up clip was KD7 (c), and the engineer
  chose (a). It can replace the pop-up later.
- **A `Correction` per tick, or the own client computing its motion:** KE5.
- **Muting in a voice rule:** KE10. **Renaming `DOWNED`:** KE11.
- **The launch and the host's body on every map, the greybox included:** against the engineer's answer and his
  standing rule (no new mechanic on the greybox).
- **A mode of its own for the House, the numbers in the House's scene, or one list per strike:** KE12 (b) to (d).
- **A greybox bot scenario of a launched body:** the greybox moves no body, and bots do not play the House
  (ARCHITECTURE §9.7), so the House's integration tests check the motion (728e).

## Consequences

- Once built, a knocked-down player never moves on its own, so "crawling into a circle and giving up" (vision
  revision 1, V4) is gone; on the House a launch can carry a body, and its package, instead.
- The point the raise, voice and the car read can move after `KnockedDown` on the House; each of them already reads
  it every tick. On the greybox it stays where the body fell.
- `server/` gains a job (ARCHITECTURE §1): on the maps `motion_maps` lists it simulates knocked-down bodies in the
  level's world and originates a command, `BodyMoved`, whose values come from physics. `core/` stays deterministic in
  what it is given, but the same match played twice can rest a body in two places: the replay holds because the
  reports are logged, and the House's tests assert where a body may rest, not where it does.
- `MovementRule` sheds the crawl and the hold; `PlayerRules` loses `crawl_speed_mps` and gains the rest's numbers, the
  longest motion and `motion_maps`; `Strike` gains a launch; `WorldQuery` gains nothing; the snapshot's own-avatar
  rule gets one exception, with a protocol bump and `WireSchema.MAX_AVATARS` raised to `MAX_PLAYERS`.
- `motion_maps` is the second per-map list in the mode's data, beside `TaskType.maps` (the Generator ADR's GE15): a
  later House-only mechanic follows the same shape. The mode check tied it to the crouch's `crouch_maps` (KE12)
  until #991 removed that list (the crouch plays everywhere: the crouch ADR's amendment of 2026-10-14).
- The knockdown now builds on the crouch (KD11): the host's body takes `crouch_height_m` (727a, #790), and a raised
  player's crouched get-up is the crouch's controller (727b, #791), so 728b follows #790 and the first launch (728e)
  follows #791.
- #646's reach convention for thrown items covers launched bodies too (KD12 (a)): a level where a launch can rest a
  body out of everyone's reach fails its check, and the fix is the level's layout, never a rule in `core/`. Tables
  keep the space under them (KD14 (a)), so a body may rest under one, held to the same reach, and a crouching player
  keeps that hiding place.
- A player raised from a body launched into the lowered car is pushed out by its own client (KD15 (a)); the host's
  world never sees it. The push starts with the feet inside the footprint box, so it can be deeper than the 0.4 m from
  the box's edge RD6 (a) accepts, and the host may correct it back into the car: 728e's test records it, and more than
  one `Correction` stops 728e and puts KD15 back to the engineer. It measured 3, and his (b2) (#976) replaced the
  push: the raised player's own client walks its capsule out of the car at walk speed over its first claims,
  ignoring `movers` until clear, which the host checks as any claims; the stand-in test measures no sink and no
  `Correction`. The search's reach (`MOVER_EXIT_REACH_M`, 3 m) is a placeholder awaiting his approval.
- The host's body never rolls (KD13 (a)): it slides off only a slope steeper than its friction angle, so on a later
  level with a gentler slope a body knocked down with no launch stays put; a body friction (KD13 (b)) can come then.
- 728b no longer waits on the throwing issues #641 and #642: the host's physics needs neither the sweep nor the arc.
- The playtest on the House tunes the launch and the rest; the bounds keep a forgotten number out.
- Built (the heading of ARCHITECTURE §7.1.18 named these until #1244): "Still" in 728a (#846); the motion, the House
  only and who gets what in 728b (#847); the ragdoll in 728d (#848).
- 2026-10-22 (#1307): ARCHITECTURE §7.1.18's two paragraphs no longer carry "Built in 728e (#849)" and "Built in 728f
  (#850)". 728e (#849) built the knife's launch on the House (its paragraph "The knife's launch"); 728f (#850) built
  KD12 (a) in the levels and the House's body-reach check (its paragraph "Thrown items and the levels").
