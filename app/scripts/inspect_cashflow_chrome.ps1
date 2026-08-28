param(
    [int]$DebugPort = 9223
)

$endpoint = "http://127.0.0.1:$DebugPort/json"
$targets = Invoke-RestMethod -Uri $endpoint -TimeoutSec 5

$targets |
    Where-Object { $_.type -eq 'page' -and $_.url -notlike 'chrome-extension://*' } |
    Select-Object id, title, url, webSocketDebuggerUrl
