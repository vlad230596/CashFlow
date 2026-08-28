[CmdletBinding()]
param(
    [string] $ProfilePath = $env:USERPROFILE,
    [string] $Server = '5.45.117.224'
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must run from an elevated PowerShell process.'
}

$clientDirectory = Join-Path $ProfilePath 'AppData\Local\CashFlowBackup'
$pullScript = Join-Path $clientDirectory 'pull-production-backup.ps1'
$privateKey = Join-Path $ProfilePath '.ssh\cashflow-backup-pc1'
$systemPrivateKey = Join-Path $clientDirectory 'cashflow-backup-system-key'
$knownHosts = Join-Path $ProfilePath '.ssh\known_hosts'
$statusPath = Join-Path $clientDirectory 'system-backup-verification.json'
$taskName = 'CashFlow Backup Verification'

foreach ($requiredPath in @($pullScript, $privateKey, $knownHosts)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required backup file not found: $requiredPath"
    }
}

if (Test-Path -LiteralPath $systemPrivateKey -PathType Leaf) {
    & takeown.exe /F $systemPrivateKey /A | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to take temporary ownership of the existing SYSTEM SSH key.'
    }
    & icacls.exe $systemPrivateKey /grant '*S-1-5-32-544:(F)' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to make the existing SYSTEM SSH key replaceable.'
    }
}

Copy-Item -LiteralPath $privateKey -Destination $systemPrivateKey -Force
$systemKeyAcl = New-Object System.Security.AccessControl.FileSecurity
$systemKeyAcl.SetOwner((New-Object System.Security.Principal.NTAccount('SYSTEM')))
$systemKeyAcl.SetAccessRuleProtection($true, $false)
$systemKeyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    'SYSTEM',
    [System.Security.AccessControl.FileSystemRights]::FullControl,
    [System.Security.AccessControl.AccessControlType]::Allow
)
$systemKeyAcl.AddAccessRule($systemKeyRule)
Set-Acl -LiteralPath $systemPrivateKey -AclObject $systemKeyAcl

& icacls.exe $knownHosts /grant:r 'SYSTEM:(R)' | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to grant SYSTEM read access to known_hosts.'
}

$arguments = @(
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy', 'Bypass',
    '-File', "`"$pullScript`"",
    '-Server', "`"$Server`"",
    '-SshKey', "`"$systemPrivateKey`"",
    '-KnownHostsFile', "`"$knownHosts`""
) -join ' '
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(10))
$principal = New-ScheduledTaskPrincipal `
    -UserId 'SYSTEM' `
    -LogonType ServiceAccount `
    -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

$startedAt = Get-Date
try {
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName

    $deadline = (Get-Date).AddMinutes(2)
    do {
        Start-Sleep -Seconds 2
        $task = Get-ScheduledTask -TaskName $taskName
        $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName
    } while (
        (Get-Date) -lt $deadline -and
        ($task.State -eq 'Running' -or $taskInfo.LastRunTime -lt $startedAt.AddSeconds(-5))
    )

    if ($taskInfo.LastTaskResult -ne 0) {
        throw "SYSTEM backup verification failed with task result $($taskInfo.LastTaskResult)."
    }

    $exportStatusPath = 'D:\Backups\CashFlow\staging\last-export.json'
    $exportStatus = Get-Content -LiteralPath $exportStatusPath -Raw | ConvertFrom-Json
    if ([DateTime]::Parse($exportStatus.completedAtUtc).ToUniversalTime() -lt $startedAt.ToUniversalTime()) {
        throw 'SYSTEM backup verification did not produce a fresh export status.'
    }

    [ordered]@{
        checkedAtUtc = [DateTime]::UtcNow.ToString('o')
        taskResult = $taskInfo.LastTaskResult
        exportCompletedAtUtc = $exportStatus.completedAtUtc
        exportBytes = $exportStatus.bytes
        exportSha256 = $exportStatus.sha256
        systemPrivateKey = $systemPrivateKey
    } | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8
} finally {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}

Write-Output "CashFlow backup access verified as SYSTEM. Status: $statusPath"
