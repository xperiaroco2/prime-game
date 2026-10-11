# The knockdown reworked (#728): still and mute, a ragdoll, and the body a rigid body in the host's physics

- **Status:** Proposed on 2026-10-10. Nothing here is built, and nothing will be until the engineer says so: for now
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
  each is a placeholder marked "not a decision" (KD9 (b)). No question is open.
- **Date:** 2026-10-10
- **Deciders:** the engineer (the decided rules; his answers to KD1 to KD9, KE1 and KE5, and the House only, in PR
  #754's comment 6097876326; KD10 (A) and KE1 (b) in its comment 6100602989); designed by the agent of #728 in the
  game-design manager session's workflow (#676)
- **Builds on:** [vision revision 1](2026-10-01-vision-revision-1.md) (Life: knockdown, death, respawn; Voice;
  Hidden information), [the M4 client design](2026-10-01-m4-first-person-client.md) (its §3, the render checklist,
  items 1, 3 and 5), [the M5 voice design](2026-10-02-m5-voice-integrated-with-the-rules.md) (E40, the ears; E41, the
  cutoff), [the throwing design](2026-10-09-throwing-held-items.md) (its TE1, whose option (b), `server/`'s physics,
  is this design's KE1 (b)), the car repair design (#688, PR #709: the lift's drop kills the living and the
  knocked-down, `LifeRules.kill`, a car only the clients collide with) and the crouch (#727, designed beside this
  one).
- **Revises, once built:** vision revision 1's crawl (the Downed row's "crawls" and "crawl and give up", the crawl
  speed, and its "Needs the engineer" 8, the hold while raised), and ARCHITECTURE §7.1.7 and §7.1.8. A dated note in
  vision revision 1 points here.
- **Words:** "knocked down" is the players' word and this ADR's; `DOWNED` stays the code's name for it (KE11).
- **Numbering:** KD1 to KD10 (the engineer's), KE1 to KE15 (technical, KE1 and KE5 the engineer's; KE2 withdrawn by
  KD10 (A)), and the proposed issues 728a, 728b, 728d and 728e (728c withdrawn by KD10 (A)).

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
which supersedes KD3 (a) and changes KE1 to (b).

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

### 3. The technical choices (KE)

| Item | Choice | Options | Recommendation, and the failure it prevents |
|---|---|---|---|
| **KE1** (the engineer's: **(b)**, PR #754 comment 6100602989, replacing his (a) of comment 6097876326) | Where the body's motion runs | (a) in `core/`: the throw's arc swept through `WorldQuery.sweep` each core tick, a stop and drop, and a slide down a steep floor; (b) `server/` simulates a rigid body in the host's level space and reports where it is; (c) the knocked-down player's own client simulates its ragdoll and claims where its body is, as it claimed its crawl | **Decided (b)** (KD10 (A)); this design recommended (a) before his answer. (c) breaks invariant 1 for the rule "cannot move": a hacked client rolls its body, and the package it holds, along any slope into its place, and headless bots have no ragdoll. What (b) costs, as the throwing design's TE1 (b) lists it, and how this design meets each: the same commands can rest a body in two places on two runs (Godot 4.7.2 steps the host's spaces by physics frames, with no call that steps one space, and drops frames under load, ARCHITECTURE §4.5.2), so `core/` takes the host's reports as logged commands (KE14): a replay reproduces every rest and runs no physics, `core/` stays deterministic in what it is given (invariant 3: no physics in `core/`), and the motion is checked by host-side integration tests that assert where a body may rest, never an exact point (§9); the spaces hold no players, so the body passes through them, as the crawling downed did; `core/` would know no position in flight, so `server/` reports one each core tick (KE14); and "when is it at rest" would become a game rule in `server/`, so `core/` decides it from the reports (KE15) |
| **KE2** (withdrawn by KD10 (A)) | The slope | Was: a new `WorldQuery` answer, `floor_normal_below(p)`, for KD3 (a)'s slide | Withdrawn: the host's physics reads every slope from the level's colliders itself, so `core/` asks for none and `WorldQuery` gains no answer |
| **KE3** | Where the motion's state lives in `core/` | `PlayerState.motion`, a `BodyMotion` (`RefCounted`, `core/life/`): the epoch of the knockdown that started it, the fallback rest, the tick of its last report faster than the rest speed (KE15) and its own tick count; null at rest. `core/` holds no physics: the point is `PlayerState.position` and the velocity `PlayerState.velocity`, set from the reports (KE14). `LifeTicks` counts the longest motion, in peer-id order; `die`, `leave`, `revive` and `ResetMatch` clear the motion, each emitting `StopBody` | Prevents: a new tick system every mode must list (the mode check already demands `LifeTicks` where a rule can knock down, ARCHITECTURE §9.1), and a second place for the body's point that a rule could read stale |
| **KE4** | What a knocked-down player's `MoveClaim` does | The host takes its facing only (unit, as for every claim) and ignores its position, velocity, jumps, sprint and crouch: no movement check, no `Correction`, no stamina spent (it regenerates as today). A taken claim still advances the claim bookkeeping as `_accept` does today (`player.claim_tick`, and the credit it covers spent), so a claim whose tick does not rise is dropped as today, an old twin (`MoveClaimReliable`, §7.1.15) or a reordered claim sets no older facing, the past-credit drop below can fire, and `SelfStatus`'s `claim_tick` names the last claim taken. Today a malformed claim, a negative client tick and a claim past its credit each get a `Correction` (`MovementRule.apply`); from a knocked-down sender each is dropped instead, with no `Correction` and its facing not taken, since the host takes no place from it to correct; a claim of an old epoch is dropped as stale, as today. `ChaosOracle`'s class 5 (ARCHITECTURE §4.6.5) is rewritten from this rule, not from the docs: no `Correction` to a knocked-down peer | The facing still matters: a dead player watching a knocked-down target looks through that target's look (vision revision 1, V9: "a downed player's third person"). Prevents: a client that still crawls (an old build, a hostile peer) moving its body, and a `Correction` storm while the host moves a body its client does not predict |
| **KE5** (the engineer's: **(a)**, PR #754 comment 6097876326) | How a knocked-down client learns where its own body is | Its snapshot holds its own avatar while it is knocked down (`Snapshots.for_peer` skips the viewer's avatar unless it is `DOWNED`); the client draws its body and places its camera and ears from it, on the interpolated timeline of the other avatars | Prevents: a `Correction` on every tick of a motion (reliable, at 20 Hz), and a client simulating a body that only the host's physics moves. Nothing hidden: a player's own place. The wire bounds a snapshot's avatars by `WireSchema.MAX_AVATARS`, today `MAX_PLAYERS - 1` (15, "a snapshot never holds the viewer's own avatar"), and the codec refuses a map past it on both ends: in a full 16-player match a knocked-down player's snapshot would be refused for the whole knockdown. So `MAX_AVATARS` becomes `MAX_PLAYERS` (16) with its comment, and the cap holds at the declared maximum: 16 avatars take about 725 bytes of the 1024 (45 bytes each with its key; today 15 take 680, pinned in `wire_schema_test.gd`). It changes ARCHITECTURE §5's "nobody gets their own avatar" and §4.3.5's `Snapshot` row, and the protocol number goes up with it: an older client would draw itself as a stranger |
| **KE6** | The revive | `revive` sends a `Correction` (a new epoch, the body's rest point), as a respawn does | Today it sends none, because a raised client claimed where it lay. A knocked-down client now claims no place, so without one it would stand up where its last walking claim was. The revive becomes a placement: `ScenarioBot`, which fails any `Correction` outside one, expects it, and the honest-bot check stays as strict (728a) |
| **KE7** | The ragdoll | Looks only, on each client: every knocked-down avatar (the own included) and every body is a ragdoll whose root is held to the host's point by a spring each physics step (`_integrate_forces` of a `PhysicalBone3D` or a `RigidBody3D`), and moved there at once when farther than a snap distance (a client constant). Its parts are on the `downed` layer and collide with the world layer only: never with players, another ragdoll or a client-only object (#688's car). On today's placeholder avatar (a capsule, on every map) it is one `RigidBody3D` capsule; with #522's character, the skeleton's `PhysicalBone3D`s under a `PhysicalBoneSimulator3D`. It starts from the standing pose with the avatar's velocity. Nothing reads it: the raise's reach, the camera, the ears and `SightHider` use the host's point. It makes no sound; a later impact or landing sound plays only within the hearing range around the listener's ears (the M4 ADR's §3, item 10, E33 as amended), so a body thrown or rolling off a roof is not heard through walls on every client | Prevents: two screens disagreeing on where a body is by more than its limbs, and a pose that feeds back into what the client shows (the render checklist's item 1). The host's body (KE13) is the truth; the ragdoll only follows it. Each Godot name is checked in 4.7.2's API |
| **KE8** | The camera and the ears of a moving body | `DownedCamera`'s pivot, for its own knocked-down player and for a spectator watching a knocked-down target alike (ARCHITECTURE §4.7.9), rises from the body's point by the standing eye height, but never higher than the standing eye height above the floor below the point (a ray down the client's own level), so a body in flight or falling off a ledge lifts it no higher than a player standing under the body would see; and it stops 0.1 m (a placeholder) below the first world hit straight above it; the arm and `SightHider` work from it as today. The ears stay at the body's lying head height above the point (today's "the own body's head") | Prevents: a body flying up against a ceiling, or lying under a low one, lifting the pivot into the room above (the render checklist's item 3: never through the level), and a body in mid-air showing its player, or a dead spectator, over a fence or onto the locked roof (item 3: never over cover more than standing at the body). Today a body lies only where a player stood, so the eye height always fitted |
| **KE9** | The launch's direction | Horizontal, from the attacker's feet towards the victim's (both last accepted positions); when they coincide, the horizontal part of the facing the strike aims with (the Use's own `facing`, else the last accepted claim's, as `Strike` picks it for `Swung`); when that has none, straight up only | Prevents: the direction resting on a claimed facing (harmless, but a glancing swing would launch a body sideways) |
| **KE10** | Voice and the mic | No change: `VoiceRule.speakers_of` drops every speaker who is not living, `VoiceSender.may_speak_of` sends nothing unless the own life is living, and #489's mic, once built, shows off while downed. The tests that pin the first two stay (ARCHITECTURE §6.3) | Prevents: a second mute path (a knocked-down check inside a voice rule) that a mode's data could route around |
| **KE11** | The code's name | `PlayerState.Life.DOWNED`, the wire's `downed` and the tests keep their names; players read "knocked down" ("You're down", #497's planned `downed.title`) | The engineer's "no downed state" is about the game (no wounded state that crawls), not an identifier. A rename touches about 160 files and the wire's flag for no change in behaviour |
| **KE12** | How the launch and the host's body play on the House alone (the engineer's answer: not on the flat greybox), while the base mode keeps both maps and the knife is one item on both | (a) one list in the mode's data: `PlayerRules.motion_maps`, the paths of the mode's maps on which a knockdown launches a body and the host simulates it, empty (the class default) for every map, the shape of `TaskType.maps` (the Generator ADR's GE15 (a), its issue G8). `knock_down` compares the match's map (`MatchState.map`) with it: on a map it does not list a knockdown takes no launch, whatever the strike's numbers, and starts no host body, so it is today's knockdown (§4, step 2). The mode check refuses a listed path that is not one of the mode's maps, as G8's does. The base mode lists the House alone from 728b on, where the field arrives, before any launch has a number (728e); (b) a mode of its own for the House; (c) the numbers in the House's scene (a node or metadata the host reads with the markers); (d) a list on each `Strike`; (e) as (a), with an empty list meaning no map | **(a)**: the data says where bodies move, read the same way as where a task type plays, so the next House-only mechanic follows one pattern. It prevents the knife's launch numbers, which live in `content/items/knife.tres` and travel with the knife to every map, moving bodies on the greybox: the base mode's first map, where every scenario, the chaos run and the perf run play. (b) fails as GE15 (d) does: the client loads one mode (`Game.MODE_PATH`), so a second needs a mode choice in the lobby and splits the settings a host knows. (c) puts a game rule in a level scene, which the humans lay out by hand, outside the content API and the mode check's bounds. (d) puts an answer about the map on every weapon: a new weapon without its list would launch on the greybox, and the host's body, which every knockdown on a listed map starts, would follow another list than the launch. (e) keeps a forgotten list from reaching the greybox, but unlike `TaskType.maps`, and every fixture mode would have to list its map; 728e's test that the base mode on the greybox moves no body catches a forgotten list instead. Not dependent on G8: G8 changes the deal and the demands, this changes the life rules |
| **KE13** | The host's body (`server/`, KD10 (A)) | `HostBodies` (`server/`) keeps one rigid body per moving body through `PhysicsServer3D` (`body_create`; `body_set_mode` with `BODY_MODE_RIGID`; `body_add_shape` of a `capsule_shape_create` shape sized by `shape_set_data` to the mode's capsule, `PlayerRules.capsule_radius_m` and `capsule_height_m`; `body_set_space`), in the current level's world, the `World3D` that answers `WorldQuery` (ARCHITECTURE §4.5.9). On `LaunchBody` it starts upright where its player stood, its lowest point at the origin (the player's feet, so its centre half its height above them; `body_set_state` with `BODY_STATE_TRANSFORM`) and its height the player's own at the knockdown (the crouched height once #727 lands), with the launch as its velocity (`BODY_STATE_LINEAR_VELOCITY`) and a topple as its spin (`BODY_STATE_ANGULAR_VELOCITY`): `PlayerRules.topple_radps` (a placeholder, "not a decision") about the horizontal axis across the fall's direction, the launch's horizontal direction, else the horizontal facing KE9 falls back to, else any fixed one, so it falls over away from the blow, and falls over with a launch of 0 too; it is on the `downed` layer with the world mask only (`body_set_collision_layer`, `body_set_collision_mask`), with continuous collision detection (`body_set_enable_continuous_collision_detection`), and moves under the engine's gravity, mass, friction and bounce. On `StopBody`, a level change or the host's end it frees the body (`free_rid`). Whether a `World3D.new()` space steps its rigid bodies as the physics frames run is unproven: 728b probes it first, as 3c probed the first query, and if it does not, `server/` sets the space active (`PhysicsServer3D.space_set_active`). Each Godot name is checked in 4.7.2's API | Upright, because its player's capsule stood there, and at its feet with its own height: prevents a body started lying across a wall its player stood beside, a capsule centred on the feet starting half inside the floor, or a full-height capsule of a crouched player starting inside the low ceiling over it, each of which the solver would push out through the wall, the floor or the ceiling. The topple: a linear velocity alone gives a capsule no spin, so without it an upright capsule on a flat floor stays standing, and a body knocked down with no launch (every one in 728b) at the top of the stairs never rolls down them. The world mask only: prevents a body resting on a player or a client-only object (#688's car) only one side knows, since the host's space holds neither. Continuous collision: prevents a launch tunnelling through a thin floor or the parapet. The engine's own gravity and materials: "a rigid body with normal physics", and no numbers to agree on until a playtest asks |
| **KE14** | How the body's place reaches `core/` and the filtered views | In each host step that runs step 4 (ARCHITECTURE §4.5.3), `server/` puts one `BodyMoved(peer, epoch, position, velocity)` for each body it simulates at the head of that step's batch, so it is stamped with t, the tick the batch runs, and applied before every network command stamped t, those carried over from an earlier step included; step 1's catch-up ticks get no report (the host's physics did not run through the freeze either). The reports go in peer-id order, each naming the epoch its `LaunchBody` named (`HostBodies` keeps it with the body, so `server/` reads no `core/` state, and a report of a body freed after a give-up cannot pass for one of the same player's next knockdown), the capsule's lowest point (its centre lowered by its half extent along the vertical, so upright or lying it is where the body touches the floor) and its linear velocity (`body_get_state`). It is a command `server/` originates, as `PeerConnected` is: it goes into the command log (ARCHITECTURE §3.3), and no message type carries it, so no peer can send one. `core/` takes it only for a body in motion whose epoch it names, and only finite: it sets `PlayerState.position` and `velocity`, which every rule reads as today (the raise's reach and sight, the voice distance, a respawn marker's free radius, the car's footprint) and the snapshot carries to everyone, and through KE5 to its own player. A report that is not finite ends the motion at the fallback, with an error. A replay reads the reports from the log, runs no physics and ignores `LaunchBody` and `StopBody` | Prevents: a rule reading a point the host's physics has left; a replay that diverges because physics ran again; a peer forging a body's place; and a raise taken in the same tick against an older point than the snapshot shows |
| **KE15** | When the body rests | `core/` decides, from the reports, counting in core ticks: once the newest report is slower than the rest speed and the rest time has passed since the tick of the last faster one (or of the knockdown), or when the motion reaches the longest motion (counted by `LifeTicks`), the motion ends. Both count ticks, not reports, so a freeze's catch-up ticks, which bring no report, move both clocks alike. The point becomes `floor_below` of the reported point, lifted as `Items.lifted` lifts a point (logged), else the fallback with an error (§4, step 6); the velocity is zero, and `core/` emits `StopBody(peer)`. The rest speed, the rest time and the longest motion are `PlayerRules` numbers with bounds, placeholders marked "not a decision" (KD9 (b)) | Prevents: "when is a tumbling body at rest" becoming a game rule in `server/` or in the engine's sleep thresholds (project settings, outside the mode's data and its bounds), and a body rocking on an edge, or a host whose reports stop, keeping a body unraisable for its whole knockdown |

### 4. The body's motion (KE1 (b) and KD10 (A); KD1, KD2, KD4 and KD8 (a), the engineer's)

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
   body that topples at the top of the stairs, KE13, rolls down them by itself): `knock_down` asks once for the fallback
   rest, `floor_below` of the last accepted position (logged like every answer), keeps the motion (KE3), and emits
   the directive `LaunchBody(peer, epoch, origin, velocity)`, the epoch being the knockdown's (the one its `Correction`
   names and the motion keeps, KE3) and the origin the last accepted position. A directive has
   the audience *server* and reaches no peer (ARCHITECTURE §4.2). `KnockedDown(peer, position)` names the origin, and
   its `Correction` (a new epoch) still drops the walking claims in flight. Until the first report the point is the
   origin and the velocity the launch (`knock_down` sets both), so the knockdown tick's snapshot starts each ragdoll
   (KE7) moving the way the host's body starts.
3. **The host's body** (KE13). `server/` starts a rigid capsule upright where the player stood, with the launch as its
   velocity and a topple that tips it over away from the blow, colliding with the world only. Each physics frame the engine moves it: it flies, lands, rolls, slides,
   and falls off whatever the level's colliders give it, a roof's edge, a ledge, the balcony or the stairs. It
   passes through players, living or knocked down, and through every other body, as the crawling downed did (vision
   revision 1).
4. **The reports** (KE14). Each core tick `server/` reports the body's lowest point and velocity in `BodyMoved`;
   `core/` sets the point and the velocity, which the snapshot carries.
5. **The rest** (KE15). Once the reports stay slower than the rest speed for the rest time, the motion ends: the
   point is the floor below the last reported point, the velocity zero, and `StopBody` lets `server/` free the body.
   No event: the snapshot shows the position and velocity to everyone, as for any avatar. A body at rest never moves
   again: a later blow skips it (KD1 (a)).
6. **No floor** (launched off the map's edge or into a hole): the reports fall on until the longest motion ends the
   motion; with no floor below its point the body rests at the fallback, and the match logs an error (a level with a
   hole), as the throwing design's TD11 (a) does for an item.
7. **The longest motion** (data): a motion still running then ends as at rest (step 5), at the floor below its point
   or at the fallback.

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
TD5). A body that rests where no player can stand keeps its items there once it dies. House's check that no throw
reaches the locked roof (#646) gets a launched body beside it (728e).

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
- **Others:** a ragdoll held to the interpolated point (KE7). The raise hint casts as today; its ray may meet a limb,
  and the reach is measured to the point.
- **The revive:** the `Correction` places the player (KE6); the ragdoll ends and the standing avatar returns (KD7 (a)).
- **The HUD** (#497, #489, both open, not built): its planned down, down-holding and raise states fit as drawn. No
  movement hint exists to remove, its planned "You're down" (`downed.title`) reads as a knockdown, and its mic is to
  show off.

| Design | Where it meets the knockdown | Here |
|---|---|---|
| The crouch (#727) | a knocked-down player cannot crouch | its claims' crouch is ignored (KE4), and a knockdown ends a crouch. A revive under something lower than a standing player (the raised car) follows #727's rule for standing up under a low ceiling (its open question 2); recommended there: the player stays crouched until it fits |
| Car repair (#688, PR #709) | the drop kills the knocked-down under the car (RD7) | by the body's point at the drop's tick, moving or at rest. The raised car is not in the host's world (RE8), so the host's body launched at it passes under or through it; the ragdoll collides with the world layer only (KE7), so no screen rests it on a car the host's body is under |
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
| It comes to rest on the parapet or a railing | it rests on top, where the physics holds it, and can be raised there from within reach | a body snapped to a floor it never reached |
| Two bodies land on one spot | both lie there; the host's bodies and the ragdolls pass through each other | a pile that differs on each screen |
| A `Raise` while the body moves | `Rejected(moving)` (KD4 (a)) | a raise of a body that leaves reach a tick later |
| A give-up or the time running out during the motion | the body lies on the floor below where it is (KD8 (a)); `StopBody` frees the host's body | items dropped away from their body |
| A leave during the motion | no body; the items drop on the floor below its point; `StopBody` | items hanging in the air, and a host body nobody owns |
| The round ends during the motion | the body moves on and rests by the reports; the reset clears it and frees the host's body | a host body left in the next match's space |
| The host's frames drop under load | its physics runs slower against the clock; the reports and the longest motion (in core ticks) still bound the motion | a body unraisable for its whole knockdown |
| A replay of the match | the reports come from the log; no physics runs | a replay that rests a body elsewhere |
| A knocked-down client claims a walk (an old build or a hostile peer) | nothing moves; no `Correction` (KE4) | a crawl the engineer ruled out |
| A knocked-down client sends voice | the host routes none (the invariant); an honest client sends none | a voice from a body |
| A body rolls under the raised car when it drops | it dies (RD7) | a body that survives under the car on one screen |
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
  toward both; no floor (the fallback and its error); a death, a give-up and a leave during a motion, each emitting
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
  ledge, a ramp, stairs, a wall and a hole, through `HostBodies` and a `Match` on a fixture mode that lists it: a body
  launched off the ledge rests on the floor below, one on the ramp rolls or slides to its foot, one knocked down
  with no launch at the top of the stairs topples and ends lower on them or at their foot, one knocked down with no
  launch on a flat floor ends lying (its capsule's axis near horizontal), one crouched under a low fixture ceiling
  starts below it, one launched at the wall rests on its near side, and one over
  the hole ends at the longest motion with the fallback and its error; each waits real physics frames and asserts
  where the body may rest (on a floor, inside the level, within the longest motion), never an exact point. A
  `StopBody`, a death and a level change free the host's body.
- Chaos and bots: a knocked-down hostile peer's walking claims (its rows, ARCHITECTURE §4.6.5.3);
  `dissident_kills_the_crew` loses "and it crawls": a knocked-down bot's `WalkTo` fails the step, as a dead bot's does.
  No scenario, chaos run or perf run plays the launch or the host's body: they play the greybox, where no body moves
  (KE12), and bots do not play the House (ARCHITECTURE §9.7).
- The House, by integration tests in the host's world of the map (`LevelWorld`, `HostWorldQuery` and `HostBodies`, as
  `tests/integration/levels/house_markers_test.gd` builds the first two; 728e): the base mode's knife launches there,
  each body coming to rest on a floor within the longest motion, and none on the locked roof (beside #646's throw
  check); and the base mode on the greybox starts no host body, whatever the knife's numbers.
- The client, over the loopback: a knocked-down joiner holding the move keys stays where the host has it with 0
  `Correction`s; launched, its camera follows its own avatar and stops under a low ceiling; the ragdoll's root stays
  within the snap distance of the point every frame; a revived joiner stands at the host's point.
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
No question is open.

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
  `LaunchBody` and `StopBody` (audience *server*); `HostBodies` in `server/` (KE13), with the probe of §9 first; the
  command `BodyMoved` that `server/` originates and logs (KE14), never decodable from the network; the rest, the no
  floor and the longest motion in `core/` (KE15, §4's steps 5 to 7); `TargetDowned` rejects `moving`; KD8 in `die`;
  `leave` and `ResetMatch` clear the motion; the own avatar in a knocked-down viewer's snapshot
  (KE5), with `WireSchema.MAX_AVATARS` raised to `MAX_PLAYERS` and a test that a full match's knocked-down viewer
  gets its 16-avatar snapshot, the own-avatar check of §9 (from the life state, not from `for_peer`) in `LeakCheck`
  and `ScenarioInvariants`, seen failing on both plants, §9's run of the invariants through a motion, and the
  protocol number, and the client's `AvatarViews` and the bots' fold skipping it until 728d draws it, so no client
  draws itself as a stranger in between; `ChaosOracle`'s reason table gains `moving`; on a map `motion_maps` leaves
  out a knockdown is today's, step for step (§4, step 2). Where bodies move (KE12): `PlayerRules.motion_maps`,
  compared with `MatchState.map` in `knock_down`, the mode check refusing a path that is not one of the mode's maps,
  and the base mode listing the House alone from this issue on, so no later change can give the greybox a launch by
  leaving the list out; the rest speed, the rest time, the longest motion and the topple (KE13) in `PlayerRules`
  with their bounds, set
  in the base mode and the fixture modes as placeholders marked "not a decision" (KD9 (b)); §9's unit tests and the
  host's-body integration tests on a fixture level. 728b ships with every launch at 0 (the knife sets none) until
  728d draws the motion: before it, a launched player's camera and ears would stay where the knockdown started while
  every other screen showed the body fly, and its client's voice cutoff (E41) would measure from the wrong place.
  With no launch the host's capsule topples where its player stood (KE13) and rests, unless the floor there sends it
  on (the stairs), so on the House a knockdown then holds a raise back about the rest time. ARCHITECTURE: §1's `server/` row (it simulates knocked-down bodies on the maps
  `motion_maps` lists); §3.3's replay (`BodyMoved` among the commands `server/` originates); §4.2's directives
  (`LaunchBody`, `StopBody`); §4.5.3 (the reports at the head of step 4's batch, stamped t, none in step 1's catch-up); §4.5.9 (the level's world holds the bodies); §5
  (the per-peer rule, and its "Widening" bullet: a knockdown now widens its own player's snapshot by its avatar);
  §4.6.2 (the bots' fold skips the own avatar); §4.6.4 (the leak test's list of invariants: the own-avatar check)
  and §4.6.4.1 (its two plants, seen failing); §4.1's `Raise` row and §9.5.13's rejection list (`moving`); §4.2's
  `KnockedDown` row and its `Swapped` row ("its avatar is never sent to it"); §4.3.1's bound ("the snapshot's
  avatars at most 15: never the viewer's own"); §4.3.5's `Snapshot` row ("16 avatars: 725" for "15 avatars: 680");
  §4.4's "the snapshot's 15 avatars take 680 bytes"; §4.6.1.1 and §4.6.1.2 ("the own player's never arrives");
  §4.7.8 ("since the own avatar never arrives"); §9.4's `Strike` row (its launch fields, 0 launching nothing, and
  their bounds), its `TargetDowned` row and §9.4.5's `LifeTicks` row (the longest motion and the no-floor error);
  §9.5.1's `PlayerRules` (the rest's numbers, the longest motion, `motion_maps`: the House); §7.1.18. Depends on:
  728a; KE1 (b), KE5, KD1, KD2, KD4, KD8, KD10 (all answered). Not on the throwing issues: the host's physics needs
  neither their sweep nor their arc. Files: `core/life/`, `core/combat/strike.gd`, `core/content/player_rules.gd`,
  `core/match/player_state.gd`, `core/match/snapshots.gd`, `core/match/reset_match.gd`,
  `core/match/phases/join_rules.gd` (`PROTOCOL_VERSION`), a new `server/host_bodies.gd`, `server/host_session.gd`,
  `server/level_world.gd`, `net/messages/wire_schema.gd` (`MAX_AVATARS`),
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
  of each in mid-flight; dead bodies keep the pose, greyed, with the cross (KD7); the revive returns the standing
  avatar; `RemotePlayerBody`'s lying pose and `LifeLooks`' lying capsule go; the render checklist's items 1, 3 and 5
  hold; the tests and the `shot` of §9; ARCHITECTURE §4.7.9. Depends on: 728b; KD6, KD7. Files:
  `client/player/remote_player_body.gd`, `client/player/life_looks.gd`, a new `client/player/ragdoll_view.gd`,
  `client/world/avatar_views.gd`, `client/world/body_views.gd`, `client/life/life_view.gd`,
  `client/life/downed_camera.gd`, `client/life/ears.gd`, `client/dev/life_preview.tscn`, `tests/integration/client/`,
  `docs/ARCHITECTURE.md`.
- **728e content: the launch on the House, its integration tests and the playtest** (size S). Goal: on the House a
  knife knockdown launches the body, and the host's physics rolls it off what it lands on; the greybox moves no body.
  Acceptance: the knife's `launch_mps` and `launch_up_mps` (`content/items/knife.tres`), placeholders the agents
  pick, marked "not a decision" (KD9 (b)), provisional under the MVP content ADR for the engineer's approval in its
  PR; `motion_maps` still the House alone (KE12, from 728b). Integration tests on the House in the host's world
  (`LevelWorld`, `HostWorldQuery` and `HostBodies`, as `house_markers_test.gd` builds the first two), since bots do
  not play the House (ARCHITECTURE §9.7): a knife launch in each direction from a sample of places players stand (the
  yard, the terrace, the balcony, the top of the stairs) rests the body on a floor within the longest motion; beside
  #646's roof check, no knife launch from where players stand rests a body on the locked roof; and the base mode on
  the greybox starts no host body with these numbers (a knife knockdown there is today's, step for step). Each test
  asserts where a body may rest, never an exact point (KE1 (b)). No bot scenario: the scenarios, the chaos run and
  the perf run play the greybox, where nothing moves, and stay as they are. The playtest's list, on the House (KD2,
  KD6, KD10 (A)). ARCHITECTURE §9.5.6 (the knife's launch). Depends on: 728b, 728d (the first non-zero launch in the
  base mode needs the own avatar's camera and ears to follow the body), #646. Files: `content/items/knife.tres`,
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

## Alternatives

- **A ragdoll free on each client** (no host motion): the body rolls off the roof on one screen only, and a raise
  fails at a body the raiser stands over (Context).
- **`core/` moving the body** (KE1 (a), this design's first recommendation, with a slide rule for steep floors, KD3
  (a), and a slope answer, KE2), **or the victim's client** (KE1 (c)): the engineer chose the host's physics (KD10
  (A), KE1 (b)).
- **The engine's sleep as the rest:** its thresholds are project settings, outside the mode's data and its bounds
  (KE15).
- **The host's body started lying:** it can start across a wall its player stood beside (KE13).
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
  later House-only mechanic follows the same shape.
- 728b no longer waits on the throwing issues #641 and #642: the host's physics needs neither the sweep nor the arc.
- The playtest on the House tunes the launch and the rest; the bounds keep a forgotten number out.
