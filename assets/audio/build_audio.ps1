# Build cozy audio WAVs for Tides of Trade (hybrid: Kenney CC0 + OGA music + ffmpeg synthesis)
$ErrorActionPreference = "Stop"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dl = Join-Path $Root "_dl"
$Out = Join-Path $Root "sources"
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$Kenney = Join-Path $Dl "kenney\Audio"
if (-not (Test-Path $Kenney)) { throw "Kenney Audio folder missing at $Kenney" }

function Invoke-Ffmpeg([string[]]$FfmpegArgs) {
    & ffmpeg -y -hide_banner -loglevel error @FfmpegArgs
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed: $($FfmpegArgs -join ' ')" }
}

# --- Slot 1: AmbientOcean (60s seamless loop, synthetic calm waves) ---
Invoke-Ffmpeg @(
    "-f", "lavfi", "-i", "anoisesrc=d=62:c=brown:r=44100:a=0.35",
    "-af", "lowpass=f=420,highpass=f=90,volume=-14dB,tremolo=f=0.12:d=0.25,afade=t=in:st=0:d=2,afade=t=out:st=60:d=2",
    "-t", "62", "-ar", "44100", "-ac", "2", (Join-Path $Out "ambient_ocean.wav")
)

# --- Slot 2: MusicHarborTheme (loop from CC0 downtown trip, slowed) ---
$MusicSrc = Join-Path $Dl "downtown_trip.mp3"
if (-not (Test-Path $MusicSrc)) { $MusicSrc = Join-Path $Dl "music_cozy.ogg" }
Invoke-Ffmpeg @(
    "-i", $MusicSrc,
    "-af", "highpass=f=80,lowpass=f=6000,volume=-8dB,atempo=0.92",
    "-t", "75", "-ar", "44100", "-ac", "2",
    (Join-Path $Out "music_harbor_theme.wav")
)

# Kenney one-shots -> mono WAV
$Map = @{
    "cast_splash.wav"     = "drop_003.ogg"
    "perfect_flash.wav"   = "bong_001.ogg"
    "coin_clink.wav"      = "click_005.ogg"
    "catch_fail.wav"      = "back_001.ogg"
    "catch_success.wav"   = "confirmation_003.ogg"
    "fish_bite.wav"       = "scratch_001.ogg"
    "harbor_upgrade.wav"  = "confirmation_004.ogg"
}

foreach ($dest in $Map.Keys) {
    $src = Join-Path $Kenney $Map[$dest]
    if (-not (Test-Path $src)) {
        # fallback
        $src = Join-Path $Kenney ($Map[$dest] -replace "swipe_001", "confirmation_002")
    }
    $peak = if ($dest -eq "catch_fail.wav") { "-6" } else { "-3" }
    $hpf = if ($dest -eq "perfect_flash.wav") { "200" } elseif ($dest -eq "coin_clink.wav") { "150" } else { "100" }
    $dur = switch ($dest) {
        "cast_splash.wav" { "0.55" }
        "perfect_flash.wav" { "0.32" }
        "coin_clink.wav" { "0.28" }
        "catch_fail.wav" { "0.38" }
        "catch_success.wav" { "0.95" }
        "fish_bite.wav" { "0.85" }
        "harbor_upgrade.wav" { "1.35" }
    }
    Invoke-Ffmpeg @(
        "-i", $src,
        "-af", "highpass=f=$hpf,volume=${peak}dB,afade=t=in:st=0:d=0.01,afade=t=out:st=0:d=0.08",
        "-t", $dur, "-ar", "44100", "-ac", "1",
        (Join-Path $Out $dest)
    )
}

# Layer harbor upgrade: soft marimba-like sine tail
$Upgrade = Join-Path $Out "harbor_upgrade.wav"
$UpgradeTmp = Join-Path $Out "_harbor_upgrade_layer.wav"
Invoke-Ffmpeg @(
    "-f", "lavfi", "-i", "sine=f=523:d=0.15",
    "-f", "lavfi", "-i", "sine=f=659:d=0.2",
    "-f", "lavfi", "-i", "sine=f=784:d=0.35",
    "-filter_complex", "[0][1][2]concat=n=3:v=0:a=1,highpass=f=200,volume=-12dB,afade=t=out:st=0.4:d=0.3",
    "-ar", "44100", "-ac", "1", $UpgradeTmp
)
Invoke-Ffmpeg @(
    "-i", $Upgrade, "-i", $UpgradeTmp,
    "-filter_complex", "[0][1]amix=inputs=2:duration=first:dropout_transition=0,volume=-2dB",
    "-ar", "44100", "-ac", "1", (Join-Path $Out "harbor_upgrade_mixed.wav")
)
Move-Item -Force (Join-Path $Out "harbor_upgrade_mixed.wav") $Upgrade
Remove-Item -Force $UpgradeTmp -ErrorAction SilentlyContinue

# Catch success: add gentle glockenspiel sine
$Success = Join-Path $Out "catch_success.wav"
$SuccessTmp = Join-Path $Out "_catch_success_layer.wav"
Invoke-Ffmpeg @(
    "-f", "lavfi", "-i", "sine=f=1047:d=0.12",
    "-f", "lavfi", "-i", "sine=f=1319:d=0.18",
    "-filter_complex", "[0][1]concat=n=2:v=0:a=1,adelay=120|120,highpass=f=400,volume=-14dB",
    "-ar", "44100", "-ac", "1", $SuccessTmp
)
Invoke-Ffmpeg @(
    "-i", $Success, "-i", $SuccessTmp,
    "-filter_complex", "[0][1]amix=inputs=2:duration=first:dropout_transition=0",
    "-ar", "44100", "-ac", "1", (Join-Path $Out "catch_success_mixed.wav")
)
Move-Item -Force (Join-Path $Out "catch_success_mixed.wav") $Success
Remove-Item -Force $SuccessTmp -ErrorAction SilentlyContinue

Write-Host "Built WAVs in $Out"
Get-ChildItem $Out -Filter "*.wav" | Format-Table Name, Length -AutoSize
