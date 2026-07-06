# =====================================================================
#  Apply Tampermonkey settings via Chrome DevTools Protocol (CDP)
#  - Launches Chrome with remote debugging on a local port
#  - Opens the TM options page (Settings tab)
#  - Selects Config mode = Advanced, External Update Interval = Always
#  - No extra software required (uses built-in .NET WebSocket)
#  Requires: Windows PowerShell 5.1
# =====================================================================
param(
  [string]$ExtId = "dhdgffkkebhmkfjojejmpbldmpobfkfo",
  [int]$DebugPort = 9333
)

$ErrorActionPreference = "Stop"
function Say($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color }

# ---------------------------------------------------------------------
# 1. Close Chrome, then relaunch with remote debugging enabled
# ---------------------------------------------------------------------
Say "Closing Chrome..." Cyan
Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

Say "Starting Chrome with remote debugging (port $DebugPort)..." Cyan
$optionsUrl = "chrome-extension://$ExtId/options.html#nav=settings"
Start-Process "chrome.exe" "--remote-debugging-port=$DebugPort --remote-allow-origins=* `"$optionsUrl`""
Start-Sleep -Seconds 6

# ---------------------------------------------------------------------
# 2. Find the options page target via the CDP HTTP endpoint
# ---------------------------------------------------------------------
$wsUrl = $null
for ($i = 0; $i -lt 15 -and -not $wsUrl; $i++) {
    try {
        $targets = Invoke-RestMethod "http://127.0.0.1:$DebugPort/json/list"
        $t = $targets | Where-Object { $_.url -like "chrome-extension://$ExtId/options.html*" } | Select-Object -First 1
        if ($t) { $wsUrl = $t.webSocketDebuggerUrl }
    } catch { }
    if (-not $wsUrl) { Start-Sleep -Seconds 1 }
}
if (-not $wsUrl) {
    Say "ERROR: Could not find the Tampermonkey options page in Chrome." Red
    Say "Make sure Tampermonkey is installed, then run this again." Yellow
    exit 1
}
Say "  -> Found Tampermonkey options page." Green

# ---------------------------------------------------------------------
# 3. Connect via WebSocket and evaluate JS that flips the settings
# ---------------------------------------------------------------------
$js = @'
(async () => {
  const dec = (id) => {
    const m = id.match(/^(?:select|input)_(.+?)(?:_dd|_cb)?$/);
    if (!m) return null;
    try {
      let b = m[1].replace(/-/g, '+').replace(/_/g, '/');
      while (b.length % 4) b += '=';
      return atob(b);
    } catch (e) { return null; }
  };
  const setSelect = (key, value) => {
    const sel = [...document.querySelectorAll('select')].find(s => {
      const d = dec(s.id) || '';
      return d.endsWith('_' + key) || d === key;
    });
    if (!sel) return 'NOTFOUND:' + key;
    sel.value = String(value);
    sel.dispatchEvent(new Event('change', { bubbles: true }));
    return 'OK:' + key + '=' + sel.value;
  };
  const r = [];
  r.push(setSelect('configMode', 100));           // Advanced
  await new Promise(res => setTimeout(res, 2000)); // wait for UI rebuild
  r.push(setSelect('external_update_interval', 1)); // Always
  await new Promise(res => setTimeout(res, 1500)); // let TM persist
  return r.join(' | ');
})()
'@

Add-Type -AssemblyName System.Net.WebSockets.Client -ErrorAction SilentlyContinue

function Invoke-CdpEval {
    param([string]$WsUrl, [string]$Expression)

    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ct = [System.Threading.CancellationToken]::None
    $uri = [Uri]$WsUrl
    $ws.ConnectAsync($uri, $ct).Wait()

    $cmd = @{
        id = 1
        method = "Runtime.evaluate"
        params = @{
            expression = $Expression
            awaitPromise = $true
            returnByValue = $true
        }
    } | ConvertTo-Json -Depth 6 -Compress

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($cmd)
    $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

    # Receive until we get the response with id=1
    $buffer = New-Object byte[] 65536
    $deadline = (Get-Date).AddSeconds(30)
    $result = $null
    while (-not $result -and (Get-Date) -lt $deadline) {
        $sb = New-Object System.Text.StringBuilder
        do {
            $rseg = New-Object System.ArraySegment[byte] -ArgumentList @(,$buffer)
            $task = $ws.ReceiveAsync($rseg, $ct)
            $task.Wait()
            $res = $task.Result
            [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $res.Count))
        } while (-not $res.EndOfMessage)
        $msg = $sb.ToString()
        try {
            $obj = $msg | ConvertFrom-Json
            if ($obj.id -eq 1) { $result = $obj }
        } catch { }
    }
    $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", $ct).Wait()
    return $result
}

Say "Applying Tampermonkey settings..." Cyan
$resp = Invoke-CdpEval -WsUrl $wsUrl -Expression $js

if ($resp -and $resp.result.result.value) {
    Say "  -> Result: $($resp.result.result.value)" Green
} else {
    Say "WARNING: No confirmation received. Settings may not have applied." Yellow
    if ($resp) { Say ($resp | ConvertTo-Json -Depth 6) Gray }
}

Start-Sleep -Seconds 2

# ---------------------------------------------------------------------
# 4. Restart Chrome normally (without debug port)
# ---------------------------------------------------------------------
Say "Restarting Chrome normally..." Cyan
Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process "chrome.exe" "chrome-extension://$ExtId/options.html#nav=settings"

Say ""
Say "SETTINGS APPLIED!" Green
Say "Chrome reopened on the Tampermonkey settings page so you can verify:" Yellow
Say "  - Config mode should be 'Advanced'" Yellow
Say "  - Externals: Update Interval should be 'Always'" Yellow
Say ""
