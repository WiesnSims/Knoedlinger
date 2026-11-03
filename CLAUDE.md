# Knödlinger

3D survivors-like (roguelike, auto-attacks, hundreds of enemies, constant level-ups) set in an Austrian village apocalypse. Solo or online co-op with 1–4 players; solo is fully supported. The twist: your XP is a physical Knödl that rolls behind you on a string, grows, crushes enemies, can be thrown (Schupfn) and cashed in at a Wirtshaus.
Godot 4 (latest 4.x stable, at least 4.6) + GDScript, **web build only** (Compatibility renderer / WebGL2, single-threaded export), hosted on Cloudflare Pages.

The full game design is here and must be followed:
@GAME-DESIGN.md

`docs/DECISIONS.md` records every decision and change made along the way – what the owner decided, what Claude chose, and why (newest at the bottom). Create it in M0 if it does not exist. Read it at the start of a session before changing anything; GAME-DESIGN.md says what the game is, DECISIONS.md how we got there and the exact numbers.

## How to work
- Work milestone by milestone (GAME-DESIGN.md, "Milestones and instructions for Claude Code", M0–M6). Co-op itself is M6, but every system is built co-op-ready from M0 (see Networking rules). Finish and test one milestone before starting the next.
- M0 is a go/no-go stress test for Godot in the browser. If it misses the performance budget after optimisation, stop and report – do not continue with M1.
- At the end of each milestone, produce a working web export, deploy it to a Cloudflare Pages **preview** URL, run the browser check, and summarise what to playtest (with the preview link).
- Work on a milestone branch. When I approve the milestone, merge it into `main` and then delete the branch (no tags needed). Always push `main` to GitHub after completing a milestone or merging into `main`.
- Production deploys only when I explicitly say so.
- If you need something from me (Godot export templates, Cloudflare login/API token, a GitHub repo, paid assets, voice recordings, a design decision), ask clearly and specifically instead of guessing.
- When a design question is not answered in GAME-DESIGN.md, make a sensible choice, note it in `docs/DECISIONS.md`, and tell me.
- Before building the deploy pipeline or the networking, look at how the previous web game **Berghittn** solved Godot export + Cloudflare Pages + the 25 MiB file limit and its 1–4 player browser co-op, and reuse those approaches. If you cannot find that project, ask me where it is.

## Code conventions
- GDScript with static typing everywhere (`var speed: float = 5.0`, typed function signatures).
- Code, comments, file and node names in English. Player-facing text in German/Austrian dialect, always through the translation system (`tr()` + `i18n/*.csv`), never hard-coded.
- snake_case files and functions, PascalCase classes and nodes.
- Characters, weapons, passives, evolutions, Knödl sorts, enemies, waves and quests are data-driven `Resource`s (`.tres`) in `data/`. All balance numbers live in `data/balance.tres`. Adding content must not require code changes.
- No real people, brands or band names in any content (see humour rules in GAME-DESIGN.md).
- Every gameplay feature must work in both solo (host only) and co-op – solo is just a host with zero clients.

## Networking rules
- Host is authoritative for world state (enemies, Brösel, Knödl physics, bosses, timer, chests, Wirtshäuser, damage). Each player owns their own input and character movement; the host validates.
- All gameplay talks to the `NetworkManager` autoload; transport code lives only in `net/`. No gameplay code may assume a single local player.
- Enemies are synced as compressed snapshots of the packed arrays (~15 Hz, unreliable channel), spawns/deaths as reliable events. Budget: < 60 KB/s per client at 500 enemies.
- Browser transport: reuse Berghittn's solution; otherwise `WebRTCMultiplayerPeer` + a signaling server on Cloudflare (Worker + Durable Object) that hands out 4-letter room codes.
- Keep a WebSocket backend working at all times – it is the main way to test multiplayer headless without browsers.
- Room codes and the handshake always carry `game=knoedlinger` and `ver=<version>`; reject mismatched versions.
- Never add a paid service (e.g. a TURN relay) without asking me first.

## Performance rules (web, non-negotiable)
- Enemies are data, not nodes: packed arrays in `EnemyManager`, rendered with one `MultiMeshInstance3D` per enemy type. Never one `CharacterBody3D`/`RigidBody3D` per enemy.
- Collisions between enemies, projectiles, Brösel and the Knödl go through the spatial hash grid, not the physics engine. Jolt physics only for player, Knödl and terrain.
- Projectiles, Brösel, damage numbers and VFX are pooled. No `instantiate()`/`queue_free()` in hot paths.
- Fodder animation in the vertex shader; skeletons only for player and bosses.
- Budgets: desktop browser 60 fps with 500 enemies + 300 projectiles; mobile browser 30 fps with 200 enemies; < 150 draw calls.
- Only use features the Compatibility renderer supports (no compute shaders, no Forward+-only effects). Test in the actual web export, not only in the editor.
- No C#, no GDExtension, no threads in the web build.

## Hosting rules (Cloudflare Pages)
- **No file in the deploy folder may exceed 25 MiB.** Check this on every export; the build script must fail if any file is larger.
- Keep the `.pck` small by design (low-poly vertex-coloured models, OGG audio, no large textures). Target < 15 MiB.
- Single-threaded export, so no COOP/COEP headers are required. Cache headers go in `_headers`.
- Save data lives in `user://` (IndexedDB in the browser) and must also be exportable/importable as a code.

## Commands
Scripts in `tools/` are created during M0 (PowerShell, logs in `build/logs/`, exit code 1 on any error or warning). Keep this list up to date when you add or change scripts.
- Run tests: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
- Export web build: `godot --headless --export-release "Web" build/web/index.html`
- Local multiplayer test: start one instance with `-- --net=ws --host` and others with `-- --net=ws --join=127.0.0.1`
- Scripts (built in M0 unless marked; all take `-Url <preview url>` where a browser is involved):
  - `tools/run_tests.ps1` – GUT tests
  - `tools/build_web.ps1` – import, web export to `build/web/`, gzip + split the wasm (Berghittn's `pack_wasm.mjs`), fail if any file > 25 MiB
  - `tools/browser_check.ps1 [-Browser msedge|firefox] [-Url <url>] [-Scene run|stress]` – serve `build/web/` locally (or use `-Url`), load it in headless Edge via Playwright, the bot plays a run with 500 enemies for 60 s, fail on any console error or fps below budget, screenshot to `build/shots/`
  - `tools/stress_test.ps1 [-Enemies 500] [-Projectiles 300] [-Browser msedge,firefox] [-Url <url>] [-Native]` – M0 scenario in Edge + Firefox, reports fps, frame times, draw calls and ms per system to `build/perf/`
  - `tools/mp_test.ps1 -Clients 3` (add `-HostLeavesFirst` for the host-quits case, `-Scene stress` for the M0 arena) – headless WebSocket host + clients play a run with bots; checks enemy sync, bandwidth, world states, the Brösel mirror, every Knödl shown, no rejected poses, version refusal and that no client errors
  - `tools/deploy_preview.ps1 -Branch <milestone>` – 25 MiB check, then `npx wrangler pages deploy build/web --project-name=knoedlinger --branch=<milestone>`; URL saved to `build/logs/last_preview_url.txt`. Refuses `main`.
  - Planned: `tools/mp_test.ps1 -Coop` – headless co-op scenario: revive, Knödl-Pass, Riesenknödl merge, shared XP
  - Planned (M6): `tools/browser_mp_check.ps1 -Tabs 4` – 4 headless browser tabs join one room via the real relay and play 60 s
  - Planned: `godot --headless -- --autoplay --runs=20` – bot plays runs and writes stats (time, level, death cause, Knödl cash-ins) to `build/balance/` for tuning
- Browser URL options mirror the command line: `index.html?enemies=200&bot=1`. The run is the default scene (`scene=stress` for M0's arena). Run flags: `bot=1` (the bot plays), `debug=1` (F3 overlay on), `god=1`, `knodl_mass=500`, `enemies=500` (hold a fixed crowd), `character=ferdl`, `seconds=60` (print a [RESULT]).
- One-time setup: `npm install` in `tools/browser/`, then `npx playwright install firefox` (Edge is used as installed). Set `GODOT` if `godot` is not on PATH.
- Run scripts with `powershell -NoProfile -ExecutionPolicy Bypass -File tools/<script>.ps1`
- Test runs must never disturb the user at the PC: prefer `--headless` and headless browsers. When a visible window is unavoidable, keep it small, unfocused, without mouse capture and muted.
- Before saying a task is done: run the tests, the web export, the browser check and a headless multiplayer test (`mp_test.ps1 -Clients 1` at minimum), and fix any errors or warnings in the output.
