# ==============================================================================
# VIET AUTH SYSTEM - BACKEND REST API SERVER
# Tương thích 100% Windows (PowerShell 5.1+ / .NET System.Net.HttpListener)
# Không cần cài đặt Node.js hay Python!
# ==============================================================================

param(
    [int]$Port = 8080,
    [string]$HostName = "localhost"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dataFile = Join-Path $scriptDir "data\database.json"

if (-not (Test-Path $dataFile)) {
    Write-Host "[!] Khong tim thay database.json, khoi tao database moi..." -ForegroundColor Yellow
    $initDb = @{
        adminKey = "thai"
        admins = @(@{ id="admin_01"; username="admin"; password="thai"; email="admin@vietauth.vn"; role="SUPER_ADMIN"; plan="ENTERPRISE" })
        apps = @()
        licenses = @()
        users = @()
        variables = @()
        devices = @()
        logs = @()
    }
    $initDb | ConvertTo-Json -Depth 10 | Set-Content -Path $dataFile -Encoding UTF8
}

function Load-Database {
    try {
        $raw = Get-Content -Path $dataFile -Raw -Encoding UTF8
        return ($raw | ConvertFrom-Json)
    } catch {
        Write-Host "[Error] Loi doc database: $_" -ForegroundColor Red
        return $null
    }
}

function Save-Database($db) {
    try {
        $json = $db | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($dataFile, $json, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Host "[Error] Loi luu database: $_" -ForegroundColor Red
    }
}

function Add-Log($action, $user, $appId, $result, $details) {
    $db = Load-Database
    if ($null -eq $db) { return }
    $newLog = [PSCustomObject]@{
        id = "log_" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        action = $action
        user = $user
        applicationId = $appId
        result = $result
        details = $details
    }
    $logList = [System.Collections.ArrayList]@($db.logs)
    $logList.Insert(0, $newLog)
    while ($logList.Count -gt 500) { $logList.RemoveAt($logList.Count - 1) }
    $db.logs = $logList
    Save-Database $db
}

# Quan ly so luong may truy cap (Online Devices / Sessions)
function Record-DeviceActivity($db, $appId, $hwid, $ip, $licenseKey, $username) {
    if ([string]::IsNullOrWhiteSpace($hwid) -and [string]::IsNullOrWhiteSpace($ip)) { return }
    if ($null -eq $db.devices) {
        $db | Add-Member -MemberType NoteProperty -Name "devices" -Value @() -ErrorAction SilentlyContinue
    }
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    $dev = $db.devices | Where-Object { 
        ((-not [string]::IsNullOrWhiteSpace($hwid)) -and $_.hwid -eq $hwid) -or 
        ([string]::IsNullOrWhiteSpace($hwid) -and $_.ip -eq $ip) 
    } | Select-Object -First 1

    $app = $db.apps | Where-Object { $_.id -eq $appId -or $_.appId -eq $appId } | Select-Object -First 1
    $appName = if ($app) { $app.name } else { "Chung" }

    if ($dev) {
        $dev.lastSeen = $now
        $dev.status = "ONLINE"
        if (-not [string]::IsNullOrWhiteSpace($appId)) { $dev.appId = if ($app) { $app.id } else { $appId } }
        if (-not [string]::IsNullOrWhiteSpace($appName)) { $dev.appName = $appName }
        if (-not [string]::IsNullOrWhiteSpace($ip)) { $dev.ip = $ip }
        if (-not [string]::IsNullOrWhiteSpace($licenseKey)) { $dev.licenseKey = $licenseKey }
        if (-not [string]::IsNullOrWhiteSpace($username)) { $dev.username = $username }
    } else {
        $newDev = [PSCustomObject]@{
            id = "dev_" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
            hwid = if (-not [string]::IsNullOrWhiteSpace($hwid)) { $hwid } else { "UNKNOWN_HWID" }
            ip = if (-not [string]::IsNullOrWhiteSpace($ip)) { $ip } else { "127.0.0.1" }
            appId = if ($app) { $app.id } else { $appId }
            appName = $appName
            licenseKey = if ($licenseKey) { $licenseKey } else { "" }
            username = if ($username) { $username } else { "Khách" }
            status = "ONLINE"
            firstConnected = $now
            lastSeen = $now
        }
        $devList = [System.Collections.ArrayList]@($db.devices)
        $devList.Insert(0, $newDev)
        while ($devList.Count -gt 500) { $devList.RemoveAt($devList.Count - 1) }
        $db.devices = $devList
    }
}

function Get-OnlineDeviceCount($db, $appId = $null) {
    if ($null -eq $db.devices) { return 0 }
    $cutoff = (Get-Date).ToUniversalTime().AddMinutes(-15)
    $active = $db.devices | Where-Object {
        try {
            $last = [DateTime]::Parse($_.lastSeen)
            if ($last -lt $cutoff) { return $false }
            if (-not [string]::IsNullOrWhiteSpace($appId) -and $_.appId -ne $appId) { return $false }
            return $true
        } catch { return $false }
    }
    return ($active | Measure-Object).Count
}

# Khoi dong HttpListener
$listener = New-Object System.Net.HttpListener
$prefix = "http://$HostName`:$Port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    Write-Host "[!] Khong the lang nghe tren $prefix ($_.Exception.Message)" -ForegroundColor Red
    Write-Host "[*] Dang thu chuyen sang cong 8081..." -ForegroundColor Yellow
    $Port = 8081
    $prefix = "http://$HostName`:$Port/"
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add($prefix)
    $listener.Start()
}

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "       VIET AUTH SYSTEM - HE THONG QUAN TRI KEY & XAC THUC API       " -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host " [*] May chu dang chay tai: $prefix" -ForegroundColor White
Write-Host " [*] Giao dien quan tri:    $prefix`index.html" -ForegroundColor Yellow
Write-Host " [*] API Health Check:      $prefix`api/1.2/status" -ForegroundColor Gray
Write-Host " [*] API Verify License:    $prefix`api/1.2/license/verify" -ForegroundColor Gray
Write-Host " [*] Tai khoan Admin mau:   admin / admin123" -ForegroundColor White
Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host " Nhan Ctrl+C de dung server bat cu luc nao.`n" -ForegroundColor DarkYellow

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        # Cho phep CORS
        $response.AddHeader("Access-Control-Allow-Origin", "*")
        $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
        $response.AddHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")

        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.Close()
            continue
        }

        $urlPath = $request.Url.AbsolutePath
        $httpMethod = $request.HttpMethod

        # Doc Body neu co
        $requestBody = ""
        if ($request.HasEntityBody) {
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $requestBody = $reader.ReadToEnd()
            $reader.Close()
        }

        $parsedBody = $null
        if (-not [string]::IsNullOrWhiteSpace($requestBody)) {
            try { $parsedBody = $requestBody | ConvertFrom-Json } catch {}
        }

        # Ham tra ve JSON
        $SendJson = {
            param($data, [int]$status = 200)
            $response.StatusCode = $status
            $response.ContentType = "application/json; charset=utf-8"
            $jsonStr = $data | ConvertTo-Json -Depth 10
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonStr)
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.Close()
        }

        # ----------------------------------------------------------------------
        # SERVE STATIC FILES (HTML, CSS, JS)
        # ----------------------------------------------------------------------
        if ($urlPath -eq "/" -or $urlPath -eq "/index.html") {
            $htmlPath = Join-Path $scriptDir "index.html"
            if (Test-Path $htmlPath) {
                $bytes = [System.IO.File]::ReadAllBytes($htmlPath)
                $response.ContentType = "text/html; charset=utf-8"
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
                $response.Close()
                continue
            }
        }
        elseif ($urlPath -eq "/style.css") {
            $cssPath = Join-Path $scriptDir "style.css"
            if (Test-Path $cssPath) {
                $bytes = [System.IO.File]::ReadAllBytes($cssPath)
                $response.ContentType = "text/css; charset=utf-8"
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
                $response.Close()
                continue
            }
        }
        elseif ($urlPath -eq "/app.js") {
            $jsPath = Join-Path $scriptDir "app.js"
            if (Test-Path $jsPath) {
                $bytes = [System.IO.File]::ReadAllBytes($jsPath)
                $response.ContentType = "application/javascript; charset=utf-8"
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
                $response.Close()
                continue
            }
        }

        # ----------------------------------------------------------------------
        # API 1.2: CLIENT VERIFICATION & ACTIVATION
        # ----------------------------------------------------------------------
        if ($urlPath -eq "/api/1.2/status" -or $urlPath -eq "/api/status") {
            &$SendJson @{
                status = "operational"
                service = "VIET AUTH SYSTEM"
                version = "1.2"
                timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                message = "May chu xac thuc VietAuth dang hoat dong tot"
            }
            continue
        }

        # CLIENT VERIFY LICENSE
        if (($urlPath -eq "/api/1.2/license/verify" -or $urlPath -eq "/api/verify") -and $httpMethod -eq "POST") {
            $db = Load-Database
            $licenseKey = if ($parsedBody.license) { $parsedBody.license.ToString().Trim() } elseif ($parsedBody.key) { $parsedBody.key.ToString().Trim() } else { "" }
            $hwid = if ($parsedBody.hwid) { $parsedBody.hwid.ToString().Trim() } else { "" }
            $appId = if ($parsedBody.appId) { $parsedBody.appId.ToString().Trim() } else { "" }

            if ([string]::IsNullOrWhiteSpace($licenseKey)) {
                &$SendJson @{ success = $false; message = "Vui long nhap ma key ban quyen" } 400
                continue
            }

            # Tim key trong database
            $lic = $db.licenses | Where-Object { $_.key -eq $licenseKey } | Select-Object -First 1

            if ($null -eq $lic) {
                Add-Log "API_VERIFY_FAILED" "Unknown" $appId "FAIL" "Key khong ton tai: $licenseKey"
                &$SendJson @{ success = $false; message = "Ma key ban quyen khong hop le hoac khong ton tai tren he thong!" } 404
                continue
            }

            # Kiem tra App ID neu client gui
            if (-not [string]::IsNullOrWhiteSpace($appId)) {
                $app = $db.apps | Where-Object { $_.id -eq $lic.applicationId -or $_.appId -eq $appId } | Select-Object -First 1
                if ($null -eq $app) {
                    &$SendJson @{ success = $false; message = "Key nay khong thuoc ve ung dung duoc chi dinh" } 400
                    continue
                }
            }

            # Kiem tra trang thai BANNED
            if ($lic.status -eq "BANNED") {
                $reason = if ($lic.banReason) { $lic.banReason } else { "Vi pham quy dinh su dung" }
                Add-Log "API_VERIFY_BANNED" $lic.key $lic.applicationId "BANNED" "Tu choi key bi khoa: $reason"
                &$SendJson @{ success = $false; message = "Key ban quyen nay da bi khoa boi Admin! Ly do: $reason" } 403
                continue
            }

            $now = (Get-Date).ToUniversalTime()

            # Neu key UNUSED -> Tu dong kich hoat va bind HWID
            if ($lic.status -eq "UNUSED") {
                $lic.status = "ACTIVE"
                $lic.activatedAt = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
                $lic.hwids = @()
                if (-not [string]::IsNullOrWhiteSpace($hwid)) {
                    $lic.hwids = @($hwid)
                    $lic.hwid = $hwid
                    $lic.activationCount = 1
                } else {
                    $lic.hwid = $null
                    $lic.activationCount = 0
                }
                $maxDev = if ($null -ne $lic.maxDevices) { [int]$lic.maxDevices } elseif ($null -ne $lic.activationLimit) { [int]$lic.activationLimit } else { 1 }
                $lic.maxDevices = $maxDev
                $lic.activationLimit = $maxDev
                if ($lic.durationDays -gt 0) {
                    $lic.expiresAt = $now.AddDays($lic.durationDays).ToString("yyyy-MM-ddTHH:mm:ssZ")
                } else {
                    $lic.expiresAt = $null # Lifetime
                }
                $lic.lastUsedAt = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
                $clientIp = if ($request.RemoteEndPoint) { $request.RemoteEndPoint.Address.ToString() } else { "127.0.0.1" }
                Record-DeviceActivity $db $lic.applicationId $lic.hwid $clientIp $lic.key "KeyClient"
                Save-Database $db

                Add-Log "API_ACTIVATE_KEY" $lic.key $lic.applicationId "SUCCESS" "Kich hoat key lan dau voi HWID: $hwid (Gioi han: $(if ($maxDev -le 0) { 'Vo han' } else { "$maxDev may" }))"
                
                $daysRemaining = if ($lic.durationDays -gt 0) { $lic.durationDays } else { 99999 }
                &$SendJson @{
                    success = $true
                    message = "Kich hoat ban quyen thanh cong lan dau!"
                    data = @{
                        key = $lic.key
                        status = "ACTIVE"
                        subscriptionLevel = $lic.subscriptionLevel
                        isLifetime = ($lic.durationDays -le 0)
                        expiresAt = $lic.expiresAt
                        daysRemaining = $daysRemaining
                        hwid = $lic.hwid
                        maxDevices = $lic.maxDevices
                        activationLimit = $lic.activationLimit
                        activationCount = @($lic.hwids).Count
                        devices = @($lic.hwids)
                    }
                }
                continue
            }

            # Neu key da ACTIVE -> Kiem tra thoi han
            if ($lic.status -eq "ACTIVE") {
                if (-not [string]::IsNullOrWhiteSpace($lic.expiresAt)) {
                    $expDate = [DateTime]::Parse($lic.expiresAt)
                    if ($now -gt $expDate) {
                        $lic.status = "EXPIRED"
                        Save-Database $db
                        Add-Log "API_EXPIRED" $lic.key $lic.applicationId "EXPIRED" "Key da het han vao $lic.expiresAt"
                        &$SendJson @{ success = $false; message = "Key ban quyen da het han su dung! Vui long gia han them." } 403
                        continue
                    }
                }

                # Chuan hoa hwids va maxDevices
                $hwidList = @()
                if ($lic.hwids) {
                    $hwidList = @($lic.hwids)
                } elseif (-not [string]::IsNullOrWhiteSpace($lic.hwid)) {
                    $hwidList = @($lic.hwid -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                }
                $maxDev = if ($null -ne $lic.maxDevices) { [int]$lic.maxDevices } elseif ($null -ne $lic.activationLimit) { [int]$lic.activationLimit } else { 1 }
                $lic.maxDevices = $maxDev
                $lic.activationLimit = $maxDev

                # Kiem tra HWID binding va gioi han thiet bi
                if ($lic.hwidEnabled -and (-not [string]::IsNullOrWhiteSpace($hwid))) {
                    $isBound = $hwidList -contains $hwid
                    if (-not $isBound) {
                        if ($maxDev -gt 0 -and $hwidList.Count -ge $maxDev) {
                            Add-Log "API_DEVICE_LIMIT" $lic.key $lic.applicationId "FAIL" "Vuot gioi han thiet bi: $($hwidList.Count)/$maxDev may (HWID: $hwid)"
                            &$SendJson @{
                                success = $false
                                message = "Khoa HWID: Key nay da dat gioi han toi da $maxDev thiet bi ($($hwidList.Count)/$maxDev may da dung)! Vui long lien he Admin de dat lai HWID."
                            } 403
                            continue
                        }
                        $hwidList += $hwid
                        $lic.hwids = $hwidList
                        $lic.hwid = ($hwidList -join ", ")
                        $lic.activationCount = $hwidList.Count
                    }
                } elseif ($hwidList.Count -eq 0 -and (-not [string]::IsNullOrWhiteSpace($hwid))) {
                    $hwidList += $hwid
                    $lic.hwids = $hwidList
                    $lic.hwid = $hwid
                    $lic.activationCount = 1
                }

                $lic.lastUsedAt = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
                $clientIp = if ($request.RemoteEndPoint) { $request.RemoteEndPoint.Address.ToString() } else { "127.0.0.1" }
                Record-DeviceActivity $db $lic.applicationId $lic.hwid $clientIp $lic.key "KeyClient"
                Save-Database $db

                $remainingDays = 99999
                if (-not [string]::IsNullOrWhiteSpace($lic.expiresAt)) {
                    $expDate = [DateTime]::Parse($lic.expiresAt)
                    $remainingDays = [Math]::Max(0, [int]($expDate - $now).TotalDays)
                }

                Add-Log "API_VERIFY_SUCCESS" $lic.key $lic.applicationId "SUCCESS" "Xac thuc thanh cong key $($lic.key) tren may $hwid"

                &$SendJson @{
                    success = $true
                    message = "Xac thuc ban quyen thanh cong!"
                    data = @{
                        key = $lic.key
                        status = "ACTIVE"
                        subscriptionLevel = $lic.subscriptionLevel
                        isLifetime = ($lic.durationDays -le 0)
                        expiresAt = $lic.expiresAt
                        daysRemaining = $remainingDays
                        hwid = $lic.hwid
                        maxDevices = $lic.maxDevices
                        activationLimit = $lic.activationLimit
                        activationCount = @($lic.hwids).Count
                        devices = @($lic.hwids)
                    }
                }
                continue
            }

            &$SendJson @{ success = $false; message = "Key o trang thai khong hop le ($($lic.status))" } 400
            continue
        }

        # CLIENT ACTIVATE LICENSE EXPLICITLY
        if (($urlPath -eq "/api/1.2/license/activate" -or $urlPath -eq "/api/activate") -and $httpMethod -eq "POST") {
            $db = Load-Database
            $licenseKey = if ($parsedBody.license) { $parsedBody.license.ToString().Trim() } else { "" }
            $hwid = if ($parsedBody.hwid) { $parsedBody.hwid.ToString().Trim() } else { "" }

            $lic = $db.licenses | Where-Object { $_.key -eq $licenseKey } | Select-Object -First 1
            if ($null -eq $lic) {
                &$SendJson @{ success = $false; message = "Key khong ton tai" } 404
                continue
            }
            if ($lic.status -eq "ACTIVE") {
                &$SendJson @{ success = $false; message = "Key da duoc kich hoat truoc do" } 400
                continue
            }

            $now = (Get-Date).ToUniversalTime()
            $lic.status = "ACTIVE"
            $lic.activatedAt = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
            $lic.hwid = $hwid
            if ($lic.durationDays -gt 0) {
                $lic.expiresAt = $now.AddDays($lic.durationDays).ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
            Save-Database $db

            &$SendJson @{
                success = $true
                message = "Kich hoat thanh cong"
                data = $lic
            }
            continue
        }

        # GET VARIABLE
        if ($urlPath -eq "/api/1.2/variable" -and $httpMethod -eq "GET") {
            $query = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
            $varName = $query["name"]
            $db = Load-Database
            $variable = $db.variables | Where-Object { $_.name -eq $varName -and -not $_.isSecret } | Select-Object -First 1
            if ($variable) {
                &$SendJson @{ success = $true; name = $variable.name; value = $variable.value }
            } else {
                &$SendJson @{ success = $false; message = "Khong tim thay bien hoac bien bi an" } 404
            }
            continue
        }

        # ----------------------------------------------------------------------
        # 3.1 CHUAN CLIENT API KEYAUTH & LONGAUTH COMPATIBLE (/api/v1/client/*)
        # ----------------------------------------------------------------------
        if ($urlPath -eq "/api/v1/client/init" -and $httpMethod -eq "POST") {
            $db = Load-Database
            $reqAppId = if ($request.Headers["x-app-id"]) { $request.Headers["x-app-id"] } elseif ($parsedBody.appId) { $parsedBody.appId.ToString() } else { "" }
            $app = $db.apps | Where-Object { $_.appId -eq $reqAppId -or $_.id -eq $reqAppId } | Select-Object -First 1

            if ($null -eq $app) {
                &$SendJson @{ success = $false; error = "App ID khong hop le hoac ung dung khong ton tai tren he thong!" } 404
                continue
            }

            $clientIp = if ($request.RemoteEndPoint) { $request.RemoteEndPoint.Address.ToString() } else { "127.0.0.1" }
            $hwid = if ($parsedBody.hwid) { $parsedBody.hwid.ToString() } elseif ($request.Headers["x-hwid"]) { $request.Headers["x-hwid"] } else { "" }
            Record-DeviceActivity $db $app.id $hwid $clientIp $null "Client Init"
            Save-Database $db

            $onlineUsers = Get-OnlineDeviceCount $db $app.id
            if ($onlineUsers -lt 1) { $onlineUsers = 1 }
            $numUsers = ($db.users | Where-Object { $_.applicationId -eq $app.id } | Measure-Object).Count
            if ($numUsers -lt 1) { $numUsers = 1 }
            $numKeys = ($db.licenses | Where-Object { $_.applicationId -eq $app.id } | Measure-Object).Count
            if ($numKeys -lt 1) { $numKeys = 1 }
            $sessionToken = "tok_" + [Guid]::NewGuid().ToString("N")

            &$SendJson @{
                success = $true
                message = "Initialized"
                version = if ($app.version) { $app.version } else { "1.0.0" }
                token = $sessionToken
                numOnlineUsers = [string]$onlineUsers
                numUsers = [string]$numUsers
                numKeys = [string]$numKeys
                app = @{
                    name = $app.name
                    version = if ($app.version) { $app.version } else { "1.0.0" }
                    numUsers = [string]$numUsers
                    numOnlineUsers = [string]$onlineUsers
                    numKeys = [string]$numKeys
                }
            }
            continue
        }

        # CLIENT LOGIN VOI KEY
        if ($urlPath -eq "/api/v1/client/login" -and $httpMethod -eq "POST") {
            $db = Load-Database
            $key = if ($parsedBody.key) { $parsedBody.key.ToString().Trim() } elseif ($parsedBody.license) { $parsedBody.license.ToString().Trim() } else { "" }
            $hwid = if ($parsedBody.hwid) { $parsedBody.hwid.ToString().Trim() } else { "" }
            $reqAppId = if ($request.Headers["x-app-id"]) { $request.Headers["x-app-id"] } elseif ($parsedBody.appId) { $parsedBody.appId.ToString() } else { "" }
            $clientIp = if ($request.RemoteEndPoint) { $request.RemoteEndPoint.Address.ToString() } else { "127.0.0.1" }

            if ([string]::IsNullOrWhiteSpace($key)) {
                &$SendJson @{ success = $false; error = "Vui long cung cap ma key ban quyen!" } 400
                continue
            }

            $lic = $db.licenses | Where-Object { $_.key -eq $key } | Select-Object -First 1
            if ($null -eq $lic) {
                Add-Log "CLIENT_LOGIN_FAIL" "Unknown" $reqAppId "FAIL" "Key khong ton tai: $key"
                &$SendJson @{ success = $false; error = "Ma key ban quyen khong ton tai tren he thong!" } 404
                continue
            }

            if ($lic.status -eq "BANNED") {
                $reason = if ($lic.banReason) { $lic.banReason } else { "Vi pham chinh sach" }
                Add-Log "CLIENT_LOGIN_BANNED" $lic.key $lic.applicationId "BANNED" "Key bi khoa: $reason"
                &$SendJson @{ success = $false; error = "Key ban quyen da bi khoa: $reason" } 403
                continue
            }

            $now = (Get-Date).ToUniversalTime()

            $maxDev = if ($null -ne $lic.maxDevices) { [int]$lic.maxDevices } elseif ($null -ne $lic.activationLimit) { [int]$lic.activationLimit } else { 1 }
            $lic.maxDevices = $maxDev
            $lic.activationLimit = $maxDev

            if ($lic.status -eq "UNUSED") {
                $lic.status = "ACTIVE"
                $lic.activatedAt = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
                $lic.hwids = @()
                if (-not [string]::IsNullOrWhiteSpace($hwid)) {
                    $lic.hwids = @($hwid)
                    $lic.hwid = $hwid
                    $lic.activationCount = 1
                } else {
                    $lic.hwid = $null
                    $lic.activationCount = 0
                }
                if ($lic.durationDays -gt 0) {
                    $lic.expiresAt = $now.AddDays($lic.durationDays).ToString("yyyy-MM-ddTHH:mm:ssZ")
                } else {
                    $lic.expiresAt = $null
                }
            } elseif ($lic.status -eq "ACTIVE") {
                if (-not [string]::IsNullOrWhiteSpace($lic.expiresAt)) {
                    $expDate = [DateTime]::Parse($lic.expiresAt)
                    if ($now -gt $expDate) {
                        $lic.status = "EXPIRED"
                        Save-Database $db
                        &$SendJson @{ success = $false; error = "Key ban quyen da het han su dung!" } 403
                        continue
                    }
                }

                $hwidList = @()
                if ($lic.hwids) {
                    $hwidList = @($lic.hwids)
                } elseif (-not [string]::IsNullOrWhiteSpace($lic.hwid)) {
                    $hwidList = @($lic.hwid -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                }

                if ($lic.hwidEnabled -and (-not [string]::IsNullOrWhiteSpace($hwid))) {
                    $isBound = $hwidList -contains $hwid
                    if (-not $isBound) {
                        if ($maxDev -gt 0 -and $hwidList.Count -ge $maxDev) {
                            Add-Log "CLIENT_DEVICE_LIMIT" $lic.key $lic.applicationId "FAIL" "Vuot gioi han may: $($hwidList.Count)/$maxDev ($hwid)"
                            &$SendJson @{
                                success = $false
                                error = "Khoa HWID: Key da dat gioi han toi da $maxDev thiet bi ($($hwidList.Count)/$maxDev may)! Vui long lien he Admin de reset HWID."
                            } 403
                            continue
                        }
                        $hwidList += $hwid
                        $lic.hwids = $hwidList
                        $lic.hwid = ($hwidList -join ", ")
                        $lic.activationCount = $hwidList.Count
                    }
                } elseif ($hwidList.Count -eq 0 -and (-not [string]::IsNullOrWhiteSpace($hwid))) {
                    $hwidList += $hwid
                    $lic.hwids = $hwidList
                    $lic.hwid = $hwid
                    $lic.activationCount = 1
                }
            }

            $lic.lastUsedAt = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
            Record-DeviceActivity $db $lic.applicationId $hwid $clientIp $lic.key "KeyClient"
            Save-Database $db

            $sessionToken = "tok_" + [Guid]::NewGuid().ToString("N")
            Add-Log "CLIENT_LOGIN_SUCCESS" $lic.key $lic.applicationId "SUCCESS" "May [$hwid] dang nhap key thanh cong ($(@($lic.hwids).Count)/$($lic.maxDevices) may)"

            $onlineCount = Get-OnlineDeviceCount $db $lic.applicationId
            if ($onlineCount -lt 1) { $onlineCount = 1 }

            &$SendJson @{
                success = $true
                message = "License login successful"
                token = $sessionToken
                expiresAt = if ($lic.expiresAt) { $lic.expiresAt } else { "2099-12-31T23:59:59Z" }
                subscription = if ($lic.subscriptionLevel) { $lic.subscriptionLevel } else { "VIP" }
                hwid = if ($lic.hwid) { $lic.hwid } else { $hwid }
                maxDevices = [string]$lic.maxDevices
                devicesUsed = [string]@($lic.hwids).Count
                activationLimit = $lic.maxDevices
                activationCount = @($lic.hwids).Count
                devices = @($lic.hwids)
                createdate = $lic.createdAt
                numOnlineUsers = [string]$onlineCount
            }
            continue
        }

        # CLIENT LOGIN VOI USER / PASSWORD
        if ($urlPath -eq "/api/v1/client/login-user" -and $httpMethod -eq "POST") {
            $db = Load-Database
            $username = if ($parsedBody.username) { $parsedBody.username.ToString().Trim() } else { "" }
            $password = if ($parsedBody.password) { $parsedBody.password.ToString().Trim() } else { "" }
            $hwid = if ($parsedBody.hwid) { $parsedBody.hwid.ToString().Trim() } else { "" }
            $clientIp = if ($request.RemoteEndPoint) { $request.RemoteEndPoint.Address.ToString() } else { "127.0.0.1" }

            $user = $db.users | Where-Object { ($_.username -eq $username -or $_.email -eq $username) -and $_.password -eq $password } | Select-Object -First 1

            if ($null -eq $user) {
                &$SendJson @{ success = $false; error = "Sai ten dang nhap hoac mat khau!" } 401
                continue
            }

            if ($user.status -eq "BANNED") {
                $reason = if ($user.banReason) { $user.banReason } else { "Tai khoan nay da bi khoa!" }
                &$SendJson @{ success = $false; error = $reason } 403
                continue
            }

            $now = (Get-Date).ToUniversalTime()

            # Kiem tra het han cho tai khoan
            if (-not [string]::IsNullOrWhiteSpace($user.expiresAt)) {
                try {
                    $expDate = [DateTime]::Parse($user.expiresAt)
                    if ($now -gt $expDate) {
                        $user.status = "EXPIRED"
                        Save-Database $db
                        &$SendJson @{ success = $false; error = "Tai khoan da het han su dung! Vui long lien he Admin de gia han." } 403
                        continue
                    }
                } catch {}
            }

            # Kiem tra HWID & Gioi han thiet bi tai khoan
            $uHwidList = @()
            if ($user.hwids) {
                $uHwidList = @($user.hwids)
            } elseif (-not [string]::IsNullOrWhiteSpace($user.hwid)) {
                $uHwidList = @($user.hwid -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }
            $uMaxDev = if ($null -ne $user.maxDevices) { [int]$user.maxDevices } else { 1 }
            $user.maxDevices = $uMaxDev

            if ($user.hwidEnabled -and (-not [string]::IsNullOrWhiteSpace($hwid))) {
                $isBound = $uHwidList -contains $hwid
                if (-not $isBound) {
                    if ($uMaxDev -gt 0 -and $uHwidList.Count -ge $uMaxDev) {
                        Add-Log "CLIENT_HWID_MISMATCH" $user.username $user.applicationId "FAIL" "Vuot gioi han may tai khoan: $($uHwidList.Count)/$uMaxDev ($hwid)"
                        &$SendJson @{ success = $false; error = "Khoa HWID: Tai khoan da dat gioi han toi da $uMaxDev thiet bi ($($uHwidList.Count)/$uMaxDev may)! Vui long lien he Admin de reset HWID." } 403
                        continue
                    }
                    $uHwidList += $hwid
                    $user.hwids = $uHwidList
                    $user.hwid = ($uHwidList -join ", ")
                }
            } elseif ($uHwidList.Count -eq 0 -and (-not [string]::IsNullOrWhiteSpace($hwid))) {
                $uHwidList += $hwid
                $user.hwids = $uHwidList
                $user.hwid = $hwid
            }

            $user.lastLogin = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
            Record-DeviceActivity $db $user.applicationId (if ($user.hwid) { $user.hwid } else { $hwid }) $clientIp (if ($user.licenseKey) { $user.licenseKey } else { $user.username }) $user.username
            Save-Database $db

            $lic = if ($user.licenseKey) { $db.licenses | Where-Object { $_.key -eq $user.licenseKey } | Select-Object -First 1 } else { $null }
            $sessionToken = "tok_" + [Guid]::NewGuid().ToString("N")
            $onlineCount = Get-OnlineDeviceCount $db $user.applicationId
            if ($onlineCount -lt 1) { $onlineCount = 1 }

            $expResult = if ($user.expiresAt) { $user.expiresAt } elseif ($lic -and $lic.expiresAt) { $lic.expiresAt } else { "2099-12-31T23:59:59Z" }
            $subResult = if ($user.subscriptionLevel) { $user.subscriptionLevel } elseif ($lic -and $lic.subscriptionLevel) { $lic.subscriptionLevel } else { "VIP" }

            Add-Log "CLIENT_USER_LOGIN" $user.username $user.applicationId "SUCCESS" "May [$hwid] dang nhap tai khoan thanh cong ($(@($user.hwids).Count)/$($user.maxDevices) may)"

            &$SendJson @{
                success = $true
                message = "Login successful"
                token = $sessionToken
                expiresAt = $expResult
                subscription = $subResult
                hwid = $user.hwid
                maxDevices = [string]$user.maxDevices
                devicesUsed = [string]@($user.hwids).Count
                devices = @($user.hwids)
                createdate = $user.createdAt
                numOnlineUsers = [string]$onlineCount
            }
            continue
        }

        # CLIENT REGISTER
        if ($urlPath -eq "/api/v1/client/register" -and $httpMethod -eq "POST") {
            $db = Load-Database
            $key = if ($parsedBody.key) { $parsedBody.key.ToString().Trim() } else { "" }
            $username = if ($parsedBody.username) { $parsedBody.username.ToString().Trim() } else { "" }
            $password = if ($parsedBody.password) { $parsedBody.password.ToString().Trim() } else { "" }
            $hwid = if ($parsedBody.hwid) { $parsedBody.hwid.ToString().Trim() } else { "" }
            $reqAppId = if ($request.Headers["x-app-id"]) { $request.Headers["x-app-id"] } elseif ($parsedBody.appId) { $parsedBody.appId.ToString() } else { "" }
            $clientIp = if ($request.RemoteEndPoint) { $request.RemoteEndPoint.Address.ToString() } else { "127.0.0.1" }

            if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password) -or [string]::IsNullOrWhiteSpace($key)) {
                &$SendJson @{ success = $false; error = "Vui long nhap day du Username, Password va License Key!" } 400
                continue
            }

            $lic = $db.licenses | Where-Object { $_.key -eq $key } | Select-Object -First 1
            if ($null -eq $lic) {
                &$SendJson @{ success = $false; error = "Ma key ban quyen khong ton tai!" } 404
                continue
            }

            if ($lic.status -eq "BANNED") {
                &$SendJson @{ success = $false; error = "Key ban quyen nay da bi khoa!" } 403
                continue
            }

            $existing = $db.users | Where-Object { $_.username -eq $username } | Select-Object -First 1
            if ($existing) {
                &$SendJson @{ success = $false; error = "Ten nguoi dung da duoc su dung!" } 400
                continue
            }

            $now = (Get-Date).ToUniversalTime()
            $hwidList = @()
            if ($lic.hwids) { $hwidList = @($lic.hwids) } elseif ($lic.hwid) { $hwidList = @($lic.hwid -split ',' | ForEach-Object { $_.Trim() }) }
            $maxDev = if ($null -ne $lic.maxDevices) { [int]$lic.maxDevices } elseif ($null -ne $lic.activationLimit) { [int]$lic.activationLimit } else { 1 }
            $lic.maxDevices = $maxDev
            $lic.activationLimit = $maxDev

            if ($lic.status -eq "UNUSED") {
                $lic.status = "ACTIVE"
                $lic.activatedAt = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
                if (-not [string]::IsNullOrWhiteSpace($hwid)) {
                    $lic.hwids = @($hwid)
                    $lic.hwid = $hwid
                    $lic.activationCount = 1
                }
                if ($lic.durationDays -gt 0) {
                    $lic.expiresAt = $now.AddDays($lic.durationDays).ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
            } elseif ($lic.status -eq "ACTIVE") {
                if ($lic.hwidEnabled -and (-not [string]::IsNullOrWhiteSpace($hwid))) {
                    if (-not ($hwidList -contains $hwid)) {
                        if ($maxDev -gt 0 -and $hwidList.Count -ge $maxDev) {
                            &$SendJson @{ success = $false; error = "Key ban quyen da dat gioi han toi da $maxDev thiet bi!" } 403
                            continue
                        }
                        $hwidList += $hwid
                        $lic.hwids = $hwidList
                        $lic.hwid = ($hwidList -join ", ")
                        $lic.activationCount = $hwidList.Count
                    }
                }
            }

            $targetAppId = if ($lic.applicationId) { $lic.applicationId } elseif ($reqAppId) { $reqAppId } else { "app_viet_01" }
            $newUser = [PSCustomObject]@{
                id = "usr_" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
                username = $username
                email = "$username@client.com"
                password = $password
                applicationId = $targetAppId
                status = "ACTIVE"
                hwid = if ($hwid) { $hwid } else { $lic.hwid }
                licenseKey = $lic.key
                ipAddress = $clientIp
                createdAt = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
                lastLogin = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
            }

            $userList = [System.Collections.ArrayList]@($db.users)
            $userList.Insert(0, $newUser)
            $db.users = $userList

            Record-DeviceActivity $db $newUser.applicationId $hwid $clientIp $lic.key $username
            Save-Database $db

            $sessionToken = "tok_" + [Guid]::NewGuid().ToString("N")
            &$SendJson @{
                success = $true
                message = "Registered"
                token = $sessionToken
            }
            continue
        }

        # CLIENT CHECK SESSION
        if ($urlPath -eq "/api/v1/client/check") {
            $db = Load-Database
            $hwid = if ($parsedBody.hwid) { $parsedBody.hwid.ToString() } elseif ($request.Headers["x-hwid"]) { $request.Headers["x-hwid"] } else { "" }
            $reqAppId = if ($request.Headers["x-app-id"]) { $request.Headers["x-app-id"] } elseif ($parsedBody.appId) { $parsedBody.appId.ToString() } else { "" }
            $clientIp = if ($request.RemoteEndPoint) { $request.RemoteEndPoint.Address.ToString() } else { "127.0.0.1" }

            Record-DeviceActivity $db $reqAppId $hwid $clientIp $null "ActiveCheck"
            Save-Database $db

            $onlineCount = Get-OnlineDeviceCount $db $reqAppId
            if ($onlineCount -lt 1) { $onlineCount = 1 }

            &$SendJson @{
                success = $true
                message = "Session valid"
                numOnlineUsers = [string]$onlineCount
            }
            continue
        }

        # CLIENT VARIABLES
        if ($urlPath -eq "/api/v1/client/variables") {
            $db = Load-Database
            $reqAppId = if ($request.Headers["x-app-id"]) { $request.Headers["x-app-id"] } else { "" }
            $vars = if ($reqAppId) {
                $db.variables | Where-Object { ($_.applicationId -eq $reqAppId -or [string]::IsNullOrWhiteSpace($_.applicationId)) -and -not $_.isSecret }
            } else {
                $db.variables | Where-Object { -not $_.isSecret }
            }
            &$SendJson @{
                success = $true
                message = "Variables loaded"
                variables = @($vars)
            }
            continue
        }

        # QUAN LY THIET BI / MAY TRUY CAP (DEVICES)
        if ($urlPath -eq "/api/devices") {
            $db = Load-Database
            if ($null -eq $db.devices) {
                $db | Add-Member -MemberType NoteProperty -Name "devices" -Value @() -ErrorAction SilentlyContinue
            }

            if ($httpMethod -eq "GET") {
                $query = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
                $appId = $query["appId"]
                $cutoff = (Get-Date).ToUniversalTime().AddMinutes(-15)

                $deviceList = @()
                foreach ($d in $db.devices) {
                    $isOnline = $false
                    try {
                        $last = [DateTime]::Parse($d.lastSeen)
                        $isOnline = ($last -ge $cutoff)
                    } catch {}

                    if (-not [string]::IsNullOrWhiteSpace($appId) -and $appId -ne "ALL" -and $d.appId -ne $appId) {
                        continue
                    }

                    $deviceList += [PSCustomObject]@{
                        id = $d.id
                        hwid = $d.hwid
                        ip = $d.ip
                        appId = $d.appId
                        appName = $d.appName
                        licenseKey = $d.licenseKey
                        username = $d.username
                        status = if ($isOnline) { "ONLINE" } else { "OFFLINE" }
                        isOnline = $isOnline
                        firstConnected = $d.firstConnected
                        lastSeen = $d.lastSeen
                    }
                }

                $onlineCount = ($deviceList | Where-Object { $_.isOnline } | Measure-Object).Count

                &$SendJson @{
                    success = $true
                    onlineCount = $onlineCount
                    totalCount = $deviceList.Count
                    data = $deviceList
                }
                continue
            }

            if ($httpMethod -eq "DELETE") {
                $query = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
                $devId = $query["id"]
                $db.devices = @($db.devices | Where-Object { $_.id -ne $devId })
                Save-Database $db
                &$SendJson @{ success = $true; message = "Da xoa thiet bi khoi danh sach!" }
                continue
            }
        }

        # ----------------------------------------------------------------------
        # DASHBOARD API: AUTHENTICATION
        # ----------------------------------------------------------------------
        # XAC THUC KEY ADMIN ("thai")
        if ($urlPath -eq "/api/auth/admin-verify" -and $httpMethod -eq "POST") {
            $db = Load-Database
            $inputKey = if ($parsedBody.adminKey) { $parsedBody.adminKey.ToString().Trim().ToLower() } elseif ($parsedBody.key) { $parsedBody.key.ToString().Trim().ToLower() } else { "" }
            $correctKey = if ($db.adminKey) { $db.adminKey.ToString().Trim().ToLower() } else { "thai" }

            if ($inputKey -eq $correctKey) {
                Add-Log "ADMIN_UNLOCK_SUCCESS" "admin" "SYSTEM" "SUCCESS" "Admin da mo khoa Bang Quan Tri bang Key"
                &$SendJson @{
                    success = $true
                    message = "Xac thuc Key Admin thanh cong! Da mo khoa Bang Quan Tri."
                    admin = @{
                        username = "Admin Thai"
                        role = "SUPER_ADMIN"
                        plan = "ENTERPRISE"
                    }
                }
            } else {
                Add-Log "ADMIN_UNLOCK_FAIL" "anonymous" "SYSTEM" "FAIL" "Nhap sai Key Admin: $inputKey"
                &$SendJson @{
                    success = $false
                    message = "Ma Key Admin khong chinh xac! Vui long thu lai."
                } 403
            }
            continue
        }

        if ($urlPath -eq "/api/auth/login" -and $httpMethod -eq "POST") {
            $db = Load-Database
            $emailOrUser = if ($parsedBody.email) { $parsedBody.email.ToString().Trim() } elseif ($parsedBody.username) { $parsedBody.username.ToString().Trim() } else { "" }
            $password = if ($parsedBody.password) { $parsedBody.password.ToString() } else { "" }

            $admin = $db.admins | Where-Object { ($_.username -eq $emailOrUser -or $_.email -eq $emailOrUser) -and $_.password -eq $password } | Select-Object -First 1

            if ($admin) {
                Add-Log "ADMIN_LOGIN" $admin.username "SYSTEM" "SUCCESS" "Admin dang nhap thanh cong"
                &$SendJson @{
                    success = $true
                    token = "viet_sess_" + [Guid]::NewGuid().ToString("N")
                    user = @{
                        username = $admin.username
                        email = $admin.email
                        role = $admin.role
                        plan = $admin.plan
                        ownerId = $admin.id
                    }
                }
            } else {
                &$SendJson @{ success = $false; message = "Sai ten dang nhap hoac mat khau!" } 401
            }
            continue
        }

        if ($urlPath -eq "/api/auth/register" -and $httpMethod -eq "POST") {
            $db = Load-Database
            $username = if ($parsedBody.username) { $parsedBody.username.ToString().Trim() } else { "" }
            $email = if ($parsedBody.email) { $parsedBody.email.ToString().Trim() } else { "" }
            $password = if ($parsedBody.password) { $parsedBody.password.ToString() } else { "" }

            if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password)) {
                &$SendJson @{ success = $false; message = "Vui long nhap day du thong tin" } 400
                continue
            }

            $exists = $db.admins | Where-Object { $_.username -eq $username -or $_.email -eq $email } | Select-Object -First 1
            if ($exists) {
                &$SendJson @{ success = $false; message = "Tai khoan hoac email nay da ton tai!" } 409
                continue
            }

            $newAdmin = [PSCustomObject]@{
                id = "admin_" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
                username = $username
                email = $email
                password = $password
                role = "ADMIN"
                plan = "PRO"
                createdAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            }

            $adminList = [System.Collections.ArrayList]@($db.admins)
            $adminList.Add($newAdmin)
            $db.admins = $adminList
            Save-Database $db

            &$SendJson @{
                success = $true
                message = "Dang ky thanh cong!"
                user = @{
                    username = $newAdmin.username
                    email = $newAdmin.email
                    role = $newAdmin.role
                    plan = $newAdmin.plan
                    ownerId = $newAdmin.id
                }
            }
            continue
        }

        # ----------------------------------------------------------------------
        # DASHBOARD API: METRICS & STATS
        # ----------------------------------------------------------------------
        if ($urlPath -eq "/api/dashboard/stats" -and $httpMethod -eq "GET") {
            $db = Load-Database
            $totalApps = ($db.apps | Measure-Object).Count
            $totalKeys = ($db.licenses | Measure-Object).Count
            $activeKeys = ($db.licenses | Where-Object { $_.status -eq "ACTIVE" } | Measure-Object).Count
            $unusedKeys = ($db.licenses | Where-Object { $_.status -eq "UNUSED" } | Measure-Object).Count
            $expiredKeys = ($db.licenses | Where-Object { $_.status -eq "EXPIRED" } | Measure-Object).Count
            $bannedKeys = ($db.licenses | Where-Object { $_.status -eq "BANNED" } | Measure-Object).Count
            $totalUsers = ($db.users | Measure-Object).Count
            $totalLogs = ($db.logs | Measure-Object).Count
            $totalOnlineDevices = Get-OnlineDeviceCount $db
            $totalDevices = if ($db.devices) { ($db.devices | Measure-Object).Count } else { 0 }

            &$SendJson @{
                success = $true
                data = @{
                    totalApps = $totalApps
                    totalLicenses = $totalKeys
                    activeLicenses = $activeKeys
                    unusedLicenses = $unusedKeys
                    expiredLicenses = $expiredKeys
                    bannedLicenses = $bannedKeys
                    totalUsers = $totalUsers
                    totalLogs = $totalLogs
                    totalOnlineDevices = $totalOnlineDevices
                    totalDevices = $totalDevices
                }
            }
            continue
        }

        # ----------------------------------------------------------------------
        # DASHBOARD API: APPLICATIONS CRUD
        # ----------------------------------------------------------------------
        if ($urlPath -eq "/api/dashboard/apps") {
            $db = Load-Database
            if ($httpMethod -eq "GET") {
                &$SendJson @{ success = $true; data = $db.apps }
                continue
            }
            if ($httpMethod -eq "POST") {
                $name = if ($parsedBody.name) { $parsedBody.name.ToString().Trim() } else { "Ung dung moi" }
                $desc = if ($parsedBody.description) { $parsedBody.description.ToString().Trim() } else { "" }
                $version = if ($parsedBody.version) { $parsedBody.version.ToString().Trim() } else { "1.0.0" }
                $platform = if ($parsedBody.platform) { $parsedBody.platform.ToString().Trim() } else { "Windows C#" }

                $newApp = [PSCustomObject]@{
                    id = "app_" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
                    name = $name
                    appId = "app_pk_viet_" + [Guid]::NewGuid().ToString("N").Substring(0, 12)
                    secretKey = "sk_live_viet_" + [Guid]::NewGuid().ToString("N")
                    version = $version
                    platform = $platform
                    description = $desc
                    status = "ACTIVE"
                    createdAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                    usersCount = 0
                    licensesCount = 0
                }
                $appsList = [System.Collections.ArrayList]@($db.apps)
                $appsList.Insert(0, $newApp)
                $db.apps = $appsList
                Save-Database $db

                Add-Log "CREATE_APP" "admin" $newApp.id "SUCCESS" "Tao ung dung: $name"
                &$SendJson @{ success = $true; data = $newApp }
                continue
            }
            if ($httpMethod -eq "DELETE") {
                $query = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
                $appId = $query["id"]
                $db.apps = @($db.apps | Where-Object { $_.id -ne $appId })
                # Xoa key lien quan
                $db.licenses = @($db.licenses | Where-Object { $_.applicationId -ne $appId })
                Save-Database $db
                Add-Log "DELETE_APP" "admin" $appId "SUCCESS" "Xoa ung dung $appId"
                &$SendJson @{ success = $true; message = "Da xoa ung dung thanh cong" }
                continue
            }
        }

        # ----------------------------------------------------------------------
        # DASHBOARD API: LICENSES CRUD & GENERATOR
        # ----------------------------------------------------------------------
        if ($urlPath -eq "/api/dashboard/licenses") {
            $db = Load-Database

            if ($httpMethod -eq "GET") {
                $query = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
                $appId = $query["applicationId"]
                $status = $query["status"]

                $result = @($db.licenses) | ForEach-Object {
                    $l = $_
                    if ($null -eq $l.hwids) {
                        $l | Add-Member -MemberType NoteProperty -Name "hwids" -Value @() -Force
                        if (-not [string]::IsNullOrWhiteSpace($l.hwid)) {
                            $l.hwids = @($l.hwid -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                        }
                    }
                    if ($null -eq $l.maxDevices) {
                        $maxVal = if ($null -ne $l.activationLimit) { [int]$l.activationLimit } else { 1 }
                        $l | Add-Member -MemberType NoteProperty -Name "maxDevices" -Value $maxVal -Force
                    }
                    $l.activationLimit = $l.maxDevices
                    $l.activationCount = @($l.hwids).Count
                    $l
                }

                if (-not [string]::IsNullOrWhiteSpace($appId) -and $appId -ne "ALL") {
                    $result = @($result | Where-Object { $_.applicationId -eq $appId })
                }
                if (-not [string]::IsNullOrWhiteSpace($status) -and $status -ne "ALL") {
                    $result = @($result | Where-Object { $_.status -eq $status })
                }
                &$SendJson @{ success = $true; data = @($result) }
                continue
            }

            # GENERATE LICENSES (BULK / SINGLE)
            if ($httpMethod -eq "POST") {
                $appId = if ($parsedBody.applicationId) { $parsedBody.applicationId.ToString() } else { ($db.apps | Select-Object -First 1).id }
                $amount = if ($parsedBody.amount) { [int]$parsedBody.amount } else { 1 }
                $durationDays = if ($parsedBody.durationDays -ne $null) { [int]$parsedBody.durationDays } else { 30 }
                $level = if ($parsedBody.subscriptionLevel) { $parsedBody.subscriptionLevel.ToString() } else { "VIP" }
                $notes = if ($parsedBody.notes) { $parsedBody.notes.ToString() } else { "" }
                $prefix = if ($parsedBody.prefix) { $parsedBody.prefix.ToString().Trim() } else { "VIET" }
                $maxDevices = if ($parsedBody.maxDevices -ne $null) { [int]$parsedBody.maxDevices } else { 1 }

                if ($amount -lt 1) { $amount = 1 }
                if ($amount -gt 500) { $amount = 500 }

                $generatedKeys = @()
                $licList = [System.Collections.ArrayList]@($db.licenses)
                $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

                for ($i = 0; $i -lt $amount; $i++) {
                    $part1 = (-join ((48..57) + (65..90) | Get-Random -Count 4 | ForEach-Object {[char]$_}))
                    $part2 = (-join ((48..57) + (65..90) | Get-Random -Count 4 | ForEach-Object {[char]$_}))
                    $part3 = (-join ((48..57) + (65..90) | Get-Random -Count 4 | ForEach-Object {[char]$_}))
                    $newKeyStr = "$prefix-$level-$part1-$part2-$part3".ToUpper()

                    $newLic = [PSCustomObject]@{
                        id = "lic_" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
                        key = $newKeyStr
                        applicationId = $appId
                        subscriptionLevel = $level
                        durationDays = $durationDays
                        status = "UNUSED"
                        hwid = $null
                        hwids = @()
                        hwidEnabled = $true
                        maxDevices = $maxDevices
                        activationLimit = $maxDevices
                        activationCount = 0
                        createdAt = $now
                        activatedAt = $null
                        expiresAt = $null
                        lastUsedAt = $null
                        notes = $notes
                        banReason = $null
                    }
                    $licList.Insert(0, $newLic)
                    $generatedKeys += $newKeyStr
                }

                $db.licenses = $licList

                # Cap nhat count ung dung
                $app = $db.apps | Where-Object { $_.id -eq $appId } | Select-Object -First 1
                if ($app) {
                    $app.licensesCount = ($db.licenses | Where-Object { $_.applicationId -eq $appId } | Measure-Object).Count
                }

                Save-Database $db
                Add-Log "GENERATE_KEYS" "admin" $appId "SUCCESS" "Tao $amount key ($level, $durationDays ngay, gioi han: $(if ($maxDevices -le 0) { 'Vo han' } else { "$maxDevices may" })) cho app $appId"

                &$SendJson @{
                    success = $true
                    message = "Da tao thanh cong $amount key!"
                    data = $generatedKeys
                }
                continue
            }

            # ACTIONS ON LICENSE (RESET HWID, REMOVE HWID, SET MAX DEVICES, BAN, UNBAN, ADD DAYS)
            if ($httpMethod -eq "PATCH") {
                $licId = if ($parsedBody.id) { $parsedBody.id.ToString() } else { "" }
                $action = if ($parsedBody.action) { $parsedBody.action.ToString().ToLower() } else { "" }
                $days = if ($parsedBody.days) { [int]$parsedBody.days } else { 0 }
                $reason = if ($parsedBody.reason) { $parsedBody.reason.ToString() } else { "Admin khoa key" }

                $lic = $db.licenses | Where-Object { $_.id -eq $licId -or $_.key -eq $licId } | Select-Object -First 1
                if ($null -eq $lic) {
                    &$SendJson @{ success = $false; message = "Khong tim thay key" } 404
                    continue
                }

                if ($null -eq $lic.hwids) {
                    $lic | Add-Member -MemberType NoteProperty -Name "hwids" -Value @() -Force
                    if (-not [string]::IsNullOrWhiteSpace($lic.hwid)) {
                        $lic.hwids = @($lic.hwid -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                    }
                }

                switch ($action) {
                    "reset_hwid" {
                        $oldHwid = $lic.hwid
                        $lic.hwid = $null
                        $lic.hwids = @()
                        $lic.activationCount = 0
                        Add-Log "RESET_HWID" "admin" $lic.applicationId "SUCCESS" "Dat lai toan bo HWID cho key $($lic.key) (Truoc do: $oldHwid)"
                    }
                    "remove_hwid" {
                        $targetHwid = if ($parsedBody.hwid) { $parsedBody.hwid.ToString().Trim() } else { "" }
                        $curHwids = @($lic.hwids | Where-Object { $_ -ne $targetHwid })
                        $lic.hwids = $curHwids
                        $lic.hwid = if ($curHwids.Count -gt 0) { $curHwids -join ", " } else { $null }
                        $lic.activationCount = $curHwids.Count
                        Add-Log "REMOVE_DEVICE_HWID" "admin" $lic.applicationId "SUCCESS" "Go thiet bi [$targetHwid] khoi key $($lic.key)"
                    }
                    "set_max_devices" {
                        $newLimit = if ($parsedBody.maxDevices -ne $null) { [int]$parsedBody.maxDevices } else { 1 }
                        $lic.maxDevices = $newLimit
                        $lic.activationLimit = $newLimit
                        Add-Log "SET_MAX_DEVICES" "admin" $lic.applicationId "SUCCESS" "Doi gioi han thiet bi key $($lic.key) thanh $newLimit"
                    }
                    "ban" {
                        $lic.status = "BANNED"
                        $lic.banReason = $reason
                        Add-Log "BAN_KEY" "admin" $lic.applicationId "SUCCESS" "Khoa key $($lic.key): $reason"
                    }
                    "unban" {
                        $lic.status = if ($lic.activatedAt) { "ACTIVE" } else { "UNUSED" }
                        $lic.banReason = $null
                        Add-Log "UNBAN_KEY" "admin" $lic.applicationId "SUCCESS" "Mo khoa key $($lic.key)"
                    }
                    "add_days" {
                        if ($days -gt 0) {
                            $lic.durationDays = $lic.durationDays + $days
                            if (-not [string]::IsNullOrWhiteSpace($lic.expiresAt)) {
                                $currExp = [DateTime]::Parse($lic.expiresAt)
                                $lic.expiresAt = $currExp.AddDays($days).ToString("yyyy-MM-ddTHH:mm:ssZ")
                            }
                            if ($lic.status -eq "EXPIRED") {
                                $lic.status = "ACTIVE"
                            }
                            Add-Log "EXTEND_KEY" "admin" $lic.applicationId "SUCCESS" "Gia han them $days ngay cho key $($lic.key)"
                        }
                    }
                }

                Save-Database $db
                &$SendJson @{ success = $true; message = "Thao tac thanh cong"; data = $lic }
                continue
            }

            # DELETE LICENSE
            if ($httpMethod -eq "DELETE") {
                $query = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
                $licId = $query["id"]
                $db.licenses = @($db.licenses | Where-Object { $_.id -ne $licId -and $_.key -ne $licId })
                Save-Database $db
                Add-Log "DELETE_KEY" "admin" "SYSTEM" "SUCCESS" "Xoa key $licId"
                &$SendJson @{ success = $true; message = "Da xoa key thanh cong" }
                continue
            }
        }

        # ----------------------------------------------------------------------
        # DASHBOARD API: APP USERS & USER ACCOUNT GENERATION
        # ----------------------------------------------------------------------
        if ($urlPath -eq "/api/dashboard/users") {
            $db = Load-Database
            if ($null -eq $db.users) {
                $db | Add-Member -MemberType NoteProperty -Name "users" -Value @() -ErrorAction SilentlyContinue
            }

            if ($httpMethod -eq "GET") {
                $query = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
                $appId = $query["applicationId"]
                $status = $query["status"]
                $search = if ($query["search"]) { $query["search"].ToLower().Trim() } else { "" }

                $result = $db.users
                if (-not [string]::IsNullOrWhiteSpace($appId) -and $appId -ne "ALL") {
                    $result = $result | Where-Object { $_.applicationId -eq $appId }
                }
                if (-not [string]::IsNullOrWhiteSpace($status) -and $status -ne "ALL") {
                    $result = $result | Where-Object { $_.status -eq $status }
                }
                if (-not [string]::IsNullOrWhiteSpace($search)) {
                    $result = $result | Where-Object {
                        ($_.username -and $_.username.ToLower().Contains($search)) -or
                        ($_.email -and $_.email.ToLower().Contains($search)) -or
                        ($_.hwid -and $_.hwid.ToLower().Contains($search)) -or
                        ($_.notes -and $_.notes.ToLower().Contains($search))
                    }
                }
                &$SendJson @{ success = $true; data = @($result) }
                continue
            }

            if ($httpMethod -eq "POST") {
                $appId = if ($parsedBody.applicationId) { $parsedBody.applicationId.ToString() } else { ($db.apps | Select-Object -First 1).id }
                $level = if ($parsedBody.subscriptionLevel) { $parsedBody.subscriptionLevel.ToString() } else { "VIP" }
                $durationDays = if ($parsedBody.durationDays -ne $null) { [int]$parsedBody.durationDays } else { 30 }
                $hwidEnabled = if ($parsedBody.hwidEnabled -ne $null) { [bool]$parsedBody.hwidEnabled } else { $true }
                $maxDevices = if ($parsedBody.maxDevices -ne $null) { [int]$parsedBody.maxDevices } else { 1 }
                $notes = if ($parsedBody.notes) { $parsedBody.notes.ToString() } else { "" }
                $now = (Get-Date).ToUniversalTime()
                $nowStr = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")
                $expStr = if ($durationDays -gt 0) { $now.AddDays($durationDays).ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $null }

                $userList = [System.Collections.ArrayList]@($db.users)

                # Truong hop 1: Tao 1 tai khoan tuy chinh
                if (-not [string]::IsNullOrWhiteSpace($parsedBody.customUsername)) {
                    $customUser = $parsedBody.customUsername.ToString().Trim()
                    $customPass = if ($parsedBody.customPassword) { $parsedBody.customPassword.ToString().Trim() } else { "Pass@123456" }

                    $exists = $db.users | Where-Object { $_.username -eq $customUser } | Select-Object -First 1
                    if ($exists) {
                        &$SendJson @{ success = $false; message = "Ten tai khoan nay da ton tai!" } 409
                        continue
                    }

                    $newUser = [PSCustomObject]@{
                        id = "usr_" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
                        applicationId = $appId
                        username = $customUser
                        password = $customPass
                        email = if ($parsedBody.email) { $parsedBody.email.ToString() } else { "$customUser@client.com" }
                        subscriptionLevel = $level
                        durationDays = $durationDays
                        status = "ACTIVE"
                        hwid = $null
                        hwids = @()
                        maxDevices = $maxDevices
                        hwidEnabled = $hwidEnabled
                        createdAt = $nowStr
                        expiresAt = $expStr
                        lastLogin = $null
                        notes = $notes
                    }

                    $userList.Insert(0, $newUser)
                    $db.users = $userList
                    Save-Database $db

                    Add-Log "CREATE_USER_ACCOUNT" "admin" $appId "SUCCESS" "Tao tai khoan: $customUser ($level, $durationDays ngay, $maxDevices may)"
                    $durLabel = if ($durationDays -gt 0) { "$durationDays ngay" } else { "Vinh vien" }
                    &$SendJson @{
                        success = $true
                        message = "Da tao tai khoan thanh cong!"
                        data = @($newUser)
                        accountsText = "Tai khoan: $customUser | Mat khau: $customPass | Goi: $level | Thoi han: $durLabel | Gioi han: $(if ($maxDevices -le 0) { 'Vo han' } else { "$maxDevices may" })"
                    }
                    continue
                }

                # Truong hop 2: Tao hang loat
                $amount = if ($parsedBody.amount) { [int]$parsedBody.amount } else { 1 }
                if ($amount -lt 1) { $amount = 1 }
                if ($amount -gt 50) { $amount = 50 }
                $prefix = if ($parsedBody.prefix) { $parsedBody.prefix.ToString().Trim() } else { "user_" }

                $createdList = @()
                $lines = @()

                for ($i = 0; $i -lt $amount; $i++) {
                    $randSuffix = (-join ((48..57) + (97..122) | Get-Random -Count 4 | ForEach-Object {[char]$_}))
                    $randPassSuffix = (-join ((48..57) + (65..90) | Get-Random -Count 4 | ForEach-Object {[char]$_}))
                    $uname = "$prefix$randSuffix"
                    $pword = "Pass@$randPassSuffix"

                    $newUser = [PSCustomObject]@{
                        id = "usr_" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
                        applicationId = $appId
                        username = $uname
                        password = $pword
                        email = "$uname@client.com"
                        subscriptionLevel = $level
                        durationDays = $durationDays
                        status = "ACTIVE"
                        hwid = $null
                        hwids = @()
                        maxDevices = $maxDevices
                        hwidEnabled = $hwidEnabled
                        createdAt = $nowStr
                        expiresAt = $expStr
                        lastLogin = $null
                        notes = $notes
                    }

                    $userList.Insert(0, $newUser)
                    $createdList += $newUser
                    $durLabel = if ($durationDays -gt 0) { "$durationDays ngay" } else { "Vinh vien" }
                    $lines += "Tai khoan: $uname | Mat khau: $pword | Goi: $level | Thoi han: $durLabel | May: $(if ($maxDevices -le 0) { 'Vo han' } else { "$maxDevices" })"
                }

                $db.users = $userList
                Save-Database $db

                Add-Log "GENERATE_USER_ACCOUNTS" "admin" $appId "SUCCESS" "Tao $amount tai khoan ($level, $durationDays ngay)"
                &$SendJson @{
                    success = $true
                    message = "Da tao thanh cong $amount tai khoan!"
                    data = $createdList
                    accountsText = ($lines -join "`n")
                }
                continue
            }

            if ($httpMethod -eq "PATCH") {
                $uId = if ($parsedBody.id) { $parsedBody.id.ToString() } else { "" }
                $action = if ($parsedBody.action) { $parsedBody.action.ToString().ToLower() } else { "" }
                $days = if ($parsedBody.days) { [int]$parsedBody.days } else { 0 }
                $reason = if ($parsedBody.reason) { $parsedBody.reason.ToString() } else { "Admin khoa tai khoan" }
                $newPass = if ($parsedBody.newPassword) { $parsedBody.newPassword.ToString().Trim() } else { "" }

                $user = $db.users | Where-Object { $_.id -eq $uId -or $_.username -eq $uId } | Select-Object -First 1
                if ($null -eq $user) {
                    &$SendJson @{ success = $false; message = "Khong tim thay tai khoan!" } 404
                    continue
                }

                if ($null -eq $user.hwids) {
                    $user | Add-Member -MemberType NoteProperty -Name "hwids" -Value @() -Force
                    if (-not [string]::IsNullOrWhiteSpace($user.hwid)) {
                        $user.hwids = @($user.hwid -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                    }
                }

                switch ($action) {
                    "reset_hwid" {
                        $oldHwid = $user.hwid
                        $user.hwid = $null
                        $user.hwids = @()
                        Add-Log "RESET_USER_HWID" "admin" $user.applicationId "SUCCESS" "Dat lai toan bo HWID cho user $($user.username)"
                    }
                    "remove_hwid" {
                        $targetHwid = if ($parsedBody.hwid) { $parsedBody.hwid.ToString().Trim() } else { "" }
                        $curHwids = @($user.hwids | Where-Object { $_ -ne $targetHwid })
                        $user.hwids = $curHwids
                        $user.hwid = if ($curHwids.Count -gt 0) { $curHwids -join ", " } else { $null }
                        Add-Log "REMOVE_USER_HWID" "admin" $user.applicationId "SUCCESS" "Go thiet bi [$targetHwid] khoi user $($user.username)"
                    }
                    "set_max_devices" {
                        $newLimit = if ($parsedBody.maxDevices -ne $null) { [int]$parsedBody.maxDevices } else { 1 }
                        $user.maxDevices = $newLimit
                        Add-Log "SET_USER_MAX_DEVICES" "admin" $user.applicationId "SUCCESS" "Doi gioi han thiet bi user $($user.username) thanh $newLimit"
                    }
                    "ban" {
                        $user.status = "BANNED"
                        $user.banReason = $reason
                        Add-Log "BAN_USER" "admin" $user.applicationId "SUCCESS" "Khoa user $($user.username): $reason"
                    }
                    "unban" {
                        $user.status = "ACTIVE"
                        $user.banReason = $null
                        Add-Log "UNBAN_USER" "admin" $user.applicationId "SUCCESS" "Mo khoa user $($user.username)"
                    }
                    "add_days" {
                        if ($days -gt 0) {
                            $user.durationDays = $user.durationDays + $days
                            $currExp = if (-not [string]::IsNullOrWhiteSpace($user.expiresAt)) { [DateTime]::Parse($user.expiresAt) } else { (Get-Date).ToUniversalTime() }
                            $user.expiresAt = $currExp.AddDays($days).ToString("yyyy-MM-ddTHH:mm:ssZ")
                            if ($user.status -eq "EXPIRED") { $user.status = "ACTIVE" }
                            Add-Log "EXTEND_USER" "admin" $user.applicationId "SUCCESS" "Gia han $days ngay cho user $($user.username)"
                        }
                    }
                    "change_password" {
                        if (-not [string]::IsNullOrWhiteSpace($newPass)) {
                            $user.password = $newPass
                            Add-Log "CHANGE_USER_PASS" "admin" $user.applicationId "SUCCESS" "Doi mat khau user $($user.username)"
                        }
                    }
                }

                Save-Database $db
                &$SendJson @{ success = $true; message = "Thao tac tai khoan thanh cong!"; data = $user }
                continue
            }

            if ($httpMethod -eq "DELETE") {
                $query = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
                $uId = $query["id"]
                $db.users = @($db.users | Where-Object { $_.id -ne $uId -and $_.username -ne $uId })
                Save-Database $db
                Add-Log "DELETE_USER" "admin" "SYSTEM" "SUCCESS" "Xoa tai khoan $uId"
                &$SendJson @{ success = $true; message = "Da xoa nguoi dung thanh cong" }
                continue
            }
        }

        # ----------------------------------------------------------------------
        # DASHBOARD API: VARIABLES
        # ----------------------------------------------------------------------
        if ($urlPath -eq "/api/dashboard/variables") {
            $db = Load-Database
            if ($httpMethod -eq "GET") {
                &$SendJson @{ success = $true; data = $db.variables }
                continue
            }
            if ($httpMethod -eq "POST") {
                $varList = [System.Collections.ArrayList]@($db.variables)
                $newVar = [PSCustomObject]@{
                    id = "var_" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
                    applicationId = if ($parsedBody.applicationId) { $parsedBody.applicationId.ToString() } else { ($db.apps | Select-Object -First 1).id }
                    name = $parsedBody.name.ToString().Trim()
                    value = $parsedBody.value.ToString()
                    isSecret = [bool]($parsedBody.isSecret)
                    updatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
                $varList.Insert(0, $newVar)
                $db.variables = $varList
                Save-Database $db
                &$SendJson @{ success = $true; data = $newVar }
                continue
            }
            if ($httpMethod -eq "DELETE") {
                $query = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
                $varId = $query["id"]
                $db.variables = @($db.variables | Where-Object { $_.id -ne $varId })
                Save-Database $db
                &$SendJson @{ success = $true; message = "Da xoa bien" }
                continue
            }
        }

        # ----------------------------------------------------------------------
        # DASHBOARD API: AUDIT LOGS
        # ----------------------------------------------------------------------
        if ($urlPath -eq "/api/dashboard/logs" -and $httpMethod -eq "GET") {
            $db = Load-Database
            &$SendJson @{ success = $true; data = $db.logs }
            continue
        }

        # DEFAULT 404 NOT FOUND
        &$SendJson @{ error = "Not found"; path = $urlPath } 404

    } catch {
        Write-Host "[!] Ngoai le xu ly request: $_" -ForegroundColor Red
        try {
            $response.StatusCode = 500
            $response.Close()
        } catch {}
    }
}
