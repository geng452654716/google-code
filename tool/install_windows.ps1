<#
.SYNOPSIS
Installs TOTP Vault for the current Windows user.

.DESCRIPTION
Uses a staging directory and a backup directory for recoverable upgrades. The
script never requests administrator privileges, never changes PATH, and never
removes Vault or backup data during uninstall.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Source,

    [Parameter()]
    [string]$Destination,

    [Parameter()]
    [switch]$SkipBuild,

    [Parameter()]
    [switch]$Launch,

    [Parameter()]
    [switch]$Uninstall,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$SkipShortcut
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = Join-Path $RepositoryRoot 'build\windows\x64\runner\Release'
}
if ([string]::IsNullOrWhiteSpace($Destination)) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is not available; provide -Destination explicitly.'
    }
    $Destination = Join-Path $env:LOCALAPPDATA 'Programs\TOTP Vault'
}

$Source = [System.IO.Path]::GetFullPath($Source)
$Destination = [System.IO.Path]::GetFullPath($Destination)
$ExecutableName = 'google_code.exe'
$ExecutablePath = Join-Path $Destination $ExecutableName
$ProgramsDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
$ShortcutPath = if ([string]::IsNullOrWhiteSpace($ProgramsDirectory)) {
    $null
} else {
    Join-Path $ProgramsDirectory 'TOTP Vault.lnk'
}

function Write-InstallerLog {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[TOTP Vault installer] $Message"
}

function Assert-SafeDestination {
    param([Parameter(Mandatory)][string]$Path)

    $root = [System.IO.Path]::GetPathRoot($Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -eq $root) {
        throw "Unsafe destination path: $Path"
    }
    if ([string]::Equals($Path, $Source, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Source and destination must be different paths.'
    }
}

function Assert-AppNotRunning {
    if (Get-Process -Name 'google_code' -ErrorAction SilentlyContinue) {
        throw 'TOTP Vault is running. Quit it before installing, upgrading, or uninstalling.'
    }
}

function Remove-ManagedShortcut {
    if ($SkipShortcut -or [string]::IsNullOrWhiteSpace($ShortcutPath)) {
        return
    }
    if (Test-Path -LiteralPath $ShortcutPath) {
        Remove-Item -LiteralPath $ShortcutPath -Force
    }
}

function New-ManagedShortcut {
    if ($SkipShortcut) {
        Write-InstallerLog 'Start Menu shortcut creation was skipped.'
        return
    }
    if ([string]::IsNullOrWhiteSpace($ShortcutPath)) {
        throw 'The current user Start Menu location is unavailable.'
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $ExecutablePath
    $shortcut.WorkingDirectory = $Destination
    $shortcut.Description = 'TOTP Vault offline authenticator'
    $shortcut.Save()
    Write-InstallerLog "Start Menu shortcut: $ShortcutPath"
}

Assert-SafeDestination -Path $Destination
if ($Uninstall -and $Launch) {
    throw '-Launch cannot be combined with -Uninstall.'
}
Assert-AppNotRunning

if ($Uninstall) {
    Write-InstallerLog "Uninstall target: $Destination"
    Write-InstallerLog 'Vault, Windows Credential Manager entries, and .gcbak files will not be removed.'
    if ($DryRun) {
        Write-InstallerLog 'Dry run complete; no files were changed.'
        return
    }

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
        Write-InstallerLog 'Application removed. User data was preserved.'
    } else {
        Write-InstallerLog 'Application is not installed; nothing to remove.'
    }
    Remove-ManagedShortcut
    return
}

if (-not $SkipBuild) {
    Write-InstallerLog 'Building Windows Release app...'
    if ($DryRun) {
        Write-InstallerLog "Would run a Flutter Release build in $RepositoryRoot."
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

Write-InstallerLog "Source: $Source"
Write-InstallerLog "Destination: $Destination"
Write-InstallerLog 'Install scope: current user only; no administrator privileges are requested.'
Write-InstallerLog 'Signature expectation: unsigned/local only; SmartScreen is not bypassed.'

if ($DryRun) {
    Write-InstallerLog 'Dry run complete; no files were changed.'
    return
}

$ParentDirectory = Split-Path -Parent $Destination
$TransactionId = [Guid]::NewGuid().ToString('N')
$StagingDirectory = "$Destination.installing-$TransactionId"
$BackupDirectory = "$Destination.backup-$TransactionId"
$BackupCreated = $false
$DestinationPromoted = $false
$InstallCompleted = $false

try {
    New-Item -ItemType Directory -Force -Path $ParentDirectory | Out-Null
    New-Item -ItemType Directory -Force -Path $StagingDirectory | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $StagingDirectory -Recurse -Force

    $StagedExecutable = Join-Path $StagingDirectory $ExecutableName
    if (-not (Test-Path -LiteralPath $StagedExecutable -PathType Leaf)) {
        throw 'Staged application is incomplete.'
    }

    if (Test-Path -LiteralPath $Destination) {
        Move-Item -LiteralPath $Destination -Destination $BackupDirectory
        $BackupCreated = $true
    }
    Move-Item -LiteralPath $StagingDirectory -Destination $Destination
    $DestinationPromoted = $true
    New-ManagedShortcut
    $InstallCompleted = $true

    if (Test-Path -LiteralPath $BackupDirectory) {
        Remove-Item -LiteralPath $BackupDirectory -Recurse -Force
    }
    $BackupCreated = $false
} finally {
    if (Test-Path -LiteralPath $StagingDirectory) {
        Remove-Item -LiteralPath $StagingDirectory -Recurse -Force
    }
    if (-not $InstallCompleted) {
        if ($DestinationPromoted -and (Test-Path -LiteralPath $Destination)) {
            Remove-Item -LiteralPath $Destination -Recurse -Force
        }
        if ($BackupCreated -and (Test-Path -LiteralPath $BackupDirectory)) {
            Move-Item -LiteralPath $BackupDirectory -Destination $Destination
            Write-Warning 'Upgrade failed; the previous installation was restored.'
        }
    } elseif (Test-Path -LiteralPath $BackupDirectory) {
        Remove-Item -LiteralPath $BackupDirectory -Recurse -Force
    }
}

Write-InstallerLog 'Installation completed successfully.'
if ($Launch) {
    Start-Process -FilePath $ExecutablePath -WorkingDirectory $Destination
    Write-InstallerLog 'Application launch requested.'
} else {
    Write-InstallerLog "Launch from the Start Menu or run: `"$ExecutablePath`""
}
