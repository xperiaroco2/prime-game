# Manors and estates as levels: research for the estate party map (M8.2)

## 0. Method and what this builds on

- **Read first in the repo:**
  - `docs/design/m8-match.md` (the story, the neighbours' anger and the cops at §5, the House at §8);
  - GDD §1 (pillars) and §13 (the House: 80 x 60 m, four levels);
  - `docs/design/house-map.md` §2 to §4;
  - the research index.
- **No "dacha" report.** The index (`docs/design/research/README.md`) has no report by that name. I used the nearest ones: the spacious House (`2026-10-15-spacious-house-level.md`), suburban blocks, map scale, scattered points and secrets, and the LOCKDOWN Protocol map teardown. Their numbers and rules are reused below, not repeated.
- **Searches:** about 60 web searches and fetches. Many wikis and publishers refused the fetch (HTTP 402, 403, 404, 525, or truncated PC Gamer, TechRadar and GamesRadar pages).
- **Tags:**
  - [V]: the fetched page says it.
  - [S]: only a search-engine summary says it.
  - [P]: opinion.
  - [A]: my analysis.
- **Our numbers** (from the task): walk 4.5 m/s; sprint 7 m/s for 5 s, then about 5.6 m/s; jump 1 m; voice 8 m.
- **Sprint time** over a distance d > 35 m is 5 s + (d − 35)/5.6.

## 1. The real country house: rooms and their old jobs

| Room | What it was for (sourced) | What it could carry for us [A] |
|---|---|---|
| Servants' hall | [V] Coleshill House (1650) had the "first purpose-built servants' hall in the basement". Belton House's semi-basement held "kitchens, pantries and servants' dining halls" ([Servants' quarters](https://en.wikipedia.org/wiki/Servants%27_quarters)) | The service floor: half underground, it can open at grade onto a lower terrace |
| Butler's pantry, plate room | [S] Used to clean, count and store silver; the butler often slept there and kept the silver and the wine cellar "under lock and key". Tredegar House has a safe room off the pantry, and Lynnewood Hall hides 14 safes behind its pantry ([Temple Newsam](https://museumsandgalleries.leeds.gov.uk/blog-the-butler-s-pantry-at-temple-newsam-house-tvfc), [People's Collection Wales](https://www.peoplescollection.wales/items/11076), [Untapped Cities](https://untappedcities.com/2023/08/31/lynnewood-hall-abandoned/2/)) | Keys and locks (house-map decision 12, "later"); the wine chain's start |
| Billiard and smoking room | [V] Part of the 19th-century "male suites", paired with smoking rooms and sometimes libraries; about 1.5 m of clearance round the table ([Billiard room](https://en.wikipedia.org/wiki/Billiard_room)). [V] At Biltmore a hidden door leads from the billiard room to the smoking and gun rooms ([Biltmore](https://biltmore.com/blog/behind-biltmores-hidden-doors)) | A furniture island (a loop); a real precedent for a secret door between two rooms |
| Library | [V] At Biltmore, doors on both sides of the library overmantel open into a passage to the second-floor living hall (same source) | The bookcase door the engineer asked for, as a back stair up |
| Breakfast room | [V] At Biltmore a hidden staff door below a painting let "servants enter with hot meals" (same source) | A hidden service door behind a portrait |
| Conservatory, winter garden | [V] At Biltmore a trap door under marble slabs lets plants move between the conservatory and the floor below "without disturbing guests" (same source) | A floor hatch from the glasshouse to the service floor |
| Orangery | [V] Built to winter orange trees. The working rule: a conservatory has over 75% of its roof glazed, an orangery less. Versailles' orangery measures 155 x 13 m for about 3,000 trees ([Orangery](https://en.wikipedia.org/wiki/Orangery)) | The alien botanical garden; the herb chain's greenhouse moves here |
| Summer kitchen | [S] Kept apart from the house for heat, smell and the "dangers of fire", and sited so the wind carried the smoke away ([Locust Grove](https://locustgrove.org/learn/places/outbuildings/kitchen/), [HMDB](https://www.hmdb.org/m.asp?m=188201)) | The grill and the ongoing "barbecue on fire" mischief (m8 §5) have a historical reason to sit here |
| Ice house | [V] Hampton Court's was a brick-lined well 9.1 m deep and 4.9 m wide. British ones were usually domed, mostly underground, with a drain ([Ice house](https://en.wikipedia.org/wiki/Ice_house_(building))) | A cold store (the raw meat); a domed mound as a landmark; a way down |
| Carriage house | [V] Housed carriages and tack, "often two stories, with related staff quarters above", and was later turned into garages ([Carriage house](https://en.wikipedia.org/wiki/Carriage_house)) | The car repair (house-map decision 9) with a loft above |
| Gatehouse | [V] Controls who enters; on estates it became a "grand entrance structure" joined to the house only by a wall ([Gatehouse](https://en.wikipedia.org/wiki/Gatehouse)) | Where the cops arrive; the "stall the cops" station (m8 §5) |
| Wine cellar | [S] In the butler's charge and kept locked (Temple Newsam, above) | Today's wine drop-off chain |
| Very large houses | [S] Biltmore has about 178,926 sq ft and 250 rooms, a basement pool and a bowling alley, with servants on the fourth floor ([EBSCO](https://www.ebsco.com/research-starters/architecture/biltmore-estate)) | Only a reminder of how far a caricature must compress |

## 2. Hidden circulation

- **Service routes were long by design.**
  - [V] "Long and complicated passages linking kitchens with dining rooms were devised", up to "an eighth of a mile" (about 200 m).
  - [V] The one door between the family side and the service side "was lined with green baize to deaden any sound".
  - [V] Connecting doors were disguised as bookcases or with matching wallpaper, because "the existence of servants was not to be acknowledged".
  - [V] Castle Coole's servants' quarters were reached by a single tunnel.
  - Source for all four: [Servants' quarters](https://en.wikipedia.org/wiki/Servants%27_quarters).
  - [A] 200 m takes 44 s at a walk. That is exactly the long hidden passage Arkane warned about (§4.3). Keep the idea and compress the length.
- **The baize door is a real "walls muffle voice" object** [A]. One known door where sound stops is a readable voice rule (m8 §8).
- **Dumbwaiters.**
  - [V] A small freight lift for food, usually 45 to 450 kg, hand-hauled on ropes until the 1920s.
  - [V] Jefferson used them to keep fewer servants near the dining room, which allowed "more private conversations".
  - [V] British maids sent laundry down them.
  - Source: [Dumbwaiter](https://en.wikipedia.org/wiki/Dumbwaiter). [S] At Biltmore, meals reached the butler's pantry "via dumbwaiters" ([Biltmore search summary](https://biltmore.com/blog/exploring-the-butlers-pantry)).
- **Bell boards.**
  - [S] Each bell on the board was labelled with its room, and a pendulum kept swinging after the ring stopped, so a servant who came late still knew which room had called. Bells of different sizes could also be told apart by ear ([Servant bell](https://en.wikipedia.org/wiki/Servant_bell)).
  - [A] This is a period-correct information tool. It can say "which room" without saying "what", or the reverse, which fits m8 §9's open question about hinting the type of a problem without its place.
- **Priest holes.**
  - [V] Hides were usually in or around chimney stacks and staircases. Harvington Hall has seven, reached through the main staircase, panelling and a false fireplace; one opens by tilting a stair step.
  - [V] Edmund Campion was found in 1581 because searchers "saw light between two planks". Searchers rarely found an occupied hide without an informant.
  - Source: [Priest hole](https://en.wikipedia.org/wiki/Priest_hole).
  - [A] The lesson for us is the tell: a hide should leak a small, learnable clue (light, a draught, a sound).
- **Hidden doors are usually mundane.** [S] The National Trust says false bookcases hiding passages appear in "many country houses" but often have "quite a mundane reason for existing" ([search summary of nationaltrust.org.uk](https://www.nationaltrust.org.uk/features/secret-doors); the fetch was blocked). [A] A hidden door works best as a service route that happens to be secret, not as treasure.
- **Tunnels.** [S] The 5th Duke of Portland's tunnels at Welbeck are estimated at 3 to 15 miles, and the underground ballroom at 49 to 53 m long; sources disagree ([Atlas Obscura](https://assets.atlasobscura.com/articles/the-duke-who-loved-tunnels-so-much-he-was-immortalized-as-a-literary-badger), [DiCamillo](https://thedicamillo.com/house/welbeck-abbey)). [A] Good parody material (an eccentric lord's tunnels); a bad model for distances.

## 3. Formal gardens, with real dimensions

### 3.1 Terraces, parterres, the ha-ha
- **Parterres were made to be read from above.** [V] "The view of a parterre from inside the house, especially from the upper floors, was a major consideration". Raised terraces were built for the purpose, and hedging was "very low, to enable the patterns to be readable from the main rooms" ([Parterre](https://en.wikipedia.org/wiki/Parterre)).
  - [A] A parterre is open ground, overlooked by design. That makes it a natural "look-up" station (m8 §6a): a pattern you can only read from the terrace or a window.
- **Terrace scale.** [S] Powis Castle has four terraces about 150 m long, with lead statues along the balustrades ([Parks and Gardens](https://www.parksandgardens.org/places/powis-castle)). [A] That is longer than our whole map.
- **The ha-ha.**
  - [V] A sunken wall that "creates a vertical barrier" but leaves the view open, so the garden and the landscape look "one and undivided". Depths run from about 0.6 m (Horton House) to 2.7 m (Petworth).
  - [V] The name is said to come from the surprised cry of people who found the drop.
  - Source: [Ha-ha](https://en.wikipedia.org/wiki/Ha-ha).
  - [A] With our 1 m jump, a drop of 1.2 m or more is a **one-way edge**: you can drop down but cannot climb back. That is the chase asymmetry the spacious House report asked for (§2.2: "one-way drops"). It is also a joke players find by walking into it.

### 3.2 Garden rooms
- **Hidcote.**
  - [V] Rooms walled by box, hornbeam, yew and stone walls, "linked, some by vistas" ([Hidcote](https://en.wikipedia.org/wiki/Hidcote_Manor_Garden)).
  - [S] One source gives 10.5 acres (about 42,500 m²) and 21 rooms, unconfirmed ([Spokesman](https://spokesman.com/stories/2011/sep/25/touring-the-historic-hidcote)).
  - [S] The windswept site "doubtless led" to the hedging (same search).
- **Sissinghurst.** [V] The gardens "occupy only 5 acres" (about 20,200 m²) of a 450-acre estate, made of rooms of "high clipped hedges and pink brick walls", with one main west–east vista through the tower gateway ([Sissinghurst](https://en.wikipedia.org/wiki/Sissinghurst_Castle_Garden)).
  - [A] Real garden rooms are about 1,000 to 2,000 m² each. Ours must be about a tenth of that.
- **Bosquets.** [V] Hedge-walled groves in French gardens; "often a single path with a discreet curve or dogleg provided the only access", and "inside the bosquet, privacy was assured" ([Bosquet](https://en.wikipedia.org/wiki/Bosquet)). [S] Le Nôtre designed about fifteen at Versailles, set in the squares of a grid of avenues ([gardentours](https://www.gardentours.com/topics/garden-travel-blog/versailles-gardens-experts-guide-beyond-the-crowds/)).
  - [A] The dogleg entrance hides the inside from the avenue: a perfect sabotage nook. Its single entrance, though, is the dead end the 30 s respawn punishes (spacious House risk 3).
- **The claire-voie.** [S] A "window" cut through a hedge or wall, sometimes with a grille, framing another part of the garden ([Designing Buildings](https://designingbuildings.co.uk/wiki/Claire-voie)). [A] This is Paul Martin's "see but not reach" (spacious House §5) in garden form.

### 3.3 Mazes
- **Hampton Court.**
  - [V] Planted 1689 to 1695 on "about one-third of an acre" (about 1,350 m²); hornbeam replaced by yew; reaching the middle takes "about 20 minutes" ([Hampton Court Maze](https://en.wikipedia.org/wiki/Hampton_Court_Maze)).
  - [S] Its longest side is 222 ft (about 68 m), with half a mile (about 800 m) of path and hedges about 7 ft (2.1 m) high ([sacred-texts, 1922 history](https://sacred-texts.com/etc/ml/ml18.htm), [CSMonitor](https://csmonitor.com/1985/0820/umaze.html)).
- **Longleat.** [V] 2.72 km of path, over 16,000 yews and six raised footbridges ([Longleat](https://en.wikipedia.org/wiki/Longleat)).
- **The Labyrinth of Versailles (1672–1677)** [V]:
  - 39 fountains, each an Aesop fable, with 333 painted metal animals;
  - "no central goal";
  - "at every turn" a fountain appeared;
  - hedges about 5 m high that still "allowed glimpses ahead";
  - a plaque at each fountain and a printed guidebook;
  - removed in 1778 for its upkeep cost.
  - Source: [Labyrinth of Versailles](https://en.wikipedia.org/wiki/Labyrinth_of_Versailles).
- **Small mazes.** [S] Home-maze guides give 0.76 to 0.91 m paths for one walker, 1.07 to 1.52 m for two, hedges of 3 to 7 ft and a footprint of 6 x 6 to 15 x 15 m ([gardeningbeyond](https://gardeningbeyond.com/?p=45353)); low quality, a starting point only.
- **[A] What this means for our speeds:**
  - Hampton Court's 800 m of path takes 178 s to walk once. A 10-minute match cannot carry that.
  - A placeholder maze of 24 x 24 m (576 m², 43% of Hampton Court) with 2 m paths and 0.8 m hedges has a corridor pitch of 2.8 m, so at most about 200 m of path. Walking all of it takes about 45 s; a direct solve takes 10 to 20 s.
  - The 2 m width lets two first-person players pass.
  - Versailles is the right model for a party game: **a maze of stations without a centre**, where every turn shows something.

### 3.4 Follies, pavilions, glasshouses, walled gardens, trick fountains
- **Follies.** [V] "A building constructed primarily for decoration, but suggesting through its appearance some other purpose": sham ruins, pyramids, pagodas, and at Painshill "a hermit's retreat with resident hermit" ([Folly](https://en.wikipedia.org/wiki/Folly)). [A] The folly is the estate's licence for alien absurdity: a building that pretends to be something else.
- **Glasshouses.** [V] Kew's Palm House (1844–48) has "an upper walkway, taking the visitor into the branches" ([Palm House](https://en.wikipedia.org/wiki/Palm_House,_Kew_Gardens)). [A] A gallery inside the orangery is a second level and a vantage in one.
- **Walled kitchen gardens.** [V] "One acre … feed[s] twelve people". They range from 1 to 30 acres. The walls make a warmer microclimate for fruit trained on them; Croome Court had a 4.0 m hot wall with furnaces ([Walled garden](https://en.wikipedia.org/wiki/Walled_garden)).
- **Trick fountains at Hellbrunn** (1613–19) [V]:
  - a prince-archbishop's "series of practical jokes";
  - jets in the stone seats round a stone table soak the guests, while the host's seat "is never wet";
  - hidden jets spray visitors along the paths;
  - a 1750 water-driven theatre has "some 200 automata".
  - Source: [Hellbrunn](https://en.wikipedia.org/wiki/Hellbrunn_Palace).
  - [A] A real 400-year-old aristocratic tradition of pranking your own guests: cringe party comedy with a pedigree, and a surprise players find only by playing.

### 3.5 Hedges and sound
- [S] A 2019 field study measured hedges cutting noise by about 2.7 dB(A) on average, 7 dB(A) at most, mostly at high frequencies ([JAE](https://agroengineering.org/index.php/jae/article/view/889)).
- [S] Thick roadside hedges gave insertion losses of 1.1 to 3.6 dBA ([Salford repository](https://salford-repository.worktribe.com/OutputFile/2478399)).
- [A] In reality **a hedge hides you but does not hide your voice**. A maze where you hear someone a metre away and cannot reach him is realistic, and funny.

## 4. Games

### 4.1 Hitman
- **Three topologies** [V] ([azhdarchid](https://azhdarchid.bearblog.dev/topology-of-hitman-levels/)):
  - **Onion**: nested zones round a core. Sapienza runs from the town to the mansion grounds to the lab; Dartmoor from the exterior to the first floor to the top floor.
  - **Festival**: a public event surrounded by a connected backstage. Paris's fashion show touches the basement, the backstage and the upstairs auction.
  - **Archipelago**: a public hub between fortresses. Whittleton Creek has six from one floorplan.
- **Sapienza** [V] ([Wikipedia](https://en.wikipedia.org/wiki/Sapienza_(Hitman))):
  - a clifftop mansion with floors, a basement, an attic, main and rear entrances, an adjacent garden, and a cave turned into a secret lab;
  - Elverdam called it "Swiss Cheese design" and a "snail house" with "no dead ends", and said it feels bigger than its footprint because it is layered;
  - one critic wrote that "bigger isn't necessarily better".
  - [V] "These connections mean that you will never get lost" ([Game Developer](https://www.gamedeveloper.com/design/from-coastal-town-to-sapienza-designing-a-i-hitman-i-level)).
  - [S] Christensen found the lab's virus task worked on a first discovery but became "a rather annoying thing" on replays (search summary of [PC Gamer](https://www.pcgamer.com/the-making-of-sapienza-hitmans-best-level/)).
- **Paris** [S] ([TechRadar](https://www.techradar.com/gaming/hitman-developers-reveal-how-they-chose-the-series-iconic-locations-it-always-starts-with-wouldnt-it-be-cool-if-47-went-somewhere)):
  - Mikkelsen picked the Palais du Luxembourg on Google Maps because its shape "allows for ledges around it", and the show "needed a courtyard";
  - an early Paris was "at least three times bigger" than the shipped one before it was cut ([TechRadar 2025](https://www.techradar.com/gaming/hitman-25-interview-2025)).
- **Dartmoor** [V] ([GamePressure](https://www.gamepressure.com/hitman-iii/her-final-resting-place/zee12f)):
  - a guarded gate with a climbable wall beside it;
  - a garden with a fountain that can be sabotaged, and a locked greenhouse of poisonous plants;
  - a two-level library;
  - four secret rooms opened by a cane, books or paintings;
  - a roof reached from an office window.
  - [S] Its murder-mystery structure fought the series' replay pillar, and randomised culprits were considered and dropped ([BusRep/Washington Post summary](https://busrep.co.za/technology/gaming/the-making-of-the-hitman-3-murder-mystery-mansion-34819d0c-98ce-430d-add1-9e2aab2e13d6)). I found no source for a hedge maze at Dartmoor.
- **Mendoza** [S]: a winery estate with a party hall above a secret facility; the villa is several floors tall ([Inverse](https://inverse.com/gaming/hitman-3-mendoza-argentina), [Sportskeeda](https://www.sportskeeda.com/esports/hitman-3-2021-all-levels-ranked)).

### 4.2 Resident Evil's mansion
- [S] Chris Pruett counted 116 unique nodes; the optimal route passes 213; 19 rooms can be skipped; about 40% of screens need one visit only.
- [S] He calls the structure "recursive unlocking": a key opens six or seven doors, and the space "widens in both directions at once" ([search summary of AOL/Pruett](https://www.aol.com/articles/speedrun-spiral-heart-resident-evil-203000066.html); the fetch returned 404).
- [A] Within one match: a house that **gets more connected as the match goes on** suits a finale that needs speed.

### 4.3 Dishonored
- **Lady Boyle's Last Party** [V] ([Kotaku, 2014](https://kotaku.com/dishonoreds-party-level-rewrote-the-rules-of-stealth-ga-1613011624)):
  - a masked party where the guards ignore you, so you walk openly and can sign the guest book;
  - three identical hosts told apart by costume colour;
  - guests send you for drinks;
  - playtesters avoided the upstairs because guards forbade it, so the game had to push them there.
  - [A] A party is a social space where everyone is allowed. A "forbidden" floor in a party map gets skipped.
- **The Clockwork Mansion** [V] ([Game Developer](https://gamedeveloper.com/design/level-design-deep-dive-i-dishonored-2-s-i-clockwork-mansion)):
  - Carrier names "long and tight passages that go in and around the walls" as the best way to cause confusion;
  - "Every backstage area had to be, as much as possible, visually connected to the big areas";
  - rooms have everyday functions, so players can play "without markers";
  - the kitchen sits below the dining room and the table rises.

### 4.4 Party and social-deduction manors
- **Cluedo** [V] ([Wikipedia](https://en.wikipedia.org/wiki/Cluedo)):
  - nine rooms, with the centre inaccessible;
  - each corner room has a secret passage to the opposite corner;
  - the 1949 design had eleven rooms, including a gun room and a cellar;
  - the 1988 Master Detective added a fountain, a gazebo, a courtyard and a carriage house.
  - [A] Its four secret passages are open knowledge printed on the board. A "secret passage" can be a known rule and still be fun.
- **Goose Goose Duck, Mallard Manor.**
  - [V] A "dark manor" with grounds outside "for fixing sabotages and completing tasks"; no vents; people hide in "leaves and cabinets" ([MuMuPlayer](https://www.mumuplayer.com/blog/goose-goose-duck-list-of-maps.html)).
  - [S] The meeting bell is in the dining room; sabotages sit at the foyer chandelier and a courtyard pump; a foyer rug can kill; a toilet flushes its hider into the lake ([xboxplay](https://xboxplay.games/goose-goose-duck/how-to-use-mallard-manor-map-in-goose-goose-duck-35815)).
  - [A] Its comedy comes from objects with a job in the house (a chandelier, a toilet). Analysis only; nothing to copy.
- **Phasmophobia.**
  - [V] Restricted variants (25 August 2026) close parts of large maps. Point Hope's runs "up to the Dining Room" (Kinetic, cited in the map-scale report §1.3).
  - [S] Players were dropped into random variants of Prison and Brownstone ([playnews](https://www.playnews.gg/en/guides/phasmophobia-the-august-25-update-adds-restricted-versions-of-prison-brownstone-and-point-hope-what-really-changes)).
- **Blue Prince (2025).**
  - [V] The house is a 9 x 5 grid of 45 plots; rooms are drafted each day and removed at day's end except permanent ones; some secret rooms (the Morning Room, the Secret Garden) can only be drafted in the wings; wing rooms "provide a view of the surrounding estate" ([Blue Prince wiki](https://blueprince.wiki.gg/wiki/House)).
  - [S] Released 10 April 2025 ([Gematsu](https://gematsu.com/2025/02/blue-prince-launches-april-10)).
  - [A] Proof that a fixed shell with drawn rooms reads as one manor.
- **R.E.P.O.** [S][P] Headman Manor has "small rooms with connecting doors and hallways that are very small and like a maze", many hiding spots and a courtyard ([itemlevel](https://itemlevel.net/r-e-p-o-best-map-tier-list-guide-low-high-quota/), [Dot Esports](https://dotesports.com/indies/news/r-e-p-o-beginners-guide-survival-tips-and-tricks)).
- **Suspects: Mystery Mansion.** [S] A manor-set social-deduction game with a proximity "Chit Chat" mode (search summary; the wiki returned 402).
- **No 2025–2026 Steam release** with a mansion setting and proximity voice turned up [S] ([wasdland](https://www.wasdland.com/games/social-deduction/)).
- **Untitled Goose Game.** Its gardens are linked by gags (a hole in the bush, a gate, a drawer); see the block report §1.4.

## 5. Scale: keeping an estate compact for 4 to 10 players

- **Real gardens are an order of magnitude too big** [A]:
  - Sissinghurst's 5 acres (about 20,200 m²) is 4.2 times the House plot (4,800 m²);
  - Hampton Court's maze alone is 28% of the plot;
  - Versailles' orangery is longer than our map.
  - Like the block, the estate must be a **compressed caricature**.
- **Reuse the bound from the earlier reports** [A]: about 100 x 80 m (8,000 m²), close to Lampkin Lane's 8,448 m² (scattered-points §4.1).
  - The diagonal of 128 m takes 28.4 s walking and 5 + 93/5.6 = 21.6 s at a sprint with our stamina.
  - The earlier report's 18 s assumed a full 7 m/s.
- **Voice coverage.** A voice circle is about 201 m², so **one garden room of about 14 x 14 to 16 x 16 m is about one voice cell** [A].
  - A dozen garden rooms of that size use about 2,500 to 3,000 m², leaving the rest for the house, terraces, lawn and service yard.
  - The 10-player chance that someone is in voice range at a random spot stays near the map-scale report's 22% on 7,400 m².
- **Sizes that suit our speeds** (all placeholders) [A]:

| Element | Placeholder | Why |
|---|---|---|
| House footprint | about 40 x 16 m (640 m²) on 2 floors plus a service floor and attic | Long and thin like a real manor, so that rooms see the garden on both sides (spacious House §5: "every room a view out") |
| Terrace drop | 1.2 to 1.5 m per step, 2 or 3 steps | Above the 1 m jump: a one-way drop with stairs to go up |
| Balustrade | either over 1 m (a wall) or under 0.6 m with gaps | So it does not become an accidental climb |
| Garden room | 14 x 14 to 16 x 16 m, hedges 2.5 to 3 m, 2 openings | One voice cell; hedges above eye height; no dead ends |
| Bounding hedge | 4 to 5 m, darker, of one kind | Lynch's "edge": players read it as the end of the world (spacious House §5). Versailles' were 5 m |
| Maze | 24 x 24 m, 2 m paths | About 45 s for every path, 10 to 20 s direct |
| Orangery | about 28 x 9 m with a 3 m gallery | One long glass room; the gallery as a second level |
| Service corridor | at most about 30 m end to end, 3 or 4 doors | 7 s walking; Arkane's limit on confusion |

- **Headcount.** DBD's 2 vs 8 grew its map only 22% for twice the players, and Phasmophobia closes wings (map-scale §1.3). [A] An estate splits naturally into wings that can close behind a locked garden gate.

## 6. Sightlines from terraces and windows, and how house and garden interlock

- **The upper terrace is the estate's roof problem.** The parterre is built to be seen from above (§3.1). Whoever stands on the terrace sees everything at the parterre's height.
  - [A] Accept it: make the parterre and the lawn the **open zone** with nothing to hide, a stage where crossings are seen.
  - Put everything that needs privacy behind hedges taller than eye height. From the terrace you see the *tops* of garden rooms, plus smoke and noise: "hide the act but not the result" (scattered-points §4.1).
- **Claire-voies and glass give designed sightlines** [A]. A few framed openings between garden rooms let a player see an act and then run round to reach it (see but not reach). Glass does the same: the orangery is visible from the terrace but sealed to the ear.
- **Three materials, three rules** [A], from the hedge acoustics in §3.5:
  - **Hedges** block sight, pass voice.
  - **Glass** passes sight, muffles voice.
  - **Masonry and the baize door** block both.
  - Players learn it from the world, without a tutorial.
  - A listener-side muffle is cosmetic. A `core/` rule is an architecture boundary (spacious House option F) that needs the engineer's word.
- **The house and garden interlock in four ways** (seen in Biltmore, Belton and Hitman) [A]:
  - a garden front of glass doors onto the upper terrace;
  - the service floor opening at grade onto a lower terrace (Belton's semi-basement);
  - a glasshouse attached to the house with a hatch below (Biltmore);
  - outbuildings (summer kitchen, carriage house, ice house) linked by service paths that skirt the garden rooms instead of crossing them.
  - That gives each outbuilding two ways in, one formal and one service: Project Winter's "two entries of different speed and risk" (spacious House pattern 6).

## 7. Patterns

1. **A manor has two circulations: a formal one for guests and a hidden one for service.** Servants' passages, baize doors, jib doors and dumbwaiters are the real "secret passages", and they exist to move things quickly and unseen. [V] (Servants' quarters, Biltmore)
2. **Gardens are a sequence of rooms divided by hedges and joined by vistas.** Hidcote, Sissinghurst, bosquets. [V]
3. **Terraces and parterres are made to be seen from above.** Height is the formal garden's vantage. [V]
4. **One-way edges are period features.** The ha-ha and terrace walls. [V]
5. **The best maze has stops, not one goal.** Versailles: 39 fountains, "at every turn". [V]
6. **Hidden layers must stay visually tied to the main rooms, and short.** Arkane. [V]
7. **Party levels are open social spaces; forbidden areas get skipped.** Dishonored's upstairs; Hitman's festival topology. [V]
8. **Big estates get cut.** Hitman's Paris was about 3 times bigger early on [S]; Lampkin Lane shrank twice [V, earlier report].
9. **Known secret passages still delight.** Cluedo prints them on the board [V]. Unlocked shortcuts make the space richer as you play (RE [S], Dark Souls in the earlier report).
10. **Fixed shells with drawn rooms read as one place.** Blue Prince [V], DBD tiles [V, earlier report].
11. **Aristocrats pranked their own guests.** Hellbrunn's trick fountains [V]: comedy native to the setting.

## 8. Risks

1. **Size creep.** "Estate" invites grandeur: every real dimension here is 4 to 30 times what our speeds can carry. Hold about 8,000 m² until a greybox measures time to cross (spacious House option E).
2. **The maze as a time sink or a guess map.** A real maze takes 20 minutes. Ours must be solvable in seconds, with a reason to be inside (stations), or players avoid it, as Dishonored's testers avoided the upstairs.
3. **Secrets against open knowledge** (GDD §1).
   - A secret that gives power becomes the meta (scattered-points risk 8). A secret known to a few veterans is a hidden advantage.
   - Secrets are also rarely found in 10 minutes.
4. **Long hidden routes disorient.** Real service corridors ran to about 200 m; Arkane names this the top cause of confusion.
5. **The terrace and the upper windows see everything.** This is the House's roof complaint again; parterres are built for it.
6. **Dead ends.** Bosquets and maze dead ends against the 30 s respawn and the 3 s of invulnerability (spacious House §8: a capsule needs two exits to different rings).
7. **Engine work.**
   - Terraces break the flat-floor assumption of bots (`house-map` §6, block report risk 7).
   - A pool needs a swim verb or must be decorative or one-way.
   - A dumbwaiter is a moving item container (host-authoritative state).
   - The three-materials voice is listener-side work or a core boundary.
8. **Content and art cost.** Many building types (glass, hedge, masonry, water). Hedges and terraces are cheap and repeatable; glasshouses and water are not.
9. **The bounding hedge reads as just another garden room.** Players then search it for an exit.
10. **Reference drift.** Estate murder mysteries are a strong trope (Cluedo; Dartmoor was billed as a Knives Out-like level, [PureXbox](https://www.purexbox.com/news/2020/08/were_getting_serious_knives_out_vibes_from_this_new_hitman_3_level)). Parody, never copy (GDD §1).

## 9. Options for the engineer (original; every number a placeholder)

Base layouts: pick one of A, B and C. D to H are overlays on top.

**A. The stepped estate: house on top, three terraces down to the lawn.**
- **Footprint:** 100 x 80 m inside a 4.5 m bounding hedge.
- **North:** the gates and lodge (cops, the stall station), the drive, the forecourt, and the carriage house on the drive.
- **The house** (40 x 16 m): a double-height hall, a library with a back stair, a billiard room with a hidden door, a dining room, the service floor below.
- **South, stepping down 1.5 m each:**
  - the upper terrace with the orangery attached at its west end;
  - the parterre terrace with two staircases and two one-way drops;
  - the lawn with the ship.
- **West wing:** 4 garden rooms (a walled kitchen garden with the summer kitchen, a dark room in a folly, the pool and pavilion, a bosquet).
- **East wing:** 4 rooms (the maze of 24 x 24 m, an ice-house mound, two more).
- **The service floor** opens at grade onto the parterre terrace.
- *For:*
  - the terraces give verticality and one-way chase breakers with no climb verb;
  - the gates (cops) and the ship (aliens) sit at opposite ends, so the finale crosses the house;
  - the parterre gives a look-up station.
- *Against:*
  - the upper terrace is a strong vantage;
  - heights need bot work;
  - north to south is long (about 80 m: 18 s walking).

**B. The courtyard estate: a U-shaped house round a forecourt, garden rooms in a grid behind.**
- **Layout:** the gates open into the forecourt between two wings (the carriage house in one, the summer kitchen in the other). Behind the house, a grid of 2 x 4 garden rooms is cut by two hedged avenues, with the maze filling one double cell and the ship on a meadow beyond a ha-ha.
- *For:* the shortest routes (two avenues are two rings); a readable grid; wings that close for headcount.
- *Against:* flat (little verticality); a grid risks the "guess map" of equal routes; the forecourt is one open stage.

**C. The house inside the maze.**
- **Layout:** the hedge maze is the estate's outer ring between the bounding hedge and the gardens, so every outbuilding is reached through part of it.
- *For:* "pleasantly confusing" everywhere; voice through hedges makes the whole edge social.
- *Against:* constant navigation load breaks "fun from the first second" after a random respawn; most expensive to tune; [A] not recommended except as a small part of A or B.

**D. Overlay: below stairs.**
- **Layout:**
  - one service corridor of at most 30 m behind jib doors linking 4 ground-floor rooms;
  - one back stair from the library to the upper hall;
  - one dumbwaiter shaft (kitchen, dining room, upper floor) that carries items, not players;
  - one baize door as the house's single voice-proof seam.
- **Arkane's rule:** each piece glimpses the main rooms (a grille, a serving hatch).
- *For:* the mesh the engineer asked for, inside the house; fast moves and covert spoiling for anyone (open knowledge).
- *Against:*
  - doors and the dumbwaiter are engine work;
  - the dumbwaiter is an item container to filter (the hidden-information invariant applies);
  - too many routes risk the guess map.

**E. Overlay: secrets in three tiers.** This resolves the open-knowledge tension.
1. **Told:** the plan in the ship shows the service routes as service routes.
2. **Kind told, place learned:** the rules say "this house has N hidden doors and M hides". A hidden door opens from its hidden side only, then **stays open and visible for the match** (RE's widening house at match scale). Everyone who walks past learns it.
3. **Drawn per match:** which of a few candidate prank fountains, hides or hidden doors are live tonight. Each has a small tell, like Campion's light between the planks.

- **No secret gives power.** Rewards are a faster route, a hiding spot or a clip.
- *For:* discovery without hidden advantages; the late match gets faster.
- *Against:* the drawn tier needs constraints (scattered-points risk 4); veterans still know the places sooner.

**F. Overlay: three materials.**
- **Rules:** hedges pass voice and block sight; glass blocks voice and passes sight; masonry and the baize door block both.
- **Start** with the listener-side muffle.
- *For:* rooms that sound like rooms, learned from the world.
- *Against:* the core version is an architecture boundary; the muffle needs tuning (the Steam Audio complaint).

**G. Overlay: wings by headcount.** For 4 to 5 players, a locked garden gate closes the east wing (about 4 garden rooms, 1,000 m²). The rooms' stations move to fixed spares in the open wing. A small sign at the gate tells which variant it is (Phasmophobia's decor tell).
- *For:* density at both ends of 4 to 10.
- *Against:* every variant needs testing; capsule and mischief pools must scale too.

**H. Overlay: the bell board.** A board in the servants' hall shows which *district* (wing, terrace, house floor) has an active ongoing mischief, by bell, without the exact room. The pendulum keeps swinging for a few seconds, so a late arrival still reads it.
- *For:* a period-correct, open-knowledge answer to m8 §9 ("the type without its place"); a reason to visit the service floor.
- *Against:* a new information tool to balance; it may make the search trivial (scattered-points risk 3).

**Recommendation [A]:** **A + D + E + G**, with F's listener-side muffle, and H as a playtest experiment.
- A gives verticality and chase breakers without a climb verb, and stretches the gates-to-ship finale across the house.
- D and E answer "mesh, secret passages, surprises" while keeping open knowledge.
- G keeps 4-player matches dense.
- Greybox the terraces, the house shell, the hedge rooms and the maze first, and measure time to cross from each capsule before any glass or water.
- Defer the pool to a decorative edge until a swim verb is decided.

**A placeholder map of existing chains to estate places** (the content is the engineer's): herbs to the orangery, the grill to the summer kitchen, the car repair to the carriage house, the photo zone to the pavilion or a folly, the darkroom to the dark room, the generator to the service floor, the cops' stall to the lodge, the calming cake to the summer kitchen, then carried over the terraces.

## 10. Open questions for the engineer

1. Which base layout (A, B, C), and is a slope with terraces in scope given the bots' flat floor?
2. Terrace drops above the 1 m jump (one-way) or below it (free)? A climb verb?
3. Should hedges carry voice (realistic, §3.5) or muffle it?
4. Secrets: is the count told to everyone (E, tier 2), do opened doors stay open, and is anything drawn per match?
5. The pool: a swim verb, a one-way escape, or decoration?
6. The ship on the lawn: is it the arrival point, and do capsules stay out of it (the block report's risk 9)?
7. May the existing chains move as in the placeholder map above, and which new rooms (library, billiard room, orangery gallery, maze) get which mechanic?
8. Should the estate scale with headcount (G), automatically or by host setting?
9. The bell board (H): an information tool for mischief, a stream of guests' requests, both, or neither?
10. The alien touches: portraits of alien lords, prank fountains, an eccentric lord's tunnels. Where does parody stop, and does any portrait do something (a camera with a tell)?