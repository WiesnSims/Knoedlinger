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
    # The Nachspielzeit itself: the clock counting on past 15:00, the white Stammgast-Geister, and from
    # 17:00 the grantige red ones.
    @{ Id = 'overtime'; Query = "$common&start_time=891&god=1"; At = '30,40' },
    @{ Id = 'grantig'; Query = "$common&start_time=1030&god=1"; At = '30,36' },
    # The new weapon effects (impacts, chain bolts, mines, the boomerang tray) in a held crowd.
    @{ Id = 'weapons'; Query = "$common&weapons=hagelkanone,krampusrute,sachertorte,tablett&enemies=250&god=1"; At = '22,23' },
    # The maps of M4 (the bot plays on them).
    @{ Id = 'gamskogl'; Query = "$common&map=gamskogl&knodl_mass=160"; At = '24,34' },
    @{ Id = 'gemeindebau'; Query = "$common&map=gemeindebau&knodl_mass=160"; At = '24,34' },
    # A minute into a run with quick picks: weapon level cards with their rolled gain, then the build.
    @{ Id = 'late'; Query = "$common&pick_delay=1.5&god=1"; At = '70,71,72,73,74,110'; Press = ',,,,,Tab' },
    # Enemy lines over their heads (EnemyVoices; voice_every makes them talk often enough to catch).
    @{ Id = 'voices'; Query = "$common&knodl_mass=160&god=1&voice_every=1"; At = '26,29,32,35' },
    @{ Id = 'pause'; Query = "$common&knodl_mass=160"; At = '24,27'; Press = 'Escape,ArrowDown+Enter' },
    # M5: the touch controls (a real finger holds the stick and walks), then the three settings tabs.
    @{ Id = 'touch'; Query = "$common&knodl_mass=160&touch=1"; At = '24,30'; Touch = $true; Press = ',drag:{sx}:{sy}:{sx2}:{sy}:600' },
    @{ Id = 'settings'; Query = 'mute=1&debug=0'; At = '12,15,17,19'; Press = 'type:Resi+Enter,ArrowDown+ArrowDown+ArrowDown+ArrowDown+ArrowDown+Enter,KeyE,KeyE' },
    # A plain start (fresh browser profile): the name prompt, the menu, Spielen, Einstellungen.
    # Then back, Spielen, "Auf geht's!": the run started from the menu.
    # The meta screens of a fresh profile: Stammtisch, Aufträge, Ehrentafel (then Eigene Rekorde), Almanach, then Spielen.
    @{ Id = 'meta'; Query = 'mute=1&debug=0'; At = '12,15,18,21,23,26,29'; Press = 'type:Resi+Enter,ArrowDown+Enter,Escape+ArrowDown+Enter,Escape+ArrowDown+Enter,ArrowRight,Escape+ArrowDown+Enter,Escape+ArrowUp+ArrowUp+ArrowUp+ArrowUp+Enter' },
    # 1.3.1: the patch list ("Was is neu?", the seventh entry), at the top and scrolled down.
    @{ Id = 'patches'; Query = 'mute=1&debug=0'; At = '12,15,17'; Press = 'type:Resi+Enter,ArrowDown+ArrowDown+ArrowDown+ArrowDown+ArrowDown+ArrowDown+Enter,PageDown+PageDown' },
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
