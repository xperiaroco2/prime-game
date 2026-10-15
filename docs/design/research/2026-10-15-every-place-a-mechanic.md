# Giving every place a purpose: a method and a dacha worked example

Research report for the engineer, 2026-10-15. This is research, not a decision. Tags: **[V]** verified on the fetched page, **[S]** search summary only, **[P]** opinion, **[A]** my analysis. All numbers for our game are placeholders.

## 0. Method and what this builds on

- **About 50 searches and fetches.** Several sources refused the fetch: the Among Us fandom wiki (HTTP 402), the PC Gamer Sapienza feature (paywall), the Amara transcript of the Hitman 2 Miami video (403) and PCGamesN's Prey making-of (403). The Dormans PDF downloaded but would not parse. Claims that rest only on those are marked [S].
- **What I read in the repo first, and do not repeat here:**
  - the decided design, `docs/design/m8-match.md`;
  - today's map, `docs/design/house-map.md`, with its §8 logic: storage as the hub, intended dead ends, stations spread to every side;
  - the LOCKDOWN Protocol map teardown, `research/2026-10-15-lp-map-voice-settings.md` §1 and §10;
  - round 2's loops and dead ends, `research/2026-10-15-spacious-house-level.md`;
  - the "known kind, unknown place" draws and the shortcuts, `research/2026-10-15-scattered-points-cameras-secrets.md`;
  - scale and density, `research/2026-10-15-map-scale-and-prototyping.md` §1.
- **What is new here:** how each space *earns* its place, a checklist of purposes, a method that pairs places with mechanics, and a cut rule. The dacha is the worked example.

### The engineer's question first: map first or mechanics first?

The evidence splits three ways, and the split itself is the answer.

| Who | Order | Source |
|---|---|---|
| LOCKDOWN Protocol | Mechanics first: "We started with the core gameplay loop, designed fun and unique tasks, positioned every room… around these established key points" | Dev update #2, quoted in the repo teardown, `lp-map-voice-settings.md:27` [V] |
| Dormans (procedural level design) | Missions first, then spaces "to accommodate those missions". The two are separate structures that both describe one level (from a study of a Zelda temple) | [pcgworkshop.com](https://www.pcgworkshop.com/archive/dormans2010adventures.pdf) [S] |
| Untitled Goose Game | Setting first ("an idea for a setting (for example, a pair of back gardens)"), then a goal per area, then a pre-written gag list, then real places found "that fit our design goals", "a patchwork of several different real locations all squished together" | [Game Developer](https://www.gamedeveloper.com/game-platforms/road-to-the-igf-house-house-s-i-untitled-goose-game-i-) [V] |
| Deus Ex | Real places first ("every map recreates either a real place"), but only places "that were naturally great game spaces": "Hotels and office buildings aren't great game spaces" | [Spector's postmortem](https://www.gamedeveloper.com/design/postmortem-ion-storm-s-i-deus-ex-i-) [V] |
| Overcooked | Experience first: they "generally work backwards" from the experience they want, and a mechanic change could get a level "completely redesigned or in some cases scrapped entirely" | [Game Developer](https://gamedeveloper.com/design/road-to-the-igf-ghost-town-games-i-overcooked-i-) [V] |

[A] **The working answer.** Fix the *setting* first; the dacha is a good one, because every building there already has a real-life verb. Then place the mechanics you already have. Then, building by building, ask whether that building's real verb can be expressed by a system we already have. That is Goose Game's order with LOCKDOWN Protocol's discipline. It is parallel, but in a fixed rhythm, not at random. §3 turns this into steps.

## 1. How games make each space earn its place

### 1.1 LOCKDOWN Protocol: layered purpose, not one purpose

From the repo teardown (`lp-map-voice-settings.md:36-53`, [V] there):
- **Each sector carries several things at once:**
  - a task machine or tool source (Storage holds the screwdrivers; the Machine room holds the filter washer);
  - one weapon case per sector ("Cameras, Outside, Machine, Storage, Medical, Restaurant, Botanical, Offices");
  - its own colour;
  - often one special: the camera room is "the only place a 2nd access card can spawn"; the card-locked rooms hold extra defibrillators or a reload station.
- **Even the corridors earn a place.** The card-locked Research Corridor is a *shortcut* to the Botanics dead end.
- **Items spawn "organically in fitting areas".**

[A] Lesson: "every room has something" means **one primary job plus two or three small ones**: an item spawn, a hiding spot, a colour, a locked extra. It does not mean one task per room.

### 1.2 Among Us: every room has work, some rooms have *information*

- **Every room on the Skeld has work.** All 14 rooms hold at least two tasks, and Navigation and Electrical hold five ([progametalk](https://progametalk.com/guides/among-us-the-skeld-map-tasks/) [V for the guide]).
- **Sabotage fixes sit in four of them:** O2, Admin, Electrical, Communications and Reactor between them (same page).
- **Two rooms exist for information:**
  - Security's cameras watch four corridors and leave blind spots ([fandom guide via search](https://among-us.fandom.com/wiki/Guide:Security) [S]);
  - Admin's table counts players per room, not in hallways, and dead bodies still count ([ludo.guide](https://www.ludo.guide/guide/among-us/side-quests-activities/admin-map-door-log-tracking-movement) [S]).
- **Other maps swap the information tool:**
  - MIRA HQ has no cameras but a doorlog of the last 20 players through its sensors;
  - Polus has one camera screen with switchable views and a vitals machine;
  - a Communications sabotage disables all four information tools ([gamewith](https://gamewith.net/among-us-wiki/article/show/22105), [PC Gamer](https://pcgamer.com/among-us-map-skeld-polus-mira-hq-guide) [S]).

[A] Lesson: **information is a room purpose of its own**, and so is the sabotage that blinds it. Our cameras and the roof lookout belong to this kind.

### 1.3 Overcooked: one twist per place

- **Every player must count.** The team wanted every player "equally responsible for the success of the team" ([Game Developer](https://gamedeveloper.com/design/road-to-the-igf-ghost-town-games-i-overcooked-i-) [V]).
- **They tune freedom against restriction.** Early builds had so many ways to fail an order that they added limits, "the ratio of freedom and restriction" (same page) [V].
- **The twists are spatial** [S] ([TheGamer](https://www.thegamer.com/overcooked-2-kevin-levels-ranked/), [fandom](https://overcooked.fandom.com/wiki/Overcooked!_2?oldid=1164)):
  - counters that rotate every half minute;
  - stations that sink and resurface elsewhere;
  - two floors joined by one uncontrollable elevator;
  - conveyor belts and portals.

[A] Lesson: **a place earns its keep with one rule-bending twist** that changes how people move or cooperate there, on top of the stations.

### 1.4 Hitman: each room is an opportunity

- **The design goal.** Lead level designer Torbjørn Christensen: the world "should feel like the world is full of ways to kill people". Sapienza's mansion holds the main challenge; the town is "filled with weapons, secret routes and Opportunities" ([PC Gamer via search](https://www.pcgamer.com/uk/the-making-of-sapienza-hitmans-best-level/) [S]).
- **The density fell, and the press noticed.** Hitman 3 has "only three Mission Stories per map", against about ten in each earlier game's levels ([PC Gamer review via search](https://www.pcgamer.com/hitman-3-review) [S]).
- **The structure.** Levels are compact "snail houses" with long obvious paths, and shortcuts such as "a hidden pipe" that give "a sense they are mastering a level" ([Kotaku](https://kotaku.com/ikea-stores-and-hitman-levels-are-both-snail-houses-wit-1832842270) [V]).

[A] Lesson: purpose density is noticed and missed when it drops. **Shortcuts learned over many matches** are the "still checking the map after 50 matches" feeling the engineer wants.

### 1.5 Immersive sims: problems, more than one way, real places

- **Spector's rules** ([postmortem](https://www.gamedeveloper.com/design/postmortem-ion-storm-s-i-deus-ex-i-) [V]):
  - "Problems not puzzles. It's an obstacle course, not a jigsaw puzzle";
  - "there should always be more than one way to get past a game obstacle. Always";
  - Harvey Smith's addendum: "Locations will be reachable in several ways".
- **The honest cost** (same page) [V]: emergent multiple solutions "didn't happen as often as we'd hoped", so designers had to plan a "skill" path, an "action" path and a "character interaction" path by hand.
- **Prey's Talos I** was meant as "an ecosystem", modelled on Arx Fatalis's dungeons ([wnhub summary](https://wnhub.io/news/game-design/item-12569) [S]).
- **Environmental storytelling.** Smith and Worch's GDC 2010 talk "What Happened Here?" adds that game systems can tell story through how the environment reacts ([GDC Vault](https://gdcvault.com/play/1012647/What-Happened-Here-Environmental), [Nieman Storyboard](https://niemanstoryboard.org/2011/01/14/harvey-smith-on-environmental-storytelling-and-embedding-narrative/) [S]).

[A] Lesson: a place should carry a *problem with two answers*, such as a front door and a cellar hatch. Its *story* can be the trace mischief leaves behind: a scorched barbecue, a tipped bin.

### 1.6 Escape rooms: every eye-catching object must matter

- **Room Escape Artist on red herrings** ([2019](https://roomescapeartist.com/2019/02/10/red-herrings/) [V]):
  - "anything that's misleading is a red herring";
  - "ghost puzzles" are props "left over from a broken or removed puzzle";
  - players assume "the most eye-catching and fun objects in the room will be integrated into the gameplay";
  - designer Eric Harshbarger: "I never design with red herrings. The players will create their own."
- **"Why is this here?"** Tampere University's PlayLab (Maija Johansson, 5 March 2021) reports Nicholson's point: many designers "forgot to ask, 'Why is this here?'" ([PlayLab](https://blogs.tuni.fi/playlab/features/inconsistency-is-the-bane-of-escape-rooms/) [V]).

[A] Lesson for a search-heavy game: a striking prop with no use costs players time and trust. On our dacha, the banya stove, the well and the scarecrow must *do* something, or be plain dressing behind the fence.

### 1.7 Phasmophobia: counted hiding, drawn candidates

- **Hiding spots are counted and "sanctioned".** 6 Tanglewood Drive has 3 closets, 1 set of lockers and 2 furniture spots, and difficulty blocks some of them ([KeenGamer](https://www.keengamer.com/articles/guides/phasmophobia-all-maps-guide-breaker-locations-best-looping-spots-and-many-more/) [S]).
- **Objectives come from small candidate pools.** The fuse box has 2 to 4 candidate spots per map and is drawn per contract. One cursed possession spawns from fixed candidates ([Prima](https://primagames.com/tips/phasmophobia-nells-diner-map-guide), [Dot Esports](https://dotesports.com/phasmophobia/news/phasmophobia-bleasdale-farmhouse-map-guide) [S]).
- **The 2026 Tanglewood rework** changed "the basement and kitchen, to improve gameplay and level flow" ([Kinetic Games](https://kineticgames.co.uk/news/6-tanglewood-drive-rework-phasmophobia-01600) [V]). The press dates it 3 March 2026 and says the kitchen loop was closed ([Destructoid](https://www.destructoid.com/all-new-features-in-phasmophobia-6-tanglewood-drive-rework-update/) [S]).

[A] Lesson: **"a candidate for a drawn item" is a purpose**, and a cheap one. A room with no fixed station can still be one of three places the fuse could be.

### 1.8 Dead by Daylight: a guaranteed kit per tile

- **Every tile has a minimum kit.** Each maze tile "Contains at least one Locker" and may also hold a chest, a hook, a totem or a generator. Tiles keep "the same general location", while "the chosen iteration may change between Trials" ([wiki.gg](https://deadbydaylight.wiki.gg/wiki/Maze_Tiles) [V]).
- **Totems.** Every map spawns "5 Totems placed randomly", and cleansing one takes 14 s and makes "a map-wide sound like a thunderclap" ([wiki.gg](https://deadbydaylight.wiki.gg/wiki/Hex_Perks) [V]).

[A] Lesson: give every place a **minimum kit**, such as one hiding spot and one item slot, plus **optional slots** the match draws. The cleanse's map-wide sound is a model for loud fixes: everyone learns where something just happened.

### 1.9 Untitled Goose Game and My Summer Car: comedy and a sauna that pay their way

- **Goose Game gives each area its own to-do list.** In the garden: get the groundskeeper wet, steal his keys, rake in the lake, and finishing a key task opens the next area ([fan walkthrough summary](https://www.nintendolife.com/news/2020/05/guide_untitled_goose_game_walkthrough_-_puzzle_solutions_and_to-do_list_objectives) [S]).
- **The gags came first,** as "a big list of gags that we wrote up early on" ([Game Developer](https://www.gamedeveloper.com/game-platforms/road-to-the-igf-house-house-s-i-untitled-goose-game-i-) [V]).
- **My Summer Car answers "why a sauna?"** It is "the main way to reduce stress". It needs heating to about 50 °C first, giving "a few minutes" to do other things. Water poured on the stones gives steam, and the faster drop comes at higher heat. Left hot too long it can burn the house down ([GamePressure](https://www.gamepressure.com/my-summer-car/how-do-i-use-the-sauna/zec821) [V]).

[A] Lesson: a sauna earns its place with **a slow setup, a payoff and a risk**, and a dacha supplies the comedy of each.

### 1.10 Level-design writing: the "why" test

- **Benefield, "Purpose" (2010)** ([Game Developer](https://www.gamedeveloper.com/design/level-design-lesson-15-purpose) [V]):
  - "Everything that goes into your map needs to have one or more of those goals supporting it";
  - "Be prepared to answer the why";
  - "trade one idea for another that has a purpose with a higher priority";
  - "one structure or idea can serve multiple goals".
- **Knowles (2011):** "All areas should have a purpose. An area that the player just walks through with limited narrative or advancement purposes is a waste of resources." He also allows scenic views ([Game Developer](https://www.gamedeveloper.com/design/my-thoughts-on-level-design) [V]).
- **Gilbert's puzzle dependency charts** reduce a game to locks and keys. Falstein's advice: make them "bushy", with parallel branches ([Gamerboom summary](https://gamerboom.com/archives/69319), [Dreams of Gerontius](https://dreamsofgerontius.com/2019/06/01/puzzle-dependency-charts/) [S]).
- **Totten's book** treats prospect (a view) and refuge (a hiding place) as paired spatial needs ([Routledge contents](https://www.routledge.com/An-Architectural-Approach-to-Level-Design/Totten/p/book/9780815361367) [S]).

## 2. The purpose checklist for our game

[A] Each place carries **at least one primary purpose and at least two in total**. Primary means a reason to go there on purpose.

| # | Purpose | Primary? | Our system | Example source above |
|---|---|---|---|---|
| 1 | Task step: source, station or drop-off | yes | the five chains, zone tasks | Among Us, LOCKDOWN Protocol |
| 2 | Mischief station (ongoing or one-off) | yes | the neighbours' anger, m8 §5 | Goose Game |
| 3 | Fix point (stops an ongoing mischief) | yes | extinguisher, rubbish | Among Us fixes |
| 4 | Spend point (stall the cops, buy) | yes | points, m8 §4 and §5 | LOCKDOWN Protocol reload station |
| 5 | Information (camera, screen, lookout) | yes | cameras, the roof | Admin, Security, doorlog |
| 6 | Route: a link, a shortcut to unlock, an underground entry | yes if unique | the underground layer | Hitman pipes, LOCKDOWN Protocol Research Corridor |
| 7 | Respawn capsule | secondary | 5 or 6 capsules | — |
| 8 | Candidate for a drawn item or mischief | secondary | "known kind, unknown place" | Phasmophobia fuse box |
| 9 | Item hiding (for sabotage) | secondary | hide an item | LOCKDOWN Protocol hiding guides |
| 10 | Player hiding or refuge | secondary | hiding spots | Phasmophobia closets, DBD lockers |
| 11 | Vantage (prospect) | secondary | roofs, trees, a tower | Totten |
| 12 | Voice shaping: a quiet or loud zone | secondary | walls muffle, m8 §8 | LOCKDOWN Protocol voice |
| 13 | Risk: a one-shot hazard, a dead end with an escape | secondary | the dropped car | DBD, round 2 option D |
| 14 | A twist: one rule-bending property | secondary | — | Overcooked |
| 15 | Comedy or clip prop, story trace | secondary | physics props | Goose Game, "What Happened Here?" |
| 16 | Landmark (orientation from afar) | secondary | — | LOCKDOWN Protocol colours |

**The cut rule** [A], adapted from Benefield and Nicholson:
1. Finish the sentence "Players come here to ___" with a row from 1 to 6.
2. If you cannot, try to **merge** the place into a neighbour (it becomes a corner of it).
3. Or **demote** it to dressing seen but not entered, behind the fence: Knowles's scenic view.
4. Or **cut** it.
5. A striking prop with no row is a red herring (§1.6), so it goes too.

## 3. Method: places and mechanics in pairs

[A] Ten steps, about an afternoon on paper before any greybox.

1. **The setting frame:** "a dacha, the aliens' party".
2. **Mechanic cards.** Write one card per existing mechanic, each with what it *needs* from space:
   - delivery: a source plus 3 to 4 drop-offs that differ by meaning;
   - generator: 4 switches at least 16 m apart (house-map §6, the 12 m cylinder rule);
   - burgers: storage, cold, fire, herb, assembly;
   - photo: a set, a print, a darkroom;
   - repair: a holder and a fitter with no line of sight (house-map §6);
   - mischief: loud and visible to the neighbours;
   - capsules: 5 or 6 spread out;
   - underground: 2 or more entries;
   - cameras and hiding spots.
3. **Place cards.** Write one card per candidate building with its **real-life verb**: banya → heat, steam, sweat; cellar → keep cold, store jars; well → draw water, go down.
4. **The matrix,** places × mechanics. Mark a cell where the mechanic's need *is* the place's verb (cooking = summer kitchen). Those are the pairs that read without a tutorial.
5. **Mechanics first.** Every existing mechanic gets its natural place.
6. **Then the places.** Each leftover place proposes one use of an *existing* system (a fix, a mischief, a source). Only if none fits, a new small mechanic, and only if it reuses a verb we already have (hold, carry, use, search).
7. **The cut test** from §2.
8. **The mesh test** (round 2's measurement kit, `spacious-house-level.md` option E):
   - every place has 2 or more exits, or a one-way escape;
   - every pair of chains shares at least one place on their routes (the teardown's §10 proposal);
   - no place is more than one two-way door deep.
9. **The compactness test:** a hidden item is findable within a budget. Placeholder: about 12 search-worthy places, each searchable in 5 s or less.
10. **Greybox and measure.**

Steps 5 and 6 answer "why a sauna?". The sauna stays only if step 6 finds it a use from our systems. If not, it moves behind the fence as dressing.

## 4. The dacha in real numbers

- **The plot.** The Soviet norm was 6 *sotky* (100 m² each), so 600 m² ([gw2ru](https://www.gw2ru.com/lifestyle/231832-soviet-dacha-6-ares) [S]). "Dacha plots are usually not more than 600 m2" ([Wikipedia](https://en.wikipedia.org/wiki/Dacha) [V]). Ukraine's Land Code art. 121 caps free plots for dacha building at 0.10 ha, 1,000 m² ([factor.ua](https://i.factor.ua/ukr/law-30/section-163/article-33952/) [S]).
- **The house.** Soviet rules allowed "not more than 25 m2 of living area" and one storey. Owners got around it with mansard roofs, counted as "just a large garret or attic". "Large attics or glazed verandas became extremely widespread and often oversized" ([Wikipedia](https://en.wikipedia.org/wiki/Dacha) [V]). [A] That is a ready-made joke and a ready-made third level: the house is officially one storey, with a huge "not a floor" attic.
- **The summer kitchen.** In Olia Hercules's account it is "a one-room brick structure" in the courtyard near the vegetables. Many had a masonry oven (*pich*); it was used for frying, preserving and pickling, "on an almost industrial scale, come September". Many are now storage ([Calvert Journal](https://www.calvertjournal.com/articles/show/11941/olia-hercules-ukrainian-summer-recipes) [S]).
- **The banya** has three parts: the changing and rest room, the washing room and the steam room [S] ([Learn Russian in EU](https://learnrussianineu.com/russian-banya-traditions-russian-bath-house-different-finnish-sauna-turkish-hammam/)).
  - The steam room runs at 60 to 90 °C, and operators differ on the exact figure [S] ([Culture Trip](https://www.theculturetrip.com/europe/russia/articles/a-first-time-visitors-guide-to-the-russian-banya), [Sole Uno](https://www.soleuno.ch/en/wellness-world-sole-uno/sauna-area/russian-banya/)).
  - The *venik* is a bundle of birch or oak twigs [S] (same Learn Russian page).
  - Builders' presets run from 3 x 4 to 6 x 6 m [S] ([neiroset planner](https://ai.neiroset.com/en/apartment-planner/sauna)).
- **The cellar.** Test with a pit about 2 m deep; if groundwater is above 1.5 m, build it half above ground. Potatoes sprout above +5 to 6 °C [S] ([zaxid.net](https://zaxid.net/chomu_kartoplya_prorostaye_v_pogrebi_yak_zupiniti_protses_poradi_n1627927)).
- **The well and the outhouse.**
  - A ring well is practical to about 15 m deep [S] ([poradu.pp.ua](https://poradu.pp.ua/dim/print:page,1,20893-scho-krasche-kolodyaz-abo-sverdlovina-vodopostachannya-budinku.html)).
  - The pit must stand at least 20 m from a private well, or 50 m from a public one, under DBN B.2.2-12:2019 as reported; sources disagree [S] ([dpss.gov.ua](https://dpss.gov.ua/news/vymohy-do-oblashtuvannia-vyhribnoi-iamy), [novyny.live](https://novyny.live/neruhomist/krinitsia-na-diliantsi-na-iakii-vidstani-vid-parkanu-mozhna-kopati-265604.html)).
  - The sweep well (*zhuravel*) lifts the bucket on a long counterweighted lever [S] ([proza.ru](https://proza.ru/2021/02/25/611)).
- **The greenhouse.** A "3 x 4" polycarbonate greenhouse is 3 m wide, 4 or 6 m long and about 2 m high, with arches 1 m apart [S] ([Rozetka listings](https://rozetka.com.ua/ua/384883770/p384883770/)).
- **The summer shower.** A flat 200 l tank is about 1 x 1 x 0.4 m, sits on the cabin's roof and is warmed by the sun [S] ([bigl.ua](https://bigl.ua/p2541327684-emkost-dlya-dusha)).
- **The vegetable patch.** About 12.4 million Ukrainians grow potatoes for themselves; 58% of rural households do, against 17% in cities (KSE with the potato producers' association, 8 July 2026) ([agroportal](https://agroportal.ua/en/news/rastenievodstvo/ponad-12-mln-ukrajinciv-viroshchuyut-kartoplyu-dlya-sebe-de-naybilsha-koncentraciya) [V]). Before the war, households grew 98% of the potatoes ([Agrosvit 2020](https://r.donnu.edu.ua/bitstream/123456789/857/1/17.%D0%A1%D1%82%D0%B0%D1%82%D1%82%D1%8F_%D0%A1%D0%B5%D0%B3%D0%B5%D0%B4%D0%B0.pdf) [S]).
- **The beetle chore.** Gardeners hand-pick Colorado potato beetles and their eggs into a bucket, checking the undersides of the leaves [S] ([zaxid.net](https://zaxid.net/yak_prognati_koloradskogo_zhuka_z_dilyanki_narodni_metodi_bez_himiyi_n1608261)).

**Scale for our game** [A]
- **Today's map is too big for a real dacha.** The 80 x 60 m plot (4,800 m²) is eight six-sotka plots, about 6,900 m² over all levels (`map-scale-and-prototyping.md:61`).
- **A compact caricature.** Placeholder: about 48 x 36 m, 1,730 m², roughly three merged plots, a "rich uncle's" dacha.
  - The diagonal is 60 m: 13.3 s walking, 8.6 s sprinting.
  - Add the cellar and tunnels (about 250 m²) and the house and attic (about 120 m²), and the total is about 2,100 m².
- **What that does to meetings.** On round 1's random-position baseline (`map-scale-and-prototyping.md:67-71`), the chance that someone is in a player's voice circle (201 m²) at a random moment is:
  - 10 players: 9 x 201 / 2,100 ≈ 0.86, about 58%;
  - 4 players: 3 x 201 / 2,100 ≈ 0.29, about 25%.
  
  That is up from 22% and 8% today. Many separate buildings with muffling walls are what keeps it from feeling crowded. The playtest decides.

## 5. Worked example: the dacha, building by building

Every idea below is **a proposal for the engineer**. None is decided, and none is copied from another work. "Uses" lists the §2 rows it carries.

**House** (small: two rooms, a glazed veranda, a huge mansard attic). Uses: 1, 4, 5, 9, 11, 16.
- *Proposal H1:* the veranda is the party's front desk, with the order board for every chain. Each guest request appears here, so the house is where everyone meets between runs.
- *Proposal H2:* the landline phone in the hall is the "special place" where points stall the cops (m8 §5): an excuse call to the neighbours. A hidden human can offer, dial and hang up. The phone works in plain view, so its trust test is visible.
- *Proposal H3:* the "not a second floor" attic is the vantage and item-hiding level. Its dormer looks over the patch and the gate, never into buildings, like the roof today (house-map §8).

**Summer kitchen.** Uses: 1, 2, 3, 12, 15.
- *Proposal K1:* burgers move here whole: assembly, the oven or grill, and the order board's copy. The long run becomes cellar → kitchen → greenhouse herb, all on short spokes of a ring.
- *Proposal K2:* the ongoing mischief "the fat caught fire" starts at the oven; the fix is a bucket from the well. That one place pairs a mischief, a fix and a chain, so it is a natural fight spot.
- *Proposal K3:* the calming action (m8 §5) is baking the neighbours' cake in the oven, with fruit from the orchard. A covert human can bake it wrong.

**Banya.** Uses: 1, 2, 12, 14, 10.
- *Proposal B1, the twist:* the banya must be **heated**. Firewood is carried from the shed. Once hot, the steam room fogs vision and muffles voice to a placeholder 2 m, making it the map's whispering room for plotting and the only place two players can talk unheard.
- *Proposal B2:* stoked too hot, the chimney puffs black smoke, an ongoing mischief the neighbours notice. The fix is to open the vent, which only works from the roof ladder outside.
- *Proposal B3:* the photo chain's silhouettes include an "after the steam" pose with a towel and a venik. The changing room is the photo set, so the photo chain moves out of the gazebo.

**Shed.** Uses: 1, 6, 9, 13.
- *Proposal S1:* the source for repair parts, firewood and the one-off fireworks (m8 §5), all from shelves. It is padlocked at the start, and the key is a drawn item (house-map decision 12's keys).
- *Proposal S2:* the shed holds the ladder. Carried and set against a wall, it **unlocks a shortcut**: the shed roof to the attic dormer, or over the fence. Once placed it stays for the match; a human can knock it down.

**Greenhouse.** Uses: 1, 5, 13.
- *Proposal G1:* keep the herb board and beds (house-map decision 6). Its twist is that it is **glass**: everyone outside sees who is inside, so nothing covert can happen there. Covert spoiling has to happen elsewhere, which spreads the suspicion.
- *Proposal G2:* the drip-watering valve is a generator switch, so one switch sits in plain view.

**Cellar.** Uses: 1, 6, 7, 9.
- *Proposal C1:* the hub of today's storage, now cold: jars, meat, buns, the film box. It is a dead end only by ladder; its second exit is a low tunnel to the underground layer.
- *Proposal C2:* jars of preserves are the delivery items, each going to its fitting place by meaning: pickles to the gazebo table, jam to the summer kitchen. This keeps the Delivery-by-meaning ADR's rule.

**Well.** Uses: 3, 6, 11, 14.
- *Proposal W1:* the well shaft is an **underground entry**: a one-way drop with a splash into the tunnel. It is the fastest way down and costs nothing but being seen go.
- *Proposal W2, a second holder-and-fitter chain:* a sweep-well lever. One player holds the counterweight, another rides the bucket to fetch a dropped item from the shaft. The holder may let go: comic, not lethal.
- *Proposal W3:* the well is the only water for the fire fix, so it becomes a contested spot.

**Outhouse.** Uses: 7, 10, 15, 13.
- *Proposal O1:* a respawn capsule disguised as an outhouse. The door bangs open and an alien steps out, a comic respawn. A placeholder sign quotes the real 20 m well-distance rule as a joke.
- *Proposal O2:* the only door on the map that locks from inside. It is a one-use refuge in a chase, but you are now in a box with one exit.

**Garage.** Uses: 1, 6, 13.
- *Proposal R1:* an old car over an **inspection pit** instead of a lift. The fitter works in the pit and the holder works the jack above. The pit's far end opens into the tunnel, the underground layer's third entry.
- *Proposal R2:* the car's horn and headlights are an ongoing mischief: a car alarm that keeps going until someone pulls the battery lead.

**Gazebo.** Uses: 1, 2, 12, 15.
- *Proposal Z1:* the party table, the main delivery drop-off for food, and the music speaker (the engineer's "music turned up" mischief). It is the loud zone: voices nearby are masked, so it suits both alibis and plots.

**Vegetable patch.** Uses: 8, 9, 11, 13, 1.
- *Proposal V1:* the search field. Humans can **bury** an item in a row: hiding as sabotage, with a shovel from the shed. Aliens dig rows to find it. Disturbed soil is the tell.
- *Proposal V2:* a beetle-picking zone task: find and pick a drawn number of bugs on random plants, an honest search task with an error rate (round 3).
- *Proposal V3:* a scarecrow is a security camera in disguise, seen as a scarecrow, so it can be found and covered. This is the open-knowledge counterplay from round 2.

**Orchard.** Uses: 1, 6, 10, 11.
- *Proposal A1:* fruit for the cake, picked by climbing a tree. The tree is also a vantage over the fence into the neighbour's plot. The trunks give cover, a loop with poor sightlines.
- *Proposal A2:* a gap in the fence behind the orchard is an unlockable shortcut to the street. Kicking a board out is permanent for the match.

**Pond.** Uses: 6, 13, 15, 16.
- *Proposal P1:* the aliens' ship hovers over the pond, the landmark seen from everywhere. Its rope ladder is a vertical link down.
- *Proposal P2:* a slow swim route under a footbridge, or a one-way fall-in that makes the faller "wet" for 20 s (a visible tell, the Goose Game humour).
- *Proposal P3:* fireworks lit on the raft count as the one-off big mischief, seen by every neighbour.

**Bonus: the summer shower tower.** Uses: 11, 14. *Proposal T1:* a 2.5 m ladder to a tank, the yard's cheapest vantage. Filling the tank from the well (a carry task) gives a warm shower that cleans a mischief tell such as soot or pond water.

**Cut candidates** [A]: from today's House, the pump room, boiler room, kids' room, bedroom, study and bathroom fail the "Players come here to ___" test, unless one takes a switch or the printer. On the dacha, the gazebo and the pond are the weakest. Each carries mostly secondary rows, so keep at most one of them as a primary.

## 6. Patterns

1. **Layered purpose beats one task per room:** LOCKDOWN Protocol's task, case, colour and special; DBD's minimum kit plus optional slots.
2. **Information rooms are their own kind,** and blinding them is a sabotage (Among Us).
3. **One twist per place** makes it memorable (Overcooked, Dishonored's time-hopping level [S] [Gamereactor](https://www.gamereactor.eu/the-time-hopping-level-in-dishonored-2-took-inspiration-from-one-great-bioshock-2-moment-1428993/)).
4. **Purpose density is noticed when it drops** (Hitman 3's three mission stories).
5. **Shortcuts learned over time are mastery** (Hitman, round 2's one-sided shortcuts).
6. **Drawn candidates give purpose cheaply** (Phasmophobia's fuse box and possessions).
7. **Eye-catching props must be used,** or they cost trust (escape rooms).
8. **The setting suggests the verbs, the verbs suggest the mechanics** (Goose Game: setting, goals, gags, real places).

## 7. Risks

1. **Purpose bloat.** Every building given a new system multiplies engine work. Steps 5 and 6 must reuse systems first.
2. **The dacha is cramped.** The 58% voice-overlap estimate (§4) may make plotting hard; muffling and buildings must carry it.
3. **Many small buildings mean many doors and chokepoints.** Each one is a camping spot near capsules (round 2, risk 6).
4. **Glass, tunnels and drops** each need rule work: visibility, voice underground, fall damage.
5. **Cultural reading.** Outside Eastern Europe the dacha may read as just "a farm". The jokes need to land without explanation. The Soviet-rule jokes are niche.
6. **Tone.** Outhouse and banya humour can slide into crude; keep it cringe, not gross (GDD §1).
7. **Search fatigue.** The vegetable patch can become a sweep ("visit every row", round 2, risk 2).
8. **The content area.** Every name, number and place here needs the engineer's word (CLAUDE.md, ownership).

## 8. Options for the engineer

**A. "Pairs on paper first."** Run the §3 matrix with place and mechanic cards before any greybox, and cut what has no pair.
- *For:* an afternoon; answers "why a sauna?" before art time is spent.
- *Against:* paper hides 3D and voice problems.

**B. "Compact ring of annexes."** About 48 x 36 m: a tiny house, a summer kitchen, banya, shed, greenhouse, cellar, well, outhouse, garage and gazebo in a loose ring with cross-paths. The existing five chains are re-homed; no new mechanic until the first playtest.
- *For:* the mesh comes from the gaps between buildings, and each building is small and cheap.
- *Against:* little height; the ring can read as a hub again if the centre is a lawn.

**C. "Three levels by the ground."** The same plot on a slope:
- a lower terrace with the pond, garage pit and cellar;
- the middle yard;
- an upper terrace with the orchard, banya and the attic's level;
- the tunnel under everything.
- *For:* 3D interest without tall buildings; vantage and refuge come naturally.
- *Against:* slopes complicate the greybox and the bot fakes. Today's bots read flat floors only (house-map §6, #681).

**D. "Two plots over the fence."** Our plot plus the neighbour's: the anger meter's face, the phone, the cake drop-off, and kickable fence boards as shortcuts.
- *For:* gives the neighbours a place, and the mesh crosses the fence.
- *Against:* more area, which cuts the density gains.

**E. "Re-purpose the House."** Keep today's House and apply the checklist: merge the empty rooms and give each survivor a pair.
- *For:* lowest cost, and the art already exists (#523).
- *Against:* keeps the hub shape the engineer wants to leave.

**F. "One new twist per milestone."** Start with B. Add one building's twist at a time (the banya's steam first, then the well drop, then the ladder shortcut), each behind a host setting.
- *For:* measurable, the way m8 §5 adds mischief one at a time.
- *Against:* the first build is plainer.

**Recommendation [A]:** A first, since it is an afternoon and decides what exists. Then B as the first greybox, growing by F's one twist at a time. Try C's slope if the greybox feels flat. Add D when the anger meter needs a face. Keep E as the fallback if the dacha's art cost is too high.

## 9. Open questions

1. Is the dacha a replacement for the House, or a second party map (m8 §1's several maps)?
2. How big: three plots (B) or the current 80 x 60 m with buildings spread out?
3. Do the existing chains move whole (burgers to the summer kitchen, the photo to the banya), or stay as they are?
4. May a place's twist change voice rules (the banya's whisper room), given m8 §8's muffling is not yet a `core/` rule?
5. Which buildings must exist for the joke even if a mechanic is thin? Dressing behind the fence, or cut?
6. Is the underground layer open knowledge from match one, with the well, cellar and garage pit as its entries?
7. How many places should be the candidate pool for a hidden item, to keep the search to a reasonable time?
8. Is the outhouse capsule in tone, or too crude?