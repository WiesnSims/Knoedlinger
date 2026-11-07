# Decisions

Every decision and change along the way: what the owner decided, what Claude chose, and why. Newest at the bottom.
GAME-DESIGN.md says what the game is; this file says how we got there and the exact numbers.

## 2026-11-03 – Project start (M0 planning)

- **Owner: co-op transport is Berghittn's WebSocket relay over a Cloudflare Durable Object, not WebRTC.**
  One WebSocket per player to a relay DO per room, reached through a Pages Function on
  `knoedlinger.pages.dev/api/room/<code>`; helper Worker without public route. Proven in Berghittn, 0 € on
  the Workers Free plan, works behind strict NATs without a (paid) TURN relay.
- **Owner: room codes are 4 letters** (Berghittn used 4 digits). Claude: alphabet without the ambiguous I and O.
- **Owner: GitHub repo `WiesnSims/Knoedlinger`** (created private, made **public** by the owner the same day: never commit secrets, tokens or `.dev.vars`); **Cloudflare Pages project `knoedlinger`** on the Berghittn account.
- **Owner: project folder renamed to `Knoedlinger`** (no umlaut, avoids path encoding trouble in PowerShell 5.1 and tools).
- **Owner: test hardware** is an RTX 3080 with a 144 Hz monitor, Microsoft Edge and Firefox (no Chrome), phone Pixel 9 Pro.
  "60 fps desktop" is judged in Edge and Firefox on this machine; browser automation uses Playwright's `msedge` channel.
- **Owner: GUT and Playwright (Chromium/Edge + Firefox) may be installed.**
- **Toolchain:** Godot 4.7.2.stable (official, export templates installed), Node 24.21, wrangler 4.156.2, GUT 9.7.1.

## 2026-11-03 – M0 build (branch m0-stress)

- **Claude: two network backends behind `NetworkManager`.** `ws` = Godot's `WebSocketMultiplayerPeer` with the
  host listening directly (headless tests, `--net=ws --host` / `--join=127.0.0.1`); `relay` = Berghittn's
  `RelayPeer` over the Durable Object for browsers, built in M6. Gameplay only sees `NetworkManager`.
- **Claude: snapshots are sent `unreliable_ordered`** with a sequence number; stale ones are dropped. On a
  WebSocket they still arrive reliably and in order.
- **Claude: snapshot format** = per alive enemy 2×int16 position (1 cm) + 1 byte (type 4 bits | HP bucket 4 bits),
  alive bitmask per slot, deflate-compressed. Measured: ~2.2 KB per snapshot at 500 enemies, **35 KiB/s per client**
  at 15 Hz (budget 60). Clients render 100 ms in the past and interpolate.
- **Claude: SceneMultiplayer `server_relay` is off**; NetworkManager passes player messages on itself (Godot's
  relay announced joins/leaves to sockets that were already closing and logged errors).
- **Claude: projectiles are host-only in M0**; how clients see them is decided in M6.
- **Claude: MultiMesh enemies use instance colours (always white).** Without them the Compatibility renderer in
  Godot 4.7.2 multiplied `COLOR` by stray per-instance data (enemies came out green/yellow).
- **Claude: input actions are registered in code** (`InputSetup`), not as InputEvent blobs in project.godot.
- **Claude: enemy respawn delay 0 and stress fire rate 600/s**, so the stress test really holds 500 enemies and 300 projectiles.
- **Claude: cache headers in M0** = `Cache-Control: no-cache` on everything (ETag revalidation). Hashed file names with
  long caching come in M5.
- **Claude: Pages project created with `--force`** (classic Pages, as in Berghittn; wrangler 4.156.2 otherwise
  delegates to Workers and fails). The first try returned a Cloudflare API 500, the retry worked.
- **Claude: build scripts** are PowerShell (`tools/*.ps1`); the wasm packer is Berghittn's, kept as `tools/pack_wasm.mjs`.
  They use the real `node.exe` (nvm's shim leaves child processes behind) and kill process trees.
- **Measured (local, RTX 3080, frame-rate cap lifted, 500 enemies + 300 projectiles):** Edge 507 fps / p95 2.1 ms,
  Firefox 539 fps / p95 2.1 ms, 22 draw calls. 2000 enemies + 1000 projectiles in Edge: 121 fps / p95 9.5 ms.
  Headless sync: 1 and 3 clients pass (no buffer underruns, no pops, version mismatch refused).
- **Preview deployed** to https://m0-stress.knoedlinger.pages.dev. Measured from the preview (headless, RTX 3080):
  Edge 497 fps / p95 2.1 ms, Firefox 515 fps / p95 2.1 ms, 22 draw calls; 60 s browser check passed with no console errors.
- **Open:** mobile budget (Pixel 9 Pro, `?enemies=200`, 30 fps) is checked by the owner by hand.

## 2026-11-03 – M0 approved, direction for M1

- **Owner: M0 approved**; merged into `main`, branch `m0-stress` deleted.
- **Owner: full 3D traversal like Megabonk, not a top-down game.** The flat plane and high camera were M0 test
  scaffolding only. From M1: jump (double jump via upgrade), slopes, ramps, stairs, ledges, and a third-person
  chase cam whose pitch and distance live in `balance.tres`, tuned in M1 toward a lower, Megabonk-like view.
- **Claude: enemies stay 2D data on 3D terrain.** They move in x/z and take their height from a baked heightmap
  of the map (no physics per enemy); snapshots stay 2×int16, clients sample the same heightmap.

## 2026-11-03 – M1 build (branch m1-knoedl)

- **Claude: the M1 map is a data-driven test field** (`data/maps/testfeld.tres`, 200 x 200 m): heightmap terrain
  (gentle noise, a flat Kirtag square in the middle, hand-placed hills, a bowl, ridges, a mountain rim at the edge)
  plus props as `MapProp` sub-resources: Kirtag stand, Maibaum, beer tents, crates, a 4 m stone plateau with ramp,
  stairs and a lookout on top, a Heustadl with a roof ramp, and a kicker ramp into the bowl. The real Kirtag map is M3.
- **Claude: terrain = 256 x 256 samples** (0.78 m apart). Jolt keeps a `HeightMapShape3D` as a real height field only
  for power-of-two sizes. Props are boxes / convex wedges; stairs collide as a smooth ramp and only look stepped.
- **Claude: enemies and Brösel stand on a baked "ground" field** (terrain plus walkable props, 0.5 m cells),
  sampled bilinearly. Walkers slow down on ground steeper than `enemy_climb_slope` (0.9 rise per metre) and scramble
  up walls at 30 % speed (no safe platforms, no physics per enemy). Enemies only touch a player whose feet are within
  1.6 m of their own (jumping or standing on a ledge keeps you out of reach).
- **Claude: camera** = pitch 30 deg, 11 m, focus 1.6 m above the feet, 70 deg FOV; swings toward the running
  direction (1.4 rad/s, not when running at the camera), Q/E turn it, a click captures the mouse for free orbit (Esc
  lets go). It only collides with the terrain, so props never yank it in front of the player. It backs off 1.6 m per
  metre of Knödl radius. Movement is camera-relative.
- **Claude: jumping** = 9.5 m/s take-off, 26 m/s^2 gravity (about 1.7 m), coyote time and jump buffer 0.12 s.
  `player_jumps` (1) + `CharacterData.extra_jumps` gives the double jump (upgrade, Cousin Toni).
- **Claude: the Spagat is a damped spring in `_integrate_forces`** (28 m/s^2 per metre beyond 3 m, damping 3/s, pull
  only), plus a hard limit at 6 m that removes outward velocity. No Jolt joint: the host simulates every player's
  Knödl and needs full control (reel-in, stuck return).
- **Claude (tuning): `knodl_mass_scale` 50 instead of the design's 200.** With 200 the Knödl grew 1 % in the first
  minute (invisible). Radius stays `0.5 * (1 + mass / scale)^(1/3)`, cap 4 m: 13 mass = 0.54 m, 100 = 0.72 m,
  1000 = 1.38 m, 10000 = 2.9 m. One mass per XP.
- **Claude: Knödl contact** = `1.0 * speed * radius` above 1.5 m/s, 0.3 s per-enemy cooldown, knockback
  `0.9 * speed * radius` (max 14 m/s); the Knödl is solid (enemies are pushed out of it). Schupfn: 18 m/s along the
  running direction + half the player's speed + 2.5 m/s lift; reel-in 1.5 s; cooldown 4 s.
- **Claude: "sheds mass while detached"** = 3 % of its mass per second while thrown, dropped in chunks of about 2 %
  as pale Brösel that give mass but **no XP** (no XP farming by throwing) and cannot be picked up for 1.2 s. The
  design's "or hit" waits for enemies that attack the Knödl (Bröselfresser, M2).
- **Claude: stuck rules** = a thrown Knödl slower than 0.4 m/s for 3 s or further than 45 m is reeled in; an attached
  one more than 7.5 m away for 3 s, or one that fell 12 m below the ground, reappears behind the player.
- **Claude: a big Knödl slows its player** by 12 % per metre of radius above 0.5 m, never below 60 % speed.
- **Claude: Brösel** = pooled packed arrays, one MultiMesh, bob and spin in the shader (lying Brösel cost no CPU and
  the buffer is only re-uploaded when something changed), 20 cm for 1 XP up to 80 cm for 100 XP. Brösel within 1 m
  of a player fly (14 m/s) to that player's Knödl; a Knödl eats what it touches. Pool full: a new Brösel merges into
  the nearest one, so XP is never lost.
- **Claude: M1 weapon** = Onkel Ferdl's Schneeschaufel (140 deg arc, 3.2 m, 3 damage, every 1.1 s, knockback 9).
  M1 enemy = Touristen-Zombie, now in a turquoise holiday shirt (its orange read as Krampus red), 5 contact damage
  per touch, 0.5 s invulnerability, 100 HP. Spawn ramp 20 + 40 per minute, max 300, on a ring 18-28 m out; the first
  wave comes from 9-15 m so the first kills come quickly.
- **Claude: no death screen in M1**: at 0 HP a player is down ("Umgfoin!") for 3 s and comes back at the spawn with
  full HP; their Knödl restarts at its start mass. The death screen and the 25 % meta payout come with M3/M4.
  When every player is down, enemies gather around them.
- **Claude: new data resources** `CharacterData` (Onkel Ferdl), `WeaponData`, `KnodlSortData` (Semmelknödl with
  parsley flecks), `WaveData` (the M1 enemy list), `MapData` + `MapProp`. Spawn and balance numbers stay in
  `balance.tres`.
- **Claude: networking for M1** (co-op-ready, played in M6): the host simulates every Knödl, Brösel, HP and XP. New
  messages: world state (per player HP, XP, level, flags, Knödl pose and mass; 48 bytes per player, 15 Hz, unreliable)
  and Brösel changes (reliable; a joining client gets the full set). `InputMessage` v2 counts Schupfn presses so a
  short press is never lost. A client re-files its local player once the host tells it its peer id (WebSocket
  clients only learn it after connecting). Measured: host + 3 clients, 500 enemies: **38.5 KiB/s per client**.
- **Claude: colours.** The Compatibility renderer lights in linear space but ignores `vertex_color_is_srgb`, so map
  vertex colours are stored linear on the CPU and the enemy/Brösel shaders convert theirs. Filmic tonemapping,
  ambient 0.4, sun 1.0.
- **Claude: physics interpolation is on** (physics at 60 Hz, displays up to 144 Hz). Camera, Spagat and swing effect
  read interpolated transforms; teleports reset the interpolation.
- **Claude: the run is the main scene** (`scenes/boot.tscn` picks `?scene=run|stress`). In a run the bot is off and
  the F3 overlay hidden unless `?bot=1` / `?debug=1`; the automated checks pass `bot=1`. Tuning flags:
  `?knodl_mass=500`, `?god=1`, `?enemies=500`, `?character=ferdl`. Version 0.1.0.
- **Measured (local, RTX 3080, run scene, 500 enemies held, bot playing):** Edge 191 fps / p95 6.8 ms, Firefox
  216 fps / p95 6 ms, 51 draw calls. M0 stress scene unchanged (~460 fps). Map bake 0.3 s in the browser.
- **Preview deployed** to https://m1-knoedl.knoedlinger.pages.dev. Measured from the preview (headless, RTX 3080, run,
  500 enemies, bot): Edge 191 fps / p95 6.6 ms, Firefox 211 fps / p95 6 ms, 51 draw calls; 60 s browser check passed
  with no console errors in both.
- **Open for the playtest:** whether the Knödl is fun (string feel, throw distance, growth speed, drag). The first
  level-up comes after about 20-25 s with the bot (pillar: 10 s), because kills only pay out once the Knödl eats the
  Brösel; XP pacing gets tuned together with the Speisekarte in M2.

## 2026-11-03 – M1 playtest round 1

- **Owner (playtest):** runs fine on the Pixel 9 Pro (no touch controls yet, and none needed now: the phone was only a
  performance check). The Knödl feels good, but it is not really round, worst when big. The camera does not feel
  like Megabonk. Jumping is fine. Climbing looks fine. Enemies sometimes sit somewhere else for a split second.
- **Claude: the enemy "teleports" were an M1 bug.** M1 turned on physics interpolation, and in Godot 4.7 that also
  interpolates every MultiMesh instance between physics ticks by its index. Enemies, Brösel and projectiles are
  repacked into their MultiMesh every frame (dead ones drop out, so the indices shift), so an instance was blended
  between two different enemies for a frame. The pooled renderers now opt out of interpolation (they are redrawn
  every rendered frame anyway); a unit test guards it.
- **Claude: the Knödl was not round** because the sphere had 28 x 14 segments (a 4 m Knödl showed 0.9 m facets)
  and the impact wobble made high-frequency lumps that never settled while it kept eating. Now 64 x 32 segments
  (about 4,000 triangles, inside the hero-object budget) and a gentle jiggle (4.5 %, capped while eating).
- **Claude: camera rebuilt in the Megabonk style.** Sources are thin (no official documentation); what we have:
  Megabonk is third person with the mouse turning the camera, a camera-distance setting, an FOV setting (a settings
  guide recommends 90), "look smoothing", optional camera rotation on arrow keys, and character movement relative to
  the camera. Applied: the mouse always looks (one click captures the pointer, Esc lets go, a hint says so), no
  auto-turn (`camera_auto_turn_speed` 0, still available), pitch 20 deg (mouse 2-70 deg), distance 8 m with mouse-wheel
  zoom 4.5-16 m, FOV 80 (wider shows more but bends a big Knödl at the screen edge), focus 2 m above the feet so the
  player sits a bit below the middle, tight follow (20/s), 0.05 s look smoothing, Q/E still turn it.
- **Claude: with the low camera the Knödl trails toward the lens**, so it dithers away (no transparency sorting)
  when it is within about 2 m of the camera or hides its player (down to 45 %).
- **Answer to "will jumping evolve":** yes, as upgrades in the level-up pool from M2 on: the design's double jump,
  plus a jump-height stat on the same footing as speed, area and the rest (data, not code).

## 2026-11-03 – M1 approved

- **Owner: M1 approved** after the second playtest (Megabonk-style camera, round Knödl, no enemy teleports); merged
  into `main`, branch `m1-knoedl` deleted. Next: M2 (core loop).

## 2026-11-03 – M2 build (branch m2-core)

- **Claude: the build is host state, mirrored in the world state.** `PlayerBuild` (weapons and passives with level
  and rarity bonus, gold, rerolls, banishes) lives in each player's `PlayerState`; the world state (v2) carries it
  as small rows (5 bytes per weapon, 4 per passive), so a client computes the same stats for its own movement and
  shows everyone's weapons from it. Item ids on the wire are indices into `data/catalog/catalog.tres`.
- **Claude: the Speisekarte is a host-driven message flow, also in solo.** The host deals an offer
  (`OfferCodec`, reliable) to whoever has level-ups waiting; the player answers with a choice (pick, reroll,
  banish, skip); the host checks and applies it and deals the next one. Solo (host without clients) pauses the
  game while the menu is open; co-op runs on, the choosing player stands still under a "Bin glei wieder da" sign,
  is invulnerable and ignored by enemies, and after 8 s the host picks a random card. A client joining a paused
  solo game unpauses it.
- **Claude: card pool** = new weapons (while weapon slots are free), weapon levels, new passives (while passive
  slots are free), passive levels and Knödl upgrades, drawn by weight (`card_weight_*`), no item twice, minus
  banished items. A ready evolution is always the first card. When nothing is left: Trinkgeld (gold) and Gulasch
  (heal). Banish removes the item for the run and deals a new menu; reroll deals a new menu; both keep the level-up.
- **Claude: rarity** (Gewöhnlich 70 / Fein 20 / Edel 8 / Hofratswürdig 2, luck multiplies rank k by (1 + luck)^k)
  scales what a level gives: a passive level counts 1.0 / 1.25 / 1.5 / 2.0 times; a weapon level adds
  (bonus - 1) * 30 % damage. Counted stats (extra jumps, Omas Rezept) ignore rarity.
- **Claude: M2 weapons** (8 levels each; damage, fire rate and area grow per level, more pieces at set levels):
  Schneeschaufel (arc, second arc behind from level 5), Kochlöffel (fast narrow arc, 20 % crits x2.5), Skistöcke
  (piercing spears in running direction, more from levels 3/5/7), Kuhglocke (shockwave ring), Watschn-Aura (damage
  aura) and Mozartkugel-Orbit (2 to 5 balls circling). Evolutions: **Omas Nudelwalker** = Kochlöffel 8 + Brettljause
  (4 big rolling pins whose circle breathes in and out) and **Kugel-Karussell** = Mozartkugel-Orbit 8 + Kräuterlimo
  (8 balls, spinning faster with the move-speed bonus). An evolution replaces its weapon in the same slot.
- **Claude: M2 passives** (5 levels unless noted): Lederhosn (+1 armor), Brettljause (+0.25 HP/s), Kräuterlimo
  (+8 % speed), Strickpullover (+10 % area), Pensionistenausweis (+7 % faster attacks), Gamsbart-Hut (+6 % crit),
  Spagat aus Hanf (+15 % string length, reels in faster), Wanderkarte (+30 % pickup range) and **Haferlschuhe**
  (2 levels: +1 jump in the air and +10 % jump height each; the owner's "jumping evolves" answer from M1). Knödl
  upgrade: **Omas Rezept** (Bröselfresser ignore your Knödl). Armor takes its value off every hit, never below 1.
- **Claude: weapon effects need no extra network traffic.** Each weapon has a fire counter in the world state;
  every machine plays the swing, ring, aura pulse or (clients) cosmetic shots when it changes. Orbit pieces are
  placed from the synced run time, so they appear where the host hits with them.
- **Claude: M2 enemies** on the Kirtag timeline (`data/waves/kirtag.tres`): Touristen-Zombie (all run), Gelse (all
  run), Kampf-Dackel (from 1:30), **Taube** (Bröselfresser, flies, 3 mass/s, from 4:00), **Wildschwein**
  (Bröselfresser, 14 HP, 8 mass/s, drops a 5er Brösel, from 5:00) and a tourist surge from 8:00 to 9:00 (a first
  nod to the Touristenbus; the real event comes with M3). The Gelse's head is grey now (it was red, and red is
  reserved for enemy attacks). Crowd: 20 + 35 per minute, max 400. Enemy HP grows 35 % per minute
  (x6.25 at 15:00).
- **Claude: Bröselfresser** steer to the nearest Knödl that is not protected and eat while touching it: half the
  bitten mass is gone, half falls off as loose Brösel (mass only, no XP) that can be collected again.
- **Claude: Wirtshäuser.** The test field has 6 spots (each a house facing the centre, part of the map's collision
  and ground); a run opens 3 at random (+1 per extra player). A Knödl touching the glowing 2.5 m door mat of an
  open Wirtshaus is eaten ("Mahlzeit!"): S (30+ mass) 0.5 gold per mass, M (120+) a chest with 1 item, L (350+)
  a chest with 3 items + 2 rerolls, XL (900+) an evolution chest (a ready evolution first, then up to 5 items).
  Below S the Wirt sends it back. The Knödl restarts at its start size; each Wirt serves once. A HUD marker points
  to the nearest open Wirtshaus.
- **Claude: Sperrstund'.** At 15:00 no more enemies come, the Riesen-Wirt (a 3.5x Wirt with a broom) appears 22 m
  behind the player and sweeps enemies away (no drops), players take no damage, and after 6 s the run ends as a
  win with an end screen (level, kills, gold, biggest Knödl, cash-ins, knock-downs; "Nochmal!" in solo). No boss
  yet (M3), so surviving to 15:00 is the win. Being knocked down still means back at the spawn after 3 s.
- **Claude: first level-up.** 14 crumbs from the family's Knödl stand lie 2.5-6 m around the spawn; rolling over
  them is the first level-up (pillar 2: within 10 s) and shows what the Knödl does.
- **Claude: balance log built in M2** (`tools/autoplay.ps1`): the bot plays whole runs headless at fixed 60 Hz
  steps (about 2 minutes per 15-minute run). The bot picks evolutions first, then its weapons, at random within
  that, and walks its Knödl to a Wirtshaus at L size.
- **Claude: co-op scaling numbers already apply** (+60 % enemy count, +40 % enemy HP, +1 Wirtshaus per extra
  player); shared XP, revives and the Knödl moves stay M6.
- **Claude: a weapon is not offered again once evolved** (found in the balance log: Mozartkugel-Orbit came back
  as a new weapon next to its Kugel-Karussell).
- **Claude: shader warm-up.** WebGL compiles a shader the first time it draws with it; the first ski pole of a
  run stalled the browser for 100 ms. A tiny copy of every effect material is drawn in front of the camera
  during the first 8 frames (`ShaderWarmup`). `?log_slow=1` prints every measured frame over 40 ms.
- **Measured (balance log, 3 bot runs, Onkel Ferdl):** first level-up at 3.2 / 3.4 / 4.2 s, level 10 at about
  1:30-1:45, level 20 at about 4:00, final level 46-54; 29,000-32,000 kills; 3 cash-ins per run (L, once M);
  both evolutions reached in one run; Bröselfresser ate up to 5,155 mass in a run without Omas Rezept. The bot
  (it never dodges) was knocked down 12-26 times per run, the first time around 0:30.
- **Measured (local, RTX 3080, run, 500 enemies held, bot, 60 s):** Edge 186 fps / p95 6.7 ms / max 22.8 ms,
  Firefox 209 fps / p95 6 ms / max 31 ms, 74 draw calls at most. `.pck` 0.30 MiB. Headless co-op: host + 3
  clients pass at 41.4 KiB/s per client, every client levels up through the host's offers.
- **Open for the playtest:** whether the early game is too harsh (the bot goes down every ~30 s in the first
  minutes; tourists hit for 5), whether level-ups come too often (about every 10-15 s early; the design asks
  15-30 s), and whether late enemies are tough enough (HP x6.25 at 15:00; maxed builds still mow everything).
- **Preview deployed** to https://m2-core.knoedlinger.pages.dev. Measured from the preview (headless, RTX 3080, run,
  500 enemies, bot, 60 s): Edge 195 fps / p95 6.5 ms, Firefox 203 fps / p95 7 ms, 76 draw calls at most; browser
  check passed with no console errors in both.

## 2026-11-03 – M2 playtest round 1

- **Owner (playtest):** looks good; the upgrade system should look better: a fitting icon for every upgrade and
  weapon, the description only on hover, clean and modern like other titles. Movement speed could be higher,
  but that can only be judged once the world has its final size.
- **Claude: icons** are a hand-drawn flat SVG set (`assets/icons/`, 20 icons: every weapon, evolution, passive,
  Omas Rezept, Trinkgeld and Gulasch), thick dark outline, warm palette, no Krampus red; referenced as `icon` in
  each `WeaponData` / `PassiveData` (data, not code). About 0.1 MiB in the `.pck`.
- **Claude: Speisekarte redesign.** Dimmed game behind, title "Was darf's sein?" with Herr Poldi as the
  subtitle, dark rounded cards (`UpgradeCard`) with a rarity-coloured border, rarity name, a NEU / STUFE n /
  EVOLUTION badge, a big icon, the name, level pips (owned levels light, the new one in the rarity colour) and the
  key. The one-liner and the stat bonus only appear on hover or keyboard focus (arrow keys, Enter), replacing the
  dimmed icon; the hovered card grows 5 %. Reroll, banish and skip are pill buttons with their key; co-op shows a
  thin time bar. The chest reveal and the end screen use the same style; the chest shows icon tiles.
- **Claude: the HUD build** is now two rows of icon slots (6 weapons, 6 passives, Knödl upgrades after them) with
  the level in the corner, a gold frame when maxed and faint frames for free slots. All icons are packed into one
  atlas texture at run start and the bar is drawn in one pass, so it costs few draw calls; still, the HUD and
  menus raise the count from about 70 to about 90 in play (up to 111 with the menu open; budget 150).
- **Open:** movement speed stays 7 m/s until the real maps (M3/M4) set the world size.
- **Preview redeployed** to https://m2-core.knoedlinger.pages.dev (build a715e9b). From the preview (headless, RTX
  3080, 500 enemies, bot): Edge 186 fps / p95 6.7 ms, Firefox 216 fps / p95 6 ms, draw calls at most 110 / 116;
  no console errors. `.pck` 0.40 MiB.

## 2026-11-03 – M2 approved

- **Owner: M2 approved** after playtest round 1 (icons, hover-only card details); merged into `main`, branch
  `m2-core` deleted. Next: M3 (first full map: Kirtag, boss gate with Stempel quest, Oberkrampus and Hofrat,
  chests, gold, death and victory screens, sound and music). Movement speed is revisited with the real map size.

## 2026-11-04 – M3 build (branch m3-kirtag)

- **Claude: the Kirtag map** (`data/maps/kirtag.tres`, 300 x 300 m, GAME-DESIGN.md map 1) is laid out by
  `tools/maps/make_kirtag.gd` and saved as data. Centre: the gravel Kirtag square with the family's Knödl stand
  (spawn), the Maibaum, two open beer tents with tables, a bandstand, stalls, a fountain. Four roads with ~40
  houses, the Gemeindeamt with the boss gate in the north, the church east, a farm with orchard and a barn whose
  back ramp leads onto its roof south-east, the chapel on its hill south-west, ~90 firs toward the mountains.
  Seven Wirtshaus spots (3 open per run), nine Stempel spots, fourteen chest spots. The test field stays as
  `?map=testfeld`.
- **Claude: buildings are `MapStructure` entries** (house, tent, stall, church, Amt, bandstand, fir, fruit tree,
  Maibaum, Knödl stand, fence, fountain, barn, chapel, crates, bench) that `StructureKit` expands into props.
  New prop kinds: gable `ROOF` and pyramid `SPIRE`; `solid = false` for decoration (windows, tree crowns). Roofs
  are walkable (Megabonk-style routes, e.g. the barn). Paths and the plaza are painted into the terrain colours.
  All props are still one mesh and one draw call.
- **Claude: see-through instead of camera collision** (M2 carry-over "the camera can end up inside props").
  The camera still only avoids terrain; houses, trees and enemies between the camera and the player are
  dithered away in a circle around the player, and anything right at the lens fades out
  (`shaders/world_props.gdshader`, the same uniforms in the enemy shader).
- **Claude: telegraphed attacks are data** (`AttackData`: circle or line, on the target, around the attacker or
  in a ring, telegraph time, damage, cooldown, dash, summons). The host's `HazardField` draws them as Krampus-red
  marks that fill up, then hits everyone inside; jumping higher than 1.1 m over a mark dodges it. Marks reach
  clients as run events.
- **Claude: elites** (GAME-DESIGN.md 5:00-10:00): Perchte (from 5:00; stands still and slams a 3.6 m circle
  around itself) and Radlfahrer (from 6:00; marks a 16 m line toward you, then dashes along it). Both drop a
  25er Brösel and a coin. Akten-Geister (from 10:00, and the Hofrat's summons) split into 3 Formulare.
- **Claude: bosses are enemies in "controlled" slots**, so weapons, the Knödl, snapshots and the renderer need
  nothing new; `BossDirector` moves them and plays their attacks from `BossData`. Oberkrampus at 5:00 (700 HP,
  10 Kampf-Dackel escort; Rute slam, charge with dash, chain ring), the second Kirtag mini-boss at 10:00 is
  **the Oberkrampus again, stronger** (2,200 HP, Perchten escort; the Lawine is the ski map's), the **Hofrat der
  Unterwelt** (6,000 HP; ABGELEHNT stamps, the Warteschlange of Akten-Geister, Dienstweg lines, a ring). Boss HP
  is fixed (not scaled by the clock), +50 % per extra player. A boss drops golden Kaiserschmarrn bits, coins and
  a free boss chest (the Hofrat's gives evolutions first). Bosses are immune to the Riesen-Wirt's broom.
- **Claude: the gate** (Megabonk-style goal): at 10:00 the Formular appears and three Stempel lie at random spots
  (gold light beams, HUD markers); with all three the gate in front of the Gemeindeamt opens and walking in
  brings the Hofrat out. At 12:00 he comes out anyway.
- **Claude: winning and losing.** Sperrstund' with the Hofrat beaten = win ("Gwonnen"); Sperrstund' with him alive
  = "da Hofrat sitzt no in seim Amt" (not a win); knocked down in solo = the run is over (end screen after 2.5 s).
  Co-op until the M6 revives: down for 30 s, then back at the spawn; the run is lost when everyone is down at
  once. `?respawn=1` keeps the M2 rule for the automated checks and the balance log. Schilling and the 25 %
  Knödl payout are saved from M4 on; the end screen shows no Schilling yet.
- **Claude: loot** (`LootField`, host-owned, mirrored by run events): coins (1 gold each; 0.6 % of kills, every
  elite, bosses drop 8 heavy coins), Gulasch (0.15 % of kills, heals 35), Stempel, map chests (6 per run; 25
  gold, +15 for each chest that player opened before; one item) and boss chests (free). Gold so far only buys map
  chests; the rest becomes Schilling in M4. Walking over loot picks it up (no extra button, pillar 1).
- **Claude: the Touristenbus** at 8:00: a coach pulls up near a player and for 45 s the crowd comes from its
  side, 80 enemies more than usual.
- **Claude: run events** (`net/run_event_codec.gd`, reliable): attack marks, loot appearing and taken, toasts,
  bosses arriving and beaten, the bus, sound cues. The host shows its own events through the same code. World
  state v3 adds the Formular, the gate, the result and the focused boss's exact HP (the boss bar).
- **Claude: audio is synthesised** (`tools/audio/make_audio.mjs`, Node + the MIT `wasm-media-encoders` Vorbis
  encoder; no ffmpeg on this machine): "Volksmusik-Techno" for the Kirtag (G major, 128 BPM, accordion with
  musette reeds, tuba oom-pah, zither, kick; speeds up 12 % toward Sperrstund'), a boss track (E minor, 140 BPM,
  Krampus bells), a slowed Schunkel waltz for Sperrstund' (3/4, 80 BPM), and 28 effects (jodel sting on
  level-up from a little formant singer, ka-ching on Einkehren, the stamp, the bus horn ...). 2.4 MiB of OGG.
  **Barks are placeholders** from the Windows Austrian TTS voice ("Microsoft Michael", de-AT): "Na servas!" at
  the start, "Heast!" at low HP, "Geh bitte." when a boss falls, "Des is ma wurscht." on skip, "Mahlzeit!" on
  every cash-in; recordings can replace the files 1:1. `GameAudio` (autoload) limits voices per sound, fades
  placed sounds with distance and keeps barks 8 s apart.
- **Claude: the bot** (automated checks, balance log) now dodges marks, collects Stempel, walks into the gate,
  faces bosses at 2.5 m, picks up boss chests, Gulasch and chests it can afford, and sidesteps and jumps when it
  is stuck on a house (no path finding).
- **Claude: `mp_test.ps1 -StartTime 595`** plays the real timeline from 9:55. With 4 players the crowd is 840
  enemies (+60 % per extra player); clients then get 63.5 KiB/s, above the 60 KiB/s budget, which CLAUDE.md sets
  for 500 enemies (500 held: 37.9 KiB/s). In timeline mode the check scales the budget with the crowd (about
  38 B per enemy per second). Fitting a full 4-player crowd under 60 KiB/s is M6 work.
- **Open: movement speed** stays 7 m/s (the owner wants to judge it on the real map): crossing the playable
  village takes about 35 s.
- **Measured (balance log, 3 bot runs, Onkel Ferdl):** Oberkrampus beaten at 5:27-5:48,
  Oberkrampus II at 13:21-14:38 (he arrives with the Formular, and the bot runs for the Stempel first), Hofrat
  beaten in 1 of 3 runs (WON at 14:32), the other two CLOSED. Bot found 2-3 Stempel. Gold left at the end
  320-680. The bot (no crowd dodging) is first knocked down at 0:33-1:07: **with solo death now ending the run
  this is the main question for the playtest** (knobs: `player_max_hp`, `player_hurt_cooldown`, tourist damage).
- **Measured (local, RTX 3080, run, 500 enemies held, bot, 60 s):** Edge 178 fps / p95 7.4 ms, Firefox 164 fps /
  p95 8 ms, at most 123 draw calls. `.pck` 2.5 MiB (audio ~2.4 MiB). Map bake 0.5 s native. Headless: host + 3
  clients from 9:55 pass (347 run events, 305 marks, all loot on every client).
- **Preview deployed** to https://m3-kirtag.knoedlinger.pages.dev (build 6478e4a). From the preview (headless, RTX 3080,
  500 enemies, bot, 60 s): Edge 192 fps / p95 6.4 ms, Firefox 200 fps / p95 7 ms, at most 120 draw calls; no console
  errors.

## 2026-11-04 – M3 approved

- **Owner: M3 approved** on the first preview; merged into `main`, branch `m3-kirtag` deleted. The open M3
  questions (early-game harshness now that solo death ends the run, boss HP 700 / 2,200 / 6,000, movement speed
  7 m/s, real voice barks instead of the TTS placeholders) stay as they are and are revisited in the M5 balance
  pass or when the owner raises them. Next: M4 (Stammtisch hub, Schilling, save/load with export code, all 8
  Knödlinger, all weapons/passives/evolutions, quests, Grant levels, maps 2 and 3).

## 2026-11-04 – Plan for M4: more vertical maps (not started)

- **Owner (after M3):** the game feels too flat; Megabonk-style verticality (steep climbs, drops) should matter
  more. Planned into M4; M4 itself is not started yet.
- **Owner: no fall damage and no landing shockwave.** Falling from any height is free.
- **Owner: no Knödl-off-a-cliff feature** (e.g. a Schupfn over an edge landing as a bomb): it would only happen by
  accident, not as a choice. The Knödl keeps its current behaviour (it is pulled back to the player when it falls
  too far below the ground or gets stuck).
- **Owner: the Kirtag map gets a little more vertical**, with a light touch: it stays the tutorial map. Plan: a few
  raised spots worth climbing to (e.g. an Alm hill behind the Gemeindeamt with a chest or Stempel on top, a
  terraced edge or riverbank drop), changed in `tools/maps/make_kirtag.gd` and re-baked into `kirtag.tres`.
- **Owner: the focus is on the M4 maps.** Gamskogl-Piste and Gemeindebau-Hof are built tall from the start: steep
  climbs that enemies scramble up slowly (`enemy_climb_slope`), real drops, high ground as a safe-ish route with
  rewards, and several levels of height instead of a single plateau.

## 2026-11-04 – UI pass (branch ui-pass, before M4)

- **Owner: the UI looked bland and overcrowded**; it should be as clean as Megabonk's and Vampire Survivors'
  upgrade screens (references: framed panel with a title bar, inventory left, stats right, rows with icon and one
  stat change; one panel owning the screen, "New!" plus one line). The owner asked for written UI rules, one
  central theme, a Speisekarte redesign, a corner-only HUD, a Stats screen and an Inventory screen, and for every
  future UI to follow the rules and be checked by screenshots (now in CLAUDE.md, "UI rules").
- **Claude: analysis of the old UI** (shown to the owner before the change): everything equally loud (one font
  with the same outline everywhere), about 14 text items on screen at 10:00 (controls help, a Knödl sentence,
  gold, markers), arbitrary offsets and the UI drawn at 720p pixel sizes on a 1080p screen (stretch mode off),
  muddy brown panels and gold used for everything, about 12 font sizes, the card hiding what it changes, almost
  no motion, no inventory or stats overview.
- **Claude: `docs/UI-STYLE.md` is the rulebook**: 8 px grid, 3 font sizes (14 / 20 / 32 at the 1280x720 base),
  Nunito (UI, numbers) + Grenze Gotisch (titles only; GAME-DESIGN.md's "Fraktur-ish display font"), both OFL in
  `assets/fonts/` (0.46 MiB), palette = dark translucent panels `#12141A`, one accent (Knödl gold `#FFC94A`),
  Krampus red `#E5383B` only for danger (enemy attacks, the boss bar, low HP), rarity as border colour only
  (Gewöhnlich grey, Fein green, Edel blue, Hofratswürdig violet; evolutions gold). The old rarity colours were
  grey / blue / violet / gold; gold is now the accent, so the scale moved one step (green added).
- **Claude: one theme, `ui/theme.tres`**, generated by `tools/ui/make_theme.gd`, set project-wide
  (`gui/theme/custom`); nodes choose a `theme_type_variation` (LabelSmall, CardRarity2, BarHp ...), drawn widgets
  read the "Palette" colours. `tests/unit/test_ui_style.gd` fails on any `add_theme_*` override in UI code, on
  more than 3 font sizes and on unknown variations.
- **Claude: the UI scales with the window** (`canvas_items` stretch, `expand` aspect, base 1280x720), so 1080p
  shows the same layout 1.5x bigger instead of tiny.
- **Claude: HUD only in the corners**: health (Lebkuchenherz, bar, number) and the XP Krügerl with the level top
  left; the wall clock (its arc fills toward Sperrstund') top right; the Knödl (disc that grows, mass, Wirtshaus
  tier, Schupfn cooldown ring) bottom right; bottom left stays free for co-op teammates (M6). Temporary only: the
  boss bar and the Formular line top centre, toasts, the chest hint (now with your gold), the controls (first 10 s
  of a run, keycaps), world markers as small pills (the Wirtshaus marker only once the Knödl is worth cashing in,
  tier S+). The build bar, the gold counter and the permanent controls text are gone from the HUD. While a
  full-screen panel is open the HUD steps back.
- **Claude: the Speisekarte is one framed menu card** between the Inventory (left) and Stats (right) panels, like
  Megabonk: rows with a 64 px icon, the name, one change line ("+18 % Schaden" from the real weapon formula
  including rarity, "+1 Stück" at piece levels, "+8 % Tempo", "Neu!", "Evolution!"), level pips and a keycap; the
  border is the rarity. The one-liner, rarity and every number show in a footer on hover/focus, and the stats
  panel shows the new values ("→ +16 %"). Rows fade/scale in 60 ms apart, grow 3 % on hover with a soft
  `ui_hover` tick, the picked row flashes and the menu fades (120 ms); the pick sound got a plate clink. Reroll /
  banish / skip are pills with keycap and count. Arrow keys now walk the rows up and down.
- **Claude: new Inventory / Stats screen on Tab (or I)**: the build as tiles (weapons, passives, Knödl recipes,
  free slots, levels, gold, rerolls, banishes; tooltips with name and level) and every stat in five groups
  (Überleben, Angriff, Bewegung, Knödl, Glück & Gold). It pauses solo games like the Speisekarte; co-op runs on.
  The end screen got the same look (title, one line, numbers as a list, the final build beside it, Enter = again).
- **Claude: in-world signs** (Wirtshaus, gate, bus, "Bin glei wieder da") use the theme's number font; they are
  3D labels, so the theme itself does not reach them.
- **Claude: `tools/ui_shots.ps1`** takes the fixed screenshot set (HUD, busy HUD from 10:00, Speisekarte with a
  hovered row, Tab screen, end screen) at 1920x1080 and 1280x720; `?debug=0` hides the F3 overlay with the bot on.
  Iterated four rounds on the shots (pills overflowing, stats panel overlapping the HUD corners, panels not
  top-aligned, menu wider than the screen) until clean.

## 2026-11-04 – Plan for M4: focused builds and a chest-only item category (not started)

- **Owner: a separate item category that only chests give** (like Megabonk's items, which come from chests, shops
  and shrines while its level-ups only offer weapons and tomes). Working name *Kirtagsware*, data in
  `data/items/`. No slot limit, items stack, each has a rarity; chests show their rarity by colour, luck raises it.
  Sources: map chests (gold, rising price as now), boss chests (free), Wirtshaus cash-ins (M 1 item, L 3 items +
  rerolls, XL ready evolutions first, then items).
- **Owner: the Speisekarte offers only weapons and stat upgrades** (the current passives), with luck-scaled rarity.
- **Owner: 2 weapon slots**, a 3rd and 4th unlocked permanently between runs (Gemeindeamt quest or Stammtisch
  upgrade; exact path chosen when the meta is built in M4). Every character still starts with 1 weapon. Replaces
  the 6 weapon slots of pillar 4.
- **Owner: 4 stat-upgrade slots** (like Megabonk's tomes), replacing the 6 passive slots.
- **Owner: open-ended levels with rolled bonuses** for weapons and stats (Megabonk-style): each card shows what it
  gives (e.g. "+18 % Schaden", "+1 Projektil"), rarity scales the roll. Needed because a run reaches level 46-54
  (M2 balance log): with 2 weapons capped at 8 levels the Speisekarte would run dry around level 35. An evolution
  happens when a weapon reaches its evolution level (a balance number, starting at 8) with the matching stat held.
- **Owner: the Knödl upgrades become items** (Bröselbutter, Powidl-Füllung, Doppelportion, Bergab-Gesetz, Omas
  Rezept). Riesenknödl der Apokalypse = Bröselbutter item + Lederhosn stat at its evolution level.
- **Claude: about 30 items for v1**; some must have visible effects so the screen still gets busy with 2 weapons.
  First ideas: Zweitschlüssel vom Gemeindeamt (chance a chest is free, like Megabonk's Key), Sparbuch (damage per
  chest opened), Glücksschwein (luck), Marterl-Kerze (one revive per run).
- **Claude: build this first in M4**, before the new content, so all 16 weapons, the stats and the items are made
  for the new system. GAME-DESIGN.md (pillar 4, level-up pool, weapons, passives, evolutions, items, Stammtisch,
  M4) is updated to match.
- **Open (not decided):** a stall-owner merchant and Marterl shrines as further item sources (Megabonk's Shady
  Guy, challenge and greed shrines).

## 2026-11-04 – Plan for M4: main menu and settings first (not started)

- **Owner: M4 starts with a proper main menu and a settings page**, before the build rework. Today `boot.tscn`
  goes straight into a run and only the end screen exists.
- **Claude: main menu** = title screen of the Gasthaus Zum Goldenen Knödl ("Knödlinger – Bis zur Sperrstund'!").
  Entries: *Spielen* (character and map choice, then the run), *Stammtisch* (meta upgrades), *Aufträge* (the
  Gemeindeamt quests, done and open), *Rekorde* (highscores), *Almanach* (unlocked and locked characters, weapons,
  stat upgrades, items, enemies, each with its deadpan line), *Einstellungen*, and a greyed-out *Stammtisch
  aufmachen* (co-op) until M6. The screens are built first with what exists and fill up as M4 adds the meta.
  All text through `tr()`.
- **Claude: highscores are local** (in the save, so in the export code too), per character and map: longest
  survival, won runs, highest level, most kills, biggest Knödl, most Schilling from one run. An online leaderboard
  is not planned (it would need a backend; ask first).
- **Claude: settings page** (also reachable from the pause menu during a run), saved in `user://`: volume for
  master, music, effects and voice barks plus mute; fullscreen; camera distance, FOV, mouse sensitivity, invert
  and look smoothing; reduce flashing; show the dialect glossary tooltips; language (German only for now). M5 keeps
  the rest of its "options" item: gamepad, auto-quality and touch settings.
- **Claude: automated checks keep skipping the menu**: any run URL flag or command-line option (`bot=1`,
  `scene=stress`, `autoplay=1`, `--net=...`) still starts the run directly; a plain URL opens the main menu.

## 2026-11-04 – Plan for M4: global highscores and player name (not started)

- **Owner: the Rekorde page shows everyone's highscores online plus your own.** This replaces "highscores are
  local only" from the entry above (the own records stay, local and in the export code).
- **Owner: the player name is asked once on the first start**, saved in `user://`, changeable in Einstellungen;
  the same name is used on the board and later in the co-op lobby.
- **Claude: reuse Berghittn's Gipfelbuch** (`X:\Code\Projects\GeilesGame`, `board/board.js`,
  `functions/api/board/[action].js`, `board/migrations`) as the *Ehrentafel vom Goldenen Knödl*: a Cloudflare D1
  database bound as `BOARD` in the `knoedlinger` Pages project, free tier, no paid service. Preview deployments get
  their own database (`knoedlinger-board-preview`), so play-tests never land on the real board; headless and
  desktop test runs never send results. Its run tickets (asked at run start, used at the end, rate-limited) make
  faked results harder; a browser game cannot stop cheating completely. Names: at most 16 characters, swear words
  folded and filtered (Berghittn's list), fallback name "Knödlinger".
- **Claude: boards** per map and per mode (solo, co-op with all names), all-time and this week, top 50 plus your
  own place. Order: result first (gewonnen > Sperrstund' erlebt > umgfoin), then Grant level, then time, then
  kills. Each entry shows name, character(s), level, kills, biggest Knödl and date. Columns and order can still
  be adjusted in M4.
- **Needs from the owner in M4:** nothing new expected (the Cloudflare login used for deploys can create the D1
  databases); if wrangler lacks the D1 permission, Claude asks.

## 2026-11-04 – UI pass: draw-call fix before the preview

- **Claude: the final browser check failed on draw calls** (max 231, budget < 150; fps was fine at 171).
  Cause: the new Speisekarte UI cost about 105 draw calls on its own (Stats panel 41, Inventory 27, rows 20,
  frame and pills 17), and for about 16 frames after a pick the full HUD came back while the menu was still
  fading out over the running game. In co-op the menu stays open over a live crowd, so this had to be fixed,
  not just tolerated.
- **Claude: fixes** – the HUD stays hidden until the menu has faded out (`Speisekarte.is_shown()`) and
  processes last in the frame, so a panel opened that frame hides it at once; the Stats rows and card titles
  trim with an ellipsis instead of `clip_text` (each clipped label was its own draw call); the Inventory tiles
  are drawn by one `TileGrid` control (frames, then atlas icons, then numbers) instead of a panel, icon and
  label per tile, same look. Result at 1080p: Speisekarte 134 → 96, Tab screen 115 → 69, end screen 72 → 60;
  browser check max 120-134 over two runs (fps avg 175-178).
- **Claude: guard** – `tools/ui_shots.ps1` now fails on any shot at 150 draw calls or more (read from
  `window.knoedlDraws`, which the debug overlay keeps current even while a menu pauses the game), and
  `docs/UI-STYLE.md` got a "Draw calls" section. Open for M6: re-measure a 4-player crowd with a Speisekarte
  open; the rows (about 20 draw calls) can use the same drawn-in-passes trick if needed.

## 2026-11-04 – M4 build (branch m4-meta)

### Part 1: main menu, settings, pause menu

- **Claude: a plain start opens the title screen**, any run option (`bot`, `autoplay`, `net`, `enemies`,
  `character`, `scene` ...; only `mute`, `debug`, `log_slow` are neutral) starts that scene directly as before
  (`boot.gd`), so every automated check is unchanged.
- **Claude: the title screen** shows the Kirtag map slowly turning behind the menu (the same map data and
  builder as the run, no extra assets), the logo and the entries on the left, the chosen screen on the right.
  Entries: Spielen, Stammtisch, Aufträge, Rekorde, Almanach, Einstellungen, Stammtisch aufmachen. The ones
  whose systems come later in M4 (and co-op in M6) are greyed out ("Kummt bald.") until they exist.
- **Claude: Spielen** = character cards with a small drawn portrait (every Knödlinger has the round family
  nose), the chosen one's start weapon, Knödl sort and trait, then the map. What the menus list comes from
  `data/content.tres` (`GameContent`: characters and `MapInfo` entries), so new characters and maps are data.
  The choice goes through `RunSetup`; URL/command-line flags still win.
- **Claude: the logo is drawn** (`TitleLogo`, the title font at 88 px): the one exception to "three font
  sizes", written into docs/UI-STYLE.md, because a title screen with a 32 px logo looks like a dialog.
- **Claude: settings** live in `user://settings.cfg` (`Settings` autoload): volume for everything, music,
  effects and barks (own audio buses) plus mute; fullscreen; camera distance, FOV, mouse speed, look smoothing,
  invert; "Weniger Blitzen" (enemy hit flashes at 35 %); dialect help (stored now, used by the glossary);
  language (German only). Automated runs (headless, `bot`, `autoplay`, `net`) never read or write the file,
  so a player's settings never change a measurement. Sliders and switches are drawn widgets in the palette
  (`UiSlider`, `UiToggle`); the theme got `MenuEntry` and `LineEdit` styles.
- **Claude: the name is asked once** on the first start ("Wia hoaßt'n du?"), at most 16 characters, no
  markup characters, fallback "Knödlinger"; changeable in Einstellungen.
- **Claude: pause menu** on Esc in a run (Weiter, Einstellungen, Zum Menü); solo pauses, co-op runs on.
  The camera no longer frees the mouse on Esc itself: Esc is the pause menu, which frees it. The browser
  swallows the Esc that ends pointer lock, so losing the pointer lock also opens the pause menu. The end screen
  got "Zum Menü" (Esc) next to "Nochmal!" (Enter).
- **Claude: `tools/ui_shots.ps1`** got the `title` set (name prompt, menu, Spielen, Einstellungen, then a run
  started from the menu) and the `pause` set; key steps can be chained (`Escape+Enter`) and text typed
  (`type:Resi`).

### Part 2: the build rework (2 weapons + 4 stat upgrades, open-ended levels, items from chests)

- **Claude: weapon levels are open-ended and every level card rolls one mod** of the weapon's own list
  (`WeaponData.level_mods`): damage, attack rate, area, crit (fractions) or one more piece, drawn by
  `balance.weapon_mod_weights` (damage 3, rate 2, area 2, crit 1.5, piece 1; no piece past `max_amount`). The
  rarity multiplies the roll (x1 / 1.25 / 1.5 / 2; a piece stays one piece below Hofratswürdig). The card says
  what it rolled ("+30 % Schaden", "+1 Stück", "+18 % Angriffstempo"). Formulas: damage x (1 + damage mod) x
  (1 + damage stat); seconds between attacks / (1 + rate mod) x (1 - cooldown stat, at most 60 % off), never
  below 0.08 s; area x (1 + area mod) x (1 + area stat). The old per-level growth and `amount_levels` are gone.
- **Claude: evolution** at `balance.evolution_level` (8) with the partner stat held; the evolution keeps the
  weapon's level and mods and keeps levelling.
- **Claude: stat upgrades** (the passives) have no level cap (`max_level` 0) unless a counted stat needs one;
  4 slots, 2 weapon slots (`PlayerBuild.weapon_slots` / `passive_slots`, so the meta can raise them).
- **Claude: items (Kirtagsware)** are `ItemData` in `data/items/` (listed in the catalog): stats per copy, a
  named effect, a rarity, an optional stack cap, an icon. First 12: Omas Rezept (Knödl, now an item), Haferlschuhe
  (the double jump, now an item, 2 at most), Glücksschwein (luck), Zweitschlüssel vom Gemeindeamt (10 % chance per
  copy that a map chest is free), Sparbuch (+3 % damage per chest opened), Marterl-Kerze (one revive at half HP per
  copy, 2 at most), Lebkuchenherz (max HP), Kirtagsbrezn (regen), Zuckerwatte (speed), Schießbudenrose (crit),
  Goldhaube (gold), Doppler (damage). The Knödl upgrades with their own mechanics (Bröselbutter, Powidl-Füllung,
  Doppelportion, Bergab-Gesetz) and items with visible effects come with the content part of M4.
- **Claude: chests roll a rarity** when they are placed (`chest_rarity_weights` 55/30/12/3, luck raises it like
  card rarity; boss chests and XL cash-ins at least Fein) and give items of that rarity, falling back when the
  player holds every copy there is. A short light column over each chest shows its rarity colour (same colours
  as the UI borders). Map chest 1 item, Wirtshaus M 1, L 3 + rerolls, XL ready evolution first then items, boss
  chests as before.
- **Claude: wire formats** – offers v2 (each card carries its mod and value; chests their rarity), world state
  v4 (weapon rows with level, fire counter and mods, item rows), so clients compute the same stats and show the
  same inventory.
- **Claude: UI** – the Speisekarte rows show the rolled gain and "Stufe n" instead of level pips (pips stay for
  capped stats); the inventory has weapon slots, stat slots ("Verbesserungen") and the Kirtagsware with copies
  in the corner and rarity frames. A chest reveal no longer shows through a Tab screen or pause menu.
- **Claude (tuning): per-level rolls raised 1.5x for damage and rate, 1.2x for area** after the first balance
  log: with 2 weapons instead of 6 the bot only reached 9-12k kills (M3: 29-32k).
- **Measured (balance log, 2 bot runs, Onkel Ferdl, after the tuning):** level 40-45, 9.7k-18k kills, first
  Oberkrampus beaten at 6:50-8:28, Oberkrampus II and the Hofrat not beaten (CLOSED), 22-35 knock-downs (the bot
  never dodges the crowd), builds like Schneeschaufel 17 + Kuhglocke 14, 3-4 stat upgrades, 3-6 items. **Open:**
  the run is clearly harder than in M3; the Stammtisch upgrades and weapon slots 3/4 (next part) are meant to
  close that gap, and the numbers get a proper pass in M5.

### Part 3: meta (Profile, Schilling, Stammtisch, quests, Grant levels, records, Almanach)

- **Claude: the `Profile` autoload** keeps the progress in `user://profile.json` (IndexedDB in the browser):
  Schilling, Stammtisch ranks, stamped quests, lifetime counters, records per character and map, the Grant level
  reached, the last choice in Spielen and what the Almanach has seen. Einstellungen → "Spielstand" copies it as a
  code (`KNDL1.<gzip+base64url>.<check>`) and loads one back (refuses foreign or damaged codes), or starts over
  (asks twice). Automated runs keep it in memory only. An older save is merged onto a fresh one, so new keys
  never break old saves.
- **Claude: Schilling per run** = 0.5 per gold picked up + per cash-in 5 / 15 / 40 / 100 (S..XL) + 100 for a win,
  or 25 % of the Knödl's mass when knocked out (GAME-DESIGN.md), times the Grant level's factor and +10 % per
  extra player. "Zum Menü" from the pause menu pays like being knocked out. The host computes it per player
  (world state v4 carries it to clients for their end screen).
- **Claude: Stammtisch** (10 upgrades, `data/stammtisch/`, `MetaUpgradeData`): Bergkas-Abo (+10 max HP, 10
  ranks), Wetzstein (+5 % damage, 10), Wanderschuhe (+3 % speed, 5), Großer Teig (+25 % start Knödl, 5),
  Nochmal-Zetterl (+1 reroll, 5), Beschwerdeformular (+1 banish, 5), Hufeisen überm Tor (+5 % luck, 5),
  Zweiter Hosensack (weapon slots 3 and 4, 500 / 1,500 S), Nachschlag (a revive per run, 2), Wanderstecken (+10 %
  pickup reach, 5). Prices grow per rank (`cost_base * cost_growth^rank`). Icons reuse the item/stat icons for now.
  **Decided: weapon slots 3 and 4 are a Stammtisch upgrade**, not a quest.
- **Claude: quests** (25 for now, `data/quests/`, `QuestData`): kills per enemy or in total, cash-ins (any, XL),
  level in one run, runs, survive, bosses (Oberkrampus, his second visit, the Hofrat, the Hofrat without a single
  Schupfn), wins, Stempel, biggest Knödl, Schilling earned, items found, a win on Grantig. **Whatever a quest
  unlocks is locked until it is done** (no separate flags): Mozartkugel-Orbit (beat the Oberkrampus),
  Watschn-Aura (level 30), Marterl-Kerze (first win), Sparbuch (10 cash-ins), Zweitschlüssel (9 Stempel),
  Doppler (10,000 kills), Goldhaube (1,000 Schilling). Locked things stay off the Speisekarte and out of chests.
  The count grows to 100 with the content part.
- **Claude: Grant levels** (`data/grant/`, `GrantData`): Gemütlich (HP / damage x0.7, Schilling x0.7), Normal,
  Grantig (HP x1.4, speed x1.1, damage x1.2, Schilling x1.4, Föhn: wind gusts push every Knödl), Hofratsgrant
  (x2 / 1.2 / 1.4 / 2, Streik: one Wirtshaus fewer), Weltuntergang (x3 / 1.3 / 1.7 / 3, Kontrolle: elites twice as
  often until the Kontrolleur enemy exists). Gemütlich and Normal are open; a win unlocks the next level.
  Chosen in Spielen (Q/E); `?grant=<index>` for tests.
- **Claude: co-op and the meta** – each player's Stammtisch bonus is applied per player on the host; the
  local player's comes from the Profile, remote players get none until the M6 lobby sends each player's loadout
  (character and ranks). Unlocks for the shared card pool are the host's.
- **Claude: new menu screens** – Stammtisch (rows with rank and price, Schilling top right), Aufträge
  (forms with a progress ring or the stamp, open ones closest to done first), Rekorde (own records per map and
  character; the online board joins it in the next part), Almanach (Familie, Waffen, Verbesserungen, Kirtagsware,
  Viecher; unknown entries are "???", locked ones name their quest; enemies got a deadpan line each). The end
  screen shows the Schilling and the quests stamped. The menu footer shows the Schilling.

### Part 4: die Ehrentafel (online highscores)

- **Claude: Berghittn's Gipfelbuch reused** as `board/board.js` + `functions/api/board/[action].js` on the
  `knoedlinger` Pages project, D1 databases **`knoedlinger-board`** (production) and **`knoedlinger-board-preview`**
  (previews, `[env.preview]` in the new `wrangler.toml`), created with the deploy login (free tier) and migrated.
  Tickets (asked at run start, used once, 30 per hour per address, 3 h life) and plausibility checks (a run cannot
  be longer than its ticket is old, at most 2,000 + 120 kills per second played per player, a win or a survived
  Sperrstund' means at least 14:50 played).
- **Claude: boards** per map and mode (solo, co-op), all time and this week, top 50. Order: result (gewonnen >
  Sperrstund' erlebt > umgfoin), Grant level, time, kills. Rows: place, name(s), Knödlinger, result and Grant,
  time, level, kills, biggest Knödl; own entries (ids kept in the Profile) in gold. Names: 16 characters,
  Berghittn's swear filter, fallback "Knödlinger".
- **Claude: only real runs count** – started from the main menu, no URL/command-line run options, the Settings
  switch "Ehrentafel mitmachen" on (default on), in the browser (the page's own origin, so previews write to the
  preview database). Headless, desktop and every automated check never send anything (`--board=<url>` for a
  manual test). "Zum Menü" mid-run is not sent. The end screen shows "Ehrentafel: Platz n · diese Woche m".
- **Claude: the local test server** (`tools/browser/serve.mjs`) answers `/api/*` with an "offline" reply, so the
  board shows its offline line there instead of a 404 console error. Board tests: `node --test
  board/test/board.test.mjs` (local D1 via `wrangler pages dev`, 8 tests).

### Part 5: content (the family, weapons, stats, items, Knödl sorts, enemies, quests)

- **Claude: all 8 Knödlinger**, traits as data (`CharacterData`: `trait_stats`, `extra_cards`, `slope_speed`,
  `knodl_start`, named `trait_effects`): Onkel Ferdl (Grant: +1 % damage per hit taken, at most 30 %), Oma Resi
  (Kochlöffel, Marillenknödl, Knödl starts 50 % bigger), Cousin Toni (Skistöcke, Germknödl, +25 % speed on slopes,
  double jump), Herr Poldi (Tablett-Wurf, one more Speisekarte card), Tante Vroni (Kuhglocke, Speckknödl, +20 max HP
  and 0.3 HP/s regen; **the design's "regen near cows" became plain regen**, there are no cows on the maps yet),
  Sepp (Obstler-Flammenwerfer, Grammelknödl, +15 % area; burn immunity waits for something that burns players),
  Kommerzialrat Gustl (Stempel, Kaspressknödl, a free banish every 60 s, every 12 s up to six enemies near him stop
  for a 3 s coffee), Kevin (Watschn-Aura, Germknödl, every 5th jump a shockwave). Ferdl, Resi and Toni are open from
  the start, the other five unlock through quests. InputMessage v3 counts jumps (Kevin's waves are host-side).
  Remote co-op players still play the host's character until the M6 lobby.
- **Claude: all 16 weapons.** New patterns: DROP (impacts on enemies near the player: Stempel stuns, Hagelkanone,
  Schneekugel freezes), MINE (blasts where the player stood: Sachertorte-Mine), CHAIN (jumps from enemy to enemy,
  -15 % per jump: Wiener Würstel, Krampusrute), boomerang shots (Tablett-Wurf), cones as narrow arcs (Obstler sets
  on fire, Alphorn pushes hard), Zither as a wide fan of piercing waves. Enemies got status effects (slow/freeze/
  stun and burn as packed arrays; bosses feel a third of a slow and never stop). The host draws the real impacts;
  clients draw the same kind of picture from the fire counter (cosmetic), so no new network traffic.
- **Claude: all 8 evolutions**: Omas Nudelwalker and Kugel-Karussell (M2), Jodel-Apokalypse (Alphorn + Gamsbart-Hut,
  big knockback ring), Jahrhundert-Unwetter (Hagelkanone + Strickpullover, hail over 30 m), Amtsweg (Stempel +
  Pensionistenausweis, 3 s stamps), Schnapsbrennerei (Obstler + Jagatee, a burning trail of small blasts),
  Watschn-Baum (Watschn-Aura + Lederhosn, bigger aura with knockback; **the reflected damage is not built yet**),
  and the Riesenknödl stays a Knödl item for later (see below).
- **Claude: all 14 stat upgrades**: new Bergkas (max HP), Jagatee (damage; the screen wobble is left out), Hufeisen
  (luck), Krügerl (attack speed, a new `rate` stat), Kaffeehaus-Zeitung (`duration`: shots fly longer, burns and
  slows last longer), Bausparvertrag (gold).
- **Claude: 30 items**: 13 more stat items, and with effects Bröselbutter (whatever touches the Knödl takes damage
  every second), Powidl-Füllung (a blast when a Schupfn ends, costs 10 % mass), Bergab-Gesetz (+100 % Knödl damage
  rolling downhill), Schweizerkracher (8 % per copy that a kill blows up), Kirchenglocke (a ring every 10 s).
  **Not built: Doppelportion (a second Knödl) and the Riesenknödl der Apokalypse evolution**; both need a second
  Knödl body or a size rule across the network and are left for M5/M6.
- **Claude: all 6 Knödl sorts**: Speck, Marillen, Germ (as in the design), Kaspressknödl (a flat disc that cuts
  through enemies instead of pushing them aside), Grammelknödl (its greasy trail slows enemies to 50 %).
- **Claude: 6 new enemies (17 in all incl. Formular and the bosses)**: Wühlmaus (pops up 4-7 m from a player),
  Rasenmäher-Roboter (circles at 7 m, cuts a marked circle around itself), Schneemann (keeps 9 m away, lobs
  snowballs; on the ski map), Gartenzwerg (explodes where it falls, marked), Kontrolleur (from 4:00 one stands at
  every open Wirtshaus, which serves nobody until he is beaten: "Kontrolle!"), Hungriger Tourist (Bröselfresser
  elite, 20 mass/s). Each wave may list 16 types (4 bits in snapshots), now checked per wave.
- **Claude: 101 quests** (the design's target of 100); everything new that is not a start pick is unlocked by one.
- **Claude: `?weapons=a,b` / `--weapons=`** gives extra weapons at the start (testing; ignores locks and slots).
- **Measured (local, RTX 3080, run, 500 enemies, bot, 60 s, Edge):** 157 fps avg, p95 7.8 ms, at most 128 draw calls.

### Part 6: maps (Gamskogl-Piste, Gemeindebau-Hof, Kirtag verticality)

- **Claude: terrain for tall maps** – `MapData.tilt` (the whole map leans: a ski slope) and `mesas` (plateaus with
  a steep edge of `mesa_edge` metres; stacked ones make several levels and real drops). Each map names its own
  `wave` (enemies, bosses, the Formular); the Kirtag keeps its wave. Map generators share `tools/maps/map_kit.gd`.
- **Claude: Gamskogl-Piste** (`tools/maps/make_gamskogl.gd`, 300 x 300 m): leans uphill to the north (17 %),
  snow colours. The Talstation with the Knödl stand is the spawn at the bottom; groomed pistes zig-zag up past
  the Mittelstation (a plateau with a ledge on it), the Schneebar (three levels with a lookout) and two hut shelves
  to the Bergstation with the boss gate at the top. Moguls, a ridge, three kickers, a lift line, ski huts as
  Wirtshäuser, firs round the edge. Stempel lie on the high ground. Its wave adds the Schneemann, more Radlfahrer
  ("skiers"), the Wühlmaus. **The Lawine** is its 10:00 mini-boss (2,600 HP, a huge heap of snow): long marked
  slides it dashes along, a ring of falling snow, a Schneemann escort. The Hofrat stays the final boss on every map.
- **Claude: Gemeindebau-Hof** (`tools/maps/make_gemeindebau.gd`): a big courtyard ringed by four flat-roofed
  council blocks (14 m, windows on both faces, a gate gap in every side). A long ramp inside each block leads onto
  the roofs, which run all the way round (the high route); stairs from outside at two corners; the courtyard has a
  raised garden in two tiers with stairs, laundry lines, a fountain; lower blocks with stairs onto some roofs in
  the quarters outside; the Hausverwaltung with the gate in the north; Beisln as Wirtshäuser. Its wave adds
  Gartenzwerge and Rasenmäher-Roboter early; the second Oberkrampus comes at 10:00.
- **Claude: Kirtag verticality, a light touch** – an Alm (7 m) behind the Gemeindeamt, a lookout in two steps in the
  west, a crag in the east, each with a chest spot on top.
- **Claude: unlocks** – the Gamskogl-Piste opens with "Durchghalten" (survive 10 minutes), the Gemeindebau-Hof with
  "Fünf Kirtage" (5 runs). Spielen chooses the map like the Grant level (‹ › or Left/Right).
- **Measured (local, RTX 3080, run, 500 enemies, bot, 60 s):** Edge 157 fps / p95 7.8 ms / at most 128 draw calls,
  Firefox 131 fps / p95 10 ms / at most 117. New maps in the browser: about 100 draw calls. Map bakes about 450 ms.
- **Measured (balance log, 2 bot runs, Onkel Ferdl, Kirtag, Normal, after all of M4):** both WON (Hofrat beaten at
  14:32 and 14:52, Oberkrampus at 5:21-6:17, Oberkrampus II at 10:31-13:02), level 60-66, 25.7k-30.8k kills, 15-27
  knock-downs, 2-3 Stempel. The gap after the build rework (part 2) is closed again; tuning stays an M5 job.
- **Preview deployed** to https://m4-meta.knoedlinger.pages.dev (with the Ehrentafel's preview database). From the
  preview (headless Edge, RTX 3080, 500 enemies, bot, 60 s): 153 fps avg, p95 8.4 ms, at most 127 draw calls, no
  console errors.

## Fix: Stammtisch icons (2026-11-04)

- **Owner (playtest):** the Stammtisch icons are wrong (Wanderschuhe showed a drink, Bergkas-Abo a Lebkuchenherz).
- **Claude:** all 10 upgrades had borrowed item/stat icons since M4 part 3. Each now has its own icon in the same
  flat SVG style, `assets/icons/meta_<id>.svg`: a cheese block with a plus (Bergkas-Abo), whetstone and blade
  (Wetzstein), hiking boot (Wanderschuhe), dough rising out of a bowl (Großer Teig), a slip with reroll arrows
  (Nochmal-Zetterl), a form crossed out in blue ink (Beschwerdeformular), a horseshoe over a door (Hufeisen überm
  Tor), a leather pocket with spoon and ladle (Zweiter Hosensack), a plate getting a second Knödl (Nachschlag) and a
  walking stick with reach arcs (Wanderstecken). No data entry shares an icon any more.

## Fix: playtest round after M4 (2026-11-04)

- **Owner (playtest):** after choosing an upgrade the game pauses and the mouse is no longer captured;
  lag spikes when a run starts (a loading bar instead of a frozen screen?); use Godot's anti-aliasing
  with a settings toggle, on by default; the start of a run is too hard.
- **Claude: pause after a pick.** A solo Speisekarte (and the Tab screen) pauses the tree, so RunWorld's
  "pointer lost = browser Esc" check kept a stale `_was_captured` and opened the pause menu on the first
  frame after the pick. Now a panel that frees the pointer is remembered and the pointer is captured
  again once the panel is gone (the pick or key press is the browser's user gesture). The pause menu
  keeps "click to look" (re-locking right after the browser's Esc is refused by browsers).
- **Claude: loading screen.** Measured with `tools/browser/hitch_probe.mjs` (fresh Edge profile): the
  first frame of a run compiled ~81 WebGL programs and froze ~11 s. `ShaderWarmup` now runs behind a
  `LoadingScreen` (title, gold bar, the page loader's LOADING_JOKE_* lines) before the clock starts:
  the camera sees only render layer 20, one node per frame joins it (one per distinct look first, never
  culled, MultiMeshes with one instance, lights always on), so each stall is ≤ 2 s and the bar moves.
  Solo stays paused meanwhile; headless runs skip it. The menu shows the screen before switching scenes.
  Returning visit (browser shader cache): through in ~1 s. Batching several nodes after a quick frame
  was tried and dropped (a batch then held several new looks: 4 s frames).
- **Claude: anti-aliasing** = setting `antialiasing` (default on) -> root viewport `msaa_3d` 4x; toggle
  "Kantenglättung" under Anzeige. Browser check: 152 fps avg (153 before), max 124 draw calls.
  M5 moves the row into its tabbed settings and turns MSAA off at quality Niedrig.
- **Claude: gentler start** (`spawn_ease_*` in BalanceData, `Formulas.early_ease`): enemy HP and
  contact damage start at 50 % and ease (smoothstep) to the full curve by 3:00; the crowd stays full.
  Autoplay, 3 runs, seed 1: first knock-down at 53-88 s (was ~37 s every run), knock-downs before 3:00
  2/4/2 (was 5/7/3), levels at 1:00/3:00 unchanged (6-7 / 13-16). A thinner crowd (count 60 %) was
  tried first: fewer Brösel, level 3 at 1:00, a weaker run overall, so it stays at 100 %. M5 part 6
  tunes on top.
## 2026-11-04 – M5 build (branch m5-polish)

### Part 1: gamepad

- **Claude: Xbox layout**, every action has its pad events in `InputSetup` next to the unchanged keys:
  left stick moves, right stick looks (own `look_*` actions, squared curve, `camera_pad_yaw_speed`
  3.2 / `camera_pad_pitch_speed` 1.6 rad/s times the "Stick-Tempo" setting), A jumps, RB or RT throws,
  Start pauses, Back/View opens the inventory. On the Speisekarte X = Nochmal bitte, Y = Des mog i ned,
  LB = Danke, passt eh; the D-pad walks the rows, A takes one. Menus use Godot's `ui_*` actions (D-pad,
  A, B); LB/RB switch pages (map in Spielen, Rekorde, settings tabs), LT/RT the Grant level.
- **Claude: no accidental picks** – A is also jump, so the Speisekarte only focuses its first row 0.4 s
  after it opens (until then A does nothing), and the end screen ignores the pad's A/B for 1 s.
  A pad cannot type: A on the name prompt takes the name as it stands (or "Knödlinger").
- **Claude: keycaps follow the device** (`InputDevice` autoload remembers keyboard/mouse, pad or touch;
  `KeycapLabel` shows "Esc", "B" or nothing). Number keycaps on the Speisekarte hide on the pad.
  Vibration is left out (not dependable in browsers).
- **Claude: Einstellungen in three tabs** (Ton & Bild, Steuerung, Spiel; Q/E or LB/RB), because gamepad,
  quality and touch options no longer fit in two columns. New drawn widget `UiChoice` (‹ value ›) for
  the choice settings.

### Part 2: quality and the auto-quality scaler

- **Claude: three levels** Hoch / Mittel / Niedrig plus Automatisch (default), in `balance.tres`:
  render resolution x1 / 0.8 / 0.65, browser pixel ratio at most 2 / 1.5 / 1, sun shadows 45 m / 28 m /
  off, and on Niedrig in a **solo** game 70 % of the crowd (in co-op the host's quality would change
  everyone's game, so the crowd stays).
- **Claude: render resolution in the browser = the canvas's pixel ratio**, not Godot's 3D scale.
  Measured: `Viewport.scaling_3d_scale` below 1 cost about 4 ms per frame in the Compatibility renderer
  on its own (151 → 96 fps at 500 enemies), because the 3D draws into an extra buffer and is copied.
  `web/pixel_scale.js` hands Godot a smaller `devicePixelRatio`, which shrinks the whole backbuffer at no
  per-frame cost (Niedrig 150 fps, the same as Hoch on this CPU-bound machine; the win is on GPU-bound
  phones, whose ~2.6x screens are also capped at 2x on Hoch). The UI gets softer at Mittel/Niedrig; on a
  desktop that only matters if a player picks it.
- **Claude: Automatisch** steps down one level after 3 s in a row below 50 fps (phones 27), after a 5 s
  warm-up; it steps back up after 20 s above 1.5x the target, never sooner than 60 s after a step down.
  Automated runs stay on Hoch (`quality=` for tests), so measurements never change underneath.

### Part 3: touch controls

- **Claude: `TouchControls`** – a floating stick where the left thumb lands (left 45 % of the screen),
  Hupfn and Schupfn bottom right, Pause and Inventory as round buttons under the clock, dragging anywhere
  else on the right turns the camera (`camera_touch_sensitivity` times Maus-Tempo). It feeds the normal
  actions; menus and the Speisekarte take taps as clicks. Shown by "Touch-Knöpfe" (Automatisch = once the
  screen is touched, Immer, Nie), size 70-150 %, opacity; hidden while a full-screen panel is up.
  The Knödl panel and the world markers move up above the buttons; the keyboard intro hides on touch.
  A tap never captures the mouse pointer. Godot's (experimental) virtual keyboard is on, so the name
  can be typed on a phone.
- **Open (owner, Pixel 9 Pro):** the mobile budget (30 fps at 200 enemies) and whether the UI text is
  big enough on a phone (the 1280x720 layout shrinks to about 0.6 on a phone in landscape, so 14 px
  text becomes about 8 CSS px). If it is too small, a "UI-Größe" setting with a smaller base layout
  on phones is the next step.

### Part 4: loading screen and cache

- **Claude: own page shell `web/shell.html`** – dark palette, a rolling Knödl, the title font, a gold
  progress bar and a dialect joke every 3 s (16 `LOADING_JOKE_*` lines); phones held upright get
  "Bitte quer halten". It stays until the game's first screen stands (`WebPage.loaded()` →
  `knoedlReady()`, at most 8 s after the engine started). All its text comes from `i18n/strings.csv`
  at build time (`{{KEY}}` placeholders, filled by `tools/pack_wasm.mjs`, which fails on leftovers).
- **Claude: hashed file names** – the engine files are renamed to `k-<hash>.*` (one hash over wasm, pck
  and scripts), the title font to `k-<fonthash>.ttf`; `_headers` gives `/k-*` a year of immutable
  caching (the `! Cache-Control` detach drops the site-wide `no-cache`), `index.html` and the small
  helper scripts stay `no-cache`. A new deploy is picked up at once, a returning player downloads
  nothing but the page.

### Part 5: content left over from M4

- **Claude: Riesenknödl der Apokalypse** as an *item evolution* (`ItemData.evolves_from` /
  `evolves_with`): holding Bröselbutter with Lederhosn at its evolution level (8) adds it by itself
  (toast + jingle). The Knödl is twice the size (past the usual 4 m cap, `riesenknodl_size`) and never
  loses mass – Bröselfresser bites, shedding while thrown and the Powidl cost do nothing; a cash-in or a
  respawn still empties it. No chest gives it. Clients draw the size from the synced items.
- **Claude: Watschn-Baum reflect** (`WeaponData.reflect_share` 2.0): each hit a player takes comes back
  as 2x the HP lost (growing with the weapon's damage like its own hits) to every enemy within its reach.
- **Claude: Jagatee sway** (`PassiveData.screen_wobble` 0.15 per level, full at 7): the camera rolls up
  to 2.5° and nods a little, slowly; off with the new setting "Bildschirm wackeln".
- **Moved to M6: Doppelportion** (a second Knödl on its own string). It needs a second Knödl body in the
  physics and in every network codec (pose, world state, Brösel credit); that is co-op work.

### Part 6: balance pass (bot data; the owner's playtest decides)

- **Claude (bug): a character's own start weapon was locked** on a fresh profile when its quest was not
  done yet (Kevin's Watschn-Aura unlocks at level 30): it never got a level card and stayed at level 1.
  The start weapon and its evolution are now never locked for that character.
- **Measured (2 bot runs each, Normal unless said):** Ferdl/Kirtag WON both (level 60-66), Resi/Kirtag
  CLOSED both (level 40-59, 1-3 Stempel), Ferdl/Kirtag on Grantig 1 WON 1 CLOSED (level 49-51, 34-40
  knock-downs), Toni/Gamskogl CLOSED both (level 26-32, 2.8-4.9k kills), Ferdl/Gamskogl CLOSED both
  (level 37-42, 7-10k kills, first Oberkrampus at 8:30), Kevin/Gemeindebau (after the fix) CLOSED both
  (level 49-56, 0 Stempel, 35-50 knock-downs).
- **Claude: the tall maps get fewer enemies within reach** (they climb slowly), so the bot gets a third
  of the Kirtag's kills and XP there. New `WaveData.enemy_hp`: Gamskogl-Piste 0.75, Gemeindebau-Hof 0.85,
  Kirtag 1.0. Measured after it (Ferdl, 2 runs each): Gamskogl 1 WON 1 CLOSED (level 41-43, Hofrat beaten
  at 14:58), Gemeindebau 1 WON 1 CLOSED (level 57-71, 27-30k kills) – a step below the Kirtag, as the
  harder maps should be. The bot is also poor at climbing to the Stempel; real players will open the gate more
  often than the logs suggest, so these maps are not tuned up to the Kirtag's win rate.
- **Merged main into m5-polish** (Stammtisch icons, the pause-menu fix, the in-game shader loading screen,
  anti-aliasing, early-game easing). The "Kantenglättung" row sits in Ton & Bild next to Qualität; the
  QualityScaler owns MSAA (the setting's value, but off on Niedrig) and does not measure during the
  shader warm-up (slow on purpose). Enemy HP takes the map factor and the early ease together. The
  Speisekarte's footer hint now matches the device ("1–3 nehmen", "A nehmen", "Antippen").
- **Measured: the early-game easing lowers the bot's end level.** Ferdl/Kirtag, same seeds, easing off vs
  on: seed 1 (2 runs) 66/60 WON vs 49/46 CLOSED; seed 2 (3 runs) 50/52/43 vs 37/44/46, all CLOSED.
  Damage-only easing (HP not eased) gave 53/42/34, so it is not the HP half. Average about 51 → 44 levels
  over five runs, but single runs swing ±10 levels, so the cause is not clear from bot data. The values
  stay as approved on main; **open for the owner's playtest** whether the late game now feels too hard
  (the first level 10 comes sooner and there are fewer early knock-downs, as intended).
- **Measured after the merge** (local, RTX 3080, 500 enemies, bot, 60 s, MSAA on): Edge 152.5 fps / p95
  8.4 ms / at most 126 draw calls, Firefox 126 fps / p95 10 ms / at most 119; `mp_test -Clients 1` 37.5 KiB/s
  per client, everything in sync; the full `ui_shots` set (80 shots) under 150 draw calls, no console errors.
- **Note for parallel sessions:** test servers on the same port serve the other worktree's build (seen
  on 8061/8071 today); pass a free `-Port` when two sessions test at once.

## 2026-11-04 – M5 approved

- **Owner: M5 approved** on the first preview; merged into `main`, branch `m5-polish` deleted.
- **Owner: first production deploy** – `main` with M5 is deployed to https://knoedlinger.pages.dev (with the
  real Ehrentafel database `knoedlinger-board`). Next: M6 (co-op).

## 2026-11-05 – M6 build (branch m6-coop)

### Part 1: transport and the co-op room

- **Claude: Berghittn's relay reused as decided at the start** (`relay/`, Worker `knoedlinger-relay` with the
  `Room` Durable Object, no public route; `functions/api/room/[code].js` hands the WebSocket over;
  `net/transports/relay_peer.gd` is Berghittn's `RelayPeer`). Changes: 4-letter codes without I and O (route.js
  draws them), the URL carries `game=knoedlinger&ver=&build=` (wrong game refused before the Durable Object, wrong
  build refused by the room: "Eicha Version is ned de gleiche."), and a new target byte **0x20 | mask** sends a
  frame to exactly the peers in the mask. Berghittn's "everyone" target reached a player the host had not heard
  of yet, and Godot's path cache logged "Duplicate remote cache ID" (seen in the 4-tab browser check).
- **Claude: NetworkManager keeps a roster** (`LobbyProfile`: name, character, Stammtisch bonus, unlocked
  characters; the host's also carries map and Grant level), sent with the handshake and on every change; the host
  starts the run for everyone (`start_run`), each client says when its run scene is loaded (`send_run_ready`) and
  only then gets gameplay messages (`client_ids()`); after a run the host takes everyone back to the room. The
  WebSocket backend works the same (`--net=ws`), and headless runs can meet in the room with `--lobby=N`
  (host starts once N clients are in) / `--lobby` (client). A run started from the room uses the room's character,
  map and Grant level, whatever the flags say.
- **Claude: the `Lobby` autoload has the rules**: whoever picks a Knödlinger someone else already plays (or joins
  with one) gets the first free one they have unlocked ("Es gibt nur eine Oma!"); the host needs at least two
  players with different Knödlinger to start. Drop-in only in the room: the relay refuses joiners once started.
- **Claude: "Stammtisch aufmachen" screen** (`CoopScreen`): Aufmachen (Enter, also Enter on an empty code field)
  or a code to sit down with; in the room the code in the number font (Fraktur letters were hard to read out),
  "Link kopieren" (`?room=KNDL` opens the menu and joins after the name prompt), four seats, the family to choose
  from (taken ones dimmed), the host's map and Grant level, Auf geht's / Gehen. Co-op end screen: the host's
  "Zurück an'n Stammtisch" brings everyone back to the room, "Gehen" leaves. If the host leaves mid-run, the others
  see "Da Wirt is hoamgangen." and go to the menu, keeping what the run paid so far.

### Part 2: every player their own Knödlinger

- **Claude: per-player characters**: each player's model, start weapon, Knödl sort, traits (Grant, coffee
  break, jump waves ...) and Stammtisch bonus come from their own room profile (`RunWorld.character_of`); the
  Ehrentafel's co-op entry lists every name and character. Unlocks for the shared card pool stay the host's.

### Part 3: downed, not dead; shared XP; the family HUD

- **Claude: `CoopRules`** (host) holds every co-op rule. Knocked down in co-op = 30 s on the ground
  (`coop_down_seconds`); a teammate standing within 2.2 m fills the revive in 3 s (it drains at 0.5/s when they
  step away), any teammate's Knödl touching them wakes them at once ("Aufgweckt!"); back up with 50 % HP and 2 s
  without hits. After 30 s they are out (spectating the nearest teammate) until the next Wirtshaus cash-in, which
  wakes everyone ("Da Wirt weckt olle auf!"). The run is lost when everyone is down at once. Marterl-Kerze and
  Nachschlag still revive on the spot first.
- **Claude: shared XP** = 50 % of a Knödl's XP to every other player within 25 m (not to players who are out),
  no mass; a merge partner gets all of it.
- **Claude: HUD** – the bottom-left corner (kept free since the UI pass) shows the family in one drawn
  `TeamPanel` (dot in the coat colour, name, level, HP bar or "umgfoin · 23 s" / "wird aufgweckt · 60 %" /
  "draußen"); teammates get edge markers when far or off screen ("Resi aufwecken · 12 m" while down); a sign over a
  knocked-down teammate counts down. World state v5 carries out, revive progress, seconds left, the merge partner,
  the co-op deeds and the Doppelportion Knödl.

### Part 4: the Knödl moves

- **Claude: Knödl-Pass** – a Schupfn with a teammate within 30° of the throw and 30 m away aims straight at them;
  when the flying Knödl reaches them (after 0.25 s in the air) they catch it: its mass above the start size goes
  into their Knödl, the thrower's reels back empty. Throws away from teammates are plain throws, so nobody loses
  mass by accident.
- **Claude: Riesenknödl** – two Knödl touching at 4.5 m/s or more relative speed (3 m/s merged walking pairs all
  the time in the first test) merge: the bigger one takes the mass and hangs on both strings (a second spring to
  the partner, drawn as a second Spagat), the smaller one hides inside it. Schupfn by either of the two, 30 s, or
  either going down splits it by the shares they brought; the same pair waits 8 s before merging again; no merge in
  a player's first 5 s (everyone spawns side by side) and none with a pass in the air. **Gemeinsam einkehren**: a
  merged Knödl at a Wirtshaus pays both players a chest of the combined tier, then both start over.
- **Claude: Familienstreit** at 7:00 (co-op only): one random player's Knödl tears loose and rolls away (9 m/s,
  wandering, turning back at the map's edge) for 10 s; Bröselfresser go for it as usual; a teammate touching it
  brings it back ("Erwischt!"), else it comes home by itself when the time is up.

### Part 5: content and bandwidth

- **Claude: Doppelportion** (item, Edel, moved here from M5): a second Knödl at 60 % size on its own 2.2 m string;
  it crushes and eats for its player (the mass goes to the main Knödl), Bröselfresser ignore it. Unlocked by the
  new quest "Nachschlag bitte" (25 cash-ins). `--items=a,b` gives items at the start (testing).
- **Claude: seven co-op quests** (kind `coop`, counted per player and stamped on each player's own Profile):
  Familienausflug (a co-op run), Aufgweckt! (wake Onkel Ferdl with a Knödl), Erste Hilfe (wake 10), Knödl-Pass
  (25 caught passes), Gemeinsam einkehren (merged XL cash-in), Streitschlichter (catch the Familienstreit Knödl),
  Die ganze Familie (win with four). 109 quests now.
- **Claude: snapshot v2** – positions in 5 cm steps (was 1 cm) and the enemy bytes as planes (all high bytes of
  x, then the low ones, then z, then type/HP), which deflate far better: ~3.6 B per enemy. **The full 4-player crowd
  (844 enemies) now needs 57.5 KiB/s per client** (was 63.5, budget 60); 500 enemies 31.8 KiB/s (was 37.5).
- **Claude: clients get the host's numbers at the end** (kills by type, bosses, their knock-downs, biggest
  Knödl, cash-ins, throws), so their end screen and their quests count the run, not zeros.

### Part 6: browser checks and draw calls

- **Claude: the relay jittered snapshots** (its 50 ms batching against the 15 Hz send): the host now flushes the
  relay right after each world send, and clients show enemies 150 ms in the past over the relay (100 ms on the
  local WebSocket). Measurements start after the loading screen (co-op runs on behind it).
- **Claude: draw calls in co-op** – each player model was 7 meshes (14 draw calls with shadows); now one
  vertex-coloured mesh. Signs over Wirtshäuser and the gate draw within 45 m, player signs within 70 m. The host's
  own Speisekarte arrived a frame after the HUD decided to stay, so for one frame both drew (163 calls); the HUD now
  steps back at once.
- **Measured (local, RTX 3080):** 4 headless Edge tabs in one room through the local relay (`browser_mp_check.ps1
  -Tabs 4`, 300 enemies, bots, 60 s): host 133 fps / at most 118 draw calls, clients 181 fps / at most 110,
  28 KiB/s down each, every Knödl and enemy shown, 0 pops, no console errors. Solo browser check: 175 fps, p95
  7.1 ms, at most 98 draw calls (M5: 152 fps, 126). Headless: `mp_test -Clients 3 -Coop` (revives, passes, merges,
  Familienstreit, Doppelportion on every client) and `-Lobby` pass; the relay's node tests pass (4). Co-op UI shots
  (`ui_shots.ps1 -Only coop`, room and HUDs at both sizes): at most 107 draw calls.
- **Owner: OK to deploy the relay.** `knoedlinger-relay` deployed with `npx wrangler deploy` in `relay/` (Durable
  Object `Room`, free plan, no public route); the Pages project binds it as `ROOMS` for production and previews.
- **Preview deployed** to https://m6-coop.knoedlinger.pages.dev. Through the real Cloudflare relay (headless Edge,
  RTX 3080, 4 tabs in room FKEE, 300 enemies, bots, 60 s): host 143 fps / at most 125 draw calls, clients 192 fps /
  at most 114, 28.3 KiB/s down each, every Knödl and enemy shown, 0 pops, no console errors. Solo browser check
  on the preview: 174.5 fps, p95 7.1 ms, at most 99 draw calls.

## 2026-11-05 – M6 approved

- **Owner: M6 approved** on the preview; merged into `main`, branch `m6-coop` deleted. All milestones of
  GAME-DESIGN.md (M0-M6) are now in `main`; production still only on the owner's word.
- **Owner: production deploy of M6** on 2026-11-05: `main` 8a3f94b is live on https://knoedlinger.pages.dev with co-op
  (relay `knoedlinger-relay`). Measured on production (headless Edge, RTX 3080): solo 179.7 fps, p95 6.9 ms, at most
  99 draw calls; 4 tabs in one room through the live relay: host 132.5 fps, clients 172 fps, at most 124 draw calls,
  28.1 KiB/s down each, every Knödl and enemy shown, 0 pops, no console errors.

## 2026-11-05 – Version 1.0.0

- **Owner: the game is 1.0.0** (it showed the placeholder 0.1.0 from M1). All v1 content of GAME-DESIGN.md is in.
  Deployed straight to production at the owner's word.
- **Owner: semantic versioning from here on:** new features and content raise the minor number (1.1.0, 1.2.0),
  bug fixes and small balance changes the patch number (1.0.1, 1.0.2); the major number only for something that
  breaks old saves or reworks the core. The only source is `application/config/version` in `project.godot`
  (HUD, co-op handshake, Ehrentafel entries all read it via `NetworkManager`).
- **Claude: co-op keeps the exact version match**, patch numbers included: a fix can change the simulation, and
  host and clients must run the same build. A player with an old tab open reloads to join.
- **Production deploy of 1.0.0** on 2026-11-05: `main` 1932e0e is live on https://knoedlinger.pages.dev. Measured on
  production (headless Edge, RTX 3080, 500 enemies, bot, 60 s): 173.5 fps, p95 7 ms, at most 99 draw calls, no
  console errors. `mp_test -Clients 1` passes and still refuses an old-version client.

## 2026-11-05 – Movement in the style of Megabonk (1.1.0)

- **Owner asked for research on Megabonk's movement** (feel, and jumping that turns into flying with enough jump
  power). What makes it feel good, from guides and reviews: jumping is the fastest way to move (running about 10
  speed, plain jumps 20–40); the air keeps momentum and only the ground's friction takes it; downhill slides build
  speed; jump height and extra jumps are build stats that stack into near-flight (Feathers: +jump height, +1 jump,
  +forward speed per jump; Birdo floats while jump is held); easy to start, high skill ceiling; maps built for it.
- **Owner: no slide button** – running downhill gains speed on its own. **Owner: no air-strafing** (no speed from
  turning the camera in the air). **Owner: a Knödl lifted into the air only eats Brösel within its reach**, and
  the player's 1 m pull only works near the player's body (height counts too), so flying high gathers nothing.
- **Claude: jump arc** – rise gravity 22, jump speed 10 (2.3 m up), falling 1.5× gravity, half gravity around the
  top while jump is held (|v.y| < 2 m/s), letting go while rising keeps 45 % of the upward speed (short hop).
  A held jump lasts 1.04 s in the air (Megabonk ≈ 1.0 s; ours was 0.73 s / 1.7 m). Max fall speed 35 m/s.
- **Claude: momentum** – each jump while moving adds 1.5 m/s forward; up to 2× run speed. Above run speed the
  stick only steers (pulling back more than 120° from the flight brakes); speed fades at 16 m/s² on flat ground,
  never in the air, and not while running downhill. Downhill gain: gravity × slope × 0.6. With no stick in the air
  the player keeps flying in the same direction (before: stopped in 0.2 s). The host's pose check allows the
  momentum cap (`Player.max_speed()`).
- **Claude: new stat `glide` ("Schweben")** – holding jump on the way down divides gravity and the fall speed by
  (1 + glide × 4), fall speed at most 6 m/s / that. Height ceiling: 30 m above the ground.
- **Claude: two new items** (appended to the catalog, so old indices stay): *Spielhahnfeder* (Fein, +30 % jump
  height, no stack limit – the "jump power" item) and *Gleitschirm* (Edel, +0.5 glide, at most 3). Gleitschirm is
  orange, not red (red is for danger only).
- **Claude: fliers rise to airborne players** – new `EnemyTypeData.air_reach` (Gelse 8 m, Taube 6 m): within
  4 m (flat) they rise toward the nearest player or Knödl in the air, fully at touch range
  (`EnemyManager.air_lift`, the same rule in the host's touch check and in every renderer, so nothing new goes
  over the network). Flying is not a free pass; a lifted Knödl also crushes nothing (its height check already did).
- **Claude: the camera widens up to 8° at full momentum** (`camera_speed_fov`), so speed reads as speed.
- **Version 1.1.0** (new feature). **Measured** (local, RTX 3080): tests 172/172; browser check 172 fps / p95
  7.2 ms / at most 103 draw calls; with the full flying build (3 Gleitschirme, 3 Federn, 2 Haferlschuhe) 148 fps /
  p95 12.1 ms / 104 draw calls (fewer kills, denser crowd); `mp_test -Clients 1` passes (31.6 KiB/s, no rejected
  poses); autoplay Ferdl/Kirtag seed 1: CLOSED at level 55, both Oberkrampusse beaten (recent baseline 44–51).
- **Owner: approved** on the preview https://movement.knoedlinger.pages.dev; merged into `main` (4887b6a), branch
  `movement` deleted. **Production deploy of 1.1.0** on 2026-11-05 at the owner's word: live on
  https://knoedlinger.pages.dev. Measured on production (headless Edge, RTX 3080, 500 enemies, bot, 60 s):
  161.8 fps, p95 7.9 ms, at most 99 draw calls, no console errors; `mp_test -Clients 1` passes.

## Audio fix (1.1.1)

- **Owner: no sound in Firefox and Edge.** Measured with a Web Audio analyser in headless Edge: the M3 preview
  plays (peak 1.22), M4 and later, including production 1.1.0, output pure silence. Cause: since M4 part 1
  GameAudio created the Music/Sfx/Voice buses at runtime with `AudioServer.add_bus()`; Godot's web audio
  (sample playback) never gets those buses, so every player on them was silent. **Claude:** the buses now
  come from `default_bus_layout.tres` (loaded at engine start); GameAudio only reports a missing bus, and
  `tests/unit/test_audio.gd` guards it. Fixed build: menu music peak 0.20, bot run peak 0.76. Patch release 1.1.1.
- **Owner: approved** on the preview https://fix-audio.knoedlinger.pages.dev ("sound is working"); merged into `main`
  (e818b0c), branch `fix-audio` deleted. **Production deploy of 1.1.1** on 2026-11-05 at the owner's word: live on
  https://knoedlinger.pages.dev. Measured on production (headless Edge, analyser on the output): menu music peak 0.25,
  bot run peak 0.98, no console errors.
## 2026-11-05 – Enemy voice lines (branch `enemy-voices`, planned 1.2.0)

- **Owner:** enemies talk like Berghittn's "Gredn" (eSpeak NG voices with a filter per enemy, the line as
  text over the head). Enemies only for now; voices for the player characters maybe later. Much less chatty
  than Berghittn: at most one enemy line overall every 3–5 s.
- **Claude:** Berghittn's pipeline is copied: `tools/audio/voices/dsp.py` as is, `voices.py` with its
  eSpeak call, vocoder and the filters the owner approved there (Tourist, Perchte, Krampus → Oberkrampus).
  New filters: Akten-Geist (hollow, detuned, office echo), Radler (out of breath), Rasenmäher-Roboter
  (vocoder on a fixed 110 Hz buzz, bitcrushed), Kontrolleur (nasal), Hofrat (dry, slow, marble hall).
  Python + eSpeak NG only on the dev machine, the OGGs are ours. Step 1 is samples for the owner
  (`python tools/audio/voices/voices.py --samples` → `build/voice_samples/index.html`, ~25 KB per line)
  before the full line set and the runtime (lines as data in `data/voice_lines/`, text via `tr()`,
  picked on the host from EnemyManager events, a SAY run event for co-op, a "Gegner reden" setting).
  Animals (Gelse, Dackel, Taube, Wildschwein) get sounds, not words.
- **Owner (2026-11-05):** samples approved ("sounds good"), build the lines.
- **Built (1.2.0):** 64 lines from 16 enemies plus the Riesen-Wirt, 16 voices (new: Hungriger Tourist =
  the Tourist lower and slower, Schneemann muffled with a shiver, Gartenzwerg and Wühlmaus quick and high
  like Berghittn's Venedigermandl, Dackel/Taube/Wildschwein as "Wuff!", "Gurr." and "Grunz!", the
  Riesen-Wirt big and booming). Only the Gelsen and the Lawine keep quiet. 1.42 MB of OGG (.pck 3.6 →
  5.2 MiB). Lines are data: `VoiceLineData` (moment, text key, sound, optional chance) in a `VoiceLineSet`
  per enemy (`data/voice_lines/`, `EnemyTypeData.voice`); the Riesen-Wirt's set is loaded by path, since
  he is no enemy type.
- **Claude – when they talk** (numbers in `balance_data.gd`, group "Enemy voices"): one line overall every
  2.5–4 s plus up to 1 s waiting for a moment's line before an idle one, never over the line before
  (measured in the test: 3.5–5.0 s apart, mean 4.4 s); one line per enemy type every 10 s; only within 20 m
  of a player. Moments: IDLE (random nearby enemy), ATTACK (its telegraph starts; 35 %), DEATH (15 %;
  Gartenzwerg 40 %), CRUSHED (killed by a Knödl, 30 %), EAT (a Bröselfresser biting a Knödl, 40 %),
  ARRIVE / HALF / BEATEN (bosses, always; the Kontrolleur arriving at the door, the Riesen-Wirt at
  Sperrstund'). Bosses skip the overall gap and the reach, with their own 6 s gap; their attacks 50 %.
- **Claude – how it shows:** the text over the head at a fixed on-screen size (about the theme's body size,
  bold, thin shadow-coloured outline, no depth test), following the speaker; last words stay where it fell.
  At most 2 shown (a nearer line replaces the farther one), within 25 m of the local player, as long as
  the voice (at least 1.6 s), then a 0.4 s fade. At most 2 lines heard at once, on the Voice bus.
  Setting "Gegner reden" (Spiel tab, on by default).
- **Claude – co-op:** the host picks every line; a new run event SAY (u8 enemy type, u8 line, u16 slot,
  x, z; 13 bytes) goes reliably to the clients (RunEventCodec VERSION 2), which show it at that slot.
  The Riesen-Wirt's line is local (every machine moves its own Riesen-Wirt). `mp_test` fails when none
  of the host's lines reach a client. Test hook `?voice_every=1` for the `voices` screenshots.
- **Claude:** the speech text is a shader variant of its own (fixed size, no depth test) and hidden
  Label3Ds are not warmed up, so the first line of a run froze the page for ~100 ms; ShaderWarmup now
  builds a copy (`EnemyVoices.make_text()`). Merged `main` (1.1.1, audio buses from the layout file) into
  the branch so the voices are heard on the web.
- **Measured** (local, RTX 3080, after the merge): tests 179/179; browser check 138 fps / p95 9.3 ms / max
  frame 20.7 ms / at most 104 draw calls; `mp_test -Clients 1` passes (30.8 KiB/s, 3 of 3 lines reached the client); `mp_test -Clients 3
  -StartTime 595` passes (57.2 KiB/s with 846 enemies, every client got the same 7 of the host's 10 lines,
  probably the 3 said before the clients had joined; not confirmed from the logs).
- **Owner: approved** on the preview https://enemy-voices.knoedlinger.pages.dev; merged into `main` (4a13ef9),
  branch `enemy-voices` deleted. **Production deploy of 1.2.0** on 2026-11-05 at the owner's word: live on
  https://knoedlinger.pages.dev. Measured on production (headless Edge, RTX 3080, 500 enemies, bot, 60 s):
  132.3 fps, p95 10.2 ms, max frame 26.1 ms, at most 98 draw calls, no console errors; `mp_test -Clients 1`
  passes (31.4 KiB/s, 3 of 3 enemy lines reached the client). The other running session (weapons) was told to
  merge `main` so its builds carry 1.2.0 too.

## 2026-11-05 – Auto-aim and longer melee reach (1.3.0)

- **Owner asked** how many weapons are ranged and auto-aimed, compared with Megabonk: melee felt weak because you
  die quickly up close. Counted on the 16 base weapons: 5 pick their own targets (Hagelkanone, Stempel,
  Schneekugel, Krampusrute, Würstel), 4 are ranged but only shot the way the player moves (Skistöcke, Zither,
  Tablett, Alphorn), 7 work close (Kochlöffel, Watschn, Mozartkugel, Sachertorte, Schaufel, Kuhglocke, Obstler);
  none home. In Megabonk, aiming is a global setting (closest target / smart targeting) and ranged weapons aim
  themselves. Kiting away from the horde used to fire every arc and shot away from it.
- **Owner: ARC and PROJECTILE weapons aim at the nearest enemy** within their reach (ARC: reach × area; shots: how
  far they fly, a boomerang half of that; same height check as the arc), else the way the player faces
  (`WeaponSystem.aim_at_nearest`). The heading travels as one byte per weapon in the build rows (world state
  codec version 6, weapon row 13 bytes), so every machine draws the swing and the shots the same way. A second
  swing (amount 2) still goes the opposite way.
- **Owner: more reach for the close weapons** (+30–40 %; area multiplies reach, so each area level is now worth
  more metres too): Kochlöffel 2.4 → 3.3, Schneeschaufel 3.2 → 4.3, Watschn-Aura 2.6 → 3.5, Watschn-Baum
  3.4 → 4.5, Kuhglocke 4.5 → 5.8, Obstler 4.6 → 5.8, Mozartkugel orbit 2.6 → 3.4, Kugel-Karussell 3.2 → 4.2,
  Nudelwalker 3.0 → 4.0, Sachertorte blast 3.0 → 3.6.
- **Owner: no defensive bonus for melee** (damage reduction / heal on hit) for now.
- **Version 1.3.0** (a feature; `main` was already 1.2.0 with the enemy voices).
- **Measured before the merge with the enemy voices** (autoplay Ferdl / Kirtag / Grant 1, seeds 1–10, the same
  seeds on 1.1.0 and on this branch): level 45.3 → 46.2, kills 16.3k → 17.5k, knock-downs 23.2 → 17.5 (−25 %),
  bosses beaten 13 → 17, Hofrat beaten 0 → 2 runs. Seeds 1–4 favoured 1.1.0 (other card picks), seeds 5–10
  favoured the branch in 5 of 6; the bot's card luck swings a run by ±8 levels.
- **Measured after the merge** (local, RTX 3080): tests 180/180; browser check 155.5 fps / p95 8.2 ms / at most
  99 draw calls; `mp_test -Clients 1` passes (the swings and shots draw from the synced aim byte).
- **Owner: approved** on the preview https://auto-aim.knoedlinger.pages.dev; merged into `main`, branch `auto-aim`
  deleted, unused worktrees removed.
- **Production deploy of 1.3.0** on 2026-11-05 at the owner's word: `main` c480221 is live on
  https://knoedlinger.pages.dev. Measured on production (headless Edge, RTX 3080, 500 enemies, bot, 60 s):
  158.5 fps, p95 7.8 ms, at most 101 draw calls, no console errors; `mp_test -Clients 1` passes.

## 2026-11-05 – Playtest fixes and the patch list (1.3.1)

- **Owner reported** (playtest of 1.3.0, asked for "1.2.1"; production was already 1.3.0): the Obstler has no
  effect and its icon looks like a sex toy; the Knödl should fly where the mouse aims; movement sometimes
  stops after a Speisekarte until the key is pressed again; some terrain cannot be jumped onto; the run
  plays itself for a few seconds at the start; enemies spawn right in front of a running player; Rüstung
  is overpowered; gold must be visible and chests should show their price from afar; a patch list.
  Owner asked whether this should be a post-release milestone. **Claude:** one branch `playtest-fixes`
  like the earlier 1.x releases, not a new milestone. Claude first numbered it 1.4.0 (the aimed Schupfn,
  the gold display, the chest prices, the slope jump and the patch list as features). **Owner: 1.3.1** –
  mostly bug fixes and small changes, so a patch release.
- **Obstler (Claude, measured):** it did work. Against the same 30 enemies for 5 s it dealt 547 damage
  (Schneeschaufel 450, Kochlöffel 475), burn included. What was missing was the look: a faint fan every
  0.35 s and no fire. New `WeaponData.Look.FLAME`: ARC weapons with it show a flickering flame stream
  (`shaders/flame.gdshader`, blend mix, deep orange tips, yellow core, never Krampus red) for 0.5 s per
  burst, which never breaks at the Obstler's 0.35 s cooldown (a burst still burning keeps its length).
  It plays from the fire counter like every swing, so co-op clients see it too. ShaderWarmup builds it.
  Burning enemies show no fire of their own: that needs a status bit in the enemy snapshots, left for later.
  New icon: a Schnaps bottle with a pear on the label, tipped forward, blasting a fan of flame.
- **Movement stuck after the Speisekarte (Claude, cause found and reproduced in headless Edge):** every
  time the Speisekarte opened or closed, `TouchControls._refresh()` ran (the screen is "covered"), and with
  the touch view hidden it called `_release_all()`, which did `Input.action_release()` on all four move
  actions, even with touch controls off. A held W/A/S/D was released inside Godot, and a held key sends
  no new press. Now the touch stick only releases the move actions it pressed itself. Before: holding S
  through a pick, the player stood still; after: holding A through a pick, x went -6.5 → -13.5 → -20.5.
- **The run starting by itself (Claude, measured):** 1 s into a run with nobody at the keys there were
  14 Brösel (the family's start crumbs, by design) and the first wave (9-15 m) arrived within a second;
  at 0:07 the player had lost 18 HP. **Solo runs now wait for the first step** (move, jump or Schupfn):
  no clock, no spawns, the crumbs lie there and the key hints stay up (`RunWorld._start_held`). Not for
  co-op, the bot, `enemies=`, `seconds=` or online hosts.
- **Spawns in front of a running player (Claude):** the camera is low (20° pitch, 8 m, 80° FOV), so it
  sees the ground up to the horizon ahead; the 18-28 m ring was in plain view ahead. New spawns ahead of
  a player (where they run above 2 m/s, else where they face) now lie up to `spawn_ring_ahead` = 24 m
  farther out (42-52 m): all of it within about 50° of the heading, nothing from about 80° on
  (`EnemyManager.ahead_share`, smoothstep over the cosine 0.17..0.64). Sides and back are unchanged
  (outside the view from about ±65°). Applies to the first ring too.
- **Terrain you cannot jump onto (Claude):** a reachability search over all three maps' ground fields
  (walk ≤ 46°, one jump ≤ 2.0 m within 3 m, from the spawn) found every hill and prop top reachable by
  some route; the unreachable tops were all buildings (houses, Wirtshäuser, stalls, the church) and the
  rim. The real trouble: ground steeper than 46° is no floor, so the player slides and cannot jump.
  Of the owner's two options Claude chose **jumping off steep slopes** (works on every map, also future
  ones): touching ground between 46° and `player_slope_jump_degrees` = 80° while not rising counts as
  ground for a jump (not for running), so a hillside is climbed in hops; walls stay walls, and the
  mountains round the map (beyond `MapData.rim_start`) stay a wall. Test: a 60° slope is climbed
  (> 3 m in 3 s; 0.6 m without the rule), an 88° wall is not.
- **Schupfn follows the mouse (Claude):** keyboard and mouse throw toward the ground under the cursor,
  or where the camera looks while it holds the pointer (mouse look); pad, touch and the bot still throw
  the way they move. `InputMessage` VERSION 4 (26 bytes): `aim_yaw` (u16) and `BUTTON_AIM`; the host
  uses `InputMessage.throw_direction()`, so the co-op pass aim works on it too.
- **Rüstung (Claude):** armor was subtracted from every hit (minimum 1). Hits come at most every 0.5 s and
  use the strongest touching enemy (fodder 2-5), and each Lederhosn level gives 1-2 armor plus the
  Trachtenjanker (+2) and Rosenkranz (+1) stack: by mid-run ~8 armor turned almost every hit into 1
  damage (75-85 % less). Now armor takes a share: `armor / (armor + armor_half)`, `armor_half` = 10
  (3 → −23 %, 8 → −44 %, 20 → −67 %), minimum hit still 1. The Werte screen shows "8 (−44 %)".
- **Gold and chest prices (Claude):** gold sits in the top-left HUD panel next to the level (coin icon).
  Every map chest in view and within 45 m carries a world marker pill "25 Gold" (accent dot when the
  player can afford it, muted when not), from the same marker pool as the Stempel and the gate.
- **Patch list (Claude):** main menu entry "Was is neu?" (after Einstellungen) opens `PatchNotesScreen`:
  every release newest first with version, date and one line per change. Data-driven:
  `data/patch_notes/patch_notes.tres` (`PatchNotes` → `PatchNote`: version, date, line keys), the text
  in `i18n/strings.csv` as `PATCH_<version>_<n>`. 1.0.0-1.3.0 written from this log. A test fails when
  the newest note is not the version in project.godot, so **every release adds its note on top**.
  `ui_shots.ps1` has a `patches` shot. `[STATS]` lines now carry the local player's position (`pos`).
- **Measured** (local, RTX 3080): tests 183/183; browser check 177 fps; `mp_test -Clients 1`,
  `-Clients 3 -StartTime 595` and `-Clients 3 -Coop` pass; preview https://playtest-fixes.knoedlinger.pages.dev
  (b054d56): 164.5 fps / p95 7.7 ms / at most 114 draw calls. Obstler damage was never broken: 547 damage in
  5 s on 30 enemies (Schneeschaufel 450, Kochlöffel 475), only its look was invisible.
- **Autoplay** (Ferdl / Kirtag / Grant 1, seeds 1-10, compared with 1.3.0): level 46.2 → 47.4, kills
  17.5k → 15.6k, knock-downs 17.5 → 27.7 (+58 %, the armour nerf: the bot no longer shrugs off fodder
  mid-run), bosses beaten 17 → 20, Hofrat beaten 2 → 3 runs (WON 3, CLOSED 7). If the owner finds it too
  hard, `armor_half` is the one number to lower (6 gives 8 armor −57 %).
- **Owner: approved** as 1.3.1; merged into `main`, branch `playtest-fixes` deleted.
- **Production deploy of 1.3.1** on 2026-11-05 at the owner's word: `main` 424bd2e is live on
  https://knoedlinger.pages.dev. Before the merge (same code, `main` had not moved): tests 183/183,
  browser check 181.9 fps, `mp_test -Clients 1` passes. On production (headless Edge, RTX 3080, 500
  enemies, bot, 60 s): 174.2 fps, p95 7.2 ms, at most 101 draw calls, no console errors.
- **Owner asked whether production gets the full test run again. Claude:** the full suite (tests, export,
  browser check, multiplayer tests) runs on the branch before approval. When `main` has not moved since,
  the merge is the same code, so after the production deploy only the browser check runs against the live
  URL: it catches deploy problems (files, headers, cache, loader). The full suite runs again only when
  something changed after approval (another merge on `main`, a fix, a version change like today).

## 1.3.2 – Ehrentafel on the title screen (2026-11-05)

Owner: 1.4 stays in planning (branch `v1-4`); this feature is needed now, as a patch release 1.3.2 off `main`
(branch `ehrentafel-menu`). Owner asked for the top 5 (or 3) runs of the Ehrentafel in the main menu so every
player sees it first, and for "Rekorde" to become "Ehrentafel" with the board shown directly and "Eigene" as
the second tab.
- **Top 5, not 3 (Claude):** five rows fit a compact panel at 1280x720 without crowding the menu, and the board
  is still young (a top 3 would mostly show the owner's own runs). `BoardTop.SIZE` = 5.
- **What it shows (Claude):** the first map (Kirtag), solo, all time – the default view of the full board, so
  the panel and the board agree. Columns: place, name, result · Grant level, time; own entries in the accent.
  Header "Ehrentafel", line "De bestn 5 · Kirtag in Unterhinterkogl · allein", pill "Ganze Ehrentafel" opens the
  screen. One `Board.fetch` when the menu opens (every return from a run reloads the menu).
- **Where (Claude):** bottom right of the title screen, 64 px from the edges, only while no menu screen is open
  (it would sit under the screens otherwise). Hidden entirely when the board cannot be reached (desktop, local
  server, offline) instead of showing the offline line on the title screen; an empty board shows
  "Do steht no kana drauf. Sei du da Erste!".
- **Renamed:** menu entry and screen title "Rekorde" → "Ehrentafel"; tabs "Ehrentafel" (first, default, LB /
  Left) and "Eigene Rekorde" (second, RB / Right).
- **Board filters in two rows (Claude):** maps, then Allein/Familie and Ewig/Diese Woche. In one row they were
  wider than the menu's free area (cut off at 1280x720 and 1920x1080); unnoticed before because the board was
  the second tab.
- Patch note 1.3.2 on top of `patch_notes.tres`, version 1.3.2 in project.godot.
- **Measured** (local, RTX 3080): tests pass; browser check 180.4 fps, p95 6.9 ms, at most 101 draw calls;
  `mp_test -Clients 1` passes; `ui_shots -Only title,meta` pass at both sizes (screens checked by eye, with the
  board list proxied read-only from production to see real rows).

## 2026-11-05 – Nachspielzeit: the Stammgast-Geister after Sperrstund' (branch `nachspielzeit`, 1.3.2)

- **Owner asked:** what happens at 15:00, and whether a fast special enemy that one-shots the player
  would be better than the end screen just appearing. Claude researched Megabonk (its "Final Swarm":
  when the stage timer runs out, endless ghosts that speed up over time, red "overtime" ghosts later,
  rewards for lasting 1 / 2 / 6 minutes) and proposed a Nachspielzeit with the result locked at 15:00.
  **Owner: "build it like you suggested in your points".** Before: at 15:00 the crowd stopped, the
  Riesen-Wirt swept for 6 s, players were invulnerable, then the end screen came, which felt abrupt.
- **Claude: the result is settled at Sperrstund'.** At 15:00, WON if the Hofrat is beaten, else CLOSED,
  exactly as before; nothing in the Nachspielzeit can turn it into a loss. Leaving (menu, host gone)
  in the Nachspielzeit records that result too (before 15:00 leaving is still "QUIT").
- **Claude: the Nachspielzeit** (phase SPERRSTUND, no new phase on the wire). The Riesen-Wirt comes as
  before and his broom keeps sweeping the Kirtag crowd (no drops), but not the ghosts
  (`EnemyTypeData.stays_at_sperrstund`) or bosses (they stand and wait, as before). New spawns are only
  the wave's entries past minute 15: the **Stammgast-Geist** (white bedsheet ghost with his Krügerl,
  6 HP, 5.0 m/s, 8 damage, 1 XP) from 15:00, the **Grantiger Stammgast** (red, 12 HP, 6.4 m/s,
  24 damage, 5 XP; toast "D' Stammgäst wern grantig! Renn!") from 17:00 at a quarter of the mix and
  half from 19:00. Both fly (no slopes, no walls) and rise 8 m to players on roofs. Crowd:
  `overtime_start_count` 80 + 60 per minute, capped like the normal crowd. The Kirtag guests go
  home: every 0.5 s any ordinary enemy more than `overtime_leave_distance` = 25 m from every player
  leaves unseen (no drops), so the ghosts get the slots (found in the 4-player test: 572 old enemies
  kept every slot and almost no ghost came). Every
  `overtime_step_seconds` = 30 s every enemy moves 6 % faster (`EnemyManager.pace`, max 2x), hits 10 %
  harder and new ones bring 10 % more HP (on top of the per-minute HP). Players take damage again (the
  old rule made them invulnerable after 15:00). The Schunkel waltz speeds up with the pace (max 1.5x).
  Red for the grantige ghost: it is the deadliest enemy, so the danger colour fits; nothing friendly
  uses it.
- **Claude: down is out.** In the Nachspielzeit a knock-down is final: no respawn (also with
  `respawn=1`, so automated runs end), co-op teammates cannot wake you (`out` at once), and every
  Wirtshaus is shut from 15:00 (so no cash-in revive either). Item revives (Marterl-Kerze, Nachschlag)
  still work. When the last player falls: 2.5 real seconds of slow motion at 0.3x (`Engine.time_scale`;
  not in automated runs), then the end screen. Text when down: "Aussegschmissn! Des wor's …". A run
  nobody can lose (god mode) ends after `overtime_max_seconds` = 10 min.
- **Claude: what it pays.** 1 Schilling per second (`schilling_per_overtime_second`, before the Grant
  and co-op multipliers); the end screen shows a "Nachspielzeit" row (only when there was any); the HUD
  clock counts "+m:ss" with its arc blinking in the danger colour. The Ehrentafel already sorts by
  result, Grant, then time, so a longer Nachspielzeit ranks higher; `MAX_RUN_SECONDS` 960 → 1560
  (otherwise every run with more than a minute would have been refused). Three new Aufträge (quest kind
  `overtime`, minutes of Nachspielzeit in one run, per character or any; Profile `best.overtime`):
  "Nachspielzeit" (1 min, 150 S), "Sperrstund' ignoriert" (3 min, 400 S), "Oma bleibt sitzen"
  (3 min with Oma Resi, 300 S). Schilling only, no unlocks.
- **Claude: 18 enemy types per wave.** Every wave already listed 16 types, the snapshot's limit (4 bits
  of type, 4 of HP bucket). Snapshot v3 splits the byte 5 / 3: up to 32 types, 8 HP buckets (they only
  flash hit enemies on clients). Same bytes per enemy, so the bandwidth stays (57.5 KiB/s per client
  at 844 enemies was too close to 60 for an extra byte plane).
- **Claude: voices.** Seven new lines through the eSpeak pipeline (`geist`: airy, wavering, a big empty
  Gaststube; `geist_grantig`: lower, driven, shaking): "Mei Stammplatzl …", "Oa Krügerl geht no!",
  "Wer geht'n do scho ham?", "I kumm morgen wieder …" / "Wer sitzt auf mein Platz?!",
  "Sperrstund' gibt's ned!", "Zahln tu i nächste Wochn …" (0.22 MB).
- **Claude: `ui_shots.ps1`** has two new scenes, `overtime` (15:01+) and `grantig` (17:10+); `end` takes
  a second shot at 100 s (the bot now plays on into the Nachspielzeit before the end screen).
- **Claude: the Formular is moot past 15:00.** Stempel can no longer be picked up in the Nachspielzeit
  (the bot finished the Formular at 15:20 and "Formular komplett! Ab zum Gemeindeamt!" came up). A
  waiting boss can still be beaten (it counts for boss quests, not for the result).
- **Tuning (Claude, balance log, Ferdl / Kirtag / Grant 1, seeds 1-3; the bot never runs away from the
  ghosts):** first numbers (150 ghosts, 12 / 30 damage): level 50-54 bots lasted 9-14 s. With the
  numbers above and the guests going home: 15 s, 17 s and 1:56 (2,432 ghosts beaten; 922 Schilling).
  A player who runs is faster than the white ghosts (7 vs 5 m/s) until the pace catches up after some
  3-4 minutes. All numbers are in balance.tres / the ghosts' .tres for the owner's playtest.
- **Measured** (local, RTX 3080): tests 188/188; browser check 173.6 fps, p95 7.1 ms, at most 101 draw
  calls; `mp_test -Clients 1` passes (33.2 KiB/s, 0 pops); `mp_test -Clients 3 -StartTime 885 -Seconds 40`
  passes (clients through Sperrstund' into 29 s of Nachspielzeit, result CLOSED on every client, ghosts
  of type 16/17 over snapshot v3); `autoplay -Runs 3` passes; `ui_shots -Only hud,end,overtime,grantig`
  passes (no console errors, under 150 draw calls).
- **Preview:** https://nachspielzeit.knoedlinger.pages.dev (66737cd): browser check 177.6 fps, p95 7 ms,
  at most 102 draw calls, no console errors. Board tests 8/8 (`MAX_RUN_SECONDS` 1560).
- **Owner: this is 1.3.2, not 1.4.0.** It ships together with the Ehrentafel fix of the other session
  (branch `ehrentafel-menu`, also 1.3.2), so 1.4 stays for the new features of the 1.4 plan. The
  patch note is one `note_1_3_2`: that branch has lines `PATCH_1_3_2_01`/`_02`, this one `_03`-`_06`;
  whichever merges second joins the two line lists.

## 1.3.2 – merged with Nachspielzeit and released (2026-11-05)

- **Owner: approved** the Ehrentafel in the menu and asked to merge it with the other session's branch
  `nachspielzeit` (already renumbered to ship as 1.3.2) and to deploy to production. Both went into
  `ehrentafel-menu`, then `main` (e7b9098). Conflicts: the 1.3.2 patch note takes the Ehrentafel lines
  01-02 then the Nachspielzeit lines 03-06; both decisions entries kept; the translation regenerated
  from the merged CSV.
- **Merged code checked** (local, RTX 3080): tests pass, web export, browser check 182.5 fps / p95 6.9 ms
  / at most 103 draw calls, `mp_test -Clients 1`, `-Clients 3 -StartTime 595` and `-Clients 3 -Coop`
  pass, `board/test/board.test.mjs` 8/8 (`MAX_RUN_SECONDS` 1560 for the Nachspielzeit; no D1 migration).
- **Production deploy of 1.3.2** at the owner's word: https://knoedlinger.pages.dev serves e7b9098.
  Live browser check (headless Edge, 500 enemies, bot, 60 s): 176.3 fps, p95 6.9 ms, at most 100 draw
  calls, no console errors; the title screen shows the real top 5.
- `v1-4`'s Part 0 (fold in `nachspielzeit`) is now just merging `main` into `v1-4`.

## 2026-11-05 – Plan for 1.4.0 (branch `v1-4`, not started)

- **Owner asked** for a new milestone for the 1.4 features: more maps, weapons and characters, plus Claude's
  suggestions for new features and changes to existing ones, as a taskboard; planning only. Board:
  https://claude.ai/artifact/NJ8t1sgRXKVoU9d79ZEHWM (task ids below match it).
- **Owner: Nachspielzeit is part of 1.4** – the branch `nachspielzeit` (a931dba, already stamped 1.4.0, not yet
  playtested) is merged into `v1-4` as Part 0 and playtested with the Part 1 preview.
- **Owner: one branch `v1-4`** for the whole milestone, a preview deploy (`deploy_preview.ps1 -Branch v1-4`)
  and the browser check after every part, the owner approves part by part; one production release 1.4.0 at
  the end, only on the owner's word. Merge into `main` and delete the branch once 1.4 is approved.
- **Owner: Heuriger now, the Kurort map in 1.5.** Moved to 1.5 with it: task 1.2 (Kurort Bad Unterhinterkogl:
  Kurpark, thermal water that slows everyone and floats the Knödl, Seilbahn high route), 4.4 (Nordic-Walker,
  Handtuch-Reservierer, Kurgast im Bademantel, mini-boss Der Bademeister) and the Kurort music and Kurkarte item.
- **Owner: English later** (task 5.6, not in 1.4).
- **Owner: start only when told** ("go with 1.4 part 1"); the session is cleared before that.
- **Claude: the parts, in order** (P1 must, P2 should, P3 could; P3 slides to 1.5 first if 1.4 runs long).
  Every number below is a starting value and goes into `balance.tres` / the data files:
  - **Part 0 – Nachspielzeit** (0.1): merge `nachspielzeit`, re-run the tests, owner playtest.
  - **Part 1 – the Heuriger map** (1.1 P1, 4.1 P1, 4.2 P1, 4.5 P1, 6.1 P1 music):
    `tools/maps/make_heuriger.gd` on `map_kit.gd` → `data/maps/heuriger.tres`, `data/waves/heuriger.tres`.
    Terraced vineyards on 4–5 levels (the Knödl rolls down terraces), Buschenschanken as the Wirtshäuser,
    wine-cellar tunnels as shortcuts, boss gate at the Presshaus, Stempel on terrace tops. New enemies:
    Weinbergschnecke (slow, tanky, slime trail slows players), Star-Schwarm (Bröselfresser flock, loose Brösel
    first, then the Knödl), Wespe (fast, prefers the sweet Knödl sorts Marillen/Germ/Topfen). Mini-boss at
    10:00: Der Sturm (a whirlwind of young wine; pulls in Brösel and enemies, flings them out with a red spiral
    where they land; heavy Knödl sorts stay on the ground). Voice lines via `voices.py` (samples to the owner
    first). Music per map: Heuriger (Schrammel techno), Gamskogl (après-ski techno), Gemeindebau (Wienerlied
    beat) from `make_audio.mjs`, ~+1.5 MiB OGG. 1.3 map traits on the map select (P3).
  - **Part 2 – the family** (2.1–2.5): Opa Hias the Schrebergärtner (Gartenschlauch, Serviettenknödl, trait
    "Hat eh Zeit": +25 % attack speed after 1 s standing still; unlock: win on the Gemeindebau-Hof), Cousine
    Mitzi the Fiakerin (Fiakerpeitsche, Topfenknödl, "Trab": +20 % speed and Knödl damage after 2 s running
    straight, a sharp turn resets it; unlock: 2 min of Nachspielzeit in one run), Steffi the Winzerin (P2;
    Steirische Harmonika, Marillenknödl, "Ausg'steckt": every Wirtshaus serves her twice; unlock: win on the
    Heuriger). New Knödl sorts: Serviettenknödl (wide roll, sweeps a 2× strip, turns slowly, only rolls
    forwards), Topfenknödl (reel-in 0.5 s, half Schupfn cooldown, −25 % contact damage). Portraits with the
    family nose, barks, Almanach, the `_40` / `_sieg` Aufträge.
  - **Part 3 – weapons, stats, evolutions** (3.1–3.8): Gartenschlauch (sweeping stream, knockback, wet =
    −30 % speed for 2 s), Fiakerpeitsche (7 m lash, the last metre hits ×3), Steirische Harmonika (pulls
    enemies within 8 m for 0.6 s, then a damage ring pushes them out), Krapfen-Kanone (P2; 3 bounces, jam
    splash slows). Stats Seniorenteller (+XP from Brösel; no XP-gain stat exists yet) and Gummistiefel
    (+knockback, slowing ground slows you less), appended to the catalog. Evolutions for the start weapons
    without one: Schneeschaufel + Bergkas = Schneepflug, Skistöcke + Krügerl = Slalom-Gewitter, Tablett-Wurf +
    Kaffeehaus-Zeitung = "Zahlen, bitte!", Kuhglocke + Hufeisen = Almabtrieb. P2: Gartenschlauch + Gummistiefel
    = Hochwasser, Fiakerpeitsche + Spagat aus Hanf = Viererzug, Harmonika + Wanderkarte = Zeltfest,
    Krapfen-Kanone + Seniorenteller = Faschingsdienstag. P2 items: Leberkässemmel (20 HP per cash-in),
    Wetterfleck (no knockback on you), Rodel (Knödl gains speed downhill on the string) + two with visible
    effects.
  - **Part 4 – Die Hausmeisterin** (4.3 P1): the Gemeindebau-Hof's own mini-boss at 10:00 instead of
    Oberkrampus II (broom sweeps in red, locks a stairwell for 10 s, voice lines).
  - **Part 5 – features**: Daily Kirtag (5.1 P1: same map/character/Grant/seed for everyone per day, a daily
    Ehrentafel board on D1, first try counts, weekly streak Auftrag), Der Standler (5.2 P2: merchant at 3:00
    and 9:00, 3 items for gold, rising prices, own offer per co-op player), Marterl (5.3 P2: Mutprobe = 30 s
    ring wave → chest, Gier = 2× enemies and gold for 60 s, Segen = 1 of 2 stat boosts; 2–3 per map),
    Run-Abrechnung (5.4 P2: end-screen tab with damage per weapon, Knödl kills, top knock-down cause; same
    numbers in autoplay JSON), co-op pings (5.5 P3), family voices via eSpeak (5.7 P3).
  - **Part 6 – changes**: "Knödl folgt brav" (6.2 P1, GAME-DESIGN.md edge case never built; Spiel tab, off by
    default), armour check after the owner's 1.3.1 playtest (6.3 P1: `armor_half` 10 → 6 is the softer
    option), ~30 new Aufträge towards 300 (6.4 P1; 109 today), rebalance with autoplay on every map and
    character, new weapons within ±10 % of the average (6.5 P2).
  - **Part 7 – release**: 60 fps with 500 enemies + 300 projectiles and < 150 draw calls on the Heuriger,
    .pck < 15 MiB; tests, export, browser check per map, `mp_test -Clients 3 -StartTime 595` on the Heuriger,
    `mp_test -Coop`, ui_shots before/after; version stays 1.4.0 (from Part 0), patch-list entry on top.
- **Kept rules:** content as data, text through `tr()`, solo and co-op alike (host-authoritative), new enemy
  types as MultiMeshes (the snapshot allows 32 types since Nachspielzeit's codec v3), new catalog entries
  appended so save indices stay.

## 2026-11-05 – 1.4 plan addition: gold and chests (task 6.6 P1, part of Part 6)

- **Owner asked** how gold works ("I was never able to buy more than one chest") and how Megabonk does it;
  then: aim for ~15 chests a run so players always look out for chests. **Owner: no edge-of-screen chest
  arrow** (the 1.3.1 price pills within 45 m stay as they are).
- **Found (1.3.1 code):** coins only from 0.6 % of kills (`coin_drop_chance`, 1 gold each, ~1 per 170 kills),
  elites from 5:00 (`gold_drop` 1, Kontrolleur 3), bosses 25 / 40 / 80 (Oberkrampus, Oberkrampus II, Hofrat),
  skip 10, S cash-in 0.5 per mass. Coins only by walking (4 m magnet), the Knödl ignores them. 6 map chests,
  price 25 + 15 per map chest opened (`_chest_price`, `run_world.gd`); boss/Wirtshaus chests free and not
  counted; Zweitschlüssel free chests still count. A ~15.6k-kill bot run makes ~100 coin gold, mostly late:
  first chest after Oberkrampus at 5:00, the second (40) around 9-11 min. 1-2 chests per run is the norm.
- **Megabonk (fan wiki/guides, not all reliable):** many chests per stage, first 30 gold, price grows per
  *bought* chest (wiki table: #10 = 495, #30 = 21,249, ~×1.35 early, ~×1.2 later), free chests (Key, ~9 %
  each) do not raise it; gold from enemies (scales with stage and gold gain), pots, Greed shrine (+25 gold,
  +5 % difficulty), bosses/elites/challenge shrines; Shady Guy sells items. Income grows faster than the
  price, so chests stay a steady buy (25-chest achievement).
- **Balance check (Claude):** 15 chests are fine. Items are small (+4-15 % one stat; strong ones capped at
  1-3 stacks), ~15 extra items ≈ 5-8 Speisekarte levels on top of ~47, and Grant 1 is hard now (bot wins 3/10,
  ~28 knock-downs). Risks: **Sparbuch** (+3 % damage per chest opened *per stack*: 15 chests × 3 stacks =
  +135 %), **Zweitschlüssel** 5 stacks = 50 % free chests (compounds once free chests do not raise the price),
  Hofratswürdig items without a cap (Maibaumspitz +15 % damage) through more rolls with luck.
- **Changes (starting values, all in `balance.tres` / item data):**
  - Price: `map_chest_price` 25 → 20, price ×1.22 per *bought* map chest (new `map_chest_price_growth`,
    replaces the +15 step): 20, 24, 30, 36, 44, 54, 66, 80, 98, 120, 146, 178, 217, 265, 323 (~1,650 for 15).
    Free chests (Zweitschlüssel) do not raise it.
  - Chests: `map_chest_count` 6 → ~15, maps get ~15-18 chest spots each (Kirtag, Gamskogl, Gemeindebau and
    the new Heuriger; `map_kit.gd` overlap check).
  - Income: `coin_drop_chance` 0.006 → ~0.03; coin value grows with the clock (new `coin_value_per_minute`,
    ~1 at 0:00 → ~5 at 12:00; boss/elite gold unchanged to start); breakable props (Kirtag barrels / pots,
    pooled, host-owned like loot, a few gold each, respawning per map area) as a steady source.
  - Fixes: Sparbuch 0.03 → 0.015 per chest and `max_stacks` 2 (or a +30 % cap per stack); Zweitschlüssel
    `max_stacks` 5 → 3; watch Hofratswürdig items in autoplay, cap their stacks only if they dominate.
  - Targets: first chest ~1:30, then about one a minute; 12-15 chests in a good run; autoplay 10 seeds
    (Ferdl / Kirtag / Grant 1) before and after: wins 3/10 → ~4-6/10 (not 10/10), no single item making up
    most of a build's damage. Autoplay JSON gets `chests_bought` and `gold_earned`. Tune the gold numbers
    first, the price growth second.
  - Interplay with the 1.4 plan: the Standler (5.2) and the Marterl "Gier" (5.3, 2× gold) spend and make
    gold too; tune them after this, on the new income. Patch-list lines for the change; co-op: gold, prices
    and chests stay per player as now.
- **Note:** Part 0 of the plan above is already done (Nachspielzeit shipped in 1.3.2); Part 0 is now only
  "merge `main` into `v1-4`".

## 2026-11-05 – 1.4 plan addition: item rework (task 6.7 P1, part of Part 6, right after 6.6)

- **Owner asked:** items mostly give a stat bonus; they should do unique things (a one-time revive, flat HP
  per second, a 10 % chance for attacks to freeze an enemy, ...), focused on the rare/legendary ones like
  Megabonk; stat items are fine and needed. Does the current roster already have that? Compare with Megabonk.
- **Found (1.3.2 data, 34 items in `data/items/`):** 23 are pure stats (Doppler, Edelweiss, Feldstecher,
  Gleitschirm, Glücksschwein, Goldhaube, Haferlschuhe, Holundersaft, Kirtagsbrezn, Kracherl, Kuckucksuhr,
  Lebkuchenherz, Maibaumspitz, Rosenkranz, Sauerkraut, Schießbudenrose, Sonntagsgwand, Spielhahnfeder,
  Spitzwegerich, Trachtenjanker, Wetterhahn, Zirbenschnaps, Zuckerwatte); 11 have a rule, 7 of them Knödl
  upgrades (Bergab-Gesetz, Bröselbutter, Doppelportion, Omas Rezept, Powidl, Riesenknödl) plus Marterl-Kerze
  (revive), Kirchenglocke (ring every few s), Schweizerkracher (kill blast), Sparbuch, Zweitschlüssel.
  Of the owner's examples, the revive exists (Marterl-Kerze) and flat HP/s exists (the `regen` stat is HP per
  second: Holundersaft, Kirtagsbrezn, Spitzwegerich); **nothing procs on hit** (no freeze/burn/chain chance),
  nothing reacts to taking damage, low HP, crits, standing still, being airborne or cheating death.
  Rarity says little: 5 of 10 Edel items and Maibaumspitz (Hofratswürdig, plain +15 % damage) are stats only;
  three pairs are near duplicates (Kracherl/Zuckerwatte, Holundersaft/Kirtagsbrezn, Lebkuchenherz/Sauerkraut).
  Each `ItemData` has one `effect` name; every rule is hand-coded in `run_world.gd`. Already there to build on:
  `EnemyManager.slow()` (0 = frozen/stunned, bosses a third and never stopped), `burn()`, Krampusrute's chain,
  the pooled projectiles, `on_kill` (Schweizerkracher) and a timer (Kirchenglocke).
- **Megabonk (guides, ~77 items, Default/Common/Rare/Epic/Legendary):** Commons are mostly stats but with
  conditions (Idle Juice: up to +100 % damage standing still, Scarf: +33 % airborne, Tactical Glasses: +20 %
  vs enemies above 90 % HP, Campfire: standing still heals, Coward's Cloak: speed when hit, Electric Plug:
  shock when hit, Ice Cube: 20 % freeze on hit, Big Bonk: 2 % for 20× damage, Borgar: healing food on kill).
  Rares/Epics are procs and conditions (Spicy Meatball 25 % explode, Moldy Cheese poison, Thunder Mitts,
  Soul Harvester homing souls, Demonic Soul +0.1 % per kill, Gamer Goggles: more damage at low HP, Turbo
  Skates: speed → attack speed, Backpack +1 projectile, Overpowered Lamp: +1 proc chance, Shattered Knowledge:
  XP shards cut enemies). Legendaries change the rules (Za Warudo: freeze time instead of dying once, Mirror:
  reflect + short invulnerability, Joe's Dagger: 1 % execute, each +1 % damage, Anvil: upgrades roll +1 stat,
  Chonkplate: overheal, Holy Book: big HP/regen + healing hurts, Sucky Magnet: pulls all XP on screen).
- **Claude: the rework** (starting values, all in item data / `balance.tres`):
  - **Data, not code:** a new `ItemEffect` resource (`trigger`, `chance`, `action`, `value`, `radius`,
    `seconds`, `cooldown`) and `ItemData.effects: Array[ItemEffect]`, so new items are `.tres` only.
    Triggers: `on_hit`, `on_crit`, `on_kill`, `on_hurt`, `on_lethal`, `periodic`, `low_hp` (< 50 %),
    `standing_still`, `moving`, `airborne`, `on_chest`, `on_cashin`, `on_schupfn_end`, `on_brosel`.
    Actions: `freeze`, `burn`, `blast`, `chain`, `homing` (pooled projectile), `execute`, `heal`, `shield`,
    `invulnerable`, `time_stop` (enemies near the player frozen; no real time-slow, co-op shares one clock),
    `damage_mult` (conditional), `stat_buff` (timed), `pull_brosel`, `drop_food`. The 11 old rules move onto
    it (old `effect` field read as a fallback until all items are converted).
  - **Proc rules:** host only (procs are damage); chance per stack 1 − (1 − p)^n; procs never trigger procs;
    a per-frame proc budget (~40) and chain/homing target caps so 500 enemies + 300 projectiles stay at 60 fps;
    pooled VFX; frozen enemies tinted ice blue, burning orange (2 status bits in the enemy snapshot if not
    sent yet). Nothing friendly in Krampus red.
  - **Rarity means something:** Gewöhnlich = one stat; Fein = stat + a condition; Edel = a proc or rule;
    Hofratswürdig = build-defining, `max_stacks` 1. Pure stats move to Gewöhnlich/Fein; the near duplicates
    become new items (one of each pair keeps the stat).
  - **New/changed items (~20, roster 34 → ~50; names/lines are drafts, all appended so save indices stay):**
    - Fein: **Gfrorns** (10 % on hit: freeze 1.5 s; the owner's example), **Kachelofen** (standing still 1 s:
      +4 HP/s), **Bierdeckel** (+20 % damage to enemies above 90 % HP), **Hosenträger** (+25 % damage
      airborne), **Weidezaun** (when hit: shock 6 m), **Distelstrauß** (thorns: 50 % of contact damage back),
      **Jagdtrophäe** (+15 % vs elites/bosses), **Leberkässemmel** (3 % on kill: a Semmel that heals 15 HP;
      replaces the Part 3 draft "20 HP per cash-in").
    - Edel: **Sonnwendfeuer** (15 % on hit: burn), **Blitzableiter** (12 % on hit: chain to 3, Krampusrute
      code), **Scharfe Pfefferoni** (20 % of hits burst for 50 % around the target), **Irrlichter** (kills:
      15 % a homing wisp), **Stallaterne** (+50 % to every proc chance), **Letzte Runde** (up to +50 %
      damage as HP falls), **Strichliste** (+0.1 % damage per 10 kills, max +50 %), **Rucksack** (+1
      projectile for all weapons), **Schutzengerl** (when hit: 1 s invulnerable + 20 % speed, 6 s cooldown),
      **Bröselsturm** (Brösel flying to your Knödl cut enemies on the way; Knödl twist), **Wetterfleck**
      (no knockback on you; from Part 3), **Rodel** (Knödl speeds up downhill on the string; from Part 3).
    - Hofratswürdig: **Marterl-Kerze** (stays: revive, now with a blast and 2 s invulnerable), **Stehengebliebene
      Uhr** (lethal hit once: enemies within 15 m frozen 3 s, heal 30 %), **Amtsschimmel** (1 % execute on
      hit, non-boss; each execute +0.5 % damage, max +50 %), **Dreschflegel** (2 % of hits deal 15×),
      **Staubsauger** (every 45 s all Brösel on screen fly to your Knödl), **Amboss vom Dorfschmied** (weapon
      cards on the Speisekarte roll one extra bonus), **Federbett** (healing above max HP becomes a shield up to
      +50 % max HP), **Maibaumspitz** (keeps +15 % damage, adds +25 % while standing higher than the enemy hit).
  - **Co-op:** effects per player, host-authoritative; heals/shields on teammates only from items that say so
    (none in this batch); revive and time stop are local to the owner's position.
  - **Checks:** unit tests (proc odds per stack, no proc recursion, cheat-death once, item tooltip numbers),
    Almanach entries and icons for every new item, deadpan line each through `tr()`, Run-Abrechnung (5.4) and
    autoplay JSON get damage per item; autoplay 10 seeds before/after: no item above ~25 % of a build's damage,
    wins within the 6.6 target (~4-6/10); stress scene with 5 proc items stacked still 60 fps.
  - **Order:** after 6.6 (more chests make items matter), before the 6.5 rebalance; patch-list lines.

## 2026-11-06 – 1.4 plan additions: item text on pickup (6.7) and the pause menu with the build (task 6.8 P1)

- **Owner: an item must say what it does when you get it.** Checked: the chest reveal (`Speisekarte.show_chest`)
  shows only icon, name and rarity border and fades after 3.5 s; no item has a line with its numbers, only the
  deadpan `desc_key`, which the reveal does not show either. Added to **6.7**:
  - **Effect text from the data:** a `ItemText.describe(item, stacks)` builder writes the exact effect from
    `stats` and `effects` through `tr()` templates ("+10 % Glück", "10 % beim Treffer: 1,5 s einfrieren",
    "Einmal pro Lauf: …"), with the stacked value when you hold more than one ("2× → 19 %"). No hand-written
    number text, so tooltips never drift from the balance. The deadpan line stays below it, smaller.
  - **Chest reveal:** each item tile gets its effect line under the name (deadpan line only for a new item);
    the reveal stays ~6 s (+1.5 s per extra item, max 10 s), a first-time item gets a "Neu!" badge, and
    hovering or Tab keeps it. The Speisekarte's item cards and the Almanach use the same builder.
  - Co-op: the text is built on each client from its own data, the offer codec does not change.
- **Owner: the Esc pause menu shows the stats and the inventory, like the upgrade UI without the choice, and
  every tile can be hovered to see exactly what it does, with damage numbers for weapons.** New task **6.8 P1**
  in Part 6, right after 6.7 (it needs 6.7's effect text):
  - **Layout (Claude):** one shared `BuildView` (today's `InventoryPanel` + `StatsPanel`) used by both screens:
    Esc = the menu column (Weiter, Einstellungen, Zum Menü) with the build view beside it; Tab stays the quick
    look (same view, no menu). Solo pauses as today; co-op keeps running, as the pause menu does now.
  - **Details on hover / focus / tap:** a detail panel (fixed spot next to the grid, not a floating tooltip, so
    gamepad focus and touch tap work too): name, rarity border, level or stack count, the exact effect text,
    the deadpan line.
    - **Weapons:** damage per hit (`Formulas.weapon_damage` with the build's damage stat), attacks per second
      (after attack speed), projectiles/hits per attack, crit chance × multiplier, and a simple
      **DPS = damage × amount × (1 + crit chance × (crit mult − 1)) ÷ cooldown**; orbits and auras use
      `hit_interval` and say "pro Gegner", burn adds its share over `burn_seconds`. Below: **this run** –
      total damage and the DPS over the last 30 s, measured. The paper DPS ignores misses and pierce, so both
      are shown and labelled ("Theorie" / "dieser Lauf").
    - **Items with procs:** chance (after stacks and Stallaterne), cooldown, procs and damage this run.
    - **Stats:** current value and what it is made of (base, stat upgrade, items, Stammtisch), as the
      StatsPanel's card preview already does for the Speisekarte.
  - **Measured damage per source:** a per-weapon / per-item damage counter on the host, sent to each player
    with the existing per-player state (a few floats every ~1 s, reliable, not per hit). This pulls the
    counter from Run-Abrechnung (5.4 P2) forward; 5.4 then only adds the end-screen tab.
  - **Checks:** UI-STYLE.md (one theme, `theme_type_variation`, 8 px grid, rarity as border colour), fits at
    1280×720 with 4 weapons, 4 stats and ~30 items (item grid scrolls), keyboard/mouse, gamepad focus and
    touch; `ui_shots.ps1` before/after with a new `pause` shot (hovered weapon and item); unit tests for the
    DPS formula per pattern and the effect-text builder; `mp_test -Clients 1` (the counter reaches the
    client).
  - **Order:** after 6.7, before the 6.5 rebalance (the DPS numbers help tuning).

## 2026-11-06 – 1.4 Part 1: the Heuriger (branch `v1-4`, version 1.4.0)

- **Owner: "go with the 1.4 plan part 1"**, keep the session lean. Part 0 is just `main` (1.3.2) merged into
  `v1-4`; the DECISIONS.md conflict kept both sides (1.3.2 entries, then the plan).
- **Version 1.4.0 now** (Part 0 no longer stamps it): `project.godot` and the patch list carry 1.4.0 from Part 1
  on; the patch entry grows with every part (four lines so far).
- **Map: Heuriger in den Weinbergen** (`tools/maps/make_heuriger.gd` → `data/maps/heuriger.tres`). Five round
  terraces of 3 m (radii 74/60/47/34/21 m round (0, −40)) with the Presshaus = boss gate on top; ramps on every
  terrace edge, turned further round per level so the way up winds; two smaller vineyard hills (2 terraces)
  east and west; vine rows with gaps so the Knödl can roll down; the Heurigen-Ort with the Knödl stand in the
  south (spawn). Eight Buschenschank spots, Stempel on the terrace tops and side hills, 14 chest spots.
- **Claude: the wine-cellar tunnels are Kellergassen, not tunnels.** The terrain is a heightmap and cannot hold
  a real tunnel, so MapData got a small generic feature, `lanes` + `lane_shapes`: a straight strip whose ground
  rises evenly from one height to another and blends back at the sides. Two Kellergassen (SE and SW) run from
  the foot straight up to the fourth terrace (12 m over 55 m) – the shortcut – sunk into the terrace walls,
  with stone cellar portals where they cross a wall and Presshäuser at their foot.
- **Claude: Buschenschanken** are the normal Wirtshaus building plus a pole with a green Buschen over the
  door (`MapData.wirtshaus_buschen`), so the Wirtshaus code stays one.
- **Unlock: Auftrag "Weinlese" – win 3 runs** (Claude's choice; the other maps unlock by surviving 10 min and
  by 5 runs). Four more Aufträge: Schneckenpost (300 Weinbergschnecken), Starenplage (1000 Stare),
  Wespennest (500 Wespen), Sturmwarnung (beat Der Sturm) – 114 in all.
- **New enemies (data flags, so later maps can reuse them):**
  - Weinbergschnecke: 30 HP, speed 1.4, 5 XP. `slime_slow` 0.35: a slime trail slows players to 65 %.
    Claude: the trail is not sent over the network – every machine drops spots behind the snails it sees
    (host: EnemyManager, clients: the replica) and slows only its own player (`SlimeTrail`, one MultiMesh,
    spots last 5 s, every 0.5 s per snail, 0.9 m radius; numbers in `balance_data.gd`).
  - Star-Schwarm: 2 HP, speed 6.5, flier. `eats_brosel` 14 m: flies to the nearest loose Brösel and pecks it
    up (nobody gets that XP; `BroselField.steal`), and goes for the Knödl like a Taube only when none lie in
    reach.
  - Wespe: 4 HP, speed 7, flier. `sweet_tooth`: a Bröselfresser only for sweet Knödl (new sort flag `sweet`:
    Marillen- and Germknödl now; the Topfenknödl of Part 2 too); with no sweet Knödl about it chases players.
- **Mini-boss at 10:00 on the Heuriger: Der Sturm** (2800 HP, escort 10 Stare). A whirlwind of young wine:
  pulls enemies (with a swirl), loose Brösel and every Knödl that is not `heavy` (Speckknödl) within 18 m
  toward it (enemies/Brösel 5 m/s, Knödl 6 m/s² through `Knodl.wind`, the Föhn hook). Its attacks: a gust
  (5 scattered red circles) and the **spiral** – a new attack aim SPIRAL: 14 red circles on two turns out to
  22 m, each filling 0.08 s after the last; when it starts, what it pulled in is flung back out (enemies with
  14 m/s knockback, Brösel scattered up to 22 m, i.e. under the red marks). Brösel moves go to clients as
  re-sent Brösel, four times a second.
- **Voices** (`voices.py`, four new filters): Schnecke (slow, low, gooey), Star (high chirp), Wespe (buzzing),
  Sturm (breathy, tipsy, echoing); 13 lines. Owner asked in the plan for samples first – they are in the
  preview to listen to; any line can be redone.
- **Music per map** (`make_audio.mjs`, `MapData.music`): Heuriger = Schrammel techno (A major, 124 BPM),
  Gamskogl = après-ski techno (D major, 134 BPM), Gemeindebau = Wienerlied beat (A minor, 96 BPM, swung).
  +1.4 MiB OGG. The Kirtag keeps its track; the boss and Sperrstund' tracks stay shared.
- Not done in Part 1: map traits on the map select (1.3, P3) – slides to later as planned.
- **Owner approved Part 1 on 2026-11-06.** Next: Part 2 (the family) on `v1-4`.

## 2026-11-06 – 1.4 Part 2: the family (branch `v1-4`)

- **Owner: "continue with 1.4 part 2".** Three new Knödlinger, two Knödl sorts, twelve Aufträge (114 → 126).
- **Claude: the three start weapons come forward from Part 3** – a Knödlinger cannot be played without one.
  Part 3 keeps the Krapfen-Kanone, the two stats, the evolutions and the items. The new weapons are appended
  to the catalog and offered to everyone on the Speisekarte (like every other start weapon):
  - **Gartenschlauch** (ARC with the stream look, water blue): 0.4 s, 1.6 damage, 6 m, 45°, knockback 7,
    wet = 70 % speed for 2 s.
  - **Fiakerpeitsche** (ARC): 1.0 s, 3.5 damage, 7 m, 26°, 10 % crit; the last metre (`tip_length`) hits ×3
    (`tip_multiplier`); a second lash behind from amount 2.
  - **Steirische Harmonika** (RING): 2.6 s, 5 damage, 8 m; `pull_seconds` 0.6 at `pull_speed` 6 m/s draws
    everything in reach toward where it started, then the ring goes off there (knockback 16). The pulls wait
    in the weapon's mine list; the ring effect closes in during the pull, then plays outward as usual.
- **Knödl sorts (new `KnodlSortData` fields):**
  - **Topfenknödl:** `reel_time_mult` 0.33 (1.5 s → 0.5 s), `cooldown_mult` 0.5 (4 s → 2 s; the HUD ring
    uses the sort's cooldown), contact damage ×0.75, sweet (Wespen).
  - **Serviettenknödl:** a roll, not a ball. `width` 2: hits a strip twice its radius to each side (an
    ellipse on its heading; only the round core shoves enemies aside). `turn_rate` 2 rad/s: its heading
    turns slowly toward where it is pulled (a roll has no front, so rolling backwards needs no turn);
    `lateral_grip` 5/s: sideways speed dies off. Jolt still rolls a sphere; the look is a stretched roll
    laid across the heading and spinning about its long axis (clients take the heading from its movement).
- **Traits (`trait_effects`, timings in `balance_data.gd` → "Character traits"):**
  - **Opa Hias, Schrebergärtner** – Gartenschlauch, Serviettenknödl. "Hat eh Zeit" (`idle_rate` 0.25):
    after `idle_seconds` 1 s below `idle_speed` 0.4 m/s, +25 % attack speed (`PlayerBuild.trait_rate`,
    host). Unlock: **Schrebergarten** – win on the Gemeindebau-Hof.
  - **Cousine Mitzi, Fiakerin** – Fiakerpeitsche, Topfenknödl. "Trab" (`trot` 0.2): after `trot_seconds`
    2 s at 60 % of run speed or more without turning more than 35° off her line (the line follows a gentle
    curve), +20 % speed (her own machine) and +20 % Knödl contact damage (host, `Knodl.damage_bonus`).
    Every machine counts it from `motion_velocity`, so nothing new goes over the network; the 2× momentum
    cap already covers the pose check. Unlock: **Fiakerfahrt** – 2 minutes of Nachspielzeit in one run.
  - **Steffi, Winzerin** – Steirische Harmonika, Marillenknödl. "Ausg'steckt" (`serves_twice`): a
    Wirtshaus that has served once (anyone) serves her once more (host `_second_serves`). Unlock:
    **Ausg'steckt is** – win on the Heuriger.
  - `_40` / `_sieg` Aufträge for all three (300 / 200 Schilling).
- **Claude: no per-character barks.** The barks are shared lines (`bark_*.ogg`), not per character; family
  voices stay task 5.7 (P3). Portraits are drawn from the character colours (straw hat, Melone, Buschen
  green), so the family nose comes for free; the Almanach lists the new characters and weapons by itself.
- **Play screen:** 11 cards in 4 columns no longer fit at 1280×720 (the start button fell off the screen).
  The cards now always take two rows: up to 6 columns, 112 px wide once there are more than 4.
- **Checks:** 202 GUT tests (new `test_family.gd`: whip tip, Harmonika pull then blast, both sorts, Trab,
  standing still, unlocks), web export (.pck 7.4 MiB), browser check (default and `character=hias`: 180 fps,
  103 draw calls), `ui_shots -Only meta,coop,title`, `mp_test -Clients 1`.
- **Owner: everything new is locked behind an Auftrag** (asked first for a Part 7 "ask about unlocks", then
  withdrew it). So the three new weapons follow the start-weapon rule (Stempel, Obstler, Tablett): they reach
  everyone's Speisekarte once their Knödlinger reaches level 15 – **Gießdienst** (Hias → Gartenschlauch),
  **Fiakerprüfung** (Mitzi → Fiakerpeitsche), **Musikantenstammtisch** (Steffi → Harmonika), 100 Schilling
  each; the character still starts with it. Aufträge 114 → 126. Parts 3 and 6.7 lock their new content too.
  Note: in this plan 6.2 is "Knödl folgt brav"; no task covered the unlocks, so this is the standing rule.
- **Autoplay** (Kirtag / Grant 1, seeds 1-3, so rough): Ferdl level 47, 23 knock-downs, 14.1k kills, 0 wins;
  Hias 46 / 25 / 16.2k / 0; Mitzi 43 / 34 / 11.3k / 0 (weakest: the bot weaves, so the Trab rarely holds);
  Steffi 54 / 12 / 21.7k / 1 win (strongest: more cash-ins = more chests). Left as is for the owner's
  playtest; tuned with the 6.5 rebalance.
- **Owner, 2026-11-06: Part 2 approved.** From now on the remaining 1.4 parts go ahead **without approval
  per part** (each still gets its preview and checks); the owner does one final playtest of the whole 1.4
  before approving the production deploy. **Every part starts in a new session**, so a session builds one
  part, pushes it to the preview and stops.

## 2026-11-06 – 1.4 Part 3: weapons, stats, evolutions (branch `v1-4`)

- **Owner: "continue with 1.4 part 3".** Built in a new worktree branch from `origin/v1-4` (the `v1-4`
  worktree was still locked by the Part 2 session) and pushed back to `v1-4`.
- **Claude: the Part 3 items stay in 6.7.** Leberkässemmel, Wetterfleck and Rodel (and "two with visible
  effects") were taken over by the item rework (6.7 lists them), so Part 3 is weapons, stats and evolutions.
- **Every family start weapon now evolves** (weapon at the evolution level + its stat; data in
  `data/weapons/`, numbers are starting values, evolutions about 2-3× their base like the old ones):
  - **Schneepflug** = Schneeschaufel + Bergkas: ARC 200°, 6.5 m, 7.5 damage, 0.9 s, knockback 18, slows to
    50 % for 1.5 s (snowed in).
  - **Slalom-Gewitter** = Skistöcke + Krügerl: 3 spears (up to 9), 0.55 s, 4.5 damage, pierce 6, 15 % crit.
  - **"Zahlen, bitte!"** = Tablett-Wurf + Kaffeehaus-Zeitung: 8 boomerang trays 45° apart (a full ring),
    9 damage, 1.3 s.
  - **Almabtrieb** = Kuhglocke + Hufeisen: ring 9 m, 9 damage, 1.8 s, knockback 20, stuns 0.8 s.
  - P2 ones, all built: **Hochwasser** = Gartenschlauch + Gummistiefel (four streams round about, 8 m, 0.35 s,
    slow 50 % for 2.5 s), **Viererzug** = Fiakerpeitsche + Spagat aus Hanf (four lashes, 9 m, tip ×3 on the
    last 1.5 m), **Zeltfest** = Steirische Harmonika + Wanderkarte (pull 13 m for 0.8 s at 9 m/s, then 11
    damage), **Faschingsdienstag** = Krapfen-Kanone + Seniorenteller (3 Krapfen, up to 8, 5 hops, 2.3 m jam
    splash slowing to 40 % for 2 s).
- **ARC with more swings:** `amount` swings now share the circle evenly (`WeaponSystem.arc_turn`; two =
  front and back as before), so Viererzug and Hochwasser need no new pattern. One SwingVfx per possible swing.
- **Krapfen-Kanone (new weapon):** Claude: the plan's "3 bounces" became **3 hops along its line** rather
  than bounces from enemy to enemy – clients replay shots from the fire counter without knowing where the
  host's enemies are, so a shot that picks its next target would fly differently on every machine. A lobbed
  shot (`WeaponData.hops`, `hop_height`) hits nothing in the air and splashes `impact_radius` with the
  weapon's statuses at each landing; the landings follow from the aim, so the host's pool and every client
  draw the same arcs and the same jam splashes (WeaponVfx rings, delayed like mines). 1.5 s, 5 damage, 1.6 m
  splash, 12 m/s over 1.2 s (4.8 m per hop), slows to 60 % for 1.5 s, up to 5 Krapfen. Apricot jam colour
  (nothing friendly in Krampus red).
- **Two new stats** (appended to `PlayerBuild.STATS` and the catalog, so save indices stay):
  - **Seniorenteller** `xp_gain` +10 % per level: all XP a player gets (Brösel and the co-op share) is
    multiplied in `PlayerState.add_xp`.
  - **Gummistiefel** `knockback` +15 % and `sure_footing` +12 % per level. Knockback: `WeaponSystem.knock`
    is set per player while their weapons fire (lobbed shots carry it). Sure footing takes that share off a
    slowing ground (the snail slime): `slow' = 1 − (1 − slow) × (1 − footing)`, capped at
    `balance.sure_footing_cap` 0.8. Rows in the Werte panel: Rückstoß, Standfest, Erfahrung.
- **Locked behind Aufträge (owner rule)** – 11 new, 126 → 137. `PlayerBuild.evolutions_ready()` now skips an
  evolution that is still locked, so it is never offered (not even from an evolution chest):
  Winterdienst / Slalomkönig / Oberkellner / Viehscheid / Hochwasserschutz / Vierspänner / Bierzelt = level 30
  with Ferdl / Toni / Poldi / Vroni / Hias / Mitzi / Steffi → that character's evolution (200 Schilling);
  Germteig (a 1000-mass Knödl) → Krapfen-Kanone; Wespensommer (2000 Wespen) → Faschingsdienstag;
  Pensionsantritt (level 40) → Seniorenteller; Schneckenzaun (1000 Weinbergschnecken) → Gummistiefel.
  The four old evolutions stay open as before.
- **Checks:** 210 GUT tests (new `test_evolutions_1_4.gd`: every start weapon evolves, new content has text,
  icon and an Auftrag, locked evolutions never ready, four lashes, the Krapfen splashes only where it lands
  and lands every hop, XP gain, knockback), web export (.pck 7.5 MiB), browser check default (180 fps, 102
  draw calls) and with all nine new weapons at once (187 fps, 112 draw calls), `mp_test -Clients 1`,
  `ui_shots -Only menu,inventory` (the Werte panel with three more rows still fits at 1280×720).
- Patch-list lines 08-10 for 1.4.0.

## 2026-11-06 – 1.4 Part 4: Die Hausmeisterin (branch `v1-4`)

- **Owner: "continue with 1.4 part 4".** Built in the `v1-4-part3` worktree (tracks `origin/v1-4`).
- **The Gemeindebau-Hof's own mini-boss at 10:00** replaces Oberkrampus II there (the Kirtag keeps it):
  Die Hausmeisterin, 2600 HP, speed 3.6, escort 8 Kampf-Dackel, chest 3 items, 40 gold, 3 golden bits.
  Look: blue dotted Kittelschürze, headscarf with curlers, keys on the belt, the Besen held across.
  Attacks in turn: Besen, Teppichklopfer, Zusperren, Besen, Teppichklopfer (pause 1.8 s):
  - **Besen** – a fan of 5 red lines (12 m, 22° apart) that fill **one after the other** (0.12 s each), so
    it reads as a sweep. New: `AttackData.stagger` now also works for LINE fans (0 = all at once as before).
  - **Teppichklopfer** – 3 red circles round the target.
  - **Zusperren** – new aim `STAIRWELL`: a red line up the whole flight of the tall stairs/ramp nearest the
    target (within 45 m; 25 m was too short – a player in the middle of the Hof is ~40 m from every ramp, so
    she never locked), then that flight is **locked for 10 s** (`lock_seconds`): an iron gate at its foot
    and one at its top, sign "Frisch gwischt!". She skips the attack when no stairs are near or a lock runs.
- **Claude: the stairwells are found, not placed.** `StairLock` takes every solid RAMP/STAIRS prop at least
  `balance.stair_lock_min_height` (6 m) high from the map (Gemeindebau: 4 roof ramps, 2 corner stairs, 4 outer
  stairs), so no map data changed and any later map with tall stairs works. Gates are two pooled StaticBodies
  on LAYER_WORLD (players and Knödl); **enemies pass** – they walk the baked ground field, and they are her
  tenants anyway. Gate height `stair_gate_height` 3.2 m. Never red (not an attack): Gemeindebau green.
- **Claude: marks can lean.** A hazard got `base_y`/`rise`; a stairwell mark is tilted up the slope (a flat
  mark would float at roof height). Network: a new run event **LOCK** (u8 stairwell, telegraph, lock time;
  `RunEventCodec` VERSION 3) instead of a HAZARD – every machine builds the same mark and gates from its own
  copy of the map and closes them when the mark hits; Sperrstund' opens them.
- **Voices** (`voices.py`, filter "hausmeisterin": sharp, nasal, a stairwell echo): 6 lines (arrive, three
  attack lines, half health, beaten). Auftrag **Hausordnung** – beat her (150 Schilling), 137 → 138.
- `mp_test.ps1 -Map <id>` added (host and clients play that map) for `-StartTime 595` on a map's own boss.
- **Checks:** 216 GUT tests (new `test_hausmeisterin.gd`), web export (.pck 7.7 MiB), browser check default and
  `map=gemeindebau&start_time=595` (120 fps, ≤ 110 draw calls), `mp_test -Clients 1` and
  `-StartTime 595 -Map gemeindebau` (she arrives at 10:00, locks reach the client, 38.7 KiB/s). Browser shots
  show her, the sweep fans and the toast; the gate itself was not caught on camera (bot elsewhere).
- Patch-list line 11 for 1.4.0.

### 1.4: preview builds have everything unlocked (owner, 2026-11-06)
- **Owner:** a preview build, made only for playtest and approval, should have everything unlocked from the
  start – content that is unlocked late is hard to test.
- **Claude: decided at runtime by the page's address, not at build time**, because the same `build/web` goes
  to production after a merge. `Profile.unlock_all` is on when the host ends in `.knoedlinger.pages.dev`
  (branch aliases and per-deploy hash URLs), off on `knoedlinger.pages.dev` itself, localhost and desktop/
  headless runs. URL option `unlock_all=0|1` forces it either way.
- It only changes the answers of `is_unlocked`, `unlocking_quest` and `grant_unlocked` (all characters, maps,
  weapons, stats, items, Knödl and every Grant level); the save is not touched, so quests still count, stamp and
  pay, and a win still raises the saved Grant level. Stammtisch ranks (incl. weapon slots 3 and 4) stay bought
  with Schilling, so balance in a playtest stays honest. Console line `[PROFILE] preview build: everything unlocked`.

## 2026-11-06 – 1.4 Part 5: features (branch `v1-4`)

- **Owner: "continue with 1.4 part 5"** (the session was cut once by a power loss before anything was
  written). Built in the `v1-4-part3` worktree (tracks `origin/v1-4`). Done: 5.1 (P1), 5.2, 5.3, 5.4 (P2).
  **Claude: 5.5 co-op pings and 5.7 family voices (both P3) slide to 1.5**, as the plan allows for P3.
- **5.1 Die Tageskarte (Daily Kirtag)** – a menu entry under "Spielen" (`DailyScreen`):
  - `Daily.pick(day)`: Knödlinger, map, Grant level (`daily_grant_min/max` 1-2: Normal or Grantig) and seed
    follow from the **UTC** date ("YYYYMMDD", the same for everyone from midnight UTC), hashed with Godot's
    stable `String.hash()`. Claude: **any Knödlinger and any map can come up, locked or not** – the
    Tageskarte is a taste and unlocks nothing; the Speisekarte still only offers unlocked weapons/items.
    (Picking only unlocked content would differ per player, and the board needs the same card for all.)
  - **First try counts:** `Profile.start_daily(day)` notes the day when the run *starts* (leaving or a
    reload never gives a second first try); only that run asks for a board ticket. "Nochmal!" after it is
    practice (no ticket; `Board.forget()` drops any stale one). Solo only. A Tageskarte run does not
    overwrite the Play screen's last choice.
  - **Board:** a third mode `daily` in `board/board.js`, map key `daily_<YYYYMMDD>` – no D1 migration. A
    daily ticket is only given for today's key (or yesterday's in the first hour after midnight UTC), one
    name only. The screen lists the day's top 50 (BoardPanel with a fixed mode). The first try is enforced
    on the client only (a browser game cannot stop a cleared save; an IP rule would block households).
  - **Streak Aufträge** (kinds `daily_streak`, `daily_days`): **Stammkundschaft** – 7 days in a row (300 S),
    **Abonnement** – 30 days (500 S). Aufträge 138 → 140. Flag `daily=1` (`daily_day=YYYYMMDD` pins the day).
- **5.4 Run-Abrechnung** – built before the Standler because it measures everything after it:
  - Host counter in `EnemyManager`: callers set `source` (a small id, `RunWorld._source(peer, kind, id)`, per
    player × weapon / Knödl / "extra" = item rings, traits, reflects) before they hurt enemies; `dealt` and
    `source_kills` count only the HP an enemy really lost (no overkill). Shots carry their source
    (`ProjectilePool`), burns keep the one that lit them. Clients get their numbers in the existing run-end
    summary (`_shared_summary`), so nothing new goes over the network during the run (6.8 adds the live sync).
  - Knock-down cause: the enemy type whose touch or attack mark hurt last (`PlayerState.last_cause`).
  - End screen: tabs "Zahlen" / "Abrechnung" (Left/Right, LB/RB): damage, share and kills per weapon, the
    Knödl and "Sonstiges", and "Am öftesten umgfoin durch: …". Autoplay JSON gets `damage_by_source`,
    `kills_by_source`, `downed_by`, `standler_buys`, `marterl_used`.
- **5.2 Der Standler** (`RunSites`, numbers in balance "Der Standler"):
  - Sets up at 3:00 and 9:00, `standler_distance` 10 m from one player, stays 75 s: a stall with a green and
    white awning and a sign seen through walls (no edge arrow, the owner's 6.6 rule). Walking within 3 m opens
    his shop – the Speisekarte with a new offer type `SHOP` (prices after the cards, `OfferCodec` VERSION 3):
    3 items per player (**own offer per co-op player**), buy = PICK (the host checks the gold), "Na, danke" =
    leave (the shop stays shut until they step away). Level-ups wait while it is open; solo pauses, co-op
    has 12 s. Bought items leave that player's counter.
  - Price = by rarity 30 / 45 / 70 / 110 × 1.3 per item already bought from him × (1 + 4 % per minute).
    **Gold income is still the 1.3 one** (bot: ~0-10 gold at 5:00, a few hundred by the end), so few buys
    for now; the plan tunes him after 6.6 raises the income.
- **5.3 Marterl** (3 per run, on chest spots no chest took; one of each kind): stand at one for 1.5 s and it
  starts (its sign and coloured panel show the kind; the candle is lit while it works):
  - **Mutprobe** – 30 s, a ring of 16 of the current main fodder 14 m out every 5 s, then a free chest
    (at least Fein) on the spot.
  - **Gier** – 60 s of twice the crowd (within the slot cap) and twice the gold per coin.
  - **Segen** – Claude: a **free Speisekarte round** (one level's worth of cards) for the one who prays,
    instead of "1 of 2 stat boosts": stat slots are limited to 4, and a free pick reuses everything
    (offers, co-op, the bot). Two cards instead of three would need a new offer size; left as is.
  - New run event `SITE` (site, index, state, extra, x, z; `RunEventCodec` VERSION 4) for both the stall and
    the Marterl; a client arriving later gets them re-sent like the loot. Note for 6.6: Marterl take chest
    spots, so the ~15-chest maps need ~3 spots more.
- **Bot:** goes to a Marterl within 40 m and to Der Standler (once per visit) when it can pay his cheapest
  item; buys the cheapest it can afford, else leaves.
- **Menu at 1280×720:** with nine entries the footer (name, Schilling, version) fell off; below 820 px of UI
  height the column now keeps half its margins and 16 px gaps.
- **Test hooks:** `standler_at=<s>` (he sets up at that second right where the first player stands),
  `marterl_drill=<kind>` (the first Marterl, of that kind, at the spawn), `gold=<n>` (start gold).
  `mp_test.ps1 -Sites` uses them: every client must see the stall and the Marterl, and a client must buy
  from him through the host. `ui_shots` got `bill`, `shop`, `marterl`; its menu paths moved one entry down
  (`meta` now ends on the Tageskarte).
- **Checks:** 230 GUT tests (new `test_part5.gd`: the day and its card, first try and streak, the streak
  Aufträge, damage per source incl. burns and no overkill, the shop codec and buying, prices, the SITE
  event), board tests 9/9 (daily mode), web export (.pck 7.7 MiB), browser check 169 fps / ≤ 112 draw calls,
  `ui_shots` (meta, settings, patches, title, bill, shop, marterl: no console errors, ≤ 106 draw calls),
  `mp_test -Clients 1`, `-Clients 1 -Sites` (the client bought from him: its own items at its own prices),
  `-Clients 3 -Coop`, one autoplay run (Kirtag / Ferdl: 2 Standler buys, 1 Marterl, all 14,275 kills
  attributed, top knock-down cause Radler 6×).
- Patch-list lines 12-15 for 1.4.0.

## 2026-11-06 – 1.4 Part 6: changes (branch `v1-4`)

- **Owner: "continue 1.4 part 6"** (interrupted once mid-session, then "continue please"). Built in the
  `v1-4-part3` worktree (tracks `origin/v1-4`). Done: 6.6, 6.7, 6.8, 6.2, 6.3, 6.4, 6.5 (measured, see below).
- **6.6 Gold and chests** (numbers in balance "Loot"):
  - Price `map_chest_price` 20 × `map_chest_price_growth` 1.22 per **bought** chest (replaces the +15 step;
    `Formulas.chest_price`). Free chests (Zweitschlüssel) do not raise it: `PlayerState.chests_bought`
    next to `chests_opened` (Sparbuch still counts every opened one), both in the world state
    (`WorldStateCodec` VERSION 7, PLAYER_SIZE 73 with the Federbett shield byte).
  - `map_chest_count` 6 → 15. Maps got 6-8 more chest spots each on the bot's lanes (Kirtag 25, Gamskogl 22,
    Gemeindebau 22, Heuriger 21: 15 chests + 3 Marterl + room to vary); only the spot lists changed.
  - Coins: worth `coin_value` + `coin_value_per_minute` 0.33 per minute (1 at 0:00, ~5 at 12:00), drop
    chance 0.006 → 0.01; no kill coins while 400 loot items lie around (`coin_loot_cap`; loot capacity
    256 → 512, so boss chests and Stempel always find a slot).
  - **Fassl** (new loot kind, appended): 5 barrels stand 14-40 m from the players (one every 8 s, far ones
    go), walking into one or rolling the Knödl over it bursts it into 2 coins. The bot breaks those within
    18 m. One more MultiMesh (+1 draw call).
  - Sparbuch 0.03 → 0.015 per chest, `max_stacks` 2; Zweitschlüssel `max_stacks` 5 → 3.
  - **Claude: `schilling_per_gold` 0.5 → 0.1** – Schilling is paid from gold earned, so the new income
    would have paid ~10× the Schilling; at 0.1 a run pays about what it did (bot: ~360 → ~340-520).
  - Bot: walks to an affordable chest within 70 m (was 40; players see price pills at 45 m). Autoplay JSON:
    `gold_earned`, `chests_bought`, `chests_opened`, `chest_times`; the table shows chests and gold.
  - Measured (5 runs each, Ferdl / Kirtag / Grant 1): first tuning (0.03 coins, 8 Fassl × 3 coins) gave
    3,700-5,300 gold and 9-14 chests; at 0.015 / 6 × 2 still 2,700-4,900 gold with 2,300-4,400 unspent and
    6-10 chests, first chest at 1:34-2:01 (target ~1:30). Cut again to 0.01 / 5 Fassl.
- **6.7 Item rework** – new `ItemEffect` resource (trigger, action, chance, value, radius, seconds, cooldown,
  cap) in `ItemData.effects`; the host runs them in `ItemProcs`:
  - Hooks: `EnemyManager.damage()` logs weapon hits (not burn ticks, not the Knödl's spikes) for sources whose
    owner holds on-hit items and multiplies hits by per-source target bonuses (healthy 90 %+, elite/boss,
    standing lower); kills carry their source (`kill_source`). `prepare()` before the weapons (conditional
    damage `PlayerBuild.cond_damage`, regen, periodic, shield share, Rodel), `after_hits()` after the
    projectiles, `on_kills()` before the Brösel; hurt, lethal (before the Marterl-Kerze), revive, cash-in and
    Brösel hooks. Proc damage goes out under the item's own source, which logs no hits: **procs never
    trigger procs**. `item_proc_budget` 40 procs a frame, `item_cue_budget` 6 effects a frame. Chances stack
    1 - (1 - p)^n, values add up, `cap` limits.
  - **Claude: the 11 old named rules stay on `ItemData.effect`** (they are data already and work); new rules
    use `effects`. Marterl-Kerze and Maibaumspitz got effects on top (revive blast + 2 s invulnerable;
    +25 % against lower enemies, `max_stacks` 1).
  - Look: frozen enemies ice blue and still, burning ones orange (shader `INSTANCE_CUSTOM.w`); the snapshot
    got a status plane (`SnapshotCodec` VERSION 4, 6 bytes per enemy, mostly zeros). New cue SPARK (a small
    ring) for chains, bursts, executes, wisps.
  - 26 new items (roster 34 → 60), all as in the plan, each behind its own Auftrag: Fein Gfrorns, Kachelofen,
    Bierdeckel, Hosenträger, Weidezaun, Distelstrauß, Jagdtrophäe, Leberkässemmel, Wetterfleck; Edel
    Sonnwendfeuer, Blitzableiter, Scharfe Pfefferoni, Irrlichter, Stallaterne, Letzte Runde, Strichliste,
    Rucksack (new counted stat `amount`: +1 piece for every weapon, also drawn on clients), Schutzengerl,
    Bröselsturm, Rodel; Hofratswürdig Stehengebliebene Uhr, Amtsschimmel, Dreschflegel, Staubsauger, Amboss
    vom Dorfschmied (a weapon card adds a second mod: the weapon's least-raised one), Federbett (shield from
    overhealing, synced, takes hits first).
  - **Claude, deviations:** Leberkässemmel 0.5 % per kill (3 % dropped ~450 Semmeln a run); Wetterfleck
    has no "no knockback" (players are never knocked back) – it is +50 % Standfest and 20 % of hits heal 8;
    Schutzengerl is 1.5 s invulnerable (6 s cooldown) without the speed boost (movement is the client's, a
    timed buff would need its own sync). Smoke runs: Weidezaun dealt more than any weapon (4,433 in 60 s)
    → ×0.8 every 2 s (was ×1.5 every 1 s); Pfefferoni 50 → 40 % splash.
  - Rarity reshuffle: Doppler, Edelweiss, Gleitschirm, Spitzwegerich, Trachtenjanker (pure stats) Edel →
    Fein. The near duplicates became rule items: Zuckerwatte (+8 % damage while moving), Kirtagsbrezn (+30 HP
    per cash-in), Sauerkraut (2 HP/s below half HP).
  - **Effect text from the data:** `ItemText.describe()` writes every stat, old rule and effect through
    templates (`IFX_WHEN_*` + `IFX_DO_*`, German number format, stacked values). Used by the chest reveal
    (effect lines under each item, "Neu!" and the one-liner for a first find; 6 s + 1.5 s per extra item,
    max 10 s; hovering keeps it), the Speisekarte/Standler footer, the Almanach and the build view.
- **6.8 Build view** (`BuildView`: inventory | detail panel | stats) in the Esc pause menu (beside its
  entries, now 240 px wide) and the Tab screen. `TileGrid` tiles can be picked by mouse, tap or pad/keyboard
  focus (accent ring); items scroll past 5 rows. Weapons: damage per hit, attacks per second, pieces, crit,
  burn, "Theorie" DPS (`Formulas.weapon_dps`; orbits per enemy) and "Dieser Lauf" total and last-30-s DPS
  measured. Items: effect text, chance with Stallaterne, procs and damage this run. Stat upgrades: the stat
  now and its parts (stat upgrades, items, Stammtisch). Measured numbers: the host sends a new `DAMAGE` run
  event (peer, source kind, index, total, procs; `RunEventCodec` VERSION 5) once a second per weapon / Knödl
  and on change per item; every machine keeps them in `DamageLedger`.
- **6.2 Knödl folgt brav** (Spiel tab, off by default): rides in the player's input as `BUTTON_FOLLOW`; the
  host pulls that player's Knödl on the string toward the nearest Brösel within string reach
  (`knodl_follow_pull` 18).
- **6.3 Armour: `armor_half` 10 → 6** (the plan's softer option): the owner left no 1.3.1 feedback on
  armour, and the bot wins 0-1 of 5 runs against the 4-6 / 10 target.
- **6.4 Aufträge 143 → 173:** one per new item (26) and Truhnkönig (200 chests), Goldene Nasn (50,000 gold),
  Wallfahrt (50 Marterl), Guter Kunde (30 Standler buys). New quest kinds `chests`, `chests_run`, `gold`,
  `standler`, `marterl` (Profile counts them per player; clients get them in the shared summary; Standler and
  Marterl are now counted per player).
- **6.5 Rebalance (measured):**
  - New weapons against the 15 older start weapons in a held crowd of 250 at 10:00 (90 s, Ferdl + the
    weapon, `start_time=600`; at 0:00 fodder dies to one hit, so the counter measures coverage, not damage).
    Older ones average 5,824 but range 918 (Würstel) to 15,170 (Sachertorte). Base damage: Gartenschlauch
    1.6 → 2.7 (5,603, −4 %), Fiakerpeitsche 3.5 → 6.6 (6,138 / 5,403 on two seeds), Steirische Harmonika
    5.0 → 2.1 (its pull makes it coverage-bound and noisy: +44 % … −36 % between 2.4 and 1.8),
    Krapfen-Kanone 5.0 → 5.9 (6,250, +7 %). **Not touched (outside 6.5's "new weapons"), for the owner:**
    Würstel, Krampusrute and Skistöcke measure far below, Tablett and Sachertorte far above.
  - Autoplay after everything (Ferdl / Kirtag / Grant 1, 5 runs): 10-14 chests, gold earned 1,381-3,895
    (500-2,300 left unspent: the bot only walks to chests it sees), first chest 0:55-2:53, Schilling
    191-587, knock-downs 16-29, wins 1/5 (target 4-6 / 10 not reached; left to the owner's playtest after
    the armour change). No item in any run's top 4 damage sources. One run per other map: Gamskogl / Toni 6
    chests, Gemeindebau / Hias 11 (Hausmeisterin beaten), Heuriger / Steffi 6 (45 knock-downs: the Heuriger
    is the hardest map for the bot).
- **Bot:** a Marterl within 40 m now comes before affordable chests (70 m) and Fassl (18 m): with start gold
  `mp_test -Sites` saw the host bot buy five chests and never pray.
- **Checks:** 241 GUT tests (new `test_part6.gd`: prices, coin value, chests bought on the wire, Fassl, proc
  odds, hit log and target bonus, shield, Amboss and Rucksack, every item's text, DPS per pattern, the
  ledger and the DAMAGE event), web export (.pck 7.9 MiB), browser check 160 fps / ≤ 123 draw calls and
  165 fps / ≤ 118 with seven proc items stacked, `ui_shots` (pause, inventory, menu, shop, settings, meta,
  late, hud: no console errors, < 150 draw calls; before shots of the old pause/Tab screens from the Part 5
  preview in `build/shots/ui/before6`), `mp_test -Clients 1` (33.7 KiB/s at 498 enemies), `-Clients 3
  -Coop`, `-Clients 1 -Sites`, autoplay as above.
- Patch-list lines 16-21 for 1.4.0.

## 2026-11-06 – 1.4 Part 7: release checks (branch `v1-4`)

- **Owner: "continue with 1.4 part 7"**. Built in the `v1-4-part3` worktree (tracks `origin/v1-4`).
- **New test flag `projectiles=<n>`** (Claude): a real run only had the weapons' 8-20 shots in flight even
  with six projectile weapons and three Rucksäcke, so "500 enemies + 300 projectiles on the Heuriger" could
  not be measured. The host now keeps n of the stress test's shots flying from the players (same feeder as
  the M0 arena, "Sonstiges" damage; the pool grows by n). `browser_check -Projectiles 300` already put it in
  the URL; the run ignored it until now.
- **Performance (RTX 3080, headless, 500 enemies, bot plays, 60 s):** Heuriger + 300 projectiles Edge
  140.7 fps (p95 8.5 ms, ≤ 135 draw calls, ~297 shots in flight), Firefox 116.3 fps (p95 11 ms, ≤ 126);
  without the extra shots Kirtag 157.7 / Gamskogl 149.1 / Gemeindebau 161 / Heuriger 144 fps, ≤ 129 draw
  calls, no console errors. Budget 60 fps / < 150 draw calls: passed on every map.
- **Size:** `.pck` 7.92 MiB (target < 15), largest file the wasm part 9.68 MiB (limit 25).
- **Multiplayer:** `mp_test -Clients 3 -StartTime 595 -Map heuriger` passes (Der Sturm, 238 attack marks,
  26 loot and the same enemy lines on every client, 843 / 843 enemies, version refusal); 58.6 KiB/s per
  client with 843 enemies (1.3: 57.2-57.5 at ~845, +1 KiB/s from Part 6's status plane; ~34 KiB/s at 500,
  the budget's figure). `-Clients 3 -Coop` (revive, 2 passes, 6 merges, Familienstreit), `-Clients 1
  -Sites`, `-Clients 1` pass. `browser_mp_check -Tabs 4` through a local relay: host 102 fps, clients
  132 fps, ≤ 136 draw calls, every tab shows 4 Knödl and all 329 enemies.
- **Tests:** 241 GUT tests pass.
- Version stays 1.4.0; the 1.4.0 patch note (21 lines, Parts 1-6) is on top; Part 7 adds no line.
- **ui_shots:** before = the live 1.3.2 site (`build/shots/ui/before7`: hud, busy, menu, inventory, end, the
  maps, late), after = this build (`after7`, every scene at both sizes; `after7b` end, bill, coop after the
  fix below). No console errors, every shot < 150 draw calls (co-op HUDs 88). The co-op step failed once
  because `wrangler dev` could not start during an internet outage; it passed on the rerun.
- **Fixed:** the end screen's two tabs (Zahlen / Abrechnung) had different heights, so switching moved
  both panels by ~120 px. `RunEndScreen._even_tabs()` measures both over two frames while the screen fades
  in and gives each the taller height.
- **Seen, left for the owner (not new in 1.4):** an enemy line said right at the top left of the view shows
  through the HUD's see-through panel (the label is behind the HUD, just visible); the centre banner
  ("Z'wenig Gold fürs Kistl!") can cross an enemy line for a moment.
- Final build: 241 tests, Heuriger 500 + 300 at 154 fps / ≤ 130 draw calls, `mp_test -Clients 1` 36.6 KiB/s.

## 1.4.0 – released (2026-11-06)

- **Owner: playtest approved, "push to production".** `v1-4` merged into `main` (392b5b4, same tree as the
  checked 66274af; `main` had not moved since 1.3.2, so the full Part 7 suite stands). The patch note's date
  06.11.2026 is the release day already; version 1.4.0.
- **Production deploy of 1.4.0** at the owner's word: https://knoedlinger.pages.dev serves the Part 7 build
  (with the board Functions). Live browser check (headless Edge, RTX 3080, 500 enemies, bot, 60 s): 173 fps,
  p95 7.1 ms, at most 118 draw calls, no console errors; `/api/board` answers. Relay and D1 unchanged.
- Branch `v1-4` deleted (local and GitHub) with the finished worktrees `v1-4`, `v1-4-part3`,
  `v1-4-gold-plan`, `v1-4-item-plan`.

## 2026-11-06 – Plan for 1.4.1 (branch `v1-4-1`, not started)

- **Owner asked** for a plan for the next update 1.4.1: bug fixes, balance and other small changes. The
  concrete items are added here over time; the lists start (nearly) empty.
- **Claude: what belongs in 1.4.1** – a patch release (CLAUDE.md versioning): fixes, balance numbers, small
  UI/quality-of-life changes and test/tool fixes. No new maps, characters, weapons, enemies or items, and no
  save or network format change that breaks 1.4.0 players beyond the normal version refusal; those go to
  1.5 (the Kurort map and its content already wait there).
- **How it runs:**
  - The owner adds items ("add to 1.4.1: …"); Claude appends them below with the next free id (B = bug,
    A = balance, C = small change), what was seen and where, and asks only when the wanted result is unclear.
  - Work starts only when the owner says so ("go with 1.4.1", or a named batch). Branch `v1-4-1` from `main`;
    the first session sets `application/config/version` to 1.4.1 and opens a 1.4.1 patch note on top of the
    patch list (`data/patch_notes/patch_notes.tres` + `PATCH_1_4_1_*` in `i18n/strings.csv`), one line per
    player-visible item.
  - Every batch: tests, web export, browser check, `mp_test -Clients 1` (plus `-Coop` / `-StartTime 595`
    / `-Sites` when the item touches co-op, the timeline or the sites), `ui_shots` before/after for UI
    items, autoplay before/after for balance items (numbers in this log), preview
    `deploy_preview.ps1 -Branch v1-4-1`, then report and stop.
  - Owner playtests the preview; production only on the owner's word: merge into `main`, deploy, live
    browser check, delete the branch, pull the owner's checkout. A blocking bug in production can ship
    alone as 1.4.1 (the rest then moves to 1.4.2).
- **Bugs (B):**
  - B1 (candidate, seen in 1.4 Part 7, not new in 1.4): an enemy line said right at the top left of the
    view shows through the HUD's see-through corner panel.
  - B2 (candidate, same): the centre banner ("Z'wenig Gold fürs Kistl!") can cross an enemy line for a
    moment.
  - B3 (owner, 2026-11-07): **the Speisekarte picks a card by itself** – often, right as it opens, a card
    is taken while the player is still jumping (Space) or walking (WASD). Likely cause (to confirm):
    Space is Godot's `ui_accept`, and a row gets the focus from the arrow keys (also movement) or the
    mouse, so the next Space presses it. Fix: the first ~0.5 s after opening nothing picks; afterwards
    a card is taken only with 1–4, a mouse click / tap, or pad A (after its existing delay). Space,
    Enter and the movement keys never pick. Solo and co-op the same; the bot unchanged.
  - B4 (owner, 2026-11-07): **end screen buttons not clickable with a long list** – a long run's list
    pushes the panel past the bottom of the screen. `RunEndScreen` has no ScrollContainer. Fix: the panel
    gets a maximum height (screen minus the margins), the list scrolls inside it (wheel, drag, pad), and
    the buttons stay fixed below the list. `ui_shots end,bill` at 1280x720 with a long run (many items).
  - B5 (owner, 2026-11-07): **co-op runs start before everyone has loaded** – `NetworkManager.start_run`
    starts the host's run at once, and the clock runs while slower clients are still loading the scene
    (`_in_run` already tracks who has arrived). Fix: every player's run waits frozen behind a "Warten auf
    …" panel with the missing names until all clients report the run loaded, then the clock starts for
    everyone on the same signal. A timeout (~45 s) starts without a client that never arrives (it gets the
    normal disconnect). Check: `mp_test -Clients 3` with an artificially slow client, `browser_mp_check`.
- **Balance (A):**
  - A1 (owner, 2026-11-06): **rebalance the old weapons that measured far off** in 1.4's 6.5 test (held crowd
    of 250 at 10:00, 90 s; older-weapon average 5,824): too weak Wiener Würstel (918), Krampusrute,
    Skistöcke; too strong Tablett-Wurf, Sachertorte-Mine (15,170). Claude offered 3 options per weapon
    (numbers only / a mechanic / a third way); **the owner picked Claude's favourites**, all numbers are
    starting values:
    - Würstel **"Mit Senf"**: every chain jump splashes ~1.2 m at 50 % damage (crowd value; sets it apart
      from the Krampusrute).
    - Krampusrute **forks**: from the 2nd jump on, each jump splits in two (no enemy hit twice per cast).
    - Skistöcke **two poles**: `amount` 1 → 2 side by side, pierce 2 → 4; Slalom-Gewitter checked to stay a
      step above.
    - Tablett-Wurf **full tray**: at most 12 hits on the way out and 12 back (pierce 99 → a per-leg cap),
      then it flies home without hitting.
    - Sachertorte **smaller blast**: `impact_radius` 3.6 → 2.6, damage 16 → 14.
    - Why: the weak ones get something visible instead of bigger numbers, the strong ones are cut only in
      big crowds, where they were too strong, so early runs feel the same. Co-op: the splash and the fork
      are host hits drawn from the existing CHAIN impacts; the tray cap is host-side only. Target band 4,500–7,500 in the same test (the old
    weapons have different jobs, so wider than the ±10 % used for the new ones); all five re-measured
    before and after, plus autoplay with a character who starts with each (Toni for the Skistöcke, Poldi
    for the Tablett).
  - A2 (owner, 2026-11-07): **more chests, fewer useless coins late.**
    - Today: 15 map chests per run, all placed at 0:00 (`map_chest_count`), each gone once anyone buys it;
      price 20 × 1.22 per own purchase. Coins: 1 % per kill, worth 1 + 0.33 per minute, so late kills pay
      a lot; autoplay ends with 500–3,650 unspent gold.
    - Wanted: (1) chests also appear after 10:00 – a second batch (start value ~5, more per extra player)
      at free chest spots, shown on the minimap. (2) **Co-op: every player can buy every chest for
      themselves** at their own price; a chest a player has opened shows as opened only for them (the
      chest keeps an "opened by" bitmask in its loot events; network change, fine with the version
      refusal). (3) The coin drop chance follows the player's gold: when the gold already covers the next
      chest price twice, kill coins for that player drop at a fraction (e.g. ×0.3); elite and boss coins
      unchanged. Coins near nobody poor count the closest player.
    - Checks: autoplay before/after (unspent gold at 15:00, chests bought per run, wins), `mp_test
      -Clients 3 -Sites` (each client buys the same chest), `-Coop`.
  - A3 (owner, 2026-11-07): **more ways to heal.** Today the only healing drop is the Gulasch (0.15 % per
    kill, 35 HP) plus items/stats; without a +HP item a run often stays low. Owner's idea: small hearts
    (+5 HP) that drop more often and are pulled from far away. Claude's take (to agree with the owner):
    small Lebkuchenherzerl (+5 HP), **drop chance rising as the nearest player's HP falls** (none at full
    HP, most below ~40 %), so the map is not covered in hearts and a strong player gets no free sustain;
    pulled from ~8 m (bigger than coins, not the whole screen). Gulasch stays as the big heal. Host-side
    like every loot; each heart heals the player who picks it up. Checks: autoplay knock-downs per run
    before/after (16–29 now), win rate.
  - A4 (owner, 2026-11-07, from Claude's suggestion S6): **keeping a big Knödl pays off – hard hits,
    above all on elites and bosses.**
    - Seen: the Knödl does only 10–23 % of a run's damage in 1.4 autoplay, and the bot cashes in about
      once per run. In code, Knödl contact damage is `knodl_contact_damage` (1.0) × speed × radius × the
      sort's multiplier × (1 + `damage_bonus`), and `damage_bonus` is only the "trot" character trait:
      the damage stat (Jagatee), Stammtisch damage and damage items do **not** reach the Knödl.
    - Owner: not cashing in with a big Knödl should be very good and deal good damage, even more against
      elites and bosses.
    - Plan (starting values, tuned by measurement):
      - The player's damage multiplier (stat, Stammtisch, items) also counts for the Knödl.
      - Size pays more than linearly: from tier L on the radius counts stronger (e.g. radius^1.5 above
        the L radius), so a kept XL Knödl hits clearly harder than two small ones.
      - Elites take ×2 and bosses ×3 from Knödl contacts (`knodl_elite_mult`, `knodl_boss_mult` in
        balance), with a heavy hit cue (sound, bigger damage number, small camera nudge). One hit on a
        boss is capped (e.g. 4 % of its max HP) so a merged co-op Riesenknödl does not erase a boss in
        two passes; the existing hit cooldown stays.
      - The Wirtshaus marker shows the reward tier your Knödl has reached ("L → Kiste + Rerolls"), so the
        choice keep / cash in is visible (the second half of S6).
    - Co-op: Knödl damage is already host-side; the hit cue goes out with the existing hit events.
    - Checks: unit tests for the formula (stat multiplier, size curve, elite/boss multiplier, boss cap);
      autoplay before/after: the Knödl's share of damage (10–23 % now; target ~25–35 % when a big one is
      kept), boss kill times, wins; `mp_test -Coop` (merged Knödl against the boss cap).
  - A5 (owner, 2026-11-07, from Claude's suggestion S4): **mini-bosses knock players down too often.**
    - Seen (1.4 autoplay): Der Sturm caused 15 of 45 knock-downs in one Heuriger run, the Lawine 5 on the
      Gamskogl, the Oberkrampus up to 5 on the Kirtag (at 5:00, the first wall).
    - In the data, no single hit is the problem: the bosses' marks warn 1.0–1.4 s (elites 0.7–1.1 s) and
      hit for 14–26 of 100 HP. So the knock-downs come from hits in a row, body contact, or Der Sturm
      pulling players in (`pull_speed` 5 m/s, radius 18 m) while its crowd keeps hitting.
    - Plan: first the log names the cause per knock-down (which attack, body contact or crowd while
      pulled; `downed_by` gets the attack id), then the culprit is softened, e.g. Der Sturm's pull on
      players 5 → 3.5 m/s, a short grace after a boss hit (~0.6 s without boss damage), or gaps between
      the Oberkrampus' attacks. Warnings stay Krampus red and readable; Grant levels keep their scaling.
    - Checks: autoplay per map before/after (knock-downs by boss, wins; Heuriger, Gamskogl and Kirtag),
      `mp_test -StartTime 595` (bosses on clients unchanged).
- **Small changes (C):**
  - C1 (owner, 2026-11-06): **Krapfen-Kanone aims into the crowd.**
    - Owner first asked for the Krapfen to bounce between enemies; Claude pointed out that is exactly the
      Würstel's and the Krampusrute's CHAIN pattern (and the Würstel measured weakest in 6.5), so the owner
      chose **option A**: the Krapfen keeps its straight lobbed hops (its identity: splash + jam on groups),
      but each one is **aimed at the thickest part of the crowd** within its reach instead of the nearest
      enemy, so the hops run through the crowd instead of beside it. Hops still follow from the aim, so
      clients keep replaying shots from the fire counter – no network change. Faschingsdienstag the same.
    - **Dropped (owner, same day): a shared "+1 Hupfer" level mod** for hops/jumps (Krapfen, Würstel,
      Krampusrute, with `amount` turned into "more sausages" for the CHAIN weapons). "+1 Projektil" already
      does the job – more Krapfen for the Kanone, one more jump for the CHAIN weapons – and every extra mod
      kind makes the other mods rarer on that weapon's cards. The Würstel's weakness (6.5) is a balance item
      if the owner wants it, not part of C1. Upgrades of the Krapfen-Kanone stay as they are.
    - Checks: a unit test (aims at the densest cell, hops land in it), a 10:00 damage measurement against
      the 6.5 number (5,603-6,250 range for the new weapons), `mp_test -Clients 1` and `-Coop` (clients
      still draw the same arcs).
  - C2 (owner, 2026-11-07): **smaller, shorter chest pop-up.** The chest reveal (`Speisekarte.show_chest`)
    is a big panel that stays 6 s + 1.5 s per extra item (max 10 s, hovering keeps it) and covers the
    play area. Wanted: smaller tiles, placed in the upper part of the screen (under the boss bar), about
    2.5 s for one item + 1.5 s per extra item (max ~6 s), and never over the middle of the screen where
    the player stands. `ui_shots` before/after at both sizes.
  - C3 (owner, 2026-11-07, from S8): **setting "fewer effects".** Today Einstellungen only has "reduce
    flashing"; with 1.4's proc items, sparks, hail and damage numbers crowd the screen by minute 10. New
    options: "Schadenszahlen: alle / nur Krit / aus" and "Item-Effekte: voll / weniger" (fewer and fainter
    proc VFX; hits and damage unchanged). Purely local display, so co-op is unaffected; saved in the
    settings. Auto-quality may pick "weniger" on weak devices. `ui_shots settings,late` before/after.
  - C4 (owner, 2026-11-07, from S12): **remind players to save their code.** Progress lives in the browser
    (IndexedDB); clearing the cache wipes it, and the export code is only in Einstellungen → Spielstand.
    After a big moment (first Knödlinger unlocked, then every 10 Aufträge) the main menu shows a small
    note "Spielstand sichern?" with "Code kopieren" and "Nimma erinnern". Remembered in the save; never
    during a run.
  - C5 (owner, 2026-11-07, from S13): **"Neu!" on the patch list after an update.** The save remembers the
    last version whose patch list was opened; while the game is newer, the menu's patch-list button gets
    a small "Neu!" tag. First start on a fresh save shows no tag. Makes balance changes like A1 visible.
- Taskboard for the owner: https://claude.ai/artifact/NUU2WXcPqcVtBSzAeXB3ww (mirrors these lists; updated
  in the same session as any change here).
