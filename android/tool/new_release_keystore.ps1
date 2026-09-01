<#
.SYNOPSIS
    Creates the HozaSend Android release keystore, once.

.DESCRIPTION
    The keystore is the app's permanent identity on Android. Android has no
    central authority for sideloaded apps: what makes an update "the same app"
    as the version already installed is that both were signed by this key. If
    it is lost, there is no recovery and no appeal - every user has to
    uninstall and reinstall, losing their settings, because Android refuses to
    replace an app with one signed by a different key.

    So: run this once, then back the .jks file and its password up somewhere
    that is not this computer.

    The keystore is deliberately written OUTSIDE the repository, so that no
    .gitignore mistake can ever commit it. android\key.properties points
    Gradle at it and is itself ignored.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File android\tool\new_release_keystore.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File android\tool\new_release_keystore.ps1 -Password (Read-Host -AsSecureString)
#>
[CmdletBinding()]
param(
    # Where the keystore lands. Outside the repo on purpose.
    [string]$KeystorePath = (Join-Path $env:USERPROFILE '.keystores\hozasend-release.jks'),

    # The name inside the certificate. Cosmetic on Android - identity comes
    # from the key itself - but it shows up in `apksigner verify --print-certs`
    # and in store listings, so it should be the real publisher.
    [string]$DistinguishedName = 'CN=Rahoz Osman Salim, O=HozaSend',

    [string]$Alias = 'hozasend',

    # 10000 days ~ 27 years. The usual floor is "must outlive the app"; Google
    # Play requires validity past 2033 and the same rule is a good idea here.
    [int]$ValidityDays = 10000,

    # Supply your own, or let the script generate a 32-character random one.
    [securestring]$Password,

    # Overwrite an existing keystore. Almost always the wrong thing to do.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Find-KeyTool {
    # Prefer the JDK that Gradle itself will run on, so the keystore is written
    # by the same vintage of tooling that has to read it back.
    # JAVA_HOME is usually unset on a machine that only ever builds through
    # Android Studio, and Join-Path throws on a null path rather than skipping
    # it - so it is tested for rather than assumed.
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += (Join-Path $env:JAVA_HOME 'bin\keytool.exe') }
    $candidates += @(
        "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe",
        "$env:ProgramFiles\Android\Android Studio\jre\bin\keytool.exe",
        "${env:ProgramFiles(x86)}\Android\Android Studio\jbr\bin\keytool.exe"
    )
    $candidates = @($candidates | Where-Object { Test-Path $_ })

    if ($candidates) { return $candidates[0] }

    $onPath = Get-Command keytool -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    throw 'keytool not found. Install a JDK 17+, or set JAVA_HOME.'
}

if ((Test-Path $KeystorePath) -and -not $Force) {
    Write-Host ''
    Write-Host "A keystore already exists at:" -ForegroundColor Yellow
    Write-Host "  $KeystorePath"
    Write-Host ''
    Write-Host 'Refusing to overwrite it. Replacing a release keystore breaks every' -ForegroundColor Yellow
    Write-Host 'update path for everyone who already installed the app. Pass -Force'  -ForegroundColor Yellow
    Write-Host 'only if you are certain nothing signed by it was ever distributed.'   -ForegroundColor Yellow
    exit 1
}

# -Force means "start over", so the old file has to go first: keytool
# -genkeypair against an existing keystore tries to *open* it, and fails on the
# password rather than replacing it.
if ((Test-Path $KeystorePath) -and $Force) {
    Write-Host "Removing the existing keystore at $KeystorePath" -ForegroundColor Yellow
    Remove-Item -LiteralPath $KeystorePath -Force
}

$keytool = Find-KeyTool
Write-Host "keytool: $keytool" -ForegroundColor DarkGray

# --- The password ---------------------------------------------------------
if ($Password) {
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    try {
        $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $generated = $false
} else {
    # 32 chars from a 62-character alphabet is ~190 bits. Alphanumeric only:
    # this string has to survive .properties files, shell quoting and base64
    # round-trips through CI, and punctuation is where that goes wrong.
    $alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $plain = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
    $generated = $true
}

$dir = Split-Path -Parent $KeystorePath
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

# --- Generate -------------------------------------------------------------
# PKCS12 rather than the older proprietary JKS: it is the standard format, it
# is what keytool defaults to on JDK 9+, and it avoids the "migrate to PKCS12"
# warning on every read. PKCS12 keeps one password for the store and the key,
# which is why -keypass matches -storepass here.
Write-Host ''
Write-Host '=== Generating the release keystore ===' -ForegroundColor Cyan

& $keytool -genkeypair -v `
    -keystore   $KeystorePath `
    -storetype  PKCS12 `
    -keyalg     RSA `
    -keysize    2048 `
    -validity   $ValidityDays `
    -alias      $Alias `
    -dname      $DistinguishedName `
    -storepass  $plain `
    -keypass    $plain

if ($LASTEXITCODE -ne 0) { throw "keytool failed with exit code $LASTEXITCODE." }

# --- Point Gradle at it ---------------------------------------------------
# storeFile is written with forward slashes: a .properties file treats a
# backslash as an escape, so C:\Users\... would silently become C:Users....
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$propsPath = Join-Path $repoRoot 'android\key.properties'
# String.Replace, not -replace: the latter takes a regex, where a lone
# backslash is not a pattern at all.
$storeForProps = $KeystorePath.Replace('\', '/')

@"
# Generated by android\tool\new_release_keystore.ps1 - DO NOT COMMIT.
# .gitignore excludes this file; if it ever shows up in git status, stop and
# fix the ignore rule rather than committing it.
storeFile=$storeForProps
storePassword=$plain
keyAlias=$Alias
keyPassword=$plain
"@ | ForEach-Object {
    # Written without a byte-order mark. Windows PowerShell's -Encoding utf8
    # emits one, and java.util.Properties.load reads the stream as ISO-8859-1 -
    # so those three bytes would be glued onto the first line instead of being
    # recognised as a BOM.
    [System.IO.File]::WriteAllText($propsPath, $_, (New-Object System.Text.UTF8Encoding $false))
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host ''
Write-Host "  Keystore      $KeystorePath"
Write-Host "  Alias         $Alias"
Write-Host "  Gradle config $propsPath"
Write-Host ''

& $keytool -list -v -keystore $KeystorePath -storepass $plain -alias $Alias |
    Select-String -Pattern 'Alias name|Creation date|Owner|Valid from|SHA256:|Signature algorithm'

if ($generated) {
    Write-Host ''
    Write-Host '--------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host ' BACK THIS UP NOW' -ForegroundColor Yellow
    Write-Host '--------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host ' A random password was generated and written to key.properties.'
    Write-Host ' Copy BOTH of these somewhere safe and off this machine - a'
    Write-Host ' password manager, an encrypted archive, anywhere but here:'
    Write-Host ''
    Write-Host "   1. the keystore file   $KeystorePath"
    Write-Host "   2. the password        (in $propsPath)"
    Write-Host ''
    Write-Host ' Lose either one and this app can never be updated again.' -ForegroundColor Yellow
    Write-Host '--------------------------------------------------------------' -ForegroundColor Yellow
}
