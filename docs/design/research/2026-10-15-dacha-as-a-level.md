# Dachas and country plots as level material for the House rebuild

Research report, 2026-10-15. Builds on [`map-scale-and-prototyping`](D:\prime-game\docs\design\research\2026-10-15-map-scale-and-prototyping.md), [`suburban-block-maps`](D:\prime-game\docs\design\research\2026-10-15-suburban-block-maps.md), [`scattered-points-cameras-secrets`](D:\prime-game\docs\design\research\2026-10-15-scattered-points-cameras-secrets.md), [`spacious-house-level`](D:\prime-game\docs\design\research\2026-10-15-spacious-house-level.md) and [`lp-map-voice-settings`](D:\prime-game\docs\design\research\2026-10-15-lp-map-voice-settings.md). Those cover area per player, block linking, chase loops, cameras, spawn pools and LOCKDOWN Protocol's map, and this report does not repeat them. Tags: **[V]** verified on the fetched page, **[S]** from a search summary only (several Russian sites failed to fetch: DNS errors or expired certificates), **[P]** opinion, **[A]** my analysis. Every number for our game is a placeholder.

## 0. The question first: map from mechanics, or mechanics from map?

The engineer asked which way to go. Here is what the evidence says.

- **LOCKDOWN Protocol went from mechanics to map.** "We started with the core gameplay loop, designed fun and unique tasks, positioned every room and corridors to ensure interesting player interactions, and we designed the current map around these established key points" (Dev update #2, quoted in our [LP map report](D:\prime-game\docs\design\research\2026-10-15-lp-map-voice-settings.md) §1.1) [V].
- **Untitled Goose Game went from real places to levels.** Its designer scouted real locations with Street View instead of greyboxing first (our [map-scale report](D:\prime-game\docs\design\research\2026-10-15-map-scale-and-prototyping.md) §2.2) [S].
- **[A] We are already halfway through the first path.** The five chains, mischief, capsules, cameras, the underground layer and the ship exist. What the House lacks is *places whose real-world job matches those mechanics*. A suburban house's rooms exist for living: sleeping, bathing, sitting. That is why the pump room, the bedroom and the kids' room had nothing to do.
- **[A] Every building on a dacha plot exists for a job.** The kitchen moved outdoors to cook and preserve. The banya is for washing. The cellar is for storing. The shed holds tools. The greenhouse grows things. That is the reason they are *separate small buildings*. So the dacha is not just a prettier setting. It is a vocabulary of places that already come with verbs.

**[A] The method that follows: a two-column matrix (§5).**
1. Column 1: what each mechanic needs (a source, a drop-off, a far-apart switch, a dead end, a lookout).
2. Column 2: what each real dacha place does.
3. Keep the matches.
4. Flag the leftovers in both columns: a place with no mechanic (banya, well, outhouse) or a mechanic with no place.
5. Then decide each leftover: give it a mechanic, merge it into another building, or cut it.

This is the working rule "no place without a mechanic, no mechanic without a place", applied as a table before any geometry.

## 1. What a dacha plot is, in numbers

### 1.1 Plot sizes
- **The "six hundred" norm.** Dacha plots "are usually not more than 600 m²", sometimes 1,200 to 1,500 m² ([Wikipedia, Dacha](https://en.wikipedia.org/wiki/Dacha)) [V]. A sotka is 100 m² ([GeoHistory](https://geohistory.today/dacha-modern-russian-history-legislation/)) [V].
- **Where 6 sotky came from.** It traces to a 1949 USSR decree built on an agronomist's calculation: a family's vegetable needs plus trees and outbuildings. The same account gives 12 sotky outside city limits ([gw2ru via search](https://www.gw2ru.com/lifestyle/231832-soviet-dacha-6-ares)) [S]. The page did not load, so the 12-sotka claim is unconfirmed.
- **Plot shape.** A 6-sotka plot is often about 20 m of frontage by 30 m deep ([cian listing via search](https://www.cian.ru/sale/suburban/332515665/)) [S]. The other 600 m² shapes (15 x 40, 12 x 50) are arithmetic [A].
- **Elsewhere in Europe.**
  - A German Kleingarten "should" be at most 400 m², with an arbour of at most 24 m² including its covered seat ([BKleingG §3](https://www.gesetze-im-internet.de/bkleingg/__3.html)) [S, statute text in the summary].
  - A Polish ROD plot may not hold an outbuilding over 35 m², or over 5 m high with a pitched roof ([eli.gov.pl](https://eli.gov.pl/api/acts/DU/2014/40/text/U/D20140040Lj.pdf)) [S].
  - Finland has close to half a million official summer cottages, with a median size of about 40 m² ([Kuopio 2026](https://www.kuopio.fi/en/2026/03/18/kuopio-has-the-most-holiday-homes-in-finland-in-2025/), [yle](https://yle.fi/a/3-8919139)) [S]. Nearly 20% of Finnish households own one or have access to one ([archinfo.fi](https://archinfo.fi/en/articles/huussi-part-of-finlands-living-cultural-heritage)) [V].

**[A] What this means for us:**
- A real 6-sotka plot (600 m²) is **one eighth** of today's House yard (80 x 60 m = 4,800 m²).
- A generous 12-sotka plot (about 30 x 40 m, 1,200 m²) is a quarter of it.
- So a dacha map cannot be one real plot. It has to be a compressed caricature, as the block report already concluded for suburbs, or several plots.

### 1.2 The house and its famous workarounds
- **The Soviet limits.** From the 1960s to 1985, a dacha house was legally capped at a single storey, no permanent heating and under 25 m² of living area. "Because of this, dachas usually had a mansard roof, which was considered by authorities as just a large garret or attic", and "large attics or glazed verandas became extremely widespread and often oversized" ([Wikipedia](https://en.wikipedia.org/wiki/Dacha)) [V]. The limits were loosened in the 1980s.
- **Today.** Ukrainian law calls a dacha "a garden house with a homestead plot". Garden houses may have up to three storeys, with the mansard not counted (ДБН Б.2.2-12:2019 as quoted by [protocol.ua](https://protocol.ua/ua/dachi_dachni_dilyanki_sadovi_tovaristva_zakonodavstvo_pro_dachi/)) [V].
- **A typical modern small house** is 6 x 6 m (36 m²) with an optional mansard and a 6 x 2 or 3 x 2 m veranda (builders' listings via [cian](https://www.cian.ru/country-projects/830/)) [S].

**[A] For level design, the workaround history is gold.** The real dacha house is a small box with an oversized attic and a glazed veranda bolted on. That shape reads as comic and three-dimensional at once: a cramped ground floor, a sloped mansard you crouch in, a glass veranda you see through. It also excuses odd self-built annexes joined to the house, which is how you get a mesh inside a small footprint (§6, option D).

### 1.3 Distances the rules impose
These are the real-world reasons buildings stand apart:

| Rule | Value | Source |
|---|---|---|
| House to the neighbour's boundary, new garden or dacha plots (Ukraine) | at least 3 m | [protocol.ua](https://protocol.ua/ua/dachi_dachni_dilyanki_sadovi_tovaristva_zakonodavstvo_pro_dachi/) [V] |
| Fence between neighbours / on the street (Ukraine) | at most 2.0 m / 2.5 m | same [V]; [24tv](https://24tv.ua/agro24/vidstan-mizh-parkanom-budinkom-skilki-metriv-maye-buti_n2807682) [V] |
| Outbuildings, including the banya, to the boundary (Russian SP 53.13330.2019) | at least 1 m | [els24 via search](https://els24.com/article/883-otstupy-ot-granits-zemelnogo-uchastka-pri-stroitelstve/) [S] |
| Detached banya to the house | 8 m (one source) | [ixbt via search](https://www.ixbt.com/live/comments/3524849) [S] |
| Outhouse or compost pit to a well | 15 to 20 m (sources differ) | [24tv via search](https://24tv.ua/agro24/yakiy-vidstani-vid-susidiv-mozhna-zvoditi-saray_n3040425) [S] |
| Compost to buildings / to water | 10 m / 20 m, in "the far corner" | [RBC via search](https://realty.rbc.ru/news/653575ca9a794725adc59509) [S] |

- **[A] These distances are why a dacha is a scatter of small buildings.** The latrine must be far from the well, the banya far from the house, and the compost in the far corner.
- **[A] The fact that the outhouse is far from the well, and the banya 8 m from the house, matches our voice range (8 m) and the generator's 12 m spacing rule (house-map §6).** Real dacha logic spaces the places almost exactly as our rules want.

### 1.4 The buildings, one by one
| Building | Real size and form | What happens there | Source |
|---|---|---|---|
| Summer kitchen | A one-room brick house in the yard, "always positioned near a fruit plot or veg patch" | Frying, cooking and preserving out of the main house's heat; pickling at scale in September; "a place of labor and a sanctuary"; now "dwindling", used as storage or dismantled | [Atlantic Council](https://www.atlanticcouncil.org/?p=278617) [V]; Olia Hercules via [The Caterer](https://thecaterer.com/sector/chef/book-review-summer-kitchens-olia-hercules) [S] |
| Banya | Three rooms: entrance and rest room (predbannik), washing room, steam room; whole buildings run about 3 x 4 to 6 x 6 m | Over 93 °C; birch venik; rolling in snow or plunging into a lake; beer or tea and talk in the rest room; "an important bonding place"; cycles for hours | [Wikipedia, Banya](https://en.wikipedia.org/wiki/Banya_(sauna)) [V]; [folkways](https://folkways.today/day-trip-russian-dacha-st-petersburg/) [V]; sizes [S] ([ai.neiroset](https://ai.neiroset.com/en/apartment-planner/sauna)) |
| Cellar (pogreb) | About 2 x 2 to 2 x 3 m, 1.8 to 2 m high; entered by a door and stairs, or by a hatch in the kitchen or hall floor (hatches sold at 60 x 60 or 60 x 120 cm); half-buried types sit 1 to 1.5 m deep | Potatoes and preserves; floods and rodents are the usual trouble | [Profile/cian via search](https://profile.ru/news/society/kak-obustroit-pogreb-na-dache-sovety-specialistov-1045392/amp/), [21vek](https://www.21vek.by/accsess_panels/ljuchkibel_024.html) [S] |
| Greenhouse | Polycarbonate arches, 3 x 4, 3 x 6, 3 x 8 m, arches 1 m apart | Tomatoes, cucumbers | [Prom](https://prom.ua/c4041030-garden-grove.html), [OLX](https://www.olx.ua/dom-i-sad/sad-ogorod/q-теплицы-поликарбонат/) [S] |
| Outhouse | About 0.86 x 0.86 x 2.05 m, or 1.2 x 1.1 x 2.83 m | Endless jokes (Finland's huussi "serves as the butt of jokes"; owners decorate it and leave privy books) | [shop.by via search](https://shop.by/dachnye_tualety/) [S]; [archinfo.fi](https://archinfo.fi/en/articles/huussi-part-of-finlands-living-cultural-heritage) [V] |
| Summer shower | About 1.2 x 1.0 x 2.25 m cabin with a 110 to 200 L black tank on its roof, heated by the sun | Lukewarm showers; about 200 kg of water on the roof | [Rozetka/Bigl via search](https://build.rozetka.com.ua/ua/385868172/p385868172/) [S] |
| Shed / utility block | Up to 6 x 2.4 m site cabins; sheds, toilet and shower are often combined under one roof | Tools, firewood, junk | [productcenter](https://productcenter.ru/products/producer-8670-produkciya-npp-sozviezdiie-iug-bytovki-vagonchiki-modulnyie-zdaniia-blok-kontieiniery-posty-okhrany), [t-j.ru](https://t-j.ru/o-bystromeniaiushchikhsia-dachnykh-planakh-ili-proekt-sanuzel/) [S] |
| Well | Stacked concrete rings, a winch with a bucket on a chain, a lid | Water; rings settle; buckets give way to pumps | [t-j.ru via search](https://t-j.ru/my-dacha-kolodets/) [S] |
| Compost | A pit of 1.5 to 2 m², at most 50 cm deep, or a heap at most 1.5 m high, in the far corner | Rot | [RBC via search](https://realty.rbc.ru/news/653575ca9a794725adc59509) [S] |
| Services | Some dachas run on "septic tanks, wells, and generators" | | [GeoHistory](https://geohistory.today/dacha-modern-russian-history-legislation/) [V] |
| Garage, carport | Garden-zone garages may be built in, attached or detached, on the building line or deep in the plot | | [protocol.ua](https://protocol.ua/ua/dachi_dachni_dilyanki_sadovi_tovaristva_zakonodavstvo_pro_dachi/) [V] |

### 1.5 How plots are laid out, and why
Guidance found in planning articles:
- **Utility block at the back.** Put it "deep in the plot so it does not block the garden or the vegetable patch".
- **Fruit trees to the north.** They go in the north, north-west or north-east part, so they do not shade the beds.
- **Beds and greenhouses to the south.** The vegetable patch and greenhouses go in the southern part for light, with the beds running north to south ([osnmedia via search](https://www.osnmedia.ru/exclusive/kak-gramotno-rasplanirovat-uchastok-v-6-sotok/), [realty.rbc](https://realty.rbc.ru/news/668732929a7947bf16907a89)) [S].
- **Traditional Ukrainian homesteads (Rohatyn studies).** These often set the house *deep in the yard*, away from the road, with outbuildings "at a certain distance from each other" by local custom ([nz.lviv.ua via search](https://nz.lviv.ua/archiv/2018-1/21.pdf)) [S].
- **One modern Dnipro-region homestead,** as described in a listing, has a parents' part with two yards, an orchard, a garage and cellars, a separate grandmother's part, and a lower utility zone with a hayloft, cowshed, pigsty and banya ([flatfy via search](https://flatfy.ua/недвижимость-пилиповка)) [S].

[A] So a real plot is zoned by job: a front yard by the gate, the house, a work yard of outbuildings, the beds in the sun, trees and the compost at the back. A zoned plot is the opposite of a hub. Each zone is reached along the fence and through the gaps between buildings, not only from the house.

### 1.6 Slopes
- I found no source on Ukrainian dacha terracing with tyre walls. The closest material:
  - tyre retaining walls in engineering use since 1982 ([Aliapur](https://aliapur.fr/en/application/21-murs-de-soutenement.html)) [S];
  - gabion walls on Carpathian roads ([restoration.gov.ua](https://restoration.gov.ua/en/blog/preventing-landslides-reinforcing-mountain-roads-with-retaining-walls/)) [S];
  - Carpathian recreational settlements raising houses and walkways on supports instead of cutting terraces (Lviv Polytechnic, 2025, [science.lpnu.ua](https://science.lpnu.ua/node/39941)) [S];
  - a Kyiv retaining wall surveyed at 0.2 to 1.7 m high ([kyivcity](https://minio.kyivcity.gov.ua/kyivcity/sites/14/NOVUNU/08.2024/05.08.24%20mayno%20stiny/rezultaty%20obsetezhennia.pdf)) [S].
- A garage tucked under a house on a sloped lot, facing the street, is a standard pattern ([search summary](https://old.orchid.com/?p=11474)) [S].
- **[A] For us, a slope makes three levels honest.**
  - A 2 to 3 m drop between terraces lets the "basement" of the upper terrace open at ground level onto the lower one: a walk-out cellar.
  - The underground stops being a separate world with two staircases. It becomes a level with doors on the outside.
  - Retaining walls 1 to 2 m high are also vault-or-ladder obstacles, which give one-way drops: the chase-breakers round 2 asked for.

### 1.7 The cooperative around the plot
- Soviet gardeners' partnerships (1955) got permanent land use and the right to connect to public electricity and water, and dacha-building cooperatives followed in 1958 ([search summary of Wikipedia, Dacha settlement](https://en.wikipedia.org/wiki/Dacha_settlement)) [S].
- Pre-revolution zemstvos required wide roads between dacha blocks "for access and fire safety, since dachas were wooden and often burned" ([Wikipedia, Dacha settlement](https://en.wikipedia.org/wiki/Dacha_settlement)) [V].
- An architect describes such allotments as "privately owned patches in densely packed rows" ([Archinect](https://archinect.com/oreshkina/project/dacha-9-18)) [S].
- [A] The neighbours are therefore *right there*, 3 m past a 2 m fence. That is a better premise for the neighbours' anger (m8 §5) than a suburban block: dacha neighbours famously see, hear and smell everything.
- Ukrainian law itself names shade and noise from a neighbour's plot as grounds for complaint ([zaxid.net](https://zaxid.net/shho_ne_mozhna_robiti_na_svoyiy_dilyantsi_bez_dozvolu_susidiv_perelik_n1622776), [glavred](https://glavred.net/life/krasnye-linii-sosedstva-chto-nelzya-delat-na-uchastke-bez-razresheniya-soseda-10712027.html)) [S].

## 2. Clutter and materials
- **Building materials.** Wooden dachas with "intricate wood carvings, lace-like wooden trims, and colorful paintwork", a warm earthy palette, and "a dacha isn't a particular style of architecture but is more a way of living" (Savintsev's photo book via [designboom](https://www.designboom.com/architecture/imperial-villas-humble-sheds-dacha-book-fairytale-wooden-world-fyodor-savintsev-09-06-2023/)) [V].
- **Folk decor.** An art historian studying folk dacha architecture lists plush-toy "altars", **tyre swans** and **palaces of glass bottles**, "dozens if not hundreds" per region ([profile.ru via search](https://profile.ru/news/lifestyle/lebedi-iz-shin-i-drugie-art-obekty-kakoj-dekor-isportit-uchastok-870269/amp/), [skillbox](https://skillbox.ru/media/design/shinolebedi/)) [S].
- **The old bathtub.** A Magnum caption shows a father and son pumping water into an old bathtub to water their garden ([Magnum via search](https://pro.magnumphotos.com/Asset/-2K7O3RKJSGTL.html)) [S].
- **Preserves.** One dacha owner has "more than 200 jars of preserves" and says each year "that's it, I am not planting", then plants again ([National Geographic, Russian Summer](https://www.nationalgeographic.com/magazine/article/russian-summer)) [V].
- **[A] What the clutter gives us.** It is *useful*: it is the hiding-spot vocabulary. Jars, crates of potatoes, a bathtub, stacked tyres, firewood piles, a hoard of glass bottles, old furniture in the mansard.
- **[A] The readability rule still applies.** LOCKDOWN Protocol had to add objects "to better visually reflect the collisions" of its hiding spots (our [LP map report](D:\prime-game\docs\design\research\2026-10-15-lp-map-voice-settings.md) §1.5) [V]. Clutter must be dense as dressing but sparse and legible where a hiding spot is.

## 3. The dacha weekend as comedy material
| Ritual | Evidence | A comic task or mischief seed [A] |
|---|---|---|
| Barbecue (shashlyk) | The May holidays came to be seen as "national days of shashlyk"; marinade with onions overnight ([znaj](https://sport.znaj.ua/380989-shashliki-na-travnevi-svyata-yak-pravilno-zamarinuvati-i-posmazhiti-m-yaso), [thepage](https://thepage.ua/ua/news/chi-svyatkuyut-v-ukrayini-1-ta-9-travnya-ta-chi-budut-vihidni-na-travnevi-2023/amp)) [S] | The grill exists; smoke blowing onto the neighbours is a natural ongoing mischief (m8 §5's "barbecue on fire") |
| Banya | Hours of heat, venik, snow or pond, beer, talk ([Wikipedia](https://en.wikipedia.org/wiki/Banya_(sauna))) [V]; first-timers confused by strangers "hitting you with twigs" ([search summary](https://www.wanderlustingk.com/?p=206389)) [S] | No mechanic yet (§5) |
| Harvest and preserves | Summer kitchens for pickling in September ([Atlantic Council](https://www.atlanticcouncil.org/?p=278617)) [V]; 200 jars ([NatGeo](https://www.nationalgeographic.com/magazine/article/russian-summer)) [V] | Jars as delivery items; a wrong label as covert spoiling (round 3's deniable error) |
| Beetle picking | Many gardeners pick Colorado beetles by hand into a bucket of water, morning or evening, under the leaves ([thepage](https://thepage.ua/ua/style/life-style/yak-vivesti-koloradskih-zhukiv-z-kartopli-bez-himiyi), [zaxid](https://zaxid.net/yak_prognati_koloradskogo_zhuka_z_dilyanki_narodni_metodi_bez_himiyi_n1608261)) [S] | A "find N things" search task in the potato rows (round 3's harder steps) |
| Watering | Bathtub filled by a pump ([Magnum](https://pro.magnumphotos.com/Asset/-2K7O3RKJSGTL.html)) [S] | A pump switched off = task sabotage; flooding a neighbour = mischief |
| Mushrooms and berries | August mushrooms, a forest nearby ([NatGeo](https://www.nationalgeographic.com/magazine/article/russian-summer)) [V] | Out of scope (a forest makes the map larger) |
| Neighbours | Shade, noise and fences are recognised legal grievances ([zaxid](https://zaxid.net/shho_ne_mozhna_robiti_na_svoyiy_dilyantsi_bez_dozvolu_susidiv_perelik_n1622776)) [S] | Exactly the anger meter |
| Repairs and self-building | Dachas "often built without permission" ([Wikipedia](https://en.wikipedia.org/wiki/Dacha)) [V] | Planks, ladders, half-built annexes as shortcuts that players unlock |

**[A] One tone note.** The real dacha weekend is the aliens' party seen from the neighbours' side: smoke, music, someone naked by the banya, a car being fixed at midnight. The game's comedy (humans spoiling the aliens' party, neighbours calling the cops) needs no new premise. It is already the dacha cliché.

## 4. Culture, media, and how foreigners read it

### 4.1 Culture
- **Russia.** "One out of three Russians owns a dacha" ([NatGeo 2012](https://www.nationalgeographic.com/magazine/article/russian-summer)) [V]. About 62% of Russians visited dachas in summer 2019 ([Wikipedia](https://en.wikipedia.org/wiki/Dacha)) [V]. The 2006 "dacha amnesty" registered 13 million dachas ([GeoHistory](https://geohistory.today/dacha-modern-russian-history-legislation/)) [V]. The standard history is Stephen Lovell's *Summerfolk: A History of the Dacha, 1710–2000* (Cornell, 2003) ([Project MUSE](https://muse.jhu.edu/article/176178)) [S].
- **Ukraine.** The Ukrainian academic dictionary defines дача as "a summer house for recreation outside the city" and "a plot outside the city with such a house" ([Goroh, СУМ-20](https://goroh.pp.ua/Тлумачення/дача)) [V], so the word is standard Ukrainian. The summer kitchen (літня кухня) is a distinctly Ukrainian village image, popularised abroad by Olia Hercules's 2020 book *Summer Kitchens* ([Atlantic Council](https://www.atlanticcouncil.org/?p=278617)) [V].
- **War context, 2022 to 2024.**
  - In 2022 many Kyiv residents fled to dachas around Moshchun, Irpin and Bucha, which were then fought over ([Boston Globe via search](https://www.bostonglobe.com/2022/09/22/opinion/russian-bombing-reduced-their-town-rubble-it-could-not-crush-their-humanity)) [S].
  - The 2024 project *Naïve Gardens* documents Ukrainians gardening under fire and decorating rockeries "with fragments of Russian shells" ([agroberichten, 12 Dec 2024](https://www.agroberichtenbuitenland.nl/actueel/nieuws/2024/12/12/ukraine-naive-gardens)) [V].
  - [A] The garden plot means resilience to Ukrainians right now. A party comedy can carry that warmth, but must keep war imagery off the map.

### 4.2 Games set on dachas or village plots (checked live)
| Game | Origin, date | What it is | Source |
|---|---|---|---|
| DACHA (VD Games, PropilGames) | 16 Sep 2025 | A single-player chill sim "on a Russian summer cottage": beds, harvest, preserves; Mostly Positive, 77% of 74 reviews | [Steam](https://store.steampowered.com/app/3854020/) [V] |
| A first-person "skuf" country sim (KickedMesh) | 20 Nov 2025 | Russian-language sandbox: chop wood, heat the sauna, pick mushrooms; "has no purpose!"; Very Positive, 88% of 671 reviews; AI-generated assets disclosed | [Steam](https://store.steampowered.com/app/4031500/) [V] |
| Russian Village Simulator 2 (VD Games) | 27 May 2025 | Village life sim; 0 to 20,000 owners, peak of 3 concurrent players the day before | [SteamSpy](https://www.steamspy.com/app/3714790) [V] |
| Dread Fields (Podoba Interactive, Ukraine) | released on Steam May 2026, 139 UAH | Ukrainian village in the late 1990s: milk the cow, chop wood, dig the patch, carry water from the well, plus supernatural horror | [Mezha](https://mezha.ua/news/vidbuvsya-steam-reliz-ukrajinskoji-gri-dread-fields-311762/) [V] |
| Back to Hearth (same studio) | Sep 2025 | Repair five houses in a Ukrainian village after a calamity; about an hour long | [dev.ua](https://dev.ua/news/reliz-back-to-hearth-1758872376) [V] |
| My Summer Car / My Winter Car (Amistech, Finland) | 1.0 on 8 Jan 2025 / early access 29 Dec 2025 | Rural Finland in 1995: family home with sauna; needs (urine, dirtiness); sequel peaked near 24,000 concurrent players, 94% of about 18,500 reviews | [Wikipedia](https://en.wikipedia.org/wiki/My_Summer_Car) [V]; [Respawn/Raijin via search](https://respawn.outlookindia.com/gaming/gaming-news/amistech-games-my-winter-car-becomes-breakout-steam-hit) [S] |

- **[A] The gap.** Every dacha game found is a single-player life sim, and most are Russian-themed. I found **no multiplayer social-deduction or party game on a dacha**.
- **[A] The flip side.** On Steam the word "dacha" currently sits next to Russian-made sims and a Russian meme. A Ukrainian studio using it should frame it as Ukrainian (language, the summer kitchen) or as a generic "country plot".
- **[P] A Ukrainian blog view (Mezha, 16 Oct 2025).** Post-Soviet settings used "without rethinking" are risky, and they "sell themselves" to foreigners, who feel no "aftertaste". It praises S.T.A.L.K.E.R. 2 for stripping Soviet symbolism and reframing the place with Ukrainian language and music ([Mezha](https://mezha.ua/en/blogs/post-sovyetskiy-seting-v-ukrajinskih-igrah-305602/)) [V].

### 4.3 How foreign players read it
- **[P]/[S] Western audiences like Soviet-flavoured settings**, which helps games like Escape from Tarkov and Atomic Heart sell ([Mezha opinion via search](https://mezha.ua/en/articles/games-are-politics-how-the-russian-game-industry-helped-prepare-this-war/)). That is opinion, not data.
- **[A] My Summer Car shows that rural specificity travels** when the comedy is physical and universal: drinking, needs, a broken car, a sauna. Kotaku "can't tell if My Summer Car is a joke or not" ([Kotaku via search](https://kotaku.com/a-car-game-so-realistic-that-it-has-permadeath-1698343837)) [S].
- **[A] What foreigners already know, and what needs no explanation:**
  - sauna (Finnish sauna culture is UNESCO-listed, [yle via search](https://yle.fi/a/3-8919139)) [S];
  - outhouse, greenhouse, barbecue, shed, garden gnome, fence.
- **What needs a visual explanation:**
  - the summer kitchen (show a stove, pots and jars in a tiny house);
  - the cellar hatch;
  - the venik;
  - six sotky as a concept (never mention it; just make plots small).

## 5. The matrix: every dacha place against our mechanics

The mechanics come from m8 §§3 to 8 and house-map §§2 and 6. "Fit" is my judgement [A].

| Place | Its real job | Mechanic it can carry | Fit |
|---|---|---|---|
| **Small house** (6 x 6 m plus a glazed veranda) | Sleeping, junk | Veranda table as a delivery drop-off; a camera monitor; one capsule | Medium: needs the mansard and veranda to earn its keep |
| **Mansard / attic** | Oversized junk store (§1.2) | Hiding spots among junk; a roof lookout through the dormer; fireworks lit on the roof (m8 §5) | **Strong** |
| **Summer kitchen** | Cooking, preserving | Burger order board and assembly; cake for the neighbours (m8 §5) | **Strong** |
| **Grill under a canopy** | Shashlyk | Burger frying; "barbecue on fire" mischief | **Strong** |
| **Cellar under the summer kitchen** (hatch in the floor) | Storage of potatoes and jars | Storage hub: buns, meat, delivery sources, car parts; a switch | **Strong**; also the entry to the underground layer |
| **Shed / utility block** | Tools, firewood | Car parts shelf; the **generator** (dachas run on generators, §1.4); a switch | **Strong** |
| **Garage or carport** | The car | The car repair (lift, fitter) | **Strong** (the MVP mechanic to be replaced, house-map §6) |
| **Greenhouse** | Growing | Herb board and beds | **Strong** |
| **Gazebo** | Sitting, drinking | Photo zone | **Strong** |
| **Fences, gaps, gate, lane** | Boundaries, neighbours | Mesh links; street spawn; the cops' arrival; music turned up (m8 §5) | **Strong** |
| **Neighbours' plots** | Complaining | Mischief targets; where the cake is delivered; anger rises when smoke or noise crosses the fence | **Strong** |
| **Banya** (3 rooms) | Steam, wash, plunge | **None yet.** Candidates: steam that blinds cameras and vision; a rest room as a muffled, private voice room; an overheated stove as ongoing mischief (smoke the neighbours see); firewood as a delivery chain | **Flag: no mechanic** |
| **Well** | Water | **None yet.** Candidates: a step in a chain (water for the banya or cooking); a shaft down to the underground; a hiding spot (lower an item in the bucket) | **Flag** |
| **Outhouse** | You know | **None yet.** Candidates: a capsule (respawn out of the outhouse is a clip); a one-person hiding spot; a camera blind spot | **Flag** |
| **Summer shower** | Lukewarm water | **None yet.** Candidates: one of four generator switches (the pump); a 200 L tank tipped over the fence as mischief | **Flag** |
| **Vegetable patch** | Potatoes, beetles | Weak today: hiding items in the rows. Candidates: a search task (beetles, a buried item); the easter-egg shovel (m8 §1); **the aliens' ship landed in it** | **Flag: weak** |
| **Orchard** | Fruit | **None yet.** Candidates: a climbable tree as a lookout or a link onto a shed roof; a ladder as a portable shortcut | **Flag** |
| **Compost heap** | Rot | Hiding spot for task sabotage only | **Flag: weak** |
| **Cooperative water pump or transformer** (the partnership's wiring, §1.7) | Shared services | A global sabotage (m8 §9's open question): cut the whole plot's power or water | Candidate |

**Mechanics left without a dacha place:**
- the photo **printer** and the **darkroom**: they can go in the mansard and the cellar, but neither is a dacha job [A];
- **security cameras**: no source found for cameras at dachas, so this is an assumption [A];
- **5 or 6 capsules**: need sci-fi justification wherever they stand.

**Count.** 9 places fit strongly, 2 are medium or candidates, 7 are flagged. The flagged ones (banya, well, outhouse, shower, patch, orchard, compost) are the engineer's call: give each a mechanic, merge, or cut. [A] My suggestion: keep the banya, the outhouse and the patch, which are the most iconic and funniest. Fold the shower into the shed, the compost into the patch, and the well into the underground's entry.

## 6. Options for the engineer (original; every size is a placeholder)

Baseline arithmetic [A]:
- **Walking times.** A 40 x 50 m plot has a 64 m diagonal: 14.2 s walking, 9.1 s sprinting. Today's House diagonal is 100 m and 22.2 s (house-map §3).
- **Voice baseline** (method from the map-scale report §1.2). On 4,000 m², the expected number of others inside one player's 8 m voice circle is 0.45 at 10 players and 0.15 at 4. On today's 7,400 m² it is 0.24 and 0.08. Halving the area doubles chance meetings.
- **The generator.** Four switches 16 m apart pairwise fit easily on a 40 x 50 m plot, even more easily across levels.

### Option A: one plot, three terraces
- **Size.** A single party plot of about 40 x 55 m on a slope, three terraces with 2.5 m drops. Total walkable area about 2,600 m² on the ground plus cellars and the mansard.
- **Layout.**
  - Top terrace: the lane gate, the house, the summer kitchen.
  - Middle terrace: the greenhouse, the patch, the gazebo, the shed.
  - Bottom terrace: the banya and a small pond, the garage reached by a ramp from a lower lane.
- **The underground.** The cellars under the top terrace open as walk-out doors onto the middle one.
- **Pros.**
  - The most compact.
  - Real three-level play: retaining walls become one-way drops and ladders.
  - Hiding-item search is fastest.
- **Cons.** Neighbours are only façades, so mischief has fewer targets. Probably too dense for 10 players.

### Option B: the cooperative corner
- **Size.** Flat. The party plot (about 30 x 40 m) plus two neighbour plots (about 20 x 30 m each) across a 5 m lane, about 3,000 m² in all.
- **Layout.**
  - Fence gaps, a shared well on the lane, a gate between the back gardens (a shortcut that can be unlocked).
  - The neighbours' plots carry mischief and the cake drop.
  - One neighbour plot closes at 4 to 6 players (DBD and Phasmophobia's scaling lesson, map-scale report §1.3).
- **Pros.** Mesh across plots; the neighbours' anger becomes physical; scales with the lobby.
- **Cons.** Flat, so less 3D. More art: three plots.

### Option C: the courtyard ring
- **Layout.** The house and its annexes form a ring around a 15 x 15 m work yard. Every annex has two doors: one onto the yard, one onto an outer path along the fence. That gives two concentric loops (yard and fence path), with the cellars linking opposite annexes underground.
- **Pros.**
  - Every place gets two exits by construction.
  - It reads at once.
  - Round 2's "two rings" idea.
- **Cons.** The central yard risks becoming the new hub. Less "pleasantly confusing".

### Option D: the dacha that grew
- **Premise.** Decades of self-building around the old limits (§1.2): the glazed veranda joins the house to the summer kitchen, the kitchen's attic runs into the shed's loft, a lean-to joins the shed to the garage. An irregular cluster you can cross indoors, at two heights, or outdoors.
- **Layout.**
  - Detached outliers (banya, outhouse, greenhouse, gazebo) stand at the real distances of §1.3.
  - The cellar under the kitchen and an old pit under the garage are joined by a crawl tunnel.
  - Shortcuts that can be unlocked are home-made: a plank across two roofs, a boarded doorway, a ladder.
- **Pros.**
  - The strongest mesh in the smallest footprint.
  - Its own story (every annex has a reason).
  - Many players will still be learning it after 50 matches.
  - Very 3D (loft runs, roofs, a hatch).
- **Cons.** The hardest to make readable, so it needs strong silhouettes per annex and colour cues (LP colour-coded its sectors). The hardest to greybox.

### Option E: the river plot
Option A's slope, ending at a stream or pond. The banya and a jetty at the bottom; the cops arrive along the top lane. NatGeo notes the most popular dachas lie along rivers ([NatGeo blog via search](https://blog.nationalgeographic.org/2016/05/22/photo-essay-dacha-season-kicks-off-in-the-russian-countryside)) [S].
- **Pros.** The banya's plunge has a place; water is a natural barrier and a landmark.
- **Cons.** Water needs swimming or falling rules. One more system.

### Option F: a modifier, not a layout: "this weekend's dacha"
On any of the options above, the layout stays fixed and each match draws:
- which home-made shortcut is open (the plank, the fence gap, the boarded door);
- which annex is locked;
- where the ripe crop or the jars stand.

This follows LOCKDOWN Protocol's "fixed layout, reshuffled contents" and its lockable rooms (LP report §§1.5 and 1.7).
- **Pros.** Cheap replay value.
- **Cons.** Players must learn the variants; it needs a pre-match tell.

### Recommendation [A]
**Option D's cluster, on two of Option A's terraces, at Option B's reduced scale,** with Option F's shortcuts.
- **Size.** About 40 x 50 m for the party plot plus one neighbour plot over the back fence, about 3,000 to 3,500 m² with the lane. That is roughly half of today's House.
- **Levels.** Three: cellars and tunnel (−1), the yard on two terraces (0), lofts, mansard and roofs (+1).
- **Why.**
  - Each match-critical place (the kitchen, the cellar store, the shed's generator, the garage, the greenhouse) gets a real dacha job, at least two exits, and one indoor and one outdoor route.
  - The neighbour plot and the lane make the anger meter concrete.
- **Before building any of it.** Settle the flagged places of §5 in one pass, then draw three variants as SVGs with the house-map tooling. Paper first, then greybox, as the map-scale report suggested.

## 7. Cross-cutting patterns
1. **Real separate buildings exist because of a job and a rule:** heat, fire, smell, water. Those jobs are our task stations, and those rules are our distances (§1.3) [A].
2. **Real dacha spacing already matches our voice and switch spacing** (3 to 20 m between buildings) [A].
3. **Small footprints plus oversized attics and verandas** are the authentic three-dimensional form (§1.2) [V].
4. **Neighbours within 3 m of a 2 m fence** make the mischief meter physical (§1.3, §1.7) [V]/[S].
5. **The fixed layout with a reshuffled state** is the proven path to "still checking the map after 50 matches" (LP report) [V].
6. **Every dacha game found is single-player**, so the multiplayer niche is open (§4.2) [V].

## 8. Risks
- **Scale.** A real plot is far too small; a caricature made too faithful will be cramped at 10 players. Mitigation: closing a neighbour plot by player count [A].
- **One-door sheds.** Real outbuildings have a single door, which makes every annex a dead end. Each needs a second exit (a window, a back door, a hatch, a roof), or it must be an *intended* dead end with a one-way escape (round 2) [A].
- **Clutter versus readability.** Kitsch dressing can bury hiding spots and items. Keep it legible (LP's collision fix, §2) [V].
- **Places that are only looks, again.** Seven places are flagged (§5). Adding them all without mechanics repeats the House's problem [A].
- **Culture.** "Dacha" on Steam is next to Russian sims and memes (§4.2) [V], and the post-Soviet aesthetic is contested among Ukrainian developers (§4.2) [V]. Avoid Soviet symbols and war imagery, and lean on Ukrainian touches and universal objects [A].
- **Banya content.** Nudity jokes versus store ratings: towels only [P].
- **Fire.** Wooden dachas burn (§1.7) [V]. Fire mischief must stay a stoppable, ongoing problem, not a map-destroying one [A].
- **Mechanics with no natural place** (the printer, the darkroom, cameras, capsules) need sci-fi justification [A].

## 9. Open questions for the engineer
1. Which way do you want to go: the matrix-first method of §0 and §5, or straight to drawing variants?
2. For each flagged place (banya, well, outhouse, shower, patch, orchard, compost): give it a mechanic, merge it, or cut it? And which candidate mechanics from §5, if any?
3. Is the setting framed as a Ukrainian dacha (summer kitchen, Ukrainian signs and music), or as a generic "country plot" readable worldwide? In English, should it be called "dacha" at all?
4. A slope (three honest levels) or flat (less art, an easier greybox)?
5. How many neighbour plots: none (façades), one, or two that open by player count?
6. Where does the aliens' ship land: in the potato patch, on the lane, on a neighbour's plot?
7. Do the capsules disguise themselves as dacha objects (an outhouse, a water barrel, a rain tank), or stay openly alien?
8. Does the car repair stay for the dacha map, given it is MVP-only (house-map §6)? A dacha would also suit a different repair: the pump, the generator, the roof.
9. Should any shortcut be home-made and unlockable (a plank, a fence gap, a boarded door), and is the open set reshuffled each match (Option F)?
10. Gaps this report could not close: real cellar-to-cellar links, cameras at dachas, and Ukrainian slope-terracing practice. Should an agent scout three real Ukrainian plots on satellite maps and trace them at our scale?