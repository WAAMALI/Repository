$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$KeystorePath = Join-Path $ProjectRoot "android\app\tvexp-release-key.jks"

if (-not (Test-Path -LiteralPath $KeystorePath)) {
    throw "Keystore not found: $KeystorePath. Run scripts\create_release_keystore.bat first."
}

$Base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($KeystorePath))
Set-Clipboard -Value $Base64
Write-Host "The Base64 keystore value has been copied to the clipboard."
Write-Host "Paste it into the GitHub Actions secret named ANDROID_KEYSTORE_BASE64."
Write-Host "Do not paste it into source files, issues, chats, or commit it to Git."
