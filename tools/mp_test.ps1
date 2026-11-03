# Headless multiplayer test over the WebSocket backend (no browsers, no signaling server): one host
# and -Clients clients run the stress arena; each client checks the enemy snapshots it gets.
# Also starts one client with a wrong version, which the host must refuse.
#
# Pass per client: handshake accepted, < 60 KiB/s down, no decode errors, the interpolation buffer
# never dry for longer than 2 snapshot intervals, no pops, the shown enemy count matches the host's,
# and no ERROR/WARNING line in any log. -HostLeavesFirst: the host quits mid-run and every client
# must notice it ("host_left") and end cleanly.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/mp_test.ps1 [-Clients 3] [-Seconds 20] [-HostLeavesFirst]
param(
    [int]$Clients = 1,
    [int]$Seconds = 20,
    [int]$Enemies = 500,
    [int]$Projectiles = 300,
    [int]$Port = 9080,
    [double]$MaxKibPerSecond = 60,
    [switch]$HostLeavesFirst,
    [switch]$Coop,
    [switch]$NoRejectTest
)
. "$PSScriptRoot\common.ps1"

$log = New-LogFile 'mp_test'
if ($Coop) {
    Complete-Script -Name 'mp_test -Coop' -Log $log -Failures @('the co-op scenario (revive, Knoedl-Pass, merge, shared XP) comes with M6')
}
$failures = @()
$runDir = Join-Path $LogDir ('mp_test-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $runDir | Out-Null
$scene = 'res://scenes/stress/stress_arena.tscn'
# Headless runs at 60 fps like a player's browser would, so the timing is real.
$common = @('--headless', '--path', $Root, '--max-fps', '60', $scene, '--')

function Start-Godot([string]$Name, [string[]]$GameArgs) {
    $out = Join-Path $runDir "$Name.log"
    $process = Start-Process -FilePath $Godot -ArgumentList ($common + $GameArgs) -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $out -RedirectStandardError "$out.err"
    return @{ Name = $Name; Process = $process; Log = $out }
}

function Get-Result([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    $line = Get-Content -Path $Path -Encoding UTF8 | Where-Object { $_ -like '[[]RESULT] *' } | Select-Object -Last 1
    if (-not $line) { return $null }
    return ($line.Substring(9) | ConvertFrom-Json)
}

$hostSeconds = if ($HostLeavesFirst) { [math]::Max([int]($Seconds / 2), 5) } else { $Seconds + 10 }
$hostRun = Start-Godot 'host' @('--net=ws', '--host', "--port=$Port", "--enemies=$Enemies", "--projectiles=$Projectiles", "--seconds=$hostSeconds")
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline -and -not (Select-String -Path $hostRun.Log -Pattern 'LISTENING' -Quiet -ErrorAction SilentlyContinue)) {
    Start-Sleep -Milliseconds 200
}
if (-not (Select-String -Path $hostRun.Log -Pattern 'LISTENING' -Quiet -ErrorAction SilentlyContinue)) {
    Stop-ProcessTree $hostRun.Process.Id
    Complete-Script -Name 'mp_test' -Log $log -Failures @('the host did not start listening')
}

$runs = @()
for ($i = 1; $i -le $Clients; $i++) {
    $runs += Start-Godot "client$i" @('--net=ws', '--join=127.0.0.1', "--port=$Port", "--seconds=$Seconds")
}
$rejectRun = $null
if (-not $NoRejectTest) {
    $rejectRun = Start-Godot 'client_old_version' @('--net=ws', '--join=127.0.0.1', "--port=$Port", '--seconds=5', '--fake-ver=0.0.0')
}

$all = @($hostRun) + $runs
if ($rejectRun) { $all += $rejectRun }
$timeout = (Get-Date).AddSeconds([math]::Max($Seconds, $hostSeconds) + 60)
foreach ($run in $all) {
    $left = [math]::Max(1, [int](($timeout - (Get-Date)).TotalMilliseconds))
    if (-not $run.Process.WaitForExit($left)) {
        Stop-ProcessTree $run.Process.Id
        $failures += "$($run.Name) did not finish in time"
    }
}

# Copy every process log into the script log and look for Godot errors and warnings.
$writer = New-Object System.IO.StreamWriter($log, $true, $Utf8NoBom)
foreach ($run in $all) {
    foreach ($file in @($run.Log, "$($run.Log).err")) {
        if (Test-Path $file) {
            $writer.WriteLine("===== $($run.Name): $(Split-Path -Leaf $file)")
            $writer.Write([System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8))
        }
    }
}
$writer.Close()
foreach ($problem in (Get-Problems $log)) { $failures += $problem }

$hostResult = Get-Result $hostRun.Log
if (-not $hostResult) { $failures += 'host: no [RESULT]' }
$intervalMs = 1000.0 / 15.0
foreach ($run in $runs) {
    $r = Get-Result $run.Log
    $n = $run.Name
    if (-not $r) { $failures += "${n}: no [RESULT]"; continue }
    if ($r.rejected) { $failures += "${n}: refused by the host ($($r.rejected))"; continue }
    $rep = $r.replica
    $net = $r.net
    Write-Host ("{0}: {1:N1} KiB/s down, {2} snapshots (interval p95 {3} ms, max {4} ms), dry max {5:N0} ms, pops {6}, clock jumps {7}, shown {8} / host {9}" -f `
        $n, $net.kib_per_s_in, $rep.snapshots, $rep.interval_ms_p95, $rep.interval_ms_max, $rep.underrun_ms_max_streak, `
        $rep.pops, $rep.clock_jumps, $rep.alive_shown, $rep.alive_host)
    if ($rep.snapshots -lt 10) { $failures += "${n}: only $($rep.snapshots) snapshots" }
    if ($net.kib_per_s_in -ge $MaxKibPerSecond) { $failures += "${n}: $($net.kib_per_s_in) KiB/s down (budget $MaxKibPerSecond)" }
    if ($rep.decode_errors -gt 0) { $failures += "${n}: $($rep.decode_errors) decode errors" }
    if ($rep.underrun_ms_max_streak -gt 2 * $intervalMs) { $failures += "${n}: buffer dry for $($rep.underrun_ms_max_streak) ms in a row" }
    if ($rep.pops -gt 0) { $failures += "${n}: $($rep.pops) pops" }
    if ([math]::Abs($rep.alive_shown - $rep.alive_host) -gt 10) { $failures += "${n}: shows $($rep.alive_shown) enemies, host has $($rep.alive_host)" }
    if ($HostLeavesFirst) {
        if ($r.ended_reason -ne 'host_left') { $failures += "${n}: did not notice the host leaving" }
    } elseif ($r.ended_reason) {
        $failures += "${n}: session ended early ($($r.ended_reason))"
    }
}
if ($rejectRun) {
    $r = Get-Result $rejectRun.Log
    if (-not $r -or $r.rejected -ne 'version') { $failures += 'the client with a wrong version was not refused' }
    else { Write-Host 'client_old_version: refused as expected (version)' }
}
if ($hostResult -and $hostResult.net) {
    # Averaged over the host's whole run, including the time before and after the clients were there.
    Write-Host ("host: {0:N1} KiB/s up in total over its run, snapshot {1} B, frame ms p95 {2}" -f `
        $hostResult.net.kib_per_s_out, $hostResult.snapshot_bytes_avg, $hostResult.frame.frame_ms_p95)
}
Write-Host "process logs: $runDir"
Complete-Script -Name "mp_test -Clients $Clients$(if ($HostLeavesFirst) { ' -HostLeavesFirst' })" -Log $log -Failures $failures
