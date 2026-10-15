# Scattered random points, surveillance cameras and secrets for the neighbourhood block

Research report, round 3 (topic: scattered random points, cameras, secrets). Builds on `docs/design/house-map.md`, the M8 match design (`docs/design/m8-match.md` exists only on branch commit `49d435247`, not on `main`; read with `git show 49d435247:docs/design/m8-match.md`) and `docs/design/research/2026-10-15-spacious-house-level.md`. LOCKDOWN Protocol's map is left to the separate teardown; only public facts appear here.

## 0. Method and confidence

- About 57 web searches and fetches. Many wikis refused the fetch (Fandom HTTP 402, Twinfinite and MapCore 403, breezewiki bot wall), so several facts rest on search summaries and are tagged [S]. [V] means I read the page myself. [P] is a source's opinion. [A] is my analysis. All numbers proposed for our game are placeholders. Content belongs to the engineer.
- Our fixed inputs, read in the repo:
  - walk 4.5 m/s, sprint 7 m/s, voice 8 m, world sounds 12 m (`docs/design/house-map.md:8`);
  - the plot is 80 x 60 m, with a 100 m diagonal crossed in 14.3 s at a sprint (`house-map.md:24-25, 57-58`);
  - the roof is a lookout over the yard (`house-map.md:47-49, 278-279`);
  - 5 or 6 capsules, a 30 s wait and 3 s of invulnerability (m8 §3);
  - mischief stations are open knowledge, anyone may use them, and the "type hinted, place hidden" reading is still open (m8 §5, §9);
  - a kill outs the killer (m8 §4);
  - roles are mechanically identical (m8 §2).
- Round 2 already covered loops, chase geometry, dead ends against the respawn, vent networks being local, the Airship's size lesson, Siege's House rework and measuring flow (`spacious-house-level.md:241-251`). None of that is repeated here.

---

## 1. "Known kind, unknown place": how games spread objectives

### 1.1 What the games do

| Game | Kind is known | Place is drawn from | Active vs candidates | How it is telegraphed |
|---|---|---|---|---|
| Dead by Daylight, generators | Always generators | Predetermined spots | 7 spawn, 5 needed; "more possible spawn locations than Generators" | Unrepaired floodlights blink; the mast height follows the room's ceiling |
| Dead by Daylight, totems | Always totems | "Random locations… nooks and crannies" | 5 per trial | A lit Hex shows candles; a Boon drones within 24 m; cleansing takes 14 s |
| Phasmophobia, fuse box | One fuse box | 2 to 4 rooms per map | 1 of 2–4 | On the site map on easier difficulties, hidden on Nightmare and Insanity |
| Phasmophobia, cursed possession | One of 7 types | One fixed spot per type per map | 1 | None: you learn the spot |
| Hunt: Showdown, clues | Clues lead to the lair | A set of positions inside each compound | About 1 per compound; 3 reveal the lair | Glow in Dark Sight, the next 2–3 visible; a used clue shows a hole |
| PAYDAY 2, Murky Station | Keys, vaults, escapes | Up to 40 key hiding spots; 2 escape routes | 1 of 2 escapes; 3–4 drones active | Yellow caution tape, a dim red light under the wheels, a unique sound per key prefab |
| Escape from Tarkov, extracts | Extracts by name | A per-map pool | 3 per raid, on the side away from your spawn | Names only, no map pins |
| LOCKDOWN Protocol, vents | Broken vents | Dots on the tablet map | The count shown, not which ones | A broken vent flashes red, a working one glows blue; you visit the dots |
| Lethal Company | Scrap, fire exits | A random interior per moon | The main entrance fixed; fire exits "anywhere" | Terminal scan |
| Among Us, tasks | Task stations | Fixed stations, a per-player random subset | Host sets common 0–2, long 0–3, short 0–5 | The task list; visual tasks |
| Hitman, opportunities | A kill or escape idea | Fixed in the level | Overheard to start | Setting "minimal": "a quick synopsis… doesn't tell you how or where" |

Sources by row:
- Dead by Daylight generators: [V] [wiki.gg Generators](https://deadbydaylight.wiki.gg/wiki/Generators). The per-map candidate count is not published. An old forum estimate said "6~" and "now randomized" [S] ([Steam](https://steamcommunity.com/app/381210/discussions/0/2828702372998620894)).
- Dead by Daylight totems: [V] [wiki.gg Totems](https://deadbydaylight.wiki.gg/wiki/Totems). Players report totems "near a generator" [P] ([gfinity](https://www.gfinityesports.com/dead-by-daylight/how-to-find-totems-in-dead-by-daylight-pc-xbox-ps4-ps5-switch/)).
- Phasmophobia fuse box: [S] [Fandom](https://phasmophobia.fandom.com/wiki/Fuse_box), [Dot Esports](https://dotesports.com/phasmophobia/news/phasmophobia-bleasdale-farmhouse-map-guide).
- Phasmophobia cursed possession: [S] [Wikipedia](https://en.wikipedia.org/wiki/Phasmophobia_(video_game)), [KeenGamer](https://www.keengamer.com/articles/guides/phasmophobia-all-cursed-possessions-guide-locations-effects-and-downsides/).
- Hunt: Showdown: [V] [wiki.gg Clues](https://huntshowdown.wiki.gg/wiki/Clues). "Randomly picked from the set of possible locations" [S] ([Fandom](https://huntshowdown.fandom.com/wiki/Tips)). Mammon's Gulch has 16 compounds [S] ([Crytek](https://press.crytek.com/a-new-era-begins-today-with-hunt-showdown-1896-out-now-on-pc-playstation-5-and-xbox-series-xs)).
- PAYDAY 2, Murky Station: [V] [Game Developer](https://www.gamedeveloper.com/design/designing-highly-replayable-stealth-levels-for-payday-2).
- Escape from Tarkov: [S] [AFK Gaming](https://afkgaming.com/esports/guide/extracts-in-escape-from-tarkov-what-are-they-how-to-extract), [GGRecon](https://cms.ggrecon.com/guides/escape-from-tarkov-customs-map/).
- LOCKDOWN Protocol: [V] (a third-party guide) [xboxplay.games](https://xboxplay.games/lockdown-protocol/how-to-fix-lockdown-protocol-the-vents-58826).
- Lethal Company: [V] [wiki.gg Moons](https://lethalcompany.wiki.gg/wiki/Moons).
- Among Us: [S] [GameWith](https://gamewith.net/among-us-wiki/article/show/22148), [Tasks](https://breezewiki.discard.no/among-us/wiki/Tasks).
- Hitman: [S] [Stevivor](https://stevivor.com/reviews/review-hitman/), [Twinfinite](https://twinfinite.net/2016/11/hitman-season-1-review/).

**The Murky Station postmortem** is the most useful single source. It was written by its designer, Jason Mojica [V] ([Game Developer](https://www.gamedeveloper.com/design/designing-highly-replayable-stealth-levels-for-payday-2)):
- **Priorities.** Each random element got a priority. Vault doors and train layouts were "high"; breach points were "low".
- **Clusters.** Keys could be "all in different corners" or "all next to each other". The same space plays differently.
- **Cleanup.** A pass removed "overpowered" or unfair spots.
- **Too much randomness.** It brings diminishing returns: randomising every small object can "ruin a planned design".
- **Learning.** Players cut a sub-goal's time by a third to a half as they learned the map. The level targets 10–15 minutes in sub-goals of about 2 minutes.
- **Telegraphing.** The random things were telegraphed by one consistent visual language (tape, red light) and "unique visual and audio cue[s]" per prefab.

**Randomising the level itself.** Dead by Daylight keeps fixed outer walls but rotates and moves its tiles between trials [S] ([wiki.gg Distances](https://deadbydaylight.wiki.gg/wiki/Distances)). Spelunky carves a guaranteed path through a 4 x 4 room grid, then fills it from hand-made templates [S] ([GMTK transcript](https://amara.org/subtitles/p6MHlmreohsY/en-gb/1/download/How%20and%20Why%20Spelunky%20Makes%20its%20Own%20Levels%20%20Game%20Makers%20Toolkit.en-gb.txt)). Party Hard, a game literally about a party that brings the police, has "19 unique levels with random variations". Its traps are re-placed between attempts and it adds random events [S] ([PureXbox](https://purexbox.com/games/xbox-one/party_hard), [Twinfinite](https://twinfinite.net/?p=137989)). It is a tone reference only; nothing to copy.

### 1.2 What keeps search fun

1. **Ratio.** One active point per 2 to 4 candidates is the common band: Phasmophobia's fuse box is 1 of 2–4, Murky's escape 1 of 2, Tarkov's extracts 3 of a pool. Exceptions only appear where the target is cheap to check or several are active (Murky's 40 key spots, DBD's 7 generators out of more spots). [A] from the table.
2. **A consistent tell at range.** Examples: DBD's blinking floodlight, Murky's tape and red light, LOCKDOWN's red/blue vent lights, Hunt's glow that shows the *next* 2–3 clues. Search is fun when you can scan from a distance and confirm close up. It is a chore when every candidate needs a walk-up. [A] from the sources above.
3. **A hint ladder as a setting.** Phasmophobia shows the fuse box on easier difficulties and hides it on harder ones [S]. Hitman's "minimal" gives "what" without "where" [S]. That is exactly m8 §9's open question: no hint, or the kind without the place.
4. **Search leaves a trace.** Hunt marks a used clue with a hole, so a later team knows someone was there [V]. In a deduction game a trace is a free clue to *who*.
5. **Search is spread by the map, not by a marker.** Tarkov puts your extracts on the far side from your spawn [S]. Hunt has about one clue per compound [V]. Both force people to cross the map instead of camping.
6. **Learning is part of the fun, and it decays.** Murky's players got a third to a half faster [V]. Fixed spots (Phasmophobia's possessions) become memorised trivia [S]. Constrained random draws keep knowledge useful ("it's one of these three") without making it a lookup.

---

## 2. Security cameras

### 2.1 Counts, placement, blind spots

**Among Us**
- [S] The Skeld has 4 cameras on one screen, aimed at the hallways outside rooms ([Guide:Security](https://among-us.fandom.com/wiki/Guide:Security), [allthings.how](https://allthings.how/every-among-us-map-explained-vents-cameras-and-kill-zones/)).
- [S] Polus has 6 ([progameguides](https://progameguides.com/among-us/all-camera-locations-in-among-us)).
- [S] MIRA HQ has no cameras; instead a door log keeps the last 20 crossings at 3 sensors ([Doorlog](https://among-us.fandom.com/wiki/Doorlog)).
- [S] The Airship has 7 cameras over 6 places; hallways and spaces between places are not covered ([BlueStacks](https://www.bluestacks.com/blog/game-guides/among-us/au-airship-map-guide-en.html)).
- [S] The Fungle replaces cameras with binoculars at a lookout over the lower map, and the comms sabotage does not affect them ([Guide:Security](https://among-us.fandom.com/wiki/Guide:Security), [Siliconera](https://siliconera.com/?p=993823)).
- [S] Admin shows counts per room, not hallways ([earlygame](https://earlygame.com/gaming/among-us-map-guide-skeld)).
- [A] The pattern: **cameras watch transitions (hallways), the admin view watches rooms.** Neither shows everything. A deliberate blind band stays between them.

**Rainbow Six Siege**
- [S] Bank and Border have 7 default cameras each, 3 outside and 4 inside ([Twinfinite](https://twinfinite.net/guides/rainbow-six-siege-all-camera-locations-every-map/), fetch refused, snippet only).
- [S] Cameras sit in corners and on poles; attackers shoot them out on entry ([TrueAchievements](https://i1.trueachievements.com/a210301/camera-shy-achievement), [Ubisoft beta guide](https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/6aCUhBLRdnVd01Ko9orFsf/open-beta-game-guide-part-4)).

**Phasmophobia**
- [S] The truck holds a CCTV computer, a site map and a sound sensor screen that "streams audio into the Truck". Pre-installed CCTV "cannot be taken or disabled" ([Truck](https://phasmophobia.fandom.com/wiki/Truck), [Video Feed](https://phasmophobia.fandom.com/wiki/Video_Feed)).
- [S] The counts per map run from 1 up to about 15 (the extracted table was jumbled).

**PAYDAY**
- [S] PAYDAY 2's pre-release preview says camera placement *and quantity* are randomised ([PC Gamer preview](https://pcgamer.com/payday-2-hands-on-preview), snippet).
- [V] Murky Station swapped cameras for drones: up to 2 per train, 3–4 active at random, a loop of about 30 s ([Game Developer](https://www.gamedeveloper.com/design/designing-highly-replayable-stealth-levels-for-payday-2)).

**The ship-as-watchtower model (Lethal Company)**
- [S] One crew member at the ship's terminal watches a radar of teammates and can open blast doors and turn off turrets by ID ([earlygame](https://earlygame.com/general-news/lethal-company-all-terminal-commands)).
- [A] It is the nearest precedent for "the ship is where you watch from".

### 2.2 Counterplay

| Counter | Example | Source |
|---|---|---|
| **A tell that someone is watching** | Among Us cameras flash red while Security is in use; ghosts don't trigger it; you can hide a light by standing in front of it | [S] [Guide:Security](https://among-us.fandom.com/wiki/Guide:Security), [earlygame](https://earlygame.com/gaming/among-us-map-guide-skeld) |
| **Break** | Siege: shoot them; the bulletproof camera is weak at the sides, and melee shatters the glass and blinds it | [S] [Fandom](https://rainbowsix.fandom.com/wiki/File:BPCamWeakPoints.png), [siege.gg](https://siege.gg/news/bulletproof-camera) |
| **Blind for a while** | PAYDAY 2's ECM blocks cameras for about 20–30 s within about 25 m (player-reported) | [S] [Steam](https://steamcommunity.com/app/218620/discussions/8/1744483505465188472) |
| **Loop** | PAYDAY 3 loops footage on a few cameras per player; a new loop past the cap ends the oldest | [S] [TV Tropes](https://tvtropes.org/pmwiki/pmwiki.php/VideoGame/PAYDAY3), [number13](https://en.number13.de/payday-3-stealth-build-marks/) |
| **Kill the source** | PAYDAY 3: shut off every camera from the security room; Among Us: the comms sabotage disables cameras, admin, door log and vitals | [S] [Prima](https://primagames.com/gaming/how-to-stealth-no-rest-for-the-wicked-in-payday-3), [GameWith](https://gamewith.net/among-us-wiki/article/show/22105) |
| **Erase the evidence** | Hitman: destroy the recorder in the security room; shooting a camera costs nothing if unseen | [S] [Gameranx](https://gameranx.com/features/id/215762/article/hitman-3-10-tips-beginners-need-to-know-to-become-true-silent-assassins/2/) |
| **Harden** | PAYDAY 3's "Titan Cameras" difficulty modifier makes cameras indestructible | [S] [Payday wiki](https://payday.fandom.com/wiki/Modifiers_(Payday_3)) |
| **Limit by cost** | Five Nights at Freddy's cameras drain the same power as the doors | [S] [TrueAchievements](https://www.trueachievements.com/game/Five-Nights-at-Freddys/walkthrough) |

**The camera as a tripwire.** In Thief Simulator a camera "will immediately alert the police" [S] ([Thief Simulator wiki](https://thief-simulator.fandom.com/wiki/Police)). The camera there is a tripwire, not a screen. That fits our cops directly.

### 2.3 Cameras and hidden roles

- **Watching is a role-neutral trap.** An Among Us impostor waits for the camera watcher to leave, or vents to Security and kills him [S] ([Guide:Kill](https://among-us.fandom.com/wiki/Guide:Kill)). A watcher is out of the action, alone, and the only witness, so his report is unverifiable. That is good deduction material [A].
- **Anything only one side can use becomes a test.** Trouble in Terrorist Town's traitor buttons are "not even visible to innocents", precisely so innocents can't make a suspect press a button to see if a door opens [V] ([TTT mapping guide](https://www.troubleinterroristtown.com/development/mapping/)). [A] Our roles are identical (m8 §2), so every camera control, tunnel and shortcut must be usable by anyone, or it becomes a free human-tester.
- **What a camera catches here is not murder.** A kill already outs the killer (m8 §4). [A] So a camera's real job is catching *who started the mischief* and *who spoiled a task* (the wrong herb, a hidden box). The balance model says covert spoiling is the humans' best tool (m8 §6b). Cameras are the aliens' answer to it, and breaking or blinding cameras is the humans' answer back.

---

## 3. Secrets and small moments

- **Secrets reward attention to the space, not to a menu.**
  - [S] Overwatch's Paris has pianos whose keys play notes when shot; players perform tunes, a clip machine ([PCGamesN](https://www.pcgamesn.com/overwatch/overwatch-piano)).
  - [S] Overwatch's Eichenwalde has a hidden bonfire that does nothing ([Icy Veins](https://www.icy-veins.com/forums/topic/22703-dark-souls-easter-egg-in-eichenwalde/)).
  - [P] Map designer Aaron Keller wanted players to explore "almost as if it were an MMO with secrets and valuable areas hidden around every corner" ([GosuGamers](https://www.gosugamers.net/overwatch/features/38997-aaron-keller-on-building-overwatch-that-thing-still-keeps-me-up-at-night)).
  - [S] PC Gamer notes that Overwatch's physics props "can become a game all on their own" ([PC Gamer](https://pcgamer.com/overwatchs-physics-objects-are-fantastic)).
- **Multi-step secrets make the best stories.**
  - [S] Hitman's Sapienza summons a creature after you shoot 4 marked bells ([GamePressure](https://www.gamepressure.com/hitman/sapienza/z58fe2)).
  - [S] Phasmophobia's "Six Become One" needs all six cursed possessions in custom settings; they then gather in a circle in the chapel ([progameguides](https://progameguides.com/phasmophobia/all-easter-eggs-in-sunny-meadows-in-phasmophobia/)).
  - [S] A Phasmophobia mask in the water appears only if you look straight down from the pier ([Dot Esports](https://dotesports.com/phasmophobia/news/all-easter-eggs-and-secrets-in-phasmophobia)).
  - [S] The 13 Willow Street rework (21 July 2026) spread "hidden lore" through the house ([Game Developer press release](https://www.gamedeveloper.com/press-release/phasmophobia-s-13-willow-street-rework-launches-alongside-major-quality-of-life-update)).
- **Shortcuts that unlock.**
  - [S] Dark Souls uses doors that open from one side only, opened later from the far side, and loops back to its hub; it has no map screen ([Boss Keys transcript](https://amara.org/subtitles/4zZSGmv4Qxsz/en/1/download/The%20World%20Design%20of%20Dark%20Souls%20%20Boss%20Keys.en.txt), [TheGamer](https://www.thegamer.com/dark-souls-1-fromsoftwares-magnum-opus-of-interconnected-level-design/)).
  - [V] Hitman's creative director: "We built a volume filled with connections, and these connections mean that you will never get lost" ([Game Developer](https://www.gamedeveloper.com/design/from-coastal-town-to-sapienza-designing-a-i-hitman-i-level)).
  - [V] Lead level designer Torbjørn Christensen called Sapienza a "snail house spiral" that "wraps around itself", with layers joined by slopes and stairways ([80.lv](https://80.lv/articles/the-snail-structure-of-hitmans-levels)).
- **Secret routes need random keys.** [S] Tarkov's secret exits are fixed, but their codes come from random loot. Campers watch the normal exits, so the secret one is safer ([Prima](https://primagames.com/tips/what-are-secret-exfils-in-escape-from-tarkov-explained)).
- **The mischief list as the joke.** [S] House House's trailer showed a to-do list of mischief, and the team planned "more items on the to-do list" ([Game Developer, Road to the IGF](https://www.gamedeveloper.com/game-platforms/road-to-the-igf-house-house-s-i-untitled-goose-game-i-)). [P] Co-designer Nico Disseldorp said it's "the groundskeeper's responses that makes the goose seem so bad" ([GoNintendo](https://gonintendo.com/stories/347285-untitled-goose-game-devs-explains-why-they-chose-a-goose-in-an-in)). [A] The *neighbour's visible reaction* is what sells mischief, not the meter.
- **A suburban block as a level.**
  - [S] Hitman 2's suburban level is praised for "neighbors gossiping at a barbecue, a jogger doing laps", and for guarded houses dressed with rec rooms that let you glimpse residents' lives ([TechSpot](https://www.techspot.com/review/1750-hitman-2/)).
  - [V] Dead by Daylight's suburban street map shrank twice: from 168 to 152 square tiles, then to 132 (8,448 m²). The second rework moved the houses together, opened them all and added street loops ([wiki.gg Lampkin Lane](https://deadbydaylight.wiki.gg/wiki/Lampkin_Lane)). It is a 1-vs-4 game, but the direction (smaller, denser, every house open) is the lesson.
- **Live 2024–2026 checks.**
  - [V] LOCKDOWN Protocol left early access on 18 Nov 2025 and has 82% positive of 9,504 English reviews today ([Steam](https://store.steampowered.com/app/2780980/LOCKDOWN_Protocol/)). Its store page mentions no cameras or spawn settings, and I found no public source on its cameras. That is for the teardown.
  - [S] Siege's Y7S1 patch made the bulletproof camera's burst disable devices for 15 s instead of 6 s ([mp1st](https://mp1st.com/news/r6-siege-update-1-000-023-fires-out-for-y7s1-demon-veil-this-march-15)).

---

## 4. Mapping it to our block [A]

### 4.1 Size first: the block must not grow past what one respawn can cross

- **Today.** The plot's diagonal is 100 m: 14.3 s at a sprint (`house-map.md:57-58`).
- **A block that keeps the House lot at 80 x 60 m** and adds four neighbour lots of about 30 x 40 m plus a street easily reaches 140 x 110 m. Its diagonal is about 178 m: 25 s at a sprint and 40 s walking, longer than the 30 s respawn wait. Round 2's pattern 4 (size cuts encounters, `spacious-house-level.md:246`) and Lampkin Lane's two shrinks both say: **do not add lots on top of today's plot; carve the block out of roughly today's footprint plus a ring.**
- **Proposed bound (placeholder).** About 100 x 80 m including the street, which is 8,000 m², close to Lampkin Lane's 8,448 m².
  - Diagonal 128 m: 18 s at a sprint, 28 s walking.
  - The party lot shrinks to about 55 x 45 m, around the 24 x 20 m house (`house-map.md:57`).
  - 3 neighbour lots wrap it, the street runs along the south, and a corner shop sits at one street end.
  - The test: any capsule to the far mischief candidate in ≤ 15 s at a sprint, so a respawned player is back in play within 45 s of dying.
- **Roof and sightlines.** The engineer's complaint is that the roof sees the whole yard (`house-map.md:278-279` designed it that way). With neighbour lots, **fences, sheds and hedges between lots** become the sightline breakers. From the roof you see *into* the party yard but only the *tops* of the neighbours' yards. Any mischief candidate must stand where the roof cannot see it, or behind something that hides the act but not the result (smoke, noise).

### 4.2 Mischief points: "known kind, unknown place"

- **Draw.** Each mischief kind (the engineer's own examples: music, a fire at the grill, the bins, fireworks, a dog, the street lights) gets **3 candidate spots, one per neighbour-facing zone**. The host draws a subset per match, e.g. 2–3 kinds active, 1 spot each.
  - That puts us in the 1-in-3 band of §1.2 (pattern 1).
  - One-off big mischief (the fireworks) stays a multi-step route with a fixed destination (attic or roof, m8 §5). Only its *source* (where the fireworks lie) is drawn.
- **Spacing (placeholders).**
  - Same-kind candidates are ≥ 25 m apart (≥ 3.5 s at a sprint) and never visible from one spot or from the roof.
  - Each candidate is > 12 m from every capsule (beyond the world-sound radius), so a respawn doesn't land on it.
  - The generator switches' "> 8 m apart" rule (`house-map.md:38-40`) is the existing precedent.
- **Telegraph ladder (a host setting, matching m8 §9's open question).**
  - (a) No hint: only the meter rises.
  - (b) The kind: an icon or a neighbour's shout says "music!".
  - (c) The kind plus the *angry neighbour*: that lot's porch light comes on, its owner appears at the window. That gives the zone, not the spot.
  - Pattern 2 says each active point also needs a close-range tell (music at 12 m, smoke above the fence, a smell cloud), so the last 10 m are a scan, not a walk-up to each candidate.
- **The search budget.** At 3 candidates about 25–35 m apart, the worst case is about 3 legs of 4–5 s at a sprint plus the fix: about 20 s. That is a race against a slowly rising meter, not a chore. If the playtest shows players sweeping every candidate on a schedule, the ratio is too low or the tell too strong. If it shows them giving up, it's the reverse.
- **Trace.** Hunt's lesson: a started mischief leaves a visible trace (a knocked bin, a burnt mark). Someone who comes back from that zone is a suspect, which feeds deduction without a marker.

### 4.3 Cameras

- **Where they are watched.** The ship is the obvious viewing place. It is already the start, a mission and a lobby theme (m8 §1), like Lethal Company's terminal and Phasmophobia's truck.
- **Count and coverage.** 4 cameras at 4–6 players and 6 at 8–10 (Skeld/Polus scale), placeholders. Each camera covers a **transition** (a gate between lots, the street, a tunnel mouth), not a candidate spot (the Among Us split).
- **Counterplay, open to anyone.**
  - A light while someone watches (the tell).
  - Knock a camera askew or cover it (a bag, paint) in 2–3 s; anyone can fix it at the camera.
  - A temporary blackout as one of the humans' buyable global sabotages (m8 §4 lists them as a points spend).
  - No recordings in the first version: live only. Recordings plus an "erase" step are a later, richer option (Hitman).
- **Architecture note.** Invariant 2 (per-peer filtering, `CLAUDE.md`) means the host must send the watcher the positions of exactly the players inside the watched camera's view, and only while he watches. A camera that also *carries audio* would be a voice route, which is game logic in `core/` (invariant 6). Both are engine work, not level dressing.

### 4.4 Secrets, shortcuts, the hidden layer, the shop

- **Shortcuts.** One shortcut per neighbour lot, closed at the start and opened from one side by anyone: a loose fence board, a dog flap, a kicked-down ladder. Once open it stays open for the match. This is Dark Souls' one-way door at match scale. It shortens returns from capsules (the 30 s respawn) and rewards players who open it.
- **Small moments.** 2–3 interactive props per lot that make clips: Paris's pianos, Overwatch's physics props. They cost no rules.
- **The hidden layer.** Tunnels between basements that anyone may use (the TTT lesson). Entrances are hidden but fixed, so they are learned, as in Dark Souls. Keep each tunnel short with visible ends, because round 2 found long hidden routes disorient (`spacious-house-level.md:258`). A drawn element per match (one tunnel blocked) keeps it "known kind, unknown state".
- **The shop run.** A corner shop on the street with a list known at the start (the kind) whose shelf positions are drawn per match (the place). It is also the natural place for a camera on the street, where the cops arrive.

---

## Cross-game patterns

1. **One active per 2 to 4 candidates** is the usual band for single objectives: Phasmophobia fuse box, Murky escapes, Tarkov extracts. Many-of-many (DBD generators, Murky keys) works only when checking a spot is cheap.
2. **A consistent tell at range, a confirmation close up.** Blinking floodlights, caution tape, red/blue vent lights, Hunt's glow on the next clues.
3. **Hint strength is a difficulty setting,** not a fixed design: Phasmophobia's fuse-box marker by difficulty, Hitman's "minimal".
4. **Constrained randomness beats pure randomness.** Fixed walls, moving tiles (DBD); a guaranteed path, random templates (Spelunky); a cleanup pass for unfair spots (Murky).
5. **Surveillance covers transitions, leaves rooms blind,** and is never total: Skeld hallways, Airship gaps, Admin's per-room counts.
6. **Every camera has a tell and a counter.** The red light, shoot, ECM, loop, comms, erase. The ones without (Phasmophobia CCTV) sit in games with no human opponent.
7. **Role-only map objects become tests** unless they are invisible to the other side (TTT).
8. **Multi-step secrets and loud props make clips;** the reaction sells mischief (Untitled Goose Game).
9. **Suburban maps get smaller and more open over time** (Lampkin Lane: 168 to 132 square tiles, every house open).

## Risks for our design

1. **The block outgrows the respawn.** Adding lots around today's 80 x 60 m plot pushes the diagonal to about 25 s at a sprint, longer than the respawn wait, and cuts encounters. §4.1 bounds it.
2. **The search becomes a sweep.** Weak tells plus many candidates make the aliens do a patrol route every minute ("visit every dot"). That is a chore, not finding.
3. **The search becomes trivial.** Fixed or memorised spots (Phasmophobia's possessions) turn into a lookup after 5 matches. The draw must vary, as in pattern 4.
4. **Random draws vary the difficulty.** Two far-apart active mischiefs in one match and two adjacent ones in the next skew the balance model (#1089). The draw needs constraints (one per zone, a maximum total distance).
5. **Cameras pull a player out of the party.** A watcher sitting at the ship hears little and does no work, and the "never boring" pillar suffers. Cameras that see too much repeat the roof problem.
6. **Cameras are engine work with architecture weight:** the per-peer filtering of feeds, and voice if a camera hears.
7. **Anything role-limited becomes a human test** (TTT). That includes the hidden layer.
8. **Secrets cost art time and rarely get found in a 10-minute match.** A secret with a power reward becomes the meta (Tarkov's secret exits).
9. **Neighbour interiors multiply the art.** Lampkin Lane's lesson: every house open, but small. Closed decorative houses read as fake.

## Options for the engineer (all values are placeholders; nothing copied)

**A. "The draw": 3 candidates per mischief kind, one per zone, hint by a host setting.** The host draws the active kinds and their spots each match, with the spacing rules of §4.2. The telegraph ladder (none / kind / kind and the angry neighbour) is a lobby setting.
- *For:* it is exactly "known kind, unknown place", it answers m8 §9's open question with a setting, and the content is pure data (invariant 4).
- *Against:* candidate spots triple the props per kind; it needs a constrained draw and a bot pass to check fairness.

**B. "The neighbours are the hint."** No icons. Each neighbour lot reacts visibly (lights, a figure at the window, a shout over the fence) when mischief near it runs, so the search narrows to a zone.
- *For:* diegetic and funny, it sells the mischief, and it gives the neighbours a face.
- *Against:* neighbour reactions are animation and audio work; the hint is weaker in a noisy party.

**C. "The ship sees": cameras watched only from the ship.** 4–6 transition cameras viewed from one console in the ship, with a light while watched. Anyone can knock or cover one in a few seconds; the humans can buy a blackout.
- *For:* it gives the ship a reason beyond the start, fits the spawn-in-ship setting, and the watcher is a classic deduction target.
- *Against:* it is engine work (feeds plus per-peer filtering), and a watcher sitting in the ship is a bored player if the console is too good.

**D. "Eyes you carry": no console, 2–3 placeable cameras (from the shop or found) that show their feed on a handheld.**
- *For:* surveillance becomes an item and a decision; it pairs with the shop run.
- *Against:* items need an inventory and UI; feeds still need per-peer filtering; harder to balance per lobby size.

**E. "One shortcut, one secret, three props per lot."** A fixed per-lot budget: a one-side-opening shortcut that stays open, a multi-step secret without power, 2–3 clip props.
- *For:* cheap, scalable, non-linear, and it lowers the respawn-return time.
- *Against:* art time for each lot; secrets may go unfound for weeks.

**F. "The under-street layer": short tunnels between 3 basements, open to all, one blocked per match.**
- *For:* the hidden alien layer the engineer wants, a fast but exposed route, and a drawn element.
- *Against:* basements under neighbour lots add a whole level per lot; disorientation risk; camera and voice rules underground.

**G. "Tight block": the party lot shrinks, three neighbours wrap it, about 100 x 80 m in total.**
- *For:* keeps the 15 s sprint test from capsule to any point and Lampkin Lane's density, and adds lots without adding minutes.
- *Against:* it reshapes today's house-map draft (the garden, the chill zone and the garage move or shrink), which is the engineer's call.

**Recommendation [A]:** G first, because it bounds everything else. Then A with the hint ladder (it fills the open m8 question and is mostly data), plus E's shortcuts, since they are cheap and help the respawn. C after the first greybox shows where the blind bands are. B as the hint's dressing once neighbours exist. D and F later, only if the playtest wants more surveillance or more routes.

## Open questions for the engineer

1. How many neighbour lots, and should the block stay at about today's footprint (option G) or grow?
2. Mischief hints: none, the kind, or the kind plus the angry neighbour's lot — a host setting or fixed? (m8 §9.)
3. How many mischief kinds active per match, and is the draw constrained to one per zone?
4. Cameras: a console in the ship, carried items, or both? How many per lobby size? Can they record?
5. Camera counterplay: who may break, cover or black them out, and does a blackout cost points (m8 §4)?
6. Does a camera carry sound? That is a voice-routing rule in `core/` (invariant 6).
7. Are the neighbours' houses enterable, and how many rooms each?
8. The hidden layer: tunnels between basements, open to everyone from match one (round 2's question 5)?
9. The shop: what list, fixed or drawn, and is a run a task, a mischief or both?
10. Spawn setting: random capsules or everyone in the ship, a host toggle as you proposed? Does the ship's start change the first minute's balance?
11. Secrets: may any secret give an advantage, or are they cosmetic only?