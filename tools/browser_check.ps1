# Per-milestone browser check: serve build/web (or use -Url), load it in a headless browser, let the
# bot play for 60 s, fail on any console error or fps below budget, save a screenshot to build/shots/.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/browser_check.ps1 [-Browser msedge] [-Url <preview url>]
param(
    [string]$Browser = 'msedge',
    [int]$Seconds = 60,
    [int]$Enemies = 500,
    [int]$Projectiles = 300,
    [string]$Url = '',
    [double]$MinFps = 60,
    [double]$MaxP95 = 16.7,
    [int]$MaxDrawCalls = 150,
    [int]$Port = 8061,
    [switch]$Headed
)
. "$PSScriptRoot\common.ps1"

$log = New-LogFile 'browser_check'
$failures = @()
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$server = $null
if ($Url -eq '') {
    $server = Start-WebServer -Port $Port -Log $log
    $Url = "http://127.0.0.1:$Port/"
}
try {
    $out = Join-Path $BuildDir "perf\browser_check-$Browser-$stamp.json"
    $shot = Join-Path $BuildDir "shots\browser_check-$Browser-$stamp.png"
    $code = Invoke-BrowserRun -Url $Url -Browser $Browser -Seconds $Seconds -Enemies $Enemies -Projectiles $Projectiles `
        -MinFps $MinFps -MaxP95 $MaxP95 -MaxDrawCalls $MaxDrawCalls -Out $out -Shot $shot -Log $log -Headed:$Headed
    if ($code -ne 0) { $failures += "browser run failed (see $out)" }
    Write-Host "screenshot: $shot"
} finally {
    if ($server) { Stop-ProcessTree $server.Id }
}
Complete-Script -Name 'browser_check' -Log $log -Failures $failures
