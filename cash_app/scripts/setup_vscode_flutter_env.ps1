[CmdletBinding()]
param(
    [string]$FlutterSdkPath,
    [string]$Run
)

$ErrorActionPreference = 'Stop'

function Remove-JsonComments {
    param([Parameter(Mandatory = $true)][string]$Text)

    $result = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    $inLineComment = $false
    $inBlockComment = $false

    for ($i = 0; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }

        if ($inLineComment) {
            if ($ch -eq "`r" -or $ch -eq "`n") {
                $inLineComment = $false
                [void]$result.Append($ch)
            }
            continue
        }

        if ($inBlockComment) {
            if ($ch -eq '*' -and $next -eq '/') {
                $inBlockComment = $false
                $i++
            }
            continue
        }

        if (-not $inString -and $ch -eq '/' -and $next -eq '/') {
            $inLineComment = $true
            $i++
            continue
        }

        if (-not $inString -and $ch -eq '/' -and $next -eq '*') {
            $inBlockComment = $true
            $i++
            continue
        }

        [void]$result.Append($ch)

        if ($ch -eq '"' -and -not $escaped) {
            $inString = -not $inString
        }

        if ($ch -eq '\' -and -not $escaped) {
            $escaped = $true
        } else {
            $escaped = $false
        }
    }

    $result.ToString()
}

function Read-VSCodeJsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $json = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($json)) {
        return $null
    }

    Remove-JsonComments -Text $json | ConvertFrom-Json
}

function Get-SettingValue {
    param(
        $Settings,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Settings) {
        return $null
    }

    $property = $Settings.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    $property.Value
}

function Add-PathEntry {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $entries = $env:Path -split [System.IO.Path]::PathSeparator
    $exists = $entries | Where-Object {
        $_ -and ([string]::Equals(
            (Resolve-Path -LiteralPath $_ -ErrorAction SilentlyContinue).Path,
            (Resolve-Path -LiteralPath $Path).Path,
            [System.StringComparison]::OrdinalIgnoreCase
        ))
    }

    if (-not $exists) {
        $env:Path = "$Path$([System.IO.Path]::PathSeparator)$env:Path"
    }
}

function Resolve-FlutterSdkPath {
    param([string]$OverridePath)

    if ($OverridePath) {
        return $OverridePath
    }

    $candidateSettings = @(
        (Join-Path $PSScriptRoot '..\.vscode\settings.json'),
        (Join-Path $env:APPDATA 'Code\User\settings.json'),
        (Join-Path $env:APPDATA 'Code - Insiders\User\settings.json'),
        (Join-Path $env:APPDATA 'VSCodium\User\settings.json')
    )

    foreach ($settingsPath in $candidateSettings) {
        $settings = Read-VSCodeJsonFile -Path $settingsPath
        $path = Get-SettingValue -Settings $settings -Name 'dart.flutterSdkPath'
        if ($path) {
            return [Environment]::ExpandEnvironmentVariables($path)
        }
    }

    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCommand) {
        $binPath = Split-Path -Parent $flutterCommand.Source
        return Split-Path -Parent $binPath
    }

    return $null
}

$resolvedFlutterSdkPath = Resolve-FlutterSdkPath -OverridePath $FlutterSdkPath

if (-not $resolvedFlutterSdkPath) {
    throw 'Could not find Flutter SDK. Set dart.flutterSdkPath in VS Code settings or pass -FlutterSdkPath C:\path\to\flutter.'
}

$resolvedFlutterSdkPath = (Resolve-Path -LiteralPath $resolvedFlutterSdkPath).Path
$flutterBin = Join-Path $resolvedFlutterSdkPath 'bin'
$dartBin = Join-Path $resolvedFlutterSdkPath 'bin\cache\dart-sdk\bin'

if (-not (Test-Path -LiteralPath (Join-Path $flutterBin 'flutter.bat'))) {
    throw "Flutter executable was not found at '$flutterBin'."
}

$env:FLUTTER_ROOT = $resolvedFlutterSdkPath
Add-PathEntry -Path $flutterBin
Add-PathEntry -Path $dartBin

Write-Host "Flutter SDK: $env:FLUTTER_ROOT"
Write-Host "flutter: $((Get-Command flutter).Source)"
Write-Host "dart: $((Get-Command dart -ErrorAction SilentlyContinue).Source)"

if ($Run) {
    Invoke-Expression $Run
    exit $LASTEXITCODE
}
