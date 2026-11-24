#Requires -Version 7.2
<#
.SYNOPSIS
    Windows installer: PowerShell 7 profile, Windows Terminal look, fonts.

.DESCRIPTION
    Idempotent.
    - Replaces Documents\PowerShell\Microsoft.PowerShell_profile.ps1 with a
      one-line stub that dot-sources powershell/ from this repo, backing up
      whatever was there first.
    - Writes a commented ~/.pwsh.local.ps1 template the first time; never
      overwrites one that exists.
    - Installs windows-terminal/dotfiles.json as a Windows Terminal fragment
      (VS Code Dark colours and SFMono on the PowerShell profile). Fragments
      add to settings.json without editing it; settings.json still wins.
    - Installs fonts/ for the current user if no SFMono font is present.

.EXAMPLE
    ./install.ps1           # profile, terminal fragment, fonts
    ./install.ps1 -Tools    # also install zoxide (and Terminal-Icons, opt-in in the profile)
    ./install.ps1 -Tune     # also turn off pwsh's telemetry and update check (~30 ms per start)
#>
[CmdletBinding()]
param([switch]$Tools, [switch]$Tune)

$ErrorActionPreference = 'Stop'

# Profile
$source = Join-Path $PSScriptRoot 'powershell\Microsoft.PowerShell_profile.ps1'
$target = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1'
$stub = @"
# Managed by $PSScriptRoot\install.ps1. Edit the repo copy, not this file.
. "$source"
"@

New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
if (Test-Path $target) {
    if ((Get-Content $target -Raw).Trim() -eq $stub.Trim()) {
        Write-Host "profile   already linked: $target"
    } else {
        $backup = "$target.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Move-Item $target $backup
        Write-Host "profile   backed up to $backup"
    }
}
if (-not (Test-Path $target)) {
    Set-Content -Path $target -Value $stub
    Write-Host "profile   linked: $target -> $source"
}

$local = Join-Path $HOME '.pwsh.local.ps1'
if (-not (Test-Path $local)) {
    Set-Content -Path $local -Value @'
# Machine-specific PowerShell settings. Loaded by the dotfiles profile, never committed.
# $ProfileMode is 'full' in an interactive terminal and 'lite' in scripts and agents.
#
# $env:PATH = "$HOME\bin;$env:PATH"
# $env:DEFAULT_USER = $env:USERNAME          # hide the ✝ segment, as on oh-my-zsh
# $ProfileIcons = $true                      # Terminal-Icons in ls (~0.5 s on the first ls)
'@
    Write-Host "local     template written: $local"
}

# Windows Terminal fragment
$fragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\dotfiles'
New-Item -ItemType Directory -Force $fragmentDir | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'windows-terminal\dotfiles.json') $fragmentDir -Force
Write-Host "terminal  fragment installed: $fragmentDir (restart Windows Terminal)"

# Fonts, per user, only when no SFMono is installed
$fontKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$installed = @((Get-ItemProperty $fontKey -ErrorAction Ignore).PSObject.Properties.Name) +
             @((Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts').PSObject.Properties.Name)
if (-not ($installed -match 'SF ?Mono')) {
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    New-Item -ItemType Directory -Force $fontDir | Out-Null
    if (-not (Test-Path $fontKey)) { New-Item $fontKey -Force | Out-Null }
    foreach ($font in Get-ChildItem (Join-Path $PSScriptRoot 'fonts') -Filter *.otf) {
        $dest = Join-Path $fontDir $font.Name
        Copy-Item $font.FullName $dest -Force
        New-ItemProperty $fontKey -Name "$($font.BaseName) (OpenType)" -Value $dest -Force | Out-Null
    }
    Write-Host "fonts     SFMono installed for this user"
} else {
    Write-Host 'fonts     SFMono already installed'
}

if ($Tools) {
    winget install --id ajeetdsouza.zoxide --exact --source winget --accept-package-agreements --silent
    if (-not (Get-Module -ListAvailable Terminal-Icons)) {
        Install-Module Terminal-Icons -Scope CurrentUser -Repository PSGallery
    }
    Write-Host 'tools     installed'
}

if ($Tune) {
    # Read once at process start, so they only help as user environment variables.
    [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'User')
    [Environment]::SetEnvironmentVariable('POWERSHELL_UPDATECHECK', 'Off', 'User')
    Write-Host 'tune      telemetry and update check off (user environment; new terminals pick it up)'
}

Write-Host 'done      open a new terminal.'
