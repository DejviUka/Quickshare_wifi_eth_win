# === Logging setup ===
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile   = Join-Path $scriptDir "logps.txt"
$macFile   = Join-Path $scriptDir "mac.txt"
"`n=== Run at $(Get-Date -Format u) ===`n" | Out-File $logFile -Append

function Log {
    param($msg)
    $t = Get-Date -Format u
    "$t  $msg" | Out-File $logFile -Append
}

# === Elevation ===
function Ensure-RunAsAdmin {
    $pr = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    if (-not $pr.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )) {
        Log "Not admin; relaunching elevated."
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
    Log "Running as admin."
}
Ensure-RunAsAdmin

# === Load MAC list ===
function Load-MacList {
    $wifiMacs = @()
    $ethMacs  = @()
    if (Test-Path $macFile) {
        Get-Content $macFile | ForEach-Object {
            if ($_ -match "^wifi:\s*(.+)$") {
                $wifiMacs += ($matches[1] -replace "[:-]", "").ToUpper()
            } elseif ($_ -match "^ethernet:\s*(.+)$") {
                $ethMacs += ($matches[1] -replace "[:-]", "").ToUpper()
            }
        }
    }
    return @{ wifi = $wifiMacs; ethernet = $ethMacs }
}

# === Add to MAC file (manual) ===
function Add-Mac {
    param($type)
    $mac = Read-Host "Enter $type MAC address (e.g., AA:BB:CC:DD:EE:FF)"
    if ($mac -match "^[0-9A-Fa-f:-]{17}$") {
        ("{0}: {1}" -f $type, $mac) | Out-File $macFile -Append
        Log "Added $type MAC: $mac"
        Write-Host "$type MAC added."
    } else {
        Write-Host "Invalid MAC address format."
        Log "Invalid MAC address entered: $mac"
    }
}

# === Auto-scan & add MAC ===
function Add-MacAuto {
    param([ValidateSet('wifi','ethernet')] $type)
    if ($type -eq 'wifi') {
        $adapters = Get-NetAdapter | Where-Object { $_.Name -match 'Wi-?Fi' -or $_.InterfaceDescription -match 'Wireless' }
    } else {
        $adapters = Get-NetAdapter | Where-Object { $_.Name -match 'Ethernet' -or $_.InterfaceDescription -match 'Ethernet' }
    }
    if (-not $adapters) {
        Write-Host "No $type adapters found."
        return
    }
    Write-Host "`nSelect a $type adapter to add:`n"
    for ($i = 0; $i -lt $adapters.Count; $i++) {
        $a = $adapters[$i]
        Write-Host "[$i] IDX:$($a.InterfaceIndex) Name: $($a.Name) MAC: $($a.MacAddress) Status: $($a.Status) LinkSpeed: $($a.LinkSpeed)"
    }
    $sel = Read-Host "`nEnter number (0..$($adapters.Count - 1)) or Q to cancel"
    if ($sel -match '^[0-9]+$' -and [int]$sel -lt $adapters.Count) {
        $chosen = $adapters[[int]$sel]
        $mac = $chosen.MacAddress
        ("{0}: {1}" -f $type, $mac) | Out-File $macFile -Append
        Log "Added $type MAC (auto): $mac ($($chosen.Name))"
        Write-Host "$type MAC $mac added."
    } else {
        Write-Host "Cancelled or invalid selection."
        Log "Auto-add $type cancelled/invalid: $sel"
    }
}

# === ICS COM setup ===
Log "Creating HNetCfg.HNetShare"
$shareMgr = New-Object -ComObject HNetCfg.HNetShare
$allConns = @($shareMgr.EnumEveryConnection())
function GetProps($c)  { $shareMgr.NetConnectionProps($c) }
function GetConfig($c){ $shareMgr.INetSharingConfigurationForINetConnection($c) }

# === Get adapter MAC by connection object ===
function Get-MacAddress {
    param($conn)
    $name = (GetProps $conn).Name
    $adapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Name -EQ $name
    return $adapter.MacAddress -replace '[:-]', ''
}

# === Match adapter by MAC priority list ===
function Match-Adapter {
    param($macList, $conns)
    foreach ($m in $macList) {
        foreach ($c in $conns) {
            if ((Get-MacAddress $c).ToUpper() -eq $m.ToUpper()) { return $c }
        }
    }
    return $null
}

# === Main logic: identify adapters ===
$macs     = Load-MacList
$wifiConn = Match-Adapter $macs.wifi      $allConns
$ethConn  = Match-Adapter $macs.ethernet ($allConns | Where-Object { $_ -ne $wifiConn })

if (-not $wifiConn -or -not $ethConn) {
    Write-Host "ERROR: could not match adapters by MAC list."; exit 1
}

$wifiName = (GetProps $wifiConn).Name
$ethName  = (GetProps $ethConn).Name
$cfgWifi  = GetConfig $wifiConn
$cfgEth   = GetConfig $ethConn
$shared   = $cfgWifi.SharingEnabled -and $cfgEth.SharingEnabled

Write-Host "`nWi-Fi:    $wifiName"
Write-Host "Ethernet: $ethName"
Write-Host -NoNewline "ICS is currently: "
if ($shared) { Write-Host "ENABLED" } else { Write-Host "DISABLED" }
Log "Adapters: Wi-Fi=$wifiName, Ethernet=$ethName, Shared=$shared"

# === Menu Loop ===
while ($true) {
    Write-Host "`nMenu:"
    Write-Host "1. Enable sharing"
    Write-Host "2. Disable sharing"
    Write-Host "3. Add Wi-Fi MAC (manual)"
    Write-Host "4. Add Ethernet MAC (manual)"
    Write-Host "5. Auto-add Wi-Fi MAC"
    Write-Host "6. Auto-add Ethernet MAC"
    Write-Host "Q. Quit"
    $choice = Read-Host "Choose an option"
    Log "User selected: $choice"

    switch ($choice.ToUpper()) {
        '1' {
            if (-not $shared) {
                foreach ($c in $allConns) {
                    $cfg = GetConfig $c
                    if ($cfg.SharingEnabled) { $cfg.DisableSharing(); Log "Disabled ICS on $((GetProps $c).Name)" }
                }
                $cfgWifi.EnableSharing(0); $cfgEth.EnableSharing(1); $shared = $true
                Write-Host "Sharing ENABLED"; Log "ICS enabled"
            } else { Write-Host "ICS already enabled."; Log "No-op enable" }
        }
        '2' {
            if ($shared) {
                $cfgWifi.DisableSharing(); $cfgEth.DisableSharing(); $shared = $false
                Write-Host "Sharing DISABLED"; Log "ICS disabled"
            } else { Write-Host "ICS already disabled."; Log "No-op disable" }
        }
        '3' { Add-Mac "wifi" }
        '4' { Add-Mac "ethernet" }
        '5' { Add-MacAuto 'wifi' }
        '6' { Add-MacAuto 'ethernet' }
        'Q' { Log "Exiting script"; break }
        default { Write-Host "Invalid choice."; Log "Invalid input: $choice" }
    }
}

Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Log "Script end"
