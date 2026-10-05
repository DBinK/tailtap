#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Build TailTap for Windows.

.DESCRIPTION
    Windows counterpart to scripts/build-desktop.sh. It installs Dart
    dependencies, builds the Go tunnel core (core/cmd/tailtap), builds the
    Flutter Windows runner, and copies tailtap-core.exe beside TailTap.exe so
    the app can launch it at runtime.

    Debug is the default mode and the host architecture is the default target,
    matching build-desktop.sh.

    'flutter build windows' can only target the architecture of the machine it
    runs on, so -Arch must match the host. Use an arm64 machine to build arm64.

.PARAMETER Mode
    Build mode: debug or release. Defaults to debug. Also accepted as a bare
    positional value, so --release works however PowerShell parses it.

.PARAMETER Debug
    Build a debug bundle. This is the default.

.PARAMETER Release
    Build a release bundle. The Go core is built with -trimpath and stripped
    symbols.

.PARAMETER Arch
    Target architecture: x86_64 or arm64. Defaults to the host architecture.
    Must match the host architecture.

.PARAMETER Package
    Also write build/tailtap_<version>_windows_<goarch>.zip.

.EXAMPLE
    pwsh scripts/build-desktop.ps1

.EXAMPLE
    pwsh scripts/build-desktop.ps1 --release

.EXAMPLE
    pwsh scripts/build-desktop.ps1 -Release -Package

.EXAMPLE
    pwsh scripts/build-desktop.ps1 release -Package
#>
param(
    # Declared first so a bare positional binds here, which also catches the
    # literal '--release' that some shells pass as a value rather than as a
    # parameter. Avoids [Parameter()], which would turn this into an advanced
    # script and clash with the built-in -Debug common parameter.
    [string]$Mode = 'debug',

    [switch]$Debug,
    [switch]$Release,

    [ValidateSet('x86_64', 'arm64')]
    [string]$Arch,

    [switch]$Package
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Mode -like '--*') { $Mode = $Mode.Substring(2) }
$Mode = $Mode.ToLowerInvariant()
if ($Mode -notin @('debug', 'release')) {
    throw "Unknown build mode '$Mode'. Use debug or release."
}

if ($Debug -and $Release) {
    throw 'Use either -Debug or -Release, not both.'
}
if ($Release) { $Mode = 'release' }
if ($Debug) { $Mode = 'debug' }

$configuration = if ($Mode -eq 'release') { 'Release' } else { 'Debug' }

$hostArch = switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { 'x86_64' }
    'ARM64' { 'arm64' }
    default { throw "Unsupported host architecture: $env:PROCESSOR_ARCHITECTURE" }
}

if (-not $Arch) { $Arch = $hostArch }
if ($Arch -ne $hostArch) {
    throw "flutter build windows can only target the host architecture ($hostArch). Run this script on a $Arch machine to build $Arch."
}

$goarch = if ($Arch -eq 'arm64') { 'arm64' } else { 'amd64' }
$flutterArch = if ($Arch -eq 'arm64') { 'arm64' } else { 'x64' }

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

foreach ($tool in 'flutter', 'go') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool was not found on PATH."
    }
}

Push-Location $root
try {
    Write-Host '==> flutter pub get'
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

    Write-Host "==> building Go core (windows/$goarch, $Mode)"
    New-Item -ItemType Directory -Force (Join-Path $root 'core/bin') | Out-Null
    $goArgs = @('build')
    if ($Mode -eq 'release') { $goArgs += @('-trimpath', '-ldflags', '-s -w') }
    $goArgs += @('-o', 'bin/tailtap-core.exe', './cmd/tailtap')
    Push-Location (Join-Path $root 'core')
    try {
        $env:CGO_ENABLED = '0'
        $env:GOOS = 'windows'
        $env:GOARCH = $goarch
        & go @goArgs
        if ($LASTEXITCODE -ne 0) { throw 'go build failed.' }
    }
    finally {
        Pop-Location
    }

    Write-Host "==> flutter build windows --$Mode"
    flutter build windows "--$Mode"
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed.' }

    $bundle = Join-Path $root "build/windows/$flutterArch/runner/$configuration"
    $exe = Join-Path $bundle 'TailTap.exe'
    if (-not (Test-Path $exe)) { throw "Build output not found: $exe" }

    Write-Host '==> bundling tailtap-core.exe'
    $coreExe = Join-Path $bundle 'tailtap-core.exe'
    # The freshly written bundle can still be held by antivirus or the indexer.
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            Copy-Item (Join-Path $root 'core/bin/tailtap-core.exe') $bundle -Force
            break
        }
        catch {
            if ($attempt -eq 5) { throw }
            Start-Sleep -Milliseconds 500
        }
    }

    Write-Host '==> bundling license notices'
    $licenseDir = Join-Path $bundle 'licenses'
    New-Item -ItemType Directory -Force $licenseDir | Out-Null
    Copy-Item (Join-Path $root 'LICENSE') $licenseDir -Force
    Copy-Item (Join-Path $root 'THIRD_PARTY_NOTICES.md') $licenseDir -Force
    Copy-Item (Join-Path $root 'third_party_licenses') $licenseDir -Recurse -Force

    if (-not (Test-Path $coreExe)) { throw "Core binary missing from bundle: $coreExe" }

    $archive = $null
    if ($Package) {
        $versionLine = Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:'
        $version = $versionLine.Line.Split(':', 2)[1].Trim().Split('+')[0]
        $archive = Join-Path $root "build/tailtap_${version}_windows_$goarch.zip"
        Write-Host "==> packaging $([System.IO.Path]::GetFileName($archive))"
        Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $archive -Force
    }

    Write-Host ''
    Write-Host "Bundle: $bundle"
    Write-Host "  TailTap.exe       $([math]::Round((Get-Item $exe).Length / 1MB, 1)) MB"
    Write-Host "  tailtap-core.exe  $([math]::Round((Get-Item $coreExe).Length / 1MB, 1)) MB"
    if ($archive) { Write-Host "Archive: $archive" }
}
finally {
    Pop-Location
}
