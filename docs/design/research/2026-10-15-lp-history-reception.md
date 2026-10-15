# LOCKDOWN Protocol: history and reception (research for prime-game)

**Scope.** This report covers the history and reception of LOCKDOWN Protocol (Mirage Creative Lab, Steam app 2780980). It gives a timeline of every update from the Kickstarter to now (2026-10-15), with the developers' stated reasons. It covers the sales and player-count estimates, review scores over time, what players love and hate, the creators who spread the game, what it does that Among Us does not, and lessons for a small team. Other researchers in this round cover the task-by-task teardown. This report checks the engineer's memories only where the history sources touch them.

**Markers.** [V] means verified at a source I read. [S] means I saw it only in a search summary. [P] means a player's opinion. [A] means my own analysis.

**Source keys** (each one fetched live on 2026-10-15):
- **N**: the Steam news API, <https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=2780980&count=100&maxlength=0>. It returned 96 items, from 2024-02-06 to 2026-09-14, and I read every one. Items are cited as N "title" (date).
- **RS**: the review summary, <https://store.steampowered.com/appreviews/2780980?json=1&language=all&purchase_type=all&num_per_page=0>.
- **RH**: the monthly review histogram, <https://store.steampowered.com/appreviewhistogram/2780980?l=english&review_score_preference=0>.
- **RV**: the "most helpful" reviews, <https://store.steampowered.com/appreviews/2780980?json=1&language=english&filter=all&review_type=negative&num_per_page=60&day_range=9223372036854775807> (also `review_type=positive`, and `filter=recent`). Reviews are cited by recommendation id. Where I have the author, the review page is `https://steamcommunity.com/profiles/<steamid>/recommended/2780980/`.
- **SA**: the store app details, <https://store.steampowered.com/api/appdetails?appids=2780980&l=english&cc=us>.
- **SC**: Steam Charts, <https://steamcharts.com/app/2780980>.

---

## 1. The studio and the pre-launch (2024-01 to 2024-07)

- **Studio.** Mirage Creative Lab, based in France. The Kickstarter tracker lists the location as "France" [V, <https://www.kicktraq.com/projects/miragecreativelab/lockdown-protocol/>]. The patch notes show French habits: the power task was first called "Alimentation", and one note says "Machine et Storage" [V, N "UPDATE 0.4.3" 2025-03-23 and "UPDATE 0.8.0" 2025-05-07].
- **Team.** The team was "initially 3 siblings before our expansion a few weeks ago", and they "all learned the field on the go" [V, N "Dev update #2" 2024-12-21]. A month later the developers said: "only two of us have actively worked on the game, and only one has the skills to work on internal game structure rework". The new hires were long-time friends who were hired for their potential and then trained [V, N "Dev update #3" 2025-01-21].
- **Engine.** Unreal Engine 5.2, moved to 5.5 in March 2025 [V, N "UPDATE 0.4.0" 2025-03-21].
- **Announcement trailer.** Posted 2024-01-31 [V, <https://www.youtube.com/watch?v=I6vN0EYSR0Q>]. The "Trailer & Gameplay" video followed on 2024-02-03, pitching "3 to 8 players" [V, <https://www.youtube.com/watch?v=D2NCCJHGSSY>]. A "Sound spatialization in LOCKDOWN Protocol" video went up on 2024-02-07. Positional voice was a selling point from day one [V, <https://www.youtube.com/watch?v=DO4UJn-JOOo>].
- **Kickstarter.** It ran 2 February to 3 March 2024 with a €10,000 goal. It raised €10,776 (107%) from 141 backers, an average of €76 [V, Kicktraq above; the Kickstarter page itself returned 403]. The only listed extra goal was a social-media goal that unlocked four faces [V, Kicktraq]. A Steam post on 2024-02-06 said the campaign was "30% of our total goal" [V, N "LOCKDOWN Protocol is live on Kickstarter!"].
- **A developer quote, second-hand.** A Steam reviewer quotes a later developer announcement (apparently October 2025, not on the Steam feed): "The goals mentioned earlier were part of our Kickstarter campaign, and even the first milestone was reached with some difficulty. Since we didn't reach the others, we simply focused on finishing the game as quickly as possible so we could move on to the next project." [P, review 207275782, <https://steamcommunity.com/profiles/76561198073295936/recommended/2780980/>]. The funding level fits that quote (107%) [A]. I could not read the original announcement, which was probably on Discord.

## 2. Early-access launch and the viral wave (2024-07 to 2024-12)

**Launch.** Early access started on 22 July 2024 at $9.99 (1,200 yen) [V, <https://streamscharts.com/games/lockdown-protocol/release-stats>; <https://automaton-media.com/newsjp/lockdown-protocol-20240820-306493/>; price in SA]. The first-day Twitch numbers were tiny: 54 hours watched and a 73-viewer peak. ChilledChaos led the first week with 17,966 hours watched and a 6,337-viewer peak [V, Streams Charts].

**How it spread.** The spread came from creators, and it was international [V: upload dates and views read from each video's YouTube page on 2026-10-15]:

| Date | Creator (country or language) | Video | Views |
|---|---|---|---|
| 2024-07-30 | alanzoka (Brazil) | "The New Among Us? - Lockdown Protocol with Friends" <https://www.youtube.com/watch?v=z39Vno0d0Gc> | 3.94M |
| 2024-08-20 | SMii7Yplus (English) | "This Game is NOT Among Us" <https://www.youtube.com/watch?v=i-6FixLeUq4> | 7.43M |
| 2024-08-21 | penguinz0 (English) | "This is the New Among Us" <https://www.youtube.com/watch?v=9REDTDNA_Yc> | 1.92M |
| 2024-09-10 | The Boys Gaming | "The Boys Are Definitely NOT Playing Among Us" <https://www.youtube.com/watch?v=IN4y9Or2XEU> | 1.89M |
| 2024-09-14 | Marmok (Russian-speaking) | "Мармок Предатель (LOCKDOWN Protocol)" <https://www.youtube.com/watch?v=EPKNhrMntTw> | 5.12M |
| 2024-09-25 | Live Insaan (India) | "Among Us in 3D is Actually Epic" <https://www.youtube.com/watch?v=T-umpczf4RU> | 3.99M |
| 2024-10-14 | Silvio Gamer (Spanish) | <https://www.youtube.com/watch?v=rUdwona92eg> | 4.50M |
| 2024-11-13 | MoreSidemen (UK) | "SIDEMEN LOCKDOWN PROTOCOL" <https://www.youtube.com/watch?v=unfHSfnvi0E> | 3.97M |
| 2025-05-17 | Aries Akana (VTuber) | "Aries Gets TAMED In Lockdown Protocol" <https://www.youtube.com/watch?v=AfKVTz7f5n0> | 1.09M |

The YouTube view-sorted search also shows ElMariana (Mexico, 3.7M), Brino (Brazil, 3.0M), Elraenn (Turkey, 2.9M), 1337LikeR (Russian, 2.2M) and NotGamerFleet (India, 3.0M) [V, <https://www.youtube.com/results?search_query=lockdown+protocol&sp=CAM%253D>, fetched with curl].

**The surge in numbers.** On 2024-08-20 AUTOMATON reported more than 1,000 concurrent players on 15 August and more than 3,000 on 18 August. It also reported a Twitch peak above 50,000 viewers on 15 August (citing TwitchTracker), and about 470 reviews, 95% positive [V, AUTOMATON]. Screen Rant (2024-10-03) credits the penguinz0 video with "1.4 million views" at the time and says the game was "trending across social media" [V, <https://screenrant.com/lockdown-protocol-gameplay-mystery-party-game/>]. VTubers mattered later. One review credits YokaSiri and Aries Akana for its purchase [P, review 228065530], and the 1.0.1 notes fix collisions on a "Yokasiri & AriesAkana terrarium" in the museum [V, N "UPDATE 1.0.1" 2025-11-19].

### The 0.1.x patches (July to September 2024)

The feed has no posts for 0.1.0 to 0.1.8. The two launch-day posts are titled "Update 0.6" and "UPDATE 0.7" [V, N 2024-07-22]. What the patches added or changed:

- **Launch-day fixes (22 to 25 July).** Fixes to the "Computers" task lock, the "Alim Box" battery sound, the "Analysis" sample slot and "Delivery case" netcode. Sessions could now be Public, Hidden or Private, and partial video tutorials went into the in-game tablet [V, N 2024-07-22 to 07-25].
- **0.1.13 (29 July).**
  - Random player spawns "to avoid unfair advantage".
  - The host can kick players.
  - A full combat rebalance (damage, endurance cost, range), with item stats shown on a hold-key.
  - Music cassettes, all NCS tracks, "so they should be fine for content creators".
  - **The pressure rebalance:** "There is now a cooldown when the pressure machine explode, before you can interact with it again. This encourage using the blinking lights to finish the task faster." [V, N "UPDATE 0.1.13"].
- **0.1.16 (1 August).**
  - Task video tutorials on a big screen in the lobby.
  - Temporary bans.
  - Rebalanced default settings, and "an option to disable weapons".
  - A screwdriver rebalance.
  - The cheat mode was removed because "Some players abused this in public sessions" [V].
- **0.1.17 (5 August).** A basic tutorial that every player is sent to after the update. Stamina now recharges much faster near full, "to better reward the stamina management" [V].
- **0.1.19 (5 August).** "Fixed issue with the screws on the vents task" [V]. This confirms the vents task uses screws.
- **0.1.22 (9 August).** "Weapons now spawn evenly across all sectors… our system was flawed and resulted in a roughly 50% spawn chance in storage" [V].
- **0.1.24 (14 August).** Forward sprint raised from 7 to 8 m/s [V].
- **0.1.25 (27 August).** Persistent local bans. "Hands up" now drops the held item [V].
- **0.1.26 (29 August).** Difficulty presets (Training, Beginner, Normal, Custom). The stated reason: "new players are often lost regarding what parameters to tweak" [V].
- **0.1.27 to 0.1.31 (20 to 21 September).** Character customization (beta), a purple colour, and one colour per player [V].

The official channel's task tutorials, uploaded 25 to 27 July 2024, show seven tasks: Analysis, Pressure, Computer, Scanner, Alimentations, Vents and Delivery. Pizzushi has none [V, <https://www.youtube.com/channel/UCQ2yTM6_UxDo3kHed060Tpw/videos>]. A player guide from 2024-08-31 lists eight tasks: Pressure, Delivery, Pizzushi, Analysis, Vents, Computers, Scanner and Alimentations (finding, then doing) [V, description of <https://www.youtube.com/watch?v=vRvoqHCTO_A>].

**Pressure stands out.** The official Pressure tutorial has 37,684 views. The other official tutorials have 6,258 to 12,631 [V, view counts on each watch page]. Pressure was the task people had to look up [A]. This fits the engineer's memory that his group opened a separate lobby to learn it.

### The weapon-crate fight (November 2024)

- **0.2.0 (25 November).** It named the problem: "The 'run to get a gun asap' META has been a problem since the beginning". Guns then spawned only in code-locked Weapon Crates, and an opened crate shows its contents "in shaped foam that lets the other players know what was inside" [V].
- **0.2.2 (28 November).** Three days later the developers admitted: "Weapons crates haven't been received well by the community. The previous iteration was a bit rushed and not tested internally as much as we wished, in a hurry to release the update before Steam sales begin. This proved to be a big mistake". They then:
  - put half the weapons back on the field (50% in crates, 50% on the field);
  - brought back random ammo;
  - made guns weaker at range and more costly in stamina;
  - locked crates for a few minutes at match start, then made them unlock at random;
  - made a failed code lock the crate again;
  - cut code attempts from 9 to 7;
  - opened a survey [V].
- **What players said.** "Everyone STILL runs for the weapon crates but now it can take some time to get one to open" [P, review 179820119]. "no one stays alive long enough to even start tasks" [P, review 179827952].

### Paid cosmetics and the second backlash (December 2024)

- **0.3.0 (18 December).** Only three active crates now ("reducing the attention and time spent opening crates"), plus Christmas decorations. It also brought **three paid DLCs**: Contrast ($4.99), Winter ($4.99) and Tiphanie ($9.99, "the first skin that completely changes the body") [V, N "UPDATATE - 0.3.0"; prices and dates in the DLC appdetails, appids 3391950, 3391960, 3391970].
- **The reaction.** The most-helpful negative reviews from that week are about it. "Releasing DLC that is the same price as the game while the game is in early access is a wild choice" (487 helpful votes) [P, review 183072595]. "the creators just released a DLC where you pay $10 to be a woman" [P, review 183079427]. ChilledChaos posted "WHAT HAPPENED TO THE GAME I LOVE?!" on 2024-12-28 [V, <https://www.youtube.com/watch?v=OxJPA5VA638>].
- **The roadmap reset.** "Dev update #2" (21 December) reset expectations [V]:
  - The UI and session code would be rebuilt, because session management lived "directly into the map".
  - The map would not grow: "the current map is balanced for 5-8 players and the size is fine tuned around that. Making the map bigger would make the experience way too uneven at varying player count and this is something we tested".
  - The round is "the current 8 minute round".
  - Every new map would bring its own mode. The next one was planned as "larger and designed for 16 players, with longer rounds".
  - Their design philosophy: "we designed everything as a whole and tested thoroughly for hours until it was fun… positioned every room and corridors to ensure interesting player interactions".
- **VICE (2024-12-31).** Praised the proximity voice ("each moment of silence all the more horrifying") and mentioned two-player tasks such as the scanner [V, <https://www.vice.com/en/article/lockdown-protocol-is-the-newest-game-my-friend-group-is-obsessed-with-and-for-good-reason/>].

## 3. The quiet rebuild and the 1.0 roadmap (2025-01 to 2025-06)

- **The gap.** Nothing shipped from 0.3.1 (2024-12-19) to 0.4.0 (2025-03-21). That is about three months during the steepest player decline (§6) [V, N dates]. "Dev update #3" (21 January) explained that one person was doing the restructure [V].
- **0.4.0 (21 March).** UE 5.5, a new render and an FPS gain, a full review of collisions "to fix most bugged and unfair hiding spots", and the Christmas decorations removed ("yes, finally") [V].
- **"Dev update #4" (24 March).** "In the past, we made the mistake of keeping future content 'secret' to keep the surprise" [V].
- **0.5.0 (26 March), alarms.** One alarm per sector. Each needs a white fuse, and not every alarm has one at the start. Pulling the fuse while the alarm sounds "will permanently disable the alarm for the rest of the match" [V]. Some hiding spots came back: collisions inside the pressure machines and under some desks were removed [V]. In 0.5.2 a sound-clipping effect was reverted because it "hasn't been received well" [V].
- **0.6.0 to 0.6.2 (28 March to 10 April).**
  - **Wink:** two keys close the left and right eyes, and other players see it ("be creative!").
  - **Snap throw:** throwing an item can snap it into a machine slot.
  - **Fish:** an April Fools' "fish stuck on your back" stayed for good, "to see how it affects balance".
  - In 0.6.1, winking while dead was fixed: "you could communicate while dead with that" [V].
- **The roadmap (4 April).** The text says "plenty of mechanics are missing" and that 1.0 would be "a stable base before expanding the game with new game modes and maps" [V, N]. The roadmap itself is three images [V, read from <https://clan.akamai.steamstatic.com/images/44859328/91a1a4603182e93d38d2b648137825d4f6ecbffc.png>, `…/7af5e8f19f321f41cd63dcf01915c98795fa7fc6.png`, `…/a7c0bff8fd4abc6e4a56ce10a250a57e3d61630f.png`]:
  - "the current map is not finished… a first playable draft".
  - "Slight rework of existing tasks. New tasks."
  - Extra rooms "accessible under specific conditions", and new non-task items and mechanics.
  - Hand emotes, deeper session settings, an in-game nickname and password, translations.
  - Full controller support.
  - Steam achievements, with achievement patches and a global levelling system with free cosmetics.
  - Planned post-1.0 modes: **"SHRIMP GAME, INVESTIGATION, RACE, CHASE, SABOTAGE"**.
- **0.7.0 (20 April), defibrillator.** It sits on a wall mount in medical and charges from two batteries placed at the same time. One charge "will either resurrect a dead player, or deal heavy damage on a living one". The knife now needs 3 frontal hits [V]. A same-day "REVERT TO 0.6.3" for "game breaking bugs" was followed by 0.7.1 [V].
- **0.8.0 (7 May), Machine Supply room.** Opened by a randomly spawning Access Card. It holds fast battery chargers and "random extra supply for certain tasks, but also doubles down as extra hiding space". Alarms now switch off after 10 s [V].
- **0.9.0 (24 June).** Two more card rooms: a Research Corridor (a shortcut into "the deadly dead end in the Botanics Greenhouse") and an Emergency Room (3 more defibrillators "but also some deadly scalpels"). There is still one card, so "only one of the 3 rooms can be opened per match, so make sure you choose wisely" [V].

## 4. Toward 1.0 (2025-07 to 2025-11)

- **0.10.0 (4 July).** Summer water-gun skins. The DLCs were renamed (Characters, Contrast, Events), with "These three will remain the only 3 DLCs in the game!" New skins were added inside the existing packs [V].
- **0.11.0 (21 August).**
  - The armory became a card room with a weapon reload station that is fed "by placing the matching plant sample".
  - A chance of a second card, in the camera room.
  - Miscellaneous items now spawn "more organically in fitting areas" [V].
- **0.12.0 (3 September).**
  - A new menu, lobby names, and a "Friends" session type.
  - No damage in the lobby, to "prevent cheaters from killing the host attempting to ban them".
  - Steam "recently played with" support.
  - New session settings: gun spawn mode, knives, detonator chance, alarms.
  - The reload station gives half the ammo per refill, and card rooms were buffed (pre-charged defibrillators, faster chargers).
  - 0.12.1 raised the maximum session from 20 to 60 minutes [V].
- **0.13.0 (8 September).** Duplicate colours became optional, and turning them on raised the player limit to 16: "It's difficult for our small team to properly test the game with 16 players" [V].
- **0.14.0 (16 September).** A new lobby with guiding wall panels, a materials-based customization revamp (the Contrast DLC became materials), and a sparse-spawn option [V].
- **0.14.4 and 0.15.0 (19 to 23 September), the social rebalance.** The changes:
  - higher stamina cost for every melee attack, "to further punish missed attacks and reward self control";
  - more knockback, "to make escape out of a duel much easier";
  - less frontal damage, "to promote and reward planned assassination";
  - a slower knife that "requires good execution and planning to confirm a kill".

  The stated goal: "to leave more space for the social aspect, while still rewarding good execution of assassination plans under the right opportunities". The same update added a heavy crate in the armory (a second card, always an empty rifle that cannot go in the bag) and a report button that sends players to Discord. It also permanently banned 240 cheaters: "We cannot provide a proper anti-cheat" [V].
- **0.16.0 (14 October).** Halloween cosmetics, and the last update before 1.0 [V].
- **1.0.0 (18 November 2025).** "we implemented all planned features". 1.0 added [V]:
  - a lobby museum (Kickstarter backers, the team, contest winners and streamers);
  - eight languages;
  - visual polish on the Pizzushi and the Power and Pressure panels ("remove unnecessary text"), and a PC task "more comprehensive, and easier on our side, to translate";
  - Steam cards, a public beta branch, a settings reset, and 41 more cheater bans.
- **"What's next for Mirage Creative Lab?" (18 November 2025).** The studio is "moving our main focus to a new game project". The game "is mostly in a finished state". Guaranteed: bug fixes, a beta branch, more session settings, more cosmetics. Maybe: events, languages, weapons, music. Not coming: "New maps" and "Integrated mod support" [V].
- **What the roadmap delivered.** The two posts together show it [V, by checking all 96 news items]:
  - Not delivered: no new task, no new map, none of the five modes, no Steam achievements (SA lists no achievements category), no controller support, no hand emotes.
  - Delivered: the card-locked rooms, the extra items, session settings, translation, and the social features.
- **LV1 Gaming (22 November 2025)** reports that players who asked about the roadmap on Discord and Steam were banned without explanation. It also says reviews read "Mixed" [S/P, <https://lv1gaming.com/lockdown-protocol-community-experiencing-lockdown-from-mirage-creative-labs/>; my RH data shows November 2025 at 82.5% positive, so "Mixed" probably refers to the recent window or a moment].

## 5. After 1.0 (2025-11 to now)

- **1.1.0 (28 November).** A shotgun in the heavy crate. A Loserfruit skin ("designed for one of our community members, as thanks for their massive contribution on our Kickstarter campaign"). A Makeship plushie. Faster battery recharge, because "the recharge time felt a bit out of place and broke the flow of the game" [V].
- **1.2.0 (12 December).**
  - An SMG and saved session presets.
  - A battery-speed multiplier from 50% to 200%.
  - Rice bags spawn even when the Pizzushi task is off, "So you can now make Pizzushi with friends no matter the available tasks!"
  - The heavy crate is always on, and the default is 2 access cards [V].
- **1.3.0 (16 December).** Christmas became a map-theme setting. Breakable cookies heal "on frontal hit". Each card room can be locked, closed or open. Hit, shot and break sounds reach about 50% farther [V].
- **1.4.0 to 1.4.3 (March to May 2026).** A fix for microphones heard "globally instead of locally". Anti-cheat hardening. Invitations temporarily host-only because of an exploit [V].
- **1.5.0 (31 May) and 1.6.0 (25 June).** Retro skin, metal materials, an in-game nod to a couple who met in the game and married, a summer theme, healing popsicles, and doubled cookie healing [V].
- **1.6.1 (14 September 2026).** A "modded lobby" flag: "Using any modification of the game outside of these lobbies is bannable". It came with a post on what gets you banned, including harassment in public lobbies, and 15 more bans [V].

Mod support exists only in this informal form. There is no official Workshop [V, N 2025-11-18 and 2026-09-14].

## 6. Numbers: players, sales and review scores

**Concurrent players** [V, SC; peaks are monthly highs]:

| Month | Avg | Peak | Note [A] |
|---|---|---|---|
| 2024-07 | 24 | 105 | launch |
| 2024-08 | 1,363 | 7,530 | alanzoka, SMii7Y, penguinz0 |
| **2024-09** | **4,216** | **9,318** (all-time) | Marmok, The Boys, Live Insaan |
| 2024-10 | 3,109 | 6,970 | |
| 2024-11 | 2,075 | 6,450 | crates, 0.2.0 |
| 2024-12 | 2,291 | 7,968 | winter sale and paid DLC |
| 2025-01 | 1,785 | 4,751 | no updates until March |
| 2025-03 | 733 | 1,967 | |
| 2025-07 | 572 | 1,378 | |
| 2025-11 | 468 | 1,131 | 1.0: **no spike** |
| 2026-01 | 527 | 1,246 | |
| 2026-09 | 255 | 669 | |
| last 30 days | 247 | 598 | |

There were 82 players online at about 16:00 UTC on 2026-10-15 [V, <https://api.steampowered.com/ISteamUserStats/GetNumberOfCurrentPlayers/v1/?appid=2780980>]. One reviewer says "the player base has already dropped from ~10k to ~1k daily players within a year" [P, review 204533886]. That matches SC [A].

**Sales: all estimates.**
- Raijin: about **764K units and $6.1M gross, "medium confidence"**, with about 408K wishlists and 58K followers. Its "all-time peak 1,426" covers only its own tracking window [S/V as read, <https://raijin.gg/app/2780980/LOCKDOWN_Protocol>].
- SteamSpy: **1,000,000 to 2,000,000 owners** [V as read, <https://steamspy.com/app/2780980>].
- My rough check: 20,060 reviews × 30 to 60 sales per review comes to about **0.6M to 1.2M copies** [A]. The figures fit together.
- On top of base sales: three DLCs at $4.99 to $9.99 and a plushie run [V, SA and N].
- One reviewer says the team "made millions" [P, review 217440767]. That is plausible but not verified.

**Reviews.**
- All time: **Very Positive, 17,239 up and 2,821 down of 20,060 (85.9%)** [V, RS]. English only: 9,498 reviews, 82.8% [V].
- By month (Steam's histogram, about 15K of the reviews) [V, RH]:
  - 2024-07: 95%. 2024-08: 94%. 2024-09: 90%.
  - **2024-12: 82%** (the DLC month; down votes doubled to 400).
  - 2025-03: 81%. **2025-07: 77%**. 2025-10: 79%.
  - 2025-11: 82.5% (825 reviews at 1.0, the second-biggest month after 2024).
  - 2026-04: 89%. **2026-10 so far: 71%** (50 up, 20 down).
- The score never collapsed, but each controversy left a dip [A].

**Press.** I found no review from PC Gamer, Rock Paper Shotgun, Kotaku or other major outlets. Coverage came from AUTOMATON (JP), Screen Rant, VICE, LV1 Gaming, G2A news [S] and Total Apex/Yardbarker [V/S, links above; <https://www.yardbarker.com/video_games/articles/lockdown_protocol_version_10_release/s1_17458_42990965>]. I found **no developer interview** [S, several searches]. The game grew through creators, not press [A].

## 7. What players love and hate

**What players love**
- **Proximity voice and the sound.** "Probably some of the best prox chat i've ever played with and the way sound travels is super cool" [P, review 172435912]. VICE says the same [V].
- **Action instead of meetings.** "The short time limit and lack of pausing for arguments make the social deduction portion add to the gameplay instead of being an interruption to it" [P, review 173734360]. Another player: "There are no meetings and the tasks are actually fun to do" [P, review 180318793].
- **Many ways to be a dissident.** "you dont HAVE to lie to win as the killer. You could just throw away all the cups into a corner… You could help do a task and make 'mistakes'" [P, review 180318793]. "win as a pacifist by hiding key items, even letting you win when dead if employees can't finish in time" [P, review 207275782].
- **Combat and stamina.** "Stamina system is interesting and makes sprinting a conscious decision… The shooting has no right to feel as good as it does" [P, review 173734360]. Another calls it a "brilliant stamina/health system" [P, review 189551559].
- **Hard tasks that you learn from friends.** "part of the charm of it is learning the tasks from friends" [P, review 180318793]. "a near perfect mix of challenging long tasks and short simple ones" [P, review 172208595 is about thoughts; quote from review 172435912's neighbour 174425653 context; see the review list: review "id=172... h=38" dated 2024-08-23].
- **Good value with friends.** "Felt like I got my money's worth in 2 hours" [P, review 173734360]. "Friends carry this game" [P, review 191845838].

**What players hate**
- **Monetization in early access** (the most-voted complaints). "Less than 6 months in early access and you have paid cosmetics hitting" (514 votes) [P, review 185920185]. Others call it "$10 to be a woman" [P, review 183079427]. One review adds that the DLCs "are not mentioned on the Steam store page" [P, review 204533886].
- **Feeling abandoned after 1.0.** "No new maps. No new tasks. Minor changes to items. The difference between early access and 1.0 is basically zero" [P, review 209605417]. Several reviews quote the scrapped modes and maps [P, reviews 209609099, 224789527].
- **Cheaters and modders in public lobbies.** "jumping into a random match is impossible without someone ruining the game about 80% of the time by spawning in heavy weapons" [P, review 214710619]. A 1,047-hour player wrote: "completely ruined by modders" [P, review 236264008].
- **Toxic public lobbies.** "public lobbies are mostly chaotic deathmatches without communication" [P, review 204533886]. Other reviews describe harassment and lobbies used as a dating space [P, reviews 194887181, 232823970, 178076634].
- **The first rush for guns.** "Please randomize weapon spawns… everyone just rushes to the weapon spawns" (April 2025, still) [P, review 193061559]. The developers named the same problem [V, 0.2.0].
- **Tasks that are obtuse or random.** One reviewer calls them "Needlessly obtuse puzzles with extensive use of RNG" and adds that one can "get stuck on a computer puzzle for whole minutes because the task keeps randomly failing" [P, review 178810365]. A Steam thread asks "PLEASE just put written tutorials", because "all there is is a vague silent film" [P, <https://steamcommunity.com/app/2780980/discussions/0/599640609289942100>].
- **Death means waiting.** "occasionally you are forced to stop playing the game and sit and be dead with the other dead people for 5 minutes out of a 10 minute game" [P, review 178810365]. Players also asked for "some kind of actions as a ghost" [P, review 174637153].
- **Balance favours whoever has the gun.** "Guns win everything, traitors with the guns kill everyone" [P, review 175519656]. The same review says the inventory (two items, and the held one dropped when the tablet opens) leaves civilians defenceless while doing tasks.
- **Being a dissident can feel flat.** "There's no thrill in being one. You can just kill anyone regardless" [P, review 232823970]. Killing dissidents does not end the match, so "finding the killer [is] largely irrelevant" and a dissident can "camp and puppy-guard the most difficult task" [P, review 178810365].
- **Accessibility.** Colour-only coding, with requests for "an X in the light bar" on dirty vents and "symbols to the batteries for the various colors" on power [P, review 182473562]. A low-stamina tinnitus sound cue was painful for one player [P, review 175850993].
- **Discord moderation.** Bans for questioning the developers [P/S, reviews 194061728, 209573632; LV1].

## 8. What it does that Among Us does not

1. **No meetings and no votes.** Discussion happens in real time over proximity voice while the clock runs [P, reviews 173734360 and 180318793; S, G2A summary]. The 8-minute round [V, Dev update #2] means nobody gets to pause.
2. **Everyone can fight.** Anyone can pick up guns, knives, screwdrivers, fish or mugs, and stamina doubles as health [V, patch notes 0.1.13 to 0.15.0; S, VICE]. Dissidents "have no special abilities and the same physical capabilities as other players" [V, AUTOMATON].
3. **Tasks are physical item chains across the whole map.** Players fetch parts, carry them and fit them. There are colour-matched batteries for power and samples for Analysis. Some tasks need two players (the scanner). A wrong step can hurt: the pressure machine explodes [V: tutorial list, patch 0.1.13, VICE; P: the pressure guide in the Steam thread says a canister in the wrong slot "can kill a player"].
4. **Sabotage is logistics, not only murder.** Hiding cups, packages or the recipe stalls the timer, so a dissident can win as a pacifist [P, reviews 180318793 and 207275782; V, 0.2.0 fixed "players could intentionally die on the table to hide the recipe"].
5. **Lots of small social signals.** Pointing, hands up, winking and eye-closing, cassette music as a lure or a noise cover, alarms you can disable [V, patches 0.1.13, 0.5.0, 0.6.0; S, VICE on the cassette lure].
6. **Shared, physical randomness.** Items, weapon and card spawns, which card room opens, and random spawns, all host-tunable [V, many patches]. In 2024 and 2025 Among Us was a 2D game with meetings and voting, while its official 3D version is a separate game [P, review 174816459].

## 9. Lessons for a small team [A unless marked]

1. **Creators, not press, sell this genre.** Every big wave matches a creator upload (§2), and the international ones are as big as the English ones. The cheap things that helped: copyright-safe music for streamers [V, 0.1.13], a lobby that is fun before the match, and moments that make clips.
2. **A launch spike decays fast whatever you do.** Peak to 10% took about 6 months. 1.0 did not bring a second spike, because it had no new content (§6).
3. **Never promise maps or modes in public.** The April 2025 roadmap named five modes. Not shipping them turned "finished small game" into "abandoned game" in the reviews [V/P, §4 and §7].
4. **Do not charge for cosmetics before the content is there, and keep body types free.** The DLC month has the worst review dip of 2024 and the most-voted negative reviews [V, RH; P, RV].
5. **Test balance changes before a sale.** The developers said this themselves in 0.2.2 [V]. Reverting within three days and running a survey kept it from getting worse.
6. **A rush for loot at match start beats any task loop.** Locking loot behind a slow minigame only moved the rush and wasted time [V/P, §2].
7. **When one person rebuilds the codebase, nothing ships.** A three-month silence during the fastest decline [V, Dev updates #2 and #3]. Modular code from day one is worth it. For us, invariants 3 and 4 already point that way.
8. **Settings and presets are cheap content.** LP's long-tail updates were mostly session settings (weapons, cards, alarms, defibrillators, battery speed, presets) [V]. Players kept praising them [A].
9. **Hosts have to moderate public lobbies.** Kick, ban, ban by Steam ID, report and a modded-lobby flag all came reactively, over two years [V]. Plan them early.
10. **Even a "complete" map earns its players' trust only if it changes.** Card rooms ("only one of the 3 rooms can be opened per match") were LP's answer to "same map forever", but players did not count them as new content [V, 0.9.0; P, review 235322429].

## 10. Checking the engineer's memories (from these sources only)

| Memory | What the sources say |
|---|---|
| **Vents** | Confirmed: the vents task uses screws and a screwdriver [V, 0.1.19 and 0.1.16]. A vent flashes red when broken and glows blue when working, and the tablet shows how many remain [S, a guide summary at <https://xboxplay.games/lockdown-protocol/how-to-fix-lockdown-protocol-the-vents-58826>]. Colour-blind players asked for "an X in the light bar to indicate it's dirty" [P, review 182473562]. Not verified here: cleaning at a station and putting the vent back where it came from. Other reports in this round should check it. |
| **Power** | Confirmed: the task was first "Alimentation(s)" and renamed "Power" in 0.4.0 "for clarity" [V]. It uses batteries ("Alim Box: Sound when the Battery is drained") [V, 2024-07-22]. Players asked for symbols on "the batteries for the various colors", which supports colour-matched parts [P, review 182473562]. A guide splits it into "Alimentations (Finding)" and "(Doing)" [V, video description]. |
| **Pressure** | Confirmed that it is hard and that it explodes: "a cooldown when the pressure machine explode" and "blinking lights" as the intended aid [V, 0.1.13]. Its tutorial has 3 to 6 times the views of the others [V]. A player guide says a wrong canister "can kill a player" and advises staying against the wall [P]. **Not confirmed: that a mistake kills *everyone*.** Every source I found says it hurts the players nearby. |
| **Dissidents, weapons for everyone, defibrillator** | All confirmed: the store text says "dissidents", weapons can be picked up by anyone and can be switched off, and the defibrillator came in 0.7.0 [V]. |

## 11. What makes it work

- Social deduction in real time with no meeting pause, played through high-quality spatial voice. The talk happens inside the action [V/P, §7 and §8].
- Physical tasks that are hard enough for veterans to teach newcomers. That makes "learning from friends" part of the fun, and it creates moments that make good clips (the pressure explosion) [P/A].
- A dissident who can win many ways: by killing, by hiding items or by bungling tasks, without special powers. So bluffing comes from what players do, not from what the rules give them [V/P].
- Combat for everyone, with stamina management, so a fight back is always possible [P].
- A cheap price ($9.99), a strong art style and a map tuned for 5 to 8 players, built and playtested "as a whole… until it was fun" [V, Dev update #2].

## 12. What players complain about

Monetization in early access. Abandonment and the scrapped modes and maps. Cheaters and modders. Toxic public lobbies. The rush for guns. Obscure, random tasks taught only by silent videos. Long waits after death. Gun-holders dominating. Thin dissident play once a dissident is outed. Colour-only coding. Heavy-handed Discord moderation (§7).

## 13. Mechanic → lesson → an original direction for our party

These are **proposals for the engineer, not decided**. GDD §1 and `docs/design/m8-match.md` (on origin/main) are the decided rules. The current branch does not have that file; I read it with `git show origin/main:docs/design/m8-match.md`.

| Mechanic in LOCKDOWN Protocol | What it teaches us | Proposal for our alien party |
|---|---|---|
| Guns on the field, then code crates, then 50/50 (0.2.0 to 0.3.0) | An opening rush for loot replaces the task loop. Gating loot with a slow minigame just wastes time. | Keep m8 §7's "ranged weapons for points": nothing worth rushing exists at the start. Comic party props everywhere act as weak melee, so the first minute is about tasks and chasing. |
| Pressure machine: a hard sequence, explodes, cooldown, light hints | One feared, lethal station becomes a legend players teach each other, and it doubles as a sabotage trap. | One "party hazard" station per map, for example an alien cocktail or slime machine. A wrong order sets off a comic blast that knocks down everyone in the room. Our 30 s respawn keeps it cheap (GDD §1, "a mistake costs a short time"). The state is shown on the station itself, so a human can "help" badly. |
| Vents: find the broken ones, unscrew, fix, return | A trip with a return leg tests memory and makes the map matter, and forgetting the origin is funny. | "Borrowed for the party": items lent by the neighbours must go back to *their* slot, which fits the neighbours' anger in m8 §5. Origin slots are open knowledge (GDD pillar "Open knowledge"). Only where an item lies now must be found by looking. |
| Colour-matched batteries (Power) | Colour-only coding excludes colour-blind players (review 182473562). | Our Generator and Cooking parts use **colour plus shape plus an icon** from the start, so colour is never the only cue. |
| Hiding cups, packages or the recipe to stall the clock (the pacifist dissident) | Sabotage by logistics is the dissident's deepest play and needs no lying. | Already ours (hiding delivery items). Extend it: humans can *swap* party supplies for convincing fakes, such as a cake that is "for the neighbours" but is really a stink bomb. Fakes are rules data (invariant 4). |
| Card-locked rooms, only one opens per match ("choose wisely") | A change in layout per match without a new map. | A "VIP room" key bought with points. Only one of the House's special rooms can open per match, and which one changes the round, for example a karaoke room that is loud on voice or a roof for the fireworks finale. |
| Fused alarms per sector that any player can disable | A global information tool with a counter is good social tension. | A party megaphone or DJ booth that sends one player's voice to everyone for 10 s, routed in `core/` (invariant 6). Humans can steal its battery. |
| Defibrillator: revives or deals heavy damage | Dual-use items create bluffs ("I was trying to save him"). | Respawn already covers death. A dual-use "party balloon pump" can inflate a downed friend back up early, or pop a standing one. Proposal only. |
| Wink and eye-closing, finger pointing | Cheap, nonverbal body language is something players invent uses for. | Alien gestures for the lobby and the match: antenna wiggles, colour flushes. They fit "fun from the first second". |
| Ghosts with nothing to do; 5 of 10 minutes spent dead | Waiting kills fun (review 178810365). | This confirms our 30 s respawn and capsules (m8 §3). Keep spectating short and give a dead player one tiny comic power, such as moving a single light object. |
| Difficulty presets (Training, Beginner, Normal, Custom) and saved session presets | Newcomers do not know which settings to change, so presets are content too. | Host presets named after party types ("chill house party", "full rave") that bundle the number of humans, weapons and the anger threshold (m8 §2, §5, §7). |
| NCS music "fine for content creators" | Creators spread this genre, and copyrighted music blocks them. | Every track in our party is original or cleared, plus a "stream-safe" switch. A party game cannot afford one copyright strike. |
| A promised 16-player map and five modes, never shipped | Public promises become the reviews. | Announce only what is built. Modes come from the mode-data design (ADR on game modes), shipped quietly. |
| Paid cosmetics in early access, body type at $9.99 | The single most-voted complaint. | Body types and basic faces are always free. Paid cosmetics, if ever, come only after real content. This is the humans' call, not an agent's. |
| Modded-lobby flag, kick, ban by ID, report | Public lobbies need tools for the host from day one. | Host-authoritative design already helps. Ship kick, ban-by-ID and a "modded" or "custom rules" lobby tag in the first public build. |

## 14. Open questions

1. **The original "recent announcement".** I could not read the developer statement quoted in review 207275782 ("even the first milestone was reached with some difficulty"). It was probably on Discord. I also could not read the Kickstarter page and its stretch goals (HTTP 403).
2. **Early patch notes.** Notes for 0.1.0 to 0.1.8 are not in the news feed. The first-day task list and its tuning are unknown.
3. **Reddit and wikis.** Reddit refused both JSON and HTML. I did not reach a Fandom or other wiki. Player opinion here comes from Steam reviews, Steam discussions and YouTube.
4. **Real sales.** All figures are third-party estimates (764K units per Raijin, 1 to 2M owners per SteamSpy). There is no developer figure.
5. **Pressure.** Does a pressure mistake kill only the players nearby or everyone? Patch notes say "explode", and a player guide says "can kill a player". A video check would settle it.
6. **Vents.** Is there a cleaning station and a return-to-origin rule? This needs the vents tutorial video (<https://www.youtube.com/watch?v=EtqwHdDhB4A>) watched or transcribed.
7. **What the engineer wants from LP.** Which part of its reception should we copy, if any? Its "hard, lethal, learn it together" tasks fit "macro skill" but pull against "never boring" for a newcomer. A decision for the engineer.
8. **The "Investigation", "Race", "Chase" and "Sabotage" modes.** Only their names exist. It is unknown what they would have been, and they must not be copied in any case.