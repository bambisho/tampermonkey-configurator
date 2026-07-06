# =====================================================================
#  Tampermonkey Configurator (v22 - single run)
# ---------------------------------------------------------------------
#  ONE run does everything:
#
#    1. Closes Chrome, removes old policies and TM leftovers
#    2. Sets force-install policy so Chrome downloads TM fresh
#    3. Opens Chrome and WAITS until Tampermonkey is downloaded
#    4. Opens the combined user script install page
#       -> YOU: enable Developer mode + 'Allow user scripts' when asked,
#          then click "Install" on the script tab. Done.
#
#  TM settings (config mode etc.) are NOT touched - set them manually.
#
#  Requires: Run as Administrator, Windows PowerShell 5.1
# =====================================================================
param(
  [string]$ExtId = "dhdgffkkebhmkfjojejmpbldmpobfkfo"  # TM stable
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
$forceListPath  = "HKLM:\Software\Policies\Google\Chrome\ExtensionInstallForcelist"
$repoRaw        = "https://raw.githubusercontent.com/bambisho/tampermonkey-configurator/master"
$scriptUrl      = "$repoRaw/scripts/amazon-suite.user.js"

function Find-Chrome {
    # 1. Registry App Paths (most reliable)
    foreach ($rk in @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"
    )) {
        try {
            $v = (Get-ItemProperty -Path $rk -ErrorAction Stop)."(default)"
            if ($v -and (Test-Path $v)) { return $v }
        } catch { }
    }
    # 2. Known install locations
    foreach ($p in @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
    )) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    # 3. PATH
    $cmd = Get-Command chrome.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-ChromeProfiles($userDataDir) {
    @("Default") + (Get-ChildItem $userDataDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "Profile *" } | ForEach-Object { $_.Name })
}

function Test-TmInstalled {
    $usersDirs = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
    foreach ($userDir in $usersDirs) {
        $userDataDir = Join-Path $userDir.FullName "AppData\Local\Google\Chrome\User Data"
        if (-not (Test-Path $userDataDir)) { continue }
        foreach ($p in (Get-ChromeProfiles $userDataDir)) {
            $extFolder = Join-Path $userDataDir "$p\Extensions\$ExtId"
            if (Test-Path $extFolder) {
                # Make sure a version folder with a manifest exists (download finished)
                $manifest = Get-ChildItem $extFolder -Recurse -Filter "manifest.json" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($manifest) { return $true }
            }
        }
    }
    return $false
}

function Close-Chrome {
    Say "Closing Chrome..." Cyan
    Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Process chrome -ErrorAction SilentlyContinue) -and ((Get-Date) -lt $deadline)) {
        Start-Sleep -Milliseconds 500
    }
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

# =====================================================================
# SINGLE RUN: everything in one go
# =====================================================================
Say "==============================================" Cyan
Say " Tampermonkey Configurator - Single-Run Setup " Cyan
Say "==============================================" Cyan

# --- Locate Chrome first (abort early if not found) ---
$chromeExe = Find-Chrome
if (-not $chromeExe) {
    Say "ERROR: Could not find chrome.exe on this system." Red
    Say "Install Google Chrome first, then run this script again." Yellow
    exit 1
}
Say "Found Chrome: $chromeExe" Green

# --- Phase 1: wipe + force-install policy ---
Close-Chrome

Say "Removing old provisioning policies..." Cyan
Remove-Item "HKLM:\Software\Policies\Google\Chrome\3rdparty\extensions\$ExtId" -Recurse -Force -ErrorAction SilentlyContinue

Wipe-TmFiles
Wipe-TmStorage

if (-not (Test-Path $forceListPath)) {
    New-Item -Path $forceListPath -Force | Out-Null
}
$installValue = "$ExtId;https://clients2.google.com/service/update2/crx"
New-ItemProperty -Path $forceListPath -Name "1" -Value $installValue -PropertyType String -Force | Out-Null
Say "  -> Set ExtensionInstallForcelist policy to install Tampermonkey." Green

# --- Phase 2: open Chrome and wait for TM to be downloaded ---
Say ""
Say "Opening Chrome and waiting for Tampermonkey to install..." Cyan
Start-Process $chromeExe "chrome://extensions"

$deadline = (Get-Date).AddSeconds(120)
$tmReady = $false
while (-not $tmReady -and ((Get-Date) -lt $deadline)) {
    Start-Sleep -Seconds 3
    $tmReady = Test-TmInstalled
    Write-Host "." -NoNewline
}
Write-Host ""

if ($tmReady) {
    Say "  -> Tampermonkey is installed!" Green
} else {
    Say "WARNING: Tampermonkey did not appear within 2 minutes." Yellow
    Say "Check your internet connection. Continuing anyway..." Yellow
}

# Give TM a few seconds to finish its first-run initialization
Start-Sleep -Seconds 5

# --- Phase 3: open the user script install page ---
$cacheBuster = Get-Date -UFormat "%s"
Say "Opening the script install page in Chrome..." Cyan
Start-Process $chromeExe "$scriptUrl`?t=$cacheBuster"

Say ""
Say "ALL AUTOMATED STEPS COMPLETE!" Green
Say ""
Say "NOW DO THIS (in the Chrome window that just opened):" Yellow
Say "  1. Go to chrome://extensions (tab is already open):" Yellow
Say "     - Turn ON 'Developer mode' (top right)" Yellow
Say "     - Open Tampermonkey 'Details' -> turn ON 'Allow user scripts'" Yellow
Say "  2. Switch to the script tab and click 'Install'." Yellow
Say "     (If it shows raw code instead of an install page, do step 1" Yellow
Say "      first, then reload the tab.)" Yellow
Say ""
Say "Check the panels afterwards:" Yellow
Say "  - Amazon UK/DE pages -> green dot bottom-right + address button" Yellow
Say "  - delta.alliance.codes -> blue dot bottom-left + FILL buttons" Yellow
Say ""
