$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$request = [Console]::In.ReadToEnd() | ConvertFrom-Json
function Await-WinRT($operation, [Type]$resultType) {
    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq "AsTask" -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1
    $task = $method.MakeGenericMethod($resultType).Invoke($null, @($operation))
    if (!$task.Wait(25000)) { throw "WinRT operation timeout" }
    return $task.Result
}
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    if ($request.operation -eq "connectWifi") {
        $ssidBytes = [Text.Encoding]::UTF8.GetBytes([string]$request.ssid)
        if ($ssidBytes.Length -lt 1 -or $ssidBytes.Length -gt 32) { throw "Invalid SSID" }
        $hex = [BitConverter]::ToString($ssidBytes).Replace("-", "")
        $profile = "NetworkSharing-" + $hex
        $key = [Security.SecurityElement]::Escape([string]$request.password)
        $security = if ([string]::IsNullOrEmpty($request.password)) {
            "<authEncryption><authentication>open</authentication><encryption>none</encryption><useOneX>false</useOneX></authEncryption>"
        } else {
            "<authEncryption><authentication>WPA2PSK</authentication><encryption>AES</encryption><useOneX>false</useOneX></authEncryption><sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>$key</keyMaterial></sharedKey>"
        }
        $xml = '<?xml version="1.0"?><WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1"><name>{0}</name><SSIDConfig><SSID><hex>{1}</hex></SSID><nonBroadcast>false</nonBroadcast></SSIDConfig><connectionType>ESS</connectionType><connectionMode>manual</connectionMode><MSM><security>{2}</security></MSM></WLANProfile>' -f $profile, $hex, $security
        $temp = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString() + ".xml")
        try {
            [IO.File]::WriteAllText($temp, $xml, [Text.UTF8Encoding]::new($false))
            $output = & "$env:SystemRoot\System32\netsh.exe" wlan add profile "filename=$temp" user=current 2>&1
            if ($LASTEXITCODE -ne 0) { throw "WLAN profile rejected: $output" }
            $output = & "$env:SystemRoot\System32\netsh.exe" wlan connect "name=$profile" 2>&1
            if ($LASTEXITCODE -ne 0) { throw "WLAN connect rejected: $output" }
        } finally {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        }
        $connected = $false
        for ($i = 0; $i -lt 15; $i++) {
            Start-Sleep -Milliseconds 700
            $profiles = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]::GetConnectionProfiles()
            foreach ($p in $profiles) {
                if ($p.IsWlanConnectionProfile -and $p.WlanConnectionProfileDetails.GetConnectedSsid() -ceq $request.ssid) { $connected = $true; break }
            }
            if ($connected) { break }
        }
        if (!$connected) { throw "WLAN connection not confirmed; check password, radio and Windows location permission" }
        @{success=$true; message="Wi-Fi connected"} | ConvertTo-Json -Compress
        exit
    }
    $profile = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType=WindowsRuntime]::GetInternetConnectionProfile()
    if (!$profile) {
        $profile = [Windows.Networking.Connectivity.NetworkInformation]::GetConnectionProfiles() | Select-Object -First 1
    }
    if (!$profile) { throw "No connection profile available for Mobile Hotspot" }
    $manager = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime]::CreateFromConnectionProfile($profile)
    if ($request.operation -eq "startHotspot" -or $request.operation -eq "stopHotspot") {
        $op = if ($request.operation -eq "startHotspot") { $manager.StartTetheringAsync() } else { $manager.StopTetheringAsync() }
        $result = Await-WinRT $op ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult, Windows.Networking.NetworkOperators, ContentType=WindowsRuntime])
        if ($result.Status.ToString() -ne "Success") { throw ("Mobile Hotspot: " + $result.Status + " " + $result.AdditionalErrorMessage) }
    }
    $config = $manager.GetCurrentAccessPointConfiguration()
    @{success=$true; enabled=($manager.TetheringOperationalState.ToString() -eq "On"); clientCount=[int]$manager.ClientCount; ssid=$config.Ssid; password=$config.Passphrase; message=$manager.TetheringOperationalState.ToString()} | ConvertTo-Json -Compress
} catch {
    @{success=$false; message=$_.Exception.Message} | ConvertTo-Json -Compress
    exit 1
}
