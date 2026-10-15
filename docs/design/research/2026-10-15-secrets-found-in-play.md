# Secrets players find by playing, in multiplayer: hidden doors, unlockable shortcuts, how fast they leak, and how to keep them alongside "open knowledge"

Research for the estate party map (the engineer's direction of 2026-10-15). This is research, not a decision. Nothing here is a rule until the engineer chooses it.

## 0. Method, confidence, and what this builds on

- **Tags.** [V] means I read it at the source myself. [S] means I saw it only in a search-result summary. [P] is a player or critic opinion. [A] is my own analysis. Every number for our game is a placeholder.
- **Volume.** I ran about 50 web searches and fetches. Several sources refused the fetch: Dot Esports, VGC, Checkpoint Gaming and Stevivor returned 403, Sports Illustrated returned 410, and Sportskeeda returned 405. Claims from those sources are [S].
- **The repo, read first.**
  - `docs/design/m8-match.md` (whole file) and `docs/GDD.md` §1, lines 23-56. "Open knowledge" is at line 54: *"The rules, how every mechanic works and the fixed places (the map, the task circles, the zones where items may appear) are known to everyone."*
  - `docs/design/research/README.md`.
  - `2026-10-15-scattered-points-cameras-secrets.md` §3, §4.4 and its options (lines 124-269).
  - `2026-10-15-suburban-block-maps.md`.
  - `2026-10-15-lp-map-voice-settings.md` and `2026-10-15-lp-rules.md` §14 (card rooms).
  - `2026-10-15-spacious-house-level.md`. Its open question 5 (line 301) asks: *"Is the alien hidden layer open knowledge from match one, or something players discover?"* This report answers it in §5.
- **No dacha report exists.** The task names one. I searched `docs/` and every branch's commit messages (`grep -ril dacha docs/`; `git log --all --grep=dacha`) and found nothing. I built on the block and LOCKDOWN Protocol (LP) reports instead.
- **Not repeated here:** the earlier reports' Overwatch pianos, Tarkov secret exits, Hitman's Sapienza bells, the Dark Souls one-way door, TTT's role-only objects and the LP card-room facts. They are cited, not re-researched.

---

## 1. How multiplayer games handle secrets: six families

### 1.1 Public routes that only some players may use (vents, traitor rooms)

- **Among Us vents.** The vents' places are fixed, and only Impostors can travel through them.
  - [V] The 2021.6.30 patch added a Clean Vent task. Cleaning "will prevent any impostors from using that specific vent". If an Impostor is inside when cleaning starts, it "'ll boot them out with a dramatic sound" and "you'll see who it is" ([Innersloth patch notes](https://innersloth.itch.io/among-us/devlog/268531/vent-cleaning-version-2021630-patch-notes)).
  - [S] The 2021.11.09 roles update added the crewmate Engineer, who can vent for 5 s by default and then waits on a cooldown ([TouchArcade](https://toucharcade.com/2021/11/10/among-us-roles-cosmicubes-update-guardian-angel-shapeshifter-engineer-scientist-paid-free-account-linking-ios-android-switch-ps5-xbox-steam/)).
  - [A] Among Us turned the vent network from "the Impostor's secret" into "a public place with a state". A crewmate task changes that state and catches whoever is inside.
- **Trouble in Terrorist Town's traitor buttons.** [V] The official mapping guide says a traitor button "is shown only on the HUD of traitors". It "can also not be used as an improvised traitor testing device where innocents tell a player to press the button to see if a door opens" ([TTT mapping guide](https://www.troubleinterroristtown.com/development/mapping/)). [S] Traitor-room doors are commonly wired to cost 1 credit ([Valve wiki](https://developer.valvesoftware.com/wiki/Trouble_in_Terrorist_Town_Mapping)).
  - [A] This is the strongest reason role-limited passages are dangerous. A designer had to make the object invisible to stop it from becoming a lie detector. Our roles are mechanically identical (m8 §2), so this risk only returns if a secret ever favours one side by rule.

### 1.2 Fixed, open geometry where knowledge is the skill (Rainbow Six Siege)

- [V] Ubisoft's dev blog (16 Sep 2019) says Siege has "an expanse of game knowledge that can and should be learned". It says entering casual PvP as a first experience "is daunting". Its answer was a Newcomer playlist with "only three bomb-only maps, and a maximum Clearance Level of 50". It also admits that "the Clearance Level cap prevents new players from playing with their friends" ([Ubisoft](https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/5yrVt7VZcpCW983dqFoMs6/dev-blog-playlist-improvements)).
- [S] In October 2025, the Siege X director called map knowledge "the hardest thing… most people run into" because of destructible walls and verticality, and called the learning curve "very aggressive" ([Checkpoint Gaming](https://checkpointgaming.net/features/2025/10/rainbow-six-siege-x-director-joshua-mills-talks-difficulty-and-future-plans/)).
- [A] Siege has no hidden doors. Every hatch and soft wall is public, but players make openings during the round. The result is still a large gap between veterans and newcomers. Public geometry does not end the gap; it moves it into experience. The repair (a separate newcomer space) is the thing a friends-only party game cannot do.

### 1.3 Fixed secrets found once (easter eggs, hidden rooms)

- **Overwatch.** [S] The Eichenwalde bonfire was reported by test-server players on 23 Aug 2016 ([Gamereactor](https://www.gamereactor.eu/?p=33598)). The test realm had opened on 17 Aug ([Blizzard](https://overwatch.blizzard.com/en-us/blog/20243886)). So it was found within about 6 days and before the map went live. It does nothing in play.
- **Call of Duty: Warzone.** [V] Warzone launched on 10 Mar 2020. By 12 Mar, Kotaku reported players "already discovering" bunkers with keypads that answered "access denied", phones with dial tones and laptops asking for passwords, posted on r/CODWarzone ([Kotaku](https://kotaku.com/secret-bunkers-and-mysterious-telephones-are-puzzling-w-1842299929)).
  - [S] On the 2025 Verdansk there are 12 bunkers. Four open with fixed codes. Bunkers 2 and 4-9 need red or blue access cards that drop randomly from crates ([Sportskeeda](https://www.sportskeeda.com/call-of-duty-game/all-verdansk-bunker-codes-warzone)).
- **Hunt: Showdown.** [S] DeSalle's Shrek-shack easter egg was found on the test servers in 2021 by a YouTuber ([PureXbox](https://www.purexbox.com/news/2021/07/random_hunt_showdowns_upcoming_map_includes_a_shrek-tacular_easter_egg)). I found no source for true secret passages inside Hunt compounds. [S] Hunt 1896's Mammon's Gulch (August 2024) has public mines "flush with accessibility, featuring loads of different entrances and shortcuts" ([Shacknews](https://www.shacknews.com/article/140977/hunt-showdown-1896-preview)). Its hidden routes are open but complicated, which is knowledge as skill again.
- **R.E.P.O. (2025, proximity-voice co-op).** [S] A secret storeroom sits above the shop's ceiling. Guides say one ceiling tile is "consistently" in a fixed spot. You get up by explosives, a float drone, or a teammate's lift, and it is reportedly reachable only from the second shop visit ([GamerBlurb](https://gamerblurb.com/articles/repo-secret-room-and-how-to-get-inside), [The Game Slayer](https://thegameslayer.com/guides/how-to-unlock-the-secret-shop-in-r-e-p-o)). [S] Players "messing around in the shop during downtime" found it by accident.
  - [A] That is the ideal discovery: play-driven, cooperative (one player lifts another), and comic.
- **Phasmophobia.** [S] The 13 Willow Street rework (21 Jul 2026) added "hiding spaces" and "hidden lore" ([Mynewsdesk press release](https://www.mynewsdesk.com/uk/swipe-right/pressreleases/phasmophobias-13-willow-street-rework-launches-alongside-major-quality-of-life-update-3458983)). I found no hidden room in Phasmophobia from 2025-2026.
- **Lethal Company.**
  - [S] Locked doors take a random key from the scrap, used up after one use. A ship terminal opens the facility's secure doors by a code ([Dot Esports](https://dotesports.com/indies/news/how-to-open-doors-with-the-terminal-in-lethal-company)).
  - [S] Its yellow "backrooms" room comes from the layout generator. Players built a myth that it predicts a monster, and others rebutted it ([Steam thread](https://steamcommunity.com/app/1966720/discussions/0/4032472803480552480)).

### 1.4 A public place and a random key: the most common modern pattern

- **LOCKDOWN Protocol** (repo, `lp-rules.md` §14, [V] there). One access card at random opens one of several card rooms ("choose wisely"). Later there were 2 cards, and a host setting puts each room in a locked, closed or open state.
  - [V] Today it has 82% positive of 9,505 English reviews, and 75% of 134 in the last 30 days. It released on 18 Nov 2025 ([Steam](https://store.steampowered.com/app/2780980/LOCKDOWN_Protocol/)).
- **Fortnite's Skeleton Key** (Fortnitemares, update 42.30, October 2026). [V] There are two Skeleton Keys per match. They are buried in 2 of 3 graveyard mausoleums. The secret room is a mansion basement with 3 doors, each key opens one door, and the loot behind each door "is randomized in every match" ([Beebom](https://beebom.com/fortnite-skeleton-key-secret-room-location/)).
  - [A] Look at the arithmetic. 2 keys for 3 doors guarantees that at least one door stays closed, so even the finder never sees everything, and the "best" door changes every match. The room itself is public knowledge on day one, but the experience of it is not.
  - [S] Earlier Fortnite vaults (Chapter 5) opened with keycards or medallions from bosses. One guide says a held medallion shows the holder's area on the map ([Gfinity](https://www.gfinityesports.com/article/how-to-open-vault-in-fortnite)). That is the carried key as a visible target.
- **ARC Raiders (launched 30 Oct 2025).** [S] Keys are single-use and drop randomly from containers, and about 20 keys open rooms across the maps. Guides map every room and key ([Nerdschalk](https://nerdschalk.com/all-keys-in-arc-raiders-and-what-they-unlock/), [Prima](https://primagames.com/tips/all-locked-rooms-and-keys-in-dam-battlegrounds-map-arc-raiders)).
- **Apex Legends (Season 3, 2019).** [S] Rare keys open 3 vaults. Only the holder sees the vault markers, and there can be more keys than vaults ([Shacknews](https://www.shacknews.com/article/114417/how-to-get-vault-keys-in-apex-legends), [Kotaku](https://kotaku.com/apex-legends-vaults-are-finally-open-1838906856)).
- **Dead by Daylight's hatch.**
  - [V] Since patch 5.3.0, the hatch "only becomes visible, and automatically opens, when there is only a single Survivor left". Before that, it appeared when completed generators equalled living survivors plus 1.
  - [V] Its spot is random, "pre-determined by the Map Generator", and "can also be tracked via an audio cue when one is close-by". A key opens a closed hatch in 2.5 s. A killer closing it starts the Endgame Collapse ([DBD wiki.gg](https://deadbydaylight.wiki.gg/wiki/Hatch)).
  - [A] This is the purest "unlocked in the match" secret. Its existence and rules are public, the spot is drawn, the opening condition is in-match, and the tell is a sound.
- **Deceive Inc. (2023).** [V] One of its maps, a villain's mansion, was "retrofitted… with loads of corridors and secret passageways to discover" ([Xbox Wire](https://news.xbox.com/en-us/2023/03/21/deceive-inc-a-guide/)). [S] A preview recalls a winning team that fired no shot, thanks to distractions and "secret passages hidden in the level" ([GameSkinny](https://www.gameskinny.com/d03j6/deceive-inc-hands-on-preview-shaken-not-stirred)).
  - [A] This is the closest genre neighbour: a mansion, disguises, and secret passages as a stealth route. They are fixed, so they are learned.

### 1.5 Multi-step quests and community puzzles

- **Call of Duty zombies.** [S] Treyarch said Black Ops 7's Cursed mode would unlock for everyone once someone in the world finished the first map's main quest ([Gfinity](https://www.gfinityesports.com/article/treyarch-considering-a-super-easter-egg-for-black-ops-7-zombies-reveals-how-cursed-mode-will-be-unlocked)). That is a world-first race built into the game.
  - I found no verifiable first-completion time for any Black Ops 6 or 7 main quest. The searches returned only guides.
- **Destiny.**
  - [S] Destiny 2's secret Whisper mission was found on 20 Jul 2018. "After a few hours", completions came in, and it vanished on Monday ([Kotaku](https://kotaku.com/destiny-2-players-find-wild-secret-quest-with-a-famili-1827764465)).
  - [S] The puzzle-heavy Salvation's Edge raid fell in 18 h 57 min (June 2024), the longest such race ever ([The Game Post](https://thegamepost.com/destiny-2-the-final-shape-salvations-edge-world-first-raid-winner/)).
- **Sea of Thieves riddles.** [S] Each riddle has 2-4 lines. The first names the island, the middle lines name a landmark confirmed by an action there (play a shanty, raise a lantern), and the last gives a compass heading and paces ([Sea of Thieves wiki](https://seaofthieves.wiki.gg/wiki/Riddle_Map)). This is a ladder of partial hints written into the world.
- **Animal Well (2024).** [S] Its designer expected some puzzles to take years. [P] A Steam post of 12 May 2024 claims the hardest were solved in "a week or so", with some brute force ([Steam](https://steamcommunity.com/app/813230/discussions/0/4365754575397988203)).
- **GTA V's Mount Chiliad.** [S] It has stayed unsolved since 2013. In November 2024 a former Rockstar developer said it was Rockstar having fun, and that such eggs "don't actually do anything" ([GTABoom](https://www.gtaboom.com/ex-gta-developer-reveals-truth-behind-decade-long-gta-5-prank-7c34), [Gameranx](https://gameranx.com/updates/id/516140/article/grand-theft-auto-v-mount-chiliad-mystery-was-reportedly-just-to-mess-with-people/)).
  - [A] The longest-lived "secret" in the set is the one with possibly nothing at the end.
  - [V] TUNIC's GDC 2023 session made the same point from the designer's side: "the joy of resolving them is not always better than the joy of having lots of tantalizing mysteries" (Andrew Shouldice, [GDC](https://gdconf.com/news/unlock-secrets-tunic-gdc-2023-design-session)).

### 1.6 Layouts that change per match, and hide-and-seek

- **Secret Neighbor.** [V] Its developers found that players "after 4-5 matches figure out the optimal route for scavenging through the house". Their first fix was to "add randomized walls in the house" ([Xbox Wire](https://news.xbox.com/en-us/2019/10/24/social-horror-secret-neighbor-available-today-xbox-game-pass/)). **Four or five matches is the half-life of a fixed route** in a small social game.
- **Phasmophobia.** [S] Each contract spawns one randomly chosen cursed possession, but each item has a fixed spot per map ([Destructoid](https://www.destructoid.com/all-cursed-object-spawn-locations-in-phasmophobia/), [Ginx](https://www.ginx.tv/en/point-hope-lighthouse-cursed-possession-locations)). Which item appears is random; where it appears is learnable.
- **Hunt: Showdown's clues.** [S] Every compound holds at least one clue, at a random spot inside it. Each clue greys out part of the map, and the third circles the boss. A roaming boss on Mammon's Gulch has no clues: you track its screams ([Hunt wiki](https://huntshowdown.fandom.com/wiki/Maps), [Shacknews](https://shacknews.com/article/141000/find-hellborn-hunt-showdown-1896)).
- **Hitman.** [S] Its developers describe the Opportunities and Mission Stories hints as onboarding for newer players before veterans "branch off". The Freelancer mode removes them and even warns there is "no guarantee that an objective is possible" ([SI](https://videogames.si.com/features/hitman-freelancer-interview), [IOI](https://ioi.dk/hitman-freelancer-you-are-in-control)).
- **Prop Hunt.**
  - [S] A Garry's Mod Prop Hunt map's changelog repeatedly fixes a "hiding exploit" and "areas that some hunters couldn't reach" ([Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/changelog/237152021)).
  - LOCKDOWN Protocol likewise curated its hiding spots and walled off unreachable ones (repo, `lp-rules.md:216`, [V] there).
  - [A] In hide-and-seek games, a hiding spot the seeker cannot learn or reach counts as a bug, not a secret.

---

## 2. How fast communities find and publish

| Secret | Found / solved | Source |
|---|---|---|
| Overwatch bonfire | about 6 days, on the test server, before launch | [S] Gamereactor, Blizzard |
| Warzone bunkers | 2 days after launch, on Reddit | [V] Kotaku |
| Hunt's DeSalle easter egg | on test servers, by a YouTuber | [S] PureXbox |
| Destiny 2's Whisper | completions "after a few hours" | [S] Kotaku |
| Salvation's Edge (puzzle raid) | 18 h 57 min | [S] The Game Post |
| Animal Well's deepest layer | "a week or so" (one forum claim) | [P] Steam |
| Secret Neighbor's best route | 4-5 matches per player group | [V] Xbox Wire |
| Mount Chiliad | not solved since 2013 | [S] GTABoom |

- **Before launch: data mining and leaks.**
  - [V] Critical Points writes that slowly released secrets give players "a reason to return for years". It says data mining now threatens this, so designers must hide the information more carefully ([Critical Points](https://critpoints.net/2017/01/09/making-a-good-video-game-secret/)).
  - [S] In 2026, reporting alleged that an Epic insider passed Fortnite's file-decryption key to a well-known leaker ([Sportskeeda](https://www.sportskeeda.com/esports/epic-games-reportedly-cracks-fortnite-leaks)). Even a studio that encrypts its files can't keep a fixed secret.
- **Spread** runs through test servers, Reddit and YouTube. The 2025-2026 guides (ARC Raiders, Fortnite, R.E.P.O.) published every key room within days. [A] The useful frame is: **a fixed secret has one surprise, for the first finder, and then it becomes a wiki entry.** In a hobby game with a small player base, the "wiki" is the host friend who read the patch notes. The gap is between friends, not strangers.
- **Our architecture changes the maths** [A].
  - Invariant 4 (mechanics are data) means every content Resource ships in the export. A fixed secret's place and trigger should be assumed readable.
  - Invariants 1 and 2 (host-authoritative, per-peer filtering) mean a secret **drawn by the host each match** never reaches a client until that client is entitled to it. Data mining yields the candidate list (which open knowledge publishes anyway), never this match's answer.
  - The host machine itself could be inspected, but CLAUDE.md says this hobby project guards against accidents, not attackers. That is acceptable.

---

## 3. The fairness problem

1. **Knowledge gaps come in four layers** [A], and each needs a different fix:
   - (a) *existence*: there is a hidden door;
   - (b) *place*: it is in the library;
   - (c) *trigger*: pull the third book;
   - (d) *state*: it is the active one this match.

   The open-knowledge pillar already covers (a) and (b) as "fixed places". Draws are what keep (c) and (d) fresh.
2. **Public geometry alone does not close the gap.** Siege publishes everything and still needed a newcomer space [V]. Hunt's mines are public but "knotted" [S]. A pleasantly confusing estate creates its own gap even with no hidden doors [A].
3. **In a group of friends, the gap goes to the host** [A]. He reads the patch notes and plays most. A fixed bookcase door turns into "the host's trick". In a 10-minute match with a 30 s respawn (m8 §3), a 4 s shortcut that only he uses is a large edge, and it is also boring for the others: "I didn't know, so I lost the chase."
4. **The side that talks wins** (m8 §6b) [A]. A discovered secret is information, and information spreads by voice. The aliens are the larger, talking side, so any secret that pays more when shared widens the edge the balance model already found against the humans.
   - The fix: **favour secrets whose value is privacy**. A hiding place, a listening spot or a quiet route is worth most while few people use it. That naturally favours the minority, with no role-limited object (and so no TTT test).
5. **Lying and manipulation.** GDD §1 says roles are played "through actions, not through manipulation or lying". Secrets invite fake tips ("the bookcase opens if you stand on the rug"). That is cringe comedy, but it pulls toward Lockdown Protocol's lying. *Flag for the engineer.*
6. **Disorientation and dead ends.** The spacious-house report found that long hidden passages were the top cause of lost players (`spacious-house-level.md:121, 258`). A pleasantly confusing estate plus secret passages doubles that risk. Short hops between two known rooms are the safe form.
7. **Art cost against discovery rate.** The repo's risk 8 (`scattered-points-cameras-secrets.md:222`): secrets cost art time and are rarely found in 10 minutes. A drawn secret is rarer per match than a fixed one, which makes this worse unless the tell is strong.

---

## 4. Designs that keep surprise alive

1. **A pool drawn per match.** Examples: Secret Neighbor's walls [V], Phasmophobia's one possession [S], Fortnite's 2 keys in 3 mausoleums [V], LP's random card [V]. The usual band is 1 active in 2-4 candidates (repo pattern 1).
   - *Strength:* it beats both the wiki and data mining under our host draw.
   - *Weakness:* candidates multiply the props, and a careless draw varies the difficulty (repo risk 4).
2. **Unlocked during the match.** Examples: the DBD hatch condition [V], LP's card choice [V], Warzone's random access cards [S], Among Us vent cleaning flipping a vent's state [V], Dark Souls' one-way doors (repo).
   - *Strength:* surprise lies in *when* and *who*, which a wiki cannot spoil.
   - *Weakness:* the unlock must not depend on a long search, or it fights "never boring".
3. **Partial hints.** Examples: Hunt's greying clues [S], Sea of Thieves' riddle ladder [S], Hitman's hints as onboarding that veterans switch off [S], and the "secret language" of consistent tells (slightly inset fake walls) [V, Critical Points]. Critical Points' bar: "people shouldn't get it on their first try, but they should always be able to get it" [V].
   - *Strength:* a newcomer who reads the world beats a veteran who doesn't.
   - *Weakness:* hints are content text, and written content belongs to the content area.
4. **Rare secrets.** Examples: the Whisper mission that vanished after a weekend [S], and Lethal Company's room as a rumour machine [S]. m8 §1's far-future shovel that digs up alien skeletons already belongs here.
   - *Strength:* rumours outlive solutions (Chiliad), and they make clips.
   - *Weakness:* below a few percent per match, most players never see it; it must never carry power.
5. **Staged reveals.** Examples: Warzone's sealed bunkers opened later [S], Black Ops 7's world-first unlock for everyone [S], and LP's map that "grew inward" by patches (repo [V]). For a hobby game, one new fixed secret per release, with its *existence* announced, is cheap and keeps old players looking.
6. **Secrets without power.** Examples: the Overwatch bonfire [S] and Mount Chiliad [S]. They cannot hurt fairness at all.

---

## 5. Open knowledge and secrets together: a proposed reading [A]

The pillar lists what is public: rules, mechanics, "the map, the task circles, the zones where items may appear", and "where a moved item lies now is not shown". It already separates **places (public)** from **states (found by looking)**. That separation is the reconciliation:

> **Every fixed place is public; every secret is a drawn state or trigger of a public place.**

- **Tier 1, open.** The estate *has* servants' corridors, bookcase doors and a maze. Their candidate endpoints are on the map, or at least named in the tutorial and lobby: "this estate hides 6 passages; 2 are unlocked tonight". Nothing about *existence* is withheld. This answers the spacious-house report's question 5: the hidden layer is open knowledge from match one.
- **Tier 2, drawn per match, learned only by play.**
  - Which candidates are active.
  - Which book, portrait or statue is the lever tonight.
  - Which grille is unblocked.
  - What waits behind a door.

  A veteran knows the candidate list, which everyone can know. Nobody knows tonight's answer. The host draws, and only entitled peers receive it.
- **Tier 3, rare and powerless.** Comic, cosmetic, clip-making moments (an alien lord's portrait drops its monocle when you pass). Kept out of balance.
- **Teach one "secret language" for the whole estate.** For example: a draught you hear within 2-3 m (proximity audio), and an alien portrait whose eyes track the lever. A newcomer who has seen one secret can read the rest. That turns a knowledge gap into an attention skill, which the "macro skill first" pillar welcomes.
- **Let discovery spread in-match.** An opened passage stays open and visibly ajar, like the repo's shortcuts at `scattered-points-cameras-secrets.md:194`. Its mechanism sounds through walls under the muffling rule (m8 §8). A newcomer learns from the veteran *during* the match, not from a wiki.
- **One flag.** A *fixed, unlisted* secret door strictly violates the pillar as written, because it is a fixed place not known to everyone. Before any such door exists, the engineer should either accept that or amend the pillar ("fixed places are public; their states, triggers and rare surprises are not").

---

## 6. Mapping it to the estate [A]

All numbers are placeholders. Walking is 4.5 m/s, sprinting 7 m/s for 5 s and then about 5.6 m/s, voice reaches 8 m, walls muffle.

- **Servants' corridors** behind the library, the dining room and the ballroom: short hops of 8-15 m between two known rooms (2-3 s walking, about 1.5-2 s sprinting), never a loop around the walls (§3, item 6).
  - Their mechanic is **listening**. A corridor runs 1-2 m from the room, inside voice range, and it hears the room *muffled*. A drawn subset of serving hatches or grilles hears it *clearly*.
  - That is a tool against the talking side (m8 §6b: "the humans need tools against the aliens' talk") that anyone may use (roles identical, no test). Its value is privacy (§3, item 4).
  - Voice routing is game logic in `core/` (invariant 6), so this is engine work, not level dressing.
- **The library's bookcase door.** It opens from the library side only after its drawn lever (one of a few books or busts) is pulled. From the corridor side it always opens. That is a one-way chase-breaker against equal speeds (the repo's loop risk 1).
  - [V] There is a real precedent for the alien touch. Owen-style priest holes were reached by "tilting a step on the grand staircase", through panelling and "a false fireplace", and searchers "rarely found an occupied hide without an informant's help" ([Wikipedia](https://en.wikipedia.org/wiki/Priest_hole)). [S] Some of Owen's hides nested inside decoy hides ([Wikipedia: Nicholas Owen](https://en.wikipedia.org/wiki/Nicholas_Owen_(Jesuit))).
  - [S] Oxburgh Hall's bookcase door has painted fake spines with joke titles ([Bite Sized Britain](https://www.bitesizedbritain.co.uk/oxburgh-hall-in-norfolk---a-stately-home-with-a-couple111/)). Fake spines are a natural place for alien jokes. Any titles are content, the engineer's word.
- **The hedge maze.** Its walls are fixed and public. A drawn gap or two per match (Secret Neighbor's lesson [V], inverted: opened, not closed) keeps it pleasantly confusing without being memorised in 4-5 matches.
- **Orangery, dark room, pool pavilion, carriage house, summer kitchen, gates.** Each needs a mechanic, and a secret is one way to give it one. For example: an alien plant that blooms only when the anger meter crosses a threshold and reveals a crawl tunnel (an in-match unlock, DBD-style, announced to all). The carriage house holds the drawn hiding place for the fireworks, the "known kind, unknown place" source of m8 §5.
- **Capsules.** Keep every secret endpoint more than 12 m from capsules (the repo's spacing rule). Then a respawn never lands someone at a shortcut, and shortcuts shorten returns to the far end of the map (the 30 s wait, m8 §3).

---

## 7. Patterns

1. **Public place, random access** is the dominant modern form: LP cards, Fortnite's Skeleton Key, ARC Raiders keys, Warzone cards, Apex vault keys, the DBD hatch. Pure fixed secrets survive only as powerless easter eggs.
2. **Fixed secrets leak in hours to days** (2 days, about 6 days, a few hours), often before launch. Fixed routes are learned in about 4-5 matches (Secret Neighbor [V]).
3. **Surprise lives in "this match", not "this map".** Per-match draws of state, trigger or contents (Fortnite's random doors [V], Phasmophobia's possession [S], Hunt's clue spots [S]) keep a known room fresh.
4. **Fewer keys than doors forces a choice.** LP's "choose wisely" [V] and Fortnite's 2 for 3 [V].
5. **The tell is diegetic and consistent.** Sound near the hatch [V], a "secret language" [V], a riddle ladder [S].
6. **Role-limited secrets become tests unless invisible** (TTT [V]). Public objects with a changeable state avoid this (Among Us vent cleaning [V]).
7. **Unreachable or unlearnable hiding spots are bugs** in hide-and-seek games (Prop Hunt changelog [S], LP [V]).
8. **Rumour outlives reward.** Chiliad [S], Lethal Company's room [S], TUNIC's "tantalizing mysteries" [V].
9. **Newcomer fixes in big games** (a separate playlist, fewer maps [V]) are unavailable to a friends' party game. Our fix must work inside the match.

## 8. Risks

1. **The host-veteran edge.** A fixed secret becomes the host's trick and a newcomer's boring loss, which is against "never boring".
2. **Pillar conflict.** A fixed, unlisted secret door breaks "open knowledge" as written (§5 flag).
3. **Secrets widen the talking side's edge** if they pay more when shared (§3, item 4).
4. **Disorientation.** Confusing estate plus hidden corridors means lost players. Keep hops short and the passages visually tied to rooms (repo).
5. **Drawn secrets are found less often.** Low discovery per match means art no one sees. It needs strong tells and a guaranteed minimum (always at least N active).
6. **Draw variance skews balance.** Two shortcuts beside one capsule this match, none the next. The draw needs constraints (one per wing; spacing) and the balance model (#1089).
7. **Fake tips push toward lying**, against the GDD's "actions, not lying".
8. **Engine weight.** Listening grilles touch voice routing (invariant 6). Per-match draws touch per-peer filtering (invariant 2). Neither is pure level work.
9. **Clip-only secrets with power become the meta** (repo risk 8; Tarkov). Keep rare ones powerless.

---

## 9. Original options for our game

All names and numbers are placeholders. Nothing is copied: references stay analysis, and content (names, numbers, texts) is the engineer's to set.

**A. "Known passages, drawn hinges"** (the backbone).
- **How:** each wing has 2-4 candidate secret doors (bookcases, panels, a fireplace back), shown on the map as possible passages. The host draws 1 active per wing per match, constrained by spacing and kept more than 12 m from capsules. One shared tell for the whole estate (a draught you hear within 2-3 m, a portrait's eyes). Once opened, a door stays open for everyone.
- *For:* it satisfies "open knowledge" as written (places public, state found by looking), defeats the wiki and data mining under the host draw, and is mostly data (invariant 4). It also answers the spacious-house report's question 5.
- *Against:* it multiplies the door props per wing and needs a constrained draw and a bot pass for variance.

**B. "Listening service" (servants' corridors that hear).**
- **How:** corridors run just behind the grand rooms. Inside them, room voice is muffled. A drawn subset of serving hatches lets you hear one room clearly, and anyone at a hatch can be seen from the room if they look.
- *For:* a mechanic for every corridor; a tool against the talking side that both sides may use; its value is privacy (it favours the minority with no role test); comic eavesdropping clips.
- *Against:* engine work in `core/` voice routing (invariant 6). It depends on walls muffling voice, which is not built yet (m8 §8).

**C. "The estate wakes up" (in-match unlocks for all).**
- **How:** one or two passages open only on a public condition, for example the anger meter's halfway mark or a set number of tasks done. The opening is announced to everyone, and its place is drawn from 2-3 public candidates (the orangery bloom, the maze centre gate).
- *For:* a midpoint beat for pacing (round 2's finding), surprise in *when* and *where* rather than *whether*, and fair to newcomers.
- *Against:* one more thing tied to the meter's tuning, and the condition must stay readable.

**D. "Fewer keys than doors" (the steward's ring).**
- **How:** one physical, visible ring of keys spawns at a drawn spot. It opens any 2 of 4 locked estate rooms (the wine cellar, the trophy room, and so on). Each room changes routes or noise, and the carrier is visible to all.
- *For:* a table argument ("which two?"), a target to chase, and the door contents can be drawn.
- *Against:* closest in structure to LP's cards and Fortnite's keys, so it needs its own twist (perhaps a key "remembers" who opened what and announces it on a board in the summer kitchen). It adds an item and an inventory slot.

**E. "Rumour pool" (rare, powerless, comic).**
- **How:** a small pool of very rare moments drawn per match. Examples: an alien lord's portrait drops its monocle as you pass; a bookcase that opens onto a closet with a sleeping butler. They give no advantage, and they sit outside the balance model, alongside the m8 shovel easter egg.
- *For:* clips and rumours; it cannot hurt fairness; it fills "alien touches everywhere".
- *Against:* art time for things most players never see; it needs a minimum rate so it is not effectively absent.

**F. "Read the house" (partial hints in the world).**
- **How:** each match, a plaque, a dinner place-card or a servant's note somewhere public gives a partial hint to one drawn passage ("behind the one who never blinks"). Hint strength is a host setting (none, wing, object), like the repo's hint ladder.
- *For:* a reader beats a veteran; it serves "the party is hard on its own" with honest mistakes; a lobby setting handles mixed groups.
- *Against:* written content is the content area (the engineer's word, never invented by agents), and hint texts need translation and testing.

**G. "One new secret per release" (staged reveal).**
- **How:** each update adds one fixed secret, and the patch notes announce its *existence* ("there is a new secret in the orangery"), not its place.
- *For:* cheap, keeps veterans exploring, follows LP's "grow inward" (repo [V]).
- *Against:* breaks "open knowledge" until it is found, and the gap returns once one friend finds it. A fixed secret has a short life (pattern 2).

**Recommendation [A].**
1. **A first, as the rule.** It is the only option that keeps both pillars intact, is mostly data, and turns our architecture (host draw, filtered) into a datamine-proof surprise.
2. **E early, as cheap garnish**, for the alien touches and clips.
3. **B as the experiment once walls muffle voice.** It is the most original and directly answers m8 §6b, but it is engine work.
4. **C if the first greybox lacks a midpoint.**
5. **F as a host setting later**, once the engineer writes texts.
6. **D only with a twist that is ours.**
7. **G not before the pillar's wording is settled** (§5 flag).

---

## 10. Open questions for the engineer

1. **The pillar:** do secrets live only as drawn *states* of public places (my reading), or may a fixed place stay unlisted? Should the GDD wording change?
2. **Power:** may a secret give an advantage (a faster route, eavesdropping), or must it be cosmetic and comic only? (This is also the repo's open question 11.)
3. **The answer to spacious-house question 5:** is the passage network open knowledge from match one, with only its active doors drawn?
4. **Listening corridors (B):** do you want the "humans' tool against talk" to be a place rather than an item, and should a hatch hear clearly or only less muffled?
5. **Hint strength:** none, wing or object, as a lobby setting (option F) or fixed?
6. **Rarity:** what share of matches should show a rare moment (option E): one in five, one in twenty?
7. **Fake tips:** are false "secret tips" over voice fine as cringe comedy, or against "actions, not lying"?
8. **Updates:** should new secrets arrive per release (G), and should their existence be announced?
9. **Constraints on the draw:** one active passage per wing? A minimum always active so the art is seen?

**Sources:** cited inline. The repo files read are listed in §0.