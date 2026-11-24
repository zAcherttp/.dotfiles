#Requires -Version 7.2
# PowerShell profile. Looks like the macOS setup (oh-my-zsh cobalt2 prompt,
# VS Code Dark colours, Iris-green completion list) and starts without
# spawning a single process.
#
#   startup      functions, PSReadLine, prompt, ls colours        (pure PowerShell)
#   each prompt  cobalt2 prompt drawn in-process; git dirty check runs in the
#                background and the prompt repaints only if the colour changes
#   first idle   zoxide, from a cached init script
#
# Mode is detected per shell; override with $env:PWSH_PROFILE_MODE = 'full' | 'lite'.
#   full  an interactive terminal
#   lite  `pwsh -c`, scripts, agents, redirected input: functions only
#
# Machine-specific settings (tokens, PATH, aliases) go in ~/.pwsh.local.ps1,
# which this repo never tracks. $ProfileMode tells it which mode it runs in;
# `$ProfileIcons = $true` there turns Terminal-Icons back on.

# Startup speed rule: no cmdlets from Microsoft.PowerShell.Utility or
# .Management before the first prompt (Select-Object, Set-Alias, Join-Path,
# Test-Path, Register-EngineEvent, Remove-Variable, Out-Null, ...). A bare pwsh
# never loads those modules, and the first such call costs 20-60 ms to load
# one. .NET and $ExecutionContext do the same work for free.

$script:clock = [Diagnostics.Stopwatch]::StartNew()
$global:DotfilesRoot = [IO.Path]::GetDirectoryName($PSScriptRoot)
$script:vars = $ExecutionContext.SessionState.PSVariable

#region Mode
$global:ProfileMode = $env:PWSH_PROFILE_MODE
if (-not $ProfileMode) {
    $cli = [Environment]::GetCommandLineArgs()
    $cli = if ($cli.Length -gt 1) { $cli[1..($cli.Length - 1)] } else { @() }
    $runsSomething = ($cli -match '^-(c|command|f|file|e|ec|encodedcommand|noni|noninteractive)$') -or
                     ($cli.Count -gt 0 -and $cli[0] -notmatch '^-')      # `pwsh script.ps1`
    $staysOpen = $cli -match '^-(noe|noexit)$'
    $global:ProfileMode = if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive -or
                              ($runsSomething -and -not $staysOpen)) { 'lite' } else { 'full' }
    'cli', 'runsSomething', 'staysOpen' | ForEach-Object { $vars.Remove($_) }
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

# Functions rather than Set-Alias, which would load the Utility module at startup.
function unzip { Expand-Archive @args }
function grep { if ($MyInvocation.ExpectingInput) { $input | Select-String @args } else { Select-String @args } }
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
    $started = [DateTime]::Now - [Diagnostics.Process]::GetCurrentProcess().StartTime
    Write-Host "${hi}mode${r}      $($t.Mode)"
    Write-Host "${hi}profile${r}   $($t.StartupMs) ms   ${no}(pwsh itself took the rest of the first prompt)${r}"
    $last = 0
    foreach ($phase in $t.Phases.GetEnumerator()) {
        Write-Host ("  ${no}{0,-12} {1,6:N1} ms${r}" -f $phase.Key, ($phase.Value - $last)); $last = $phase.Value
    }
    if ($t.Mode -eq 'full') {
        Write-Host "${hi}deferred${r}  $(if ($null -ne $t.DeferredMs) { "$($t.DeferredMs) ms after the first prompt" } else { 'not run yet' })"
        Write-Host "${hi}prompt${r}    $($global:__prompt.LastMs) ms to draw the last one"
        foreach ($name in 'zoxide', 'Terminal-Icons') {
            $state = $t.Loaded[$name]
            $mark = if ($state) { "${ok}●${r} $state" } elseif ($name -eq 'Terminal-Icons' -and -not $global:ProfileIcons) { "${no}○ off (`$ProfileIcons = `$true in ~/.pwsh.local.ps1)${r}" } else { "${no}○ not loaded${r}" }
            Write-Host ("  {0,-15} {1}" -f $name, $mark)
        }
    }
    foreach ($e in $t.Errors) { Write-Host "  $($PSStyle.Foreground.BrightRed)! $e$r" }
    Write-Host "${no}shell open for $([int]$started.TotalSeconds) s${r}"
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

$global:ProfileTiming = @{ Mode = $ProfileMode; StartupMs = $null; DeferredMs = $null; Loaded = @{}; Errors = @()
                           Phases = [ordered]@{ functions = $clock.Elapsed.TotalMilliseconds } }

$localProfile = [IO.Path]::Combine($HOME, '.pwsh.local.ps1')
if ([IO.File]::Exists($localProfile)) { . $localProfile }
$vars.Remove('localProfile')

$ProfileTiming.Phases['local'] = $clock.Elapsed.TotalMilliseconds
if ($ProfileMode -ne 'full') {
    $ProfileTiming.StartupMs = $clock.ElapsedMilliseconds
    'clock', 'vars' | ForEach-Object { $vars.Remove($_) }
    return
}

$e = [char]27

#region Interactive: PSReadLine (input colours, Iris-green completion list)
Set-PSReadLineOption -PredictionViewStyle ListView -Colors @{
    Command                = '#87CEEB'
    Parameter              = '#98FB98'
    Operator               = '#FFB6C1'
    Variable               = '#DDA0DD'
    String                 = '#FFDAB9'
    Number                 = '#B0E0E6'
    Type                   = '#F0E68C'
    Comment                = '#D3D3D3'
    Keyword                = '#8367c7'
    Error                  = '#FF6347'
    Selection              = "$e[48;2;38;79;120m"       # iTerm VSCodeDark selection
    InlinePrediction       = '#436352'                  # Iris ghost_text
    ListPrediction         = '#56b97f'                  # Iris accent
    ListPredictionSelected = "$e[48;2;22;53;38m"        # Iris sel_bg
    ListPredictionTooltip  = '#7ba38f'                  # Iris desc
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
$ProfileTiming.Phases['psreadline'] = $clock.Elapsed.TotalMilliseconds
#endregion

#region Interactive: ls colours (oh-my-zsh's LSCOLORS on macOS)
$PSStyle.FileInfo.Directory    = "$e[1;36m"
$PSStyle.FileInfo.SymbolicLink = "$e[35m"
$PSStyle.FileInfo.Executable   = "$e[31m"
$PSStyle.FileInfo.Extension.Clear()
$ProfileTiming.Phases['lscolors'] = $clock.Elapsed.TotalMilliseconds
#endregion

#region Interactive: cobalt2 prompt
# A port of the cobalt2 oh-my-zsh theme (github.com/wesbos/Cobalt2-iterm):
#   [✘ ⚡ ⚙] [✝] [blue: last 3 folders] [green/yellow:  branch±]
# Named ANSI colours, so the terminal's scheme (VS Code Dark) decides the
# exact shades, as it does on the Mac.
#
# Branch comes from reading .git/HEAD. Whether the tree is dirty needs
# `git status`, which takes 30-50 ms, so it runs in the background: the prompt
# waits up to WaitMs for it, otherwise draws the last known colour and the
# idle handler repaints when the answer differs.
#
# Where git lives is cached: a PATH lookup costs more than the rest of the prompt.
$cacheDir = [IO.Path]::Combine($env:LOCALAPPDATA, 'pwsh-profile')
$gitCache = [IO.Path]::Combine($cacheDir, 'git.txt')
$git = if ([IO.File]::Exists($gitCache)) { [IO.File]::ReadAllText($gitCache) }
if (-not $git -or -not [IO.File]::Exists($git)) {
    $git = @(Get-Command git -CommandType Application -ErrorAction Ignore)[0].Source
    if ($git -like '*\cmd\git.exe') {
        # cmd\git.exe only launches mingw64\bin\git.exe; calling that directly saves a process.
        $direct = [IO.Path]::GetFullPath([IO.Path]::Combine($git, '..\..\mingw64\bin\git.exe'))
        if ([IO.File]::Exists($direct)) { $git = $direct }
    }
    if ($git) {
        $null = [IO.Directory]::CreateDirectory($cacheDir)
        [IO.File]::WriteAllText($gitCache, $git)
    }
}
$global:__prompt = @{
    Git     = $git
    WaitMs  = 40            # only on the first prompt in a repo, when no colour is known yet
    Dirty   = @{}           # repo root -> $true / $false
    Pending = $null         # the running git status
    Shown   = $null         # "root|dirty" the visible prompt was drawn with
    LastPwd = $null
    Zoxide  = $null         # zoxide.exe once the idle handler has loaded it
    LastMs  = $null
    LastOk  = $true
    LastHistoryId = $null
    Admin   = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                  [Security.Principal.WindowsBuiltInRole]::Administrator)
}
'git', 'direct', 'gitCache' | ForEach-Object { $vars.Remove($_) }

function global:__Prompt-FindRepo ([string]$dir) {
    while ($dir) {
        $dot = [IO.Path]::Combine($dir, '.git')
        if ([IO.Directory]::Exists($dot)) { return $dir, $dot }
        if ([IO.File]::Exists($dot)) {                          # worktree or submodule
            $line = [IO.File]::ReadAllText($dot).Trim()
            if ($line.StartsWith('gitdir: ')) {
                return $dir, [IO.Path]::GetFullPath($line.Substring(8), $dir)
            }
        }
        $dir = [IO.Path]::GetDirectoryName($dir)
    }
}

function global:__Prompt-StartDirtyCheck ([string]$root) {
    $s = $global:__prompt
    if ($s.Pending) { $s.Pending.Rerun = $root; return }
    $psi = [Diagnostics.ProcessStartInfo]::new($s.Git, '--no-optional-locks status --porcelain --ignore-submodules=dirty')
    $psi.WorkingDirectory = $root
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $s.Pending = @{ Root = $root; Proc = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync(); Rerun = $null }
}

# Collects a finished dirty check. Returns $true when the visible prompt is now wrong.
function global:__Prompt-CollectDirtyCheck {
    $s = $global:__prompt
    $p = $s.Pending
    if (-not $p -or -not $p.Out.IsCompleted) { return $false }
    $s.Pending = $null
    $s.Dirty[$p.Root] = $p.Out.Result.Length -gt 0
    $p.Proc.Dispose()
    if ($p.Rerun) { __Prompt-StartDirtyCheck $p.Rerun }
    $s.Shown -and $s.Shown -ne "$($p.Root)|$($s.Dirty[$p.Root])" -and $s.Shown.StartsWith("$($p.Root)|")
}

function prompt {
    $ok = $?
    $s = $global:__prompt
    $clock = [Diagnostics.Stopwatch]::StartNew()
    # A repaint (or an empty Enter) runs no command: keep the last status, as zsh does.
    $historyId = (Get-History -Count 1).Id
    if ($historyId -eq $s.LastHistoryId) { $ok = $s.LastOk } else { $s.LastHistoryId = $historyId; $s.LastOk = $ok }
    try {
        $e = [char]27
        $loc = $executionContext.SessionState.Path.CurrentLocation
        $path = $loc.ProviderPath
        $isFs = $loc.Provider.Name -eq 'FileSystem'

        # zoxide's own prompt hook would hide $?, so this one feeds it instead.
        if ($isFs -and $s.Zoxide -and $path -ne $s.LastPwd) {
            $psi = [Diagnostics.ProcessStartInfo]::new($s.Zoxide)
            $psi.ArgumentList.Add('add'); $psi.ArgumentList.Add('--'); $psi.ArgumentList.Add($path)
            $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            [Diagnostics.Process]::Start($psi).Dispose()
        }
        $s.LastPwd = $path

        # Segments: background, foreground, text. 0-7 are the ANSI colours; 9 = default.
        $segments = [Collections.Generic.List[object]]::new()

        $status = ''
        if (-not $ok) { $status += "$e[31m✘" }
        if ($s.Admin) { $status += "$e[33m⚡" }
        if (Get-Job | Where-Object { $_ -isnot [Management.Automation.PSEventJob] -and $_.State -eq 'Running' }) { $status += "$e[36m⚙" }
        if ($status) { $segments.Add(@(0, 9, $status)) }

        if ($env:USERNAME -ne $env:DEFAULT_USER -or $env:SSH_CLIENT) {
            $segments.Add(@(0, $(if ($s.Admin) { 3 } else { 9 }), '✝'))
        }

        # zsh %3~: home as ~, then the last three parts.
        $short = $path
        if ($isFs -and $path.StartsWith($HOME, [StringComparison]::OrdinalIgnoreCase)) { $short = '~' + $path.Substring($HOME.Length) }
        $parts = $short -split '[\\/]' | Where-Object { $_ }
        $short = if ($parts.Count -gt 3) { $parts[-3..-1] -join '/' } elseif ($short -match '^[A-Za-z]:\\?$') { $short.TrimEnd('\') + '/' } else { $parts -join '/' }
        $segments.Add(@(4, 0, $short))

        $s.Shown = $null
        if ($isFs -and $s.Git) {
            $repo = __Prompt-FindRepo $path
            if ($repo) {
                $root, $gitDir = $repo
                $head = try { [IO.File]::ReadAllText([IO.Path]::Combine($gitDir, 'HEAD')).Trim() } catch { '' }
                $ref = if ($head.StartsWith('ref: refs/heads/')) { "$([char]0xE0A0) " + $head.Substring(16) }
                       elseif ($head.Length -ge 7) { '➦ ' + $head.Substring(0, 7) } else { '➦ ?' }

                $null = __Prompt-CollectDirtyCheck
                __Prompt-StartDirtyCheck $root
                if (-not $s.Dirty.ContainsKey($root) -and $s.Pending -and $s.Pending.Root -eq $root -and
                    $s.Pending.Out.Wait($s.WaitMs)) { $null = __Prompt-CollectDirtyCheck }

                $dirty = [bool]$s.Dirty[$root]
                $s.Shown = "$root|$dirty"
                $segments.Add(@($(if ($dirty) { 3 } else { 2 }), 0, $(if ($dirty) { "$ref±" } else { $ref })))
            }
        }

        $sb = [Text.StringBuilder]::new()
        $null = $sb.Append("$e]0;$short$([char]7)")             # tab title, as oh-my-zsh sets it
        $prev = $null
        foreach ($seg in $segments) {
            $bg, $fg, $text = $seg
            if ($null -eq $prev) { $null = $sb.Append("$e[4${bg}m$e[3${fg}m ") }
            else { $null = $sb.Append(" $e[4${bg}m$e[3${prev}m$([char]0xE0B0)$e[3${fg}m ") }
            $null = $sb.Append($text)
            $prev = $bg
        }
        $null = $sb.Append(" $e[49m$e[3${prev}m$([char]0xE0B0)$e[0m ")
        $sb.ToString()
    } catch {
        "PS $path> "
    } finally {
        $s.LastMs = [Math]::Round($clock.Elapsed.TotalMilliseconds, 1)
    }
}
$ProfileTiming.Phases['prompt'] = $clock.Elapsed.TotalMilliseconds
#endregion

#region Interactive: Terminal-Icons, opt-in, on the first directory listing
if ($global:ProfileIcons) {
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
}
$ProfileTiming.Phases['icons'] = $clock.Elapsed.TotalMilliseconds
#endregion

#region Interactive: idle handler (zoxide once, then git repaints)
# PSReadLine raises OnIdle itself every few hundred ms while waiting for keys.
# Subscribed through $ExecutionContext.Events, which is what
# Register-EngineEvent calls, minus loading the Utility module to get there.
$global:__ProfileDeferred = @{ Cache = $cacheDir }
$null = $ExecutionContext.Events.SubscribeEvent($null, $null, 'PowerShell.OnIdle', $null, {
    if (__Prompt-CollectDirtyCheck) { [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt() }

    $cfg = $global:__ProfileDeferred
    if (-not $cfg) { return }
    $global:__ProfileDeferred = $null
    $timing = $global:ProfileTiming
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        # Cached `zoxide init`, rebuilt when zoxide.exe is newer than the cache.
        # The first line records the executable, so a fresh cache needs no PATH lookup.
        $null = [IO.Directory]::CreateDirectory($cfg.Cache)
        $file = [IO.Path]::Combine($cfg.Cache, 'zoxide.ps1')
        $exe = if ([IO.File]::Exists($file)) { foreach ($line in [IO.File]::ReadLines($file)) { $line -replace '^# exe: '; break } }
        if (-not $exe -or -not [IO.File]::Exists($exe) -or [IO.File]::GetLastWriteTimeUtc($exe) -gt [IO.File]::GetLastWriteTimeUtc($file)) {
            $exe = @(Get-Command zoxide -CommandType Application -ErrorAction Ignore)[0].Source
            if ($exe) { [IO.File]::WriteAllText($file, "# exe: $exe`n" + ((& $exe init --cmd z --hook none powershell) -join "`n")) }
        }
        if ($exe) {
            . $file
            $global:__prompt.Zoxide = $exe
            $timing.Loaded['zoxide'] = "$($clock.ElapsedMilliseconds) ms"
        } else { $timing.Errors += 'zoxide is not installed (winget install ajeetdsouza.zoxide)' }
    } catch { $timing.Errors += "zoxide: $_" }
    $timing.DeferredMs = $clock.ElapsedMilliseconds
}, $false, $false)
$ProfileTiming.Phases['idle'] = $clock.Elapsed.TotalMilliseconds
#endregion

$ProfileTiming.StartupMs = $clock.ElapsedMilliseconds
'clock', 'e', 'cacheDir', 'vars' | ForEach-Object { $vars.Remove($_) }
