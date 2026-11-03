# M0 stress test: N enemies + M projectiles in the web build, in each browser, reporting fps, frame
# times, draw calls and ms per system. Pass = the budgets below in every browser (CLAUDE.md: desktop
# 60 fps with 500 enemies + 300 projectiles, < 150 draw calls). Reports go to build/perf/.
# -Native measures the simulation's CPU cost in a headless desktop run instead (no rendering).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/stress_test.ps1 [-Enemies 500] [-Projectiles 300]
#        [-Seconds 30] [-Browser msedge,firefox] [-Url https://<preview>.knoedlinger.pages.dev/] [-Headed] [-Native]
param(
    [int]$Enemies = 500,
    [int]$Projectiles = 300,
    [int]$Seconds = 30,
    [string[]]$Browser = @('msedge', 'firefox'),
    [string]$Url = '',
    [double]$MinFps = 60,
    [double]$MaxP95 = 16.7,
    [int]$MaxDrawCalls = 150,
    [int]$Port = 8060,
    [switch]$Headed,
    [switch]$Native
)
. "$PSScriptRoot\common.ps1"

$log = New-LogFile 'stress_test'
$failures = @()
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if ($Native) {
    $arguments = @('--headless', '--path', $Root, 'res://scenes/stress/stress_arena.tscn', '--',
        "--enemies=$Enemies", "--projectiles=$Projectiles", "--seconds=$Seconds", '--encode=1')
    $code = Invoke-Logged -Exe $Godot -Arguments $arguments -Log $log
    if ($code -ne 0) { $failures += "godot exited with $code" }
    $failures += Get-Problems $log
    Complete-Script -Name 'stress_test -Native' -Log $log -Failures $failures
}

$server = $null
if ($Url -eq '') {
    $server = Start-WebServer -Port $Port -Log $log
    $Url = "http://127.0.0.1:$Port/"
}
try {
    foreach ($name in $Browser) {
        Write-Host "== ${name}: $Enemies enemies, $Projectiles projectiles, $Seconds s =="
        $out = Join-Path $BuildDir "perf\stress-$name-$stamp.json"
        $shot = Join-Path $BuildDir "shots\stress-$name.png"
        $code = Invoke-BrowserRun -Url $Url -Browser $name -Seconds $Seconds -Scene 'stress' -Enemies $Enemies -Projectiles $Projectiles `
            -MinFps $MinFps -MaxP95 $MaxP95 -MaxDrawCalls $MaxDrawCalls -Out $out -Shot $shot -Log $log -Headed:$Headed
        if ($code -ne 0) { $failures += "$name run failed (see $out)" }
    }
} finally {
    if ($server) { Stop-ProcessTree $server.Id }
}
Complete-Script -Name 'stress_test' -Log $log -Failures $failures
