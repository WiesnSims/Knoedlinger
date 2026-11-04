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
- **Not touched here:** the first minutes (a parallel session adds early-game easing to `balance.tres`).
