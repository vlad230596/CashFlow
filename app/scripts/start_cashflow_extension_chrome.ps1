param(
    [ValidateSet('user-1', 'user-2')]
    [string]$Profile = 'user-1',
    [int]$DebugPort = 9223,
    [string]$StartUrl = 'https://www.tbank.ru/login/',
    [string]$Language = 'ru-RU',
    [string]$BrowserExecutable
)

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$chromeForTestingRoot = Join-Path $repositoryRoot '.local\browsers\chrome'

if (-not $BrowserExecutable) {
    $chromeForTesting = Get-ChildItem -LiteralPath $chromeForTestingRoot -Directory -Filter 'win64-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'chrome-win64\chrome.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1

    if ($chromeForTesting) {
        $BrowserExecutable = $chromeForTesting
    }
    else {
        $BrowserExecutable = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
    }
}

$profileDirectory = Join-Path $repositoryRoot ".local\chrome-profiles\$Profile"
$extensionDirectory = Join-Path $repositoryRoot 'browser_extension\.output\chrome-mv3'
$manifestPath = Join-Path $extensionDirectory 'manifest.json'

if (-not (Test-Path -LiteralPath $BrowserExecutable)) {
    throw "A Chromium browser was not found at $BrowserExecutable"
}

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Extension build was not found at $manifestPath. Run npm run build first."
}

New-Item -ItemType Directory -Force -Path $profileDirectory | Out-Null
$defaultProfileDirectory = Join-Path $profileDirectory 'Default'
$certificateStore = Join-Path $defaultProfileDirectory 'ServerCertificate'
$certificateStoreSource = Join-Path $repositoryRoot '.local\chrome-profiles\user-1\Default\ServerCertificate'

# Chrome keeps user-added trust anchors in this dedicated SQLite database.
# Seed it for a new secondary profile without copying cookies, local storage,
# history, credentials, or any other browser state.
if ($Profile -ne 'user-1' -and
    -not (Test-Path -LiteralPath $certificateStore) -and
    (Test-Path -LiteralPath $certificateStoreSource)) {
    New-Item -ItemType Directory -Force -Path $defaultProfileDirectory | Out-Null
    Copy-Item -LiteralPath $certificateStoreSource -Destination $certificateStore
}
$baseLanguage = ($Language -split '-')[0]

$arguments = @(
    "--user-data-dir=$profileDirectory"
    '--profile-directory=Default'
    "--remote-debugging-port=$DebugPort"
    '--remote-debugging-address=127.0.0.1'
    '--enable-unsafe-extension-debugging'
    "--lang=$Language"
    "--accept-lang=$Language,$baseLanguage,en-US,en"
    "--disable-extensions-except=$extensionDirectory"
    "--load-extension=$extensionDirectory"
    '--no-first-run'
    '--no-default-browser-check'
    $StartUrl
)

Start-Process -FilePath $BrowserExecutable -ArgumentList $arguments

$debugEndpoint = "http://127.0.0.1:$DebugPort/json/version"
$chromeReady = $false
for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try {
        $null = Invoke-RestMethod -Uri $debugEndpoint -TimeoutSec 1
        $chromeReady = $true
        break
    }
    catch {
        Start-Sleep -Milliseconds 250
    }
}

if (-not $chromeReady) {
    throw "Chrome did not expose its DevTools endpoint at $debugEndpoint"
}

& (Join-Path $PSScriptRoot 'load_cashflow_extension.ps1') -DebugPort $DebugPort
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
