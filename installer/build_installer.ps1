# Builds HozaSend for Windows and packs it into one Setup.exe.
#
#   .\installer\build_installer.ps1
#
# Needs two things installed:
#   - Visual Studio with the "Desktop development with C++" workload
#     (flutter doctor will tell you if it is missing)
#   - Inno Setup 6            https://jrsoftware.org/isdl.php
#
# The result lands in dist\HozaSend-Setup-<version>.exe and is fully
# self-contained: the exe, the Flutter runtime, every plugin DLL and the data
# folder are all inside that one file.

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$script      = Join-Path $PSScriptRoot 'hoza_send.iss'
$releaseDir  = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$distDir     = Join-Path $projectRoot 'dist'

Write-Host ''
Write-Host '=== 1/3  Building the Windows release ===' -ForegroundColor Cyan
Push-Location $projectRoot
try {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        throw 'flutter build failed. Run "flutter doctor -v" and check the Visual Studio line.'
    }
}
finally {
    Pop-Location
}

# Guards against packaging a stale or empty folder into a setup that installs
# an app which cannot start.
$exe = Join-Path $releaseDir 'hoza_send.exe'
if (-not (Test-Path $exe)) {
    throw "Build finished but $exe is missing."
}
if (-not (Test-Path (Join-Path $releaseDir 'data'))) {
    throw "The data folder is missing from the build. The app will not start without it."
}

Write-Host ''
Write-Host '=== 2/3  Locating Inno Setup ===' -ForegroundColor Cyan

# Look where the installer puts it, then fall back to PATH.
$candidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
)
$iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    $onPath = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($onPath) { $iscc = $onPath.Source }
}
if (-not $iscc) {
    throw 'Inno Setup 6 not found. Install it from https://jrsoftware.org/isdl.php'
}
Write-Host "  $iscc"

Write-Host ''
Write-Host '=== 3/3  Packing the installer ===' -ForegroundColor Cyan
if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir | Out-Null
}

& $iscc $script
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed.' }

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Get-ChildItem $distDir -Filter '*.exe' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 |
    ForEach-Object {
        $mb = [math]::Round($_.Length / 1MB, 1)
        Write-Host "  $($_.FullName)  ($mb MB)" -ForegroundColor Green
    }
