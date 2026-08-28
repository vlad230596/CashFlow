[CmdletBinding()]
param(
    [string] $Destination = 'D:\Backups\CashFlow\staging\cashflow.sql',
    [string] $SshKey = "$env:USERPROFILE\.ssh\cashflow-backup-pc1",
    [string] $KnownHostsFile = "$env:USERPROFILE\.ssh\known_hosts",
    [Parameter(Mandatory = $true)][string] $Server,
    [string] $SshUser = 'cashflow-backup'
)

$ErrorActionPreference = 'Stop'

$destinationPath = [System.IO.Path]::GetFullPath($Destination)
$destinationDirectory = Split-Path -Parent $destinationPath
$partialPath = "$destinationPath.partial"
$stderrPath = "$destinationPath.stderr"
$statusPath = Join-Path $destinationDirectory 'last-export.json'
$errorStatusPath = Join-Path $destinationDirectory 'last-export-error.log'

trap {
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    ($_ | Out-String) | Set-Content -LiteralPath $errorStatusPath -Encoding utf8
    throw
}

if (-not (Test-Path -LiteralPath $SshKey -PathType Leaf)) {
    throw "SSH key not found: $SshKey"
}
if (-not (Test-Path -LiteralPath $KnownHostsFile -PathType Leaf)) {
    throw "SSH known_hosts file not found: $KnownHostsFile"
}

New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
Remove-Item -LiteralPath $partialPath, $stderrPath -Force -ErrorAction SilentlyContinue

$sshArguments = @(
    '-T',
    '-i', $SshKey,
    '-o', 'BatchMode=yes',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', "UserKnownHostsFile=$KnownHostsFile",
    '-o', 'ConnectTimeout=20',
    "$SshUser@$Server"
)

$process = Start-Process `
    -FilePath 'ssh.exe' `
    -ArgumentList $sshArguments `
    -NoNewWindow `
    -Wait `
    -PassThru `
    -RedirectStandardOutput $partialPath `
    -RedirectStandardError $stderrPath

if ($process.ExitCode -ne 0) {
    $stderr = if (Test-Path -LiteralPath $stderrPath) {
        (Get-Content -LiteralPath $stderrPath -Raw).Trim()
    } else {
        'No SSH error output was captured.'
    }
    Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
    throw "Database export failed with SSH exit code $($process.ExitCode): $stderr"
}

$dump = Get-Item -LiteralPath $partialPath
if ($dump.Length -eq 0) {
    throw 'Database export produced an empty file.'
}
if (-not (Select-String -LiteralPath $partialPath -SimpleMatch 'PostgreSQL database dump complete' -Quiet)) {
    throw 'Database export is incomplete: the pg_dump completion marker is missing.'
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $partialPath).Hash
Move-Item -LiteralPath $partialPath -Destination $destinationPath -Force
Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue

[ordered]@{
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    path = $destinationPath
    bytes = $dump.Length
    sha256 = $hash
} | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding utf8

Remove-Item -LiteralPath $errorStatusPath -Force -ErrorAction SilentlyContinue
Write-Output "CashFlow database export completed: $($dump.Length) bytes, SHA-256 $hash"
