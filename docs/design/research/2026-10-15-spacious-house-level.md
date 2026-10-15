# Making the House feel spacious, connected and fun to move through

*Research for "My Alien Prime Friends", round 2. This is research, not a decision. Tags: [V] verified at the source, [P] a player or press opinion, [A] my analysis. A [V] marked "(snippet)" comes only from a search-result summary, because the page itself refused the fetch.*

## 0. Method, confidence and what this builds on

I made about 48 web searches and fetches, plus local reads of the repo. Several sources refused the fetch: the Epic Games Store news page, Valve's developer wiki, Stevivor and Playnews (HTTP 403). Facts from those come from search summaries and are marked as snippets. I could not verify LOCKDOWN Protocol's map layout at all: its Steam page and every search gave nothing about rooms, vents or how its voice behaves near walls. I also could not get an official Behaviour (Dead by Daylight) statement on map philosophy; only patch notes and the fan wiki.

**Round 1 already covers** spawn camping and capsule protection (`docs/design/research/2026-10-15-death-respawn.md` §5 and §8, risk 1: "Known fixed capsules plus open knowledge is a spawn-camping recipe"). Proximity-voice comedy is in `2026-10-15-meta-and-voice-chaos.md` Part B. This report does not repeat them. It looks at the geometry around those systems.

**Facts about our game that shape everything below:**
- [V] Round voice is pure distance. `core/voice/round_voice.gd:3` says a listener hears a speaker "within `living_m`". `content/modes/base_mode.tres:350` sets `living_m = 8.0`. Nothing in `core/voice/` looks at walls, so walls do not cut voice today. The topic's premise "walls cut voice; open spaces carry it" is false for the current build. Section 6 treats that as a choice to make.
- [V] Movement (`content/modes/base_mode.tres:383-407`): walk 4.5 m/s, sprint 7.0 m/s, stamina 100, sprint costs 20/s, regen 15/s, sprint needs 20 to start, jump 1.0 m (costs 10), crouch 1.2 m at 2.0 m/s, knockdown 10 s, respawn 30 s, invulnerable 3 s. From full stamina a sprint lasts 100 / 20 = 5 s [A].
- [V] `docs/design/house-map.md` §3: the plot is 80 x 60 m and the house 24 x 20 m on two floors, plus a basement and an attic. The plot's diagonal is 22.2 s walking. Upstairs, rooms are 8 x 10 m, 8 x 8 m and 8 x 4 m (§4). §8 calls the boiler room, pump room, switch room, darkroom, attic and the spot under the car "intended dead ends ... That is the tension: who comes in after you?"
- [A] I could not find the audit behind "7 loops and 12 dead ends" in the repo (`grep` of `docs/` for "dead-end rooms", "laundry chute" and "trellis": no matches). I take its numbers as given.

---

## 1. What level-design writing says about loops, circulation and flow

### 1.1 Circulation and lanes
- [V] The Level Design Book defines circulation as "the in-between space that connects other areas, like hallways, aisles, and stairs". It splits it into *diegetic* circulation (how a resident would plausibly move) and *formal* circulation (the abstract function of the space for movement and conflict). Formal circulation matters most in multiplayer. It says most maps use 1 to 3 lanes, and "too many lanes or no clear hierarchy makes a map feel like a maze, and players get lost and miss each other". ([circulation](https://book.leveldesignbook.com/process/layout/flow/circulation))
- [V] The same page notes that wider passages read as primary and narrower ones as secondary. It also notes a large garage door may read as a locked vehicle entrance, so the small door beside it becomes the likely route. ([circulation](https://book.leveldesignbook.com/process/layout/flow/circulation))
- [A] For us: the House needs a visible primary ring (the hallway, the main stairs, the landing, the kitchen) and clearly *secondary* routes (a crawl duct, a trellis, a chute). Then a new player learns the house in one match and a veteran still finds edges. Eighteen loops of equal weight would be the "maze" failure.

### 1.2 Loops, and how many
- [V] Critical Points: loops let players "move around one another and position effectively". Popular Counter-Strike maps overlay about three large loops with smaller loops between them. Too many paths create what Quake players call "guess maps", where any angle can hide an attacker. de_dust2 has "no absolute chokepoints", while de_dust's middle "is more like a chokepoint". ([critpoints](https://critpoints.net/2018/02/18/good-fps-map-design/))
- [V] (snippet) Valve's wiki says cs_italy has three main routes joined by a central crossing route, which recreates a "four-square" pattern. ([Valve wiki](https://developer.valvesoftware.com/wiki/How_to_Develop_a_Map_That_Works))
- [V] Joris Dormans' cyclic generation for *Unexplored* builds levels from loops instead of a start-to-goal path with branches. It gives fewer dead ends and less backtracking, and the layouts "feel less artificial, almost natural". The main loop's two arcs can be two alternative routes, a lock and key, or a "lake" whose shore is the loop. ([Game Developer](https://www.gamedeveloper.com/design/unexplored-s-secret-cyclic-dungeon-generation-), [Boris the Brave](https://www.boristhebrave.com/2021/04/10/dungeon-generation-in-unexplored/))
- [V] The Level Design Book warns about loopbacks: "Overly convenient loopbacks can feel like contrived shortcuts that plead for the player's gratitude." ([typology](https://book.leveldesignbook.com/process/layout/typology))
- [A] For us: the right figure is not "as many loops as possible". Aim for 2 or 3 big rings that span floors, with small rings inside each floor. Going from 7 to 18 loops is mostly about the small ones. Each new opening should either (a) give a room its second exit or (b) shorten a ring that is too long, and the playtest should be able to say which.

### 1.3 Dead ends
- [V] Emil Glans, "On Flow": "Flow should rarely be broken, meaning that the flow should not lead to a dead end most of the time", and dead ends "are okay if they are leading to something else". ([Game Developer](https://www.gamedeveloper.com/design/on-flow))
- [V] (snippet) A multiplayer level-design article: dead ends are "rare in multiplayer environments, because multiplayer levels rely on a strong, looping flow". A dead end can still work as a deliberate trap, for example a strong item at its end. ([filmstories](https://filmstories.co.uk/features/the-essential-techniques-for-great-multiplayer-level-design/))
- [V] The R.E.P.O. Difficulty Editor mod documents the vanilla generator: extraction points sit in *outer rooms with one entrance*, rooms with four connections appear inside the map, and rooms with one to three connections go on the edges. That is third-party mod documentation, not Semiwork's. ([Thunderstore](https://thunderstore.io/c/repo/p/CbIPOK_Studio/Difficulty_Editor/))
- [A] For us: our dead ends are intentional (house-map §8), but the pillars changed after that note was written. A trapped player who dies waits 30 s, which is exactly the "long wait" the "never boring" pillar forbids. The useful middle ground is a **dead end with a one-way escape**. You enter by one door, so "who comes in after you?" survives. But you can always leave by a drop, a chute or a window that the chaser cannot use quickly in reverse. Section 7, option D develops this.

### 1.4 Verticality
- [V] The Level Design Book: "Most maps tend to max-out at three different floor planes for any given area". One-way drops stop backtracking and "commit players"; dropping is easier than climbing, so downward flow "feels heavier". ([verticality](https://book.leveldesignbook.com/process/layout/flow/verticality))
- [V] (snippet) Movement devices change fights: lifts and doors create stalls and surprises, and "ladders leave players vulnerable when climbing". ([filmstories](https://filmstories.co.uk/features/the-essential-techniques-for-great-multiplayer-level-design/))
- [V] IO Interactive's Torbjørn Christensen describes Sapienza and Hokkaido as "snail" spirals that "wrap around themselves, with their layers interconnected with slopes and stairways". The levels feel larger than they are, and the player is never forced to backtrack. ([80.lv](https://80.lv/articles/the-snail-structure-of-hitmans-levels))
- [A] For us: the House has four levels (-1 to 2), but any one *area* should show at most three planes at once, for example the hallway floor, a gallery and the landing. The balcony-to-roof ladder and the trellis are slow climbs where a climber is exposed. That is good risk and reward, but only if the bottom of each climb can be seen from somewhere, so the risk can be read.

---

## 2. Chase geometry: what makes running around a room fun

This matters more for us than for most social-deduction games, because a respawned player is back in 30 s and often in a chase at once.

### 2.1 Dead by Daylight: loops are tuned objects
- [V] The fan wiki's window rules: after a survivor vaults the same window three times in one chase, the window is blocked *for that survivor only* for 30 s; others and the killer can still use it. Vaulting it again within 30 s of the unblock blocks it after one vault. The vault counter keeps rising for 5 s after the killer loses the survivor. ([DBD wiki, Window](https://deadbydaylight.wiki.gg/wiki/Window))
- [V] Vault speeds: a fast vault takes 0.5 s, needs a 2.5 m run-up, keeps momentum and is *loud*. A medium vault takes 0.9 s, a slow one 1.5 s and *quiet*. The killer vaults in 1.7 s. ([DBD wiki, Window](https://deadbydaylight.wiki.gg/wiki/Window))
- [V] Bloodlust was added mainly against "infinites": windows whose surrounding geometry let survivors loop forever. ([DBD wiki, Bloodlust](https://deadbydaylight.wiki.gg/wiki/Status_HUD/Bloodlust))
- [V] Patch notes treat loops as numbers to tune:
  - 3.1.0 (Badham): loop safety ratings adjusted; minimum distance between pallets lowered to 8 m ([SixthAxis](https://www.thesixthaxis.com/?p=340637)).
  - 3.5.1 (Treatment Theatre): window loops in large rooms weakened and pallet loops strengthened to compensate ([GameRevolution](https://www.gamerevolution.com/?p=644759)).
  - 7.3.2 (Shattered Square): pallets raised from about 8 to about 18, and loop safety reduced ([GoNintendo](https://www.gonintendo.com/contents/27882-dead-by-daylight-updated-to-ver-7-3-2)).
- [P] Players call a loop "unsafe" when the killer needs about 1 s to reach the other side. They say a jungle gym's strength "comes from the window", and that loop direction matters. ([BHVR forum](https://forums.bhvr.com/dead-by-daylight/discussion/comment/1205437/), [Steam](https://steamcommunity.com/app/381210/discussions/0/1644292549034761922/))
- **Why it works** [A]: a loop turns a chase from a speed test (micro) into a reading test (macro): which way will he go, when do I break off. The fixed tiles are open knowledge, which fits our pillars.
- **What goes wrong** [A]: when speeds are equal and the geometry is symmetric, a loop never ends. DBD's killer is faster, and it still needed a block rule and Bloodlust.

### 2.2 Our numbers make this worse
[A] Our roles are mechanically identical, so chaser and chased have the same 7 m/s sprint, the same 5 s of stamina and the same 4.5 m/s walk. Around a furniture island, neither can ever close the gap. Take an island with a 16 m perimeter (an example size): at a 7 m/s sprint a lap takes about 2.3 s, at a walk about 3.6 s, forever. That can be funny once, but it is boring the fourth time. The chase needs **asymmetry from the geometry, not from the roles**:
- doors that cost time to open but not to slam shut;
- vaults that cost the leader a little time but cost the follower more (the follower lands where the leader can see him);
- one-way drops;
- stamina-heavy climbs;
- the third party: someone else in the room.

### 2.3 Phasmophobia: kitchen islands and the "too good" loop
- [V] Kinetic Games' rework of 6 Tanglewood Drive (3 March 2026): "the looping spot has indeed been removed from the kitchen area", but "there's still excellent locations within the walls ... to loop your ghost". They "keep the core design of the house as familiar as possible". ([Kinetic Games](https://kineticgames.co.uk/news/6-tanglewood-drive-rework-release-date-announcement))
- [V] (snippet) The rework adds a train set on a central basement table that creates a new loop, plus a new hiding spot under the stairs. ([KeenGamer](https://www.keengamer.com/articles/guides/phasmophobia-6-tanglewood-drive-rework-guide/))
- [V] (snippet) Edgefield and Ridgeview are listed as small maps with 16 rooms on three floors. Edgefield is "very tight and congested", Ridgeview "much less claustrophobic". ([Dot Esports](https://dotesports.com/phasmophobia/news/all-maps-in-phasmophobia))
- [P] Players loop ghosts around kitchen islands and picnic tables, and crouch at a table's short end to break line of sight. ([Steam](https://steamcommunity.com/app/739630/discussions/0/595135660380175591), [Phasmophobia wiki](https://phasmophobia.fandom.com/wiki/Camp_Woodwind))
- [A] Lesson: a suburban house with about 16 rooms naturally contains furniture islands. The designer's job is to decide *which* islands are loops, and to make sure no single one is the best answer. Kinetic moved the loop from the kitchen to the basement rather than delete looping.

---

## 3. Social-deduction and hide-and-seek maps

### 3.1 Among Us: size, chokepoints and how fragile a map is
- [V] (snippet, quoting Innersloth's Tamayo) The Airship was their largest map. As a map grows "it also reduces the opportunities for [players] to run into one another or to be spotted". "The Fungle is probably about 80% the size of The Airship." Its Mountain is reachable only through "chokepoints", a zipline and two ladders, which is "good for cornering". Moving one vent forced rechecks of tasks, sabotages and abilities. ([Epic Games Store](https://store.epicgames.com/news/among-us-welcomes-us-to-the-fungle-update-play-the-new-map-now))
- [V] (snippet) The Skeld's 14 vents form "small, localized vent networks" that keep impostors from jumping across the whole map. Storage has three doors an impostor can sabotage, and MedBay's only exit can be closed. ([allthings.how](https://allthings.how/every-among-us-map-explained-vents-cameras-and-kill-zones/), [Among Us wiki via BreezeWiki](https://breezewiki.discard.no/among-us/wiki/Storage))
- [A] For us: (1) Density beats area. For 4 players the House may be too big; for 10 it may be right. A host-side setting that closes a wing would let one map serve both (option E). (2) A hidden fast network must be *local*, a few linked points per zone, never a map-wide teleport, or chases have no geography. (3) Expect one change to ripple: every new opening changes task and sabotage timing, so re-measure after each one (section 5).

### 3.2 Goose Goose Duck: comedy through one-way transport
- [V] (snippet) Mallard Manor has tasks inside the manor and in its grounds. A guide says a flushing toilet can flush a hiding player out into the lake. On the Basement map, transporters drop you in a random spot. Nexus Colony has two buildings with teleports between them. Sources contradict each other on vents. ([gamerjournalist](https://gamerjournalist.com/all-maps-in-goose-goose-duck/), [MuMu](https://www.mumuplayer.com/blog/goose-goose-duck-list-of-maps.html), [Twinfinite](https://twinfinite.net/guides/how-many-maps-goose-duck-duck-answered/))
- [A] Lesson: an absurd one-way transport (a toilet into a lake) is a "randomness is fun" device that also works as an escape. Our proposed laundry chute is the same family. Its comedy comes from where it lands: visible, noisy, slightly humiliating, but safe.

### 3.3 Project Winter: fixed hubs with two ways in
- [V] (snippet) The Cabin map puts the cabin on the northernmost, elevated tile, with "only two ways to get to and from it – the gondola or a narrow ramp". Traitors can sabotage the gondola. Blizzards force players together. ([PC Invasion](https://www.pcinvasion.com/?p=259220), [Epic store](https://store.epicgames.com/p/project-winter-3b9e84))
- [A] Lesson: two entries, one fast and sabotageable, one slow and safe, is a clean risk-and-reward pair. It maps directly onto our two basement entrances.

### 3.4 Rainbow Six Siege's House: a house map that grew on purpose
- [V] Early prototype: a player blew open the floor above the garage to make an "island", then ran out the clock behind shields. The team concluded it needed safeguards. ([Trusted Reviews](https://www.trustedreviews.com/news/cant-blow-floors-rainbow-six-siege-cheesy-move-blame-3660587))
- [V] The 2020 rework added "an entirely new section on the South side, with two rooms on each floor and a staircase to connect them". It cut North-side sightlines (main door blocked, a shuttered window replaced by a hallway) and made most floors breakable for "vertical play". ([Gfinity](https://www.gfinityesports.com/article/rainbow-six-siege-house-map-rework-operation-steel-wave))
- [V] Ubisoft's rework philosophy: give players rotation options so they "are not funneling through a single choke point". ([Ubisoft](https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/5jByh7fv1VJuvR3cwx2XmB/map-rework-philosophy))
- [A] Lesson: the professional fix for a cramped house was a **second staircase plus a new wing on each floor**, not more doors. Our upper floor has one inside stair and an outside stair. A second inside link between floors (the proposed gallery, or a back stair from the kitchen) is the change most likely to make the house feel "connected".

### 3.5 Hello Neighbor, Prop Hunt, Meccha Chameleon
- [V] (snippet) Hello Neighbor's AI "learns your tactics"; if you keep climbing through the same window, it eventually puts a bear trap there. An alpha preview called the house deliberately absurd (a windmill, rooms on stilts, a roller coaster). ([Wikipedia summary](https://simple.wikipedia.com/wiki/Hello_Neighbor), [GamingTrend](https://gamingtrend.com/previews/a-creepy-day-in-the-neighborhood-hello-neighbor-alpha/))
- [V] (snippet) A Garry's Mod Prop Hunt map's changelog shows typical fixes: props that got hiders stuck made static, hiding spots hunters cannot reach fixed, spawn points raised from 16 to 32. ([Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/changelog/534693586?l=spanish))
- [V] Meccha Chameleon (released 10 June 2026, by lemorion_1224): hiders paint a white body to blend into the stage, for 2 to 10 players. GamingOnLinux reported 7 million sold and a 24-hour peak of 340,534 concurrent players; much of its life is Workshop maps. ([GamingOnLinux](http://www.gamingonlinux.com/2026/06/meccha-chameleon-is-a-hide-and-seek-body-painting-game-taking-over-steam)) Sales are third-party figures, right in order of magnitude only.
- [A] Lessons:
  - A repeated route can be *answered by the world*. In our game that answer could come from players, not AI: an alien who sees everyone use the trellis can set a trap there.
  - Every hiding spot must be reachable by seekers, and must not trap the hider in geometry.
  - Hide-and-seek runs on dense, legible clutter. The attic "full of old things" (house-map decision 11) is our version.

### 3.6 LOCKDOWN Protocol
- [V] A first-person social deduction game by Mirage Creative Lab for up to 16 players: early access 22 July 2024, release 18 November 2025. ([Steam](https://store.steampowered.com/app/2780980/LOCKDOWN_Protocol/))
- [P] (snippet) A reply in a Steam thread says the team plans to finish its map ("always planned to be 2 stories") and make another one. ([Steam](https://steamcommunity.com/app/2780980/discussions/0/603021022325687469))
- **Not verified:** its layout, vents, and whether walls affect its voice.

---

## 4. Immersive sims: one building, many routes

- [V] Dishonored 2's Clockwork Mansion:
  - Level design director Christophe Carrier: "making sure the player wouldn't be lost was one of the biggest challenges".
  - The team avoided "long, tight passages that loop around the walls", since those confused players most.
  - Backstage spaces were "visually tied to the main rooms" so players sensed where they were.
  - Rooms have recognisable real-world functions; the kitchen sits under the dining room and a lift raises the table.
  
  ([Game Developer](https://www.gamedeveloper.com/design/level-design-deep-dive-i-dishonored-2-s-i-clockwork-mansion))
- [V] (snippet) Thief's Lord Bafford's Manor covers three floors plus vaults, a cellar and the streets around it. The front gate is guarded and slow; a sewer reaches the basement storerooms; a secret passage runs from the rooftop gardens to the throne room. ([Thief wiki](https://thief.fandom.com/wiki/Lord_Bafford%27s_Manor_(mission)), [walkthrough](https://www.gamerevolution.com/guides/30016-thief-the-dark-project))
- [V] (snippet) Deus Ex: a building "may have had three or more different ways of moving in and out of it". Human Revolution's level designer Steven Ciciola calls "multi-path, multi-solution" the top rule. ([game-wisdom](https://game-wisdom.com/series/design-encyclopedia-d-deus-ex), [PlayStation Blog](https://blog.playstation.com/?p=43045))
- [V] (snippet) Prey's Talos I is continuous, with unlockable shortcuts and exterior routes between interior sections; a reviewer said backtracking still caused friction. ([Wikipedia](https://en.wikipedia.org/wiki/Prey_(2017_video_game)), [Checkpoint](https://checkpointgaming.net/reviews/2017/05/prey-review/))
- [A] Lessons for "a hidden alien layer behind a normal home":
  1. The hidden layer must be **spatially tied** to the normal rooms: glimpses through grilles, the same wallpaper on the back of a panel, a window into the kitchen. Then a player inside it never loses the mental map.
  2. Avoid long, narrow passages that wrap around the walls. Short hops between two known rooms are better.
  3. Real room functions give free wayfinding. Even the alien layer should look *functional* as a party machine: pipes carrying punch, speaker cables, a disco-ball motor. Not abstract corridors.
  4. Roughly three ways in and out of the house per side is the immersive-sim norm. Thief's front, sewer and roof map one to one onto our hallway, basement and roof.

---

## 5. Making small spaces read big

- [V] Architecture advice for small houses (Matthew James Taylor):
  - "Extra headroom can make a small room feel bigger without increasing the floor area";
  - "When you see beyond the walls, you can feel less enclosed by them";
  - large glass doors make the outside feel part of the room;
  - "Every square foot of hallway that you eliminate becomes part of another room";
  - include at least one generously sized area: "A small house should never feel claustrophobic".
  
  ([source](https://matthewjamestaylor.com/small-house-design-principles))
- [V] (snippet) A lower entry that opens into a taller room gives a reveal. Double-height voids and see-through floors let viewers "look up and through". Rooms staggered around a central void "promote diagonal visual communication". ([Homestyler](https://www.homestyler.com/article/doubleheight-living-room-design), [Dwell](https://www.dwell.com/collection/new-mit-media-lab-opens-doors-4b4f3879/6133490305728385024))
- [V] Kevin Lynch's five elements of a mental map are paths, edges, districts, nodes and landmarks. A Wellesley study of open-world games confirmed only some of them in players' accounts (2 of 5 in its poster, with 3 full participants: not conclusive). ([Wellesley paper](https://cs.wellesley.edu/~pmwh/mvmap/papers/open_world_elements/open_world_elements.html), [poster](https://cs.wellesley.edu/~pmwh/mvmap/posters/open_world_elements/IOOW_Poster.pdf))
- [V] Paul Martin measured stealth levels with isovist area and a "visibility/accessibility discrepancy": a place you can see but not reach. ([Nottingham](https://eprints.nottingham.ac.uk/47734))

**[A] Applied to a house of 24 x 20 m, technique by technique:**
- **Double height:** one void over the hallway (the proposed gallery). It is the single strongest "big" cue. It also links planes 0 and 1 visually and creates a place you can see but not reach, which is Martin's discrepancy: a player on the gallery sees the hallway, but must take a route down.
- **Sightlines past the walls:** glass doors and low windows from the living and dining rooms to the garden. Every inside room on the ground floor should have at least one view out, so the plot (80 x 60 m) feels like part of the house. A view across a room into a second room (two doors in a line) also doubles perceived depth.
- **Interior and exterior linked:** low vaultable windows turn each ground-floor room into a pass-through. The 16 m-wide garden ring becomes part of the house's circulation instead of a separate map.
- **Minimise hallways:** our landing is 8 x 20 m (house-map §4), a long corridor with rooms off one side. An opening between two side rooms (bedroom to kids' room, study to bathroom to guest room) turns a comb into a ring without new square metres.
- **One generous room per floor:** on the ground floor the living room fills this role. Upstairs nothing does yet. The gallery, or a bedroom opened to the balcony, could.
- **Landmarks per floor and per district:** each floor needs one object seen from far away. Examples, all placeholders: an absurd alien party device visible through the gallery, the grill's smoke from the yard, a lit sign in the basement. Rooms also need different light colours, so that a player who respawns at a random capsule knows in under a second where he is. That is the "fun from the first second" pillar applied to respawns.
- **Compression and release:** a low duct or stair (1.2 m crouch) that opens into the double-height hall gives a reveal on every pass, at no cost.

---

## 6. Proximity voice and layout

- [V] Our current rule (section 0): 8 m, distance only. In the House an 8 m radius reaches through one or two walls into the next rooms, since upstairs rooms are 8 m wide (house-map §4). So today the layout barely shapes who hears whom; only distance does. house-map §10 already asks whether stations "far apart on the plan are also apart to the ear".
- [V] (snippet) BetterCrewLink, the Among Us proximity mod, lists "walls block audio" and "hear people in vision only" among its options. The original CrewLink let players hear "even through walls". ([npm](https://www.npmjs.org/package/bettercrewlink-rhdev), [Business Insider](https://businessinsider.nl/how-to-install-the-among-us-proximity-chat-mod-and-make-your-games-even-more-suspenseful))
- [V] (snippet) Third-party voice tools muffle by material (glass, wood, concrete) with volume loss plus a low-pass filter. They use a cone of several rays with hysteresis so audio does not flicker at doorways, and compute occlusion on each client with no network sync. ([Unreal forum](https://forums.unrealengine.com/t/del-studio-easy-proximity-voice-chat-epvc/2743973), [booth.pm Audio Trace](https://booth.pm/en/items/8566260))
- [P] A Steam Audio user found the default occlusion far too strong ("nearly every material made sound inaudible"). ([Steam](https://steamcommunity.com/app/596420/discussions/0/2530372519568287315))
- [P] (snippet) Lethal Company players like "hearing team mates in the distance, through walls". I found no source on whether it occludes. ([Steam](https://steamcommunity.com/app/1966720/discussions/0/4032472470675813770/?ctp=2))
- [V] Godot 4.7.2's API dump has `attenuation_filter_cutoff_hz` and `attenuation_filter_db`, as well as `reverb_bus_*` and `area_mask` properties (`tools/out/godot-api/4.7.2/extension_api.json`, grep). So a listener-side muffle is buildable without an addon.
- [A] Architecture invariant 6 splits voice in two. *Who hears whom* is a `core/` rule. *How it sounds* (spatialization) happens on the listener. That gives three layers:
  - **Cosmetic muffle** on the listener: doors and walls lower the volume and filter the sound, but the speaker is still heard. No core change; layout gains feel but no rules.
  - **A core rule** in which walls shrink the radius: closed doors make private rooms, the open-plan ground floor is a "party zone" where voice carries. Layout becomes voice design. It needs geometry queries in core (`core/items/in_sight.gd` already checks walls between an eye and an item, so the ground exists). It touches the per-peer filtering invariant, which is an architecture boundary and needs the engineer's word.
  - **Leave it as is**, and use distance alone, by placing loud and quiet zones far apart.
- [A] How layout and voice interact either way:
  - Open-plan spaces where many paths cross are where mixed chatter happens, and comedy needs that. Put them on the ground floor, around the kitchen and living room.
  - Quiet task dead ends (switches more than 8 m apart, house-map decision 8) are where a human can whisper to another or sabotage unheard.
  - The double-height hallway becomes the house's "voice well": shout from the gallery and the hallway hears. A cheap, legible vantage for calling out chases.

---

## 7. Measuring flow

- [V] Bungie published Halo 3 heatmaps in November 2007: kills and deaths from thousands of matches drawn over the maps ("the darker the red, the more frequent the deaths"), filterable by weapon. ([Cool Infographics](https://www.coolinfographics.com/blog/2009/1/12/halo-3-heatmaps.html), [Gigazine](https://gigazine.net/gsc_news/en/20071114_halo3_heatmaps/))
- [V] Left 4 Dead's "flow" is a number on each nav area: its distance from the start toward the goal, which the AI uses to tell who is ahead or behind. Designers inspect it with `z_show_flow_distance`, and broken connections show as -9999. ([Valve wiki](https://developer.valvesoftware.com/wiki/Sorting_out_navigation_flow))
- [V] Space-syntax measures of game levels: integration (how central a space is), connectivity (direct links) and depth distance, applied to a "Haunted House" test game; changing room size changed the measures and the number of spawn points. ([METU](https://avesis.metu.edu.tr/publication/details/568c5026-3dfe-457e-b84a-0a417e8b6d2f/developing-a-space-syntax-based-evaluation-method-for-procedurally-generated-game-levels))
- [V] The Level Design Book's playtesting chapter:
  - basic stats need only notes: play time, deaths, win rates, time to reach a point;
  - Rob Meyer used telemetry charts to spot "clumping that might be unhealthy" in a 20-person test;
  - Valve held a weekly Friday playtest with an outsider;
  - Adriaan de Jongh warns of "evil data".
  
  ([playtesting](https://book.leveldesignbook.com/process/blockout/playtesting))

**[A] A measurement kit fitted to our pillars.** All thresholds below are placeholders for the engineer.

| Metric | How | What "good" might look like (placeholder) |
|---|---|---|
| Independent loops | The room graph's cyclomatic number E − V + 1 (rooms as nodes, openings as edges), per floor and in total | Every floor ≥ 2; the whole house ≥ 2 rings that span floors |
| Dead ends | Rooms with exactly one two-way exit; a one-way escape (a chute, a drop) counts as an exit | Only rooms whose task *needs* tension, each with a one-way escape |
| Time-to-cross | Bots sprint and walk between each pair of capsules and stations (we have bots, AGENT_WORKFLOW `bots`) | No capsule more than ~15 s walking from the nearest task |
| Chase length | From the first hit to a knockdown or a lost contact, logged on the host | A median of seconds, not minutes; no spot where chases never end |
| Position heatmap | Host-side sampling of every player each second, drawn over the floor plan SVGs | No room unvisited across 5 matches; no room holding > 30% of player-time |
| Voice overlap | Per-second count of hearing pairs (from `core/voice/`) | Open zones busy, task rooms quiet |
| Respawn-to-action | Seconds from leaving a capsule to the next task contact, encounter or point | Short; this is the "never boring" check |

Two things matter most [A]. **Time-to-cross per capsule** is the direct test of the 30 s respawn pillar. **Heatmap clumping** shows whether 18 loops actually spread 10 players, or whether everyone still runs the kitchen.

---

## 8. Mapping to the House

**[A] A reason for every room** (illustrative; the content belongs to the engineer):

| Room type in our House | Reason it can carry | Pattern from above |
|---|---|---|
| Kitchen, living room (open plan) | A party hub: busy voice, crossings, a furniture island to circle | Arena with central cover; Siege's rotations |
| Hallway + gallery | Vantage and voice well; the double-height "big" cue | Double-height void; see but not reach |
| Bedrooms, kids' room | A trellis entry from outside; a hiding spot; a link between side rooms that turns the comb into a ring | Small loops; prospect and refuge |
| Bathroom → boiler room chute | One-way escape and comedy landing | Downward flow; a GGD-style absurd transport |
| Switch, pump, boiler rooms | A quiet task dead end, each with a one-way escape | A dead end "leading to something" |
| Attic | Hide-and-seek clutter; a second ladder makes it a pass-through | Prop Hunt reachability lessons |
| Roof | A lookout over the yard (decision 11); a slow, exposed climb | Ladders are vulnerable |
| Garage | Two speeds of entry (the gates vs the side door), a one-shot hazard | Project Winter's fast-and-risky vs slow-and-safe |
| Basement storage | The hub with two far-apart entries (house-map §8) | Fixed hub, two ways in |

**Chases after a respawn** [A]. A respawned player gets 3 s of invulnerability (`invulnerable_s = 3.0`). At 7 m/s that is about 21 m: enough to leave one room only if the capsule room has **two exits that point to different rings**. A capsule in a dead end turns those 3 s into a delay before the same kill.

**Hiding and sabotage** [A]:
- Sabotage needs a place where you are briefly unseen, plus an exit that does not cross the room you came from. A loop through the room gives both.
- The alien hidden layer (ducts, a chute, panels) is open knowledge. Humans know it exists, so the deduction pillar is untouched. The point is that it is faster to move through but noisier, or more exposed at its ends.

**Capsules** [A]. Round 1's camping risk becomes a set of layout rules. Each capsule:
- sits in a room with ≥ 2 exits;
- is not visible from another capsule;
- is not in a room with a station;
- has one on every level (5 or 6 over four levels plus the yard);
- is at least a placeholder distance from the nearest station, so a spawn is never a free return to the task you were killed at.

---

## Cross-game patterns

1. **Loops are tuned, not counted.** DBD rates loop safety and moves pallets in patches; Phasmophobia moved its best loop out of the kitchen; Siege funnels through no single choke. Professionals keep both the number of loops and how strong each one is under control. [V], see §2 and §3.4.
2. **The fix for a cramped house is a second vertical link and a wing, not more doors.** [V] Siege's rework. [A] For us: the gallery or a back stair.
3. **Hidden networks are local and tied visually to the normal space.** The Skeld's vent groups; Dishonored's backstage seen from the main rooms. [V]
4. **Size cuts encounters; density beats area.** The Airship lesson, and The Fungle at 80% of its size. [V] (snippet)
5. **One-way devices commit players and create comedy.** Drops in shooters, the GGD toilet, random transporters. [V], [V] (snippet)
6. **Two entries of different speed and risk make a place interesting.** Project Winter's gondola vs ramp; Thief's front gate vs sewer. [V] (snippet)
7. **Repeated routes get answered.** DBD blocks a window after 3 vaults; Hello Neighbor sets traps on reused windows. [V]
8. **Map changes ripple.** One Among Us vent forced rechecks of tasks, sabotages and abilities. So measure after each change. [V] (snippet)

## Risks for our design

1. **Equal speeds make loops infinite** (§2.2). With identical roles, a furniture island ends no chase by itself. Without a geometric asymmetry, loops become stalemates, which is boring.
2. **"18 loops" can become a guess map.** Too many equal routes make the house a maze where players "miss each other". The Among Us lesson cuts the same way: fewer encounters, so less comedy.
3. **Intended dead ends now clash with the 30 s respawn** (house-map §8 against the "never boring" pillar).
4. **Walls do not cut voice today.** Any layout argument that relies on rooms being private by sound is false under the current rule (§6).
5. **The alien layer can disorient.** Long hidden passages around walls were Arkane's top cause of lost players.
6. **Capsules in poor rooms are spawn traps,** given round 1's camping risk and only 3 s of invulnerability.
7. **Vault and ladder are new verbs** (none exist yet). Each is engine work, and the vault's timing is a fairness lever that needs tuning, as DBD shows.
8. **One-shot hazards on loop routes:** the dropping car must never sit on a chase ring, or it becomes a cheap kill zone.

## Options for the engineer (all values are placeholders)

**A. "Two rings and a void": the minimum connective set first.** Of the eleven proposed openings, ship first the ones that (1) give every station room a second exit or a one-way escape, (2) add a second link between the ground and upper floor inside the house (the gallery or a back stair), and (3) link the upstairs side rooms. Defer the rest until a heatmap shows the need.
- *For:* fewer greybox changes, and a readable hierarchy (one primary ring, a few secondary ones).
- *Against:* you may undershoot, since 7 loops is the measured starting point; it needs a second pass.

**B. All eleven openings plus the traversal set at once** (vault windows, trellis, ladder, chute, gallery).
- *For:* one greybox pass; the maximum "connected" feeling for the first playtest.
- *Against:* risks the guess map, needs both new verbs (vault, ladder) at once, and makes it hard to tell which change helped.

**C. Chase-breaker geometry, an original set.** Give loops asymmetry without touching roles:
- doors are slow to open (placeholder 0.6 s) but instant to slam;
- a vaultable low window costs the vaulter a short landing stagger, and the same player's next vault through *that* window within a short time (placeholder 10 s) is slower. A personal "the window sticks" cost, not a block;
- one-way drops and the chute.
- *For:* chases end within seconds and stay macro (route reading); it fits identical roles.
- *Against:* engine work on doors and vaults; the timings need playtest tuning.

**D. Dead ends with escape hatches.** Keep the task dead ends (switches, darkroom, attic) for their tension, but give each a one-way exit that lands somewhere visible and a bit silly: a chute, a drop through a window into a hedge, a duct to the garden. Placeholder rule: no room more than one two-way door deep without a one-way exit.
- *For:* keeps "who comes in after you?" and removes the trap.
- *Against:* one-way exits are new geometry per room, and landings must be checked against capsules and camping.

**E. A measurement kit before the redesign.** Add host-side position and voice-pair sampling, a room-graph test (loops, dead ends, depth from each capsule) over the level data, and bot time-to-cross runs. Then run the same 5-match test for 4 and for 10 players.
- *For:* turns "feels spacious" into numbers and catches ripples (pattern 8).
- *Against:* tooling time before visible progress.
- *Variant:* a host setting that closes one wing for 4 to 5 players, if the 4-player heatmap is sparse.

**F. Voice that respects walls.** Either a listener-side muffle (cosmetic, no architecture change) or a `core/` rule in which walls and closed doors shrink the radius (layout becomes voice design; an architecture boundary).
- *For:* the House's rooms start to *sound* like rooms, and the open ground floor becomes the party zone.
- *Against:* the core version is a boundary change and costs per-pair geometry queries on the host; muffling must be tuned not to silence everything (the Steam Audio complaint).

**Recommendation [A]:** E first, because it is small and every other option needs it. Then A with D in the greybox, then C once the first chases are on record. Decide F separately: the listener-side muffle is cheap and low-risk; the core rule is a bigger call.

## Open questions for the engineer

1. Should walls and doors affect voice at all, and if so cosmetically on the listener or as a `core/` rule (option F)?
2. Can players open, close or lock doors during a round? Doors are the cheapest chase breaker, but also a camping tool.
3. Vault and ladder: both, one, or neither in the next milestone? And may a vault be slower for a follower than for the leader?
4. Do the intended task dead ends stay, now that death costs 30 s? If so, does each get a one-way escape (option D)?
5. Is the alien hidden layer open knowledge from match one (my reading of the pillars), or something players discover?
6. Capsule rules: one per level? Never in a station room? A minimum distance to the nearest station?
7. Is 80 x 60 m right for both 4 and 10 players, or should the host be able to close a wing?
8. How many vantage points (the roof, the gallery) is too many for "open knowledge" without making hiding impossible?
9. What does a "good" match look like in numbers (chase length, respawn-to-action, heatmap spread), so the playtest has a pass mark?

---

### Sources (all cited inline above)
Level Design Book ([layout](https://book.leveldesignbook.com/process/layout), [circulation](https://book.leveldesignbook.com/process/layout/flow/circulation), [verticality](https://book.leveldesignbook.com/process/layout/flow/verticality), [typology](https://book.leveldesignbook.com/process/layout/typology), [playtesting](https://book.leveldesignbook.com/process/blockout/playtesting)) · [Critical Points](https://critpoints.net/2018/02/18/good-fps-map-design/) · [On Flow](https://www.gamedeveloper.com/design/on-flow) · [Unexplored cyclic generation](https://www.gamedeveloper.com/design/unexplored-s-secret-cyclic-dungeon-generation-) · [Boris the Brave](https://www.boristhebrave.com/2021/04/10/dungeon-generation-in-unexplored/) · [Clockwork Mansion deep dive](https://www.gamedeveloper.com/design/level-design-deep-dive-i-dishonored-2-s-i-clockwork-mansion) · [Hitman snail structure](https://80.lv/articles/the-snail-structure-of-hitmans-levels) · [GDC Holistic Level Design](https://gdcvault.com/play/1024301/Level-Design-Workshop-An-Approach) · [DBD Window](https://deadbydaylight.wiki.gg/wiki/Window) · [DBD Bloodlust](https://deadbydaylight.wiki.gg/wiki/Status_HUD/Bloodlust) · [Kinetic Games Tanglewood](https://kineticgames.co.uk/news/6-tanglewood-drive-rework-release-date-announcement) · [Ubisoft rework philosophy](https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/5jByh7fv1VJuvR3cwx2XmB/map-rework-philosophy) · [Gfinity House rework](https://www.gfinityesports.com/article/rainbow-six-siege-house-map-rework-operation-steel-wave) · [Trusted Reviews Siege floors](https://www.trustedreviews.com/news/cant-blow-floors-rainbow-six-siege-cheesy-move-blame-3660587) · [Epic: The Fungle](https://store.epicgames.com/news/among-us-welcomes-us-to-the-fungle-update-play-the-new-map-now) · [LOCKDOWN Protocol Steam](https://store.steampowered.com/app/2780980/LOCKDOWN_Protocol/) · [GamingOnLinux Meccha Chameleon](http://www.gamingonlinux.com/2026/06/meccha-chameleon-is-a-hide-and-seek-body-painting-game-taking-over-steam) · [Small house principles](https://matthewjamestaylor.com/small-house-design-principles) · [Wellesley Lynch study](https://cs.wellesley.edu/~pmwh/mvmap/papers/open_world_elements/open_world_elements.html) · [Martin, Splinter Cell spatial analysis](https://eprints.nottingham.ac.uk/47734) · [METU space syntax](https://avesis.metu.edu.tr/publication/details/568c5026-3dfe-457e-b84a-0a417e8b6d2f/developing-a-space-syntax-based-evaluation-method-for-procedurally-generated-game-levels) · [Halo 3 heatmaps](https://www.coolinfographics.com/blog/2009/1/12/halo-3-heatmaps.html) · [L4D nav flow](https://developer.valvesoftware.com/wiki/Sorting_out_navigation_flow) · the other snippet sources as linked in the text.

Local sources: `core/voice/round_voice.gd`, `content/modes/base_mode.tres`, `docs/design/house-map.md`, `docs/design/research/2026-10-15-death-respawn.md`, `tools/out/godot-api/4.7.2/extension_api.json`.