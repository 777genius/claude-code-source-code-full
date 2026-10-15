<#
.SYNOPSIS
    Removes the ClaudeSessionKeeper scheduled task. Never touches Claude Code or its credentials.

.PARAMETER RemoveData
    Also delete the keeper's own log/state folder (%LOCALAPPDATA%\ClaudeSessionKeeper).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param([switch]$RemoveData)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ClaudeSessionKeeper.Common.ps1')

if (-not (Test-IsWindows)) { throw 'This script only applies to Windows.' }
if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { throw 'The ScheduledTasks module is not available in this PowerShell session.' }

$taskName = 'ClaudeSessionKeeper'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    if ($PSCmdlet.ShouldProcess($taskName, 'Remove scheduled task')) {
        if ($task.State -eq 'Running') { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue }
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Removed scheduled task '$taskName'." -ForegroundColor Green
    }
} else {
    Write-Host "Scheduled task '$taskName' does not exist."
}

if ($RemoveData) {
    $dir = Get-KeeperStateDir
    if ((Test-Path -LiteralPath $dir) -and $PSCmdlet.ShouldProcess($dir, 'Delete keeper log/state folder')) {
        Remove-Item -LiteralPath $dir -Recurse -Force
        Write-Host "Deleted $dir" -ForegroundColor Green
    }
}
