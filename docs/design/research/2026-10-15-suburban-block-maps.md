# The neighbourhood block: how a street of houses becomes a good multiplayer level

*Research for "My Alien Prime Friends", round 3 (level). This is research, not a decision. Tags: [V] verified on the fetched page, [S] from a search summary only (the page refused the fetch or I did not open it), [P] a player or press opinion, [A] my analysis. All numbers for our game are placeholders.*

## 0. Method, and what this builds on

I ran about 55 web searches and fetches, and read the repo. Several key pages refused the fetch: the Hitman and Untitled Goose fandom wikis (HTTP 402), PC Gamer, Liquipedia, Mobalytics, Dot Esports, PCGamesN and Gematsu (403). Facts from those pages are tagged [S]. I found no official sizes in metres for Nuketown or Whittleton Creek. I found no usable Payday suburban layout. Those gaps are marked where they matter.

This report builds on, and does not repeat:
- `docs/design/house-map.md`: the 80 x 60 m plot (4,800 m², or 5,280 m² with the 6 m street), the 24 x 20 m house, the roof lookout (decision 11) and the routes in §7.
- `docs/design/research/2026-10-15-spacious-house-level.md`: loops, chase asymmetry, one-way escapes, the measurement kit, capsule rules, and the Siege House rework.
- `docs/design/m8-match.md` (branch `content/1093-…`, commit 49d435247): capsules (§3), mischief and the cops (§5), and "walls muffle voice" (§8).

Facts from the repo used below: walk 4.5 m/s and sprint 7.0 m/s (`content/modes/base_mode.tres:391-392`), voice 8 m (`:353`), respawn 30 s with 3 s of invulnerability (`:398-399`). Crouch speed (2.0 m/s) and the 5 s sprint are round 2's reading of the same file. [V]

A movement figure used throughout [A]: over runs longer than about 35 m, stamina caps the average speed near 6 m/s. A 100 m run takes about 22 s walking and about 17 s with sprint-walk cycling.

---

## 1. Case studies

### 1.1 Hitman 2, Whittleton Creek: a public party house in a private block
- [V] A guide counts "14 properties". Some can be entered. "The Wilson property hosts a party that is open to everyone". The houses and yards are otherwise private, and entering them needs a disguise. The construction site and the reservoir are off-limits. The creek runs along the east and south edges. ([ludo.guide](https://www.ludo.guide/guide/hitman-world-of-assassination/hitman-world-of-assassination-part-425))
- [V] "A tunnel connects the Janus and Griswold properties" (a challenge, "Tunnel Ducks Rule!"). (same source)
- [S] The fan wiki says the tunnel links the two *basements*, and that the suburb sits "on a single block". ([Hitman wiki](https://hitman.fandom.com/wiki/Whittleton_Creek))
- [V][P] A player explains the second house as a front: "a fake entry for Janus bodyguards to use the tunnels". "The entry doesn't even connect with the shell of the house." Another poster saw "three houses with only exits… that are off the map". ([Steam](https://steamcommunity.com/app/863550/discussions/0/1676938384246808385))
- [V] Other places named in one walkthrough: a tree house used for sniper shots, a shed in a neighbour's garden, and the target's back door "near the river". ([SegmentNext](https://segmentnext.com/2018/11/20/hitman-2-whittleton-creek-walkthrough/))
- [S] The whole neighbourhood is invited to the Wilson barbecue. The barbecue grill is itself a tool a player can use against a target. ([GamesHedge](https://www.gameshedge.com/hitman-2-whittleton-creek-walkthrough-guide-points-interest-disguises/))
- [S] IOI's GDC 2019 talk framed its levels "as social spaces", in effect the social anthropology of level design. ([GDC](https://gdconf.com/news/what-makes-hitman-2-levels-tick-find-out-gdc-2019s-level-design-workshop))

**Lesson [A]:**
- One public hub (the party) sits among private lots, and each private lot has a reason to enter it.
- A neighbour's basement can be a hidden door into another house.
- Some houses are only exits or facades at the edge.
- 14 properties suit one slow stealth player. For 4 to 10 players in 10 minutes, that is far too many.

### 1.2 Call of Duty, Nuketown: two houses and a street
- [V] "Two symmetrical sides divided by a road". Each side has a "brightly colored" two-storey house and an "AstroTurfed" backyard. A school bus and a moving van in the road give cover. Nuketown returned in Black Ops 6 (2024) and Black Ops 7 (2025). ([Wikipedia](https://en.wikipedia.org/wiki/Nuketown))
- [S] An unofficial estimate puts it at "around 1,000 square yards", about 840 m². That is a sixth of our plot. ([whiteclouds](https://www.whiteclouds.com/?p=29456))
- [S][P] Black Ops 6's day-one variant (Warhead) has one house and a sandy area opposite. Its middle cover is "one-laned", with the vehicles head-on rather than parallel. Fans "slammed" it. ([GGRecon](https://ggrecon.com/articles/black-ops-6-new-nuketown-slammed-amid-tiny-map-influx))

**Lesson [A]:**
- The street is the open middle. Big vehicles parked in the road are what make it crossable.
- Taking away one house, or one lane of cover, broke a much-loved map.
- Nuketown is a shooter arena with mirrored halves. That is the opposite of what a party block needs, so treat it only as a lower bound on scale.

### 1.3 Dead by Daylight, Lampkin Lane: a street that had to shrink
- [V] Today's size is 132 sqT, where a tile is 8 x 8 m, so 8,448 m². It was 168 sqT at first, then 152 after patch 5.7.0. Landmarks: the main house, plus two houses across the street. The main house has three ground-floor windows, two entrances, a basement and a balcony. ([DBD wiki](https://deadbydaylight.wiki.gg/wiki/Lampkin_Lane))
- [V] Patch 7.7.0 (23 April 2024): "The map has been difficult for the players to enjoy." Behaviour:
  - shortened the street;
  - added line-of-sight blockers in it;
  - "removed any closed houses" and cut the tile count;
  - added gameplay to the border tiles;
  - added openings in the main house.
  
  ([MP1st](https://mp1st.com/news/dead-by-daylight-update-3-12-for-patch-7-7-0-brings-game-engine-update-and-more))
- [S][P] Before the rework, a player wrote that "there are almost zero obstacles… connecting one side of the street to the other". ([Steam](https://steamcommunity.com/app/381210/discussions/0/3388408347639386960))
- [V] Maps are assembled from tiles of 16 x 16, 16 x 32 or 32 x 32 m, which can rotate between matches. ([DBD wiki, Distances](https://deadbydaylight.wiki.gg/wiki/Distances))
- [S] Behaviour's Springwood post: rules fix the shape and the landmarks, and generic tiles fill the rest, randomly rotated. ([devtrackers](https://devtrackers.gg/deadbydaylight/p/022b01d3-map-update-springwood))

**Lessons [A]:**
1. A street of houses for 5 players settled at about 8,400 m², roughly 1.6 times our plot with its street.
2. A closed house is filler, and the professional fix was to delete it.
3. A wide, empty street is a sightline that needs blockers.
4. Fixed landmarks plus rotating generic pieces is a proven recipe for "same map, new match".

### 1.4 Untitled Goose Game: gardens linked by gags
- [V] Each area starts from a setting ("a pair of back gardens") and a focus, for example "playing two parties against each other". Finished areas are "a patchwork of several different real locations all squished together". ([Game Developer](https://www.gamedeveloper.com/game-platforms/road-to-the-igf-house-house-s-i-untitled-goose-game-i-))
- [V] The areas were designed separately and then joined into one village with "a circular flow". ([ACMI](https://www.acmi.net.au/works/122683--the-world-of-untitled-goose-game/))
- [V] The source places were scouted on Street View; the GDC 2020 talk was "Google Maps, Not Greyboxes". ([GDC](https://gdconf.com/news/come-gdc-and-see-how-untitled-goose-games-levels-were-scouted))
- [V] A speedrun guide's details:
  - a gate between the two back gardens, and a desk drawer that, pulled open, becomes a walkway over the divide;
  - a vase thrown back over the fence by a neighbour;
  - a "little hole in the fence" at the back of the pub, through which items are carried in;
  - "7 minutes to do each area, before the bell rings".
  
  ([gamepretty](https://gamepretty.com/untitled-goose-game-speedrun-task-guide/))
- [S] The garden can be entered through the gate or "via a hole in the bush". The pub is reached by hiding in a delivery box. The model village is reached by swimming under a bridge. ([Nintendo Life](https://nintendolife.com/news/2020/05/guide_untitled_goose_game_walkthrough_-_puzzle_solutions_and_to-do_list_objectives), [PowerPyx](https://www.powerpyx.com/untitled-goose-game-trophy-guide-roadmap/))

**Lesson [A]:**
- The links between lots are themselves jokes and puzzles: a hole, a drawer, a box, a swim.
- Two neighbours on either side of one fence make one set piece.
- A task that needs *both* gardens (the rose and the hedge) is what turns a fence into play.

### 1.5 Phasmophobia: streets that are only addresses
- [S] 13 Willow Street has 10 rooms on two floors. Ridgeview Court and Edgefield Road have 16 rooms on three floors. ([Dot Esports](https://dotesports.com/phasmophobia/news/all-maps-in-phasmophobia))
- [V] The Willow rework (21 July 2026) kept "nearly the same layout", rebuilt the basement and added hiding spaces. ([Game Developer](https://www.gamedeveloper.com/press-release/phasmophobia-s-13-willow-street-rework-launches-alongside-major-quality-of-life-update))
- [S] The next new map was pushed to 2027. ([Kinetic](https://kineticgames.co.uk/news/phasmophobia-2026-and-beyond))
- I found no source on its exteriors.

**Lesson [A]:** its "streets" are one house each. The neighbourhood is a backdrop, which is exactly what our engineer wants to move beyond.

### 1.6 Rainbow Six Siege: cameras on the outside
- [S] Bank has seven cameras, three outside and four inside. On Border, the three outdoor cameras have "a considerable line of sight". ([Twinfinite](https://twinfinite.net/guides/rainbow-six-siege-all-camera-locations-every-map/))
- [S] Y11S3 (September 2026) reportedly adds fire extinguishers "around critical bottlenecks of every floor" of House. Only one guide reports it. ([Mobalytics](https://mobalytics.gg/gamebase/guides/rainbow-six-siege-y11s3-map-changes))
- Round 2 covered the House rework itself.

### 1.7 Hello Neighbor and Secret Neighbor
- [S] Hello Neighbor's player moves into a house "across the street". Act 1's neighbour house has two floors and nine rooms. The roof is reached by a ladder and boxes, and a hole in it leads into a child's room. ([GameSkinny](https://www.gameskinny.com/05dka/hello-neighbor-guide-act-1-puzzle-walkthrough))
- [S] Hello Neighbor 2 is open world: some puzzles need an item from another house. ([Shacknews](https://www.shacknews.com/article/133515/hello-neighbor-2-review-score))
- [V] Secret Neighbor is social deduction for up to 6 players with one hidden neighbour. Its developer: "the first thing we did was add randomized walls in the house", which permanently closes some doors "forcing players into using alternate routes". ([Xbox Wire](https://news.xbox.com/en-us/2019/10/24/social-horror-secret-neighbor-available-today-xbox-game-pass/))

### 1.8 Examples from 2024 to 2026
- **NEIGHBORS: Suburban Warfare** (Invisible Walls):
  - [S] Early access began 17 April 2025, for up to 8 players. It had "five houses playable in both maps", and players spawn in one of the five houses.
  - [S] Full release came in September 2026.
  
  ([Gematsu 2025](https://gematsu.com/2025/03/neighbors-suburban-warfare-launches-in-early-access-on-april-17), [Gematsu 2026](https://www.gematsu.com/2026/09/neighbors-suburban-warfare-now-available-for-ps5-xbox-series-and-pc))
- **Killer Klowns from Outer Space: The Game** (2024), with a Suburbs map:
  - [S] It has four escape types, each needing items.
  - [S][P] A reviewer: "the escapes often choose you through a randomized itemization system".
  
  ([Wikipedia](https://en.wikipedia.org/wiki/Killer_Klowns_from_Outer_Space:_The_Game), [Thumb Culture](https://www.thumbculture.co.uk/killer-klowns-from-outer-space-ps5-review))
- **The Texas Chain Saw Massacre** (2023, updated through 2024):
  - [V] The basement start was invented for the game and is "packed with shadows, hiding spots, and crawl spaces". The team's challenge was "creating the spaces you don't see… and giving them purpose". ([Game Developer](https://www.gamedeveloper.com/design/deep-dive-pursuing-an-authentic-cinematic-experience-with-texas-chainsaw-massacre))
  - [S][P] A reviewer found the exits too alike, so the road exit became their default. ([Analog Stick](https://www.analogstickgaming.com/game-reviews/2023/8/22/the-texas-chain-saw-massacre))
- **Fortnite, Pleasant Park:**
  - [S] Houses ring a small park with a pitch, a gazebo and a barbecue.
  - [S] The gas station roof is the vantage point.
  - [S] A secret safe house sat under the pitch.
  
  ([Fortnite wiki](https://fortnite.fandom.com/wiki/Pleasant_Park))

### 1.9 Ships, spawns, cameras and alert meters
- **Spawning together or apart (Among Us):**
  - [S] The Fungle starts everyone at a campfire. ([BlueStacks](https://www.bluestacks.com/blog/updates/among-us/au-new-map-the-fungle-en.html))
  - [S] The Airship offers a random set of three spawn rooms. ([Dexerto](https://www.dexerto.com/among-us/new-among-us-map-the-airship-revealed-1478056/))
  - [S][P] PC Gamer called the Airship "too big", reporting "a minute or two" without meeting anyone, and said the random spawns make it "impossible to know who is where". ([PC Gamer](https://www.pcgamer.com/uk/among-us-new-airship-map-is-too-big-making-it-an-impostors-dream))
- **The ship as a base (Lethal Company):**
  - [S] Each interior has "one main entrance and 1 fire exit". ([Lethal Company wiki](https://lethalcompany.wiki.gg/wiki/Moons))
  - [S] The landed ship is a base with a monitor that cycles between teammates. ([Dot Esports](https://dotesports.com/indies/news/lethal-company-ship-duty-full-guide-to-running-the-ship-in-lethal-company))
- **Camera evidence (Hitman):** [S] In Hitman 3, destroying any recorder disables all cameras on the map. In the 2016 game and Hitman 2, each camera had its own recorder. ([Nexus mod description](https://www.nexusmods.com/hitman3/mods/860))
- **An alert meter that escalates (Destroy All Humans!):**
  - [S] Its alert level goes from police, to police hunting with cruisers, to the army, to the agents.
  - [S] It rises "simply by being out in the open" and "drastically" with havoc, and falls by staying out of sight.
  
  ([DAH wiki](https://destroyallhumans.fandom.com/wiki/Alert_Level))
- **Pranks on a neighbour's routine (Neighbours from Hell):** [S] It is a prank game built on the neighbour's routine and his pets (a parrot, a dog), where noise draws him. ([Wikipedia](https://en.wikipedia.org/wiki/Neighbours_from_Hell))

---

## 2. Real suburbs in metres

These are real-world anchors, so a block reads as a plausible street:
- **Lots.** [S] US single-family codes give lots 12 to 18 m wide and 27 to 30 m deep. Front setbacks are 6 m, side setbacks 1.5 m (so 3 m between houses), and rear setbacks 3 m. Lot areas run from 465 to 1,400 m². ([Firebaugh CA code](https://www.zoneomics.com/code/firebaugh-CA/chapter_37))
- **Streets.** [S] A local street is a 50 ft (15 m) right of way with 22 to 35 ft (7 to 11 m) of pavement. A cul-de-sac turning circle has a 40 to 50 ft (12 to 15 m) radius. ([Show Low code](https://showlow.municipal.codes/Code/17.20.020(A)), [North Londonderry specs](https://www.nlondtwp.com/wp-content/uploads/2020/06/StreetSpecs.pdf))
- **Houses.** [S] The median new US house completed in 2024 was 2,146 sq ft, about 200 m²: roughly 10 x 10 m on two floors. ([Census](https://www.census.gov/construction/chars/highlights.html))
- **Fences.** [S] In England, back fences up to 2 m need no permission, but only 1 m next to a road. ([PlanWatch](https://planwatch.co.uk/guides/do-i-need-planning-permission-for-a-fence))
- **Street layout.** [S] An informal Pac-Man-on-real-maps experiment found grids offer more escape routes than cul-de-sacs. Its page has since moved. ([Louisville, via search](https://louisville.edu/upa/udstudio/blog/posts/google-maps-pac-man-and-street-connectivity))

What this means for us [A]:
- Our party house (24 x 20 m, two floors, about 960 m²) is nearly **five median houses**. It reads as a mansion among normal homes for free, and becomes the landmark.
- Neighbour houses of about 10 x 10 m keep art and test costs down. A 3 m gap between houses is a ready side passage.
- The real fence rule gives a free legibility gradient: **front gardens are low and public, back gardens are tall and private.** Players read that without being taught.

---

## 3. The topic, element by element

### 3.1 How many lots, and how far apart
[A] Our reference points:
- Nuketown: 2 houses in about 840 m², for 12 players in a shooter.
- Lampkin Lane: about 8,400 m² for 5 players, after it was shrunk.
- Whittleton Creek: 14 properties, for one stealth player.
- NEIGHBORS: 5 houses, for 8 players.
- Our House: 5,280 m² with its street, which round 2 already worried was big for 4 players.

**A working budget:**
- The party lot plus **4 enterable neighbour lots**, plus 1 or 2 garden-only or facade lots at the edges, plus the shop.
- Total footprint **6,500 to 8,000 m²**, at most about 1.5 times today.
- Keep it there by **shrinking the party lot** from 80 x 60 m to about 44 x 44 m. The house stays; the yard shrinks.
- Distances: no enterable lot more than about 45 m from the party house's front door (10 s walking), and no capsule more than about 15 s from a task (round 2's mark).
- Then the block's diagonal is about 110 to 125 m: 25 to 28 s walking, 19 to 21 s with sprint cycles. That is comparable to today's 100 m plot diagonal (22 s), so total crossing time barely grows.

### 3.2 The street
- [V] Lampkin Lane's lesson: a long, open street has to be shortened and blocked.
- [V] Nuketown's lesson: parked vehicles are the cover.
- [A] For us the street has three jobs:
  1. the front stage (low fences, public, visible);
  2. where the cops arrive (m8 §5);
  3. the run to the shop.
- [A] Keep it short (60 to 80 m of frontage) with 2 or 3 big occluders: a parked van, a skip, a hedge island.
- [A] A cul-de-sac bulb (12 to 15 m radius) is the most compact version. Every front door faces one small stage.

### 3.3 Back gardens, fences and gaps
- [V] In the Goose gardens, a gate, a drawer and a hole turn one fence into three ways across, each with a different cost.
- [V] Secret Neighbor shows that randomly closing a few links forces new routes each match.
- [A] Fences 1.8 to 2 m tall hide a standing player (eye height about 1.6 m) at ground level. So the back of the block is where hiding and mischief live, and the gaps are its doors:
  - a loose board (crouch through, about 1 s at 2 m/s);
  - a hedge hole;
  - a gate that creaks (a sound cue);
  - a trampoline or wheelie bin to climb over.

### 3.4 Roofs, garage roofs, sheds and pool houses
- [V] Whittleton Creek has a tree house for sniping. [S] Fortnite's gas-station roof overlooks Pleasant Park.
- [A] A vantage point on a block is a strong piece, so price it. Geometry for the engineer's roof complaint:
  - A viewer at height H sees over a fence of height h at distance d. The ground stays hidden only for a strip d·h/(H−h) deep behind the fence.
  - From an 8 m roof over a 2 m fence that is d/3. A garden 30 m away keeps only a 10 m strip hidden.
  - **Fences do not defeat a roof.** Only taller things do: a neighbour's house (about 7 m), trees, a garage, and the ship itself.
  - So put mischief points and back gardens **in the shadow of a neighbour's house** as seen from the party roof.
- [A] Flat garage roofs and lean-to sheds chained across two or three lots give an "over" route. It is fast but exposed, and it needs a climb verb we do not have (jump height is 1.0 m today). A shed or pool house is the natural home for a capsule, a mischief prop or a tunnel hatch.

### 3.5 How lots link: front, back, under, over
[A] An original typology. Each kind of link has its own speed, visibility and sound:

| Link | Example | Speed | Seen from | Heard | Good for |
|---|---|---|---|---|---|
| Front | street, front paths, low gates | fast (sprint) | street, roof, cameras | street is open, voice carries | the cops, the shop, the public stage |
| Side | the 3 m passage between two houses, a side gate | medium | almost no one | muffled by both houses | the spokes from street to back |
| Back | fence gaps, hedge holes | slow (crouch) | neighbours' back windows only | private | mischief, sabotage, escape |
| Over | garage roofs, sheds, a trampoline | fast but needs climbs | everyone looking up | loud on tin | chase breakers, lookouts |
| Under | basement tunnels (the alien layer) | fast | no one | inaudible above | the hidden layer, the ship |

Round 2's rules apply here: networks stay local, and each link opens a ring or shortens one. One "under" link of two or three nodes is enough. [V] Whittleton Creek has exactly one, between two basements.

### 3.6 Sightlines and cover between lots
- [A] Separate the views:
  - the **front** is mutually visible;
  - the **back** is visible only from the adjacent lots' upper windows;
  - **the party roof sees the street and its own garden, not the neighbours' backs**.
- [V] Lampkin Lane's street blockers are the precedent.
- [A] This turns "the neighbours notice" into geometry: a mischief point is noticed if it is in sight of a neighbour's window. `core/items/in_sight.gd` already checks walls between an eye and an item (round 2), so a host-side check from a window marker could reuse it. That is an engine call for the engineer.

### 3.7 Landmarks
- [A] Every lot needs one silhouette readable from the street in under a second: the party house's size, the ship's glow, a neighbour's odd feature (a water tower, a giant inflatable, a satellite dish).
- [A] This doubles as respawn orientation (round 2, §5).

### 3.8 Keeping the party house the centre without filler
- [V] Whittleton Creek: a public hub, with private lots each worth entering.
- [V] Lampkin Lane deleted its closed houses.
- [V] TCSM gave its invented spaces purpose.
- [V] The Level Design Book on hub-and-spoke: "returning to a hub can feel like a relaxing reward". ([Level Design Book](https://book.leveldesignbook.com/process/layout/typology))
- [A] The rule: **the hub keeps what everyone shares** (storage, the kitchen, the order board), and **each spoke lot gets at least three of the following**:
  - one task station;
  - one or two mischief points;
  - one capsule;
  - one link of a different kind (side, back, over or under);
  - a landmark.
  
  A lot that cannot meet this is a facade beyond the fence, never an empty enterable house. Moving existing stations (the greenhouse, the gazebo, the grill) out of the party yard and into neighbours' gardens is the cheapest way to do it. Then fetching herbs means trespassing. That is a content call for the engineer.

---

## 4. Mapping our mechanics onto a block

**The ship in the yard.**
- [A] It is a second pole beside the house. The Level Design Book's "Figure 8" (two bases and their connectors) fits it ([typology](https://book.leveldesignbook.com/process/layout/typology)).
- [A] Place it in the party garden's back half: as an occluder it hides part of the garden from the roof, and as the hidden layer's entrance it sits on the tunnel.
- [A] The two spawn settings map onto known trade-offs:
  - **Everyone in the ship**: the shared start reads like a campfire start. Deduction gets a clean "who left which way" at second zero.
  - **Random**: the Airship-style scatter that PC Gamer said hid everyone [S][P].
  - So default to the ship and offer random as the host option. Under random, spawn only at capsules, which already follow round 2's rules.
- [A] The ship as a mission (a repair or a quest) gives the alien layer its reason to exist. Keep its entrances to two (one main, one hidden), as in Lethal Company.

**Mischief spread and partly hidden, a random subset per match.**
- [A] Use a pool of 10 to 14 mischief points across the lots, with 3 or 4 active each match (placeholders): "known kind, unknown place".
- [V] DBD fixes its landmarks and rotates the generic pieces.
- [V][P] Two warnings: TCSM's same-looking exits made players fixate on the easiest, and Killer Klowns' randomised escapes "choose you".
- [A] So randomise *which* point is active, not *what kinds* exist. Make each kind look the same everywhere, and give each lot a different mix.
- [A] Bins are the engineer's own example: today everyone knows they are at the road. Give every lot its own bins (front kerb, back lane, the ship's waste), and the knowledge stops being an answer.

**Capsules (5 or 6).**
- [A] One per spoke lot plus one in or near the ship, each in a shed or garage with two exits facing different links.
- [A] Because lots are fenced, capsules gain separation of sight for free.

**Walls muffle voice.**
- [A] The block makes it legible: the street carries voice, houses muffle, back gardens are private.
- [A] An 8 m radius spans a 3 m side passage, so two players in adjacent houses hear each other muffled through two walls. That is good comedy, but test it.

**The cops on the street.**
- [A] The finale pulls everyone to the front. Put the "stall the cops" place at the street's mouth, so a human offering to stall them walks into the most public spot on the map.

**Cameras.**
- [S] Siege places half its cameras outside. [S] Hitman ties footage to recorders.
- [A] Use 3 or 4 fixed cameras (the street, the party garden, the back lane, the shop door), one monitor (in the ship or the house), a tell when a camera is watched, deliberate blind spots, and a way to cut them (counter-play for the humans).
- [A] **Cameras should replace the roof's omniscience, not add to it.** Make the roof lookout see only the street.
- [A] Engineering note: if the host ever filters which players a client receives by distance, a camera feed needs the host to send what each camera sees. A grep of `server/` for `interest|relevan|in_range` found no such filter today, but confirm it before designing on that assumption. The host's own client must use the same path (invariant 2).

**The shop run.**
- [A] Put the shop just off the block at the street's mouth: about 50 m and 11 s walking from the party door, so a round trip is about 25 s.
- [A] The trip crosses the public front. It is quick, seen, and a natural meeting place, and a good decoy for a human.
- [A] "A clear list" fits a fixed board. What the humans can do to the list is a content question.

**The hidden alien layer.**
- [A] One tunnel line of 2 or 3 nodes: party basement, the ship, one neighbour's cellar or shed. It is local, never a map-wide teleport (round 2).
- [V] A Hitman player read the second house as a decoy entrance. That is the right flavour: a neighbour's cellar that is secretly the aliens' back door.

---

## Cross-game patterns

1. **A street of houses grows too big, then gets cut.** DBD reduced Lampkin Lane twice (168 → 152 → 132 sqT) and removed closed houses. Black Ops 6's one-house variant drew a backlash. [V], [S]
2. **One public hub among private lots.** Whittleton Creek's open party among private properties. [V]
3. **Links between lots are content.** Goose gardens' gate, drawer, hole and box; Hello Neighbor's ladder and roof hole. [V], [S]
4. **Exactly one secret underground link.** Whittleton's basement tunnel; Pleasant Park's safe house under the pitch. [V], [S]
5. **Open streets need blockers.** DBD's line-of-sight blockers; Nuketown's bus and van. [V]
6. **Fixed landmarks, rotating details.** DBD tiles; Secret Neighbor's random walls; and the warning from TCSM and Killer Klowns when variety is fake or decides for you. [V], [S]
7. **Spawning together helps deduction, scattering hides people.** Fungle's campfire against the Airship. [S]
8. **Information tools are placed and priced.** Siege's outdoor cameras, Hitman's recorders, Lethal Company's monitor. [S]

## Risks for our design

1. **Size creep kills encounters.** Each new lot adds area, and the Airship lesson applies. At 4 players a 6-lot block could be empty. Hold the footprint near 1.3 to 1.5 times today, or scale the open lots by player count.
2. **Filler lots.** An enterable house with nothing in it is DBD's closed house. Every enterable lot needs the §3.8 kit, and that costs content and art.
3. **The roof stays omniscient.** Fences do not block an 8 m vantage (§3.4). Without houses or trees in the way, or a narrowed roof, the engineer's complaint survives the move to a block.
4. **Cameras plus roof plus open street means no secrets.** Too much information kills the humans' covert play, which the balance model (#1089) calls their best answer.
5. **Randomness that is invisible or decides for you.** Mischief variety must stay readable ("a fire somewhere") or the search becomes a coin flip.
6. **The street as a dead stage.** If nothing happens at the front until the finale, the street is a wide empty run.
7. **Engine and test work multiply.** More interiors, more colliders, more bot paths (bots read a flat floor at y = 0, house-map §6), and a climb verb for "over" routes. Moving stations is a content change for the engineer.
8. **Voice through 3 m gaps.** Two houses side by side are one voice zone under pure distance. If the wall muffle is cosmetic only, private rooms may not feel private.
9. **The ship as a spawn camp.** "Everyone in the ship" at the start is safe, but if the ship also holds a capsule, it becomes a farm. Keep capsules out of the ship.

## Options for the engineer (original, placeholders throughout)

**A. "The Wheel": the party house at the head of a cul-de-sac.**
- Layout:
  - 4 neighbour lots fan around a bulb of about 13 m radius, with the shop and a 25 m entry road at the mouth on the main street;
  - the back gardens meet behind the houses as an outer ring, with fence gaps;
  - side passages are the spokes;
  - the ship stands in the party garden at the back.
- Footprint: about 85 x 90 m, roughly 7,000 m².
- Distances: bulb crossing 6 s walking; party door to the shop about 11 s.
- *For:* compact; two concentric rings with radial spokes; one clear front stage where the cops arrive.
- *Against:* the bulb sees every front door; deep fan-shaped back gardens are awkward to build.

**B. "Row and Lane": the party lot in the middle of a row.**
- Layout:
  - 2 neighbour lots on each side, 15 x 35 m each;
  - a 4 m back lane behind the row (bins, garages, the tunnel hatch);
  - 2 lots and the shop across a 10 m street.
- Footprint: about 100 x 80 m.
- *For:* the most realistic and easiest to read; the lane is a natural second ring; each lot is a simple rectangle.
- *Against:* closest to the linear feel the engineer dislikes; the far lots are about 40 m along the street.

**C. "The Island": the party lot hidden in the middle of a block.**
- Layout:
  - the party lot is reached by a driveway between two houses;
  - every neighbour's back garden borders it;
  - streets run outside.
- *For:* the neighbours literally surround the party, so "they notice" follows from their windows; the party is the hub in every sense.
- *Against:* a long street ring (about 360 m round a 90 m block); the cops' street is far from the house; the party yard is overlooked from every side.

**D. "Open by headcount": an overlay for A, B or C.**
- Lots have slots. The host or the player count opens 2, 3 or 4 neighbour lots: about 2 for 4 to 5 players, 4 for 8 to 10.
- A closed lot is a fenced facade, never an enterable empty house.
- *For:* fixes Risk 1 and scales the work (#1089).
- *Against:* every opened variant must be tested; capsule and mischief pools must scale too.

**E. "Over and Under": an overlay.**
- One "under" line (party basement, ship, one neighbour cellar) and one "over" chain (two or three garage roofs).
- *For:* the alien layer and the chase breakers in two pieces.
- *Against:* "over" needs a climb verb; "under" needs hidden-layer art that stays tied to known rooms.

**F. "Watch Swap": an overlay.**
- Cut the roof lookout down to the street.
- Add 3 or 4 cameras with blind spots, a tell and a way to cut them, with the monitor in the ship.
- *For:* fixes Risk 3, gives the ship a second job, and gives humans counter-play.
- *Against:* netcode and per-peer filtering work; a camera tuned too strong recreates the roof problem.

**Recommendation [A]:** **A + D + F**, then E's "under" line only.
- The Wheel gives the most connection per square metre and keeps the party house the literal head of the street.
- D keeps 4-player matches dense.
- F turns the engineer's two complaints (the roof sees everything, the yard is one open stage) into a priced information tool.
- Start the greybox with the street, the four lot shells and the fence gaps. Measure travel time with the round-2 kit before any interiors are built.
- Defer the "over" chain until a climb verb exists.

## Open questions for the engineer

1. Which archetype (A, B, C) is closest to the picture in your head: a cul-de-sac, a row with a lane, or a hidden lot?
2. How many neighbour houses are enterable, and are the rest facades?
3. May existing stations (greenhouse, gazebo, grill, photo zone) move into neighbours' gardens?
4. Does "the neighbours notice" depend on sight from their windows (a host-side sight check), or is it a flat rise per active mischief?
5. Default spawn: the ship or random? Under random, capsules only?
6. Cameras: where is the monitor, can humans cut or loop the feed, and does the roof lookout shrink?
7. Is the shop on the block, at its mouth, or a short trip off-map? Can humans tamper with the list?
8. The alien tunnel: open knowledge from match one, and which three nodes?
9. Does the block scale with the player count (option D), and by host setting or automatically?
10. Is a climb verb (for roofs and fences) in scope for M8.2?

---

### Sources
All are cited inline. Main ones:
- **Hitman:** [ludo.guide](https://www.ludo.guide/guide/hitman-world-of-assassination/hitman-world-of-assassination-part-425) · [Hitman wiki](https://hitman.fandom.com/wiki/Whittleton_Creek) · [Steam](https://steamcommunity.com/app/863550/discussions/0/1676938384246808385) · [SegmentNext](https://segmentnext.com/2018/11/20/hitman-2-whittleton-creek-walkthrough/) · [GamesHedge](https://www.gameshedge.com/hitman-2-whittleton-creek-walkthrough-guide-points-interest-disguises/) · [GDC 2019](https://gdconf.com/news/what-makes-hitman-2-levels-tick-find-out-gdc-2019s-level-design-workshop) · [Nexus](https://www.nexusmods.com/hitman3/mods/860)
- **Nuketown:** [Wikipedia](https://en.wikipedia.org/wiki/Nuketown) · [GGRecon](https://ggrecon.com/articles/black-ops-6-new-nuketown-slammed-amid-tiny-map-influx) · [whiteclouds](https://www.whiteclouds.com/?p=29456)
- **Dead by Daylight:** [Lampkin Lane](https://deadbydaylight.wiki.gg/wiki/Lampkin_Lane) · [Distances](https://deadbydaylight.wiki.gg/wiki/Distances) · [7.7.0 notes](https://mp1st.com/news/dead-by-daylight-update-3-12-for-patch-7-7-0-brings-game-engine-update-and-more) · [Springwood post](https://devtrackers.gg/deadbydaylight/p/022b01d3-map-update-springwood) · [Steam](https://steamcommunity.com/app/381210/discussions/0/3388408347639386960)
- **Untitled Goose Game:** [Game Developer](https://www.gamedeveloper.com/game-platforms/road-to-the-igf-house-house-s-i-untitled-goose-game-i-) · [ACMI](https://www.acmi.net.au/works/122683--the-world-of-untitled-goose-game/) · [GDC 2020](https://gdconf.com/news/come-gdc-and-see-how-untitled-goose-games-levels-were-scouted) · [gamepretty](https://gamepretty.com/untitled-goose-game-speedrun-task-guide/)
- **Phasmophobia:** [Willow rework](https://www.gamedeveloper.com/press-release/phasmophobia-s-13-willow-street-rework-launches-alongside-major-quality-of-life-update) · [Dot Esports](https://dotesports.com/phasmophobia/news/all-maps-in-phasmophobia)
- **Rainbow Six Siege:** [Twinfinite](https://twinfinite.net/guides/rainbow-six-siege-all-camera-locations-every-map/) · [Mobalytics](https://mobalytics.gg/gamebase/guides/rainbow-six-siege-y11s3-map-changes)
- **Hello Neighbor and Secret Neighbor:** [Xbox Wire](https://news.xbox.com/en-us/2019/10/24/social-horror-secret-neighbor-available-today-xbox-game-pass/) · [GameSkinny](https://www.gameskinny.com/05dka/hello-neighbor-guide-act-1-puzzle-walkthrough) · [Shacknews](https://www.shacknews.com/article/133515/hello-neighbor-2-review-score)
- **NEIGHBORS: Suburban Warfare:** [Gematsu 2025](https://gematsu.com/2025/03/neighbors-suburban-warfare-launches-in-early-access-on-april-17) · [Gematsu 2026](https://www.gematsu.com/2026/09/neighbors-suburban-warfare-now-available-for-ps5-xbox-series-and-pc)
- **Killer Klowns:** [Wikipedia](https://en.wikipedia.org/wiki/Killer_Klowns_from_Outer_Space:_The_Game) · [Thumb Culture](https://www.thumbculture.co.uk/killer-klowns-from-outer-space-ps5-review)
- **The Texas Chain Saw Massacre:** [Game Developer](https://www.gamedeveloper.com/design/deep-dive-pursuing-an-authentic-cinematic-experience-with-texas-chainsaw-massacre) · [Analog Stick](https://www.analogstickgaming.com/game-reviews/2023/8/22/the-texas-chain-saw-massacre)
- **Fortnite:** [Pleasant Park](https://fortnite.fandom.com/wiki/Pleasant_Park)
- **Among Us:** [Dexerto](https://www.dexerto.com/among-us/new-among-us-map-the-airship-revealed-1478056/) · [PC Gamer](https://www.pcgamer.com/uk/among-us-new-airship-map-is-too-big-making-it-an-impostors-dream) · [BlueStacks](https://www.bluestacks.com/blog/updates/among-us/au-new-map-the-fungle-en.html)
- **Lethal Company:** [Moons wiki](https://lethalcompany.wiki.gg/wiki/Moons) · [Dot Esports](https://dotesports.com/indies/news/lethal-company-ship-duty-full-guide-to-running-the-ship-in-lethal-company)
- **Alert meters and pranks:** [Destroy All Humans! wiki](https://destroyallhumans.fandom.com/wiki/Alert_Level) · [Neighbours from Hell](https://en.wikipedia.org/wiki/Neighbours_from_Hell)
- **Level design:** [Level Design Book, typology](https://book.leveldesignbook.com/process/layout/typology)
- **Real-world scale:** [Firebaugh code](https://www.zoneomics.com/code/firebaugh-CA/chapter_37) · [Show Low code](https://showlow.municipal.codes/Code/17.20.020(A)) · [North Londonderry](https://www.nlondtwp.com/wp-content/uploads/2020/06/StreetSpecs.pdf) · [Census](https://www.census.gov/construction/chars/highlights.html) · [PlanWatch](https://planwatch.co.uk/guides/do-i-need-planning-permission-for-a-fence) · [Louisville](https://louisville.edu/upa/udstudio/blog/posts/google-maps-pac-man-and-street-connectivity)

**Local sources:**
- `D:\prime-game\docs\design\house-map.md`
- `D:\prime-game\docs\design\research\2026-10-15-spacious-house-level.md`
- `docs/design/m8-match.md` at commit 49d435247 (branch `content/1093-docs-design-the-pillar-the-party-is-hard`)
- `D:\prime-game\content\modes\base_mode.tres:353,391-399`
- `D:\prime-game\server\` (grep, no distance filter found)