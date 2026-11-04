# Knödlinger – Game Design Document

*Bis zur Sperrstund'!* · Version 1.1 (co-op added) · 3 Nov 2026

## Pitch and how to use this doc

**Knödlinger is a 3D browser survivors-like where you play the Knödlinger family and your XP rolls behind you as a giant dumpling you can hurl at the horde.** Auto-attacks, hundreds of enemies, a level-up every few seconds, Austrian village apocalypse humour, and one new verb: the Knödl. Solo or online co-op with 1–4 players, where the Knödl becomes a team tool. Built in Godot 4 (GDScript, Compatibility renderer), hosted free on Cloudflare Pages like Berghittn.

For Claude Code: treat this doc as the spec. Build in the milestone order of the last section, keep all balance numbers in data files (not code), and treat every number here as a starting value to tune. Where the doc is silent, pick the simplest option and note it in `DECISIONS.md`. When you need something from me (accounts, assets, a decision), stop and ask clearly.

Glossary for non-Austrian readers: *Knödl* = dumpling, *Brösel* = breadcrumbs, *Spagat* = string (Austrian), *Grant* = grumpiness, *Schmäh* = Viennese wit, *Sperrstund'* = closing time, *Wirt* = innkeeper, *Gemeindeamt* = municipal office.

## Name, premise and tone

**Title: Knödlinger** — subtitle *"Bis zur Sperrstund'!"*. It sounds like a real Austrian surname (Huber, Moser, Knödlinger), carries the Knödl in it, and doubles as the name of the playable family.

**Die Familie Knödlinger.** Every playable character is a Knödlinger, a family that has made Knödl in Unterhinterkogl for generations. Each member brings their own sort of Knödl and their own way of fighting.

- Family business: Gasthaus *Zum Goldenen Knödl*, "seit 1848" (nobody can prove it)
- The secret family recipe is filed at the Gemeindeamt — which is exactly where the portal opened
- Family motto: *"Da Knödl muas rolln."*
- Family feud: the Kommerzialrat thinks he is better than the rest, and the rest agree he is not

**Premise.** At the village Kirtag in Unterhinterkogl, the Bürgermeister stamps the wrong form at the Gemeindeamt and opens a portal to the *Amt der Unterwelt*. Out pour Touristen-Zombies, Gelsen swarms, possessed Akten, Krampusse and worse. Everyone flees — except the Knödlingers, who refuse to leave the Kirtag before their Knödl stand has sold out. Armed with kitchenware, folk instruments and one ever-growing Knödl each, they defend the village until Sperrstund'.

**Humour rules (same spirit as Berghittn):**

1. Joke at Austrian clichés we love: Grant, Bürokratie, Gemütlichkeit, Schmäh, Tourismus, Wirtshaus culture, Pensionisten, Kirtag.
2. In-game text is German with light Austrian dialect, readable for Germans too. Every dialect word gets a tooltip on first use.
3. Item descriptions are one deadpan line, e.g. *Lederhosn: "Hält alles aus. Riecht auch so."*
4. No real people, brands or band names. Generic types only (der Hofrat, die Hausmeisterin, der Skilehrer).
5. Punch up and sideways, never at minorities. Tourists, officials and the player characters themselves are fair game.
6. Barks are short, recorded or TTS, max one per 8 s: *"Heast!"*, *"Geh bitte."*, *"Na servas."*, *"Des is ma wurscht."*

## What the best games in the genre get right

**The genre's hits share one formula: one-stick control, a reward every few seconds, and builds that snowball into screen-filling chaos.** Each standout adds exactly one big idea on top. Knödlinger copies the formula and adds its own one idea (next section).

| Game | Its big idea | What critics praise | What critics dislike | What we take |
| --- | --- | --- | --- | --- |
| [Vampire Survivors](https://www.gamesasylum.com/?p=52010) (poncle, 2022) | Weapon + passive = evolution | Movement plus a single confirm button; [rewards roughly every 23 s](https://jboger.substack.com/p/the-secret-sauce-of-vampire-survivors) | Late-game visual noise | Evolutions, fast level-up cadence, hidden unlocks |
| [Halls of Torment](https://fullcleared.com/reviews/halls-of-torment-review/) (Chasing Carrots, 1.0 Sept 2024) | 90s Diablo look, deep trait tree, items you carry between runs | 900+ traits in up to 5 tiers; almost any build can be made to work; pink/purple marks every enemy attack | [Grindy, basic enemy AI](https://vaporlens.app/app/2218750/halls_of_torment) | Forgiving builds, strict attack colour-coding, quests as achievements |
| [Megabonk](https://pcgamer.com/games/roguelike/megabonk-review) (solo dev, Sept 2025) | Survivors in full 3D with jumping and verticality | [Multi-jumps, route planning over cliffs and ramps](https://www.aol.com/articles/megabonk-quick-review-224852532.html); 10-minute stages where you find a gate and spawn the boss; absurd humour | RNG-heavy pressure, repetitive music | 3D terrain that matters, short stages with a goal, silly tone |
| Brotato (Godot, 2023) | Shop between waves | Short runs, many characters | Arena feels small | Proof that Godot handles the genre |

**Must-have pillars (non-negotiable for v1):**

1. Movement is the only required input; all weapons fire automatically.
2. First level-up within 10 s, then roughly every 15–30 s for the first 5 minutes.
3. Level-up = choose 1 of 3 (reroll, banish, skip available).
4. Focused builds: 2 weapon slots (a 3rd and 4th are unlocked permanently between runs) + 4 stat slots, with open-ended levels; weapon at its evolution level + matching stat = evolution. Items come only from chests and have no slot limit.
5. Enemy count ramps to hundreds; the screen must look overwhelming by minute 10.
6. Every enemy attack is telegraphed in one colour (we use Krampus-red ground decals).
7. Runs of about 15 minutes, ending in a boss and the Sperrstund' wave.
8. Meta currency and unlocks so a lost run still pays out.
9. Quests that unlock content (target 100+ at launch, 300 later).
10. Solo and co-op (1–4 players) are the same game: solo is simply a host with zero clients.

Brotato's engine note is from memory and approximate; all other rows link their source.

## The twist: Da Knödl

**In short: you are not the Knödl.** You play a member of the Knödlinger family, and the Knödl rolls behind you on a string, like a dog on a leash or a flail. Enemies hit *you*; the Knödl only shrinks when Bröselfresser eat from it. It soaks up the Brösel enemies drop (you get the XP, it gets bigger), it flattens whatever it rolls over when you move or turn sharply, and with Schupfn you throw it ahead and reel it back.

**Your XP is not a number in a corner. It is a physical dumpling, tied to you on a string, that grows with every pickup, crushes enemies, and can be thrown, stolen and cashed in.** Think Katamari inside Vampire Survivors. In the genre's best-known titles XP is always banked instantly; here it is a weapon, a shield and a risk at the same time.

### How it works

1. **Brösel instead of gems.** Killed enemies drop Brösel (breadcrumbs). Brösel are absorbed by the Knödl, not by the player. Each Brösel gives XP instantly (the level-up rhythm stays), *and* adds mass to the Knödl.
2. **On the Spagat.** The Knödl rolls behind you on an elastic string (spring joint, rest length 3 m, max 6 m). Moving drags it; turning sharply swings it around you like a flail. No input needed — it is part of movement.
3. **Size = power.** Radius grows with mass: `radius = 0.5 m * (1 + mass/200)^(1/3)`, capped at 4 m. Contact damage = `base * speed * radius`. Big Knödl knocks enemies back and blocks projectiles; it also turns slower and drags you a little.
4. **Schupfn! (one optional button).** Release the string and hurl the Knödl in your movement direction. It rolls freely, flattening everything in its path; downhill it accelerates. Press again to reel it back (1.5 s). Cooldown 4 s.
5. **Knödl at risk.** While detached or hit, it sheds mass. Bröselfresser enemies (Tauben, Wildschweine, hungry Touristen) target the Knödl, not you, and nibble mass off it. Shed mass becomes loose Brösel you can recollect.
6. **Einkehren (cash-in).** 3–4 Wirtshäuser per map. Roll your Knödl into a Wirt's door: it is eaten (*"Mahlzeit!"*) and its mass converts to a reward by size tier — S: gold, M: chest, L: chest + reroll tokens, XL: evolution chest. The Knödl resets to starting size. Each Wirt serves once per run.
7. **The dilemma.** A huge Knödl makes you strong now; cashing it in makes you stronger later but naked for a minute. That push-pull is the decision the genre normally lacks between level-ups.

### Knödl sorts (chosen per character, changeable via unlocks)

| Sort | Feel | Special rule |
| --- | --- | --- |
| Semmelknödl | Balanced starter | None |
| Speckknödl | Heavy, slow, brutal | +40% contact damage, −20% roll speed |
| Marillenknödl | Sweet support | Heals you 1 HP per 25 mass absorbed |
| Germknödl | Bouncy | Bounces off walls and enemies, Schupfn travels 2× farther |
| Kaspressknödl | Flat disc | Skims like a stone, pierces lines of enemies |
| Grammelknödl | Greasy | Leaves a slippery trail that slows enemies |

### Knödl upgrades (items, found only in chests)

- **Bröselbutter** — enemies touching the Knödl stick to it (true Katamari), adding spikes that deal damage; they fall off after 5 s.
- **Powidl-Füllung** — Schupfn ends in an explosion that costs 10% mass.
- **Doppelportion** — a second, smaller Knödl on its own string.
- **Bergab-Gesetz** — +100% speed and damage on slopes.
- **Omas Rezept** — Bröselfresser ignore your Knödl.
- **Knödl-Evolution: Riesenknödl der Apokalypse** — Bröselbutter item + Lederhosn stat at its evolution level: the Knödl never sheds mass and is permanently twice the size.

### Edge cases for implementation

- If the Knödl gets stuck (wall, pit), it auto-returns to the player after 3 s.
- Brösel within 1 m of the *player* are pulled to the Knödl, so you never have to steer the ball onto every crumb.
- If the player dies, the Knödl's current mass is added to meta currency at 25% (a lost run still pays).
- Accessibility option: "Knödl folgt brav" — auto-steer the Knödl toward Brösel clusters.

## Core loop and run structure

**A run is 15 minutes on one map: kill, absorb Brösel, level up every few seconds, decide when to cash in the Knödl, beat the boss at 12:00, survive Sperrstund' at 15:00.**

```
Enemies die ──> Brösel drop ──> Knödl grows + XP ──> Level-up card
    ^   ^                              │                    │
    │   │                   (Bröselfresser shrink it)       │
    │   │                              v                    v
    │   └── Knödl as weapon <─keep it─ Cash in? ─Einkehren─> Stronger build
    │       (Schupfn = more kills)                          │
    └───────────────────────── kill faster ─────────────────┘
```

The classic loop runs along the top; the Knödl adds the second decision underneath: keep a big ball as a weapon, or cash it in at a Wirt for a chest.

### Controls

| Action | Keyboard / mouse | Gamepad | Touch (later) |
| --- | --- | --- | --- |
| Move | WASD | Left stick | Left virtual stick |
| Jump (double jump via upgrade) | Space | A | Right button |
| Schupfn / reel in Knödl | Shift or right click | RB | Second button |
| Pick level-up card | 1/2/3 or click | D-pad + A | Tap |
| Pause | Esc | Start | Pause icon |

Camera: third-person chase cam, about 50° pitch, 14 m distance, follows movement direction with slight lag. Optional free mouse orbit. No manual aiming in v1.

### Run timeline (15:00)

| Time | What happens |
| --- | --- |
| 0:00 | Spawn at the Kirtag stand with 1 weapon and a Semmelknödl |
| 0:00–5:00 | Ramp-up; 30–150 enemies on screen; first Wirtshaus usable |
| 5:00 | Mini-boss (Oberkrampus); drops a chest |
| 5:00–10:00 | Elites with telegraphed attacks; Bröselfresser start hunting the Knödl |
| 8:00 | Event: Touristenbus arrives (wave from one direction) |
| 10:00 | Mini-boss 2; *Formular* appears: collect 3 Stempel on the map to unlock the boss gate (Megabonk-style goal) |
| 12:00 at latest | Boss fight at the Gemeindeamt (forced if gate not opened) |
| 15:00 | Sperrstund': the Wirt with the broom spawns, unkillable, run ends as victory if you survived the boss |

### XP and levelling

- XP needed to go from level n to n+1: `5 + 8*n + 0.4*n^2` (1→2 needs ~13, 20→21 ~325, 50→51 ~1405).
- Brösel sizes: small 1 XP, medium 5, large 25 (elites), golden Kaiserschmarrn bit 100 (bosses).
- Level-up UI is the **Speisekarte**: the Ober presents 3 cards — *"Was darf's sein?"* Buttons: *Nochmal bitte* (reroll, 3 per run), *Des mog i ned* (banish, 3 per run), *Danke, passt eh* (skip, small gold).
- Card pool per level: new weapon (while a weapon slot is free), weapon level, new stat upgrade (while a stat slot is free), stat upgrade level. Nothing else: items come only from chests. Levels are open-ended (Megabonk-style): each card shows its rolled bonus (e.g. *+18 % Schaden*, *+1 Projektil*, *+Fläche*), and rarity (Gewöhnlich, Fein, Edel, Hofratswürdig) scales that bonus; luck stat raises the odds.
- Multiple queued level-ups open one after another. **Solo:** the game is paused during the menu. **Co-op:** the game keeps running; the choosing player stands still under a *"Bin glei wieder da"* sign, is invulnerable and ignored by enemies while the Speisekarte is open (max 8 s per card, then a random card is picked). Their Knödl keeps rolling on its own.

## Content: characters, weapons, passives, enemies, maps

**v1 ships 8 characters, 16 weapons, 14 stat upgrades (passives), about 30 items, 8 evolutions, 14 enemy types, 4 bosses and 3 maps.** All live in `data/*.json` (or Godot `.tres` resources) so Claude Code can add more without touching logic.

### Characters — Die Familie Knödlinger (start unlocked: first 3)

| Character | Role in the family | Start weapon | Knödl | Passive trait |
| --- | --- | --- | --- | --- |
| Onkel Ferdl Knödlinger | Hausmeister, the family Grantler | Schneeschaufel | Semmelknödl | +1% damage per hit taken, max 30% (*Grant*) |
| Oma Resi Knödlinger | Head of the family, keeper of the recipe | Kochlöffel | Marillenknödl | Knödl starts 50% bigger |
| Cousin Toni Knödlinger | Skilehrer, thinks he is a star | Skistöcke | Germknödl | +25% speed on slopes, starts with double jump |
| Herr Poldi Knödlinger | Ober in a Viennese Kaffeehaus | Tablett-Wurf | Semmelknödl | One extra card on every Speisekarte |
| Tante Vroni Knödlinger | Almbäuerin | Kuhglocke | Speckknödl | +20% max HP, regen near cows |
| Sepp Knödlinger | Freiwillige Feuerwehr | Obstler-Flammenwerfer | Grammelknödl | Immune to burn, +area |
| Kommerzialrat Gustl Knödlinger | The black sheep with a title | Stempel | Kaspressknödl | Every 60 s a free banish; enemies sometimes "pause for a coffee break" |
| Kevin Knödlinger | The youngest, Schuhplattler | Watschn-Aura | Germknödl | Every 5th jump creates a shockwave |

### Weapons (auto-fire, open-ended levels with rolled bonuses)

Each character starts with 1 weapon; level-ups level it or offer a new random weapon while a slot is free (2 slots, 3–4 after meta unlocks).

| Weapon | Pattern |
| --- | --- |
| Schneeschaufel | Wide melee arc in facing direction |
| Kochlöffel | Fast melee jabs, high crit |
| Skistöcke | Piercing spears in movement direction |
| Tablett-Wurf | Boomerang tray |
| Kuhglocke | Shockwave ring around player |
| Obstler-Flammenwerfer | Short cone, burn DoT |
| Stempel | Slams *ABGELEHNT* zones on enemies, stuns |
| Watschn-Aura | Damage aura (the famous Austrian slap) |
| Mozartkugel-Orbit | Orbiting chocolate balls |
| Alphorn | Long cone blast, knockback |
| Hagelkanone | Shoots up, hail rains on random targets |
| Schneekugel | Lobbed snow globes, freeze AoE |
| Wiener Würstel | Bouncing chain projectile |
| Zither | Sound waves that ricochet |
| Krampusrute | Chain lightning |
| Sachertorte-Mine | Dropped mines, big splash |

### Stat upgrades / passives (4 slots, open-ended levels with rolled bonuses)

Lederhosn (armor), Gamsbart-Hut (crit), Bergkas (max HP), Brettljause (regen), Kräuterlimo (move speed), Jagatee (damage, slight screen wobble), Pensionistenausweis (cooldown), Wanderkarte (pickup range), Hufeisen vom Kirtag (luck), Krügerl (attack speed), Strickpullover (area), Kaffeehaus-Zeitung (duration), Bausparvertrag (gold gain), Spagat aus Hanf (Knödl string length + reel speed).

### Evolutions (weapon at its evolution level + matching stat upgrade)

| Weapon | + Passive | = Evolution |
| --- | --- | --- |
| Kochlöffel | Brettljause | **Omas Nudelwalker** — spinning rolling pin storm |
| Alphorn | Gamsbart-Hut | **Jodel-Apokalypse** — 360° echo blasts |
| Hagelkanone | Strickpullover | **Jahrhundert-Unwetter** — screen-wide hail |
| Stempel | Pensionistenausweis | **Amtsweg** — enemies are stuck in a 3 s queue |
| Obstler-Flammenwerfer | Jagatee | **Schnapsbrennerei** — burning trail behind you |
| Mozartkugel-Orbit | Kräuterlimo | **Kugel-Karussell** — orbit doubles, spins faster with speed |
| Watschn-Aura | Lederhosn | **Watschn-Baum** — aura reflects damage |
| Knödl | Bröselbutter (item) + Lederhosn | **Riesenknödl der Apokalypse** (see twist) |

### Items: Kirtagsware (chests only)

A third build layer next to weapons and stats, like Megabonk's items: passive gear with special effects, **no slot limit, stacking**, each with a rarity. Items never appear on the Speisekarte; they come only from chests (map chests bought with rising gold prices, free boss chests, Wirtshaus cash-ins). Chest colour shows its rarity; luck raises it. Data-driven like everything else (`data/items/`).

- The Knödl upgrades above are items.
- Some items must cause visible effects (sparks, hail, extra hits), so the screen still fills with chaos at 2 weapons.
- Starting ideas (one deadpan line each, as always): *Zweitschlüssel vom Gemeindeamt* (chance a chest is free), *Sparbuch* (more damage per chest opened), *Glücksschwein* (luck), *Marterl-Kerze* (a revive per run).

### Enemies

| Enemy | Behaviour | Note |
| --- | --- | --- |
| Gelsen | Fast swarm, 1 HP | Fodder from 0:00 |
| Touristen-Zombie | Walks at you, stops to take selfies | Fodder |
| Wühlmaus | Pops out of ground | Ambush |
| Akten-Geist | Floating file, slow | Splits into 3 Formulare |
| Taube | **Bröselfresser**, flies to the Knödl | Knödl threat |
| Wildschwein | **Bröselfresser**, charges the Knödl | Knödl threat |
| Radlfahrer | Telegraphed dash line | Elite pattern |
| Rasenmäher-Roboter | Circles, leaves cut zone | Area denial |
| Perchte | Tanky, ground-slam telegraph | Elite |
| Kampf-Dackel | Small, fast, many | Swarm |
| Schneemann | Lobs snowballs | Ranged |
| Gartenzwerg | Explodes on death | Chain reactions |
| Kontrolleur | Blocks the Wirtshaus door until killed | Knödl cash-in blocker |
| Hungriger Tourist | **Bröselfresser** elite, eats a lot | Knödl threat |

**Bosses:** Oberkrampus (mini, 5:00), Die Lawine (mini, 10:00 on the ski map — a chasing wall you outrun), Der Hofrat der Unterwelt (main boss: stamps ABGELEHNT zones, spawns queues), Der Riesen-Wirt (Sperrstund' entity, unkillable).

### Maps (each about 300 × 300 m, hand-built with random chest/Wirt placement)

1. **Kirtag in Unterhinterkogl** — mostly flat village square with a few raised spots worth climbing to, beer tents, Maibaum in the middle, the family's Knödl stand. Tutorial map.
2. **Gamskogl-Piste** — ski slope with lifts, steep climbs and drops; slopes make the Knödl deadly; Lawine mini-boss.
3. **Gemeindebau-Hof** — Viennese council block courtyard with stairs, balconies and laundry lines; vertical routes over several levels.
4. *(post-launch)* **Heuriger in den Weinbergen** — terraced vineyards; Knödl rolls down terraces.

## Co-op: Familienausflug (1–4 players)

**Up to four Knödlinger play online together; the Knödl turns into a team tool, so co-op is more than four people auto-attacking side by side.** Co-op is its own milestone (M6) after the single-player game is fun, but every system is built co-op-ready from M0.

### Rules

- **Joining:** the host clicks *"Stammtisch aufmachen"* and gets a 4-letter room code (e.g. `KNDL`); friends enter the code. Drop-in only in the Stammtisch hub, not mid-run.
- **Characters:** each player picks a different Knödlinger (no duplicates — *"Es gibt nur eine Oma!"*).
- **Own Knödl, own build:** every player has their own Knödl, own level, own weapons and own Speisekarte.
- **Shared XP:** Brösel go to the Knödl that absorbs them, but every other player within 25 m also gets 50% of that XP (no mass). Nobody falls hopelessly behind.
- **Scaling per extra player:** +60% enemy count, +40% enemy HP, +50% boss HP, +1 Wirtshaus. Numbers live in `balance.tres`.
- **Downed, not dead:** at 0 HP a player is *"umgfoin"* (knocked down) for 30 s. A teammate revives them by standing next to them for 3 s — or instantly by rolling a Knödl over them (*"Aufgweckt!"*). If nobody comes, the player is out until the next Wirtshaus cash-in, which revives everyone. The run ends when all players are down.
- **Camera:** each player has their own chase cam; teammates off-screen are shown with an edge marker.
- **Meta progress:** each player keeps their own Schilling and unlocks; co-op runs pay +10% Schilling per extra player.

### Co-op Knödl moves

| Move | How | Effect |
| --- | --- | --- |
| **Knödl-Pass** | Schupfn toward a teammate | The Knödl rolls through the horde to them; they can catch it and its mass goes to their Knödl |
| **Riesenknödl (merge)** | Two players roll their Knödl into each other | They merge into one huge Knödl held by both strings. Moving apart pulls the strings tight like a clothesline through the enemies. Splits back after 30 s or when one player presses Schupfn |
| **Gemeinsam einkehren** | Cash in a merged Knödl | Reward tier from the combined mass; every player in the merge gets a chest |
| **Knödl-Wache** | — | Bröselfresser make guarding a Knödl a real role: one player defends, the others fight |

### Co-op-only content

- **Quests:** "Revive Onkel Ferdl with a Knödl", "Cash in a merged Riesenknödl of XL size", "Win a run with the whole family" (4 players).
- **Event:** *Familienstreit* — at 7:00 the Kommerzialrat's ghost curses one random player; their Knödl tears loose and rolls away on its own for 10 s, and the other players have to catch it before Bröselfresser eat it.

## Meta progression and difficulty

**Between runs the family sits at the Stammtisch of the Gasthaus Zum Goldenen Knödl: spend Schilling on permanent upgrades, unlock family members through Gemeindeamt quests, and raise the difficulty with Grant levels.** Progress is saved in the browser (`user://` → IndexedDB) with an export/import code so players don't lose it when clearing the cache.

- **Currency: Schilling** (the old Austrian money — a joke older players will love). Earned from gold pickups, Wirtshaus cash-ins and 25% of the Knödl's mass on death.
- **Stammtisch upgrades** (permanent, 5–10 ranks each): max HP, damage, speed, starting Knödl size, rerolls, banishes, luck, weapon slots 3 and 4, revival (*"Nachschlag"*), magnet.
- **Gemeindeamt quests** ("Aufträge"), each one stamped on a form when done: kill 1,000 Gelsen; cash in an XL Knödl; reach level 40 with Oma Resi; beat the Hofrat without Schupfn. Quests unlock characters, weapons, Knödl sorts and maps. Target 100 at launch.
- **Grant levels** (difficulty, like Halls of Torment's Agony mode): Gemütlich (easy) → Normal → Grantig → Hofratsgrant → Weltuntergang. Each adds enemy HP/speed and a modifier (e.g. *Föhn*: wind pushes the Knödl; *Streik*: one Wirtshaus closed; *Kontrolle*: Kontrolleure everywhere). Higher levels multiply Schilling.
- **Almanach**: bestiary and item list that fills as you discover things, each with a deadpan dialect line.
- **Daily Kirtag** (post-launch): seeded daily run with fixed character, local leaderboard.

## Tech: engine, performance, hosting

**Decision: Godot 4 again (latest 4.x stable, at least 4.6), GDScript, Compatibility renderer, single-threaded web export, hosted on Cloudflare Pages.** You already have a working Godot → Cloudflare pipeline from Berghittn, Claude Code can export and test it headlessly, and Brotato proves Godot carries this genre. The real risk is not the engine but browser performance with hundreds of enemies, so milestone 0 is a stress test that decides it.

| Option | Pros | Cons | Verdict |
| --- | --- | --- | --- |
| **Godot 4 (web)** | Editor, scenes, Jolt physics, known pipeline, one codebase for a later Steam build | Web runs on [WebGL2 / Compatibility only](https://forum.godotengine.org/t/godot-4-web-export-issues/49346); engine download is several MB; C# not supported on web | **Use it** |
| Three.js + TypeScript | Tiny download, native web speed, no 25 MiB issue | No editor; you build tooling, UI and physics yourself | Fallback if milestone 0 fails |
| Babylon.js | Strong web engine with inspector and physics | Same "no scene editor" problem; less Claude Code experience in your setup | Not chosen |

### Godot settings that matter for web

- Renderer: **Compatibility** (WebGL2). No Forward+ features, no compute shaders, no SDFGI/volumetric fog.
- Export: **Threads off** (single-threaded, available since 4.3) — no COOP/COEP headers needed, works in Safari and in iframes.
- Language: **GDScript only**. C# is not officially supported for web export.
- Physics: Jolt is the default for new 3D projects since [Godot 4.6](https://app.cinevva.com/news/2026-02-27-godot-4-6-released) and performs better on web than the old backend. Use it only for player, Knödl and terrain — never for enemies.

### Performance architecture (mandatory)

1. **Enemies are data, not nodes.** One `EnemyManager` holds packed arrays (position, velocity, HP, type, state) and renders each enemy type with one `MultiMeshInstance3D`. No `CharacterBody3D` per enemy.
2. **Spatial hash grid** (2 m cells) for separation, contact damage, projectile hits and Knödl collisions. Enemies far from the camera update every 2nd–3rd frame.
3. **Animation in the vertex shader** (waddle, bob, squash) for all fodder. Skeletons only for player and bosses.
4. **Projectiles, Brösel and damage numbers are pooled** and MultiMesh-rendered. Brösel cap 1,500; when exceeded, distant Brösel merge into bigger ones.
5. **Lighting:** one directional light, shadows only for player/Knödl/bosses, blob-shadow decals for enemies, vertex colours instead of textures.
6. **Budgets:** desktop browser 60 fps with 500 enemies + 300 projectiles; mobile browser 30 fps with 200 enemies; < 150 draw calls. An auto-quality scaler lowers enemy cap, shadows and render scale when fps drops below target for 3 s.
7. **Debug overlay** (F3): fps, enemy count, draw calls, frame time per system — Claude Code reads these during automated tests.

### Networking (co-op)

1. **Host-authoritative.** The host simulates the whole world: enemies, Brösel, Knödl physics, bosses, timer, chests, Wirtshäuser, damage. Clients send their input and own movement; the host validates and broadcasts.
2. **Solo = host with zero clients.** All gameplay code goes through a `NetworkManager` autoload from M0 on, even before co-op exists. No gameplay code may assume a single local player.
3. **Enemy sync via snapshots:** because enemies are packed arrays, the host sends compressed snapshots (position as 2×int16 on a grid, type, HP bucket) about 15 times per second on an unreliable channel; clients interpolate. Spawns and deaths as reliable events. Target < 60 KB/s per client at 500 enemies.
4. **Transport:** reuse what Berghittn used for its 1–4 player browser co-op. If starting fresh: Godot's `WebRTCMultiplayerPeer` with a small signaling server on Cloudflare (Worker + Durable Object, free tier) that also hands out room codes. Some players behind strict networks may need a TURN relay — ask before adding anything that costs money.
5. **Local test backend:** a WebSocket backend (`WebSocketMultiplayerPeer`) that runs headless on the PC, so multiplayer can be tested automatically without browsers or the signaling server. Keep it working at all times.
6. **Lobby filter:** room codes and the handshake always carry `game=knoedlinger` and `ver=<version>`; mismatched versions are rejected with a friendly message (*"Eicha Version is ned de gleiche."*).

### Staying under Cloudflare Pages' 25 MiB per file

[Cloudflare Pages](https://developers.cloudflare.com/pages/platform/limits) allows max 25 MiB per file and 20,000 files per site on the free plan. Two files can hit that: the engine `.wasm` and the game `.pck`. In this order:

1. **Reuse the Berghittn solution.** Claude Code should first open the Berghittn repo and copy its build/deploy script as-is.
2. **Keep the `.pck` small by design:** low-poly vertex-coloured models, no large textures, OGG music at 96 kbps, short loops. Target < 15 MiB total.
3. **Slim custom export template** (SCons build profile disabling unused modules and classes). Smaller `.wasm` also means faster loading.
4. **Fallback:** split any file > 24 MiB into parts at build time and reassemble them in a small JS loader before handing them to the Godot engine.

Also: hashed filenames + `_headers` with long cache for `.wasm`/`.pck`, and a loading screen with rotating dialect jokes (*"Der Knödl wird no geformt …"*).

## Art, audio and UI

**Look: bright low-poly "Alpenkitsch" with flat vertex colours — readable in chaos, tiny in file size, and fast in WebGL2.** This is deliberately different from Berghittn's low-res realistic textures, because 500 enemies need silhouettes, not detail.

- **Models:** chunky low-poly, big heads, 200–800 triangles for fodder, up to 5,000 for player and bosses. Start from CC0 packs (e.g. Kenney, Quaternius) and recolour; generate the rest procedurally or with simple Blender exports. The Knödlinger family should share a visual trait (e.g. the same round nose) so they read as one family.
- **Palette:** warm wood, Alpine green, sky blue, Dirndl red-white. All enemy attacks use one danger colour (Krampus red) and nothing friendly may use it.
- **The Knödl** is the hero object: soft shader with breadcrumb texture noise, wobble on impact, visible growth, enemies stuck to it when Bröselbutter is active.
- **VFX:** stylised particles (Brösel sparkle, Watschn hand imprint, Stempel *ABGELEHNT* decal). Option to reduce flashing.
- **Music:** "Volksmusik-Techno" — accordion, tuba and zither over a kick drum, tempo rising with the timer; Sperrstund' track is a slowed-down Schunkel waltz. 3–4 tracks, looped OGG.
- **SFX/voice:** jodel sting on level-up, cash-register *ka-ching* on Einkehren, *"Mahlzeit!"* when the Wirt eats the Knödl, short dialect barks per character.
- **UI:** level-up as a Speisekarte held by Herr Poldi; HUD timer as a Wirtshaus wall clock; XP bar as a filling Krügerl; health as Lebkuchenherzen. Font: a readable sans for numbers, a Fraktur-ish display font only for titles.
- **Language:** German UI with Austrian dialect plus a glossary toggle; strings in a CSV so English can be added later.

## Milestones and instructions for Claude Code

**Build in seven milestones; each ends with a web export deployed to a Cloudflare preview URL and an automated browser check.** Do not start the next milestone until the current one plays well in the browser.

1. **M0 – Stress test (go/no-go for Godot and for co-op).** Flat plane, capsule player, 500 MultiMesh enemies chasing with spatial hash, 300 projectiles. Export, deploy, measure fps in Chrome and Firefox. Pass = 60 fps desktop. Also: one headless client connected through the WebSocket backend receives the enemy snapshots; measure bandwidth and check the client view stays smooth. If fps fails after optimisation, stop and report — we then discuss Three.js. If only the sync fails, report it — the game can still ship single-player.
2. **M1 – Knödl prototype.** Player movement + jump, chase cam, the Knödl on its Spagat, Brösel absorption, size growth, contact damage, Schupfn and reel-in. One weapon, one enemy type. *This milestone decides whether the twist is fun* — tune until it is.
3. **M2 – Core loop.** XP formula, Speisekarte level-up UI, 6 weapons, 6 passives, 2 evolutions, 5 enemy types, Wirtshaus cash-in, Bröselfresser, 15-minute timer with Sperrstund'.
4. **M3 – First full map.** Kirtag map, boss gate with Stempel quest, Oberkrampus and Hofrat bosses, chests, gold, death/victory screens, sound and music pass.
5. **M4 – Meta and content.** First a proper main menu (Spielen, Stammtisch, Aufträge, Rekorde: a global online highscore board (Berghittn's Gipfelbuch on Cloudflare D1) plus own records, player name asked on first start, Almanach, Einstellungen) and a settings page (audio volumes, display, camera, flashing, glossary), then the build rework (2 weapon + 4 stat slots, open-ended levels with rolled bonuses, chest-only items incl. the Knödl upgrades), then Stammtisch hub, Schilling, save/load with export code, all 8 Knödlinger, all weapons/passives/evolutions, quests, Grant levels, maps 2 and 3 (built with Megabonk-style verticality: steep climbs, drops, several levels; no fall damage), and a light verticality pass on the Kirtag map.
6. **M5 – Polish.** Auto-quality scaler, gamepad, remaining options (gamepad, quality, touch), loading screen, balance pass from playtest data, mobile touch controls if fps allows.
7. **M6 – Co-op (Familienausflug).** Signaling server + room codes, WebRTC transport, lobby in the Stammtisch, enemy snapshot sync, revives, shared XP, scaling, Knödl-Pass, Riesenknödl merge, co-op quests and the Familienstreit event. Test with 4 browser tabs and headless clients.

### Working rules

- **Project layout:** `scenes/`, `scripts/systems/` (EnemyManager, SpawnDirector, KnodlController, LevelUp, Save), `data/` (weapons, passives, enemies, characters, waves, quests as JSON or `.tres`), `assets/`, `tests/`, `tools/` (build + deploy scripts).
- **Co-op-ready from M0:** gameplay goes through the `NetworkManager`; the host owns world state; player input is a message, even in solo. Add a `net/` folder (NetworkManager, transports, snapshot code).
- **Data-driven:** every weapon, enemy, wave and quest is a data entry. Adding content must not require code changes.
- **Tests:** unit tests (GUT or gdUnit4) for XP curve, damage formulas, Knödl mass/size, save/load. Run headless on every change.
- **Browser check per milestone:** export → local server → headless Chrome (Playwright) loads the game, plays 60 s with a bot input script, fails on any console error or fps below budget, saves a screenshot.
- **Deploy:** `wrangler pages deploy` to a preview branch per milestone; production only when I say so.
- **Balance log:** a `--autoplay` mode where a bot survives as long as possible and writes run stats (time, level, death cause, Knödl cash-ins) to JSON for tuning.
- **Ask me** for: Cloudflare login/token, any paid asset, voice recordings.

### Open questions

- Which transport did Berghittn use for its browser co-op? Claude Code should check that project first and reuse it.
- TURN relay: only if testing shows players can't connect; it may cost money, so ask first.

## Sources

Search results reviewed on 3 Nov 2026.

- [PC Gamer – Megabonk review](https://pcgamer.com/games/roguelike/megabonk-review)
- [AOL/Quick review – Megabonk movement and routes](https://www.aol.com/articles/megabonk-quick-review-224852532.html)
- [Vaporlens – Megabonk content counts](https://vaporlens.app/app/3405340/megabonk.md)
- [FullCleared – Halls of Torment review](https://fullcleared.com/reviews/halls-of-torment-review/)
- [Vaporlens – Halls of Torment player feedback](https://vaporlens.app/app/2218750/halls_of_torment)
- [The Secret Sauce of Vampire Survivors](https://jboger.substack.com/p/the-secret-sauce-of-vampire-survivors)
- [Games Asylum – Vampire Survivors review](https://www.gamesasylum.com/?p=52010)
- [Cloudflare Pages limits](https://developers.cloudflare.com/pages/platform/limits)
- [Godot 4.6 release summary](https://app.cinevva.com/news/2026-02-27-godot-4-6-released)
- [Godot forum – web export uses Compatibility renderer](https://forum.godotengine.org/t/godot-4-web-export-issues/49346)
- [Godot 4 for web games (dev.to)](https://dev.to/ziva/godot-4-fur-web-spiele-export-wasm-und-browser-performance-4315)
