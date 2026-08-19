param(
    [ValidateSet('user-1', 'user-2')]
    [string]$Profile = 'user-1',
    [int]$DebugPort = 9223,
    [string]$StartUrl = 'https://www.tbank.ru/mybank/bonuses/',
    [string]$Language = 'ru-RU'
)

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$profileDirectory = Join-Path $repositoryRoot ".local\chrome-profiles\$Profile"

if (Test-Path -LiteralPath $profileDirectory) {
    $resolvedProfile = (Resolve-Path -LiteralPath $profileDirectory).Path
    $profileProcesses = Get-CimInstance Win32_Process -Filter "name='chrome.exe'" |
        Where-Object { $_.CommandLine -like "*$resolvedProfile*" }

    foreach ($process in $profileProcesses | Where-Object { $_.CommandLine -notlike '*--type=*' }) {
        $nativeProcess = Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
        if ($nativeProcess) {
            $null = $nativeProcess.CloseMainWindow()
        }
    }

    Start-Sleep -Seconds 2

    Get-CimInstance Win32_Process -Filter "name='chrome.exe'" |
        Where-Object { $_.CommandLine -like "*$resolvedProfile*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
}

& (Join-Path $PSScriptRoot 'start_cashflow_extension_chrome.ps1') `
    -Profile $Profile `
    -DebugPort $DebugPort `
    -StartUrl $StartUrl `
    -Language $Language

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
