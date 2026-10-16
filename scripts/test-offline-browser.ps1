[CmdletBinding()]
param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

Push-Location (Join-Path $repoRoot 'app')
try {
    if (-not $SkipBuild) {
        . .\scripts\setup_vscode_flutter_env.ps1
        flutter build web --release --no-web-resources-cdn --dart-define=CASHFLOW_API_URL=http://127.0.0.1:18741
        if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed.' }
    }
} finally { Pop-Location }

Push-Location (Join-Path $repoRoot 'tests\browser')
try {
    npm.cmd ci
    if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' }
    npx.cmd playwright install chromium
    if ($LASTEXITCODE -ne 0) { throw 'Chromium installation failed.' }
    npm.cmd run test:repeat
    if ($LASTEXITCODE -ne 0) { throw 'Offline browser tests failed. See tests/browser/playwright-report.' }
} finally { Pop-Location }
