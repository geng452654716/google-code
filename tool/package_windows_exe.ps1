<#
.SYNOPSIS
Builds a personal-use Windows setup EXE for TOTP Vault.

.DESCRIPTION
Builds or reuses the Flutter Windows Release directory and compiles it with
Inno Setup. The resulting installer is current-user scoped, unsigned, and does
not bypass SmartScreen. Uninstall preserves Vault data, Windows Credential
Manager entries, and .gcbak backups because they live outside the app directory.
#>
[CmdletBinding()]
param(
    [string]$Source,
    [string]$OutputDirectory,
    [string]$InnoCompiler,
    [switch]$SkipBuild,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = Join-Path $RepositoryRoot 'build\windows\x64\runner\Release'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $RepositoryRoot 'dist\windows'
}
$InstallerScript = Join-Path $RepositoryRoot 'windows\installer\google_code.iss'
$ExecutableName = 'google_code.exe'

function Write-PackagerLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[TOTP Vault EXE] $Message"
}

function Resolve-InnoCompiler {
    if (-not [string]::IsNullOrWhiteSpace($InnoCompiler)) {
        if (-not (Test-Path -LiteralPath $InnoCompiler -PathType Leaf)) {
            throw "Inno Setup compiler does not exist: $InnoCompiler"
        }
        return (Resolve-Path -LiteralPath $InnoCompiler).Path
    }

    $command = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidates += Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    throw 'Inno Setup 6 compiler (ISCC.exe) was not found. Install Inno Setup 6 or pass -InnoCompiler.'
}

$VersionLine = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'pubspec.yaml') |
    Where-Object { $_ -match '^version:\s*[0-9]+\.[0-9]+\.[0-9]+(?:\+[0-9]+)?\s*$' } |
    Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($VersionLine)) {
    throw 'Unable to read a valid version from pubspec.yaml.'
}
$VersionValue = ($VersionLine -replace '^version:\s*', '').Trim()
$VersionParts = $VersionValue.Split('+', 2)
$AppVersion = $VersionParts[0]
$BuildNumber = if ($VersionParts.Length -eq 2) { $VersionParts[1] } else { '0' }
$PackageVersion = "$AppVersion-build$BuildNumber"
$OutputBaseFilename = "TOTPVault-$PackageVersion-windows-x64-setup"
$ExpectedInstaller = Join-Path $OutputDirectory "$OutputBaseFilename.exe"
$ChecksumPath = "$ExpectedInstaller.sha256"

if (-not $SkipBuild) {
    Write-PackagerLog 'Building Windows Release app...'
    if ($DryRun) {
        Write-PackagerLog "Would run a Flutter Release build in $RepositoryRoot."
    } else {
        Push-Location $RepositoryRoot
        try {
            $LASTEXITCODE = 0
            $FlutterBuildArguments = @('build', 'windows', '--release')
            if (-not [string]::IsNullOrWhiteSpace($env:TOTP_VAULT_GITHUB_CLIENT_ID)) {
                $FlutterBuildArguments += "--dart-define=TOTP_VAULT_GITHUB_CLIENT_ID=$($env:TOTP_VAULT_GITHUB_CLIENT_ID)"
            }
            if (Get-Command 'fvm' -ErrorAction SilentlyContinue) {
                & fvm flutter @FlutterBuildArguments
            } elseif (Get-Command 'flutter' -ErrorAction SilentlyContinue) {
                & flutter @FlutterBuildArguments
            } else {
                throw 'Neither fvm nor flutter is available. Install Flutter or use -SkipBuild.'
            }
            if ($LASTEXITCODE -ne 0) {
                throw "Flutter build failed with exit code $LASTEXITCODE."
            }
        } finally {
            Pop-Location
        }
    }
}

$SourceExecutable = Join-Path $Source $ExecutableName
if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    throw "Source directory does not exist: $Source"
}
if (-not (Test-Path -LiteralPath $SourceExecutable -PathType Leaf)) {
    throw "Source executable is missing: $SourceExecutable"
}
if (-not (Test-Path -LiteralPath $InstallerScript -PathType Leaf)) {
    throw "Inno Setup definition is missing: $InstallerScript"
}

$Compiler = Resolve-InnoCompiler
Write-PackagerLog "Source: $Source"
Write-PackagerLog "Output: $ExpectedInstaller"
Write-PackagerLog "Compiler: $Compiler"
Write-PackagerLog 'Install scope: current user only; no administrator privileges are requested.'
Write-PackagerLog 'Signature expectation: unsigned/local only; SmartScreen is not bypassed.'

if ($DryRun) {
    Write-PackagerLog 'Dry run complete; no files were changed.'
    return
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$arguments = @(
    "/DAppVersion=$AppVersion",
    "/DBuildNumber=$BuildNumber",
    "/DSourceDir=$Source",
    "/DOutputDir=$OutputDirectory",
    "/DOutputBaseFilename=$OutputBaseFilename",
    $InstallerScript
)
$LASTEXITCODE = 0
& $Compiler @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $ExpectedInstaller -PathType Leaf)) {
    throw "Expected installer was not produced: $ExpectedInstaller"
}

$hash = (Get-FileHash -LiteralPath $ExpectedInstaller -Algorithm SHA256).Hash.ToLowerInvariant()
$checksum = "$hash  $([System.IO.Path]::GetFileName($ExpectedInstaller))`n"
[System.IO.File]::WriteAllText($ChecksumPath, $checksum, [System.Text.Encoding]::ASCII)

$signature = Get-AuthenticodeSignature -LiteralPath $ExpectedInstaller
Write-PackagerLog "Authenticode status: $($signature.Status)"
Write-PackagerLog 'Setup EXE created successfully.'
Write-PackagerLog "SHA-256: $hash"
Write-PackagerLog "Package: $ExpectedInstaller"
Write-PackagerLog "Checksum: $ChecksumPath"
