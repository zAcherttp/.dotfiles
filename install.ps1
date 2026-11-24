#Requires -Version 7.2
<#
.SYNOPSIS
    Windows installer: points the PowerShell 7 profile at this repo.

.DESCRIPTION
    Idempotent. Replaces Documents\PowerShell\Microsoft.PowerShell_profile.ps1
    with a one-line stub that dot-sources powershell/ from this repo, backing up
    whatever was there first. Writes a commented ~/.pwsh.local.ps1 template the
    first time; never overwrites one that exists.

.EXAMPLE
    ./install.ps1           # profile only
    ./install.ps1 -Tools    # also install oh-my-posh, zoxide and Terminal-Icons
#>
[CmdletBinding()]
param([switch]$Tools)

$ErrorActionPreference = 'Stop'
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
# $env:POSH_THEME = "$HOME\my-theme.omp.json"
# if ($ProfileMode -eq 'full') { Set-Alias -Name vim -Value nvim }
'@
    Write-Host "local     template written: $local"
}

if ($Tools) {
    foreach ($id in 'JanDeDobbeleer.OhMyPosh', 'ajeetdsouza.zoxide') {
        winget install --id $id --exact --source winget --accept-package-agreements --silent
    }
    if (-not (Get-Module -ListAvailable Terminal-Icons)) {
        Install-Module Terminal-Icons -Scope CurrentUser -Repository PSGallery
    }
    Write-Host 'tools     installed. The prompt needs a Nerd Font in your terminal (fonts/ has SFMono).'
}

Write-Host 'done      open a new terminal.'
