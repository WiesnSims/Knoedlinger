# Co-op in real browsers (M6): -Tabs headless Edge tabs meet in one room through the relay and play
# -Seconds with bots (tools/browser/mp_tabs.mjs). Without -Url: serves build/web and runs the relay
# locally (wrangler dev in relay/, the real Durable Object code); with -Url: the preview's (or live
# site's) own relay. Fails on console errors, a tab without a result, a client missing Knoedl or
# enemies, or a client below -MinFps.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/browser_mp_check.ps1 [-Tabs 4] [-Url <preview url>]
#        [-Seconds 60] [-Enemies 300] [-Port 8062] [-RelayPort 8790]
param(
    [int]$Tabs = 4,
    [int]$Seconds = 60,
    [int]$Enemies = 300,
    [string]$Url = '',
    [double]$MinFps = 30,
    [int]$Port = 8062,
    [int]$RelayPort = 8790
)
. "$PSScriptRoot\common.ps1"

$log = New-LogFile 'browser_mp_check'
$failures = @()
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$server = $null
$relay = $null
$relayArg = @()
try {
    if ($Url -eq '') {
        $server = Start-WebServer -Port $Port -Log $log
        $Url = "http://127.0.0.1:$Port/"
        # The relay Worker with its Durable Object, locally (its own fetch serves /api/room/<code>).
        $relayLog = "$log.relay.out"
        $relay = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', 'npx', 'wrangler@latest', 'dev', '--port', "$RelayPort", '--ip', '127.0.0.1') `
            -WorkingDirectory (Join-Path $Root 'relay') -PassThru -WindowStyle Hidden -RedirectStandardOutput $relayLog -RedirectStandardError "$log.relay.err"
        $deadline = (Get-Date).AddSeconds(90)
        while ((Get-Date) -lt $deadline -and -not (Select-String -Path $relayLog -Pattern 'Ready on' -Quiet -ErrorAction SilentlyContinue)) {
            Start-Sleep -Milliseconds 500
        }
        if (-not (Select-String -Path $relayLog -Pattern 'Ready on' -Quiet -ErrorAction SilentlyContinue)) {
            throw 'the local relay (wrangler dev) did not start'
        }
        $relayArg = @("--relay=ws://127.0.0.1:$RelayPort")
    }
    $out = Join-Path $BuildDir "perf\browser_mp_check-$stamp.json"
    $shots = Join-Path $BuildDir "shots\browser_mp_check-$stamp"
    $arguments = @((Join-Path $Root 'tools\browser\mp_tabs.mjs'), "--url=$Url", "--tabs=$Tabs", "--seconds=$Seconds",
        "--enemies=$Enemies", "--min-fps=$MinFps", "--out=$out", "--shot-dir=$shots") + $relayArg
    $code = Invoke-Logged -Exe $Node -Arguments $arguments -Log $log -WorkingDirectory (Join-Path $Root 'tools\browser')
    if ($code -ne 0) { $failures += "co-op browser run failed (see $out)" }
    Write-Host "screenshots: $shots"
} catch {
    $failures += $_.Exception.Message
} finally {
    if ($server) { Stop-ProcessTree $server.Id }
    if ($relay) { Stop-ProcessTree $relay.Id }
}
Complete-Script -Name "browser_mp_check -Tabs $Tabs" -Log $log -Failures $failures
