# LOCKDOWN Protocol teardown, part: the space, the voice and the settings

**Topic:** the map, proximity voice, the lobby, host settings and presets, player counts, cosmetics, and how new players learn the game.
**Method:** I read all 96 items in the official Steam news feed, from the Kickstarter post (Feb 2024) to update 1.6.1 (14 Sep 2026). I also read the store API, the developer's own site, Steam discussions (31 threads opened), 179 recent Steam reviews from the review API, the Steam Points Shop API, YouTube titles and descriptions, and a few guide pages.
**Marks:** [V] verified at a source I read. [S] search summary only. [P] player opinion or report. [A] my analysis.
**Patch-note citations:** "PN x.y.z" means that version's post in the official feed. Every PN links to its post in the reference list at the end. The full feed is https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=2780980&count=100&maxlength=0.

Repo note: on the current branch (`content/1093-docs-design-the-pillar-the-party-is-hard`) `docs/design/m8-match.md` does not exist. I read it from `origin/main` (42cb93f19). The earlier research `docs/design/research/2026-10-15-spacious-house-level.md:7` says it "could not verify LOCKDOWN Protocol's map layout at all". This report fills that gap as far as public sources allow.

---

## 0. Snapshot

- **Studio and engine.** Mirage Creative Lab, a small family team. It was "initially 3 siblings", and in January 2025 one person did all the engine-side rework (Dev update #2 and #3) [V]. The game moved from Unreal Engine 5.2 to 5.5 in 0.4.0 (PN 0.4.0, Dev update #3) [V].
- **Status.** Early access from July 2024. 1.0 came on 18 Nov 2025 (store API `release_date`, https://store.steampowered.com/api/appdetails?appids=2780980) [V]. After 1.0 the studio moved its main focus to a new project. Under "what you cannot expect" it lists "New maps" and "Integrated mod support" ("What's next for Mirage Creative Lab?") [V].
- **Price.** $9.99 base. The cosmetic DLCs are Characters $9.99, Contrast $4.99 and Holidays $4.99 (store API with `cc=us`, appids 2780980, 3391970, 3391950, 3391960) [V].
- **Reviews.** 11,535 reviews in all, "Very Positive" (9,556 positive) (appreviews API `query_summary`, https://store.steampowered.com/appreviews/2780980?json=1). The store page shows 75% positive over the last 30 days (https://store.steampowered.com/app/2780980/) [V].

---

## 1. The map

### 1.1 One map, on purpose

- **There is exactly one match map**, plus a separate lobby area and a tutorial room (below).
- **The developers refused to make it bigger.** In December 2024 they wrote: "the current map is balanced for 5-8 players and the size is fine tuned around that. Making the map bigger would make the experience way too uneven at varying player count and this is something we tested in our early iterations" (Dev update #2) [V].
- **How they designed it.** "We started with the core gameplay loop, designed fun and unique tasks, positioned every room and corridors to ensure interesting player interactions, and we designed the current map around these established key points" (Dev update #2) [V].
- **They planned a second, larger map but never shipped it.** It was to be "designed for 16 players, with longer rounds to introduce mechanics that we couldn't fit in the current 8 minute round", with each new map bringing "its own rules, player count and unique mechanics" (Dev update #2) [V]. After 1.0, new maps went on the "won't happen" list ("What's next") [V].
- **The design goal for distances**, from the developer's site: "define ranges of play that are long enough to set apart certain players, while forcing them to occasionally cross each other and encourage interactions. Certain tasks will require moving across different rooms to interact with a specific machine, find a tool or deposit an item" (https://miragecreativelab.com/lockdown-protocol/) [V].
- **Instead of new maps, the map grew inward.** Patches added card-locked rooms, a shortcut corridor and themed items, without making the map larger (PN 0.8.0, 0.9.0, 0.11.0) [V].

### 1.2 Known areas

Nobody publishes an official map. I rebuilt this list from patch notes, which name areas in passing, and from guides.

| Area | What is known | Source |
|---|---|---|
| Central area / centre garden | Paths of different colours meet here. A central tree is the default grouped spawn. A blue ladder. Mid-round joiners used to "spawn dead in the garden". | PN 0.2.0, 0.4.1, 0.14.0, 1.3.0 [V] |
| Storage | Many shelves. Tools such as screwdrivers are mostly here. Marked by an orange box on the map. | PN 0.4.2; vent guide https://xboxplay.games/lockdown-protocol/how-to-fix-lockdown-protocol-the-vents-58826 [V for the guide's text] |
| Machine area / machine room | Filter washing station, marked by a blue wrench on the map. Cassette player. | xboxplay guide [V]; PN 0.5.0 [V] |
| Machine Supply room | Card-locked, opened from two doors in the Machine and Storage area. Holds fast battery chargers, extra task supplies, and "extra hiding space". | PN 0.8.0, 0.12.0 [V] |
| Red area / Armory | Revamped in 0.2.0. Became a card-locked room with a gun reload station and a heavy weapon crate. | PN 0.2.0, 0.11.0, 0.15.0 [V] |
| Botanics | A corridor, a greenhouse, and a lab with machines. Has a "deadly dead end" in the greenhouse. | PN 0.4.2, 0.5.0, 0.6.0, 0.9.0 [V] |
| Medical | A medical scanner room. The defibrillator's wall slot. Rearranged in 0.9.0. | PN 0.5.0, 0.7.0, 0.9.0 [V] |
| Research Corridor | Card-locked shortcut from Medical to the Botanics dead end. | PN 0.9.0 [V] |
| Emergency Room | Card-locked. Holds 3 extra defibrillators (later pre-charged) and scalpels. | PN 0.9.0, 0.12.0 [V] |
| Restaurant (Pizzushi) and kitchen | The cooking task. Tables were made non-walkable after a hide-the-recipe exploit. Has a vent. | PN 0.2.0, 0.6.2 [V] |
| Surveillance area / camera room | Camera screens. The only place a 2nd access card can spawn. | PN 0.4.1, 0.4.2, 0.11.0, 1.4.0 [V] |
| Offices | Desks. Hiding spots under them were removed and later restored. | PN 0.5.0 [V] |
| South corridor, west corridor | Connectors between areas. | PN 0.4.1, 0.6.1 [V] |

- **Weapon-case locations, one per area** (Nov 2024): "Cameras, Outside, Machine, Storage, Medical, Restaurant, Botanical, Offices" (https://gameplay.tips/guides/lockdown-protocol-weapon-cases-locations-guide.html, a mirror of a Steam guide) [V for the guide's text]. That suggests about eight top-level sectors [A]. Armory and Lab may count inside Red and Botanics.
- **Each sector has its own colour.** Decorative plants match "the area" colour so the paths blend into the centre (PN 0.2.0). Rare eggs "match the area colour they spawn at" (PN 0.8.0) [V]. The developer site says players find their way "through the architecture signage or with the help of their game assistant tablet" (miragecreativelab.com) [V].

### 1.3 Size, floors and vertical play

- **No published size.** I found no figure in metres or rooms. Sprint speed is 8 m/s, raised from 7 in PN 0.1.24 [V]. One Discord-era answer calls it "one detailed map" (https://steamcommunity.com/app/2780980/discussions/0/4635988522932715980/) [P].
- **Mostly one floor.** A player wrote that "they do plan on finishing this map (I guess it was always planned to be 2 stories)" (https://steamcommunity.com/app/2780980/discussions/0/603021022325687469/) [P]. Others asked for "the second floor to the storage room" (https://steamcommunity.com/app/2780980/discussions/0/594037096767820479/) [P]. A 2026 review wants "a new map that has elevation … pushing people off ledges", which implies the current map has little height (review 76561199013410907, https://steamcommunity.com/profiles/76561199013410907/recommended/2780980) [P].
- **Falls still matter.** Fall and stamina deaths exist ("Self-inflicted death (from stamina or fall)", PN 0.14.2). Landing from a fall slows you (PN 0.14.0) [V].

### 1.4 Vents and movement tricks

- **"Vents" are a task, not a way to travel.** Wall vents hold dirty filters: unscrew two screws, wash the filter in the machine room, put it back (xboxplay guide) [V for the guide]. The tablet map shows every vent spot as a blinking white dot. A broken vent glows red and a working one blue, so you must visit each dot to learn which are broken (same guide, and https://digitalphablet.com/gaming/repairing-lockdown-protocol-vents-a-step-by-step-guide/) [V for the guide's text].
- **This corrects the engineer's memory a little.** The candidate spots are marked on the map. What is random is which of them are broken, and you must walk to each one to find out [A].
- **No Among Us-style vent travel.** I found no evidence of hidden passages for dissidents. The developer says dissidents have "no unique role specific game mechanics" (miragecreativelab.com) [V]. The only special routes are the card-locked rooms, above all the Research Corridor shortcut, and ghost-only spots (below).

### 1.5 Chokepoints, locked rooms and hiding spots

- **Locked rooms are a one-off strategic choice.**
  - In 0.9.0 there was one access card and three locked rooms: "only one of the 3 rooms can be opened per match, so make sure you choose wisely" (PN 0.9.0) [V].
  - From 0.11.0 a 2nd card could spawn, only in the camera room (PN 0.11.0) [V]. The default became 2 cards in 1.2.0 (PN 1.2.0) [V].
  - From 1.3.0 each locked room can be set to locked, closed (opens with a card) or already open (PN 1.3.0) [V].
- **Dead ends are a named hazard.** The developers themselves call the Botanics greenhouse end "the deadly dead end" (PN 0.9.0) [V].
- **Alarms per sector.**
  - One per sector. Each needs a white fuse, and not every alarm has one at the start. Removing the fuse while the alarm sounds kills that alarm for the rest of the match (PN 0.5.0) [V].
  - Alarms turn off automatically after 10 s (PN 0.8.0) [V].
  - [A] Alarms are a noise tool laid on the map. They call for help over distance, and a dissident can disable them first.
- **Hiding spots are designed, and made readable.** Several patches removed or brought back item-hiding spots (inside the pressure machines, under the scanner room table, under office desks). The developers then "added objects in certain spots to better visually reflect the collisions" (PN 0.5.0) [V]. A popular Steam guide is "Where to hide filters and boxes while playing for a dissident" (https://steamcommunity.com/app/2780980/guides/) [V for the title]. Players complained "you cant hide things behind radios anymore" (https://steamcommunity.com/app/2780980/discussions/0/4635988286620397261/) [P].
- **Snap throw.** You can throw an item into a machine slot "for super cool skill shots", and the developers restored the spots where it worked (PN 0.6.0, SUMMARY) [V].

### 1.6 How players learn the map

- **The tablet:** "The tablet contains a map, explanations on procedures for every task and informations about most elements of the game" (miragecreativelab.com) [V]. The minimap was redrawn at 1.0 "to fit the map changes" (PN 1.0.0) [V].
- **Map legend:** areas are colour-coded with icons, for example an orange box for Storage and a blue wrench for the Machine room (xboxplay guide) [V for the guide]. Sector names appear on the camera and computer screens (PN "0.7", 2024-07-22) [V].
- **Spawns:**
  - Players were made to "spawn randomly to avoid unfair advantage" (PN 0.1.13) [V].
  - Later the host chooses "a grouped spawn around the central tree (current and default) or a sparse spawn across the map" (PN 0.14.0) [V].
- **Community map help:** YouTube has "Map layout, and helpful tips. Lockdown Protocol Task Tutorials pt. 1" (Andy_Havok, 2026, https://www.youtube.com/watch?v=jQpXHxj6iM8) and "Navigate The Map EASY!" (HausOfG, 2024, https://www.youtube.com/watch?v=4xCdllkN2w0) [V for titles]. Their content was not readable: I could not get transcripts.

### 1.7 What moves on the map from match to match

- Items spawn at random. Weapons were made to spawn "evenly across all sectors" after a bug gave Storage about 50% of them (PN 0.1.22) [V].
- Weapon crates sit at fixed places, need a 4-digit code (Mastermind-style colour hints, at first 9 tries, then 7), and unlock after a random delay (PN 0.2.0, 0.2.2, 0.3.0; gameplay.tips guide) [V].
- The access card, eggs and miscellaneous room-themed items spawn "organically in fitting areas" (PN 0.11.0) [V].
- [A] **The pattern:** the layout is fixed and learnable, while what lies where is reshuffled each match. Our "open knowledge" pillar takes the same stance (GDD §1, `docs/GDD.md:47-50`).

---

## 2. Proximity voice

### 2.1 What the developers built

The developer site gives the one technical statement (https://miragecreativelab.com/lockdown-protocol/) [V]:

> "We developed a tailor-made sound propagation system, forcing any sound to follow a cohesive path within the environment, rather than simply being muffled behind walls. The player won't unrealistically hear the sound source location, but the complex echo resulting from the entire path… won't always be able to pinpoint the exact location of a sound, but will know the precise direction it comes from… Lockdown Protocol incorporates a voice chat working with this sound system. Players can isolate themselves to have private conversations, hear a faraway call for help or clearly identify who speaks in a group conversation. … A headphone is highly recommended."

- **Walls:** sound travels around them through doors and corridors. The design does not just muffle a voice behind a wall [V].
- **Range:** I found no number. Players describe a smooth fade with distance: "you can hear people loud and clear if they are close. But you hear them less and less as they go further away, so someone might be getting killed and yelling and if you're not cl[ose]…" (https://steamcommunity.com/app/2780980/discussions/0/599648681388418729/) [P].
- **Game sounds use the same system, and it was tuned after release.**
  - 0.5.0 "readjusted all the sound dynamic and ranges" (PN 0.5.0, SUMMARY) [V].
  - A clipping effect for loud sounds was removed after a poor reception (PN 0.5.2) [V].
  - 1.3.0 increased the range of item hits, gunshots and breaking items "by roughly 50%" (PN 1.3.0) [V].
  - Gun sounds were "rebalanced … across all range for gameplay purpose" (PN 0.1.13) [V].
- **Reviewers note the room effect:** voices are isolated "if a player is in a different room" (Sportskeeda, Jan 2025, https://www.sportskeeda.com/esports/is-worth-playing-lockdown-protocol-2025) [V for the article's text]. The same article wrongly calls the game free-to-play, so treat it with care.

### 2.2 Radios and private channels

- **No radios or walkie-talkies.** Players have asked for them since August 2024, with designs such as channels, charging docks and a listening station ("Add a Walkie-talkie, maybe...", https://steamcommunity.com/app/2780980/discussions/0/599649070605177801/) [P]. Nothing in the 96 news items adds one [V by absence].
- **Dissidents get no private channel either.** A request for one drew the reply that it "would take away from some of the sneakiness you need as a dissident" (https://steamcommunity.com/app/2780980/discussions/0/758394056999961461/) [P].
- **Dissidents do know each other** ("aside from the ability to recognize each other", miragecreativelab.com) [V].
- **The "radios" players mention are music players.** Cassettes play NCS tracks at stations in certain rooms (PN 0.1.13). Players hid items behind them [V/P]. [A] Music is the only map sound players can control, and it competes with voice.

### 2.3 The dead

- **The dead become ghosts and spectate:** "if you die you just turn into a ghost to spectate the match" (https://steamcommunity.com/app/2780980/discussions/0/4635988522932715980/) [P]. "Nope you just die and spectate" (https://steamcommunity.com/app/2780980/discussions/0/4703539869281947855/) [P].
- **Ghosts are coloured light orbs.**
  - Players call them "the balls" (https://steamcommunity.com/app/2780980/discussions/0/4703539060902426956/) [P].
  - Ghosts were made "brighter to be more visible" (PN 0.1.22) [V].
  - Their light pulses when the player speaks ("Fixed ghosts light not pulsing when a player speaks", PN 1.0.0) [V].
  - [A] The pulse only makes sense if ghosts talk to each other, so they do.
- **The living cannot see ghosts.** "Fixed ghost being visible by resurrected players" (PN 0.7.1) [V]. [A] Ghost-to-ghost only.
- **The developers block dead-to-living contact on purpose.**
  - When the wink was added, they "Fixed ability to wink while dead (you could communicate while dead with that)" (PN 0.6.1) [V].
  - Ghosts later got the blink back (PN 0.14.2) [V]. [A] That only works if the living cannot see it, which fits 0.7.1.
  - [A] The rule is "the dead must not inform the living". This is close to our rule, under which nobody hears a dead player (`docs/GDD.md:715-719`).
- **Whether ghosts hear the living:** not verified. One bug report says that after joining mid-round, "if someone is a ghost, you can hear them all over the entirety of the map" (https://steamcommunity.com/app/2780980/discussions/0/599639260006494670/) [P]. A separate bug that made some microphones heard "globally instead of locally" was fixed in 1.4.0 (PN 1.4.0) [V].
- **Ghosts have little to do.** Players: "It's really boring to be a ghost, not being able to do anything" (https://steamcommunity.com/app/2780980/discussions/0/4845400193810649516/) [P]. A 2026 review: "once youre in ghost mode, you can't fly or hover … no nametags … if you want to know how many players are still alive or who is talking it's also impossible" (https://steamcommunity.com/profiles/76561198128471209/recommended/2780980) [P]. There are "a couple spots in the map only accessible by being a ghost" (https://steamcommunity.com/app/2780980/discussions/0/603020374162118416/) [P].
- **The defibrillator** can bring a dead player back: a wall slot with two battery slots charges it (PN 0.7.0). Emergency Room copies arrive pre-charged from 0.12.0 [V].
- **Training mode respawns players** "on the body position instead of the ghost" (PN 0.14.2) [V]. [A] So the Training preset has respawn and normal play does not.

### 2.4 Signals without words

- **Hands:** pointing and interacting with free hands (miragecreativelab.com) [V]. Hands up drops the held item (PN 0.1.25, 1.6.1) [V]. A thumbs-up gesture exists (review 76561198100951441, https://steamcommunity.com/profiles/76561198100951441/recommended/2780980) [P].
- **Eyes:** each eye opens and closes on its own key, "People see your eyes, so you can communicate with them! (Wink…)" (PN 0.6.0) [V].
- **Helmet glow:** the helmet colour pulses while a player talks (PN 0.1.29) [V].
- **Pause indicator:** a visual marker shows a player is in the pause menu (PN 1.0.0) [V].

### 2.5 Voice problems players report

- No volume slider per player: loud strangers overwhelm, quiet ones vanish (https://steamcommunity.com/app/2780980/discussions/0/4845401230251432771/) [P].
- You cannot switch voice off, which is a problem for younger players (review 76561198052393856, https://steamcommunity.com/profiles/76561198052393856/recommended/2780980) [P].
- The input device cannot be changed in-game. It is only shown, since 0.12.3 (PN 0.12.3) [V].
- A mic setup notice was added because "the need to set your microphone properly in windows" kept tripping players (PN 0.1.26) [V].
- 16-player lobbies were flagged as untested, "especially related to microphones" (PN 0.13.0) [V].

---

## 3. The lobby and its toys

- **The lobby is a walkable physical area, not a menu.** Over time it gained:
  - a mannequin that shows your customisation (PN 0.1.27);
  - task video tutorials "on a big screen in the lobby" (PN 0.1.16);
  - a Discord QR code on the walls (PN 0.1.10);
  - a Kickstarter backers panel (PN 0.10.0);
  - a redesign with "wall panels" that guide new players into their first session, and a back corridor opened "to welcome future additions" (PN 0.14.0);
  - a big rock with plants behind glass (PN 0.15.0);
  - a museum: Kickstarter tribute, the team, community contest winners and streamers (PN 1.0.0);
  - plushies, a merch tie-in (PN 1.1.0);
  - a framed community photo in the Restaurant (PN 0.9.0);
  - an in-world easter egg for two players who met in the game and married (PN 1.5.0) [V].
- **Combat in the lobby was turned off.** Lobby griefing was real: "You can no longer deal damage in the lobby and items cannot exist there… should prevent cheaters from killing the host attempting to ban them" (PN 0.12.0) [V]. Earlier, players died and respawned there (PN 0.4.1 fixed "areas in the lobby where you could die and respawn to unintended locations") [V]. Players asked for lobby music. One objected that "people could start killing each other in the lobby with the cassette tape" (https://steamcommunity.com/app/2780980/discussions/0/4635988779091462000/) [P]. "Items in the lobby" sits on the post-1.0 "could happen" list ("What's next") [V].
- **Readiness matters.** Players say that when the host force-starts, roles repeat, and everyone must ready up for a fair draw. They also say "dying on the lobby" resets it (https://steamcommunity.com/app/2780980/discussions/0/4845401230251980961/, https://steamcommunity.com/app/2780980/discussions/0/4764333414208635266/) [P]. [A] So the lobby had a physical ready-up, and the role draw was a known pain point.
- **Session tools:**
  - Visibility is Public, Hidden (later replaced by Friends) or Private (PN 0.1.10, 0.12.0) [V].
  - Lobby name of up to 20 characters (PN 0.12.0) [V].
  - Kick, and bans that persist locally plus ban by Steam ID (PN 0.1.13, 0.1.25, 0.12.0) [V].
  - Steam "recently played with" support (PN 0.12.0) [V].
  - Invites were briefly host-only because of an exploit (PN 1.4.1, 1.4.3) [V].
  - A "modded lobby" flag is required for mods. Mods anywhere else are bannable (PN 1.6.1, "What can get you banned") [V].

---

## 4. Host settings and presets

### 4.1 Presets

- **Added in 0.1.26** because "new players are often lost regarding what parameters to tweak". The presets are Training ("Learn the tasks"), Beginner ("simplified version"), Normal ("the full LOCKDOWN Protocol experience") and Custom (PN 0.1.26) [V].
- **Saved custom presets, any number**, from 1.2.0 (PN 1.2.0) [V].
- **Players ask for ranges** (for example, a random number of dissidents or tasks) "like the pre-set rules have". That implies the built-in presets roll from ranges (https://steamcommunity.com/app/2780980/discussions/0/695374081774682136/) [P]. A 2026 review asks for the same thing (76561198100951441) [P].
- **I found no breakdown of what each preset sets.**

### 4.2 Custom settings found (by area)

| Setting | Values | Source |
|---|---|---|
| Round length | Default 8 min. Limit was 20 min, raised to 60 min. | Dev update #2 ("current 8 minute round") [V]; PN 0.12.1 [V]; thread 4635988522932715980 [P] |
| Dissident count | Can be 0 (co-op only) | https://steamcommunity.com/app/2780980/discussions/0/686363730790070847/ [P] |
| Which tasks are in the match, and how many | Tasks can be absent ("regardless of the Pizzushi task presence") | PN 1.2.0 [V]; thread 4428814417440681280 [P] |
| Weapons on or off | Toggle from 0.1.16. Guns: none, default, crates only, field only. Knives 0 to 2. Detonator: none to guaranteed. | PN 0.1.16, 0.12.0 [V] |
| Heavy weapons | Rifle spawn on/off and its ammo. Which heavy guns may spawn. Heavy case always or 50/50. | PN 0.15.0, 0.15.3, 1.1.0, 1.2.0 [V] |
| Gun reload station | Disabled, random, enabled | PN 0.13.0 [V] |
| Alarms | Disabled, 2 fuses, all fuses | PN 0.12.0, 0.13.0 [V] |
| Access cards | 0 to 3 in 50% steps. Default 2. | PN 0.13.0, 1.2.0 [V] |
| Locked rooms | Each one locked, closed or open | PN 1.3.0 [V] |
| Defibrillators | Medical and emergency ones: off, or on with various charge | PN 0.13.0 [V] |
| Battery charge speed | 50% to 200% | PN 1.2.0 [V] |
| Spawn | Grouped at the central tree, or sparse | PN 0.14.0 [V] |
| Map theme | Overrides the seasonal theme (Christmas, Summer) | PN 1.3.0, 1.6.0, 1.6.1 [V] |
| Colours and player cap | "One player per color" on or off. Allowing duplicate colours unlocks up to 16 players. Both are set before the lobby is created. | PN 0.13.0, 1.6.1 [V] |
| Modded lobby | Flag | PN 1.6.1 [V] |

- [A] **Settings grow item by item.** Almost every new item or room arrives with its own setting. The host can turn any one ingredient off, and that is how presets stay cheap to add. This fits our "mechanics are data" invariant.

---

## 5. Player counts

- **The official count changed over time.**
  - Kickstarter trailer and studio site: "3 to 8 players" (https://www.youtube.com/watch?v=D2NCCJHGSSY, miragecreativelab.com; the site was never updated) [V].
  - Store today: "1 to 16 players" (store API) [V].
  - The cap went from 8 to 16 in 0.13.0, but only when duplicate colours are allowed. A fix followed the same day for lobbies above 8 not working (PN 0.13.0, 0.13.1, SUMMARY) [V].
  - Before that, a mod ("PlayerPlusPlus") gave 10 to 16 (https://steamcommunity.com/app/2780980/discussions/0/4759830532863466412/; YouTube "Up To 16 Players In A Lobby With This Mod!", https://www.youtube.com/watch?v=G4-OXcQpYmM) [P/V title].
- **The developers' balance point is 5 to 8** (Dev update #2) [V].
- **Players recommend:**
  - "at least 5" and "Best at 6 or 7 but min is certainly 5" (https://steamcommunity.com/app/2780980/discussions/0/599639565862505302/) [P].
  - "need at least 4 … 6-7 feels like the sweet spot" (review 76561198100951441) [P].
  - With 4, "the dissident won 99% of the time" (https://steamcommunity.com/app/2780980/discussions/0/4428814417440681280/) [P].
  - With 3, "you can't really have a dissident because they throw off the balance" (https://steamcommunity.com/app/2780980/discussions/0/6546631477890117789/) [P].
  - "Look at the size of the map. do you think more than 8 players makes sense" (thread 4703539060902426956) [P].
- **Solo** means the tutorial and practice: "You can access the tutorial at any moment from your tablet if you are in solo" (PN 0.1.17) [V].

---

## 6. Cosmetics and the points shop

- **There is no in-game currency or earned unlocks.** Customisation is free to choose among what you own, and the extras are paid DLC.
  - Colours: one per player, with "Purple" added (PN 0.1.31).
  - Suit variants (PN 0.2.0); bag patches and a charm (PN 0.3.0).
  - Body skins: Tiphanie, Theodore, Delphine, Cleo, Retro (PN 0.3.0, 0.10.0, 0.16.0, 1.5.0).
  - From 0.14.0, a material system lets you paint any model with any owned material, plus eye and hair colour (PN 0.14.0).
  - A 2D skin-colour slider (PN 0.12.0); 12 saved character presets (PN 1.2.0); metal finishes (PN 1.5.0) [V].
- **The DLC packs** were promised to remain "the only 3 DLCs in the game". New content goes into them at no extra cost (PN 0.10.0, 0.16.0, 1.2.0) [V].
- **Other cosmetic sources:** Kickstarter skins, contest-winner patches and charms, and a Twitch drop that was made free for everyone (PN 0.9.0, 1.0.1, 1.1.0) [V].
- **The "Points Shop" is Steam's, not the game's.** The Steam Loyalty API lists 10 items: 5 emoticons at 100 points, 3 profile backgrounds at 500, 1 avatar frame at 2,000 and 1 animated avatar at 3,000 (https://api.steampowered.com/ILoyaltyRewardsService/QueryRewardItems/v1/?appids%5B0%5D=2780980). They came with the trading cards at 1.0 (PN 1.0.0) [V].
- **Save editing to get cosmetics is a bannable cheat** ("What can get you banned") [V].

---

## 7. Tutorial and how new players learn

- **Learning came in layers over time:**
  1. Partial video tutorials in the tablet (PN "1.1.12", really 0.1.12).
  2. Task videos on a big lobby screen and in the tablet; before that they linked to YouTube (PN 0.1.16).
  3. A basics tutorial room. Every player was sent there after the update and could leave at any time. Its walls were later recoloured (PN 0.1.17, 0.1.18).
  4. The difficulty presets above (PN 0.1.26).
  5. In-game item stats on hold (PN 0.1.13).
  6. Lobby wall panels (PN 0.14.0).
  7. A new tablet at 1.0 "including shortcuts to various menus and tutorials for the basics" (PN 1.0.0) [V].
- **Players disagree on how well it works.**
  - Negative: "tutorial covers nothing" (https://steamcommunity.com/app/2780980/discussions/0/4635988779091464947/) [P]. "no one knows how to do pressure they just blow that up until it works" (https://steamcommunity.com/app/2780980/discussions/0/4845401032848890435/) [P]. A beginner video says "The in game tutorials aren't the best, and some of the tasks have tricks to them that are not easily discovered" (https://www.youtube.com/watch?v=EHTUQjfGCp0) [V for the description]. Steam's popular guides include "Pressure Task Explanation" and "Scanner Tutorial (Solo)" (https://steamcommunity.com/app/2780980/guides/) [V for titles].
  - Positive: in 2026 reviews, "tutorials are good and easy to comprehend" (76561199217739230) and "Tutorial videos very well made!" (76561198727611979) [P].
  - Players asked to watch tutorials while dead (https://steamcommunity.com/app/2780980/discussions/0/4428814058382603960/) [P]. A forum regular describes a newcomer who skipped "the obvious tutorial section in the lobby and tablet" (https://steamcommunity.com/app/2780980/discussions/0/4625853246786769821/) [P].
- **How groups really learn: a private practice lobby.** "you can start custom games on your own and test the tasks a little bit with the videos" (thread 4635988779091464947) [P]. This matches the engineer's memory of opening a separate lobby to learn Pressure.
- **The Pressure punishment was softened.** A cooldown after the machine explodes was added to "encourage using the blinking lights to finish the task faster" (PN 0.1.13) [V]. I did not verify the "kills everyone" detail. The task teardown covers it.
- **Task count at the end of 2024:** a beginner video's chapters list 8 tasks: Alimentation (renamed Power in 0.4.0), Analysis, Computers, Delivery, Pizzushi, Pressure, Scanner, Vents (https://www.youtube.com/watch?v=EHTUQjfGCp0; PN 0.4.3) [V].

---

## 8. What makes it work

1. **The space was built around the tasks** [V Dev update #2]. Rooms exist because a task chain needs a walk between a tool, a machine and a drop-off. The walks create the meetings.
2. **The map size was fixed to the player count** (5 to 8) and held there against strong community pressure [V]. Players still hit each other often enough for social play [A].
3. **Sound that travels like sound** [V site]. Voices come around corners with the right direction, so a cry for help is real information while privacy is still possible. Players name proximity chat as the main reason they prefer it to Among Us (vaporlens summary, https://vaporlens.app/app/2780980/lockdown_protocol.md) [S].
4. **One layout, a new spread each match:** random items, a random access card, crates that unlock at random [V]. Locked rooms force a match-level decision ("choose wisely") [V].
5. **Layers of host settings with presets**, so each group shapes its own game [V].
6. **Physical tools for talking without words:** pointing, raised hands, winking, the helmet glow [V]. Cheap features that fill the space between voice and action [A].
7. **A lobby that is a place** with a mirror (the mannequin), screens, a museum, and later safety [V]. It holds the community's identity [A].

## 9. What players complain about

1. **One map forever,** and the sense of being abandoned after 1.0 (many 2026 reviews, for example 76561198385999296, 76561198304432722) [P]. The developers did say plainly: no new maps ("What's next") [V].
2. **Paid cosmetics at full game price,** especially body types ("Gender DLC", https://steamcommunity.com/app/2780980/discussions/0/599639260006502456/) [P].
3. **Toxic public lobbies, kicks, griefing and cheaters** (vaporlens [S]; reviews 76561199066448943, 76561199742780321 [P]). The developers answered with bans of 240, then 41, then 15 cheaters (PN 0.15.0, 1.0.0, 1.6.1) [V].
4. **Being a ghost is boring.** You cannot fly, there are no nametags, and you cannot see who is alive or talking (threads 4845400193810649516, 603020374162118416; review 76561198128471209) [P].
5. **Voice gaps:** no per-player volume, voice cannot be muted, mic setup trouble (section 2.5) [P/V].
6. **Role draws feel streaky,** especially on force-start (threads 4764333414208635266, 4845401230251980961) [P].
7. **Small groups break the balance** (3 or 4 players) (section 5) [P].
8. **Hard tasks are poorly taught** (Pressure, Scanner) (section 7) [P].

## 10. Mechanic -> lesson -> an original direction for our alien party

The third column is **a proposal for the engineer** in every row. It is not a decision and not a copy. Our design context: House on four levels (`docs/GDD.md:728-735`), voice is pure 8 m distance now and walls should muffle it (m8-match §8 on main), nobody hears the dead (`docs/GDD.md:715-719`), the lobby is the aliens' spaceship (m8-match §1), weapons come with host presets (m8-match §7), the tutorial deals no task (`docs/GDD.md:752-766`).

| Mechanic in LOCKDOWN Protocol | What it teaches us | An original direction for our alien party (proposal for the engineer) |
|---|---|---|
| One map, size tuned to 5 to 8 players, enlargement refused | Size and player count are one decision. A map that is too big at 4 empties out, one too small at 10 jams. | Proposal: for small parties, close off part of the House in a way that fits the story. The aliens' party grows room by room: below a host-set guest count, the planner has shut the attic or the basement with "party not here yet" tape. The same House then plays at 4 and at 10. |
| Rooms laid out around task chains (tool, machine, drop-off) | The walks are where people meet. Place them on purpose. | Proposal: draw each chain of ours on the House plan as a line, and make sure every pair of chains crosses in at least one shared room (the kitchen, the stairs) so routes meet naturally. |
| Card-locked rooms, one card, "choose wisely" | A scarce key turns layout into a decision the team argues about. | Proposal: a single "party upgrade" token per match that opens one of several party extras (a dance floor in the garage, a roof bar, a basement arcade). Each changes the routes or the noise. Humans can steal the token or waste it. |
| Colour-coded sectors, signs, icons on the tablet map | Players learn a map through colour plus labels, not by memorising it. | Proposal: each floor of the House gets its own party light colour and decorations. Our tablet map uses the same colours, so "the blue floor" is something you can say over voice. |
| Fixed vent spots shown on the map, broken ones random | "Search" fun works when the places are known and the state is not. This matches our open-knowledge pillar. | Proposal: a decoration task where all spots are drawn on the map but which ones are "sad" (deflated, unlit) is only visible on site. Fix them in any order, and the room's music gets louder each time. |
| Path-based sound around corners, not wall muffling | Direction plus a route around walls gives both privacy and calls for help. | Proposal: under our planned wall muffling, add one game-logic voice rule. Loud party zones (a speaker a player can turn up) mask voices nearby, which makes quiet spots for plotting and lets humans drown out a warning. |
| No radios, no private dissident channel | Leaving out radios keeps distance meaningful. Players still want one. | Proposal: a rare alien toy pair (two linked party antennas) that lets their two holders hear each other at any distance. Everyone can see who wears one, so it can be grabbed and is never a secret. |
| Ghost orbs talk only to each other, the living cannot see them, winking while dead blocked | The no-dead-to-living rule must cover every channel, gestures and eyes included. | Proposal: when we add gestures and faces, put them under the same rule as voice in `core/` (a downed or dead player's gestures reach nobody). Run them through the bots leak test like voice. |
| Ghosts have nothing to do | Long spectating is the top dead-player complaint. | Our 30 s respawn already answers this. Proposal: while waiting, the dead pick their respawn "entrance" (a door, a window, the chimney) from a short list, so the wait is a choice and not idle. |
| Wink, pointing, hands up, helmet glow when talking | Cheap body signals give the space between voice and action, and they are fun at once. | Proposal: alien expressions (antennae up or down, eye-stalk blink, a glow when talking), in the lobby from the first second (our "fun from the first second" pillar). |
| A walkable lobby with a mannequin, screens and a museum, damage off after griefing | The lobby is a place, and it must be safe from griefers. | Proposal: the spaceship lobby has a mirror for customisation, a holo-screen with 15-second clips of each task, and a crew photo wall of recent matches. No harm can be done there by design. |
| Presets (Training, Beginner, Normal, Custom) plus saved presets, players ask for ranges | Presets are the easy way in. Ranges ("1 to 2 humans") add surprise. | Proposal: three named party presets (calm, normal, wild) plus saved custom ones. A host may set the number of humans as a range, which fits our "randomness is fun" pillar. |
| A setting for each new item or room (alarms, cards, defibrillators, reload station) | When each mechanic arrives with its own on or off, settings scale with content. | Proposal: every content Resource (item, task, sabotage) declares its own host setting and default, and the lobby lists them automatically. A small change, inside our "mechanics are data" invariant. |
| Grouped or sparse spawn | Spawn layout changes the first minute. | Proposal: a host choice between "everyone arrives together at the front door" and "guests are already scattered around the House". |
| Up to 16 only with duplicate colours | More players means telling people apart is harder. | Proposal: since we cap at 10, keep colours unique and give each player a name shown when nearby (a party badge), so voice and face line up. |
| Players open a private lobby to learn a hard task | A deadly task with no safe practice gets learnt outside the game. | Proposal: a "rehearsal party" lobby option with no humans, any task chain on, and instant respawn. Lets a group learn our harder chains (including any "a mistake hurts everyone" task) without a full match. |
| Paid DLC skins at full game price, backlash | Paywalled identity (body type) hurts goodwill. | Proposal: for a hobby game, all faces and bodies are free. Rare cosmetics are earned through our points or meta-progression (M8.3). |

## 11. Open questions

**For the engineer:**
1. Should the House shrink for small parties (rooms closed below a guest count), or always play whole?
2. Do we want any voice-masking rule (loud party zones) on top of walls muffling (#1035)?
3. Should gestures and alien expressions be under the same dead and downed rule as voice?
4. Do we want a "rehearsal party" practice option, or does the no-task tutorial plus a normal match with 0 humans cover it?
5. Should host settings allow ranges (for example 1 to 2 humans), or exact counts only (#1032 says exact)?
6. Do we want a one-per-match key-style choice in the House?

**Not found or not verifiable:**
- An official map image or room count, and the map's size in metres.
- The voice range in metres, and whether ghosts hear the living. Only bug reports hint at it.
- What each preset (Training, Beginner, Normal) sets.
- The full Custom settings menu, task-count and dissident-count limits.
- Whether a meeting or voting exists. A 2026 thread asks "does the game have voting?" and the replies suggest none (https://steamcommunity.com/app/2780980/discussions/0/804596245555435938/) [P].
- The developer's in-game roadmap.
- The Kickstarter page (HTTP 403, Cloudflare) and the Fandom wiki (HTTP 402).
- Steam guide bodies: they are rendered on the client, and the API returned result 9.
- Reddit: blocked.
- YouTube transcripts: 404.

---

### References: patch notes in the official feed

Base URL: `https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/<id>`

| Post | id | Post | id |
|---|---|---|---|
| "0.7" | 5969041959980209427 | 0.1.10 | 5969041959983789532 |
| "1.1.12" (0.1.12) | 5963413094348609804 | 0.1.13 | 5963413094362993265 |
| 0.1.16 | 5963413728335602739 | 0.1.17 | 5963413728350074254 |
| 0.1.18 | 5963413728350100295 | 0.1.22 | 5963414363394658604 |
| 0.1.24 | 5875594803674905743 | 0.1.25 | 5875595438706842498 |
| 0.1.26 | 6240387642453992521 | 0.1.27 | 6341720536506870787 |
| 0.1.29 | 6341720536507169691 | 0.1.31 | 6341720536510634270 |
| 0.2.0 | 1783872412119573 | 0.2.2 | 1784506359024311 |
| 0.3.0 | 1786409468853983 | Dev update #2 | 1786573930684503 |
| Dev update #3 | 1789039014502669 | 0.4.0 | 1794830910909080 |
| 0.4.1 | 1794830910914277 | 0.4.2 | 1794830910971904 |
| 0.4.3 | 1794830910977217 | 0.5.0 | 1795283637796297 |
| 0.5.2 | 1795283637816521 | 0.6.0 | 1795283637848735 |
| 0.6.1 | 1795283637964318 | 0.6.2 | 1796631172249159 |
| 0.7.0 | 1797185861741648 | 0.7.1 | 1797185861744713 |
| 0.8.0 | 1799088287806789 | 0.9.0 | 1803527891452146 |
| 0.10.0 | 1803527891781088 | 0.11.0 | 1808601382457961 |
| 0.12.0 | 1809869180011514 | 0.12.1 | 1809869180013278 |
| 0.12.3 | 1809869180067653 | 0.13.0 | 1809869180167881 |
| 0.13.1 | 1809869180168425 | 0.14.0 | 1810503566590423 |
| 0.14.2 | 1811138915364785 | 0.15.0 | 1811138915562759 |
| 0.15.3 | 1811772772248762 | 0.16.0 | 1813041031380453 |
| SUMMARY 0.1 to 1.0 | 1816307528974161 | What's next | 1816307528974164 |
| 1.0.0 | 1816307528974172 | 1.0.1 | 1816849002008569 |
| 1.1.0 | 1817483467039846 | 1.2.0 | 1818752592128670 |
| 1.3.0 | 1818752592137222 | 1.4.0 | 1828441623110624 |
| 1.4.1 | 1828441623110914 | 1.4.3 | 1832700592787228 |
| 1.5.0 | 1833968530895846 | 1.6.0 | 1836506165547478 |
| 1.6.1 | 1843481262702321 | What can get you banned | 1843481262702346 |

The researcher's raw downloads (the patch-note feed as text, wiki and guide extracts) were temporary working files of the session and are not kept.