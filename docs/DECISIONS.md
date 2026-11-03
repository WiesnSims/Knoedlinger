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
