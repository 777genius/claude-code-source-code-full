<#
.SYNOPSIS
    Read-only diagnostic for Claude Session Keeper. Prints no token values and changes nothing.

.PARAMETER AuthStatus
    Also run `claude auth status --json` and show only loggedIn / authMethod / subscriptionType.

.NOTES
    Exit code: 0 = no problems, 2 = at least one warning/failure that needs attention.
#>
[CmdletBinding()]
param(
    [string]$ClaudePath,
    [string]$ConfigDir,
    [switch]$AuthStatus
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ClaudeSessionKeeper.Common.ps1')

$script:problems = 0
function Show-Line {
    param([ValidateSet('OK', 'WARN', 'FAIL', 'INFO')][string]$Kind, [string]$Text)
    $color = switch ($Kind) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'FAIL' { 'Red' } default { 'Gray' } }
    if ($Kind -eq 'WARN' -or $Kind -eq 'FAIL') { $script:problems++ }
    Write-Host ('[{0,-4}] {1}' -f $Kind, (Protect-KeeperText $Text)) -ForegroundColor $color
}

Write-Host "Claude Session Keeper $script:KeeperVersion - diagnostic (read-only; no tokens are printed)" -ForegroundColor Cyan
Write-Host ("PowerShell {0} on {1}" -f $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString)

# --- CLI ----------------------------------------------------------------------------------------
$exe = Resolve-ClaudeExecutable -Override $ClaudePath
if (-not $exe) {
    Show-Line FAIL 'claude executable not found (checked PATH, %USERPROFILE%\.local\bin, %APPDATA%\npm).'
} else {
    Show-Line OK "CLI: $exe"
    try {
        $r = Invoke-ClaudeCommand -ExePath $exe -Arguments @('--version') -TimeoutSeconds 30 -RemoveEnv @()
        $ver = ($r.Output -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
        if ($ver) { Show-Line INFO "Version: $($ver.Trim())" } else { Show-Line WARN 'Could not read `claude --version`.' }
    } catch { Show-Line WARN "claude --version failed: $($_.Exception.Message)" }
}
if (Get-Command npm -ErrorAction SilentlyContinue) {
    try {
        $npmRoot = (& npm root -g 2>$null | Select-Object -Last 1)
        $pj = if ($npmRoot) { Join-Path $npmRoot.Trim() '@anthropic-ai\claude-code\package.json' }
        if ($pj -and (Test-Path -LiteralPath $pj)) {
            Show-Line INFO ("npm package @anthropic-ai/claude-code {0} at {1}" -f (Get-Content -LiteralPath $pj -Raw | ConvertFrom-Json).version, (Split-Path -Parent $pj))
        }
    } catch { }
}

# --- Environment overrides ----------------------------------------------------------------------
$overrides = @($script:AuthOverrideEnvVars | Where-Object { [Environment]::GetEnvironmentVariable($_) })
if ($overrides.Count) {
    Show-Line WARN ("These variables are set and override the saved login in your shells: {0}. The keeper removes them for its own check, but Claude Code in your shells ignores the saved login while they are set (and the expiry banner does not apply)." -f ($overrides -join ', '))
} else { Show-Line OK 'No credential-override environment variables are set.' }

# --- Credential metadata ------------------------------------------------------------------------
$credPath = Join-Path (Get-ClaudeConfigDir $ConfigDir) '.credentials.json'
Show-Line INFO "Credential file: $credPath"
$cred = Read-ClaudeCredential -Path $credPath
switch ($cred.Status) {
    'Missing' { Show-Line FAIL 'No credential file. Sign in with /login (or pass -ConfigDir if you use CLAUDE_CONFIG_DIR).' }
    'Unreadable' { Show-Line FAIL "Credential file unreadable: $($cred.Error)" }
    'NoOAuth' { Show-Line WARN 'No claudeAiOauth entry (API key or other login method); the keeper has nothing to maintain.' }
    default {
        Show-Line INFO ("Last written: {0}" -f $cred.LastWriteUtc.ToLocalTime().ToString('g'))
        if ($cred.HasRefreshToken) { Show-Line OK 'Refresh token present.' } else { Show-Line FAIL 'No refresh token: only /login can fix this.' }
        Show-Line INFO ("Scopes: {0}; subscription: {1}; clientId recorded: {2}" -f ($cred.Scopes -join ' '), $cred.SubscriptionType, $cred.HasClientId)
        if ($cred.Scopes -notcontains 'user:inference') { Show-Line WARN 'Scopes lack user:inference - not a claude.ai subscription login.' }
        $st = Get-LoginStatus -Credential $cred
        if ($cred.AccessExpiresUtc) {
            Show-Line INFO ("Access token (expiresAt): {0} -> {1}. Short-lived; Claude Code renews it automatically." -f $cred.AccessExpiresUtc.ToLocalTime().ToString('g'), (Format-Span $st.AccessRemaining))
        } else { Show-Line WARN 'expiresAt is not recorded.' }
        if ($st.RefreshKnown) {
            $line = "Login (refreshTokenExpiresAt): {0} -> {1}. This is the value behind 'Your login expires in N days'." -f $cred.RefreshExpiresUtc.ToLocalTime().ToString('g'), (Format-Span $st.RefreshRemaining)
            if ($st.LoginExpired) { Show-Line FAIL $line }
            elseif ($st.BannerDaysLeft) { Show-Line WARN $line; Show-Line INFO "Claude Code would currently show: Your login expires in $($st.BannerDaysLeft) day(s)." }
            else { Show-Line OK $line }
        } else {
            Show-Line WARN 'refreshTokenExpiresAt is not recorded (older credential, or the server did not report one). The keeper will refresh whenever the access token expires, but cannot predict login expiry. Run /login once on a current Claude Code to record it.'
        }
    }
}
if ((Test-IsWindows) -and (Test-Path -LiteralPath $credPath)) {
    try {
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $bad = @()
        foreach ($ace in (Get-Acl -LiteralPath $credPath).Access) {
            if ($ace.AccessControlType -ne 'Allow') { continue }
            $sid = try { $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]) } catch { $null }
            if ($sid -and ($sid -eq $me -or $sid.Value -eq 'S-1-5-18' -or $sid.Value -eq 'S-1-5-32-544')) { continue }
            $bad += [string]$ace.IdentityReference
        }
        if ($bad.Count) { Show-Line WARN ("Credential file is readable by: {0}. It should be limited to your account, SYSTEM and Administrators." -f ($bad -join ', ')) }
        else { Show-Line OK 'Credential file ACL is limited to you, SYSTEM and Administrators.' }
    } catch { Show-Line INFO "ACL check skipped: $($_.Exception.Message)" }
}

# --- Optional live status -----------------------------------------------------------------------
if ($AuthStatus -and $exe) {
    $r = Invoke-ClaudeCommand -ExePath $exe -Arguments @('auth', 'status', '--json') -TimeoutSeconds 60 -RemoveEnv @()
    try {
        $j = ($r.Output.Trim() | ConvertFrom-Json)
        Show-Line INFO ("auth status: loggedIn={0}; authMethod={1}; subscription={2}" -f $j.loggedIn, $j.authMethod, $j.subscriptionType)
    } catch { Show-Line WARN 'Could not parse `claude auth status --json`.' }
}

# --- Scheduled task + log -----------------------------------------------------------------------
if ((Test-IsWindows) -and (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
    $task = Get-ScheduledTask -TaskName 'ClaudeSessionKeeper' -ErrorAction SilentlyContinue
    if ($task) {
        $info = Get-ScheduledTaskInfo -TaskName 'ClaudeSessionKeeper'
        Show-Line INFO ("Scheduled task: state={0}; last run={1}; last result=0x{2:X}; next run={3}" -f $task.State, $info.LastRunTime, $info.LastTaskResult, $info.NextRunTime)
        if ($task.State -eq 'Disabled') { Show-Line WARN 'Scheduled task is disabled.' }
        if ($info.LastTaskResult -notin 0, 267011) { Show-Line WARN 'Last task result was non-zero (keeper exit codes: 1 error, 2 needs /login, 3 login expired/rejected, 4 refresh not confirmed). See renewal.log.' }
    } else { Show-Line INFO 'Scheduled task is not installed (run Install-ClaudeSessionKeeper.ps1).' }
}
$stateDir = Get-KeeperStateDir
$state = Read-KeeperState
Show-Line INFO ("Last keeper result: {0}; last success: {1}; consecutive failures: {2}; refresh-didn't-extend count: {3}" -f $state.lastResult, $state.lastSuccessUtc, $state.consecutiveFailures, $state.noExtendCount)
$logPath = Join-Path $stateDir 'renewal.log'
if (Test-Path -LiteralPath $logPath) {
    Write-Host "Last log lines ($logPath):" -ForegroundColor DarkGray
    Get-Content -LiteralPath $logPath -Tail 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
}

Write-Host ''
Write-Host 'No files or credentials were changed.' -ForegroundColor Green
if ($script:problems -gt 0) { exit 2 } else { exit 0 }
