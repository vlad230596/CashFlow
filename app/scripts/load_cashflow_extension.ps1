param(
    [int]$DebugPort = 9223
)

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$nodeExecutable = Join-Path $env:ProgramFiles 'nodejs\node.exe'
$loaderScript = Join-Path $PSScriptRoot 'load_unpacked_extension.mjs'
$extensionDirectory = Join-Path $repositoryRoot 'browser_extension\.output\chrome-mv3'

if (-not (Test-Path -LiteralPath $nodeExecutable)) {
    throw "Node.js was not found at $nodeExecutable"
}

& $nodeExecutable $loaderScript $extensionDirectory $DebugPort
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
