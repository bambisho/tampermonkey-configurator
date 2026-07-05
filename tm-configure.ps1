# =====================================================================
#  Tampermonkey Configurator (Enterprise Policy Edition)
# ---------------------------------------------------------------------
#  Applies:
#    1. Installs Tampermonkey via Chrome ExtensionInstallForcelist policy
#    2. Configures Tampermonkey settings via Managed Storage policy
#    3. Pre-installs two user scripts (Amazon Address Filler, Amazon Platinum Autofill)
#
#  Requires:
#    - Run as Administrator (to write to HKLM registry)
#    - Windows PowerShell 5.1
#
#  Note: Developer mode and "Allow user scripts" must be enabled manually.
# =====================================================================
param(
  [string]$ExtId = "dhdgffkkebhmkfjojejmpbldmpobfkfo"  # TM stable
)

$ErrorActionPreference = "Stop"

function Say($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color }

# Check for Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Say "This script requires Administrator privileges to configure Chrome policies." Red
    Say "Please right-click PowerShell and select 'Run as Administrator', then run the script again." Yellow
    exit 1
}

Say "Configuring Tampermonkey via Chrome Enterprise Policies..." Cyan

# 1. Force-install Tampermonkey
$forceListPath = "HKLM:\Software\Policies\Google\Chrome\ExtensionInstallForcelist"
if (-not (Test-Path $forceListPath)) {
    New-Item -Path $forceListPath -Force | Out-Null
}
# The value format is "extension_id;update_url"
$installValue = "$ExtId;https://clients2.google.com/service/update2/crx"
New-ItemProperty -Path $forceListPath -Name "1" -Value $installValue -PropertyType String -Force | Out-Null
Say "  -> Set ExtensionInstallForcelist policy to install Tampermonkey." Green

# 2. Configure Managed Storage (JSON Import)
# The JSON file is hosted on GitHub Pages (or raw.githubusercontent)
$jsonUrl = "https://raw.githubusercontent.com/bambisho/tampermonkey-configurator/master/tm-provision.json"
# This is Tampermonkey's STRUCTURAL hash of the JSON content (not a plain
# file SHA256). TM recursively hashes sorted keys/values; verified against
# TM v5.5.0 source and confirmed working in end-to-end tests.
$jsonHash = "1:8be53b6aa1fa8bad288bf5f8a17c6be6e1fc0793a9f7407b63c6ed2b89a6b6ba"

# Tampermonkey's official docs write the policy directly under the extension key
# (no 'policy' segment), while Chromium docs use a 'policy' segment. Set BOTH
# to be safe across Chrome versions.
$managedStoragePaths = @(
    "HKLM:\Software\Policies\Google\Chrome\3rdparty\extensions\$ExtId\policy\jsonImport\1",
    "HKLM:\Software\Policies\Google\Chrome\3rdparty\extensions\$ExtId\jsonImport\1"
)
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

# 3. Wipe Tampermonkey's local storage so it re-runs provisioning fresh.
#    (TM caches failed import attempts; a clean storage forces a retry.)
Say "Closing Chrome to reset Tampermonkey storage..." Cyan
Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
# wait until all chrome processes are really gone (max 15s)
$deadline = (Get-Date).AddSeconds(15)
while ((Get-Process chrome -ErrorAction SilentlyContinue) -and ((Get-Date) -lt $deadline)) {
    Start-Sleep -Milliseconds 500
}

$userDataDir = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
$profiles = @("Default") + (Get-ChildItem $userDataDir -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "Profile *" } | ForEach-Object { $_.Name })
foreach ($p in $profiles) {
    foreach ($sub in @("Local Extension Settings", "Sync Extension Settings", "Managed Extension Settings", "IndexedDB")) {
        $base = Join-Path $userDataDir "$p\$sub"
        if (-not (Test-Path $base)) { continue }
        Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*$ExtId*" } |
            ForEach-Object {
                Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                Say "  -> Cleared $sub in $p" Green
            }
    }
}

Say ""
Say "Configuration applied successfully!" Green
Say "Chrome was closed. Open Chrome now - Tampermonkey will be reinstalled" Yellow
Say "automatically and import the settings and scripts within a few seconds." Yellow
Say ""
Say "MANUAL STEPS REQUIRED:" Cyan
Say "1. Open chrome://extensions and turn ON 'Developer mode' (top right)."
Say "2. Click 'Details' on Tampermonkey and turn ON 'Allow user scripts'."
