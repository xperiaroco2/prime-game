# Harder, more engaging tasks: find, look up, remember, communicate

## 0. Scope, tags and verification

The question: how do other games make tasks that ask for search, observation, memory or a relay between players fun and not tedious? This report maps the answer onto the House's five chains (Delivery, Generator, Cooking, Photo, Car repair) and onto the decided M8 match. It builds on `docs/design/m8-match.md` (origin/main), `docs/GDD.md` §8, `docs/design/house-map.md` §6–7, round 2's sabotage report (`docs/design/research/2026-10-15-sabotage-and-scoring.md` §2.4) and the balance model in issue #1089. It does not repeat them.

**Tags.** [V] means verified on a page I fetched. [V-s] means the fact comes only from a search-result summary, so treat it as likely but unconfirmed. [P] is an opinion (a designer's, a reviewer's or a player's). [A] is my analysis. Every number in a proposal is a **placeholder**.

**Limits.** Fandom wikis (Among Us, Lethal Company) refused fetches (HTTP 402, or a bot wall). The GDC Vault talks are behind a login. The session's shared web-search budget ran out after about 48 searches and fetches, so a few planned checks were not done. They are listed in §9.

## 1. Where we start

- **The work is too short today.** Model v2 (#1089) priced a step at 8–18 sprint-seconds and counted 30 steps at default settings and 52 at maximum. With no interference the aliens finish in 2.9–3.9 minutes at almost every player count. The engineer's answer: the tasks get harder ("find, look up, remember"), and the model reruns with the new step times [V, #1089 comments].
- **What thinking the chains already ask for.** Delivery asks you to tell an item's place "by meaning, not by colour", with no markers (GDD §8). Cooking asks you to decode the herb icon on a board in the greenhouse, 94 m away from the kitchen and back (house-map §7). The Generator makes players coordinate out of earshot. Photo has a three-floor path. Car repair asks the lift holder to trust someone he cannot see. The engineer already marked car repair "for the MVP only", to be replaced by "a much more interesting mechanic", and floated "a player crawls under the car to see what it needs" (GDD §8) [V].
- **Covert spoiling is visible at once.** A wrong ingredient on a plate shows a red outline right away and can be taken back (GDD §8 Cooking). So "the wrong herb on a burger" costs the aliens only seconds, and it is seen at the plate [A].

## 2. Case studies

### 2.1 Among Us: the reference list of task shapes
- **How it works.** There are three categories: short (one stage), long (several stages, or a wait, or several rooms) and common (everyone gets the same one) [V-s, [Android Central](https://www.androidcentral.com/among-us-polus-tasks-guide)]. The host sets 0–2 common, 0–3 long and 0–5 short tasks per player [V-s, [GameWith](https://gamewith.net/among-us-wiki/article/show/22148)]. "Visual" tasks play an animation others can see, which can prove a crewmate innocent. The Skeld has 5 visual tasks out of 14 [V-s, [Pro Game Guides](https://progameguides.com/among-us/how-to-do-all-visual-tasks-in-among-us/)].
- **The thinking tasks are tiny but real.** Each of these takes seconds:
  - Unlock Manifolds: press 1 to 10 in order. A wrong press resets it, and leaving reshuffles the keypad, so you cannot learn positions by heart [V-s, [GetDroidTips](https://www.getdroidtips.com/among-us-unlock-manifolds/)].
  - Start Reactor: a Simon-style sequence repeated over five rounds [V-s, [Windows Central](https://www.windowscentral.com/among-us-task-guide-skeld)].
  - Enter ID Code: read a code off the card in your wallet and type it in [V-s, [TrueAchievements](https://www.trueachievements.com/game/Among-Us/walkthrough)].
  - Inspect Sample: start it, wait 60 s, come back and pick the right sample [V-s, [Windows Central](https://www.windowscentral.com/among-us-task-guide-skeld)]. Players value it because you can walk away during the wait [P, [TheTopTens](https://www.thetoptens.com/among-us/among-us-skeld-map-tasks/)].
- **Length.** Speedruns of "all tasks" on The Skeld (every task on the map, by one player) take 2:43 on keyboard and 4:27 on controller [V-s, [speedrun.com](https://www.speedrun.com/among_us)]. So a normal player's list of a few tasks is a minute or two of hands-on work.
- **The lesson from its history.** In early builds "the ship was always in crisis" and "Impostors could do tasks wrong to hinder players". The team found that "too stressful", with too little time for detective work, and dropped it [V, [Nintendo interview](https://nintendo.com/whatsnew/among-us-dev-recounts-how-the-game-took-flight)].
- **What goes wrong.** Crewmate tasks "can become rather monotonous" [P, [Mechanics of Magic](https://mechanicsofmagic.com/2022/04/07/critical-play-among-us-alex-tsai/)]. Swipe Card is "finicky", and the Submit Scan screen hides any impostor walking up [P, V-s, [TV Tropes](https://www.tvtropes.org/pmwiki/pmwiki.php/ThatOneLevel/AmongUs)]. Visual tasks remove doubt, which some players dislike [P, V-s, [itch.io](https://itch.io/post/1912686)].
- **Mapping [A].** Among Us tasks are verification devices, not engaging work. We have no meetings and deduction is not central, so we need the reverse: tasks that are fun in themselves. The "do tasks wrong" sabotage it dropped is a good fit for us, because we have no meetings to starve of time and the tone is comic chaos.

### 2.2 LOCKDOWN Protocol: orders by code (checked live)
- **Status.** Early Access opened 22 July 2024 and the full release came 18 November 2025, for 1 to 16 players, by Mirage Creative Lab [V, [Steam](https://store.steampowered.com/app/2780980/LOCKDOWN_Protocol/)].
- **Pizzushi.** Each order needs one rice out of 3 kinds, one fish out of 4 and one coloured plant out of 5. The plant colour is coded in the recipe code: the first letter of the third code part gives the colour ("G3M" means green). Players place a base, add the parts, box the result and deliver it to the matching table, where a top light turns red if something is wrong [V, [Steam thread](https://steamcommunity.com/app/2780980/discussions/0/599640609289942100)].
- **Pressure.** Canisters marked 1, 2 and 3 pop off at thresholds, and players must swap in the next grade [V, same thread].
- **The risks players name** are "dissidents stealing rice containers" and employees "accidentally swapping proteins or colors" [V, same thread]. So honest mistakes happen often enough to cover deliberate ones [A].
- **What goes wrong.** Players learn the tasks from a "vague silent film". Some did not know the pressure tanks could be removed. One calls Pizzushi "just another time sink", while another finds it satisfying once the ingredients are staged [P, V, same thread]. An aggregate of Steam reviews (AI-made, so treat it with caution) puts "lack of … varied tasks" as the top complaint, and praises interactive tasks over button presses [P, [Vaporlens](https://vaporlens.app/app/2780980/lockdown_protocol.md)].
- **Mapping [A].** Our Cooking is already this shape. Variety and teaching are where these tasks die, so each new thinking beat needs a how-to card and must stay readable in under 10 s.

### 2.3 Keep Talking and Nobody Explodes: one sees, the other reads
- **How it works.** The defuser sees the bomb and the experts hold the manual [V-s, [GDC Vault](https://gdcvault.com/play/1023113/Designing-Asymmetric-Gameplay-For-Keep)]. The rules themselves, not only the bombs, are procedurally generated [V-s, [PC Gamer](https://www.pcgamer.com/au/keep-talking-and-nobody-explodes-has-sold-over-200000-copies)].
- **Rules that send you looking.** The rules hang on facts printed elsewhere on the casing, which forces the defuser to go and look. For example: "If there is more than one red wire and the last digit of the serial number is odd, cut the last red wire". The batteries and the lit indicators sit "on the sides of the bomb casing" [V, [bombmanual.com](https://www.bombmanual.com/web/index.html)].
- **Memory.** Later stages of the Memory module say "press the button in the same position as you pressed in stage 1", and a wrong press resets to stage 1 [V, same].
- **Pressure.** Three strikes, plus "needy" modules that come back again and again [V, same].
- **Why it works.** The team "needed a reason for the players to talk to each other" [P, V-s, [Voices of VR](https://voicesofvr.com/?p=927)]. The manual is deliberately dense with irrelevant procedures, so finding the right section is part of the challenge [P, V-s, [KeenGamer](https://www.keengamer.com/articles/news/keep-talking-and-nobody-explodes-short-review/)].
- **Mapping [A].** "Look up a fact somewhere else first" is the cheapest way to add a thinking beat to a station. Our herb board already does it. The car is the natural second place, and it fits the engineer's own idea of crawling under it.

### 2.4 Spaceteam: a stream of shouted orders
- **How it works.** Each player sees one instruction that is usually for someone else's panel, so they shout it. Shouting was "not an intended feature": it is "the only way to getting someone to hear your instruction" [V, [Episodic Content, ch. 3](https://episodiccontentmag.com/2016/02/05/everybodyshake3/)].
- **What its playtests found** [V, same]:
  - Four instructions at once "overwhelmed" testers, so the game went to one at a time per player.
  - Without a global clock "people just ended up with their spaceship in the middle of the screen", so a supernova chases them.
  - Playtesters suggested the mundane jokes ("Feed Fish").
  - An anomaly turns all text into icons.
- **Mapping [A].** A stream of orders works when each person holds one at a time, the orders are cheap to say aloud, and a global clock exists. We already have the clock (the timer, the cops).

### 2.5 We Were Here, Operation: Tango, Big Walk (2026): voice as the medium
- **We Were Here and Operation: Tango.** In We Were Here, two players in separate places describe their surroundings over a walkie-talkie [V-s, [Room Escape Artist](https://roomescapeartist.com/2021/02/02/we-were-here-review/)]. In Operation: Tango, the hacker guides the agent across electric tiles only the hacker can see. The developer says "communication … can be the biggest puzzle of all" [P, V-s, [Retroware](https://articles.retroware.com/2021/06/03/retroware-sit-downs-operation-tango-is-a-co-op-game-inspired-by-mission-impossible/)].
- **Big Walk (House House), out on 4 August 2026, 2 to 12 players** [V-s, [Wikipedia](https://en.wikipedia.org/wiki/Big_Walk)]. Its voice system makes voices "muffle through walls" [V-s, [press kit](https://www.bigwalk.game/presskit/)]. That is exactly our planned rule.
  - "Soundproof rooms forced our team to figure out how to communicate nonverbally." One puzzle puts a player in a helmet that muffles his voice and blocks his view, and the others steer him ("turn 10 degrees to your left") [V, [Game Informer review](https://gameinformer.com/review/big-walk/a-walk-to-remember)].
  - Puzzles are tuned to the group: a crane sits lower for two players and higher for four or more [V, [Game Informer preview](https://gameinformer.com/preview/2026/03/09/a-walk-well-wasted)].
  - The designers cap the core design at four because coordinating five or more "became unwieldy". They call the walking between challenges "the negative space … for you to have your own fun" [P, V, same].
- **Mapping [A].** Muffling walls turn the House's layout into a communication puzzle for free. A relay task should put "the reader" and "the doer" just beyond clear earshot, so players must shout, move, or go and look for themselves.

### 2.6 Overcooked: orders, timers, layout
- **How it works.** Orders "pile up on top of the screen". Every order has a visible timer, and faster delivery earns bigger tips. One star is "almost too easy", three stars need planning and talk. Counters split ingredients from stations, so players have to pass things across. Layouts change mid-level, plates are limited and fires break out [V, [SuperJump](https://superjumpmagazine.com/overcooked-how-design-creates-teamwork)].
- **Length.** Most levels run 4 minutes, and the first real one 2:30 [V-s, [TrueAchievements](https://www.trueachievements.com/game/Overcooked/walkthrough/3)]. Order frequency scales with the player count [V-s, [Push Square](https://www.pushsquare.com/reviews/ps4/overcooked_2)]. The co-founder drew on restaurant work: "constant communication, working against the clock" [P, V-s, [Red Bull](https://www.redbull.com/us-en/overcooked-2-ghost-town-games-interview)].
- **Mapping [A].** The engineer asked for Cooking "in the spirit of Overcooked" (GDD §8). What we lack is the stream: one burger by default, at most 3, all posted at the round's start.

### 2.7 Phasmophobia: evidence and a random checklist
- **Evidence.** Every ghost leaves 3 kinds of evidence out of about 7. Higher difficulties hide one or more, so players fall back on behaviour [V-s, [ExitLag](https://www.exitlag.com/blog/phasmophobia-cheat-sheet/), [PC Gamer](https://www.pcgamer.com/au/phasmophobia-ghost-types-orb-models)].
- **A random checklist.** Optional objectives are drawn at random for each contract and posted on a whiteboard in the van. Only "identify the ghost" is always there [V-s, [Shacknews](https://www.shacknews.com/article/121116/how-to-get-photo-rewards-phasmophobia)].
- **Voice as input.** The ghost hears the microphone without push-to-talk, and saying its name can start a hunt [V-s, [PC Gamer](https://pcgamer.com/au/phasmophobia-spirit-box-questions)].
- **Mapping [A].** "A fixed frame, a random draw of objectives each round" is a cheap source of variety. Voice recognition is out of scope for a hobby project, but "talking near something has a cost" is not.

### 2.8 Lethal Company and R.E.P.O.: scavenging against a quota
- **Lethal Company.** The quota rises quadratically per cycle, and each cycle gives 3 days to collect [V-s, [Lethal Company wiki](https://lethal-company.fandom.com/wiki/Profit_Quota)]. One player at the ship terminal reads a teammate's grid code off the radar (e.g. "E4") and types it, which opens a door or stops a turret for about 5 s. The walkie-talkie connects the two [V-s, [Common Sense Gamer](https://commonsensegamer.com/lethal-company-terminal-how-to-open-doors-with-it/), [Prima](https://primagames.com/tips/all-terminal-commands-in-lethal-company)]. This is a relay role that players invented a team job around [A].
- **R.E.P.O.** Semiwork; Early Access 26 February 2025; up to 6 players; about 230,000 concurrent players at its peak. Damaging an object lowers its value [V, [Wikipedia](https://en.wikipedia.org/wiki/R.E.P.O.)]. Extraction points grow from 1 to 4 as levels advance, each used once, and the next must be found [V, [GamerBlurb](https://gamerblurb.com/articles/repo-difficulty-scaling-explained), a fan guide]. Quotas reportedly scale with team size [V-s, same search].
- **Mapping [A].** "Find the next place" and "fragile value" turn carrying into a skill. A fragile Delivery item fits our comic violence and gives humans a deniable spoil: "I tripped".

### 2.9 Escape rooms: the craft of fair search
- **Structure.** Rooms come in linear, open and multi-linear shapes [V-s, [ASEE paper](https://nemo.asee.org/public/conferences/327/papers/36891/download)]. "One padlock and six people" leaves five standing idle [P, V-s, [Escape Reality](https://www.escapereality.com/blog/escape-rooms-for-large-teams)].
- **Emily Short's multiplayer lessons** [V, [Emily Short](https://emshort.blog/2016/06/02/learning-about-multiplayer-puzzle-design-from-escape-rooms/)]:
  - Give two or three puzzles at once.
  - Not everyone has to solve everything.
  - Put the information "at some distance from where you're going to be able to use it".
  - Coordinating "three people" is easier than ten.
- **Searching** [V, [Escape the Review](https://www.escapethereview.co.uk/?p=7599)]:
  - "It's not the searching that's fun – it's the finding."
  - State how many items exist.
  - Hide more than needed: teams "just need to find enough".
  - Narrow the area: players will search one small part thoroughly if they know something is there.
- **Red herrings and clue chains.** Red herrings are "almost always detrimental"; "the players will create their own" [P, V, [Room Escape Artist](https://roomescapeartist.com/2019/02/10/red-herrings/)]. "Make sure the connection between clues is strong"; "don't make clue collecting tedious" [P, V, [Room Escape Artist](https://roomescapeartist.com/2016/07/17/the-room-escape-artist-dos-and-donts/)].
- **Mapping [A].** A "find" task on the House must state the count and use a pool of plausible spots, more spots than items. Never pixel-hunt for a tiny object.

### 2.10 Hidden objects, spotting differences, memory
- **Hidden-object scenes.** Wooga spreads items of mixed size, colour and shape evenly, avoids big empty gaps, and places some items where players do not expect them. Common objects come back in different places [V, [Wooga](https://www.wooga.com/blog/hidden-in-plain-sight-making-hidden-object-scenes-fun-to-play-8d3483f43f6c)]. Hidden Folks hides targets behind interactions (open a tent, shake a tree) and gives sound hints [V-s, [PocketGamer](https://www.pocketgamer.com/articles/073054/hidden-folks-creator-adriann-de-jongh-gives-us-an-insight-into-this-quirky-little-puzzler/)].
- **Anomaly games.** The Exit 8 asks you to spot anomalies against a remembered baseline, eight times in a row. One anomaly (larger posters) was so subtle that players reported a bug [V-s, [Automaton](https://automaton-media.com/en/news/20231208-23845/)]. I'm on Observation Duty loses you the game when unreported anomalies pile up [V-s, [Giant Bomb](https://giantbomb.com/wiki/Games/Im_on_Observation_Duty_5)].
- **Mapping [A].** "Spot what changed" fits a party House: the humans' mischief can be a changed room. Tune it as two levels, obvious or nearly obvious, never the poster-size kind.

### 2.11 Board games: talk with an eavesdropper
- **Decrypto.** Clues are spoken aloud, so they must be "clear enough for your teammates … obscure enough to baffle your adversaries". Repeated clues leak over time [V-s, [Wikipedia](https://en.wikipedia.org/wiki/Decrypto), [rulebook](https://cdn.1j1ju.com/medias/fb/0d/f3-decrypto-rulebook.pdf)].
- **Captain Sonar.** The enemy's radio operator plots the captain's spoken moves. The real-time mode carries the excitement [V-s, [Tabletop Gaming](https://www.tabletopgaming.co.uk/reviews/captain-sonar-review/)].
- **Magic Maze.** Played in silence with a "Do Something" pawn, plus short talk windows that still cost time. It kills the "alpha leader" problem [V-s, [Opinionated Gamers](https://opinionatedgamers.com/2017/03/15/dale-yu-two-real-time-co-op-games-magic-maze-sit-down-and-dungeon-time-ares/)].
- **Mapping [A].** With proximity voice, any spoken code reaches whoever is near. "The side that talks wins" becomes "the side that talks *carefully* wins": a hidden human nearby hears the code too. That is a tool against the aliens' talk that needs no new rule, only tasks whose codes are worth overhearing.

### 2.12 Other 2024–2026 games (checked live)
- **Dale & Dawson Stationery Supplies** (30 August 2024): slackers must "look busy" while goofing off; proximity voice; 88% positive of 4,596 reviews [V, [Steam](https://store.steampowered.com/app/2920570/), [Wikipedia](https://en.wikipedia.org/wiki/Dale_%26_Dawson_Stationery_Supplies)]. Faking work is itself a task there [A].
- **PEAK** (16 June 2025): four players, a new map every 24 hours, voice that echoes with distance [V-s, [Wikipedia](https://en.wikipedia.org/wiki/Peak_(video_game))].
- **MIMESIS** (Early Access 27 October 2025): keep a tram running while a monster mimics voices; "Three is too few. Five is too many" [V-s, [Vaporlens](https://vaporlens.app/app/2827200/mimesis.md)].
- **Escape Simulator 2** (Steam lists 27 October 2025): co-op for up to 8 [V-s, [Steambase](https://steambase.io/games/escape-simulator-2/info)].
- **Schedule I**: customers judge timeliness, quality and price, and their standards rise by area [V-s, [Destructoid](https://destructoid.com/how-to-reach-friendly-status-with-a-buyer-in-schedule-1)].

## 3. Cross-cutting design questions

### 3.1 Task length targets
- **The evidence.** An Among Us task takes seconds of work, or a 60 s wait (§2.1). An Overcooked level is 2.5–4 minutes of continuous orders (§2.6). Spaceteam gives one instruction at a time (§2.4).
- **Arithmetic for us [A, placeholders].** Take 8 players with 6 aliens, efficiency 0.7, and aim for the work to finish around minute 8 without interference. That is 6 × 0.7 × 480 s ≈ 2,000 player-seconds, against today's 30–52 steps of 8–18 s (≈ 400–700 player-seconds). So the work pool must grow about three to five times. Making each step slower does not get there. Two levers do:
  - a unit of 30–60 s that holds one thinking beat (find, look up, remember or relay);
  - more units in parallel as the player count grows.
- **A unit should still end visibly within a minute.** Spaceteam and Overcooked keep each order short, and the length comes from the stream.

### 3.2 Variety per match
- **Draw the rules each round, not only the layout.** KTANE generates its rules (§2.3). Our herb code is already drawn per round. Each chain should get one such draw: which part the car needs, which switch setting, which shot the photo needs, where the lost items lie.
- **Draw the checklist from a frame.** Phasmophobia posts 3 random objectives (§2.7).
- **Guard against noise.** Avoid fake puzzles and junk props in the House (§2.9) [A].

### 3.3 Scaling with player count
- **Three patterns:**
  - more units per player (Among Us);
  - faster orders (Overcooked, V-s);
  - a different geometry per group size (Big Walk's crane).
- **For us [A].** Scale the *width*: more concurrent orders, more switches and more lost items, with a host setting. Keep each unit's length fixed so a unit feels the same at 4 and at 10. Relay tasks should not need more than 2–3 people at once (Big Walk's cap of four; "Three is too few. Five is too many").

### 3.4 How a task creates conversation
- **Four mechanisms:**
  1. Information sits away from where it is used (escape rooms, KTANE, our herb board).
  2. One person holds the order and another the means (Spaceteam).
  3. A shared stream needs claiming: "I'm on burger 2".
  4. A mistake needs explaining.
- **Muffling walls** (Big Walk) and **an eavesdropper** (Decrypto) make the talk itself the game [A].

### 3.5 Room for covert spoiling that looks like a mistake
- **The precondition is an honest error rate.** LOCKDOWN players swap proteins by accident (§2.2). Overcooked burns things all the time. Without honest errors, every error is a confession [A].
- **The second condition is delayed or ambiguous feedback.** Our red outline appears instantly at the plate, so a wrong herb is caught on the spot. LOCKDOWN's red light shows only at the delivery table, after the work is done (§2.2) [A].
- **The third condition is a deniable story:** "I misheard", "the board said moon". Dread Hunger players advise the traitor cook *not* to poison food, because the trace leads straight to the cook [P, V-s, [TheGamer](https://www.thegamer.com/dread-hunger-thrall-play-guide-winning-tips/)]. A spoil needs more than one plausible author [A].
- **The limit.** Among Us cut "do tasks wrong" as too stressful (§2.1). In a game with meetings it ate the detective time. With us it costs only time, but it must be capped so the aliens do not stop trusting every task [A].

### 3.6 A stream of orders against a fixed list
- **Fixed list** (Among Us, our five chains today). Strength: you can plan, and the task screen reads "2 / 5". Weakness: once planned, it becomes errand-running, and its length is set up front.
- **Stream** (Overcooked, Spaceteam, Schedule I). Strength: never boring, keeps talk going ("who's on the new one?"), and scales with players through its rate. Weakness: needs a visible queue and a clock, and can overwhelm (Spaceteam's four instructions).
- **A hybrid for us [A].** Keep the chains as the goal's backbone, and let a request board feed more units while the match runs, capped at a fixed number open at once.

## 4. Mapping to the five chains and the House

| Chain | Thinking beat today | Proposed beat (original, placeholder) | Covert spoil that looks like a mistake | Scaling lever |
|---|---|---|---|---|
| Delivery | Meaning → place | **Find**: some items start in a pool of plausible House spots (more spots than items); the count is stated on the task screen; fragile items lose a step's worth when dropped hard | "Delivered" to a plausible wrong place; dropped in a fall | Items ∝ aliens (host setting) |
| Generator | Out-of-earshot coordination | **Remember/relay**: the panel shows a per-round setting for each active switch (e.g. one of 3 positions); the runner remembers it or someone relays it over 20–39 m | Sets "the wrong position" ("you said 3!") | 2–4 switches already |
| Cooking | Look up the herb icon | **Stream**: new orders arrive while the match runs, up to K open; the check is deferred to a "serve" step | Wrong herb noticed only when served | Open orders ∝ players |
| Photo | Path over 3 floors | **Brief**: a per-round shot list (how many people, which prop, which pose) posted far from the camera, in the study or the darkroom; checked when hung | A photo-bomb, a wrong prop, a "forgot it said two people" | Photos per round |
| Car repair | Trust at the lift | **Diagnose**: the fitter crawls under and sees a symptom; a chart at the lift panel maps symptom → part; the holder reads it, within voice range but out of sight | The holder "misreads" the chart (the fit is refused: time lost), or lets go | Parts per repair |

[A] The House already places stations so that information and use sit apart (house-map §6). The herb board is 94 m round-trip from the kitchen; the photo path is 118 m. Relay beats should reuse those distances, not add new rooms.

## 5. Cross-game patterns

1. **Information away from its use** (KTANE's casing, escape rooms, our herb board). It is the cheapest beat to add and the one most likely to start talk.
2. **One order per person at a time, with a global clock** (Spaceteam, Overcooked). A list of many at once overwhelms.
3. **Rules drawn each round** beat layouts drawn each round (KTANE, the herb code).
4. **State the count and over-supply the hiding spots** (escape rooms). Finding is the fun; open-ended searching is the chore.
5. **Honest error rates and delayed checks** create deniable sabotage (LOCKDOWN, Overcooked). Instant feedback removes it.
6. **Talk with an eavesdropper** turns talk into a skill (Decrypto, Captain Sonar), and proximity voice gives us that for free.
7. **Scale width, not length** (Overcooked's order rate, Big Walk's tuned puzzles).
8. **Tasks die by repetition and bad teaching** (LOCKDOWN's top complaint; Among Us "monotonous").

## 6. Risks for our design

1. **Too much thinking for a 10-minute action party [A].** KTANE-level manuals break "action over long discussions" and "fun from the first second". Every beat must be readable in under 10 s.
2. **Teaching cost.** LOCKDOWN's silent film failed [V]. Five chains with new beats need on-screen how-to cards and a tutorial pass (`docs/design/tutorial.md`).
3. **The trust collapse.** If spoils are too easy, the aliens double-check everything, and that is the tedium Among Us cut [A].
4. **Search becomes pixel-hunting [A].** Small items in a big, spacious House (#1035) with no count shown are the escape-room trap.
5. **A stream that floods [A].** Without a cap on open orders, 10 players drown in requests (Spaceteam's four-at-once lesson).
6. **The relay needs exactly two people [A].** At 4 players with 3 aliens, a holder-and-fitter beat ties up two thirds of the team.
7. **The balance model's assumptions flip [A].** A stream changes "work done" from a fixed sum to a rate. #1089 must model the cap and the arrival rate, not a step count.
8. **Covert spoils outing the wrong person [A].** A deferred check without any trace punishes the honest cook and is never resolved. The game needs a way to learn who served a plate.

## 7. Options for the engineer (original; every value is a placeholder)

**Option A: Diagnose the car (replaces the wall picture).** Under the raised car the fitter sees one of a few symptoms, drawn each round (a coloured drip, a rattle sound, a bent piece). A chart at the lift panel maps symptom to part. The holder reads the chart; the fitter describes the symptom from under the car.
- Pro: makes the engineer's own "crawl under" idea a talk task in voice range; a human holder can misread deniably; no new room.
- Con: the fitter still goes to storage for the part (54 m, house-map §7), so a unit is about 40–60 s.

**Option B: Generator settings to remember.** Each active switch has a per-round position (one of 3) shown only on the generator panel. A wrong position counts as off.
- Pro: adds "remember" and "relay" to a chain already built for out-of-earshot play; a misset switch is a deniable spoil.
- Con: the panel shows how many switches are on, not which; a fourth beat would need the battery bars to show "right setting" too.

**Option C: A party request board (a stream).** Small requests pulled from the five chains and from cheap errands. At most K open at once (e.g. 2 + players ÷ 3), a new one arriving when one is done, each worth its steps' points.
- Pro: "never boring"; scales with players through K; talk to claim requests.
- Con: a bigger design and engine change; the task screen's per-chain counts (#738) need a new row form; the aliens' goal becomes "N requests" instead of "every chain".

**Option D: Deferred check on burgers.** No green or red outline at the plate. A burger is checked when someone presses "serve", and a wrong one is sent back to be remade. Sounds and a trace say who served it.
- Pro: makes the humans' natural spoil (the wrong herb) worth real time and deniable.
- Con: honest mistakes cost more; the green outline is part of the decided rules today.

**Option E: Lost party things (find).** Each round, some Delivery items start in a random draw from a pool of plausible spots around the House (e.g. 3 spots per item). The task screen states how many are still missing.
- Pro: adds "find" with the escape-room fairness rules; reuses Delivery.
- Con: more art to make hiding spots read clearly; it must stay out of "deduction".

**Option F: A photo brief.** A per-round shot list (how many people, one prop, one pose) posted in the study, far from the camera. A hung photo counts only if it matches the brief.
- Pro: adds a "remember" beat and builds on the engineer's "later: poses or gestures"; a photo-bomb spoil is comic.
- Con: the host must check props and poses in the frame, an engine extension.

**Option G: A balance rule, "scale width, keep the unit".** A design rule rather than a mechanic. A unit is 30–60 s with exactly one thinking beat; the player count changes how many units run in parallel, never how long one takes.
- Pro: gives the #1089 model one parameter per chain.
- Con: it is a constraint; it adds no fun on its own.

**Recommendation [A].** Start with A and B: one beat each, in chains built for it, at no new map cost. Adopt G as the rule that sizes them. Then rerun the balance model with about 45 s units. Pilot D, because it is the cheapest way to give the humans a deniable spoil. Keep C as the long-term direction for "never boring", but only after the first playtest shows whether the fixed chains feel like errands.

## 8. Open questions for the engineer

1. Should every chain get exactly one thinking beat (find, look up, remember or relay), or only some chains?
2. Cooking: keep the instant green or red outline, or defer the check to a serve step (Option D)?
3. A stream of requests (Option C) or fixed chains with more units: which fits "action over long discussions" better in your view?
4. Car repair: is "diagnose under the car" the "more interesting mechanic" you meant, or a step towards it?
5. Teaching: one how-to card per station, a tutorial room, or both?
6. Should a spoken code be worth overhearing (a hidden human hears it and spoils), or should codes stay harmless to overhear?
7. What target time should the #1089 rerun use: aliens finishing at about minute 8 with no interference?

## 9. What I could not verify

- **Not checked:** whether Among Us added tasks in 2024–2026; PlateUp's and Overcooked's exact player scaling; the KTANE GDC talk content (login wall); LOCKDOWN Protocol's full task list after 1.0 (no wiki found). The search budget ran out before the Among Us update check.
- **Search-summary only ([V-s]):** the Among Us task details, the Lethal Company quota formula, the R.E.P.O. team-size scaling, The Exit 8's poster anomaly, and the board-game rules.
- **Third-party and approximate:** the R.E.P.O. haul-goal numbers come from a fan guide.