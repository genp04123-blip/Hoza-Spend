<#
.SYNOPSIS
    Verifies that a release APK is properly signed and safe to publish.

.DESCRIPTION
    Checks, in order, the things that actually go wrong:

      1. The APK verifies at all.
      2. It is NOT signed with the Android debug key. This is the one that
         matters most - a debug-signed release looks completely normal until
         you notice that the signing key ships with every copy of the Android
         SDK, so anyone can publish an "update" over the top of it.
      3. The signature schemes the APK's own minSdk requires.
      4. The certificate matches this project's keystore, compared by SHA-256
         fingerprint rather than by name - names are not unique and are
         trivially forged, fingerprints are the identity.
      5. The manifest: application id, version, not debuggable, and the full
         merged permission list including anything a plugin added.

    Exits non-zero if any check fails, so it can gate a release.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File android\tool\verify_apk.ps1
#>
[CmdletBinding()]
param(
    [string]$ApkPath,
    [string]$ExpectedKeystore,
    [string]$ExpectedApplicationId = 'com.rahozosman.hozasend'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if (-not $ApkPath) {
    $ApkPath = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
}

$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$m) { $script:failures.Add($m); Write-Host "  FAIL  $m" -ForegroundColor Red }
function Pass([string]$m) { Write-Host "  ok    $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Host "  warn  $m" -ForegroundColor Yellow }
function Note([string]$m) { Write-Host "  --    $m" -ForegroundColor DarkGray }

# --- Locate the SDK tools -------------------------------------------------
function Find-SdkRoot {
    if ($env:ANDROID_SDK_ROOT -and (Test-Path $env:ANDROID_SDK_ROOT)) { return $env:ANDROID_SDK_ROOT }
    if ($env:ANDROID_HOME     -and (Test-Path $env:ANDROID_HOME))     { return $env:ANDROID_HOME }

    # android/local.properties is what Gradle itself uses, so it is the most
    # reliable answer on this machine.
    $localProps = Join-Path $repoRoot 'android\local.properties'
    if (Test-Path $localProps) {
        $line = Select-String -Path $localProps -Pattern '^\s*sdk\.dir\s*=\s*(.+)$' | Select-Object -First 1
        if ($line) {
            # .properties escapes backslashes, so C:\\Users\\... comes back doubled.
            $dir = $line.Matches[0].Groups[1].Value.Trim().Replace('\\', '\')
            if (Test-Path $dir) { return $dir }
        }
    }
    $default = Join-Path $env:LOCALAPPDATA 'Android\sdk'
    if (Test-Path $default) { return $default }
    throw 'Android SDK not found. Set ANDROID_SDK_ROOT, or add sdk.dir to android\local.properties.'
}

$sdk = Find-SdkRoot
$buildToolsRoot = Join-Path $sdk 'build-tools'
if (-not (Test-Path $buildToolsRoot)) { throw "No build-tools under $sdk." }

# Sorted as versions, not as strings - otherwise "9.0.0" sorts above "37.0.0".
$buildTools = Get-ChildItem $buildToolsRoot -Directory |
    Sort-Object { try { [version]$_.Name } catch { [version]'0.0.0' } } |
    Select-Object -Last 1

$apksigner = Join-Path $buildTools.FullName 'apksigner.bat'
$aapt      = Join-Path $buildTools.FullName 'aapt.exe'
foreach ($t in @($apksigner, $aapt)) {
    if (-not (Test-Path $t)) { throw "Missing $t. Install Android SDK build-tools." }
}

Write-Host ''
Write-Host '=== HozaSend release APK verification ===' -ForegroundColor Cyan
Write-Host "  apk         $ApkPath"
Write-Host "  build-tools $($buildTools.Name)"

if (-not (Test-Path $ApkPath)) {
    throw "APK not found at $ApkPath. Build it first: flutter build apk --release"
}

$apkItem = Get-Item $ApkPath
Write-Host ("  size        {0:N1} MB" -f ($apkItem.Length / 1MB))
Write-Host ("  built       {0}" -f $apkItem.LastWriteTime)

# --- Manifest first -------------------------------------------------------
# Read before the signature checks, because minSdk decides which signature
# schemes are actually required.
$badging = & cmd /c "`"$aapt`" dump badging `"$ApkPath`" 2>&1" | Out-String

$minSdk = 0
if ($badging -match "sdkVersion:'(\d+)'") { $minSdk = [int]$Matches[1] }

Write-Host ''
Write-Host '--- Manifest ---' -ForegroundColor Cyan

if ($badging -match "package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'") {
    $pkg = $Matches[1]; $vCode = $Matches[2]; $vName = $Matches[3]
    Write-Host "        package     $pkg"
    Write-Host "        version     $vName ($vCode)"
    if ($pkg -eq $ExpectedApplicationId) {
        Pass "application id is $ExpectedApplicationId"
    } else {
        Fail "application id is '$pkg', expected '$ExpectedApplicationId'"
    }
    if ($pkg -like 'com.example.*') { Fail 'application id is still a com.example placeholder' }
} else {
    Fail 'could not read the package line out of the manifest'
}

if ($badging -match "application-label:'([^']+)'") { Write-Host "        label       $($Matches[1])" }
Write-Host "        minSdk      $minSdk"
if ($badging -match "targetSdkVersion:'([^']+)'") { Write-Host "        targetSdk   $($Matches[1])" }

if ($badging -match "application-icon-\d+:'([^']+)'") {
    Pass 'launcher icon is present'
} else {
    Fail 'no launcher icon in the APK'
}

if ($badging -match "(?m)^application-debuggable") {
    Fail 'the APK is marked debuggable'
} else {
    Pass 'not debuggable'
}

$abis = [regex]::Matches($badging, "native-code:\s*(.+)") | ForEach-Object { $_.Groups[1].Value.Trim() }
if ($abis) { Write-Host "        ABIs        $abis" }

# --- Signature ------------------------------------------------------------
Write-Host ''
Write-Host '--- Signature ---' -ForegroundColor Cyan

# apksigner writes to stderr as well, and PowerShell 5.1 turns a native
# command's stderr into error records - so it is captured as plain text.
$verifyOut  = & cmd /c "`"$apksigner`" verify --verbose --print-certs `"$ApkPath`" 2>&1"
$verifyExit = $LASTEXITCODE
$verifyText = ($verifyOut | Out-String)

if ($verifyExit -ne 0) {
    Fail "apksigner could not verify the APK (exit $verifyExit)."
    Write-Host $verifyText -ForegroundColor DarkGray
} else {
    Pass 'apksigner verifies the APK'
}

function Test-Scheme([string]$scheme) {
    # The scheme name contains a dot in "v3.1", so it is escaped rather than
    # left as a regex wildcard that would also match "v301".
    return $verifyText -match ("(?im)^Verified using {0} scheme \(.*\):\s*true" -f [regex]::Escape($scheme))
}

# v2 arrived in Android 7.0, which is API 24. If the APK cannot be installed
# below 24, every device that can install it verifies v2 - and v1 (JAR
# signing) is not merely redundant there but actively worse: a v1-only APK is
# what the Janus vulnerability (CVE-2017-13156) exploits. AGP drops v1 for
# minSdk >= 24 on purpose, so it is only required here below that.
if ($minSdk -lt 24) {
    if (Test-Scheme 'v1') { Pass 'signed with v1 scheme (required: minSdk < 24)' }
    else { Fail "NOT signed with v1 scheme, and minSdk is $minSdk - Android 6 and below cannot verify this APK" }
} else {
    if (Test-Scheme 'v1') { Note "v1 also present (not required at minSdk $minSdk)" }
    else { Note "v1 not used - correct, minSdk $minSdk means every device supports v2" }
}

foreach ($scheme in @('v2', 'v3')) {
    if (Test-Scheme $scheme) { Pass "signed with $scheme scheme" }
    else { Fail "NOT signed with $scheme scheme" }
}

# --- Signing identity -----------------------------------------------------
Write-Host ''
Write-Host '--- Signing identity ---' -ForegroundColor Cyan

if ($verifyText -match 'CN=Android Debug' -or $verifyText -match 'O=Android, C=US') {
    Fail 'SIGNED WITH THE ANDROID DEBUG KEY. This APK must not be distributed.'
} else {
    Pass 'not the Android debug certificate'
}

# Build-tools 35+ label these lines "V3.0 Signer:" where older ones said
# "Signer #1"; both spellings are accepted so the script does not silently
# skip the most important comparison after an SDK update.
$signerLine = '(?m)^(?:Signer #\d+|V\d+(?:\.\d+)? Signer):?\s+certificate'

if ($verifyText -match ($signerLine + ' DN:\s*(.+)$')) {
    Write-Host "        DN          $($Matches[1].Trim())"
}

$apkSha256 = $null
if ($verifyText -match ($signerLine + ' SHA-256 digest:\s*([0-9a-fA-F]{64})')) {
    $apkSha256 = $Matches[1].ToLowerInvariant()
    Write-Host "        SHA-256     $apkSha256"
} else {
    Warn 'could not parse the certificate fingerprint out of apksigner output'
}

# --- Certificate matches the project keystore -----------------------------
$expectedAlias = $null
$expectedPass  = $null
if (-not $ExpectedKeystore) {
    $propsPath = Join-Path $repoRoot 'android\key.properties'
    if (Test-Path $propsPath) {
        $props = @{}
        Get-Content $propsPath | ForEach-Object {
            if ($_ -match '^\s*([^#!][^=]*)=(.*)$') { $props[$Matches[1].Trim()] = $Matches[2].Trim() }
        }
        $ExpectedKeystore = $props['storeFile']
        $expectedAlias    = $props['keyAlias']
        $expectedPass     = $props['storePassword']
    }
}

if (-not $ExpectedKeystore) {
    Warn 'no android\key.properties on this machine; skipped the keystore comparison'
} elseif (-not (Test-Path $ExpectedKeystore)) {
    Warn "the keystore named in key.properties is missing ($ExpectedKeystore); skipped the comparison"
} elseif (-not $apkSha256) {
    Warn 'no fingerprint parsed from the APK; skipped the keystore comparison'
} else {
    $keytool = @(
        "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe",
        "$env:ProgramFiles\Android\Android Studio\jre\bin\keytool.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $keytool) {
        $onPath = Get-Command keytool -ErrorAction SilentlyContinue
        if ($onPath) { $keytool = $onPath.Source }
    }

    if (-not $keytool) {
        Warn 'keytool not found; skipped the keystore comparison'
    } else {
        $listing = & cmd /c "`"$keytool`" -list -v -keystore `"$ExpectedKeystore`" -storepass `"$expectedPass`" -alias `"$expectedAlias`" 2>&1" | Out-String
        if ($listing -match 'SHA256:\s*([0-9A-Fa-f:]+)') {
            $keystoreSha = $Matches[1].Replace(':', '').ToLowerInvariant()
            if ($keystoreSha -eq $apkSha256) {
                Pass 'certificate matches this project''s release keystore'
            } else {
                Fail "certificate does NOT match $ExpectedKeystore (keystore $keystoreSha vs apk $apkSha256)"
            }
        } else {
            Warn 'could not read the fingerprint out of the keystore'
        }
    }
}

# --- Permissions ----------------------------------------------------------
Write-Host ''
Write-Host '--- Permissions (merged, including any a plugin added) ---' -ForegroundColor Cyan
[regex]::Matches($badging, "uses-permission: name='([^']+)'(?:\s+maxSdkVersion='(\d+)')?") |
    ForEach-Object {
        $name = $_.Groups[1].Value
        $max  = $_.Groups[2].Value
        if ($max) { Write-Host "          $name  (maxSdkVersion $max)" }
        else      { Write-Host "          $name" }
    }

# --- Verdict --------------------------------------------------------------
Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "=== $($failures.Count) check(s) FAILED ===" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

Write-Host '=== All checks passed. This APK is signed and installable. ===' -ForegroundColor Green
Write-Host ''
Write-Host "  $ApkPath"
Write-Host ''
exit 0
