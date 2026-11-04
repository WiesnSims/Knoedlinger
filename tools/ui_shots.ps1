# UI screenshots for checking the look against docs/UI-STYLE.md: serves build/web (or uses -Url) and
# takes a fixed set of moments in headless Edge at every size: the HUD in play, the HUD with the
# Formular / boss / markers (from 10:00), the Speisekarte with a hovered card, the Inventory/Stats
# screen (Tab) and the end screen. PNGs go to build/shots/ui/<Name>/<scene>-<size>-<s>s.png.
# Fails on console errors and on any moment at 150 draw calls or more (the web budget, UI included).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/ui_shots.ps1 [-Name after] [-Url <preview url>]
#        [-Sizes 1920x1080,1280x720] [-Only hud,menu]
param(
    [string]$Name = 'current',
    [string]$Url = '',
    [string]$Sizes = '1920x1080,1280x720',
    [string]$Only = '',
    [int]$Port = 8062
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
    @{ Id = 'end'; Query = "$common&start_time=891"; At = '32' }
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
            if ($scene.Press) { $arguments += "--keys=$($scene.Press)" }
            $code = Invoke-Logged -Exe $Node -Arguments $arguments -Log $log -WorkingDirectory (Join-Path $Root 'tools\browser')
            if ($code -ne 0) { $failures += "$($scene.Id) at $size failed (console errors or draw calls, see log)" }
        }
    }
    Write-Host "screenshots: $outDir"
} finally {
    if ($server) { Stop-ProcessTree $server.Id }
}
Complete-Script -Name 'ui_shots' -Log $log -Failures $failures
