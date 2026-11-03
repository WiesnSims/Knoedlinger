# Web build for Cloudflare Pages: import, headless export of the "Web" preset to build/web/, then
# tools/pack_wasm.mjs (gzip + split the engine wasm, copy web/*, size table). Fails if any file is
# over 25 MiB or Godot prints an error or warning.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_web.ps1
. "$PSScriptRoot\common.ps1"

$log = New-LogFile 'build_web'
$failures = @()
$web = Join-Path $BuildDir 'web'
if (Test-Path $web) { Remove-Item -Recurse -Force $web }
New-Item -ItemType Directory -Force $web | Out-Null

# The build id ends up in the .pck (export include_filter) and in the co-op handshake, so a browser
# with a stale cached build is refused instead of desyncing.
$commit = (& git -C $Root rev-parse --short HEAD).Trim()
$dirty = if ((& git -C $Root status --porcelain).Length -gt 0) { '-dirty' } else { '' }
$buildId = '{0}{1}-{2}' -f $commit, $dirty, ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
$buildIdFile = Join-Path $Root 'build_id.txt'
[System.IO.File]::WriteAllText($buildIdFile, $buildId, $Utf8NoBom)
try {
    $code = Invoke-Logged -Exe $Godot -Arguments @('--headless', '--path', $Root, '--import') -Log $log -Quiet
    if ($code -ne 0) { $failures += "import exited with $code" }
    $code = Invoke-Logged -Exe $Godot -Arguments @('--headless', '--path', $Root, '--export-release', 'Web', (Join-Path $web 'index.html')) -Log $log
    if ($code -ne 0) { $failures += "export exited with $code" }
} finally {
    Remove-Item -Force $buildIdFile -ErrorAction SilentlyContinue
}
if (-not (Test-Path (Join-Path $web 'index.wasm'))) {
    $failures += 'export produced no index.wasm'
} else {
    $code = Invoke-Logged -Exe $Node -Arguments @((Join-Path $Root 'tools\pack_wasm.mjs'), $web) -Log $log
    if ($code -ne 0) { $failures += 'pack_wasm failed (a file over 25 MiB?)' }
}
[System.IO.File]::WriteAllText((Join-Path $web 'build_id.txt'), $buildId, $Utf8NoBom)
Write-Host "build id: $buildId"
$failures += Get-Problems $log
Complete-Script -Name 'build_web' -Log $log -Failures $failures
