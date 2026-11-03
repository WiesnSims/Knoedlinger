# Deploys build/web to a Cloudflare Pages PREVIEW (never production; production deploys only when
# the owner says so, and not with this script).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/deploy_preview.ps1 -Branch m0-stress
param([Parameter(Mandatory = $true)][string]$Branch)
. "$PSScriptRoot\common.ps1"

$log = New-LogFile 'deploy_preview'
$failures = @()
if ($Branch -eq 'main' -or $Branch -eq 'production') {
    Complete-Script -Name 'deploy_preview' -Log $log -Failures @("'$Branch' is production; this script only deploys previews")
}
$web = Join-Path $BuildDir 'web'
if (-not (Test-Path (Join-Path $web 'index.html'))) {
    Complete-Script -Name 'deploy_preview' -Log $log -Failures @('no web build; run tools/build_web.ps1 first')
}
# The 25 MiB rule again, in case build/web was changed by hand since the build.
foreach ($file in Get-ChildItem -File -Recurse $web) {
    if ($file.Length -gt 25MB) { $failures += "$($file.Name) is $([math]::Round($file.Length / 1MB, 2)) MiB (limit 25 MiB)" }
}
if ($failures.Count -gt 0) { Complete-Script -Name 'deploy_preview' -Log $log -Failures $failures }

$code = Invoke-Logged -Exe 'cmd.exe' -Arguments @('/c', 'npx', 'wrangler', 'pages', 'deploy', $web,
    '--project-name=knoedlinger', "--branch=$Branch", '--commit-dirty=true') -Log $log
if ($code -ne 0) { $failures += "wrangler exited with $code" }
$text = [System.IO.File]::ReadAllText($log, [System.Text.Encoding]::UTF8)
$urls = [regex]::Matches($text, 'https://[a-z0-9.-]+\.knoedlinger\.pages\.dev') | ForEach-Object { $_.Value } | Select-Object -Unique
if ($urls) {
    $alias = "https://$($Branch.ToLower() -replace '[^a-z0-9-]', '-').knoedlinger.pages.dev"
    Write-Host ''
    Write-Host "Deployment: $($urls -join ', ')"
    Write-Host "Branch alias: $alias"
    [System.IO.File]::WriteAllText((Join-Path $LogDir 'last_preview_url.txt'), ($urls[0] + "`n" + $alias + "`n"), $Utf8NoBom)
} elseif ($code -eq 0) {
    $failures += 'no deployment URL in the wrangler output'
}
Complete-Script -Name 'deploy_preview' -Log $log -Failures $failures
