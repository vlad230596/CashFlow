param(
    [ValidateSet('user-1', 'user-2')]
    [string]$Profile = 'user-1',
    [int]$DebugPort = 9225,
    [string]$StartUrl = 'https://web.alfabank.ru/'
)

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$browserExecutable = Join-Path $env:LOCALAPPDATA 'Yandex\YandexBrowser\Application\browser.exe'
$profileDirectory = Join-Path $repositoryRoot ".local\yandex-profiles\$Profile"
$extensionDirectory = Join-Path $repositoryRoot 'browser_extension\.output\chrome-mv3'

if (-not (Test-Path -LiteralPath $browserExecutable)) {
    throw "Yandex Browser was not found at $browserExecutable"
}

New-Item -ItemType Directory -Force -Path $profileDirectory | Out-Null

$arguments = @(
    "--user-data-dir=$profileDirectory"
    '--profile-directory=Default'
    "--remote-debugging-port=$DebugPort"
    '--remote-debugging-address=127.0.0.1'
    '--lang=ru-RU'
    '--accept-lang=ru-RU,ru,en-US,en'
    "--disable-extensions-except=$extensionDirectory"
    "--load-extension=$extensionDirectory"
    '--no-first-run'
    '--new-window'
    $StartUrl
)

Start-Process -FilePath $browserExecutable -ArgumentList $arguments

$debugEndpoint = "http://127.0.0.1:$DebugPort/json/version"
for ($attempt = 0; $attempt -lt 40; $attempt++) {
    try {
        $null = Invoke-RestMethod -Uri $debugEndpoint -TimeoutSec 1
        exit 0
    }
    catch {
        Start-Sleep -Milliseconds 250
    }
}

throw "Yandex Browser did not expose its DevTools endpoint at $debugEndpoint"
