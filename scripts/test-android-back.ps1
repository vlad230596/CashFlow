[CmdletBinding()]
param([string]$Device = 'emulator-5554', [switch]$SkipBuild, [int]$Passes = 1, [string]$Only = '', [int]$FirstPass = 1)
$ErrorActionPreference = 'Stop'
if ($Device -notmatch '^emulator-\d+$') { throw 'Use a dedicated Android emulator.' }
if ($Passes -lt 1) { throw 'Passes must be positive.' }
if ($FirstPass -lt 1) { throw 'FirstPass must be positive.' }
$repoRoot = Split-Path -Parent $PSScriptRoot
$serverProcess = $null
$previousDevice = $env:CASHFLOW_ANDROID_DEVICE
$previousPass = $env:BACK_PASS
Push-Location $repoRoot
try {
    $env:CASHFLOW_ANDROID_DEVICE = $Device
    if ((adb -s $Device get-state) -ne 'device') { throw 'Start the selected emulator first.' }
    $resultsPath = Join-Path $repoRoot 'tests/android/results'
    New-Item -ItemType Directory -Force -Path $resultsPath > $null
    $qaApk = Join-Path $resultsPath 'cashflow-backqa.apk'
    if (-not $SkipBuild) {
        Push-Location app
        try {
            . .\scripts\setup_vscode_flutter_env.ps1
            flutter build apk --release --dart-define=CASHFLOW_API_URL=http://10.0.2.2:18742 --dart-define=CASHFLOW_OFFLINE_QA_METRICS=true
            if ($LASTEXITCODE -ne 0) { throw 'QA APK build failed.' }
        } finally { Pop-Location }
        Copy-Item -LiteralPath app/build/app/outputs/flutter-apk/app-release.apk -Destination $qaApk
    }
    $sdkRoot = Split-Path -Parent (Split-Path -Parent (Get-Command adb).Source)
    $aapt = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') -Directory |
        Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'aapt.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $aapt) { throw 'Android build-tools aapt.exe is required.' }
    $identity = & $aapt dump badging $qaApk | Select-Object -First 1
    if ($identity -notmatch "name='com.example.cash_app.offlineqa'") { throw 'Refusing APK outside isolated QA package.' }
    adb -s $Device install -r -g $qaApk
    if ($LASTEXITCODE -ne 0) { throw 'QA APK installation failed.' }
    $alreadyRunning = $false
    try { Invoke-RestMethod http://127.0.0.1:18742/__qa/status -TimeoutSec 1 > $null; $alreadyRunning = $true } catch {}
    if ($alreadyRunning) { throw 'Port 18742 is occupied; stop its fixture server first.' }
    $serverProcess = Start-Process -FilePath (Get-Command node).Source -ArgumentList @('tests/android/back-fixture-server.mjs') `
        -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $resultsPath 'back-server.log') `
        -RedirectStandardError (Join-Path $resultsPath 'back-server-error.log')
    $ready = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try { Invoke-RestMethod http://127.0.0.1:18742/__qa/status -TimeoutSec 1 > $null; $ready = $true; break } catch { Start-Sleep -Milliseconds 200 }
    }
    if (-not $ready) { throw 'Synthetic API did not start; see back-server-error.log.' }
    $failed = $false
    foreach ($pass in 1..$Passes) {
        $env:BACK_PASS = "$($FirstPass + $pass - 1)"
        $runnerArgs = @('tests/android/run-back.mjs')
        if ($Only) { $runnerArgs += @('--only', $Only) }
        node @runnerArgs
        if ($LASTEXITCODE -ne 0) { $failed = $true }
    }
    if ($failed) { throw 'Back suite exited nonzero; inspect failed/error verdicts in tests/android/results/back-pass-*.json.' }
} finally {
    if ($serverProcess) { Stop-Process -Id $serverProcess.Id -ErrorAction SilentlyContinue }
    $env:CASHFLOW_ANDROID_DEVICE = $previousDevice
    $env:BACK_PASS = $previousPass
    Pop-Location
}
