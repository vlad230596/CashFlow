param(
    [string]$Run
)

$nodeDirectory = Join-Path $env:ProgramFiles 'nodejs'
$nodeExecutable = Join-Path $nodeDirectory 'node.exe'

if (-not (Test-Path -LiteralPath $nodeExecutable)) {
    throw "Node.js was not found at $nodeExecutable"
}

$env:Path = "$nodeDirectory;$env:Path"

if ($Run) {
    Invoke-Expression $Run
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}
