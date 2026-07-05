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
# This hash must match the exact SHA256 of the hosted JSON file
$jsonHash = "1:10f5369d7ac6a9b321edef1adc1e9dcb91df60303b23e47ddda77357fba4db57"

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

Say ""
Say "Configuration applied successfully!" Green
Say "Please restart Chrome for the policies to take effect." Yellow
Say ""
Say "MANUAL STEPS REQUIRED:" Cyan
Say "1. Open chrome://extensions and turn ON 'Developer mode' (top right)."
Say "2. Click 'Details' on Tampermonkey and turn ON 'Allow user scripts'."
