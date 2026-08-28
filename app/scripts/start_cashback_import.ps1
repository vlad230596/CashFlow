param(
    [ValidateSet('user-1', 'user-2')]
    [string]$Profile = 'user-1',
    [int]$DebugPort = 9223,
    [string[]]$Banks = @('tbank', 'yandex', 'alfa', 'sber', 'ozon', 'vtb'),
    [string]$ExtensionId
)

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$nodeExecutable = Join-Path $env:ProgramFiles 'nodejs\node.exe'
$versionEndpoint = "http://127.0.0.1:$DebugPort/json/version"
$chromeIsRunning = $false

try {
    $null = Invoke-RestMethod -Uri $versionEndpoint -TimeoutSec 1
    $chromeIsRunning = $true
}
catch {
    $chromeIsRunning = $false
}

if ($chromeIsRunning) {
    $loaderOutput = @(
        & (Join-Path $PSScriptRoot 'load_cashflow_extension.ps1') -DebugPort $DebugPort
    )
}
else {
    $loaderOutput = @(
        & (Join-Path $PSScriptRoot 'start_cashflow_extension_chrome.ps1') `
            -Profile $Profile `
            -DebugPort $DebugPort `
            -StartUrl 'about:blank'
    )
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not $ExtensionId) {
    foreach ($line in $loaderOutput) {
        try {
            $loadResult = $line | ConvertFrom-Json -ErrorAction Stop
            if ($loadResult.id) {
                $ExtensionId = $loadResult.id
            }
        }
        catch {
            # Other launcher output is informational and does not contain the ID.
        }
    }
}

if (-not $ExtensionId) {
    throw 'The extension ID could not be determined from the Chrome loader output.'
}

$banksValue = $Banks -join ','
& $nodeExecutable (Join-Path $PSScriptRoot 'configure_cashback_import.mjs') `
    $DebugPort $ExtensionId $banksValue
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $nodeExecutable (Join-Path $PSScriptRoot 'open_cashflow_sidepanel.mjs') `
    $DebugPort $ExtensionId
exit $LASTEXITCODE
