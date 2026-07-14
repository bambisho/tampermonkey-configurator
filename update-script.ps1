# update-script.ps1 — Opens the userscript install/update page in Chrome
# This does NOT reinstall extensions or wipe any data.
# Usage: irm "https://raw.githubusercontent.com/bambisho/tampermonkey-configurator/master/update-script.ps1" | iex

$scriptUrl = "https://raw.githubusercontent.com/bambisho/tampermonkey-configurator/master/scripts/amazon-suite.user.js"
$cacheBuster = Get-Date -UFormat "%s"

Write-Host ""
Write-Host "Opening userscript update page in Chrome..." -ForegroundColor Cyan
Start-Process "chrome.exe" "$scriptUrl`?t=$cacheBuster"
Write-Host "Done! Click 'Reinstall' or 'Update' in the Tampermonkey tab that opens." -ForegroundColor Green
Write-Host ""
