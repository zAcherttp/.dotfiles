#Requires -Version 7.2
# PowerShell profile: the fast path runs at startup, everything heavy waits
# until it is needed.
#
#   startup      functions, aliases, PSReadLine, a plain prompt   (no processes spawned)
#   first idle   oh-my-posh prompt + zoxide, from a cached init script
#   first `ls`   Terminal-Icons (it costs ~1s to import, and only `ls` uses it)
#
# Mode is detected per shell; override with $env:PWSH_PROFILE_MODE = 'full' | 'lite'.
#   full  an interactive terminal
#   lite  `pwsh -c`, scripts, agents, redirected input: functions only, nothing spawned
#
# Machine-specific settings (tokens, PATH, aliases) go in ~/.pwsh.local.ps1,
# which this repo never tracks. $ProfileMode tells it which mode it runs in.

$script:clock = [Diagnostics.Stopwatch]::StartNew()
$global:DotfilesRoot = Split-Path $PSScriptRoot -Parent

#region Mode
$global:ProfileMode = $env:PWSH_PROFILE_MODE
if (-not $ProfileMode) {
    $cli = [Environment]::GetCommandLineArgs() | Select-Object -Skip 1
    $runsSomething = ($cli -match '^-(c|command|f|file|e|ec|encodedcommand|noni|noninteractive)$') -or
                     ($cli.Count -gt 0 -and $cli[0] -notmatch '^-')      # `pwsh script.ps1`
    $staysOpen = $cli -match '^-(noe|noexit)$'
    $global:ProfileMode = if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive -or
                              ($runsSomething -and -not $staysOpen)) { 'lite' } else { 'full' }
    Remove-Variable cli, runsSomething, staysOpen
}
#endregion

#region Files and folders
function touch ($File) {
    if (Test-Path $File) { (Get-Item $File).LastWriteTime = Get-Date }
    else { New-Item $File -ItemType File | Out-Null }
}

function mkcd ($Path) {
    New-Item -Path $Path -ItemType Directory -Force | Out-Null
    Set-Location -Path $Path
}

function trash ($Path) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $full = (Resolve-Path $Path).ProviderPath
    if (Test-Path $full -PathType Container) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($full, 'OnlyErrorDialogs', 'SendToRecycleBin')
    } else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($full, 'OnlyErrorDialogs', 'SendToRecycleBin')
    }
}

function ff ($Name) { Get-ChildItem -Recurse -Filter $Name -File | Select-Object -ExpandProperty FullName }
function head ($Path, [int]$n = 10) { Get-Content $Path -Head $n }
function sed ($File, $Find, $Replace) { (Get-Content $File).Replace("$Find", $Replace) | Set-Content $File }
function docs { Set-Location ([Environment]::GetFolderPath('MyDocuments')) }
function la { Get-ChildItem @args | Format-Table -AutoSize }
function ll { Get-ChildItem -Force @args | Format-Table -AutoSize }

Set-Alias -Name unzip -Value Expand-Archive
Set-Alias -Name grep  -Value Select-String
#endregion

#region Processes and system
function which ($Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd.Source) { $cmd.Source } elseif ($cmd) { $cmd.Definition }
}
function pgrep ($Name) { Get-Process -Name $Name -ErrorAction SilentlyContinue }
function pkill ($Name) { Get-Process -Name $Name -ErrorAction SilentlyContinue | Stop-Process -Force }
function k9 ($Name) { pkill $Name }
function uptime { [TimeSpan]::FromMilliseconds([Environment]::TickCount64) | Select-Object Days, Hours, Minutes, Seconds }
function winutil { Invoke-RestMethod https://christitus.com/win | Invoke-Expression }
function winutildev { Invoke-RestMethod https://christitus.com/windev | Invoke-Expression }
#endregion

#region Git
function gs { git status @args }
function ga { git add . }
function gp { git push @args }
function gpush { git push @args }
function gpull { git pull @args }
function gcl { git clone @args }
function gcom { git add .; git commit -m "$args" }
function lazyg { git add .; git commit -m "$args"; git push }
function g { __zoxide_z github }
#endregion

#region Profile management
function Update-Profile {
    git -C $DotfilesRoot pull --ff-only
    if ($?) { Write-Host 'Profile updated. Open a new shell to load it.' -ForegroundColor Green }
}

function Edit-Profile { & ($env:EDITOR ?? 'code') $PSCommandPath }

function Show-ProfileStatus {
    $t = $global:ProfileTiming
    $ok = $PSStyle.Foreground.BrightGreen; $no = $PSStyle.Foreground.BrightBlack
    $hi = $PSStyle.Foreground.BrightCyan; $r = $PSStyle.Reset
    Write-Host "${hi}mode${r}      $($t.Mode)"
    Write-Host "${hi}startup${r}   $($t.StartupMs) ms"
    if ($t.Mode -eq 'full') {
        Write-Host "${hi}deferred${r}  $(if ($null -ne $t.DeferredMs) { "$($t.DeferredMs) ms after the first prompt" } else { 'not run yet' })"
        foreach ($name in 'oh-my-posh', 'zoxide', 'Terminal-Icons') {
            $state = $t.Loaded[$name]
            $mark = if ($state) { "${ok}●${r} $state" } else { "${no}○ not loaded${r}" }
            Write-Host ("  {0,-15} {1}" -f $name, $mark)
        }
    }
    foreach ($e in $t.Errors) { Write-Host "  $($PSStyle.Foreground.BrightRed)! $e$r" }
}
#endregion

#region Help
function Show-Help {
    $title = $PSStyle.Foreground.BrightMagenta; $section = $PSStyle.Foreground.BrightBlue
    $cmd = $PSStyle.Foreground.BrightGreen; $desc = $PSStyle.Foreground.BrightWhite
    $dim = $PSStyle.Foreground.BrightBlack; $r = $PSStyle.Reset
    $rule = "${dim}$('─' * 52)${r}"
    $row = { param($c, $d) "  ${cmd}{0,-28}${r}${desc}{1}${r}" -f $c, $d }

    Write-Host "`n${title}󰘳  PowerShell Profile${r}"
    Write-Host $rule
    Write-Host "${section}󰊢  Git${r}"
    & $row 'g'              'cd to the github folder (zoxide)'
    & $row 'gs'             'git status'
    & $row 'ga'             'git add .'
    & $row 'gcom <msg>'     'add + commit'
    & $row 'lazyg <msg>'    'add + commit + push'
    & $row 'gp / gpush'     'git push'
    & $row 'gpull'          'git pull'
    & $row 'gcl <repo>'     'git clone'
    Write-Host "`n${section}󰉋  Files${r}"
    & $row 'z <dir> / zi'   'jump to a frequent folder'
    & $row 'la / ll'        'list files (ll shows hidden)'
    & $row 'ff <name>'      'find files by name'
    & $row 'grep <pat> <p>' 'search text'
    & $row 'head <file> [n]' 'first n lines'
    & $row 'sed <f> <a> <b>' 'replace text in a file'
    & $row 'touch <file>'   'create file or bump its time'
    & $row 'mkcd <dir>'     'create + enter folder'
    & $row 'trash <path>'   'move to the Recycle Bin'
    & $row 'unzip <file>'   'extract a zip'
    & $row 'docs'           'Documents folder'
    Write-Host "`n${section}󰘴  System${r}"
    & $row 'which <name>'   'locate a command'
    & $row 'pgrep / pkill <name>' 'find / stop processes'
    & $row 'uptime'         'time since boot'
    & $row 'winutil(dev)'   'Chris Titus WinUtil'
    Write-Host "`n${section}  Profile${r}"
    & $row 'Show-ProfileStatus' 'mode, load times, what loaded'
    & $row 'Update-Profile' 'git pull the dotfiles'
    & $row 'Edit-Profile'   'open this file in $EDITOR'
    Write-Host "$rule`n"
}
#endregion

$global:ProfileTiming = @{ Mode = $ProfileMode; StartupMs = $null; DeferredMs = $null; Loaded = @{}; Errors = @() }

$localProfile = Join-Path $HOME '.pwsh.local.ps1'
if (Test-Path $localProfile) { . $localProfile }
Remove-Variable localProfile

if ($ProfileMode -ne 'full') {
    $ProfileTiming.StartupMs = $clock.ElapsedMilliseconds
    Remove-Variable clock -Scope Script
    return
}

#region Interactive: PSReadLine
Set-PSReadLineOption -PredictionViewStyle ListView -Colors @{
    Command   = '#87CEEB'
    Parameter = '#98FB98'
    Operator  = '#FFB6C1'
    Variable  = '#DDA0DD'
    String    = '#FFDAB9'
    Number    = '#B0E0E6'
    Type      = '#F0E68C'
    Comment   = '#D3D3D3'
    Keyword   = '#8367c7'
    Error     = '#FF6347'
}

Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
Set-PSReadLineKeyHandler -Chord Ctrl+d  -Function DeleteChar
Set-PSReadLineKeyHandler -Chord Ctrl+w  -Function BackwardDeleteWord
Set-PSReadLineKeyHandler -Chord Alt+d   -Function DeleteWord
Set-PSReadLineKeyHandler -Chord Ctrl+LeftArrow  -Function BackwardWord
Set-PSReadLineKeyHandler -Chord Ctrl+RightArrow -Function ForwardWord
Set-PSReadLineKeyHandler -Chord Ctrl+z  -Function Undo
Set-PSReadLineKeyHandler -Chord Ctrl+y  -Function Redo
#endregion

#region Interactive: plain prompt until oh-my-posh takes over
# Folder name only: a prompt that wraps would leave its first line behind when
# oh-my-posh redraws over it.
function prompt {
    $path = $executionContext.SessionState.Path.CurrentLocation.ProviderPath
    $name = if ($path -eq $HOME) { '~' } else { Split-Path $path -Leaf }
    "$($PSStyle.Foreground.FromRgb(0x1478DB))$name$($PSStyle.Reset) $($PSStyle.Foreground.BrightYellow)❯$($PSStyle.Reset) "
}
#endregion

#region Interactive: Terminal-Icons on the first directory listing
# Get-ChildItem (and ls, dir, gci, la, ll) resolves to this function until it
# has run once; it then removes itself so the real cmdlet answers from then on.
function Get-ChildItem {
    Remove-Item Function:\Get-ChildItem -ErrorAction SilentlyContinue
    $iconClock = [Diagnostics.Stopwatch]::StartNew()
    Import-Module Terminal-Icons -Global -ErrorAction SilentlyContinue
    if (Get-Module Terminal-Icons) { $ProfileTiming.Loaded['Terminal-Icons'] = "$($iconClock.ElapsedMilliseconds) ms, on first ls" }
    else { $ProfileTiming.Errors += 'Terminal-Icons is not installed (Install-Module Terminal-Icons -Scope CurrentUser)' }
    if ($MyInvocation.ExpectingInput) { $input | Microsoft.PowerShell.Management\Get-ChildItem @args }
    else { Microsoft.PowerShell.Management\Get-ChildItem @args }
}
#endregion

#region Interactive: oh-my-posh and zoxide after the first prompt
# PSReadLine raises OnIdle itself, so -MessageData never reaches the action;
# hand the settings over in a global that the action removes.
$global:__ProfileDeferred = @{
    Theme = $env:POSH_THEME ?? (Join-Path $PSScriptRoot 'cobalt2.omp.json')
    Cache = Join-Path $env:LOCALAPPDATA 'pwsh-profile'
}
$null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
    $cfg = $global:__ProfileDeferred
    Remove-Variable __ProfileDeferred -Scope Global
    $timing = $global:ProfileTiming
    $clock = [Diagnostics.Stopwatch]::StartNew()
    [IO.Directory]::CreateDirectory($cfg.Cache) | Out-Null

    # Returns a cached init script for a tool, regenerating it when the tool's
    # executable or a watched file is newer than the cache. The cache's first
    # line records the executable, so a fresh cache needs no PATH lookup.
    function Get-InitScript ([string]$Name, [string[]]$Watch, [scriptblock]$Generate) {
        $file = Join-Path $cfg.Cache "$Name.ps1"
        if ([IO.File]::Exists($file)) {
            $built = [IO.File]::GetLastWriteTimeUtc($file)
            $exe = [IO.File]::ReadLines($file) | Select-Object -First 1
            $exe = $exe -replace '^# exe: '
            $stale = -not [IO.File]::Exists($exe) -or [IO.File]::GetLastWriteTimeUtc($exe) -gt $built
            foreach ($w in $Watch) { if ([IO.File]::GetLastWriteTimeUtc($w) -gt $built) { $stale = $true } }
            if (-not $stale) { return $file }
        }
        $exe = (Get-Command $Name -CommandType Application -ErrorAction Ignore | Select-Object -First 1).Source
        if (-not $exe) { return $null }
        $body = & $Generate $exe | Out-String
        [IO.File]::WriteAllText($file, "# exe: $exe`n$body")
        $file
    }

    try {
        $step = [Diagnostics.Stopwatch]::StartNew()
        if (-not (Test-Path $cfg.Theme)) { throw "oh-my-posh theme not found: $($cfg.Theme)" }
        $omp = Get-InitScript 'oh-my-posh' -Watch $cfg.Theme -Generate {
            param($exe)
            # --print gives the whole script instead of a line that calls back
            # into oh-my-posh. The session id must stay unique per shell.
            (& $exe init pwsh --config $cfg.Theme --print | Out-String) -replace
                '\$env:POSH_SESSION_ID = "[^"]*";', '$env:POSH_SESSION_ID = [guid]::NewGuid().ToString();'
        }
        if ($omp) { & $omp; $timing.Loaded['oh-my-posh'] = "$($step.ElapsedMilliseconds) ms" }
        else { $timing.Errors += 'oh-my-posh is not installed (winget install JanDeDobbeleer.OhMyPosh)' }
    } catch { $timing.Errors += "oh-my-posh: $_" }

    # After oh-my-posh: zoxide wraps whatever prompt function exists.
    try {
        $step = [Diagnostics.Stopwatch]::StartNew()
        $zoxide = Get-InitScript 'zoxide' -Generate { param($exe) & $exe init --cmd z powershell }
        if ($zoxide) { & $zoxide; $timing.Loaded['zoxide'] = "$($step.ElapsedMilliseconds) ms" }
        else { $timing.Errors += 'zoxide is not installed (winget install ajeetdsouza.zoxide)' }
    } catch { $timing.Errors += "zoxide: $_" }

    $timing.DeferredMs = $clock.ElapsedMilliseconds
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}
#endregion

Write-Host "$($PSStyle.Foreground.BrightBlack)Show-Help for commands · Show-ProfileStatus for load times$($PSStyle.Reset)"
$ProfileTiming.StartupMs = $clock.ElapsedMilliseconds
Remove-Variable clock -Scope Script
