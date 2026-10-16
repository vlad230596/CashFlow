[CmdletBinding()]
param(
    [string]$Device = 'emulator-5554',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
if ($Device -notmatch '^emulator-\d+$') { throw 'Use a dedicated Android emulator.' }
$repoRoot = Split-Path -Parent $PSScriptRoot
$previousDevice = $env:CASHFLOW_ANDROID_DEVICE
$env:CASHFLOW_ANDROID_DEVICE = $Device
$serverProcess = $null
$resultsPath = Join-Path $repoRoot 'tests/android/results'
$qaApk = Join-Path $resultsPath 'cashflow-offlineqa.apk'

Push-Location $repoRoot
try {
    if ((adb -s $Device get-state) -ne 'device') { throw 'Start the selected emulator first.' }
    New-Item -ItemType Directory -Path $resultsPath -Force > $null
    if (-not $SkipBuild) {
        Push-Location app
        try {
            . .\scripts\setup_vscode_flutter_env.ps1
            flutter build apk --release --dart-define=CASHFLOW_API_URL=http://10.0.2.2:18742 --dart-define=CASHFLOW_OFFLINE_QA_METRICS=true
            if ($LASTEXITCODE -ne 0) { throw 'QA APK build failed.' }
        } finally { Pop-Location }
        Copy-Item -LiteralPath app/build/app/outputs/flutter-apk/app-release.apk -Destination $qaApk
    }
    # Inspect the actual APK, not only Gradle metadata, before installation.
    $sdkRoot = Split-Path -Parent (Split-Path -Parent (Get-Command adb).Source)
    $aapt = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') -Directory |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'aapt.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $aapt) { throw 'Android build-tools aapt.exe is required.' }
    $identity = & $aapt dump badging $qaApk | Select-Object -First 1
    if ($identity -notmatch "name='com.example.cash_app.offlineqa'") {
        throw 'Refusing to install an APK outside the isolated QA package.'
    }
    adb -s $Device install -r -g $qaApk
    if ($LASTEXITCODE -ne 0) { throw 'QA APK installation failed.' }
    Push-Location tests/browser
    try {
        npm.cmd ci
        if ($LASTEXITCODE -ne 0) { throw 'Test dependency installation failed.' }
    } finally { Pop-Location }
    $secretsPath = Join-Path $repoRoot '.argent/secrets.env'
    $existingSecrets = if (Test-Path -LiteralPath $secretsPath) { Get-Content -LiteralPath $secretsPath -Raw } else { '' }
    if ($existingSecrets -notmatch '(?m)^OFFLINE_QA_USER=') { Add-Content -LiteralPath $secretsPath -Value 'OFFLINE_QA_USER=offline-reader' }
    if ($existingSecrets -notmatch '(?m)^OFFLINE_QA_PASSWORD=') { Add-Content -LiteralPath $secretsPath -Value 'OFFLINE_QA_PASSWORD=synthetic-test-password' }
    $alreadyRunning = $false
    try { Invoke-WebRequest http://127.0.0.1:18742/__qa/status -TimeoutSec 1 > $null; $alreadyRunning = $true } catch { }
    if ($alreadyRunning) { throw 'Port 18742 already has a server; stop it before starting an isolated run.' }
    $serverProcess = Start-Process -FilePath (Get-Command node).Source `
        -ArgumentList @('tests/android/fixture-server.mjs') -WorkingDirectory $repoRoot `
        -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $resultsPath 'server.log') `
        -RedirectStandardError (Join-Path $resultsPath 'server-error.log')
    $serverReady = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try { Invoke-RestMethod http://127.0.0.1:18742/__qa/status -TimeoutSec 1 > $null; $serverReady = $true; break } catch { Start-Sleep -Milliseconds 200 }
    }
    if (-not $serverReady) { throw 'Synthetic API server did not start.' }
    $argentPath = (Get-Command argent -ErrorAction Stop).Source
    & $argentPath run stop-all-simulator-servers --devices $Device
    if ($LASTEXITCODE -ne 0) { throw 'Cannot recycle the scoped Argent service.' }
    foreach ($pass in 1..2) {
        & $argentPath flow run qa-android-offline-cache --device $Device --platform android --json |
            Set-Content -LiteralPath (Join-Path $resultsPath "pass-$pass.json") -Encoding utf8
        if ($LASTEXITCODE -ne 0) { throw "Android offline pass $pass failed; see tests/android/results." }
    }
} finally {
    if ($serverProcess) {
        node tests/android/scripts/cleanup.mjs
        Stop-Process -Id $serverProcess.Id -ErrorAction SilentlyContinue
    }
    $env:CASHFLOW_ANDROID_DEVICE = $previousDevice
    Pop-Location
}
