$ProfileDir = "/home/ubuntu/tm-work/profile-test/Default"
$ChromePath = "chromium"
$activePortFile = Join-Path $ProfileDir "DevToolsActivePort"
if (Test-Path $activePortFile) { Remove-Item $activePortFile -Force }

$chromeArgs = @(
  "--remote-debugging-port=0",
  "--remote-allow-origins=*",
  "--user-data-dir=`"$ProfileDir`"",
  "--no-first-run",
  "--no-default-browser-check",
  "--disable-features=MediaRouter",
  "--window-size=1200,900",
  "--headless"
)
$chromeArgs += "about:blank"
Start-Process -FilePath $ChromePath -ArgumentList $chromeArgs -PassThru

Start-Sleep -Seconds 3
if (Test-Path $activePortFile) {
  Write-Host "Success: $(Get-Content $activePortFile)"
} else {
  Write-Host "Failed: File not found"
}
Stop-Process -Name chromium -Force -ErrorAction SilentlyContinue
