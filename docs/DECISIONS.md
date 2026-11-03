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
