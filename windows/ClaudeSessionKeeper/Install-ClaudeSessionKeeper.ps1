<#
.SYNOPSIS
    Registers the per-user scheduled task that runs Renew-ClaudeLogin.ps1.

.PARAMETER IntervalMinutes
    How often to check (default 60). Checks are cheap and read-only; a request is only made when a
    refresh is actually due.

.PARAMETER RunWhetherLoggedOn
    Run even when you are signed out (S4U logon type; needs no stored password, but no desktop
    notifications and no network credentials). Default is "only while logged on".

.PARAMETER RunNow
    Start the task immediately after registering it.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateRange(15, 1440)][int]$IntervalMinutes = 60,
    [string]$ClaudePath,
    [string]$ConfigDir,
    [switch]$RunWhetherLoggedOn,
    [switch]$RunNow
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ClaudeSessionKeeper.Common.ps1')

if (-not (Test-IsWindows)) { throw 'Scheduled-task installation is only supported on Windows.' }
if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) { throw 'The ScheduledTasks module is not available in this PowerShell session.' }

$scriptPath = Join-Path $PSScriptRoot 'Renew-ClaudeLogin.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) { throw 'Renew-ClaudeLogin.ps1 and ClaudeSessionKeeper.Common.ps1 must be in the same folder as this script.' }

$exe = Resolve-ClaudeExecutable -Override $ClaudePath
if (-not $exe) { throw 'Claude Code was not found. Install it first, or pass -ClaudePath.' }

# Files downloaded from the internet carry a Zone.Identifier mark that can block them under RemoteSigned.
Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' | Unblock-File -ErrorAction SilentlyContinue

# The task runs these scripts as you, so they must not be writable by other users.
try {
    $risky = @()
    foreach ($ace in (Get-Acl -LiteralPath $PSScriptRoot).Access) {
        if ($ace.AccessControlType -ne 'Allow') { continue }
        if ($ace.IdentityReference.Value -match '(^|\\)(Everyone|Users|Authenticated Users)$' -and
            ($ace.FileSystemRights -band ([Security.AccessControl.FileSystemRights]::WriteData -bor [Security.AccessControl.FileSystemRights]::Modify -bor [Security.AccessControl.FileSystemRights]::FullControl))) {
            $risky += $ace.IdentityReference.Value
        }
    }
    if ($risky.Count) { Write-Warning ("This folder is writable by {0}. Move the scripts to a folder only you can write to before installing; the task runs them with your account." -f ($risky -join ', ')) }
} catch { }

$taskName = 'ClaudeSessionKeeper'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -ClaudePath "{1}"' -f $scriptPath, $exe
if ($ConfigDir) { $arguments += ' -ConfigDir "{0}"' -f $ConfigDir }
elseif ($env:CLAUDE_CONFIG_DIR) { $arguments += ' -ConfigDir "{0}"' -f $env:CLAUDE_CONFIG_DIR }

$action = New-ScheduledTaskAction -Execute $psExe -Argument $arguments -WorkingDirectory $PSScriptRoot
$triggers = @(
    (New-ScheduledTaskTrigger -AtLogOn -User $identity),
    (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650))
)
$logonType = if ($RunWhetherLoggedOn) { 'S4U' } else { 'Interactive' }
$principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType $logonType -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RunOnlyIfNetworkAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 10)

if ($PSCmdlet.ShouldProcess($taskName, "Register scheduled task (every $IntervalMinutes min and at logon; $logonType)")) {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings `
        -Description 'Keeps the Claude Code subscription login fresh by letting Claude Code refresh it itself when due. Read-only on credentials; never prints tokens.' -Force | Out-Null
    $info = Get-ScheduledTaskInfo -TaskName $taskName
    Write-Host "Installed scheduled task '$taskName' ($logonType, every $IntervalMinutes min + at logon). Next run: $($info.NextRunTime)" -ForegroundColor Green
    Write-Host "Logs: $(Join-Path (Get-KeeperStateDir) 'renewal.log')"
    Write-Host 'Run Test-ClaudeSessionKeeper.ps1 any time for a status report. Remove with Uninstall-ClaudeSessionKeeper.ps1.'
    if ($RunNow) { Start-ScheduledTask -TaskName $taskName; Write-Host 'Started the task once.' }
}
