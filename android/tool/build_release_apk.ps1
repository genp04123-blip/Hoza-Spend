<#
.SYNOPSIS
    Builds and verifies the signed HozaSend release APK for direct install.

.DESCRIPTION
    One command from a clean checkout to a distributable APK:

        build  ->  verify signature  ->  copy to dist\  ->  print checksum

    The default output is a single universal APK. That is the right shape for
    sideloading: one file that installs on every phone, so nobody has to work
    out whether their device is arm64 or arm32 before they can download
    anything. -SplitPerAbi produces the smaller per-architecture APKs instead,
    which is worth it only if download size matters more than that.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File android\tool\build_release_apk.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File android\tool\build_release_apk.ps1 -Clean -SplitPerAbi
#>
[CmdletBinding()]
param(
    # Also emit one APK per architecture, alongside the universal one.
    [switch]$SplitPerAbi,

    # flutter clean first. Slower, but the only way to be sure a Gradle or
    # signing change actually took effect.
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $repoRoot
try {
    # --- Preflight --------------------------------------------------------
    Write-Host ''
    Write-Host '=== 1/4  Checking the release signing configuration ===' -ForegroundColor Cyan

    $propsPath = Join-Path $repoRoot 'android\key.properties'
    if (-not (Test-Path $propsPath)) {
        throw @"
No android\key.properties.

Create the release keystore first:
  powershell -ExecutionPolicy Bypass -File android\tool\new_release_keystore.ps1

The build would otherwise stop at the same place - it will not fall back to
the debug signing key.
"@
    }

    $props = @{}
    Get-Content $propsPath | ForEach-Object {
        if ($_ -match '^\s*([^#!][^=]*)=(.*)$') { $props[$Matches[1].Trim()] = $Matches[2].Trim() }
    }
    foreach ($required in @('storeFile', 'storePassword', 'keyAlias', 'keyPassword')) {
        if (-not $props[$required]) { throw "android\key.properties is missing '$required'." }
    }
    if (-not (Test-Path $props['storeFile'])) {
        throw "The keystore named in key.properties does not exist: $($props['storeFile'])"
    }
    Write-Host "  keystore  $($props['storeFile'])"
    Write-Host "  alias     $($props['keyAlias'])"

    # --- Build ------------------------------------------------------------
    if ($Clean) {
        Write-Host ''
        Write-Host '=== flutter clean ===' -ForegroundColor Cyan
        flutter clean
        if ($LASTEXITCODE -ne 0) { throw 'flutter clean failed.' }
    }

    Write-Host ''
    Write-Host '=== 2/4  Building the release APK ===' -ForegroundColor Cyan

    # Dart obfuscation (--obfuscate --split-debug-info) is deliberately NOT
    # used. PreferencesService persists ThemeMode by its enum `.name`, and
    # obfuscation has a history of rewriting exactly those strings - which
    # would silently reset saved settings between builds. The Java/Kotlin half
    # is still shrunk and optimised by R8; see android/app/proguard-rules.pro.
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build apk --release failed.' }

    if ($SplitPerAbi) {
        Write-Host ''
        Write-Host '=== Building per-ABI APKs ===' -ForegroundColor Cyan
        flutter build apk --release --split-per-abi
        if ($LASTEXITCODE -ne 0) { throw 'flutter build apk --release --split-per-abi failed.' }
    }

    # --- Verify -----------------------------------------------------------
    Write-Host ''
    Write-Host '=== 3/4  Verifying the signature ===' -ForegroundColor Cyan

    $universal = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
    & (Join-Path $PSScriptRoot 'verify_apk.ps1') -ApkPath $universal
    if ($LASTEXITCODE -ne 0) { throw 'Signature verification failed. The APK was NOT published.' }

    # --- Collect ----------------------------------------------------------
    Write-Host ''
    Write-Host '=== 4/4  Collecting into dist\ ===' -ForegroundColor Cyan

    # The version in the filename is what stops three downloads called
    # app-release.apk piling up in someone's Downloads folder.
    $pubspec = Get-Content (Join-Path $repoRoot 'pubspec.yaml') -Raw
    $version = if ($pubspec -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') { $Matches[1] } else { '0.0.0' }

    $distDir = Join-Path $repoRoot 'dist'
    if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir | Out-Null }

    $outputs = @()
    $target = Join-Path $distDir "HozaSend-$version.apk"
    Copy-Item $universal $target -Force
    $outputs += $target

    if ($SplitPerAbi) {
        Get-ChildItem (Join-Path $repoRoot 'build\app\outputs\flutter-apk') -Filter 'app-*-release.apk' |
            Where-Object { $_.Name -ne 'app-release.apk' } |
            ForEach-Object {
                $abi = $_.Name -replace '^app-', '' -replace '-release\.apk$', ''
                $dest = Join-Path $distDir "HozaSend-$version-$abi.apk"
                Copy-Item $_.FullName $dest -Force
                $outputs += $dest
            }
    }

    Write-Host ''
    Write-Host 'Done.' -ForegroundColor Green
    Write-Host ''
    foreach ($o in $outputs) {
        $item = Get-Item $o
        $sha = (Get-FileHash $o -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Host ("  {0}" -f $item.FullName) -ForegroundColor Green
        Write-Host ("    {0:N1} MB" -f ($item.Length / 1MB))
        Write-Host ("    sha256 {0}" -f $sha) -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  Install with:  adb install -r "<path above>"' -ForegroundColor DarkGray
    Write-Host '  Or copy the .apk to the phone and tap it.' -ForegroundColor DarkGray
    Write-Host ''
}
finally {
    Pop-Location
}
