# Compact compounds: farmsteads, camps and small settlements as levels, and what they mean for a dacha map

Research round for M8.2 (rebuilding the House, 2026-10-15). This is research, not a decision. Every number for our game is a placeholder. Tags: **[V]** I read the page; **[S]** search-result summary only; **[P]** opinion; **[A]** my analysis.

## 0. Method and what this builds on

- **What I read in the repo:** `docs/design/m8-match.md`, `docs/design/house-map.md`, the research index, and the four earlier level reports (spacious house, suburban block, map scale, LOCKDOWN Protocol (LP) map).
- **What I do not repeat:**
  - Lampkin Lane's shrinking, the Goose gardens, and Hunt's 1 km² with 16 compounds: block report.
  - Square metres per player and the voice-encounter baseline: map-scale report §1.
  - DBD loop tuning and equal-speed chases: spacious-house report §2.
  - LP's sector list: LP map report §1.2.
- **How I searched:** about 60 searches and fetches. Fandom wikis returned HTTP 402 (Phasmophobia, Payday, Among Us), so some facts are [S]. I found no Hunt compound page and no published building sizes for most games.
- **Real-world facts:** the dacha and Ukrainian homestead facts come from Wikipedia, museum pages and Ukrainian building-norm articles. Each is tagged.
- **One thing I left out:** the search tool sometimes added "typical sizes" with no source behind them. None of those are used here.

## 1. Mechanics first or map first? What shipped games did

The engineer's core confusion (2026-10-15) is which comes first. The evidence says neither: the best compounds design a **place and its verb as one pair**.

- **LP went mechanics first.** "We started with the core gameplay loop, designed fun and unique tasks, positioned every room and corridors to ensure interesting player interactions, and we designed the current map around these established key points" (Dev update #2, quoted in `docs/design/research/2026-10-15-lp-map-voice-settings.md` §1.1) [V].
- **Hunt went terrain first.** On Lawson Delta the team placed the river, the delta and the forest first, "then we had compounds grow up naturally around those features, the way they do in real life" ([CRYENGINE](https://www.cryengine.com/news/view/cryengine-forge-making-hunt-showdown)) [V].
- **Goose did both at once, per area.** Each area started from a setting plus a focus, for example "a pair of back gardens" plus "playing two parties against each other" (block report §1.4, [Game Developer](https://www.gamedeveloper.com/game-platforms/road-to-the-igf-house-house-s-i-untitled-goose-game-i-)) [V there].
- [A] The engineer's rule, "no place without a mechanic, no mechanic without a place", is exactly the Goose method. In practice it becomes a **place card**: one line per place saying what it is, the verb done there, which chain uses it, its two exits, and what makes it visible from afar.
  - Fill the cards before drawing a plan.
  - Places whose verb column stays empty get cut. DBD did the same when it "removed any closed houses" from Lampkin Lane (block report §1.3).

## 2. Case studies

### 2.1 Dead by Daylight, Coldwind Farm: buildings as tuned loops

| Map | Size | Main building | Openings |
|---|---|---|---|
| The Thompson House | 152 tiles = 9,728 m² (2v8: 180 = 11,520 m²) | farmhouse, two storeys, inner stairs | ground floor "has five entrances", upper floor one window |
| Fractured Cowshed | 152 tiles = 9,728 m² | barn, one storey | "four entrances", 2 windows |
| Rancid Abattoir | 140 tiles = 8,960 m² (2v8: 192 = 12,288 m²) | slaughterhouse, one storey | four entrances, 3 windows, 2 pallets |

- **Sources:** [Thompson House](https://deadbydaylight.wiki.gg/wiki/The_Thompson_House), [Fractured Cowshed](https://deadbydaylight.wiki.gg/wiki/Fractured_Cowshed), [Rancid Abattoir](https://deadbydaylight.wiki.gg/wiki/Rancid_Abattoir) [V]. A tile is 8 x 8 m.
- **The maps shrank:**
  - Cowshed went 168 → 156 (3.7.0), then 152 (7.1.0) "to include new loops, including a pallet".
  - Thompson went 160 → 152 [V, same pages].
- **The small annex:** the Killer Shack is "a small one-story building" with a window and two doorways, one with a pallet. In the beta it had one door and two windows. The basement can spawn under it, or under one of several main buildings ([Killer Shack](https://deadbydaylight.wiki.gg/wiki/Killer_Shack)) [V].
- **Landmarks:** recurring ones are the Sacrificial Tree, the Harvester, the Killer Shack and the Basement. Torment Creek's icon shows a silo ([Coldwind Farm](https://deadbydaylight.wiki.gg/wiki/Coldwind_Farm)) [V].
- **Lessons [A]:**
  1. Even a cowshed gets four doors, and the smallest shack gets two openings plus a window.
  2. A farm for 5 players is under 10,000 m², and it shrinks across patches.
  3. A cellar whose entrance moves between buildings is cheap variety.

### 2.2 Among Us, Polus and the Fungle: separate buildings on open ground

- **Polus is the cautionary case:** a mostly outdoor outpost of separate buildings with "a large, open space in the middle".
  - The lab sits behind two decontamination rooms.
  - Security is a "Doorlog" of up to 20 entries from three sensors.
  - Sources: [Sportskeeda](https://sportskeeda.com/esports/among-us-full-map-layouts), [GameWith](https://gamewith.net/among-us-wiki/article/show/22105) [S].
- **What players say about it:**
  - Polus "feel[s] like the place is a ghost town as there are few places where players naturally encounter one another".
  - Its Specimen Room is "difficult to get to and unconnected" ([Sportskeeda](https://sportskeeda.com/esports/why-the-skeld-best-map-among-us)) [S/P].
  - Players often raise movement speed to 1.25x to offset the distances (same search) [P].
- **The Fungle has three zones:** beach, mountain and mushroom wastes.
  - The mountain connects "only through 'chokepoints'": a zipline down to the beach and two ladders ([Siliconera](https://www.siliconera.com/what-does-the-among-us-fungle-map-look-like/)) [V].
  - Mushrooms release a haze that blocks vision for a few seconds (same) [V].
  - Innersloth: "the highlands gives Crewmates at a higher elevation more vision than those below" ([Innersloth](https://innersloth.com/new-map-the-fungle-out-now-emergency-meeting-38)) [S].
- **Among Us VR's Polus Point (2023)** rebuilt Polus for first person with modular rooms and nine new rooms. The team wanted players to feel the map extends beyond what they see ([Meta](https://www.meta.com/blog/among-us-vr-polus-point-new-map-schell-games/)) [V].
- **Lesson [A]:** a compound of small buildings fails when open ground separates them. It works when the ground between them is itself a place, and when height changes pass through a few known transitions.

### 2.3 Rainbow Six Siege, Outback: one compound, three readable sections

- **Sections:** "We divided the map into three distinct sections – the Garage, the Motel, and the Restaurant". Each "is recognisable, even from far away" and has its own colours, with a limited number of doors between sections ([Ubisoft](https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/7q4jE2STCB2TCHta1fVBX8/new-map-outback)) [V].
- **Floors:** three stairs join the two floors, at Garage, Shark and Motel ([siege.gg](https://siege.gg/news/rainbow-six-siege-map-guide-outback)) [S].
- **Chalet's rework** added roof access, linked basement rooms by a second hallway and made the Wine Cellar a "donut" ([Gfinity](https://www.gfinityesports.com/article/rainbow-six-siege-chalet-map-rework-guide-all-changes-ps4-xbox-pc)) [S].
- **Lesson [A]:** in a dacha, each building can be one section with its own material and colour, so a glance tells you where you are.

### 2.4 Hunt: Showdown: silhouettes, readable lines, elevation

- **Silhouettes:** "we thought a lot about the compounds' silhouettes", and the brickworks' tall chimney is a landmark ([CRYENGINE](https://www.cryengine.com/news/view/cryengine-forge-making-hunt-showdown)) [V].
- **Readability:** Reynard Mill is "clear and readable, with clear lines and clear pathways… You can see your enemies and anticipate where they are going". It became "a bit of a blueprint" for later maps (same) [V].
- **Mammon's Gulch (2024):** 16 compounds, "verticality with plenty of vantage points", and "mines and oil wells to explore below that connect the two mountainous regions" ([TheSixthAxis](https://www.thesixthaxis.com/2024/07/25/hunt-showdown-1896-will-replace-the-original-in-august-sunsetting-ps4-and-xbox-one/)) [V].
- **Lesson [A]:** one tall thing per compound (a chimney, a tower, a ship) is what keeps players oriented. The underground earns its place by linking regions the surface separates.

### 2.5 Payday, Cook Off: cooking with ingredients scattered across outbuildings

- **Ingredients:** one player says the ingredients lie "in the basement, the pickup truck, and the two sheds" ([Steam](https://steamcommunity.com/app/218620/discussions/14/530646080864642917)) [S; I could not open the comment].
- **Supply:** 7 bags of ingredients at the start, plus 3 more by helicopter after a flare "when most of the ingredients in the house are gone" ([Steam](https://steamcommunity.com/app/218620/discussions/8/224446340333999367)) [V].
- **Payday 3's remake** lists "a larger map, tactical scaffolding, a new garage area" ([Starbreeze PDF](https://www.paydaythegame.com/ovk-media/2023/11/pd3-102-presentation.pdf)) [S].
- **Lesson [A]:** it is our burger chain on a farmstead. A cellar plus small sheds as ingredient sources, and a lab building as the assembly point, is a proven, readable spread.

### 2.6 The Texas Chain Saw Massacre (2023–2024): start in the cellar, leave by the yard

- **Every map starts in the basement:** "a feature on each map is the basement where all the victims and Leatherface begin". Four exits are "always present in every map" ([Wikipedia](https://en.wikipedia.org/wiki/The_Texas_Chain_Saw_Massacre_(2023_video_game))) [V].
- **Each exit needs an item:** a valve from the barn, a fuse, a car battery ([Prima](https://primagames.com/gaming/all-map-exits-in-texas-chainsaw-massacre)) [S].
- **Map size and count:** six maps, seven players.
- **Design intent:** "carving up the gameplay spaces to promote our cat and mouse philosophy… a feeling of progress as Victims moved through each zone".
  - The Family House stands "nearly alone in open grass and sunflowers", with open sightlines.
  - The Slaughterhouse is "a claustrophobic, maze-like tangle".
  - Source: ([official](https://www.txchainsawgame.com/hub/the-maps-of-texas)) [V].
- **Lesson [A]:** a farmstead can trade off openness and maze within one map. The cellar works as a shared start and a hub.

### 2.7 Phasmophobia: camps and farmhouses

- **Camp Woodwind** has "only a handful of tents, a couple of bathrooms, and the central campfire". It "only possesses one open area pathway that can be circumnavigated around the main tent", and the campfire has one entrance ([fandom via search](https://phasmophobia.fandom.com/wiki/Camp_Woodwind)) [S].
- **Maple Lodge Campsite** lists 11 tents, a reception building, toilet blocks, a cabin, a pier and two campfires ([Karotte](https://phasmo.karotte.org/maps/maple-lodge-campsite)) [V].
- **Bleasdale Farmhouse's rework** (10 March 2025): "two floors, 21 rooms, and a spacious attic", plus "a garden just outside of the main living room". The stated goal was "a more unique identity" ([press release](https://www.mynewsdesk.com/uk/swipe-right/pressreleases/phasmophobias-new-bleasdale-farmhouse-arrives-on-march-10th-3374117)) [V].
- **Grafton's rework** (August 2025) added an attic floor and resized rooms. Its teaser showed a chicken coop ([MP1st](https://mp1st.com/title-updates-and-patches/phasmophobia-new-update-1-000-021-applies-grafton-farmhouse-rework)) [S].
- **Lesson [A]:** a camp is a cluster of one-room shells around a fire, and it reads instantly. Kinetic gave its farmhouse identity by adding small distinct places, not floor area.

### 2.8 Lethal Company: two doors far apart, the second one harder

- **Two ways in:** each moon's facility has a main entrance and a fire exit.
  - On Vow, "a large valley separates" them.
  - Adamance has a valley with "a breakable bridge to each".
  - Only March has three fire exits ([wiki](https://lethalcompany.wiki.gg/wiki/Moons)) [V].
- **The ship as a fixed home:** on Titan, "the ship lands directly in front of a ladder and staircase network" (same) [V].
- **Lesson [A]:** the second door belongs on the other side of a terrain feature, at a cost (a ladder, a bridge). That is a one-building mesh.

### 2.9 PEAK: a gathering place by rule

- **The campfire rule:** it can be lit "once every player is within 19.2 meters". It burns out after 60 s while anyone is outside the radius, and it then cooks food ([wiki](https://peak.wiki.gg/wiki/Campfire)) [V].
- **Lesson [A]:** a place can force a meeting by rule. A dacha's mangal or table could gather the party for a moment, which our voice comedy needs.

### 2.10 Other compounds, briefly

- **Tarkov, Shoreline village:** houses across a bog joined by plank bridges; "walk off the beaten path… the swampy water slows you down heavily". The priest's house sits "on a hill overlooking the village… southwest of the church" ([Dot Esports](https://dotesports.com/escape-from-tarkov/news/how-to-complete-the-courtesy-visit-quest-in-escape-from-tarkov)) [S].
  - [A] Slow ground makes paths without walls.
- **R.E.P.O.:** Headman Manor's "small rooms with connecting doors and hallways… feel like a maze". The October 2025 update added two rooms to it ([Insider Gaming](https://insider-gaming.com/repo-monster-update-patch-notes-october-2025/)) [S].
- **Untitled Goose Game:** gates unlock between areas, and the finale runs back through all of them ([Wikipedia](https://en.wikipedia.org/wiki/Untitled_Goose_Game)) [S]. House House's next game, Big Walk, places players where they "can see but not hear each other" ([waxy.org, June 2026](https://waxy.org/2026/06/big-walk-and-the-magic-of-proximity-chat/)) [V].
- **LOCKDOWN Protocol (teardown):**
  - one map tuned for 5 to 8 players;
  - about eight colour-coded sectors;
  - three card-locked rooms of which first only one could open per match;
  - a card-locked shortcut corridor;
  - one alarm per sector.
  - Source: (LP map report §1.1–1.5) [V there].
- **Hitman's "snail" levels:** "They wrap around themselves, with their layers interconnected with slopes and stairways", and they "feel bigger than they really are" ([80.lv](https://80.lv/articles/the-snail-structure-of-hitmans-levels)) [V].
- **My Summer Car (and My Winter Car, Early Access 29 Dec 2025):** a Finnish countryside game where the sauna is a mechanic.
  - It heats until the thermometer reaches about 50 degrees, and water on the stones cuts stress.
  - "leaving the sauna at a high temperature for too long can cause a house fire" ([Gamepressure](https://www.gamepressure.com/my-summer-car/how-do-i-use-the-sauna/zec821); [Steam](https://store.steampowered.com/app/4164420/My_Winter_Car/)) [V].
  - [A] This answers "why a sauna?": it has a warm-up time, a resource (water, wood) and a failure that spreads (fire).

## 3. Real dachas and farmsteads in metres

| Fact | Value | Source |
|---|---|---|
| Soviet dacha plot | "usually not more than 600 m²"; rules capped it at 0.06 ha | [Wikipedia](https://en.wikipedia.org/wiki/Dacha) [V]; [PhMuseum](https://phmuseum.com/projects/six-hundred) [V] |
| A 600 m² plot | e.g. 20 x 30 m; the 1949 norm was 6 ares in cities, 12 outside | [search summary of gw2ru](https://www.gw2ru.com/lifestyle/231832-soviet-dacha-6-ares) [S] |
| House limit | "not more than 25 m² of living area and… only one story"; so a big attic (mansard) and glazed verandas became "extremely widespread and often oversized" | [Wikipedia](https://en.wikipedia.org/wiki/Dacha) [V] |
| Typical contents | "a single-story plywood house without permanent heating", "a vegetable lot, a greenhouse and flower beds"; later "attics into second floors, added glazed verandas" | [PhMuseum](https://phmuseum.com/projects/six-hundred) [V] |
| Colony lanes | "narrow (often about 6 m (20 ft) between fences)" | [Wikipedia](https://en.wikipedia.org/wiki/Dacha) [V] |
| Summer kitchen | "a separate little house… a one-room brick structure", near the fruit and vegetable plot, often with a masonry oven (pich), used for cooking and preserving | [Olia Hercules via Calvert Journal](https://www.calvertjournal.com/articles/show/11941/olia-hercules-ukrainian-summer-recipes) [S]; [Atlantic Council](https://www.atlanticcouncil.org/event/summer-kitchens/) [S] |
| Grain barn (klunia) | set apart from the house, near the vegetable garden, against fire; a museum example is 6.10 x 6.10 m | [Pyrohiv](https://pyrohiv.com/exponates/26-klunya-iz-s-vidranitsya/) [S] |
| Hutsul hrazhda | a closed yard: house plus two rows of outbuildings, roofs merged, later "connected with a roof corridors or galleries"; a roofed fence stored wood | [Green Ukraine](https://green-ukraine.com/grazhda) [V] |
| Ukrainian norms (popular legal summary of DBN B.2.2-12:2019) | house to fence ≥ 3 m; house to neighbour's house 8 m; non-residential building to fence 1 m; house to toilet with a cesspit 12 m; house to well 15 m; two storeys plus mansard at most | [protocol.ua](https://protocol.ua/ua/normativi_pri_zabudovi_dachnoi_dilyanki/) [V] |
| Fence heights | at most 2 m between neighbours and 2.5 m on the street (Pochaiv council); preferably 1.5 m and 2.2 m (protocol.ua) | [Pochaiv council](https://pochaiv-rada.pp.ua/novyny/budivelni--normy--dlya-roztashuvannya-bilya--jytlovogo-budynku-ogoroji---ta--gospodarskyh-sporud) [V] |

What this means for us [A]:
- **A real dacha is tiny.** 600 m² is one eighth of today's 4,800 m² yard (`house-map.md:24`). A one-plot dacha at real scale holds 4 players, not 10. So the map is either a **caricature plot** (an oversized "chairman's dacha") or **several plots of a dacha colony**.
- **Real rules already separate places by earshot.**
  - The outhouse sits 12 m from the house and the well 15 m: beyond our 8 m voice range and the 12 m world sounds.
  - The generator needs switch markers at least 16 m apart (`house-map.md:209-217`). A 40 x 30 m inner area holds four of them at its corners.
- **The Soviet legal joke is ready-made comedy.** The attic "is not a floor", and the veranda grew bigger than the house. That gives the engineer's three levels (cellar, ground, mansard) a reason that people from the region recognise.
- **The summer kitchen exists to cook and to keep heat out of the house.** That is exactly where burgers belong.

## 4. The topic, element by element

### 4.1 Building counts and sizes
- **Shipped compounds:**
  - DBD farm maps: one main building plus one shack plus scattered tiles.
  - Outback: one compound in three sections.
  - Woodwind: about 4 tents plus toilets plus a fire.
  - Maple Lodge: about 15 named shells.
  - Polus: about 15 rooms in separate buildings (sources above).
- [A] **For 4 to 10 players and five chains:** about 8 to 10 places.
  - 1 house of 2 or 3 rooms plus a veranda and a mansard.
  - 5 or 6 annexes of 15 to 40 m² each (one room each, two or more doors).
  - 2 or 3 open places (the vegetable patch, the mangal, the ship).
  - Everything under about 60 m² stays readable at a glance, as the shack and tents are.

### 4.2 Distances between buildings
- **Real spacing:** 1 to 15 m (norms above).
- [A] **Our numbers:** a 10 m gap is 2.2 s walking or 1.4 s sprinting.
  - Gaps under 8 m put neighbouring buildings in one voice room unless walls muffle it (`m8-match.md` §8: walls muffle voice, today pure distance).
  - Gaps of 12 to 16 m keep two places out of earshot.
  - Under 4 m reads as one building with a gap. That suits a passage: a breezeway or an alley between two sheds.
- **Polus's lesson:** no gap should be open ground with nothing in it. Put a woodpile, a clothesline, a bed of plants or the mangal in it.

### 4.3 How the buildings connect
| Link | Evidence | For a dacha [A] |
|---|---|---|
| Two doors on opposite sides | DBD barns 4, farmhouse 5, shack 2 + window; Lethal's two entrances across a valley | every annex has a yard door and a back door, or a window to climb |
| Covered walkway | hrazhda galleries; Outback's limited doors between sections | a roofed gallery from the house to the summer kitchen and the sauna: rain-free, out of the roof's sight |
| Cellar | TCSM's basement start; Coldwind's basement that moves; Hunt's mines | the cellar (pogrib) as the underground layer, with a hatch in two or three buildings |
| Roof | Chalet's roof access; the shack roof DBD made unreachable | a shed roof and the veranda roof as a high path to the mansard window; locked or unlockable |
| Gap or hole | Goose's fence hole; Polus's decontamination gate | a missing fence board to the neighbours; a gap behind the woodpile |
| One-way or slow | Fungle zipline and ladders; Tarkov's bog | a slide or drop from the mansard to the haystack; mud on the patch that slows you |
| Unlockable shortcut | LP card rooms (one of three per match); Goose gates | a padlocked gate or a cellar door opened by a key found on the map |

### 4.4 Verticality on slopes and terraces
- **Height gives sight** (Fungle, Mammon's Gulch) and has to pass through **known transitions** (the Fungle's zipline and two ladders).
- **Hitman's snail:** layers wrap around one another, so a small area feels big.
- [A] **A dacha on a slope** gives three ground levels from terrain, not floors:
  - a lane terrace;
  - a house terrace;
  - a patch terrace.
  - The retaining walls between them hold the cellars, each with a door on the lower terrace and a hatch on the upper one.
  - Each step can be 2.5 to 3 m, about one storey. The mansard sees the lower terraces but not the cellars.
- **Technical risk:** the bot scenarios read every base-mode map through a flat fake floor at y = 0 (`house-map.md:185-186`). Terraces need that fake rethought before a greybox.

### 4.5 Sightlines and cover
- **Two ways to fail:** total openness (Polus, the old Lampkin street) or total maze.
- **TCSM uses both on purpose:** the open-field Family House and the maze-like Slaughterhouse.
- [A] **For a dacha:**
  - Fences of 1.5 to 2 m, hedges, sheds and a greenhouse break the long views, but the roof and the mansard keep a few views (the earlier report's "the roof sees the yard, not inside", `house-map.md:278`).
  - Tall crops on the patch are soft cover, like the Fungle's haze.
  - The ship is the one thing visible from everywhere.

### 4.6 Landmarks and the 3D silhouette from the ground
- **Lynch's five elements** (paths, edges, districts, nodes, landmarks) are the vocabulary. "Players don't look up unless something draws their eye" ([Level Design Book](https://book.leveldesignbook.com/process/blockout/wayfinding)) [V].
- **Silhouette and colour per section:** Hunt's chimney, Outback's sections recognisable "even from far away".
- [A] **A dacha's skyline has natural spikes:**
  - the mansard's steep roof;
  - the sauna's chimney;
  - a dovecote or water tower;
  - the electric pole with its wires;
  - the well's crane;
  - the aliens' ship.
  - Give each building one material (brick summer kitchen, log sauna, corrugated shed, glass greenhouse, painted plywood house) and one colour, so that "the blue one" and "the one with the chimney" are names players use on voice.

### 4.7 Mapping to 4 to 10 players and 10 minutes
- **A compact target** [A]: about 55 x 45 m of ground (2,475 m²), plus cellars (~300 m²) and the mansard and other upper parts (~250 m²), so about 3,000 m².
  - That is 300 m² per player at 10 and 750 at 4, against today's 6,900 m², or 690 and 1,725.
- **Crossing:** the diagonal is 71 m, which is 15.8 s walking and 10.1 s sprinting (today's: 22.2 s and 14.3 s).
- **Chance of meeting:** with players at random, the expected number of others inside one player's voice circle (201 m²) is 9 x 201 / 3,000 ≈ 0.6 at 10 players and 0.2 at 4. Today's House gives 0.24 and 0.08 (map-scale report §1.2). The compact map roughly **doubles chance meetings**.
- **At 4 players:** shut one module, as Phasmophobia's Restricted variants do (map-scale report §1.3).
- **"Findable in reasonable time"** [A]: with 8 to 10 places of one room each, a hidden item needs at most one visit per place. That means a known kind of place and an unknown spot (scattered-points report), and a search lap of about 60 to 90 s.

## 5. No place without a mechanic: the dacha's places against our chains

These are ideas for the engineer, not content. He decides every place, name and rule.

| Place | Existing mechanic it could host | A possible verb if it needs one |
|---|---|---|
| Small house (2 or 3 rooms) | photo printer; hiding spots; the generator's switch | the order board for guests' requests |
| Glazed veranda | delivery drop-off (the long table); music (ongoing mischief) | the party's gathering table (a PEAK-style moment) |
| Mansard ("not a floor") | the lookout; fireworks launched from it (one-off mischief, `m8-match.md` §5); hidden loot | locked; the key is somewhere on the plot |
| Summer kitchen | burger assembly (order board, three places); the cake for the neighbours (calming) | the oven needs fuel |
| Cellar (pogrib) | storage hub (buns, meat, delivery items, parts, film); the underground layer; a capsule | jars on shelves as hiding spots |
| Sauna | a generator switch; a respawn capsule | a warm-up chain (wood plus water); left too hot it catches fire: an ongoing mischief with a reason |
| Vegetable patch | the herb beds and their code board (greenhouse); the gnome drop-off | items buried by the humans, dug up with a shovel (the "find something" step, #1033); the skeleton easter egg |
| Greenhouse | the herb board; hiding behind the plants | steam on the glass hides who is inside |
| Shed or garage | car parts; car repair (holder and fitter) | if the ship replaces the car: ship parts |
| Aliens' ship in the yard | the landmark; the lobby's link (`m8-match.md` §1) | the repair with a holder and a fitter under its hull |
| Mangal (barbecue) | the grill for the patties; "barbecue on fire" (ongoing mischief) | the forced gathering spot |
| Outhouse | a hiding spot; a capsule (comic) | a camera's blind spot |
| Well | water for the sauna | a human drops an item down it (sabotage); the bucket brings it up (a fix) |
| Electric pole and meter box | the generator's power; "the street's lights cut" (ongoing mischief) | the security cameras' feed |
| Lane, gate and the neighbours' fence | where the neighbours' anger lives; the cops arrive; the bins (ongoing mischief) | a fence gap to a neighbour plot (Option C) |

[A] Every example mischief in `m8-match.md` §5 already has a natural dacha place: the music, the barbecue, the bins, the lights, the fireworks and the cake. That is the strongest sign that the dacha fits the design.

## 6. Patterns across games

1. **Each building has at least two openings**, and the second is often harder to reach (DBD, Lethal Company).
2. **Fewer, better buildings.** Maps shrink over their lives (Coldwind, Lampkin), and closed or empty buildings get cut.
3. **Open ground between buildings kills meetings** (Polus's "ghost town"). Compounds work when the gaps are short and the paths cross.
4. **One section, one look.** Colour, material and silhouette per section, plus one tall landmark (Outback, Hunt).
5. **The underground links what the surface separates**, and it can be the start (TCSM, Mammon's Gulch, Coldwind's moving basement).
6. **Height gives information but passes through a few chokepoints** (Fungle, Mammon's Gulch).
7. **A place can gather players by rule** (PEAK's 19.2 m campfire).
8. **Shortcuts are unlocked, rationed or one-way** (LP's cards, Goose's gates, the Fungle's zipline).
9. **Slow ground and soft cover shape paths without walls** (Tarkov's bog, the Fungle's haze).
10. **Places and verbs are designed as pairs** (§1).

## 7. Risks for our design

- **Polus at dacha scale.** Too many small buildings on open grass give long empty walks. Mitigation [A]: gaps under about 12 m, every gap furnished, at least one place where the chains cross per terrace.
- **Cramped one-room annexes break the spaciousness rule** (`m8-match.md` §8, #1035). A 4 x 5 m sauna is a box. Use open sides, verandas, windows to climb and high ceilings under pitched roofs.
- **Endless loops with equal speeds.** A two-door shed is a DBD shack without the faster killer (spacious-house report §2.2). Doors, vaults and drops need asymmetric costs.
- **Voice bleed between close buildings.** Below 8 m, two annexes share a voice room unless walls muffle. The muffling rule (#1035) becomes load-bearing, not optional.
- **Terraces break the bots' flat fake** (`house-map.md:185-186`), and stairs and ramps multiply.
- **Too compact at 10 players.** Kitchen and cellar crowds make kills by grenade trivial (`m8-match.md` §7). Every hub place needs a second exit.
- **Rebuilding resets work.** The House's station placements, its tests (`tests/integration/levels/house_drop_offs_test.gd`) and #1035 to #1037 change.
- **Cultural reading.** Outside Eastern Europe a dacha reads as "a country cottage". The parody frame (bad broadcasts) can carry it, but the legal and comic quirks (the "not a floor" attic) land mostly with people from the region.
- **The content area.** Every place, name and number here needs the engineer's word (CLAUDE.md, Ownership).

## 8. Options for the engineer

All are original. Sizes are placeholders for a greybox.

### Option A: "Three terraces" (a dacha on a slope)
About 55 x 45 m, three ground levels 2.5 to 3 m apart:
- **Top terrace, by the lane:** the gate, the shed or garage, the electric pole, the bins.
- **Middle terrace:** the house with its veranda and mansard, the summer kitchen, the sauna, the mangal.
- **Bottom terrace:** the vegetable patch, the greenhouse, the well, the outhouse, and the ship landed across the bottom.

Cellars dug into the two retaining walls each open on the lower terrace and by a hatch on the upper one. Two stairs and one ramp per step.
- **Plus:** the 3D interest comes from the ground itself; the mansard sees down but not into the cellars; a natural snail (Hitman); the ship's silhouette reads from above.
- **Minus:** the bots' flat fake must change; more stairs to tune; some sightlines from above may be too strong.

### Option B: "Courtyard ring" (a closed yard of linked buildings)
- **Layout:** a 40 x 40 m enclosure. The house and annexes form a ring around an inner yard of about 16 x 16 m, joined by a roofed gallery, as in a hrazhda. An outer garden ring of 8 to 10 m holds the patch, the well and the ship.
- **Loops:** two loops (the inner yard and the outer garden) plus the gallery's roof as a third, unlockable one.
- **Plus:** very compact; a mesh by construction; the gallery is a covered route out of the lookout's sight.
- **Minus:** flatter; the ring may feel symmetric and learnable fast. Break the symmetry with one big building and one gap.

### Option C: "Three plots" (a slice of a dacha colony)
- **Layout:** our party plot of about 30 x 40 m, plus two neighbour plots of about 20 x 30 m across a 5 m lane, about 2,800 m² in all.
- **The neighbours' plots** hold the anger meter's targets (windows, a dog, a garden) and the cake's destination. Fence gaps and a shared cellar link them.
- **At 4 to 6 players** one neighbour plot is fenced shut.
- **Plus:** the anger mechanic gets a physical home; it scales by modules; the neighbours are real places, not filler.
- **Minus:** more art; the risk of thin neighbour plots (Hello Neighbor 2's criticism, map-scale report §1.4).

### Option D: "The long annex" (a farmstead under one roof)
- **Layout:** a row of annexes about 6 m wide and 45 m long under one roof (veranda, kitchen, sauna, shed, garage), with a loft running over all of them. Yards lie on both sides, and every annex has a door to each yard.
- **Plus:** a ladder-shaped mesh; strong silhouette; cheap to build.
- **Minus:** linear; the loft becomes a super-highway unless its hatches are few.

### Option E: "Cellar web" (flat plot, rich underground)
- **Layout:** a flat plot of about 50 x 40 m with simple buildings. Each building has a hatch into a shared cellar network of about 300 m² (pogrib, wine cellar, a dug passage).
- **Plus:** the underground layer does the meshing; no terrace problem for the bots above ground.
- **Minus:** a dark underground that everyone hates if it is big (Polus's isolated Specimen Room). It must stay short.

### Option F: "The ship on the patch" (the landmark is a building)
- **Layout:** the aliens' ship landed across the plot. Its hull is a bridge from the mansard window to the shed roof, its underside a covered space, its interior one room (the ship repair).
- **Plus:** the landmark becomes a building with a purpose; the alien comedy is visible from everywhere.
- **Minus:** it ties the map to the lobby-ship story, which is still open (`m8-match.md` §1).

### Recommendation [A]
- **The frame:** take **Option A**, using **Option E's** cellars as the links between terraces.
- **Large lobbies:** keep **Option C's** neighbour plot as a module for 8 to 10 players.
- **The landmark:** add Option F's ship as the landmark if the story allows.
- **Before a greybox:** fill one place card per place (§1) and redraw the five chains on paper, with travel times measured against the House's table (`house-map.md` §7).
- **The greybox:** start at about 55 x 45 m. Make the bots' fake floor work on terraces first.

## 9. Open questions for the engineer

1. **Scale:** one oversized plot, or a slice of a colony (Option C)? And roughly how big: about 3,000 m² against today's 6,900?
2. **Ground:** a slope with terraces (A), or flat with cellars (E)?
3. **The house:** does it keep a second floor, or only the "not a floor" mansard?
4. **Mechanics:** which chain moves to which place? Does the sauna get its own chain or only host a switch, a capsule or a mischief?
5. **The ship:** is it a building on the plot (F), a backdrop, or the lobby only?
6. **Shortcuts:** which ones unlock, and how (a key, points, a one-off rationing as in LP)?
7. **Voice:** muffling through walls (#1035) becomes essential at these distances. Does it come before the rebuild?
8. **Low player counts:** does the map shrink by shutting a module?
9. **The House:** does it stay as a second map, or is it replaced?

### Sources
Every URL is cited inline above. Repo files read: `D:\prime-game\docs\design\m8-match.md`, `D:\prime-game\docs\design\house-map.md`, `D:\prime-game\docs\design\research\README.md`, and these earlier reports in `D:\prime-game\docs\design\research\`:
- `2026-10-15-lp-map-voice-settings.md`
- `2026-10-15-map-scale-and-prototyping.md`
- `2026-10-15-spacious-house-level.md`
- `2026-10-15-suburban-block-maps.md`