# Headless multiplayer test over the WebSocket backend (no browsers, no signaling server): one host
# and -Clients clients play a run (bots, -Enemies held constant); each client checks what it gets.
# Also starts one client with a wrong version, which the host must refuse.
#
# Pass per client: handshake accepted, < 60 KiB/s down, no decode errors, the interpolation buffer
# never dry for longer than 2 snapshot intervals, no pops, the shown enemy count matches the host's,
# and no ERROR/WARNING line in any log. In the run scene also: world states arrive, the Brosel mirror
# matches the host, every player's Knoedl is shown, the host rejected no pose, and every client got
# Speisekarte offers from the host and levelled up by answering them, and the enemy lines the host
# picked reached them (EnemyVoices).
# -HostLeavesFirst: the host quits mid-run and every client must notice it ("host_left") and end cleanly.
# -StartTime 595: instead of holding -Enemies, the host plays the real timeline from that second (M3:
# bosses, attack marks, the Formular, loot); every client must then get run events, marks and loot.
# -Scene stress runs the M0 stress arena instead.
# -Lobby: everyone meets in the co-op room first (`--lobby`, the real game's path: roster, unique
# characters, the host starts the run for all) instead of the clients dropping into a running host.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/mp_test.ps1 [-Clients 3] [-Seconds 20] [-HostLeavesFirst]
#        [-Scene run|stress] [-StartTime 595]
param(
    [int]$Clients = 1,
    [ValidateSet('run', 'stress')][string]$Scene = 'run',
    [int]$Seconds = 20,
    [int]$Enemies = 500,
    [int]$Projectiles = 300,
    [int]$Port = 9080,
    [double]$MaxKibPerSecond = 60,
    [switch]$HostLeavesFirst,
    [switch]$Coop,
    [switch]$Lobby,
    [switch]$NoRejectTest,
    [int]$StartTime = -1
)
. "$PSScriptRoot\common.ps1"

$log = New-LogFile 'mp_test'
# -Coop: the co-op rules (M6) through the room, no respawn: the host's drill (--coop_drill) knocks a
# client down at 0:10 (the bots must wake it) and rolls two Knoedl together at 0:25 (a merge), the
# Familienstreit comes at 0:30 (--streit_at), the bots throw to each other (Knoedl-Pass).
if ($Coop) {
    $Lobby = $true
    if ($Seconds -lt 40) { $Seconds = 40 }
    # Level-1 bots without respawn: a crowd they can live with for a while.
    if (-not $PSBoundParameters.ContainsKey('Enemies')) { $Enemies = 150 }
}
$failures = @()
$runDir = Join-Path $LogDir ('mp_test-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $runDir | Out-Null
$scenePath = if ($Scene -eq 'run') { 'res://scenes/run/run_world.tscn' } else { 'res://scenes/stress/stress_arena.tscn' }
# Headless runs at 60 fps like a player's browser would, so the timing is real.
$common = @('--headless', '--path', $Root, '--max-fps', '60', $scenePath, '--')
if ($Lobby) {
    # The boot scene waits in the room; the Lobby autoload starts the run.
    $common = @('--headless', '--path', $Root, '--max-fps', '60', '--')
}
$room = if ($Lobby) { @("--lobby=$Clients") } else { @() }
$guest = if ($Lobby) { @('--lobby') } else { @() }
# Each client asks for a Knoedlinger (two ask for the same one: the host hands out a free one).
$wanted = @('ferdl', 'ferdl', 'toni', 'resi')

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
$crowd = if ($StartTime -ge 0) { "--start_time=$StartTime" } else { "--enemies=$Enemies" }
# Everyone gets the Doppelportion in -Coop: the second Knoedl must reach every client too.
$respawn = if ($Coop) { @('--coop_drill=1', '--streit_at=30', '--items=doppelportion') } else { @('--respawn=1') }
$hostRun = Start-Godot 'host' (@('--net=ws', '--host', "--port=$Port", $crowd, "--projectiles=$Projectiles", "--seconds=$hostSeconds", '--bot=1', '--character=ferdl', '--name=Host') + $respawn + $room)
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
    $runs += Start-Godot "client$i" (@('--net=ws', '--join=127.0.0.1', "--port=$Port", "--seconds=$Seconds", '--bot=1',
        "--character=$($wanted[$i % $wanted.Count])", "--name=Gast$i") + $guest)
}
$rejectRun = $null
if (-not $NoRejectTest) {
    $rejectRun = Start-Godot 'client_old_version' (@('--net=ws', '--join=127.0.0.1', "--port=$Port", '--seconds=5', '--fake-ver=0.0.0') + $guest)
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
    # The budget (CLAUDE.md) is for 500 enemies; the real co-op timeline holds more (+60 % per extra
    # player), so it scales with the crowd the client was shown.
    $budget = if ($StartTime -ge 0) { $MaxKibPerSecond * [math]::Max(1.0, $rep.alive_host / 500.0) } else { $MaxKibPerSecond }
    if ($net.kib_per_s_in -ge $budget) { $failures += "${n}: $($net.kib_per_s_in) KiB/s down (budget $([math]::Round($budget, 1)) for $($rep.alive_host) enemies)" }
    if ($rep.decode_errors -gt 0) { $failures += "${n}: $($rep.decode_errors) decode errors" }
    if ($rep.underrun_ms_max_streak -gt 2 * $intervalMs) { $failures += "${n}: buffer dry for $($rep.underrun_ms_max_streak) ms in a row" }
    if ($rep.pops -gt 0) { $failures += "${n}: $($rep.pops) pops" }
    if ([math]::Abs($rep.alive_shown - $rep.alive_host) -gt 10) { $failures += "${n}: shows $($rep.alive_shown) enemies, host has $($rep.alive_host)" }
    if ($Scene -eq 'run') {
        Write-Host ("{0}: {1} world states, Brosel shown {2} / host {3}, {4} Knoedl shown" -f `
            $n, $rep.world_states, $rep.brosel_shown, $rep.brosel_host, $rep.knodls_shown)
        if ($rep.world_states -lt 10) { $failures += "${n}: only $($rep.world_states) world states" }
        if ($rep.brosel_errors -gt 0) { $failures += "${n}: $($rep.brosel_errors) bad Brosel messages" }
        # The host count comes with the latest world state; Brosel changes may be a tick apart.
        if ([math]::Abs($rep.brosel_shown - $rep.brosel_host) -gt [math]::Max(20, $rep.brosel_host * 0.05)) {
            $failures += "${n}: shows $($rep.brosel_shown) Brosel, host has $($rep.brosel_host)"
        }
        if (-not $HostLeavesFirst -and $rep.knodls_shown -lt $Clients + 1) { $failures += "${n}: shows $($rep.knodls_shown) Knoedl for $($Clients + 1) players" }
        if ($Coop -and $rep.seconds_shown -lt $Clients + 1) { $failures += "${n}: shows $($rep.seconds_shown) Doppelportion Knoedl for $($Clients + 1) players" }
        Write-Host ("{0}: level {1}, {2} Speisekarte messages, weapons {3}" -f $n, $r.run.level, $rep.offers_received, ($r.run.weapons -join ', '))
        Write-Host ("{0}: {1} run events, {2} attack marks, {3} loot shown, {4} enemy lines (host said {5})" -f `
            $n, $rep.run_events, $rep.hazards_seen, $rep.loot_shown, $rep.voice_lines, $hostResult.voices_said)
        if (-not $HostLeavesFirst -and $hostResult.voices_said -ge 3 -and $rep.voice_lines -lt 1) {
            $failures += "${n}: none of the host's $($hostResult.voices_said) enemy lines reached the client"
        }
        if ($rep.loot_shown -lt 1) { $failures += "${n}: no loot shown (the map chests come with the join)" }
        if ($StartTime -ge 0 -and -not $HostLeavesFirst) {
            if ($rep.run_events -lt 5) { $failures += "${n}: only $($rep.run_events) run events" }
            if ($rep.hazards_seen -lt 1) { $failures += "${n}: no attack marks reached the client" }
        }
        if (-not $HostLeavesFirst) {
            if ($rep.offers_received -lt 1) { $failures += "${n}: no Speisekarte offer reached the client" }
            if ($r.run.level -lt 2) { $failures += "${n}: still level $($r.run.level)" }
        }
    }
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
if ($Coop) {
    # The host logs every co-op deed ([RUN] revive / pass / merge / split / familienstreit).
    $hostLog = Get-Content -Path $hostRun.Log -Encoding UTF8
    $revives = @($hostLog | Where-Object { $_ -like '[[]RUN] revive *' }).Count
    $passes = @($hostLog | Where-Object { $_ -like '[[]RUN] pass *' }).Count
    $merges = @($hostLog | Where-Object { $_ -like '[[]RUN] merge *' }).Count
    $streit = @($hostLog | Where-Object { $_ -like '[[]RUN] familienstreit *' }).Count
    $downs = 0
    foreach ($run in @($hostRun) + $runs) { $r = Get-Result $run.Log; if ($r -and $r.run) { $downs += @($r.run.downed_times).Count } }
    Write-Host ("co-op: {0} knock-downs, {1} revives, {2} passes, {3} merges, Familienstreit {4}" -f $downs, $revives, $passes, $merges, $streit)
    if ($streit -lt 1) { $failures += 'co-op: the Familienstreit did not come' }
    if ($passes -lt 1) { $failures += 'co-op: no Knoedl-Pass' }
    if ($revives -lt 1) { $failures += 'co-op: nobody was woken' }
    if ($merges -lt 1) { $failures += 'co-op: no Riesenknoedl merge' }
}
if ($Lobby -and $hostResult) {
    # The room hands every player a different Knoedlinger.
    $chars = @($hostResult.run.character) + @($runs | ForEach-Object { $r = Get-Result $_.Log; if ($r -and $r.run) { $r.run.character } })
    Write-Host ("room: characters {0}" -f ($chars -join ', '))
    if (($chars | Select-Object -Unique).Count -ne $chars.Count) { $failures += "two players played the same Knoedlinger ($($chars -join ', '))" }
}
if ($hostResult -and $hostResult.rejected_poses -gt 0) { $failures += "host: rejected $($hostResult.rejected_poses) poses" }
if ($hostResult -and $hostResult.net) {
    # Averaged over the host's whole run, including the time before and after the clients were there.
    Write-Host ("host: {0:N1} KiB/s up in total over its run, snapshot {1} B, frame ms p95 {2}" -f `
        $hostResult.net.kib_per_s_out, $hostResult.snapshot_bytes_avg, $hostResult.frame.frame_ms_p95)
}
Write-Host "process logs: $runDir"
Complete-Script -Name "mp_test -Clients $Clients$(if ($Coop) { ' -Coop' } elseif ($Lobby) { ' -Lobby' })$(if ($HostLeavesFirst) { ' -HostLeavesFirst' })$(if ($StartTime -ge 0) { " -StartTime $StartTime" })" -Log $log -Failures $failures
