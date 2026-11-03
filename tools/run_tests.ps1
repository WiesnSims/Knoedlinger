# Runs the GUT unit tests headless (tests/unit, see .gutconfig.json).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_tests.ps1
. "$PSScriptRoot\common.ps1"

$log = New-LogFile 'run_tests'
$failures = @()
# Import first: a fresh checkout has no class cache, and GUT needs the classes.
$code = Invoke-Logged -Exe $Godot -Arguments @('--headless', '--path', $Root, '--import') -Log $log -Quiet
if ($code -ne 0) { $failures += "import exited with $code" }
$code = Invoke-Logged -Exe $Godot -Arguments @('--headless', '--path', $Root, '-s', 'addons/gut/gut_cmdln.gd') -Log $log
if ($code -ne 0) { $failures += "GUT exited with $code" }
$text = [System.IO.File]::ReadAllText($log, [System.Text.Encoding]::UTF8)
if ($text -notmatch 'All tests passed') { $failures += 'GUT did not report "All tests passed"' }
$failures += Get-Problems $log
Complete-Script -Name 'run_tests' -Log $log -Failures $failures
