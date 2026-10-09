# Throwing held items (#37): the flight in `core/`, and the engineer's questions

- **Status:** Proposed on 2026-10-09 for the engineer's review on the design PR. Nothing here is built. The TD items
  are his (game rules and taste: the [trust ADR](2026-10-04-trust-based-autonomy-gated-merge-into-main.md)'s tier
  (c), "ask and wait"), and no task is opened on a TD item before his answer; the TE items are technical, and each
  recommendation stands until he says otherwise. TE1 is his too, because it revises what two accepted ADRs sketched
  for #37. Where a technical choice also decides what players see (bounces, a running throw, where an item with no
  floor rests, the downed in the way), that part is a TD item of its own (TD9 to TD12), and the TE item only follows it.
- **Date:** 2026-10-09
- **Deciders:** the engineer (TD1 to TD12, TE1); designed by the agent of #37 in the meta manager session's M7 design
  workflow, started on the engineer's word (#302, his answer 3 of 2026-10-09)
- **Builds on:** [MVP rules](2026-09-29-mvp-rules.md) (Items; Tasks: a package counts when it "rests inside its
  circle, however it got there"), [content API v0](2026-09-29-content-api-v0.md) and
  [the match loop](2026-09-29-match-loop-intents-events-and-entitlement.md) (their sketch of #37),
  [wire format and the host session](2026-09-30-wire-format-and-host-session.md) (E3: the snapshot holds avatars
  only), [vision revision 1](2026-10-01-vision-revision-1.md) (two hands, the pillars), and the engineer's answer on
  PR #82, item 5, recorded on #37: when a throw lands, its rest is the item's base point on the floor it rests on, as
  `WorldQuery.rest_position` gives for a put-down, not its centre of mass.
- **Revises, if TE1 (a) is taken:** the sketch in the content API v0 ADR's Consequences and in the match-loop ADR's
  list of extensions: "`server/` simulates the flight and reports `ItemRested`". Each has a dated note pointing here.
- **Numbering:** TD1 to TD12 and TE1 to TE7 are this ADR's own: #36 and #73 are designed at the same time, and
  continuing the M6 ADR's E61 and D24 would collide. The proposed issues are 37a to 37f.

## Context

**What exists.** `PutDown(facing)` (ARCHITECTURE §7.1.12): the client sends only its facing, and the host places
the hand item 1 m in front (a placeholder), from the eye, stopped 0.2 m before a wall and dropped to the floor. Every
rest raises the fact `item_rested`, on which Delivery checks the package's circle whatever the cause
(ARCHITECTURE §7.1.14; `Delivery.on_fact` reads no cause). The rest position is the one point `core/` knows of an
item: the centre of its base on the surface it rests on.

**What the accepted ADRs sketched** (ARCHITECTURE §9.8): a new intent `Throw(facing)`, because a throw is a verb for
every item while `Use` is the item's own action (the knife strikes); a flying state in `MatchState`; a public
`ItemThrown`; and `server/` simulating the flight in its physics and reporting `ItemRested`, a command it originates
and the command log keeps (ARCHITECTURE §3.3). They left two things to #37: how clients show the flight, since `core/`
would not know an item's position in flight, and whether an impact does anything ("Damage on impact needs an impact
fact").

**The host's physics today** (ARCHITECTURE §4.5.9): one `World3D` per level holding only the level's static
colliders (layer 1, `world`), built through `PhysicsServer3D` and asked through `World3D.direct_space_state`. No
player capsule and no item is in it. Godot 4.7.2's `PhysicsServer3D` has no call that steps one space: there is no
`space_step` (checked against `tools/out/godot-api/4.7.2/extension_api.json`; only the extension class's virtual
`_step` exists). The engine steps the active spaces once per physics frame, 60 Hz here (`project.godot` keeps the
default), while `core/` ticks at 20 Hz from the host's clock.

**What weighs on the rules** (GDD §1, §3): the pillar "macro skill over micro skill", with no aim-heavy mechanics
(kept by the amendment of 2026-10-08 in vision revision 1, which allows only rare one-shot moments); a cringe-fun,
chaotic vibe; and the base mode's sabotage, which is hiding packages. The first map, House (GDD §13,
[its design](../design/house-map.md), #591), has a balcony over a terrace, a roof behind a door that is always locked
(its decision 11: a key or a lockpick opens it, and neither is in the MVP) and an attic to hide items in: places a
throw reaches and a put-down does not.

## Decision (proposed)

### The engineer's questions (TD)
None of these is decided here. The design below follows each recommendation where it can be reverted; no number and
no key is proposed.

| Item | Question | Options | Recommendation, and the failure it prevents |
|---|---|---|---|
| **TD1** | Throw strength and range | (a) one launch speed per rule; the camera's pitch aims, so the range follows from the speed and the pitch (on flat ground at most about v²/g, at 45°); (b) hold the key to charge, up to a highest speed; (c) a speed per item kind, through TD2 (b) | **(a)**: one press, and an arc the thrower can foresee. (b) adds a timing skill and a charge field in the intent that the host must clamp. The numbers (the speed, the arc's gravity, the item's radius for collisions, the longest flight) are the engineer's; the build gives each the bound that refuses a forgotten value, as every part has |
| **TD2** | Which items can be thrown | (a) every item alike: one `Throw` rule on the mode; (b) a rule per item kind (the package slower than the knife, say), which ARCHITECTURE §9.2's order (the hand item's rule first, then the role's, then the mode's) already allows beside (a); (c) only some kinds: a kind with no rule answers `nothing_to_do`, as `Use` does with a package | **(a)** first, (b) after the playtest if the kinds should differ. One set of numbers to tune |
| **TD3** | What a thrown item does to a living player it meets | (a) nothing: it flies through them; (b) it stops against them and falls at their feet, nothing more; (c) as (b), and `core/` raises a new fact `item_struck` (the item, the player), so a content rule can hurt or slow by data; (d) built-in damage (a thrown knife wounds) | **(b)** now; (c)'s fact with the first rule that uses it (one class, no change to the loop). (a) looks broken (a package flies through a body) and rules out passing a package to a teammate. Hurting, in (c) or (d), means hitting a moving player with an arc: an aim-heavy mechanic, against the pillar. A stun needs movement modifiers (ARCHITECTURE §10), which do not exist. Whether a downed player stops an item too is TD12 |
| **TD4** | Does a thrown package count when it comes to rest in its circle? | (a) yes, by the rule "rests inside its circle, however it got there"; (b) no: Delivery ignores the cause `thrown`, and someone must pick the package up and put it down there (a package then lies in its circle undone, which the circle must show); (c) yes, only when thrown from within some distance of the circle | **(a)**: one check for every cause, as built. A lob over the railing into a circle is team play more than aim, since a miss costs a walk. (b) and (c) each add a rule every player must learn |
| **TD5** | Where a thrown item may come to rest | A throw reaches what a put-down never does: a high shelf or a roof, out of reach (`InReach` measures the 3D distance from the feet: 2 m), and a pit with no floor. (a) wherever the flight ends; the levels keep every surface a throw can reach within reach of a spot where a player can stand (a level convention in `levels/CLAUDE.md`), and the longest flight (TE3) ends a fall with no floor; (b) as (a), plus level-marked "no rest" volumes (a marker kind): an item that comes to rest in one returns to where its thrower stood when throwing it; (c) the host returns any rest that no standing spot reaches: a reachability search over the level | **(a)** for the first map, **(b)** when a level needs it (House's roof, whose door no MVP item opens, if a throw from the yard or the balcony reaches it). Prevents: a dissident throwing a package where nobody can ever reach it, which settles the match with one throw, since the crew can then never finish. (c) costs a search per landing and an answer to "where can a player stand" that the host does not have |
| **TD6** | What a throw costs | (a) nothing: the next throw needs a pick-up within reach first; (b) stamina, as a knife hit (`StaminaCost`); (c) a cooldown (`Cooldown`) | **(a)**: the pick-up already limits the rate, and one number fewer |
| **TD7** | The key | (a) a new input action `throw` on a key of its own (which key is the engineer's); (b) Q held to throw, tapped to put down; (c) the right mouse button | **(a)**: Q stays an exact put-down; (b) delays every put-down by the hold threshold |
| **TD8** | Catching | (a) no: an item in flight cannot be picked up (`unavailable`, as for a held one); (b) E catches an item in flight within reach | **(a)**: (b) is a reach check against a moving point, timed by the catcher: a micro skill |
| **TD9** | What a thrown item does when it meets the world | (a) stop and drop: the first contact ends the flight and the item drops straight to the floor below it; (b) it bounces off walls and floors (a restitution, data) and rolls to a stop; (c) as (a) for walls, but it slides on along a floor it lands on | **(a)**: the thrower sees where the item lands from the arc alone, so a lob over a railing into a circle is planned, not lucky (the pillar: macro over micro). (b) decides where every package ends by a chain of contacts no player can foresee, can roll a package into or out of a circle, and makes the drawn arcs harder (TE5); it can come later as a setting. (c) needs a friction rule, a number nobody has |
| **TD10** | Does the thrower's own movement add to a throw | (a) no: every throw leaves at the rule's speed, whether the thrower stands or sprints; (b) yes: the thrower's velocity is added, so a running throw goes farther | **(a)**: the range never depends on a velocity the client claims, which the host checks only loosely (ARCHITECTURE §7.1.5), so a hacked client cannot stretch its throws by claiming speed. (b) feels more physical, at the cost of a second bound (the claimed velocity clamped to the sprint speed) and a longer range to keep in mind for TD5 |
| **TD11** | Where an item rests when its flight ends over no floor (thrown off the map's edge, or into a gap in its floor) | (a) back where the thrower stood at the throw; (b) where the flight stopped, in the air, as a drop with no floor does (ARCHITECTURE §7.1.13); (c) at a free item marker of the level (`Items.free_markers`), as at a spawn | **(a)**: the item stays near the thrower, where the crew can find it, and the match logs an error (a level with a hole). (b) leaves a package hanging where nobody can reach it, so the crew can never finish: the failure TD5 guards against. (c) teleports a package across the map, which reads as a bug and can drop it near its own circle |
| **TD12** | Does a downed player stop a thrown item | (a) no: a downed player is flown over; (b) yes, as a living one (TD3) | **(a)**: the downed body's capsule still stands under a lying mesh (ARCHITECTURE §7), so a stop there would look like a hit on empty air above the body. (b) needs a lying capsule for the downed first, which no rule has |

### The technical choices (TE)

| Item | Choice | Options | Recommendation, and the failure it prevents |
|---|---|---|---|
| **TE1** (the engineer's) | Where the flight runs | (a) in `core/`: a ballistic arc swept through `WorldQuery` each core tick, the contacts with players checked in `core/` against the host's positions; (b) `server/` simulates a rigid body in the level's space (Jolt) and reports `ItemRested` (the accepted sketch); (c) the thrower's client simulates and reports where it landed | **(a)**. (b): the engine steps the host's spaces by physics frames, not by core ticks, with no per-space step in 4.7.2, so the same commands can land an item differently on two runs (a flaky bot test; a replay that holds only because the landing is logged) and tests must wait real frames; the space holds no player and no item, so a thrown item passes through players unless `server/` mirrors their capsules; `core/` knows no position in flight, so every contact and every drawing needs more commands from `server/`; and "when is a tumbling item at rest" (a speed threshold, a time) becomes a game rule in `server/`, which ARCHITECTURE §1 gives to `core/`. (c) breaks invariant 1: a hacked client lands a package in its circle from across the map. What (a) gives up: tumbling, bounces and rolling, and a thrown item does not push the items lying on the ground (to `core/` an item is a point). A client may spin the item in flight; that changes nothing |
| **TE2** | The geometry question | A new `WorldQuery` question, `sweep(from: Vector3, to: Vector3, radius: float) -> Vector3`: the farthest point from `from` towards `to` that a sphere of `radius` reaches without touching the world; `to` when nothing is in the way; `from` when the sphere at `from` already touches it. (a) a sphere, which `server/` answers with `PhysicsDirectSpaceState3D.intersect_shape` at `from` (a `PhysicsShapeQueryParameters3D` holding a `SphereShape3D`, mask of layer 1), then `cast_motion`'s safe fraction; (b) a ray, as `rest_position` uses | **(a)**. (b): a point slips through a crack between two wall boxes, or between a door and its frame, which no package could pass. The start check: the 4.7 docs say `cast_motion` ignores a shape the sphere already overlaps, so without it a sphere that starts inside a low ceiling, or a wall the thrower leans on, would fly through it. Its price: a sphere at the eye that touches a wall stops every throw at once, even one away from the wall, so the mode check refuses a throw radius with which the sphere at the eye would stick out of the player's capsule, with a margin: the radius must be at most `min(PlayerRules.capsule_radius_m, capsule_height_m - eye_height_m)` less a named tolerance, `THROW_RADIUS_MARGIN_M`, whose value 37a fixes from its integration tests against Jolt's contact margin (a technical constant, not a game number). An honest capsule pressed against a wall then leaves the sphere clear of it. One case stays: `Items.eye_of` raises the eye from the highest floor under its footprint rays, so a thrower whose capsule rim stands on a step has a host eye up to the step's height above its real capsule; under a low ceiling there (House's attic) the sphere can start in the ceiling and the throw drops at the thrower's feet. Accepted as it is (a throw from the foot of a step under a low ceiling falls short; the thrower steps up and throws again), and tested (TE7). Recorded and replayed like every answer (`RecordingWorldQuery`, `ReplayWorldQuery`); `FlatWorldQuery` answers it on its floor and walls |
| **TE3** | How the flight is computed | Follows TD9 (the rule is the engineer's). Under TD9 (a): a closed-form arc swept segment by segment, ended at the first contact, then one `floor_below`; under TD9 (b): the same, plus the contact normal from one more answer (`get_rest_info`'s `normal`) and a restitution per bounce, and a rest test (a speed under some threshold) | The model below, under TD9 (a): each point computed from the launch, so no error adds up, and a client can compute the same points |
| **TE4** | The intent and how the host validates it | `Throw(facing)` and the rule; below | The host takes only the facing from the client. Prevents: a throw farther than the rule, from somewhere else, or through a wall |
| **TE5** | What clients draw | (a) the thrower's client predicts the arc at the key press; the others draw it from `ItemThrown` on the timeline they draw avatars on; (b) the snapshot carries every item in flight; (c) no prediction | **(a)**, below. (b) breaks E3 (the snapshot holds avatars only, under the 1024-byte unreliable cap) and is still a round trip late for the thrower. (c): the thrower's own item leaves its hand a round trip after the press (over the internet, often 50 to 150 ms), on the one action whose result the player watches |
| **TE6** | The wire and who sees what | Two rows and a cause; below | `ItemThrown` goes to everyone: nothing in it is hidden |
| **TE7** | Tests | Below | Each rule of this design has a test that fails without it |

**The flight (TE3, under TD9 (a)).** On the launch tick L the item leaves the hand into a new state, `ItemState.Where.FLYING`
(appended after `BELT`, so the older values keep theirs), with the origin o (`Items.eye_of(thrower)`) and the velocity v
(the facing, normalized, times the speed). The item's state keeps the flight (o, v, the gravity g, the ticks flown n
and the fallback rest f, below), as `Channels` keeps a raise, and its `position` holds o until it rests. On every later tick a new tick system,
`FlightTicks`, adds one to the flight's own count of flown ticks n and sweeps the segment from p(n−1) to p(n), where
p(n) = o + v·s + ½·g·s², s = `float(n) / Ticks.RATE` in seconds (both are ints, so an integer division would
give s = 0 for the whole first second) and g points straight down. The count is the flight's, not the
host tick less L, so a phase that lists no `FlightTicks` pauses a flight instead of making it jump past a wall when the
next phase resumes it (no base-mode phase does: End freezes it, below). Each point is computed from the launch, never
integrated step by step, so no error adds up; one static function in `core/` computes it, and a client calls the same
one (as it calls `StaminaLedger.simulate_ticks`), so the client's points are the host's. That holds only on the same
inputs: the flight keeps o, v and g exactly as the `Vector3`s `ItemThrown` carries (single precision; g straight down
as a vector, TE6), set once at the launch, and every point is computed from those stored vectors, never again from the
rule's numbers (data floats, which are double). The host's arc is then bit for bit the one every client decodes. The first contact along the
segment ends the flight, whichever comes first: the world's (the sweep's answer, TE2), or a living player's other than
the thrower (TD3 (b); a downed one is flown over, TD12 (a)), tested in `core/` against the `PlayerRules` capsule standing at that player's last accepted
position, widened by the item's radius, with no lag compensation, as for hits (ARCHITECTURE §7.1.10). The item then
drops to `WorldQuery.floor_below` of the stop point lifted (`Items.lifted`) and rests there through `Items.place` with
the cause `thrown`: `ItemPlaced` and `item_rested`, so Delivery runs unchanged. That rest is the base point on the floor
below, as the engineer asked on PR #82. A flight that has not ended within the longest flight (data) stops at its last
point. With no floor below the stop (TD11 (a)), the item rests at the fallback f that the launch fixed, and the match
logs an error: a level with a hole, as for a drop (ARCHITECTURE §7.1.13). f is one more answer, asked once at the
throw: `WorldQuery.floor_below(Items.lifted(feet))` at the thrower's last accepted position, logged like every answer
and kept in the flight. It is not o less the eye height: `Items.eye_of` raises the eye from the highest floor under
its footprint rays, so at a ledge's edge that point keeps the thrower's x and z beside the floor, in the air, and with
no floor at all it is the claimed position itself. With no floor below the thrower either (a jump over a pit, or a
client that walked out through the level's wall, which the host does not check, ARCHITECTURE §7.1.9), the `Throw` is
refused with a new reason, `no_floor`, which names only the thrower's own position, and the item stays in the hand.
Unlike a drop, which rests at the point itself, a throw's fallback goes back to where the thrower stood. Prevents: a
package thrown over the edge of the map, or into a gap in its floor, hanging in the air where nobody can reach it, so
that the crew can never finish; no rest of a throw is ever above no floor. Further:
- `FlightTicks` runs each item in flight in id order. A phase whose rules can throw lists it, or the mode check
  refuses the phase, as for `ChannelTicks`. The base mode's Round would list it after `ChannelTicks`, before
  `TaskTicks` (content, provisional). A landing on the match clock's last tick counts, because tick systems run before
  the clock (ARCHITECTURE §3.3).
- The thrower being knocked down, dying or leaving does not touch the flight: the item is no longer theirs. End
  freezes a flight (it has no `FlightTicks`), and the next match clears every item (`MatchState.reset_match`). A
  client hides an item still in flight when the phase changes, since no `ItemPlaced` will end its arc: the match is
  decided, and an item hanging in the air through End would look like a bug. A later mode that leaves Round and comes
  back to it (the meetings mode, #35) resumes a paused flight, which a client cannot draw from `ItemThrown` alone; that
  mode's design picks a transition action that lands every flight at the phase change, or a row that tells clients the
  ticks flown. The base mode needs neither.
- The cost: one `sweep` per item in flight per core tick (two space queries on the host, TE2, and one answer in the
  command log), for at most the longest flight; a held item is needed for each throw, so at most as many flights as
  items run at once.
- `PickUp` of an item in flight is `unavailable` (`ItemOnGround`). Every reader of `ItemState.where` is checked for
  the new state: `ItemOnGround`, `Items.free_markers`, Delivery, the snapshot's items in `core/` (not on the wire).

**The intent (TE4).** `Throw(facing)`: RELIABLE, `seq` and `facing`, like `PutDown`. The base mode accepts it from the
living in Round; the downed and the dead get `not_accepted`. It joins `Intents.PLAYER_ACTIONS`, so the dead never throw,
not even the host's own player, and the client sends its last claim again as `MoveClaimReliable` right before it
(ARCHITECTURE §7.1.15): a lost claim would otherwise launch the item from where the thrower stood a step earlier. It
spends from the reliable intents' bucket (ARCHITECTURE §4.5.6), so a looping client's throws stay bounded with no new
budget. It goes to the first `Throw` rule of the hand item's kind, the actor's role or the mode (ARCHITECTURE §9.2);
with none, `nothing_to_do`. The rule: `HoldsItem` (`empty_hand`: a belt item is never thrown), TD6's costs if any, and a
new effect, `ThrowItem`, whose settings are the speed, the gravity, the radius and the longest flight (TD1; the radius
moves to `ItemKind` if one mode rule must throw kinds of different sizes). The host takes only the facing from the
client: a non-finite or zero facing takes the last accepted claim's, as `Strike` does. The origin, the speed and the
gravity are the host's, and the thrower's own velocity is not added (TD10 (a)), so the range never depends on a claim. Each
prevents a hacked client's throw: farther than the rule (the speed is data), from somewhere else (the origin is the
host's eye, the floor below the last accepted position plus the eye height, so a jump does not raise it, as for a
put-down), or through a wall (the sweep from the eye, with TE2's start check). An applied `Throw` stops its thrower's
raise, as every action does. Every refusal names only the sender's own facts (`no_floor` among them, TD11). Accepted, as for a put-down: a client that
walked into a wall (the host does not check walls for movement, ARCHITECTURE §7.1.9) throws from inside it.

**What clients draw (TE5 (a)).** At the key press the thrower's client hides its hand item and starts the arc from its
own camera with the rule's numbers (its own copy of the mode, found as `core/` finds the rule); it eases onto the host's
arc when `ItemThrown` arrives, and puts the item back in the hand on a `Rejected`. Until `ItemPlaced` arrives it stops
its drawn arc at the first wall of its own scene (`cast_motion` in its own world: presentation only, which the host
never reads), so an item thrown at a wall a step away is not seen passing through it for a round trip. Every other
client draws the arc from `ItemThrown` on the host-tick timeline it draws the avatars on (ARCHITECTURE §7: behind by the
interpolation delay), so the item leaves the hand as the thrower's body is seen throwing it. `ItemPlaced` with the cause
`thrown` ends the arc. Since `floor_below` keeps x and z, the stop is the arc's point above the rest, found from the
horizontal distance (a throw with no horizontal speed falls to the rest's height); the client holds the rest until its
drawn time reaches the stop, then shows a short fall. A rest that is not below the arc (the no-floor fallback) ends the
arc at once at the rest. The view of an item in flight joins `SightHider.GROUP` as every item view does (ARCHITECTURE
§4.7.10), so the downed camera's arm does not show an arc that the body's eye could not see. Sounds: one at the launch
(an asset the engineer picks, as for #144's sounds) and `ItemPlaced`'s at the rest, once the drawn item gets there.
Both follow the M4 client ADR's §3 checklist: the launch sound goes through `SoundChooser` at the origin, cut beyond
`HEARING_RANGE_M` of the listener and muffled behind the level like every world sound (item 10), and the item in flight
is an ordinary depth-tested `ItemView`, with no trail, outline or `no_depth_test` overlay (item 5). Prevents:
`ItemThrown` reaches everyone with an origin, so an uncut launch sound, or an arc drawn through walls, would tell every
crew client where a dissident just threw a package to hide it, the leak item 10 was written for.

**The wire and who sees what (TE6).** A `Throw` row (C→H, the next free intent kind: RELIABLE, `seq: u32`,
`facing: vec3`) and an `ItemThrown` row (H→C, the next free event kind: `item: item`, `peer: peer`, `origin: vec3`,
`velocity: vec3`, `gravity: vec3`, `tick: tick`, the launch tick). `ItemThrown`'s audience is everyone: the item was
in a hand that everyone sees, and items are public (ARCHITECTURE §5); the velocity gives away the thrower's look, which
the snapshot's facing already shows. The `gravity` field spares a remote client a second copy of the rule lookup; the
thrower's own prediction does that lookup anyway. It is the acceleration as a `vec3` (straight down), not a plain
`f32`: `core/` computes the arc in `Vector3`s, whose components are single precision, so the field round-trips
exactly as E6 needs, while the codec refuses an `f32` field holding a data value such as 0.1, which no single
precision number holds (`WireField._is_plain`). The `Items` causes gain `thrown` (`wire_core_test` pins the list), the
protocol version rises, and the chaos bots cover `Throw` (`ChaosHostile._refused`, `ChaosOracle`). `server/`
originates no new command: ARCHITECTURE §3.3 drops `ItemRested` from its list, and the flight's geometry reaches the
command log as `WorldQuery` answers, as every other rule's does.

**Tests (TE7).** Unit, in `core/`: the arc's points against the formula, p(1) among them (the first tick moves);
the points computed from a decoded `ItemThrown` equal `FlightTicks`' points on every tick of a flight; a stop at a wall, a ceiling, a floor and a
living player; the thrower and a downed player flown through; the rest on the floor below the stop; the longest flight
with and without a floor; a thrower at a ledge's edge whose flight ends over no floor rests the item on the floor
below its feet, never in the air; a `Throw` by a thrower over no floor refused with `no_floor`; a flight paused by a phase without `FlightTicks` resuming where it stopped; a package thrown
into its circle delivered (TD4 (a)) with the cause `thrown`; every refusal, the dead host's own `Throw` among them
(`Intents.PLAYER_ACTIONS`); the mode check (a phase that accepts a throw with no `FlightTicks`, a radius too big for
the capsule); a throw replayed from its log. Integration, in `server/`: `HostWorldQuery.sweep` on the fixture level
`tests/fixtures/levels/wall_ledge_crate.tscn` (the wall, the ledge, the low crate), and on a new fixture level beside
it with a gap narrower than the sphere and a low ceiling (a sweep through the gap stops; one that starts inside the
ceiling answers `from`), and a step under a low ceiling (the sphere at the eye of a capsule pressed against a wall
starts clear of it with the margin; one at the eye `Items.eye_of` gives a thrower at the step's foot answers `from`). Client: the claim's twin sent before a `Throw`; the predicted arc against `core/`'s points; a `sound_chooser_test`
case that plays no launch sound for an `ItemThrown` beyond the hearing range.
Bots: a `Throw(towards, pitch)` step, and a scenario that throws a package into its circle (under TD4 (b): next to it,
then puts it down). The leak test compares `ItemThrown` exactly, as every event; no new invariant is needed, since
nothing in it is hidden. A playtest by a human checks the feel: TD1's numbers and TE5's arcs.

### Proposed issues
The manager opens them after the engineer's answers; the last column is each one's `Size:` line. Each is cut to what an
implementer finishes in about 150 tool calls ([the pipeline v2
ADR](2026-10-02-ai-productivity-baseline-and-pipeline-v2.md)'s task size).

| Issue | What | Depends on | Size |
|---|---|---|---|
| 37a | `core/` and `server/`: `WorldQuery.sweep` in the port, `FlatWorldQuery`, `RecordingWorldQuery`, `ReplayWorldQuery`, the test worlds `tests/fixtures/world/fixture_level_world.gd` and `tests/fixtures/match/fixture_terrain_world.gd` (without their own answer a flight in them would pass through their geometry), and `HostWorldQuery`'s sphere answer with the start check; integration tests on the two fixture levels (TE7); ARCHITECTURE §4.5.9's "The answers" and §7.1.1's list of questions | TE1 (a), TE2 | S |
| 37b | `core/`, the flight: `ItemState.Where.FLYING` and the flight it keeps, the arc's static function, `FlightTicks` with the world and player contacts, the rest through `Items.place` with the new cause `Items.THROWN` and the no-floor fallback, every reader of `where` (`ItemOnGround`, `Items.free_markers`, Delivery, the snapshot's items); the cause added to both lists of causes in `tests/unit/net/messages/wire_core_test.gd` (the id check and `test_the_items_causes_are_every_string_name_constant_of_items`); unit tests that put an item in flight directly | 37a; TD3, TD4, TD8, TD9, TD11, TD12 | M |
| 37c | `core/` and `net/`, the throw: the `Throw` intent in `Intents` and `Intents.PLAYER_ACTIONS`, the `ThrowItem` effect with its bounds, `ItemThrownEvent` (everyone), the mode checks (`FlightTicks` listed, the radius against the capsule); in the same task the wire, since `wire_core_test` requires a row for every intent and a row and a sample for every event a peer receives: `WireSchema`'s `Throw` and `ItemThrown` rows, their samples in `wire_samples.gd`, the protocol bump; ARCHITECTURE §4.1, §4.2, §4.3 and §9.4's rows | 37b; TD1, TD2, TD6, TD10 | M |
| 37d | `client/net/`, the bots: the chaos rows (§4.6.5.3: `ChaosHostile`'s `Throw` shapes, refused as `not_accepted` while no phase accepts it), `ClientModel`'s fold of `ItemThrown`, the claim's twin before `Throw`, the bots' `Throw` step, `ScenarioBot`'s copy of `ItemState.Where` (`tests/harness/scenario_bot.gd`) and its fold of `ItemThrown` and `ItemPlaced` with the cause `thrown` | 37c | M |
| 37e | `client/`: the throw key (TD7), the prediction, the arcs on the avatars' timeline, the stop and the fall, the hide at a phase change, `SightHider`'s group, the sounds' hooks (the launch sound through `SoundChooser`, cut beyond its range; no trail or overlay on the item in flight), a `shot` preview on a fixture mode with a `Throw` rule (the base mode gets its rule only in 37f) | 37d | M |
| 37f | `content/`, `levels/` (the engineer's word, provisional under the MVP-content ADR): the base mode's `Throw` rule with the engineer's numbers, `FlightTicks` in Round, Round's allowlist, with outside `content/` in the same change §3.2's Round row, `ChaosOracle.ACCEPTS` and the hostile's expected outcome for `Throw` in Round (§4.6.5.3: a change of §3.2's table changes them with it, or `bots --chaos` goes red); TD5's level convention in `levels/CLAUDE.md`; a bot scenario that throws a package; then the playtest | 37c, 37d; TD5 and TD1's numbers | S |

Every task leaves `verify --full` green on its own, `tests/unit/net/messages/wire_core_test.gd` among it: that test pins
every intent and peer-bound event to a wire row and a sample, and every `Items` cause to the list it holds, so a task
that adds one of those adds its row, sample or list entry too.

They run in that order, one after another, except the last two: 37e (`client/`) and 37f (`content/`, `levels/`)
touch different folders and can run side by side. If the engineer takes TE1 (b) instead, 37a becomes `server/`'s
simulation (a rigid body per flight in the level's space, positions reported to `core/` as logged commands), 37b
keeps the flying state with `ItemRested` as a command of `server/`'s, and 37e draws the reported positions.

## Needs the engineer
- **TD1 to TD12**, each with the options and the recommendation above. A one-line answer per item is enough, such as
  "TD1 a, TD3 b, the rest as recommended", plus the numbers of TD1 when he has them. TD9 to TD12 are the rule side of
  choices the technical design leans on (bounces, a running throw, the rest with no floor, the downed in the way).
- **TE1**: the flight in `core/` (a), against the accepted sketch's `server/` physics (b). The rest of the TE items
  follow (a); under (b), TE2, TE3 and TE5 change as the last paragraph above says.

## Alternatives
- **A rigid body on the host** (TE1 (b)) and **the client's own simulation** (TE1 (c)): above.
- **Positions in flight as commands from `server/`**, the sketch's first way to show the flight: one logged command per
  item per tick, and a second source of state beside `core/`'s rules. Not needed once `core/` flies the item.
- **A ray** for the sweep (TE2 (b)), **bounces** (TD9 (b)), **positions in the snapshot** (TE5 (b)), **no prediction**
  (TE5 (c)): above.
- **A longer put-down as the throw** (`rest_position` to a point farther away): the item would jump there at once,
  with no arc to watch and no way over a railing, since `rest_position` stops at the first wall in a straight line.
- **The throw as each item's `Use`**: `Use` is the item's own action (the knife strikes), so a knife could not be
  thrown without losing its strike; a new verb for every item is the content API v0 ADR's reason for `Throw`.
- **Adding the thrower's velocity to the throw** (TD10 (b)): above.

## Consequences
- ARCHITECTURE §7.1.16 holds this design's authority rules. §3.3, §7.1.14, §9.2 and §9.8 no longer say that `server/`
  reports a throw's rest from its physics, and §10 lists TD1 to TD12 and TE1. GDD §6 lists the questions.
- The content API gains one intent, one effect, one tick system, one event, one fact cause and one `WorldQuery`
  question, and no change to `Match` or the phase loop. ARCHITECTURE §9.8's row for throwing counts two part classes
  instead of one (the effect, and the flight's tick system) and no simulation in `server/`.
- Whatever the answers, the rest of a throw goes through `Items.place` and `item_rested`, so the delivery check, the
  win check and the drops at a death stay as they are.
