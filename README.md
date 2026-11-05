# Knödlinger

*Bis zur Sperrstund'!* A 3D browser survivors-like with a dumpling on a string. Godot 4 web build, hosted on Cloudflare Pages.

- Design: [GAME-DESIGN.md](GAME-DESIGN.md) · decisions and numbers: [docs/DECISIONS.md](docs/DECISIONS.md) · working rules and commands: [CLAUDE.md](CLAUDE.md)

## Play (M2: the core loop)

| Action | Keys |
| --- | --- |
| Move (relative to the camera) | WASD |
| Jump | Space |
| Schupfn / reel the Knödl back in | Shift or right click |
| Look around | Mouse (click into the game once; Esc lets go), or Q / E |
| Zoom | Mouse wheel |
| Speisekarte (level-up) | 1 / 2 / 3 or click · R: Nochmal bitte · B: Des mog i ned · N: Danke, passt eh |
| Cash in the Knödl | Roll it onto the glowing mat in front of an open Wirtshaus door |
| Debug overlay | F3 |

URL flags for testing: `?bot=1` (a bot plays), `?god=1`, `?knodl_mass=500`, `?enemies=500`, `?debug=1`,
`?start_time=880` (start the clock late, e.g. to see Sperrstund' and the Nachspielzeit), `?scene=stress` (the M0 stress arena).

## Toolchain

| Tool | Version |
| --- | --- |
| Godot | 4.7.2.stable, official web export templates |
| GUT | 9.7.1 (`addons/gut`) |
| Node | 24.21 |
| Playwright | 1.64.1 (`tools/browser`), Edge channel + Firefox |
| wrangler | 4.156.2 (via `npx`) |

## Quick start

```powershell
cd tools/browser; npm install; npx playwright install firefox; cd ../..
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_web.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/browser_check.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/mp_test.ps1 -Clients 1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/autoplay.ps1 -Runs 3
```

Logs go to `build/logs/`; every script exits 1 on any error or warning.
