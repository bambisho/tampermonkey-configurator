# =====================================================================
#  Tampermonkey Configurator (Two-Step Enterprise Policy Edition)
# ---------------------------------------------------------------------
#  Same command runs BOTH steps automatically (it remembers where it is):
#
#    STEP 1: Clean install of Tampermonkey
#      - Removes old provisioning policy (so TM installs "vanilla")
#      - Deep wipes old TM files + storage from all Chrome profiles
#      - Sets force-install policy so Chrome downloads TM fresh
#      -> Then YOU: open Chrome, wait for TM to appear, close Chrome,
#         and run the SAME command again.
#
#    STEP 2: Apply settings + install user scripts
#      - Sets the Managed Storage (jsonImport) provisioning policy
#      - Wipes TM storage once more so it re-runs provisioning fresh
#      -> Then YOU: open Chrome, enable Developer mode + Allow user
#         scripts, and check the Tampermonkey dashboard.
#
#  Requires: Run as Administrator, Windows PowerShell 5.1
# =====================================================================
param(
  [string]$ExtId = "dhdgffkkebhmkfjojejmpbldmpobfkfo",  # TM stable
  [ValidateSet("auto","1","2","reset")]
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
$managedStoragePaths = @(
    "HKLM:\Software\Policies\Google\Chrome\3rdparty\extensions\$ExtId\policy\jsonImport\1",
    "HKLM:\Software\Policies\Google\Chrome\3rdparty\extensions\$ExtId\jsonImport\1"
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
    if ((Test-Path $stateFile) -and ((Get-Content $stateFile -ErrorAction SilentlyContinue) -eq "step1-done")) {
        $Step = "2"
    } else {
        $Step = "1"
    }
}

# =====================================================================
# STEP 1: Clean install of Tampermonkey (no provisioning yet)
# =====================================================================
if ($Step -eq "1") {
    Say "=========================================" Cyan
    Say " STEP 1 of 2: Clean Tampermonkey install " Cyan
    Say "=========================================" Cyan

    Close-Chrome

    # Remove any previous provisioning policy so TM installs completely
    # vanilla with NO managed storage. This avoids the race condition
    # where TM boots before the policy JSON can be fetched.
    Say "Removing old provisioning policy (temporary)..." Cyan
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
    Say "  3. CLOSE Chrome completely." Yellow
    Say "  4. Run this SAME command again to do STEP 2:" Yellow
    Say ""
    Say "     irm https://raw.githubusercontent.com/bambisho/tampermonkey-configurator/master/tm-configure.ps1 | iex" Cyan
    Say ""
    exit 0
}

# =====================================================================
# STEP 2: Apply settings + install user scripts via provisioning policy
# =====================================================================
if ($Step -eq "2") {
    Say "===============================================" Cyan
    Say " STEP 2 of 2: Apply settings + install scripts " Cyan
    Say "===============================================" Cyan

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
        Say "If not: open Chrome, wait ~30s for Tampermonkey to appear, close Chrome," Yellow
        Say "then run this command again." Yellow
        Say ""
        Say "Continuing anyway (the policy will still be applied)..." Cyan
    }

    Close-Chrome

    # Configure Managed Storage (jsonImport provisioning)
    $cacheBuster = Get-Date -UFormat "%s"
    $jsonUrl = "https://raw.githubusercontent.com/bambisho/tampermonkey-configurator/master/tm-provision.json?t=$cacheBuster"
    # Tampermonkey's STRUCTURAL hash of the JSON content (not a plain file
    # SHA256). Verified against TM v5.5.0 source and end-to-end tests.
    $jsonHash = "1:f657e3cab927c4d8cac02e01e00dc856800b43c3e43434d442d4d3ee7900073f"

    foreach ($managedStoragePath in $managedStoragePaths) {
        if (-not (Test-Path $managedStoragePath)) {
            New-Item -Path $managedStoragePath -Force | Out-Null
        }
        New-ItemProperty -Path $managedStoragePath -Name "url" -Value $jsonUrl -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $managedStoragePath -Name "hash" -Value $jsonHash -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $managedStoragePath -Name "haltOnError" -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $managedStoragePath -Name "installAsSystemScripts" -Value 0 -PropertyType DWord -Force | Out-Null
    }
    Say "  -> Set Managed Storage policy to import settings and scripts." Green

    # Wipe TM's storage (but NOT the extension files) so it boots fresh
    # and runs the provisioning import on next start.
    Wipe-TmStorage

    # Clear state so a future run starts over at Step 1
    Remove-Item $stateFile -Force -ErrorAction SilentlyContinue

    Say ""
    Say "STEP 2 COMPLETE!" Green
    Say ""
    Say "NOW DO THIS:" Yellow
    Say "  1. Open Chrome." Yellow
    Say "  2. Wait ~30 seconds, then open the Tampermonkey dashboard." Yellow
    Say "     Both scripts should be installed and settings applied." Yellow
    Say "  3. If Developer mode / 'Allow user scripts' got reset, turn them" Yellow
    Say "     back ON in chrome://extensions -> Tampermonkey Details." Yellow
    Say ""
    exit 0
}
