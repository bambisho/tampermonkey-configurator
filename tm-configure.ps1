# =====================================================================
#  Tampermonkey Configurator (Native Install Edition, v20 - 3 steps)
# ---------------------------------------------------------------------
#  Same command runs ALL steps automatically (it remembers where it is):
#
#    STEP 1: Clean install of Tampermonkey
#      - Removes old provisioning policy and force-install remnants
#      - Deep wipes old TM files + storage from all Chrome profiles
#      - Sets force-install policy so Chrome downloads TM fresh
#      -> Then YOU: open Chrome, wait for TM to appear, enable
#         Developer mode + Allow user scripts,
#         and run the SAME command again.
#
#    STEP 2: Install the user script (Tampermonkey native flow)
#      - Opens the combined .user.js file in Chrome
#      - Tampermonkey shows its install page
#      -> YOU: click "Install" (1 click), then run the SAME command again.
#
#    STEP 3: Apply Tampermonkey settings
#      - Automates the TM settings page via Chrome DevTools Protocol
#        (selects Advanced mode + Always update interval like a human)
#      - Restarts Chrome normally afterwards
#      -> YOU: verify settings in the TM dashboard.
#
#  Requires: Run as Administrator, Windows PowerShell 5.1
# =====================================================================
param(
  [string]$ExtId = "dhdgffkkebhmkfjojejmpbldmpobfkfo",  # TM stable
  [ValidateSet("auto","1","2","3","reset")]
  [string]$Step = "auto"
)

$ErrorActionPreference = "Stop"

function Say($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color }

# ---------------------------------------------------------------------
# Admin check
# ---------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Say "This script requires Administrator privileges to configure Chrome policies." Red
    Say "Please right-click PowerShell and select 'Run as Administrator', then run the script again." Yellow
    exit 1
}

# ---------------------------------------------------------------------
# Shared paths / helpers
# ---------------------------------------------------------------------
$stateFile      = "C:\ProgramData\tm-configurator-state.txt"
$forceListPath  = "HKLM:\Software\Policies\Google\Chrome\ExtensionInstallForcelist"
$repoRaw        = "https://raw.githubusercontent.com/bambisho/tampermonkey-configurator/master"
$scriptUrls     = @(
    "$repoRaw/scripts/amazon-suite.user.js"
)

function Close-Chrome {
    Say "Closing Chrome..." Cyan
    Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Process chrome -ErrorAction SilentlyContinue) -and ((Get-Date) -lt $deadline)) {
        Start-Sleep -Milliseconds 500
    }
}

function Get-ChromeProfiles($userDataDir) {
    @("Default") + (Get-ChildItem $userDataDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "Profile *" } | ForEach-Object { $_.Name })
}

function Wipe-TmStorage {
    $usersDirs = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
    foreach ($userDir in $usersDirs) {
        $userDataDir = Join-Path $userDir.FullName "AppData\Local\Google\Chrome\User Data"
        if (-not (Test-Path $userDataDir)) { continue }
        foreach ($p in (Get-ChromeProfiles $userDataDir)) {
            foreach ($sub in @("Local Extension Settings", "Sync Extension Settings", "Managed Extension Settings", "IndexedDB")) {
                $base = Join-Path $userDataDir "$p\$sub"
                if (-not (Test-Path $base)) { continue }
                Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "*$ExtId*" } |
                    ForEach-Object {
                        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        Say "  -> Cleared $sub in $($userDir.Name)\$p" Green
                    }
            }
        }
    }
}

function Wipe-TmFiles {
    Say "Deep wiping Tampermonkey extension files..." Cyan
    $usersDirs = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
    foreach ($userDir in $usersDirs) {
        $userDataDir = Join-Path $userDir.FullName "AppData\Local\Google\Chrome\User Data"
        if (-not (Test-Path $userDataDir)) { continue }
        foreach ($p in (Get-ChromeProfiles $userDataDir)) {
            $extFolder = Join-Path $userDataDir "$p\Extensions\$ExtId"
            if (Test-Path $extFolder) {
                Remove-Item $extFolder -Recurse -Force -ErrorAction SilentlyContinue
                Say "  -> Removed TM extension files from $($userDir.Name)\$p" Green
            }
            foreach ($extra in @("Extension Rules\$ExtId", "Extension Scripts\$ExtId", "Extension State\$ExtId")) {
                $extraPath = Join-Path $userDataDir "$p\$extra"
                if (Test-Path $extraPath) {
                    Remove-Item $extraPath -Recurse -Force -ErrorAction SilentlyContinue
                    Say "  -> Cleared $extra in $($userDir.Name)\$p" Green
                }
            }
        }
    }
}

# ---------------------------------------------------------------------
# Determine which step to run
# ---------------------------------------------------------------------
if ($Step -eq "reset") {
    Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
    Say "State reset. Next run will start at STEP 1." Yellow
    exit 0
}

if ($Step -eq "auto") {
    $state = if (Test-Path $stateFile) { Get-Content $stateFile -ErrorAction SilentlyContinue } else { "" }
    if ($state -eq "step2-done") { $Step = "3" }
    elseif ($state -eq "step1-done") { $Step = "2" }
    else { $Step = "1" }
}

# =====================================================================
# STEP 1: Clean install of Tampermonkey (no scripts yet)
# =====================================================================
if ($Step -eq "1") {
    Say "=========================================" Cyan
    Say " STEP 1 of 3: Clean Tampermonkey install " Cyan
    Say "=========================================" Cyan

    Close-Chrome

    # Remove any previous provisioning policy - we now use TM's native
    # install flow instead of managed-storage jsonImport.
    Say "Removing old provisioning policy..." Cyan
    Remove-Item "HKLM:\Software\Policies\Google\Chrome\3rdparty\extensions\$ExtId" -Recurse -Force -ErrorAction SilentlyContinue

    # Deep wipe: extension files + all storage
    Wipe-TmFiles
    Wipe-TmStorage

    # Force-install policy so Chrome downloads TM fresh from the Web Store
    if (-not (Test-Path $forceListPath)) {
        New-Item -Path $forceListPath -Force | Out-Null
    }
    $installValue = "$ExtId;https://clients2.google.com/service/update2/crx"
    New-ItemProperty -Path $forceListPath -Name "1" -Value $installValue -PropertyType String -Force | Out-Null
    Say "  -> Set ExtensionInstallForcelist policy to install Tampermonkey." Green

    # Remember that step 1 is done
    Set-Content -Path $stateFile -Value "step1-done" -Force

    Say ""
    Say "STEP 1 COMPLETE!" Green
    Say ""
    Say "NOW DO THIS:" Yellow
    Say "  1. Open Chrome and wait ~30 seconds until Tampermonkey appears" Yellow
    Say "     in chrome://extensions (Chrome downloads it automatically)." Yellow
    Say "  2. While you are there: turn ON 'Developer mode' (top right)," Yellow
    Say "     open Tampermonkey 'Details' and turn ON 'Allow user scripts'." Yellow
    Say "  3. Run this SAME command again to do STEP 2:" Yellow
    Say ""
    Say "     irm https://raw.githubusercontent.com/bambisho/tampermonkey-configurator/master/tm-configure.ps1 | iex" Cyan
    Say ""
    exit 0
}

# =====================================================================
# STEP 2: Install user scripts via Tampermonkey's NATIVE install flow
# =====================================================================
if ($Step -eq "2") {
    Say "================================================" Cyan
    Say " STEP 2 of 3: Install user scripts (native flow) " Cyan
    Say "================================================" Cyan

    # Sanity check: is TM actually installed?
    $tmFound = $false
    $usersDirs = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
    foreach ($userDir in $usersDirs) {
        $userDataDir = Join-Path $userDir.FullName "AppData\Local\Google\Chrome\User Data"
        if (-not (Test-Path $userDataDir)) { continue }
        foreach ($p in (Get-ChromeProfiles $userDataDir)) {
            if (Test-Path (Join-Path $userDataDir "$p\Extensions\$ExtId")) { $tmFound = $true }
        }
    }
    if (-not $tmFound) {
        Say "WARNING: Tampermonkey extension files were not found on disk." Red
        Say "Did you open Chrome after Step 1 and wait for Tampermonkey to install?" Yellow
        Say "If not: open Chrome, wait ~30s for Tampermonkey to appear," Yellow
        Say "then run this command again." Yellow
        Say ""
        Say "Continuing anyway..." Cyan
    }

    # Open each .user.js URL in Chrome. Tampermonkey intercepts the
    # navigation and shows its native install page - just click Install.
    $cacheBuster = Get-Date -UFormat "%s"
    Say "Opening script install pages in Chrome..." Cyan
    foreach ($u in $scriptUrls) {
        Start-Process "chrome.exe" "$u`?t=$cacheBuster"
        Start-Sleep -Seconds 2
    }

    # Remember that step 2 is done
    Set-Content -Path $stateFile -Value "step2-done" -Force

    Say ""
    Say "STEP 2 COMPLETE!" Green
    Say ""
    Say "NOW DO THIS:" Yellow
    Say "  1. Chrome just opened a tab showing a Tampermonkey install page." Yellow
    Say "  2. Click the 'Install' button (1 click)." Yellow
    Say "  3. Run this SAME command again to do STEP 3 (apply TM settings):" Yellow
    Say ""
    Say "     irm https://raw.githubusercontent.com/bambisho/tampermonkey-configurator/master/tm-configure.ps1 | iex" Cyan
    Say ""
    Say "  If the tab shows raw code instead of an install page, make sure" Yellow
    Say "  'Allow user scripts' is ON for Tampermonkey in chrome://extensions," Yellow
    Say "  then re-run this command." Yellow
    Say ""
    exit 0
}

# =====================================================================
# STEP 3: Apply Tampermonkey settings via Chrome DevTools Protocol.
# This automates the TM settings page exactly like a human would,
# which is TM's fully supported path - no policies, no hashes.
# =====================================================================
if ($Step -eq "3") {
    Say "==========================================" Cyan
    Say " STEP 3 of 3: Apply Tampermonkey settings " Cyan
    Say "==========================================" Cyan

    $DebugPort = 9333

    # Remove any old managed-storage policy so it cannot interfere
    Remove-Item "HKLM:\Software\Policies\Google\Chrome\3rdparty\extensions\$ExtId" -Recurse -Force -ErrorAction SilentlyContinue

    Close-Chrome

    Say "Starting Chrome with remote debugging (port $DebugPort)..." Cyan
    $optionsUrl = "chrome-extension://$ExtId/options.html#nav=settings"
    Start-Process "chrome.exe" "--remote-debugging-port=$DebugPort --remote-allow-origins=* `"$optionsUrl`""
    Start-Sleep -Seconds 6

    # Find the options page target via the CDP HTTP endpoint
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
        Say "Make sure Tampermonkey is installed (Steps 1+2), then run this again." Yellow
        exit 1
    }
    Say "  -> Found Tampermonkey options page." Green

    # JS that flips the settings on the TM options page
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
  r.push(setSelect('configMode', 100));
  await new Promise(res => setTimeout(res, 2000));
  r.push(setSelect('external_update_interval', 1));
  await new Promise(res => setTimeout(res, 1500));
  return r.join(' | ');
})()
'@

    function Invoke-CdpEval {
        param([string]$WsUrl, [string]$Expression)
        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $ct = [System.Threading.CancellationToken]::None
        $ws.ConnectAsync([Uri]$WsUrl, $ct).Wait()
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
            try {
                $obj = $sb.ToString() | ConvertFrom-Json
                if ($obj.id -eq 1) { $result = $obj }
            } catch { }
        }
        $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", $ct).Wait()
        return $result
    }

    Say "Applying Tampermonkey settings..." Cyan
    $resp = Invoke-CdpEval -WsUrl $wsUrl -Expression $js

    $applied = $false
    if ($resp -and $resp.result.result.value) {
        Say "  -> Result: $($resp.result.result.value)" Green
        if ($resp.result.result.value -like "OK:*") { $applied = $true }
    } else {
        Say "WARNING: No confirmation received. Settings may not have applied." Yellow
    }

    Start-Sleep -Seconds 2

    # Clear state so a future run starts over at Step 1
    Remove-Item $stateFile -Force -ErrorAction SilentlyContinue

    # Restart Chrome normally (without debug port) on the settings page
    Say "Restarting Chrome normally..." Cyan
    Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process "chrome.exe" $optionsUrl

    Say ""
    Say "STEP 3 COMPLETE!" Green
    Say ""
    Say "Chrome reopened on the Tampermonkey settings page so you can verify:" Yellow
    Say "  - Config mode should be 'Advanced'" Yellow
    Say "  - Externals: Update Interval should be 'Always'" Yellow
    Say ""
    Say "Check the panels:" Yellow
    Say "  - Amazon UK/DE pages -> green dot bottom-right + address button" Yellow
    Say "  - delta.alliance.codes -> blue dot bottom-left + FILL buttons" Yellow
    Say ""
    exit 0
}
