# Placeholder voice barks with the Windows Austrian German text-to-speech voice (de-AT, needs the
# "Deutsch (Oesterreich)" speech pack). GAME-DESIGN.md allows TTS or recordings; real recordings
# from the owner replace these files 1:1 (assets/audio/sfx/bark_<id>.ogg and mahlzeit.ogg).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools/audio/make_barks.ps1
# Keep this file ASCII (Windows PowerShell 5.1 reads it in the ANSI code page).
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path -Parent (Split-Path -Parent $here)
$out = Join-Path $root 'assets\audio\sfx'
$tmp = Join-Path $root 'build\barks'
New-Item -ItemType Directory -Force $tmp | Out-Null

# id = text, speaking rate, pitch shift (SSML prosody)
$lines = [ordered]@{
    'bark_heast'     = @('Heast!', '1.05', '-4%')
    'bark_geh_bitte' = @('Geh bitte.', '0.95', '-6%')
    'bark_servas'    = @('Na servas!', '1.0', '-2%')
    'bark_wurscht'   = @('Des is ma wurscht.', '1.0', '-6%')
    'bark_obacht'    = @('Obacht!', '1.1', '0%')
    'bark_aufgweckt' = @('Aufgweckt!', '1.05', '+2%')
    'mahlzeit'       = @('Mahlzeit!', '0.9', '-8%')
}

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Wait-Op($operation, [Type]$type) {
    $task = $asTask.MakeGenericMethod($type).Invoke($null, @($operation))
    [void]$task.Wait(-1)
    return $task.Result
}
[void][Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType = WindowsRuntime]
[void][Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType = WindowsRuntime]

$synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
$voice = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | Where-Object { $_.Language -eq 'de-AT' } | Select-Object -First 1
if (-not $voice) { throw 'No de-AT voice installed (Settings > Time & language > Speech).' }
$synth.Voice = $voice
Write-Host "voice: $($voice.DisplayName) ($($voice.Language))"
$node = (& node -p 'process.execPath').Trim()

foreach ($id in $lines.Keys) {
    $text, $rate, $pitch = $lines[$id]
    $ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='de-AT'>" +
        "<prosody rate='$rate' pitch='$pitch'>$text</prosody></speak>"
    $stream = Wait-Op ($synth.SynthesizeSsmlToStreamAsync($ssml)) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
    $size = [uint32]$stream.Size
    $reader = New-Object Windows.Storage.Streams.DataReader($stream.GetInputStreamAt(0))
    [void](Wait-Op ($reader.LoadAsync($size)) ([uint32]))
    $bytes = New-Object byte[] $size
    $reader.ReadBytes($bytes)
    $wav = Join-Path $tmp "$id.wav"
    [System.IO.File]::WriteAllBytes($wav, $bytes)
    & $node (Join-Path $here 'wav_to_ogg.mjs') $wav (Join-Path $out "$id.ogg")
    if ($LASTEXITCODE -ne 0) { throw "converting $id failed" }
}
