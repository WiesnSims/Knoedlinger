# Decisions

Every decision and change along the way: what the owner decided, what Claude chose, and why. Newest at the bottom.
GAME-DESIGN.md says what the game is; this file says how we got there and the exact numbers.

## 2026-11-03 – Project start (M0 planning)

- **Owner: co-op transport is Berghittn's WebSocket relay over a Cloudflare Durable Object, not WebRTC.**
  One WebSocket per player to a relay DO per room, reached through a Pages Function on
  `knoedlinger.pages.dev/api/room/<code>`; helper Worker without public route. Proven in Berghittn, 0 € on
  the Workers Free plan, works behind strict NATs without a (paid) TURN relay.
- **Owner: room codes are 4 letters** (Berghittn used 4 digits). Claude: alphabet without the ambiguous I and O.
- **Owner: private GitHub repo `WiesnSims/Knoedlinger`; Cloudflare Pages project `knoedlinger`** on the Berghittn account.
- **Owner: project folder renamed to `Knoedlinger`** (no umlaut, avoids path encoding trouble in PowerShell 5.1 and tools).
- **Owner: test hardware** is an RTX 3080 with a 144 Hz monitor, Microsoft Edge and Firefox (no Chrome), phone Pixel 9 Pro.
  "60 fps desktop" is judged in Edge and Firefox on this machine; browser automation uses Playwright's `msedge` channel.
- **Owner: GUT and Playwright (Chromium/Edge + Firefox) may be installed.**
- **Toolchain:** Godot 4.7.2.stable (official, export templates installed), Node 24.21, wrangler 4.156.2, GUT 9.7.1.
