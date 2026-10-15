# Random events and emergent comedy in a 10-minute hidden-role party

## 0. Scope, tags and what earlier rounds already cover

**Tags.** [V] means verified on the page I fetched. [V, snippet] means the claim comes only from a search-result summary because the page was not fetched or refused the fetch (403). [P] is an opinion from a developer, critic or player. [A] is my analysis. Every number I propose for our game is a **placeholder**.

**What this report builds on.** I read the decided design on `origin/main:docs/design/m8-match.md` (commit 42cb93f19). The local `main` checkout does not have that file yet. I also read the research index and the parts of rounds 1 and 2 that touch this topic. I do not repeat them:
- Phasmophobia's hunt cooldown and smudge timings, Deceit's scheduled blackouts and the Apparatus are in `2026-10-15-sabotage-and-scoring.md` §1.2.
- That report also has Option D (bought global sabotages) and Option F ("House accidents that pay nobody").
- `2026-10-15-win-and-pacing.md` §2.8 and §3 have the midpoint-event deck, the Overcooked 2 recipe change and the pacing table. Round 2 could not verify the L4D Director's phase names. §1.1 below verifies them from Booth's slides.
- `2026-10-15-meta-and-voice-chaos.md` B4 says how funny moments arise in the voice co-op wave.

This report goes deeper on four things: how events are *scheduled and telegraphed*, *NPCs and physics as comedy generators*, *designing for clips*, and *how events interact with the hidden side*.

---

## 1. Event systems: how they work, and what they teach

### 1.1 The Left 4 Dead Director: pacing by measured intensity (now verified)

**How it works.** Booth's GDC 2009 slides ("The AI Systems of Left 4 Dead") are now verified from the PDF text ([slides](https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf)) [V]:
- **Survivor Intensity** is a value per player. It rises "when injured by the Infected, proportional to damage taken", when incapacitated, when pulled off a ledge, and "when nearby Infected dies, inversely proportional to distance".
- It decays toward zero over time, but **not while Infected are actively engaging** that survivor.
- The Director tracks the *maximum* across the 4 survivors.
- **The phases, in Booth's words:** **Build Up** ("create full threat population until Survivor Intensity crosses peak threshold"), then **Sustain Peak** (3 to 5 s more), then **Peak Fade** (minimal threats until intensity decays). Peak Fade exists "so current combat engagement can play out without using up entire Relax period". Then **Relax**: "minimal threat population for 30-45 seconds, or until Survivors have traveled far enough toward the next safe room".
- **Bosses are exempt** from adaptive pacing. The pacing is "affected too much if they are missing", and bosses "are intended to change up the pacing anyhow".
- Spawns use "Structured Unpredictability": "not purely random, nor deterministically uniform". Example: "Mob spawns occur at randomized interval between 90 and 180 seconds", at a spot "behind" the team.
- Several such functions are layered at different frequencies: wanderers high; mobs, specials and scavenge items medium; bosses and weapon caches low.

**Why it works.** Booth writes that static placement "removes suspense of not knowing what will happen next" and produces an "optimal strategy that works every time". Even "multiple sets of manually placed triggers" fail: "if they don't see A, they prepare for B or C" [V, same slides].

**What goes wrong.** An unmeasured Director becomes noise. Valve's own fix was to exempt the big set pieces [V].

**For us.** [A]
- The decided neighbours' anger meter (`m8-match.md` §5) is already a match-state value.
- A tiny "party director" in `core/` can gate *when* random events may fire: never during a chase or the cops' minute, and after a relax window. That is cheap, deterministic with the injected seeded RNG (invariant 3), and keeps "never boring" without stacking chaos on chaos.
- Our "bosses" are the cops' finale and any bought global sabotage. As in L4D, they should be exempt from the director.

### 1.2 Deep Rock Galactic: mutators with hard caps, shown before you commit

**How it works.** A mission has at most two mutators, and at most one of them is an Anomaly ([wiki](https://deeprockgalactic.wiki.gg/wiki/Warning)) [V]:
- In any rotation, exactly one mission can have two warnings.
- Each mission type always has at least one mutator-free mission.
- Warnings pay a Hazard Bonus: Lethal Enemies (melee damage doubled) +25%, Low Oxygen +20%, Haunted Cave +30%, Shield Disruption +30% "but Dwarves take 30% less damage".
- Some pairs are excluded. Core Corruption and Lithophage Outbreak stack with nothing; Low Oxygen never comes with Rich Atmosphere [V].
- Anomalies such as Low Gravity, Gold Rush and Critical Weakness are positive and pay no bonus ([Update 15](https://deeprockgalactic.wiki.gg/wiki/Update_15:_Mutation_Warning)) [V, snippet].

**Why it works.** [A] It is input randomness: you see the warning on the mission board before you pick, so you plan around it. The bonus prices the pain. The "always one clean mission" rule protects players who want the baseline.

**What goes wrong.** [A] Without the exclusion table, two mutators can combine into an unwinnable mission. DRG maintains that table by hand.

**For us.** [A] A per-match "party condition" can be shown in the ship's lobby before landing. Cap it at one or two, with an exclusion table and a "plain party" chance. It costs little because it mostly reweights existing numbers. It fits invariant 4, mechanics as data.

### 1.3 Lethal Company: weather as a visible forecast, lightning with a two-beat telegraph

**How it works.**
- Five base weathers: foggy, rainy, stormy, flooded, eclipsed.
- Each is shown in parentheses next to the moon on the ship's terminal, so you choose with knowledge ([Prima](https://primagames.com/tips/lethal-company-all-weather-conditions-explained)) [V, snippet].
- Eclipsed spawns nocturnal monsters from the start. Flooded water rises over the day [V, snippet].
- In stormy weather lightning prefers players carrying metal items, warned by a flash and "a very loud sound cue right as it's about to hit". Players learn to drop metal scrap and come back for it ([Prima](https://primagames.com/tips/how-to-deal-with-lightning-storm-in-lethal-company)) [V, snippet].
- One guide gives a 1.2x scrap multiplier for stormy weather. I could not verify it ([DungeonPath](https://dungeonpath.com/posts/lethal-company/weather-and-conditions-guide/)).

**Why it works.** [A] The lightning rule turns a hazard into a *decision* (keep the loot or drop it) with a *readable* warning. The comedy comes from the greedy friend who did not drop the brass bell.

**For us.** [A] The best random events change what is smart to carry or where it is smart to stand. Delivery items and the fireworks chain are carried objects already.

### 1.4 PEAK: tornado timing tuned by patch

**How it works.** The first tornado comes 30 to 120 s after its spawner activates, then one every 1 to 5 minutes, each lasting 30 to 120 s ([wiki](https://peak.wiki.gg/wiki/Tornado)) [V]:
- Crouching cuts the pull by 75%. A disabled "Tornado Hell" variant used 0 to 30 s, then 30 to 120 s.
- Patch 1.28.a (2025-09-08) "reduced the maximum time before the first tornado" and "slightly increased the minimum time before another tornado" [V]. The developers moved the first event earlier and spread the rest apart.
- The Final Ascent (11 August 2026) added two biomes and brought the game from about 24,000 to over 120,000 concurrent players ([dlcompare](https://www.dlcompare.com/gaming-news/peaks-final-ascent-sends-player-numbers-soaring-again)) [V]. The article names no new random events.

**For us.** [A] "First event early, then spacing with a floor" is exactly what a 10-minute match needs. Crouch-to-resist is the cheapest counterplay there is: one input, readable, and funny when someone forgets it.

### 1.5 Phasmophobia: clarity beats surprise at the moment of danger

An April 2021 update froze the ghost during a hunt's starting phase and cut that phase from 8 s to 5 s. The stated reason was "to prevent confusion as to when the hunt has actually started" ([Gfinity](https://www.gfinityesports.com/article/phasmophobia-update-april-26-patch-notes-ghost-ability-bug-fixes)) [V, snippet].

[A] Even a horror game, where surprise is the product, chose an unambiguous start signal. A party game needs it more.

### 1.6 Overcooked 2: the level changes under you, but the recipe stays simple

**How it works.**
- Dynamic levels change recipes halfway through. In one, a crashing hot-air balloon restaurant moves you "from making salad to sushi" ([Red Bull](https://www.redbull.com/int-en/overcooked-2-ghost-town-games-interview)) [V, snippet].
- Fire can erupt and spread over wooden floors, and every kitchen has an extinguisher ([Twinfinite preview](https://twinfinite.net/features/overcooked-2-adds-more-spice-yes-online-co-op/), wiki) [V, snippet].
- Duncan: the team keeps recipes "simple enough and the process streamlined enough" that dynamic levels challenge "without feeling overbearing". Early prototypes "allowed too many errors", which frustrated players ([Push Square](https://pushsquare.com/news/2018/08/interview_chewing_the_fat_with_overcooked_2_developer_ghost_town_games)) [V, snippet].
- Each level has separate score boundaries for 1, 2, 3 and 4 players, and a small speed change can force a full rebalance ([Game Developer](https://gamedeveloper.com/design/road-to-the-igf-ghost-town-games-i-overcooked-i-)) [V, snippet].

**For us.** [A] The House's cooking chain already copies Overcooked's spirit. The lesson is that **an event is only affordable if the base task is simple**. If tasks become harder ("find, look up, remember", the engineer's wish), events must touch them lightly, or the two complexity budgets collide. Overcooked's per-player-count scoring is a warning too: our events also need tuning per player count (4 to 10).

### 1.7 Fall Guys: variations, a chaotic-neutral hammer, and the pillars

**How it works.**
- A September 2020 patch added "dynamic variations" of rounds from one playthrough to the next, including new objects ([Gematsu](https://www.gematsu.com/2020/09/fall-guys-ultimate-knockout-mid-season-update-now-available-adds-round-variations-big-yeetus-and-anti-cheating-system-for-pc)) [V, snippet].
- Update 1.23 (May 2021) added 55 more variations across 12 rounds ([MP1st](https://mp1st.com/news/fall-guys-update-1-23-may-13-patch-stumbles-out-for-season-4-5)) [V, snippet].
- Big Yeetus, a giant hammer that appears at random, was billed as "chaotic neutral": it can fling you *ahead* if you line up ([Push Square](https://www.pushsquare.com/news/2020/09/fall_guys_patch_1_07_available_now_on_ps4_adds_big_yeetus_and_other_level_variations)) [V, snippet].
- Mediatonic's round pillars ([blog](https://mediatonicgames.com/blog/behind-the-beans-the-story-of-snowball-survival)) [V]:
  - "80% Skill, 20% Chaos": "Every level should make players feel rewarded for skillful play, while also retaining the sense of chaos".
  - "A Million Slapstick Moments": obstacles "that can create gif-able moments", "every stumble is important!".
  - "It's Only Over When It's Over", citing "a clutch save from Big Yeetus".
  - "Failure should feel fair and deserved."
  - On readability: "the snowballs' path should be readable so that players could tactically react."
- Lead designer Joe Walsh wanted the game "easy to spectate and easy to understand what's going on". Megan Ralph said they "knew it was aiming at streamers" ([Push Square](https://www.pushsquare.com/news/2020/08/interview_fall_guys_devs_on_ps_plus_post-launch_support_and_craig_charles)) [V, snippet].

**What goes wrong.** [P] Some players said a level had been "absolutely ruined" by the hammer, while others asked for "almost uncontrolled chaos" (article comments summarised in [search results](https://www.pushsquare.com/news/2020/09/fall_guys_patch_1_07_available_now_on_ps4_adds_big_yeetus_and_other_level_variations)) [V, snippet].

**For us.** [A] The chaotic-neutral framing is the key idea. A good random event **can help or hurt anyone**, depending on how they position themselves. A neutral event never reads as the game taking sides, and it creates "clutch" stories.

### 1.8 Mario Party: scheduled chaos, catch-up chaos, and NPC moods

**How it works.**
- **The late-game event** (Last Five Turns; Jamboree calls it the Homestretch): Toad announces the standings and doubles Blue and Red Spaces to 12 coins ([MarioWiki](https://www.mariowiki.com/Last_Five_Turns_Event)) [V].
  - One special event follows, "chosen randomly or by a player, except in Pro Rules". Options include double dice, more Chance Time spaces and an extra Star exchange, with some excluded per board [V].
  - In Mario Party 4 to 8 the **last-place player** spins for the rule [V].
- **Board gimmicks on fixed rhythms:**
  - On King Bowser's Keep, every three turns two random spaces become Bowser Spaces ([MarioWiki](https://www.mariowiki.com/King_Bowser's_Keep)) [V, snippet].
  - Waking the Mega Wiggler with a bell "makes them angry", turning lucky spaces on its back into unlucky ones ([Pocket Tactics](https://www.pockettactics.com/super-mario-party-jamboree/boards)) [V, snippet].
- **Chance Time:** three timed wheels pick a giver, an action and a receiver.
  - A 2026 analysis notes that the *threat* changes decisions: a player declined to buy a star while a losing rival was in Chance Time range ([Mechanics of Magic](https://mechanicsofmagic.com/2026/04/07/short-exercise-mda-8-kinds-of-fun-45/)) [V].
  - [P] Critics say a late swing can make "long efforts... erased in an instant" ([ExpertBeacon](https://expertbeacon.com/why-is-mario-party-so-infuriating/)) [V, snippet]. Nintendo offers Pro Rules that remove the random pick [V].

**For us.** [A]
- A fixed *rhythm* (every N turns) with random *content* is the same structure round 2 suggested for the midpoint.
- The Wiggler is a template for a **player-triggered NPC mood shift**: someone deliberately angers an NPC, and the board's rules flip. That is our neighbours' anger with a face.
- Pro Rules are the template for a host setting that turns chaos down.

### 1.9 Hidden-role games: events as cover

**How it works.**
- **Among Us, lights:**
  - Crewmate vision shrinks to a small circle, but Impostors and ghosts are unaffected.
  - The guide notes kills during lights "usually leave no witnesses". Crewmates crowding the panel leaves distant targets alone, and cameras keep full vision ([wiki](https://among-us.fandom.com/wiki/Guide:Sabotage)) [V, snippet].
  - The cooldown of the main sabotages starts only after the fix, about 30 s, and only one major sabotage runs at a time ([wiki](https://among-us.fandom.com/wiki/Guide:Sabotage)) [V, snippet].
- **Among Us, Mushroom Mixup** (The Fungle, v2023.10.24):
  - Everyone gets a random colour and cosmetics, and names are hidden from crewmates for about 10 s. It cannot be repaired, and meetings can still be called ([wiki](https://among-us.fandom.com/wiki/Mushroom_Mixup)) [V, snippet].
  - Impostors still see names [V, snippet].
- **Goose Goose Duck, Ancient Sands:** a recurring outdoor sandstorm "that players can use camouflage in to lose potential pursuers" ([GodisaGeek](https://godisageek.com/2023/01/goose-goose-duck-getting-new-content/)) [V, snippet; the page refused the fetch]. Its timing could not be verified.
- **Project Winter:** a review summary says a snowstorm comes "roughly every five minutes", driving players back to the cabin where they talk [V, snippet; source page refused the fetch]. I found no source saying traitors use storms as cover.

**Why it works.** [A] The event creates an *information asymmetry* (Among Us) or a *symmetric fog* (GGD, Mushroom Mixup) that the hidden side is better placed to use, because it knows its own intent.

**For us.** [A]
- Our pillars say deduction is not central, so cover matters less for surviving a vote and more for *deniability*. "The burger is ruined: was it the grill flare or Kevin?"
- A symmetric event is enough. An asymmetric one, such as humans seeing through a blackout, would break "roles mechanically identical", unless it is a mutation that anyone can buy.
- Mushroom Mixup is the cleanest model: short, unrepairable, symmetric, with no blame.

---

## 2. NPCs that create chaos

### 2.1 Untitled Goose Game: bothering someone whose job is to put up with you

**How it works.**
- House House gave villagers "very limited vision" and "very discrete AI states" (noticing something missing, spotting the goose).
- Gags came from a list of slapstick clichés ("steal someone's glasses, they grope around on the ground for them").
- The conflict "is always easy to read". The goose is "never really that bad", so "no one gets hurt".
- "Playful cruelty is a very easy motivation for players to tap into" ([Game Developer, 17 Feb 2020](https://www.gamedeveloper.com/game-platforms/road-to-the-igf-house-house-s-i-untitled-goose-game-i-)) [V].
- At a Fantastic Arcade talk they said "it's infinitely funnier to bother someone whose job it is to put up with you" ([PCGamesN](https://www.pcgamesn.com/untitled-goose-game-video-pandas)) [V, snippet].

**For us.** [A] This is the neighbours' anger meter in one sentence. The aliens are hosts trying to keep a party going, and the humans are the goose. The neighbour himself is the second victim: he only wants to sleep.

The design lessons:
- **Discrete, readable states** (curtain moves, face at the window, phone in hand) beat a hidden number.
- Mischief is funnier **when the victim is not looking**. That suggests the neighbour notices mischief only through his window's sight line or by ear, which makes geography part of the game.

### 2.2 Item-stealing and mood-flip creatures

- **Lethal Company's Hoarding Bug** collects scrap "in direct competition with you" and carries it to a nest. It is harmless until you take items back from the nest, and you can drop an item to placate it ([Prima](https://primagames.com/tips/how-to-deal-with-hoarding-bugs-in-lethal-company)) [V, snippet].
- **R.E.P.O.'s duck** follows you harmlessly, but grab it and it turns into a biting monster for about 10 s ([Destructoid](https://www.destructoid.com/repo-monster-list/)) [V, snippet]. The Monster Update (30 October 2025) added 10 monsters [V, snippet].

[A] Both creatures are harmless until provoked, and the provocation is a player's choice. That is "randomness with a chance to react" in creature form.

An item-carrying House animal would also produce **free cover**: an item goes missing, and it may have been the animal. But it duplicates the humans' "hide an item" sabotage. It needs a visible tell (a trail, a nest everyone can learn), or it makes the humans' work indistinguishable from noise and kills the "who did it?" joke.

### 2.3 Voice-driven chaos NPCs

- **MIMESIS** (ReLU Games and Krafton, 26 October 2025): monsters copy the voices and behaviour of the players they hide among, and a microphone is required.
- Its major update gave each mimic its own traits so players "can no longer rely on memorized patterns", and replaced the three-day cycle to reduce predictability ([Game Developer](https://www.gamedeveloper.com/press-release/mimesis-major-update-makes-its-ai-driven-monster-more-unpredictable)) [V, snippet; round 2 fetched it].
- **Lethal Company's TZP-Inhalant** raises your voice's pitch as an impairment that grows with use ([Prima](https://primagames.com/tips/what-does-tzp-inhalant-do-in-lethal-company-answered)) [V, snippet].

[A] Voice effects are a cheap, very clip-friendly event class. In a hidden-role game, a pitch-shifted voice also blurs "who said that?", which is cover without lying.

---

## 3. Physics comedy

### 3.1 Evidence

- **Human Fall Flat:** "I had to use procedural animation... no way anyone would agree to motion capture this for me" (Sakalauskas). Each arm reaches where the camera points, and the reviewer says "there's something about the way you move that's just inherently funny" ([bit-tech](https://www.bit-tech.net/previews/gaming/human-fall-flat-preview/1)) [V, snippet]. Its tenth anniversary claims 60 million players ([Game Developer](https://www.gamedeveloper.com/press-release/human-fall-flat-celebrates-10-year-anniversary-alongside-60-million-players)) [V, snippet; title only].
- **Gang Beasts:** physics came first ("if they could get a satisfying punch mechanic, they could build a game around it"), and character design "was largely dictated by the demands of the game's physics" ([bit-tech](https://bit-tech.net/reviews/gaming/pc/interview-gang-beasts/1/)) [V, snippet]. On the Wheel stage, letters fall, the wheel's speed turns erratic and the pier crumbles over the round ([wiki](https://gangbeasts.wiki.gg/wiki/Wheel)) [V, snippet]. It is a *ramping* stage hazard.
- **Goat Simulator:** bugs were "purposefully been left in place", and only crash or freeze bugs were fixed ([Pocket Gamer](https://www.pocketgamer.com/articles/061022/r/)) [V, snippet]. In 2024 Coffee Stain called the "janky physics... unpredictable" part of the appeal ([Epic](https://store.epicgames.com/news/cleaning-up-the-chaos-in-goat-simulator-remastered)) [V, snippet].
- **Party Animals:** the studio's copy says the comedy is the gap between intent and outcome. A punch might "send your foe flying" or "knock your own character completely off balance" ([MassivelyOP](https://massivelyop.com/?p=443908)) [V, snippet].
- **R.E.P.O.:** valuables lose value when damaged (round 1, [Wikipedia](https://en.wikipedia.org/wiki/R.E.P.O.)) [V]. "Everything actually has weight and gravity" ([Tek.no](https://www.tek.no/nyheter/nyhet/i/yErRLr/r-e-p-o-er-den-siste-virale-spillhitten)) [V, snippet].

### 3.2 What this means for a first-person, host-authoritative game [A]

- **Physics comedy needs a third-person view of someone else.** First person hides your own wobble. The joke lives in *watching others*: their capsule landing, their death splat, their fumble. Our plasticine look should squash and stretch *other* players visibly, and our own body should be visible on death (a short third-person beat).
- **Keep gameplay physics simple and authoritative; make comedy physics cosmetic.**
  - Invariant 1 makes the host the authority. Full ragdoll gameplay (Gang Beasts) means syncing many bodies, and its outcome is output randomness, which our "chance to react" pillar dislikes.
  - Human Fall Flat's procedural animation suggests a middle way: the host decides "knocked back 2 m". Each client renders that with its own wobble, jiggle and squash. Clients may differ slightly, and that is fine.
- **Plasticine squash and stretch is a telegraph language.** Classic animation uses squash for weight and anticipation. An object that *inflates and wobbles* before it bursts is a 1 to 2 s warning that reads without UI.
- **No gore, literally built in.** A plasticine death can be a pancake-flat squash that peels back up at the capsule. It is comic, visibly not gore, and a great clip.

---

## 4. Designing for clips and streams

**Evidence.**
- **Fall Guys** made "gif-able moments" a written pillar, and its designer wanted it "easy to spectate" (§1.7) [V].
- **Steam Timeline** (part of Steam Game Recording, out of beta for all users in November 2024 per [AlternativeTo](https://alternativeto.net/news/2024/11/steam-s-native-gameplay-recording-is-out-of-beta-and-available-for-everyone), [V, snippet]):
  - A game can add events with a clip priority: None ("not appropriate as a clip"), Standard ("may want to make a clip"), or Featured ("likely to want a clip"), and "Featured events will be offered before Standard events" ([ISteamTimeline](https://partner.steamgames.com/doc/api/ISteamTimeline)) [V].
  - "Negative times indicate an event that happened in the past", so you can mark a death where its cause began [V].
  - Game phases are "usually 10 minutes to a few hours long" [V], which is our match length.
  - GodotSteam exposes `addInstantaneousTimelineEvent`, `addRangeTimelineEvent`, `startGamePhase`, `addGamePhaseTag` and more, "only available in the main GodotSteam branches" ([GodotSteam](https://godotsteam.com/classes/timeline/)) [V]. Its Godot 4.7 support was not checked.
- **Overwatch's Play of the Game** scores more than kills, including how hard a shot was. Engineers replay finished matches to tune the weights. Kaplan said turret kills and long snipes "were not showing well" in first person, and planned more cinematic framing ([GodisaGeek](https://www.godisageek.com/2016/05/blizzard-planning-improving-overwatchs-play-game)) [V, snippet].
- **TF2's freeze cam** zooms on your killer with their health and nemesis status, and offers an in-game screenshot with a shutter sound. An achievement rewards taunting on someone's freeze cam ([TF2 wiki](https://wiki.teamfortress.com/wiki/Killcam)) [V, snippet].
- **Emotes are few:** Lethal Company ships two (dance, point) ([Dexerto](https://www.dexerto.com/gaming/how-to-use-emotes-in-lethal-company-2399041/)) [V, snippet]. A mod page says R.E.P.O. ships six facial expressions ([Thunderstore](https://thunderstore.io/c/repo/p/Vippy/Wink/)) [V, snippet].

**For us.** [A]
- **Our core already produces the clip log.** Invariant 3 is "commands in, events out". The host's event stream knows every death, mischief, finished chain, meter jump and cops' arrival.
- An end-of-match "party highlights" screen with 3 moments costs mostly UI, not systems. The moments are scored like Play of the Game, filtered per peer (invariant 2), and shown only after the reveal.
- Steam markers can come later, when the Steam transport exists.
- **The decided "a killed alien tells everyone who killed him"** is a freeze-cam waiting to happen: a 1.5 s squashed third-person beat of the killer, then the capsule.
- **First-person framing hides the best moments,** as Overwatch learned. Highlights should be rendered from a third-person replay camera.
- **The photo task is a built-in camera.** Content Warning pays for filmed deaths (round 1). A photo that catches an event, such as the grill flare, could be the funniest proof in the match.

---

## 5. Randomness with a chance to react

**Definitions.** Burgun: output randomness is "noise injected between the player's decision and the outcome", while input randomness "informs the player before he makes his decision". He argues output noise muddies cause and effect, so players blame their own play for losses the dice caused ([Game Developer, 15 Oct 2014](https://www.gamedeveloper.com/design/randomness-and-game-design)) [V]. Input randomness is "more acceptable to experienced gamers" ([Game Developer](https://www.gamedeveloper.com/game-platforms/the-2-types-of-randomness-and-how-to-apply-them-to-your-board-game)) [V, snippet].

**A party game is not a strategy game.** [P] Mario Party defenders argue randomness lets weaker players compete (§1.8). Mediatonic budgets 20% chaos [V]. [A] The pillar "randomness is part of the fun, always with a chance to react" sits between the two camps. Randomness should be mostly input (announced, visible) or **output with a reaction window** (telegraphed, avoidable, fixable).

**A checklist derived from the evidence.** [A]

| Test | Pass | Source pattern |
|---|---|---|
| Announced before it bites? | ≥2 s warning, in sound *and* sight | Lethal Company lightning flash plus sound [V, snippet]; Phasmophobia 5 s start [V, snippet] |
| Is there a counter? | One verb: crouch, drop, fix, move | PEAK crouch −75% [V]; Among Us panel [V, snippet] |
| Neutral? | Can help or hurt either side | Big Yeetus "chaotic neutral" [V, snippet] |
| Bounded? | A duration, a cap, a floor between events | DRG ≤2 [V]; L4D relax 30 to 45 s [V]; Among Us cooldown after fix [V, snippet] |
| Never decides the match alone? | Big outcomes go through player action | Booth exempts bosses [V]; Chance Time criticism [P] |
| Learnable, never memorisable? | A fixed rhythm, random content | L4D "structured unpredictability" [V]; MIMESIS update [V, snippet] |

**Our already-decided randomness, checked.** [A]
- The **random capsule** is output randomness for the dead player, but the 3 s of invulnerability is the reaction window. It passes.
- **The neighbours' anger** must never rise from a random event alone. If an accident (say, a tipped bin) feeds the meter, it should do so only while *nobody fixes it*. The randomness then creates a task, and the players decide the outcome.

---

## 6. How often, and how to telegraph, in a 10-minute match

**Observed rates.**

| Game | Rate or duration | Tag |
|---|---|---|
| L4D mobs | Every 90 to 180 s, random; relax 30 to 45 s after a peak | [V] |
| PEAK tornado | First at 30 to 120 s, then every 1 to 5 min, each lasting 30 to 120 s | [V] |
| Among Us major sabotage | About 30 s cooldown starting after the fix; one at a time; doors lock 10 s | [V, snippet] |
| Mushroom Mixup | About 10 s, cannot be fixed | [V, snippet] |
| Project Winter storms | About 5 min apart | [V, snippet] |
| DRG | ≤2 mutators per mission, at least one clean mission per type | [V] |
| Mario Party | A board gimmick every 3 turns; one late-game event | [V, snippet], [V] |
| Overcooked 2 | One mid-level transformation per dynamic level | [V, snippet] |

**A placeholder budget for our match.** [A]
- **No random event in the first 45 s.** "Fun from the first second" is served by tasks and mischief, which players understand. PEAK's patch moved its *first* hazard earlier, but PEAK has no tasks competing for attention.
- **Small accidents:** 3 to 5 per match, one at a time, at least 60 to 90 s apart. Each gives a 2 to 4 s warning and clears in under 15 s of effort plus travel. That works out to one every 1.5 to 2.5 minutes, between L4D's mobs and PEAK's tornadoes.
- **One "party condition"** per match, announced in the ship before landing, as input randomness. Some matches roll none.
- **The midpoint twist** stays round 2's Option 4, if adopted. It is not counted here.
- **Quiet windows:** no accidents during an active chase, near a fresh respawn, or in the cops' minute. That minute has its own escalation, so it is a boss in L4D terms.
- **Scaling:** at 4 players, a 15 s fix is a bigger share of the team's time than at 10. Fewer accidents or shorter fixes at low counts follows Overcooked's per-count tuning.

**A three-beat telegraph** that suits the plasticine look and proximity voice. [A]
1. **Sound first**, spatialised (a fuse box buzz, a grill hiss). Proximity voice already trains players to listen. Sound is the only cue that goes through walls, and wall muffling makes it a *where* cue.
2. **Squash anticipation:** the object swells and wobbles for 2 to 3 s (placeholder).
3. **The pop**, then a persistent visual state ("broken" pose and colour) that stays until fixed. Latecomers can read what happened.

A HUD marker is only for consequences that matter to a side's goal, like the decided "the neighbours complain about the rubbish".

---

## 7. Events and the hidden side

1. **Cover by deniability.** [A] Accidents that pay nobody (round 2, Option F) mean a failed task is "funny before suspicious". The humans' natural strength, covert spoiling, gains camouflage. But if accidents and sabotage look identical, aliens stop trying to catch saboteurs, and the outing mechanic loses its stakes. Fix: accidents have a **signature** (sound, colour, a smoke puff) that sabotage lacks, and attentive players learn to tell them apart. That rewards macro attention, our pillar.
2. **Cover by fog.** Symmetric fogs (Mushroom Mixup, a sandstorm) help whoever has a plan, and that is usually the hidden side [A]. A short identity blur is the strongest hidden-role event per unit of content. For us it could be visual (everyone's clay looks the same) or vocal (everyone's voice pitch shifted). It needs a filtered event per peer only if it hides *names* (invariant 2).
3. **Opportunities to lie.** "I'll fix the fuse" is the same shape as the decided "I'll stall the cops". Events that need *one* person to go and fix them create cheap promises that a hidden human can break [A].
4. **Exploits to watch.** [A]
   - **Timing exploits:** if accidents are on a fixed clock, humans time their mischief to them.
   - **Blame laundering:** aliens accuse "it was an accident" and stop checking.
   - **Event farming:** if fixing an accident pays points, everyone loiters near accident sites. Round 2 already says accidents pay nobody, and fixes should pay nobody too.

---

## 8. Content cost by event type [A]

| Type | Content | Engineering | Netcode | Notes |
|---|---|---|---|---|
| Rule modifier (party condition) | Low: a name, a lobby card, numbers | Low: a `Resource` that patches rules (invariant 4) | None beyond existing state | Cheapest; needs an exclusion table |
| Station accident (reuses a task station) | Low to medium: one sound, one VFX, a broken pose | Low: a trigger, conditions, effects | One event | Best value; scales with stations |
| Voice event (range or pitch) | Low: audio DSP on the listener | Medium: routing rule in `core/` (invariant 6) | Per-peer routing update | Unique to us; test mic loudness |
| Identity blur | Medium: material swap, name hiding | Medium | Filtered events (invariant 2) | Strong hidden-role effect |
| NPC with states (neighbour, animal) | High: model, animations, sounds, barks | High: navigation, perception, states | Replicated transform plus state | A neighbour at a fixed window is far cheaper than a walking one |
| Physics hazard (gameplay) | Medium | High: host simulation plus correction | Many replicated bodies | Prefer cosmetic physics on top of authoritative outcomes |
| Highlight reel | Low content | Medium: scoring the event log, replay camera | Post-match only | Reuses the core event stream |

---

## 9. Cross-game patterns

1. **A fixed rhythm with random content.** L4D's 90 to 180 s window, Mario Party's every-three-turns gimmick and DRG's rotation all make events learnable but never memorisable [V].
2. **Measure before you spike.** L4D will not spawn threats while intensity is high, and exempts its set pieces [V]. Chaos on top of chaos is noise.
3. **Announce, counter, bound.** Lightning's flash plus sound, Phasmophobia's frozen 5 s start, PEAK's crouch and DRG's caps [V].
4. **Neutral chaos is fair chaos.** Big Yeetus can save you, and weather hits everyone [V, snippet].
5. **Hard caps and a plain option.** At most two DRG mutators and always one clean mission; Mario Party's Pro Rules [V].
6. **Comedy is watching a victim with a job.** The goose's gardener, the Hoarding Bug, the Mega Wiggler's anger [V], [V, snippet].
7. **Physics comedy comes from the gap between intent and outcome**, and is shown from outside the body [V, snippet].
8. **Clip-making is designed in:** gif-able pillars, freeze cams, Featured clip priorities, highlight scoring [V].
9. **Hidden-role events are cover.** Lights, the Mixup and the sandstorm help whoever already has a plan [V, snippet].

## 10. Risks for our design

1. **Two complexity budgets collide.** The engineer wants harder tasks (find, look up, remember). Events on top of those can overload new players, as Overcooked's warning shows [A].
2. **Events decide the humans' win.** A random event that fills the anger meter by itself is output randomness on a win condition [A].
3. **Accidents erase the "who did it?" joke** if they look like sabotage (§7) [A].
4. **First person hides physics comedy.** Without a third-person beat, plasticine squash is invisible to its owner [A].
5. **Gameplay physics versus host authority.** Ragdoll outcomes are costly to sync and feel random. Keep them cosmetic [A].
6. **Voice events and unequal microphones.** Range or pitch events depend on players' gain and hardware. Test with the bots and a real session [A].
7. **Clip features versus filtered information.** A replay or highlight shown before the reveal leaks roles. Highlights must be post-reveal and filtered (invariant 2) [A].
8. **Content creep.** Each NPC is expensive. Start with one stationary neighbour, not a crowd [A].
9. **Repetition.** A fixed event schedule goes stale (MIMESIS, L4D's "prepare for B or C") [V, snippet], [V].

## 11. Options for the engineer to decide

All names, values and examples below are **placeholders** for the engineer. The content area changes only on his word.

**Option 1: A party director in `core/` (pacing only).**
- *Mechanism:*
  - A small state machine (calm, building, peak, cooldown) reads match state: active chases, recent deaths, the meter's rate, the cops' minute.
  - It *permits* accidents only in building, and enforces a floor of 60 to 90 s between them. It blocks accidents in the first 45 s and the cops' minute. It draws from the seeded RNG.
- *For:* L4D's proven structure, deterministic, testable headless, and every other option plugs into it.
- *Against:* invisible to players; tuning effort; a bug here makes the match feel random or dead.

**Option 2: Station accidents with a signature (the first content).**
- *Mechanism:* 2 accidents to start, each on an existing station:
  - the grill flares (extinguish, 5 s);
  - a fuse trips a room's lights (one switch at the panel).
- Three-beat telegraph (§6). They pay nobody, fixes pay nobody, and each has a visible signature that sabotage lacks.
- An accident left unfixed for 30 s may tick the anger meter like ongoing mischief, so the players decide the outcome.
- *For:* the cheapest "randomness with a chance to react"; adds cover without destroying blame; reuses chains.
- *Against:* another rule to explain; tuning per player count; the signature must be learnable.

**Option 3: A face for the neighbours' anger.**
- *Mechanism:* one neighbour at a fixed window or fence with 4 or 5 discrete readable states (asleep, curtain twitch, staring, phone out, dialling). The states mirror the meter's bands.
- Optional: the neighbour notices mischief only along his sight line and hearing range, so where you misbehave matters.
- The decided cake delivery goes to him.
- *For:* the Goose lesson. It makes the meter funny and readable, and costs little (stationary, no navigation).
- *Against:* the sight-line rule adds level-design constraints; art and animation cost; must never become the only way to read the meter.

**Option 4: A party condition announced in the ship.**
- *Mechanism:* before landing, the lobby shows 0 to 1 condition from a small deck. Placeholder kinds: one mischief station is twice as loud; the garden is dark; deliveries weigh more and slow carriers.
- At most one per match in the first version, an exclusion table, and a host toggle ("plain party").
- *For:* pure input randomness (DRG, Lethal Company weather); cheap as rule-patching `Resource`s; variety across matches.
- *Against:* each condition needs balance on both sides; a bad condition spoils a whole match; overlaps with the midpoint twist.

**Option 5: Short symmetric blurs (hidden-role cover).**
- *Mechanism:* a rare, unrepairable 8 to 10 s event. Either everyone's clay turns one colour and names hide, or everyone's voice shifts pitch. Strong telegraph, at most once per match.
- *For:* the strongest cover per unit of content (Mushroom Mixup); the voice variant is unique to our game; a clip machine.
- *Against:* needs filtered events; the voice variant needs DSP on the listener and testing for comprehension; may frustrate chases.

**Option 6: A clip kit from the event log.**
- *Mechanism:*
  - The victim sees a 1.5 s freeze of the killer: a squashed third-person view with the name, already decided as the announcement.
  - The end-of-match screen shows 3 highlights scored from the host's event log (biggest meter jump, a clutch delivery in the cops' minute, the funniest death), from a third-person replay camera, after the reveal and filtered per peer.
  - Later: Steam Timeline markers, Featured for those 3.
- *For:* the moments players share are the game's marketing (Fall Guys, Overwatch); reuses core events.
- *Against:* a replay camera is real work; the scoring weights need tuning; a highlight must never leak a role before the reveal.

**Option 7: Plasticine comedy as cosmetic physics.**
- *Mechanism:* the host decides outcomes (a knockback distance, a death). Clients render them with squash, stretch, jiggle and a pancake death that peels up at the capsule. A rare capsule mishap (a bounce on the roof) has its own 3 s invulnerability window.
- *For:* comic violence without gore; no physics sync; matches the visual identity.
- *Against:* animation-system work; must stay readable in first person; jiggle that differs per client can confuse aim slightly.

**Recommendation.**
1. Build **Option 1 with Option 2's two accidents** first. That is the smallest set that proves "randomness with a chance to react" in the House.
2. Add **Option 3** as the meter's face once the meter exists in play, because it turns a number into a joke.
3. Do **Option 6's** freeze beat early, since it is cheap and decided in spirit. The highlight reel comes later.
4. **Options 4 and 5** wait for the first playtest. Option 4 overlaps round 2's midpoint deck, so choose one of them.
5. **Option 7** belongs to the art and animation track.

## 12. Open questions for the engineer

1. Should random accidents ever touch the neighbours' anger meter, or only player mischief?
2. Must accidents look different from sabotage (a signature), or is full ambiguity the joke you want?
3. Do you want the neighbour as a character (Option 3), and a stationary or a walking one?
4. Is a short identity blur (visual or voice) compatible with "roles private but not protected", or too much protection?
5. A party condition before landing (Option 4) or round 2's midpoint deck: which one first?
6. What is the event budget: how many accidents per match feels "never boring" without noise? (placeholder 3 to 5)
7. A third-person beat on death and on the highlights: acceptable in a first-person game?
8. A host setting for chaos (off, normal, lots), like the weapons presets in `m8-match.md` §7?
9. Should events scale with player count, or stay fixed with tuned fix times?

## 13. What I could not verify

- The timing of Goose Goose Duck's sandstorm and its exact effect: the source page refused the fetch.
- Project Winter's storm interval, and any link between storms and traitor cover.
- Lethal Company's weather scrap multipliers and the exact lightning rules: no official source.
- The Big Yeetus spawn chance, and how often Fall Guys variants appear.
- Valve's Director script default values: the Valve Developer Community page refused the fetch. The phase logic itself is verified from Booth's slides.
- Whether GodotSteam's Timeline functions build against Godot 4.7.2.
- An Untitled Goose Game GDC talk on NPCs: only the Fantastic Arcade quote (via PCGamesN) and the Game Developer interview were found.
- R.E.P.O.'s built-in expression count: from a mod page only.