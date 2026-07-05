$ErrorActionPreference = "Stop"

$script1Path = "/home/ubuntu/upload/amazon-address-filler.user.js"
$script2Path = "/home/ubuntu/upload/amazonplatinum_autofill.user.js"

$script1Content = [System.IO.File]::ReadAllText($script1Path)
$script2Content = [System.IO.File]::ReadAllText($script2Path)

$script1Base64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($script1Content))
$script2Base64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($script2Content))

$tmJson = @{
    version = "1"
    scripts = @(
        @{
            name = "Amazon Address Filler"
            enabled = $true
            position = 1
            uuid = "11111111-1111-1111-1111-111111111111"
            source = $script1Base64
        },
        @{
            name = "Amazon Platinum Autofill"
            enabled = $true
            position = 2
            uuid = "22222222-2222-2222-2222-222222222222"
            source = $script2Base64
        }
    )
    settings = @{
        configMode = 100
        external_update_interval = "Always"
        page_filter_mode = "Disabled"
    }
}

$jsonString = $tmJson | ConvertTo-Json -Depth 10
$jsonPath = "/home/ubuntu/tm-easy/tm-provision.json"
[System.IO.File]::WriteAllText($jsonPath, $jsonString)

$sha256 = New-Object System.Security.Cryptography.SHA256Managed
$bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonString)
$hashBytes = $sha256.ComputeHash($bytes)
$hashString = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()

Write-Host "JSON saved to $jsonPath"
Write-Host "Hash: 1:$hashString"
