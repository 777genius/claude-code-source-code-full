# Shared helpers for Claude Session Keeper. Dot-sourced by the other scripts; not run directly.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+. Keep this file ASCII-only: 5.1 reads
# BOM-less files as ANSI, so non-ASCII characters would be corrupted.

$script:KeeperVersion = '2.0.0'

# Environment variables that would make `claude` authenticate with something other than the saved
# claude.ai login. They are removed from the child process so a refresh check really exercises the
# stored OAuth credentials (otherwise `claude -p` would silently use an API key and refresh nothing).
$script:AuthOverrideEnvVars = @(
    'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'CLAUDE_CODE_OAUTH_TOKEN',
    'CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR', 'ANTHROPIC_PROFILE',
    'CLAUDE_CODE_USE_BEDROCK', 'CLAUDE_CODE_USE_VERTEX', 'CLAUDE_CODE_USE_FOUNDRY',
    'CLAUDE_CODE_OAUTH_REFRESH_TOKEN', 'CLAUDE_CODE_OAUTH_SCOPES'
)

# The login-expiry banner in Claude Code ("Your login expires in N days") is shown while the
# credential's refreshTokenExpiresAt is within this window. Mirrors the CLI (3 days).
$script:BannerWindow = [TimeSpan]::FromDays(3)

function Test-IsWindows {
    return ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
}

function Get-KeeperStateDir {
    if ($env:CLAUDE_KEEPER_STATE_DIR) { return $env:CLAUDE_KEEPER_STATE_DIR }
    $base = [Environment]::GetFolderPath('LocalApplicationData')
    if (-not $base) { $base = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.local/share' }
    return (Join-Path $base 'ClaudeSessionKeeper')
}

function Get-ClaudeConfigDir {
    param([string]$Override)
    # Same resolution as the CLI: CLAUDE_CONFIG_DIR, else <home>\.claude (home = USERPROFILE on Windows).
    if ($Override) { return $Override }
    if ($env:CLAUDE_CONFIG_DIR) { return $env:CLAUDE_CONFIG_DIR }
    $home_ = $env:USERPROFILE
    if (-not $home_) { $home_ = [Environment]::GetFolderPath('UserProfile') }
    return (Join-Path $home_ '.claude')
}

# ---------------------------------------------------------------------------------------------
# Logging (never logs token values)
# ---------------------------------------------------------------------------------------------

function Protect-KeeperText {
    param([string]$Text)
    if (-not $Text) { return '' }
    $t = $Text
    $t = [regex]::Replace($t, 'sk-ant-[A-Za-z0-9_\-]{6,}', 'sk-ant-[REDACTED]')
    $t = [regex]::Replace($t, '(?i)(bearer\s+)[A-Za-z0-9._\-~+/=]{12,}', '$1[REDACTED]')
    $t = [regex]::Replace($t, '(?i)((?:access|refresh)[_-]?token"?\s*[:=]\s*"?)[A-Za-z0-9._\-~+/=]{12,}', '$1[REDACTED]')
    return $t
}

function Write-KeeperLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')][string]$Level = 'INFO'
    )
    if ($Level -eq 'DEBUG' -and $VerbosePreference -eq 'SilentlyContinue') { return }
    $line = '{0} [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'), $Level, (Protect-KeeperText $Message)
    $color = switch ($Level) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } 'DEBUG' { 'DarkGray' } default { 'Gray' } }
    Write-Host $line -ForegroundColor $color
    try {
        $dir = Get-KeeperStateDir
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $path = Join-Path $dir 'renewal.log'
        # Simple size-based rotation: renewal.log -> .1 -> .2 -> .3 (about 1 MB each).
        if ((Test-Path -LiteralPath $path) -and ((New-Object System.IO.FileInfo($path)).Length -gt 1MB)) {
            try {
                if (Test-Path "$path.3") { Remove-Item "$path.3" -Force }
                foreach ($i in 2, 1) { if (Test-Path "$path.$i") { Move-Item "$path.$i" ("$path." + ($i + 1)) -Force } }
                Move-Item $path "$path.1" -Force
            } catch { }
        }
        $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($line + "`r`n")
        for ($i = 0; $i -lt 5; $i++) {
            try {
                $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
                try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
                break
            } catch { Start-Sleep -Milliseconds (60 * ($i + 1)) }
        }
    } catch { }
}

# ---------------------------------------------------------------------------------------------
# Small JSON/state helpers (atomic write so readers never see a half-written file)
# ---------------------------------------------------------------------------------------------

function Write-KeeperJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Object)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = '{0}.{1}.tmp' -f $Path, [Guid]::NewGuid().ToString('N')
    $json = $Object | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    try {
        # [NullString]::Value: a plain $null would be coerced to "" for the backup-path parameter and throw.
        if (Test-Path -LiteralPath $Path) { [System.IO.File]::Replace($tmp, $Path, [NullString]::Value) }
        else { [System.IO.File]::Move($tmp, $Path) }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Read-KeeperState {
    $path = Join-Path (Get-KeeperStateDir) 'state.json'
    $state = [ordered]@{
        lastAttemptUtc = $null; lastSuccessUtc = $null; lastResult = $null
        consecutiveFailures = 0; noExtendCount = 0; notified = @{}
    }
    if (Test-Path -LiteralPath $path) {
        try {
            $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
            foreach ($k in 'lastAttemptUtc', 'lastSuccessUtc', 'lastResult', 'consecutiveFailures', 'noExtendCount') {
                if ($null -ne $raw.$k) { $state[$k] = $raw.$k }
            }
            if ($raw.notified) {
                foreach ($p in $raw.notified.PSObject.Properties) { $state.notified[$p.Name] = [string]$p.Value }
            }
        } catch { Write-KeeperLog "state.json is unreadable and will be rebuilt: $($_.Exception.Message)" 'WARN' }
    }
    return $state
}

function Save-KeeperState {
    param([Parameter(Mandatory)]$State)
    try { Write-KeeperJson -Path (Join-Path (Get-KeeperStateDir) 'state.json') -Object $State }
    catch { Write-KeeperLog "Could not save state.json: $($_.Exception.Message)" 'WARN' }
}

function ConvertTo-UtcDateTime {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [DateTime]) { return $Value.ToUniversalTime() }
    if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime }
    $s = [string]$Value
    $d = 0.0
    if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
        if ($d -le 0) { return $null }
        if ($d -lt 100000000000) { $d = $d * 1000 }   # looks like epoch seconds; the CLI writes milliseconds
        try { return [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$d).UtcDateTime } catch { return $null }
    }
    $o = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$o)) {
        return $o.UtcDateTime
    }
    return $null
}

function Get-TokenFingerprint {
    # Short SHA-256 prefix: lets us tell "the token changed" without ever holding a token in a log.
    param([string]$Token)
    if ([string]::IsNullOrEmpty($Token)) { return $null }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Token)) } finally { $sha.Dispose() }
    return (($h[0..3] | ForEach-Object { $_.ToString('x2') }) -join '')
}

# ---------------------------------------------------------------------------------------------
# Credentials (READ-ONLY: this tool never writes .credentials.json; only Claude Code does)
# ---------------------------------------------------------------------------------------------

function Read-ClaudeCredential {
    param([Parameter(Mandatory)][string]$Path)
    $result = [pscustomobject]@{
        Status = 'Missing'; Path = $Path; Error = $null; LastWriteUtc = $null
        HasRefreshToken = $false; Scopes = @(); SubscriptionType = $null; HasClientId = $false
        AccessExpiresUtc = $null; RefreshExpiresUtc = $null
        AccessFingerprint = $null; RefreshFingerprint = $null
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $result }
    $json = $null
    # Claude Code rewrites this file in place, so a read can land mid-write: retry a few times.
    for ($i = 0; $i -lt 6; $i++) {
        try {
            $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            try { $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true); $text = $sr.ReadToEnd() } finally { $fs.Dispose() }
            $json = $text | ConvertFrom-Json -ErrorAction Stop
            break
        } catch {
            $result.Error = $_.Exception.Message
            Start-Sleep -Milliseconds (150 * ($i + 1))
        }
    }
    if ($null -eq $json) { $result.Status = 'Unreadable'; return $result }
    $result.Error = $null
    $result.LastWriteUtc = (New-Object System.IO.FileInfo($Path)).LastWriteTimeUtc   # Get-Item would need -Force for hidden files
    $oauth = $json.claudeAiOauth
    if ($null -eq $oauth) { $result.Status = 'NoOAuth'; return $result }
    $result.Status = 'Ok'
    $result.HasRefreshToken = -not [string]::IsNullOrWhiteSpace([string]$oauth.refreshToken)
    $result.Scopes = @($oauth.scopes | Where-Object { $_ } | ForEach-Object { [string]$_ })
    $result.SubscriptionType = $oauth.subscriptionType
    $result.HasClientId = -not [string]::IsNullOrWhiteSpace([string]$oauth.clientId)
    $result.AccessExpiresUtc = ConvertTo-UtcDateTime $oauth.expiresAt
    $result.RefreshExpiresUtc = ConvertTo-UtcDateTime $oauth.refreshTokenExpiresAt
    $result.AccessFingerprint = Get-TokenFingerprint ([string]$oauth.accessToken)
    $result.RefreshFingerprint = Get-TokenFingerprint ([string]$oauth.refreshToken)
    return $result
}

function Get-LoginStatus {
    # expiresAt = ACCESS token expiry (hours; Claude Code refreshes it itself).
    # refreshTokenExpiresAt = LOGIN expiry (what the "Your login expires in N days" banner uses).
    param([Parameter(Mandatory)]$Credential, [DateTime]$NowUtc = [DateTime]::UtcNow)
    $s = [pscustomobject]@{
        AccessRemaining = $null; RefreshRemaining = $null; RefreshKnown = $false
        BannerDaysLeft = $null; AccessExpired = $false; LoginExpired = $false
    }
    if ($Credential.AccessExpiresUtc) {
        $s.AccessRemaining = $Credential.AccessExpiresUtc - $NowUtc
        $s.AccessExpired = ($s.AccessRemaining.TotalSeconds -le 0)
    }
    if ($Credential.RefreshExpiresUtc) {
        $s.RefreshKnown = $true
        $s.RefreshRemaining = $Credential.RefreshExpiresUtc - $NowUtc
        $s.LoginExpired = ($s.RefreshRemaining.TotalSeconds -le 0)
        # Banner rule, as implemented in Claude Code 2.1.x: hidden when the access token outlives the
        # refresh token by more than the window; otherwise shown while 0 < remaining <= 3 days.
        $suppressed = ($Credential.AccessExpiresUtc -and ($Credential.AccessExpiresUtc -gt ($Credential.RefreshExpiresUtc + $script:BannerWindow)))
        if (-not $suppressed -and $s.RefreshRemaining.TotalSeconds -gt 0 -and $s.RefreshRemaining -le $script:BannerWindow) {
            $s.BannerDaysLeft = [int][math]::Ceiling($s.RefreshRemaining.TotalDays)
        }
    }
    return $s
}

function Format-Span {
    param($Span)
    if ($null -eq $Span) { return 'unknown' }
    $neg = $Span.TotalSeconds -lt 0
    $a = if ($neg) { $Span.Negate() } else { $Span }
    $txt = if ($a.TotalDays -ge 1) { '{0:N1} days' -f $a.TotalDays } elseif ($a.TotalHours -ge 1) { '{0:N1} hours' -f $a.TotalHours } else { '{0:N0} minutes' -f $a.TotalMinutes }
    if ($neg) { return "expired $txt ago" }
    return $txt
}

# ---------------------------------------------------------------------------------------------
# Locating and running the CLI
# ---------------------------------------------------------------------------------------------

function Resolve-ClaudeExecutable {
    # Returns a real executable (.exe preferred, then .cmd). Never a .ps1 shim: those depend on the
    # caller's execution policy and are not reliably launchable from a scheduled task.
    param([string]$Override)
    if ($Override) {
        if (Test-Path -LiteralPath $Override -PathType Leaf) { return (Resolve-Path -LiteralPath $Override).Path }
        return $null
    }
    $candidates = @()
    try { $candidates += @(Get-Command claude -All -CommandType Application -ErrorAction SilentlyContinue | ForEach-Object { $_.Source }) } catch { }
    $userHome = [Environment]::GetFolderPath('UserProfile')
    if ($userHome) { $candidates += (Join-Path $userHome '.local\bin\claude.exe') }
    if ($env:APPDATA) { $candidates += (Join-Path $env:APPDATA 'npm\claude.cmd') }
    $candidates = @($candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -Unique)
    foreach ($ext in '.exe', '.cmd', '.bat', '') {
        foreach ($c in $candidates) { if ([IO.Path]::GetExtension($c).ToLowerInvariant() -eq $ext) { return $c } }
    }
    return $null
}

function ConvertTo-ArgumentString {
    # Quotes arguments per the Windows CommandLineToArgvW rules (Windows PowerShell 5.1 has no ArgumentList).
    param([string[]]$Arguments)
    $parts = foreach ($a in $Arguments) {
        if ($null -eq $a -or $a.Length -eq 0) { '""' }
        elseif ($a -notmatch '[\s"]') { $a }
        else {
            $q = [regex]::Replace($a, '(\\*)"', '$1$1\"')
            $q = [regex]::Replace($q, '(\\+)$', '$1$1')
            '"' + $q + '"'
        }
    }
    return ($parts -join ' ')
}

function Invoke-ClaudeCommand {
    param(
        [Parameter(Mandatory)][string]$ExePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory,
        [int]$TimeoutSeconds = 120,
        [string[]]$RemoveEnv = @(),
        [hashtable]$SetEnv = @{}
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $ext = [IO.Path]::GetExtension($ExePath).ToLowerInvariant()
    if ($ext -eq '.cmd' -or $ext -eq '.bat') {
        $comspec = $env:ComSpec; if (-not $comspec) { $comspec = 'cmd.exe' }
        $psi.FileName = $comspec
        $psi.Arguments = '/d /s /c "' + (ConvertTo-ArgumentString (@($ExePath) + $Arguments)) + '"'
    } else {
        $psi.FileName = $ExePath
        $psi.Arguments = ConvertTo-ArgumentString $Arguments
    }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    foreach ($n in $RemoveEnv) { if ($psi.EnvironmentVariables.ContainsKey($n)) { $psi.EnvironmentVariables.Remove($n) } }
    foreach ($k in $SetEnv.Keys) { $psi.EnvironmentVariables[$k] = [string]$SetEnv[$k] }

    $out = [pscustomobject]@{ ExitCode = $null; TimedOut = $false; Output = ''; StartError = $null; Seconds = 0 }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    try {
        [void]$p.Start()
    } catch {
        $out.StartError = $_.Exception.Message
        return $out
    }
    try {
        try { $p.StandardInput.Close() } catch { }   # `claude -p` reads stdin if it is left open
        $stdout = $p.StandardOutput.ReadToEndAsync()
        $stderr = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            $out.TimedOut = $true
            try {
                if (Test-IsWindows) { & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null } else { $p.Kill() }
            } catch { try { $p.Kill() } catch { } }
            [void]$p.WaitForExit(5000)
        } else {
            $p.WaitForExit()   # flush the async readers
        }
        try { $out.ExitCode = $p.ExitCode } catch { }
        $text = ''
        try { if ($stderr.Wait(3000)) { $text += $stderr.Result } } catch { }
        try { if ($stdout.Wait(3000)) { $text += "`n" + $stdout.Result } } catch { }
        $out.Output = $text
    } finally {
        $sw.Stop(); $out.Seconds = [int]$sw.Elapsed.TotalSeconds
        $p.Dispose()
    }
    return $out
}

# ---------------------------------------------------------------------------------------------
# Single-instance lock (keeper vs keeper only; Claude Code uses its own lock for the refresh itself)
# ---------------------------------------------------------------------------------------------

function Enter-KeeperMutex {
    param([string]$Key)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Key.ToLowerInvariant())) } finally { $sha.Dispose() }
    $name = 'ClaudeSessionKeeper-' + (($h[0..7] | ForEach-Object { $_.ToString('x2') }) -join '')
    $mutex = $null
    foreach ($prefix in 'Global\', 'Local\') {
        try { $mutex = New-Object System.Threading.Mutex($false, ($prefix + $name)); break } catch { $mutex = $null }
    }
    if ($null -eq $mutex) { return [pscustomobject]@{ Acquired = $true; Mutex = $null } }   # cannot lock: proceed rather than never run
    $acquired = $false
    try { $acquired = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) { $mutex.Dispose(); $mutex = $null }
    return [pscustomobject]@{ Acquired = $acquired; Mutex = $mutex }
}

function Exit-KeeperMutex {
    param($Handle)
    if ($Handle -and $Handle.Mutex) {
        try { $Handle.Mutex.ReleaseMutex() } catch { }
        try { $Handle.Mutex.Dispose() } catch { }
    }
}

# ---------------------------------------------------------------------------------------------
# Best-effort desktop notification (Windows toast). Failure is silent by design.
# ---------------------------------------------------------------------------------------------

function Show-KeeperToast {
    param([string]$Title, [string]$Message)
    try {
        if (-not (Test-IsWindows) -or -not [Environment]::UserInteractive) { return }
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $esc = { param($x) [System.Security.SecurityElement]::Escape($x) }
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml('<toast><visual><binding template="ToastGeneric"><text>' + (& $esc $Title) + '</text><text>' + (& $esc $Message) + '</text></binding></visual></toast>')
        $toast = New-Object Windows.UI.Notifications.ToastNotification($xml)
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    } catch { }
}
