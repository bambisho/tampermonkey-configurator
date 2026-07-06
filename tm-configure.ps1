# =====================================================================
#  Tampermonkey Configurator (Native Install Edition, v19 - 3 steps)
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
#      - Sets a settings-only managed storage policy (no scripts touched)
#      - Restarts Chrome so TM picks up the new settings
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
# STEP 3: Apply Tampermonkey settings (settings-only policy, no scripts)
# =====================================================================
if ($Step -eq "3") {
    Say "==========================================" Cyan
    Say " STEP 3 of 3: Apply Tampermonkey settings " Cyan
    Say "==========================================" Cyan

    Close-Chrome

    # Settings-only provisioning JSON (does NOT contain scripts, so your
    # installed scripts are untouched).
    $cacheBuster = Get-Date -UFormat "%s"
    $jsonUrl = "$repoRaw/tm-settings.json?t=$cacheBuster"
    # Tampermonkey's STRUCTURAL hash of tm-settings.json content.
    $jsonHash = "1:ad0480752ee8b32055ccb59c9530f38e695fa1d2fa3b05b67ebff90473ca36f5"

    $managedStoragePaths = @(
        "HKLM:\Software\Policies\Google\Chrome\3rdparty\extensions\$ExtId\policy\jsonImport\1",
        "HKLM:\Software\Policies\Google\Chrome\3rdparty\extensions\$ExtId\jsonImport\1"
    )
    foreach ($msp in $managedStoragePaths) {
        if (-not (Test-Path $msp)) { New-Item -Path $msp -Force | Out-Null }
        New-ItemProperty -Path $msp -Name "url" -Value $jsonUrl -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $msp -Name "hash" -Value $jsonHash -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $msp -Name "haltOnError" -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $msp -Name "installAsSystemScripts" -Value 0 -PropertyType DWord -Force | Out-Null
    }
    Say "  -> Set settings-only Managed Storage policy." Green

    # Clear state so a future run starts over at Step 1
    Remove-Item $stateFile -Force -ErrorAction SilentlyContinue

    # Reopen Chrome so TM picks up the settings policy
    Start-Process "chrome.exe" "chrome://extensions"

    Say ""
    Say "STEP 3 COMPLETE!" Green
    Say ""
    Say "NOW DO THIS:" Yellow
    Say "  1. Chrome just reopened. Wait ~20 seconds." Yellow
    Say "  2. Open the Tampermonkey dashboard -> Settings tab." Yellow
    Say "     Config mode should now be 'Advanced'." Yellow
    Say "  3. Check the panels:" Yellow
    Say "     - Amazon UK/DE pages -> green dot bottom-right + address button" Yellow
    Say "     - delta.alliance.codes -> blue dot bottom-left + FILL buttons" Yellow
    Say ""
    exit 0
}
