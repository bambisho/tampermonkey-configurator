$ext = "/home/ubuntu/tm-work/tm-ext"
$env:TM_TEST_EXTRA = "--headless=new --no-sandbox --disable-extensions-except=$ext --load-extension=$ext"
$ProfileDir = "/home/ubuntu/tm-work/profile-test"
$ChromePath = "chromium"
$ExtId = "hcjamhlkmdbgmibmnlehejchdhmolohh"
& /home/ubuntu/tm-easy/tm-configure.ps1 -ChromePath $ChromePath -ProfileDir $ProfileDir -ExtId $ExtId
