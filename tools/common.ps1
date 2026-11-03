# Shared helpers for the tools/*.ps1 scripts (dot-source this file). Every script writes its log to
# build/logs/ and exits 1 on any error or warning (CLAUDE.md). Keep this file ASCII: Windows
# PowerShell 5.1 reads scripts without a BOM in the ANSI code page.

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $Root 'build'
$LogDir = Join-Path $BuildDir 'logs'
New-Item -ItemType Directory -Force $LogDir | Out-Null
# Without this Godot would import everything under build/ (exports, screenshots).
$GdIgnore = Join-Path $BuildDir '.gdignore'
if (-not (Test-Path $GdIgnore)) { New-Item -ItemType File $GdIgnore | Out-Null }
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Godot = if ($env:GODOT) { $env:GODOT } else { (Get-Command godot -ErrorAction Stop).Source }
# The real node.exe: with nvm, `node` on PATH is a shim that starts node as a child process, and
# stopping the shim would leave the child (and the pipes it inherited) running.
$Node = (& node -p 'process.execPath').Trim()
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
# Lines Godot prints for errors and warnings; any of them fails a script.
$ProblemPattern = '^(USER |SCRIPT )?(ERROR|WARNING):'

function New-LogFile([string]$Name) {
    return Join-Path $LogDir ('{0}-{1}.log' -f $Name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

function ConvertTo-ArgString([string]$Value) {
    if ($Value -eq '') { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '"', '\"') + '"'
}

# Runs a program, streams its output to the console (unless -Quiet) and appends it to the log.
# Returns the exit code. stderr is collected separately and appended after stdout.
function Invoke-Logged {
    param(
        [string]$Exe,
        [string[]]$Arguments,
        [string]$Log,
        [string]$WorkingDirectory = $Root,
        [switch]$Quiet
    )
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Exe
    $info.Arguments = (($Arguments | ForEach-Object { ConvertTo-ArgString $_ }) -join ' ')
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $info.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $info.CreateNoWindow = $true
    $writer = New-Object System.IO.StreamWriter($Log, $true, $Utf8NoBom)
    try {
        $writer.WriteLine('> ' + $Exe + ' ' + $info.Arguments)
        $process = [System.Diagnostics.Process]::Start($info)
        $errors = $process.StandardError.ReadToEndAsync()
        # Not "read until end of file": a browser started by the program can inherit its stdout and
        # keep the pipe open after the program exited. Stop reading shortly after the exit instead.
        $pending = $null
        $exitedAt = $null
        while ($true) {
            if ($null -eq $pending) { $pending = $process.StandardOutput.ReadLineAsync() }
            if ($pending.Wait(200)) {
                $line = $pending.Result
                $pending = $null
                if ($null -eq $line) { break }
                $writer.WriteLine($line)
                if (-not $Quiet) { Write-Host $line }
            } elseif ($process.HasExited) {
                if ($null -eq $exitedAt) { $exitedAt = Get-Date }
                elseif (((Get-Date) - $exitedAt).TotalSeconds -gt 3) { break }
            }
        }
        # With a timeout: WaitForExit() alone also waits for those inherited pipes to close.
        [void]$process.WaitForExit(5000)
        $stderr = if ($errors.Wait(3000)) { $errors.Result } else { '' }
        if ($stderr) {
            $writer.Write($stderr)
            if (-not $Quiet) { Write-Host $stderr }
        }
        return $process.ExitCode
    } finally {
        $writer.Close()
    }
}

# Godot error/warning lines in a log file (ANSI colour codes stripped).
function Get-Problems([string]$Log) {
    $found = @()
    foreach ($line in [System.IO.File]::ReadAllLines($Log, [System.Text.Encoding]::UTF8)) {
        $clean = $line -replace ([string][char]27 + '\[[0-9;]*m'), ''
        if ($clean -match $ProblemPattern) { $found += $clean }
    }
    return ,$found
}

# Prints the problems and the verdict, then exits with 0 or 1.
function Complete-Script {
    param([string]$Name, [string]$Log, [string[]]$Failures)
    if ($Failures.Count -gt 0) {
        Write-Host ''
        Write-Host "FAIL: $Name ($($Failures.Count) problem(s)), log: $Log" -ForegroundColor Red
        foreach ($f in $Failures) { Write-Host "  - $f" -ForegroundColor Red }
        exit 1
    }
    Write-Host ''
    Write-Host "PASS: $Name, log: $Log" -ForegroundColor Green
    exit 0
}

# Serves build/web on 127.0.0.1:<Port> with tools/browser/serve.mjs. Returns the process.
function Start-WebServer([int]$Port, [string]$Log) {
    $serve = Join-Path $Root 'tools\browser\serve.mjs'
    $web = Join-Path $BuildDir 'web'
    if (-not (Test-Path (Join-Path $web 'index.html'))) { throw "No web build in $web. Run tools/build_web.ps1 first." }
    $process = Start-Process -FilePath $Node -ArgumentList @($serve, $web, $Port) -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput "$Log.server.out" -RedirectStandardError "$Log.server.err"
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        try {
            Invoke-WebRequest -Uri "http://127.0.0.1:$Port/index.html" -UseBasicParsing -TimeoutSec 2 | Out-Null
            return $process
        } catch { Start-Sleep -Milliseconds 300 }
    }
    Stop-ProcessTree $process.Id
    throw "The local web server did not start on port $Port."
}

# Stops a process and everything it started.
function Stop-ProcessTree([int]$Id) {
    & taskkill.exe /PID $Id /T /F 2>&1 | Out-Null
}

# One browser run of the game through Playwright (tools/browser/run_game.mjs). Returns the exit code;
# the runner checks the budgets and writes its JSON report to -Out.
function Invoke-BrowserRun {
    param(
        [string]$Url,
        [string]$Browser,
        [int]$Seconds,
        [int]$Enemies,
        [int]$Projectiles,
        [string]$Scene = 'run',
        [double]$MinFps,
        [double]$MaxP95,
        [int]$MaxDrawCalls,
        [string]$Out,
        [string]$Shot,
        [string]$Log,
        [switch]$Headed
    )
    $runner = Join-Path $Root 'tools\browser\run_game.mjs'
    $arguments = @($runner, "--url=$Url", "--browser=$Browser", "--seconds=$Seconds", "--scene=$Scene", "--enemies=$Enemies",
        "--projectiles=$Projectiles", "--min-fps=$MinFps", "--max-p95=$MaxP95", "--max-draw-calls=$MaxDrawCalls",
        "--out=$Out", "--shot=$Shot")
    if ($Headed) { $arguments += '--headed' }
    return Invoke-Logged -Exe $Node -Arguments $arguments -Log $Log -WorkingDirectory (Join-Path $Root 'tools\browser')
}
