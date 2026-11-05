# Balance log (GAME-DESIGN.md "Balance log"): the bot plays whole 15-minute runs headless, as fast as
# the CPU allows (fixed 60 Hz steps), and writes one JSON per run to build/balance/<stamp>/: time,
# level and when each level came, knock-downs (the bot gets back up, see --respawn), Knoedl cash-ins,
# kills, Stempel, bosses beaten and the result, the build. Prints a table and
# fails on any Godot error or warning, or a run that did not reach Sperrstund'.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/autoplay.ps1 [-Runs 3] [-Seed 1] [-Character ferdl]
#        [-Map kirtag|gamskogl|gemeindebau|heuriger] [-Grant 1]   (Grant level index, 0 = Gemuetlich .. 4)
param(
    [int]$Runs = 3,
    [int]$Seed = 1,
    [string]$Character = 'ferdl',
    [string]$Map = 'kirtag',
    [int]$Grant = 1
)
. "$PSScriptRoot\common.ps1"

$log = New-LogFile 'autoplay'
$failures = @()
$outDir = Join-Path $BuildDir ('balance\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$Character-$Map-g$Grant")
New-Item -ItemType Directory -Force $outDir | Out-Null
$outArg = $outDir -replace '\\', '/'
# Every run is about 54,000 frames; allow ten minutes each.
$started = Get-Date
$code = Invoke-Logged -Exe $Godot -Arguments @('--headless', '--fixed-fps', '60', '--path', $Root,
    'res://scenes/run/run_world.tscn', '--', '--autoplay=1', "--runs=$Runs", "--seed=$Seed", "--character=$Character",
    "--map=$Map", "--grant=$Grant", "--out=$outArg") -Log $log -Quiet
if ($code -ne 0) { $failures += "godot exited with $code" }
$failures += Get-Problems $log

$files = @(Get-ChildItem -Path $outDir -Filter 'run-*.json' | Sort-Object Name)
if ($files.Count -ne $Runs) { $failures += "expected $Runs run logs, found $($files.Count)" }
Write-Host ('{0,-4} {1,6} {2,6} {3,8} {4,8} {5,6} {6,8} {7,10} {8,8} {9,7} {10,-7} {11}' -f 'run', 'time', 'level', 'first lv', 'lv10 at', 'downs', 'kills', 'cash-ins', 'eaten', 'stempel', 'result', 'bosses beaten at')
foreach ($file in $files) {
    $r = Get-Content -Raw -Path $file.FullName -Encoding UTF8 | ConvertFrom-Json
    $first = if ($r.level_times.Count -gt 0) { $r.level_times[0] } else { '-' }
    $ten = if ($r.level_times.Count -ge 9) { $r.level_times[8] } else { '-' }
    $bosses = ($r.bosses_beaten | ForEach-Object { '{0}@{1}' -f $_[0], $_[1] }) -join ' '
    Write-Host ('{0,-4} {1,6} {2,6} {3,8} {4,8} {5,6} {6,8} {7,10} {8,8} {9,7} {10,-7} {11}' -f $r.run, $r.time, $r.level, $first, $ten, $r.deaths, `
        $r.kills, ($r.cash_ins -join '/'), $r.mass_eaten, $r.stempel, $r.result, $bosses)
    if ($r.phase -ne 'ENDED') { $failures += "run $($r.run) ended in phase $($r.phase)" }
}
Write-Host ("{0} runs in {1:N0} s, logs in {2}" -f $files.Count, ((Get-Date) - $started).TotalSeconds, $outDir)
Complete-Script -Name "autoplay -Runs $Runs" -Log $log -Failures $failures
