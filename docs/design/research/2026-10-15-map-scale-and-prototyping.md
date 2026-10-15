# Map scale and fast prototyping for a 4 to 10 player neighbourhood block

*Research for "My Alien Prime Friends", round 3, on map scale and prototyping. This is research only: nothing here is decided. Tags: [V] checked at the source page, [S] from a search summary only (the page was not fetched or refused the fetch), [P] an opinion from a player, the press or a blogger, [A] my own analysis. Every number I propose is a placeholder for the engineer to set.*

## 0. Method and what this builds on

I ran about 50 web searches and fetches, plus read-only checks of the repo. Some pages refused the fetch (PCGamesN, TechRaptor, a Bungie PDF that would not render), so facts from them are tagged [S]. I did not study LOCKDOWN Protocol's map, because a separate teardown covers it.

**This report builds on three files and does not repeat them:**
- `docs/design/m8-match.md` (origin/main): the anger meter, the 5 or 6 capsules, the cops' minute, walls that muffle voice.
- `docs/design/house-map.md`: the 80 x 60 m plot, the room tables, the route times in §7.
- `docs/design/research/2026-10-15-spacious-house-level.md`: loops, chase geometry, the measurement kit.

Round 2 already cited the Fungle "80% of the Airship" line, the Halo heatmaps and the Level Design Book's playtesting chapter. I only point back to them here.

**Facts about our build, checked live:**
- [V] Movement and life numbers, from `content/modes/base_mode.tres:389-400`:
  - walk 4.5 m/s, sprint 7.0 m/s;
  - stamina 100, sprint costs 20/s, regeneration 15/s, a sprint needs 20 stamina to start;
  - voice range `living_m = 8.0` (line 353);
  - respawn 30 s, then 3 s of invulnerability.
- [V] Stamina refills on every tick you are not sprinting, walking included (`core/stamina/stamina_ledger.gd:8-9`).
- [A] So a full sprint lasts 5 s and covers 35 m. After that, a player who pulses the sprint keeps an average of about 5.6 m/s. The cycle is 1 s of sprint and 1.33 s of walking: (7 + 4.5 × 1.33) / 2.33 ≈ 5.57 m/s. Over 100 m that is 22.2 s walking, or about 16.7 s with sprinting (5 s for the first 35 m, then 65 m at 5.57 m/s).
- [V] The level rules, from `levels/CLAUDE.md:14-27` (origin/main):
  - whole-metre grid, 3.2 m from floor to floor, doors 1.4 x 2.15 m;
  - collision only from `StaticBody3D` with `CollisionShape3D` on layer 1;
  - CSG and `GridMap` are for looks only, and the host refuses a level that uses them for collision.
- [V] The repo already has a greybox test map and a material kit: `levels/greybox/greybox.tscn` and `levels/kit/greybox_*.tres`.

---

## 1. Scale

### 1.1 What shipped maps measure

| Game, map | Players | Area | Per player | Crossing | Source |
|---|---|---|---|---|---|
| Dead by Daylight, Wreckers' Yard (1 vs 4) | 5 | 144 tiles = 9,216 m² | 1,843 m² | — | [V] [wiki](https://deadbydaylight.wiki.gg/wiki/Wreckers'_Yard) |
| Same map, the 2 vs 8 version | 10 | 176 tiles = 11,264 m² | 1,126 m² | — | [V] same page |
| DBD, Lampkin Lane (a suburban street) | 5 | 132 tiles = 8,448 m² (was 168, then 152) | 1,690 m² | — | [V] [wiki](https://deadbydaylight.wiki.gg/wiki/Lampkin_Lane) |
| DBD, smallest and largest maps | 5 | 98 to 176 tiles = 6,272 to 11,264 m² | 1,250 to 2,250 m² | — | [S] [Timesaver](https://timesaver.gg/blog/dbd-maps-list-all-maps-realms) |
| DBD, Nostromo Wreckage | 5 | 120 tiles | — | "24 seconds length wide … 20 seconds width wise" at 4 m/s | [P] [BHVR forum](https://forums.bhvr.com/dead-by-daylight/discussion/comment/3533586) |
| Hunt: Showdown | teams | 1 km², 16 compounds | — | about 250 m between compound centres [A] | [V] [wiki](https://huntshowdown.wiki.gg/wiki/Maps); [S] 1 km² ([wiki](https://huntshowdown.wiki.gg/wiki/Maps)) |
| Phasmophobia | 1 to 4 | small maps 11 to 16 rooms, medium 17 to 31; overall range 10 to 111 rooms | — | — | [S] [Dot Esports](https://dotesports.com/phasmophobia/news/all-maps-in-phasmophobia) |
| Lethal Company moons | up to 4 | March's interior is "roughly twice the size of Experimentation or Assurance"; Titan has "the largest interior in the game" | — | — | [V] [wiki](https://lethalcompany.wiki.gg/wiki/Moons); 4 players [S] [ProGameGuides](https://progameguides.com/lethal-company/how-many-people-can-play-lethal-company/) |
| R.E.P.O. | co-op | 4 to 6 modules on levels 1 to 4, growing with the level | — | — | [S] fan mod data, [Thunderstore](https://thunderstore.io/c/repo/p/Swaggies/LevelScaling/v/0.6.4/) |
| Among Us | up to 15 | no published area; the Skeld has 14 rooms | — | — | [S] [Sportskeeda](https://sportskeeda.com/esports/among-us-full-map-layouts) |

[V] How DBD measures area: one tile in its area unit is 8 x 8 m (64 m²), while the physical map pieces are 16 x 16, 16 x 32 or 32 x 32 m ([Distances](https://deadbydaylight.wiki.gg/wiki/Distances)). [S] Survivors run at 4.0 m/s and killers at 4.4 or 4.6 m/s ([wiki](https://deadbydaylight.wiki.gg/wiki/Movement_speed)), so DBD's speeds are close to our 4.5 m/s walk.

I found no published areas for Among Us, PEAK's biomes, R.E.P.O.'s modules, or LOCKDOWN Protocol's map. For LOCKDOWN Protocol, a 2024 player said it is "bigger then some Among Us maps" [P] ([Steam](https://steamcommunity.com/app/2780980/discussions/0/4759830532863466412)).

### 1.2 What our own numbers say

[A] The House today, summed from the room tables in house-map §4:
- yard level: 80 x 60 = 4,800 m²;
- second floor and balcony: 510 m²;
- basement: 1,112 m²;
- attic: 480 m².

That is about **6,900 m²** (7,400 m² with the 6 m street). Per player:
- **4 players: about 1,750 m² each.** That is DBD's 1 vs 4 density, and DBD is a game built for hiding.
- **10 players: about 700 m² each.** That is denser than DBD's 2 vs 8 maps (1,126 m²).

The plot's 100 m diagonal (22.2 s walking) already matches the crossing times of a DBD map.

[A] **A baseline for how often players meet.** Our voice reaches a circle of π × 8² ≈ 201 m². If players stood at random spots on 7,400 m², the expected number of other players inside a given player's voice circle would be:
- 10 players: 9 × 201 / 7,400 ≈ 0.24, so someone is in voice range about 22% of the time;
- 4 players: about 8% of the time.

On a 12,000 m² block those figures drop to about 14% and 5%. Real players bunch at tasks, so the true rates are higher. Still, the baseline shows the shape of the problem: **adding area without adding reasons to meet cuts voice encounters in proportion.** That matters for a game whose comedy runs on proximity voice.

[V] Two rules of thumb from the Level Design Book's blockout page ([link](https://book.leveldesignbook.com/process/blockout)):
- Dirty Bomb aimed for **8 to 12 s from spawn to an objective**;
- "if it feels long, it's too long."

[P] A September 2026 blog post puts "fifteen to twenty seconds from spawn to a fight" as alive and "past forty" as empty. It cites no data ([Geek Vibes Nation](https://geekvibesnation.com/battlefield-player-count-vs-map-density/)).

[V] An older Game Developer guideline ([Timothy Ryan, 2009](https://www.gamedeveloper.com/design/multiplayer-map-game-design-guidelines)):
- "finding players is the number one concern in any map";
- "the size of the map should be inversely proportional to the amount of occlusion."

### 1.3 Scaling with the player count

The studios that solved this do not build one size for every lobby:
- **DBD's 2 vs 8 maps** double the players and grow the same map by only 22% (144 to 176 tiles), with 3 exit gates instead of 2 [V] ([Wreckers' Yard](https://deadbydaylight.wiki.gg/wiki/Wreckers'_Yard), [Exit Gates](https://deadbydaylight.wiki.gg/wiki/Exit_Gates)). So DBD treats density as the variable to protect.
- **Phasmophobia's Restricted variants** (25 August 2026) close parts of large maps "for quicker games". On Point Hope the accessible area goes "up to the Dining Room". Prison and Brownstone variants are "randomly assigned upon loading into a contract", and "small decor outside" each variant tells players which one they are in [V] ([Kinetic Games](https://kineticgames.co.uk/news/phasmophobia-quality-of-life-part-2-preview)).
- **Counter-Strike's Wingman** plays 2 vs 2 on cut-down parts of the competitive maps, for example Inferno's B site and Banana [S] ([ExitLag](https://www.exitlag.com/blog/counter-strike-2-maps/)).
- **Among Us's 15-player lobbies (2021):** the press called the Skeld and MIRA HQ "quite cramped" with that many players and the Airship a good fit [P] ([GamePressure](https://www.gamepressure.com/S013-amp.asp?ID=12731)).
- **Bungie's Chris Carney** designs for a player bracket first: 4 to 8, 8 to 12 or 12 to 16 [S] ([PDF](https://www.jmeiners.com/shamans/papers/art/bungie_map_design.pdf)).

[A] For us, 4 to 10 players spans two of Carney's brackets. One fixed block cannot hit a good density at both ends.

### 1.4 The risk of a map that is too big

- [S] Innersloth's lesson from the Airship was about "the limits on how big a map should be" ([Epic](https://store.epicgames.com/news/among-us-welcomes-us-to-the-fungle-update-play-the-new-map-now)). Round 2 covers this.
- [S] A Phasmophobia Discord poll asked whether players would play Asylum more if it were half the size. Of about 19,400 votes, roughly 82% said they would play it more, and about 11% voted against making it smaller. Kinetic's CEO called Tanglewood (11 rooms) "probably everybody's favorite map because of its size" ([PCGamesN](https://www.pcgamesn.com/phasmophobia/maps-size), via search summary).
- [V] DBD shrank its suburban street map twice: patch 5.7.0 took it from 168 to 152 tiles, and patch 7.7.0 took it to 132 tiles, with "fewer houses spawning" and houses "adjusted to weaken strong loops" ([Lampkin Lane](https://deadbydaylight.wiki.gg/wiki/Lampkin_Lane)). This is the closest existing analogue to our block, and it got smaller over time, not bigger.
- [P] Perceived size is not the same as area. On Nostromo, a player said "it feels super big but statistically it's the smallest map." Another said objectives placed along the edges make a small map play big ([BHVR forum](https://forums.bhvr.com/dead-by-daylight/discussion/comment/3533586)).
- [P] Hello Neighbor 2's open neighbourhood drew criticism that each location "feels short and undercooked", and that houses are empty outside their chapter ([KeenGamer](https://www.keengamer.com/articles/reviews/pc-reviews/hello-neighbour-2-review-deluxe-edition-neither-stealth-nor-horror/), [TapTap](https://www.taptap.io/vn/post/3644875)). A neighbourhood made of thin lots is the typical failure.

### 1.5 Real-world proportions, to keep the block believable

- [V] The median lot of a new US single-family home sold in 2024 was 8,506 sq ft, about **790 m²** ([NAHB](https://eyeonhousing.org/2025/07/shrinking-lots-spec-building-new-norm/)).
- [S] Residential streets commonly take about 15 m from lot line to lot line, with 7.3 to 7.9 m of paved road. Codes set block lengths of about 150 to 550 m ([ecode360](https://ecode360.com/8911506)).

[A] What that means for us:
- Our 80 x 60 m party plot is already about **six real lots**.
- Our 6 m street is narrower than a real one.
- A real block (150 m or more) would be far too big.

So the block has to be a **compressed caricature**: a party lot that is still larger than life, neighbour lots of about 400 to 800 m², and one short street. That fits the parody tone. Nobody will measure the fences.

---

## 2. Fast prototyping

### 2.1 Paper and bubble diagrams first

- [V] The Level Design Book's layout page ([link](https://book.leveldesignbook.com/process/layout)):
  - a bubble diagram is ovals for rooms that "establish proportions and relationships";
  - "a bad bubble diagram is good";
  - draw **at least three** alternatives;
  - "a layout drawing cannot tell you if your level works."
- [S] Bungie's Mike Zak starts from a "napkin sketch" of the core layout hook ([Prima](https://vip-develop.primagames.com/?p=524)).

[A] For us, the paper step can be data. house-map.md already generates its floor plans (`house-map/level-*.svg`) and route tables from coordinates. A block plan with the same shape (lots as rectangles, gates and gaps as points, candidate mischief spots, capsules, the ship, the shop) lets an agent draw three variants as SVG, plus a table of walk and sprint times, in one session, before anyone builds geometry.

### 2.2 Scouting real places instead of inventing them

[S] House House's GDC 2020 Level Design Summit talk on Untitled Goose Game says Jake Strasser "went location scouting (with the help of Street View) for real world places" instead of building greyboxes first ([GDC](https://gdconf.com/news/come-gdc-and-see-how-untitled-goose-games-levels-were-scouted)). [V] The Level Design Book adds that the Goose Game team found research and references answered their questions better than blockouts did ([blockout](https://book.leveldesignbook.com/process/blockout)).

[A] A suburban block is the case where this works best. Real cul-de-sacs, back alleys, gaps in hedges and shared driveways already solve the "plausible shortcut" problem. The engineer, or an agent with a satellite map, can pick three real blocks, trace them at our compressed scale, and turn the tracings into the three bubble variants. This is free and quick, and it gives believable proportions.

### 2.3 A greybox in Godot under our rules

[V] Blockout rules from the Level Design Book ([link](https://book.leveldesignbook.com/process/blockout)):
- hallways at least **twice the width** of the scale figure;
- walls **150 to 200%** of the figure's height;
- a ramp instead of stairs;
- doors are just gaps;
- "99% of the time, your blockout will not survive a playtest";
- Neon White's team made about 50 changes to one level.

[V] Our engine's constraints:
- Godot 4.7.2's API dump has `bake_static_mesh` and `bake_collision_shape` (`tools/out/godot-api/4.7.2/extension_api.json`).
- Our level rules forbid CSG collision anyway (`levels/CLAUDE.md:25-27`).
- [S] FuncGodot (TrenchBroom brushes into Godot scenes) has a 2025.12 build that targets Godot 4.5 ([asset library](https://godotengine.org/asset-library/asset/edit/20080)).

[A] The cheapest route that needs no new dependency: **one scene per lot, built only from box `StaticBody3D`s** using the existing greybox materials, on the whole-metre grid. Place the lots in a test map, not in the House, as the greybox already is (#767). FuncGodot would be an addon, so per CLAUDE.md it needs the engineer's word, and our box rule makes it unnecessary.

### 2.4 Playtest protocol and metrics

- [S] Valve's GDC 2009 talk: "Game designs are hypotheses; Playtests are experiments". A playtest is "Not bug testing; Not game balancing; DEFINITELY not focus testing" ([slides](https://cdn.fastly.steamstatic.com/apps/valve/2009/GDC2009_ValvesApproachToPlaytesting.pdf)).
- [S] Hi-Rez put greybox maps for Paladins into a public test queue (Andrew Yoder, GDC 2018) ([Vault](https://gdcvault.com/play/1025183/Level-Design-Workshop-The-Holy)).
- [S] Bungie playtested "in the mornings and the evenings" ([80.lv](https://80.lv/articles/interview-working-on-the-maps-for-halo-games/)).
- [S] Innersloth moved one vent and had to recheck tasks, sabotages and abilities ([Epic](https://store.epicgames.com/news/among-us-welcomes-us-to-the-fungle-update-play-the-new-map-now)). So change **one thing per round** of tests.

[A] A protocol sized for one engineer, a few friends, and bots (`tools/run.sh bots`, `playcheck` and `perf` exist: `--help`, checked live). All thresholds are placeholders:

| Step | What | Pass mark |
|---|---|---|
| Bots, no humans | Walk time matrix between the ship, the shop, every capsule, every mischief spot, the street | No mischief spot more than 20 s walk from the party house door; capsule to nearest task 15 s or less (round 2) |
| 4-player session, 3 matches | One variant with lots closed | Time to first encounter 20 s or less; no lot unvisited in a match |
| 10-player session, 3 matches | Same variant with lots open | No lot holds more than 30% of player-time; voice-pair share at or above the random baseline (22%) |
| Observe, don't explain | Note where players stop, get lost or ask "where is…?" | Fewer than 2 "where is" questions per match by match 3 |
| Two questions after each match | "Where was the funniest moment?" "Where did you feel alone too long?" | Answers point to different lots |
| Change one thing | Only between sessions | — |

### 2.5 How small teams iterate

- [S] PEAK's core was built in a one-month jam in February 2025 by seven developers (three from Aggro Crab, four from Landfall) and released in June ([Inverse](https://www.inverse.com/gaming/peak-steam-landcrab-friendslop-update-interview-nick-kaman-pc)).
- [V] R.E.P.O.'s co-founder Walter Tischkewitz: "Let's just fail quickly this time", meaning the studio bet on a cheaper, riskier project after a six-year previous game ([Yahoo/GamesRadar](https://tech.yahoo.com/gaming/articles/lets-just-fail-quickly-time-222337087.html)).
- [S] Lethal Company has a hand-made outdoor map for each moon and an interior randomly generated from a few types ([wiki](https://lethalcompany.wiki.gg/wiki/Moons)).

[A] The common thread: **a fixed hand-made frame plus random content inside it.** That suits a one-engineer team better than more area. Build the block once, then randomise which spots and lot variants are active.

---

## 3. Places that carry a mission

### 3.1 The vehicle as the hub

Three successful co-op games anchor the whole run on a vehicle:
- **Lethal Company's ship:** players must be back on board before midnight, or the autopilot leaves without them [S] ([Wikipedia](https://en.wikipedia.org/wiki/Lethal_Company)). Its terminal is the store [S] ([Prima](https://primagames.com/tips/all-terminal-commands-in-lethal-company)).
- **Phasmophobia's truck:** it holds the surveillance computer with up to five live feeds, from fixed CCTV (from one camera up to 15, depending on the map) and from cameras players place [S] ([wiki](https://phasmophobia.fandom.com/wiki/Video_Feed), [Kinetic v0.13](https://www.kineticgames.co.uk/blog/phasmophobia-chronicle-v013)).
- **R.E.P.O.'s truck:** each level starts at it, it heals a little, and the shop sits between levels [S] ([Dot Esports](https://dotesports.com/indies/news/how-to-extract-in-r-e-p-o)).

[A] The pattern: **one vehicle is the start, the monitors, the shop or terminal, and the clock.** For us the ship can be all of that, while the House stays the party. That also answers m8-match §1's open question about what the garage's tech becomes once the ship is the lobby.

### 3.2 A landmark that anchors navigation, and the vantage risk

- [S] Disney's "weenie": the castle pulls visitors down Main Street, and further landmarks pull them left and right at the hub. Scott Rogers' GDC 2009 talk carried the idea into games ([above-the-garage](https://www.above-the-garage.com/wienies/), [Boing Boing](https://boingboing.net/2009/03/27/gamedesign-lessons-f.html/amp)).
- [V] Valorant's Split had a central tower with bulletproof glass. In playtests "players were fighting over it" instead of the site, so the team split it into two smaller towers and removed the glass ([The Spike](https://www.thespike.gg/news/the-design-behind-split-explained/192)).

[A] This is the engineer's roof problem exactly: one vantage point that sees everything takes over the game. The fixes are to split the vantage and block the lines of sight:
- the ship itself is a big object in the yard;
- hedges and fences taller than eye height;
- lots that bend behind the house.

Then the roof sees the street and the front yards, but not the back gardens. A ship that is visible above the roofs from every lot gives orientation (a weenie). A ship that blocks the roof's view of part of the yard gives cover. One object can do both.

### 3.3 Spawn settings: one start point or random

| Game | Start | Source |
|---|---|---|
| Lethal Company, Phasmophobia, R.E.P.O. | Everyone at the vehicle | as §3.1 |
| Among Us, the Skeld | At or near the cafeteria table | [S] [Steam](https://steamcommunity.com/app/945360/discussions/0/744883149453935674) |
| Among Us, the Airship | Each player picks from 3 random options, at the start and after meetings | [S] [Santa Clarita Library](https://teens.santaclaritalibrary.com/2021/04/30/new-among-us-map-airship/) |
| Hunt (DeSalle) | Teams at random spawn points, "no two teams … within 110 meters" | [V] [wiki](https://huntshowdown.wiki.gg/wiki/Maps) |

[A] The two settings the engineer wants give two different first minutes:

**Everyone in the ship:**
- *For:* a crowd moment with everyone in voice range at once (comedy, a briefing, "who goes to the shop?"); the landmark is learned in match one.
- *Against:* the ship's own tasks are done first by default, so ship tasks should need parts from far lots. The ship's exits must point at different lots, or the first 20 s is one queue at one door.

**Random places:**
- *For:* instant spread and early suspicion ("why were you behind the neighbour's shed?").
- *Against:* new players can be lost. A random place should be a capsule-quality spot (two exits, a visible landmark), and the ship must be visible from it.

A middle way exists too: random places drawn from a small set, with a minimum distance between players (Hunt-style).

### 3.4 The shop run

[S] The genre keeps its shops in a separate, known place: Lethal Company sells at the Company building on its own moon ([Prima](https://primagames.com/tips/all-terminal-commands-in-lethal-company)), and R.E.P.O. buys at a service station between levels ([itemlevel](https://itemlevel.net/repo-complete-beginners-guide/)).

[A] For us, a shop on another lot along the street is a forced crossing of public space. It is a sure encounter point and a place for alibis ("I was at the shop"). Rough numbers:
- At 40 to 60 m from the party house's door, a round trip is 18 to 27 s walking, about 14 to 20 s with sprints, plus the buying.
- The engineer's "unlimited money, a clear list" fits the existing Delivery-by-meaning style: the list says what, the shelf shows where.
- A human can buy the wrong thing, or "lose" the bag on the way back.

The shop should not be a dead end: give it a front door to the street and a back door to an alley.

### 3.5 The street as the finale stage

- [V] In Killer Klowns from Outer Space: The Game (2024), 3 players hunt 7 in 15-minute matches. There are four escape routes, and with 30 s left a truck crashes through a wall to open a fifth ([Wikipedia](https://en.wikipedia.org/wiki/Killer_Klowns_from_Outer_Space:_The_Game)).
- [V] In DBD, opening an exit gate takes 20 s and starts the Endgame Collapse ([Exit Gates](https://deadbydaylight.wiki.gg/wiki/Exit_Gates)). [S] The timer is 2 to 3 minutes, depending on the source ([patch notes](https://deadbydaylight.fandom.com/wiki/Patch_Notes_2.7.X)).

[A] A finale that arrives at a known edge (the street) makes the last minute readable: everyone knows where the danger comes from. In 60 s a walker covers 270 m, so in the cops' minute nobody is too far from anything on a compact block. The stage matters for drama, not for distance. A place to stall the cops (m8-match §5) could stand on the street side, where a hidden human who offers to stall them is seen going there and can be watched.

### 3.6 Security cameras

- [S] In Among Us, a red light blinks on every camera while someone watches. The Skeld has 4 camera views and Polus 6. MIRA HQ has a door log of the last 20 people through its sensors instead of cameras ([wiki](https://among-us.fandom.com/wiki/Guide:Security), [BreezeWiki](https://breezewiki.discard.no/among-us/wiki/Camera)).
- [S] Rainbow Six Siege's bulletproof camera was made to force a choice on attackers: deal with it or accept the risk ([Ubisoft](https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/6KlY4IEhecnajBCIzPc89l/dev-blog-observation-tool-changes-and-bulletproof-camera)).

[A] Cameras are a remote vantage, so they bring back the roof problem unless they have a tell (someone is watching), a counter (a cover, a cut wire, a mischief) and limited coverage (a few views of public spaces, never the back gardens). The ship's monitors are a natural home: watching then costs you the ship's position.

### 3.7 "Known kind, unknown place" at block scale

- [S] In Hunt, clues found at compounds rule out other compounds as the target's location ([BreezeWiki](https://breezewiki.discard.no/huntshowdown/wiki/Maps)).
- [V] Phasmophobia picks among variants at load time and shows players which one with small decor ([Kinetic](https://kineticgames.co.uk/news/phasmophobia-quality-of-life-part-2-preview)).

[A] For the anger meter: give each lot 2 or 3 candidate spots per kind of mischief (a bin, a speaker, a barbecue), and activate a random subset (for example 4 of 12). The aliens' marker could name the lot or the side of the block ("complaints from the back alley"), not the spot. Searching then has geography: narrow down the lot, then find the spot, which is a short hunt rather than a map-wide one.

---

## 4. Cross-game patterns

1. **Density is protected; area follows.** DBD grows a map 22% for twice the players. Phasmophobia closes wings for quick games. Among Us players found the small maps cramped at 15. [V]/[S]
2. **Suburban maps shrink over time.** Lampkin Lane went from 168 to 152 to 132 tiles, with fewer houses. [V]
3. **Thin lots are the failure of open neighbourhoods.** Every enterable place needs a reason to be there. [P]
4. **One vehicle is the hub:** the start, the monitors, the shop, the clock. [S]
5. **A vantage point that sees everything takes over the match.** Split it and block it. [V]
6. **A fixed frame with random content** gives replay value without more area. [S]/[V]
7. **Paper and real references come before geometry, and geometry before art.** Blockouts rarely survive their first playtest. [V]
8. **Change one thing per test,** because map changes ripple. [S]

## 5. Risks for our design

1. **The block dilutes voice.** Every 1,000 m² added cuts the random encounter baseline. At 4 players even today's House is at DBD's hiding density (§1.2).
2. **The 4-player game becomes a walking simulator** if the block is sized for 10.
3. **Empty lots.** A neighbour lot without a mischief spot, a capsule, a shortcut or a secret is dead area.
4. **The vantage problem comes back** through the ship's height, the cameras or a shared street with long sightlines (§3.2, §3.6).
5. **The ship start becomes a queue,** or always resolves the ship's tasks first (§3.3).
6. **Rebuilding the art plot is expensive.** `levels/house/outdoor.tscn` is laid out for the 80 x 60 plot, and moving its stations means re-measuring house-map §6 and §7.
7. **Equal speeds on a bigger map** make chases longer, not better (round 2, §2.2).
8. **Tunnels as map-wide teleports** erase geography (round 2, §3.1). Keep them local.

## 6. Options for the engineer (original layouts; all sizes are placeholders)

**A. Two neighbours and a shop: grow the edges.** Keep the 80 x 60 m plot and the House as they are. Add one narrow neighbour lot on each side (about 20 x 60 m, each with a small house of one or two enterable rooms and a garden) and the shop across a widened street (about 10 m).
- Ground area: about 8,500 m²; with floors, about 10,500 m².
- Per player: about 1,050 m² at 10 players, 2,600 m² at 4. So option D is needed for 4.
- The longest walk along the street is about 120 m, 27 s.
- *For:* reuses all the existing art and stations; the smallest change; neighbours' fences become the side edges of the party.
- *Against:* still a linear row; the party plot stays oversized; the back of the block stays the party's own.

**B. A shared back: houses around a common middle.** The party house and three or four neighbours face outward to the streets. Their back gardens meet in a common middle with gaps, gates and sheds, and the ship stands there.
- Size: about 100 x 100 m, with the party lot shrunk to about 45 x 50 m.
- *For:* non-linear by nature, with many short cuts between lots; the roof sees only its own side; the cops can come down any street (randomised).
- *Against:* the outdoor plot and most station positions are rebuilt; the most expensive option; four façades of art.

**C. A dead-end street: the party at its head.** The party lot closes the end of a short dead-end street. Three or four lots sit around a turning circle (about 12 m in radius), a footpath runs behind the lots, and the shop stands at the mouth of the street, about 50 m away.
- *For:* one readable finale stage (the only road in); the shop run is a clear trip out and back; easy to learn.
- *Against:* the circle is one big open space, so it needs occluders; the party lot must be re-laid on one side.

**D. A block of modules, sized by the host.** Any of A to C, built as lot scenes on fixed footprints (for example 20 x 30 m), each with two or three variants.
- A host setting (or the player count) opens 2, 4 or 6 neighbour lots. Closed lots are locked gates and a sign.
- Each match picks the variants at random; decor tells players which variant they are in, as Phasmophobia does.
- Mischief spots and capsules exist only in open lots.
- *For:* one block serves 4 and 10 players; replay value from variants; each lot is a separate unit of work for an agent and for art.
- *Against:* every variant needs its own routes measured; the closed-lot fences must not trap anyone.

**E. Under and over: a compact block that plays bigger.** Do not add lots; add routes. Two or three short tunnel links between basements, a fence-top run, a gap in the hedge, a garage that goes straight through. The tunnels are fast but noisy, and they stay local (round 2, §3.1).
- *For:* more paths without diluting density; the alien layer becomes the secret.
- *Against:* risks a maze where players miss each other; each link needs testing for chases and camping.

**F. The ship as the second hub.** Put the ship on the party lot's back half as a visible landmark that also blocks the roof's view. Inside: the "ship start" spawn, the camera monitors, and a repair mission whose parts come from the neighbour lots and the shop.
- *For:* answers the roof problem, the spawn settings, the cameras and "what the garage tech becomes" in one object.
- *Against:* concentrates attention at one place; the ship start must push players outward (exits toward different lots, tasks elsewhere).

**Recommendation [A]:** paper first, then **A + D + F** as a box greybox on a test map.
1. Draw A, B and C as data-driven SVG variants with route tables (§2.1), traced from three real blocks (§2.2).
2. Build A with module lots (D) and the ship (F) on a test map.
3. Measure with bots, then playtest at 4 and at 10 players (§2.4).

Go to B or C only if A's heatmaps show the linear-row problem the engineer describes. Add E's links one at a time, only where the measurements show a gap.

## 7. Open questions for the engineer

1. What density target? For example 700 to 1,200 m² per player at 10, and no more than DBD's 1,800 at 4.
2. Should the host close lots by a setting, by the player count, or both?
3. Is the party plot allowed to shrink below 80 x 60 m, given the art cost?
4. How many neighbour houses can players enter: one room each, or only gardens and façades?
5. Where does the ship stand, and is the "ship start" the default spawn setting?
6. Does the shop stand on the street, a public space with an encounter guaranteed, or behind the block?
7. Do cameras live in the ship? What is their tell, and what counters them?
8. How many candidate mischief spots per lot, and does the aliens' marker name the lot, the side or the spot?
9. Do the cops always come from one street, or from a random one?
10. May an agent trace real blocks from a satellite map for proportions?

---

**Files used in the repo:**
- `D:\prime-game\docs\design\m8-match.md` (origin/main)
- `D:\prime-game\docs\design\house-map.md`
- `D:\prime-game\docs\design\research\2026-10-15-spacious-house-level.md`
- `D:\prime-game\content\modes\base_mode.tres`
- `D:\prime-game\core\stamina\stamina_ledger.gd`
- `D:\prime-game\levels\CLAUDE.md`
- `D:\prime-game\tools\out\godot-api\4.7.2\extension_api.json`

Sources:
- [DBD Wreckers' Yard](https://deadbydaylight.wiki.gg/wiki/Wreckers'_Yard) · [Lampkin Lane](https://deadbydaylight.wiki.gg/wiki/Lampkin_Lane) · [Distances](https://deadbydaylight.wiki.gg/wiki/Distances) · [Exit Gates](https://deadbydaylight.wiki.gg/wiki/Exit_Gates) · [Movement speed](https://deadbydaylight.wiki.gg/wiki/Movement_speed) · [Patch notes 2.7](https://deadbydaylight.fandom.com/wiki/Patch_Notes_2.7.X) · [Timesaver DBD map list](https://timesaver.gg/blog/dbd-maps-list-all-maps-realms) · [BHVR forum, Nostromo](https://forums.bhvr.com/dead-by-daylight/discussion/comment/3533586)
- [Kinetic Games QoL 2](https://kineticgames.co.uk/news/phasmophobia-quality-of-life-part-2-preview) · [Kinetic v0.13](https://www.kineticgames.co.uk/blog/phasmophobia-chronicle-v013) · [Phasmophobia Video Feed](https://phasmophobia.fandom.com/wiki/Video_Feed) · [PCGamesN Phasmophobia poll](https://www.pcgamesn.com/phasmophobia/maps-size) · [Dot Esports Phasmophobia maps](https://dotesports.com/phasmophobia/news/all-maps-in-phasmophobia)
- [Lethal Company Moons](https://lethalcompany.wiki.gg/wiki/Moons) · [Lethal Company, Wikipedia](https://en.wikipedia.org/wiki/Lethal_Company) · [Prima terminal commands](https://primagames.com/tips/all-terminal-commands-in-lethal-company) · [ProGameGuides, players](https://progameguides.com/lethal-company/how-many-people-can-play-lethal-company/)
- [Hunt Maps](https://huntshowdown.wiki.gg/wiki/Maps) · [Hunt BreezeWiki](https://breezewiki.discard.no/huntshowdown/wiki/Maps)
- [R.E.P.O. LevelScaling](https://thunderstore.io/c/repo/p/Swaggies/LevelScaling/v/0.6.4/) · [Dot Esports, R.E.P.O. extraction](https://dotesports.com/indies/news/how-to-extract-in-r-e-p-o) · [itemlevel R.E.P.O. guide](https://itemlevel.net/repo-complete-beginners-guide/) · [Yahoo, "fail quickly"](https://tech.yahoo.com/gaming/articles/lets-just-fail-quickly-time-222337087.html)
- [Inverse, PEAK](https://www.inverse.com/gaming/peak-steam-landcrab-friendslop-update-interview-nick-kaman-pc)
- [Epic, The Fungle](https://store.epicgames.com/news/among-us-welcomes-us-to-the-fungle-update-play-the-new-map-now) · [GamePressure, 15 players](https://www.gamepressure.com/S013-amp.asp?ID=12731) · [Among Us Security](https://among-us.fandom.com/wiki/Guide:Security) · [Among Us Camera](https://breezewiki.discard.no/among-us/wiki/Camera) · [Airship spawns](https://teens.santaclaritalibrary.com/2021/04/30/new-among-us-map-airship/) · [Steam, Skeld start](https://steamcommunity.com/app/945360/discussions/0/744883149453935674) · [Sportskeeda map layouts](https://sportskeeda.com/esports/among-us-full-map-layouts)
- [Killer Klowns, Wikipedia](https://en.wikipedia.org/wiki/Killer_Klowns_from_Outer_Space:_The_Game) · [KeenGamer, Hello Neighbor 2](https://www.keengamer.com/articles/reviews/pc-reviews/hello-neighbour-2-review-deluxe-edition-neither-stealth-nor-horror/) · [TapTap, Hello Neighbor 2](https://www.taptap.io/vn/post/3644875) · [The Spike, Split](https://www.thespike.gg/news/the-design-behind-split-explained/192) · [Ubisoft, bulletproof camera](https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/6KlY4IEhecnajBCIzPc89l/dev-blog-observation-tool-changes-and-bulletproof-camera)
- [Level Design Book, blockout](https://book.leveldesignbook.com/process/blockout) · [Level Design Book, layout](https://book.leveldesignbook.com/process/layout) · [GDC, Goose Game scouting](https://gdconf.com/news/come-gdc-and-see-how-untitled-goose-games-levels-were-scouted) · [Valve playtesting slides](https://cdn.fastly.steamstatic.com/apps/valve/2009/GDC2009_ValvesApproachToPlaytesting.pdf) · [GDC Vault, Yoder](https://gdcvault.com/play/1025183/Level-Design-Workshop-The-Holy) · [80.lv, Halo maps](https://80.lv/articles/interview-working-on-the-maps-for-halo-games/) · [Prima, Mike Zak](https://vip-develop.primagames.com/?p=524) · [Bungie map design PDF](https://www.jmeiners.com/shamans/papers/art/bungie_map_design.pdf) · [Game Developer guidelines](https://www.gamedeveloper.com/design/multiplayer-map-game-design-guidelines) · [Geek Vibes Nation](https://geekvibesnation.com/battlefield-player-count-vs-map-density/)
- [above-the-garage, weenies](https://www.above-the-garage.com/wienies/) · [Boing Boing, Rogers](https://boingboing.net/2009/03/27/gamedesign-lessons-f.html/amp) · [ExitLag, CS2 maps](https://www.exitlag.com/blog/counter-strike-2-maps/) · [Steam, LOCKDOWN Protocol](https://steamcommunity.com/app/2780980/discussions/0/4759830532863466412)
- [NAHB, lot sizes](https://eyeonhousing.org/2025/07/shrinking-lots-spec-building-new-norm/) · [ecode360, block length](https://ecode360.com/8911506) · [FuncGodot](https://godotengine.org/asset-library/asset/edit/20080)