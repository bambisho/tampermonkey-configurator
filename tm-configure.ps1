# =====================================================================
#  Tampermonkey Configurator (zero-install, Chrome, stock Windows)
# ---------------------------------------------------------------------
#  Applies:
#    1. chrome://extensions  -> Developer mode = ON
#    2. Tampermonkey details -> Allow user scripts = ON
#    3. TM settings          -> Config mode = Advanced
#    4. TM settings          -> Externals / Update Interval = Always
#    5. TM settings          -> Security / Page Filter Mode = Disabled
#    6. Presses the section Save button
#
#  Requires nothing but Windows PowerShell 5.1 (built into Windows 10/11)
#  and Google Chrome. Run via run.cmd or:
#    powershell -ExecutionPolicy Bypass -File tm-configure.ps1
#
#  Optional parameters:
#    -ChromePath "C:\...\chrome.exe"   (auto-detected if omitted)
#    -ProfileDir "C:\Users\X\AppData\Local\Google\Chrome\User Data"
#    -ExtId      "dhdgffkkebhmkfjojejmpbldmpobfkfo"  (TM stable)
# =====================================================================
Invoke-Command -ScriptBlock {
param(
  [string]$ChromePath = "",
  [string]$ProfileDir = "",
  [string]$ExtId = "dhdgffkkebhmkfjojejmpbldmpobfkfo",
  [int]$Port = 9333
)

$ErrorActionPreference = "Stop"
$ok = $true

function Say($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color }

# ------------------------------------------------ locate chrome
if (-not $ChromePath) {
  $candidates = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  )
  $ChromePath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $ChromePath -or -not (Test-Path $ChromePath)) {
  Say "Chrome was not found. Pass -ChromePath 'C:\...\chrome.exe'" Red
  exit 1
}
if (-not $ProfileDir) { $ProfileDir = "$env:LOCALAPPDATA\Google\Chrome\User Data" }

Say "Chrome  : $ChromePath"
Say "Profile : $ProfileDir"
Say "Ext ID  : $ExtId"
Say ""

# ------------------------------------------------ ensure chrome is closed
$running = Get-Process chrome -ErrorAction SilentlyContinue
if ($running) {
  Say "Chrome is running. It must be closed to apply settings." Yellow
  $ans = Read-Host "Close Chrome now? (y/n)"
  if ($ans -match '^[yY]') {
    Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
  } else {
    Say "Aborted. Close Chrome and run again." Red
    exit 1
  }
}

# ------------------------------------------------ start chrome with CDP
Say "Starting Chrome with automation port..."
$chromeArgs = @(
  "--remote-debugging-port=$Port",
  "--remote-allow-origins=*",
  "--user-data-dir=`"$ProfileDir`"",
  "--no-first-run",
  "--no-default-browser-check",
  "--disable-features=MediaRouter",
  "--window-size=1200,900"
)
if ($env:TM_TEST_EXTRA) { $chromeArgs += ($env:TM_TEST_EXTRA -split ' ') }
$chromeArgs += "about:blank"
$proc = Start-Process -FilePath $ChromePath -ArgumentList $chromeArgs -PassThru

# wait for the DevTools endpoint
$targets = $null
foreach ($i in 1..30) {
  Start-Sleep -Milliseconds 700
  try {
    $targets = Invoke-RestMethod "http://127.0.0.1:$Port/json" -TimeoutSec 2
    if ($targets) { break }
  } catch {}
}
if (-not $targets) {
  Say "Could not reach Chrome's automation port. Something else may be using port $Port." Red
  exit 1
}

# ------------------------------------------------ minimal CDP client (WebSocket)
Add-Type -AssemblyName System.Net.WebSockets.Client -ErrorAction SilentlyContinue

$script:msgId = 0
function Connect-Tab([string]$wsUrl) {
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(30)
  $ct = [Threading.CancellationToken]::None
  $ws.ConnectAsync([Uri]$wsUrl, $ct).Wait()
  return $ws
}
function Send-Cdp($ws, [string]$method, $params) {
  $script:msgId++
  $payload = @{ id = $script:msgId; method = $method } 
  if ($params) { $payload.params = $params }
  $json = $payload | ConvertTo-Json -Depth 10 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $seg = New-Object ArraySegment[byte] -ArgumentList @(,$bytes)
  $ct = [Threading.CancellationToken]::None
  $ws.SendAsync($seg, [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
  # read until we get the reply with our id
  $buf = New-Object byte[] 262144
  $deadline = (Get-Date).AddSeconds(20)
  while ((Get-Date) -lt $deadline) {
    $sb = New-Object Text.StringBuilder
    do {
      $seg2 = New-Object ArraySegment[byte] -ArgumentList @(,$buf)
      $res = $ws.ReceiveAsync($seg2, $ct).GetAwaiter().GetResult()
      [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $res.Count))
    } while (-not $res.EndOfMessage)
    $obj = $null
    try { $obj = $sb.ToString() | ConvertFrom-Json } catch { continue }
    if ($obj.id -eq $script:msgId) { return $obj }
  }
  throw "CDP timeout waiting for reply to $method"
}
function Eval-Js($ws, [string]$expr) {
  $r = Send-Cdp $ws "Runtime.evaluate" @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { throw ("JS error: " + $r.result.exceptionDetails.text) }
  return $r.result.result.value
}
function Open-Tab([string]$url) {
  $enc = [Uri]::EscapeDataString($url)
  $t = Invoke-RestMethod -Method Put "http://127.0.0.1:$Port/json/new?$enc" -TimeoutSec 5
  return $t
}
function Navigate($ws, [string]$url) {
  [void](Send-Cdp $ws "Page.navigate" @{ url = $url })
  Start-Sleep -Seconds 2
}

# use the first page target
$page = $targets | Where-Object { $_.type -eq "page" } | Select-Object -First 1
$ws = Connect-Tab $page.webSocketDebuggerUrl
[void](Send-Cdp $ws "Page.enable" $null)

# ============================================================ STEP 1+2:
# Developer mode + Allow user scripts (chrome://extensions)
Say "Step 1: Developer mode..." Cyan
Navigate $ws "chrome://extensions/"
Start-Sleep -Seconds 1
$r = Eval-Js $ws @"
(() => {
  const mgr = document.querySelector('extensions-manager');
  const tb = mgr && mgr.shadowRoot.querySelector('extensions-toolbar');
  const dev = tb && tb.shadowRoot.querySelector('#devMode');
  if (!dev) return 'FAIL: toggle not found';
  if (dev.checked) return 'already on';
  dev.click();
  return 'enabled';
})()
"@
if ($r -like 'FAIL*') { $ok = $false; Say "  Developer mode: $r" Red } else { Say "  Developer mode: $r" Green }
Start-Sleep -Seconds 1

Say "Step 2: Allow user scripts..." Cyan
Navigate $ws "chrome://extensions/?id=$ExtId"
Start-Sleep -Seconds 1
$r = Eval-Js $ws @"
(() => {
  const mgr = document.querySelector('extensions-manager');
  const detail = mgr && mgr.shadowRoot.querySelector('extensions-detail-view');
  if (!detail) return 'FAIL: Tampermonkey not found in this profile';
  const row = detail.shadowRoot.querySelector('#allow-user-scripts');
  if (!row) return 'skipped (toggle not present in this Chrome version; Developer mode covers it)';
  const crt = row.shadowRoot ? row.shadowRoot.querySelector('cr-toggle') : row.querySelector('cr-toggle');
  if (!crt) return 'FAIL: toggle control not found';
  if (crt.checked) return 'already on';
  crt.click();
  return 'enabled';
})()
"@
if ($r -like 'FAIL*') { $ok = $false; Say "  Allow user scripts: $r" Red } else { Say "  Allow user scripts: $r" Green }
Start-Sleep -Seconds 1

# ============================================================ STEP 3-6:
# Tampermonkey settings page
Say "Step 3-6: Tampermonkey settings..." Cyan
Navigate $ws "chrome-extension://$ExtId/options.html#nav=settings"
Start-Sleep -Seconds 3

$helpers = @"
  var __dec = (id) => {
    const m = id.match(/^(?:select|input)_(.+?)(?:_dd|_cb)?`$/);
    if (!m) return null;
    try {
      let b = m[1].replace(/-/g, '+').replace(/_/g, '/');
      while (b.length % 4) b += '=';
      return atob(b);
    } catch (e) { return null; }
  };
  var __findSelect = (key) => [...document.querySelectorAll('select')].find(s => {
    const d = __dec(s.id) || '';
    return d === key || d.endsWith('_' + key);
  });
  var __set = (key, value) => {
    const sel = __findSelect(key);
    if (!sel) return 'FAIL: ' + key + ' not found';
    const opts = [...sel.options].map(o => ({ v: o.value, t: o.textContent.trim() }));
    let t = opts.find(o => o.v === String(value)) || opts.find(o => o.t.toLowerCase() === String(value).toLowerCase());
    if (!t) return 'FAIL: value ' + value + ' not in options';
    if (sel.value === t.v) return key + ': already set (' + t.t + ')';
    sel.value = t.v;
    sel.dispatchEvent(new Event('change', { bubbles: true }));
    return key + ': set to ' + t.t;
  };
"@

$sanity = Eval-Js $ws "document.querySelectorAll('select').length"
if ([int]$sanity -lt 2) {
  Say "  FAIL: Tampermonkey settings page did not load. Is Tampermonkey installed?" Red
  $ok = $false
} else {
  $r = Eval-Js $ws "$helpers __set('configMode', 100)"
  if ($r -like 'FAIL*') { $ok = $false; Say "  $r" Red } else { Say "  $r" Green }
  Start-Sleep -Seconds 2

  $r = Eval-Js $ws "$helpers __set('external_update_interval', 'Always')"
  if ($r -like 'FAIL*') { $ok = $false; Say "  $r" Red } else { Say "  $r" Green }
  Start-Sleep -Seconds 1

  $r = Eval-Js $ws "$helpers __set('page_filter_mode', 'Disabled')"
  if ($r -like 'FAIL*') { $ok = $false; Say "  $r" Red } else { Say "  $r" Green }
  Start-Sleep -Seconds 1

  # press Save buttons (commits Security section changes).
  # Retry a few times: the button enables asynchronously after the change event.
  $saved = $false
  foreach ($try in 1..5) {
    Start-Sleep -Seconds 1
    $r = Eval-Js $ws @"
(() => {
  let n = 0, pending = 0;
  document.querySelectorAll('input[type=button], input[type=submit], button').forEach(b => {
    const label = (b.value || b.textContent || '').trim().toLowerCase();
    if (label === 'save') {
      if (!b.disabled) { b.click(); n++; } else { pending++; }
    }
  });
  return JSON.stringify({ clicked: n, stillDisabled: pending });
})()
"@
    $obj = $r | ConvertFrom-Json
    if ($obj.clicked -gt 0) { Say "  Save buttons clicked: $($obj.clicked)" Green; $saved = $true; break }
    if ($obj.stillDisabled -eq 0 -or $try -ge 3) { break }
    if ($try -eq 1) { Say "  Waiting for Save button to enable..." Gray }
  }
  if (-not $saved) { Say "  Save: nothing pending (already saved or no changes needed)" Green }
  Start-Sleep -Seconds 2

  # ------------------------------------------------ verify (reload page)
  Say ""
  Say "Verifying..." Cyan
  Navigate $ws "chrome-extension://$ExtId/options.html#nav=settings"
  Start-Sleep -Seconds 3
  $v = Eval-Js $ws @"
$helpers
(() => {
  const get = (k) => {
    const s = __findSelect(k);
    return s ? s.options[s.selectedIndex].textContent.trim() : 'NOT VISIBLE';
  };
  return 'configMode=' + get('configMode') +
    ' | external_update_interval=' + get('external_update_interval') +
    ' | page_filter_mode=' + get('page_filter_mode');
})()
"@
  Say "  $v" Yellow
  if ($v -notmatch 'external_update_interval=Always' -or $v -notmatch 'page_filter_mode=Disabled') { $ok = $false }
}

# ------------------------------------------------ close chrome
try { $ws.Dispose() } catch {}
Start-Sleep -Seconds 1
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue

Say ""
if ($ok) { Say "DONE. All settings applied and verified." Green } else { Say "FINISHED WITH ERRORS - see messages above." Red }
if (-not $ok) { throw "Configuration failed" }
}
