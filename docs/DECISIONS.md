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
