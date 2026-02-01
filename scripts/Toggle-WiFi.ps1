# Toggle-WiFi.ps1
# Automatically disables Wi-Fi when Ethernet 2 is connected,
# and re-enables Wi-Fi when Ethernet 2 is disconnected.

# Brief delay to let adapter state settle after a plug/unplug event
Start-Sleep -Seconds 2

$ethernet = Get-NetAdapter -Name "Ethernet 2" -ErrorAction SilentlyContinue
$wifi = Get-NetAdapter -Name "Wi-Fi" -ErrorAction SilentlyContinue

if (-not $ethernet -or -not $wifi) {
    exit 0
}

if ($ethernet.Status -eq "Up") {
    if ($wifi.Status -ne "Disabled") {
        Disable-NetAdapter -Name "Wi-Fi" -Confirm:$false
    }
} else {
    if ($wifi.Status -eq "Disabled") {
        Enable-NetAdapter -Name "Wi-Fi" -Confirm:$false
    }
}
