# UI screenshots for checking the look against docs/UI-STYLE.md: serves build/web (or uses -Url) and
# takes a fixed set of moments in headless Edge at every size: the HUD in play, the HUD with the
# Formular / boss / markers (from 10:00), the Speisekarte with a hovered card, the Inventory/Stats
# screen (Tab), the end screen, the touch controls and the settings tabs, and co-op (M6, `coop`: two
# players through the real menus and a local relay, the room and both HUDs; tools/browser/coop_shots.mjs). PNGs go to build/shots/ui/<Name>/<scene>-<size>-<s>s.png.
# Fails on console errors and on any moment at 150 draw calls or more (the web budget, UI included).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/ui_shots.ps1 [-Name after] [-Url <preview url>]
#        [-Sizes 1920x1080,1280x720] [-Only hud,menu]
param(
    [string]$Name = 'current',
    [string]$Url = '',
    [string]$Sizes = '1920x1080,1280x720',
    [string]$Only = '',
    [int]$Port = 8062,
    [int]$RelayPort = 8791
)
. "$PSScriptRoot\common.ps1"

$log = New-LogFile 'ui_shots'
$failures = @()
$server = $null
if ($Url -eq '') {
    $server = Start-WebServer -Port $Port -Log $log
    $Url = "http://127.0.0.1:$Port/"
}
$outDir = Join-Path $BuildDir "shots\ui\$Name"
New-Item -ItemType Directory -Force $outDir | Out-Null
# Scene name, query, shot times (s after page load), what to do before each shot.
$common = 'bot=1&respawn=1&debug=0&mute=1&seed=3'
$scenes = @(
    @{ Id = 'hud'; Query = "$common&knodl_mass=160"; At = '30' },
    @{ Id = 'busy'; Query = "$common&start_time=598&god=1"; At = '34' },
    @{ Id = 'menu'; Query = "$common&pick_delay=90"; At = '22,24'; Move = 'center,card' },
    @{ Id = 'inventory'; Query = "$common&knodl_mass=160"; At = '40'; Press = 'Tab' },
    # 1.3.2: Sperrstund' settles the result, then the Nachspielzeit runs until the bot falls (a fresh
    # level-1 bot lasts some 30-60 s), then the end screen with its Nachspielzeit row.
    @{ Id = 'end'; Query = "$common&start_time=891"; At = '32,100' },
    # 1.4: the end screen's second tab, the Run-Abrechnung (damage per weapon, the knock-down cause).
    @{ Id = 'bill'; Query = "$common&start_time=891"; At = '100'; Press = 'ArrowRight' },
    # 1.4.1 (B4): a long run's end screen (36 items): the list scrolls inside the panel, the buttons stay
    # on screen; the Run-Abrechnung too.
    @{ Id = 'endlong'; Query = "$common&start_time=891&items=amboss,amtsschimmel,bierdeckel,blitzableiter,distelstrauss,doppler,dreschflegel,edelweiss,federbett,feldstecher,gfrorns,gleitschirm,gluecksschwein,goldhaube,haferlschuhe,holundersaft,hosentraeger,irrlichter,jagdtrophaee,kachelofen,kirchenglocke,kirtagsbrezn,kracherl,kuckucksuhr,leberkaessemmel,lebkuchenherz,maibaumspitz,pfefferoni,rosenkranz,rucksack,sauerkraut,schiessbudenrose,sonntagsgwand,sparbuch,stallaterne,zuckerwatte"; At = '100,102'; Press = ',ArrowRight' },
    # 1.4.1 (C2): the bot with plenty of gold buys map chests; the smaller reveal under the top edge.
    # 1.4.1 (C6): the bot at 9:58 without god mode gets hit: the edge glow, the blink, the white HP chunk.
    @{ Id = 'hit'; Query = "$common&start_time=598"; At = '20,21,22,23' },
    @{ Id = 'hitdrill'; Query = "$common&knodl_mass=160&god=1&hit_drill=1"; At = '24,24.15,24.3,24.6,25,25.3' },
    @{ Id = 'chest'; Query = "$common&gold=3000&god=1"; At = '30,32,34,36,38,40,42,44' },
    # 1.4: Der Standler right where the bot stands (it has gold and waits on his shop), then a Marterl
    # by the spawn (the bot prays at it: a Mutprobe with its rings).
    @{ Id = 'shop'; Query = "$common&standler_at=2&gold=200&pick_delay=90"; At = '24,26'; Move = 'center,card' },
    @{ Id = 'marterl'; Query = "$common&marterl_drill=0&god=1"; At = '20,30' },
    # The Nachspielzeit itself: the clock counting on past 15:00, the white Stammgast-Geister, and from
    # 17:00 the grantige red ones.
    @{ Id = 'overtime'; Query = "$common&start_time=891&god=1"; At = '30,40' },
    @{ Id = 'grantig'; Query = "$common&start_time=1030&god=1"; At = '30,36' },
    # The new weapon effects (impacts, chain bolts, mines, the boomerang tray) in a held crowd.
    @{ Id = 'weapons'; Query = "$common&weapons=hagelkanone,krampusrute,sachertorte,tablett&enemies=250&god=1"; At = '22,23' },
    # The maps of M4 (the bot plays on them).
    @{ Id = 'gamskogl'; Query = "$common&map=gamskogl&knodl_mass=160"; At = '24,34' },
    @{ Id = 'gemeindebau'; Query = "$common&map=gemeindebau&knodl_mass=160"; At = '24,34' },
    # 1.4: the Heuriger, early (Wespen, Stare) and at 10:00 with Der Sturm.
    @{ Id = 'heuriger'; Query = "$common&map=heuriger&knodl_mass=160"; At = '24,34' },
    @{ Id = 'sturm'; Query = "$common&map=heuriger&start_time=598&god=1"; At = '12,16,20' },
    # A minute into a run with quick picks: weapon level cards with their rolled gain, then the build.
    @{ Id = 'late'; Query = "$common&pick_delay=1.5&god=1"; At = '70,71,72,73,74,110'; Press = ',,,,,Tab' },
    # Enemy lines over their heads (EnemyVoices; voice_every makes them talk often enough to catch).
    @{ Id = 'voices'; Query = "$common&knodl_mass=160&god=1&voice_every=1"; At = '26,29,32,35' },
    # 1.4: the pause menu with the build view: a weapon picked (its numbers), then an item (its effect),
    # then the settings from the menu.
    @{ Id = 'pause'; Query = "$common&knodl_mass=160&items=gfrorns,blitzableiter,amboss,rucksack,stallaterne,sparbuch"; At = '24,26,28,31'; Press = 'Escape,ArrowRight,ArrowDown+ArrowDown,Escape+Escape+ArrowDown+Enter' },
    # M5: the touch controls (a real finger holds the stick and walks), then the three settings tabs.
    @{ Id = 'touch'; Query = "$common&knodl_mass=160&touch=1"; At = '24,30'; Touch = $true; Press = ',drag:{sx}:{sy}:{sx2}:{sy}:600' },
    @{ Id = 'settings'; Query = 'mute=1&debug=0'; At = '12,15,17,19'; Press = 'type:Resi+Enter,ArrowDown+ArrowDown+ArrowDown+ArrowDown+ArrowDown+ArrowDown+Enter,KeyE,KeyE' },
    # A plain start (fresh browser profile): the name prompt, the menu, Spielen, Einstellungen.
    # Then back, Spielen, "Auf geht's!": the run started from the menu.
    # The meta screens of a fresh profile: Stammtisch, Aufträge, Ehrentafel (then Eigene Rekorde), Almanach, then
    # the Tageskarte (1.4, the second entry).
    @{ Id = 'meta'; Query = 'mute=1&debug=0'; At = '12,15,18,21,23,26,29'; Press = 'type:Resi+Enter,ArrowDown+ArrowDown+Enter,Escape+ArrowDown+Enter,Escape+ArrowDown+Enter,ArrowRight,Escape+ArrowDown+Enter,Escape+ArrowUp+ArrowUp+ArrowUp+ArrowUp+Enter' },
    # 1.3.1: the patch list ("Was is neu?", the eighth entry since 1.4), at the top and scrolled down.
    @{ Id = 'patches'; Query = 'mute=1&debug=0'; At = '12,15,17'; Press = 'type:Resi+Enter,ArrowDown+ArrowDown+ArrowDown+ArrowDown+ArrowDown+ArrowDown+ArrowDown+Enter,PageDown+PageDown' },
    @{ Id = 'title'; Query = 'mute=1&debug=0'; At = '12,15,18,21,26,34,44'; Press = ',type:Resi+Enter,Enter,Escape+ArrowDown+Enter,Escape+ArrowUp+Enter+Enter,,' }
)
try {
    foreach ($size in $Sizes.Split(',')) {
        $w, $h = $size.Split('x') | ForEach-Object { [int]$_ }
        foreach ($scene in $scenes) {
            if ($Only -ne '' -and -not ($Only.Split(',') -contains $scene.Id)) { continue }
            $sep = if ($Url.Contains('?')) { '&' } else { '?' }
            $arguments = @((Join-Path $Root 'tools\browser\screenshots.mjs'), "--url=$Url$sep$($scene.Query)",
                "--out=$(Join-Path $outDir "$($scene.Id)-$size")", "--at=$($scene.At)", "--size=$size", '--max-draws=150')
            if ($scene.Move) {
                # "center" = middle of the screen, "card" = a little below it (the second menu row).
                $points = $scene.Move.Split(',') | ForEach-Object {
                    if ($_ -eq 'center') { '{0}:{1}' -f [int]($w / 2), [int]($h / 2) } else { '{0}:{1}' -f [int]($w / 2), [int]($h * 0.5) }
                }
                $arguments += "--move=$($points -join ',')"
            }
            if ($scene.Press) {
                # {sx} {sy} {sx2}: a point in the stick area (left, low) and one a stick's width right of it.
                $keys = $scene.Press.Replace('{sx}', [string][int]($w * 0.15)).Replace('{sy}', [string][int]($h * 0.75)).Replace('{sx2}', [string][int]($w * 0.15 + 120))
                $arguments += "--keys=$keys"
            }
            if ($scene.Touch) { $arguments += '--touch=1' }
            $code = Invoke-Logged -Exe $Node -Arguments $arguments -Log $log -WorkingDirectory (Join-Path $Root 'tools\browser')
            if ($code -ne 0) { $failures += "$($scene.Id) at $size failed (console errors or draw calls, see log)" }
        }
    }
    if ($Only -eq '' -or ($Only.Split(',') -contains 'coop')) {
        $relay = $null
        $relayArg = @()
        try {
            if ($server) {
                $relay = Start-LocalRelay -Port $RelayPort -Log $log
                $relayArg = @("--relay=ws://127.0.0.1:$RelayPort")
            }
            foreach ($size in $Sizes.Split(',')) {
                $arguments = @((Join-Path $Root 'tools\browser\coop_shots.mjs'), "--url=$Url", "--out=$(Join-Path $outDir "coop-$size")",
                    "--size=$size", '--max-draws=150') + $relayArg
                $code = Invoke-Logged -Exe $Node -Arguments $arguments -Log $log -WorkingDirectory (Join-Path $Root 'tools\browser')
                if ($code -ne 0) { $failures += "coop at $size failed (console errors or draw calls, see log)" }
            }
        } catch {
            $failures += $_.Exception.Message
        } finally {
            if ($relay) { Stop-ProcessTree $relay.Id }
        }
    }
    Write-Host "screenshots: $outDir"
} finally {
    if ($server) { Stop-ProcessTree $server.Id }
}
Complete-Script -Name 'ui_shots' -Log $log -Failures $failures
