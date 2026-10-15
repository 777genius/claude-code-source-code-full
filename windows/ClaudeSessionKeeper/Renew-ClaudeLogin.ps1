<#
.SYNOPSIS
    Keeps a Claude Code subscription login from lapsing by letting Claude Code refresh it itself.

.DESCRIPTION
    This script never reads tokens into a request, never calls the OAuth endpoint, and never writes
    .credentials.json. It only:
      1. reads the credential METADATA (expiry timestamps + token fingerprints),
      2. decides whether a refresh is due,
      3. runs one tiny `claude -p` request so Claude Code's own refresh path runs (it takes the
         refresh lock, calls the token endpoint, and saves the rotated token with a compare-and-swap),
      4. re-reads the metadata to confirm the new tokens were persisted and whether the login
         lifetime (refreshTokenExpiresAt) actually moved.

    Exit codes: 0 ok / nothing to do, 1 unexpected error, 2 needs interactive /login (no usable
    credential), 3 login expired or refresh rejected, 4 refresh not confirmed.

.PARAMETER ThresholdHours
    Act when the login (refresh token) expires within this many hours. Default 72 = the CLI's banner window.

.PARAMETER AccessGraceMinutes
    The CLI only refreshes an access token that is expired or within ~5 minutes of expiry, so the
    check request is only useful then. Default 2.

.PARAMETER DryRun
    (alias -WhatIf) Evaluate everything and log what would happen, but do not run Claude Code.

.PARAMETER Force
    Ignore the threshold and the retry cooldown and run the check request now. Claude Code still only
    refreshes when its own expiry test says so; -Force cannot make it refresh a still-valid token.
#>
[CmdletBinding()]
param(
    [int]$ThresholdHours = 72,
    [int]$AccessGraceMinutes = 2,
    [int]$MinRetryMinutes = 30,
    [int]$TimeoutSeconds = 120,
    [string]$Model = 'haiku',
    [double]$MaxBudgetUsd = 0.05,
    [string]$ClaudePath,
    [string]$ConfigDir,
    [switch]$Force,
    [Alias('WhatIf')][switch]$DryRun   # custom switch: the built-in -WhatIf would also block the keeper's own log/state writes
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ClaudeSessionKeeper.Common.ps1')

function Send-KeeperAlert {
    # At most one desktop notification per kind every 12 hours.
    param($State, [string]$Kind, [string]$Message)
    $last = $null
    if ($State.notified.ContainsKey($Kind)) { $last = ConvertTo-UtcDateTime $State.notified[$Kind] }
    if ($last -and (([DateTime]::UtcNow - $last).TotalHours -lt 12)) { return }
    $State.notified[$Kind] = [DateTime]::UtcNow.ToString('o')
    Show-KeeperToast -Title 'Claude Session Keeper' -Message $Message
}

function Invoke-Keeper {
    $credPath = Join-Path (Get-ClaudeConfigDir $ConfigDir) '.credentials.json'
    $lock = Enter-KeeperMutex -Key $credPath
    if (-not $lock.Acquired) {
        Write-KeeperLog 'Another Claude Session Keeper run is already active for this credential file; skipping.' 'INFO'
        return 0
    }
    try {
        $state = Read-KeeperState
        $now = [DateTime]::UtcNow
        Write-KeeperLog ("Keeper {0} on PowerShell {1}; credential file: {2}" -f $script:KeeperVersion, $PSVersionTable.PSVersion, $credPath) 'DEBUG'

        # --- 1. Inspect (read-only) -------------------------------------------------------------
        $cred = Read-ClaudeCredential -Path $credPath
        switch ($cred.Status) {
            'Missing' {
                Write-KeeperLog "No credential file at $credPath. Sign in with /login first (or pass -ConfigDir if CLAUDE_CONFIG_DIR is used)." 'ERROR'
                $state.lastResult = 'NoCredentials'; Save-KeeperState $state; return 2
            }
            'Unreadable' {
                Write-KeeperLog "Credential file could not be read/parsed: $($cred.Error)" 'ERROR'
                $state.lastResult = 'Unreadable'; Save-KeeperState $state; return 1
            }
            'NoOAuth' {
                Write-KeeperLog 'Credential file has no claudeAiOauth entry (API-key / other login?). Nothing for this tool to keep alive.' 'WARN'
                $state.lastResult = 'NoOAuth'; Save-KeeperState $state; return 2
            }
        }
        if (-not $cred.HasRefreshToken) {
            Write-KeeperLog 'The saved login has no refresh token. Run /login; this tool cannot create one.' 'ERROR'
            $state.lastResult = 'NoRefreshToken'; Send-KeeperAlert $state 'login' 'Claude login has no refresh token. Run /login.'; Save-KeeperState $state; return 2
        }
        if ($cred.Scopes -notcontains 'user:inference') {
            Write-KeeperLog ('Saved scopes ({0}) do not include user:inference; this is not a claude.ai subscription login, so Claude Code will not refresh it.' -f ($cred.Scopes -join ' ')) 'WARN'
            $state.lastResult = 'NotSubscriptionLogin'; Save-KeeperState $state; return 2
        }

        $st = Get-LoginStatus -Credential $cred -NowUtc $now
        $summary = 'Access token: {0}; login (refresh token): {1}' -f (Format-Span $st.AccessRemaining), $(if ($st.RefreshKnown) { Format-Span $st.RefreshRemaining } else { 'expiry not recorded' })
        if ($st.BannerDaysLeft) { $summary += "; CLI banner would read 'Your login expires in $($st.BannerDaysLeft) day(s)'" }
        Write-KeeperLog $summary 'INFO'

        if ($st.LoginExpired) {
            Write-KeeperLog 'The recorded login expiry has passed. A refresh may still be attempted below, but if the server rejects it you must run /login.' 'WARN'
        }

        # --- 2. Decide --------------------------------------------------------------------------
        $inWindow = (-not $st.RefreshKnown) -or ($st.RefreshRemaining.TotalHours -le $ThresholdHours)
        $accessDue = ($null -ne $st.AccessRemaining) -and ($st.AccessRemaining.TotalMinutes -le $AccessGraceMinutes)
        if ($null -eq $st.AccessRemaining) { Write-KeeperLog 'expiresAt is not recorded; cannot tell when the access token is due.' 'WARN' }

        if (-not $Force) {
            if (-not $inWindow) {
                Write-KeeperLog ("No action: login has {0} left (threshold {1} h)." -f (Format-Span $st.RefreshRemaining), $ThresholdHours) 'INFO'
                $state.lastResult = 'NotNeeded'; Save-KeeperState $state; return 0
            }
            if (-not $accessDue) {
                Write-KeeperLog ("Login is inside the {0} h window, but the access token is still valid for {1}; Claude Code refreshes it when it expires, and the next run will trigger that." -f $ThresholdHours, (Format-Span $st.AccessRemaining)) 'INFO'
                $state.lastResult = 'WaitingForAccessExpiry'; Save-KeeperState $state; return 0
            }
            $lastAttempt = ConvertTo-UtcDateTime $state.lastAttemptUtc
            if ($lastAttempt -and (($now - $lastAttempt).TotalMinutes -lt $MinRetryMinutes)) {
                Write-KeeperLog ("Skipping: last attempt was {0:N0} minutes ago (cooldown {1} min)." -f ($now - $lastAttempt).TotalMinutes, $MinRetryMinutes) 'INFO'
                return 0
            }
        }

        $exe = Resolve-ClaudeExecutable -Override $ClaudePath
        if (-not $exe) { throw 'Could not find claude.exe/claude.cmd. Install Claude Code or pass -ClaudePath.' }

        # --- 3. Trigger Claude Code's own refresh -----------------------------------------------
        $workDir = Join-Path (Get-KeeperStateDir) 'work'
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
        # The prompt is positional and must come before the variadic --tools option.
        $args_ = @('-p', 'Reply with the single word: ok')
        if ($Model) { $args_ += @('--model', $Model) }
        $args_ += @('--no-session-persistence', '--output-format', 'json', '--setting-sources', 'local',
            '--disable-slash-commands', '--max-budget-usd', ([string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $MaxBudgetUsd)), '--tools', '')
        $setEnv = @{}
        if ($ConfigDir) { $setEnv['CLAUDE_CONFIG_DIR'] = $ConfigDir }

        if ($DryRun) {
            Write-KeeperLog ("Dry run: a refresh is due; would run: {0} {1}" -f $exe, (ConvertTo-ArgumentString $args_)) 'INFO'
            return 0
        }

        Write-KeeperLog "Triggering Claude Code's own token refresh via a minimal request ($exe)." 'INFO'
        $state.lastAttemptUtc = $now.ToString('o')
        Save-KeeperState $state
        $run = Invoke-ClaudeCommand -ExePath $exe -Arguments $args_ -WorkingDirectory $workDir `
            -TimeoutSeconds $TimeoutSeconds -RemoveEnv $script:AuthOverrideEnvVars -SetEnv $setEnv
        if ($run.StartError) { throw "Could not start Claude Code: $($run.StartError)" }
        $tail = (Protect-KeeperText $run.Output).Trim()
        if ($tail.Length -gt 300) { $tail = $tail.Substring(0, 300) + '...' }
        Write-KeeperLog ("claude exited with code {0}{1} after {2}s." -f $run.ExitCode, $(if ($run.TimedOut) { ' (TIMED OUT, process killed)' } else { '' }), $run.Seconds) 'DEBUG'

        # --- 4. Verify persistence --------------------------------------------------------------
        $after = Read-ClaudeCredential -Path $credPath
        if ($after.Status -ne 'Ok' -or -not $after.HasRefreshToken) {
            Write-KeeperLog "CRITICAL: credential file state after the refresh attempt is '$($after.Status)'. Run /login if Claude Code reports it is logged out." 'ERROR'
            $state.lastResult = 'CredentialsLostOrUnreadable'; $state.consecutiveFailures = [int]$state.consecutiveFailures + 1
            Send-KeeperAlert $state 'login' 'Claude credentials look damaged. Run /login.'; Save-KeeperState $state; return 3
        }
        $accessChanged = ($after.AccessFingerprint -ne $cred.AccessFingerprint)
        $rotated = ($after.RefreshFingerprint -ne $cred.RefreshFingerprint)
        $afterSt = Get-LoginStatus -Credential $after
        $extended = $false
        if ($cred.RefreshExpiresUtc -and $after.RefreshExpiresUtc) {
            $extended = ($after.RefreshExpiresUtc -gt $cred.RefreshExpiresUtc.AddMinutes(1))
        }

        if ($accessChanged) {
            $state.lastSuccessUtc = [DateTime]::UtcNow.ToString('o'); $state.lastResult = 'Refreshed'; $state.consecutiveFailures = 0
            Write-KeeperLog ("Refresh persisted. Access token replaced; refresh token rotated: {0}; new access token valid {1}; login now {2}." -f $rotated, (Format-Span $afterSt.AccessRemaining), $(if ($afterSt.RefreshKnown) { Format-Span $afterSt.RefreshRemaining } else { 'expiry not recorded' })) 'INFO'
            if ($cred.RefreshExpiresUtc -and $after.RefreshExpiresUtc) {
                if ($extended) {
                    $state.noExtendCount = 0
                    Write-KeeperLog ("Login lifetime extended by {0}." -f (Format-Span ($after.RefreshExpiresUtc - $cred.RefreshExpiresUtc))) 'INFO'
                } else {
                    $state.noExtendCount = [int]$state.noExtendCount + 1
                    Write-KeeperLog ("The refresh succeeded but the login expiry did NOT move (still {0}). The server appears to enforce a fixed lifetime for this login (e.g. an organization/SSO session limit), which no local tool can extend. Run /login before it expires." -f $after.RefreshExpiresUtc.ToString('u')) 'WARN'
                    if ($afterSt.RefreshRemaining.TotalHours -le $ThresholdHours) {
                        Send-KeeperAlert $state 'fixed-expiry' ("Claude login expires {0} and cannot be extended automatically. Run /login." -f $after.RefreshExpiresUtc.ToLocalTime().ToString('g'))
                    }
                }
            } else {
                Write-KeeperLog 'refreshTokenExpiresAt is not recorded, so lifetime extension cannot be verified.' 'WARN'
            }
            Save-KeeperState $state
            return 0
        }

        if ($afterSt.AccessRemaining -and $afterSt.AccessRemaining.TotalMinutes -gt 6) {
            # Another Claude Code process refreshed it first (or the CLI judged the token still valid).
            $state.lastSuccessUtc = [DateTime]::UtcNow.ToString('o'); $state.lastResult = 'RefreshedByOtherProcess'; $state.consecutiveFailures = 0
            Write-KeeperLog ("Access token is valid for {0}; no refresh was needed by Claude Code (or a concurrent session already did it)." -f (Format-Span $afterSt.AccessRemaining)) 'INFO'
            Save-KeeperState $state
            return 0
        }

        # Not refreshed and the access token is still (nearly) expired.
        $state.consecutiveFailures = [int]$state.consecutiveFailures + 1
        $needsLogin = ($tail -match '(?i)login expired|please run\s*/login|invalid_grant|not logged in|refresh token|\b401\b|oauth')
        if ($run.TimedOut) { $state.lastResult = 'TimedOut'; $code = 4 }
        elseif ($needsLogin -or $st.LoginExpired) { $state.lastResult = 'NeedsLogin'; $code = 3 }
        else { $state.lastResult = 'NotConfirmed'; $code = 4 }
        Write-KeeperLog ("Refresh NOT confirmed ({0}). Claude Code output: {1}" -f $state.lastResult, $(if ($tail) { $tail } else { '(none)' })) 'ERROR'
        if ($state.lastResult -eq 'NeedsLogin') {
            Write-KeeperLog 'The server/CLI rejected the saved login. Run /login (interactive); a script cannot do that step.' 'ERROR'
            Send-KeeperAlert $state 'login' 'Claude login expired or was rejected. Run /login.'
        } elseif ([int]$state.consecutiveFailures -ge 3 -or ($afterSt.RefreshKnown -and $afterSt.RefreshRemaining.TotalHours -le 24)) {
            Send-KeeperAlert $state 'failing' 'Claude Session Keeper cannot refresh your login. Check renewal.log.'
        }
        Save-KeeperState $state
        return $code
    } finally {
        Exit-KeeperMutex $lock
    }
}

try {
    $code = Invoke-Keeper
} catch {
    Write-KeeperLog ("Unexpected error: {0}" -f $_.Exception.Message) 'ERROR'
    Write-KeeperLog ($_.ScriptStackTrace) 'DEBUG'
    $code = 1
}
exit $code
