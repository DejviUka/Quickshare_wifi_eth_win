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
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`"" -Verb RunAs
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

# === Add to MAC file ===
function Add-Mac {
    param($type)
    $mac = Read-Host "Enter $type MAC address (e.g., AA:BB:CC:DD:EE:FF)"
    if ($mac -match "^[0-9A-Fa-f:-]{17}$") {
        # Use formatted string to avoid ":" being mis-parsed
        ("{0}: {1}" -f $type, $mac) | Out-File $macFile -Append
        Log "Added $type MAC: $mac"
        Write-Host "$type MAC added."
    } else {
        Write-Host "Invalid MAC address format."
        Log "Invalid MAC address entered: $mac"
    }
}

# === ICS Setup ===
Log "Creating HNetCfg.HNetShare"
$shareMgr = New-Object -ComObject HNetCfg.HNetShare
$allConns = @($shareMgr.EnumEveryConnection())

function GetProps($c) { $shareMgr.NetConnectionProps($c) }
function GetConfig($c) { $shareMgr.INetSharingConfigurationForINetConnection($c) }

# === Get MAC address for adapter ===
function Get-MacAddress($conn) {
    $name = (GetProps $conn).Name
    $adapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $name }
    return $adapter.MacAddress -replace "[:-]", ""
}

# === Match Adapter by MAC ===
function Match-Adapter($macList, $adapters) {
    foreach ($mac in $macList) {
        foreach ($conn in $adapters) {
            $connMac = Get-MacAddress $conn
            if ($connMac.ToUpper() -eq $mac.ToUpper()) {
                return $conn
            }
        }
    }
    return $null
}

# === Main logic ===
$macs     = Load-MacList
$wifiConn = Match-Adapter $macs.wifi      $allConns
$ethConn  = Match-Adapter $macs.ethernet ($allConns | Where-Object { $_ -ne $wifiConn })

if (-not $wifiConn) {
    Log "ERROR: No matching Wi-Fi MAC"
    Write-Host "ERROR: No matching Wi-Fi adapter found in MAC list."
    Pause; exit 1
}
if (-not $ethConn) {
    Log "ERROR: No matching Ethernet MAC"
    Write-Host "ERROR: No matching Ethernet adapter found in MAC list."
    Pause; exit 1
}

$wifiName = (GetProps $wifiConn).Name
$ethName  = (GetProps $ethConn).Name
$cfgWifi  = GetConfig $wifiConn
$cfgEth   = GetConfig $ethConn
$shared   = $cfgWifi.SharingEnabled -and $cfgEth.SharingEnabled

Write-Host "`nWi-Fi:    $wifiName"
Write-Host "Ethernet: $ethName"
Write-Host -NoNewline "ICS is currently: "
# Replace ternary with if/else
if ($shared) {
    Write-Host "ENABLED"
} else {
    Write-Host "DISABLED"
}
Log "Adapters: Wi-Fi=$wifiName, Ethernet=$ethName, Shared=$shared"

# === Menu Loop ===
while ($true) {
    Write-Host "`nMenu:"
    Write-Host "1. Enable sharing"
    Write-Host "2. Disable sharing"
    Write-Host "3. Add Wi-Fi MAC"
    Write-Host "4. Add Ethernet MAC"
    Write-Host "Q. Quit"
    $choice = Read-Host "Choose an option"
    Log "User selected: $choice"

    switch ($choice.ToUpper()) {
        "1" {
            if ($shared) {
                Write-Host "ICS already enabled."
                Log "No change: already enabled"
            } else {
                foreach ($c in $allConns) {
                    $cfg = GetConfig $c
                    if ($cfg.SharingEnabled) {
                        $cfg.DisableSharing()
                        Log "Disabled ICS on $((GetProps $c).Name)"
                    }
                }
                $cfgWifi.EnableSharing(0)
                $cfgEth.EnableSharing(1)
                $shared = $true
                Write-Host "Sharing ENABLED"
                Log "ICS enabled"
            }
        }
        "2" {
            if (-not $shared) {
                Write-Host "ICS already disabled."
                Log "No change: already disabled"
            } else {
                $cfgWifi.DisableSharing()
                $cfgEth.DisableSharing()
                $shared = $false
                Write-Host "Sharing DISABLED"
                Log "ICS disabled"
            }
        }
        "3" { Add-Mac "wifi" }
        "4" { Add-Mac "ethernet" }
        "Q" {
            Log "Exiting script"
            break
        }
        default {
            Write-Host "Invalid choice."
            Log "Invalid input: $choice"
        }
    }
}

Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Log "Script end"
