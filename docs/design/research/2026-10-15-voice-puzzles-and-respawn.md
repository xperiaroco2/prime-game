# Co-op voice mini-games and the respawn spectacle: research for the estate

Research report, 2026-10-15 (the estate round). This is research, not a decision. Every number in the options is a placeholder.

## 0. Scope, method, tags

**What it builds on.** I read `docs/design/m8-match.md`, `docs/GDD.md` §1 (pillars) and §8 Cooking, and the research index `docs/design/research/README.md`. From the reports it indexes I used three most:
- `2026-10-15-harder-tasks.md`, which has the unit rule "30–60 s with one thinking beat" (Option G) and the KTANE case.
- `2026-10-15-death-respawn.md`, which covers respawn systems and sabotageable capsules.
- `2026-10-15-lp-rules.md` §8.4, which covers LOCKDOWN Protocol's weapon crates.

**What is not in the repo.** The index has no "dacha" report. A `grep -ril dacha docs/` found nothing. I could not read one, so this report builds on the block, house and LOCKDOWN reports instead.

**What already exists.** The game already has one codebook mini-game:
- The kitchen's order board shows the herb as an icon, and "only the greenhouse's herb board decodes" it. "The icon-to-herb mapping is new each round" (`docs/GDD.md`:446-447).
- The five icons are told apart "by shape alone" (`docs/GDD.md`:505-509).
- The estate's orangery inherits this loop for free.

**Tags.**
- **[V]** I fetched the page and read the claim myself.
- **[S]** The claim comes from a search-result summary only; check it before relying on it.
- **[P]** Someone's opinion.
- **[A]** My analysis.

I ran 58 searches and fetches. Fandom, Barotrauma and Splatoon wikis refused the fetch (HTTP 402 or 403), so those facts are [S].

**A correction to round 3.** `harder-tasks.md` §2.3 says KTANE's "rules themselves, not only the bombs, are procedurally generated".
- Wikipedia says the bombs are generated procedurally, but the final game "has statically defined rules for defusing", with only "a framework" to vary them later [V, [Wikipedia](https://en.wikipedia.org/wiki/Keep_Talking_and_Nobody_Explodes)].
- Rules that change per bomb come from a community mod, "Rule Seed Modifier" [S, [Steam thread](https://steamcommunity.com/app/341800/discussions/0/2448217258989296329)].
- The lesson still holds for us: our herb code does change each round. But KTANE is evidence that a fixed rulebook with a random bomb is enough to stay fresh for years. It is not evidence for random rules.

---

## 1. Codebook tasks: one sees, the other reads

### 1.1 Keep Talking and Nobody Explodes (KTANE)

**Facts.**
- A bomb has "up to 11 modules". It explodes at 0:00 or on the third strike when it has a strike indicator, and on the first strike without one. "The timer will begin to count down faster after a strike" [V, [bombmanual.com](https://www.bombmanual.com/web/index.html)].
- Keypads: "Only one column below has all four of the symbols from the keypad". You press them "in the order their symbols appear from top to bottom within that column" [V, same].
- Morse: a light spells one of 16 words, each mapped to a frequency from 3.505 to 3.600 MHz [V, same].
- The communication friction is deliberate. Some modules use "unusual glyphs that require description" and some use "words that may be homophones" [V, [Wikipedia](https://en.wikipedia.org/wiki/Keep_Talking_and_Nobody_Explodes)].
- More than 200,000 copies sold by March 2016 [V, same]. Raijin's July 2026 estimate is about 275k on Steam alone [S, [Raijin](https://raijin.gg/app/341800/Keep_Talking_and_Nobody_Explodes)].
- Ben Kane's GDC 2016 talk frames the game as being about "communication between players", tuned "to keep players talking in ways that encourage tension, mistakes, and camaraderie" [S, [GDC Vault](https://gdcvault.com/play/1023113/Designing-Asymmetric-Gameplay-For-Keep)].

**For us [A].**
- **Time.** One keypad unit is roughly: describe four glyphs, find the right column, read the order back. That fits our 30–60 s unit.
- **Scaling.** KTANE scales by module count, by time, and by "needy" modules that keep coming back (all on the same manual page). It never scales by making one module longer. That matches "scale width, keep the unit" (harder-tasks Option G).
- **Deniable spoiling.** The reader can "misread". Because homophones and glyph descriptions produce honest errors, a human's wrong reading looks like a normal failure.
- **Learnability.** A dense manual where finding the right page is part of the puzzle works for a 5-minute bomb. It breaks "action over long discussions" in a 10-minute party, so a board must fit on one screen.

### 1.2 We Were Here: the communication test

**Facts.**
- The studio's puzzle rule: "every puzzle should be related in some way to communication". Their kinds include "describing symbols, guiding someone to navigate a maze, mimicking sounds, pronouncing silly words" [V, [Xbox Wire](https://news.xbox.com/en-us/?p=190237)].
- Their filter: "if it doesn't get you talking, whispering, laughing or yelling then it shouldn't be in our games" [V, same].
- On fairness: "if players get stuck it should be because they're not cooperating or communicating well" [V, same].
- On new players: "Any puzzle should be just as interesting to a series veteran as to a brand new player" [V, same].
- The players talk through a radio with separate send and receive buttons [S, [Punished Backlog](https://punishedbacklog.com/we-were-here-series-review-retrospective/)].

**For us [A].** "Pronouncing silly words" is the cheapest comedy an alien language gives us. A glyph whose name is fun to say aloud makes the relay itself the joke.

### 1.3 Lethal Company: the operator in a proximity-voice game

**Facts.**
- One teammate stays on the ship at the terminal. They read a radar and type short codes ("A1", "Z9") to open secure doors or to disable turrets and mines "for 5 seconds". The crew inside hears them by walkie-talkie [S, [Prima](https://primagames.com/tips/all-terminal-commands-in-lethal-company), [PCGamesN](https://www.pcgamesn.com/lethal-company/disable-turrets)].
- A guide calls the role a way to "either save or kill your teammates" [S, [Dot Esports](https://dotesports.com/indies/news/all-terminal-commands-in-lethal-company-and-what-they-do)].

**For us [A].**
- This is the closest analogue to our game: proximity voice, a remote reader, and a door code read under pressure.
- The operator can betray deniably: a slow code, a wrong code, a door locked "by accident".
- That suits our humans, but only if the reader's mistake has more than one plausible author (harder-tasks §3.5).

---

## 2. Invented languages as puzzles

### 2.1 Chants of Sennaar

**Facts.**
- The notebook lists the glyphs you have met. You type your own guess, which "is then displayed above that grapheme the next time".
- After enough sightings, a test page pairs drawings with glyphs. "If the player correctly matches all graphemes to meanings on the page, those graphemes will be considered solved" [V, [Wikipedia](https://en.wikipedia.org/wiki/Chants_of_Sennaar)].
- Released 5 September 2023, mobile on 26 August 2025 [V, same]. It passed 500,000 copies on PC and console by August 2025 [S, [Playdigious](https://playdigious.com/news/chants-of-sennaar-is-available-now-on-mobile)].
- The writing systems are logographic, one glyph per word, with no tenses or articles [S, [Oulu thesis](https://oulurepo.oulu.fi/handle/10024/55661)].
- The designers: "They were created as part of a game design process, not a linguistic one". The languages are "puzzle elements like any others" [V, [GoNintendo](https://www.gonintendo.com/contents/31644-chants-of-sennaar-devs-explain-how-the-game-s-fictional-languages-were-developed)].
- The typical clue: a pottery shop's sign "is probably pot" [S, [Elliot C Smith](https://www.elliotcsmith.com/page/9/)].

### 2.2 Heaven's Vault

**Facts.**
- The game never confirms a guess: "we won't tell you if you're right or wrong". Inkle expects players to be confident in "about a third" of the language by the end [V, [TheSixthAxis](https://www.thesixthaxis.com/2018/04/27/interview-talking-with-inkles-about-deciphering-ancient-language-in-heavens-vault/)].
- Each glyph group comes with a short list of English candidates, and context decides [S, [PCWorld](https://www.pcworld.com/article/403592/heavens-vault-review.html)].

### 2.3 Tunic

**Facts.**
- The glyphs make you feel "out of place". If they carried meaning, it would matter that they were "not a simple letter-for-letter cipher" [S, [Red Bull](https://www.redbull.com/int-en/tunic-video-game-developer-interview)].
- The mechanics hide in manual pages found "as treasures around the game world" [S, [Tales from the Backlog](https://talesfromthebacklog.fireside.fm/articles/tunic)].
- A player decoded the language from about ten pages [S, [3DJuegos](https://www.3djuegos.com/juegos/tunic/noticias/un-jugador-descifra-el-misterioso-lenguaje-de-tunic-y-ya-220403-121206)].

### 2.4 Plant identification: the orangery's cousins

**Strange Horticulture.**
- Players identify invented plants from a book of sketches and descriptions.
- The designers rotate which clue type helps: sometimes the sketch, sometimes text like "curled leaves", sometimes touch or smell.
- They include decoy features. Both developers are colourblind, and they changed colours after player reports [V, [Game Developer](https://www.gamedeveloper.com/design/strange-horticulture---bad-viking)].

**Botany Manor (April 2024).**
- A botanist grows plants by finding scattered clues around a manor and its grounds.
- The core move is substitution: a tool stands in for a natural condition, such as a heater for germination [S, [Pocket Tactics](https://www.pockettactics.com/botany-manor/review), [Checkpoint](https://checkpointgaming.net/reviews/2024/04/botany-manor-review-growing-strong/)].

### 2.5 For us [A]

- **Party scale.** Chants and Heaven's Vault take hours. Our scale is one match, so the language must be about 5 to 8 glyphs, learnable in one look and redrawn each match. That is the herb board's size (5 icons).
- **Heaven's Vault's "never confirm"** is a gift for deniability: an unconfirmed reading can always be "an honest guess". But in a 10-minute match it turns into frustration. A delayed confirmation at the serve step (harder-tasks Option D) is the party-sized version.
- **Strange Horticulture's multi-sense clues map to the orangery.** A plant hums, smells or glows, and the catalogue in the library names the trait, so the clue and its use sit apart. The colourblind lesson matches our existing rule "told apart by shape alone".

---

## 3. Safes, locks and codes

### 3.1 Feel-based locks (Thief, Payday 3)

**Facts.**
- Thief (2014) used controller rumble to signal when a pin could be picked [S, [Destructoid](https://vip-develop.destructoid.com/?p=167858)].
- A failed pick "is noisy … adds more risk to your looting" [S, [Steam](https://steamcommunity.com/app/239160/discussions/0/558749191396677435)].
- Players complained that "the mechanics are hidden", so they could not tell what mistake they had made [S, same thread].
- Payday 3 safes are a dial: turn until it shakes, stop on green, click, reverse. At least three rounds, an overshoot costs a stage, and a crack takes "15 seconds to a minute" [S, [GGRecon](https://ggrecon.com/guides/payday-3-lockpicking-safe-cracking), [Pro Game Guides](https://progameguides.com/payday-3/how-to-crack-safes-in-payday-3/)].
- Payday 2's 100x100 safe needs 300 s of drilling, and drills can jam [S, [Payday Wiki](https://payday.fandom.com/wiki/Safe_(Payday_2))].

### 3.2 Codes found in the world (Hitman, Deathloop)

**Hitman.**
- Codes sit on whiteboards and notice boards, in overheard conversations, and in a symbolic puzzle beside the safe [S, [PC Gamer](https://www.pcgamer.com/hitman-3-safe-keypad-code/)].
- They are fixed, so after one match everyone knows them [A]. That is exactly what open knowledge does to any fixed secret.

**Deathloop.**
- Codes are "random to each playthrough and will be different for every player".
- The delivery booth code is the key pattern: "randomized … the location where the code is found is always the same" [S, [PowerPyx](https://powerpyx.com/deathloop-all-door-codes-lock-combinations), [Gameranx](https://gameranx.com/features/id/260445/article/deathloop-how-to-unlock-delivery-booths-secret-code-location-guide/)].

### 3.3 Mastermind-style crates (LOCKDOWN Protocol)

**Facts.**
- The crate code is 4 digits with no repeats, with feedback per digit: grey, yellow or blue (`lp-rules.md`:183, [gameplay.tips](https://gameplay.tips/guides/lockdown-protocol-weapon-cases-locations-guide.html)).
- The crates "haven't been received well". Patch 0.3.0 cut them to 3 "to reduce the attention and time spent opening crates" (`lp-rules.md`:185-191).
- 4 distinct digits from 10 gives 10×9×8×7 = 5040 codes [S, [Codeforces](https://codeforces.com/blog/entry/49635)].
- Seven attempts is the commonly cited worst-case target; I could not verify that it is optimal [S, same].

### 3.4 For us [A]

- **"Fixed place, drawn value"** (the Deathloop booth) reconciles secrets with open knowledge. Everyone knows the safe exists, where its clue hangs and how it works. Only the value is new each match, which is exactly how the herb board already works.
- **A lock needs a sound.** A noisy failure (Thief) tells nearby players someone is at the safe, which suits proximity voice.
- **Keep it small.** Mastermind is solo deduction, not talk. A 4-digit code is too heavy. A 3-glyph code with lamp feedback lands near 20–40 s, if it gates something worth a minute.
- **Do not gate guns behind it.** LOCKDOWN's crates turned the opening minute into a rush for weapons.

---

## 4. Drink mixing

### 4.1 The single-player recipe games

**VA-11 Hall-A.**
- Five ingredients (sweet, bold, sour, spicy, and Karmotrine, the alcohol).
- Ice and ageing are toggles. Mixing becomes "blending" if you shake past about 5 s, until the shaker speeds up.
- There is no time limit, and you can reset an order [S, [Wikipedia](https://en.wikipedia.org/wiki/VA-11_Hall-A), [Steam](https://steamcommunity.com/app/447530/discussions/0/152393186502349158)].

**Coffee Talk Tokyo.**
- Temperature first, then base + primary + secondary. Order matters: the primary "affects flavor more".
- Any combination makes a drink, but only 54 combinations are "special" and get logged when first made [S, [games.gg](https://games.gg/fr/coffee-talk-tokyo/guides/guide-débutant-coffee-talk-tokyo-réussissez-toutes-vos-boissons/), [intoindiegames](https://intoindiegames.com/walkthroughs/coffee-talk-tokyo-walkthrough-part-2-day-three-day-six/)].

**Tavern Talk (June 2024).**
- A drink is up to 5 parts, 1–3 of any one potion, poured into a jug whose chart fills toward the target. You reset by dumping it.
- Reviewers found it "simple yet mostly satisfying" but repetitive [S, [Destructoid](https://www.destructoid.com/reviews/review-tavern-talk/), [GamingTrend](https://gamingtrend.com/reviews/tavern-talk-review-welcome-weary-traveler-would-you-like-to-take-a-look-at-my-drinks/), [Pro Game Guides](https://progameguides.com/general-walkthroughs/tavern-talk-walkthrough-best-outcomes/)].

**Potion Craft.**
- Each ingredient moves the bottle along a path on a map. Grinding sets the distance, and the bellows lock in an effect [S, [Rambling Reviews](https://ramblingreviews.substack.com/p/potion-craft?open=false)].

**Schedule I (2025).**
- 16 ingredients each add one effect. Order creates advanced effects, and a product holds at most 8 [S, [Deltia's](https://deltiasgaming.com/?p=194476), [schedule-1-calculator](https://schedule-1-calculator.com/blog/mastering-the-mixing-in-schedule-1)].

### 4.2 The co-op ones

- **The Mixologist (VR, 2024).** Up to five players. One can sit as a patron while friends mix his drink [S, [SideQuest](https://sidequestvr.com/app/37978/the-mixologist)].
- **Overcooked 2.** Each ticket has its own countdown. A tip multiplier rewards serving in order [S, [Pocket Gamer](https://www.pocketgamer.com/articles/078179/r/), [Steam](https://steamcommunity.com/app/728880/discussions/0/1652171126130895739)].
- **Overcooked's plates.** Each served meal leaves a dirty plate to collect and wash. That is a bottleneck that forces role switching [S, [SUPERJUMP](https://superjumpmagazine.com/overcooked-how-design-creates-teamwork), [Cubed3](https://cubed3.com/review/3229/1/overcooked-playstation-4.html)].

### 4.3 For us [A]

- **Mixing is a recipe lookup plus a skill step** (pour amounts, shake length). The lookup is where talk happens: "what does the toast glyph want?" The skill step is where honest errors happen: over-shaken, one part too many.
- **Order and partial amounts** (Coffee Talk, Potion Craft) make a wrong drink look plausible, which makes a human's spoil deniable.
- **Overcooked's dirty plate is a free second task.** Every drink served leaves a glass at the pool, and someone must bring it back. Chores like that let the work scale with the player count without new rules.
- **The tab is wrong.** VA-11 Hall-A's no-time-limit, reset-anytime design fits a cosy game. A party wants Overcooked's ticket clock.

---

## 5. Cleaning that is fun

### 5.1 PowerWash Simulator

**Design facts.**
- The design maximises the contrast between dirty and clean.
- The "DING" began as a placeholder for "fully finished" and gave "an almost Pavlovian dopamine rush". The distribution of DINGs is now "foundational" to every job [S, [Kotaku](https://kotaku.com/powerwash-sim-devs-on-making-cleaning-fun-advanced-cro-1847319502), [Shacknews](https://www.shacknews.com/article/131441/powerwash-simulator-developer-interview)].
- An object above 99% clean auto-completes [S, [TrueAchievements](https://www.trueachievements.com/game/PowerWash-Simulator/walkthrough/3)].
- The top complaint is the last per cent: a part "99.9 done" with nothing visible left [S, [Steam](https://steamcommunity.com/app/1290000/discussions/0/3041605810444728233), [GamesRadar](https://gamesradar.com/powerwash-simulator-tips)].

**Numbers.**
- The first game has more than 17 million players [S, [Gamereactor](https://www.gamereactor.eu/powerwash-simulator-surpasses-17-million-players-1521253/)].
- PowerWash Simulator 2 launched 23 October 2025 at $24.99, with two-player split screen and four players online [S, [GamingOnLinux](https://www.gamingonlinux.com/2025/10/powerwash-simulator-2-release-date-confirmed-for-october), [Hitmarker](https://hitmarker.net/news/powerwash-simulator-2-officially-announced-for-2025-no-nintendo-launch-currently-planned-1274797)].
- It had "over 1 million washers" in its first week [S, [FuturLab](https://www.futurlab.co.uk/news/remarkably-satisfying-one-month-of-powerwash-simulator-2)].

### 5.2 Viscera Cleanup Detail: the saboteur's dream

- A bucket of clean water cleans a mop about 6 times. Fully dirty, "the bucket becomes a new source of mess".
- Blood spreads "by dropping debris, spilling used buckets, or simply by the player tracking blood on the bottom of their boots" [S, [VCD wiki](https://viscera-cleanup-detail.fandom.com/wiki/Viscera_Cleanup_Detail)].
- The co-op pitch includes adding to the mess [S, [Steam](https://store.steampowered.com/app/246900/Viscera_Cleanup_Detail/)].

### 5.3 Crime Scene Cleaner (14 August 2024)

- 355k units and about $5.4M gross in 60 days, and 97% positive reviews [S, [WN Hub](https://wnhub.io/news/stores-and-publishing/item-45772)].
- A "Cleaner's Sense" vision highlights what is left [S, [Steam](https://store.steampowered.com/app/1040200/Crime_Scene_Cleaner/)].

### 5.4 Untitled Goose Game

- The garden keeper's reactions are the comedy: "it's often the groundskeeper's responses that makes the goose seem so bad" [S, [ACMI](https://www.acmi.net.au/education/school-program-and-resources/honk-untitled-goose-exhibition-education-resource/)].
- This is the reverse view of a garden chore: the mischief is fun because someone has to clean it up.

### 5.5 For us [A]

- **Cleaning is the natural fix for mischief.** The engineer's ongoing mischief ("the bins knocked over", `m8-match.md` §5) already needs a fix. Making that fix a satisfying clean, with a progress ring and a DING, turns a chore into a reward.
- **It works with no humans at all.** Clumsy aliens track goo and kick buckets by accident. That is "the party is hard on its own" and "fun for two aliens".
- **The spoil is deniable.** Tracking mess on your feet is exactly the Viscera case: "I didn't see the puddle".
- **Engine cost.** Painted dirt masks are expensive to sync. A grid of discrete dirt patches (each a small host-authoritative object) gives 90% of the feel. Clear an object at 95% to avoid PowerWash's last-per-cent hunt.

---

## 6. Summary table

| Kind | Unit time (evidence) | How it scales | How it makes talk | Deniable spoil | Learnability |
|---|---|---|---|---|---|
| Codebook (KTANE, terminal) | a module ≈ 30–90 s [A]; Lethal Company disable 5 s [S] | number of modules, needy modules [V] | the reader is away from the doer; homophones [V] | misread, slow read | one page per board; glyphs must be describable |
| Invented language | hours in Chants [V]; we need 1 look | glyph count | "pronouncing silly words" [V] | an "honest guess" (Heaven's Vault) [V] | 5–8 glyphs per match, shape only |
| Safe or code | Payday 3 15–60 s [S]; Payday 2 drill 300 s [S] | number of safes | the clue is far from the safe (Hitman notes) [S] | a wasted attempt, a lockout | fixed place, drawn value (Deathloop) [S] |
| Drink mixing | VA-11 untimed [S]; Overcooked ticket timers [S] | open orders, dirty glasses | a lookup plus "who's on it" | order, amounts, over-shake | recipe size ≤ 3 parts (Tavern Talk 5 is already "repetitive") [S] |
| Cleaning | Among Us Clean O2 ≈ 10 s record [S, [speedrun.com](https://www.speedrun.com/among_us_ce/levels)]; PowerWash jobs much longer | the amount of mess | little; finding the last patch | tracking mess, a spilled bucket [S] | instant; the risk is last-% hunting [S] |

---

## 7. The respawn spectacle

### 7.1 Case facts

**Fortnite (checked live).**
- Reboot: a 10 s interaction. Letting go drains the progress slowly.
- A van cooldown of 120 s at launch, silently cut to 60 s in Chapter 2 Season 4. A Reboot Card stays on the ground for 90 s [S, [Shacknews](https://www.shacknews.com/article/111076/how-the-reboot-van-works-in-fortnite-v830), [Gfinity](https://www.gfinityesports.com/article/fortnite-chapter-2-season-4-secret-reboot-vans-buff-reduce-cooldown-waitin-time-ps4-xbox-one-pc-ios-android-switch)].
- The show: squad members "appear one by one on top of the van", a rift opens above it for each, and "a giant beacon of light is projected into the sky" [S, [GameRevolution](https://www.gamerevolution.com/?p=521243)].
- Chapter 7 added drivable vans. Whether a van is drivable is random per match (tyres versus wheel clamps), and the back revives a downed teammate while the van moves [S, [All Things How](https://allthings.how/fortnite-chapter-7-drivable-reboot-vans-spawns-map-basics-and-how-revives-work/), [Epic dev docs](https://dev.epicgames.com/documentation/fortnite/drivable-reboot-van-devices-in-fortnite)].
- The 6 December 2025 hotfix: "Reboot Vans now start with a full tank of fuel", because they "were being dumped more commonly on the map due to low-fuel than we intended" [V, [Shacknews](https://www.shacknews.com/article/147063/fortnite-patch-notes-dec-6-2025)].
- Reload mode: an automatic 30 s timer rising to 40 s, shortened by 2 s per down, 4 s per elimination and 10 s per squad wipe [S, [SI](https://videogames.si.com/guides/fortnite-v30-20-patch-notes-fortnite-reload)].

**Apex Legends.** A beacon channel of about 5 s (6 s per the Titanfall wiki). The dead arrive by "a small spaceship, which is visible and audible to other legends" [S, [Apex wiki](https://apexlegends.wiki.gg/wiki/Respawn_Beacon), [Titanfall wiki](https://titanfall.wiki.gg/wiki/Respawn_beacon)]. Campers hid inside beacons (`death-respawn.md` §2.4).

**Splatoon: the best small-marker precedent.**
- Respawn ≈ 0.5 s splat + ~6 s splat cam + ~2 s respawn animation ≈ 8.5 s. Splatoon 3 is about 9 s [S, [Inkipedia](https://splatoonwiki.org/wiki/Quick_Respawn), [Game8](https://game8.co/games/Splatoon-3/archives/387627)].
- A Super Jump shows a landing marker: the player's name and a down arrow whose "ink" drains as landing nears, so enemies time attacks on it.
- The Stealth Jump ability hides the marker from distant players [S, [Inkipedia](https://splatoonwiki.org/wiki/Superjump), [Inkipedia](https://splatoonwiki.org/wiki/Ninja_Jump)].

**Team Fortress 2.** A player who teleported glows in team colour for 18 seconds, which "can reveal a Teleporter location to the enemy". A recharging teleporter spins faster, and its beeps tell its level [S, [TF2 wiki](https://wiki.teamfortress.com/wiki/Tele)].

**Call of Duty Tactical Insertion.** A flare the player places, green to friends and red to enemies. Enemies can disable it by interacting or shooting, or wait beside it [S, [CoD wiki](https://callofduty.fandom.com/wiki/Tactical_Insertion), [Pro Game Guides](https://progameguides.com/call-of-duty/how-to-use-the-tactical-insertion-field-upgrade-in-mw3/)].

**Helldivers 2.** Pods are steerable and "squash enemies and allies alike". A new ticket comes every 120 s once tickets run out (90 s with the booster) [V, [Helldivers wiki](https://helldivers.wiki.gg/wiki/Reinforce)].

**Rebuilt or cloned bodies.**
- **Borderlands New-U.** It stores DNA against "accidental death or dismemberment" and "digistructs" a new body [S, [Borderlands wiki](https://borderlands.fandom.com/wiki/New-U_Station)]. I could not verify Borderlands 4.
- **BioShock Vita-Chambers.** Criticised as having "removed any sort of challenge". Ken Levine: they "didn't break the flow" [S, [bit-tech](https://bit-tech.net/news/gaming/bioshock_dowloadable_content_on_the_way_/1), [Shacknews](https://shacknews.com/article/48587/creative-director-ken-levine-on)].
- **Oxygen Not Included.** A Printing Pod offers new printables every 3 cycles [S, [ONI wiki](https://oxygennotincluded.wiki.gg/wiki/Printing_Pod)].
- **Hardspace: Shipbreaker.** Each clone adds over a million credits to your debt [S, [God is a Geek](https://www.godisageek.com/reviews/hardspace-shipbreaker-review/)].
- **Space Station 13: a social-deduction cloner.**
  - Cloning takes 2–3 minutes.
  - A traitor can eject a clone early or cut the power, producing a body "without limbs or vital organs".
  - The wiki suggests an aborted clone as petty traitor revenge [S, [BeeStation wiki](https://wiki.beestation13.com/view/Hulk)].
- **Barotrauma.** A respawn shuttle wave every 300 s by default, with up to 180 s to reach the sub. It triggers when 20% of the crew are dead [S, [XGamingServer](https://xgamingserver.com/blog/barotrauma-server-settings-explained-a-serversettings-xml-guide/)].
- **PEAK (2025).** An Ancient Statue revives once and its head crumbles. The revived return at Hunger 30 with +5 Curse [S, [PEAK wiki](https://peak.wiki.gg/wiki/Ancient_Statue)].
- **R.E.P.O.** The dead become a head that is carried to extraction, and they return at 1 HP [S, [Dot Esports](https://dotesports.com/indies/news/how-to-revive-your-teammates-in-r-e-p-o)].
- **Mercy (Overwatch 2).** Resurrect has a 1.75 s cast [S, [VideoGamer](https://www.videogamer.com/?p=211836)].

**A warning from Splitgate.** A battle-royale player says he feels "randomly thrown back into the game to the point I don't know I'm back", and asks for a sound or screen effect [S, [BetaHub](https://app.betahub.io/projects/pr-2055671118/feature_requests/312)].

### 7.2 What it shows to others

| Moment | Typical length | What others see |
|---|---|---|
| **Telegraph** | 2–6 s | a marker (Splatoon's draining arrow, Apex's ship, Fortnite's light beam) |
| **The rebuild** | 1.5–2 s | Splatoon ~2 s, Mercy 1.75 s; the body forms |
| **Trace** | the protection window | a glow on the player (TF2's 18 s team glow) |

**For us [A].**
- The telegraph is our pillar's "chance to react": a camper sees it coming, and so does a friend.
- The trace makes our 3 s invulnerability readable, so nobody wastes a swing.
- The arrival is also the respawned player's own cue (the Splitgate warning).

### 7.3 Marking a respawn point without a big prop

The cases show four tools [A]:
1. A transient marker at the moment of use (Splatoon, Fortnite's beam), with nothing permanent.
2. A small fixture with a state cue (TF2's spin and beeps, CoD's coloured flare).
3. A glow on the arrival, not on the place (TF2).
4. A once-only fixture that visibly breaks (PEAK's crumbling head).

In a manor, the capsule can be ordinary furniture that only betrays itself when used. That is the engineer's "normal manor with alien touches".

---

## 8. Patterns

1. **Information away from its use, a short distance apart.** KTANE, Lethal Company's terminal, Hitman's notes, our herb board. With 8 m voice and muffling walls, the gap does the work.
2. **A fixed rulebook with a drawn value** beats random rules (KTANE's static manual [V], Deathloop's fixed-place, random-value booth code [S]). This is the bridge between open knowledge and per-match secrets.
3. **The fun is in describing and saying** (glyphs, homophones, "silly words" [V]). Choose glyphs for how funny they are to name aloud.
4. **Honest error comes from the medium:** muffled voice, homophones, order-sensitive mixes, tracked mess. Then a deliberate spoil has more than one author.
5. **Rewards are sounds.** PowerWash's DING, TF2's beeps, Fortnite's chime when the van is ready [S, [Inverse](https://inverse.com/article/54739-fortnite-reboot-van-locations-map)].
6. **Every unit leaves a by-product** (Overcooked's plates, Viscera's bucket), so work scales without new rules.
7. **A respawn has three beats** (telegraph, rebuild, trace), totalling 2–8 s in the fast games, and each beat is information.
8. **Cloners invite sabotage** (SS13, the Supervive and Space Engineers cases in `death-respawn.md`), and that is a lever for an outed human.

## 9. Risks

1. **Too much reading [A].** Five codebook stations make the party a library. At most one or two lookups should be active per player at a time.
2. **Same loop, new skin [A].** A cocktail lexicon that copies the herb board is a reskin, not a new task. The second station needs a different skill step (pour amounts, shaking), not only a new lookup.
3. **Fixed secrets die after one match [A].** Hitman-style codes are memorised by week two, and open knowledge then makes them a speed check.
4. **Gated rewards cause rushes.** LOCKDOWN's weapon crates had to be cut back ("to reduce the attention and time spent opening crates", `lp-rules.md`:191).
5. **Last-per-cent cleaning [S].** PowerWash's most common complaint.
6. **Physics mess costs network budget [A].** Many small dirt objects or painted masks over ENet; the wire budget is already being sized (`docs/GDD.md`, #775).
7. **A telegraph invites camping.** Apex players hid inside beacons; Splatoon's marker is designed to be attacked [S]. Our 3 s invulnerability covers it only if the trace is clear.
8. **Accessibility.** Colour clues fail colourblind players (Strange Horticulture's fixes [V]). Voice-only relays fail players without a microphone (`communication-mechanics.md`).
9. **The surprise-versus-open-knowledge clash [A].** A secret that gives power becomes the meta once found (`scattered-points-cameras-secrets.md`:222). A secret that only exists for one player breaks "the rules are known to all".

---

## 10. Options for the engineer (original; every value is a placeholder)

### Option 1: one alien lexicon for the whole estate

- **What.** One per-match alphabet of 6–8 shape-only glyphs, each with a silly spoken name printed under it ("the wobbly egg"). It is shown in full only in the library, on a big lectern book.
- Every station that "reads" draws from the same glyphs: the orangery's herb board, the bar, the safe.
- **Pros.**
  - One learning pays everywhere.
  - Names made to be said aloud give comedy and honest mishearing through walls.
  - The library gets its mechanic.
- **Cons.**
  - One read of the library book can solve several stations. Answer: each station uses a different mapping (glyph to herb, glyph to bottle, glyph to digit).
  - If the lexicon is badly made, every station fails at once.

### Option 2: the pavilion bar (cocktails from a toast card)

- **What.** A guest's toast card shows 3 glyphs. The lexicon maps each glyph to a bottle. The bartender pours them in order and holds to shake.
- Too short is "stirred", too long is "frothed", with the window shown on the shaker.
- The bartender serves the drink on the lawn. The check is deferred: the guest's reaction at the sip, such as a spit-take for a wrong drink.
- **By-product.** Every glass returns dirty to a tray that someone carries to the summer kitchen.
- **Time.** 40–60 s per drink. Open orders up to 2 + players ÷ 3 (round-3 placeholder).
- **Pros.**
  - A real skill step, not only a lookup.
  - The spoil is deniable (order, amounts, shaking).
  - Gives the pool pavilion and the summer kitchen their mechanics.
- **Cons.**
  - Close to Cooking. It must replace a Cooking unit in the work budget, not add on top, or the #1089 model doubles.
  - Needs a guest reaction (animation or audio).

### Option 3: the lord's portrait safe ("fixed place, drawn value")

- **What.** A safe behind a portrait of an alien lord in the study.
- Its 3-glyph code is new each match. Each glyph hangs at a fixed, known estate place (the sundial, the hall clock, the orangery label) and changes each match.
- Lamp feedback per position, 5 tries, then a 20 s lockout with a loud clunk heard through walls.
- **What it holds.** Never a weapon. Rather a "stall the cops" voucher, one big mischief item (the fireworks), or a passage key.
- **Pros.**
  - Reconciles secrets with open knowledge.
  - A noisy failure tells the room.
  - A human who wastes tries is deniable.
- **Cons.**
  - Solo deduction competes with talk.
  - Gated rewards attract rushes (LOCKDOWN).
  - One more lock to teach.

### Option 4: cleaning as the fix for mischief

- **What.** The ongoing mischief leaves cleanable mess: the overturned bins on the lawn, goo spilled in the ballroom, leaves in the pool.
- Mess is a grid of discrete patches, each a host-authoritative object.
- A ring fills over the object. A ding when a patch clears, a louder ding when the area clears at 95%. Only clearing the area stops the anger from rising.
- **Mess spreads.** Walking through goo tracks footprints (new patches). A kicked bucket spills.
- **Pros.**
  - Ties the cleaning to the neighbours' anger meter (§5) instead of adding a new goal.
  - Fun with no humans (clumsy aliens spread it).
  - A deniable spoil ("I didn't see it").
  - Scales with the chaos itself.
- **Cons.**
  - Patch count is a network cost.
  - A spilled-bucket spoil may be too strong and needs a cap.
  - Art for footprints and patches.

### Option 5: the reprint fixtures (respawn without a big prop)

- **What.** The 5–6 capsules become ordinary manor fixtures with one alien seam: a grandfather clock, a dumbwaiter hatch, a wardrobe, a garden fountain, a portrait frame, a hedge niche.
- Three beats:
  1. **Telegraph, 3 s.** A faint outline of the coming body glows at the fixture, and a chime is heard within 15 m (the Splatoon marker, but local).
  2. **Rebuild, 1.5 s.** The alien is printed bottom-up in slices, briefly wrong in one comic way (a monocle, wet "ink").
  3. **Trace, 3 s.** A glossy "fresh print" sheen marks the invulnerability (TF2's glow).
- **Pros.**
  - Every capsule is a room feature, not a box.
  - The telegraph is the pillar's chance to react for both sides.
  - The respawned player knows he is back.
  - 4.5 s total keeps "never boring".
- **Cons.**
  - The telegraph helps campers (mitigated by the invulnerability).
  - Six bespoke fixtures cost art.
  - The rebuild must stay short in clips and in play.

### Option 6: respawn through the passages (surprises found in play)

- **What.** Some fixtures sit inside the servants' corridors or behind the bookcase door.
- A player printed there steps out through a passage he may not have known about. The passage is on the map as a dotted line (open knowledge), but its door opens from inside only until someone has walked it.
- **Pros.**
  - Gives the "surprises discovered only by playing" a fair delivery: death itself shows you the secret.
  - The random capsule makes it a lucky break.
- **Cons.**
  - Passage geometry must be safe as a spawn (no dead-end trap with a camper at the exit).
  - A one-way-at-first door is extra state to sync and teach.

### Option 7: a jammable capsule (a sabotage at the cloner)

- **What.** A human can clog one capsule with orangery goo: a 10 s action, deniable as "I was cleaning it".
- While jammed, the next player printed there comes out a comic mess: slowed for 5 s, wrong colour.
- An alien fixes it with a short clean (Option 4's patch).
- **Pros.**
  - The outed human gets a lever.
  - The cloner becomes a place where both goals meet (SS13, `death-respawn.md` Option E).
  - Never a lockout.
- **Cons.**
  - Must never trap a player.
  - It is one more rule for the respawn, which today is decided as simple (`m8-match.md` §3).

### Recommendation [A]

- **First:**
  - Option 1 as the rule.
  - Option 4 next, because it answers the decided anger meter's open "fix it" step and gives the estate's lawn and pool their mechanics. It is fun with no humans and needs no new goal.
  - Option 5 for the respawn, with the decided 30 s wait and 3 s invulnerability unchanged, so it is pure presentation.
- **Second:** Option 2, as the bar that replaces one Cooking unit, after the #1089 rerun with about 45 s units.
- **Hold:**
  - Option 3 until the rewards for points are decided (§7, weapons deferred).
  - Options 6 and 7 until the first estate greybox shows the passages work as chase-breakers.

---

## 11. Open questions for the engineer

1. One shared alien lexicon (Option 1), or each station with its own icons like the herb board today?
2. Should a glyph's spoken name be part of the open knowledge printed in the library, so mishearing it is the honest error?
3. Does the bar replace a Cooking unit, or is it a second food-and-drink chain with its own share of points (§4)?
4. Is cleaning the fix for the ongoing mischief (the bins, the goo), or a separate chore in the work pool?
5. What may a safe hold: points, a cops voucher, a mischief item, a key? Never a weapon?
6. Respawn telegraph: seen by everyone in the room, or only within a short radius (Splatoon's Stealth Jump is the precedent for a hidden variant)?
7. May a capsule sit in a secret passage, so a respawn reveals it (Option 6)? Or must the passages stay found only by walking?
8. Is one comic flaw on reprinting (a monocle, wet ink) welcome as tone, or does it read as a penalty?
9. May a human jam a capsule (Option 7), or are capsules untouchable as in today's rules?

## 12. What I could not verify

- KTANE's default timer per bomb and real module solve times.
- The exact length of Apex's dropship arrival and Fortnite's 2026 van cooldown (the newest data I found is the Dec 2025 hotfix).
- Borderlands 4's respawn.
- Barotrauma's official wiki (HTTP 403).
- Whether the LOCKDOWN Protocol crate rules changed after 1.2.0.
- Godot 4.7's cost for painted dirt masks. Measure it in a greybox before choosing Option 4's form.